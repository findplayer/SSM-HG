#!/usr/bin/env python3
"""误报率 / 漏报率的回归测试（`scripts/error_rates.py`，2026-09-17）。

锁住四件事：
  1. **手算可核的小例**——逐类与 micro 两个口径都对着算一遍，防止混淆计数写反
     （`FP`/`FN` 是这类统计里最容易互换的一对）；
  2. **退化解必须自曝**——「全判负」要给 FNR=1.0（漏掉一切）而**不是**好看的 0，
     这正是 `metrics.micro_f1` 的 `.ravel()` 缺陷（`decisions.md` §28）当年掩盖掉的形态：
     坏实现让「什么都没预测」拿到 0.93 的高分。**误报/漏报统计不得重犯**；
  3. **分母为 0 记 None，不记 0**——0 会被读成「没有误报」，是静默的错误结论；
  4. **恒等式**：`micro FNR = 1 − micro recall`，且 **L3 合约级 FPR/FNR 恒等于**
     把 7 类塌成 `any(...)` 后的二分类 FPR/FNR（结论卷 §9 的核心读法依赖此式）。

运行：`pytest tests/test_error_rates.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import error_rates as er  # noqa: E402


# 3 个样本 × 3 类的小例，逐格可手算。
#   y = [[1,0,1],      p = [[1,0,0],      → 类0: TP=1 FP=1 FN=0 TN=1  （样本2 误报）
#        [0,1,0],           [0,0,0],        类1: TP=0 FP=0 FN=1 TN=2  （样本1 全漏）
#        [0,0,0]]           [1,0,0]]        类2: TP=0 FP=0 FN=1 TN=2  （样本0 漏）
Y = np.array([[1, 0, 1],
              [0, 1, 0],
              [0, 0, 0]])
P = np.array([[1, 0, 0],
              [0, 0, 0],
              [1, 0, 0]])
NAMES3 = ["c0", "c1", "c2"]


def test_confusion_counts_are_not_swapped():
    c = er.confusion_per_class(Y, P)
    assert c["TP"] == [1, 0, 0]
    assert c["FP"] == [1, 0, 0]      # 只可能是被「多报」的那格（类0 样本2）
    assert c["FN"] == [0, 1, 1]      # 只可能是被「漏报」的那格（类1 样本1、类2 样本0）
    assert c["TN"] == [1, 2, 2]
    assert c["support"] == [1, 1, 1]
    assert c["negatives"] == [2, 2, 2]


def test_per_class_rates_hand_checked():
    r = er.per_class_error_rates(Y, P, NAMES3)
    assert r["FPR"] == [0.5, 0.0, 0.0]    # 类0: 1/(1+1)
    assert r["FNR"] == [0.0, 1.0, 1.0]    # 类1、类2 各漏掉唯一正样本


def test_micro_rates_hand_checked():
    m = er.micro_error_rates(Y, P)
    # 全局: TP=1 FP=1 FN=2 TN=5
    assert m["sum_TP"] == 1 and m["sum_FP"] == 1 and m["sum_FN"] == 2 and m["sum_TN"] == 5
    assert m["FPR"] == pytest.approx(1 / 6)
    assert m["FNR"] == pytest.approx(2 / 3)
    assert m["recall"] == pytest.approx(1 / 3)
    assert m["precision"] == pytest.approx(1 / 2)


def test_all_negative_predictions_expose_everything():
    """退化解：全判负 → 误报率 0、漏报率 1、合约级漏检率 1。**不得给出好看的数字。**"""
    allneg = np.zeros_like(Y)
    m = er.micro_error_rates(Y, allneg)
    assert m["FPR"] == 0.0
    assert m["FNR"] == 1.0
    assert m["recall"] == 0.0
    l3 = er.contract_level_rates(Y, allneg)
    assert l3["miss_rate"] == 1.0          # 2 个有漏洞合约全漏
    assert l3["false_alarm_rate"] == 0.0
    assert l3["binary_f1"] == 0.0          # ← 坏实现会在这里给 0.5（accuracy）


def test_all_positive_predictions_is_the_mirror_image():
    """反向退化解：全判正 → 漏报率 0、误报率拉满。"""
    allpos = np.ones_like(Y)
    m = er.micro_error_rates(Y, allpos)    # 全局: TP=3 FP=6 FN=0 TN=0
    assert m["FPR"] == 1.0
    assert m["FNR"] == 0.0
    l3 = er.contract_level_rates(Y, allpos)
    assert l3["miss_rate"] == 0.0
    assert l3["false_alarm_rate"] == 1.0   # 唯一干净合约被误报


def test_zero_denominator_is_none_not_zero():
    """分母为 0（该类无正样本 / 无负样本）必须记 None —— 记 0 会被读成「没有误报」。"""
    y = np.array([[1, 0], [1, 0]])         # 类0 无负样本、类1 无正样本
    p = np.zeros_like(y)
    r = er.per_class_error_rates(y, p, ["c0", "c1"])
    assert r["FPR"][0] is None             # 类0 无负样本 → 无定义（**不得记 0**）
    assert r["FNR"][0] == 1.0
    assert r["FNR"][1] is None             # 类1 support=0 → 无定义
    assert r["FPR"][1] == 0.0              # 类1 有负样本且零误报 → 真的是 0
    assert er._div(0, 0) is None
    assert er._div(0, 5) == 0.0


def test_l3_equals_collapsed_binary_view():
    """L3 合约级 FPR/FNR **恒等于**「有没有漏洞」二分类的 FPR/FNR（结论卷 §9 的读法依据）。"""
    l3 = er.contract_level_rates(Y, P)
    yb, pb = Y.any(axis=1).astype(int), P.any(axis=1).astype(int)
    tp = int(((yb == 1) & (pb == 1)).sum()); fp = int(((yb == 0) & (pb == 1)).sum())
    fn = int(((yb == 1) & (pb == 0)).sum()); tn = int(((yb == 0) & (pb == 0)).sum())
    assert l3["false_alarm_rate"] == pytest.approx(fp / (fp + tn))
    assert l3["miss_rate"] == pytest.approx(fn / (fn + tp))
    assert l3["binary_precision"] == pytest.approx(tp / (tp + fp))
    assert l3["binary_recall"] == pytest.approx(tp / (tp + fn))
    assert l3["binary_accuracy"] == pytest.approx((tp + tn) / (tp + tn + fp + fn))


def test_micro_fnr_is_complement_of_recall():
    """micro FNR = 1 − micro recall（与 `metrics.micro_f1` 同源，口径必须自洽）。"""
    rng = np.random.default_rng(0)
    y = (rng.random((64, 7)) < 0.15).astype(int)
    p = (rng.random((64, 7)) < 0.20).astype(int)
    m = er.micro_error_rates(y, p)
    assert m["FNR"] == pytest.approx(1.0 - m["recall"])
    assert m["FPR"] == pytest.approx(1.0 - er._div(
        m["sum_TN"], m["sum_TN"] + m["sum_FP"]))


def test_consistent_with_metrics_micro_f1_and_per_class_prf():
    """两套实现不得各说各话：micro 分量要拼回 `metrics.micro_f1`，逐类要等于 `per_class_prf`。"""
    metrics = pytest.importorskip("metrics")
    rng = np.random.default_rng(1)
    y = (rng.random((40, 7)) < 0.2).astype(int)
    p = (rng.random((40, 7)) < 0.25).astype(int)

    m = er.micro_error_rates(y, p)
    assert metrics.micro_f1(y, p) == pytest.approx(
        2 * m["precision"] * m["recall"] / (m["precision"] + m["recall"]))

    r = er.per_class_error_rates(y, p, metrics.VULN_NAMES)
    ref = metrics.per_class_prf(y, p)
    for ci in range(len(metrics.VULN_NAMES)):
        if ref["support"][ci] > 0:
            assert r["FNR"][ci] == pytest.approx(1.0 - ref["recall"][ci])
        # 精确率无代数关系可套（FPR 的分母是负样本、precision 的分母是预测正），
        # 故直接由混淆计数复算 precision，确认两套实现的 TP/FP 一致
        tp, fp = r["TP"][ci], r["FP"][ci]
        if tp + fp > 0:
            assert tp / (tp + fp) == pytest.approx(ref["precision"][ci])
