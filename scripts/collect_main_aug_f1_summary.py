#!/usr/bin/env python3
"""① 主库 vs ② 增强集：**七类逐类 F1 + micro-F1 + macro-F1 并列一张表**（2026-09-28）。

**存在理由**：论文要的是一张「两语料 × 七类 + 两个汇总列」的**总表**。这些数字早已存在，
但落在两份文件里、且**各自缺一半**：

| 现有文件 | 生成脚本 | 有 | 缺 |
|---|---|---|---|
| `experiments/per_class_three_caliber_tables.md` | `collect_three_caliber_tables.py` | ① 与 ② 的逐类 F1 | 只有**一个**汇总列（micro 或 macro，看表号）；基线/工具**整块不在** |
| `experiments/baseline_three_caliber_tables.md` | `collect_baseline_tables.py` | 基线 + 六工具 + 逐类 | **只有 ① 主库**（② 增强集整块没有） |

⇒ 想回答「② 上基线/工具是多少」要翻两份文件，而**答案其实是「没跑」**——
这个「没跑」在两份文件里都**看不出来**（它们各自沉默，沉默长得像「不在范围」）。
本脚本把两语料、五类方法、两个工作点收进一张表，并把**没跑的格子显式画成 `—` 并点名原因**。

🔴 **零重实现**：逐类格与汇总列一律走 `collect_three_caliber_tables.row_from_run` /
`collect_baseline_tables.trad_row`，`metrics` 仍是唯一实现。本脚本只做三件事：
**拼行、加第二汇总列（micro 与 macro 同表）、写没跑清单**。

🔴 **为什么 micro 与 macro 能在同一张表里**：两者用的是**同一批逐类 F1**（`micro` 口径的
逐类格），只是汇总方式不同（标签对级全局 / 七类未加权平均）。故同表不产生任何口径混用
—— 这条在 `collect_three_caliber_tables.py` 的抬头里已有定义，本脚本只是把两个汇总列并排。

用法（仓库根目录）：
    python scripts/collect_main_aug_f1_summary.py            # 只打印
    python scripts/collect_main_aug_f1_summary.py --out experiments/main_aug_f1_summary.md
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_three_caliber_tables as T                                  # noqa: E402
import collect_baseline_tables as B                                       # noqa: E402

NAMES = T.NAMES
SEEDS = T.SEEDS
CALIBERS = T.CALIBERS
WORKPOINTS = [(wp, disp) for wp, disp, _dk, _bk in T.WORKPOINTS]
WP_DISP = dict(WORKPOINTS)

# ------------------------------------------------------------------ 行定义
# 🔴 两语料的**正典 run 目录**：① = `runs/`，② = `runs/augmentation/`。
#    ② 未换代（仍是冻结编码器树 + 其正典 run），故路径与 ① 不对称是**事实**、不是笔误。
AUG_RUNS = "runs/augmentation"

# 二语料 × 三条论文基线：`(臂名, 显示名)`。
# 🔴 `egfl_ownlr` 是 EGFL 的**敏感性命中臂**（改用其论文 lr=0.002）——`collect_baseline_tables`
#    把它并列上报的理由（"否则 EGFL 弱无法与超参没调对区分开"）在这里同样成立，故一并带上。
PAPER_ARMS = [
    ("mvdhg", "**MVD-HG**（忠实复现）"),
    ("egfl", "**EGFL**（按论文重实现）"),
    ("egfl_ownlr", "**EGFL**（改用其论文 `lr=0.002`）"),
    ("mando", "**MANDO-LLM**（按论文重实现）"),
]
TRADITIONAL = B.TRADITIONAL


def empty_row() -> dict:
    """空行 → `render_table` 走「无 pairs」分支，逐类与两个汇总列全 `—`。"""
    return {"cells": {wp: {c: [] for c in CALIBERS} for wp, _ in WORKPOINTS}, "support": {}}


def paper_row(arm: str, layout: str = "canon37", seeds=None) -> dict | None:
    """三条论文基线 → 与 `row_from_run` 同构的行（复用 `collect_baseline_tables.rel_of`）。

    它们与本文方法**共用同一个行构造器**：`results.json`/`test_probs.pt`/`thresholds.json`
    的形态由同一套 `train.py`/`evaluate.py`/`diagnose.py` 写出 ⇒ 重写一份只会分叉。
    """
    rel = B.rel_of(arm, layout)
    if not (REPO / rel / f"seed{seeds[0] if seeds else 0}" / "test_probs.pt").exists():
        return None
    return T.row_from_run(rel, seeds or SEEDS)


def trad_row(tool: str, layout: str = "canon37", seeds=None) -> dict | None:
    return B.trad_row(tool, seeds, layout)


def build(best_seed: bool = False):
    """→ `[(label, row)]`，外加 `(supports, missing)` 两个旁注块。"""
    k = {}
    for ckey, rel in (("main", "runs"), ("aug", AUG_RUNS)):
        k[ckey] = [T.best_seed_from_runs(rel)] if best_seed else list(SEEDS)

    rows: list[tuple[str, dict]] = []
    supports: dict[str, dict] = {}
    missing: list[str] = []

    # ---- ① 主库 ----------------------------------------------------------
    r = T.row_from_run("runs", k["main"])
    rows.append(("**① 主库 · 本文方法（正典）**", r))
    supports["① 主库"] = r["support"]
    for arm, label in PAPER_ARMS:
        pr = paper_row(arm, "canon37", k["main"])
        rows.append((f"① 主库 · {label}", pr if pr else empty_row()))
        if pr is None:
            missing.append(f"① 主库 · {label}")
    for tool in TRADITIONAL:
        tr = trad_row(tool, "canon37", k["main"])
        rows.append((f"① 主库 · {B.trad_label(tool)}", tr if tr else empty_row()))
        if tr is None:
            missing.append(f"① 主库 · {tool}")

    # ---- ② 增强集 --------------------------------------------------------
    r = T.row_from_run(AUG_RUNS, k["aug"])
    rows.append(("**② 增强集 · 本文方法（正典）**", r))
    supports["② 增强集"] = r["support"]
    # 🔴 **没有 "aug" 这个 layout**：`baseline_common.LAYOUTS` 只有 canon37 / buggy。
    #    故这里**不猜路径**——逐条实测候选产物根，有就出行、没有就画 `—` 并点名。
    for arm, label in PAPER_ARMS:
        pr = None
        for cand in (f"eval_results/baseline/{arm}_aug", f"eval_results/baseline/aug_{arm}"):
            if (REPO / cand / f"seed{k['aug'][0]}" / "test_probs.pt").exists():
                pr = T.row_from_run(cand, k["aug"])
                break
        rows.append((f"② 增强集 · {label}", pr if pr else empty_row()))
        if pr is None:
            missing.append(f"② 增强集 · {label}")
    for tool in TRADITIONAL:
        found = None
        for cand in (f"eval_results/baseline/{B.trad_root(tool)}_aug",
                     f"eval_results/baseline/{tool}_alldata_aug"):
            if (REPO / cand / f"seed{k['aug'][0]}_eval.json").exists():
                found = B.slither_row(k["aug"], cand, tool=tool)
                break
        rows.append((f"② 增强集 · {B.trad_label(tool)}", found if found else empty_row()))
        if found is None:
            missing.append(f"② 增强集 · **{B.TRAD_LABEL[tool]}**（传统工具）")

    return rows, supports, missing


# ------------------------------------------------------------------ 排版
def render(rows, wp: str) -> list[str]:
    """七类逐类 F1 + **micro-F1** + **macro-F1**（两列并排）。"""
    head = ("| 行 | " + " | ".join(NAMES) + " | **micro-F1** | **macro-F1** |")
    sep = "| --- | " + " | ".join(["---"] * (len(NAMES) + 2)) + " |"
    lines = [head, sep]
    for label, r in rows:
        mic = r["cells"][wp]["micro"]
        mac = r["cells"][wp]["macro"]
        if not mic:
            lines.append(f"| {label} | " + " | ".join(["—"] * (len(NAMES) + 2)) + " |")
            continue
        cells = [T._ms_col(mic, i) for i in range(len(NAMES))]
        lines.append(f"| {label} | " + " | ".join(cells)
                     + f" | **{T._ms_col(mic)}** | **{T._ms_col(mac)}** |")
    return lines


# ------------------------------------------------------------------ 独立对拍守卫
# 🔴 **为什么要有 `--check`**：本表的数字要进论文，而它读的是**同一批产物**。
#    若某个 row 构造器将来改了（或某个产物被重跑覆盖），本表会**静默**给出
#    与另外两份表不一致的格子 —— 两份文件都"看起来对"，只有对拍能发现。
#    对拍对象是**另两个脚本**写出的文件（`collect_baseline_tables.py` /
#    `collect_three_caliber_tables.py`），故这是**跨实现**的比较，不是自证。
REF_BASELINE = "experiments/baseline_three_caliber_tables.md"     # ① 全部行
REF_PERCLASS = "experiments/per_class_three_caliber_tables.md"    # ① ② 本文方法

_METHOD = {
    "本文方法": "self", "正典": "self",
    "MVD-HG": "mvdhg", "EGFL": "egfl", "MANDO-LLM": "mando",
    "Slither": "slither", "Mythril": "mythril", "Manticore": "manticore",
    "Smartcheck": "smartcheck", "Securify": "securify", "Oyente": "oyente",
}


def _method_key(label: str) -> str | None:
    """行名 → 方法键（`self`/`mvdhg`/…）。**不含语料**（语料由调用方给）。

    ⚠ EGFL 有两行（统一 lr / 论文 lr），**只靠方法名分不开** ⇒ 必须先判 `lr=0.002`。
    判反了不会报错，只会让两行互相"对上了"，那是最坏的一种通过。
    """
    body = label.replace("*", "")
    if "lr=0.002" in body:
        return "egfl_ownlr"
    for name, key in _METHOD.items():
        if name in body:
            return key
    return None


def _key_of(label: str) -> tuple[str, str] | None:
    """`① 主库 · **EGFL**（改用其论文 lr=0.002）` → `("main", "egfl_ownlr")`。

    ⚠ **先剥掉 `**`**：正典那两行的标签是加粗的（`**① 主库 · 本文方法（正典）**`），
    直接 `startswith("①")` 会判 False ⇒ 两行**静默跳过对拍**、`checked` 少 36 格却仍报"通过"。
    （这正是 `checked == 0` 之外还要打印**格数**的原因：少对拍也是错，只是不容易发现。）
    """
    body = label.replace("*", "")
    corpus = "main" if body.startswith("①") else ("aug" if body.startswith("②") else None)
    if corpus is None:
        return None
    mk = _method_key(label)
    return (corpus, mk) if mk else None


def _parse_tables(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    """md → `{(口径, 工作点): {行名: "| a | b | ... |"}}`。

    按**抬头文字**定位表（不按表号——表号会随新增小节平移，写死就会指错表且不报错）。

    🔴 **必须按「节」限域，不能全文件扫**：`baseline_three_caliber_tables.md` 里有**两个**
    「3 种子 mean±std」节（§二 = 池 453、§三之二 = 池 497），两节的**行名逐字相同**；
    全文件扫会让后一节**静默覆盖**前一节 ⇒ 拿池 497 的数字去"对拍"池 453 的表，
    报出一堆假不一致（本轮实测就是这么发现的）。故只取**第一个不含 `buggy` 的
    `附录：3 种子 mean±std` 节**，遇到下一个一级标题即停止。
    """
    if not path.exists():
        return {}
    out: dict[tuple[str, str], dict[str, str]] = {}
    cur: tuple[str, str] | None = None
    caliber = None
    in_scope = False
    seen_scope = False                    # 🔴 只认**第一个**匹配节：§三之二 的抬头里
                                          #    没有 `buggy` 二字（它在 §三 里），只靠关键词
                                          #    挡不住它 —— 实测正是它把 §二 盖掉的。
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("# "):
            if not seen_scope and "3 种子 mean±std" in line and "buggy" not in line:
                in_scope = seen_scope = True
            else:
                in_scope = False
            cur = None
            continue
        if not in_scope:
            continue
        if line.startswith("## 表"):
            for c in ("micro", "macro", "buggy"):
                if f"{c}-F1 口径" in line:
                    caliber = c
            wp = "fixed_0.5" if "@0.5" in line else ("val_thr" if "@验证集阈值" in line else None)
            cur = (caliber, wp) if (caliber and wp and caliber != "buggy") else None
            if cur:
                out.setdefault(cur, {})
            continue
        if not line.startswith("|"):
            if line.startswith("#") or not line:
                if line.startswith("#"):
                    cur = None
            continue
        if cur is None:
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if not cells or cells[0] in ("行", "---") or set(cells[0]) <= {"-", " "}:
            continue
        out[cur][cells[0]] = cells[1:]
    return out


def _digits(s: str) -> str:
    """`**0.6804±0.0908**` → `0.6804±0.0908`（剥掉加粗与空白，只比数字串）。"""
    return s.replace("*", "").strip()


def check(rows_ms: list[tuple[str, dict]], missing: list[str]) -> int:
    refs = {REF_BASELINE: _parse_tables(REPO / REF_BASELINE),
            REF_PERCLASS: _parse_tables(REPO / REF_PERCLASS)}
    if not any(refs.values()):
        print("[check] ⚠ 两份参照文件都读不到，跳过对拍（**不是通过**）")
        return 0

    bad = checked = 0
    for wp in ("fixed_0.5", "val_thr"):
        for ref_file, tables in refs.items():
            micro_t = tables.get(("micro", wp))
            macro_t = tables.get(("macro", wp)) or {}
            if not micro_t:
                continue
            # 该文件里能对拍的方法键 → 行名。语料由文件决定（baseline 文件只有 ①）。
            ref_corpus = "main" if ref_file == REF_BASELINE else None
            ref_map: dict[tuple[str, str], str] = {}
            for rl in micro_t:
                mk = _method_key(rl)
                if mk is None:
                    continue
                if ref_corpus is None:                      # per_class 文件：语料写在行名前缀
                    rb = rl.replace("*", "")                # ⚠ 同样要先剥 `**`（见 `_key_of`）
                    rc = "main" if rb.startswith("①") else ("aug" if rb.startswith("②") else None)
                    if rc is None:
                        continue
                else:
                    rc = ref_corpus
                ref_map[(rc, mk)] = rl

            for label, r in rows_ms:
                k = _key_of(label)
                if k is None or not r["cells"][wp]["micro"] or k not in ref_map:
                    continue
                ref_label = ref_map[k]
                mine = [_digits(T._ms_col(r["cells"][wp]["micro"], i)) for i in range(len(NAMES))]
                mine += [_digits(T._ms_col(r["cells"][wp]["micro"])),
                         _digits(T._ms_col(r["cells"][wp]["macro"]))]
                theirs = [_digits(c) for c in micro_t[ref_label][:len(NAMES) + 1]]
                theirs.append(_digits(macro_t[ref_label][len(NAMES)])
                              if ref_label in macro_t else "?")
                if len(theirs) < len(mine):
                    continue
                for i, (a, b) in enumerate(zip(mine, theirs)):
                    if b == "?":
                        continue
                    checked += 1
                    if a != b:
                        bad += 1
                        where = NAMES[i] if i < len(NAMES) else ("micro" if i == len(NAMES) else "macro")
                        print(f"[check] ✗ {wp} {ref_file} 行={ref_label} 列={where}："
                              f"本表 {a} vs 参照 {b}")

    if missing:
        print(f"[check] i ② 未跑的方法 {len(missing)} 条（已在本表 §4 逐条点名）")
    # 🔴 **`checked == 0` 必须判失败**：行名对不上时 `continue` 会静默跳过，
    #    结果是"扫了 0 格却报通过"——那种通过比不检查更危险（它给了虚假的安心）。
    if checked == 0:
        print("[check] ✗ 一格都没对上（行名匹配失效？）——**不是通过**")
        return 1
    print(f"[check] ✓ {checked} 格与两份参照表逐格一致" if bad == 0
          else f"[check] ✗ 共 {bad} 格不一致（已比对 {checked} 格）")
    return 1 if bad else 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="", help="输出路径；空 = 只打印")
    ap.add_argument("--check", action="store_true",
                    help="与另外两份程序生成的表逐格对拍；不一致则 rc=1（不落盘）")
    args = ap.parse_args()

    rows_ms, supports, missing = build(best_seed=False)
    rows_bs, _sup_bs, _miss_bs = build(best_seed=True)

    if args.check:
        sys.exit(check(rows_ms, missing))

    doc: list[str] = []
    doc.append("# ① 主库 vs ② 增强集：七类逐类 F1 + micro-F1 / macro-F1")
    doc.append("")
    doc.append("> 程序生成（`scripts/collect_main_aug_f1_summary.py`）：**只搬运产物、只调 `metrics`**，"
               "不手抄、不重实现指标。逐类格与 `collect_three_caliber_tables.py` **共用同一个"
               "行构造器**（`row_from_run`），基线/工具行与 `collect_baseline_tables.py` **共用**"
               "（`trad_row`）⇒ 同口径、可对拍。")
    doc.append(">")
    doc.append("> 🔴 **两列汇总同表不产生口径混用**：`micro-F1` 与 `macro-F1` 用的是**同一批逐类 F1**"
               "（全测试集 micro 口径），只是汇总方式不同（标签对级全局 / 七类未加权平均）。"
               "定义见 `collect_three_caliber_tables.py` 抬头。")
    doc.append(">")
    doc.append("> 🔴 **① 与 ② 的数字不可横比**（`decisions.md` §23）：① 是真实部署合约（多标签、"
               "含天然极稀缺类），② 是单标签合成增强集（正样本充足）。两组**各自独立完整、并列呈现**；"
               "**禁止**跨组比较绝对值、**禁止**平均/相加/合并成一个数字。")
    doc.append("")
    doc.append("---")
    doc.append("")

    # ---- §0 support ----
    doc.append("## 0. 逐类 support（先读，按种子 0/1/2）")
    doc.append("")
    doc.append("| 语料 | " + " | ".join(NAMES) + " |")
    doc.append("| --- | " + " | ".join(["---"] * len(NAMES)) + " |")
    for gname in ("① 主库", "② 增强集"):
        sup = supports.get(gname, {}).get("fixed_0.5") or []
        cells = ["/".join(str(s[i]) for s in sup) if sup else "—" for i in range(len(NAMES))]
        doc.append(f"| {gname} | " + " | ".join(cells) + " |")
    doc.append("")
    doc.append("> 🔴 ① 的 `dos`/`front_running`/`time_manipulation` test support 低到 **1–2**："
               "**单类 F1 一次翻转即跳 ±0.67**，这些类**仅描述性呈现、不进方法间比较**（`decisions.md` §13）。"
               "② 的逐类 support 在 10–39 之间，无此类问题。")
    doc.append("> 两个工作点的 support **逐位相同**（同一测试集，只是阈值不同），故只列一张。")
    doc.append("")
    doc.append("### 0.1 🔴 基线/工具行的分母**与本表不同**（逐条从产物读出，不手抄）")
    doc.append("")
    doc.extend(B.coverage_block("canon37"))
    doc.append("")
    doc.append("| 工具 | test 分母 `n_in_split` | 可分析 `n_analyzed` | 覆盖率 |")
    doc.append("| --- | --- | --- | --- |")
    _cov_seen = False
    for tool in TRADITIONAL:
        d = REPO / B.trad_root(tool) / "seed0_eval.json"
        if not d.exists():
            doc.append(f"| {B.TRAD_LABEL[tool]} | — | — | **未跑** |")
            continue
        t = json.loads(d.read_text(encoding="utf-8"))["test"]
        doc.append(f"| {B.TRAD_LABEL[tool]} | {t['n_in_split']} | {t['n_analyzed']} | "
                   f"{t['coverage']:.4f} |")
        _cov_seen = True
    doc.append("")
    doc.append("> 🔴 **分析失败的合约不计入分母、也不记全零** ⇒ 传统工具行的逐格 Δ 与三条基线**不可直接解读**"
               "（这是「工具跑不了」与「工具说没漏洞」的区别，`decisions.md` §56）。")
    doc.append("> 🔴 **分母本身不是随机缺失**：Securify 只吃 pragma 0.5.x、Oyente 钉死 solc 0.4.19，"
               "而 ① 真实池里「有漏洞 ⟺ 0.4.x」是**完美分离**（0.4.x 38% 含漏洞 / 0.5.x **0%**）"
               "⇒ Securify 的可分析集**恰好全是干净合约**，其整行**结构性不可评估**"
               "（表里画 `—`，`collect_traditional_tools.py` 会自动报 warning）。")
    doc.append("")
    doc.append("---")
    doc.append("")

    # ---- 两个工作点 ----
    for wp, disp in WORKPOINTS:
        title = "@0.5" if wp == "fixed_0.5" else "@验证集阈值"
        tag = "表 1" if wp == "fixed_0.5" else "表 2"
        doc.append(f"## {tag} —— 3 种子 mean±std {title}")
        doc.append("")
        doc.extend(render(rows_ms, wp))
        doc.append("")

    doc.append("---")
    doc.append("")
    doc.append("## 表 3 —— 最佳种子（① seed1 / ② seed1）@0.5（单值，无 ±）")
    doc.append("")
    doc.append("> 判据与全仓一致 = 本文方法正典在 **micro-F1@val_thr** 上最高的种子"
               "（`decisions.md` §39）。两条基线/工具行**与该语料共用同一个种子**。")
    doc.append("")
    doc.extend(render(rows_bs, "fixed_0.5"))
    doc.append("")

    doc.append("---")
    doc.append("")

    # ---- 未跑清单 ----
    doc.append("## 4. 🔴 ② 增强集上**没有跑**的方法（本表的 `—` 从这里来）")
    doc.append("")
    if missing:
        doc.append("| 方法 | 语料 | 状态 |")
        doc.append("| --- | --- | --- |")
        for m in missing:
            gname, label = m.split(" · ", 1)
            doc.append(f"| {label} | {gname} | **未跑** |")
        doc.append("")
        doc.append("> 成因逐条相同：**② 增强集没有对应的产物根**。三条论文基线与六工具**共用同一套**"
                   "「布局 → 产物根」派生（`baseline_common.LAYOUTS` / `trad_root()`），"
                   "而该表**只有 `canon37`/`buggy` 两个 layout，没有 `aug`** ⇒ 十行一起缺。")
    else:
        doc.append("（无：本表所有行都有产物。）")
        doc.append("")
    doc.append("> 🔴 **`—` 在这里只有一种成因 = 「尚未评测」**，不得读成「该工具在增强集上 F1=0」。"
               "这与传统工具行里的结构性 `—`（工具不提供此检测项 / 整行不可评估）**是两回事**，"
               "各自的判据见 `experiments/baseline_three_caliber_tables.md` 与 "
               "`experiments/traditional_tools_results.md` 第四节。")
    doc.append("")
    doc.append("**要补跑的话，成本量级**（供裁定，不构成承诺）：")
    doc.append("")
    doc.append("- **三条论文基线**：`run_baselines.py` 的 `--layout` 只有 `canon37`/`buggy` ⇒ "
               "补 ② 需**先加一个 `aug` layout**（四处一起改：`split_dir`/`graph_dir`/"
               "`feature_suffix`/`out_dir`，`baseline_common.check_layout()` 会硬拒不一致组合），"
               "再重建 ② 的离线特征（MVD-HG 的 AST/CFG/DFG + word2vec、EGFL 的 opcode 序列）。"
               "② 池 **1774** 对 ① 池 453 ≈ **3.9 倍**合约数 ⇒ 离线建图与训练时间同倍增长"
               "（① 的三基线训练规模见 `baseline_three_caliber_tables.md` §2）。")
    doc.append("- **六工具**：产物根命名是 `{tool}_alldata{suffix}`，`suffix` 由 layout 派生 ⇒ "
               "同样要先有 `aug` layout。成本上**符号执行类是瓶颈**（manticore 单路 + cgroup 5 GB 上限，"
               "见 `decisions.md` §56；**不得并行**）；且 ② 的 pragma 分布会让 "
               "**Securify（只吃 0.5.x）/ Oyente（钉死 solc 0.4.19）的可分析集进一步收缩**——"
               "② 的可分析集上逐类 support 是否全 0 **须实测**，不能沿用 ① 的结论"
               "（① 的「0.5.x 恰好全干净」是**该池**的性质，`decisions.md` §56 已点明是完美分离、不可外推）。")
    doc.append("")

    text = "\n".join(doc) + "\n"
    if args.out:
        out = REPO / args.out
        out.write_text(text, encoding="utf-8")
        print(f"[summary] 写入 {args.out}（{len(text)} 字节）")
    else:
        print(text)


if __name__ == "__main__":
    main()
