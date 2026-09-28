#!/usr/bin/env python3
"""消融**三口径表**的程序生成器：`experiments/ablation_three_metric_table.md` 的 4 张表。

🔴 **为什么必须补这个脚本**（2026-09-25 补，根因修复）：
  该文件正文**自称**「**生成方式**：从各臂的 `test_probs.pt` + `thresholds.json` 程序复算
  （唯一事实来源 `scripts/metrics.py`），**不手抄**」，但实测**全仓没有任何脚本写它**
  （`grep -rn 'experiments/ablation_three_metric_table.md' scripts/` 只命中 `run_ablation.py`
  的一句注释）。⇒ 2026-09-25 编码器换代后它继续发出**整代旧数字**。本脚本把这句话变成真的。

**口径与来源**（逐列，**不重实现指标**，全部调 `scripts/metrics.py`）：
  - Micro-F1 / Macro-F1 / mAP ← 各 run 的 `results.json`
    （`test.val_threshold.*` / `test.fixed_0.5.*` / `mAP.mAP`；**与 `collected.json` 同源**）
  - Buggy-F1（有漏洞合约子集）← `metrics.buggy_f1(y, pred >= thr)["f1"]`（自 `test_probs.pt`）
  - Buggy-F1（合约级二分类）← `metrics.binary_prf(contract_any_labels(y), contract_any_scores(p) >= thr)["f1"]`
  - 阈值 ← 各 run 的 `results.json::val_threshold`（**只由验证集搜出**，测试集不参与）

⚠ **两个 Buggy-F1 不是同一个数**，且免罚方向相反（`decisions.md` §30 / `tests/test_metrics.py`）。

用法（仓库根目录）：
    python scripts/collect_ablation_three_metric.py            # 打印
    python scripts/collect_ablation_three_metric.py --write    # 落盘
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
import metrics                                                       # noqa: E402

OUT = REPO / "experiments" / "ablation_three_metric_table.md"
SEEDS = (0, 1, 2)
ARMS = ("ast_parent", "callback_risk", "cb_frozen", "cb_func_only", "cb_node_only", "cb_rev",
        "cb_unlimited", "cfg_flow", "dfg_dep", "dropedge02", "feat_base", "feat_base_sem",
        "hid256", "layers1", "layers3", "meanpool", "no_lvar", "no_prior_drop",
        "numbases1", "numbases3", "numbases4")

# 层 / 臂 / 变量（唯一改动）——**策展文本**（人工维护，不与产物同步；产物只提供数值）
LAYERS: list[tuple[str, str, str]] = [
    ("**编码器层**<br>（输入表征来源）", "cb_frozen", "CodeBERT **冻结**（正典为微调）"),
    ("**结构层**<br>（图边集）", "ast_parent", "去 AST_PARENT（关系 1+2，`--drop-ast`）"),
    ("", "cfg_flow", "去 CFG_FLOW（物理关系 0）"),
    ("", "dfg_dep", "去 DFG_DEP（物理关系 3）"),
    ("", "callback_risk", "去 CALLBACK_RISK（物理关系 4）"),
    ("", "cb_rev", "**加**反向关系 CALLBACK_RISK_REV（关系数 5→6）"),
    ("", "cb_unlimited", "CALLBACK_RISK 出边不设上限（正典 4）"),
    ("", "dropedge02", "DropEdge 概率 0.2（正典 0.0＝关）"),
    ("**特征层**<br>（节点通道）", "cb_func_only", "去节点级 CodeBERT（只留函数级）"),
    ("", "cb_node_only", "去函数级 CodeBERT（只留节点级）"),
    ("", "feat_base", "结构特征分组 = base"),
    ("", "feat_base_sem", "结构特征分组 = base+sem"),
    ("**模型层**<br>（聚合/深度/容量）", "meanpool", "meanpool 替换 $a_v$ 加权 readout"),
    ("", "layers1", "RGCN 层数 L=1（正典 L=2）"),
    ("", "layers3", "RGCN 层数 L=3（正典 L=2）"),
    ("", "hid256", "隐藏维度 256（正典 128）"),
    ("", "numbases1", "RGCN 基分解 num_bases=1（正典 5）"),
    ("", "numbases3", "RGCN 基分解 num_bases=3（正典 5）"),
    ("", "numbases4", "RGCN 基分解 num_bases=4（正典 5）"),
    ("**训练目标/正则层**", "no_lvar", "关闭 $L_{var}$（方差正则）"),
    ("", "no_prior_drop", "关闭先验 Dropout（正典丢弃率 0.2）"),
]

CORPORA = [
    {"label": "① 主库 `alldata(readonly)`",
     "canon_dir": "runs/seed{seed}", "arm_dir": "runs/ablation/{arm}/seed{seed}",
     "tbl_thr": 1, "tbl_05": 2},
    {"label": "② 增强集 `alldata_augmentation`",
     "canon_dir": "runs/augmentation/seed{seed}", "arm_dir": "runs/ablation_aug/{arm}/seed{seed}",
     "tbl_thr": 3, "tbl_05": 4},
]


def _probs_labels(run_dir: Path):
    p = run_dir / "test_probs.pt"
    if not p.exists():
        raise SystemExit(f"🔴 缺 {p} —— `test_probs.pt` 只由 `diagnose.py` 写"
                         f"（漏掉它不是报错而是整列 `—`，本仓已栽过）")
    d = torch.load(p, map_location="cpu")
    return d["probs"].numpy(), d["labels"].numpy()


def read_run(run_dir: Path) -> dict:
    """一个 run 的五个口径（@thr 与 @0.5 各一套）。"""
    res = json.loads((run_dir / "results.json").read_text(encoding="utf-8"))
    pr, y = _probs_labels(run_dir)
    out = {}
    for wp, key in (("thr", "val_threshold"), ("05", "fixed_0.5")):
        thr = float(res["val_threshold"]) if wp == "thr" else 0.5
        pred = (pr >= thr).astype(int)
        t = res["test"][key]
        out[wp] = {
            "micro": t["micro_f1"], "macro": t["macro_f1"], "mAP": res["mAP"]["mAP"],
            "buggy": metrics.buggy_f1(y, pred)["f1"],
            "cbin": metrics.binary_prf(metrics.contract_any_labels(y),
                                       metrics.contract_any_scores(pr) >= thr)["f1"],
        }
    return out


def _fmt(vals: list[float]) -> str:
    a = np.array(vals, dtype=float)
    if np.isnan(a).any():
        return "—"
    return f"{a.mean():.4f}±{a.std(ddof=1):.4f}"


def collect(cfg: dict) -> dict[str, dict[str, list[float]]]:
    """→ {ann: {"thr": {...各口径的 3 种子列表}, "05": {...}}}"""
    acc: dict[str, dict[str, list[float]]] = {}
    rows = [("**正典**", cfg["canon_dir"])] + [(a, cfg["arm_dir"]) for a in ARMS]
    for ann, tmpl in rows:
        per = {"thr": {k: [] for k in ("micro", "macro", "mAP", "buggy", "cbin")},
               "05": {k: [] for k in ("micro", "macro", "mAP", "buggy", "cbin")}}
        for s in SEEDS:
            d = read_run(REPO / tmpl.format(seed=s, arm=ann))
            for wp in ("thr", "05"):
                for k in per[wp]:
                    per[wp][k].append(d[wp][k])
        acc[ann] = per
    return acc


def table(title: str, wp: str, acc: dict) -> list[str]:
    L = [f"### {title}", "",
         "| 层 | 臂 | 变量（唯一改动） | Micro-F1 | Buggy-F1<br>（有漏洞合约子集） | "
         "Buggy-F1<br>（合约级二分类） | Macro-F1 | mAP |",
         "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    c = acc["**正典**"][wp]
    L.append("| — | **正典** | **微调 CodeBERT + 全部组件** | "
             + " | ".join([f"**{_fmt(c['micro'])}**", f"**{_fmt(c['buggy'])}**",
                           f"**{_fmt(c['cbin'])}**", f"**{_fmt(c['macro'])}**",
                           f"**{_fmt(c['mAP'])}**"]) + " |")
    for layer, arm, var in LAYERS:
        a = acc[arm][wp]
        L.append(f"| {layer} | `{arm}` | {var} | "
                 + " | ".join([_fmt(a['micro']), _fmt(a['buggy']), _fmt(a['cbin']),
                               _fmt(a['macro']), _fmt(a['mAP'])]) + " |")
    return L + [""]


def main() -> int:
    ap = argparse.ArgumentParser(description="生成消融三口径表的 4 张表")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    hdr = [
        "# 消融三口径表：Micro-F1 / Buggy-F1 / Macro-F1",
        "",
        "> 🔴 **本文件的 4 张表由 `scripts/collect_ablation_three_metric.py` 程序生成，不要手改。**",
        "> 生成时间点的正典即表内数字的口径；**换代后必须重跑本脚本**。",
        "> （根因：本文件长期自称「程序复算、不手抄」却实为手写，2026-09-25 编码器换代后",
        "> 继续发出整代旧数字，故补上本脚本。）",
        ">",
        "> **口径与来源**：Micro/Macro/mAP ← 各 run 的 `results.json`；两个 Buggy-F1 ← ",
        "> `scripts/metrics.py` 的 `buggy_f1` / `binary_prf`，自 `test_probs.pt` 复算；",
        "> 阈值 ← 各 run 的 `results.json::val_threshold`（只由验证集搜出）。",
        "> 3 种子 mean±std（ddof=1）。**n=3 只作描述性读数**，判「干预有效/无效」须同配对 ≥9 点",
        "> （原话见 `decisions.md` §26.7/§27.5；n=9 判据见 `experiments/ablation_n9_results.md`）。",
        "",
        "## 0. 三个口径分别是什么（**先读，否则整张表会读反**）",
        "",
        "| 口径 | 定义（本仓实现） | 它对哪一类错误**免罚** | 回答的问题 |",
        "| --- | --- | --- | --- |",
        "| **Micro-F1** | 全部 `(合约, 类别)` 标签对的全局 F1 | 不免罚 | 「七类标签判得准不准」 |",
        "| **Buggy-F1（有漏洞合约子集）** | 先按 `y.any(axis=1)` 切片，再算 micro-F1"
        "（`metrics.buggy_f1`） | **干净合约上的误报**整段摘掉 | 「在真正有漏洞的合约上，七类判得准不准」 |",
        "| **Buggy-F1（合约级二分类）** | 把七类真值与预测都塌成 `any(...)` 后算二分类 F1"
        "（`metrics.binary_prf`，即 `decisions.md` §30 的 L3） | **「报错了哪一类」**"
        "（只看有没有报出至少一类） | 「部署上会不会漏掉整份合约」 |",
        "| **Macro-F1** | 7 类 F1 的未加权平均（`metrics.macro_f1`） | 不免罚；**小类权重被放大** | "
        "「稀有类是否被牺牲」 |",
        "",
        "> 🔴 **两个 Buggy-F1 不是同一个数**，仓内有专门用例锁住不相等",
        "> （`tests/test_metrics.py::test_buggy_f1_differs_from_contract_binary_f1`）。",
        "> ⚠ 两者**免罚的方向相反**，这是排序反转的来源。",
        "",
    ]

    doc = list(hdr)
    for cfg in CORPORA:
        doc += [f"## 表 {cfg['tbl_thr']} / 表 {cfg['tbl_05']}：{cfg['label']}", ""]
        acc = collect(cfg)
        doc += table(f"表 {cfg['tbl_thr']} —— @验证集阈值（主工作点，test 集，3 种子 mean±std）",
                     "thr", acc)
        doc += table(f"表 {cfg['tbl_05']} —— @固定 0.5（未标定工作点）", "05", acc)

    # 🔴 **只替换「头部 + §0 + 4 张表」，`## 1. 分析` 之后的正文原样保留**。
    #    理由：那些段落是**人工写的分析/规划**（不是产物），生成器无权删除它们。
    #    ⚠ 代价（必须知道）：**分析段里的数值不会自动跟着换代**——故下面在拼接处插一条横幅，
    #      把「表已换代、分析未换代」这件事写在读者必经之路上。
    splice = ""
    out_p = Path(args.out)
    if out_p.exists():
        cur = out_p.read_text(encoding="utf-8")
        i = cur.find("\n## 1. 分析")
        if i > 0:
            splice = cur[i:]
    if splice:
        doc += [
            "---",
            "",
            "> 📌 **本节以下的复核状态（2026-09-25 逐节标注）**：",
            "> - **§1.1 / §1.2 / §1.3 / §1.4 已在现行正典上重算**；正文结论一律以现行正典为准",
            ">   （用户 2026-09-25 裁定「消融结论翻转**直接用好的作为正典**」）。",
            ">   各节末尾的 `📌 审计留痕` 块**只作可追溯性用，不入论文正文**。",
            "> - **§1.5（② 增强集）仍然有效**：② 本次**未换代**，其读数逐位未变。",
            "> - **§2 / §3 是 2026-09-20 的「现状与下一步」规划**，部分已完成、部分已作废，**不可当作当前状态**。",
            "",
        ]
        doc.append(splice.lstrip("\n"))

    text = "\n".join(doc) + "\n"
    if args.write:
        out_p.write_text(text, encoding="utf-8")
        print(f"[three-metric] 已写 {out_p}（{len(text)} 字符；分析段{'原样保留' if splice else '不存在'}）")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
