#!/usr/bin/env python3
"""M5 指标层（手册 10.5 / 12.4；大纲改II 5.2）：图级七类多标签指标与阈值扫描的**纯函数**。

契约（与 train/evaluate/ablation 三处共用；**不得 import dataset/model**，可独立单测）：
  - 主指标 **micro-F1（标签对级）**：把全部 `(样本, 类)` 标签对汇总后统计全局 TP/FP/FN 再算 F1，
    即 sklearn `f1_score(average="micro")`；不逐类平均、不额外做标签组合。macro-F1 为参考指标，
    报告时须注明支撑构成。
    ⚠ 「汇总标签对」是**统计口径**，**不是**把数组 `.ravel()` 后送 sklearn ——展平会把
    `type_of_target` 从 `multilabel-indicator` 改判成 `binary`，`average="micro"` 随即退化为
    逐样本准确率（数学恒等）。输入须保持 `[N,7]` 二维，见 `_as_2d` 与其回归测试。
  - 逐类 P/R/F1 与 per-class PR-AUC **必须随 support 同时给出**；support=0 的类保留（F1=0、support=0，
    不除零）；support≤2 的类仅描述性呈现、不进比较结论（由 evaluate 侧标注，本层只返回原始值）。
  - mAP 口径 = **macro AP**（仅对 support>0 的类求平均），返回 `ap_classes_used` 供报告；跳过类记入
    `skipped`（不静默吞掉）。
  - `search_global_threshold` 只在验证集调用：候选 0.20~0.80 步长 0.05，目标 **val micro-F1**
    （2026-09-12 由 macro-F1 改），并列取**较小阈值**（`>=` 下较小阈值更偏向召回）；val macro-F1 同步
    记录作参考。只计算不落盘（落盘由 train/evaluate 侧写 `thresholds.json`）。

阈值口径（大纲 5.2 / 手册 10.5）：固定 0.5 与验证集搜索阈值**双报告**；测试集不参与阈值选择；
稀有类不在验证集单独调阈（per-class 阈值仅补充分析，不进主结果）。

CLI：无（纯函数库，无 main）。
"""

from __future__ import annotations

import numpy as np
import torch
from sklearn.metrics import (average_precision_score, f1_score,
                             precision_recall_fscore_support)

# 标签顺序固定（锁死；与 dataset.VULN_NAMES / model num_classes=7 一致，不得重排）
VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]

# 全局阈值扫描候选（大纲 5.2：0.2 ~ 0.8，步长 0.05；只用验证集）
THRESHOLD_CANDIDATES = tuple(round(0.20 + 0.05 * i, 2) for i in range(13))  # 0.20..0.80


def _as_numpy(t) -> np.ndarray:
    """torch.Tensor → numpy（detach + cpu）；numpy 原样转回 np.asarray。"""
    if isinstance(t, torch.Tensor):
        return t.detach().cpu().numpy()
    return np.asarray(t)


def _as_2d(t) -> np.ndarray:
    """保证 [N, C] 二维（一维输入视为单列 N×1）。

    ⚠ **严禁 ravel 后再送 sklearn**：`[N,7]` 展平成 1-D `{0,1}` 会把 sklearn 的
    `type_of_target` 从 `multilabel-indicator` 改判成 `binary`，而 `average="micro"`
    在 binary 下**恒等于逐样本 accuracy**（数学恒等），使标签对级 F1 退化成准确率。
    2026-09-17 修复，见 `experiments/decisions.md` §28。
    """
    a = _as_numpy(t)
    if a.ndim == 1:
        a = a.reshape(-1, 1)
    return a


def binary_preds(probs: torch.Tensor, thr: float) -> torch.Tensor:
    """概率 [N,7] → 0/1 预测 [N,7]（`>= thr` 为 1）。"""
    return (probs >= thr).to(torch.int64)


def micro_f1(y, p) -> float:
    """主指标：标签对级 micro-F1（sklearn `average="micro"`，zero_division=0）。

    语义 = 把全部 `(样本, 类)` 标签对展平后统计全局 TP/FP/FN 再算 F1；**不是**逐样本
    准确率，也**不是**精确匹配率（后者见 `subset_accuracy`）。二者按定义可相差数十个点
    （稀有类多时 micro-F1 远低于准确率），不得混用。
    """
    return float(f1_score(_as_2d(y), _as_2d(p), average="micro", zero_division=0))


def macro_f1(y, p) -> float:
    """参考指标：macro-F1（zero_division=0；报告时须注明支撑构成）。"""
    return float(f1_score(_as_numpy(y), _as_numpy(p), average="macro", zero_division=0))


def per_class_prf(y, p, names=VULN_NAMES) -> dict:
    """逐类 precision / recall / F1 / support（含 support=0 类：F1=0、support=0，不除零）。

    返回 {names, precision, recall, f1, support}，各为长度 7 的列表（顺序与 names 一致）。
    """
    y_np, p_np = _as_numpy(y), _as_numpy(p)
    pr, rc, f1, sup = precision_recall_fscore_support(y_np, p_np, zero_division=0)
    return {
        "names": list(names),
        "precision": [float(v) for v in pr],
        "recall": [float(v) for v in rc],
        "f1": [float(v) for v in f1],
        "support": [int(v) for v in sup],
    }


def mean_average_precision(probs, y, names=VULN_NAMES) -> dict:
    """per-class PR-AUC 与 mAP（macro AP，仅对 support>0 的类求平均）。

    返回 {"mAP": float, "ap": [7]（跳过类为 None）, "ap_classes_used": int, "skipped": [names]}。
    support=0 的类跳过该类 AP 并记入 skipped（不除零、不静默）。
    """
    y_np, p_np = _as_numpy(y), _as_numpy(probs)
    ap: list = [None] * len(names)
    skipped: list[str] = []
    used = 0
    for c in range(len(names)):
        yc = y_np[:, c]
        if int(yc.sum()) == 0:
            skipped.append(names[c])
            continue
        ap[c] = float(average_precision_score(yc, p_np[:, c]))
        used += 1
    used_values = [v for v in ap if v is not None]
    mAP = float(np.mean(used_values)) if used_values else 0.0
    return {"mAP": mAP, "ap": ap, "ap_classes_used": used, "skipped": skipped}


def subset_accuracy(y, p) -> float:
    """可选：精确匹配率（整条 7 维标签全等 / 样本数）。"""
    y_np, p_np = _as_numpy(y), _as_numpy(p)
    n = y_np.shape[0]
    if n == 0:
        return 0.0
    return float((y_np == p_np).all(axis=1).sum()) / n


def search_global_threshold(probs_val, y_val,
                            candidates=THRESHOLD_CANDIDATES,
                            metric: str = "micro_f1") -> dict:
    """全局阈值扫描（**只在验证集**）：候选 0.20~0.80 步长 0.05，目标 val micro-F1。

    `metric` 决定按 micro_f1（默认，主）还是 macro_f1 选；无论选哪个，micro/macro 两套都记录。
    并列（指标值精确相等）时取**较小阈值**（`>=` 下更偏向召回）。
    返回全部候选指标与 tie 依据，供 evaluate/train 侧落盘 `thresholds.json`。
    """
    y_np, p_np = _as_2d(y_val), _as_2d(probs_val)
    best_threshold = None
    best_value = -float("inf")
    best_micro = best_macro = None
    scanned: list[dict] = []
    for thr in candidates:                      # 升序遍历 → 并列自然保留较小阈值
        preds = (p_np >= thr).astype(int)
        mif = float(f1_score(y_np, preds, average="micro", zero_division=0))
        maf = float(f1_score(y_np, preds, average="macro", zero_division=0))
        scanned.append({"threshold": thr, "micro_f1": mif, "macro_f1": maf})
        value = mif if metric == "micro_f1" else maf
        if value > best_value:                  # 严格大于才更新 → tie 取更小阈值
            best_value = value
            best_threshold = thr
            best_micro, best_macro = mif, maf
    return {
        "metric": metric,
        "best_threshold": best_threshold,
        f"best_{metric}": best_value,
        "best_micro_f1": best_micro,
        "best_macro_f1": best_macro,
        "candidates": scanned,
        "tie_break": "并列取较小阈值（`>=` 下更偏向召回）",
    }
