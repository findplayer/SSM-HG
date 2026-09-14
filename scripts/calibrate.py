#!/usr/bin/env python3
"""M5 标定补充分析（温度缩放 + per-class 阈值；**仅补充，不进主结果**，decisions §13）。

定位：主实验（`evaluate.py`）的口径是「固定 0.5 + 验证集全局阈值双报告、主指标 micro-F1」。
本脚本回答「欠置信/标定是否是稀有类 F1=0 的可解原因」，全部结果写 `eval_results/calibration/`，
**不修改也不替代 `runs/` 主结果**，任何数字不得作为主指标结论。

分析项（每 seed；probs 复用 `runs/seed{N}/{val_best_probs,test_probs}.pt` 缓存，缺失才重推理）：
  1. 标定度量：逐类 ECE（10 分箱）与 Brier，macro 平均；温度缩放前后对比（val 与 test）；
  2. 温度缩放（**只在验证集拟合 T**）：`z=logit(p)` 复原 → `p_cal=sigmoid(z/T)`；
     在 val 上拟合 T（最小化 val BCE）→ 在 val 重搜全局阈值 → test 双报告；
  3. per-class 阈值（**只在验证集选**）：逐类在 val 上独立选 F1 最优阈值（候选同主协议 0.20–0.80
     步长 0.05，并列取小）→ 应用到 test，报逐类 P/R/F1、macro-F1（逐类 F1 平均）、micro-F1；
  4. 组合：温度缩放 + per-class 阈值；
  5. **过拟合审计**：per-class 阈值的 val 侧得分（被优化的那一侧）与 test 侧得分的落差，以及
     test 侧单类 oracle 上限与「regret = oracle − 实际」——val 正样本仅 1–3 个，逐类调阈极易过拟合。

不变量（须在解读时记住）：温度缩放与 per-class 阈值都是**逐类单调变换**，因此 **AP/ROC-AUC/mAP
完全不变**；能改善的只有「绝对概率落点」与「阈值命中」。故本分析只可能改善 F1，不可能改善 mAP。

用法：`python scripts/calibrate.py [--seed 0|1|2] [--runs-dir runs] [--out-dir eval_results/calibration]`
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
from scipy.optimize import minimize_scalar

import metrics
from dataset import DEFAULT_GRAPH_DIR, build_index, load_graph
from evaluate import _load_ablation, infer, rebuild_models

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
DEFAULT_SPLIT_DIR = f"{BASE}/products/alldata/splits"
DEFAULT_RUNS_DIR = f"{BASE}/runs"
DEFAULT_OUT_DIR = f"{BASE}/eval_results/calibration"
NAMES = metrics.VULN_NAMES
EPS = 1e-7                      # logit 复原的数值夹紧（probs 缓存为 float32 sigmoid 输出）
T_BOUNDS = (0.05, 20.0)         # 温度搜索区间


def _round(x, nd=6):
    return None if x is None else round(float(x), nd)


# --------------------------------------------------------------------- 纯函数
def to_logits(probs: np.ndarray) -> np.ndarray:
    """`p=sigmoid(z)` 可逆复原 `z=logit(p)`（等价于重跑推理拿 logits，避免二次前向）。"""
    p = np.clip(probs.astype(np.float64), EPS, 1.0 - EPS)
    return np.log(p / (1.0 - p))


def apply_temperature(logits: np.ndarray, t: float) -> np.ndarray:
    """`p_cal = sigmoid(z/T)`；T>1 软化（更保守）、T<1 锐化（更自信）。"""
    return 1.0 / (1.0 + np.exp(-logits / float(t)))


def bce_mean(logits: np.ndarray, y: np.ndarray) -> float:
    """平均逐元素 BCE（温度拟合目标；只在验证集调用）。"""
    z = np.clip(logits, -60.0, 60.0)
    return float(np.mean(np.logaddexp(0.0, z) - y * z))


def fit_temperature(val_logits: np.ndarray, val_labels: np.ndarray) -> dict:
    """在验证集上最小化平均 BCE 拟合单一温度 T（bounded Brent）。返回 {T, bce_before, bce_after}。"""
    flat_z, flat_y = val_logits.ravel(), val_labels.ravel().astype(np.float64)
    before = bce_mean(flat_z, flat_y)
    res = minimize_scalar(lambda t: bce_mean(flat_z / float(t), flat_y),
                          bounds=T_BOUNDS, method="bounded",
                          options={"xatol": 1e-4})
    return {"T": _round(res.x), "bce_before": _round(before),
            "bce_after": _round(float(res.fun))}


def ece_binary(y_c: np.ndarray, p_c: np.ndarray, n_bins: int = 10) -> float | None:
    """二分类 ECE（等宽分箱）：sum_b (n_b/N) * |acc_b - conf_b|。conf 取「预测类」的概率。"""
    if len(y_c) == 0:
        return None
    pred = (p_c >= 0.5).astype(int)
    conf = np.where(pred == 1, p_c, 1.0 - p_c)
    correct = (pred == y_c).astype(float)
    edges = np.linspace(0.0, 1.0, n_bins + 1)
    idx = np.clip(np.digitize(conf, edges[1:-1]), 0, n_bins - 1)
    ece, n = 0.0, float(len(y_c))
    for b in range(n_bins):
        m = idx == b
        if m.sum() == 0:
            continue
        ece += (m.sum() / n) * abs(correct[m].mean() - conf[m].mean())
    return float(ece)


def brier_binary(y_c: np.ndarray, p_c: np.ndarray) -> float | None:
    """Brier 分数（均方概率误差）：越低越好。"""
    if len(y_c) == 0:
        return None
    return float(np.mean((p_c - y_c) ** 2))


def calibration_metrics(probs: np.ndarray, labels: np.ndarray) -> dict:
    """逐类 ECE/Brier + macro 平均（support=0 的类跳过并记录）。"""
    ece, brier, skipped = {}, {}, []
    for c, name in enumerate(NAMES):
        if int(labels[:, c].sum()) == 0:
            skipped.append(name)
            continue
        ece[name] = _round(ece_binary(labels[:, c], probs[:, c]))
        brier[name] = _round(brier_binary(labels[:, c], probs[:, c]))
    return {
        "per_class_ece": ece, "per_class_brier": brier, "skipped": skipped,
        "macro_ece": _round(np.mean(list(ece.values()))) if ece else None,
        "macro_brier": _round(np.mean(list(brier.values()))) if brier else None,
    }


def per_class_thresholds(val_probs: np.ndarray, val_labels: np.ndarray,
                         candidates=metrics.THRESHOLD_CANDIDATES) -> dict:
    """**只在验证集**逐类独立选 F1 最优阈值（候选同主协议；并列取小）。返回阈值 + val 侧 F1。"""
    thrs, val_f1 = {}, {}
    for c, name in enumerate(NAMES):
        y_c, p_c = val_labels[:, c], val_probs[:, c]
        best_t, best_f = float(candidates[0]), -1.0
        for t in candidates:                    # 升序 → 并列自然保留较小阈值
            tp = int(((p_c >= t) & (y_c == 1)).sum())
            fp = int(((p_c >= t) & (y_c == 0)).sum())
            fn = int(((p_c < t) & (y_c == 1)).sum())
            f = (2 * tp / (2 * tp + fp + fn)) if (2 * tp + fp + fn) > 0 else 0.0
            if f > best_f:
                best_f, best_t = f, float(t)
        thrs[name], val_f1[name] = best_t, round(best_f, 6)
    return {"thresholds": thrs, "val_per_class_f1": val_f1,
            "val_macro_f1": _round(np.mean(list(val_f1.values())))}


def search_fine_threshold(val_probs: np.ndarray, val_labels: np.ndarray) -> dict:
    """**网格分辨率对照**：在 val 的全部唯一概率上搜全局阈值（连续分辨率，非 0.05 步长网格）。

    存在意义：`sigmoid(z/T)` 对 z 严格单调 ⇒ **全局阈值下温度缩放只是阈值的重参数化**，
    与「原始概率上换一个阈值」可达的预测集合完全相同。所以「温度缩放 + 全局阈值」相对主协议的
    任何收益，只可能来自主协议阈值网格（0.20–0.80 步长 0.05）的**分辨率损失**。本函数用连续分辨率
    的原始概率阈值做对照，二者若持平即证明该收益与标定无关。并列取较小阈值。
    """
    cands = np.unique(val_probs)
    best_t, best_f = float(cands[0]), -1.0
    for t in cands:                             # 升序 → 并列自然保留较小阈值
        f = metrics.micro_f1(val_labels, (val_probs >= t).astype(int))
        if f > best_f:
            best_f, best_t = f, float(t)
    return {"best_threshold": round(best_t, 6), "val_micro_f1": round(best_f, 6)}


def effective_raw_threshold(t_calibrated: float, t: float) -> float:
    """标定阈值 `t_calibrated` 在原始概率上的等效阈值：`sigmoid(T·logit(t))`。

    用于把「温度缩放 + 全局阈值」翻译回主协议语言，直接暴露它其实是哪个原始阈值。
    """
    t_c = min(max(float(t_calibrated), EPS), 1.0 - EPS)
    return round(float(1.0 / (1.0 + np.exp(-float(t) * np.log(t_c / (1.0 - t_c))))), 6)


def apply_per_class(probs: np.ndarray, thresholds: dict) -> np.ndarray:
    """按逐类阈值二值化 → preds[N,7]。"""
    out = np.zeros_like(probs, dtype=int)
    for c, name in enumerate(NAMES):
        out[:, c] = (probs[:, c] >= thresholds[name]).astype(int)
    return out


def oracle_f1_per_class(probs: np.ndarray, labels: np.ndarray) -> dict:
    """test 侧单类 oracle（遍历该类全部唯一概率取 best F1）= 该阈值方案的**天花板**。"""
    out = {}
    for c, name in enumerate(NAMES):
        y_c, p_c = labels[:, c], probs[:, c]
        if int(y_c.sum()) == 0:
            out[name] = None
            continue
        best = 0.0
        for t in np.unique(np.concatenate([p_c, [0.0, 1.0]])):
            pred = (p_c >= t).astype(int)
            tp = int(((pred == 1) & (y_c == 1)).sum())
            fp = int(((pred == 1) & (y_c == 0)).sum())
            fn = int(((pred == 0) & (y_c == 1)).sum())
            d = 2 * tp + fp + fn
            best = max(best, (2 * tp / d) if d > 0 else 0.0)
        out[name] = round(float(best), 6)
    return out


def evaluate_scheme(probs: np.ndarray, labels: np.ndarray, preds: np.ndarray) -> dict:
    """给定 preds 计算 micro/macro-F1 + 逐类 P/R/F1（support 随附）。"""
    prf = metrics.per_class_prf(labels, preds)
    return {
        "micro_f1": _round(metrics.micro_f1(labels, preds)),
        "macro_f1": _round(metrics.macro_f1(labels, preds)),
        "subset_accuracy": _round(metrics.subset_accuracy(labels, preds)),
        "per_class": prf,
    }


# --------------------------------------------------------------------- 单 seed
def calibrate_seed(seed: int, args: argparse.Namespace) -> dict:
    seed_dir = Path(args.runs_dir) / f"seed{seed}"
    checkpoint = torch.load(seed_dir / "best.pt", map_location="cpu")
    config = checkpoint["config"]
    split_seed = config.get("split_seed", seed)

    # ---- val / test probs（复用缓存，缺失才重推理）----
    vb = torch.load(seed_dir / "val_best_probs.pt", map_location="cpu")
    val_probs, val_labels = vb["probs"].numpy(), vb["labels"].numpy()
    tp_path = seed_dir / "test_probs.pt"
    if tp_path.exists():
        tb = torch.load(tp_path, map_location="cpu")
        test_probs, test_labels = tb["probs"].numpy(), tb["labels"].numpy()
    else:
        device = "cuda" if torch.cuda.is_available() else "cpu"
        fuser, model = rebuild_models(config, checkpoint)
        fuser.to(device)
        model.to(device)
        with open(f"{args.split_dir}/split_seed{split_seed}.json", encoding="utf-8") as fh:
            split = json.load(fh)
        index, _ = build_index(Path(args.graph_dir))
        ab = _load_ablation(config)
        verify = "all" if config["args"].get("verify_channel_hash") else "cheap"
        samples = [load_graph(b, graph_dir=args.graph_dir, ab=ab, index=index,
                              verify_channels=verify) for b in split["test"]]
        tp, tl = infer(samples, fuser, model, args.batch_size, device=device)
        test_probs, test_labels = tp.numpy(), tl.numpy()

    # ---- 1) 温度缩放（只在 val 拟合）----
    val_logits, test_logits = to_logits(val_probs), to_logits(test_probs)
    temp = fit_temperature(val_logits, val_labels)
    val_cal = apply_temperature(val_logits, temp["T"]).astype(np.float32)
    test_cal = apply_temperature(test_logits, temp["T"]).astype(np.float32)

    # ---- 2) 全局阈值（每套 probs 各自在 val 上重搜，口径同主协议）----
    g_thr_raw = metrics.search_global_threshold(val_probs, val_labels)
    g_thr_cal = metrics.search_global_threshold(val_cal, val_labels)
    # 网格分辨率对照：连续分辨率阈值（原始 & 标定）
    fine_raw = search_fine_threshold(val_probs, val_labels)
    fine_cal = search_fine_threshold(val_cal, val_labels)

    # ---- 3) per-class 阈值（只在 val 选；原始与标定后各一套）----
    pc_raw = per_class_thresholds(val_probs, val_labels)
    pc_cal = per_class_thresholds(val_cal, val_labels)

    schemes = {
        # 基线：与主实验同口径（校核用，应逐位复现 results.json）
        "baseline_fixed_0.5": evaluate_scheme(
            test_probs, test_labels, (test_probs >= 0.5).astype(int)),
        "baseline_val_threshold": evaluate_scheme(
            test_probs, test_labels, (test_probs >= g_thr_raw["best_threshold"]).astype(int)),
        # 方案 A：仅温度缩放 + 全局阈值（在 val 重搜）
        "temperature_global_threshold": evaluate_scheme(
            test_cal, test_labels, (test_cal >= g_thr_cal["best_threshold"]).astype(int)),
        # 方案 B：仅 per-class 阈值（原始 probs）
        "per_class_threshold": evaluate_scheme(
            test_probs, test_labels, apply_per_class(test_probs, pc_raw["thresholds"])),
        # 方案 C：温度缩放 + per-class 阈值
        "temperature_per_class_threshold": evaluate_scheme(
            test_cal, test_labels, apply_per_class(test_cal, pc_cal["thresholds"])),
        # 对照 D：连续分辨率全局阈值（原始概率；隔离「网格分辨率」效应）
        "fine_grid_raw_threshold": evaluate_scheme(
            test_probs, test_labels, (test_probs >= fine_raw["best_threshold"]).astype(int)),
        # 对照 E：连续分辨率全局阈值（标定后；与 D 对照即证明温度缩放在全局阈值下是否等价）
        "fine_grid_calibrated_threshold": evaluate_scheme(
            test_cal, test_labels, (test_cal >= fine_cal["best_threshold"]).astype(int)),
    }

    # ---- 4) 过拟合审计：val 侧（被优化）vs test 侧 ----
    val_schemes = {
        "per_class_threshold": evaluate_scheme(
            val_probs, val_labels, apply_per_class(val_probs, pc_raw["thresholds"])),
        "temperature_per_class_threshold": evaluate_scheme(
            val_cal, val_labels, apply_per_class(val_cal, pc_cal["thresholds"])),
    }
    oracle_raw = oracle_f1_per_class(test_probs, test_labels)
    oracle_cal = oracle_f1_per_class(test_cal, test_labels)
    audit = {
        "per_class_threshold": {
            "val_macro_f1": pc_raw["val_macro_f1"],
            "test_macro_f1": schemes["per_class_threshold"]["macro_f1"],
            "val_test_gap": _round(pc_raw["val_macro_f1"]
                                   - schemes["per_class_threshold"]["macro_f1"]),
            "test_oracle_macro_f1": _round(np.mean([v for v in oracle_raw.values()
                                                    if v is not None])),
            "regret_vs_test_oracle": _round(
                float(np.mean([v for v in oracle_raw.values() if v is not None]))
                - schemes["per_class_threshold"]["macro_f1"]),
        },
        "temperature_per_class_threshold": {
            "val_macro_f1": pc_cal["val_macro_f1"],
            "test_macro_f1": schemes["temperature_per_class_threshold"]["macro_f1"],
            "val_test_gap": _round(pc_cal["val_macro_f1"]
                                   - schemes["temperature_per_class_threshold"]["macro_f1"]),
            "test_oracle_macro_f1": _round(np.mean([v for v in oracle_cal.values()
                                                    if v is not None])),
        },
    }

    out = {
        "seed": seed, "split_seed": split_seed,
        "n_val": int(val_labels.shape[0]), "n_test": int(test_labels.shape[0]),
        "temperature": temp,
        "global_threshold": {"raw": g_thr_raw["best_threshold"],
                             "calibrated": g_thr_cal["best_threshold"],
                             "raw_val_micro_f1": _round(g_thr_raw["best_micro_f1"]),
                             "calibrated_val_micro_f1": _round(g_thr_cal["best_micro_f1"]),
                             "calibrated_effective_raw": effective_raw_threshold(
                                 g_thr_cal["best_threshold"], temp["T"])},
        "grid_resolution_control": {
            "raw": fine_raw, "calibrated": fine_cal,
            "note": "连续分辨率原始阈值（对照组 D）若与温度方案持平 → 温度缩放的微 F1 收益来自主协议"
                    "阈值网格分辨率而非标定本身。"},
        "per_class_thresholds": {"raw": pc_raw, "calibrated": pc_cal},
        "calibration": {
            "val_raw": calibration_metrics(val_probs, val_labels),
            "val_calibrated": calibration_metrics(val_cal, val_labels),
            "test_raw": calibration_metrics(test_probs, test_labels),
            "test_calibrated": calibration_metrics(test_cal, test_labels),
        },
        "test_schemes": schemes,
        "val_schemes": val_schemes,
        "overfit_audit": audit,
        "invariance_note": "温度缩放与 per-class 阈值均为逐类单调变换 → AP/ROC-AUC/mAP 不变。",
        "caveat": "per-class 阈值在 val 上仅 1–3 个正样本上调优，过拟合风险高；仅补充分析，不进主结果（decisions §13）。",
    }
    out["_probs_cache"] = {"val_cal": val_cal, "test_cal": test_cal}
    return out


def aggregate(per_seed: dict[int, dict]) -> dict:
    """跨 seed 聚合（mean±std，ddof=1）；仅对 test 侧各方案的关键指标 + 标定度量。"""
    seeds = sorted(per_seed)
    keys = ["baseline_fixed_0.5", "baseline_val_threshold", "temperature_global_threshold",
            "per_class_threshold", "temperature_per_class_threshold",
            "fine_grid_raw_threshold", "fine_grid_calibrated_threshold"]

    def ms(vals):
        arr = np.asarray([v for v in vals if v is not None], dtype=float)
        if arr.size == 0:
            return {"mean": None, "std": None, "n": 0}
        return {"mean": round(float(arr.mean()), 6),
                "std": round(float(arr.std(ddof=1)), 6) if arr.size > 1 else 0.0,
                "n": int(arr.size)}

    schemes = {}
    for k in keys:
        schemes[k] = {
            "micro_f1": ms([per_seed[s]["test_schemes"][k]["micro_f1"] for s in seeds]),
            "macro_f1": ms([per_seed[s]["test_schemes"][k]["macro_f1"] for s in seeds]),
            "subset_accuracy": ms([per_seed[s]["test_schemes"][k]["subset_accuracy"]
                                   for s in seeds]),
            "per_class_f1": {n: ms([dict(zip(per_seed[s]["test_schemes"][k]["per_class"]["names"],
                                             per_seed[s]["test_schemes"][k]["per_class"]["f1"]))[n]
                                    for s in seeds]) for n in NAMES},
        }
    calibration = {}
    for side in ["val", "test"]:
        for kind in ["raw", "calibrated"]:
            tag = f"{side}_{kind}"
            calibration[tag] = {
                "macro_ece": ms([per_seed[s]["calibration"][tag]["macro_ece"] for s in seeds]),
                "macro_brier": ms([per_seed[s]["calibration"][tag]["macro_brier"] for s in seeds]),
            }
    return {
        "seeds": seeds, "classes": NAMES, "std_ddof": 1,
        "temperature": {s: per_seed[s]["temperature"] for s in seeds},
        "global_threshold": {s: per_seed[s]["global_threshold"] for s in seeds},
        "per_class_thresholds_raw": {s: per_seed[s]["per_class_thresholds"]["raw"]["thresholds"]
                                     for s in seeds},
        "test_schemes": schemes,
        "calibration": calibration,
        "overfit_audit": {s: per_seed[s]["overfit_audit"] for s in seeds},
        "note": "标定/per-class 阈值仅为补充分析，不进主结果；AP/ROC-AUC/mAP 对逐类单调变换不变。",
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="M5 calibration: temperature scaling + per-class thresholds.")
    p.add_argument("--seed", type=int, default=None, help="单 seed；省略 = 全部 runs/seed*。")
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR)
    p.add_argument("--split-dir", default=DEFAULT_SPLIT_DIR)
    p.add_argument("--runs-dir", default=DEFAULT_RUNS_DIR)
    p.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    return p.parse_args()


def main() -> None:
    args = parse_args()
    runs_dir = Path(args.runs_dir)
    seeds = [args.seed] if args.seed is not None else \
        sorted(int(p.name.replace("seed", "")) for p in runs_dir.glob("seed*")
               if (p / "best.pt").exists())
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    per_seed = {}
    for s in seeds:
        r = calibrate_seed(s, args)
        per_seed[s] = r
        t = r["temperature"]
        b = r["test_schemes"]["baseline_fixed_0.5"]
        print(f"seed{s}: T={t['T']:.4f} (val BCE {t['bce_before']:.4f}→{t['bce_after']:.4f}) | "
              f"test micro-F1 基线 {b['micro_f1']:.4f} / "
              f"温度 {r['test_schemes']['temperature_global_threshold']['micro_f1']:.4f} / "
              f"per-class {r['test_schemes']['per_class_threshold']['micro_f1']:.4f} / "
              f"组合 {r['test_schemes']['temperature_per_class_threshold']['micro_f1']:.4f}")
        payload = {k: v for k, v in r.items() if k != "_probs_cache"}
        (out_dir / f"seed{s}.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    summary = aggregate(per_seed)
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"跨种子聚合 → {out_dir / 'summary.json'}")


if __name__ == "__main__":
    main()
