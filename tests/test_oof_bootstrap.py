#!/usr/bin/env python3
"""bootstrap / 加权 macro 的回归测试（`scripts/oof_bootstrap.py`，2026-09-21）。

锁住三件事：

  1. **重采样单位必须是合约，不是标签对**——这是本脚本唯一容易写错、且写错了**不会报错**的地方：
     按标签对重采样会假装同一合约的 7 个标签互相独立（多标签下它们高度相关），
     ⇒ 区间被**系统性做窄**，而"窄"看起来像"精度高"，是最讨喜的错。
     判据：构造一组**同一合约内标签全同**的退化数据，两种口径的区间宽度必须显著不同。
  2. **加权 macro 的算术**——对着手算的小例核一遍（`support` 权重最容易写成"类数权重"）。
  3. **可复现**——同一 seed 两次调用逐位相同（bootstrap 用 `default_rng(seed)`，不得用全局 RNG）。

运行：`pytest tests/test_oof_bootstrap.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import oof_bootstrap as ob  # noqa: E402


# ---------------------------------------------------------------- 3. 可复现

def test_bootstrap_reproducible():
    y = np.array([[1, 0], [1, 0], [0, 1], [0, 0]])
    p = np.array([[1, 0], [1, 0], [0, 1], [1, 0]])
    a = ob.bootstrap(y, p, n_boot=200, seed=7)
    b = ob.bootstrap(y, p, n_boot=200, seed=7)
    assert a == b, "同 seed 两次调用必须逐位相同（不得用全局 RNG）"


def test_bootstrap_interval_ordering():
    rng = np.random.default_rng(0)
    y = rng.integers(0, 2, size=(20, 3))
    p = (rng.random((20, 3)) > 0.5).astype(int)
    r = ob.bootstrap(y, p, n_boot=300, seed=1)
    for k in ("micro", "macro"):
        assert r[k]["lo"] <= r[k]["mean"] <= r[k]["hi"], f"{k}: 区间次序不对"


# ---------------------------------------------------------------- 1. 重采样单位

def test_bootstrap_resamples_contracts_not_label_pairs():
    """合约级重采样必须比标签对级**更宽**——这是"没有偷偷按标签对抽样"的判据。

    构造：4 个合约 × 2 类，**每个合约的 2 个标签完全相同**（类间完全相关）。
    此时真实的采样不确定度只来自"抽到哪 4 个合约"，与标签对口径应差出明显宽度。
    """
    y = np.array([[1, 1], [1, 1], [0, 0], [0, 0]])
    p = np.array([[1, 1], [1, 1], [0, 0], [1, 1]])       # 后两个合约判错一个
    r = ob.bootstrap(y, p, n_boot=500, seed=3)
    width_contract = r["micro"]["hi"] - r["micro"]["lo"]

    # 手写"按标签对重采样"的对照实现（仅测试内使用，不污染脚本）。
    # ⚠ 采样后必须 reshape 成 **`[n/2, 2]`** 而不是 `[n, 1]`：`metrics.micro_f1` 对单列
    #   `[N,1]` **硬报错**（`_as_2d_multilabel` 的守卫，`decisions.md` §28 的教训）——
    #   这不是障碍，正是那条守卫在阻止"micro 退化成 accuracy"。两列布局与逐对统计等价。
    rng = np.random.default_rng(3)
    n = y.size
    vals = []
    yf, pf = y.ravel(), p.ravel()
    for _ in range(500):
        idx = rng.integers(0, n, size=n)
        vals.append(ob.f1_pair(yf[idx].reshape(-1, 2), pf[idx].reshape(-1, 2))[0])
    width_pair = float(np.percentile(vals, 97.5) - np.percentile(vals, 2.5))

    assert r["n_contracts"] == 4
    assert width_contract > width_pair, (
        f"合约级区间（{width_contract:.4f}）应当**宽于**标签对级（{width_pair:.4f}）；"
        "若相反，说明实现里按标签对抽了样")


# ---------------------------------------------------------------- 2. 加权 macro

def test_weighted_macro_hand_computed():
    """手算例：support 为 3/1 的两类，F1 为 1.0/0.0。

    未加权 macro = 0.5；按 support 加权 = (1.0×3 + 0.0×1) / 4 = **0.75**。
    若实现误用"类数权重"，会得到 0.5（与未加权相同）⇒ 本测试即把它钉死。
    """
    y = np.array([[1, 1], [1, 0], [1, 0], [0, 0]])       # 类0 support=3、类1 support=1
    p = np.array([[1, 1], [1, 0], [1, 0], [0, 0]])       # 全对
    r = ob.weighted_macro(y, p)
    assert r["per_class_support"] == [3, 1]
    assert r["macro_unweighted"] == pytest.approx(1.0)
    assert r["macro_support_weighted"] == pytest.approx(1.0)

    # 让类1 全错、类0 全对 → 未加权 0.5、加权 0.75
    p2 = np.array([[1, 0], [1, 0], [1, 0], [0, 0]])
    r2 = ob.weighted_macro(y, p2)
    assert r2["macro_unweighted"] == pytest.approx(0.5)
    assert r2["macro_support_weighted"] == pytest.approx(0.75)


def test_thin_classes_are_support_le_2():
    """薄支撑类判据 = support ≤ 2（大纲 5.1 的"仅作描述性呈现"门槛）。"""
    y = np.array([[1, 0, 0], [1, 0, 0], [1, 1, 0]])      # support = 3/1/0
    p = y.copy()
    r = ob.weighted_macro(y, p)
    thin = r["thin_classes"]
    assert "arithmetic" in thin and "front_running" not in thin  # 1 与 3 的差别
    assert r["n_kept_classes"] == 1, "只有 support=3 的 access_control 该留下"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
