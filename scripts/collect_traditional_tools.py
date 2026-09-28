#!/usr/bin/env python3
"""5.3 六个传统工具的**报告生成器**（大纲 `改II` 5.3；2026-09-25）。

**为什么单独出一份报告**：`scripts/collect_baseline_tables.py` 已经把六个工具拼进
`experiments/baseline_three_caliber_tables.md` 的对比表，但对比表放不下三样东西，
而这三样**恰好是读那六行数字的前提**：

  1. **检测项 → 七类的映射表**（逐条带 SWC 依据）—— 没有它，读者无从判断
     「某一类为 0」是工具没这个检测项、还是模型/映射的问题；
  2. **能力边界**（solc 版本面、是否符号执行、多合约如何处理）—— 决定覆盖率为什么是那个数；
  3. **覆盖率与成本**（`n_analyzed/n_in_split`、单合约预算、status 分布）——
     §47.4 明确要求「先统计各工具可分析合约数并写进行注」，否则
     「工具跑不了」会被误读成「工具说没漏洞」，那是**系统性偏差**。

🔴 **本文件是程序生成物，一律改本脚本、不手改**（本仓既有约定）。

用法（从仓库根目录）：
  python scripts/collect_traditional_tools.py                 # 写 experiments/traditional_tools_results.{md,json}
  python scripts/collect_traditional_tools.py --out ""        # 只打印
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics                                    # noqa: E402  只调既有实现，不重写指标
import static_tool_adapters as STA                # noqa: E402  能力边界的**唯一真源**

NAMES = list(metrics.VULN_NAMES)
# 显示名。🔴 Slither 的产物是 2026-09-21 写的，**没有 `tool_label` 字段**（旧格式），
# 故必须有这张兜底表，否则它在报告里会显示成小写的 `slither`。
LABELS = {"slither": "Slither", "mythril": "Mythril", "manticore": "Manticore",
          "smartcheck": "Smartcheck", "securify": "Securify", "oyente": "Oyente"}
SEEDS = (0, 1, 2)
BASE = REPO / "eval_results" / "baseline"

# 🔴 **Slither 的范围与其余五个不同**（2026-09-25 实测）：它是 2026-09-21 跑的，
# 覆盖 `products/alldata/graphs` 的**全部 590 个**图；其余五个只在
# 「三种子 val∪test 的并集 = 214 个合约」上跑（成本：六个工具的逐合约预算见下）。
# 这不是疏漏而是成本决策，必须显式披露——否则覆盖率一栏看起来像"某工具更差"。
SLITHER_SCOPE = "全量 590 图（`products/alldata/graphs`）"
NEW_SCOPE = "三种子 val∪test 并集 214 个合约"

# 逐工具的调用口径要点（与 `scripts/static_tool_adapters.py` 的 `capability` 同源，
# 这里只留"进论文行注"的那一句）。
SOLC_NOTE = {
    "slither": "按源码 pragma 选 solc，候选序列逐个重试（上限 8）",
    "mythril": "`--solv` 由 pragma 决定（py-solc-x 从本机 `~/.solcx` 取，**离线**）；候选上限 3",
    "manticore": "`--solc` 由 pragma 决定；**逐合约**跑（多合约文件必须 `--contract`），候选上限 3",
    "smartcheck": "**不用 solc**（JVM 自己解析源码）⇒ 无 pragma 版本限制",
    "securify": "`SOLC_BINARY` 指它支持的版本；**会自动改写 pragma 但只改 pragma 行、不升级语法**",
    "oyente": "solc **钉死 0.4.19**（env 内 shim），不吃候选 ⇒ 0.5+/0.8 源码编译失败",
}


def live_spec(tool: str):
    """🔴 能力边界/排除项/不提供的类一律**以活代码为准**（`static_tool_adapters.TOOLS`），
    产物里那份是**写出时的快照**。理由：本轮实测更正了两次能力边界（securify 的
    0.4.x 结论、SmartCheck 缺 reentrancy），若报告读快照，**报告会与代码说的不一致**
    且看不出来——这正是本仓反复在防的那类静默漂移。产物快照仍保留，供审计"当时是怎么写的"。"""
    return STA.TOOLS.get(tool)


def spec_of(tool: str, raw_d: dict, field: str):
    """取活代码的值；活代码没有该工具（如 Slither）时退回产物快照。"""
    sp = live_spec(tool)
    if sp is not None:
        return getattr(sp, field)
    return raw_d.get(field)


def load_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def tool_names() -> list[str]:
    """有原始产物的工具（按大纲 5.3 的顺序）。"""
    order = ("slither", "mythril", "manticore", "smartcheck", "securify", "oyente")
    return [t for t in order if (BASE / f"{t}_alldata.json").exists()]


def fmt(vals: list[float]) -> str:
    v = [x for x in vals if x is not None]
    if not v:
        return "—"
    if len(v) == 1:
        return f"{v[0]:.4f}"
    return f"{statistics.mean(v):.4f} ± {statistics.stdev(v):.4f}"


def section_scope(raw: dict[str, dict]) -> list[str]:
    lines = [
        "## 一、范围与口径（**读任何数字之前先读这一节**）",
        "",
        "| 项 | 值 |",
        "| --- | --- |",
        "| 语料 | §37 正典池 **453**（`products/alldata/graphs`，含 `buggy_*` 共 590 图） |",
        "| 划分 | `products/alldata/splits/split_seed{0,1,2}.json`（8:1:1 覆盖约束校正） |",
        "| 评测工作点 | **只有一个**：固定 0.5。传统工具是确定性规则，**没有阈值可搜**，"
        "故不存在 `@val_thr` 那一列 |",
        "| 指标 | `micro_f1` / `macro_f1` / `逐类 F1`，全部调 `scripts/metrics.py`（三个基线同一份实现） |",
        f"| Slither 的跑动范围 | {SLITHER_SCOPE} |",
        f"| 其余五工具的跑动范围 | {NEW_SCOPE} |",
        "",
        "🔴 **两条必须随数字一起读的口径**：",
        "",
        "1. **分母只有「成功分析」的合约**：编译失败／超时／不支持的合约记 `error`/`timeout`，",
        "   **不计入分母、也不记成全零预测**。记成全零等于把「工具跑不了」算成「工具说没漏洞」，",
        "   那是系统性压低 FP、抬高 F1 的偏差。每行的实际分母见第三节。",
        "2. **映射是人为规定的**：工具输出的是各自的检测项名，本仓的七类是 MVD-HG 的类目，",
        "   二者**没有官方对照表**。映射尺子见第二节，每条都给出 SWC 编号作为可核对的依据。",
        "",
        "> ⚠ **禁止跨行比较「某一类为 0」**：那可能是**该工具不提供此检测项**（映射/能力的边界），",
        "> 而不是「该工具在此类上 F1=0」。第二节的「未纳入」清单与第三节的「不提供的类」是判据。",
        "",
    ]
    return lines


def section_mapping(raw: dict[str, dict]) -> list[str]:
    lines = ["## 二、检测项 → 七类映射（**同一把尺**）", "",
             "尺子（六个工具一致）：**一个检测项进入七类，当且仅当它有唯一且明确的 SWC 锚点，"
             "且该 SWC 落在七类语义内**。无锚点者一律不纳入——宁可漏，不可编。", ""]
    for tool, d in raw.items():
        label = d.get("tool_label") or LABELS.get(tool, tool)
        mp = spec_of(tool, d, "detector_to_class") or {}
        lines += [f"### 2.{list(raw).index(tool) + 1} {label}（纳入 {len(mp)} 项）", "",
                  "| 检测项（工具原生写法） | → 类 |", "| --- | --- |"]
        # 按类分组，同类的排在一起，便于和第七节的逐类 F1 对照
        for cls in NAMES:
            items = [k for k, v in mp.items() if v == cls]
            for k in items:
                lines.append(f"| `{k}` | {cls} |")
        exc = spec_of(tool, d, "excluded") or {}
        if exc:
            lines += ["", f"**未纳入但可能被观察到（{len(exc)} 条）**：", ""]
            for k, why in exc.items():
                lines.append(f"- `{k}` —— {why}")
        lines.append("")
    return lines


def section_coverage(raw: dict[str, dict]) -> list[str]:
    lines = ["## 三、能力边界与覆盖率（§47.4 要求随表披露）", "",
             "| 工具 | solc 口径 | 覆盖率（三种子 test，`n_analyzed/n_in_split`） | 状态分布（全部跑动的合约） |",
             "| --- | --- | --- | --- |"]
    for tool, d in raw.items():
        label = d.get("tool_label") or LABELS.get(tool, tool)
        covers = []
        for s in SEEDS:
            e = load_json(BASE / f"{tool}_alldata" / f"seed{s}_eval.json")
            if e:
                t = e["test"]
                covers.append(f"{t['n_analyzed']}/{t['n_in_split']}")
        st = d.get("status_counts") or {}
        st_s = "、".join(f"{k} {v}" for k, v in sorted(st.items(), key=lambda x: -x[1]))
        lines.append(f"| **{label}** | {SOLC_NOTE.get(tool, '—')} | {'、'.join(covers) or '—'} | {st_s} |")
    lines += ["", "**能力边界（逐工具，进论文行注）**：", ""]
    for tool, d in raw.items():
        label = d.get("tool_label") or LABELS.get(tool, tool)
        cap = spec_of(tool, d, "capability") or []
        if not cap:
            continue
        lines.append(f"- **{label}**：")
        for c in cap:
            lines.append(f"  - {c}")
    # 不提供检测项的类
    nd = {t: list(spec_of(t, d, "no_detector_classes") or []) for t, d in raw.items()}
    if any(nd.values()):
        lines += ["", "**该工具不提供检测项、恒为 0 的类**（不得读成「在此类上 F1=0」）：", ""]
        for t, cs in nd.items():
            lines.append(f"- **{raw[t].get('tool_label') or LABELS.get(t, t)}**："
                         f"{'、'.join('`'+c+'`' for c in cs) if cs else '**（无——七类都有对应检测项）**'}")
        lines.append("")
        lines.append("> ⚠ **上表与「能分析几个合约」是两件事**：`Securify` 七类都有检测项，"
                     "但它的**可分析合约只有 15%（pragma 0.5.x）** ⇒ 它的行是"
                     "「检测项齐全、但只在少数合约上跑得出来」；`Smartcheck` 反之"
                     "（**全部 214 个合约都能分析**，但**没有 reentrancy 规则**）。"
                     "前者影响**分母**，后者影响**某一类恒为 0** —— 读表时必须分开看。")
    lines += ["", "> ⚠ **`front_running` 是重灾区**：Slither 0.11.5 的 100 个检测器里没有任何一个覆盖 "
              "SWC-114（Transaction Order Dependence）。凡该工具不提供此检测项，其 F1 恒为 0，"
              "论文里必须写成「**该工具不提供此检测项**」，不得写成「该工具在此类上 F1=0」。", ""]
    return lines


def no_detector_idx(tool: str, raw_d: dict | None = None) -> set[int]:
    """该工具**不提供检测项**的类下标（`front_running` 是重灾区）。

    🔴 **唯一真源**（与本模块既有的 `spec_of` 同源，不另写清单）：
    活代码 `static_tool_adapters.TOOLS[tool].no_detector_classes` 优先（它是**从映射表派生的差集**，
    见那里的 docstring），Slither 不在活代码里 ⇒ 退回产物 JSON 的 `no_detector_classes` 快照。

    ⚠ 与「该切分里 support=0」是**两件不同的事**，别混：
      · 本函数 = **工具没这项能力**（F1 恒 0，且**永远**不会有值）；
      · support=0 = **这个切分里没有该类正样本**（换个划分就可能有了）。
    两者在表里都画 `—`，判据分别见「交叉表」与「支持度表」。
    """
    d = raw_d if raw_d is not None else (load_json(BASE / f"{tool}_alldata.json") or {})
    miss = set(spec_of(tool, d, "no_detector_classes") or [])
    return {i for i, n in enumerate(NAMES) if n in miss}


GRAPH_DIR = REPO / "products" / "alldata" / "graphs"
SPLIT_DIR = REPO / "products" / "alldata" / "splits"
_INDEX_CACHE: dict = {}


def _labels_index() -> dict:
    """`base → 七维标签`（与 `baseline_static_tools.evaluate()` **同一句** `dataset.build_index`）。"""
    if "idx" not in _INDEX_CACHE:
        import dataset                                  # 只在真要算覆盖类口径时才 import（重）
        _INDEX_CACHE["idx"] = dataset.build_index(GRAPH_DIR, None, None)[0]
    return _INDEX_CACHE["idx"]


def covered_metrics(tool: str, raw_d: dict | None = None) -> dict[int, dict]:
    """**仅该工具有检测项的类**上的 micro/macro（用户 2026-09-26 要求）。

    为什么要有第二个口径：逐类格把「工具没有这项能力」画成 `—` 之后，`micro`/`macro` 若仍按
    七类聚合，就等于**替工具在它压根没有的能力上扣分**——那些格的 0 是结构性的，不是"测出来的"。

    ⚠ **两个口径都保留**（表里并排）：全七类口径 = "该工具作为七类检测器"的真实读数，与本文方法
      和三条基线**可比**；仅覆盖类口径回答"它在自己声称能做的范围内有多好"。**二者不可互相替代**，
      论文要引用哪一个必须写明——只给后者会**系统性抬高**每个工具。

    实现上**从标签与原始预测重算**（不解析产物里的 P/R 快照——`precision=0` 时反推不出 FP 计数）。
    逐类独立 ⇒ 切列后直接调 `metrics.micro_f1` / `macro_f1`。
    🔴 **自检**：切列前的重算值必须与产物 `seed{S}_eval.json` 的 `micro_f1` 逐位相等，
    否则说明标签对不齐 ⇒ **直接拒绝出数**（本仓"静默给个数"的教训已经够多）。
    """
    import numpy as np
    d = raw_d if raw_d is not None else (load_json(BASE / f"{tool}_alldata.json") or {})
    contracts = d.get("contracts") or {}
    miss = no_detector_idx(tool, d)
    keep = [i for i in range(len(NAMES)) if i not in miss]
    idx = _labels_index()
    out: dict[int, dict] = {}
    for s in SEEDS:
        sp, ev = load_json(SPLIT_DIR / f"split_seed{s}.json"), \
            load_json(BASE / f"{tool}_alldata" / f"seed{s}_eval.json")
        if not sp or not ev:
            continue
        rows = [(b, idx[b]) for b in sp["test"]
                if b in idx and contracts.get(b, {}).get("status") == "ok"]
        if not rows:
            continue
        y = np.array([lab for _, lab in rows])
        p = np.array([contracts[b]["classes"] for b, _ in rows])
        ref = ev["test"].get("micro_f1")
        m7 = metrics.micro_f1(y, p)
        if ref is not None and abs(m7 - ref) > 1e-6:
            raise SystemExit(f"🔴 {tool} seed{s}：重算 micro={m7} 与产物 {ref} 不一致"
                             "（标签对不齐）—— 拒绝出数")
        if len(keep) >= 2:
            out[s] = {"micro": metrics.micro_f1(y[:, keep], p[:, keep]),
                      "macro": metrics.macro_f1(y[:, keep], p[:, keep])}
        else:   # 单类：micro ≡ macro ≡ 该类的 F1（切成一列会撞 `_as_2d_multilabel` 的 [N,1] 守卫）
            f1s = [ev["test"]["per_class_f1"][i] for i in keep]
            out[s] = {"micro": f1s[0] if f1s else None, "macro": f1s[0] if f1s else None}
    return out


def no_eval_tools(raw: dict[str, dict]) -> list[str]:
    """有**原始产物**（`<工具>_alldata.json`）但**一个 `seed{S}_eval.json` 都没有**的工具。

    🔴 为什么必须单独点名：它那一行在第四节也是全 `—`，**与「不可评估」长得一模一样**，
    但成因相反——前者是**还没评测**（跑一次 `--eval-only` 就有了），后者是**评测了但没有正样本**。
    不点名就会把「没跑完」读成「工具不行」。
    """
    return [t for t in raw
            if not any((BASE / f"{t}_alldata" / f"seed{s}_eval.json").exists() for s in SEEDS)]


def degenerate_tools(raw: dict[str, dict]) -> dict[str, str]:
    """🔴 **test 划分里逐类 support 全为 0 的工具** —— 它们那一行**不可评估**。

    为什么必须自动检测而不是靠人看：`micro_f1` 在这种情况下算出的是 **0.0**，
    与"工具预测得全错"**看起来一模一样**，但含义相反——
    后者是工具的结论，前者是**分母里压根没有正样本**（评测本身无信息量）。
    本仓既有约定是"分母不同要披露"（`slither_row` 的 docstring），这里把那条推到极端情形并**机检**。
    """
    out: dict[str, str] = {}
    for tool in raw:
        sup: list[int] = []
        for s in SEEDS:
            e = load_json(BASE / f"{tool}_alldata" / f"seed{s}_eval.json")
            if e:
                sup.append(sum(e["test"].get("per_class_support") or []))
        if sup and all(x == 0 for x in sup):
            out[tool] = "、".join(str(x) for x in sup)
    return out


def section_metrics(raw: dict[str, dict]) -> list[str]:
    lines = ["## 四、逐类 F1（固定 0.5，三种子 mean ± std）", "",
             "| 工具 | " + " | ".join(f"`{n}`" for n in NAMES) + " | micro | macro | micro† | macro† |",
             "| --- | " + " | ".join("---" for _ in NAMES) + " | --- | --- | --- | --- |"]
    deg = degenerate_tools(raw)
    dropped: dict[str, dict[str, list[int]]] = {}      # 裁定 A：被剔除的 (工具, 类, 种子)
    for tool, d in raw.items():
        label = d.get("tool_label") or LABELS.get(tool, tool)
        # 🔴 ① **整行不可评估**（该切分里逐类 support 全 0）⇒ 全行 `—`，**不写 0.0000**：
        #    `zero_division=0` 会把它算成 0，与「预测全错」长得一样而含义相反。
        if tool in deg:
            lines.append(f"| **{label}** | " + " | ".join(["—"] * (len(NAMES) + 4)) + " |")
            continue
        # 🔴 ② **工具不提供该检测项**的类直接画 `—`（用户 2026-09-26 裁定）：
        #    那一格的 0 是"工具没有这项"，不是"测出来是 0"——不画成数字就不必再靠注释提醒。
        miss = no_detector_idx(tool, d)
        per = {n: [] for n in NAMES}
        micros, macros = [], []
        for s in SEEDS:
            e = load_json(BASE / f"{tool}_alldata" / f"seed{s}_eval.json")
            if not e:
                continue
            t = e["test"]
            micros.append(t.get("micro_f1"))
            macros.append(t.get("macro_f1"))
            sup = t.get("per_class_support") or []
            for i, (n, v) in enumerate(zip(NAMES, t.get("per_class_f1") or [])):
                if i in miss:
                    continue
                # 🔴 **裁定 A（2026-09-26 用户裁定）**：该种子该类 **support=0 ⇒ F1 是 0/0 未定义**，
                # 被 `zero_division=0` 记成 `0.0`。把它当「报错了」计入均值，是把「没有样本可评」
                # 当成「预测失败」——两者含义相反。⇒ **剔除该种子**（不是置 0），并在表里标 `‡`。
                if i < len(sup) and sup[i] == 0:
                    dropped.setdefault(tool, {}).setdefault(n, []).append(s)
                    continue
                per[n].append(v)
        cov = covered_metrics(tool, d)
        mark = {n: "‡" for n in (dropped.get(tool) or {})}
        lines.append(f"| **{label}** | " + " | ".join(fmt(per[n]) + mark.get(n, "") for n in NAMES)
                     + f" | {fmt(micros)} | {fmt(macros)}"
                     + f" | {fmt([v['micro'] for v in cov.values()])}"
                     + f" | {fmt([v['macro'] for v in cov.values()])} |")
    # 🔴 **"谁在哪些类上压根没有检测项"一览**：直接回答「表里那个 0 是"工具不行"还是"工具没有这项"」。
    # 全自动：从各工具的映射表取差集（`no_detector_classes`），不与任何手写清单耦合。
    lines += ["",
              "> 🔴 **上表的 `—` 有两种判据，读法不同**（两种都**不写 0.0000**，因为那样会被读成成绩）：",
              "> ① **`—`（能力缺失）**= 该工具**不提供**此检测项 ⇒ 见下面这张交叉表的 `✗`；",
              "> ② **`—`（整行）**= 该划分里**逐类 support 全为 0** ⇒ 该行**不可评估**（见下方 warning）。",
              "> 二者与「工具跑了但没检出」**都不是一回事**——后者才是真正带信息量的 0（如 Slither 的 "
              "`arithmetic`/`dos`：有检测项、support>0、确实一个没报对）。",
              "> ⚠ **`micro` / `macro`（不带 †）不因 `—` 而改变**：它们仍按**七类全量**聚合"
              "（即把该工具结构性检测不到的那些类计入漏检）——这是一把尺下「该工具作为七类检测器」的"
              "真实读数，**与本文方法、三条基线可比**。",
              "> ",
              "> 🔴 **带 † 的两列 = 「仅该工具有检测项的类」上的 micro / macro**（用户 2026-09-26 要求）："
              "把上表画 `—` 的类**从分母里去掉**再算，回答「它在自己声称能做的范围内有多好」。"
              "**两列口径不可互相替代**：",
              "> - 不带 † 的是**对比用**读数（工具与模型在同一张表里必须同口径）；",
              "> - 带 † 的**只描述工具自身的覆盖范围**，它**系统性偏高**（分母小了），"
              "**不得**拿去和本文方法、三条基线的 micro/macro 横比——那是拿 5 类的分母比 7 类的分母。",
              "> ⚠ 覆盖 7/7 类的工具（Mythril、Securify）两列**必然逐位相同**；"
              "Securify 两列都是 `—`（整行不可评估，见下）。"
              "算法：从标签与原始预测切列重算（`covered_metrics()`），"
              "切列前的重算值与产物存档逐位对拍不符即**拒绝出数**。",
              "", "**交叉表：`✗` = 该工具**不提供**此检测项（**表中该格已画 `—`**）；"
              "`·` = 有检测项**：", "",
              "| 工具 | " + " | ".join(f"`{n}`" for n in NAMES) + " |",
              "| --- | " + " | ".join("---" for _ in NAMES) + " |"]
    for tool, d in raw.items():
        miss = set(spec_of(tool, d, "no_detector_classes") or [])
        cells = ["✗" if n in miss else "·" for n in NAMES]
        lines.append(f"| **{d.get('tool_label') or LABELS.get(tool, tool)}** | " + " | ".join(cells) + " |")
    lines.append("")
    if dropped:
        # 🔴 标出来而不是悄悄剔除：`0.5000 ± 0.7071` 与 `0.3333 ± 0.5774` 都是「看起来正常」的数，
        # 读者**无法**从格子里看出前者只有 2 个种子。故加 `‡` 并逐格列出。
        items = []
        for tool, cls in dropped.items():
            label = raw[tool].get("tool_label") or LABELS.get(tool, tool)
            for n, ss in cls.items():
                items.append(f"**{label}** 的 `{n}`（缺 seed{'/'.join(str(x) for x in ss)}）")
        lines += ["", "> ‡ **该格不是 3 种子均值**：列出的种子在该类上 **support=0**"
                  "（F1 是 0/0 未定义，`zero_division=0` 会记成 0.0）⇒ 按用户 2026-09-26 裁定 **剔除**，"
                  "不当成「预测失败」计入。受影响：" + "、".join(items)
                  + "。其余各格均为 3 种子。"
                  "⚠ `micro`/`macro` 两列**仍按全量口径**（含零支撑类）——那是全仓统一实现"
                  "（`metrics.macro_f1`，本文方法与三条基线同理），改它会动到所有已报告数字。", ""]
    noev = no_eval_tools(raw)
    if noev:
        lines += ["", "> 🔴 **第三种 `—`：尚未评测** —— "
                  + "、".join(f"**{raw[t].get('tool_label') or LABELS.get(t, t)}**" for t in noev)
                  + " 有原始产物（`<工具>_alldata.json`）但**没有 `seed{S}_eval.json`** ⇒ 第四节整行为 `—`。"
                    "这与上一条「不可评估」**成因相反**：跑一次 "
                    "`python scripts/baseline_static_tools.py --tool <名> --eval-only` 就有数了，"
                    "**不得**读成「该工具测出来是 0」。", ""]
    if deg:
        lines += ["", "> 🔴🔴 **warning：下列工具在 test 划分里「逐类 support 全为 0」⇒ 该行不可评估**", ">"]
        for tool, sup in deg.items():
            label = raw[tool].get("tool_label") or LABELS.get(tool, tool)
            lines += [f"> - **{label}**：三种子 test 的正样本合计 = {sup} ⇒ **第四节该行已全部画 `—`**"
                      f"（**不是**它跑了得到 0，而是**分母里没有正样本**）——"
                      f"底层 `micro_f1` 落在产物里是 `0.0`，那是 `zero_division=0` 的占位，**不可引用**。", ">"]
        lines += ["> ⚠ 论文里这一格**不能写 F1=0**，必须写「**该工具在本语料上可分析的合约集"
                  "与 test 的漏洞合约集不相交，故在 test 上不可评估**」，并给出覆盖率与 pragma 分布作依据。", ""]
    lines += ["", "支持度（三种子 test 的逐类正样本数，**各行分母可能不同**）：", "",
              "| 工具 | " + " | ".join(f"`{n}`" for n in NAMES) + " |",
              "| --- | " + " | ".join("---" for _ in NAMES) + " |"]
    for tool in raw:
        d = raw[tool]
        e = next((load_json(BASE / f"{tool}_alldata" / f"seed{s}_eval.json") for s in SEEDS
                  if (BASE / f"{tool}_alldata" / f"seed{s}_eval.json").exists()), None)
        if not e:
            continue
        sup = e["test"].get("per_class_support") or []
        lines.append(f"| **{d.get('tool_label') or LABELS.get(tool, tool)}** | " + " | ".join(str(x) for x in sup) + " |")
    return lines


def section_missing_not_at_random(raw: dict[str, dict]) -> list[str]:
    """🔴🔴 **覆盖率不是随机缺失** —— 每个工具的「能分析 / 不能分析」两集，**标签分布完全不同**。

    为什么这是必读而不是花边：对比表里传统工具的行都带一个"分母不同"的脚注，读者容易以为
    缺失是**随机的**（随机缺失只影响精度、不影响无偏性）。实测不是：

      · Securify 只吃 **pragma 0.5.x**；而本池**所有漏洞合约都在 0.4.x**（0.5.x 一个都没有）
        ⇒ 它的可分析集**恰好全是干净合约** ⇒ test 上 support 恒为 0 ⇒ **那一行不可评估**；
      · Oyente 钉 **solc 0.4.19** ⇒ 可分析面**正好落在漏洞所在的 0.4.x** ⇒ 它是唯一有公平机会的。

    ⇒ 结论必须写成「**这几个工具的覆盖率与标签强相关，故其行不可与本文方法直接横比**」，
    **不能**只写"分母不同"。本节数值全部现算（`dataset.build_index` + `parse_pragma`）。
    """
    import collections
    gd = REPO / "products" / "alldata" / "graphs"
    try:
        import dataset
        from make_splits import source_path_of
        from baseline_static_tools import parse_pragma
        index, _ = dataset.build_index(gd, None, None)
    except Exception:                                             # noqa: BLE001
        return []
    # 🔴 编号必须与 `build()` 的拼装顺序一致（本节在「成本」之前拼）——2026-09-26 修：
    # 原先本节标题写 六、而拼在 五、成本 之前，成品里章节序为 四 → 六 → 五。
    lines = ["## 五、🔴 覆盖率**不是**随机缺失（读对比表前必读）", "",
             "每个工具把**它自己跑动的合约集**（Slither = 590 全库；其余五个 = 214 并集）"
             "切成「能分析 / 不能分析」两集，两集的**漏洞比例**：", "",
             "| 工具 | 能分析：合约数 / 含漏洞 | 不能分析：合约数 / 含漏洞 | 该工具的 pragma 面 |",
             "| --- | --- | --- | --- |"]
    pragma_of: dict[str, str] = {}
    for tool, d in raw.items():
        cs = d.get("contracts") or {}
        a = [b for b, v in cs.items() if v.get("status") == "ok" and b in index]
        n = [b for b, v in cs.items() if v.get("status") != "ok" and b in index]
        if not a:
            continue
        va = sum(1 for b in a if any(index[b]))
        vn = sum(1 for b in n if any(index[b])) if n else 0
        # 该工具能分析的合约的 pragma 主版本分布
        dist: collections.Counter = collections.Counter()
        for b in a:
            try:
                sp = parse_pragma(source_path_of(b, gd))
            except FileNotFoundError:
                continue
            dist["无pragma" if not sp else f"{sp[0][1][0]}.{sp[0][1][1]}.x"] += 1
        pm = "、".join(f"{k} {v}" for k, v in dist.most_common(3)) or "—"
        pragma_of[tool] = pm
        lines.append(f"| **{d.get('tool_label') or LABELS.get(tool, tool)}** | {len(a)} / **{va}**"
                     f"（{va / len(a) * 100:.0f}%） | {len(n)} / {vn}"
                     f"（{(vn / len(n) * 100) if n else 0:.0f}%） | {pm} |")
    # 漏洞与 pragma 的关系 —— 🔴 **必须分「真实池 / `buggy_*` 合成注入族」两栏**。
    # 不分栏会把两件相反的事混成一句错话：全库口径下 0.5.x 有 35% 含漏洞，
    # 而**那 35% 全部是 `buggy_*`**（100% 正例的合成注入，且**不在池 453 的划分里**）。
    # 真实池的口径才是本节要的那个事实：**自然语料里「有漏洞 ⟺ 0.4.x」是完美分离**。
    lines += ["", "**核心事实（全库 590 图，现算；🔴 必须分族看）**：", "",
              "| 族 | pragma 主版本 | 合约数 | 其中含漏洞 | 比例 |", "| --- | --- | --- | --- | --- |"]
    for fam, key in (("**真实池**", lambda b: "buggy_" not in b),
                     ("`buggy_*`（合成注入）", lambda b: "buggy_" in b)):
        for maj in ("0.4.x", "0.5.x", "无pragma"):
            tot = vul = 0
            for b in index:
                if not key(b):
                    continue
                try:
                    sp = parse_pragma(source_path_of(b, gd))
                except FileNotFoundError:
                    continue
                m = "无pragma" if not sp else f"{sp[0][1][0]}.{sp[0][1][1]}.x"
                if m != maj:
                    continue
                tot += 1
                vul += bool(any(index[b]))
            if tot:
                lines.append(f"| {fam} | {maj} | {tot} | {vul} | {vul / tot * 100:.0f}% |")
    lines += ["", "🔴 **上表两族必须分开读，合起来会得出相反的结论**：",
              "· **真实池**：0.4.x 有 38% 含漏洞，**0.5.x 与无 pragma 的合约一个漏洞都没有** —— "
              "自然语料里「有漏洞 ⟺ 0.4.x」是**完美分离**（128 vs 0）；",
              "· **`buggy_*`**：**100% 正例的合成注入族**（0.5.x 那 80 个 0.5 漏洞全在这里），"
              "而它**不在池 453 的划分里**（`dataset.exclude_buggy`）⇒ 与 5.3 的对比表无关。",
              "",
              "⇒ 对本报告涉及的工具，结论是：**Securify（只吃 0.5.x）的可分析集在真实池里"
              "恰好全是干净合约 ⇒ 它的行在 test 上结构性不可评估；Oyente（钉 0.4.19）的可分析面"
              "正好落在漏洞所在的 0.4.x ⇒ 它是唯一有公平机会的**。",
              "凡引用这几行，必须同时给出覆盖率与本节的分集漏洞率；"
              "**不能只写「分母不同」**（那会让读者以为缺失是随机的）。", ""]
    return lines


def section_cost(raw: dict[str, dict]) -> list[str]:
    lines = ["## 六、成本（单合约耗时分布，供复现估时）", "",
             "| 工具 | 单合约预算 (s) | 合约数 | 实测耗时 p50 / p90 / max (s) | 合计 wall |",
             "| --- | --- | --- | --- | --- |"]
    for tool, d in raw.items():
        label = d.get("tool_label") or LABELS.get(tool, tool)
        els = sorted(float(c.get("elapsed") or 0) for c in (d.get("contracts") or {}).values()
                     if c.get("elapsed") is not None)
        if not els:
            continue

        def q(f):
            return els[min(int(len(els) * f), len(els) - 1)]
        budget = d.get("tool_timeout_s")
        lines.append(f"| **{label}** | {budget if budget else '—（Slither 无墙钟预算）'} | {len(els)} | "
                     f"{q(.5):.1f} / {q(.9):.1f} / {els[-1]:.1f} | {sum(els) / 3600:.2f} h |")
    lines += ["", "> 符号执行类（Mythril / Manticore）的成本由**单合约预算**封顶，"
              "超时记 `timeout`（与 Slither 的 `error` 同口径：不计入分母）。"
              "故它们的召回**受预算限制**，这个限制必须随结果披露。", ""]
    lines += _run_env_notes(raw)
    return lines


def _run_env_notes(raw: dict[str, dict]) -> list[str]:
    """跑动环境的额外约束 —— **一行**，不展开（用户 2026-09-26：论文披露不要堆乱七八糟的）。

    事实本身仍留在产物 `run_env.json` 与 `decisions.md` §56.7（内部记录），
    报告只留一句可核查的指针：manticore 那一行是在**加了内存上限**的条件下跑的。
    """
    for tool, d in raw.items():
        env = load_json(BASE / f"{tool}_alldata" / "run_env.json")
        if not env:
            continue
        label = d.get("tool_label") or LABELS.get(tool, tool)
        n_aff, n_all = env.get("affected_contracts"), d.get("n_contracts")
        pct = f"（{n_aff}/{n_all} ≈ {100 * n_aff / n_all:.1f}%）" if n_aff and n_all else ""
        return [f"> ⚠ **{label}** 跑动时因本机内存（WSL 总内存 7.8 GB，工具默认起 24 个 z3 进程）"
                f"加了 cgroup 内存上限 {env.get('mem_cap')}：**{n_aff} 个合约{pct}撞到上限、"
                f"分析被内核中断**（在产物里表现为 `error`/`timeout`，不计入分母），其余合约不受影响。"
                f"详见 `run_env.json` 与 `decisions.md` §56.7.4。", ""]
    return []


def build() -> tuple[str, dict]:
    raw = {t: (load_json(BASE / f"{t}_alldata.json") or {}) for t in tool_names()}
    md: list[str] = [
        "# 5.3 六个传统工具的对比实验（程序生成，勿手改）",
        "",
        "> 生成脚本：`scripts/collect_traditional_tools.py`；驱动：`scripts/baseline_static_tools.py --tool <名>`；",
        "> 五工具的调用/解析/映射在 `scripts/static_tool_adapters.py`。",
        "> **主对比表**在 `experiments/baseline_three_caliber_tables.md`（同一份生成器 `collect_baseline_tables.py`）。",
        "> 本文只放**读那六行数字的前提**：映射、能力边界、覆盖率、成本。",
        "",
    ]
    md += section_scope(raw)
    md += section_mapping(raw)
    md += section_coverage(raw)
    md += section_metrics(raw)
    md += section_missing_not_at_random(raw)
    md += section_cost(raw)
    miss = [t for t in ("slither", "mythril", "manticore", "smartcheck", "securify", "oyente")
            if t not in raw]
    if miss:
        md += ["", f"> 🔴 **无产物**：{'、'.join(miss)}（无 `eval_results/baseline/<工具>_alldata.json`）。",
               "> 本报告与主对比表都会**少这几行**，且这一句就是判据——不要读成「这些工具测出来是 0」。", ""]
    payload = {
        "created_utc": __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc).isoformat(timespec="seconds"),
        "scope": {"slither": SLITHER_SCOPE, "others": NEW_SCOPE},
        "tools": {t: {**{k: v for k, v in d.items() if k != "contracts"},
                    "no_detector_classes": list(spec_of(t, d, "no_detector_classes") or []),
                    "capability_live": list(spec_of(t, d, "capability") or [])}
               for t, d in raw.items()},
        "missing": miss,
    }
    return "\n".join(md) + "\n", payload


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="experiments/traditional_tools_results.md",
                    help="写入的 markdown 路径；传空串只打印")
    ap.add_argument("--json", default="experiments/traditional_tools_results.json")
    args = ap.parse_args()
    md, payload = build()
    if args.out:
        (REPO / args.out).write_text(md, encoding="utf-8")
        print(f"[collect] 写入 {args.out}（{len(md.splitlines())} 行）")
    else:
        print(md)
    if args.json:
        (REPO / args.json).write_text(json.dumps(payload, ensure_ascii=False, indent=1),
                                      encoding="utf-8")
        print(f"[collect] 写入 {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
