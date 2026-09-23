#!/usr/bin/env python3
"""5.3 对比表：本文方法 + 三条论文基线（EGFL / MVD-HG / MANDO-LLM）三口径 × 两工作点。

**零重实现**：逐类格与汇总列一律走 `collect_three_caliber_tables.render_table`，
support 走 `support_block`、薄支撑警告走 `_thin_support_note`（从实际 support 推导，
不写死句子）。本脚本只做两件事：**拼行**与**写抬头声明**。

产物 = `experiments/baseline_three_caliber_tables.md`。

用法（仓库根目录）：
    python scripts/collect_baseline_tables.py                    # 只打印
    python scripts/collect_baseline_tables.py --out experiments/baseline_three_caliber_tables.md
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_three_caliber_tables as T                                 # noqa: E402

NAMES = T.NAMES
SEEDS = T.SEEDS
CALIBERS = T.CALIBERS

# 行 = (显示名, run 相对路径, 该基线的一句话"实现性质"声明)
BASELINES = [
    ("**MVD-HG**（忠实复现）", "eval_results/baseline/mvdhg",
     "建图**驱动其原仓库代码**（AST/CFG/DFG 三关系 RGCN，300 维 word2vec）。"
     "偏离：DFG 有它的 40 s/文件上限（被截断的样本只含**部分 DFG 边**）；"
     "词向量只用 train 划分拟合（原实现用全体）；dropout 保持它的 0.1（不是正典 0.3）；"
     "输出头 1→7。**覆盖率 448/453**（5 个合约在任何已装 solc 下都编不出 compact AST），"
     "但那 5 个**全在 train**（seed2 另有 1 个在 val）⇒ **test 仍是完整 46**，与本表其它行逐格可比。"),
    ("**EGFL**（按论文重实现）", "eval_results/baseline/egfl",
     "原生**字节码**模态（solc --bin → 反汇编 → 基本块 CFG → BFS 展平）+ Conformer 序列分支。"
     "🔴🔴 **两处必须随结果披露的重建/损失**：① **图分支的 256 维是重建件** —— 原 `cfg_graph` 是"
     "作者未开源的预处理产物（`Weights_CFG_SimOp/` 为空目录、全仓无脚本产出它），论文只写"
     "「BFS 展平」、切法不可考，本实现按「块内 opcode 词向量取平均 → BFS 前 k 块 concat」重建；"
     "② **序列被截断到 512 token，池内 83.2% 的合约受此影响**（token 数中位数 3118）—— "
     "它的注意力是**稠密 O(L²)**，本机 8 GB 卡实测 L=1024 就溢出到共享显存（9.9 GB / 慢 48 倍），"
     "原论文 `SEQ_LEN=8000` 在 8 GB 卡上任何实现都跑不动。**这是硬件逼出来的口径损失，"
     "会系统性压低 EGFL 的读数**。词表/词向量只用 train 划分拟合。"),
    ("**MANDO-LLM**（按论文重实现）", "eval_results/baseline/mando",
     "图算子用 PyG `HGTConv` 替代 dgl 的 `HGTLayer`（不新建 conda 环境）；"
     "🔴 图 = **我方 CFG 中心异构图**（不是原版的 slither 图）、节点类型取 `type_id` 的 9 类语义角色。"
     "节点输入主臂 = `NodeFuser` 融合后的 h_v^(0)，与本文方法**逐字相同** ⇒ 唯一变量 = 图算子。"
     "输出头 2→7。**参数化方式不是逐位等价**（PyG 用 bases/attention 分解）。"),
]


# 敏感性命中臂：**基线的论文自带超参**（与"统一口径"相反的方向）。
# 🔴 为什么必须并列：EGFL 论文的 `--lr` 默认 **0.002**，是正典 1e-4 的 **20 倍**。
# 只报统一口径那一行，会让"EGFL 弱"这个结论**无法与"超参没调对"区分开**——
# 这正是计划里 R5 点名的风险。两行并列，读者可自行判断。
SENSITIVITY = [
    ("**EGFL**（改用其论文 `lr=0.002`）", "eval_results/baseline/egfl_ownlr",
     "同一份离线特征、同一 `seq_len=512`/结构，**唯一变量 = lr**（1e-4 → 2e-3）。"
     "🔴 **实测结论（三种子）**：统一 lr 的 `micro@val_thr` = **0.209/0.182/0.209**"
     "（均值 0.200，`best_epoch` 停在 0–2），本论文 lr 的 = **0.222/0.333/0.383**"
     "（均值 **0.313**，`best_epoch` 12–15）⇒ **lr 确是显著压制项（+0.113）**，"
     "但**改对 lr 后 EGFL 仍在 0.31 量级**，远低于 MVD-HG 与本文方法。"
     "剩下的差距归因于 **`seq_len=512` 的截断（池内 83.2% 的合约受影响，token 数中位数 3118）**"
     "与图分支 256 维是重建件。**本表不得据此宣称「EGFL 方法本身弱」**——"
     "它是一个在 8 GB 卡上被截断到约 1/6 长度的 EGFL；两行并列正是为了让这个区别可见。"),
]


def coverage_block() -> list[str]:
    """三条基线的**离线覆盖率**（分母是否与本文方法相同）—— 逐行读各自 results.json。"""
    lines = ["| 基线 | 离线特征覆盖 | test 覆盖 | 备注 |", "| --- | --- | --- | --- |"]
    for label, rel, _n in BASELINES:
        fs = [REPO / rel / f"seed{s}" / "results.json" for s in SEEDS]
        fs = [f for f in fs if f.exists()]
        if not fs:
            lines.append(f"| {label} | — | — | 尚未跑 |")
            continue
        d0 = json.loads(fs[0].read_text(encoding="utf-8"))
        cov = d0.get("coverage")
        if not cov:
            # 无离线步的基线（MANDO 直接读正典 `graphs_ft/ss{S}`，不落 feat/*.pt）。
            # ⚠ 不能显示成「— 个 feat」——那读起来像"产出缺失"，实际是**没有这一步**。
            lines.append(f"| {label} | 无离线步（直接读正典图） | test 完整 | 与本文方法**同一批图** |")
            continue
        dropped = cov.get("dropped_test") or []
        note = "test 完整" if not dropped else f"🔴 test 少 {len(dropped)} 个"
        lines.append(f"| {label} | {cov.get('n_features', '—')} 个 feat/*.pt | "
                     f"{note} | 训练集剔除 {sum((cov.get('dropped') or {}).values())} 个 |")
    return lines


def slither_row(seeds=None) -> dict | None:
    """Slither 的 `seed{S}_eval.json` → 与 `row_from_run` 同构的行（buggy 口径无产物 ⇒ `—`）。

    🔴 **分母不同**：`n_analyzed` < `n_in_split`（分析失败/不支持的合约**不计入分母、也不记全零**），
    故它与三条基线的逐格 Δ **不可解读**。
    """
    root = REPO / "eval_results/baseline/slither_alldata"
    # 🔴 **必须接受 seeds 过滤**：最佳种子表里如果 Slither 仍铺开 3 个种子，
    # 它就会带着 `±` 混进一张「每行一个数」的表——口径不一致且不会报错。
    want = list(SEEDS if seeds is None else seeds)
    seeds = [s for s in want if (root / f"seed{s}_eval.json").exists()]
    if not seeds:
        return None
    out = {wp: {c: [] for c in CALIBERS} for wp, *_ in T.WORKPOINTS}
    support = {}
    for s in seeds:
        d = json.loads((root / f"seed{s}_eval.json").read_text(encoding="utf-8"))
        t = d["test"]
        support.setdefault("fixed_0.5", []).append(t["per_class_support"])
        for wp, *_ in T.WORKPOINTS:
            # 两个工作点同源：Slither 是确定性规则工具，没有阈值可搜（json 也只有一套）
            out[wp]["micro"].append((t["per_class_f1"], t["micro_f1"]))
            out[wp]["macro"].append((t["per_class_f1"], t["macro_f1"]))
            out[wp]["buggy"].append(([None] * len(NAMES), None))
    n_in = None
    n_an = None
    if seeds:
        d0 = json.loads((root / f"seed{seeds[0]}_eval.json").read_text(encoding="utf-8"))["test"]
        n_in, n_an = d0["n_in_split"], d0["n_analyzed"]
    return {"cells": out, "support": support, "_denominator": (n_in, n_an),
            "_seeds": seeds}


def timing_block() -> list[str]:
    """训练时间与规模（用户 2026-09-22 要求记录成本）。"""
    lines = ["| 基线 | 种子 | 参数量 (M) | best epoch | 训练 (s) | 每 epoch (s) | 总 wall (s) | device |",
             "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for label, rel, _note in BASELINES:
        for s in SEEDS:
            f = REPO / rel / f"seed{s}" / "results.json"
            if not f.exists():
                lines.append(f"| {label} | seed{s} | — | — | — | — | — | — |")
                continue
            d = json.loads(f.read_text(encoding="utf-8"))
            t = d.get("timing") or {}
            lines.append(
                f"| {label} | seed{s} | "
                f"{(d.get('n_params') or 0)/1e6:.3f} | {d.get('best_epoch')} | "
                f"{t.get('train_seconds')} | {t.get('seconds_per_epoch')} | "
                f"{t.get('wall_seconds')} | {(d.get('environment') or {}).get('device')} |")
    return lines


def main() -> None:
    ap = argparse.ArgumentParser(description="5.3 基线三口径对比表")
    ap.add_argument("--runs-dir", default="runs", help="本文方法的正典 run 目录。")
    ap.add_argument("--out", default="", help="写入的 markdown 路径；留空只打印。")
    args = ap.parse_args()

    best = T.best_seed_from_runs(args.runs_dir, SEEDS)
    if best is None:
        raise SystemExit(f"🔴 {args.runs_dir} 下没有 results.json，无法选最佳种子")

    rows_all, rows_best = [], []
    canon = T.row_from_run(args.runs_dir, SEEDS)
    rows_all.append(("**本文方法**（§37 正典）", canon))
    rows_best.append(("**本文方法**（§37 正典）", T.row_from_run(args.runs_dir, [best])))
    present = []
    for label, rel, _note in BASELINES:
        if not (REPO / rel).exists():
            print(f"[warn] 缺 {rel}（该基线还没跑）——该行将显示为 —")
            continue
        present.append((label, rel))
        rows_all.append((label, T.row_from_run(rel, SEEDS)))
        rows_best.append((label, T.row_from_run(rel, [best])))

    for label, rel, _note in SENSITIVITY:
        if not (REPO / rel).exists():
            continue
        rows_all.append((label, T.row_from_run(rel, SEEDS)))
        rows_best.append((label, T.row_from_run(rel, [best])))

    sl = slither_row()
    if sl is not None:
        rows_all.append(("**Slither**（传统工具）", sl))
        rows_best.append(("**Slither**（传统工具）", slither_row([best])))

    supports = {"本文方法与三基线共用（§37 正典 test）": canon["support"]}
    if sl is not None:
        supports["Slither（分母不同）"] = sl["support"]

    doc: list[str] = []
    doc += ["# 5.3 对比表：本文方法 vs 三条论文基线（EGFL / MVD-HG / MANDO-LLM）",
            "",
            "> 程序生成（`scripts/collect_baseline_tables.py`）：**只搬运产物、只调 `metrics`**，"
            "不手抄、不重实现指标。逐类格与汇总列一律经 "
            "`collect_three_caliber_tables.render_table`。", "",
            f"> 🔴 **表 1–6 = 最佳种子口径**（判据 = 本文方法正典在 micro-F1@val_thr 上最高 ⇒ "
            f"**seed{best}**；全部行共用同一个种子，否则同一批行不是同一批模型）；"
            "**表 7–12 = 3 种子 mean±std 附录**（ddof=1）。"
            "⚠ 最佳种子口径下没有 ±，且本仓实测重跑抖动 ≈0.012 ⇒ **不得**据单种子差下「某方法更强」的结论。",
            "",
            "## 0. 口径声明（引用本表前必读）", "",
            "**1）正典与池。** 本表正典 = **§37 正典**（`products/alldata/graphs_ft/ss{S}` + "
            "`products/alldata/splits/split_seed{S}.json`，池 **453**、train/val/test = 362/45/46）。"
            "该池**已剔除全部 `buggy_*` 合约**——这正是用户 2026-09-22 裁定的「去除 `buggy_*` 的数据集」"
            "（497 删 44 个 `buggy_*` 后与 453 **集合级恒等**）。"
            "▶ 本表与 `experiments/per_class_three_caliber_tables.md` **同池同划分**，"
            "与 `..._tables_buggy.md` **不是同一个 test 集**，两边数字**不可直接相减**。", "",
            "**2）三口径。** `micro` / `macro` 的**逐类格是全测试集**逐类 F1；`buggy` 的逐类格是"
            "**仅 `y.any(axis=1)` 的合约**上的逐类 F1。汇总列：`micro` = 标签对 micro-F1，"
            "`buggy` = 漏洞子集上的 micro-F1，`macro` = 那 7 个逐类 F1 的未加权平均。"
            "🔴 **`macro` 表与 `micro` 表的逐类格逐位相同**（恒等，不是重复计算），差异只在汇总列。", "",
            "**3）训练口径。** 三条基线共用同一套超参"
            "（`epochs=200, lr=1e-4, weight_decay=1e-4, scheduler_patience=3, "
            "pos_weight_cap=20.0`），早停判据 = val micro-F1，阈值只在验证集搜"
            "（0.20–0.80 步长 0.05）。**与本文方法有两处已知口径差，逐条列出：**"
            "① 🔴 **`early_stop_patience` 基线用 20、本文方法正典用 5**——正典的 5 是为 SSM-HG 调的，"
            "实测套到 MVD-HG 上会在 **loss 仍在下降**（2.20→0.64）时于第 14 轮截断、**系统性压低基线**；"
            "② **batch 配置因显存/耗时而异，逐行列出**：**本文方法与 MANDO-LLM = 字面 `batch_size=32`**；"
            "**MVD-HG 与 EGFL = `batch_size=4 × accum_steps=8`**（等效 batch 仍是 32）。"
            "EGFL 是因为 `seq_len=512` 下整批反传会 OOM（本机 8 GB）；MVD-HG 为与 EGFL **口径一致**故同款。"
            "MANDO 实测**不能**用累积：它的 HGT 有 186 种边类型 × 2 层 = 372 次 Python 级小算子调用，"
            "**每步开销与样本数几乎无关**（batch 4 时 4.5 s/步 × 90 步 = 408 s/epoch，"
            "batch 32 时 10.4 s/步 × 12 步 = 125 s/epoch）⇒ 累积形式慢 3.3 倍，故用整批。"
            "⚠ **`4×8` 与「整批 32」不逐位等价**：损失期望相同，但 dropout 采样结构不同"
            "（每 step 抽 8 次 micro-batch 掩码而非 1 次）⇒ **等效正则强度不完全相同**。"
            "这条差异是已知的、未消除的。"
            "**逐处有意偏离已写入各自的 `results.json::reconstruction_notes`。**", "",
            "**4）离线覆盖率（分母是否相同）。**", ""]
    doc += coverage_block()
    doc += ["",
            "> ⚠ **分母不可比的只有 Slither**（见下）：三条基线的 `test_probs.pt` 行数"
            "**全部等于 46**（正典 test 的合约数），故与本文方法**逐格可比**。", "",
            "**5）🔴 三条基线的实现性质与口径损失不同，逐行声明（不得只写一个总注，"
            "不得声称复现了作者原结果）：**", ""]
    for label, _rel, note in BASELINES:
        doc.append(f"- {label}：{note}")
    doc += ["",
            "⇒ 三者是**规模各异的「按论文重实现 / 驱动原码」**，**不是原作者的二进制**；"
            "**不得声称复现了作者原结果**，也不得把它们的差值解读为「方法优劣」——"
            "输入模态、图定义、节点特征来源三者**各自不同**。", ""]
    for label, _rel, note in SENSITIVITY:
        doc.append(f"- {label}：{note}")
    if sl is not None:
        n_in, n_an = sl["_denominator"]
        doc += [f"- **Slither**：分母不同 —— test 里 {n_in} 个合约只有 {n_an} 个被成功分析"
                f"（`status != ok` 的**不计入分母、也不记全零**）⇒ 它与三条基线的逐格 Δ **不可解读**；"
                "且它**不提供** `front_running` 检测项（该格是「无此项」而非「F1=0」），"
                "`buggy` 口径无逐合约产物 ⇒ 该口径整列 `—`。", ""]
    doc += ["**6）成本。** 训练时间与规模见 §2。三条基线的推理产物（`test_probs.pt`）已入库，"
            "全部指标可**离线重算、无需重训**。", "",
            "---", "", "## 1. 逐类 support（先读）", ""]
    doc += T.support_block(supports)
    doc += [T._thin_support_note(supports), "", "---", "",
            "## 2. 训练时间与规模（成本）", ""]
    doc += timing_block()
    doc += ["", "> `训练 (s)` = 训练循环净耗时；`总 wall (s)` = 含验证推理与阈值搜索的整段耗时。", "",
            "---", "", f"# 一、主口径：最佳种子（seed{best}）", ""]
    n = 0
    for wp, disp, _dk, _bk in T.WORKPOINTS:
        for c in CALIBERS:
            n += 1
            cname = {"micro": "micro-F1 口径（全测试集逐类 F1）",
                     "buggy": "buggy-F1 口径（仅有漏洞合约子集逐类 F1）",
                     "macro": "macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均）"}[c]
            doc += [f"## 表 {n} —— {cname} @{disp}", ""]
            doc += T.render_table(rows_best, wp, c)
            doc += [""]
    doc += ["---", "", "# 二、附录：3 种子 mean±std", ""]
    for wp, disp, _dk, _bk in T.WORKPOINTS:
        for c in CALIBERS:
            n += 1
            cname = {"micro": "micro-F1 口径（全测试集逐类 F1）",
                     "buggy": "buggy-F1 口径（仅有漏洞合约子集逐类 F1）",
                     "macro": "macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均）"}[c]
            doc += [f"## 表 {n} —— {cname} @{disp}", ""]
            doc += T.render_table(rows_all, wp, c)
            doc += [""]

    text = "\n".join(doc) + "\n"
    if args.out:
        p = REPO / args.out
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
        print(f"[collect] 已写 {p}（{len(text)} 字符，{n} 张表；最佳种子 seed{best}）")
    else:
        print(text)


if __name__ == "__main__":
    main()
