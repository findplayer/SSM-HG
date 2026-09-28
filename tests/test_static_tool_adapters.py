#!/usr/bin/env python3
"""五个非 Slither 传统工具适配层的回归测试（`scripts/static_tool_adapters.py`，2026-09-25）。

**这个文件里的每一条都对应一个已经真实踩到的坑**，而且**全部属于"不报错"的那一类**：
写错了不会崩、不会有异常，只会让某个工具的七维向量**悄悄变成全零或全一**，
最后进论文的对比表。这是本仓最贵的一种错，所以逐条钉住。

| # | 坑 | 症状 | 对应测试 |
| --- | --- | --- | --- |
| 1 | securify 输出用**展示名**（`Unused Return Pattern`），`--list-patterns` 给的是**类名**（`UnusedReturn`） | 恒空集 ⇒ 全零预测 | `test_securify_keys_are_display_names` |
| 2 | manticore 的 `global.findings` 是**描述文本**（`Reachable SELFDESTRUCT`），不是 ARGUMENT 名 | 恒空集 | `test_manticore_keys_are_descriptors` |
| 3 | oyente **把 8 个检查名全打印**，每个后面跟 True/False | **恒全集** ⇒ 六个类全亮（比全零更危险：micro-F1 看着还"高"） | `test_oyente_must_read_the_boolean` |
| 4 | oyente 的结果走 **stderr**（Python logging） | 恒空集 | `test_parsers_read_merged_stream` |
| 5 | securify 的 `Pattern:` 与**源码回显**混在同一份输出里 | 全文子串匹配 ⇒ 假阳性 | `test_securify_only_reads_pattern_lines` |
| 6 | `tail_msg` 若取"最后一行"，securify 的版本线索（`ParserError`）被挤出 | 候选重试**永不触发** ⇒ 样本被记成"工具跑不了" | `test_tail_msg_keeps_solc_hint` |
| 7 | 相对路径 + `cwd`（oyente 的 `-s`、manticore 的 `--workspace` 各踩一次） | `does not exist`／`FileNotFoundError` | `test_stage_source_returns_absolute_path` |
| 8 | 源码在 `alldata(readonly)/`，工具会写临时文件/改写 pragma | 违反硬规则（只读源） | `test_stage_source_does_not_touch_source` |

运行：`pytest tests/test_static_tool_adapters.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import baseline_static_tools as bst      # noqa: E402
import metrics                            # noqa: E402
import static_tool_adapters as sta        # noqa: E402

CLASSES = set(metrics.VULN_NAMES)


# ------------------------------------------------------------------ 1. 映射表的基本性质


def test_every_tool_map_targets_valid_classes():
    """每个工具的映射值都必须是七类之一（写错一个类名 ⇒ 该检测项静默失效）。"""
    for key, spec in sta.TOOLS.items():
        assert spec.detector_to_class, f"{key} 的映射表是空的"
        bad = {v for v in spec.detector_to_class.values() if v not in CLASSES}
        assert not bad, f"{key} 映射到了不存在的类：{bad}"


def test_each_entry_lights_exactly_its_own_class():
    """逐条走一遍**每个工具**的映射表：点亮的位数必须恰为 1，且落在正确的类上。

    这是 Slither 那份测试的同款，但对五个工具各做一遍 —— 复用 `detectors_to_vector`
    的 `mapping` 参数（评测逻辑只有一份，这正是六工具可比的前提）。
    """
    for key, spec in sta.TOOLS.items():
        for det, cls in spec.detector_to_class.items():
            vec = bst.detectors_to_vector([det], mapping=spec.detector_to_class,
                                          strict_excluded=spec.strict_excluded_extra)
            assert sum(vec) == 1, f"{key}/{det} 点亮的不是恰好一位：{vec}"
            assert vec[metrics.VULN_NAMES.index(cls)] == 1, f"{key}/{det} 没落在 {cls}"


def test_no_detector_classes_are_derived():
    """🔴 `no_detector_classes` **必须从映射表派生**，不能手写。

    实测教训：原先它是手写字段，我给 SmartCheck 写了空元组，而它**根本没有 reentrancy 规则**
    （40 条规则里没有），`reentrancy` 却是最大的漏洞类（本池 24 个正例）。
    手写会漏、会漂移；派生永远自洽。本条同时钉住"派生值确实等于差集"这个定义。
    """
    for key, spec in sta.TOOLS.items():
        want = tuple(c for c in metrics.VULN_NAMES
                     if c not in set(spec.detector_to_class.values()))
        assert spec.no_detector_classes == want, f"{key} 的 no_detector_classes 不是差集"


def test_smartcheck_lacks_reentrancy_and_front_running():
    """SmartCheck 的 40 条规则里**没有** reentrancy、也没有 front_running —— 这是它那两格为 0 的
    **唯一原因**，论文里必须写成「该工具不提供此检测项」，不得写成「在此类上 F1=0」。"""
    got = set(sta.TOOLS["smartcheck"].no_detector_classes)
    assert got == {"reentrancy", "front_running"}, got


def test_slither_constant_agrees_with_derived():
    """Slither 的 `NO_DETECTOR_CLASSES` 是**独立手写的常量**（13 个单测钉住它，不能改）。
    它必须与该映射表的差集一致，否则六个工具的表里会出现"Slither 缺的类比实际多/少"。"""
    derived = tuple(c for c in metrics.VULN_NAMES
                    if c not in set(bst.DETECTOR_TO_CLASS.values()))
    assert tuple(bst.NO_DETECTOR_CLASSES) == derived, \
        f"Slither 手写常量 {bst.NO_DETECTOR_CLASSES} 与派生 {derived} 不一致"


def test_no_detector_classes_are_real_and_unmapped():
    """`no_detector_classes` 里的类必须：① 是合法类名 ② **没有任何检测项映射到它**。

    这一项是论文口径的守门员：它声明的是「**该工具不提供此检测项**」，
    而**不是**「该工具在此类上 F1=0」。二者在表里长得一样，含义完全不同。
    """
    for key, spec in sta.TOOLS.items():
        for cls in spec.no_detector_classes:
            assert cls in CLASSES, f"{key}: {cls} 不是合法类名"
            assert cls not in set(spec.detector_to_class.values()), \
                f"{key}: {cls} 被声明为'无检测项'却有检测项映射到它"


def test_excluded_keys_do_not_overlap_mapped_keys():
    """同一个检测项不能既"纳入"又"排除"——那会让产物里的说明自相矛盾。"""
    for key, spec in sta.TOOLS.items():
        overlap = set(spec.excluded) & set(spec.detector_to_class)
        assert not overlap, f"{key}: {overlap} 同时在映射表与排除表里"


def test_unknown_finding_contributes_nothing():
    """映射表外的项不得点亮任何类——宁可漏，不可编。"""
    for key, spec in sta.TOOLS.items():
        vec = bst.detectors_to_vector(["__not_a_real_detector__"], mapping=spec.detector_to_class)
        assert sum(vec) == 0, f"{key} 被一个不存在的检测项点亮了"


# ------------------------------------------------------------------ 2. 键的形态（坑 1、2）


def test_securify_keys_are_display_names():
    """🔴 securify 的键必须是**展示名**（多词），不能退回 pattern **类名**（单 token）。

    实测：`--list-patterns` 打的是 `ExternalFunction`／`UnusedReturn`，
    而结果里印的是 `External Calls of Functions`／`Unused Return Pattern` ——
    两套名字毫无字面关系。拿类名去匹结果**恒为空集**，且不报错。
    判据取"键里必须有空格"：展示名全是多词短语，类名全是单 token（`DAO` 那种也已被展示名取代）。
    """
    single = [k for k in sta.SECURIFY_MAP if " " not in k]
    assert not single, f"疑似退回了 pattern 类名（单 token）：{single}"


def test_manticore_keys_are_descriptors():
    """🔴 manticore 的键必须是 `global.findings` 里的**描述文本**，不能是 ARGUMENT 名。

    ARGUMENT 名（`suicidal`/`reentrancy`/`overflow`…）只出现在 CLI 与源码里，
    **从不出现在结果文件中**。这个测试直接对着"结果是描述文本"这个事实钉住。
    """
    arg_names = {"env-instr", "suicidal", "ext-call-leak", "invalid", "reentrancy",
                 "reentrancy-adv", "overflow", "unused-return", "delegatecall",
                 "uninitialized-memory", "uninitialized-storage", "race-condition", "lockdrop"}
    overlap = set(sta.MANTICORE_MAP) & arg_names
    assert not overlap, f"manticore 映射里混进了 ARGUMENT 名：{overlap}"
    assert all(" " in k or k.endswith("at") for k in sta.MANTICORE_MAP), \
        "manticore 的键应当都是描述文本（含空格或以 'at' 结尾的占位符前缀）"


def test_manticore_prefers_longest_descriptor():
    """描述符按**长度降序**匹配：`Reentrancy bug` 是 `Reentrancy bug (different method)`
    的前缀，短键必须先被排除，否则所有 advanced 命中都会被归成 simple（同类，但计数会错）。"""
    text = "- Reentrancy bug (different method) -\n"
    got = sta._manticore_findings(text, Path("/nonexistent"))
    assert got == {"Reentrancy bug (different method)"}, got


def test_manticore_unknown_descriptor_is_ignored():
    got = sta._manticore_findings("- Something totally new -\n", Path("/nonexistent"))
    assert got == set()


# ------------------------------------------------------------------ 3. 解析的形态（坑 3、4、5）


# 真实格式（逐字抄自实测输出）：**8 个检查名全打印**，每个后面跟 True/False
OYENTE_BLOCK_ALL_FALSE = """
INFO:symExec:\t============ Results ===========
INFO:symExec:\t  EVM Code Coverage: \t\t\t 98.7%
INFO:symExec:\t  Integer Underflow: \t\t\t False
INFO:symExec:\t  Integer Overflow: \t\t\t False
INFO:symExec:\t  Parity Multisig Bug 2: \t\t\t False
INFO:symExec:\t  Callstack Depth Attack Vulnerability: \t False
INFO:symExec:\t  Transaction-Ordering Dependence (TOD): False
INFO:symExec:\t  Timestamp Dependency: \t\t\t False
INFO:symExec:\t  Re-Entrancy Vulnerability: \t\t False
"""


def test_oyente_must_read_the_boolean():
    """🔴🔴 **本文件最重要的一条**：oyente 把 8 个名字全打印，只匹配名字 ⇒ **六个类全亮**。

    "全亮"比"全零"更危险：它不会崩、micro-F1 甚至看着不低（正例多），
    但那一行数字**全是假的**。故此处用"全 False 的完整块"钉死：必须返回空集。
    """
    assert sta._oyente_checks(OYENTE_BLOCK_ALL_FALSE) == set()


def test_oyente_reads_true_values():
    block = OYENTE_BLOCK_ALL_FALSE.replace("Integer Underflow: \t\t\t False",
                                           "Integer Underflow: \t\t\t True")
    got = sta._oyente_checks(block)
    assert got == {"Integer Underflow"}, got


def test_parsers_read_merged_stream():
    """🔴 坑 4：oyente 的结果走 **stderr**（Python logging 的默认 handler）。
    只解析 stdout ⇒ 恒空集。此处模拟"stdout 空、全在 stderr"的真实情形。
    """
    got = sta._oyente_checks(sta._merged("", OYENTE_BLOCK_ALL_FALSE))
    assert got == set()          # 全 False 仍是空集 —— 关键是它**没有崩**且读到了内容
    merged_true = sta._merged("", OYENTE_BLOCK_ALL_FALSE.replace(
        "Re-Entrancy Vulnerability: \t\t False", "Re-Entrancy Vulnerability: \t\t True"))
    assert sta._oyente_checks(merged_true) == {"Re-Entrancy Vulnerability"}


def test_securify_only_reads_pattern_lines():
    """🔴 坑 5：securify 会把命中的**源码片段**一起打印。源码里出现 `call`/`send` 是常态，
    全文子串匹配会把"源码里有这个词"当成"命中了这个检测项" —— 纯假阳性且不报错。"""
    src_echo = """
Pattern:     Low Level Calls
Source:
>     if (!msg.sender.call.value(amount)()) { revert(); }
>     balances[msg.sender] = 0;
"""
    assert sta._securify_patterns(src_echo) == {"Low Level Calls"}
    # 只有源码回显、没有 Pattern 行 ⇒ 必须空集
    assert sta._securify_patterns("> msg.sender.call.value(1)() ; // send transfer") == set()


def test_securify_unknown_pattern_line_is_ignored():
    """未纳入的展示名（如 `Locked Ether`）不得点亮任何类，但也不该让解析崩。"""
    assert sta._securify_patterns("Pattern:     Locked Ether\n") == set()


# ------------------------------------------------------------------ 4. 报错与路径（坑 6、7、8）


def test_tail_msg_keeps_solc_hint():
    """🔴 坑 6：securify 遇 solc 失败抛的是未捕获异常，traceback **最后一行**是 `> stdout:`，
    版本线索在倒数第二行的 `SolcError` 文本里。取"最后一行" ⇒ `looks_like_solc_error` 永假
    ⇒ 候选重试永不触发 ⇒ 样本被记成"工具跑不了"（系统性压低覆盖率，不报错）。"""
    stderr = "\n".join([
        "Traceback (most recent call last):",
        '  File ".../solidity_ast_compiler.py", line 31, in compile_ast',
        "solc.exceptions.SolcError: x.sol:10:5: ParserError: Expected ',' but got 'payable'",
        "        > command: `solc --standard-json`",
        "        > return code: `0`",
        "        > stdout:",
    ])
    msg = sta.tail_msg(stderr)
    assert "ParserError" in msg, "tail_msg 丢掉了版本线索"
    assert bst.looks_like_solc_error(msg), "looks_like_solc_error 必须认出这条"
    # 反面对照：只取最后一行会失败（这正是原先的写法）
    assert not bst.looks_like_solc_error(stderr.strip().splitlines()[-1])


def test_version_of_parses_solc_path():
    assert sta.version_of(Path("/x/solc-0.4.24/solc-0.4.24")) == "0.4.24"
    assert sta.version_of(Path("/x/solc-0.8.35/solc-0.8.35")) == "0.8.35"
    assert sta.version_of(Path("/x/not-solc")) == ""


def test_contract_names_dedup_and_order(tmp_path):
    p = tmp_path / "m.sol"
    p.write_text(
        "pragma solidity ^0.4.24;\n"
        "interface IThing { }\n"
        "library Lib { }\n"
        "contract A { }\n"
        "contract A { }\n"          # 重复名只算一次
        "contract B is A { }\n",
        encoding="utf-8")
    assert sta.contract_names(p) == ["IThing", "Lib", "A", "B"]


def test_stage_source_returns_absolute_path(tmp_path):
    """🔴 坑 7：相对路径 + `cwd` 会让 `-s`／`--workspace` 解析失败。
    实测在 oyente（`-s`）与 manticore（`--workspace`）上各踩一次。
    """
    src = tmp_path / "a.sol"
    src.write_text("contract A {}", encoding="utf-8")
    work = tmp_path / "w"
    out = sta.stage_source(src, work, "base")
    assert out.is_absolute(), f"stage_source 必须返回绝对路径，实际 {out}"
    assert out.exists() and out.read_text(encoding="utf-8") == "contract A {}"


def test_stage_source_does_not_touch_source(tmp_path):
    """🔴 坑 8：源在 `alldata(readonly)/`（硬规则：只读、绝不写入或改名）。
    工具会写临时文件（Slither 的 `--json`）、甚至会**改写 pragma**（securify）
    ⇒ 一律在副本上跑，源目录一个字节都不许动。
    """
    srcdir = tmp_path / "ro"
    srcdir.mkdir()
    src = srcdir / "a.sol"
    src.write_text("pragma solidity ^0.4.10;\ncontract A {}", encoding="utf-8")
    before = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in srcdir.iterdir()}
    sta.stage_source(src, tmp_path / "w", "base")
    after = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in srcdir.iterdir()}
    assert before == after, "stage_source 动了只读源目录（新增/改写/改了 mtime）"


def test_stage_source_disambiguates_same_stem(tmp_path):
    """两个不同 base 的源码可能同名（`buggy_21.sol` vs `buggy_21.sol`），
    文件名必须带 base 前缀，否则后一个会**覆盖**前一个且不报错。"""
    s1 = tmp_path / "d1" / "buggy_21.sol"
    s2 = tmp_path / "d2" / "buggy_21.sol"
    for p, body in ((s1, "contract A {}"), (s2, "contract B {}")):
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    work = tmp_path / "w"
    a = sta.stage_source(s1, work, "asd_buggy_21__buggy_21")
    b = sta.stage_source(s2, work, "nasd_buggy_21__buggy_21")
    assert a != b
    assert a.read_text(encoding="utf-8") == "contract A {}"
    assert b.read_text(encoding="utf-8") == "contract B {}"


# ------------------------------------------------------------------ 5. CLI 契约


def test_tool_registry_matches_cli_choices():
    """`--tool` 的 choices 必须与本模块的注册表一致（漏一个 ⇒ 该工具跑不到，且不报错）。"""
    ap_src = (REPO / "scripts" / "baseline_static_tools.py").read_text(encoding="utf-8")
    for key in sta.TOOLS:
        assert f'"{key}"' in ap_src, f"--tool 的 choices 里没有 {key}"
    assert '"slither"' in ap_src


def test_every_tool_has_a_runner():
    assert set(sta.RUNNERS) == set(sta.TOOLS), "有工具没有 run_* 实现（会在运行时 KeyError）"


def test_capability_and_excluded_are_documented():
    """每个工具都必须写清能力边界、且排除项要带理由 —— 这两样会进产物与论文行注。"""
    for key, spec in sta.TOOLS.items():
        assert spec.capability, f"{key} 没写能力边界"
        for k, why in spec.excluded.items():
            assert why and len(why) > 6, f"{key}/{k} 的排除理由太短（等于没写）"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
