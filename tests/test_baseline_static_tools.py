#!/usr/bin/env python3
"""传统工具基线的回归测试（`scripts/baseline_static_tools.py`，2026-09-21）。

锁住四件事（每件都对应一个**已经踩过或极易踩**的坑）：

  1. **`^` 的 Solidity 语义**——`^0.5.6` 是 `>=0.5.6 <0.6.0`，**不是**"与大版本 0 相同"。
     实测教训：只比大版本时 `^0.5.6` 被判成 0.8.35 满足 → 拿 0.8 编译 0.5 源码 →
     满屏 pragma 错 → **看起来像"这工具跑不了"，其实是选错版本**。
     这类"不报错的错"在本仓是常客（§28 / §29.4 / §35）。
  2. **检测器 → 七类映射**：一条检测器命中必须**只**点亮它该点的那一类；
     `front_running` **无对应检测器**（Slither 0.11.5 无 SWC-114），必须恒为 0 —— 这是
     映射的边界，论文里要写成"该工具不提供此检测项"，不得读成"该工具在此类上 F1=0"。
  3. **严格子集的语义**：`strict=True` 只能**减少**命中，绝不能凭空增加。
  4. **候选版本序列的完备性**：无 pragma 的合约必须先给 0.8.x 回退（大纲 4.1.1），
     但**也要**给低版本兜底——实测 47 个首轮失败的样本里大部分正是靠低版本兜底救回的。

运行：`pytest tests/test_baseline_static_tools.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import baseline_static_tools as bst  # noqa: E402


# ------------------------------------------------------------------ 1. `^` 的语义


def test_caret_locks_minor_when_major_is_zero():
    """`^0.5.6` 只接受 0.5.x —— 0.8.35 **不**满足（这是实测踩到的那个 bug）。"""
    assert bst.version_ok((0, 5, 17), "^", (0, 5, 6))
    assert not bst.version_ok((0, 8, 35), "^", (0, 5, 6))
    assert not bst.version_ok((0, 5, 5), "^", (0, 5, 6)), "低于下界不得通过"
    assert not bst.version_ok((0, 6, 0), "^", (0, 5, 6)), "越出次版本不得通过"


def test_caret_keeps_major_when_major_nonzero():
    """主版本非 0 时才退化为"锁主版本"。"""
    assert bst.version_ok((1, 9, 0), "^", (1, 2, 3))
    assert not bst.version_ok((2, 0, 0), "^", (1, 2, 3))


def test_range_operators():
    assert bst.version_ok((0, 6, 0), ">=", (0, 4, 22))
    assert bst.version_ok((0, 4, 22), "<", (0, 6, 0))
    assert bst.version_ok((0, 4, 24), "=", (0, 4, 24))
    assert not bst.version_ok((0, 4, 25), "=", (0, 4, 24))


# ------------------------------------------------------------------ 2. pragma 解析


def test_parse_pragma_single_and_range(tmp_path):
    p = tmp_path / "a.sol"
    p.write_text("pragma solidity ^0.5.7;\ncontract A {}", encoding="utf-8")
    assert bst.parse_pragma(p) == [("^", (0, 5, 7))]

    q = tmp_path / "b.sol"
    q.write_text("pragma solidity >=0.4.22 <0.6.0;\ncontract B {}", encoding="utf-8")
    assert bst.parse_pragma(q) == [(">=", (0, 4, 22)), ("<", (0, 6, 0))]


def test_parse_pragma_absent_returns_empty(tmp_path):
    p = tmp_path / "c.sol"
    p.write_text("contract C {}", encoding="utf-8")
    assert bst.parse_pragma(p) == []


# ------------------------------------------------------------------ 3. 检测器 → 七类


def test_each_detector_lights_exactly_its_own_class():
    """逐条走一遍映射表：点亮的位数必须恰为 1，且落在正确的类上。"""
    for det, cls in bst.DETECTOR_TO_CLASS.items():
        vec = bst.detectors_to_vector([det])
        assert sum(vec) == 1, f"{det} 点亮的不是恰好一位"
        assert vec[bst.class_index(cls)] == 1, f"{det} 没落在 {cls}"


def test_front_running_has_no_detector():
    """Slither 0.11.5 无 SWC-114 检测器 ⇒ front_running 恒定 0，且必须显式登记。"""
    assert "front_running" in bst.NO_DETECTOR_CLASSES
    assert not any(c == "front_running" for c in bst.DETECTOR_TO_CLASS.values())
    vec = bst.detectors_to_vector(list(bst.DETECTOR_TO_CLASS))
    assert vec[bst.class_index("front_running")] == 0


def test_unknown_detector_contributes_nothing():
    """映射表外的检测器（如 erc20-interface）不得点亮任何类——宁可漏，不可编。"""
    assert sum(bst.detectors_to_vector(["erc20-interface", "naming-convention"])) == 0


def test_strict_is_a_subset():
    """严格子集只能**减少**命中。

    ⚠ 判据必须**逐检测器**比，不能拿"全部检测器叠加后的并集"比：被排除的 4 条
    （`tautology`→arithmetic、`weak-prng`→time_manipulation 等）各自所属的类
    **另有别的检测器也会点亮**，所以两个并集向量可以完全相同 —— 拿并集比会得出
    "排除项没生效"的错误结论（本测试的第一版就是这么写错的）。
    """
    for det in bst.DETECTOR_TO_CLASS:
        broad = bst.detectors_to_vector([det])
        strict = bst.detectors_to_vector([det], strict=True)
        assert all(s <= b for s, b in zip(strict, broad)), f"{det}: 严格子集反而多出命中"
        if det in bst.STRICT_EXCLUDED:
            assert sum(strict) == 0, f"{det} 在严格子集里必须被排除"
        else:
            assert strict == broad, f"{det} 不在排除名单，两套口径应当相同"


def test_strict_excluded_are_all_mapped():
    """排除名单里的每一条都必须在映射表里——否则是"排除了一个不存在的键"，静默失效。"""
    assert bst.STRICT_EXCLUDED <= set(bst.DETECTOR_TO_CLASS)


# ------------------------------------------------------------------ 4. 候选版本序列


def _fake_versions(*vers):
    return sorted(((v, Path(f"/fake/solc-{'.'.join(map(str, v))}")) for v in vers),
                  key=lambda t: t[0])


def test_no_pragma_falls_back_to_08_then_lower(tmp_path):
    """无 pragma：先给最高 0.8.x（大纲 4.1.1），**之后仍要有低版本兜底**。"""
    p = tmp_path / "d.sol"
    p.write_text("contract D {}", encoding="utf-8")
    cands = bst.pick_solc_candidates(p, _fake_versions((0, 4, 24), (0, 8, 35)))
    tags = [t for _, t in cands]
    assert tags[0] == "fallback-0.8", f"首选项应为 0.8 回退，实际 {tags[0]}"
    assert any(t.startswith("fallback-0.4") for t in tags), "缺低版本兜底"


def test_pragma_match_comes_first(tmp_path):
    p = tmp_path / "e.sol"
    p.write_text("pragma solidity ^0.5.7;\ncontract E {}", encoding="utf-8")
    cands = bst.pick_solc_candidates(p, _fake_versions((0, 4, 24), (0, 5, 17), (0, 8, 35)))
    assert cands[0][1] == "0.5.17", f"首个候选应是 pragma 命中的 0.5.17，实际 {cands[0][1]}"


def test_no_versions_installed(tmp_path):
    p = tmp_path / "f.sol"
    p.write_text("pragma solidity ^0.5.7;\ncontract F {}", encoding="utf-8")
    assert bst.pick_solc_candidates(p, []) == []


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
