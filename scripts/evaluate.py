#!/usr/bin/env python3
"""M5 纯评估（手册 10.5/12.7；`docs/M5_dev_plan.md` §6）：加载 checkpoint、推理、写报告。

契约（只 import `model`/`dataset`/`metrics`；**不实现数据/指标逻辑**）：
  - 主实验（默认）：读 `runs/seed{seed}/best.pt` + `config.json` → 重建 `fuser`+`model`（维度从
    config 回读，`SSMHG(in_dim=fuser.hidden)`）→ 阈值搜索（**只读 val**，复用 `val_best_probs.pt`
    免重复推理，缺失则重算）→ **MVD-HG 内部测试**固定 0.5 与验证集阈值**双报告** →
    `runs/seed{seed}/results.json`。
  - 阈值候选 0.20~0.80 步长 0.05、目标 **val micro-F1**（并列取小），由 `metrics.search_global_threshold`
    完成；测试集不参与阈值选择；稀有类不单独调阈。
  - `--summarize`：聚合各 seed 的 `results.json` → `runs/summary.json`（每指标 mean ± std，
    主种子声明 seed0）。
  - 消融/基线（`--task ablation|baseline`）与 DIVE/SolidiFI（阶段 5）属阶段 F/G，不在本文件主体；
    结果写 `eval_results/`，不污染 `runs/`。

产物：`runs/seed{seed}/results.json`（双阈值 micro/macro-F1、每类 P/R/F1 随 support、mAP、
subset accuracy、阈值全扫描、计时/环境）；`runs/summary.json`（`--summarize`）。
"""

from __future__ import annotations

import argparse
import json
import platform
import time
from pathlib import Path

import numpy as np
import torch

import metrics
from dataset import (DEFAULT_GRAPH_DIR, Ablation, build_index, collate,
                     load_graph)
from model import AblationConfig, NodeFuser, SSMHG

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
DEFAULT_SPLIT_DIR = f"{BASE}/products/alldata/splits"
DEFAULT_RUNS_DIR = f"{BASE}/runs"
NUM_CLASSES = 7
NUM_RELATIONS = 5


def parse_args() -> argparse.Namespace:
    """CLI：--seed（单 seed 评估）或 --summarize（汇总）；路径与 batch size。"""
    p = argparse.ArgumentParser(description="M5 evaluate: load checkpoint, infer, report.")
    p.add_argument("--seed", type=int, default=None, help="要评估的 seed（读 runs/seedN/best.pt）。")
    p.add_argument("--summarize", action="store_true",
                   help="聚合 runs/seed*/results.json → runs/summary.json（mean ± std）。")
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR)
    p.add_argument("--split-dir", default=DEFAULT_SPLIT_DIR)
    p.add_argument("--runs-dir", default=DEFAULT_RUNS_DIR)
    return p.parse_args()


def rebuild_models(config: dict, checkpoint: dict):
    """从 config + checkpoint 重建 (fuser, model) 并置 eval；维度回读（不硬编码 128/1631）。

    `SSMHG(in_dim=fuser.hidden)`：SSMHG 接收 fuser 的**输出** h_v^(0) ∈ R^128，而非融合输入
    `fuser.in_dim`（=1631）。消融配置（ablate_sv/feat_groups/cb_channels）与模型超参从
    `config["args"]` 复原，保证与训练时一致。
    """
    d = config["derived"]
    args = config["args"]
    ablation = AblationConfig(
        ablate_sv=bool(args.get("ablate_sv", False)),
        feat_groups=args.get("feat_groups", "all"),
        cb_channels=tuple(args.get("cb_channels", "cb_func,cb_node").split(",")))
    fuser = NodeFuser(int(d["D_struct"]), dict(d["struct_layout"]), ablate=ablation,
                      prior_dropout=args.get("prior_dropout", 0.2),
                      struct_dropout=args.get("struct_dropout", 0.2))
    model = SSMHG(in_dim=fuser.hidden, hid=args.get("hid", 128), num_relations=NUM_RELATIONS,
                  num_bases=args.get("num_bases", 5), num_classes=NUM_CLASSES,
                  dropout=args.get("model_dropout", 0.3),
                  conv_type=args.get("conv", "rgcn"),
                  use_meanpool=bool(args.get("meanpool", False)))
    fuser.load_state_dict(checkpoint["fuser_state_dict"])
    model.load_state_dict(checkpoint["model_state_dict"])
    fuser.eval()
    model.eval()
    return fuser, model


def infer(samples, fuser: NodeFuser, model: SSMHG, batch_size: int, device: str = "cpu"):
    """前向（eval、无掩码、不丢边）→ (probs[N,7], labels[N,7])；结果回 CPU（指标层统一 numpy）。"""
    probs_list, labels_list = [], []
    with torch.no_grad():
        for i in range(0, len(samples), batch_size):
            chunk = samples[i:i + batch_size]
            channels, ei, et, batch, labels = collate(chunk, training=False, device=device)
            x = fuser(channels, batch=batch)
            z, _, _ = model(x, ei, et, batch=batch)
            probs_list.append(torch.sigmoid(z).cpu())
            labels_list.append(labels.cpu())
    return torch.cat(probs_list, dim=0), torch.cat(labels_list, dim=0)


def compute_report(probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """单阈值报告：micro/macro-F1、逐类 P/R/F1（随 support）、subset accuracy。"""
    preds = metrics.binary_preds(probs, thr)
    return {
        "threshold": thr,
        "micro_f1": metrics.micro_f1(labels, preds),
        "macro_f1": metrics.macro_f1(labels, preds),
        "per_class": metrics.per_class_prf(labels, preds),
        "subset_accuracy": metrics.subset_accuracy(labels, preds),
    }


def _load_ablation(config: dict) -> Ablation:
    args = config["args"]
    drop_edges = {int(t) for t in args.get("drop_edges", "").split(",") if t.strip()}
    return Ablation(drop_edges=drop_edges, drop_ast=bool(args.get("drop_ast", False)))


def eval_seed(seed: int, args: argparse.Namespace) -> dict:
    """单 seed 主评估：读 best.pt + config → val 选阈值（复用 val_best_probs.pt）→ test 双报告。"""
    seed_dir = Path(args.runs_dir) / f"seed{seed}"
    checkpoint = torch.load(seed_dir / "best.pt", map_location="cpu")
    config = checkpoint["config"]
    split_seed = config.get("split_seed", seed)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    fuser, model = rebuild_models(config, checkpoint)
    fuser.to(device)
    model.to(device)

    with open(f"{args.split_dir}/split_seed{split_seed}.json", encoding="utf-8") as fh:
        split = json.load(fh)
    index, _ = build_index(Path(args.graph_dir))
    ab = _load_ablation(config)
    verify = "all" if config["args"].get("verify_channel_hash") else "cheap"

    # ---- 阈值搜索（只读 val；复用 best epoch 的 val probs，缺失则重算）----
    t0 = time.perf_counter()
    vb_path = seed_dir / "val_best_probs.pt"
    val_bases = split["val"]
    if vb_path.exists():
        vb = torch.load(vb_path, map_location="cpu")
        if list(vb.get("sample_ids", [])) == val_bases:
            val_probs, val_labels = vb["probs"], vb["labels"]
        else:
            vb = None
    else:
        vb = None
    if vb is None:
        val_samples = [load_graph(b, graph_dir=args.graph_dir, ab=ab, index=index,
                                  verify_channels=verify) for b in val_bases]
        val_probs, val_labels = infer(val_samples, fuser, model, args.batch_size, device=device)
    thr = metrics.search_global_threshold(val_probs, val_labels)
    best_threshold = float(thr["best_threshold"])

    # ---- 内部测试双报告 ----
    test_samples = [load_graph(b, graph_dir=args.graph_dir, ab=ab, index=index,
                               verify_channels=verify) for b in split["test"]]
    test_probs, test_labels = infer(test_samples, fuser, model, args.batch_size, device=device)
    infer_seconds = time.perf_counter() - t0

    mAP = metrics.mean_average_precision(test_probs, test_labels)
    results = {
        "seed": seed,
        "split_seed": split_seed,
        "val_threshold": best_threshold,
        "threshold_scan": thr,
        "mAP": mAP,                              # 不依赖阈值，仅此一份
        "test": {
            "fixed_0.5": compute_report(test_probs, test_labels, 0.5),
            "val_threshold": compute_report(test_probs, test_labels, best_threshold),
        },
        "support_note": "support≤2 的类仅描述性呈现、不进方法间比较结论（decisions §13）",
        "timing": {"infer_seconds": round(infer_seconds, 4)},
        "environment": {
            "device": device,
            "torch_version": torch.__version__,
            "python_version": platform.python_version(),
        },
    }
    (seed_dir / "results.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    r05 = results["test"]["fixed_0.5"]
    rvt = results["test"]["val_threshold"]
    print(f"seed{seed} (split_seed{split_seed}): test micro-F1 0.5={r05['micro_f1']:.4f} / "
          f"val_thr({best_threshold})={rvt['micro_f1']:.4f}；macro 0.5={r05['macro_f1']:.4f}；"
          f"mAP={mAP['mAP']:.4f} (classes used {mAP['ap_classes_used']})")
    return results


def _mean_std(values: list[float]) -> dict:
    arr = np.asarray(values, dtype=float)
    if arr.size == 0:
        return {"mean": None, "std": None, "n": 0}
    return {"mean": round(float(arr.mean()), 6),
            "std": round(float(arr.std(ddof=1)), 6) if arr.size > 1 else 0.0,
            "n": int(arr.size)}


def summarize(args: argparse.Namespace) -> None:
    """聚合 runs/seed*/results.json → runs/summary.json（每指标 mean ± std；主种子 seed0）。"""
    runs_dir = Path(args.runs_dir)
    result_paths = sorted(runs_dir.glob("seed*/results.json"))
    if not result_paths:
        raise RuntimeError(f"{runs_dir} 下没有 seed*/results.json（先跑 train + evaluate）")
    per_seed: dict = {}
    for rp in result_paths:
        data = json.loads(rp.read_text(encoding="utf-8"))
        seed = int(data["seed"])
        per_seed[seed] = {
            "split_seed": data["split_seed"],
            "val_threshold": data["val_threshold"],
            "micro_f1_fixed_0.5": data["test"]["fixed_0.5"]["micro_f1"],
            "macro_f1_fixed_0.5": data["test"]["fixed_0.5"]["macro_f1"],
            "micro_f1_val_threshold": data["test"]["val_threshold"]["micro_f1"],
            "macro_f1_val_threshold": data["test"]["val_threshold"]["macro_f1"],
            "mAP": data["mAP"]["mAP"],
        }
    seeds = sorted(per_seed)

    summary = {
        "seeds": seeds,
        "n_seeds": len(seeds),
        "main_seed": 0,
        "std_ddof": 1,
        "test": {
            "fixed_0.5": {
                "micro_f1": _mean_std([per_seed[s]["micro_f1_fixed_0.5"] for s in seeds]),
                "macro_f1": _mean_std([per_seed[s]["macro_f1_fixed_0.5"] for s in seeds]),
            },
            "val_threshold": {
                "micro_f1": _mean_std([per_seed[s]["micro_f1_val_threshold"] for s in seeds]),
                "macro_f1": _mean_std([per_seed[s]["macro_f1_val_threshold"] for s in seeds]),
            },
        },
        "mAP": _mean_std([per_seed[s]["mAP"] for s in seeds]),
        "per_seed": per_seed,
        "note": "主指标 micro-F1（标签对级）；macro-F1 为参考，注释须与其计算划分的支撑同口径；"
                "support≤2 的类仅描述性呈现（decisions §13）。",
    }
    (runs_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"summary: {len(seeds)} seeds {seeds} → micro-F1(0.5) "
          f"{summary['test']['fixed_0.5']['micro_f1']['mean']}±{summary['test']['fixed_0.5']['micro_f1']['std']}"
          f"；micro-F1(val_thr) {summary['test']['val_threshold']['micro_f1']['mean']}±"
          f"{summary['test']['val_threshold']['micro_f1']['std']} → {runs_dir / 'summary.json'}")


def main() -> None:
    args = parse_args()
    if args.summarize:
        summarize(args)
        return
    if args.seed is None:
        raise SystemExit("请指定 --seed <N>（单 seed 评估）或 --summarize（汇总）。")
    eval_seed(args.seed, args)


if __name__ == "__main__":
    main()
