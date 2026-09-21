#!/usr/bin/env python3
"""七类逐类 F1「三口径 × 两工作点」对比表（**纯聚合层**：不重实现任何指标，只调 `metrics`）。

**存在理由**：论文要一张「7 种漏洞各自的 F1」在**四组对象**（正典 / 增强集 / 消融臂 / DIVE）
之间可比的表。这些数字早已存在，但散在三处、口径互不相同：

| 来源 | 产物 | 提供什么 |
|---|---|---|
| ① 主库 | `runs/seed{S}/`、`runs/ablation/<臂>/seed{S}/` | `test_probs.pt` + `thresholds.json` |
| ② 增强集 | `runs/augmentation/seed{S}/`、`runs/ablation_aug/<臂>/seed{S}/` | 同上 |
| DIVE 外部测试 | `eval_results/dive/matrix_{main,aug}.json` | 逐种子逐类 P/R/F1 + 漏洞子集块 |

🔴 **三个口径的逐类格含义不同，但都落在同一张「行 × 7 类」网格上**：

| 口径 | 逐类格（列的含义） | 汇总列 | 回答的问题 |
|---|---|---|---|
| `micro` | **全测试集**逐类 F1 | `metrics.micro_f1`（标签对级全局 F1） | 七类标签判得准不准 |
| `buggy` | **仅 `y.any(axis=1)` 的合约**上的逐类 F1 | `metrics.buggy_f1`（子集切片后算 micro-F1） | 在真正有漏洞的合约上判得准不准 |
| `macro` | **与 `micro` 逐格相同** | `metrics.macro_f1`（= 上表 7 个 F1 的未加权平均） | 七类等权平均表现 |

⚠ **`macro` 口径的逐类格与 `micro` 口径逐位相同，这是数学恒等**（macro-F1 就是逐类 F1 的
算术平均），不是本脚本重复计算。故「macro 表」的正文与「micro 表」一致，**差异只在汇总列**。
`macro` 表的价值在于：它让「汇总列怎么来的」一眼可见（把这 7 个数平均即得）。

⚠ **`buggy` 口径不是「合约级二分类 F1」**（`decisions.md` §30）：后者把七类真值与预测都塌成
`any(...)`，会把「有漏洞但报错了类」整类免罚；本表**不做塌缩**。两者免罚方向相反，不得互换。

🔴 **逐类格在薄支撑下不可解读**：① 主库 test 集逐类 support 低到 **1**（`dos`/`front_running`），
此时单类 F1 一次翻转就能差 0.67。故本文件**开头先打 support 表**——与 F1 分开呈现，
不为每张表重复 46 行 × 8 列。

用法（仓库根目录）：
    python scripts/collect_three_caliber_tables.py --out experiments/per_class_three_caliber_tables.md
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

import metrics                                                          # noqa: E402
import run_ablation as RA                                               # noqa: E402

SEEDS = (0, 1, 2)
NAMES = list(metrics.VULN_NAMES)
# 工作点键 → (显示名, DIVE matrix 里的键名, DIVE matrix 里的漏洞子集键名)
WORKPOINTS = (("fixed_0.5", "0.5", "fixed_0.5", "buggy_subset_0.5"),
              ("val_thr", "验证集阈值", "source_val_threshold", "buggy_subset_val_thr"))
CALIBERS = ("micro", "buggy", "macro")


# ------------------------------------------------------------------ 读取层
def _read_json(p: Path):
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def _load_probs(run_rel: str, seed: int):
    """读 `test_probs.pt`；缺失返回 None（**不静默回退到更差的来源**）。"""
    p = REPO / run_rel / f"seed{seed}" / "test_probs.pt"
    if not p.exists():
        return None
    b = torch.load(p, map_location="cpu")
    return b["probs"].numpy(), b["labels"].numpy()


def _val_thr(run_rel: str, seed: int):
    d = _read_json(REPO / run_rel / f"seed{seed}" / "thresholds.json")
    return None if d is None else float(d["best_threshold"])


def _per_class(y, preds, mask=None):
    """逐类 F1（可选先按 `mask` 切行）——**唯一实现来自 `metrics.per_class_prf`**。"""
    if mask is not None:
        y, preds = y[mask], preds[mask]
    return metrics.per_class_prf(y, preds)


def row_from_run(run_rel: str, seeds=SEEDS) -> dict:
    """一个 run 目录（正典或消融臂）→ 逐种子、逐工作点、逐口径的 (逐类 F1, 汇总)。

    返回 `{wp: {caliber: [(f1[7], summary), ...]}}`，外加 `{wp: support}`。
    `seeds` 只取一个元素时 = **最佳种子口径**（表里就没有 ±，只有一个数）。
    """
    out = {wp: {c: [] for c in CALIBERS} for wp, *_ in WORKPOINTS}
    support = {}
    for s in seeds:
        blob = _load_probs(run_rel, s)
        if blob is None:
            continue
        probs, labels = blob
        for wp, _disp, _dk, _bk in WORKPOINTS:
            thr = 0.5 if wp == "fixed_0.5" else _val_thr(run_rel, s)
            if thr is None:
                continue
            preds = metrics.binary_preds(torch.as_tensor(probs), thr).numpy()
            y = labels.astype(int)
            mask = y.any(axis=1)
            full = _per_class(y, preds)
            sub = _per_class(y, preds, mask=mask)
            # support 逐种子留全（① 主库逐种子不同：3/3/3、2/2/3…），不取首种子了事
            support.setdefault(wp, []).append(full["support"])
            out[wp]["micro"].append((full["f1"], metrics.micro_f1(y, preds)))
            out[wp]["buggy"].append((sub["f1"], metrics.buggy_f1(y, preds)["f1"]))
            out[wp]["macro"].append((full["f1"], metrics.macro_f1(y, preds)))
    return {"cells": out, "support": support}


def row_from_dive(matrix_file: Path, arm: str = "canon", seeds=SEEDS) -> dict:
    """DIVE matrix json 的一个臂 → 同上结构（逐类 P/R/F1 已在 json 里，零重算）。"""
    d = _read_json(matrix_file)
    if d is None:
        return None
    seed_list = [p for p in d["arms"].get(arm, {}).get("per_seed", [])
                 if p["seed"] in seeds]
    out = {wp: {c: [] for c in CALIBERS} for wp, *_ in WORKPOINTS}
    support = {}
    for p in seed_list:
        for wp, _disp, dkey, bkey in WORKPOINTS:
            t = p["test"][dkey]
            support.setdefault(wp, []).append(t["per_class"]["support"])
            b = p.get(bkey)
            if b is None:                      # 旧 matrix（未重跑）：buggy 口径留空，不编数
                out[wp]["buggy"].append(([None] * len(NAMES), None))
            else:
                out[wp]["buggy"].append((b["per_class"]["f1"], b["buggy_f1"]))
            out[wp]["micro"].append((t["per_class"]["f1"], t["micro_f1"]))
            out[wp]["macro"].append((t["per_class"]["f1"], t["macro_f1"]))
    return {"cells": out, "support": support}


# ------------------------------------------------------------------ 聚合与排版
def _ms(vals) -> str:
    """逐类或标量序列 → `mean±std`（ddof=1）；全 None 记 `—`，n<2 只给均值。"""
    v = [x for x in vals if x is not None]
    if not v:
        return "—"
    if len(v) == 1:
        return f"{v[0]:.4f}"
    return f"{np.mean(v):.4f}±{np.std(v, ddof=1):.4f}"


def _ms_col(pairs, idx=None) -> str:
    """`[(f1[7], summary), ...]` → 某一列的 `mean±std`（`idx=None` 取汇总标量）。"""
    vals = [(p[1] if idx is None else p[0][idx]) for p in pairs]
    return _ms(vals)


def render_table(rows: list[tuple[str, dict]], wp: str, caliber: str) -> list[str]:
    head = ("| 行 | " + " | ".join(NAMES) + " | **汇总** |")
    sep = "| --- | " + " | ".join(["---"] * len(NAMES)) + " | --- |"
    lines = [head, sep]
    for label, r in rows:
        pairs = r["cells"][wp][caliber]
        if not pairs:
            lines.append(f"| {label} | " + " | ".join(["—"] * (len(NAMES) + 1)) + " |")
            continue
        cells = [_ms_col(pairs, i) for i in range(len(NAMES))]
        lines.append(f"| {label} | " + " | ".join(cells) + f" | **{_ms_col(pairs)}** |")
    return lines


def best_seed_of(corpus: str) -> int:
    """该**语料**的最佳种子 = 正典在**主指标 micro-F1@val_thr** 上最高的那个种子。

    口径与 `collect_ablation_results.best_seed_of` / `collect_dive_comparison` **完全一致**
    （2026-09-20 用户裁定；理由见 `decisions.md` §39）：按论文主指标选、只从正典选、
    全部臂与该语料的两列共用同一个种子。
    """
    f = (REPO / "eval_results" / "ablation" /
         ("collected.json" if corpus == "main" else "collected_aug.json"))
    d = _read_json(f)
    if d is None:
        return {"main": 2, "aug": 1}[corpus]        # 兜底：已裁定的定值
    ps = d["canon"]["per_seed"]
    return int(max(ps, key=lambda s: ps[s]["micro_thr"]))


def best_seed_from_runs(run_rel: str, seeds=SEEDS) -> int:
    """从一个 run 目录自己的 `seed*/results.json` 选最佳种子（**主指标 micro-F1@val_thr**）。

    与 `best_seed_of` 同一口径（`decisions.md` §39），但**不读 `eval_results/ablation/`**——
    那份 JSON 服务的是正典那批 run，换正典（如任务 2 的含 buggy 臂）后它就是**旧工作点**，
    拿它选种子会把"按旧正典挑的种子"套到新正典上（同一类口径错配，本仓已栽过两次）。
    """
    best, best_v = None, -1.0
    for s in seeds:
        d = _read_json(REPO / run_rel / f"seed{s}" / "results.json")
        if not d:
            continue
        v = (d.get("test", {}).get("val_threshold", {}) or {}).get("micro_f1")
        if v is not None and v > best_v:
            best, best_v = s, float(v)
    return best if best is not None else seeds[0]


def build_rows(best_seed: bool = False):
    """按「① 正典 → ① 21 臂 → ② 正典 → ② 21 臂 → DIVE ①②模型」构造行。

    `best_seed=True` 时**每个语料只取它自己那个最佳种子**（① seed2 / ② seed1），
    且该语料的内测行与 DIVE 行**共用同一个种子**——否则同一批行里"① 模型"会是不同模型。
    """
    rows, supports = [], {}
    k = {c: [best_seed_of(c)] if best_seed else list(SEEDS) for c in ("main", "aug")}
    groups = (("① 主库", "runs", "runs/ablation", "eval_results/dive/matrix_main.json",
               "①模型", "main"),
              ("② 增强集", "runs/augmentation", "runs/ablation_aug",
               "eval_results/dive/matrix_aug.json", "②模型", "aug"))
    for gname, canon_dir, abl_root, matrix_file, dtag, ckey in groups:
        r = row_from_run(canon_dir, k[ckey])
        rows.append((f"**{gname} · 正典**", r))
        supports[gname] = r["support"]
        for arm, _ov, desc in RA.ABLATIONS:
            rel = f"{abl_root}/{arm}"
            if not (REPO / rel).exists():
                continue
            rows.append((f"{gname} · `{arm}`", row_from_run(rel, k[ckey])))
        d = row_from_dive(REPO / matrix_file, seeds=k[ckey])
        if d is not None and any(d["cells"][wp]["micro"] for wp, *_ in WORKPOINTS):
            rows.append((f"**DIVE（{dtag}）**", d))
            supports[f"DIVE（{dtag}）"] = d["support"]
    return rows, supports


def _thin_support_note(supports: dict) -> str:
    """按**实际 support** 生成薄支撑警告——**不写死数字**。

    ⚠ 这一行原来是硬编码的「① 主库 test 的 `dos`/`front_running` 逐类 support 低到 1」，
    换正典（任务2 的池 497 划分）后那句就**变成假的**（实测 support 是 6–14）。
    样板句失真是本仓点过名的一类问题（`decisions.md` §40.7 第 5 条）——
    这类句子**不会报错、只会误导**，故改为从数据推导。
    """
    per_seed = next(iter(supports.values()), {}).get("val_thr") or []
    if not per_seed:
        return "> ⚠ 逐类 support 见上表；support ≤ 2 的类，单类 F1 一次翻转即跳 ±0.67，跨行 Δ 不可解读。"
    mins = [min(per_seed[i][c] for i in range(len(per_seed))) for c in range(len(NAMES))]
    thin = [NAMES[c] for c in range(len(NAMES)) if mins[c] <= 2]
    if thin:
        return (f"> ⚠ **跨全部种子**的最小逐类 support：`{'`/`'.join(thin)}` ≤ **2** —— "
                f"该 support 下单类 F1 一次翻转就差 0.67，跨行 Δ 不可解读"
                f"（大纲 5.1：support ≤ 2 的类仅作描述性呈现、不进入方法间比较结论）。")
    return (f"> ✅ **全部 7 类在全部种子上 support ≥ {min(mins)}** —— 无 support ≤ 2 的薄支撑类，"
            f"逐类 F1 可进入方法间比较（仍受重跑抖动 0.012 约束）。")


def support_block(supports: dict) -> list[str]:
    """逐类正样本数**按种子呈现**（`a/b/c`）——① 主库逐种子不同，取首种子会丢信息。"""
    lines = ["| 语料 | " + " | ".join(NAMES) + " |",
             "| --- | " + " | ".join(["---"] * len(NAMES)) + " |"]
    for name, sp in supports.items():
        per_seed = sp.get("val_thr") or sp.get("fixed_0.5")
        if not per_seed:
            continue
        n_cls = len(per_seed[0])
        cells = ["/".join(str(per_seed[i][c]) for i in range(len(per_seed)))
                 for c in range(n_cls)]
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    lines += ["",
              "> 上表为 test 集**逐类正样本数**，按种子 0/1/2 排列（`a/b/c`）。"
              "两个工作点的 support **逐位相同**（同一测试集，只是阈值不同），故只列一张。", "",
              "> ⚠ **漏洞子集（buggy 口径）的逐类 support 与上表逐位相同**——"
              "干净合约七类真值全 0，切片不会增减任何一类的正样本数。"
              "故「buggy 表」的 support 直接读本表，不另列。", ""]
    return lines


def main() -> None:
    ap = argparse.ArgumentParser(description="七类逐类 F1 三口径 × 两工作点对比表")
    ap.add_argument("--out", default="", help="写入的 markdown 路径；留空只打印到 stdout")
    ap.add_argument("--canon-only-runs", default=None,
                    help="**只出主库一行**：行 = 该 run 目录的正典（如 `runs/buggy_canon`）。"
                         "供新正典（任务 2 的含 buggy 臂）单独出一份表；"
                         "最佳种子从**该目录自己的** results.json 选，不读旧正典的 collected.json。")
    args = ap.parse_args()

    if args.canon_only_runs:
        rel = args.canon_only_runs
        k = best_seed_from_runs(rel)
        rows_best = [(f"**① 主库 · 正典（{rel}）**", row_from_run(rel, [k]))]
        rows = [(f"**① 主库 · 正典（{rel}）**", row_from_run(rel, list(SEEDS)))]
        supports = {"① 主库": rows[0][1]["support"]}
        k_main, k_aug = k, k
        header_extra = [
            f"> 🔴 **本表的正典 = `{rel}`**（含 `buggy_*` 的新池 497 / 新划分），"
            f"**与 `per_class_three_caliber_tables.md` 不是同一个 test 集** ⇒ "
            f"两边的数字**不可直接相减**。", "",
            "> 🔴🔴 **本表的逐类格与汇总列都含「标签假象」，引用前必须读 "
            "`experiments/buggy_canon_summary.md`**：`buggy_*` 合约的标签绝大多数是**七类全 1**"
            "（上游按「每类各放一份」复制，`decisions.md` §18.4），模型「全报有漏洞」即可在它们身上拿满分。"
            "实测（3 种子）：把 test 里那 **7 个** `buggy_*` 剔掉后，"
            "**micro 掉 0.10–0.16、macro 掉 0.33–0.61**（`buggy_canon_summary.md` §3）。",
            "> ⇒ **本表可用于「申报口径下的完整读数」，但不得据此声称「补回 buggy 提升了检测能力」。**", ""]
    else:
        rows_best, sup_best = build_rows(best_seed=True)
        rows, supports = build_rows(best_seed=False)
        k_main, k_aug = best_seed_of("main"), best_seed_of("aug")
        header_extra = []
    if not rows:
        raise SystemExit("[tables] 没有取到任何行——产物缺失？")

    doc = ["# 七类逐类 F1：三口径 × 两工作点对比", "",
           "> 程序生成（`scripts/collect_three_caliber_tables.py`）：**只搬运产物、只调 `metrics`**，"
           "不手抄、不重实现指标。", "",
           (f"> 🔴 **表 1–6 = 最佳种子口径**（用户 2026-09-20 裁定，`decisions.md` §39；取 **seed{k_main}**，"
            f"判据 = 该正典在 micro-F1@val_thr 上最高），**表 7–12 = 3 种子 mean±std 附录**（ddof=1）。"
            if args.canon_only_runs else
            f"> 🔴 **两组表并列**：**表 1–6 = 最佳种子口径**（用户 2026-09-20 裁定，`decisions.md` §39；"
            f"① 取 **seed{k_main}**、② 取 **seed{k_aug}**，判据 = 该语料正典在 micro-F1@val_thr 上最高），"
            f"**表 7–12 = 3 种子 mean±std 附录**（ddof=1）。"), "",
           "> ⚠ 最佳种子口径下**没有 ±**（单种子无方差），且本仓实测重跑抖动 ≈0.012"
           "（约为种子间 std 的 40%，`decisions.md` §36.4）⇒ **不得**据它下「某干预有效」的结论；"
           "那种结论仍须同配对 ≥9 点。", "",
           "> **三个口径的区别**：`micro` / `macro` 的逐类格是**全测试集**逐类 F1，"
           "`buggy` 的逐类格是**仅 `y.any(axis=1)` 的合约**上的逐类 F1。", "",
           "> 🔴 **`macro` 表与 `micro` 表的逐类格逐位相同**——macro-F1 就是那 7 个数的"
           "未加权平均，**差异只在汇总列**（这是恒等，不是重复计算）。", "",
           _thin_support_note(supports), ""]
    doc += header_extra
    doc += ["## 0. 逐类 support（先读）", ""]
    doc += support_block(supports)
    doc += ["---", ""]

    # 表号按「工作点 → 口径」顺序连续编号；**最佳种子系列在前**（表 1–6）
    title_of = {"micro": "micro-F1 口径（全测试集逐类 F1）",
                "buggy": "buggy-F1 口径（仅有漏洞合约子集逐类 F1）",
                "macro": "macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均）"}
    n = 0
    doc += ["---", "", f"# 一、主口径：最佳种子（① seed{k_main} / ② seed{k_aug}）", ""]
    for wp, disp, _dk, _bk in WORKPOINTS:
        for caliber in CALIBERS:
            n += 1
            doc += [f"## 表 {n} —— {title_of[caliber]} @{disp}", ""]
            doc += render_table(rows_best, wp, caliber)
            doc += [""]
    doc += ["---", "", "# 二、附录：3 种子 mean±std（保留——单种子无方差，见抬头）", ""]
    for wp, disp, _dk, _bk in WORKPOINTS:
        for caliber in CALIBERS:
            n += 1
            doc += [f"## 表 {n} —— {title_of[caliber]} @{disp}", ""]
            doc += render_table(rows, wp, caliber)
            doc += [""]

    text = "\n".join(doc)
    if args.out:
        out = Path(args.out)
        if not out.is_absolute():
            out = REPO / out
        out.write_text(text + "\n", encoding="utf-8")
        print(f"[tables] {len(rows)} 行 × {n} 表 → {out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
