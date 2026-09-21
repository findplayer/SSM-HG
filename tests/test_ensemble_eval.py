#!/usr/bin/env python3
"""多种子集成的回归测试（`scripts/ensemble_eval.py`，2026-09-21）。

锁住**一条**最重要的性质：**按 `sample_ids` 对齐，不对齐就报错退出**。

为什么值得单独一个测试文件：按行序平均是**静默的**——它不会抛异常、不会出 NaN，
只会把 A 模型的合约和 B 模型的合约平均在一起，产出一个"看起来正常"的数。
这是本仓反复出现的失效形态（§28 `.ravel()`、§29.4 标签源、§35 静默消失）的第 N 例。

另锁：集成必须**真的平均**（不是取其中一个），且单模型指标取自各自的阈值。

运行：`pytest tests/test_ensemble_eval.py -q`
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import ensemble_eval as ee  # noqa: E402


def _write_run(d: Path, seed: int, ids: list[str], val_p, test_p, labels):
    d.mkdir(parents=True, exist_ok=True)
    torch.save({"probs": torch.tensor(val_p, dtype=torch.float32),
                "labels": torch.tensor(labels, dtype=torch.float32),
                "sample_ids": ids, "threshold": 0.5},
               d / "val_best_probs.pt")
    torch.save({"probs": torch.tensor(test_p, dtype=torch.float32),
                "labels": torch.tensor(labels, dtype=torch.float32),
                "sample_ids": ids, "threshold": 0.5},
               d / "test_probs.pt")


def _make_group(root: Path, *, swap_ids: bool = False):
    """建 2 个训练种子的 run（同划分）。`swap_ids=True` 时让第二个 run 的 sample_ids 顺序不同。"""
    ids = ["a", "b", "c", "d"]
    labels = [[1, 0], [1, 0], [0, 1], [0, 0]]
    base_val = [[0.9, 0.1], [0.8, 0.2], [0.1, 0.9], [0.2, 0.1]]
    base_test = [[0.9, 0.1], [0.8, 0.2], [0.1, 0.9], [0.2, 0.1]]
    for ts in (0, 1):
        ids_t = list(reversed(ids)) if (swap_ids and ts == 1) else ids
        rows = list(reversed(base_val)) if (swap_ids and ts == 1) else base_val
        rows_t = list(reversed(base_test)) if (swap_ids and ts == 1) else base_test
        _write_run(root / f"m_ts{ts}_ss0" / f"seed{ts}", ts, ids_t, rows, rows_t, labels)
    return root


def test_alignment_mismatch_is_fatal(tmp_path):
    """`sample_ids` 顺序不同 ⇒ 必须报错退出，**绝不能**按行序算出个数来。"""
    group = _make_group(tmp_path / "g", swap_ids=True)
    with pytest.raises(SystemExit) as exc:
        ee.evaluate_group(group, "m", [0, 1], [0])
    assert "sample_ids" in str(exc.value)


def test_aligned_group_runs_and_ensembles(tmp_path):
    """对齐时能跑通；集成概率是**逐元素平均**（不是取某一个 run）。"""
    group = _make_group(tmp_path / "g")
    res = ee.evaluate_group(group, "m", [0, 1], [0])
    rec = res["split_seeds"]["ss0"]
    assert rec["n_models"] == 2
    assert "ensemble" in rec and len(rec["singles"]) == 2
    # 两个 run 概率完全相同 ⇒ 平均后与单模型一致，Δvs均值 ≈ 0
    assert abs(rec["delta_vs_mean"]) < 1e-9
    assert abs(rec["delta_vs_best"]) < 1e-9


def test_too_few_runs_is_skipped_not_crashed(tmp_path):
    """只有一个 run 时跳过并说明原因，而不是硬算一个假的"集成"。"""
    group = _make_group(tmp_path / "g")
    shutil.rmtree(group / "m_ts1_ss0")
    res = ee.evaluate_group(group, "m", [0, 1], [0])
    assert "skipped" in res["split_seeds"]["ss0"]
    assert "engine" not in res["split_seeds"]["ss0"]


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
