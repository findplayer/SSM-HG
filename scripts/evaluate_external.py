#!/usr/bin/env python3
"""**外部测试**：把已训练好的模型原样搬到另一个数据集（DIVE）上推理并报告（大纲 `改II` 5.2 层次一）。

**它与 `evaluate.py` 的三点不同**（也是不能直接复用后者的原因）：

| | `evaluate.py` | 本脚本 |
| --- | --- | --- |
| 数据 | 训练语料的 val/test 划分 | **另一个数据集**的全部图（DIVE 900 张） |
| 阈值 | **在 val 上重新搜** | **只读源语料的 `thresholds.json`**，绝不重搜 |
| 划分 | 读 `split_seed*.json` | 无划分概念（外部测试集不参与任何选择） |

🔴 **阈值纪律**：DIVE 是外部测试集，**不得用它回头调参或调阈值**（`AGENTS.md`、大纲 5.1）。
故 `@val_thr` 一列的阈值逐字来自**源语料验证集**的搜索结果，本脚本只把它**应用**到 DIVE 上。

**报告内容**（`改II` 5.5.1 五项分析里的 (1)(2)(3)）：
  1. micro-F1 / macro-F1 / 逐类 F1（两个工作点：固定 0.5 + 源语料验证集阈值）；
  2. 逐类 PR-AUC 与 mAP（**不依赖阈值**，先验失配下比 F1 稳定）+
     训练语料与 DIVE 的逐类正样本率并列（区分"先验变化"与"排序质量变化"）；
  3. DIVE **全零标签（正常合约）子集**上的每类假阳性率 + 合约级误报率。

用法（从仓库根目录运行）：
  # 单臂
  python scripts/evaluate_external.py --runs-dir runs/ablation/cb_frozen \\
      --graph-dir products/dive/graphs --out eval_results/dive/cb_frozen.json
  # 全部 21 臂 × ①② 两组语料 → eval_results/dive/matrix_{main,aug}.json
  python scripts/evaluate_external.py --matrix main --out eval_results/dive/matrix_main.json
"""
from __future__ import annotations

import argparse
import json
import platform
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import evaluate as EV                                                   # noqa: E402
import metrics                                                          # noqa: E402
import run_ablation as RA                                               # noqa: E402
from dataset import build_index, load_graph                             # noqa: E402

SEEDS = (0, 1, 2)
VULN = metrics.VULN_NAMES
# 语料 → 它在 DIVE 上的特征树（见 `build_dive_external_set.py` 的编码器矩阵）
DIVE_TREE = {"main": REPO / "products" / "dive" / "graphs_ft",
             "aug": REPO / "products" / "dive" / "graphs_ft_aug"}
FROZEN_TREE = REPO / "products" / "dive" / "graphs"


def rel(p: Path) -> str:
    """仓库相对路径（用于写进产物）；不在仓库内时原样返回（自检传 `/tmp` 之类时不炸）。"""
    try:
        return str(Path(p).resolve().relative_to(REPO))
    except ValueError:
        return str(p)


def dive_graph_dir_of(main: bool, src_graph_dir: str, split_seed: int = 0) -> Path:
    """把**源语料**的 `graph_dir` 映射到 DIVE 上对应的一棵树。

    映射规则（与 `build_dive_external_set.py` 的布局逐条对应）：
      `products/<语料>/graphs`                        → `products/dive/graphs`（冻结编码器，①②共用）
      `products/<语料>/graphs_ft/ss{S}`               → `products/dive/graphs_ft{,_aug}/ss{S}`
      `products/<语料>/graphs_ft/graph_variants/<变体>_ss{S}` → 同名子树

    `split_seed` 只用于取"哪一棵微调树"——同一划分种子下，①② 的 DIVE 树各一份。
    """
    src = Path(src_graph_dir).resolve()
    name, parent = src.name, src.parent.name
    tree = DIVE_TREE["main" if main else "aug"]
    if name == "graphs":
        return FROZEN_TREE
    if re.fullmatch(r"ss\d+", name) and parent == "graphs_ft":
        return tree / name
    if parent == "graph_variants" and src.parent.parent.name == "graphs_ft":
        return tree / "graph_variants" / name
    raise SystemExit(f"[ext] 无法把源 graph_dir 映射到 DIVE：{src}\n"
                     f"  （本脚本只认 graphs / graphs_ft/ss<S> / graph_variants/<变体>_ss<S> 三种形态）")


def per_class_fpr_on_normals(probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """**全零标签（正常合约）子集**上的逐类假阳性率（`改II` 5.5.1(3)）。

    取 `labels.sum(dim=1) == 0` 的合约，看模型在阈值下判出了哪些类——
    这些全是假阳性（真值七类全 0）。合约级误报率 = 至少报出一类的比例。
    """
    y = metrics._as_numpy(labels)
    normals = np.where(y.sum(axis=1) == 0)[0]
    if normals.size == 0:
        return {"n": 0, "per_class_FPR": [None] * len(VULN), "contract_level_FPR": None}
    p = metrics._as_numpy(probs)[normals] >= thr
    per_class = [float(p[:, c].mean()) for c in range(len(VULN))]
    return {
        "n": int(normals.size),
        "per_class_FPR": per_class,
        "contract_level_FPR": float(p.any(axis=1).mean()),
        "note": "分母是 DIVE 全零标签合约数；多标签下这是**条件** FPR（真值全 0 时误报该类的概率）",
    }


def buggy_subset_prf(probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """**有漏洞合约子集**上的逐类 P/R/F1（`metrics.buggy_f1` 的逐类版，`改II` 5.5.1 补充口径）。

    取 `labels.any(axis=1)` 的合约——干净合约上的误报被**整段摘掉**，只回答
    「在真正有漏洞的合约上，七类标签判得准不准」。标量 `buggy_f1` 直接调
    `metrics.buggy_f1`（子集切片后算 micro-F1），**不另写一份实现**（§28 的教训）。

    🔴 **与「合约级二分类 F1」不是同一个数**（`decisions.md` §30）：后者把七类真值与预测
    都塌成 `any(...)`，会把「有漏洞但报错了类」整类免罚；本函数**不做塌缩**。
    """
    if not metrics._as_numpy(labels).any(axis=1).any():
        return {"n": 0, "buggy_f1": None, "per_class": None,
                "note": "子集为空（本集无任何有漏洞合约）"}
    preds = metrics.binary_preds(probs, thr)
    mask = metrics._as_numpy(labels).any(axis=1)
    return {
        "n": int(mask.sum()),
        "buggy_f1": metrics.buggy_f1(labels, preds)["f1"],
        "per_class": metrics.per_class_prf(metrics._as_numpy(labels)[mask],
                                           metrics._as_numpy(preds)[mask]),
        "note": "子集 = labels.any(axis=1)；干净合约上的误报被整段摘掉",
    }


def prior_comparison(labels: torch.Tensor, src_train_rate: list[float] | None) -> dict:
    """训练语料 vs DIVE 的逐类正样本率（`改II` 5.5.1(2)：区分"先验变化"与"排序质量变化"）。"""
    y = metrics._as_numpy(labels)
    dive_rate = [float(y[:, c].mean()) for c in range(len(VULN))]
    return {
        "dive_test_pos_rate": dive_rate,
        "dive_test_support": [int(y[:, c].sum()) for c in range(len(VULN))],
        "source_train_pos_rate": src_train_rate,
        "delta": ([round(d - s, 4) for d, s in zip(dive_rate, src_train_rate)]
                  if src_train_rate else None),
    }


def source_train_pos_rate(run_dir: Path) -> list[float] | None:
    """源语料**训练划分**的逐类正样本率（`改II` 5.5.1(2)：与 DIVE 并列，看类别先验是否漂移）。

    只读划分文件 + 标签文件，**不扫图**（故不必依赖 graph_dir 存在）。
    标签源按 `train.py` 记进 config 的 `label_source` 回退（与训练同源，`decisions.md` §29）。
    """
    from dataset import build_proj_labels, project_of_base
    cfg = json.loads((run_dir / "seed0" / "config.json").read_text(encoding="utf-8"))
    args, src = cfg["args"], cfg.get("label_source", {})
    lab = args.get("label_file") or src.get("file") or str(
        REPO / "alldata(readonly)" / "contract_labels.json")
    mode = args.get("label_key_mode") or src.get("key_mode") or "project"
    plabels = build_proj_labels(label_file=lab, key_mode=mode)
    split = json.loads((Path(args["split_dir"]) / f"split_seed{args.get('split_seed', 0)}.json")
                       .read_text(encoding="utf-8"))
    rows = []
    for base in split["train"]:
        targets_list = plabels.get(base if mode == "stem" else project_of_base(base))
        if not targets_list:
            continue
        v = [0] * len(VULN)
        for t in targets_list:
            for i, x in enumerate(t[:len(VULN)]):
                if x:
                    v[i] = 1
        rows.append(v)
    if not rows:
        return None
    arr = np.asarray(rows, dtype=float)
    return [round(float(arr[:, c].mean()), 4) for c in range(len(VULN))]


def eval_one_seed(run_dir: Path, seed: int, graph_dir: Path, label_file: str,
                  key_mode: str, batch_size: int, bases: list[str] | None = None) -> dict:
    """单 seed 外部测试：读 best.pt → 全量推理 → 两个工作点报告 + mAP + 正常子集 FPR。"""
    seed_dir = run_dir / f"seed{seed}"
    ckpt = torch.load(seed_dir / "best.pt", map_location="cpu")
    config = ckpt["config"]
    head = EV.head_of(config)
    if head != "multi":
        raise SystemExit(f"[ext] {seed_dir} 的 head={head}；本脚本只处理七类多标签臂")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    fuser, model = EV.rebuild_models(config, ckpt)
    fuser.to(device)
    model.to(device)

    # 🔴 阈值**只读**源语料验证集的搜索结果，绝不在 DIVE 上重搜
    thr_path = seed_dir / "thresholds.json"
    if not thr_path.exists():
        raise SystemExit(f"[ext] {thr_path} 不存在——阈值必须来自源语料验证集，"
                         f"不能就地重搜（大纲 5.1）。先跑该臂的 evaluate.py。")
    val_thr = float(json.loads(thr_path.read_text(encoding="utf-8"))["best_threshold"])

    index, _unmatched = build_index(graph_dir, label_file=label_file, key_mode=key_mode)
    # `bases` 非空 = 自检模式：只在指定子集上评（用来对拍同语料内部测试的既有数字）
    bases = bases or sorted(p.name[: -len("_pyg.pt")] for p in graph_dir.glob("*_pyg.pt"))
    missing = [b for b in bases if b not in index]
    if missing:
        raise SystemExit(f"[ext] {len(missing)}/{len(bases)} 张 DIVE 图没有匹配到标签"
                         f"（--label-key-mode 用错了？）例：{missing[:5]}")

    ab = EV._load_ablation(config)
    verify = "all" if config["args"].get("verify_channel_hash") else "cheap"
    t0 = time.perf_counter()
    samples = [load_graph(b, graph_dir=str(graph_dir), ab=ab, index=index,
                          verify_channels=verify) for b in bases]
    probs, labels = EV.infer(samples, fuser, model, batch_size, device=device, head=head)
    infer_s = time.perf_counter() - t0

    mAP = metrics.mean_average_precision(probs, labels)
    return {
        "seed": seed,
        "source_run": rel(seed_dir),
        "source_val_threshold": val_thr,
        "n_contracts": len(bases),
        "test": {
            "fixed_0.5": EV.compute_report_for(head, probs, labels, 0.5),
            "source_val_threshold": EV.compute_report_for(head, probs, labels, val_thr),
        },
        "mAP": mAP,
        "normal_subset_0.5": per_class_fpr_on_normals(probs, labels, 0.5),
        "normal_subset_val_thr": per_class_fpr_on_normals(probs, labels, val_thr),
        "buggy_subset_0.5": buggy_subset_prf(probs, labels, 0.5),
        "buggy_subset_val_thr": buggy_subset_prf(probs, labels, val_thr),
        "prior": prior_comparison(labels, None),
        "timing": {"infer_seconds": round(infer_s, 4), "device": device},
    }


def mean_std(values: list[float]) -> dict:
    arr = np.asarray([v for v in values if v is not None], dtype=float)
    if arr.size == 0:
        return {"mean": None, "std": None, "n": 0}
    return {"mean": round(float(arr.mean()), 6),
            "std": round(float(arr.std(ddof=1)), 6) if arr.size > 1 else 0.0,
            "n": int(arr.size)}


def summarize(per_seed: list[dict]) -> dict:
    """跨 3 种子聚合：标量取 mean±std，逐类取逐类 mean±std（附 support）。"""
    out = {"micro_f1@0.5": [], "micro_f1@val_thr": [], "macro_f1@0.5": [], "macro_f1@val_thr": [],
           "mAP": [], "contract_FPR@0.5": [], "contract_FPR@val_thr": [],
           "buggy_f1@0.5": [], "buggy_f1@val_thr": []}
    for r in per_seed:
        out["micro_f1@0.5"].append(r["test"]["fixed_0.5"]["micro_f1"])
        out["micro_f1@val_thr"].append(r["test"]["source_val_threshold"]["micro_f1"])
        out["macro_f1@0.5"].append(r["test"]["fixed_0.5"]["macro_f1"])
        out["macro_f1@val_thr"].append(r["test"]["source_val_threshold"]["macro_f1"])
        out["mAP"].append(r["mAP"]["mAP"])
        out["contract_FPR@0.5"].append(r["normal_subset_0.5"]["contract_level_FPR"])
        out["contract_FPR@val_thr"].append(r["normal_subset_val_thr"]["contract_level_FPR"])
        # `.get` 链使 `--resummarize` 能吃**没有该字段的旧 matrix json**（回填时不炸）
        out["buggy_f1@0.5"].append((r.get("buggy_subset_0.5") or {}).get("buggy_f1"))
        out["buggy_f1@val_thr"].append((r.get("buggy_subset_val_thr") or {}).get("buggy_f1"))
    res = {k: mean_std(v) for k, v in out.items()}

    # ---- 逐类明细 ----
    # 🔴 结构必须与 `collect_ablation_results._agg_per_class` **逐键一致**
    #    （`names` / `per_seed_support` / 每个指标是 {类名: {mean,std}}），
    #    否则 `collect_dive_comparison` 取不到值、整张表静默变成「—」。
    # ⚠ 首版把"逐类列表"当成标量序列聚合，结果 `f1` 塌成一个数（不报错、只是表全空）。
    res["per_class"] = {}
    for wp in ("fixed_0.5", "source_val_threshold"):
        names = list(per_seed[0]["test"][wp]["per_class"]["names"])
        block = {"names": names,
                 "per_seed_support": {str(SEEDS[i]): list(r["test"][wp]["per_class"]["support"])
                                      for i, r in enumerate(per_seed)},
                 "f1": {}, "precision": {}, "recall": {}}
        for ci, cn in enumerate(names):
            for m in ("f1", "precision", "recall"):
                vals = [float(r["test"][wp]["per_class"][m][ci]) for r in per_seed]
                block[m][cn] = {"mean": round(float(np.mean(vals)), 6),
                                "std": round(float(np.std(vals, ddof=1)), 6) if len(vals) > 1 else 0.0}
        res["per_class"][wp] = block

    # 逐类 PR-AUC（`改II` 5.5.1(2) 明确要求）：**不依赖阈值**，先验失配下比 F1 稳定，
    # 是"排序质量有没有跨数据集掉下来"的唯一可用证据。`ap` 长度 7，support=0 的类为 None。
    res["per_class_AP"] = {c: mean_std([r["mAP"]["ap"][i] for r in per_seed])
                           for i, c in enumerate(VULN)}
    res["ap_classes_used"] = [r["mAP"]["ap_classes_used"] for r in per_seed]
    res["ap_skipped"] = [r["mAP"]["skipped"] for r in per_seed]
    res["per_class_support"] = per_seed[0]["test"]["fixed_0.5"]["per_class"]["support"]
    res["names"] = list(VULN)
    res["normal_subset_n"] = per_seed[0]["normal_subset_0.5"]["n"]
    res["normal_subset_per_class_FPR@val_thr"] = [
        mean_std([r["normal_subset_val_thr"]["per_class_FPR"][c] for r in per_seed])
        for c in range(len(VULN))]
    return res


def run_arm(name: str, run_dir: Path, graph_dirs: dict[int, Path], label_file: str,
            key_mode: str, batch_size: int, selfcheck: bool = False) -> dict:
    """一个臂 × 三个种子。`graph_dirs` 逐种子给（微调编码器每个划分种子一套 ⇒ DIVE 树也逐种子）。"""
    per_seed = []
    train_rate = source_train_pos_rate(run_dir)          # 源语料训练划分的逐类正样本率
    for s in SEEDS:
        if not (run_dir / f"seed{s}" / "best.pt").exists():
            print(f"  [{name}] seed{s} 无 best.pt，跳过", flush=True)
            continue
        # 自检：只在**该种子自己的内部测试划分**上评，用来与 `results.json` 对拍。
        # 🔴 自检时标签源**必须**取自该 run 的 `label_source`（不是 CLI 默认值）——
        #    否则主库会被按 DIVE 的 stem 键去匹配，46/46 全部报"没有匹配到标签"。
        subset = None
        if selfcheck:
            cfg = json.loads((run_dir / f"seed{s}" / "config.json").read_text(encoding="utf-8"))
            args, src = cfg["args"], cfg.get("label_source", {})
            split = json.loads((Path(args["split_dir"])
                                / f"split_seed{args.get('split_seed', s)}.json")
                               .read_text(encoding="utf-8"))
            subset = split["test"]
            # 🔴 自检要比的是**源语料自己的**图，不是 DIVE 树——否则会把 DIVE 的图
            #    拿去和源语料的标签对，46/46 全不匹配。逐种子取源目录（`ss<N>` → `ss{s}`）。
            src_dir = Path(re.sub(r"ss\d+$", f"ss{s}", str(args["graph_dir"])))
            r = eval_one_seed(run_dir, s, src_dir, src.get("file", label_file),
                              src.get("key_mode", key_mode), batch_size, bases=subset)
        else:
            r = eval_one_seed(run_dir, s, graph_dirs[s], label_file, key_mode, batch_size)
        r["prior"]["source_train_pos_rate"] = train_rate
        r["prior"]["delta"] = ([round(d - t, 4) for d, t in
                                zip(r["prior"]["dive_test_pos_rate"], train_rate)]
                               if train_rate else None)
        per_seed.append(r)
        print(f"  [{name}] seed{s}: micro@0.5={r['test']['fixed_0.5']['micro_f1']:.4f} "
              f"@val_thr({r['source_val_threshold']})="
              f"{r['test']['source_val_threshold']['micro_f1']:.4f} "
              f"mAP={r['mAP']['mAP']:.4f}", flush=True)
    return {"arm": name, "run_dir": rel(run_dir),
            "graph_dirs": {str(k): rel(v) for k, v in graph_dirs.items()},
            "per_seed": per_seed, "summary": summarize(per_seed) if per_seed else None}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="DIVE 外部测试")
    p.add_argument("--runs-dir", default="", help="单个臂的 run 目录（含 seed{0,1,2}/best.pt）")
    p.add_argument("--graph-dir", default="", help="DIVE 图目录（显式指定时不做映射）")
    p.add_argument("--matrix", choices=["main", "aug"], default="",
                   help="跑该组语料的全部 21 个消融臂 + 正典")
    p.add_argument("--label-file", default=str(REPO / "DIVE" / "contract_labels.json"))
    p.add_argument("--label-key-mode", default="stem")
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--selfcheck", action="store_true",
                   help="自检模式：只在**源语料自己的内部测试划分**上评，用来与 results.json 对拍"
                        "（验证本脚本的阈值/标签/指标路径与 evaluate.py 一致，**不用于 DIVE**）")
    p.add_argument("--resummarize", default="",
                   help="只从既有 matrix json 的 `per_seed` 重算 `summary`（不重跑推理）——"
                        "改了 `summarize()` 之后用它回填，避免为改表格式而重跑 890 张图")
    p.add_argument("--out", required=True)
    return p.parse_args()


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    if args.resummarize:
        src = Path(args.resummarize)
        d = json.loads(src.read_text(encoding="utf-8"))
        for arm, v in d["arms"].items():
            if v.get("per_seed"):
                v["summary"] = summarize(v["per_seed"])
        d["resummarized_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        out.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[ext] 已重算 {len(d['arms'])} 臂的 summary → {out}")
        return
    out.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()

    if args.matrix:
        main_group = args.matrix == "main"
        # ① 正典 runs/seed{S}；② 正典 runs/augmentation/seed{S}（decisions §23：两组各自独立）
        canon_dir = REPO / "runs" if main_group else REPO / "runs" / "augmentation"
        base_cfg = canon_dir / "seed0" / "config.json"
        canon_args = RA.canonical_args(base_cfg)
        variants = RA.variants_root_of(canon_args)
        frozen = RA.frozen_graphs_of(canon_args)
        arms = [("canon", None)] + [(n, ov) for n, ov, _d in RA.ABLATIONS]
        result = {"dataset": "DIVE", "corpus": args.matrix, "label_file": args.label_file,
                  "label_key_mode": args.label_key_mode, "arms": {}, "created_utc":
                  datetime.now(timezone.utc).isoformat(timespec="seconds")}
        for name, override in arms:
            run_dir = canon_dir if name == "canon" else (REPO / ("runs/ablation" if main_group
                                                                 else "runs/ablation_aug") / name)
            # 逐种子一套编码器 ⇒ 映射也逐种子做（`seed0` 定树；三条种子各评各的树）。
            # 无 `graph_dir` 覆盖的臂（开关类）沿用正典那一棵，与 `run_ablation.build_args` 同一逻辑。
            gds = {}
            for s in SEEDS:
                ov = override or {}
                src = RA.expand(ov.get("graph_dir", canon_args["graph_dir"]), s, variants, frozen)
                gds[s] = dive_graph_dir_of(main_group, str(src), s)
            gd = gds[SEEDS[0]]
            absent = [s for s in SEEDS if not gds[s].exists()]
            if absent:
                print(f"  [{name}] DIVE 树缺 seed{absent}（{gds[absent[0]]}），跳过", flush=True)
                continue
            result["arms"][name] = run_arm(name, run_dir, gds, args.label_file,
                                           args.label_key_mode, args.batch_size, args.selfcheck)
    else:
        run_dir = Path(args.runs_dir).resolve()
        if args.graph_dir:
            gds = {s: Path(args.graph_dir) for s in SEEDS}
        else:
            cfg_args = json.loads((run_dir / "seed0" / "config.json").read_text(
                encoding="utf-8"))["args"]
            # 语料由**源 graph_dir 的父目录名**判定（products/<语料>/…），不靠调用方声明——
            # 声明错了会静默拿 ① 的 DIVE 特征树去喂 ② 的模型（两份编码器不同，结果无意义）
            corpus = Path(cfg_args["graph_dir"]).parent.parent.name
            if corpus not in ("alldata", "augmentation"):
                raise SystemExit(f"[ext] 无法从 {cfg_args['graph_dir']} 判定语料；"
                                 f"请显式传 --graph-dir")
            # 🔴 `config.json` 里记的是**已展开**的 `graph_dir`（如 `.../graphs_ft/ss0`），
            #   对它调 `RA.expand` 是**空操作**——于是三个种子全落回 `ss0` 那棵树，
            #   把 seed1/seed2 的模型配上了 ss0 编码器产出的特征（不报错、只是结果无意义）。
            #   故这里必须**先把结尾的 `ss<N>` 变回模板**再逐种子展开。
            tmpl = re.sub(r"ss\d+$", "ss{seed}", str(cfg_args["graph_dir"]))
            gds = {s: dive_graph_dir_of(corpus == "alldata", tmpl.format(seed=s), s)
                   for s in SEEDS}
            got = {gds[s].name for s in SEEDS}
            if corpus == "alldata" or corpus == "augmentation":
                want = {f"ss{s}" for s in SEEDS}
                if got != want:      # 冻结臂（`graphs/`）本就与种子无关，允许
                    if any(n.startswith("ss") for n in got):
                        raise SystemExit(f"[ext] 逐种子映射异常：得到 {sorted(got)}，期望 {sorted(want)}")
        result = {"dataset": "DIVE", "label_file": args.label_file,
                  "label_key_mode": args.label_key_mode,
                  "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                  "arms": {run_dir.name: run_arm(run_dir.name, run_dir, gds, args.label_file,
                                                 args.label_key_mode, args.batch_size,
                                                 args.selfcheck)}}

    result["environment"] = {"device": "cuda" if torch.cuda.is_available() else "cpu",
                             "torch_version": torch.__version__,
                             "python_version": platform.python_version()}
    result["wall_seconds"] = round(time.perf_counter() - t0, 1)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n[ext] {len(result['arms'])} 臂 → {out}（{result['wall_seconds']}s）", flush=True)


if __name__ == "__main__":
    main()
