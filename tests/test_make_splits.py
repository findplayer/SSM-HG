"""M5 划分单测（2026-09-12：A2 覆盖约束校正 + T-A 两级池去重）。

覆盖：合成池的 C1/C2 达标、规模/互斥/并集、确定性、换出必为全零；不可行路径报错；
两级去重的保留规则与确定性（源码内容相同 / 同地址不同内容）；
真实池三种子的黄金值（去重后池规模、替换数、下限修正、val/test 支撑）回归。

运行：pytest tests/ -q
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from dataset import BASE, build_index, is_buggy_project, project_of_base  # noqa: E402
from make_splits import (MIN_POS_PER_SPLIT, VULN_NAMES,  # noqa: E402
                         dedup_pool, make_split_for_seed, refine_coverage)

N_CLS = len(VULN_NAMES)
RATIO = [0.8, 0.1, 0.1]
MIN_RATIO = 0.30

# 2026-09-12 真实池黄金值（T-A 两级去重后池 448 = 358/45/45；支撑顺序同 VULN_NAMES）
GOLDEN = {
    0: {"swaps": 18, "floor_fixes": 1,
        "val": [3, 3, 1, 1, 5, 1, 8], "test": [2, 2, 1, 1, 5, 2, 7]},
    1: {"swaps": 16, "floor_fixes": 0,
        "val": [3, 3, 1, 1, 5, 1, 8], "test": [2, 2, 1, 1, 5, 1, 7]},
    2: {"swaps": 12, "floor_fixes": 0,
        "val": [3, 2, 1, 1, 5, 1, 8], "test": [2, 3, 1, 1, 5, 1, 7]},
}
GOLDEN_POOL = 448
GOLDEN_DROPPED = {"source-sha1": 46, "address": 1}


def _counts(bases, index):
    return [sum(1 for b in bases if index[b][i]) for i in range(N_CLS)]


def _synthetic(n_per=6, n_zero=60):
    """合成池：每类 n_per 个专用携带者 + n_zero 个全零合约。"""
    index, pool = {}, []
    for i in range(N_CLS):
        for j in range(n_per):
            name = f"c{i}_p{j}"
            label = [0] * N_CLS
            label[i] = 1
            index[name] = label
            pool.append(name)
    for k in range(n_zero):
        name = f"z{k}"
        index[name] = [0] * N_CLS
        pool.append(name)
    return set(pool), index


def test_refine_coverage_synthetic_constraints_and_determinism():
    pool, index = _synthetic()
    out1 = make_split_for_seed(11, pool, index, RATIO, "constrained", MIN_RATIO)
    out2 = make_split_for_seed(11, pool, index, RATIO, "constrained", MIN_RATIO)
    assert out1 == out2, "同 seed 必须完全确定"
    train, val, test, stats = out1
    assert (len(train), len(val), len(test)) == (82, 10, 10)
    assert set(train) | set(val) | set(test) == pool
    assert not (set(train) & set(val)) and not (set(train) & set(test)) \
        and not (set(val) & set(test))
    pos = _counts(sorted(pool), index)
    for i in range(N_CLS):
        req = math.ceil(MIN_RATIO * pos[i] - 1e-9)
        assert _counts(val, index)[i] + _counts(test, index)[i] >= req      # C1
        assert _counts(val, index)[i] >= MIN_POS_PER_SPLIT                  # C2
        assert _counts(test, index)[i] >= MIN_POS_PER_SPLIT
    for _, evicted in stats["swaps"]:
        assert not any(index[evicted]), "换出必须是全零合约"


def test_refine_coverage_infeasible_raises():
    pool = {f"p{k}" for k in range(6)}
    index = {b: [1] + [0] * (N_CLS - 1) for b in pool}   # 全携带 class0 且无全零合约
    order = sorted(pool)
    with pytest.raises(RuntimeError):
        refine_coverage(order[:2], order[2:4], order[4:], index, ratio=1.0)


@pytest.mark.skipif(not (Path(BASE) / "products/alldata/graphs").exists(),
                    reason="真实池产物缺失")
def test_refine_coverage_real_pool_golden():
    graph_dir = Path(BASE) / "products/alldata/graphs"
    index, _ = build_index(graph_dir)
    pre_dedup = {b for b in index if not is_buggy_project(project_of_base(b))}
    assert len(pre_dedup) == 495, "去重前池（剔 buggy_* 后）"
    kept, dropped, _ = dedup_pool(pre_dedup, graph_dir)
    assert len(kept) == GOLDEN_POOL, "T-A 两级去重后池"
    dropped_by_level = {}
    for item in dropped:
        dropped_by_level[item["level"]] = dropped_by_level.get(item["level"], 0) + 1
    assert dropped_by_level == GOLDEN_DROPPED, "逐级丢弃数（level-1 内容 / level-2 地址）"
    included = set(kept)
    for seed, golden in GOLDEN.items():
        train, val, test, stats = make_split_for_seed(seed, included, index, RATIO,
                                                      "constrained", MIN_RATIO)
        assert stats["swaps_count"] == golden["swaps"]
        assert stats["floor_fixes"] == golden["floor_fixes"]
        assert _counts(val, index) == golden["val"]
        assert _counts(test, index) == golden["test"]
        assert (len(train), len(val), len(test)) == (358, 45, 45)
        assert not (set(train) & set(val)) and not (set(train) & set(test)) \
            and not (set(val) & set(test))
        assert set(train) | set(val) | set(test) == included


def test_dedup_pool_two_levels_and_determinism(tmp_path):
    """level-1 内容相同（nasd_0xa 副本）、level-2 同地址不同内容（0xb）——保留规则确定。"""
    files = {
        "asd_0xa__1": "contract A {}",
        "nasd_0xa__1": "contract A {}",          # 与 asd_0xa 字节相同 → level-1 丢弃
        "asd_0xb__2": "contract B1 {}",
        "nasd_0xb__2": "contract B2 {}",         # 字节不同，但同地址 → level-2 丢弃
        "asd_0xc__3": "contract C {}",
    }
    for base, text in files.items():
        proj, stem = base.split("__")
        (tmp_path / proj).mkdir(parents=True, exist_ok=True)
        (tmp_path / proj / f"{stem}.sol").write_text(text, encoding="utf-8")

    source_of = lambda b: tmp_path / b.split("__")[0] / f"{b.split('__')[1]}.sol"  # noqa: E731
    kept, dropped, _ = dedup_pool(sorted(files), tmp_path, source_of=source_of)
    assert kept == ["asd_0xa__1", "asd_0xb__2", "asd_0xc__3"], "同组保留路径字典序首个"
    assert {d["base"]: d["level"] for d in dropped} == {
        "nasd_0xa__1": "source-sha1", "nasd_0xb__2": "address"}

    kept1, _, _ = dedup_pool(sorted(files), tmp_path, levels=("source-sha1",),
                             source_of=source_of)
    assert sorted(kept1) == ["asd_0xa__1", "asd_0xb__2", "asd_0xc__3", "nasd_0xb__2"], \
        "只做 level-1 时同地址不同内容的副本仍保留"

    kept_again, dropped_again, _ = dedup_pool(sorted(files), tmp_path, source_of=source_of)
    assert (kept_again, dropped_again) == (kept, dropped), "同输入两次运行结果必须逐项一致"
