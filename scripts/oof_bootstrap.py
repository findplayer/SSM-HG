#!/usr/bin/env python3
"""评测分辨率的两个补充口径（`improvement_proposals.md` §3 的 C2 / C3）。

**它们不涨点，作用是把「涨了多少才算涨」变成可判定的**。① 主库 test 只有 46 个合约、
21 个正标签对（正样本率 6.5%），单张合约翻转就能让 micro-F1 动 0.012–0.040
（`improvement_proposals.md` §0.2）。在这种分辨率上，报一个点估计而不报区间，
等于把一个测不出来的目标当成可优化的目标。

| 项 | 做什么 | 回答什么 |
| --- | --- | --- |
| **C2 bootstrap 置信区间** | 对 test **合约**做有放回重采样 B 次，每次重算 micro/macro-F1，取百分位区间 | 「0.78 vs 0.80 可分吗」 |
| **C3 加权 macro** | 按逐类 support 加权平均逐类 F1；另报剔除薄支撑类后的 macro | 「macro-F1 是不是被 support=1 的类绑架了」 |

🔴 **两条口径纪律**：
  1. **重采样单位是合约，不是标签对**。按标签对重采样会假装同一合约的 7 个标签互相独立，
     把区间**系统性做窄**——而同一合约的 7 类高度相关（这正是多标签的语义）。
  2. **阈值在每个重采样里保持不变**（用原 val 上搜出的那个），**不在重采样里重搜阈值**：
     重搜会让区间反映"阈值搜索的不稳定性"而不是"test 采样不确定性"，两件事混在一起。
     阈值搜索本身的过拟合风险由 `calibrate.py` 的 `overfit_audit` 单独报。

C1（池级 K 折 OOF）**不在本脚本**：它需要新划分 + 重训，属训练侧，见 `run_buggy_canon.py`
同族的做法；且 C1 与大纲 5.1 的固定 8:1:1 **冲突**，只能作补充口径并同步大纲。

用法（从仓库根目录运行）：
  python scripts/oof_bootstrap.py --runs-dir runs --out eval_results/bootstrap/main.json

产物：JSON + 同目录 markdown 摘要。
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

import metrics                                                    # noqa: E402

NAMES = list(metrics.VULN_NAMES)


def load(run_dir: Path, seed: int):
    """读 `test_probs.pt` 与阈值。**缺失返回 None**（不静默回退到更差来源）。"""
    p = run_dir / f"seed{seed}" / "test_probs.pt"
    t = run_dir / f"seed{seed}" / "thresholds.json"
    if not p.exists():
        return None
    b = torch.load(p, map_location="cpu")
    thr = json.loads(t.read_text(encoding="utf-8"))["best_threshold"] if t.exists() else 0.5
    return b["probs"].numpy(), b["labels"].numpy().astype(int), float(thr)


def f1_pair(y: np.ndarray, preds: np.ndarray) -> tuple[float, float]:
    """(micro, macro) —— **只调 `metrics`**，不另写实现。"""
    return metrics.micro_f1(y, preds), metrics.macro_f1(y, preds)


def bootstrap(y: np.ndarray, preds: np.ndarray, n_boot: int, seed: int,
              alpha: float = 0.05) -> dict:
    """合约级有放回重采样 → micro/macro-F1 的百分位区间。

    **合约级**：一次抽一个合约的整行（7 个标签一起走），保住类间相关性。
    """
    rng = np.random.default_rng(seed)
    n = y.shape[0]
    micros, macros = [], []
    for _ in range(n_boot):
        idx = rng.integers(0, n, size=n)
        m, M = f1_pair(y[idx], preds[idx])
        micros.append(m)
        macros.append(M)
    a = 100 * alpha / 2
    return {
        "n_boot": n_boot, "n_contracts": int(n),
        "micro": {"mean": float(np.mean(micros)),
                  "lo": float(np.percentile(micros, a)),
                  "hi": float(np.percentile(micros, 100 - a))},
        "macro": {"mean": float(np.mean(macros)),
                  "lo": float(np.percentile(macros, a)),
                  "hi": float(np.percentile(macros, 100 - a))},
    }


def weighted_macro(y: np.ndarray, preds: np.ndarray) -> dict:
    """C3：按逐类 support 加权的 macro-F1，以及剔除薄支撑类后的 macro。

    两者回答的是同一个质疑：「macro-F1 里有几个类 support 只有 1，它们的 F1 一次翻转就跳 0.67，
    是不是把整张表的 macro 绑架了？」——加权版让 support 大的类说话，剔除版干脆不看它们。
    """
    prf = metrics.per_class_prf(y, preds)
    f1 = np.array(prf["f1"], dtype=float)
    sup = np.array(prf["support"], dtype=float)
    # ⚠ 类的个数取**实际列数**，不写死 7：写死会在单元测试的小例上越界，
    #   也会让"将来改类别数"变成一处静默的错（本仓 §28/§29.4 同族教训）。
    names = list(prf["names"])
    total = sup.sum()
    weighted = float((f1 * sup).sum() / total) if total > 0 else None
    thin = sup <= 2                       # 大纲 5.1：support ≤ 2 的类"仅作描述性呈现"
    kept = ~thin & (sup > 0)
    return {
        "macro_unweighted": float(f1.mean()),
        "macro_support_weighted": weighted,
        "thin_classes": [names[i] for i in range(len(sup)) if thin[i]],
        "macro_excluding_thin": float(f1[kept].mean()) if kept.any() else None,
        "n_kept_classes": int(kept.sum()),
        "per_class_support": sup.astype(int).tolist(),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs-dir", default="runs")
    ap.add_argument("--seeds", type=int, nargs="*", default=[0, 1, 2])
    ap.add_argument("--n-boot", type=int, default=2000)
    ap.add_argument("--label", default=None, help="报告里显示的名字（默认取 --runs-dir）")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    run_dir = REPO / args.runs_dir
    label = args.label or args.runs_dir
    out = Path(args.out) if args.out else REPO / "eval_results" / "bootstrap" / "main.json"
    res: dict = {"runs_dir": args.runs_dir, "label": label, "n_boot": args.n_boot, "seeds": {}}
    for s in args.seeds:
        blob = load(run_dir, s)
        if blob is None:
            res["seeds"][f"seed{s}"] = {"skipped": "缺 test_probs.pt"}
            continue
        probs, y, thr = blob
        entry: dict = {"val_threshold": thr}
        for wp, t in (("fixed_0.5", 0.5), ("val_thr", thr)):
            preds = (probs >= t).astype(int)
            micro, macro = f1_pair(y, preds)
            entry[wp] = {"micro_f1": micro, "macro_f1": macro,
                         "bootstrap": bootstrap(y, preds, args.n_boot, seed=1000 + s),
                         "caliber_c3": weighted_macro(y, preds)}
        res["seeds"][f"seed{s}"] = entry

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")

    lines = [f"# bootstrap 置信区间 / 加权 macro：`{label}`", "",
             f"> 由 `scripts/oof_bootstrap.py` 生成（零重训，只读 `test_probs.pt`；"
             f"B={args.n_boot}，合约级有放回重采样，95% 百分位区间）。", "",
             "> 🔴 **重采样单位 = 合约**（不是标签对）——按标签对重采样会假装同一合约的 7 个标签"
             "互相独立，把区间**系统性做窄**。阈值在每个重采样里**保持不变**（用原 val 搜出的那个），"
             "不在重采样里重搜，否则区间会混入「阈值搜索的不稳定性」而不是「test 采样不确定性」。", "",
             "| 种子 | 工作点 | micro-F1 | 95% CI | macro-F1 | 95% CI | macro(加权) | macro(剔薄类) |",
             "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for s, e in res["seeds"].items():
        if "skipped" in e:
            lines.append(f"| {s} | — | — | — | — | — | — | — |")
            continue
        for wp, disp in (("fixed_0.5", "0.5"), ("val_thr", "验证集阈值")):
            w = e[wp]
            mic, mac = w["bootstrap"]["micro"], w["bootstrap"]["macro"]
            c3 = w["caliber_c3"]
            lines.append(
                f"| {s} | {disp} | {w['micro_f1']:.4f} | "
                f"[{mic['lo']:.4f}, {mic['hi']:.4f}] | {w['macro_f1']:.4f} | "
                f"[{mac['lo']:.4f}, {mac['hi']:.4f}] | "
                f"{c3['macro_support_weighted']:.4f} | {c3['macro_excluding_thin']:.4f} |")
    thin = next((e[wp]["caliber_c3"]["thin_classes"]
                 for e in res["seeds"].values() if "skipped" not in e
                 for wp in ("val_thr",)), [])
    lines += ["", f"> 薄支撑类（support ≤ 2，大纲 5.1 只作描述性呈现）：**{', '.join(thin) or '无'}**。", ""]
    md = out.with_suffix(".md")
    md.write_text("\n".join(lines), encoding="utf-8")

    for s, e in res["seeds"].items():
        if "skipped" in e:
            print(f"[boot] {s}: 跳过（{e['skipped']}）")
            continue
        b = e["val_thr"]["bootstrap"]["micro"]
        print(f"[boot] {s} @val_thr: micro {e['val_thr']['micro_f1']:.4f} "
              f"CI [{b['lo']:.4f}, {b['hi']:.4f}]（宽 {b['hi'] - b['lo']:.4f}）")
    print(f"→ {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
