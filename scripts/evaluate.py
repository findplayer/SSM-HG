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
import os
import time
from pathlib import Path

import numpy as np
import torch

import metrics
from dataset import (DEFAULT_GRAPH_DIR, ENV_LABEL_FILE, ENV_LABEL_KEY_MODE, Ablation,
                     build_index, collate, load_graph, resolve_label_key_mode)
from model import AblationConfig, NodeFuser, SSMHG

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
DEFAULT_SPLIT_DIR = f"{BASE}/products/alldata/splits"
DEFAULT_RUNS_DIR = f"{BASE}/runs"
NUM_RELATIONS = 5


def head_of(config: dict) -> str:
    """从产物读输出头型（`config["args"]["head"]` → `derived.head` → 默认 `multi`）。

    默认 `multi` 保证**引入 `--head` 之前的旧产物**照常评估（decisions §31）。
    """
    return config.get("args", {}).get("head") or config.get("derived", {}).get("head") or "multi"


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
    p.add_argument("--label-file", default=None,
                   help="标签文件路径；省略时按 CLI → SSMHG_LABEL_FILE → checkpoint 记录的 "
                        "label_source.file 依次回退（评估必须与训练同源，否则逐类 support 对错）。")
    p.add_argument("--label-key-mode", choices=["project", "stem"], default=None,
                   help="标签键模式；省略时按 CLI → SSMHG_LABEL_KEY_MODE → checkpoint 记录回退。")
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
    # 头宽**必须回读**（`--head binary` → 1；decisions §31）。原先硬编码 NUM_CLASSES=7，
    # 会在 `load_state_dict` 上炸出 `Linear(64,7)` vs `Linear(64,1)` 的尺寸 traceback。
    head = head_of(config)
    num_classes = int(d.get("num_classes", metrics.head_num_classes(head)))
    ckpt_head_w = int(checkpoint["model_state_dict"]["cls.2.weight"].shape[0])
    if ckpt_head_w != num_classes:
        raise SystemExit(
            f"[evaluate] 头宽不一致：config 说 {num_classes}（head={head}），"
            f"checkpoint 的 cls.2.weight 是 {ckpt_head_w} 行——config 与 best.pt 不同源？")
    # `num_relations` / `num_layers` 与 `num_classes` **同一回读模式**：一律取自 `derived`
    # （由图产物/本次训练写死），**不读模块常量、也不读 `args` 的默认值**。
    # RGCN 的 comp 是 [num_relations, num_bases]、层数是 state_dict 的键集合，两者任一错位
    # 都会在 `load_state_dict` 上炸出尺寸/缺键 traceback（或更糟：静默少加载）。
    model = SSMHG(in_dim=fuser.hidden, hid=args.get("hid", 128),
                  num_relations=int(d.get("num_relations", NUM_RELATIONS)),
                  num_bases=args.get("num_bases", 5), num_classes=num_classes,
                  dropout=args.get("model_dropout", 0.3),
                  conv_type=args.get("conv", "rgcn"),
                  use_meanpool=bool(args.get("meanpool", False)),
                  num_layers=int(d.get("num_layers", 2)))
    fuser.load_state_dict(checkpoint["fuser_state_dict"])
    model.load_state_dict(checkpoint["model_state_dict"])
    fuser.eval()
    model.eval()
    return fuser, model


def infer(samples, fuser: NodeFuser, model: SSMHG, batch_size: int, device: str = "cpu",
          head: str = "multi"):
    """前向（eval、无掩码、不丢边）→ (probs[N,C], labels[N,C])；结果回 CPU（指标层统一 numpy）。

    `C` = 头宽（`multi` 7 / `binary` 1），由 `head` 经 `dataset.stack_labels` 决定。
    """
    probs_list, labels_list = [], []
    with torch.no_grad():
        for i in range(0, len(samples), batch_size):
            chunk = samples[i:i + batch_size]
            channels, ei, et, batch, labels = collate(chunk, training=False, device=device,
                                                      head=head)
            x = fuser(channels, batch=batch)
            z, _, _ = model(x, ei, et, batch=batch)
            probs_list.append(torch.sigmoid(z).cpu())
            labels_list.append(labels.cpu())
    return torch.cat(probs_list, dim=0), torch.cat(labels_list, dim=0)


def compute_report(probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """单阈值报告（**多标签臂专用**）：micro/macro-F1、逐类 P/R/F1（随 support）、subset accuracy。"""
    preds = metrics.binary_preds(probs, thr)
    return {
        "threshold": thr,
        "micro_f1": metrics.micro_f1(labels, preds),
        "macro_f1": metrics.macro_f1(labels, preds),
        "per_class": metrics.per_class_prf(labels, preds),
        "subset_accuracy": metrics.subset_accuracy(labels, preds),
    }


def compute_binary_report(probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """单阈值报告（**二分类臂专用**，decisions §31）。

    键空间与多标签臂**只共享 `micro_f1` 一个键**（同一指标定义，见下），其余一律换名：
    `binary_*` 而非 `macro_f1`/`per_class`/`subset_accuracy`——那些量在单列下**没有意义**，
    读 `test.fixed_0.5.macro_f1` 会拿到 `KeyError`（响亮），而不是一个看着像数的假值。

    `micro_f1` 的两种地位要分清：
      - **定义上与七类臂同一个量**：标签对级全局 TP/FP/FN ⇒ 两条臂可直接进同一张主表；
      - **数值上与 `binary_f1` 恒等**：`C == 1` 时 `2TP/(2TP+FP+FN)` 就是二分类 F1。
        ⚠ 因此它**必须**由 `metrics.micro_f1_counts` 计数式算出，**绝不能**调
        `metrics.micro_f1`——后者对 `[N,1]` 会退化成 accuracy（§28 陷阱）。
    """
    p = (metrics._as_numpy(probs) >= thr).astype(int)
    y = metrics._as_numpy(labels)
    r = metrics.binary_prf(y, p)
    return {
        "threshold": thr,
        # `micro_f1`：**与七类臂同一个指标定义**（标签对级全局 TP/FP/FN）。单列下它恒等于
        # `binary_f1`——两者是同一式子的两种叫法，故并列给出，便于两条臂进同一张主表。
        # ⚠ 由 `micro_f1_counts` 计数式算出，**绝不走 `metrics.micro_f1`**（单列会退化成 accuracy，§28）。
        "micro_f1": metrics.micro_f1_counts(y, p),
        "binary_f1": r["f1"] if r["f1"] is not None else 0.0,
        "binary_precision": r["precision"],
        "binary_recall": r["recall"],
        "binary_accuracy": r["accuracy"],
        "binary_FPR": r["FPR"],
        "binary_FNR": r["FNR"],
        "TP": r["TP"], "FP": r["FP"], "FN": r["FN"], "TN": r["TN"],
        "support": r["support"],
    }


def compute_report_for(head: str, probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """按头型分派单阈值报告（两条臂**只共享 `micro_f1` 键**）。"""
    return (compute_binary_report if head == "binary" else compute_report)(probs, labels, thr)


def _load_ablation(config: dict) -> Ablation:
    args = config["args"]
    drop_edges = {int(t) for t in args.get("drop_edges", "").split(",") if t.strip()}
    return Ablation(drop_edges=drop_edges, drop_ast=bool(args.get("drop_ast", False)))


def eval_seed(seed: int, args: argparse.Namespace) -> dict:
    """单 seed 主评估：读 best.pt + config → val 选阈值（复用 val_best_probs.pt）→ test 双报告。"""
    seed_dir = Path(args.runs_dir) / f"seed{seed}"
    checkpoint = torch.load(seed_dir / "best.pt", map_location="cpu")
    config = checkpoint["config"]
    head = head_of(config)
    split_seed = config.get("split_seed", seed)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    fuser, model = rebuild_models(config, checkpoint)
    fuser.to(device)
    model.to(device)

    with open(f"{args.split_dir}/split_seed{split_seed}.json", encoding="utf-8") as fh:
        split = json.load(fh)
    # 标签来源优先级：CLI → 环境变量 → checkpoint 的 label_source（评估必须与训练同源）
    saved = config.get("label_source") or {}
    lab_file = (args.label_file or os.environ.get(ENV_LABEL_FILE) or saved.get("file"))
    lab_mode = (args.label_key_mode or os.environ.get(ENV_LABEL_KEY_MODE)
                or saved.get("key_mode"))
    if lab_file or lab_mode:
        print(f"[evaluate] 标签来源：file={lab_file or '(默认)'} key_mode={lab_mode or '(默认)'}")
    index, _unmatched = build_index(Path(args.graph_dir), label_file=lab_file, key_mode=lab_mode)
    missing = [b for b in split["val"] + split["test"] if b not in index]
    if missing:
        raise SystemExit(f"[evaluate] 划分内有 {len(missing)} 个合约不在标签索引中"
                         f"（标签文件或 --label-key-mode 与训练不一致？）例：{missing[:5]}")
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
        val_probs, val_labels = infer(val_samples, fuser, model, args.batch_size,
                                      device=device, head=head)
    if head == "binary":
        # ⚠ **绝不能走 search_global_threshold**：单列 [N,1] 会让 micro-F1 退化成 accuracy（§28）。
        thr = metrics.search_global_threshold_binary(val_probs, val_labels)
    else:
        thr = metrics.search_global_threshold(val_probs, val_labels)
    best_threshold = float(thr["best_threshold"])

    # ---- 内部测试双报告 ----
    test_samples = [load_graph(b, graph_dir=args.graph_dir, ab=ab, index=index,
                               verify_channels=verify) for b in split["test"]]
    test_probs, test_labels = infer(test_samples, fuser, model, args.batch_size,
                                    device=device, head=head)
    infer_seconds = time.perf_counter() - t0

    # mAP 只对多标签臂有意义；二分类臂改报 AP（同样阈值无关）。
    # ⚠ 键名**不复用 `mAP`**：`mean_average_precision` 在 [N,1] 上会 IndexError，
    #   而把二分类 AP 塞进 `mAP` 键会让下游把两个不同的量当成同一个。
    mAP = (metrics.binary_average_precision(test_probs, test_labels) if head == "binary"
           else metrics.mean_average_precision(test_probs, test_labels))
    results = {
        "seed": seed,
        "split_seed": split_seed,
        "head": head,                            # 供 summarize / aggregate 分辨口径
        "select_metric": "val_binary_ap" if head == "binary" else "val_micro_f1",
        "val_threshold": best_threshold,
        "threshold_scan": thr,
        "mAP" if head == "multi" else "AP": mAP,  # 不依赖阈值，仅此一份
        "test": {
            "fixed_0.5": compute_report_for(head, test_probs, test_labels, 0.5),
            "val_threshold": compute_report_for(head, test_probs, test_labels, best_threshold),
        },
        "support_note": ("support≤2 的类仅描述性呈现、不进方法间比较结论（decisions §13）"
                         if head == "multi" else
                         "二分类臂：单类「有没有漏洞」，键名一律 binary_*；不报 per-class/macro-F1"
                         "（decisions §31）"),
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
    if head == "binary":
        print(f"seed{seed} (split_seed{split_seed}) [head=binary]: test F1 0.5={r05['binary_f1']:.4f} / "
              f"val_thr({best_threshold})={rvt['binary_f1']:.4f}；"
              f"FPR 0.5={r05['binary_FPR']:.4f} FNR 0.5={r05['binary_FNR']:.4f}；"
              f"AP={mAP['AP'] if mAP['AP'] is not None else float('nan'):.4f}")
    else:
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


def _provenance(runs_dir: Path, seeds: list) -> dict:
    """**口径戳**：summary 描述的是哪一套正典（编码器树 / 划分种子 / 每种子阈值）。

    只读各 seed 的 `config.json`，**不加载权重**。取不到就记 null，**不猜**。
    `graph_dir` 是判定的唯一依据：`…/graphs_ft/ss{S}` = 微调正典（§37 起）、
    `…/graphs` = 冻结编码器树（现仅 `cb_frozen` 类消融臂）、其余按原样记录。
    """
    graph_dirs, heads, n = set(), set(), 0
    for s in seeds:
        cfg = runs_dir / f"seed{s}" / "config.json"
        if not cfg.exists():
            continue
        try:
            c = json.loads(cfg.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        n += 1
        heads.add((c.get("args") or {}).get("head", "multi"))
        gd = (c.get("args") or {}).get("graph_dir")
        if gd:
            graph_dirs.add(str(gd))
    trees = sorted({Path(g).name for g in graph_dirs})          # ss0/ss1/ss2 或 graphs
    if not graph_dirs:
        encoding = None
    elif all("graphs_ft_buggy" in g for g in graph_dirs):
        # ⚠ **必须比下面那条泛匹配先判**：`graphs_ft_buggy` 是 `graphs_ft` 的超串，
        #   否则新臂会被口径戳写成"§37 正典"——那正是口径戳要防的事（自己认错自己）。
        encoding = "fine-tuned CodeBERT（**含 buggy_* 的池 497 划分**；任务2 臂，非 §37 正典）"
    elif all("graphs_ft" in g for g in graph_dirs):
        encoding = "fine-tuned CodeBERT（§37 起正典）"
    elif all(Path(g).name == "graphs" for g in graph_dirs):
        encoding = "frozen CodeBERT（§37 前正典；现仅消融臂 cb_frozen）"
    else:
        encoding = "混合（⚠ 同一次聚合里出现了不同的编码器树，结果不可解读）"
    return {"n_configs": n, "encoder": encoding,
            "graph_dir_leaf": trees,
            "head": sorted(heads) if heads else None,
            "note": "由各 seed 的 config.json::args 只读推导；不加载权重。"}


def summarize(args: argparse.Namespace) -> None:
    """聚合 runs/seed*/results.json → runs/summary.json（每指标 mean ± std；主种子 seed0）。"""
    runs_dir = Path(args.runs_dir)
    result_paths = sorted(runs_dir.glob("seed*/results.json"))
    if not result_paths:
        raise RuntimeError(f"{runs_dir} 下没有 seed*/results.json（先跑 train + evaluate）")
    per_seed: dict = {}
    heads: set = set()
    for rp in result_paths:
        data = json.loads(rp.read_text(encoding="utf-8"))
        seed = int(data["seed"])
        head = data.get("head", "multi")
        heads.add(head)
        if head == "binary":
            per_seed[seed] = {
                "split_seed": data["split_seed"],
                "val_threshold": data["val_threshold"],
                "micro_f1_fixed_0.5": data["test"]["fixed_0.5"]["micro_f1"],
                "micro_f1_val_threshold": data["test"]["val_threshold"]["micro_f1"],
                "binary_f1_fixed_0.5": data["test"]["fixed_0.5"]["binary_f1"],
                "binary_f1_val_threshold": data["test"]["val_threshold"]["binary_f1"],
                "binary_precision_val_threshold": data["test"]["val_threshold"]["binary_precision"],
                "binary_recall_val_threshold": data["test"]["val_threshold"]["binary_recall"],
                "binary_FPR_val_threshold": data["test"]["val_threshold"]["binary_FPR"],
                "binary_FNR_val_threshold": data["test"]["val_threshold"]["binary_FNR"],
                "AP": data["AP"]["AP"],
            }
        else:
            per_seed[seed] = {
                "split_seed": data["split_seed"],
                "val_threshold": data["val_threshold"],
                "micro_f1_fixed_0.5": data["test"]["fixed_0.5"]["micro_f1"],
                "macro_f1_fixed_0.5": data["test"]["fixed_0.5"]["macro_f1"],
                "micro_f1_val_threshold": data["test"]["val_threshold"]["micro_f1"],
                "macro_f1_val_threshold": data["test"]["val_threshold"]["macro_f1"],
                "mAP": data["mAP"]["mAP"],
            }
    # 两种头型的键空间互不相交，混在一起聚合会产出"看着正常实为拼凑"的均值
    if len(heads) > 1:
        raise RuntimeError(
            f"[evaluate] {runs_dir} 下混有 head={sorted(heads)} 两种产物，拒绝汇总"
            "（口径不同、键空间不相交；请分目录评估，decisions §31）")
    seeds = sorted(per_seed)

    summary = {
        "seeds": seeds,
        "n_seeds": len(seeds),
        "main_seed": 0,
        "std_ddof": 1,
        "per_seed": per_seed,
    }
    head = sorted(heads)[0]
    if head == "binary":
        summary["head"] = "binary"
        summary["test"] = {
            "fixed_0.5": {
                "micro_f1": _mean_std([per_seed[x]["micro_f1_fixed_0.5"] for x in seeds]),
                "binary_f1": _mean_std([per_seed[x]["binary_f1_fixed_0.5"] for x in seeds]),
            },
            "val_threshold": {
                "micro_f1": _mean_std([per_seed[x]["micro_f1_val_threshold"] for x in seeds]),
                "binary_f1": _mean_std([per_seed[x]["binary_f1_val_threshold"] for x in seeds]),
                "binary_precision": _mean_std([per_seed[x]["binary_precision_val_threshold"] for x in seeds]),
                "binary_recall": _mean_std([per_seed[x]["binary_recall_val_threshold"] for x in seeds]),
                "binary_FPR": _mean_std([per_seed[x]["binary_FPR_val_threshold"] for x in seeds]),
                "binary_FNR": _mean_std([per_seed[x]["binary_FNR_val_threshold"] for x in seeds]),
            },
        }
        summary["AP"] = _mean_std([per_seed[x]["AP"] for x in seeds])
        summary["note"] = ("二分类臂（--head binary，decisions §31）：单类「有没有漏洞」。"
                           "`micro_f1` 与 `binary_f1` 在此**恒等**（标签对级 micro-F1 在 C=1 下的两种叫法），"
                           "并列给出以便与七类臂进同一张主表；不报 macro-F1 与 per-class。")
        line = (f"summary[head=binary]: {len(seeds)} seeds {seeds} → micro-F1(=binary-F1)(0.5) "
                f"{summary['test']['fixed_0.5']['micro_f1']['mean']}±"
                f"{summary['test']['fixed_0.5']['micro_f1']['std']}"
                f"；micro-F1(val_thr) {summary['test']['val_threshold']['micro_f1']['mean']}±"
                f"{summary['test']['val_threshold']['micro_f1']['std']}")
    else:
        summary["head"] = "multi"
        summary["test"] = {
            "fixed_0.5": {
                "micro_f1": _mean_std([per_seed[x]["micro_f1_fixed_0.5"] for x in seeds]),
                "macro_f1": _mean_std([per_seed[x]["macro_f1_fixed_0.5"] for x in seeds]),
            },
            "val_threshold": {
                "micro_f1": _mean_std([per_seed[x]["micro_f1_val_threshold"] for x in seeds]),
                "macro_f1": _mean_std([per_seed[x]["macro_f1_val_threshold"] for x in seeds]),
            },
        }
        summary["mAP"] = _mean_std([per_seed[x]["mAP"] for x in seeds])
        summary["note"] = ("主指标 micro-F1（标签对级）；macro-F1 为参考，注释须与其计算划分的支撑同口径；"
                           "support≤2 的类仅描述性呈现（decisions §13）。")
        # 🔴 **口径戳（2026-09-20 补）**：summary 是跨种子聚合，一旦正典换了而它没重算，
        #    就会与本目录的 seed*/results.json **对不上**（§37 切换时实际发生过：run 是新的、
        #    summary 还是冻结口径的旧值）。把来源写进产物，读者不必靠数字反推是哪一套正典。
        summary["provenance"] = _provenance(runs_dir, seeds)
        line = (f"summary: {len(seeds)} seeds {seeds} → micro-F1(0.5) "
                f"{summary['test']['fixed_0.5']['micro_f1']['mean']}±"
                f"{summary['test']['fixed_0.5']['micro_f1']['std']}"
                f"；micro-F1(val_thr) {summary['test']['val_threshold']['micro_f1']['mean']}±"
                f"{summary['test']['val_threshold']['micro_f1']['std']}")
    (runs_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{line} → {runs_dir / 'summary.json'}")


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
