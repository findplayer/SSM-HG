#!/usr/bin/env python3
"""近重复检测与簇原子划分的回归测试（2026-09-14）。

锁住三件事：
  1. `near_dup_clusters` 的相似度判据与**全链接**聚类（单链接会把同族合约串成巨簇）；
  2. `dataset.build_index` 的 `stem` 键模式（扁平语料：图 base 就是标签键，含 `__` 也不切）；
  3. `make_splits` 的簇原子划分：任何簇不得跨划分，且覆盖约束（C1/C2）仍达标。

运行（仓库根目录）：`python -m pytest tests/test_near_dup_clusters.py -v`
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "scripts"))

import dataset  # noqa: E402
import make_splits  # noqa: E402
import near_dup_clusters as nd  # noqa: E402


# ------------------------------------------------------------ 相似度与聚类
def _sig(lines: list[str]) -> frozenset[str]:
    import hashlib
    return frozenset(hashlib.sha1(l.encode()).hexdigest() for l in lines)


def test_jaccard_basic():
    a = _sig(["alpha line one", "beta line two", "gamma line three"])
    assert nd.jaccard(a, a) == 1.0
    b = _sig(["alpha line one", "beta line two", "delta line four"])
    assert nd.jaccard(a, b) == pytest.approx(2 / 4)
    assert nd.jaccard(a, _sig(["nothing shared here"])) == 0.0


def test_rare_line_index_drops_high_frequency_lines():
    """高频行（每个文件都有）不承载信号，必须被 df_cap 滤掉。"""
    common = "pragma solidity ^0.8.0;"
    sigs = {f"f{i}": _sig([common, f"unique body line number {i} xyz"]) for i in range(10)}
    rare = nd.rare_line_index(sigs, df_cap=5)
    assert all(len(files) >= 2 for files in rare.values()), "单文件独占行不成对，不参与"


def test_complete_linkage_does_not_chain():
    """单链接会把 A~B、B~C 合成 A≁C 的巨簇；全链接必须把它们拆开。

    构造：A 与 B 相似、B 与 C 相似、A 与 C 不相似（共享行数为 0）。
    """
    sims = {("a", "b"): 0.9, ("b", "c"): 0.9}
    clusters = nd.complete_linkage_clusters(sims, ["a", "b", "c"])
    # 关键：不得因为传递性把 a 与 c 并进同一簇（单链接会，全链接不会）
    assert not any("a" in c and "c" in c for c in clusters)
    assert clusters == [["a", "b"]], clusters


def test_complete_linkage_groups_true_twins():
    sims = {("a", "b"): 0.95, ("a", "c"): 0.9, ("b", "c"): 0.91}
    clusters = nd.complete_linkage_clusters(sims, ["a", "b", "c", "d"])
    assert clusters == [["a", "b", "c"]], clusters   # d 无边 → 不成簇


def test_detect_end_to_end_on_synthetic_sources(tmp_path):
    """端到端：两份孪生 + 两份无关，要求只聚出孪生那一簇。"""
    twin = "\n".join(f"    uint256 valueNumber{i} = computeValue({i});" for i in range(30))
    (tmp_path / "twin_a.sol").write_text("contract A {\n" + twin + "\n}", encoding="utf-8")
    (tmp_path / "twin_b.sol").write_text("contract B {\n" + twin + "\n}", encoding="utf-8")
    other = "\n".join(f"    bytes32 hashValue{i} = keccak256({i});" for i in range(30))
    (tmp_path / "other.sol").write_text("contract C {\n" + other + "\n}", encoding="utf-8")
    clusters, stats = nd.detect(["twin_a", "twin_b", "other"], tmp_path,
                                source_of=lambda b: tmp_path / f"{b}.sol")
    assert clusters == [["twin_a", "twin_b"]], clusters
    assert stats["n_clusters"] == 1 and stats["max_cluster"] == 2


def test_line_hashes_skips_blank_and_short_lines(tmp_path):
    p = tmp_path / "x.sol"
    p.write_text("contract AlphaContract {\n\n  }\n    uint256 realLongLine = 1;\n",
                 encoding="utf-8")
    sig = nd.line_hashes_of(p)
    # 保留：`contract AlphaContract {`（长）与 `uint256 realLongLine = 1;`
    # 跳过：空行、`}`（strip 后 1 字符）
    assert len(sig) == 2, f"空行与短行都应被跳过，实际 {len(sig)}"


# ------------------------------------------------------------ 连通分量与泄漏审计
def test_connected_components_merges_transitive_chain():
    """连通分量必须把链式相连的 a-b-c 合成一组；全链接刻意不合并（两者用途不同）。"""
    sims = {("a", "b"): 0.9, ("b", "c"): 0.9}
    bases = ["a", "b", "c", "d"]
    assert nd.connected_components_clusters(sims, bases) == [["a", "b", "c"]]
    # 全链接：a~c 无边 → 不并入同一簇（这正是划分残留泄漏的根因）
    assert nd.complete_linkage_clusters(sims, bases) == [["a", "b"]]


def test_components_atomic_split_yields_zero_cross_split_pairs():
    """分量作原子单位时，跨划分相似对必须恒为 0（可证性质，本测试钉死它）。"""
    sims = {("a", "b"): 0.9, ("b", "c"): 0.9, ("d", "e"): 0.8}
    bases = ["a", "b", "c", "d", "e", "f"]
    groups = {b: f"c{i}" for i, members in
              enumerate(nd.connected_components_clusters(sims, bases))
              for b in members}
    # 手工构造一个"簇不跨划分"的划分（正是 make_splits --near-dup-mode cluster 的产物）
    split = {"train": ["a", "b", "c", "f"], "val": ["d", "e"], "test": []}
    assert nd.split_leakage(sims, split)["n_cross"] == 0, "分量原子划分不该有跨划分相似对"
    # 反例：把链拆开（模拟全链接/宽松划分）就会漏
    leaked = {"train": ["a", "b"], "val": ["c"], "test": []}
    assert nd.split_leakage(sims, leaked)["n_cross"] == 1


def test_split_leakage_reports_counts_and_worst():
    sims = {("a", "b"): 0.9, ("c", "d"): 0.7, ("a", "x"): 0.95}
    split = {"train": ["a", "x"], "val": ["b"], "test": ["c", "d"]}
    res = nd.split_leakage(sims, split)
    # 只有 a-b 跨划分：c-d 同在 test、a-x 同在 train，都不算泄漏
    assert res["n_cross"] == 1
    assert res["by_pair"] == {"train|val": 1}
    assert res["max_jaccard"] == 0.9
    assert res["worst"][0][:2] == ["a", "b"]       # 按 Jaccard 降序


def test_detect_mode_components_end_to_end(tmp_path):
    """端到端：链式三份 + 无关一份 → components 模式聚出一组三人，complete 不聚齐。"""
    twin = "\n".join(f"    uint256 value{i} = computeValue({i});" for i in range(30))
    for name in ("ta", "tb", "tc"):
        (tmp_path / f"{name}.sol").write_text(f"contract {name} {{\n{twin}\n}}", encoding="utf-8")
    other = "\n".join(f"    bytes32 hash{i} = keccak256({i});" for i in range(30))
    (tmp_path / "zz.sol").write_text(f"contract zz {{\n{other}\n}}", encoding="utf-8")
    args = dict(source_of=lambda b: tmp_path / f"{b}.sol")
    comp, _ = nd.detect(["ta", "tb", "tc", "zz"], tmp_path, mode="components", **args)
    assert comp == [["ta", "tb", "tc"]], comp
    assert len(comp[0]) == 3
    _, stats = nd.detect(["ta", "tb", "tc", "zz"], tmp_path, mode="components", **args)
    assert stats["cluster_mode"] == "components"
    with pytest.raises(ValueError):
        nd.detect(["ta"], tmp_path, mode="nonsense", **args)


# ------------------------------------------------------------ stem 键模式
def test_build_index_stem_mode_matches_stem_with_dunder(tmp_path):
    """`stem` 模式下含 `__` 的词干必须整体作为标签键，不得按 `__` 切开。"""
    graphs = tmp_path / "graphs"
    graphs.mkdir()
    for base in ("dos__buggy_25", "0xabc"):
        (graphs / f"{base}_pyg.pt").write_bytes(b"")     # build_index 只看文件名
    labels = tmp_path / "labels.json"
    labels.write_text(
        '[{"contract_name": "dos__buggy_25-A.sol", "targets": [1, 0, 0, 0, 0, 0, 0]},'
        ' {"contract_name": "0xabc-B.sol", "targets": [0, 1, 0, 0, 0, 0, 0]}]',
        encoding="utf-8")
    index, unmatched = dataset.build_index(graphs, label_file=labels, key_mode="stem")
    assert unmatched == []
    assert index["dos__buggy_25"][0] == 1        # 未被切成 "dos"
    assert index["0xabc"][1] == 1


def test_build_index_project_mode_unchanged_by_default(tmp_path):
    """默认（project）模式行为不变：键取 `__` 前一段。"""
    graphs = tmp_path / "graphs"
    graphs.mkdir()
    (graphs / "asd_0xabc__Token_pyg.pt").write_bytes(b"")
    labels = tmp_path / "labels.json"
    labels.write_text('[{"contract_name": "0xabc-Token.sol", "targets": [1,0,0,0,0,0,0]}]',
                      encoding="utf-8")
    index, unmatched = dataset.build_index(graphs, label_file=labels)
    assert list(index) == ["asd_0xabc__Token"] and index["asd_0xabc__Token"][0] == 1


def test_resolve_label_key_mode_rejects_unknown():
    with pytest.raises(ValueError):
        dataset.resolve_label_key_mode("nonsense")


# ------------------------------------------------------------ 簇原子划分
def _toy(n_clusters: int = 6, per_cluster: int = 3, n_single: int = 60):
    """合成池：n_clusters 个簇（每簇 per_cluster 个成员，同簇共享同一标签）+ 若干单例。"""
    index: dict[str, list[int]] = {}
    groups: dict[str, str] = {}
    pool: set[str] = set()
    for c in range(n_clusters):
        members = [f"cl{c}_m{k}" for k in range(per_cluster)]
        for m in members:
            lab = [0] * 7
            lab[c % 7] = 1
            index[m] = lab
            groups[m] = f"c{c}"
            pool.add(m)
    for s in range(n_single):
        name = f"single{s}"
        lab = [0] * 7
        lab[s % 7] = 1 if s % 3 == 0 else 0
        index[name] = lab
        pool.add(name)
    return pool, index, groups


def test_cluster_atomic_split_never_splits_a_cluster():
    pool, index, groups = _toy()
    train, val, test, stats = make_splits.cluster_atomic_split(0, pool, groups, [0.8, 0.1, 0.1])
    assert sorted(train + val + test) == sorted(pool)
    assert not (set(train) & set(val)) and not (set(train) & set(test)) and not (set(val) & set(test))
    for key, members in make_splits.cluster_members(pool, groups).items():
        where = {n for n, arr in (("train", train), ("val", val), ("test", test)) if set(members) & set(arr)}
        assert len(where) == 1, f"簇 {key} 跨划分 {where}"
    assert stats["groups_mode"] is True


def test_refine_coverage_with_groups_keeps_atomicity_and_meets_constraints():
    pool, index, groups = _toy()
    train, val, test, stats = make_splits.cluster_atomic_split(0, pool, groups, [0.8, 0.1, 0.1])
    train, val, test, cstats = make_splits.refine_coverage(train, val, test, index, 0.30,
                                                           groups=groups)
    for key, members in make_splits.cluster_members(pool, groups).items():
        where = {n for n, arr in (("train", train), ("val", val), ("test", test)) if set(members) & set(arr)}
        assert len(where) == 1, f"校正后簇 {key} 跨划分 {where}"
    # 换出必须整簇全零
    for _carrier, evicted in cstats["swaps"]:
        assert not any(index[evicted])


def test_refine_coverage_without_groups_is_unchanged():
    """`groups=None` 必须与旧行为逐元素一致（默认路径不漂移）。"""
    pool, index, _groups = _toy()
    order = sorted(pool)
    import random
    random.Random(0).shuffle(order)
    n_train = int(round(len(order) * 0.8))
    n_val = int(round(len(order) * 0.1))
    base = (order[:n_train], order[n_train:n_train + n_val], order[n_train + n_val:])
    a = make_splits.refine_coverage(*[list(x) for x in base], index, 0.30)
    b = make_splits.refine_coverage(*[list(x) for x in base], index, 0.30, groups=None)
    assert a == b


def test_dedup_pool_key_of_prevents_dunder_collapse(tmp_path):
    """`key_of=lambda b: b` 时含 `__` 的词干不得被塌缩成同一组。"""
    for name in ("dos__buggy_3", "dos__buggy_4", "uncheck__buggy_5"):
        (tmp_path / f"{name}.sol").write_text(f"contract C {{ uint {name.replace('_','')}; }}",
                                              encoding="utf-8")
    bases = ["dos__buggy_3", "dos__buggy_4", "uncheck__buggy_5"]
    src = lambda b: tmp_path / f"{b}.sol"
    collapsed, dropped_a, _ = make_splits.dedup_pool(bases, tmp_path, levels=("address",), source_of=src)
    kept, dropped_b, _ = make_splits.dedup_pool(bases, tmp_path, levels=("address",),
                                                source_of=src, key_of=lambda b: b)
    # 默认 project_of_base 把 dos__buggy_3/4 塌缩成同一组（丢 1 个），uncheck 组只有 1 个成员故不丢
    assert len(dropped_a) == 1 and dropped_a[0]["group_key"] == "dos", dropped_a
    assert dropped_b == [] and len(kept) == 3, "key_of=自身时每个样本自成一键"
