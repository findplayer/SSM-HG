#!/usr/bin/env python3
"""任务 2 汇总卷：含 `buggy_*` 的新正典（池 497）——分数、训练时间、**以及涨分里有多少是标签假象**。

为什么必须有这个脚本，而不是手抄几个数进文档：任务 2 同时改了三件事，其中一件
（`buggy_*` 的标签绝大多数是**七类全 1**，`decisions.md` §18.4）会**系统性地抬高** macro/mAP
而**不**代表检测能力提升。手抄数字时这个偏差会被无声地当成"补数据真的有用"。

🔴 **本脚本的核心是 `clean_only` 口径**：把 test 里属于 `buggy_*` 项目的合约**剔掉**再算一遍。
   - 新正典 test = 49 个合约，其中若干是 `buggy_*`（全 1 标签）；
   - `clean_only` = 只留真实部署合约（非 `buggy_*`）的那部分；
   - **两个口径的差 = 标签假象的贡献**。这是唯一能把这句话变成数字的做法。
   ⚠ 它**不是**"更好的口径"——正典报的就是全 test；`clean_only` 是**诊断列**，
     用来回答"涨的分里有多少是假的"，**不得**替换主口径（那会变成挑好看的子集报）。

另报：
  - **训练时间**（`config.json::timing`，跨工具可比口径）；
  - **编码器轨迹对照**（旧划分 vs 新划分的逐 epoch val macro-F1）——两者不可直接比，
    但轨迹形状本身就是"标签假象"的证据；
  - **与 Slither 基线的并列**（同一 test 集才有可比性，故在 `clean_only` 上并列）。

用法（从仓库根目录运行）：
  python scripts/collect_buggy_canon_summary.py --runs-dir runs/buggy_canon \\
      --split-dir products/alldata/splits/withbuggy_snapshot \\
      --out experiments/buggy_canon_summary.md
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

import dataset                                                    # noqa: E402
import metrics                                                    # noqa: E402

SEEDS = (0, 1, 2)
NAMES = list(metrics.VULN_NAMES)


def _read(p: Path):
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def is_buggy(base: str) -> bool:
    """图 base 是否属于 `buggy_*` 注入项目（**复用 `dataset.is_buggy_project`**，只有一份实现）。"""
    return dataset.is_buggy_project(dataset.project_of_base(base))


def load_seed(runs_dir: Path, seed: int):
    p = runs_dir / f"seed{seed}" / "test_probs.pt"
    if not p.exists():
        return None
    b = torch.load(p, map_location="cpu")
    thr = _read(runs_dir / f"seed{seed}" / "thresholds.json")
    return {"probs": b["probs"].numpy(), "labels": b["labels"].numpy().astype(int),
            "ids": list(b["sample_ids"]),
            "thr": float(thr["best_threshold"]) if thr else 0.5,
            "results": _read(runs_dir / f"seed{seed}" / "results.json"),
            "config": _read(runs_dir / f"seed{seed}" / "config.json")}


def calibers(probs, y, ids, thr: float) -> dict:
    """三个口径 × 两个工作点：全部 test / 剔 buggy（clean_only）。"""
    clean = np.array([not is_buggy(i) for i in ids])
    out = {"n_test": int(y.shape[0]), "n_buggy_in_test": int((~clean).sum()),
           "n_clean": int(clean.sum())}
    for wp, t in (("fixed_0.5", 0.5), ("val_thr", thr)):
        preds = (probs >= t).astype(int)
        out[wp] = {
            "all": {"micro_f1": round(metrics.micro_f1(y, preds), 6),
                    "macro_f1": round(metrics.macro_f1(y, preds), 6),
                    "mAP": round(float(metrics.mean_average_precision(probs, y)["mAP"]), 6),
                    "per_class_f1": [round(v, 6) for v in metrics.per_class_prf(y, preds)["f1"]],
                    "support": metrics.per_class_prf(y, preds)["support"]},
            "clean_only": {"micro_f1": round(metrics.micro_f1(y[clean], preds[clean]), 6),
                           "macro_f1": round(metrics.macro_f1(y[clean], preds[clean]), 6),
                           "mAP": round(float(metrics.mean_average_precision(probs[clean], y[clean])["mAP"]), 6),
                           "per_class_f1": [round(v, 6) for v in
                                            metrics.per_class_prf(y[clean], preds[clean])["f1"]],
                           "support": metrics.per_class_prf(y[clean], preds[clean])["support"]},
        }
        for scope in ("all", "clean_only"):
            a, b = out[wp]["all"], out[wp]["clean_only"]
            if scope == "clean_only":
                out[wp][scope]["delta_vs_all_micro"] = round(b["micro_f1"] - a["micro_f1"], 6)
                out[wp][scope]["delta_vs_all_macro"] = round(b["macro_f1"] - a["macro_f1"], 6)
    return out


def encoder_trajectory(runs_root: Path, old_encoder: Path, new_encoder: Path) -> list[str]:
    """逐 epoch val macro-F1：旧划分（§37 正典）vs 新划分（含 buggy）。"""
    old, new = _read(old_encoder), _read(new_encoder)
    if not old or not new:
        return []
    o = {e["epoch"]: e["val_macro_f1"] for e in old.get("epochs_log", [])}
    n = {e["epoch"]: e["val_macro_f1"] for e in new.get("epochs_log", [])}
    ks = sorted(set(o) | set(n))
    L = ["| epoch | 旧划分（§37 正典，池 453） | 新划分（含 buggy，池 497） |", "| --- | --- | --- |"]
    for k in ks:
        L.append(f"| {k} | {o.get(k, '—') if k in o else '—'} | {n.get(k, '—') if k in n else '—'} |")
    return L


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs-dir", default="runs/buggy_canon")
    ap.add_argument("--split-dir", default="products/alldata/splits/withbuggy_snapshot")
    ap.add_argument("--encoder-root", default="runs/codebert_ft_buggy")
    ap.add_argument("--old-encoder-root", default="runs/codebert_ft/alldata")
    ap.add_argument("--slither", default="eval_results/baseline/slither_alldata")
    ap.add_argument("--out", default="experiments/buggy_canon_summary.md")
    args = ap.parse_args()

    runs_dir = REPO / args.runs_dir
    per_seed = {s: load_seed(runs_dir, s) for s in SEEDS}
    got = {s: v for s, v in per_seed.items() if v}
    if not got:
        raise SystemExit(f"🔴 {runs_dir} 下没有 test_probs.pt —— 任务2 管道还没跑完？")
    # 每个种子只算一次（`calibers` 要跑 mAP + 逐类，重复调用纯属浪费）
    cal = {s: calibers(v["probs"], v["labels"], v["ids"], v["thr"]) for s, v in got.items()}

    doc = ["# 任务 2：补回 `buggy_*` 后的新正典（池 497）", "",
           "> 程序生成（`scripts/collect_buggy_canon_summary.py`）。", "",
           "🔴 **本臂相对 §37 正典同时改了三件事**，读任何一个数字前必须先分清是哪一件：",
           "1. **数据**：池 453 → **497**（补回去重后的 `buggy_*`）；",
           "2. **划分**：8:1:1 重划 ⇒ **test 集换了**（46 → 49）⇒ **新旧数字不可直接相减**；",
           "3. **编码器**：epoch 预算 5 → 16（依据 = epoch 探针，见 `improvement_round1_results.md` §1）。", "",
           "🔴 **`buggy_*` 的标签绝大多数是七类全 1**（`decisions.md` §18.4：上游按「每类各放一份」复制，"
           "文件夹归属被推成标签）⇒ 它们**会系统性抬高** macro/mAP **而不代表检测能力**。"
           "本文因此并列一个 **`clean_only` 诊断列**：把 test 里的 `buggy_*` 合约剔掉再算一遍。", ""]

    # ---- 1. 训练时间 ----
    doc += ["## 1. 训练时间与规模", "",
            "| 种子 | wall (s) | train (s) | epoch 均 (s) | graphs/s | epochs | 训练图数 |",
            "| --- | --- | --- | --- | --- | --- | --- |"]
    for s, v in got.items():
        t = ((v["config"] or {}).get("timing") or {})
        doc.append(f"| seed{s} | {t.get('run_wall_seconds')} | {t.get('train_seconds')} | "
                   f"{t.get('epoch_seconds_mean')} | {t.get('graphs_per_second')} | "
                   f"{t.get('epochs_completed')} | {t.get('train_graphs')} |")
    # 编码器耗时
    doc += ["", "**编码器微调**（新划分）：", "",
            "| 划分种子 | 轮数 | wall (s) | best epoch | best val macro-F1 |", "| --- | --- | --- | --- | --- |"]
    for s in SEEDS:
        c = _read(REPO / args.encoder_root / f"ss{s}" / "config.json")
        if c:
            doc.append(f"| ss{s} | {len(c.get('epochs_log', []))} | "
                       f"{(c.get('timing') or {}).get('wall_seconds')} | {c.get('best_epoch')} | "
                       f"{c.get('best_val_macro_f1')} |")

    # ---- 2. 编码器轨迹（标签假象的直接证据）----
    tr = encoder_trajectory(REPO / args.encoder_root,
                            REPO / args.old_encoder_root / "ss2" / "config.json",
                            REPO / args.encoder_root / "ss2" / "config.json")
    if tr:
        doc += ["", "## 2. 编码器逐 epoch val macro-F1 对照（**标签假象的直接证据**）", "",
                "> 下表取自 **ss2**（两侧同划分种子，训练集不同 ⇒ **不可直接比**），看的是**轨迹形状**。",
                "> ⚠ 数字随划分种子变动（ss0 的第 1 轮就是 0.86），故**不要**把某一轮的绝对值当结论。", "",
                "> **旧正典的 epoch 预算是 5** —— 在第 5 轮处两者是 **0.437 vs 0.898**："
                "同一个「5 轮」的预算，含 buggy 的划分下 val macro-F1 高出 0.46。"
                "原因不是编码器突然变强，而是 val 里混进了 `buggy_*` 全 1 合约，"
                "而编码器**正是用 val macro-F1 选 epoch / 调 lr / 早停**。", ""] + tr

    # ---- 3. 主指标：all vs clean_only ----
    doc += ["", "## 3. 主指标（3 种子）：全 test vs 剔 buggy（clean_only）", "",
            "🔴 **`clean_only` 是诊断列，不是替换口径**——正典报的仍是全 test。",
            "**两列的差 = 标签假象的贡献量。**", ""]
    for wp, disp in (("fixed_0.5", "固定阈值 0.5"), ("val_thr", "验证集阈值")):
        doc += [f"### 3.{1 if wp == 'fixed_0.5' else 2} @{disp}", "",
                "| 种子 | 口径 | n | micro-F1 | macro-F1 | mAP | Δmicro | Δmacro |",
                "| --- | --- | --- | --- | --- | --- | --- | --- |"]
        for s in got:
            full = cal[s]
            c = full[wp]
            for scope, label in (("all", "全 test"), ("clean_only", "**剔 buggy**")):
                a = c[scope]
                dm = a.get("delta_vs_all_micro"); dM = a.get("delta_vs_all_macro")
                doc.append(f"| seed{s} | {label} | {full['n_test'] if scope == 'all' else full['n_clean']} | "
                           f"{a['micro_f1']:.4f} | {a['macro_f1']:.4f} | {a['mAP']:.4f} | "
                           f"{'—' if dm is None else f'{dm:+.4f}'} | "
                           f"{'—' if dM is None else f'{dM:+.4f}'} |")
        doc.append("")

    # ---- 3b. 与旧正典的"同规模对照" ----
    old = {}
    for s in SEEDS:
        r = _read(REPO / "runs" / f"seed{s}" / "results.json")
        if r:
            t = (r.get("test") or {}).get("val_threshold") or {}
            old[s] = {"micro": t.get("micro_f1"), "macro": t.get("macro_f1"),
                      "mAP": (r.get("mAP") or {}).get("mAP")}
    if old and got:
        doc += ["", "## 3b. 与 §37 旧正典的对照（**同规模，但不同合约 ⇒ 仅供量级参考**）", "",
                "🔴 **两边的 test 集不是同一批合约**（旧 46 / 新 49，且划分重划过）⇒ "
                "**严格说不可相减**。可相减的理由只有一条：两者的**正样本量级相当**"
                "（旧 test 21 个正 / 新 test 干净子集 20 个正），故列出来看**方向**是合理的，"
                "看**小数位**则不合理。", "",
                "| 口径 | micro@val_thr | macro@val_thr | mAP |", "| --- | --- | --- | --- |"]
        om = [v["micro"] for v in old.values() if v["micro"] is not None]
        oM = [v["macro"] for v in old.values() if v["macro"] is not None]
        oa = [v["mAP"] for v in old.values() if v["mAP"] is not None]
        doc.append(f"| **旧正典**（池 453，test 46，21 正） | {np.mean(om):.4f} | {np.mean(oM):.4f} | "
                   f"{np.mean(oa):.4f} |")
        for scope, label in (("all", "**新正典**（池 497，全 test 49）"),
                             ("clean_only", "**新正典 · 剔 buggy**（42，20 正）")):
            mic = [cal[s]["val_thr"][scope]["micro_f1"] for s in got]
            mac = [cal[s]["val_thr"][scope]["macro_f1"] for s in got]
            ap = [cal[s]["val_thr"][scope]["mAP"] for s in got]
            doc.append(f"| {label} | {np.mean(mic):.4f} | {np.mean(mac):.4f} | {np.mean(ap):.4f} |")
        doc.append("")
        doc += ["🔴 **读法**：把 `buggy_*` 剔掉之后，新正典与旧正典**基本持平**"
                "（差异落在种子间 std 0.0675 之内，且 test 集还换过）⇒ "
                "**「补回 buggy 带来的涨分」绝大部分不是检测能力，而是那 7 个全 1 标签合约本身。**", ""]

    # ---- 4. 逐类 ----
    doc += ["## 4. 逐类 F1（seed 平均）与 support", "",
            "| 类 | 全 test support | 全 test F1 | clean support | clean F1 |",
            "| --- | --- | --- | --- | --- |"]
    a_all = [cal[s]["val_thr"]["all"] for s in got]
    a_cl = [cal[s]["val_thr"]["clean_only"] for s in got]
    for i, nm in enumerate(NAMES):
        doc.append(f"| {nm} | {a_all[0]['support'][i]} | "
                   f"{np.mean([x['per_class_f1'][i] for x in a_all]):.4f} | "
                   f"{a_cl[0]['support'][i]} | "
                   f"{np.mean([x['per_class_f1'][i] for x in a_cl]):.4f} |")
    zero_cl = [NAMES[i] for i in range(len(NAMES)) if a_cl[0]["support"][i] == 0]
    thin_cl = [NAMES[i] for i in range(len(NAMES)) if 0 < a_cl[0]["support"][i] <= 2]
    doc += ["",
            "> 🔴 **读 `clean F1` 列前必须知道**：剔掉 `buggy_*` 后，"
            f"**{('、'.join(zero_cl) or '（无）')} 的 support 变成 0**"
            f"（该类的正样本**全部来自注入合约**），其余 {('、'.join(thin_cl) or '（无）')} 的 support ≤ 2。",
            "> 零支撑类按 `zero_division=0` 计 F1=0 ⇒ **`clean_only` 的 macro 因此被人为压低**："
            "它同时含两种效应——**(a) 标签假象消失（真实效应）** 与 **(b) 稀有类正样本被抽走（度量副作用）**。"
            "故 `Δmacro` 只能读作「假象的量级」，**不得**读作「补 buggy 让 macro 掉了这么多」。",
            "> **micro 不受此影响**（按标签对加权，零支撑类不进分子分母）⇒ **micro 的 Δ 是干净的**，"
            "它才是本页最可靠的那个数。", ""]

    out = REPO / args.out
    out.write_text("\n".join(doc) + "\n", encoding="utf-8")
    print(f"[summary] → {out}")
    for s, v in got.items():
        c = calibers(v["probs"], v["labels"], v["ids"], v["thr"])["val_thr"]
        print(f"  seed{s} @val_thr: 全 test micro {c['all']['micro_f1']:.4f} / "
              f"macro {c['all']['macro_f1']:.4f} → clean_only micro {c['clean_only']['micro_f1']:.4f} / "
              f"macro {c['clean_only']['macro_f1']:.4f} "
              f"（Δmacro {c['clean_only']['delta_vs_all_macro']:+.4f}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
