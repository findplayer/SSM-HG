#!/usr/bin/env python3
"""七类逐类 F1 汇总表（**纯聚合层**：不重实现任何指标，只搬运已落盘的产物）。

**存在理由**：论文要求「7 种漏洞各自的 F1 分数」在同一张表里可比。这些数字**早已存在**，
但散落在三类产物里、口径互不相同：

| 来源 | 产物 | 提供什么 |
|---|---|---|
| 主评估 | `runs/seed{S}/results.json` | 正典 RGCN 的 `test.{fixed_0.5,val_threshold}.per_class.f1` |
| 标定补充分析 | `eval_results/calibration{_aug}/seed{S}.json` | **per-class 阈值**（`calibrate.py` 在 val 上选出的） |
| 基线/消融臂 | `runs/baseline_gcn{,_aug}/`、`runs/ablation{_aug}/cb_frozen/` | 各对照臂的逐类 F1 |

🔴 **本脚本刻意不重算逐类 P/R/F1**——那是 `metrics.py` 的唯一职责；重复实现必然分叉
（本仓 §28 的教训：「同一语义两处实现」）。**唯一的计算**是「按 `calibrate.py` 已给出的
per-class 阈值把概率二值化」与「合约级 `any` 塌缩」，两者都用 `metrics` 的纯函数，
且 `--check` 会与 `calibrate.py` 自己报的逐类 F1 **逐位对拍**，不一致即拒绝落盘。

⚠ **每张表都必须把 support 与 F1 同列呈现**（`metrics.py` 模块契约）。主库测试集逐类 support
低到 **1**（`dos`/`front_running`），此时单类 F1 一次翻转就能差 0.67，
**任何跨配置的逐类 Δ 在这种 support 下都不可解读**——support 打在同一行就是为了让读者
第一眼看到这件事，而不是把 std 藏进附录。

用法（仓库根目录）：
    python scripts/collect_per_class_f1.py --check

产物：`eval_results/per_class_f1.json`（表格由本脚本打印到 stdout）。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch

import metrics

REPO = Path(__file__).resolve().parents[1]
NAMES = metrics.VULN_NAMES
SEEDS = (0, 1, 2)


# ------------------------------------------------------------------ 读取层
def _read_json(p: Path):
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def _load_probs(runs_rel: str, seed: int):
    """读 `test_probs.pt`；缺失返回 None（**不静默回退到更差的来源**）。"""
    p = REPO / runs_rel / f"seed{seed}" / "test_probs.pt"
    if not p.exists():
        return None
    b = torch.load(p, map_location="cpu")
    return {"probs": b["probs"].numpy(), "labels": b["labels"].numpy()}


def _val_thr(runs_rel: str, seed: int):
    d = _read_json(REPO / runs_rel / f"seed{seed}" / "thresholds.json")
    return None if d is None else d.get("best_threshold")


def _contract_f1(pred: np.ndarray, y: np.ndarray):
    """合约级二分类 F1（「有没有漏洞」）——**委托 `metrics.binary_prf`**，不走 sklearn 的 `average=`。

    与 `error_rates.contract_level_rates` 同源同式（`decisions.md` §30 的 L3 口径）。
    """
    bp = metrics.binary_prf(metrics.contract_any_labels(y),
                            metrics.contract_any_scores(pred) >= 1)
    return bp["f1"]


def _pred_at(blob: dict, thr: float) -> np.ndarray:
    return (blob["probs"] >= thr).astype(int)


# ------------------------------------------------------------------ 单个工作点
def row_from_results(runs_rel: str, wp: str) -> dict | None:
    """从 `results.json` 取逐类 F1（零重算）+ 从 `test_probs.pt` 复算合约级 F1。"""
    f1, sup, mic, mac, maps, contracts = [], [], [], [], [], []
    names = list(NAMES)
    for s in SEEDS:
        d = _read_json(REPO / runs_rel / f"seed{s}" / "results.json")
        if d is None:
            continue
        t = (d.get("test") or {}).get(wp)
        if not t:
            continue
        pc = t.get("per_class") or {}
        names = pc.get("names", names)
        f1.append(pc.get("f1"))
        sup.append(pc.get("support"))
        mic.append(t.get("micro_f1"))
        mac.append(t.get("macro_f1"))
        maps.append((d.get("mAP") or {}).get("mAP"))
        blob = _load_probs(runs_rel, s)
        thr = 0.5 if wp == "fixed_0.5" else _val_thr(runs_rel, s)
        contracts.append(_contract_f1(_pred_at(blob, thr), blob["labels"])
                         if blob is not None and thr is not None else None)
    if not f1:
        return None
    return {"names": names, "f1": f1, "support": sup,
            "micro_f1": mic, "macro_f1": mac, "mAP": maps, "contract_f1": contracts}


def row_from_per_class_thresholds(runs_rel: str, calib_rel: str) -> dict | None:
    """按 `calibrate.py` 在 **val** 上选出的 per-class 阈值应用于 test。

    ⚠ 阈值取自 `calibration/seed{S}.json`，**本脚本不重搜**——搜阈值是 `calibrate.py` 的职责，
    重搜会造出第二个「per-class 阈值」定义。本函数只做**应用**（`probs[:,c] >= t_c`）。
    """
    f1, sup, mic, mac, contracts, thrs = [], [], [], [], [], {}
    for s in SEEDS:
        cal = _read_json(REPO / calib_rel / f"seed{s}.json")
        blob = _load_probs(runs_rel, s)
        if cal is None or blob is None:
            continue
        th = cal["per_class_thresholds"]["raw"]["thresholds"]
        thrs[s] = th
        y, p = blob["labels"], blob["probs"]
        pred = np.stack([(p[:, c] >= th[n]).astype(int) for c, n in enumerate(NAMES)], axis=1)
        # 逐类 P/R/F1 **委托 metrics.per_class_prf**（唯一事实来源，本层不自行实现）
        prf = metrics.per_class_prf(y, pred, names=NAMES)
        f1.append([float(v) for v in prf["f1"]])
        sup.append(y.sum(axis=0).astype(int).tolist())
        mic.append(metrics.micro_f1(y, pred))
        mac.append(metrics.macro_f1(y, pred))
        contracts.append(_contract_f1(pred, y))
    if not f1:
        return None
    return {"names": list(NAMES), "f1": f1, "support": sup,
            "micro_f1": mic, "macro_f1": mac, "mAP": [None] * len(f1),
            "contract_f1": contracts, "thresholds": thrs}


# ------------------------------------------------------------------ 聚合
def _ms(vals, nd=6):
    v = [float(x) for x in vals if x is not None]
    if not v:
        return {"mean": None, "std": None, "n": 0}
    return {"mean": round(float(np.mean(v)), nd),
            "std": round(float(np.std(v, ddof=1)), nd) if len(v) > 1 else 0.0,
            "n": len(v)}


def entry(label: str, wp: str, raw: dict | None) -> dict | None:
    """一行 = 一个（配置 × 工作点），跨种子 mean±std。"""
    if raw is None:
        return None
    e = {"label": label, "workpoint": wp, "n_seeds": len(raw["f1"]),
         "per_class_f1": {n: _ms([r[i] for r in raw["f1"]]) for i, n in enumerate(NAMES)},
         "micro_f1": _ms(raw["micro_f1"]), "macro_f1": _ms(raw["macro_f1"]),
         "mAP": _ms(raw["mAP"]), "contract_f1": _ms(raw["contract_f1"])}
    ok = [s for s in raw["support"] if s is not None]
    e["support"] = ([float(np.mean([s[i] for s in ok])) for i in range(len(NAMES))]
                    if ok else None)
    if raw.get("thresholds"):
        e["per_class_thresholds"] = {
            n: {"mean": round(float(np.mean(v)), 4),
                "per_seed": v,
                "range": round(float(max(v) - min(v)), 4)}
            for n, v in ((n, [raw["thresholds"][s][n] for s in sorted(raw["thresholds"])])
                         for n in NAMES)}
    return e


CORPORA = (
    ("① alldata（池 453，多标签）", "runs", "eval_results/calibration",
     "runs/baseline_gcn", "runs/ablation/cb_frozen"),
    ("② augmentation（池 1774，单标签）", "runs/augmentation", "eval_results/calibration_aug",
     "runs/baseline_gcn_aug", "runs/ablation_aug/cb_frozen"),
)


def build() -> dict:
    out: dict[str, list] = {}
    for name, canon, calib, gcn, frozen in CORPORA:
        rows = []
        for label, rel, wp in (
            ("正典 RGCN（微调 CodeBERT）", canon, "val_threshold"),
            ("正典 RGCN（微调 CodeBERT）", canon, "fixed_0.5"),
            ("GCN 基线（关系盲）", gcn, "val_threshold"),
            ("GCN 基线（关系盲）", gcn, "fixed_0.5"),
            ("消融 cb_frozen（冻结 CodeBERT）", frozen, "val_threshold"),
            ("消融 cb_frozen（冻结 CodeBERT）", frozen, "fixed_0.5"),
        ):
            r = entry(label, "@val_thr" if wp == "val_threshold" else "@0.5",
                      row_from_results(rel, wp))
            if r:
                rows.append(r)
        r = entry("正典 RGCN + per-class 阈值（val 逐类选）", "@per-class",
                  row_from_per_class_thresholds(canon, calib))
        if r:
            rows.append(r)
        out[name] = rows
    return out


# ------------------------------------------------------------------ 打印与对拍
def fmt(ms, nd=4):
    if not ms or ms.get("mean") is None:
        return "—"
    return f"{ms['mean']:.{nd}f}±{ms['std']:.{nd}f}"


def print_md(all_rows: dict) -> None:
    for corpus, rows in all_rows.items():
        print(f"\n## {corpus}\n")
        print("| 配置 | 工作点 | " + " | ".join(NAMES) +
              " | micro-F1 | macro-F1 | mAP | 合约级 F1 |")
        print("|---|---|" + "---|" * (len(NAMES) + 4))
        for e in rows:
            print(f"| {e['label']} | {e['workpoint']} | "
                  + " | ".join(fmt(e["per_class_f1"][n]) for n in NAMES)
                  + f" | {fmt(e['micro_f1'])} | {fmt(e['macro_f1'])} | "
                    f"{fmt(e['mAP'])} | {fmt(e['contract_f1'])} |")
        sup = next((e["support"] for e in rows if e.get("support")), None)
        if sup:
            print(f"\n测试集逐类 support（3 种子均值）："
                  + "、".join(f"{n} {v:.1f}" for n, v in zip(NAMES, sup)))


def check_against_calibrate(all_rows: dict) -> list[str]:
    """对拍：本脚本按阈值复算的逐类 F1 ↔ `calibrate.py` 自己报的逐类 F1。

    两者若不一致，说明「应用阈值」这一步在某处被实现了两遍且已分叉——**必须响亮失败**。
    """
    bad: list[str] = []
    for (name, _, calib, _, _) in CORPORA:
        ref = _read_json(REPO / calib / "summary.json")
        if ref is None:
            bad.append(f"{calib}/summary.json 缺失")
            continue
        row = next((e for e in all_rows.get(name, []) if e["workpoint"] == "@per-class"), None)
        if row is None:
            bad.append(f"{name}: 未生成 @per-class 行")
            continue
        for n in NAMES:
            a = row["per_class_f1"][n]["mean"]
            b = ref["test_schemes"]["per_class_threshold"]["per_class_f1"][n]["mean"]
            if a is None or b is None:
                continue
            if abs(a - b) > 1e-6:
                bad.append(f"{name}/{n}: 复算 {a:.6f} != calibrate {b:.6f}")
        for key, a, b in (("micro", row["micro_f1"]["mean"],
                           ref["test_schemes"]["per_class_threshold"]["micro_f1"]["mean"]),
                          ("macro", row["macro_f1"]["mean"],
                           ref["test_schemes"]["per_class_threshold"]["macro_f1"]["mean"])):
            if a is not None and b is not None and abs(a - b) > 1e-6:
                bad.append(f"{name}/{key}: 复算 {a:.6f} != calibrate {b:.6f}")
    return bad


def main() -> None:
    ap = argparse.ArgumentParser(description="七类逐类 F1 汇总（纯聚合，零重算）")
    ap.add_argument("--out-dir", default=str(REPO / "eval_results"))
    ap.add_argument("--check", action="store_true",
                    help="与 calibrate.py 的 per-class F1 逐位对拍，不一致则不落盘")
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    all_rows = build()
    print_md(all_rows)

    if args.check:
        bad = check_against_calibrate(all_rows)
        print("\n[对拍] 本脚本复算 vs calibrate.py："
              + ("✅ 逐位一致" if not bad else "❌ " + "; ".join(bad)))
        if bad:
            raise SystemExit("[collect_per_class_f1] 对拍失败，拒绝落盘")

    if not args.no_write:
        out = Path(args.out_dir)
        out.mkdir(parents=True, exist_ok=True)
        (out / "per_class_f1.json").write_text(
            json.dumps({"note": "七类逐类 F1 汇总（纯聚合，零重算）；"
                                "support 必须与 F1 同看，主库逐类 support 低至 1。",
                        "rows": all_rows}, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"\n已落盘：{out / 'per_class_f1.json'}")


if __name__ == "__main__":
    main()
