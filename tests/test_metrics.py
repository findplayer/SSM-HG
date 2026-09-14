"""M5 指标层单测（手册 12.4；纯函数、零数据依赖）。

覆盖（关卡 = 合成边界无 NaN、与 sklearn 对照逐位相等、zero-positive 跳过、tie 取小）：
  1. micro/macro-F1 对合成边界（全 0 预测、全 1 预测、含空标签类）无 NaN、zero_division=0，
     且与 sklearn 对照逐位相等；
  2. per_class_prf 在含 support=0 类时返回该 support=0 且 F1=0，不除零；
  3. mean_average_precision 跳过 zero-positive 类、ap_classes_used 计数正确、单类数据 AP=1.0；
  4. search_global_threshold 在单调场景选到正确阈值；并列时取较小阈值；候选列表完整。

运行：pytest tests/test_metrics.py -q
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest
import torch
from sklearn.metrics import average_precision_score, f1_score

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics  # noqa: E402
from metrics import (VULN_NAMES, binary_preds, macro_f1,  # noqa: E402
                     mean_average_precision, micro_f1, per_class_prf,
                     search_global_threshold, subset_accuracy)

N_CLS = len(VULN_NAMES)


def _y(rows):
    return torch.tensor(rows, dtype=torch.float32)


def _p(rows):
    return torch.tensor(rows, dtype=torch.float32)


# ----------------------------------------------------------------- 1) F1 边界与 sklearn 对照
def test_micro_macro_f1_boundaries_no_nan_and_sklearn_match():
    y = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0]])
    for preds in (_p([[0] * 7] * 3), _p([[1] * 7] * 3)):
        y_np, p_np = y.numpy(), preds.numpy()
        assert micro_f1(y, preds) == pytest.approx(
            f1_score(y_np.ravel(), p_np.ravel(), average="micro", zero_division=0))
        assert macro_f1(y, preds) == pytest.approx(
            f1_score(y_np, p_np, average="macro", zero_division=0))
        assert not np.isnan(micro_f1(y, preds)) and not np.isnan(macro_f1(y, preds))


def test_micro_f1_matches_sklearn_random():
    g = torch.Generator().manual_seed(0)
    y = (torch.rand(20, 7, generator=g) < 0.3).float()
    p = (torch.rand(20, 7, generator=g) < 0.4).int()
    assert micro_f1(y, p) == pytest.approx(
        f1_score(y.numpy().ravel(), p.numpy().ravel(), average="micro", zero_division=0))
    assert macro_f1(y, p) == pytest.approx(
        f1_score(y.numpy(), p.numpy(), average="macro", zero_division=0))


def test_binary_preds_threshold_inclusive():
    probs = torch.tensor([[0.2, 0.5, 0.8]])
    assert torch.equal(binary_preds(probs, 0.5), torch.tensor([[0, 1, 1]]))


# ----------------------------------------------------------------- 2) 逐类 P/R/F1（support=0）
def test_per_class_prf_zero_support_class_not_divide_by_zero():
    y = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0]])
    p = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0]])
    out = per_class_prf(y, p)
    assert out["names"] == VULN_NAMES
    assert out["support"][0] == 1 and out["support"][1] == 1
    assert out["support"][2] == 0 and out["f1"][2] == 0.0
    assert out["precision"][2] == 0.0 and out["recall"][2] == 0.0
    # class0: 预测正确 1/1 → P=R=F1=1
    assert out["f1"][0] == pytest.approx(1.0)
    assert all(not np.isnan(v) for v in out["f1"] + out["precision"] + out["recall"])


# ----------------------------------------------------------------- 3) mAP / per-class PR-AUC
def test_mean_average_precision_skips_zero_positive_and_single_class_ap_is_one():
    probs = torch.tensor([[0.1], [0.2], [0.9], [0.8]])
    y = torch.tensor([[0], [0], [1], [1]])
    # 扩展为 7 列：class0 有正样本，其余 6 类无正样本
    P = torch.cat([probs, torch.zeros(4, 6)], dim=1)
    Y = torch.cat([y, torch.zeros(4, 6, dtype=torch.long)], dim=1)
    out = mean_average_precision(P, Y)
    assert out["ap_classes_used"] == 1
    assert out["skipped"] == VULN_NAMES[1:]
    assert out["ap"][0] == pytest.approx(1.0)
    assert out["mAP"] == pytest.approx(1.0)
    assert all(v is None for v in out["ap"][1:])
    # 对照 sklearn 单列 AP
    ref = average_precision_score(Y[:, 0].numpy(), P[:, 0].numpy())
    assert out["ap"][0] == pytest.approx(ref)


def test_mean_average_precision_all_zero_positive():
    probs = torch.rand(5, 7)
    y = torch.zeros(5, 7)
    out = mean_average_precision(probs, y)
    assert out["ap_classes_used"] == 0 and out["mAP"] == 0.0
    assert out["skipped"] == VULN_NAMES


# ----------------------------------------------------------------- 4) 阈值扫描
def test_search_global_threshold_monotonic_selects_separator():
    probs = torch.tensor([[0.55], [0.45], [0.55], [0.45]])
    y = torch.tensor([[1], [0], [1], [0]])
    P = torch.cat([probs, torch.zeros(4, 6)], dim=1)
    Y = torch.cat([y, torch.zeros(4, 6, dtype=torch.long)], dim=1)
    out = search_global_threshold(P, Y)
    assert out["best_threshold"] == pytest.approx(0.50)
    assert out["best_micro_f1"] == pytest.approx(1.0)
    assert out["metric"] == "micro_f1"
    # 候选完整（0.20..0.80 步长 0.05，共 13 个）
    assert [c["threshold"] for c in out["candidates"]] == \
        [round(0.20 + 0.05 * i, 2) for i in range(13)]
    assert all(set(c) == {"threshold", "micro_f1", "macro_f1"} for c in out["candidates"])


def test_search_global_threshold_tie_breaks_to_smaller_threshold():
    # 全部预测为负 → 所有候选 micro-F1 相同（0）→ 取最小阈值 0.20
    probs = torch.zeros(3, 7) + 0.1
    y = torch.ones(3, 7)
    out = search_global_threshold(probs, y)
    assert out["best_threshold"] == pytest.approx(0.20)
    assert out["best_micro_f1"] == pytest.approx(0.0)


def test_subset_accuracy_exact_match():
    y = _y([[1, 0, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0, 0]])
    p = _y([[1, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0]])
    assert subset_accuracy(y, p) == pytest.approx(0.5)
