#!/usr/bin/env python3
"""任务2 汇总卷的回归测试（`scripts/collect_buggy_canon_summary.py`，2026-09-21）。

锁住的核心是 **`clean_only` 诊断列的中立性**：

  该列的作用是回答「补回 `buggy_*` 之后涨的分里，有多少来自它们**七类全 1 的标签**」
  （`decisions.md` §18.4）。它只有在 test 里**真的混入了** `buggy_*` 时才应该起作用；
  在**没有** buggy 的 test 上，它必须与全 test **逐位相同**。

  为什么必须钉死这条：写错的方向有很多种，而**最坏的一种是"永远有差"**——
  比如把"干净合约"判成 `y.any(axis=1)` 为假（那是 `buggy` 口径，语义完全不同），
  那样两列会一直有差，读者会以为"标签假象一直都在"，从而**把一条真实存在的偏差
  误读成无关紧要的常数**。中立性测试同时钉住了判据（按**项目名** `buggy_*`，不是按标签）。

运行：`pytest tests/test_collect_buggy_canon.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_buggy_canon_summary as cs  # noqa: E402


# 图 base 形如 `<项目>__<合约>`（`dataset.project_of_base` 取 `__` 前一段、剥 asd_/nasd_ 前缀）
CLEAN_IDS = [f"asd_alpha__c{i}" for i in range(4)] + [f"nasd_beta__d{i}" for i in range(2)]
BUGGY_IDS = [f"asd_buggy_7__buggy_7"] + [f"nasd_buggy_9__buggy_9"]


def test_is_buggy_reuses_dataset_predicate():
    """判据必须是**项目名**前缀，且复用 `dataset.is_buggy_project`（只有一份实现）。"""
    import dataset
    assert cs.is_buggy("asd_buggy_7__buggy_7")
    assert cs.is_buggy("buggy_9__buggy_9")
    assert not cs.is_buggy("asd_alpha__c0")
    # 与 dataset 侧口径逐例一致（不得各写一份）
    for b in ["asd_buggy_7__buggy_7", "asd_alpha__c0", "nasd_beta__d1"]:
        assert cs.is_buggy(b) == dataset.is_buggy_project(dataset.project_of_base(b))


def _blob(ids, labels, probs):
    return cs.calibers(np.array(probs, dtype=float), np.array(labels, dtype=int),
                       ids, thr=0.5)


def test_clean_only_is_identical_when_no_buggy_in_test():
    """**中立性**：test 里没有 `buggy_*` 时，两列必须逐位相同。"""
    labels = [[1, 0, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0, 0],
              [0, 0, 1, 0, 0, 0, 0], [0, 0, 0, 1, 0, 0, 0],
              [1, 1, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0]]
    probs = [[0.9, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], [0.1, 0.8, 0.1, 0.1, 0.1, 0.1, 0.1],
             [0.1, 0.1, 0.7, 0.1, 0.1, 0.1, 0.1], [0.1, 0.1, 0.1, 0.6, 0.1, 0.1, 0.1],
             [0.7, 0.6, 0.1, 0.1, 0.1, 0.1, 0.1], [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]]
    c = _blob(CLEAN_IDS, labels, probs)
    assert c["n_buggy_in_test"] == 0
    for wp in ("fixed_0.5", "val_thr"):
        a, b = c[wp]["all"], c[wp]["clean_only"]
        assert a["micro_f1"] == b["micro_f1"]
        assert a["macro_f1"] == b["macro_f1"]
        assert a["per_class_f1"] == b["per_class_f1"]
        assert b["delta_vs_all_macro"] == 0.0


def test_clean_only_drops_exactly_the_buggy_contracts():
    """混入全 1 标签的 buggy 后：只剔掉它们、support 同步缩小、**Δ 的符号必须为负**。

    🔴 **符号约定要说死**：`delta_vs_all_macro = clean_only − all`。
    本测试里两个 buggy 是**七类全 1 且被完全判对**（模型全报 1）——即"最容易刷分"的极端。
    此时把它们剔掉，读数必然**变差** ⇒ **Δ < 0**。
    若实现写反（把 clean_only 当成"更好的口径"或算成 all − clean_only），符号就反了，
    而**两个方向都能讲出通顺的故事**——这正是要靠测试钉死而不是靠读代码的原因。
    """
    ids = CLEAN_IDS + BUGGY_IDS
    labels = ([[1, 0, 0, 0, 0, 0, 0]] * 2 + [[0, 0, 0, 0, 0, 0, 0]] * 2
              + [[0, 1, 0, 0, 0, 0, 0]] * 2
              + [[1, 1, 1, 1, 1, 1, 1]] * 2)          # 两个 buggy：七类全 1
    probs = ([[0.9, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]] * 2 + [[0.1] * 7] * 2
             + [[0.1, 0.8, 0.1, 0.1, 0.1, 0.1, 0.1]] * 2
             + [[0.9] * 7] * 2)                       # buggy 被完全判对（全 1 预测）
    c = _blob(ids, labels, probs)
    assert c["n_test"] == 8 and c["n_buggy_in_test"] == 2 and c["n_clean"] == 6
    for wp in ("fixed_0.5", "val_thr"):
        assert c[wp]["clean_only"]["delta_vs_all_macro"] < 0, \
            "剔掉「全 1 且被完全判对」的合约只会让 macro 变差 ⇒ Δ = clean_only − all 必须为负"
    # 逐类 support 必须同步缩小（buggy 贡献的正样本被剔掉），且干净合约的类不减
    sup_all = c["val_thr"]["all"]["support"]
    sup_clean = c["val_thr"]["clean_only"]["support"]
    assert all(sc <= sa for sc, sa in zip(sup_clean, sup_all))
    assert sum(sup_clean) < sum(sup_all)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
