#!/usr/bin/env python3
"""同划分多种子概率集成（`improvement_proposals.md` §2.1 的 P1 项）。

**它回答什么**：同一划分、不同**训练种子**训出的 N 个模型，把预测概率**平均**后再阈值化，
是否比单模型好？这是把「训练种子方差」从**噪声**变成**增益**——与「挑最好的那次种子」
（`decisions.md` §39 的"最佳种子"口径）性质相反：后者是选择膨胀，前者是方差消减。

**零重训**：只读各 run 已有的 `val_best_probs.pt` / `test_probs.pt`，
阈值在**平均后的 val 概率**上搜（与单模型完全同一套流程：阈值只来自验证集）。

🔴 **两条口径必须随结果一起报**：
  1. **对齐靠 `sample_ids`，不靠行序**。不同 run 的样本顺序不保证一致；
     按行号平均会静默地把 A 的合约和 B 的合约平均在一起——**不报错、结果无意义**（§28/§29 同类）。
     本脚本对每个 run 的 val/test 都断言 sample_ids 与基准 run **逐个相等**，不等即报错退出。
  2. **对照要报三个数**：单模型均值（mean of singles）、单模型最好（best of singles）、
     集成。只报「集成 vs 最好单模型」会低估集成（因为最好单模型已含选择膨胀）；
     只报「集成 vs 均值」会高估。两个都报才诚实。

用法（从仓库根目录运行）：
  python scripts/ensemble_eval.py --group runs/cbft_study --prefix cbft
  python scripts/ensemble_eval.py --group runs/seed --prefix seed --split-seeds 0 1 2

产物：`eval_results/ensemble/<group名>.json` + 同名 `.md`
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics                                                    # noqa: E402

OUT_ROOT = REPO / "eval_results" / "ensemble"


def rel(path: Path) -> str:
    """相对仓库根的显示路径；**不在仓库内时退回绝对路径**（不抛错）。

    `Path.relative_to` 对仓库外路径会抛 `ValueError`——而 run 目录允许在仓库外
    （单元测试的 tmp 目录、以及将来可能的共享盘产物）。报告里显示什么不重要，
    **因为路径显示不出来而中断整次分析**才是问题。
    """
    try:
        return str(path.resolve().relative_to(REPO))
    except ValueError:
        return str(path)


def load_probs(path: Path) -> tuple[torch.Tensor, torch.Tensor, list[str], float | None]:
    """读一个 run 的概率产物 → (probs, labels, sample_ids, threshold)。"""
    if not path.exists():
        raise FileNotFoundError(f"缺产物：{path}（该 run 未跑完？）")
    d = torch.load(path, map_location="cpu")
    if not isinstance(d, dict) or "probs" not in d:
        raise ValueError(f"{path} 结构不是 {probs,labels,sample_ids,...} 字典")
    return d["probs"], d["labels"], list(d["sample_ids"]), d.get("threshold")


def search_threshold(probs: torch.Tensor, labels: torch.Tensor) -> tuple[float, float]:
    """在验证集上按 micro-F1 搜全局阈值。

    **直接调 `metrics.search_global_threshold`**（候选 0.20–0.80 步长 0.05、并列取小阈值），
    保证集成的阈值搜索与单模型**不是两套逻辑**（两份实现必然漂移——§28 的教训）。
    """
    res = metrics.search_global_threshold(probs, labels)
    if res["best_threshold"] is None:
        raise ValueError("阈值搜索未产出候选（阈值列表为空？）")
    return float(res["best_threshold"]), float(res["best_micro_f1"])


def evaluate_group(group: Path, prefix: str, ts_list: list[int],
                   split_seeds: list[int]) -> dict:
    """逐划分种子：取 N 个训练种子的 run → 平均 → 与单模型对比。"""
    out: dict = {"group": str(group), "prefix": prefix, "split_seeds": {}}
    for ss in split_seeds:
        runs = []
        for ts in ts_list:
            d = group / f"{prefix}_ts{ts}_ss{ss}" / f"seed{ts}"
            if not d.exists():
                d = group / f"{prefix}_ts{ts}_ss{ss}"
            runs.append(d)
        runs = [d for d in runs if d.exists()]
        if len(runs) < 2:
            out["split_seeds"][f"ss{ss}"] = {"skipped": f"可用 run 只有 {len(runs)} 个（<2）"}
            continue
        rec: dict = {"runs": [rel(d) for d in runs], "n_models": len(runs)}
        val_ref = load_probs(runs[0] / "val_best_probs.pt")
        test_ref = load_probs(runs[0] / "test_probs.pt")
        # ---- 🔴 对齐断言：sample_ids 必须逐个相等 ----
        for d in runs[1:]:
            v = load_probs(d / "val_best_probs.pt")
            t = load_probs(d / "test_probs.pt")
            if v[2] != val_ref[2]:
                raise SystemExit(f"🔴 {d} 的 val sample_ids 与基准 run 不一致——"
                                 f"按行序平均会把不同合约混在一起，拒绝出数")
            if t[2] != test_ref[2]:
                raise SystemExit(f"🔴 {d} 的 test sample_ids 与基准 run 不一致——同上")
        val_p = [load_probs(d / "val_best_probs.pt")[0] for d in runs]
        test_p = [load_probs(d / "test_probs.pt")[0] for d in runs]
        y_val, y_test = val_ref[1], test_ref[1]

        singles = []
        for i, d in enumerate(runs):
            thr_i, _ = search_threshold(val_p[i], y_val)
            singles.append({
                "run": rel(d),
                "val_threshold": thr_i,
                "test_micro@0.5": round(metrics.micro_f1(y_test, test_p[i].ge(0.5).int()), 6),
                "test_micro@val_thr": round(metrics.micro_f1(y_test, test_p[i].ge(thr_i).int()), 6),
                "test_macro@val_thr": round(metrics.macro_f1(y_test, test_p[i].ge(thr_i).int()), 6),
            })
        avg_val = torch.stack(val_p).mean(dim=0)
        avg_test = torch.stack(test_p).mean(dim=0)
        thr_ens, val_micro_ens = search_threshold(avg_val, y_val)
        ens = {
            "val_threshold": thr_ens,
            "val_micro@val_thr": round(val_micro_ens, 6),
            "test_micro@0.5": round(metrics.micro_f1(y_test, avg_test.ge(0.5).int()), 6),
            "test_micro@val_thr": round(metrics.micro_f1(y_test, avg_test.ge(thr_ens).int()), 6),
            "test_macro@val_thr": round(metrics.macro_f1(y_test, avg_test.ge(thr_ens).int()), 6),
        }
        mean_micro = sum(s["test_micro@val_thr"] for s in singles) / len(singles)
        best_micro = max(s["test_micro@val_thr"] for s in singles)
        rec.update({
            "singles": singles,
            "mean_of_singles_micro@val_thr": round(mean_micro, 6),
            "best_of_singles_micro@val_thr": round(best_micro, 6),
            "ensemble": ens,
            "delta_vs_mean": round(ens["test_micro@val_thr"] - mean_micro, 6),
            "delta_vs_best": round(ens["test_micro@val_thr"] - best_micro, 6),
        })
        out["split_seeds"][f"ss{ss}"] = rec
    got = [v for v in out["split_seeds"].values() if "ensemble" in v]
    if got:
        out["mean_delta_vs_mean"] = round(
            sum(v["delta_vs_mean"] for v in got) / len(got), 6)
        out["mean_delta_vs_best"] = round(
            sum(v["delta_vs_best"] for v in got) / len(got), 6)
    return out


def render_md(res: dict) -> str:
    L = [f"# 同划分多种子概率集成：`{Path(res['group']).name}` / `{res['prefix']}`", "",
         "> 由 `scripts/ensemble_eval.py` 生成（零重训，只读既有 `val_best_probs.pt` / `test_probs.pt`）。",
         "> 阈值口径与单模型一致：**只在验证集上搜**，再套到 test。", "",
         "| 划分 | 单模型均值 | 单模型最好 | **集成** | Δ vs 均值 | Δ vs 最好 | 集成 val 阈值 |",
         "| --- | --- | --- | --- | --- | --- | --- |"]
    for k, v in res["split_seeds"].items():
        if "ensemble" not in v:
            L.append(f"| {k} | — | — | — | — | — | {v.get('skipped', '')} |")
            continue
        L.append(f"| {k} | {v['mean_of_singles_micro@val_thr']:.4f} | "
                 f"{v['best_of_singles_micro@val_thr']:.4f} | "
                 f"**{v['ensemble']['test_micro@val_thr']:.4f}** | "
                 f"{v['delta_vs_mean']:+.4f} | {v['delta_vs_best']:+.4f} | "
                 f"{v['ensemble']['val_threshold']} |")
    if "mean_delta_vs_mean" in res:
        L += ["", f"**平均 Δ vs 均值 = {res['mean_delta_vs_mean']:+.4f}**；"
                  f"平均 Δ vs 最好单模型 = {res['mean_delta_vs_best']:+.4f}。",
              "", "⚠ 对照基准是 `decisions.md` §36.4 实测的**重跑抖动 ≈0.012**；"
                  "Δ 小于它的一律不得称「有效」。", ""]
    return "\n".join(L)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", required=True, help="run 组目录，如 runs/cbft_study")
    ap.add_argument("--prefix", required=True, help="run 目录前缀，如 cbft / seed")
    ap.add_argument("--ts", type=int, nargs="*", default=[0, 1, 2], help="训练种子")
    ap.add_argument("--split-seeds", type=int, nargs="*", default=[0, 1, 2])
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    group = REPO / args.group
    res = evaluate_group(group, args.prefix, args.ts, args.split_seeds)
    out = Path(args.out) if args.out else OUT_ROOT / f"{group.name}_{args.prefix}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    md = out.with_suffix(".md")
    md.write_text(render_md(res), encoding="utf-8")
    for k, v in res["split_seeds"].items():
        if "ensemble" in v:
            print(f"[ensemble] {k}: 均值 {v['mean_of_singles_micro@val_thr']:.4f} → "
                  f"集成 {v['ensemble']['test_micro@val_thr']:.4f} "
                  f"({v['delta_vs_mean']:+.4f})")
        else:
            print(f"[ensemble] {k}: 跳过（{v.get('skipped')}）")
    print(f"→ {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
