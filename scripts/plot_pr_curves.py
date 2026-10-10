#!/usr/bin/env python3
"""正典 vs 三条论文基线的 **PR 曲线**（逐类 + micro-average），零重实现指标。

**为什么单独出图**：`experiments/baseline_three_caliber_tables.md` 表 2 已有 mAP 一列，
但 mAP 是**一个数**——它把七类的排序能力压成均值，看不出「哪一类拖后腿」「差距落在哪个召回区间」。
PR 曲线是 mAP 的**完整底图**，两者必须同源：本脚本的 AP **直接调 `metrics.pr_curve`**
（其 `ap` 字段来自 `metrics.mean_average_precision`），与表里那一列逐位相同，不是第二份实现。

🔴 **四个必须随图读的口径**：
 1. **每个方法一条曲线 = 三种子的平均曲线**（2026-10-10 按用户要求由「3 条种子线」改为平均）。
    ⚠ **代价必须知情**：三种子是**三个独立划分**（
    `products/alldata/splits/withbuggy_snapshot/split_seed{0,1,2}.json`），test 集**不是同一批合约**
    （实测 seed0 与 seed1 的 test 无交集，各自 49 个）。因此这条「平均曲线」是在**统一 recall 网格
    上对各条曲线线性插值后再平均**得到的 —— 它**不是**任何一次真实运行的结果，只作趋势对照用；
    要引用单次实验的精确 P/R，须回 `eval_results/figures/pr_curves.json` 的逐种子曲线。
    图例的 AP = **三个种子 AP 的算术平均**（不含 ±，按用户要求）。
 2. **micro 曲线 = 标签对级**：把全部 `(样本, 类)` 对展平后按分数排序算全局 P/R，
    与主指标 **micro-F1 同口径**，是把多条曲线压成一条的**唯一**不失真做法。
 3. **不画随机基线**（2026-10-10 按用户要求移除）。如需参照：PR 空间的随机基线是
    **正类占比的水平线**（不是对角线——对角线是 ROC 的基线），逐类/整体的 prevalence
    仍保留在 `pr_curves.json` 里。
 4. **本图只含「有连续分数」的方法**。六个传统工具的产物是**逐合约二值规则命中**
    （`classes` ∈ {0,1}⁷，工具自带的 `checks` 只有检测项名、无置信度）⇒ 没有可排序的分数，
    PR 曲线**退化成一个工作点、AUC 无定义**，故**不进本图**（判据见
    `experiments/baseline_three_caliber_tables.md` 表 2 的 mAP 行注）。

用法（仓库根目录）：
    python scripts/plot_pr_curves.py                     # 正典（池 497）+ 三基线
    python scripts/plot_pr_curves.py --with-egfl-ownlr   # 追加 EGFL 论文自带 lr 那一行
    python scripts/plot_pr_curves.py --layout canon37    # 对照口径（池 453；产物已清理则报缺）
产物：`eval_results/figures/pr_micro_<layout>.{png,pdf}`、
      `eval_results/figures/pr_per_class_<layout>.{png,pdf}`、
      `eval_results/figures/pr_curves.json`（逐格 AP，供复核）。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch

import matplotlib
matplotlib.use("Agg")                                            # 无头：本机没有 DISPLAY
import matplotlib.pyplot as plt                                  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics                                                   # noqa: E402  只调既有实现

NAMES = list(metrics.VULN_NAMES)
SEEDS = (0, 1, 2)

# 两段口径（与 `collect_baseline_tables.LAYOUTS` 同源语义；此处**只读不写**）
LAYOUTS = {
    "buggy": {"canon": "runs/buggy_canon/seed{seed}",
              "base": "eval_results/baseline/{arm}_buggy/seed{seed}",
              "title": "canonical pool 497 (incl. buggy_*)"},
    "canon37": {"canon": "runs/seed{seed}",
                "base": "eval_results/baseline/{arm}/seed{seed}",
                "title": "reference pool 453"},
}

# 行 = (显示名, 产物键, 颜色)。**正典置首**，其余按 5.3 对比表的行序。
METHODS = (
    ("Ours (SSM-HG)", "canon", "#d62728"),
    ("MVD-HG", "mvdhg", "#1f77b4"),
    ("EGFL", "egfl", "#2ca02c"),
    ("MANDO-LLM", "mando", "#ff7f0e"),
)
OPTIONAL = (("EGFL (own lr)", "egfl_ownlr", "#9467bd"),)

# 平均曲线用的统一 recall 网格。🔴 因为三种子的 test 集不同，**不能**直接对概率取平均；
# 唯一可行的做法是各自算 PR 再在公共 recall 轴上插值后平均（口径已在模块 docstring 声明）。
GRID = np.linspace(0.0, 1.0, 201)


# ------------------------------------------------------------------ 读取层
def path_of(layout: str, key: str, seed: int) -> Path:
    L = LAYOUTS[layout]
    rel = L["canon"] if key == "canon" else L["base"]
    return REPO / rel.format(seed=seed, arm=key) / "test_probs.pt"   # 一次 format：模板里 {seed}/{arm} 并存


def load_curves(layout: str, key: str) -> dict[int, dict]:
    """逐种子的 PR 曲线（**委托 `metrics.pr_curve`**，本层不做任何指标计算）。"""
    out: dict[int, dict] = {}
    for s in SEEDS:
        p = path_of(layout, key, s)
        if not p.exists():
            continue
        b = torch.load(p, map_location="cpu")
        out[s] = metrics.pr_curve(b["probs"].numpy(), b["labels"].numpy().astype(int),
                                  names=NAMES)
    return out


def _curve_of(c: dict, cls: str | None) -> dict | None:
    return c["micro"] if cls is None else c["classes"].get(cls)


def ap_stats(cv: dict[int, dict], cls: str | None) -> tuple[float, float, int]:
    """AP 跨种子 mean/std/n（`cls=None` 取 micro）。种子数 <2 时 std 记 0。"""
    vals = [d["ap"] for c in cv.values() if (d := _curve_of(c, cls)) is not None]
    vals = [v for v in vals if v is not None]
    if not vals:
        return float("nan"), float("nan"), 0
    return (float(np.mean(vals)),
            float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0, len(vals))


def mean_curve(cv: dict[int, dict], cls: str | None) -> dict | None:
    """三种子 PR 曲线的**平均曲线**（在公共 recall 网格 `GRID` 上插值后平均）。

    ⚠ 三种子的 test 集**不是同一批合约** ⇒ 这条线不是任何一次真实运行的结果，
    只作趋势对照；精确的逐种子 P/R 见 `pr_curves.json`。

    实现要点：sklearn 的 `precision_recall_curve` 返回的 recall **递减**，先翻成递增；
    同一 recall 上取**最大 precision**（PR 曲线的标准包络，与 `average_precision_score`
    的阶梯积分同思路），再线性插值到公共网格。
    """
    pcs = []
    for c in cv.values():
        d = _curve_of(c, cls)
        if d is None:
            continue
        r = np.asarray(d["recall"])[::-1]
        p = np.asarray(d["precision"])[::-1]
        ur, idx = np.unique(r, return_inverse=True)
        up = np.full(ur.shape, -np.inf)
        np.maximum.at(up, idx, p)
        pcs.append(np.interp(GRID, ur, up))
    if not pcs:
        return None
    return {"recall": GRID, "precision": np.mean(pcs, axis=0), "n_seeds": len(pcs)}


# ------------------------------------------------------------------ 绘图层
def _panel(ax, methods, layout, cls, cvs_cache, *, legend=False,
           ylabel=False, xlabel=False, title=None):
    """一个面板：每个方法画**一条**三种子平均曲线（不画随机基线）。"""
    for label, key, color in methods:
        cv = cvs_cache[key]
        d = mean_curve(cv, cls) if cv else None
        if d is None:
            ax.text(0.5, 0.5, "no artifact", ha="center", va="center",
                    transform=ax.transAxes, fontsize=8, color="0.5", rotation=30)
            continue
        ax.plot(d["recall"], d["precision"], color=color, lw=1.6, zorder=3)
        m, _sd, n = ap_stats(cv, cls)
        if n:
            ax.plot([], [], color=color, lw=2.2, label=f"{label}  AP {m:.3f}")
    if title:
        ax.set_title(title, fontsize=9.5)
    ax.set_xlim(-0.02, 1.02)
    ax.set_ylim(-0.02, 1.02)
    ax.grid(alpha=0.25, lw=0.5)
    ax.tick_params(labelsize=7.5)
    if xlabel:
        ax.set_xlabel("Recall", fontsize=8.5)
    if ylabel:
        ax.set_ylabel("Precision", fontsize=8.5)
    if legend:
        ax.legend(fontsize=8, loc="lower left", framealpha=0.92)


def fig_micro(methods, layout, cvs_cache) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(6.6, 5.2))
    _panel(ax, methods, layout, None, cvs_cache, legend=True, ylabel=True, xlabel=True,
           title=f"Micro-average PR (label-pair level), 3-seed mean curve\n"
                 f"{LAYOUTS[layout]['title']}")
    fig.tight_layout()
    return fig


def fig_per_class(methods, layout, cvs_cache) -> plt.Figure:
    """网格 = **行：方法** × **列：类**（末列为 micro）。每格 3 条种子曲线。"""
    panels = [(n, n) for n in NAMES] + [("micro\n(label-pair)", None)]
    nrow, ncol = len(methods), len(panels)
    fig, axes = plt.subplots(nrow, ncol, figsize=(2.55 * ncol, 2.85 * nrow), squeeze=False)
    for r, (label, key, color) in enumerate(methods):
        for c, (ptitle, cls) in enumerate(panels):
            ax = axes[r][c]
            # 🔴 列标题 = 类名（只在首行）；**行标签用图左侧的独立文字**（不在格子标题里），
            #    否则只有 (0,0) 那格带方法名，其余行看不出来 —— 初版就踩了这个。
            _panel(ax, [(label, key, color)], layout, cls, cvs_cache,
                   ylabel=(c == 0), xlabel=(r == nrow - 1),
                   title=ptitle if r == 0 else None)
        m, _sd, n = ap_stats(cvs_cache[key], None)      # 只取均值（用户要求不显示波动值）
        fig.text(0.012, 1 - (r + 0.55) / nrow, f"{label}\nmicro-AP {m:.3f}",
                 rotation=90, va="center", ha="center", fontsize=9.5, color=color, weight="bold")
    fig.suptitle(f"Per-class PR curves (3-seed mean curve per method) — {LAYOUTS[layout]['title']}\n"
                 f"rows = method, columns = vulnerability class", fontsize=12, y=0.998)
    fig.tight_layout(rect=(0.032, 0, 1, 0.955))
    return fig


# ------------------------------------------------------------------ 入口
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--layout", default="buggy", choices=sorted(LAYOUTS))
    ap.add_argument("--with-egfl-ownlr", action="store_true",
                    help="追加 EGFL（论文自带 lr=0.002）那一行（5.3 表的敏感性臂）")
    ap.add_argument("--out-dir", default="eval_results/figures")
    args = ap.parse_args()

    methods = list(METHODS) + (list(OPTIONAL) if args.with_egfl_ownlr else [])
    cvs_cache = {key: load_curves(args.layout, key) for _l, key, _c in methods}
    missing = [l for l, k, _c in methods if not cvs_cache[k]]
    if missing:
        print(f"[plot_pr_curves] ⚠ 无产物、图中将标 no artifact：{'、'.join(missing)}")
    if all(not v for v in cvs_cache.values()):
        raise SystemExit(f"[plot_pr_curves] 🔴 布局 {args.layout} 下所有方法都没有 test_probs.pt，"
                         "拒绝出图（池 453 的产物已于 2026-10-02 清理）")

    out = REPO / args.out_dir
    out.mkdir(parents=True, exist_ok=True)
    for name, fig in (("pr_micro", fig_micro(methods, args.layout, cvs_cache)),
                      ("pr_per_class", fig_per_class(methods, args.layout, cvs_cache))):
        for ext in ("png", "pdf"):
            p = out / f"{name}_{args.layout}.{ext}"
            fig.savefig(p, dpi=200, bbox_inches="tight")
            print(f"[plot_pr_curves] 写入 {p.relative_to(REPO)}")
        plt.close(fig)

    # 逐格 AP 落盘 —— 供复核「图上的 AP」与「表里的 mAP」是不是同一个数
    rec = {"layout": args.layout, "title": LAYOUTS[args.layout]["title"],
           "note": "AP 由 metrics.mean_average_precision 给出（经 metrics.pr_curve），"
                   "与 experiments/baseline_three_caliber_tables.md 表 2 的 mAP 列同源；"
                   "**图例的 AP = 三种子 AP 的算术平均**（无 ±）。⚠ 三种子是三个独立划分"
                   "（test 集不是同一批合约）⇒ 图上的单条曲线是三种子曲线在公共 recall 网格上"
                   "插值后平均得到，**不是任何一次真实运行的结果**；下方 per_seed 存逐种子 AP。"
                   "曲线本身是确定性的、可重算：`metrics.pr_curve(...)` 取逐种子点，"
                   "再经 `plot_pr_curves.mean_curve(...)` 平均（无需重训）。",
           "methods": {}}
    for label, key, _c in methods:
        cv = cvs_cache[key]
        per_seed = {str(s): {"micro_ap": c["micro"]["ap"],
                             **{n: c["classes"][n]["ap"] for n in NAMES if n in c["classes"]},
                             "skipped": c["skipped"]}
                    for s, c in sorted(cv.items())}
        m_micro, sd_micro, _n = ap_stats(cv, None)
        per_class_means = [ap_stats(cv, n)[0] for n in NAMES
                           if any(n in c["classes"] for c in cv.values())]
        rec["methods"][label] = {
            "per_seed": per_seed,
            "micro_ap_mean": m_micro, "micro_ap_std": sd_micro,
            "mAP_mean_over_seeds": float(np.mean(per_class_means)) if per_class_means else None,
            "seeds": sorted(cv),
        }
    (out / "pr_curves.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1),
                                        encoding="utf-8")
    print(f"[plot_pr_curves] 写入 {(out / 'pr_curves.json').relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
