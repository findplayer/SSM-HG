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
# 🔴 「某工具**不提供**哪些检测项」的唯一定义在 `collect_traditional_tools.no_detector_idx`
#    （活代码 `static_tool_adapters` 优先、Slither 退回落产物快照）——这里只调用，不另写一份清单。
import collect_traditional_tools as C                                    # noqa: E402

NAMES = T.NAMES
SEEDS = T.SEEDS
CALIBERS = T.CALIBERS

# ---------------------------------------------------------------- 布局（正典选择）
# 🔴 **2026-10-01 口径对调（用户裁定）**：池 497 升为正典（默认），池 453 降为对照口径。
#    两个 key 的**字面名与全部路径字段一律未改**（它们与未改名的产物路径绑定），
#    只有**角色**互换 ⇒ 读到 `canon37` 时不要按字面当「正典」，它现在是**对照口径**（追加段）。
# 🔴 两段（正典 池 497 / 对照口径 池 453）**共用同一份行定义与同一套渲染**，
#    只有「产物根」这一件事不同 ⇒ 用后缀派生，不复制第二份行清单
#    （复制会让两张表的行集合漂移——本仓点过名的一类问题）。
LAYOUTS = {
    "canon37": {"suffix": "", "runs_dir": "runs",
                "split_dir": "products/alldata/splits",
                "graph_dir": "products/alldata/graphs_ft_p2/cb_ft_ss{S}",
                "title": "对照口径（池 453）"},
    "buggy": {"suffix": "_buggy", "runs_dir": "runs/buggy_canon",
              "split_dir": "products/alldata/splits/withbuggy_snapshot",
              "graph_dir": "products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S}",
              "title": "正典（池 497）"},
}
# 🔴 `split_dir` / `graph_dir` 与 `baseline_common.LAYOUTS` **必须逐字相同**：
#    它们是「这是哪个正典」的判据，而本文件只出表、不跑批 ⇒ 漂移了不会报错，
#    只会让表头标注的来源与实际训练时用的池不一致（`tests/test_baseline_tables.py` 有守卫）。


def rel_of(arm: str, layout: str = "buggy") -> str:
    """臂名 + 布局 → 产物相对路径。默认 = **正典**（2026-10-01 起 = 池 497 / `_buggy`）。"""
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


def coverage_block(layout: str = "buggy") -> list[str]:
    """三条基线的**离线覆盖率**（分母是否与本文方法相同）—— 逐行读各自 results.json。

    🔴 **test 覆盖按「全部种子取并集」判**（不是只看 seed0）：正典段（池 497）实测 MVD-HG
    在 **seed1** 上掉了 1 个 test 合约（对照段（池 453）是三个种子都完整）⇒ 只看 seed0 会
    把它报成「test 完整」，而那一行的分母其实是 48 —— 正是本表最不能静默出错的一格。
    「训练集剔除」仍按 seed0 报。
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


def slither_row(seeds=None, root_rel: str = "eval_results/baseline/slither_buggy",
                tool: str | None = None) -> dict | None:
    """Slither 的 `seed{S}_eval.json` → 与 `row_from_run` 同构的行（某池无产物 ⇒ `—`）。

    🔴 **分母不同**：`n_analyzed` < `n_in_split`（分析失败/不支持的合约**不计入分母、也不记全零**），
    故它与三条基线的逐格 Δ **不可解读**。

    🔴 `root_rel` **必须可传**：它原先硬编码 `slither_alldata`。若忘了参数化，正典（池 497）
    段会**静默出现对照段（池 453）的 Slither 数字**（两份 json 都长一个样、都叫
    `seed{S}_eval.json`），是本表最隐蔽的一类错（`decisions.md` §52.6）。
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
    out = _blank_unsupported(out, tool, root_rel, support)
    return {"cells": out, "support": support, "_denominator": (n_in, n_an),
            "_seeds": seeds}


def _blank_unsupported(out: dict, tool: str | None, root_rel: str, support: dict) -> dict:
    """把**结构性拿不到值**的格子置 `None` ⇒ `_ms` 渲染成 `—`（用户 2026-09-26 裁定）。

    两种情形**都置 `None`**，但成因不同，表下行注必须分开说：
      ① **该工具不提供此检测项**（如 Slither 无 `front_running` 检测器）——
         那一格的 0 是"工具没这项"，画成数字就会被读成"测出来是 0"；
      ② **该划分里逐类 support 全为 0**（如 Securify 的可分析集恰好全是干净合约）——
         那一整行**不可评估**，`micro_f1` 落在产物里的 `0.0` 是 `zero_division=0` 的占位。
    ⚠ **只改渲染、不改指标**：产物 JSON 里的原始数字一个字节都不动；
       `micro`/`macro` 汇总列**也不置空**（它们按七类全量聚合，是"作为七类检测器"的真实读数）。
    """
    if tool is None:
        return out
    prod = REPO / (root_rel + ".json")
    raw_d = json.loads(prod.read_text(encoding="utf-8")) if prod.exists() else {}
    miss = C.no_detector_idx(tool, raw_d)
    sup_lists = support.get("fixed_0.5") or []
    deg = bool(sup_lists) and all(sum(s) == 0 for s in sup_lists)
    for wp in out:
        for cal in out[wp]:
            if deg:
                # 整行 `—`：**逐种子写 `([None]*7, None)` 而不是 `[]`** —— 后者会让 `render_table`
                # 走「空 pairs」分支、汇总格渲染成不加粗的 `—`，与其余行的 `**—**` 不一致（纯排版，
                # 但论文表里一眼能看出）。逐格置 None 则走正常分支，逐类与汇总都自然成 `—`。
                out[wp][cal] = [([None] * len(NAMES), None) for _ in out[wp][cal]]
            else:
                # 🔴 **裁定 A（2026-09-26 用户裁定）**：某个种子上该类的 **support=0 ⇒ F1 是 0/0 未定义**
                # （`zero_division=0` 会把它记成 `0.0`）。把它当「报错了」计入均值，等于把「没有样本可评」
                # 当成「预测失败」⇒ **该种子在这一格置 None、不进均值**（不是置 0）。
                # 受影响格在报告第四节以 `‡` 逐格列出（本表横跨十几张表，注记统一放行注里指过去）。
                out[wp][cal] = [
                    ([None if (i in miss or (i < len(sup_lists[j] if j < len(sup_lists) else [])
                                             and (sup_lists[j])[i] == 0)) else v
                      for i, v in enumerate(f1)], agg)
                    for j, (f1, agg) in enumerate(out[wp][cal])]
    return out


def slither_root(layout: str = "buggy") -> str:
    """Slither 产物根。🔴 **逐段不同**：正典段（池 497）是 `slither_buggy`，对照段（池 453）
    是 `slither_alldata`。

    两段的 json 同名同形（`seed{S}_eval.json`），**唯一能分辨的是目录名**——
    故这个函数是防「453 池数字混进 497 池表」那类静默错的唯一一道。
    """
    return ("eval_results/baseline/slither_alldata" if layout == "canon37"
            else f"eval_results/baseline/slither{LAYOUTS[layout]['suffix']}")


# --------------------------------------------------------------------------- 5.3 六个传统工具
# 顺序 = 论文 5.3 表里的顺序（大纲 `改II` 段落 [400]–[411]）。
TRADITIONAL: tuple[str, ...] = ("slither", "mythril", "manticore", "smartcheck", "securify", "oyente")
TRAD_LABEL: dict[str, str] = {
    "slither": "Slither", "mythril": "Mythril", "manticore": "Manticore",
    "smartcheck": "Smartcheck", "securify": "Securify", "oyente": "Oyente",
}
# 行标记前缀。`<trad:slither>` 就是原先的 `<slither>` ⇒ 旧代码路径逐字兼容。
TRAD_MARK = "<trad:"


def trad_root(tool: str, layout: str = "buggy") -> str:
    """某传统工具的产物根。🔴 **逐工具、逐段都不同**（`slither_alldata` 是历史命名，不带工具后缀的
    那一层是 `_alldata`），故这里逐条列出，不做字符串拼接的猜测。"""
    if tool == "slither":
        return slither_root(layout)
    suffix = "" if layout == "canon37" else LAYOUTS[layout]["suffix"]
    return f"eval_results/baseline/{tool}_alldata{suffix}"


def available_trads(layout: str = "buggy") -> list[str]:
    """已有产物的传统工具（缺的**不静默出行**，而是不出行并在表下点名）。"""
    return [t for t in TRADITIONAL
            if (REPO / trad_root(t, layout) / "seed0_eval.json").exists()]


def missing_trads(layout: str = "buggy") -> list[str]:
    return [t for t in TRADITIONAL if t not in available_trads(layout)]


def trad_row(tool: str, seeds=None, layout: str = "buggy") -> dict | None:
    """复用 `slither_row`：六工具的 `seed{S}_eval.json` 由**同一个** `evaluate()` 写出，
    格式同形 ⇒ 同一个行构造器就够（这正是"评测只有一份实现"带来的便利）。

    🔴 `tool=` **必须传**（2026-09-26 加）：`slither_row` 靠它把「该工具**不提供**此检测项」的类
    画成 `—`。漏传不会报错，只会让那些格子又变回 `0.0000` —— 而那正是要被消灭的读法。
    """
    return slither_row(seeds, trad_root(tool, layout), tool=tool)


def trad_label(tool: str) -> str:
    return f"**{TRAD_LABEL[tool]}**（传统工具，分母不同）"


# 🔴 **传统工具行里 `—` 的读法**（用户 2026-09-26 裁定：没有该项能力的类**直接画 `—`**，
# 不把结构性 0 摆成一个看起来像成绩的数字）。两段共用同一份文字，避免两边说法漂移。
TRAD_DASH_NOTE = (
    "> 🔴 **传统工具行里的 `—` = 「结构性拿不到值」，不是 0**，两种成因**都不得**读成"
    "「该工具在此类上 F1=0」：① **该工具不提供此检测项**（Slither 无 `front_running`；"
    "Smartcheck 无 `reentrancy`/`front_running`；Oyente 无 `dos`/`uncheck`；"
    "Manticore 无 `dos`/`time_manipulation`）；② **整行不可评估** —— 该工具可分析的合约集里"
    "逐类 support 全为 0（Securify：只吃得下 pragma 0.5.x，而真实池里 0.5.x 的 147 个合约"
    "**恰好一个漏洞都没有**）。"
    "③ 某格**只用了 2 个种子**（该种子上**该类 support=0** ⇒ F1 是 0/0 未定义，"
    "按用户 2026-09-26 裁定**剔除**、不当成「预测失败」计入；受影响格在报告第四节以 `‡` 逐格列出，"
    "本表不逐格标注）——格子里看不出来，读跨种子均值时必须带着。"
    "⚠ 汇总列（`micro`/`macro`）**不因 `—` 而改变**：它们仍按七类全量聚合，"
    "是「该工具作为七类检测器」的真实读数 —— **本表是方法间对比表，只有这个口径与本表的其他行同尺**。"
    "若要看「只算该工具有检测项的类」的 micro/macro（会**系统性偏高**，因为分母小了），"
    "见 `experiments/traditional_tools_results.md` 第四节的 **† 两列**——"
    "**那两列不得横比到本表**。逐条判据见同报告第四节（交叉表 + 支持度表）"
    "与第五节（覆盖率不是随机缺失）。")



def _trivial_table_stats(run_rel: str, seeds) -> dict:
    """从**本文方法**该段的 `test_probs.pt` 算两个平凡下限与正例率（供本块的读法句用）。

    🔴 **必须从数据算，不能写死**：对照段（池 453）的「二分类 0.62 / 七维 0.12」是
    那批产物的性质，**换到正典段（池 497）就全变了**——实测七维平凡下限从 0.12 抬到约 **0.31**
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


def binary_caliber_block(runs_dir: str, layout: str = "buggy",
                         method_label: str = "**本文方法**（正典）") -> list[str]:
    """**合约级二分类**口径对照（三条基线论文的原生口径）——解释「为什么七维 F1 看起来低」。

    🔴 **为什么必须并列这一块**：三条基线的论文报的都是**合约级二分类 F1**（有/无漏洞），
    而大纲 [411] 要求 5.3 **统一按七维多标签**评测。两个口径的**平凡下限差 0.50**
    （对照段（池 453）实测 七维 0.1224 vs 二分类 0.6199）⇒ 只看七维数字会把「任务更难」
    误读成「这些方法不行」。本块给出**同数据、同划分、同产物**下的二分类读数，
    并**强制附上平凡下限**。

    坍缩规则：`max_c p_c >= t ⇔ any_c(p_c >= t)`（`decisions.md` §31 已机检），
    故合约级预测 = `probs.max(axis=1) >= thr`，**不是**另训一个模型。

    🔴 分母与读法句里的四个数（合约数 / 二分类平凡下限 / 七维平凡下限 / 正例率）
    **一律由数据算**（见 `_trivial_table_stats`）：正典段（池 497）的分母是 **49** 不是 46，
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
    # 🔴 **canon37（对照段，池 453）的分句逐字保留原文**（该段数字已发布、已被人引用；
    #    改成现算会让每一次重生成都动到已发布的行）。**buggy（正典段，池 497）必须现算**——
    #    池换了之后分母（49 不是 46）与两个平凡下限都变了，写死的句子会"看着仍权威"却已失真。
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

    只用 `runs`（对照段，池 453——存量审计产物即出自它，2026-10-01 口径对调后它不再叫正典）
    时才有可比对象。不一致即**拒绝**——本仓的规矩是宁可硬失败也不静默产出两套数字
    （同 `collect_per_class_f1.py --check` 的做法）。
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


def per_class_binary_block(runs_dir: str, seeds, layout: str = "buggy",
                           method_label: str = "**本文方法**（正典）",
                           table_title: str = "## 表 1 —— 逐类 binary-F1 @逐类验证集阈值"
                                              "（3 种子 mean±std）",
                           xref: str = "（见 §一 的表 5、§二 的表 11）") -> list[str]:
    """§4.1：逐类二分类 F1（binary-F1）@逐类验证集阈值。

    🔴 `table_title`/`xref`/`method_label`/`layout` 全部外置：本函数被**两段**（正典 池 497 /
    对照口径 池 453）共用，表号与「见哪几张表」的交叉引用逐段不同；写死会让正典段指向
    对照段的表号。
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
    sl_note = ""
    for tool in available_trads(layout):
        r = trad_row(tool, seeds, layout)
        if r is None:
            continue
        # 传统工具本来就是若干条独立规则探针（各自自带判决门槛）⇒ 它的 @0.5 行**就是**
        # 逐类二分类行，不存在"另一个工作点"。两格同源，不编数。
        rows.append((trad_label(tool),
                     {"cells": {PC_WP: {PC_CAL: r["cells"]["fixed_0.5"]["macro"]}}}))
        if not sl_note:
            n_in, n_an = r["_denominator"]
            sl_note = (f"⚠ 传统工具的分母与其余行不同（test {n_in} 个合约只有 {n_an} 个被成功分析），"
                       if n_in else "⚠ 它的分母与其余行不同，")
    miss = missing_trads(layout)
    if miss:
        # 🔴 措辞是「**无产物**」而非「未接入」（2026-09-26 更正）：六个工具的**适配器 2026-09-25 已全部实现**，
        # 缺行只可能是「该池没跑」或「跑了但没跑完」——写成「未接入」会让读者以为工具没实现。
        sl_note += ("⚠ **无产物**：" + "、".join(TRAD_LABEL[t] for t in miss)
                    + "（`eval_results/baseline/<工具>_alldata/` 无 `seed0_eval.json` ⇒ 表中无行；"
                      "**不得**读成「该工具测出来是 0」）。")

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
            "传统工具的行里有 `—` ⇒ 成因见上面第 4 条的 `—` 读法（**不是** F1=0），跨行 Δ 不可解读。",
            "> ⚠ **本表的 @0.5 工作点不另列**：0.5 对七类相同，故那一版**逐位等于** micro/macro 表的逐类格，"
            "其平均列**恒等于 macro-F1@0.5**" + xref + "。"
            "⇒ 本表相对三口径表的**唯一新增信息**就是「阈值逐类独立」这一件事，"
            "这一点在下面 §4.2 有代价说明。"]
    if canon:
        chk = _pc_crosscheck(runs_dir, canon)
        if chk:                      # buggy 段无存量审计产物可比 ⇒ 不补空行
            out += ["", chk]
    return out


def overview_block(runs_dir: str, seeds, layout: str = "buggy",
                   method_label: str = "**本文方法**（正典）",
                   xref_buggy_thr: str = "（见 §一 的表 7、§二 的表 13）",
                   xref_pcbin: str = "（见 §一 的表 5、§二 的表 11）") -> list[str]:
    """§4.2：各口径汇总列总览（"有哪些好看的读数可放"）。

    🔴 `method_label` / `layout` / 两处交叉引用外置的理由同 `per_class_binary_block`：
    本函数被两段共用，**表号逐段不同**。表尾那两句读法里的平凡下限也**从数据算**
    （`_trivial_table_stats` / `_below_trivial_note`），不写死。
    """
    entries = [(method_label, runs_dir)] + \
              [(lbl, rel_of(arm, layout)) for lbl, arm, _n in BASELINES + SENSITIVITY]
    # 传统工具无逐合约预测 ⇒ 逐类 binary / 合约级 binary / mAP 三列**不存在**（记 `—`，不编数）；
    # micro / buggy / macro 三列有（来自它的逐类聚合 json），故仍立行。
    for tool in available_trads(layout):
        entries.append((trad_label(tool), f"{TRAD_MARK}{tool}>"))

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
        # 🔴 传统工具走 `<trad:名>` 标记（原先只有 `<slither>` 一个值）。
        # 它们的产物没有逐合约概率 ⇒ 逐类 binary / 合约级 binary / mAP 三列记 `—`，**不编数**。
        is_sl = rel.startswith(TRAD_MARK)
        r = trad_row(rel[len(TRAD_MARK):-1], seeds, layout) if is_sl else T.row_from_run(rel, seeds)
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
        # 🔴 `best` 可能是 `None`：整行都是 `—` 的方法（如 Securify —— 可分析集里没有正样本，
        # `_blank_unsupported` 已把该行置空）**没有任何一列配叫「本行最高」**。
        # 原先这里直接 `disp[best]` ⇒ `KeyError: None`（2026-09-26 把该行改成 `—` 时暴露）。
        lines.append(f"| {label} | " + " | ".join(cell[k] for k in
                     ("micro05", "micro_thr", "buggy05", "buggy_thr", "macro05",
                      "pcbin", "cbbin", "mAP")) + f" | **{disp[best] if best else '—'}** |")
    st = _trivial_table_stats(runs_dir, seeds)
    mf = st["micro_floor"] if st else float("nan")
    bf = st["binary_floor"] if st else float("nan")
    # 🔴 同 `binary_caliber_block`：canon37（对照段）的两句读法**逐字保留原文**，
    #    buggy（正典段）现算。
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
              "是唯一不能用「阈值没调好」解释的一列——它的高低直接反映排序能力。"
              "口径 = **macro AP**（逐类 PR-AUC 仅对 support>0 的类取平均，"
              "`metrics.mean_average_precision`）；它是**逐类平均**，与 PR 曲线图上的 "
              "**micro-AP**（标签对级展平后排序）**不是同一个数**，两者都合法但**不可互引**"
              "（两段的数值各自见本段表 2 与 `eval_results/figures/pr_curves.json`）。",
              "> 🔴 **六行传统工具的 mAP 恒为 `—`：不是缺数，是不可定义。** 它们的产物是逐合约的"
              "**二值规则命中**（`classes` ∈ {0,1}⁷；工具自带的 `checks` 只有检测项名、**无置信度**）"
              "⇒ **没有可排序的分数**，PR 曲线退化成一个点、AUC 无定义。硬填一个数只能是把该工作点的 "
              "precision 换个名字（对二值分数，sklearn 的 AP **恒等于** precision），"
              "**不含任何排序信息**，属本仓「不编数」约定明令禁止。"
              "它们的排序能力**不是没测，是没有可测的对象**；论文里必须写「该工具不输出置信度，"
              "故不参与 PR-AUC / mAP 比较」，**不得**写「未测」或留空让人以为漏跑。",
              f"> 🔴 **「本行最高」只是口径指路，不是「好看」的证明**：{low_note}"
              "⇒ 跨行比较只能同列相比，且**必须**带上 §0 的实现性质声明。"]
    return lines


def _below_trivial_note(runs_dir: str, layout: str) -> str:
    """「哪些行的**合约级二分类**读数**不高于**该口径的平凡下限」——**从数据算，不写死**。

    对照段（池 453）原来是写死的（「EGFL 两行与 MANDO 行的最高列 0.6199 / 0.5254 / 0.6178
    都不高于 0.6199」）。换到正典段（池 497）后平凡下限变成另一组数（且逐种子可变），
    写死的句子会**看起来仍然权威**却已失真。

    ⚠ **只说「合约级二分类」这一列，不说「最高列」**：本函数只算得出这一列的平凡下限，
    而某行的实际最高列**可能不是它**——实测正典段（池 497）EGFL-ownlr 的最高列是
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


def _canon_timing_row(layout: str, seed: int) -> dict | None:
    """**本文方法**该种子的规模/成本行——从产物复算，**不手抄**（用户 2026-09-24 要求）。

    🔴 `best_epoch` **不在 `config.json` 里**（`train.py` 只把 `timing` 的汇总量写进 config），
    故从 `log.txt` 的逐 epoch JSONL 复算，判据与 `train.py::best_monitor` **逐字相同**：
    严格 `>` ⇒ 并列取**第一个**最大值；multi 臂看 `val_micro_f1`、binary 臂看 `val_binary_ap`。
    取不到就返回 `None`，**不猜**（宁可出 `—`）。"""
    run_dir = REPO / LAYOUTS[layout]["runs_dir"] / f"seed{seed}"
    cfg_f, log_f = run_dir / "config.json", run_dir / "log.txt"
    if not cfg_f.exists():
        return None
    cfg = json.loads(cfg_f.read_text(encoding="utf-8"))
    t = cfg.get("timing") or {}
    derived = cfg.get("derived") or {}
    head = derived.get("head", "multi")
    key = "val_binary_ap" if head == "binary" else "val_micro_f1"
    best_epoch = None
    if log_f.exists():
        best_val = float("-inf")
        for ln in log_f.read_text(encoding="utf-8").strip().splitlines():
            if not ln.strip():
                continue
            row = json.loads(ln)
            v = row.get(key)
            if v is not None and float(v) > best_val:      # 严格 > ⇒ 与 train.py 的并列取第一致
                best_val, best_epoch = float(v), int(row["epoch"])
    n_params = (derived.get("parameter_report") or {}).get("total_params")
    return {
        "params_m": (n_params or 0) / 1e6 if n_params else None,
        "best_epoch": best_epoch,
        "train_seconds": t.get("train_seconds"),
        "seconds_per_epoch": t.get("epoch_seconds_mean"),
        "wall_seconds": t.get("run_wall_seconds"),
        "device": (cfg.get("environment") or {}).get("device"),
    }


def _inputs_block(layout: str = "buggy") -> list[str]:
    """**表前**标注：本表各行的（a）图/特征来源、（b）逐种子项目数量（用户 2026-09-24 要求）。

    🔴 数量**逐种子从产物读**（`results.json::n_*_graphs`、`config.json::derived`），不写死——
    两段的池不同（453 / 497），且基线因编译失败会**逐种子掉样本**（MVD-HG 实测 train 357/357/358、
    val 45/45/44），写死必错。本文方法的 test 数取自 `split_seed{S}.json`。"""
    L = LAYOUTS[layout]
    lines = ["| 行 | 图 / 特征来源（逐种子） | train / val / test（seed 0 / 1 / 2） |",
             "| --- | --- | --- |"]
    # ---- 本文方法 ----
    per = []
    for s in SEEDS:
        cfg_f = REPO / L["runs_dir"] / f"seed{s}" / "config.json"
        sp_f = REPO / L["split_dir"].format(S=s) / f"split_seed{s}.json"
        if not cfg_f.exists() or not sp_f.exists():
            per.append("—")
            continue
        d = json.loads(cfg_f.read_text(encoding="utf-8")).get("derived") or {}
        sp = json.loads(sp_f.read_text(encoding="utf-8"))
        per.append(f"{len(sp['train'])}/{len(sp['val'])}/{len(sp['test'])}"
                   if d else "—")
    lines.append(f"| **本文方法** · {L['title']} | `{L['graph_dir'].format(S='{S}')}`"
                 f"（微调 CodeBERT 重编码；结构软链自 `graphs/`） | {'、'.join(per)} |")
    # ---- 三条论文基线（⚠ 来源列**不得嵌套反引号**：markdown 里内层反引号会截断外层代码 span）----
    roots = {"mvdhg": "`products/alldata/baseline/mvdhg{sfx}/`"
                      "（`sol_source` / `AST_json` / `feat` 三类离线件）",
             "egfl": "`products/alldata/baseline/egfl{sfx}/`（`seq` / `feat`，原生字节码模态）",
             "mando": "**直接读正典图**（与本文方法同一批图，**无离线特征步**）"}
    for label, arm, _n in BASELINES:
        per = []
        for s in SEEDS:
            f = REPO / rel_of(arm, layout) / f"seed{s}" / "results.json"
            if not f.exists():
                per.append("—")
                continue
            d = json.loads(f.read_text(encoding="utf-8"))
            per.append(f"{d.get('n_train_graphs')}/{d.get('n_val_graphs')}/{d.get('n_test_graphs')}")
        lines.append(f"| {label} | {roots[arm].format(sfx=L['suffix'])} | {'、'.join(per)} |")
    for tool in available_trads(layout):
        r = trad_row(tool, None, layout)
        if r is None:
            continue
        n_in, n_an = r["_denominator"]
        lines.append(f"| **{TRAD_LABEL[tool]}**（传统工具） | 静态分析，**不训练**；规则命中读 `_m1.json` | "
                     f"— / — / {n_an}（{n_in} 个里 {n_an} 个可分析） |")
    return lines


def timing_block(layout: str = "buggy") -> list[str]:
    """训练时间与规模（用户 2026-09-22 要求记录成本；2026-09-24 起**含本文方法**）。"""
    lines = ["| 方法 | 种子 | 参数量 (M) | best epoch | 训练 (s) | 每 epoch (s) | 总 wall (s) | device |",
             "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    m_label = "**本文方法**" + ("（正典）" if layout == "buggy" else "（对照口径）")
    for s in SEEDS:
        r = _canon_timing_row(layout, s)
        if r is None:
            lines.append(f"| {m_label} | seed{s} | — | — | — | — | — | — |")
            continue
        pm = "—" if r["params_m"] is None else f"{r['params_m']:.3f}"
        be = "—" if r["best_epoch"] is None else r["best_epoch"]
        lines.append(f"| {m_label} | seed{s} | {pm} | {be} | {r['train_seconds']} | "
                     f"{r['seconds_per_epoch']} | {r['wall_seconds']} | {r['device']} |")
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


def _cross_canon_note() -> tuple[list[str], list[str]]:
    """两段口径（正典 池 497 / 对照 池 453）的**方向性对照**（micro@val_thr，3 种子均值）。

    🔴 **它是「看方向、不看小数位」的表**，理由与 `experiments/buggy_canon_summary.md` §3b 逐字相同：
    两段的 **test 集不是同一批合约**（46 vs 49，且划分重划过）⇒ **严格说不可相减**。
    可以做方向对照的唯一依据是**两段的 test 正样本量级相当**（旧 test 21 个正 / 新 test 干净子集 20 个正）。
    ⚠ 而且本段的基线还多差一层「特征配对方式」（见 §0 第 4 条）⇒ 这张表的 Δ **只能读作
    「补回注入噪声样本之后读数怎么动」，不得读作「某方法更强/更弱」**。

    本表唯一要回答的问题：**把 `buggy_*` 补回池里之后，基线与本文方法的差距形状变了没有。**

    返回 `(正文, 表下声明)`：正文 = §2b 标题 + 两张**不编号**的对照表 + 一句话的表引导，
    声明下沉到文末「附-D」（用户 2026-09-24 裁定）。
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
    lines = ["| 方法 | 池 453（对照口径） | 池 497（正典） | Δ（方向） |",
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
    body = ["", "### 2b. 🔴 两段正典的方向对照（**这张表是本次补跑要回答的问题**）", ""]
    body += lines
    body += [""]
    notes = ["",
             "> 🔴 **不得把 Δ 读作「补数据提升了检测能力」**：`buggy_*` 的标签绝大多数是七类全 1，"
             "模型「一律报有漏洞」即可在它们身上拿满分（§0 第 2 条）⇒ **Δ 里混着标签假象**。"
             "**Δmicro 才是干净的那个数**（零支撑类不进分子分母），Δmacro 只作量级参考。"
             "⚠ 且两段的 test 集**不是同一批合约**（46 vs 49），本表**只读方向、不读小数位**"
             "（同 `experiments/buggy_canon_summary.md` §3b 的口径）。"]
    if gl:
        body += ["**同上，换成「与本文方法的差距」**（本表加它只为让「差距形状变了没有」一眼可见）：", ""]
        body += gl
        body += [""]
        notes += ["",
                  "> ⚠ Slither **不在**下表里：它不训练、无阈值，且**分母不同**（46 池只分析了 45 个、"
                  "497 池 46–47 个）⇒ 它的 Δ 与其余行的 Δ **不可并列解读**。"]
    return body, notes


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
    # 六个传统工具各出一行。🔴 **缺产物的工具不出行、也不静默补零**——
    # 表下会由 `missing_trads` 点名，避免"没跑"与"跑了但全错"看起来一样。
    sl = None
    for tool in available_trads(layout):
        r = trad_row(tool, None, layout)
        if r is None:
            continue
        sl = sl if sl is not None else r          # 兼容旧调用方：返回第一个（Slither）
        rows_all.append((f"**{TRAD_LABEL[tool]}**（传统工具）", r))
        rb = trad_row(tool, [best], layout)
        if rb is not None:
            rows_best.append((f"**{TRAD_LABEL[tool]}**（传统工具）", rb))
    supports = {supports_key: canon["support"]}
    for tool in available_trads(layout):
        r = trad_row(tool, None, layout)
        if r is not None:
            supports[f"{TRAD_LABEL[tool]}（分母不同）"] = r["support"]
    return rows_all, rows_best, supports, sl


def _split_table(block: list[str]) -> tuple[list[str], list[str]]:
    """把「表 + 表下解释文字」拆成两份：**表**（含其 `## 表 N` 标题）留在正文，
    **解释文字**（`>` 引用段、普通段落）下沉到文末「附」。

    🔴 **只做位置重排**：两边字符串**逐字未动**，故 `grep '^|' | sort` 的多重集、表号序列、
    以及「正文非表行」的多重集都可机器对拍（用户 2026-09-24 裁定的三步自检，见 `log.md`）。
    """
    tbl = [ln for ln in block if ln.startswith("|") or ln.startswith("## 表 ")]
    notes = [ln for ln in block
             if ln.strip() and not ln.startswith("|") and not ln.startswith("## 表 ")]
    return tbl, notes


def clean_doc() -> tuple[list[str], list[str], int]:
    """**对照口径段（池 453，已剔除全部 `buggy_*`）** —— 追加在 §二 之后（§三，表 15–28）。

    🔴 **2026-10-01 口径对调（用户裁定）**：本段原是居正文主体的「§37 正典」；用户当日裁定
    池 453 降为对照口径 ⇒ 它现居文末、表号顺延为 15–28。**报告主体（表 1–14）= 正典
    （池 497）**，由 `canon_doc()` 生成。

    🔴 正文只剩 **抬头 + 指针行 + 一张表一句话的引导 + 全部表格**：解释性文字一律下沉到
    全文件末尾的单一「附」（用户 2026-09-24 裁定：表与表之间不留任何说明文字）；
    本段的声明块收在文末「附-A / 附-B / 附-C」。

    返回 `(正文, 「附」的正文, 末表号)`——「附」由 `main()` 与正典段的「附-D」拼在同一个
    `## 附` 下。
    """
    layout = "canon37"
    runs_dir = LAYOUTS[layout]["runs_dir"]
    best = T.best_seed_from_runs(runs_dir, SEEDS)
    if best is None:
        raise SystemExit(f"🔴 {runs_dir} 下没有 results.json，无法选最佳种子")
    method_label = "**本文方法**（对照口径）"
    rows_all, rows_best, supports, sl = _rows_for(
        layout, runs_dir, method_label, best, slither_root(layout),
        supports_key="本文方法与三基线共用（对照口径 test）")

    # ---- 正文：只留「抬头 + 指针行 + 一张表一句话的引导 + 表格」 --------------------------
    doc: list[str] = []
    doc += ["---", "", "---", "",
            "# 三、对照口径：仅正常合约的池 453", "",
            "> 🔴🔴 **本段与上面 §一–§二 不是同一个 test 集**（49 → **46**，且各自划分）"
            "⇒ **跨段数字不可直接相减**，只能看**方向**。本段回答的是「把被剔除的注入噪声合约"
            "移除、只用正常合约时，基线与本文方法的**差距形状**是否改变」。", "",
            "> 🔴 **口径声明与逐行声明（引用本段前必读）在文末「附-A/B/C」**——移到文末是为了"
            "**不打断表的阅读**。读表顺序：§1 support → §2 成本 → "
            f"§3 合约级二分类 → §4 表 15/表 16 → 三之一、表 17–22（最佳种子 **seed{best}**）"
            "→ 三之二、表 23–28（3 种子 mean±std）。", "",
            "---", "", "## 1. 逐类 support（先读）", ""]
    sup_tbl, sup_notes = _split_table(T.support_block(supports))
    thin_note = T._thin_support_note(supports)
    doc += sup_tbl
    doc += ["", "---", "", "## 2. 训练时间与规模（成本）", "",
            "**先看输入**——本表各行的图/特征来源与项目数量（逐种子，**从产物读、不手抄**）：", ""]
    doc += _inputs_block(layout)
    doc += [""] + timing_block(layout)
    timing_notes = [
        "> `训练 (s)` = 训练循环净耗时；`总 wall (s)` = 含验证推理与阈值搜索的整段耗时。",
        "> ⚠ **本文方法的表内成本只是 GNN 段**：它的输入要先经 CodeBERT 微调"
        "（`finetune_codebert.py`）与 M3 重编码，这两步是**一次性上游成本**、不计在上表内；"
        "三条基线则把特征工程放在离线步（同样不计在表内）。"]
    doc += ["", "---", "", "## 3. 🔴 合约级二分类口径（三条基线论文的原生口径）", ""]
    bin_tbl, bin_notes = _split_table(
        binary_caliber_block(runs_dir, layout=layout, method_label=method_label))
    doc += bin_tbl
    doc += ["", "---", "", "## 4. 逐类二分类 F1（binary-F1）与全口径总览", "",
            "> 本节两张表是**同一批产物**的不同算法（3 种子 mean±std）。"
            "**定义（附-C-2）与代价说明（附-C-3）在文末「附-C」**——不打断表的阅读。", ""]
    pc_tbl, pc_notes = _split_table(per_class_binary_block(
        runs_dir, list(SEEDS), layout=layout, method_label=method_label,
        table_title="## 表 15 —— 逐类 binary-F1 @逐类验证集阈值"
                    "（3 种子 mean±std）",
        xref="（见本段表 19 与表 25）"))
    doc += pc_tbl
    doc += ["", "同一批产物、不同算法（3 种子 mean±std）：", "",
            "## 表 16 —— 方法 × 口径 汇总列总览（3 种子 mean±std）", ""]
    ov_tbl, ov_notes = _split_table(overview_block(
        runs_dir, list(SEEDS), layout=layout, method_label=method_label,
        xref_buggy_thr="（见本段表 21、表 27）",
        xref_pcbin="（见本段表 19、表 25）"))
    doc += ov_tbl
    sec4 = ["", "#### 附-C-2 什么是 binary-F1", "",
            "**定义。** 把「这个合约有没有第 $c$ 类漏洞」当成一个**只有两个答案**的问题（有 / 没有）"
            "去算的 F1：",
            "",
            "$$F1_c=\\frac{2\\,TP_c}{2\\,TP_c+FP_c+FN_c}$$",
            "",
            "其中 $TP_c$ = 真值有第 $c$ 类、模型也判有的合约数；$FP_c$ = 真值没有、模型判有的；"
            "$FN_c$ = 真值有、模型判没有的。末列的**平均** = 7 个 $F1_c$ 的**算术平均**"
            "（每类等权，不受类大小影响）。",
            "",
            "**它与本段表 17–28 的「逐类格」是不是一回事？** —— **公式完全相同**。"
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
            "本块把它**扩到三条论文基线**上，并**逐位对拍**（见下）。", "",
            "#### 附-C-3 代价：本口径的过拟合是**已量化**的", "",
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
            "🔴 **所以引用本段表 15 时的强制声明（缺一不可）**：",
            "① 它是**补充口径**，不进 5.3 主表；② 它建立在 **val 每类 1–3 个正样本**上，"
            "**过拟合已量化**（val→test 落差最大 0.16，`dos` 阈值三种子极差 0.55）；"
            "③ 它与三口径表的 @0.5 版**同源**，不得当成两套独立证据；"
            "④ **不得**用本表宣称「比论文高」——它们的数据集、划分、类别数、支撑量都不同。",
            "",
            "> **一条有价值的正面结论（来自同一份审计）**：test **oracle** macro-F1 ≈ **0.80**，"
            "而逐类阈值实际只拿到 **0.636**。oracle 是在 test 上作弊选阈值，衡量的是「**阈值选对了能到多少**」"
            "⇒ **排序里带着的信息量支持约 0.80 的 macro-F1，实际只兑现了 0.636**。"
            "这把主库的瓶颈定位得很干净：**不在模型的排序能力**（AP/ROC-AUC 已在 0.76–0.98），"
            "**而在「用一个全局阈值去卡七类概率尺度差异极大的输出」这件事本身**。", ""]
    doc += ["", "---", "", f"# 三之一、最佳种子（seed{best}）", ""]
    sub, n = _detail_tables(rows_best, 16)
    doc += sub
    doc += ["---", "", "# 三之二、附录：3 种子 mean±std", ""]
    sub, n = _detail_tables(rows_all, n)
    doc += sub

    # ---- 文末「附」（本段部分 = 附-A / 附-B / 附-C）-------------------------------------
    # 🔴 解释性文字**一律下沉到全文件末尾的单一「附」**（用户 2026-09-24 裁定：表与表之间
    #    不留任何说明文字）。小节标题里保留「§0」字样是为了让全仓既有的「见本表 §0 第 N 条」
    #    引用继续可解析（Markdown 里的段号引用**不会被任何测试发现失效**）。
    tail: list[str] = ["### 附-A 对照口径段口径声明（引用作「本段 §0 第 1–6 条」）", "",
                       "> **表 17–22 = 最佳种子口径**（判据 = 本文方法在 micro-F1@val_thr 上最高 ⇒ "
                       f"**seed{best}**；全部行共用同一个种子，否则同一批行不是同一批模型）；"
                       "**表 23–28 = 3 种子 mean±std 附录**（ddof=1）。"
                       "⚠ 最佳种子口径下没有 ±，且本仓实测重跑抖动 ≈0.012 ⇒ "
                       "**不得**据单种子差下「某方法更强」的结论。",
                       "",
                       "> **表 15–16 = 跨口径总览（先读这两张）**：表 15 = 逐类 **binary-F1**"
                       "（三篇论文的原生判决规则），表 16 = 各口径的汇总列一览（选口径用）。"
                       "两者**都是零重训**的离线重算，与表 17–28 **同一批产物**，只是换算法。", ""]
    tail += _canon_section0(runs_dir, sl)
    tail += ["**6）成本。** 训练时间与规模见 §2；**本文方法的上游成本**（CodeBERT 微调 + M3 重编码）"
             "见 附-A-2（§2 表下注）——两张表的口径都是「模型训练」，不含各自的特征工程步。"
             "三条基线与本文方法的推理产物（`test_probs.pt`）已入库，全部指标可**离线重算、无需重训**。", "",
             "#### 附-A-1 §1 逐类 support 的读法", ""]
    tail += sup_notes + [thin_note, ""]
    tail += ["#### 附-A-2 §2 成本表的读法", ""] + timing_notes + [""]
    tail += ["### 附-B 为何必须并列合约级二分类（§3 表的读法）", ""] + bin_notes + ["",
             "**为什么必须并列这一块**：三条基线的论文报的都是**合约级二分类 F1**（有/无漏洞），"
             "而大纲 [411] 要求 5.3 **统一按七维多标签**评测。两个口径的**平凡下限相差 0.50**"
             "（七维 0.1224 vs 二分类 0.6199，实测）⇒ 只摆七维数字会把「任务本身更难」"
             "误读成「这些方法不行」。本块用**同一批产物**坍缩出二分类读数，"
             "坍缩规则 `max_c p_c >= t ⇔ any_c(p_c >= t)`（`decisions.md` §31 已机检），"
             "**不是**另训一个模型。", ""]
    tail += ["### 附-C binary-F1 的定义、代价与 §4 两张总览表的读法", "",
             "#### 附-C-1 表 1（逐类 binary-F1）的读法与对拍", ""] + pc_notes + [""]
    tail += sec4
    tail += ["#### 附-C-4 表 16（全口径总览）的读法", ""] + ov_notes + [""]
    return doc, tail, n


def _canon_section0(runs_dir: str, sl) -> list[str]:
    """**对照口径段（池 453）的 §0 声明** —— 2026-10-01 口径对调后本段居 §三（表 15–28）。

    ⚠ 函数名仍叫 `_canon_section0`（为兼容既有引用与测试；它现在服务的是**对照段**）。
    """
    doc: list[str] = []
    doc += ["**1）对照口径与池。** 本段为**对照口径** —— **池 453，已剔除全部 `buggy_*`**"
            "（`products/alldata/graphs_ft_p2/cb_ft_ss{S}` + "
            "`products/alldata/splits/split_seed{S}.json`，池 **453**、train/val/test = 362/45/46）。"
            "它是用户 2026-09-22 裁定的「去除 `buggy_*` 的数据集」"
            "（497 删 44 个 `buggy_*` 后与 453 **集合级恒等**）。"
            "▶ 本段与 `experiments/per_class_three_caliber_tables.md` **同池同划分**，"
            "与 `..._tables_buggy.md`（正典段）**不是同一个 test 集**，两边数字**不可直接相减**。", "",
            "**2）三口径。** `micro` / `macro` 的**逐类格是全测试集**逐类 F1；`buggy` 的逐类格是"
            "**仅 `y.any(axis=1)` 的合约**上的逐类 F1。汇总列：`micro` = 标签对 micro-F1，"
            "`buggy` = 漏洞子集上的 micro-F1，`macro` = 那 7 个逐类 F1 的未加权平均。"
            "🔴 **`macro` 表与 `micro` 表的逐类格逐位相同**（恒等，不是重复计算），差异只在汇总列。", "",
            "**3）训练口径。** 三条基线共用同一套超参"
            "（`epochs=200, lr=1e-4, weight_decay=1e-4, scheduler_patience=3, "
            "pos_weight_cap=20.0`），早停判据 = val micro-F1，阈值只在验证集搜"
            "（0.20–0.80 步长 0.05）。**与本文方法有两处已知口径差，逐条列出：**"
            "① 🔴 **`early_stop_patience` 基线用 20、本文方法（池 453）用 5**——5 是为 SSM-HG 调的，"
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
    doc += coverage_block("canon37")
    doc += ["", TRAD_DASH_NOTE, ""]
    doc += ["",
            "> ⚠ **分母不可比的只有 Slither**（见下）：三条基线的 `test_probs.pt` 行数"
            "**全部等于 46**（本段 test 的合约数），故与本文方法**逐格可比**。", "",
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


def canon_doc(runs_dir: str, with_clean: bool = False) -> tuple[list[str], list[str], int, int]:
    """**正典段（池 497，含全部 `buggy_*`）** —— 本文件主体（§一–§二，表 1–14）。

    🔴 **2026-10-01 口径对调（用户裁定）**：本段原是附在文末的「含 `buggy_*` 的主库」；用户
    当日裁定池 497 升为正典 ⇒ 它现居正文主体、表号 1–14。另一段为**对照口径（池 453，已剔除
    `buggy_*`）**，由 `clean_doc()` 追加在 §二 之后（§三，表 15–28）。

    🔴 与对照段的差别**逐条列出**，因为读者最容易在这里做错比较：
     1. **池与 test 都不同**（497 / 49 vs 453 / 46，划分各自重划）⇒ **跨段不可相减**；
     2. **`buggy_*` 的标签是度量假象**（39/44 为 `1111111`）⇒ 必须并列 `clean_only` 列；
     3. **特征约定与对照段不同**：本段用与 `--split-seed` **配对**的 `cb_ft_ss{S}`
        （与 `runs/buggy_canon/seed{S}` 同款），而对照段的三条基线三种子**都用 `ss0`**
        （历史事实）。两段各自内部可比、**跨段不可比**。

    返回 `(正文, 「附」的正文, 末表号, 最佳种子)`——本段的声明块收在文末「附-D」（用户
    2026-09-24 裁定：表与表之间不留任何说明文字），由 `main()` 与对照段的「附-A/B/C」拼在
    同一个 `## 附` 下。
    """
    layout = "buggy"
    method_label = "**本文方法**（正典）"
    # 🔴 最佳种子必须有 3/3 的 results.json：`T.best_seed_from_runs` 在缺文件时**静默回退 seeds[0]**
    #    （它永不返回 None），于是「某个种子没跑完」会被读成「最佳种子就是 seed0」。
    missing = [s for s in SEEDS if not (REPO / runs_dir / f"seed{s}" / "results.json").exists()]
    if missing:
        raise SystemExit(f"🔴 {runs_dir} 缺 seed{missing} 的 results.json——"
                         f"先跑完三种子再出表（否则最佳种子会静默取 seed0）")
    # 🔴 **缺任何一个基线就硬失败，不静默出少几行的表**：`_rows_for` 对缺产物是
    # `continue`（对照段沿用该行为，因为"某基线还没跑"在那里是合法的中间态），
    # 但**正典段是报告主体**，缺行会让「497 池上没有这条基线」与「它还没跑完」看起来一模一样。
    absent = [f"{arm}{LAYOUTS[layout]['suffix']}"
              for arm in [a for _l, a, _n in BASELINES + SENSITIVITY]
              if not (REPO / rel_of(arm, layout)).exists()]
    if absent or slither_row(root_rel=slither_root(layout)) is None:
        raise SystemExit(f"🔴 正典段需要的产物尚未齐（缺 {absent or []}"
                         f"{'；slither_buggy 也缺' if slither_row(root_rel=slither_root(layout)) is None else ''}）"
                         f"——先跑 `python scripts/run_baselines.py --layout buggy` 与 "
                         f"`scripts/baseline_static_tools.py --tag buggy`")
    best = T.best_seed_from_runs(runs_dir, SEEDS)
    rows_all, rows_best, supports, sl = _rows_for(
        layout, runs_dir, method_label, best, slither_root(layout),
        supports_key="本文方法与三基线共用（正典 test）")

    # ---- 正文：只留「抬头 + 指针行 + 一张表一句话的引导 + 表格」 --------------------------
    doc: list[str] = []
    doc += ["# 5.3 对比表：本文方法 vs 三条论文基线（EGFL / MVD-HG / MANDO-LLM）",
            "",
            "> 程序生成（`scripts/collect_baseline_tables.py`）：**只搬运产物、只调 `metrics`**，"
            "不手抄、不重实现指标。逐类格与汇总列一律经 "
            "`collect_three_caliber_tables.render_table`。", "",
            "> 🔴 **口径声明与逐行声明（引用本表前必读）在文末「附」（即原「§0」）**——"
            "移到文末是为了**不打断表的阅读**（用户 2026-09-24 裁定）。声明按来源分四小节："
            "**附-A** 对照口径段（池 453，原「§0」第 1–6 条）、**附-B** 为何必须并列合约级二分类、"
            "**附-C** binary-F1 的定义与代价、**附-D** 正典段（池 497，原「§0」第 1–7 条）。"
            "读表顺序："
            f"§1 support → §2 成本 → §3 合约级二分类 → §4 表 1/表 2 总览 → "
            f"一、表 3–8（最佳种子 **seed{best}**）→ 二、表 9–14（3 种子 mean±std）→ "
            "三、表 15–28（对照口径：仅正常合约的池 453）→ 附（全部声明）。", "",
            *(["> 🔴🔴 **本文件有两段（两个口径）**：**§一–§二 = 正典（池 497，含全部 `buggy_*`）**；"
               "**文件末尾的「三、」= 对照口径（池 453，仅正常合约）**。"
               "两段的 test 集**不是同一批合约**（49 vs 46）⇒ **跨段数字不可相减**；"
               "两段的三条基线连**特征配对方式都不同**（见 附-D 第 4 条）。", ""]
              if with_clean else []),
            "---", "", "## 1. 逐类 support（先读）", ""]
    sup_tbl, sup_notes = _split_table(T.support_block(supports))
    thin_note = T._thin_support_note(supports)
    clean_only_note = (
        "> 🔴 **`clean_only` 侧的 support 极薄、且有的类会归零**（实测 seed1 为 "
        "`1/1/0/0/4/0/6`，`time_manipulation` 的 test 正样本**全部来自注入合约**）"
        "⇒ 零支撑类按 `zero_division=0` 计 F1=0，**`clean_only` 的 macro 因此被人为压低**："
        "它同时含 (a) 假象消失（真实效应）与 (b) 稀有类正样本被抽走（度量副作用）"
        "⇒ **`clean_only` 的 Δmacro 只能读作「假象的量级」，`Δmicro` 才是干净的那个数**"
        "（`experiments/buggy_canon_summary.md` §4）。"
        "⚠ 本节的薄支撑判定只覆盖**全 test**（`support_block` 的输入）；`clean_only` 侧的薄支撑"
        "见上一句的人列数字，不另立表。")
    doc += sup_tbl
    doc += ["", "---", "", "## 2. 训练时间与规模（成本）", "",
            "**先看输入**——本段各行的图/特征来源与项目数量（逐种子，**从产物读、不手抄**）：", ""]
    doc += _inputs_block(layout)
    doc += [""] + timing_block(layout)
    timing_note = ("> `训练 (s)` = 训练循环净耗时；`总 wall (s)` = 含验证推理与阈值搜索的整段耗时。"
                   "⚠ 基线三臂为 `--early-stop-patience 20`（与对照段同款，见 §0 第 3 条）；"
                   "本文方法（正典）为 `patience 5`。"
                   "**本文方法的表内成本只是 GNN 段**：上游的 CodeBERT 微调与 M3 重编码不计在内。")
    cross_body, cross_notes = _cross_canon_note()
    doc += cross_body
    doc += ["", "---", "", "## 3. 🔴 合约级二分类口径（三条基线论文的原生口径）", ""]
    bin_tbl, bin_notes = _split_table(
        binary_caliber_block(runs_dir, layout=layout, method_label=method_label))
    doc += bin_tbl
    doc += ["", "---", "", "## 4. 逐类二分类 F1（binary-F1）与全口径总览", "",
            "> 本段两张表同源（同一批产物、3 种子 mean±std）。"
            "**定义与恒等式与对照段 附-C-2 逐字相同**（`decisions.md` §13/§49），"
            "本段**不重复**那段推导，只给本段的读数。", ""]
    pc_tbl, pc_notes = _split_table(per_class_binary_block(
        runs_dir, list(SEEDS), layout=layout,
        method_label=method_label,
        table_title="## 表 1 —— 逐类 binary-F1 @逐类验证集阈值"
                    "（3 种子 mean±std）",
        xref="（见 §一 的表 5、§二 的表 11）"))
    doc += pc_tbl
    overfit_note = (
        "> 🔴 **本段该口径的过拟合比对照段更重**：`clean_only` 侧 val/test 的逐类正样本"
        "低到 **0–6**，在 0 个正样本上调阈值在数学上无约束。"
        "故本段表 1 **只作描述性呈现**，**不得**据此下「某方法在此口径更强」的结论。")
    doc += ["", "同一批产物、不同算法（3 种子 mean±std）：", "",
            "## 表 2 —— 方法 × 口径 汇总列总览（3 种子 mean±std）", ""]
    ov_tbl, ov_notes = _split_table(overview_block(
        runs_dir, list(SEEDS), layout=layout, method_label=method_label,
        xref_buggy_thr="（见 §一 的表 7、§二 的表 13）",
        xref_pcbin="（见 §一 的表 5、§二 的表 11）"))
    doc += ov_tbl
    # 🔴 标题**必须带段号**：本段（正典）与文末对照段各自有一组「主口径 / 附录」，
    #    若都写 `# 一、`/`# 二、`，同一个文件里就有两套同名标题。
    doc += ["", "---", "", f"# 一、主口径：最佳种子（seed{best}）", ""]
    sub, n = _detail_tables(rows_best, 2)
    doc += sub
    doc += ["---", "", "# 二、附录：3 种子 mean±std", ""]
    sub, n = _detail_tables(rows_all, n)
    doc += sub
    # ---- 文末「附」（本段部分 = 附-D）----------------------------------------------------
    tail: list[str] = ["### 附-D 正典段口径声明（引用作「本段 §0 第 1–7 条」）", ""]
    tail += ["**1）正典与池。** `products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S}` + "
             "`products/alldata/splits/withbuggy_snapshot/split_seed{S}.json`，池 **497**、"
             "train/val/test = **398/50/49**；本文方法 = `runs/buggy_canon`"
             "（池 497 正典口径，原「任务 2」；`decisions.md` §43–§46、§58）。", "",
             "**2）🔴 `buggy_*` 标签是度量假象，故本段必须并列 `clean_only` 诊断列。**"
             "那 44 个补回的合约里 **39 个标签为 `1111111`、5 个为 `0100011`**"
             "（上游按「每类各放一份」复制，`decisions.md` §18.4/§46.2）——"
             "模型「一律报有漏洞」即可在它们身上拿满分。⇒ **不得**据本段声称"
             "「补回 buggy 提升了检测能力」。代价已量化"
             "（`experiments/buggy_canon_summary.md` §3，3 种子）："
             "剔掉 test 里那 7–8 个 `buggy_*` 后，本文方法 **micro 掉 0.10–0.16、"
             "macro 掉 0.33–0.61**。", "",
             "**3）三口径与训练口径：与 §0 第 2/3 条逐字相同**（同一套超参、同一套已知口径差、"
             "同一批 `run_baselines.PIPELINE` 训练参数）。**本文方法侧唯一的不同是正典**；"
             "**基线侧另有一处不同（特征配对方式），见下条第 4 条**。", "",
             "**4）🔴 特征约定（跨段不可比的一条，必须单独声明）：**"
             "本段三条基线用的是**与 `--split-seed` 配对的** `cb_ft_ss{S}`。"
             "⚠ 2026-09-25 换代前，上面 §三（对照段）三条基线**三个种子用的都是 `graphs_ft/ss0`**"
             "（历史事实）；本次换代把两段统一为**配对**写法，该不对称已消除。"
             "配对本仓是硬要求（`AGENTS.md` 语义锁死项）："
             "**`_cb.pt` 的 CodeBERT 节点行逐张量随 `ss` 变**，"
             "实测 ss0/ss1/ss2 全不同、跨正典更不同 ⇒ 不配对就是拿另一套编码器特征训练。"
             "⇒ **两段各自内部可比，跨段除了「池」还差着「特征配对方式」**。", "",
             "**5）离线覆盖率（分母是否相同）。**", ""]
    tail += coverage_block(layout)
    tail += ["", TRAD_DASH_NOTE, ""]
    tail += ["",
             "> ⚠ 三条基线的 `test_probs.pt` 行数**应当**等于 49（本文方法 test 的合约数）。"
             "**MVD-HG 在 seed1 上少 1 个**（该合约在任何已装 solc 下都编不出 compact AST）"
             "⇒ **该行分母是 48，与其余行逐格不可解读**，读表时必须带着这条。", "",
             "**6）实现性质与口径损失**：三条基线的实现性质**与本段无关**（与池无关），"
             "逐行声明见对照段 附-A §0 第 5 条，**同样适用**，**不得**声称复现了作者原结果。", "",
             "**7）成本。** 训练时间与规模见 §2（已含本文方法）；"
             "本文方法该正典的上游成本（CodeBERT 微调 + M3 重编码）与更细的吞吐数字见 "
             "`experiments/buggy_canon_summary.md` §1。", "",
             "#### 附-D-1 本段 §1 逐类 support 的读法（含 `clean_only` 侧）", ""]
    tail += sup_notes + [thin_note, clean_only_note, ""]
    tail += ["#### 附-D-2 本段 §2 成本表与 §2b 方向对照表的读法", ""]
    tail += [timing_note, ""] + cross_notes + [""]
    tail += ["#### 附-D-3 本段 §3 合约级二分类表为何必须并列", ""] + bin_notes + ["",
             "**为什么必须并列这一块**：三条基线的论文报的都是**合约级二分类 F1**（有/无漏洞），"
             "而大纲 [411] 要求 5.3 **统一按七维多标签**评测。本块用**同一批产物**坍缩出二分类读数"
             "（坍缩规则 `max_c p_c >= t ⇔ any_c(p_c >= t)`，`decisions.md` §31 已机检），"
             "**不是**另训一个模型。"
             "🔴 **本段的平凡下限与对照段不同**（`buggy_*` 的全 1 标签把「本来就有漏洞」的比例"
             "从 45.7% 抬到约 51%），故**逐种子可变**——表尾的读法句已按本段数据现算。", ""]
    tail += ["#### 附-D-4 本段 §4 两张总览表的读法", ""] + pc_notes + [overfit_note, ""] + ov_notes + [""]
    return doc, tail, n, best


def main() -> None:
    ap = argparse.ArgumentParser(description="5.3 基线三口径对比表")
    ap.add_argument("--runs-dir", default="runs/buggy_canon",
                    help="本文方法**正典**（池 497）的 run 目录。")
    ap.add_argument("--out", default="", help="写入的 markdown 路径；留空只打印。")
    ap.add_argument("--with-clean", "--with-buggy", dest="with_clean", action="store_true",
                    help="在 §二 之后追加「三、对照口径：仅正常合约的池 453」整段"
                         "（本文方法 = `runs`，基线 = `eval_results/baseline/*`，**无后缀**）。"
                         "缺产物即硬失败，不静默出 `—` 行。（`--with-buggy` 是旧名隐藏别名。）")
    args = ap.parse_args()

    doc, tail, n, best = canon_doc(args.runs_dir, with_clean=args.with_clean)
    if args.with_clean:
        sub, sub_tail, n = clean_doc()
        doc += sub
        tail += sub_tail
    # 🔴 **全文件只有这一个「附」**（用户 2026-09-24 裁定）：两段各自的声明块都收在这里。
    #    标题里保留「§0」字样 ⇒ 全仓既有的「见本表 §0 第 N 条」引用继续可解析。
    doc += ["", "---", "", "## 附（原「§0」）：口径声明与逐行声明（引用本表前必读）", ""] + tail

    text = "\n".join(doc) + "\n"
    if args.out:
        p = REPO / args.out
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
        k = "两段" if args.with_clean else "一段"
        print(f"[collect] 已写 {p}（{len(text)} 字符，{k}共 {n} 张明细表 + 两段的表 1/2/15/16 总览；"
              f"正典最佳种子 seed{best}）")
    else:
        print(text)


if __name__ == "__main__":
    main()
