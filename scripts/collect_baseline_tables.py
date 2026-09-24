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

import numpy as np
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_three_caliber_tables as T                                 # noqa: E402

NAMES = T.NAMES
SEEDS = T.SEEDS
CALIBERS = T.CALIBERS

# ---------------------------------------------------------------- 布局（正典选择）
# 🔴 两段正典（§37 池 453 / 含 buggy 池 497）**共用同一份行定义与同一套渲染**，
#    只有「产物根」这一件事不同 ⇒ 用后缀派生，不复制第二份行清单
#    （复制会让两张表的行集合漂移——本仓点过名的一类问题）。
LAYOUTS = {
    "canon37": {"suffix": "", "runs_dir": "runs", "title": "§37 正典（池 453）"},
    "buggy": {"suffix": "_buggy", "runs_dir": "runs/buggy_canon",
              "title": "含 `buggy_*` 的新正典（池 497）"},
}


def rel_of(arm: str, layout: str = "canon37") -> str:
    """臂名 + 布局 → 产物相对路径。canon37 下与引入布局参数之前**逐字符相同**。"""
    return f"eval_results/baseline/{arm}{LAYOUTS[layout]['suffix']}"


# 行 = (显示名, 臂名, 该基线的一句话"实现性质"声明)
BASELINES = [
    ("**MVD-HG**（忠实复现）", "mvdhg",
     "建图**驱动其原仓库代码**（AST/CFG/DFG 三关系 RGCN，300 维 word2vec）。"
     "偏离：DFG 有它的 40 s/文件上限（被截断的样本只含**部分 DFG 边**）；"
     "词向量只用 train 划分拟合（原实现用全体）；dropout 保持它的 0.1（不是正典 0.3）；"
     "输出头 1→7。**覆盖率 448/453**（5 个合约在任何已装 solc 下都编不出 compact AST），"
     "但那 5 个**全在 train**（seed2 另有 1 个在 val）⇒ **test 仍是完整 46**，与本表其它行逐格可比。"),
    ("**EGFL**（按论文重实现）", "egfl",
     "原生**字节码**模态（solc --bin → 反汇编 → 基本块 CFG → BFS 展平）+ Conformer 序列分支。"
     "🔴🔴 **两处必须随结果披露的重建/损失**：① **图分支的 256 维是重建件** —— 原 `cfg_graph` 是"
     "作者未开源的预处理产物（`Weights_CFG_SimOp/` 为空目录、全仓无脚本产出它），论文只写"
     "「BFS 展平」、切法不可考，本实现按「块内 opcode 词向量取平均 → BFS 前 k 块 concat」重建；"
     "② **序列被截断到 512 token，池内 83.2% 的合约受此影响**（token 数中位数 3118）—— "
     "它的注意力是**稠密 O(L²)**，本机 8 GB 卡实测 L=1024 就溢出到共享显存（9.9 GB / 慢 48 倍），"
     "原论文 `SEQ_LEN=8000` 在 8 GB 卡上任何实现都跑不动。**这是硬件逼出来的口径损失，"
     "会系统性压低 EGFL 的读数**。词表/词向量只用 train 划分拟合。"),
    ("**MANDO-LLM**（按论文重实现）", "mando",
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
    ("**EGFL**（改用其论文 `lr=0.002`）", "egfl_ownlr",
     "同一份离线特征、同一 `seq_len=512`/结构，**唯一变量 = lr**（1e-4 → 2e-3）。"
     "🔴 **实测结论（三种子）**：统一 lr 的 `micro@val_thr` = **0.209/0.182/0.209**"
     "（均值 0.200，`best_epoch` 停在 0–2），本论文 lr 的 = **0.222/0.333/0.383**"
     "（均值 **0.313**，`best_epoch` 12–15）⇒ **lr 确是显著压制项（+0.113）**，"
     "但**改对 lr 后 EGFL 仍在 0.31 量级**，远低于 MVD-HG 与本文方法。"
     "剩下的差距归因于 **`seq_len=512` 的截断（池内 83.2% 的合约受影响，token 数中位数 3118）**"
     "与图分支 256 维是重建件。**本表不得据此宣称「EGFL 方法本身弱」**——"
     "它是一个在 8 GB 卡上被截断到约 1/6 长度的 EGFL；两行并列正是为了让这个区别可见。"),
]


def coverage_block(layout: str = "canon37") -> list[str]:
    """三条基线的**离线覆盖率**（分母是否与本文方法相同）—— 逐行读各自 results.json。

    🔴 **test 覆盖按「全部种子取并集」判**（不是只看 seed0）：buggy 段实测 MVD-HG 在
    **seed1** 上掉了 1 个 test 合约（正典段是三个种子都完整）⇒ 只看 seed0 会把它报成
    「test 完整」，而那一行的分母其实是 48 —— 正是本表最不能静默出错的一格。
    「训练集剔除」仍按 seed0 报（与引入本参数之前的输出逐字符相同）。
    """
    lines = ["| 基线 | 离线特征覆盖 | test 覆盖 | 备注 |", "| --- | --- | --- | --- |"]
    for label, arm, _n in BASELINES:
        rel = rel_of(arm, layout)
        fs = [REPO / rel / f"seed{s}" / "results.json" for s in SEEDS]
        fs = [f for f in fs if f.exists()]
        if not fs:
            lines.append(f"| {label} | — | — | 尚未跑 |")
            continue
        d0 = json.loads(fs[0].read_text(encoding="utf-8"))
        cov = d0.get("coverage")
        if not cov:
            # 无离线步的基线（MANDO 直接读正典图，不落 feat/*.pt）。
            # ⚠ 不能显示成「— 个 feat」——那读起来像"产出缺失"，实际是**没有这一步**。
            lines.append(f"| {label} | 无离线步（直接读正典图） | test 完整 | 与本文方法**同一批图** |")
            continue
        # 逐种子收集「test 掉了几个」，并集非空即报，且把是哪个种子写出来
        miss = {}
        for s, f in zip(SEEDS, fs):
            dt = json.loads(f.read_text(encoding="utf-8")).get("coverage", {}).get("dropped_test")
            if dt:
                miss[s] = len(dt)
        if not miss:
            note = "test 完整"
        else:
            who = "/".join(f"seed{s}" for s in sorted(miss))
            note = f"🔴 test 少 {'/'.join(str(miss[s]) for s in sorted(miss))} 个（{who}，该行分母不同）"
        lines.append(f"| {label} | {cov.get('n_features', '—')} 个 feat/*.pt | "
                     f"{note} | 训练集剔除 {sum((cov.get('dropped') or {}).values())} 个 |")
    return lines


def slither_row(seeds=None, root_rel: str = "eval_results/baseline/slither_alldata") -> dict | None:
    """Slither 的 `seed{S}_eval.json` → 与 `row_from_run` 同构的行（buggy 口径无产物 ⇒ `—`）。

    🔴 **分母不同**：`n_analyzed` < `n_in_split`（分析失败/不支持的合约**不计入分母、也不记全零**），
    故它与三条基线的逐格 Δ **不可解读**。

    🔴 `root_rel` **必须可传**：它原先硬编码 `slither_alldata`。若忘了参数化，497 池的表里
    会**静默出现 46 池的 Slither 数字**（两份 json 都长一个样、都叫 `seed{S}_eval.json`），
    是本表最隐蔽的一类错（`decisions.md` §52.6）。
    """
    root = REPO / root_rel
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


def slither_root(layout: str = "canon37") -> str:
    """Slither 产物根。🔴 **逐段不同**：正典段是 `slither_alldata`，buggy 段是 `slither_buggy`。

    两段的 json 同名同形（`seed{S}_eval.json`），**唯一能分辨的是目录名**——
    故这个函数是防「46 池数字混进 497 池表」那类静默错的唯一一道。
    """
    return ("eval_results/baseline/slither_alldata" if layout == "canon37"
            else f"eval_results/baseline/slither{LAYOUTS[layout]['suffix']}")


def _trivial_table_stats(run_rel: str, seeds) -> dict:
    """从**本文方法**该正典的 `test_probs.pt` 算两个平凡下限与正例率（供本块的读法句用）。

    🔴 **必须从数据算，不能写死**：正典段（池 453）的「二分类 0.62 / 七维 0.12」是
    那批产物的性质，**换到池 497 就全变了**——实测七维平凡下限从 0.12 抬到约 **0.31**
    （`buggy_*` 的全 1 标签把正例率从 6.5% 抬到约 18%）。写死的读法句不会报错，只会误导。
    """
    import torch
    import metrics
    bins, micros, crate, crate_n, lrate = [], [], [], [], []
    n_cells = 0
    for s in seeds:
        p = REPO / run_rel / f"seed{s}" / "test_probs.pt"
        if not p.exists():
            continue
        y = torch.load(p, map_location="cpu")["labels"].numpy().astype(int)
        anyp = y.any(axis=1).astype(int)                 # 合约级「有没有漏洞」
        bins.append(metrics.binary_f1(anyp, np.ones(len(anyp), dtype=int)))
        P, N = int(y.sum()), int(y.size - y.sum())
        micros.append(2 * P / (2 * P + N))               # 七维：全判 1 的 micro-F1
        crate.append(float(anyp.mean()))                 # 合约级正例率
        lrate.append(P / y.size)                         # 标签格正例率
        n_cells = int(y.size)
    if not bins:
        return {}
    return {"binary_floor": float(np.mean(bins)), "micro_floor": float(np.mean(micros)),
            "contract_pos_rate": float(np.mean(crate)), "label_pos_rate": float(np.mean(lrate)),
            "n_cells": n_cells, "n_contracts": n_cells // len(NAMES)}


def binary_caliber_block(runs_dir: str, layout: str = "canon37",
                         method_label: str = "**本文方法**（§37 正典）") -> list[str]:
    """**合约级二分类**口径对照（三条基线论文的原生口径）——解释「为什么七维 F1 看起来低」。

    🔴 **为什么必须并列这一块**：三条基线的论文报的都是**合约级二分类 F1**（有/无漏洞），
    而大纲 [411] 要求 5.3 **统一按七维多标签**评测。两个口径的**平凡下限差 0.50**
    （正典段实测 七维 0.1224 vs 二分类 0.6199）⇒ 只看七维数字会把「任务更难」误读成
    「这些方法不行」。本块给出**同数据、同划分、同产物**下的二分类读数，并**强制附上平凡下限**。

    坍缩规则：`max_c p_c >= t ⇔ any_c(p_c >= t)`（`decisions.md` §31 已机检），
    故合约级预测 = `probs.max(axis=1) >= thr`，**不是**另训一个模型。

    🔴 分母与读法句里的四个数（合约数 / 二分类平凡下限 / 七维平凡下限 / 正例率）
    **一律由数据算**（见 `_trivial_table_stats`）：buggy 段的分母是 **49** 不是 46，
    且它的二分类平凡下限**逐种子可变**（0.71/0.58/0.68）——写死会错得很自然。
    """
    seeds = list(SEEDS)
    rows: list[tuple[str, str, list[float], list[float]]] = []
    for label, arm, _n in BASELINES + SENSITIVITY:
        rel = rel_of(arm, layout)
        b, triv = _binary_of(rel, seeds)
        if b:
            rows.append((label, rel, b, triv))
    b, triv = _binary_of(runs_dir, seeds)
    if b:
        rows.insert(0, (method_label, runs_dir, b, triv))

    if not rows:
        return ["（尚无产物）"]
    st = _trivial_table_stats(runs_dir, seeds)
    denom = str(st["n_contracts"]) if st else "—"
    out = ["| 方法 | 合约级二分类 F1@val_thr | 平凡下限（全报「有漏洞」） | **净技能** | 预测为正类的合约数 |",
           "| --- | --- | --- | --- | --- |"]
    for label, _rel, b, triv in rows:
        mean = sum(b) / len(b)
        tm = sum(triv) / len(triv)
        out.append(f"| {label} | **{mean:.4f}** | {tm:.4f} | **{mean - tm:+.4f}** | "
                   f"{'/'.join(str(x) for x in _n_pos(_rel, seeds))} / {denom} |")
    # 🔴 **canon37 段的分句逐字保留原文**（该段已发布、数字已被人引用；改成现算会让
    #    每一次重生成都动到已发布的行）。**buggy 段必须现算**——池换了之后
    #    分母（49 不是 46）与两个平凡下限都变了，写死的句子会"看着仍权威"却已失真。
    if layout == "canon37":
        floor_txt = "二分类的平凡下限是 **0.62**（46 个测试合约里 45.7% 本来就有漏洞）"
        micro_txt = "而七维 micro 的平凡下限只有 **0.12**（322 个标签格里 6.5% 是正例）"
    else:
        floor_txt = (f"二分类的平凡下限是 **{st['binary_floor']:.2f}**（{denom} 个测试合约里 "
                     f"**{st['contract_pos_rate'] * 100:.1f}%** 本来就有漏洞）" if st
                     else f"二分类的平凡下限见上表（分母 {denom}）")
        micro_txt = (f"而七维 micro 的平凡下限只有 **{st['micro_floor']:.2f}**"
                     f"（{st['n_cells']} 个标签格里 **{st['label_pos_rate'] * 100:.1f}%** 是正例）"
                     if st else "")
    out += ["",
            f"> 🔴 **读法**：{floor_txt}，{micro_txt}。"
            "⇒ **两个口径的数字不可互比**，也不可与各论文正文的数字直接比"
            "（它们的数据集、划分、类别数都不同，见 `decisions.md` §46/§48）。",
            "> ⚠ **Slither 在二分类口径下整行缺席**：它的产物只有逐类聚合，**没有逐合约预测**，"
            "无法坍缩到合约级（不编数）。",
            "> 🔴 **三篇论文的原始口径（逐篇核对过 PDF，详见 `decisions.md` §48.6）**："
            "**没有一篇是多标签**，全部是「每类漏洞各训一个独立二分类器」——"
            "EGFL 6 类（平均 F1 **87.32**，42,910 合约）、MVD-HG 7 类（合约级 **0.9056–0.9559**，"
            "每类 88–190 **文件夹记录数**——⚠ 非正例数，其标签文件口径为 4–50，"
            "见 `decisions.md` §48.6.3/§51）、MANDO-LLM 7 类（合约级 **86.65–97.06**，作者自建 846/1,928 合约）。"
            "且**每一篇都含至少一条会抬高数字、而本仓明确禁止的做法**：EGFL 对**评测集**做 SMOTE 且"
            "用同一集合选模型、MVD-HG **在训练集上调阈值**且无验证集、MANDO-LLM 合约级把 "
            "clean:buggy **人为平衡成 1:1**（论文脚注自陈）、三者都**没有独立测试集**。"
            "⇒ **论文里的 90+ 与本表七维的 0.19–0.41 在口径上不可比**，"
            "也**不得**反过来用本表宣称超越它们。",
            "> ⚠ **本块的二分类读数是「同一份七维模型的坍缩」，不是另训的二分类模型**。"
            "它的合法性来自 `max_c p_c >= t ⇔ any_c(p_c >= t)`（对「有没有任何一类漏洞」这个问题，"
            "两种写法给出**逐位相同**的判定）。若要「原生二分类头」的读数，见本仓既有的 "
            "`runs/binary_arm/`（`--head binary`，**单变量消融**，其 multi 行用的是冻结编码器 "
            "`graphs` 而非正典 `graphs_ft`，故两处**不可混读**）。"]
    return out


def _binary_of(rel: str, seeds) -> tuple[list[float], list[float]]:
    import torch
    import metrics
    b, triv = [], []
    for s in seeds:
        p = REPO / rel / f"seed{s}" / "test_probs.pt"
        if not p.exists():
            continue
        d = torch.load(p, map_location="cpu")
        y = d["labels"].numpy().astype(int)
        probs = d["probs"].numpy()
        anyp = y.any(axis=1).astype(int)
        thr = T._val_thr(rel, s)
        if thr is None:
            continue
        b.append(metrics.binary_f1(anyp, (probs.max(axis=1) >= thr).astype(int)))
        triv.append(metrics.binary_f1(anyp, np.ones(len(anyp), dtype=int)))
    return b, triv


def _n_pos(rel: str, seeds) -> list[int]:
    import torch
    out = []
    for s in seeds:
        p = REPO / rel / f"seed{s}" / "test_probs.pt"
        if not p.exists():
            continue
        d = torch.load(p, map_location="cpu")
        y = d["labels"].numpy().astype(int)
        probs = d["probs"].numpy()
        thr = T._val_thr(rel, s)
        if thr is None:
            continue
        out.append(int((probs.max(axis=1) >= thr).sum()))
    return out


# ---------------------------------------------------------- 逐类二分类（binary-F1）
# 🔴 本块回答「三篇论文报的那个二分类 F1，逐类是多少」。它是**已有的补充口径**的延伸：
#    `metrics.py` 模块契约与 `论文开发手册.md` §1223 早已裁定「per-class 阈值仅作补充分析、
#    不进主结果」，本文方法的该口径读数也已由 `calibrate.py` 产出并审计过
#    （`eval_results/calibration/summary.json` + `experiments/gcn_baseline_and_per_class_f1.md`）。
#    本块做的**不是**发明新指标，而是把**同一口径**补到三条论文基线上，并把「平均列 = macro-F1」
#    这个恒等式显式写出——否则读者会把同一批数字误当成两套证据。
PC_WP = "per_class_thr"      # 自定义工作点键（只为复用 T.render_table，不改共享层）
PC_CAL = "perclass"


def _pc_pairs(rel: str, seeds) -> list[tuple[list[float], float]]:
    """逐类二分类 F1：`[(逐类 F1[7], 七类算术平均), ...]`，每种子一项。

    🔴 **阈值搜索复用 `calibrate.per_class_thresholds`**（不另写一份）——该函数是仓库里
    per-class 阈值的唯一实现，`eval_results/calibration/` 的存量产物即出自它；重写会在
    本仓最忌讳的地方（"两套实现各说各话"）开一个口子。逐类 F1 一律走 `metrics.per_class_prf`。
    """
    import torch
    import metrics
    import calibrate as CAL
    out = []
    for s in seeds:
        tp = REPO / rel / f"seed{s}" / "test_probs.pt"
        vp = REPO / rel / f"seed{s}" / "val_best_probs.pt"
        if not (tp.exists() and vp.exists()):
            continue
        dt = torch.load(tp, map_location="cpu")
        dv = torch.load(vp, map_location="cpu")
        y, p = dt["labels"].numpy().astype(int), dt["probs"].numpy()
        vy, vpp = dv["labels"].numpy().astype(int), dv["probs"].numpy()
        th = CAL.per_class_thresholds(vpp, vy)          # **只在 val 上选**
        pred = CAL.apply_per_class(p, th["thresholds"])
        f1 = [float(v) for v in metrics.per_class_prf(y, pred)["f1"]]
        out.append((f1, float(np.mean(f1))))
    return out


def _mAP_of(rel: str, seeds) -> list[float]:
    """逐种子 mAP（阈值无关）。`results.json::mAP` 是 dict（`mean_average_precision` 的返回）。"""
    vals = []
    for s in seeds:
        f = REPO / rel / f"seed{s}" / "results.json"
        if not f.exists():
            continue
        d = json.loads(f.read_text(encoding="utf-8")).get("mAP")
        if isinstance(d, dict):
            d = d.get("mAP")
        if d is not None:
            vals.append(float(d))
    return vals


def _pc_crosscheck(runs_dir: str, pairs) -> str:
    """🔴 与既有审计产物逐位对拍：`eval_results/calibration/summary.json`（`calibrate.py` 生成）。

    只用 `runs`（正典）时才有可比对象。不一致即**拒绝**——本仓的规矩是宁可硬失败也不静默
    产出两套数字（同 `collect_per_class_f1.py --check` 的做法）。
    """
    if runs_dir != "runs" or not pairs:
        return ""
    f = REPO / "eval_results/calibration/summary.json"
    if not f.exists():
        return "> ⚠ 未找到 `eval_results/calibration/summary.json`，本块**未经对拍**。"
    sc = json.loads(f.read_text(encoding="utf-8"))["test_schemes"]["per_class_threshold"]
    mine = [float(np.mean([p[0][i] for p in pairs])) for i in range(len(NAMES))]
    ref = [float(sc["per_class_f1"][n]["mean"]) for n in NAMES]
    mine_mean = float(np.mean([p[1] for p in pairs]))
    ref_mean = float(sc["macro_f1"]["mean"])
    bad = [(NAMES[i], mine[i], ref[i]) for i in range(len(NAMES))
           if abs(mine[i] - ref[i]) > 1e-6]
    if bad or abs(mine_mean - ref_mean) > 1e-6:
        raise SystemExit(
            "🔴 逐类二分类口径与 eval_results/calibration/summary.json 不一致，拒绝出表："
            f"逐类 {bad}；平均 本脚本 {mine_mean:.6f} vs 存量 {ref_mean:.6f}")
    return ("✅ **已与存量审计产物对拍**：本文方法这一行的逐类格与平均列，与 "
            "`eval_results/calibration/summary.json::test_schemes.per_class_threshold` "
            "**逐位相同**（7 类 + 平均，容差 1e-6）。⇒ 本块没有第二套实现。")


def per_class_binary_block(runs_dir: str, seeds, layout: str = "canon37",
                           method_label: str = "**本文方法**（§37 正典）",
                           table_title: str = "## 表 1 —— 逐类 binary-F1 @逐类验证集阈值"
                                              "（3 种子 mean±std）",
                           xref: str = "（见 §一 的表 5、§二 的表 11）") -> list[str]:
    """§4.1：逐类二分类 F1（binary-F1）@逐类验证集阈值。

    🔴 `table_title`/`xref`/`method_label`/`layout` 全部外置：本函数被**两段**（canon37 与
    buggy）共用，表号与「见哪几张表」的交叉引用逐段不同；写死会让 buggy 段指向 canon 段的表号。
    """
    # 🔴 本表里 EGFL 有**两行**（统一 lr 与它的论文 lr），行名必须把 lr 写出来，
    #    否则「EGFL」那一行会被误读成论文口径——这正是 §0 第 5 条要防的那种误读。
    def _lbl(s: str) -> str:
        return s.replace("**EGFL**（按论文重实现）",
                         "**EGFL**（按论文重实现，**统一 lr=1e-4**）")

    rows: list[tuple[str, dict]] = []
    for label, arm, _n in BASELINES + SENSITIVITY:
        pr = _pc_pairs(rel_of(arm, layout), seeds)
        if pr:
            rows.append((_lbl(label), {"cells": {PC_WP: {PC_CAL: pr}}}))
    canon = _pc_pairs(runs_dir, seeds)
    if canon:
        rows.insert(0, (method_label, {"cells": {PC_WP: {PC_CAL: canon}}}))
    sl = slither_row(seeds, slither_root(layout))
    sl_note = ""
    if sl is not None:
        # Slither 本来就是 7 条独立规则探针（各自自带判决门槛）⇒ 它的 @0.5 行**就是**
        # 逐类二分类行，不存在"另一个工作点"。两格同源，不编数。
        rows.append(("**Slither**（传统工具，分母不同）",
                     {"cells": {PC_WP: {PC_CAL: sl["cells"]["fixed_0.5"]["macro"]}}}))
        n_in, n_an = sl["_denominator"]
        sl_note = (f"⚠ 它的分母与其余行不同（test {n_in} 个合约只有 {n_an} 个被成功分析），"
                   if n_in else "⚠ 它的分母与其余行不同，")

    out = [table_title, ""]
    tbl = T.render_table(rows, PC_WP, PC_CAL)
    # 表头两处改名：`render_table` 的表头是为"逐类 F1 + 汇总"写的，本表的末列是**逐类等权的平均**
    # （不是 micro 那种标签对加权），沿用「汇总」二字会被读成 micro，故显式改成「平均」。
    tbl[0] = tbl[0].replace("| 行 |", "| 方法 |").replace("**汇总**", "**平均**")
    out += tbl
    out += ["",
            "> **读法**：每一格 = 「该合约是否含第 c 类漏洞」这个**独立二分类问题**的 F1，"
            "判决阈值 $t_c$ **逐类各一个、只在验证集上按该类自身的 F1 选**（候选 0.20–0.80 步长 0.05，"
            "并列取小）。末列 = 7 个 $F1_c$ 的**算术平均**（逐类等权）。",
            "> 🔴 **Slither 行的两个工作点逐位相同**：它是 7 条独立规则探针、**没有可搜的阈值**，"
            "「逐类二分类」本来就是它的原生形态（它也是本表唯一真正「原生二分类」的行）。"
            + sl_note +
            "且**不提供** `front_running` 检测项 ⇒ 该格与「F1=0」不是一回事，跨行 Δ 不可解读。",
            "> ⚠ **本表的 @0.5 工作点不另列**：0.5 对七类相同，故那一版**逐位等于** micro/macro 表的逐类格，"
            "其平均列**恒等于 macro-F1@0.5**" + xref + "。"
            "⇒ 本表相对三口径表的**唯一新增信息**就是「阈值逐类独立」这一件事，"
            "这一点在下面 §4.2 有代价说明。"]
    if canon:
        chk = _pc_crosscheck(runs_dir, canon)
        if chk:                      # buggy 段无存量审计产物可比 ⇒ 不补空行
            out += ["", chk]
    return out


def overview_block(runs_dir: str, seeds, layout: str = "canon37",
                   method_label: str = "**本文方法**（§37 正典）",
                   xref_buggy_thr: str = "（见 §一 的表 7、§二 的表 13）",
                   xref_pcbin: str = "（见 §一 的表 5、§二 的表 11）") -> list[str]:
    """§4.2：各口径汇总列总览（"有哪些好看的读数可放"）。

    🔴 `method_label` / `layout` / 两处交叉引用外置的理由同 `per_class_binary_block`：
    本函数被两段共用，**表号逐段不同**。表尾那两句读法里的平凡下限也**从数据算**
    （`_trivial_table_stats` / `_below_trivial_note`），不写死。
    """
    entries = [(method_label, runs_dir)] + \
              [(lbl, rel_of(arm, layout)) for lbl, arm, _n in BASELINES + SENSITIVITY]
    # Slither 无逐合约预测 ⇒ 逐类 binary / 合约级 binary / mAP 三列**不存在**（记 `—`，不编数）；
    # micro / buggy / macro 三列有（来自它的逐类聚合 json），故仍立行。
    sl = slither_row(seeds, slither_root(layout))
    if sl is not None:
        entries.append(("**Slither**（传统工具，分母不同）", "<slither>"))

    def ms(vals):
        v = [x for x in vals if x is not None]
        if not v:
            return None, "—"
        if len(v) == 1:
            return float(v[0]), f"{v[0]:.4f}"
        return float(np.mean(v)), f"{np.mean(v):.4f}±{np.std(v, ddof=1):.4f}"

    head = ("| 方法 | micro@0.5 | micro@val_thr | buggy@0.5 | buggy@val_thr | macro@0.5 "
            "| **逐类 binary@逐类阈值** | **合约级 binary@val_thr** | mAP（无阈值） | **本行最高** |")
    lines = [head, "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for label, rel in entries:
        is_sl = rel == "<slither>"
        r = sl if is_sl else T.row_from_run(rel, seeds)
        pc = [] if is_sl else _pc_pairs(rel, seeds)
        cb = [] if is_sl else _binary_of(rel, seeds)[0]
        cols = {}
        for key, (wp, cal) in {"micro05": ("fixed_0.5", "micro"),
                               "micro_thr": ("val_thr", "micro"),
                               "buggy05": ("fixed_0.5", "buggy"),
                               "buggy_thr": ("val_thr", "buggy"),
                               "macro05": ("fixed_0.5", "macro")}.items():
            cols[key] = ms([p[1] for p in r["cells"][wp][cal]])
        cols["pcbin"] = ms([p[1] for p in pc]) if pc else (None, "—")
        cols["cbbin"] = ms(cb)
        cols["mAP"] = (None, "—") if is_sl else ms(_mAP_of(rel, seeds))
        best = max(((k, v[0]) for k, v in cols.items() if v[0] is not None),
                   key=lambda kv: kv[1], default=(None, None))[0]
        disp = {"micro05": "micro@0.5", "micro_thr": "micro@val_thr", "buggy05": "buggy@0.5",
                "buggy_thr": "buggy@val_thr", "macro05": "macro@0.5",
                "pcbin": "逐类 binary", "cbbin": "合约级 binary", "mAP": "mAP"}
        cell = {k: ("**" + v[1] + "**" if k == best else v[1]) for k, v in cols.items()}
        lines.append(f"| {label} | " + " | ".join(cell[k] for k in
                     ("micro05", "micro_thr", "buggy05", "buggy_thr", "macro05",
                      "pcbin", "cbbin", "mAP")) + f" | **{disp[best]}** |")
    st = _trivial_table_stats(runs_dir, seeds)
    mf = st["micro_floor"] if st else float("nan")
    bf = st["binary_floor"] if st else float("nan")
    # 🔴 同 `binary_caliber_block`：canon37 段的两句读法**逐字保留原文**，buggy 段现算。
    if layout == "canon37":
        floor_line = ("不存在谁更真——但**不同口径的平凡下限差 0.50**"
                      "（七维 0.1224 vs 合约级二分类 0.6199），")
        low_note = ("EGFL 两行与 MANDO 行的最高列"
                    "（合约级 binary 0.6199 / 0.5254 / 0.6178）**都不高于该口径的平凡下限 0.6199**"
                    "（判据见 §3），即那三行**换成任何口径都打不过「一律报有漏洞」**。")
    else:
        floor_line = (f"不存在谁更真——但**不同口径的平凡下限差 0.50**"
                      f"（七维 {mf:.4f} vs 合约级二分类 {bf:.4f}，本段实测），")
        low_note = _below_trivial_note(runs_dir, layout)
    lines += ["",
              "> 🔴 **本表的用途是「选口径」，不是「挑最大值」**：同一行内各列是**同一批产物**的不同算法，"
              + floor_line +
              "所以**跨行的同列**可比、**同一行的跨列**不可比。论文里写哪一列，就**必须**同时写明该列的"
              "平凡下限与 support 构成。",
              "> **可选的三个「好看」档（按本表实测，均属本文方法）**："
              "① **合约级 binary@val_thr** —— 四个口径里最高的一档，且是三条基线论文的**原生口径**，"
              "5.3 对比表与之对齐时可比性最强；"
              "② **buggy@val_thr** —— 漏洞子集上的读数，避开了「干净合约七类全 0 拉低 micro」这一项；"
              "③ **micro@val_thr / @0.5** —— 大纲 [411] 规定的主口径，与 `results.md` 主表同源。"
              "⇒ **建议正文以 ③ 为主、① 为辅**（① 用来回答「为什么基线数字低」），"
              "② 作为补充列。**不要只放 ①**：那会被读成避重就轻。",
              "> ⚠ **mAP 列是阈值无关的**（对逐类单调变换不变），因此它**不受任何阈值口径影响**，"
              "是唯一不能用「阈值没调好」解释的一列——它的高低直接反映排序能力。",
              f"> 🔴 **「本行最高」只是口径指路，不是「好看」的证明**：{low_note}"
              "⇒ 跨行比较只能同列相比，且**必须**带上 §0 的实现性质声明。"]
    return lines


def _below_trivial_note(runs_dir: str, layout: str) -> str:
    """「哪些行的**合约级二分类**读数**不高于**该口径的平凡下限」——**从数据算，不写死**。

    正典段原来是写死的（「EGFL 两行与 MANDO 行的最高列 0.6199 / 0.5254 / 0.6178 都不高于 0.6199」）。
    换到池 497 后平凡下限变成另一组数（且逐种子可变），写死的句子会**看起来仍然权威**却已失真。

    ⚠ **只说「合约级二分类」这一列，不说「最高列」**：本函数只算得出这一列的平凡下限，
    而某行的实际最高列**可能不是它**——实测 `_buggy` 段 EGFL-ownlr 的最高列是
    `buggy@val_thr`（0.5553）而非合约级 binary（0.3748）。沿用「最高列」会把一个只对
    一列成立的判断说成对整行成立，那是本仓点过名的「样板句失真」。
    """
    st = _trivial_table_stats(runs_dir, list(SEEDS))
    if not st:
        return ""
    floor = st["binary_floor"]
    bad, names = [], []
    for label, arm, _n in BASELINES + SENSITIVITY:
        b, _t = _binary_of(rel_of(arm, layout), list(SEEDS))
        if b and sum(b) / len(b) <= floor:
            bad.append(f"{sum(b) / len(b):.4f}")
            names.append(label)
    if not bad:
        return (f"本段实测**没有**任何基线的合约级二分类读数低于平凡下限 {floor:.4f}"
                f"（判据见 §3）——但这是 `buggy_*` 全 1 标签抬高了「全报有漏洞」的下限所致，"
                f"**不得**读作「基线够强」。")
    return (f"{'、'.join(names)} 三行的**合约级二分类**读数（{' / '.join(bad)}）"
            f"**都不高于该口径的平凡下限 {floor:.4f}**（判据见 §3），"
            f"即那三行**在合约级二分类口径下打不过「一律报有漏洞」**"
            f"（⚠ 不断言它们的**其他**口径如何，见各行的「本行最高」列）。")


def timing_block(layout: str = "canon37") -> list[str]:
    """训练时间与规模（用户 2026-09-22 要求记录成本）。"""
    lines = ["| 基线 | 种子 | 参数量 (M) | best epoch | 训练 (s) | 每 epoch (s) | 总 wall (s) | device |",
             "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for label, arm, _note in BASELINES:
        rel = rel_of(arm, layout)
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


def _cross_canon_note() -> list[str]:
    """两段正典的**方向性对照**（micro@val_thr，3 种子均值）。

    🔴 **它是「看方向、不看小数位」的表**，理由与 `experiments/buggy_canon_summary.md` §3b 逐字相同：
    两段的 **test 集不是同一批合约**（46 vs 49，且划分重划过）⇒ **严格说不可相减**。
    可以做方向对照的唯一依据是**两段的 test 正样本量级相当**（旧 test 21 个正 / 新 test 干净子集 20 个正）。
    ⚠ 而且本段的基线还多差一层「特征配对方式」（见 §0 第 4 条）⇒ 这张表的 Δ **只能读作
    「补回注入噪声样本之后读数怎么动」，不得读作「某方法更强/更弱」**。

    本表唯一要回答的问题：**把 `buggy_*` 补回池里之后，基线与本文方法的差距形状变了没有。**
    """
    import json as _json

    def ms(rel: str) -> float | None:
        v = []
        for s in SEEDS:
            f = REPO / rel / f"seed{s}" / "results.json"
            if f.exists():
                d = _json.loads(f.read_text(encoding="utf-8"))
                x = (d.get("test", {}).get("val_threshold", {}) or {}).get("micro_f1")
                if x is not None:
                    v.append(float(x))
        return sum(v) / len(v) if v else None

    rows = [("**本文方法**", LAYOUTS["canon37"]["runs_dir"], LAYOUTS["buggy"]["runs_dir"])]
    for label, arm, _n in BASELINES + SENSITIVITY:
        rows.append((label, rel_of(arm, "canon37"), rel_of(arm, "buggy")))
    lines = ["| 方法 | 池 453（§37 正典） | 池 497（含 `buggy_*`） | Δ（方向） |",
             "| --- | --- | --- | --- |"]
    gap_lines = []
    for label, r0, r1 in rows:
        a, b = ms(r0), ms(r1)
        lines.append(f"| {label} | " + ("—" if a is None else f"{a:.4f}") + " | "
                     + ("—" if b is None else f"{b:.4f}") + " | "
                     + ("—" if (a is None or b is None) else f"**{b - a:+.4f}**") + " |")
        if a is not None and b is not None:
            gap_lines.append((label, a, b))
    # 「与本文方法的差距」——本表唯一要回答的那个问题
    if gap_lines and gap_lines[0][0] == "**本文方法**":
        _, m0, m1 = gap_lines[0]
        gl = ["| 方法 | 池 453 上距本文方法 | 池 497 上距本文方法 | 差距变化 |", "| --- | --- | --- | --- |"]
        for label, a, b in gap_lines[1:]:
            gl.append(f"| {label} | {m0 - a:+.4f} | {m1 - b:+.4f} | **{(m1 - b) - (m0 - a):+.4f}** |")
    else:
        gl = []
    out = ["", "### 2b. 🔴 两段正典的方向对照（**这张表是本次补跑要回答的问题**）", ""]
    out += lines
    out += ["",
            "> 🔴 **不得把 Δ 读作「补数据提升了检测能力」**：`buggy_*` 的标签绝大多数是七类全 1，"
            "模型「一律报有漏洞」即可在它们身上拿满分（§0 第 2 条）⇒ **Δ 里混着标签假象**。"
            "**Δmicro 才是干净的那个数**（零支撑类不进分子分母），Δmacro 只作量级参考。"
            "⚠ 且两段的 test 集**不是同一批合约**（46 vs 49），本表**只读方向、不读小数位**"
            "（同 `experiments/buggy_canon_summary.md` §3b 的口径）。", ""]
    if gl:
        out += ["**同上，换成「与本文方法的差距」**（本表加它只为让「差距形状变了没有」一眼可见）：", ""]
        out += gl
        out += ["",
                "> ⚠ Slither **不在**下表里：它不训练、无阈值，且**分母不同**（46 池只分析了 45 个、"
                "497 池 46–47 个）⇒ 它的 Δ 与其余行的 Δ **不可并列解读**。", ""]
    return out


def _detail_tables(rows, start: int) -> tuple[list[str], int]:
    """表 `<start+1>` 起的 6 张明细表（三口径 × 两工作点）。返回 (行, 末表号)。"""
    out, n = [], start
    for wp, disp, _dk, _bk in T.WORKPOINTS:
        for c in CALIBERS:
            n += 1
            cname = {"micro": "micro-F1 口径（全测试集逐类 F1）",
                     "buggy": "buggy-F1 口径（仅有漏洞合约子集逐类 F1）",
                     "macro": "macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均）"}[c]
            out += [f"## 表 {n} —— {cname} @{disp}", ""]
            out += T.render_table(rows, wp, c)
            out += [""]
    return out, n


def _rows_for(layout: str, runs_dir: str, method_label: str, best: int,
              sl_rel: str, supports_key: str) -> tuple[list, list, dict, dict | None]:
    """该正典的 (3 种子行, 最佳种子行, supports, slither 行)。**两段共用同一份拼行逻辑**。"""
    rows_all, rows_best = [], []
    canon = T.row_from_run(runs_dir, SEEDS)
    rows_all.append((method_label, canon))
    rows_best.append((method_label, T.row_from_run(runs_dir, [best])))
    for label, arm, _note in BASELINES + SENSITIVITY:
        rel = rel_of(arm, layout)
        if not (REPO / rel).exists():
            print(f"[warn] 缺 {rel}（该基线还没跑）——该行将显示为 —")
            continue
        rows_all.append((label, T.row_from_run(rel, SEEDS)))
        rows_best.append((label, T.row_from_run(rel, [best])))
    sl = slither_row(root_rel=sl_rel)
    if sl is not None:
        rows_all.append(("**Slither**（传统工具）", sl))
        rows_best.append(("**Slither**（传统工具）", slither_row([best], sl_rel)))
    supports = {supports_key: canon["support"]}
    if sl is not None:
        supports["Slither（分母不同）"] = sl["support"]
    return rows_all, rows_best, supports, sl


def canon_doc(runs_dir: str, with_buggy: bool = False) -> tuple[list[str], int, int]:
    """**§37 正典段**（池 453）——本函数输出必须与引入 buggy 段之前**逐字节相同**
    （唯一的例外：`with_buggy=True` 时在抬头加一条「本文件有两段」的指路 blockquote）。"""
    best = T.best_seed_from_runs(runs_dir, SEEDS)
    if best is None:
        raise SystemExit(f"🔴 {runs_dir} 下没有 results.json，无法选最佳种子")
    method_label = "**本文方法**（§37 正典）"
    rows_all, rows_best, supports, sl = _rows_for(
        "canon37", runs_dir, method_label, best, slither_root("canon37"),
        supports_key="本文方法与三基线共用（§37 正典 test）")

    doc: list[str] = []
    doc += ["# 5.3 对比表：本文方法 vs 三条论文基线（EGFL / MVD-HG / MANDO-LLM）",
            "",
            "> 程序生成（`scripts/collect_baseline_tables.py`）：**只搬运产物、只调 `metrics`**，"
            "不手抄、不重实现指标。逐类格与汇总列一律经 "
            "`collect_three_caliber_tables.render_table`。", "",
            f"> 🔴 **表 3–8 = 最佳种子口径**（判据 = 本文方法正典在 micro-F1@val_thr 上最高 ⇒ "
            f"**seed{best}**；全部行共用同一个种子，否则同一批行不是同一批模型）；"
            "**表 9–14 = 3 种子 mean±std 附录**（ddof=1）。"
            "⚠ 最佳种子口径下没有 ±，且本仓实测重跑抖动 ≈0.012 ⇒ **不得**据单种子差下「某方法更强」的结论。",
            "",
            "> 🔴 **表 1–2 = 跨口径总览（先读这两张）**：表 1 = 逐类 **binary-F1**（三篇论文的原生判决规则），"
            "表 2 = 各口径的汇总列一览（选口径用）。两者**都是零重训**的离线重算，"
            "与表 3–14 **同一批产物**，只是换算法。", "",
            *(["> 🔴🔴 **本文件有两段（两个正典）**：**§0–§二 = §37 正典（池 453）**；"
               "**文件末尾的「三、」= 含 `buggy_*` 的新正典（池 497）**。"
               "两段的 test 集**不是同一批合约**（46 vs 49）⇒ **跨段数字不可相减**；"
               "两段的三条基线连**特征配对方式都不同**（见「三、」§0 第 4 条）。", ""]
              if with_buggy else []),
            "## 0. 口径声明（引用本表前必读）", ""]
    doc += _canon_section0(runs_dir, sl)
    doc += ["**6）成本。** 训练时间与规模见 §2。三条基线的推理产物（`test_probs.pt`）已入库，"
            "全部指标可**离线重算、无需重训**。", "",
            "---", "", "## 1. 逐类 support（先读）", ""]
    doc += T.support_block(supports)
    doc += [T._thin_support_note(supports), "", "---", "",
            "## 2. 训练时间与规模（成本）", ""]
    doc += timing_block()
    doc += ["", "> `训练 (s)` = 训练循环净耗时；`总 wall (s)` = 含验证推理与阈值搜索的整段耗时。", "",
            "---", "", "## 3. 🔴 合约级二分类口径（三条基线论文的原生口径）", "",
            "**为什么必须并列这一块**：三条基线的论文报的都是**合约级二分类 F1**（有/无漏洞），"
            "而大纲 [411] 要求 5.3 **统一按七维多标签**评测。两个口径的**平凡下限相差 0.50**"
            "（七维 0.1224 vs 二分类 0.6199，实测）⇒ 只摆七维数字会把「任务本身更难」"
            "误读成「这些方法不行」。本块用**同一批产物**坍缩出二分类读数，"
            "坍缩规则 `max_c p_c >= t ⇔ any_c(p_c >= t)`（`decisions.md` §31 已机检），"
            "**不是**另训一个模型。", ""]
    doc += binary_caliber_block(runs_dir)
    doc += ["", "---", "", "## 4. 逐类二分类 F1（binary-F1）与全口径总览", "",
            "### 4.1 什么是 binary-F1", "",
            "**定义。** 把「这个合约有没有第 $c$ 类漏洞」当成一个**只有两个答案**的问题（有 / 没有）"
            "去算的 F1：",
            "",
            "$$F1_c=\\frac{2\\,TP_c}{2\\,TP_c+FP_c+FN_c}$$",
            "",
            "其中 $TP_c$ = 真值有第 $c$ 类、模型也判有的合约数；$FP_c$ = 真值没有、模型判有的；"
            "$FN_c$ = 真值有、模型判没有的。末列的**平均** = 7 个 $F1_c$ 的**算术平均**"
            "（每类等权，不受类大小影响）。",
            "",
            "**它与本文件表 3–14 的「逐类格」是不是一回事？** —— **公式完全相同**。"
            "多标签评测里的「第 $c$ 类 F1」**本身就是**该类的二分类 F1（同一个混淆矩阵）。"
            "🔴 **两者唯一的分歧在判决规则**：",
            "",
            "| 口径 | 模型形态 | 判决规则 | 平均列的算法 |",
            "| --- | --- | --- | --- |",
            "| **多标签**（大纲 [411] 主口径） | 一个模型出 7 个概率 | **七类共用一个阈值** $t$ | micro = 标签对加权；macro = 逐类等权 |",
            "| **逐类二分类**（三篇论文的原生形态） | 7 个**独立**二分类器 | **每类各有一个阈值** $t_c$ | 逐类等权（= 本表的「平均」列） |",
            "",
            "⇒ 由此得到**两条恒等式**（不是近似，本文件已逐位核对）：",
            "",
            "1. **@0.5 的 binary-F1 ≡ 三口径表的逐类格**（0.5 对七类相同，判据也相同），"
            "其**平均列 ≡ macro-F1@0.5**。故本文件**不另列** @0.5 版（那是同一批数字的第二次排印）。",
            "2. **@逐类阈值的 binary-F1 才是本块唯一新增的信息**——阈值从「七类共享」换成「逐类各一」。",
            "",
            "🔴 **「平均」列 ≠ micro-F1，二者不可互换**：micro 是**标签对加权**（样本多的类权重自然大，"
            "`uncheck`/`reentrancy` 这类大类主导），平均列是**逐类等权**（`dos` 只有 1 个正样本也占 1/7）。"
            "在测试集逐类 support 为 3/2/1/1/5/2/7 的这种极端不均下，两者实测可差 **0.10 以上**。",
            "",
            "**这个口径的合法性。** `metrics.py` 模块契约与 `论文开发手册.md` 早已裁定："
            "「**稀有类不在验证集上单独调阈**，per-class 阈值**仅作补充分析、不进主结果**」"
            "（`decisions.md` §13）。⇒ 本块**不进 5.3 的主表**，只回答「三篇论文报的那个数字，"
            "在**它们的判决规则**下我们这边是多少」。**本仓对本文方法的该口径读数早有存量产物**"
            "（`eval_results/calibration/summary.json`，由 `calibrate.py` 生成，含过拟合审计），"
            "本块把它**扩到三条论文基线**上，并**逐位对拍**（见下）。", ""]
    doc += per_class_binary_block(runs_dir, list(SEEDS))
    doc += ["",
            "### 4.2 代价：本口径的过拟合是**已量化**的", "",
            "`eval_results/calibration/summary.json::overfit_audit` 给的实测（本文方法，零重训）：",
            "",
            "| 种子 | val macro-F1（被优化的那一侧） | test macro-F1 | val→test 落差 | test **oracle** macro-F1 | 距 oracle 的遗憾 |",
            "| --- | --- | --- | --- | --- | --- |",
            "| 0 | 0.7541 | 0.7197 | 0.0344 | 0.8095 | 0.0898 |",
            "| 1 | 0.6984 | 0.5378 | **0.1606** | 0.7952 | **0.2574** |",
            "| 2 | 0.6762 | 0.6515 | 0.0247 | 0.8059 | 0.1544 |",
            "",
            "**逐类选出的阈值极不稳定**（同一个类、只换划分种子，`dos` 的极差达 **0.55**）——"
            "根因是 **val 上 `dos`/`front_running`/`time_manipulation` 各只有 1 个正样本**，"
            "在 1 个正样本上「调 F1 最优阈值」在数学上近乎无约束（总能取到 F1=1）。",
            "",
            "🔴 **所以引用表 1 时的强制声明（缺一不可）**：",
            "① 它是**补充口径**，不进 5.3 主表；② 它建立在 **val 每类 1–3 个正样本**上，"
            "**过拟合已量化**（val→test 落差最大 0.16，`dos` 阈值三种子极差 0.55）；"
            "③ 它与三口径表的 @0.5 版**同源**，不得当成两套独立证据；"
            "④ **不得**用本表宣称「比论文高」——它们的数据集、划分、类别数、支撑量都不同。",
            "",
            "> **一条有价值的正面结论（来自同一份审计）**：test **oracle** macro-F1 ≈ **0.80**，"
            "而逐类阈值实际只拿到 **0.636**。oracle 是在 test 上作弊选阈值，衡量的是「**阈值选对了能到多少**」"
            "⇒ **排序里带着的信息量支持约 0.80 的 macro-F1，实际只兑现了 0.636**。"
            "这把主库的瓶颈定位得很干净：**不在模型的排序能力**（AP/ROC-AUC 已在 0.76–0.98），"
            "**而在「用一个全局阈值去卡七类概率尺度差异极大的输出」这件事本身**。", "",
            "### 4.3 全口径总览：有哪些读数可以放", "",
            "同一批产物、不同算法（3 种子 mean±std）：", "",
            "## 表 2 —— 方法 × 口径 汇总列总览（3 种子 mean±std）", ""]
    doc += overview_block(runs_dir, list(SEEDS))
    doc += ["", "---", "", f"# 一、主口径：最佳种子（seed{best}）", ""]
    sub, n = _detail_tables(rows_best, 2)
    doc += sub
    doc += ["---", "", "# 二、附录：3 种子 mean±std", ""]
    sub, n = _detail_tables(rows_all, n)
    doc += sub
    return doc, n, best


def _canon_section0(runs_dir: str, sl) -> list[str]:
    """canon37 段的 §0 声明（原样保留；抽成函数只是为了两段各写各的，内容逐字未动）。"""
    doc: list[str] = []
    doc += ["**1）正典与池。** 本表正典 = **§37 正典**（`products/alldata/graphs_ft/ss{S}` + "
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
    for label, _arm, note in BASELINES:
        doc.append(f"- {label}：{note}")
    doc += ["",
            "⇒ 三者是**规模各异的「按论文重实现 / 驱动原码」**，**不是原作者的二进制**；"
            "**不得声称复现了作者原结果**，也不得把它们的差值解读为「方法优劣」——"
            "输入模态、图定义、节点特征来源三者**各自不同**。", ""]
    for label, _arm, note in SENSITIVITY:
        doc.append(f"- {label}：{note}")
    if sl is not None:
        n_in, n_an = sl["_denominator"]
        doc += [f"- **Slither**：分母不同 —— test 里 {n_in} 个合约只有 {n_an} 个被成功分析"
                f"（`status != ok` 的**不计入分母、也不记全零**）⇒ 它与三条基线的逐格 Δ **不可解读**；"
                "且它**不提供** `front_running` 检测项（该格是「无此项」而非「F1=0」），"
                "`buggy` 口径无逐合约产物 ⇒ 该口径整列 `—`。", ""]
    return doc


def buggy_doc() -> tuple[list[str], int]:
    """**含 `buggy_*` 的新正典段**（池 497）——追加在 §二 之后，表号顺延。

    🔴 与 canon37 段的差别**逐条列出**，因为读者最容易在这里做错比较：
     1. **池与 test 都换了**（497 / 49，划分重划）⇒ 跨段不可相减；
     2. **`buggy_*` 的标签是度量假象**（39/44 为 `1111111`）⇒ 必须并列 `clean_only` 列；
     3. **特征约定与 canon37 段不同**：本段用与 `--split-seed` **配对**的 `cb_ft_ss{S}`
        （与 `runs/buggy_canon/seed{S}` 同款），而 canon37 段的三条基线三种子**都用 `ss0`**
        （历史事实）。两段各自内部可比、**跨段不可比**。
    """
    layout = "buggy"
    runs_dir = LAYOUTS[layout]["runs_dir"]
    method_label = "**本文方法**（含 `buggy_*` 新正典）"
    # 🔴 最佳种子必须有 3/3 的 results.json：`T.best_seed_from_runs` 在缺文件时**静默回退 seeds[0]**
    #    （它永不返回 None），于是「某个种子没跑完」会被读成「最佳种子就是 seed0」。
    missing = [s for s in SEEDS if not (REPO / runs_dir / f"seed{s}" / "results.json").exists()]
    if missing:
        raise SystemExit(f"🔴 {runs_dir} 缺 seed{missing} 的 results.json——"
                         f"先跑完三种子再出表（否则最佳种子会静默取 seed0）")
    # 🔴 **缺任何一个基线就硬失败，不静默出少几行的表**：`_rows_for` 对缺产物是
    # `continue`（canon37 段沿用该行为，因为"某基线还没跑"在那里是合法的中间态），
    # 但 `--with-buggy` 是**显式**要求出这一段的，缺行会让「497 池上没有这条基线」
    # 与「它还没跑完」看起来一模一样。
    absent = [f"{arm}{LAYOUTS[layout]['suffix']}"
              for arm in [a for _l, a, _n in BASELINES + SENSITIVITY]
              if not (REPO / rel_of(arm, layout)).exists()]
    if absent or slither_row(root_rel=slither_root(layout)) is None:
        raise SystemExit(f"🔴 --with-buggy 需要的产物尚未齐（缺 {absent or []}"
                         f"{'；slither_buggy 也缺' if slither_row(root_rel=slither_root(layout)) is None else ''}）"
                         f"——先跑 `python scripts/run_baselines.py --layout buggy` 与 "
                         f"`scripts/baseline_static_tools.py --tag buggy`")
    best = T.best_seed_from_runs(runs_dir, SEEDS)
    rows_all, rows_best, supports, sl = _rows_for(
        layout, runs_dir, method_label, best, slither_root(layout),
        supports_key="本文方法与三基线共用（含 `buggy_*` 新正典 test）")

    doc: list[str] = []
    doc += ["---", "", "---", "",
            "# 三、含 `buggy_*` 的主库（池 497 · 新正典）", "",
            "> 🔴🔴 **本段与上面 §0–§二 不是同一个 test 集**（46 → **49**，且 8:1:1 重划过）"
            "⇒ **跨段数字不可直接相减**，只能看**方向**。本段回答的是「把被剔除的注入噪声合约"
            "补回池里之后，基线与本文方法的**差距形状**是否改变」。", "",
            f"> 🔴 **表 17–22 = 最佳种子口径**（判据 = 本文方法在该正典的 micro-F1@val_thr 上最高 ⇒ "
            f"**seed{best}**，全部行共用同一个种子）；**表 23–28 = 3 种子 mean±std 附录**（ddof=1）。",
            "",
            "## 0. 口径声明（引用本段前必读）", "",
            "**1）正典与池。** `products/alldata/graphs_ft_buggy/cb_ft_ss{S}` + "
            "`products/alldata/splits/withbuggy_snapshot/split_seed{S}.json`，池 **497**、"
            "train/val/test = **398/50/49**；本文方法 = `runs/buggy_canon`（任务 2，"
            "`decisions.md` §43–§46）。", "",
            "**2）🔴 `buggy_*` 标签是度量假象，故本段必须并列 `clean_only` 诊断列。**"
            "那 44 个补回的合约里 **39 个标签为 `1111111`、5 个为 `0100011`**"
            "（上游按「每类各放一份」复制，`decisions.md` §18.4/§46.2）——"
            "模型「一律报有漏洞」即可在它们身上拿满分。⇒ **不得**据本段声称"
            "「补回 buggy 提升了检测能力」。代价已量化（`experiments/buggy_canon_summary.md` §3，3 种子）："
            "剔掉 test 里那 7–8 个 `buggy_*` 后，本文方法 **micro 掉 0.10–0.16、macro 掉 0.33–0.61**。", "",
            "**3）三口径与训练口径：与 §0 第 2/3 条逐字相同**（同一套超参、同一套已知口径差、"
            "同一批 `run_baselines.PIPELINE` 训练参数）。**本文方法侧唯一的不同是正典**；"
            "**基线侧另有一处不同（特征配对方式），见下条第 4 条**。", "",
            "**4）🔴 特征约定与上面那段不同（跨段不可比的一条，必须单独声明）：**"
            "本段三条基线用的是**与 `--split-seed` 配对的** `cb_ft_ss{S}`，"
            "而上面 canon37 段三条基线**三个种子用的都是 `graphs_ft/ss0`**（历史事实，已在库的产物如此）。"
            "配对本仓是硬要求（`AGENTS.md` 语义锁死项）：**`_cb.pt` 的 CodeBERT 节点行逐张量随 `ss` 变**，"
            "实测 ss0/ss1/ss2 全不同、跨正典更不同 ⇒ 不配对就是拿另一套编码器特征训练。"
            "⇒ **两段各自内部可比，跨段除了「池」还差着「特征配对方式」**。", "",
            "**5）离线覆盖率（分母是否相同）。**", ""]
    doc += coverage_block(layout)
    doc += ["",
            "> ⚠ 三条基线的 `test_probs.pt` 行数**应当**等于 49（本文方法 test 的合约数）。"
            "**MVD-HG 在 seed1 上少 1 个**（该合约在任何已装 solc 下都编不出 compact AST）"
            "⇒ **该行分母是 48，与其余行逐格不可解读**，读表时必须带着这条。", "",
            "**6）实现性质与口径损失**：三条基线的实现性质**与本段无关**（与池无关），"
            "逐行声明见上面 §0 第 5 条，**同样适用**，**不得**声称复现了作者原结果。", "",
            "**7）成本。** 训练时间与规模见下节；本文方法该正典的训练成本见 "
            "`experiments/buggy_canon_summary.md` §1（wall/train/每 epoch 秒/graphs per second）。",
            "", "---", "", "## 1. 逐类 support（先读）", ""]
    doc += T.support_block(supports)
    doc += [T._thin_support_note(supports), "",
            "> 🔴 **`clean_only` 侧的 support 极薄、且有的类会归零**（实测 seed1 为 "
            "`1/1/0/0/4/0/6`，`time_manipulation` 的 test 正样本**全部来自注入合约**）"
            "⇒ 零支撑类按 `zero_division=0` 计 F1=0，**`clean_only` 的 macro 因此被人为压低**："
            "它同时含 (a) 假象消失（真实效应）与 (b) 稀有类正样本被抽走（度量副作用）"
            "⇒ **`clean_only` 的 Δmacro 只能读作「假象的量级」，`Δmicro` 才是干净的那个数**"
            "（`experiments/buggy_canon_summary.md` §4）。"
            "⚠ 本节的薄支撑判定只覆盖**全 test**（`support_block` 的输入）；`clean_only` 侧的薄支撑"
            "见上一句的人列数字，不另立表。", "",
            "---", "", "## 2. 训练时间与规模（成本）", ""]
    doc += timing_block(layout)
    doc += ["", "> `训练 (s)` = 训练循环净耗时；`总 wall (s)` = 含验证推理与阈值搜索的整段耗时。"
            "⚠ 基线三臂为 `--early-stop-patience 20`（与 canon37 段同款，见 §0 第 3 条）；"
            "本文方法该正典为 `patience 5`，其成本另见 `buggy_canon_summary.md` §1。", ""]
    doc += _cross_canon_note()
    doc += ["", "---", "", "## 3. 🔴 合约级二分类口径（三条基线论文的原生口径）", "",
            "**为什么必须并列这一块**：三条基线的论文报的都是**合约级二分类 F1**（有/无漏洞），"
            "而大纲 [411] 要求 5.3 **统一按七维多标签**评测。本块用**同一批产物**坍缩出二分类读数"
            "（坍缩规则 `max_c p_c >= t ⇔ any_c(p_c >= t)`，`decisions.md` §31 已机检），"
            "**不是**另训一个模型。"
            "🔴 **本段的平凡下限与 canon37 段不同**（`buggy_*` 的全 1 标签把「本来就有漏洞」的比例"
            "从 45.7% 抬到约 51%），故**逐种子可变**——表尾的读法句已按本段数据现算。", ""]
    doc += binary_caliber_block(runs_dir, layout=layout, method_label=method_label)
    doc += ["", "---", "", "## 4. 逐类二分类 F1（binary-F1）与全口径总览", "",
            "定义、两条恒等式、以及「本口径仅作补充、不进 5.3 主表」的合法性裁定，"
            "与上面 §4.1 逐字相同（`decisions.md` §13/§49）。本段**不重复**那段推导，"
            "只给本段的读数。", ""]
    doc += per_class_binary_block(runs_dir, list(SEEDS), layout=layout,
                                 method_label=method_label,
                                 table_title="## 表 15 —— 逐类 binary-F1 @逐类验证集阈值"
                                             "（3 种子 mean±std）",
                                 xref="（见本段表 19 与表 25）")
    doc += ["",
            "> 🔴 **本段该口径的过拟合比 canon37 段更重**：`clean_only` 侧 val/test 的逐类正样本"
            "低到 **0–6**，在 0 个正样本上调阈值在数学上无约束。"
            "故本段表 15 **只作描述性呈现**，**不得**据此下「某方法在此口径更强」的结论。", "",
            "### 4.3 全口径总览：有哪些读数可以放", "",
            "同一批产物、不同算法（3 种子 mean±std）：", "",
            "## 表 16 —— 方法 × 口径 汇总列总览（3 种子 mean±std）", ""]
    doc += overview_block(runs_dir, list(SEEDS), layout=layout, method_label=method_label,
                          xref_buggy_thr="（见本段表 21、表 27）",
                          xref_pcbin="（见本段表 19、表 25）")
    # 🔴 标题**必须带段号**：本段与 canon37 段各自有一组「主口径 / 附录」，
    #    若都写 `# 一、`/`# 二、`，同一个文件里就有两套同名标题（本段初版即如此）。
    doc += ["", "---", "", f"# 三之一、主口径：最佳种子（seed{best}）", ""]
    sub, n = _detail_tables(rows_best, 16)
    doc += sub
    doc += ["---", "", "# 三之二、附录：3 种子 mean±std", ""]
    sub, n = _detail_tables(rows_all, n)
    doc += sub
    return doc, n


def main() -> None:
    ap = argparse.ArgumentParser(description="5.3 基线三口径对比表")
    ap.add_argument("--runs-dir", default="runs", help="本文方法的正典 run 目录。")
    ap.add_argument("--out", default="", help="写入的 markdown 路径；留空只打印。")
    ap.add_argument("--with-buggy", action="store_true",
                    help="在 §二 之后追加「三、含 `buggy_*` 的主库（池 497）」整段"
                         "（本文方法 = `runs/buggy_canon`，基线 = `eval_results/baseline/*_buggy`）。"
                         "缺产物即硬失败，不静默出 `—` 行。")
    args = ap.parse_args()

    doc, n, best = canon_doc(args.runs_dir, with_buggy=args.with_buggy)
    if args.with_buggy:
        sub, n = buggy_doc()
        doc += sub

    text = "\n".join(doc) + "\n"
    if args.out:
        p = REPO / args.out
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
        k = "两段" if args.with_buggy else "一段"
        print(f"[collect] 已写 {p}（{len(text)} 字符，{k}共 {n} 张明细表 + 两段的表 1/2/15/16 总览；"
              f"canon37 最佳种子 seed{best}）")
    else:
        print(text)


if __name__ == "__main__":
    main()
