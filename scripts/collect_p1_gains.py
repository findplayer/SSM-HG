#!/usr/bin/env python3
"""P1 三笔**零重训**头寸的交付物：把 `improvement_proposals.md` §7 优先级表里的 P1 三项，
从"建议 + 实测记录"落成**可引用的并列口径**。

**它不产生任何新数字**：三笔全部读既有产物，本脚本只做「搬运 + 对齐口径 + 写使用规则」。
与 `collect_three_caliber_tables.py` 同一条纪律：**不手抄、不重实现指标**。

| 表 | 头寸 | 唯一产物来源 | 成本 |
|---|---|---|---|
| 1 | **三种替代工作点** vs 现行主口径 | `eval_results/calibration/summary.json::test_schemes` | 零（已有） |
| 2 | **同划分多种子概率集成** | `eval_results/ensemble/cbft_study_cbft.json` | 零重训（复用既有 run） |
| 3 | **分辨率**：bootstrap 95% CI + 按 support 加权 macro | `eval_results/bootstrap/main.json` | 零（已有） |

🔴 **三条使用规则（写进正文，不是可选注释）**：
 ① **集成不得与 best-of-3 并列比较**——"挑最好"含选择膨胀（3 次取最大），集成不含。
 ② **逐类阈值的过拟合已量化**（val 每类 1–3 个正样本，`dos` 阈值三种子极差 0.55）⇒ 它是**并列口径**，
    不是替换现行 `val_thr` 的更好口径：它换来 macro **+0.138**、代价是 micro **−0.045**。
 ③ **本文件的三笔都只进“报告口径”，不进训练控制流**（早停/调度/选点/阈值搜索目标）。

用法（仓库根目录）：
    python scripts/collect_p1_gains.py                                  # 只打印
    python scripts/collect_p1_gains.py --out experiments/p1_gains.md
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

CALIB = "eval_results/calibration/summary.json"
ENSEMBLE = "eval_results/ensemble/cbft_study_cbft.json"
BOOT = "eval_results/bootstrap/main.json"
CANON = "experiments/canonical_ft_numbers.md"          # 权威数字出处（只作指路，不解析）

# 工作点的显示名（键名 = `calibrate.py` 写进 summary.json 的方案名）
SCHEMES = [("baseline_fixed_0.5", "固定 0.5"),
           ("baseline_val_threshold", "验证集阈值（**现行主口径**）"),
           ("per_class_threshold", "**逐类阈值**（每类各一个，只在 val 上按该类 F1 选）")]


def _load(rel: str) -> dict:
    p = REPO / rel
    if not p.exists():
        raise SystemExit(f"🔴 缺产物 {rel}——先跑产出它的脚本（见文件头表格的成本列）")
    return json.loads(p.read_text(encoding="utf-8"))


def _fmt(m: dict) -> tuple[str, float]:
    """`{mean, std}` → (`0.1234±0.0567`, mean)。std 缺失时只给均值。"""
    if m is None:
        return "—", float("nan")
    mean = float(m["mean"])
    std = m.get("std")
    return (f"{mean:.4f}±{float(std):.4f}" if std is not None else f"{mean:.4f}"), mean


def workpoint_block() -> list[str]:
    """表 1：现行主口径 vs 三种替代工作点（同一批 `test_probs.pt`，零重训）。"""
    cal = _load(CALIB)
    ts = cal.get("test_schemes") or {}
    out = ["| 工作点 | micro-F1 | macro-F1 | Δmicro vs 现行 | Δmacro vs 现行 |",
           "| --- | --- | --- | --- | --- |"]
    base_micro = float(ts["baseline_val_threshold"]["micro_f1"]["mean"])
    base_macro = float(ts["baseline_val_threshold"]["macro_f1"]["mean"])
    for key, disp in SCHEMES:
        if key not in ts:
            out.append(f"| {disp} | — | — | — | — |")
            continue
        mi, mv = _fmt(ts[key].get("micro_f1"))
        ma, av = _fmt(ts[key].get("macro_f1"))
        dm = "—" if key == "baseline_val_threshold" else f"**{mv - base_micro:+.4f}**"
        da = "—" if key == "baseline_val_threshold" else f"**{av - base_macro:+.4f}**"
        out.append(f"| {disp} | {mi} | {ma} | {dm} | {da} |")
    return out


def ensemble_block() -> list[str]:
    """表 2：同划分多种子概率集成。**逐 split 一行**（集成的合法性来自"同一划分"）。"""
    e = _load(ENSEMBLE)
    out = ["| 划分 | 单模型均值 | 单模型最好 | **集成** | Δ vs 均值 | Δ vs 最好 |",
           "| --- | --- | --- | --- | --- | --- |"]
    for ss, d in sorted(e["split_seeds"].items()):
        ens = d["ensemble"]["test_micro@val_thr"]
        out.append(f"| {ss} | {d['mean_of_singles_micro@val_thr']:.4f} | "
                   f"{d['best_of_singles_micro@val_thr']:.4f} | **{ens:.4f}** | "
                   f"**{d['delta_vs_mean']:+.4f}** | {d['delta_vs_best']:+.4f} |")
    out += ["", f"| 均值 | — | — | — | **{e['mean_delta_vs_mean']:+.4f}** | "
                f"{e['mean_delta_vs_best']:+.4f} |"]
    out += ["",
            f"> 集成的 3 个成员 = `{e['prefix']}` 研究臂里**同一划分、不同训练种子**的三个 run"
            f"（`{e['group'].split('/')[-1]}/`）；概率按 `sample_ids` **逐个断言对齐**后平均，"
            "阈值只从**平均后的 val** 上重搜。"]
    return out


def resolution_block() -> list[str]:
    """表 3：bootstrap 95% CI + 按 support 加权 macro（两者都是"分辨率"而非"涨点"）。"""
    b = _load(BOOT)
    out = ["| 种子 | 工作点 | micro-F1 | **95% CI** | macro-F1 | 95% CI | macro(按 support 加权) | macro(剔薄类) |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    thin = None
    for seed, d in sorted(b["seeds"].items(), key=lambda kv: str(kv[0])):
        for wp, disp in (("fixed_0.5", "0.5"), ("val_thr", "val_thr")):
            w = d.get(wp)
            if not w:
                continue
            bs = w["bootstrap"]
            c3 = w["caliber_c3"]
            thin = c3.get("thin_classes") or thin
            out.append(f"| {seed} | {disp} | {w['micro_f1']:.4f} | "
                       f"**[{bs['micro']['lo']:.3f}, {bs['micro']['hi']:.3f}]** | "
                       f"{w['macro_f1']:.4f} | [{bs['macro']['lo']:.3f}, {bs['macro']['hi']:.3f}] | "
                       f"{c3['macro_support_weighted']:.4f} | {c3['macro_excluding_thin']:.4f} |")
    widths = []
    for d in b["seeds"].values():
        w = d.get("val_thr") or {}
        if w:
            bs = w["bootstrap"]["micro"]
            widths.append(bs["hi"] - bs["lo"])
    wnote = (f"实测区间宽达 **{min(widths):.2f}–{max(widths):.2f}**"
             if widths else "区间宽度见上表")
    out += ["",
            f"> 🔴 **本表是“分辨率”而不是“涨点”**：micro-F1 的 95% CI {wnote}（B={b['n_boot']}，"
            "重采样单位 = **合约**、阈值在每个重采样里**保持不变**）⇒ 在 46 个合约、21 个正标签对的 test 上，"
            "**方法间 |Δ| < 0.1 的比较先天测不出来**。",
            f"> 末两列把“未加权 macro 被薄支撑类拖住”量化了：test 上 support ≤ 2 的类是 "
            f"**{'、'.join(thin) if thin else '（见产物）'}**，剔掉它们后 macro 明显抬升。"
            "⚠ 这与大纲 5.1「support ≤2 的类仅作描述性呈现、不进方法间比较结论」是同一条规定的两种表述。"]
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="P1 三笔零重训头寸的交付物")
    ap.add_argument("--out", default="", help="写入的 markdown 路径；留空只打印。")
    args = ap.parse_args()

    doc = ["# P1 三笔零重训头寸：口径、实测与使用规则", "",
           "> 程序生成（`scripts/collect_p1_gains.py`）：**只读既有产物、只搬运数字**，"
           "不手抄、不重实现指标、不重训。", "",
           "> **定位**：把 `improvement_proposals.md` §7 优先级表的 **P1 三项**从"
           "「建议 + 实测记录」落成**可引用的并列口径**。三笔**全部零重训**；"
           "逐条的诊断与否定证据见 `improvement_round1_results.md`。", "",
           "## 0. 使用规则（引用本文件前必读，三条缺一不可）", "",
           "**① 集成不得与 best-of-3 并列比较。** 「单模型最好」那一列含**选择膨胀**"
           "（3 次取最大 ⇒ 期望 +0.85σ），它是在**用 test 挑种子**，不可进论文；"
           "集成是在不知道 test 的情况下做的（阈值也只读 val），**无选择膨胀**。",
           "",
           "**② 逐类阈值是并列口径，不是“更好的主口径”。** 它换来 macro 的明显提升，代价是 micro 下降；"
           "且它的过拟合**已量化**——val 上 `dos`/`front_running`/`time_manipulation` 各只有 1 个正样本，"
           "`dos` 的阈值三种子极差达 **0.55**，val→test 落差最大 **0.16**"
           "（审计见 `eval_results/calibration/summary.json::overfit_audit` 与 "
           "`experiments/gcn_baseline_and_per_class_f1.md` §3）。",
           "",
           "**③ 三笔都只进“报告口径”，不进训练控制流。** 早停 / 学习率调度 / `best.pt` 选点 / "
           "阈值搜索目标**一律不动**——改它们的代价是全部结果作废（`decisions.md` §28 的教训）。",
           "", "---", "", "## 表 1 —— 工作点对比（① 主库，3 种子 mean±std，零重训）", ""]
    doc += workpoint_block()
    doc += ["",
            "> 三个工作点跑在**同一批 `test_probs.pt`** 上（同一批模型、同一个 test），"
            "差异**只来自判决规则**。阈值一律**只在验证集**上搜索（候选 0.20–0.80 步长 0.05，并列取小）。",
            "> ⚠ 现行主口径（验证集阈值）**仍是论文主表**；本表的作用是让「换判决规则能换到多少」可见。",
            "", "---", "", "## 表 2 —— 同划分多种子概率集成（零重训）", ""]
    doc += ensemble_block()
    doc += ["",
            "> 🔴 **读法**：集成相对**均值**是 **> 抖动 0.012** 的正面增益；"
            "相对**最好单模型**是负的——这不矛盾，是两条不同口径（见 §0 第 ① 条）。"
            "⇒ 论文里应把集成写成**独立一行口径**（“多种子集成的正典”），与单模型并列报。",
            "", "---", "", "## 表 3 —— 分辨率：bootstrap 95% CI 与按 support 加权 macro（零重训）", ""]
    doc += resolution_block()
    doc += ["", "---", "", "## 复现命令（全部零重训）", "",
            "```bash",
            "# ---- 工作点对比（读 test_probs.pt / val_best_probs.pt）----",
            "python scripts/calibrate.py                     # → eval_results/calibration/summary.json",
            "",
            "# ---- 同划分多种子集成 ----",
            "python scripts/ensemble_eval.py                 # → eval_results/ensemble/",
            "",
            "# ---- 分辨率：bootstrap CI + 加权 macro ----",
            "python scripts/oof_bootstrap.py                 # → eval_results/bootstrap/main.json",
            "",
            "# ---- 本文件 ----",
            "python scripts/collect_p1_gains.py --out experiments/p1_gains.md",
            "```", "",
            f"> 三层权威关系：**数字出处** = 上列三个 JSON 产物；**解读与否定证据** = "
            f"`improvement_round1_results.md`（§3 集成 / §5 逐类阈值 / §5b bootstrap）；"
            f"**论文口径数字的权威出处** = `{CANON}` 与 `experiments/results.md`。"]

    text = "\n".join(doc) + "\n"
    if args.out:
        p = REPO / args.out
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
        print(f"[p1] 已写 {p}（{len(text)} 字符，{text.count('## 表 ')} 张表）")
    else:
        print(text)


if __name__ == "__main__":
    main()
