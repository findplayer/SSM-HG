#!/usr/bin/env python3
"""五个**非 Slither** 传统工具的适配层（大纲 `改II` 5.3「六工具对比」）。

**为什么单独成模块**：5.3 的对比表要求六个工具**同一套指标口径**。评测部分
（检测项 → 七维向量 → 逐划分 P/R/F1）对所有工具都是同一份实现，改一处就同时改六个 ——
这是表格内部可比的前提。但**调用与解析**每个工具都不同（各自的 conda env、solc 口径、
输出格式、能力边界），塞进 `baseline_static_tools.py` 会让 430 行的脚本变成 1000+ 行。
故：**调用/解析/映射表**放这里，**评测**留在原处。原脚本只有一个 `--tool` 分派。

🔴 **映射的尺子（六个工具同一把，2026-09-25 定）**：一个检测项进入七类，
当且仅当它有**唯一且明确的 SWC 锚点**，且该 SWC 落在七类语义内。**无锚点者一律不纳入**
（宁可漏，不可编）——`EXCLUDED` 逐条记下"已观察但不纳入"的项与理由，必须在报告里披露。
Slither 那张 29 条的 `DETECTOR_TO_CLASS` 是同一把尺的第一份，本模块与之对齐。

⚠ **此处与 Slither 的一个自觉差异**：Slither 的映射键是**检测器名**，本模块里 Mythril
改用 **SWC 编号**（Mythril 在 JSON 里自述 `swc-id`）——那是工具**自己声明的**归属，
比"我按名字猜"更硬，故不迁就 Slither 的键形。

🔴 **一律不在只读源目录里写任何东西**（`AGENTS.md` 数据边界）：
调用前把源码 `cp` 到 `work/` 里再跑。Slither 的 `--json` 原先写在 `source.parent`
（= `alldata(readonly)/…`）再删掉 —— 瞬时也违规，2026-09-25 一并改到 `work/`。

用法：不直接调用，由 `baseline_static_tools.py --tool <名>` 分派。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

import metrics          # noqa: E402  七类的**唯一权威**顺序（本模块不另立一份）
CLASS_NAMES: tuple[str, ...] = tuple(metrics.VULN_NAMES)

CONDA = Path.home() / "anaconda3"
TOOLS_DIR = Path.home() / "tools"
GETH_BIN = TOOLS_DIR / "geth-alltools-linux-amd64-1.7.3-4bb3c89d"
SOLC_SHIM_0419 = CONDA / "envs" / "oyente" / "bin" / "solc"

# manticore 单合约预算下限（秒）。🔴 文件级总预算在 `run_manticore` 里封顶，见那里的说明。
MIN_MC_BUDGET = 15


# --------------------------------------------------------------------------- solc 口径
# `baseline_static_tools` 负责**选**版本（`installed_solc_versions` / `pick_solc_candidates`，
# 已被 13 个单测钉住），本模块只负责**把选出来的版本喂给各工具**。故候选序列由调用方传入。
SOLC_MODE_BINARY = "binary"    # 直接吃 solc 可执行文件路径（--solc / SOLC_BINARY）
SOLC_MODE_VERSION = "version"  # 只吃版本号字符串（mythril --solv，py-solc-x 自己找）
SOLC_MODE_FIXED = "fixed"      # 工具自带/钉死某个版本，不吃候选（oyente）
SOLC_MODE_NONE = "none"        # 不需要 solc（smartcheck 自己解析源码）


def _merged(stdout: str, stderr: str) -> str:
    """把 stdout 与 stderr **合并**后再解析。

    🔴 **必须合并**（2026-09-25 实测踩到，与 securify 的"展示名"是同一类静默错）：
    本仓这五个工具里，**结果常常写在 stderr 上**——Oyente 用 Python `logging`（默认 handler 走
    stderr），实测 `Integer Underflow: True` 等 8 行全在 stderr；Manticore 同理。
    只解析 stdout 的后果**不是报错而是空集** ⇒ 每个合约都被记成"零命中"
    （= 把"工具跑不了/没抓到"当成"工具说没漏洞"）。
    """
    return (stdout or "") + "\n" + (stderr or "")


def tail_msg(text: str, n: int = 400) -> str:
    """报错摘要：取 stderr/stdout 的**末 n 个字符**（不是最后一行）。

    🔴 **必须取尾部片段而不是最后一行**（2026-09-25 实测踩到）：securify 遇 solc 失败时
    抛的是**未捕获异常**，traceback 的**最后一行**是 `        > stdout:` ——
    版本线索（`ParserError` / `requires different compiler version`）在**倒数第二行**
    的 `SolcError` 文本里。取最后一行会让 `looks_like_solc_error()` **永远判 false**，
    于是候选重试永不触发，全部样本被记成"工具跑不了"（系统性压低覆盖率，且不报错）。
    """
    text = (text or "").strip()
    return text[-n:] if text else ""


def version_of(exe: Path) -> str:
    """solc 可执行文件路径 → 版本号字符串（`…/solc-0.4.24/solc-0.4.24` → `0.4.24`）。"""
    m = re.search(r"solc-(\d+\.\d+\.\d+)", str(exe))
    return m.group(1) if m else ""


# --------------------------------------------------------------------------- 映射表
# ⚠ 每条的 `SWC-nnn` 都是**可核对的依据**，不是注释。无依据的一律不列。

MYTHRIL_MAP: dict[str, str] = {          # 键 = Mythril 自述的 SWC 编号
    "107": "reentrancy",          # Reentrancy
    "106": "access_control",      # Unprotected SELFDESTRUCT
    "105": "access_control",      # Unprotected Ether Withdrawal
    "112": "access_control",      # Delegatecall to Untrusted Callee
    "115": "access_control",      # Authorization through tx.origin
    "124": "access_control",      # Write to Arbitrary Storage Location
    "101": "arithmetic",          # Integer Overflow and Underflow
    "104": "uncheck",             # Unchecked Call Return Value
    "113": "dos",                 # DoS with Failed Call
    "116": "time_manipulation",   # Block values as a proxy for time
    "120": "time_manipulation",   # Weak Sources of Randomness
    "114": "front_running",       # Transaction Order Dependence（Mythril **有**此项）
}


SMARTCHECK_MAP: dict[str, str] = {       # 键 = SmartCheck 的 ruleId
    "SOLIDITY_TX_ORIGIN":                 "access_control",  # SWC-115
    "SOLIDITY_ARRAY_LENGTH_MANIPULATION": "access_control",  # SWC-124
    "SOLIDITY_UNCHECKED_CALL":            "uncheck",         # SWC-104
    "SOLIDITY_SEND":                      "uncheck",         # SWC-104（send 返回值）
    "SOLIDITY_DIV_MUL":                   "arithmetic",      # SWC-101 族（先除后乘精度损失）
    "SOLIDITY_SAFEMATH":                  "arithmetic",      # SWC-101（该用 SafeMath 而未用）
    "SOLIDITY_EXACT_TIME":                "time_manipulation",  # SWC-116
    "SOLIDITY_INCORRECT_BLOCKHASH":       "time_manipulation",  # SWC-120
    "SOLIDITY_DOS_WITH_THROW":            "dos",             # SWC-113
    "SOLIDITY_TRANSFER_IN_LOOP":          "dos",             # SWC-113
    "SOLIDITY_GAS_LIMIT_IN_LOOPS":        "dos",             # SWC-128
}

SECURIFY_MAP: dict[str, str] = {         # 键 = **输出里的展示名**（不是 pattern 类名，见下）
    "Gas-dependent Reentrancy":                      "reentrancy",      # SWC-107
    "Reentrancy with constant gas":                  "reentrancy",      # SWC-107
    "Benign Reentrancy":                             "reentrancy",      # SWC-107
    "No-Ether-Involved Reentrancy":                  "reentrancy",      # SWC-107
    "Unrestricted call to selfdestruct":             "access_control",  # SWC-106
    "Unrestricted Ether Flow":                       "access_control",  # SWC-105
    "Arbitrary Send":                                "access_control",  # SWC-105（与 Slither `arbitrary-send-eth` 同源）
    "Unrestricted write to storage":                 "access_control",  # SWC-124
    "Delegatecall or callcode to unrestricted address": "access_control",  # SWC-112
    "Possibly unsafe usage of tx-origin":            "access_control",  # SWC-115
    "Unused Return Pattern":                         "uncheck",         # SWC-104
    "Unhandled Exception":                           "uncheck",         # SWC-104（send/transfer 未查返回值）
    "Low Level Calls":                               "uncheck",         # SWC-104
    "Usage of block timestamp":                      "time_manipulation",  # SWC-116
    "Transaction Order Affects Ether Receiver":      "front_running",   # SWC-114
    "Transaction Order Affects Execution of Ether Transfer": "front_running",  # SWC-114
    "Transaction Order Affects Ether Amount":        "front_running",   # SWC-114
    "Multiplication after division":                 "arithmetic",      # SWC-101 族（≈ Slither `divide-before-multiply`）
    "External call in loop":                         "dos",             # SWC-113
    "Dos gas limit pattern":                         "dos",             # SWC-128（= SmartCheck `SOLIDITY_GAS_LIMIT_IN_LOOPS`）
}

# 🔴🔴 **为什么键必须是展示名**（2026-09-25 实测踩到，是本模块最隐蔽的一个坑）：
# `securify --list-patterns` 打的是 **pattern 类名**（`ExternalFunction`、`UnusedReturn`…），
# 而**分析结果里印的是另一套展示名**（`External Calls of Functions`、`Unused Return Pattern`…）。
# 两套名字**毫无字面关系** ⇒ 拿类名去 grep 输出**恒为空**，
# 于是每个合约都被记成"零命中"（= 把"工具说没漏洞"当结论），而且**不报错**。
# 展示名的唯一真源 = `souffle_analysis/patterns/*.dl` 里的 `NAME("…")`（本表逐条抄自那里）。
# 教训：**别拿 `--list-patterns` 当输出键**。

OYENTE_MAP: dict[str, str] = {           # 键 = oyente 输出的检查项名
    "Re-Entrancy Vulnerability":         "reentrancy",        # SWC-107
    "Integer Overflow":                  "arithmetic",        # SWC-101
    "Integer Underflow":                 "arithmetic",        # SWC-101
    "Timestamp Dependency":              "time_manipulation", # SWC-116
    "Transaction-Ordering Dependence (TOD)": "front_running", # SWC-114
    "Parity Multisig Bug 2":             "access_control",    # SWC-105/106 族（未保护的初始化入口）
}


# 🔴 **manticore 的输出是描述文本，不是检测项名**（2026-09-25 实测踩到，第三个同类静默错）。
# 全部命中写在 `<workspace>/global.findings` 里，每条形如 `- Reachable SELFDESTRUCT -`；
# 这些字符串与 `--list-detectors` 的 ARGUMENT 名（`suicidal`、`reentrancy`…）**毫无字面关系**。
# 又：`--list-detectors` 在本机**直接崩**（上游 `DetectorClassification` 排序 bug），
# 所以 ARGUMENT 名只能从源码里读。下表 = 逐条抄自
# `manticore/ethereum/detectors.py` 各 `DetectX` 类里的 finding 消息原文。
# ⚠ 部分消息带占位符（`Returned value at {:s} instruction is not used`）⇒ 用**子串匹配**，按长度降序取首个命中。
MANTICORE_MAP: dict[str, str] = {
    "Reachable SELFDESTRUCT":                      "access_control",  # SWC-106
    "Reachable selfdestruct instructions":         "access_control",  # SWC-106（同上，另一条消息）
    "Potential reentrancy vulnerability":          "reentrancy",      # SWC-107
    "Reentrancy bug (different method)":           "reentrancy",      # SWC-107（advanced）
    "Reentrancy multi-million ether bug":          "reentrancy",      # SWC-107（advanced）
    "Reentrancy bug":                              "reentrancy",      # SWC-107（两条的公共前缀，必须排最后）
    "Reachable external call or ether leak to sender or arbitrary address": "access_control",  # SWC-105
    "Reachable ether leak to user controlled address via argument": "access_control",           # SWC-105
    "Reachable external call to user controlled address via argument": "access_control",        # SWC-105
    "Reachable ether leak to sender via argument": "access_control",  # SWC-105
    "Reachable external call to sender via argument": "access_control",  # SWC-105
    "Reachable ether leak to sender":              "access_control",  # SWC-105
    "Reachable external call to sender":           "access_control",  # SWC-105
    "Delegatecall to user controlled address":     "access_control",  # SWC-112
    "Delegatecall to user controlled function":    "access_control",  # SWC-112
    "Signed integer overflow at":                  "arithmetic",      # SWC-101
    "Unsigned integer overflow at":                "arithmetic",      # SWC-101
    "Integer underflow at":                        "arithmetic",      # SWC-101
    "Returned value at":                           "uncheck",         # SWC-104
    "Unused internal transaction return values":   "uncheck",         # SWC-104
    "Potential race condition (transaction order dependency)": "front_running",  # SWC-114
    "Possible transaction race conditions":        "front_running",   # SWC-114
}

# 已观察但**不纳入**的描述符（必须能在报告里逐条说明）。
MANTICORE_MAP_EXCLUDED: dict[str, str] = {
    "Potentially reading uninitialized storage": "SWC-109，七类无此语义",
    "Potentially reading uninitialized memory": "SWC-109 同上",
    "INVALID instruction": "执行到 INVALID 指令，无 SWC 锚点",
    "Manipulable balance used in a strict comparison": "无 SWC 锚点（与 SmartCheck "
        "`SOLIDITY_BALANCE_EQUALITY` 同概念，一起排除）",
    "instruction used": "env-instr：环境指令可操纵，无 SWC 锚点",
}


@dataclass(frozen=True)
class ToolSpec:
    """一个工具的调用契约。`excluded` / `capability` 都会进产物与报告，不是内部注释。"""

    key: str                                   # CLI 名 = 产物文件名前缀
    label: str                                 # 论文里的写法
    detector_to_class: dict[str, str]
    solc_mode: str
    capability: tuple[str, ...] = ()            # 能力边界（必须写进对比表行注）
    excluded: dict[str, str] = field(default_factory=dict)   # 已观察但不纳入的项 → 理由
    timeout_default: int = 300
    max_attempts: int = 3                       # solc 候选重试上限（见下方说明）
    strict_excluded_extra: frozenset[str] = frozenset()
    batch_dir: bool = False                     # 能否一次吃一个目录（只有 smartcheck）

    @property
    def no_detector_classes(self) -> tuple[str, ...]:
        """该工具**不提供任何检测项**、因而恒为 0 的类 —— **从映射表派生，不手写**。

        🔴 2026-09-25 实测教训：原先这是手写字段，而我给 SmartCheck 写了空元组。
        退化检查（看工具"预测为 1 的比例"）才发现 **SmartCheck 的 40 条规则里根本没有
        reentrancy 规则**，而 `reentrancy` 恰好是最大的漏洞类（本池 24 个正例）
        ⇒ 它那一格为 0 是**工具没这个检测项**，不是「在此类上 F1=0」。
        手写就会漏、会漂移；派生则**永远与映射表自洽**（有机检：
        `tests/test_static_tool_adapters.py::test_no_detector_classes_are_derived`）。

        ⚠ 与 `excluded` 的区别：`excluded` 是「**观察到了但没纳入**」（映射决策），
        这里是「**压根没有这项**」（工具能力）。两者都要随结果披露，但含义不同。
        """
        covered = set(self.detector_to_class.values())
        return tuple(c for c in CLASS_NAMES if c not in covered)


# 🔴 `max_attempts` **不是** Slither 的 8。理由是一条实测的成本账：
# `pick_solc_candidates` 会给 8 个候选（pragma 命中 → 0.8 回退 → 低版本兜底），
# Slither 单个合约只需几秒，8 次无所谓；而 Mythril/Manticore 的单合约预算是 180–300 s，
# 8 次 = 24–40 min/合约，214 个合约就是 85–142 h —— **不可行**。
# 取 3：pragma 命中 + 0.8 回退 + 最低兜底，已覆盖 Slither 那批"47 个首轮失败"样本的救回路径。
# ⚠ 代价（知情）：更边缘的版本组合救不回来，会被记成 `error`（= 不计入分母），
# 该口径与 Slither 的 `error` 同源，必须在对比表行注里写明"重试上限不同"。


# 🔴 `no_detector_classes` 是**必须披露**的口径：它是**映射/工具能力的边界**，
# 不是"该工具在此类上 F1=0"。六个工具各自缺哪些类见下表（front_running 是重灾区）。
TOOLS: dict[str, ToolSpec] = {
    "mythril": ToolSpec(
        key="mythril", label="Mythril", detector_to_class=MYTHRIL_MAP,
        solc_mode=SOLC_MODE_VERSION, timeout_default=180,
        capability=(
            "符号执行工具，逐合约**按时间预算**跑；超时记 `timeout`，与 Slither 的 `error` 同口径"
            "（不计入分母、不记全零）。",
            "solc 由 py-solc-x 按 `--solv` 选择；本机已把 solc-select 的 101 个版本软链进 "
            "`~/.solcx`（`solc-bin.ethereum.org` 直连被 SSL 拦，**离线**是硬前提）。",
        ),
        excluded={
            "SWC-100/108/109/110/111/117/118/119/121/122/123/125/126/127/128/129/130/131/132":
                "落在七类语义之外的 SWC，无对应类目",
        },
    ),
    "manticore": ToolSpec(
        key="manticore", label="Manticore", detector_to_class=MANTICORE_MAP,
        solc_mode=SOLC_MODE_BINARY, timeout_default=300,
        capability=(
            "🔴 **必须 `--thorough-mode`**：非该模式下 CLI 强制 `exclude_all=True`，一个检测器都不跑"
            "（且会撞 finalize() 的判空缺失 bug）。",
            "🔴 **多合约文件必须显式 `--contract`**：实测单文件最多含 19 个 contract/library/interface，"
            "本适配层**逐个合约跑并取并集**（Slither 是按文件整体分析，两者口径在此不同，须披露）。",
            "符号执行，逐合约按时间预算；超时记 `timeout`。",
        ),
        excluded={
            "Potentially reading uninitialized storage": "SWC-109，七类无此语义",
            "Potentially reading uninitialized memory": "SWC-109 同上",
            "INVALID instruction": "执行到 INVALID 指令，无 SWC 锚点",
            "Manipulable balance used in a strict comparison": "无 SWC 锚点（与 SmartCheck "
                "`SOLIDITY_BALANCE_EQUALITY` 同概念，一起排除）",
            "instruction used": "env-instr：环境指令可操纵，无 SWC 锚点",
        },
    ),
    "smartcheck": ToolSpec(
        key="smartcheck", label="Smartcheck", detector_to_class=SMARTCHECK_MAP,
        solc_mode=SOLC_MODE_NONE, timeout_default=120, batch_dir=True,
        capability=(
            "🔴 **走 JVM 自己解析源码，不调用 solc** ⇒ **无 pragma 版本限制**（本轮覆盖面最广的工具）。",
            "`--help` 不是合法参数（会抛 IllegalArgumentException）；用法是 `smartcheck -p <路径>`。",
            "规则表 = 包内 `solidity-rules.xml` 的 40 条 `RuleId`（映射只取其中 11 条，见 `excluded`）。",
        ),
        excluded={
            "SOLIDITY_BALANCE_EQUALITY": "`.balance ==` 无 SWC 锚点（与 manticore `lockdrop` 同概念，一起排除）",
            "SOLIDITY_LOCKED_MONEY": "锁定资金，无 SWC 锚点（Slither 的 `locked-ether` / Securify 的 "
                                     "`LockedEther` 同样未纳入 ⇒ 三个工具一致）",
            "SOLIDITY_OVERPOWERED_ROLE": "角色权限过大，无 SWC 锚点",
            "SOLIDITY_VISIBILITY": "默认可见性（SWC-100）——⚠ **本项是边界情形**：SWC-100 真实存在，"
                                   "但 7 类 `access_control` 的原生语义是「授权/权限控制」而非「可见性声明」，"
                                   "且 Slither/Securify 均无对应项 ⇒ 为跨工具一致而不纳入",
            "其余 27 条": "风格/兼容性/ERC 接口/气体优化类规则，无 SWC 锚点或落在七类之外",
        },
    ),
    "securify": ToolSpec(
        key="securify", label="Securify", detector_to_class=SECURIFY_MAP,
        solc_mode=SOLC_MODE_BINARY, timeout_default=180,
        capability=(
            "🔴 **实测边界（2026-09-25，本池 214 个合约逐条验过；最终跑数）**："
            "**47 个成功里 45 个是 0.5.x、2 个是 0.4.x**（后者语法恰好 0.5 兼容）。"
            "按 pragma 分：**0.5.x 成功 45/46（98%）**、**0.4.x 成功 2/161（1.2%）**、"
            "**无 pragma 成功 0/7** ⇒ 总覆盖 **47/214 = 22.0%**。"
            "⚠ 措辞取「只能吃 0.5.x 的老合约」而非「只吃 ≥0.5.8」——实测成功的 0.5.x 里含 `^0.5.0`/`^0.5.4` 这类 <0.5.8 的。",
            "🔴 **两条失败路径都实测到了**（这是「真的不行」而非「参数没调对」的证据）："
            "① 给 pragma 匹配的 0.4.x solc ⇒ `Solc version X not supported by CFG compiler`"
            "（`ast_dict[_solc_version]` KeyError —— 它的 CFG 语法表里没有 0.4）；"
            "② 给 0.5.12 ⇒ `SyntaxError: No visibility specified` + "
            "`TypeError: Wrong argument count for function call: 0 arguments given but expected 1`"
            "（0.4 语法在 0.5.0+ 非法）。**pragma 改写只改 pragma 行、不升级语法**，故两条路都堵死。",
            "⚠ **`--ignore-pragma` 不要传**：默认的 pragma 改写正是它能吃 0.5.x 老合约的原因"
            "（改写后按它支持的 solc 编译，0.5.x 语法恰好兼容）。",
            "需 `SOUFFLE_BINARY=souffle162` 与 `libfunctors` 的 `LD_LIBRARY_PATH`（见 "
            "`install_traditional_tools.sh`；souffle 2.5 会被 2019 年的 `.dl` 拒收）。",
            "⚠ 它**会改写源码副本**（pragma 替换）⇒ 必须在 `work/` 的副本上跑，绝不能碰只读源。",
        ),
        excluded={
            "Locked Ether": "锁定资金，无 SWC 锚点（与 Slither `locked-ether`、SmartCheck "
                            "`SOLIDITY_LOCKED_MONEY` 一致排除）",
            "Repeated Call to Untrusted Contract": "「重复调用可能返回不同值」无单一 SWC 锚点",
            "Missing Input Validation": "无 SWC 锚点（Slither 的 `missing-zero-check` 亦未纳入）",
            "Dangerous Strict Equalities": "严格相等比较，无 SWC 锚点（Slither `incorrect-equality` 亦未纳入）",
            "Constable State Variables": "可声明为 constant，纯风格问题",
            "External Calls of Functions": "「可标为 external」，纯风格问题",
            "Uninitialized State Variable": "SWC-109 未初始化存储，七类无此语义",
            "Unused State Variable": "无 SWC 锚点",
            "State Variable Shadowing": "无 SWC 锚点",
            "Taint Analysis for PASS Project": "特定项目的污点分析，非本文语料",
        },
    ),
    "oyente": ToolSpec(
        key="oyente", label="Oyente", detector_to_class=OYENTE_MAP,
        solc_mode=SOLC_MODE_FIXED, timeout_default=180,
        capability=(
            "🔴 **solc 钉死 0.4.19**（源码内 tested 版本，env 内的 `solc` shim 保证）⇒ "
            "**0.5.x/0.8.x 的合约一律编译失败**；本轮池里 214 个合约有 161 个是 0.4.x，"
            "故 Oyente 的可分析面**结构性偏向老合约**，这个偏差必须写进行注。",
            "必须在 `~/tools/oyente/oyente` 目录内跑（源码用顶层 import）；"
            "`-s` **必须是绝对路径**（相对路径在 cd 后会解析失败）；`eval` 二进制由 `PATH` 提供。",
            "⚠ 启动时硬检查 `z3.z3util`，故 z3 钉 4.8.17。",
        ),
        excluded={
            "Callstack Depth Attack Vulnerability": "调用深度攻击，**EIP-150 后已不可行**，"
                                                    "且无 SWC 锚点",
        },
    ),
}

# Slither 不在本模块（留在 `baseline_static_tools.py`，其映射与 13 个单测已冻结）。
NON_SLITHER = tuple(TOOLS)


# --------------------------------------------------------------------------- 源码副本
CONTRACT_RE = re.compile(r"^\s*(?:contract|library|interface)\s+([A-Za-z_$][\w$]*)", re.M)


def contract_names(source: Path) -> list[str]:
    """源码里定义的 contract/library/interface 名（manticore 的 `--contract` 要用）。"""
    try:
        text = source.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    seen: list[str] = []
    for name in CONTRACT_RE.findall(text):
        if name not in seen:
            seen.append(name)
    return seen


def stage_source(source: Path, work: Path, tag: str) -> Path:
    """把源码**复制**进 `work/`（只读源目录一个字节都不写）。

    🔴 复制是安全的：本轮 test∪val 的 214 个合约里 **`import` 数为 0**（实测），
    故不存在"相对 import 需要同级兄弟文件"的情形。Slither 的 `--json` 原先写在
    `source.parent`（= `alldata(readonly)/…`）再删掉，瞬时也违规，本轮一并改到这里。
    """
    work.mkdir(parents=True, exist_ok=True)
    dst = (work / f"{tag}__{source.name}").resolve()
    shutil.copy2(Path(source).resolve(), dst)
    return dst


def _run(cmd: list[str], cwd: Path, timeout: int, env: dict | None = None) -> tuple[int, str, str, float]:
    """跑一条命令 → (rc, stdout, stderr, elapsed)。**超时返回 rc=-9**。"""
    t0 = time.time()
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    try:
        p = subprocess.run(cmd, cwd=str(Path(cwd).resolve()), capture_output=True, text=True,
                           timeout=timeout, env=full_env)
        return p.returncode, p.stdout or "", p.stderr or "", round(time.time() - t0, 1)
    except subprocess.TimeoutExpired:
        return -9, "", f"超时 {timeout}s", round(time.time() - t0, 1)
    except (OSError, subprocess.SubprocessError) as exc:      # noqa: BLE001
        return -1, "", f"{type(exc).__name__}: {exc}"[:300], round(time.time() - t0, 1)


# --------------------------------------------------------------------------- 各工具
SC_RULE_RE = re.compile(r"ruleId:\s*([A-Z_0-9]+)")


def run_smartcheck(source: Path, work: Path, solc: Path | None, timeout: int) -> dict:
    """SmartCheck：JVM 解析源码，**不吃 solc**。`-p` 给文件或目录。"""
    rc, out, err, el = _run(["smartcheck", "-p", source.name], cwd=source.parent, timeout=timeout)
    if rc != 0 and not out.strip():
        return {"status": "error", "elapsed": el, "error": tail_msg(err or out) or f"rc={rc}"}
    checks = sorted(set(SC_RULE_RE.findall(_merged(out, err))))
    return {"status": "ok", "elapsed": el, "checks": checks}


MYTH_SWC_RE = re.compile(r"\bSWC\s*ID:?\s*(\d+)\b", re.I)


def run_mythril(source: Path, work: Path, solc: Path | None, timeout: int) -> dict:
    """Mythril：`--solv <版本>`（py-solc-x 从 `~/.solcx` 取，离线）。

    键取 **SWC 编号**（工具自述），比按 issue 标题猜更硬。
    """
    ver = version_of(solc) if solc else ""
    cmd = [str(CONDA / "envs" / "mythril" / "bin" / "myth"),
           "analyze", str(source), "-o", "json", "--no-onchain-data",
           "--execution-timeout", "60"]
    if ver:
        cmd += ["--solv", ver]
    rc, out, err, el = _run(cmd, work, timeout)
    if rc == -9:
        return {"status": "timeout", "elapsed": el, "error": err[:300]}
    # mythril 即便失败也返回 rc=0 且 stdout 是 JSON（"success": false）
    try:
        data = json.loads(out[out.index("{"):out.rindex("}") + 1])
    except (ValueError, json.JSONDecodeError):
        return {"status": "error", "elapsed": el,
                "error": tail_msg(err or out) or f"rc={rc}"}
    if not data.get("success", False):
        return {"status": "error", "elapsed": el, "error": str(data.get("error") or "")[:300]}
    checks: set[str] = set()
    for issue in data.get("issues") or []:
        swc = issue.get("swc-id") or issue.get("swcID") or issue.get("swc_id")
        if swc is None:
            m = MYTH_SWC_RE.search(str(issue.get("title") or ""))
            swc = m.group(1) if m else None
        if swc is not None:
            checks.add(str(swc).strip())
    return {"status": "ok", "elapsed": el, "checks": sorted(checks)}



MAN_FINDING_LINE_RE = re.compile(r"^-\s*(.+?)\s*-\s*$", re.M)


def run_manticore(source: Path, work: Path, solc: Path | None, timeout: int) -> dict:
    """Manticore：**逐个合约**跑（多合约文件必须 `--contract`）→ 取并集。

    🔴 与 Slither「按文件整体分析」不同，这是本工具的能力差异，须在行注披露。
    ⚠ 必须把 env 的 `bin` 加进 PATH（它调的是**外部 z3 可执行文件**）。
    ⚠ **可能返回空集而不报错**：因此存活判据取「stdout 出现 `Total time:`」或
    「workspace 有 `global.summary`」——两者都没有才算失败（原先只看
    `Manticore failed to run` 字样，会让静默失败被记成 `ok` 且零命中）。
    """
    names = contract_names(source) or [None]
    checks: set[str] = set()
    elapsed = 0.0
    statuses: list[str] = []
    errs: list[str] = []
    covered = 0
    for i, name in enumerate(names):
        remaining = timeout - elapsed
        if remaining < MIN_MC_BUDGET:
            # 🔴 **总预算必须在文件级封顶**，否则"单合约下限 × 文件内合约数"会突破它：
            # 本仓实测**单文件最多 19 个** contract/library/interface（全池 719 个定义），
            # 若按"每合约至少 30 s"算，一个文件最坏 570 s —— 是 214 个文件预算的灾难。
            statuses.extend(["skipped"] * (len(names) - i))
            break
        left = len(names) - i
        budget = max(int(remaining / left), MIN_MC_BUDGET)
        ws = (work / f"mc_{source.stem}_{i}").resolve()
        cmd = [str(CONDA / "envs" / "manticore" / "bin" / "manticore"), str(Path(source).resolve()),
               "--thorough-mode", "--workspace", str(ws),
               # 🔴 用 manticore **自带的** `--core.timeout` 而不是外部 kill：
               # 优雅停止会走 finalize() 把 `global.findings` 落盘，外部 SIGKILL 则丢掉全部命中
               # （那会把"跑超时"错记成"零命中"，正是本模块反复在防的那类静默错）。
               "--core.timeout", str(budget)]
        if solc:
            cmd += ["--solc", str(solc)]
        if name:
            cmd += ["--contract", name]
        rc, out, err, el = _run(cmd, work, budget + 30,        # 外层兜底：给 finalize 留 30 s
                                env={"PATH": f"{CONDA / 'envs' / 'manticore' / 'bin'}:{os.environ.get('PATH', '')}"})
        elapsed += el
        merged = _merged(out, err)
        checks |= _manticore_findings(merged, ws)
        alive = ("Total time:" in merged) or (ws / "global.summary").exists()
        if alive:
            statuses.append("ok")
            covered += 1
        elif rc == -9:
            statuses.append("timeout")
        else:
            statuses.append("error")
            errs.append(_manticore_error(merged))
    n_ok = statuses.count("ok")
    res: dict = {"status": "ok" if n_ok else ("timeout" if "timeout" in statuses else "error"),
                 "elapsed": round(elapsed, 1), "checks": sorted(checks),
                 "n_contracts": len(names), "n_covered": covered,
                 "contract_status": statuses}
    if not n_ok and errs:
        res["error"] = errs[0][:300]
    return res


def _manticore_findings(stdout: str, ws: Path) -> set[str]:
    """从 `<workspace>/global.findings` 取描述文本 → 映射到检测项名。

    每条命中形如 `- Reachable SELFDESTRUCT -`。按**长度降序**匹配 `MANTICORE_MAP`
    （`Reentrancy bug` 是 `Reentrancy bug (different method)` 的前缀，短键必须排后面）。
    """
    gf = ws / "global.findings"
    text = ""
    if gf.exists():
        try:
            text = gf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
    if not text:
        text = stdout                       # 兜底：某些版本直接打在输出里
    msgs = MAN_FINDING_LINE_RE.findall(text) or text.splitlines()
    out: set[str] = set()
    for msg in msgs:
        for key in sorted(MANTICORE_MAP, key=len, reverse=True):
            if key in msg:
                out.add(key)
                break
    return out


def _manticore_error(merged: str) -> str:
    """优先给 `Failed to build contract` 行（编译失败的真实错因），否则退回尾部片段。"""
    for line in merged.splitlines():
        if "Failed to build contract" in line:
            return line.strip()[-300:]
    for line in merged.splitlines():
        if "Error" in line and len(line.strip()) > 25:
            return line.strip()[-300:]
    return tail_msg(merged) or "Manticore 未产出 global.summary（静默失败）"


SEC_PATTERN_RE = re.compile(r"^\s*Pattern:\s*(.+?)\s*$", re.M)


def _securify_patterns(stdout: str) -> set[str]:
    """securify2 的命中行形如 `Pattern:     Unused Return Pattern`（**展示名**，见 `SECURIFY_MAP`）。

    🔴 只认 `Pattern:` 行，**不做全文子串匹配**。理由：securify 会把命中的**源码片段**一起打印，
    源码里出现 `call`/`send` 之类的字样是常态，全文匹配会把"源码里有这个词"当成"命中了这个检测项"
    —— 那是纯粹的假阳性，而且不报错。宁可漏，不可编。
    """
    found = set(SEC_PATTERN_RE.findall(stdout))
    return {p for p in found if p in SECURIFY_MAP}


# 已知的**未纳入**检测项（`ToolSpec.excluded` 的键）——出现时必须能在报告里说明，故一并收集。
SEC_UNMAPPED_KNOWN = ("Locked Ether", "Repeated Call to Untrusted Contract",
                      "Missing Input Validation", "Dangerous Strict Equalities",
                      "Constable State Variables", "External Calls of Functions",
                      "Uninitialized State Variable", "Unused State Variable",
                      "State Variable Shadowing", "Taint Analysis for PASS Project")


def run_securify(source: Path, work: Path, solc: Path | None, timeout: int) -> dict:
    """Securify2：`SOLC_BINARY` + `SOUFFLE_BINARY=souffle162` + `libfunctors` 的 LD_LIBRARY_PATH。

    ⚠ 它**会改写源码副本的 pragma** ⇒ 只在 `work/` 的副本上跑。
    ⚠ **不要传 `--ignore-pragma`**：默认的 pragma 改写正是它覆盖 0.4.x 的手段。
    """
    env = {
        "SOUFFLE_BINARY": "souffle162",
        "LD_LIBRARY_PATH": f"{TOOLS_DIR / 'securify2' / 'securify' / 'staticanalysis' / 'libfunctors'}"
                           f":{os.environ.get('LD_LIBRARY_PATH', '')}",
    }
    if solc:
        env["SOLC_BINARY"] = str(solc)
    rc, out, err, el = _run([str(CONDA / "envs" / "securify" / "bin" / "python"), "-m", "securify",
                             source.name], cwd=source.parent, timeout=timeout, env=env)
    if rc == -9:
        return {"status": "timeout", "elapsed": el, "error": err[:300]}
    checks = _securify_patterns(_merged(out, err))
    if not checks and rc != 0:
        return {"status": "error", "elapsed": el,
                "error": tail_msg(err or out) or f"rc={rc}"}
    return {"status": "ok", "elapsed": el, "checks": sorted(checks)}


def _securify_patterns_legacy_removed() -> None:
    """占位：旧的"按类名全文 grep"实现在 2026-09-25 被删——它对 securify **恒返回空集**
    （展示名 ≠ 类名），会把每个合约记成"零命中"且不报错。见 `SECURIFY_MAP` 上方的说明。"""


def run_oyente(source: Path, work: Path, solc: Path | None, timeout: int) -> dict:
    """Oyente：必须在 `~/tools/oyente/oyente` 内跑；`-s` 用绝对路径；`eval` 由 PATH 提供。

    🔴 solc 钉死 0.4.19（env 内 shim），**不接受候选** —— 这是工具能力边界，不是配置疏漏。
    """
    oy_dir = TOOLS_DIR / "oyente" / "oyente"
    env = {"PATH": f"{CONDA / 'envs' / 'oyente' / 'bin'}:{GETH_BIN}:{os.environ.get('PATH', '')}"}
    rc, out, err, el = _run([str(CONDA / "envs" / "oyente" / "bin" / "python"), "oyente.py",
                             "-s", str(Path(source).resolve()), "-t", "60"],
                        cwd=oy_dir, timeout=timeout, env=env)
    if rc == -9:
        return {"status": "timeout", "elapsed": el, "error": err[:300]}
    # oyente 把结果同时打成文本与 JSON 片段；编译失败时 stdout 为空、stderr 有 CryticCompile
    checks = _oyente_checks(_merged(out, err))
    if not checks:
        if "does not exist" in err or "CryticCompile" in err or "Compilation" in (err + out):
            return {"status": "error", "elapsed": el, "error": _oyente_error(err or out)}
        if not out.strip():
            return {"status": "error", "elapsed": el, "error": (err or out).strip()[-300:] or f"rc={rc}"}
    return {"status": "ok", "elapsed": el, "checks": sorted(checks)}


def _oyente_checks(stdout: str) -> set[str]:
    """oyente 的 6 项检查 —— 🔴 **必须连值一起解析，不能只认名字**。

    实测（2026-09-25）：oyente 的结果块把**全部 8 个检查名都打印出来**，每个后面跟 True/False：

        INFO:symExec:\t  Integer Underflow: \t\t\t True
        INFO:symExec:\t  Integer Overflow: \t\t\t False
        INFO:symExec:\t  Re-Entrancy Vulnerability: \t\t False

    只匹配名字的后果**不是报错而是"全亮"** —— 每个合约六个类全部置 1，
    Oyente 那一行会变成"一律报有漏洞"（micro-F1 看起来还很"高"，因为正例多）。
    这是本模块第四个"不报错的错"，也是最危险的一个：它不会让任何东西崩，只会让一行数字全是假的。
    ⚠ **只认这一种形态**：oyente 源码里的 `integer_overflow`/`integer_underflow` 是**内部字典键**，
    从不出现在打印结果里 —— 为它们写解析分支属"编"，按本仓「宁可漏，不可编」不写。
    """
    found: set[str] = set()
    for key in OYENTE_MAP:
        if re.search(rf"{re.escape(key)}\s*:\s*(True|true)\b", stdout):
            found.add(key)
    return found


def _oyente_error(text: str) -> str:
    """优先给 `ERROR` 行；🔴 取不到就退回**尾部片段**——不能取"最后一行"，
    实测最后一行往往是源码回显或文件路径（路径还可能被截成半截），把真正的错因挤掉。"""
    for line in text.splitlines():
        if "ERROR" in line or "Error" in line:
            if len(line.strip()) > 20:                     # 跳过只剩路径的残行
                return line.strip()[-300:]
    return tail_msg(text)


RUNNERS = {
    "mythril": run_mythril,
    "manticore": run_manticore,
    "smartcheck": run_smartcheck,
    "securify": run_securify,
    "oyente": run_oyente,
}


def run_tool(spec: ToolSpec, source: Path, work: Path, tag: str,
             solc: Path | None = None) -> dict:
    """分派到具体工具。`source` 必须是 `work/` 里的副本（调用方负责 stage）。"""
    fn = RUNNERS[spec.key]
    if spec.solc_mode == SOLC_MODE_NONE:
        return fn(source, work, None, spec.timeout_default)
    return fn(source, work, solc, spec.timeout_default)
