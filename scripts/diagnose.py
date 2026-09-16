#!/usr/bin/env python3
"""M5 诊断脚本（阶段 E 补充分析，只读产物 + 写诊断 JSON；不参与训练/阈值选择/主结果口径）。

目的：为主实验「macro-F1 / mAP 偏低、逐类大量 F1=0」提供**可量化的根因证据与改进线索**。

只读：`runs/seed{N}/best.pt`、`config.json`、`val_best_probs.pt`、`products/alldata/splits`、
      `products/alldata/graphs`。
写入：`runs/seed{N}/test_probs.pt`（test 推理缓存，供后续免重复推理）、
      `runs/seed{N}/diagnosis.json`（逐 seed 诊断）、`runs/diagnosis_summary.json`（跨 seed 聚合）。

诊断维度（每类 × 每 seed，标签序与 `metrics.VULN_NAMES` 一致）：
  1. 数据稀缺：train/val/test 正样本数、池级正样本数、pos_weight（截断前后）；
  2. 混淆计数：TP/FP/FN/TN（固定 0.5 与验证集阈值）；
  3. 排序能力：PR-AUC(AP) + ROC-AUC（正负两类都存在时才定义）；
  4. 标定/置信：正/负样本预测概率的 mean/median/max/min、≥0.5 比例、≥0.2 比例；
  5. 单类天花板：遍历阈值的 best per-class F1（oracle 上限）与对应阈值；
  6. 正样本逐条预测概率（support 小，可直接读「模型到底给正样本打了几分」）；
  7. 标签共现：训练集条件概率 P(y_j=1 | y_i=1)（多标签结构，供解耦参考）。

用法：`python scripts/diagnose.py [--seed 0|1|2] [--batch-size 32]`（省略 --seed = 全种子）。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
from sklearn.metrics import (average_precision_score, f1_score,
                             roc_auc_score)

import metrics
from dataset import (DEFAULT_GRAPH_DIR, Ablation, build_index, load_graph)
from evaluate import _load_ablation, infer, rebuild_models

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
DEFAULT_SPLIT_DIR = f"{BASE}/products/alldata/splits"
DEFAULT_RUNS_DIR = f"{BASE}/runs"
NAMES = metrics.VULN_NAMES          # 7 类固定序


def _round(x, nd=6):
    return None if x is None else round(float(x), nd)


def confusion_counts(y_c: np.ndarray, p_c: np.ndarray, thr: float) -> dict:
    pred = (p_c >= thr).astype(int)
    tp = int(((pred == 1) & (y_c == 1)).sum())
    fp = int(((pred == 1) & (y_c == 0)).sum())
    fn = int(((pred == 0) & (y_c == 1)).sum())
    tn = int(((pred == 0) & (y_c == 0)).sum())
    return {"threshold": thr, "TP": tp, "FP": fp, "FN": fn, "TN": tn}


def prob_stats(y_c: np.ndarray, p_c: np.ndarray) -> dict:
    """正/负样本预测概率分布与阈值命中率（标定/置信证据）。"""
    pos, neg = p_c[y_c == 1], p_c[y_c == 0]
    out = {
        "pos_n": int(len(pos)), "neg_n": int(len(neg)),
        "pos_mean": _round(pos.mean()) if len(pos) else None,
        "pos_median": _round(np.median(pos)) if len(pos) else None,
        "pos_min": _round(pos.min()) if len(pos) else None,
        "pos_max": _round(pos.max()) if len(pos) else None,
        "neg_mean": _round(neg.mean()) if len(neg) else None,
        "neg_median": _round(np.median(neg)) if len(neg) else None,
        "neg_max": _round(neg.max()) if len(neg) else None,
        "frac_pos_ge_0.5": _round((pos >= 0.5).mean()) if len(pos) else None,
        "frac_pos_ge_0.2": _round((pos >= 0.2).mean()) if len(pos) else None,
        "frac_neg_ge_0.5": _round((neg >= 0.5).mean()) if len(neg) else None,
        "frac_neg_ge_0.2": _round((neg >= 0.2).mean()) if len(neg) else None,
        "pos_probs_sorted": [round(float(v), 4) for v in sorted(pos, reverse=True)],
    }
    return out


def oracle_best_f1(y_c: np.ndarray, p_c: np.ndarray) -> dict:
    """单类天花板：遍历该类的排序唯一概率（+0/1）取 best F1 与对应阈值（独立于全局阈值）。"""
    cands = np.unique(np.concatenate([p_c, np.array([0.0, 1.0])]))
    best_t, best_f = 0.5, -1.0
    for t in cands:
        f = float(f1_score(y_c, (p_c >= t).astype(int), zero_division=0))
        if f > best_f:
            best_f, best_t = f, float(t)
    return {"best_f1": round(best_f, 6), "best_threshold": round(best_t, 6)}


def label_cooccurrence(labels: np.ndarray) -> list[list[float]]:
    """训练集标签共现条件概率 P(y_j=1 | y_i=1)，[7,7]，对角线 = 1。labels[N,7]。"""
    n = labels.shape[1]
    mat = np.zeros((n, n), dtype=float)
    for i in range(n):
        denom = int(labels[:, i].sum())
        if denom == 0:
            mat[i, :] = float("nan")
            continue
        mat[i, :] = labels[labels[:, i] == 1].mean(axis=0)
    return [[round(float(v), 4) if not np.isnan(v) else None for v in row]
            for row in mat]


def per_class_diagnosis(probs: np.ndarray, labels: np.ndarray, val_thr: float,
                        train_pos, train_neg, pos_weight_used, val_pos) -> list[dict]:
    """逐类诊断（test probs/labels + 训练/验证支撑 + 全局阈值）。"""
    rows = []
    for c in range(len(NAMES)):
        y_c, p_c = labels[:, c], probs[:, c]
        ap = float(average_precision_score(y_c, p_c)) if y_c.sum() > 0 else None
        roc = (float(roc_auc_score(y_c, p_c)) if (y_c.sum() > 0 and (1 - y_c).sum() > 0)
               else None)
        true_ratio = (train_neg[c] / train_pos[c]) if train_pos[c] > 0 else None
        rows.append({
            "class": NAMES[c],
            "support": {"train_pos": int(train_pos[c]), "train_neg": int(train_neg[c]),
                        "val_pos": int(val_pos[c]), "test_pos": int(y_c.sum()),
                        "pool_pos": int(train_pos[c] + val_pos[c] + y_c.sum())},
            "pos_weight_used": _round(pos_weight_used[c]),
            "true_neg_pos_ratio": _round(true_ratio),
            "confusion_0.5": confusion_counts(y_c, p_c, 0.5),
            "confusion_val_thr": confusion_counts(y_c, p_c, val_thr),
            "AP": _round(ap),
            "ROC_AUC": _round(roc),
            "oracle": oracle_best_f1(y_c, p_c),
            "prob_stats": prob_stats(y_c, p_c),
        })
    return rows


def diagnose_seed(seed: int, args: argparse.Namespace) -> dict:
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

    # ---- 验证集 probs（复用 best epoch 的 val_best_probs.pt）+ val 支撑 ----
    vb = torch.load(seed_dir / "val_best_probs.pt", map_location="cpu")
    val_probs, val_labels = vb["probs"].numpy(), vb["labels"].numpy()
    val_pos = val_labels.sum(0).astype(int)

    # ---- 测试集推理（缓存 test_probs.pt 免重复）----
    # 缓存必须按**内容**校验：只判“文件存在”会在划分变更后静默沿用旧划分的推理结果，
    # 逐类 support 与诊断结论随之错位（2026-09-14 实际发生过）。与 evaluate.py 同一校验方式。
    tp_path = seed_dir / "test_probs.pt"
    test_bases = split["test"]
    tb = torch.load(tp_path, map_location="cpu") if tp_path.exists() else None
    if tb is not None and list(tb.get("sample_ids", [])) != test_bases:
        print(f"[warn] {tp_path.name} 的 sample_ids 与当前划分不符"
              f"（缓存 {len(tb.get('sample_ids', []))} 行 vs 划分 {len(test_bases)} 行）"
              "→ 忽略缓存、重新推理")
        tb = None
    if tb is not None:
        test_probs, test_labels = tb["probs"].numpy(), tb["labels"].numpy()
    else:
        test_samples = [load_graph(b, graph_dir=args.graph_dir, ab=ab, index=index,
                                   verify_channels=verify) for b in test_bases]
        tp, tl = infer(test_samples, fuser, model, args.batch_size, device=device)
        test_probs, test_labels = tp.numpy(), tl.numpy()
        torch.save({"probs": torch.from_numpy(test_probs),
                    "labels": torch.from_numpy(test_labels),
                    "sample_ids": test_bases}, tp_path)

    val_thr = float(json.loads((seed_dir / "results.json").read_text(encoding="utf-8"))
                    ["val_threshold"])
    d = config["derived"]
    rows = per_class_diagnosis(
        test_probs, test_labels, val_thr,
        np.asarray(d["train_pos"], dtype=int), np.asarray(d["train_neg"], dtype=int),
        np.asarray(d["pos_weight"], dtype=float), val_pos)

    # ---- 训练集标签共现（从 index + split["train"] 直接算，不加载图）----
    train_labels = np.asarray([index[b] for b in split["train"]], dtype=int)
    out = {
        "seed": seed, "split_seed": split_seed, "val_threshold": val_thr,
        "n_train": len(split["train"]), "n_val": len(split["val"]),
        "n_test": len(split["test"]),
        "per_class": rows,
        "label_cooccurrence_train": label_cooccurrence(train_labels),
    }
    (seed_dir / "diagnosis.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


def aggregate(per_seed: dict[int, dict]) -> dict:
    seeds = sorted(per_seed)
    agg = {"seeds": seeds, "classes": NAMES,
           "support_train_pos": {}, "support_val_pos": {}, "support_test_pos": {},
           "AP": {}, "ROC_AUC": {}, "oracle_f1": {}}
    for c, name in enumerate(NAMES):
        for key in ("support_train_pos", "support_val_pos", "support_test_pos",
                    "AP", "ROC_AUC", "oracle_f1"):
            vals = []
            for s in seeds:
                row = per_seed[s]["per_class"][c]
                if key == "support_train_pos":
                    vals.append(row["support"]["train_pos"])
                elif key == "support_val_pos":
                    vals.append(row["support"]["val_pos"])
                elif key == "support_test_pos":
                    vals.append(row["support"]["test_pos"])
                elif key == "AP":
                    vals.append(row["AP"])
                elif key == "ROC_AUC":
                    vals.append(row["ROC_AUC"])
                else:
                    vals.append(row["oracle"]["best_f1"])
            vals = [v for v in vals if v is not None]
            if vals:
                arr = np.asarray(vals, dtype=float)
                agg[key][name] = {"mean": round(float(arr.mean()), 4),
                                  "std": round(float(arr.std(ddof=1)), 4)
                                  if arr.size > 1 else 0.0, "n": int(arr.size)}
            else:
                agg[key][name] = None
    return agg


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="M5 diagnosis: per-class deep diagnostics.")
    p.add_argument("--seed", type=int, default=None, help="单 seed；省略 = 全种子。")
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR)
    p.add_argument("--split-dir", default=DEFAULT_SPLIT_DIR)
    p.add_argument("--runs-dir", default=DEFAULT_RUNS_DIR)
    return p.parse_args()


def main() -> None:
    args = parse_args()
    runs_dir = Path(args.runs_dir)
    seeds = [args.seed] if args.seed is not None else \
        sorted(int(p.name.replace("seed", "")) for p in runs_dir.glob("seed*")
               if (p / "best.pt").exists())
    per_seed = {}
    for s in seeds:
        per_seed[s] = diagnose_seed(s, args)
        r = per_seed[s]
        print(f"seed{s}: 逐类诊断完成 → runs/seed{s}/diagnosis.json "
              f"（test pos " +
              ",".join(str(r['per_class'][c]['support']['test_pos']) for c in range(7)) + "）")
    summary = aggregate(per_seed)
    (runs_dir / "diagnosis_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"跨种子聚合 → {runs_dir / 'diagnosis_summary.json'}")


if __name__ == "__main__":
    main()
