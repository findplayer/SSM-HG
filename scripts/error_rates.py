#!/usr/bin/env python3
"""M5 误报率 / 漏报率统计（只读产物 → 打印 markdown + 落盘 `runs/error_rates.json`）。

**定位**：补充分析层，不参与训练/阈值选择/模型选择，不改动任何主结果口径。目的只有一个——
把「准确率/F1 高不高」换成**运维语言**：*干净合约有多少被误标*、*真漏洞有多少被漏掉*。

**数据来源（全部已入库、零重训、零 GPU）**：`<runs>/<arm>/seed{N}/test_probs.pt`
（`probs`/`labels` 二维 `[N,7]` 缓存，`evaluate.py` 落盘）与同目录 `thresholds.json`。
⚠ **只读**：本脚本不写任何 run 目录，唯一落盘是聚合 JSON `runs/error_rates.json`。

**三层口径（多标签下「误报率」有三个互不相等的定义，必须分清、必须都给）**

| 层 | 问的是 | 定义 |
|---|---|---|
| L1 标签对级（micro） | 全部 `(合约, 类别)` 判定里错了多少 | `FPR=ΣFP/(ΣFP+ΣTN)`、`FNR=ΣFN/(ΣFN+ΣTP)` |
| L2 逐类 | 某一类判错了多少 | `FPR_c=FP_c/(FP_c+TN_c)`、`FNR_c=FN_c/(FN_c+TP_c)` |
| L3 合约级 | 一个合约整体判错了多少 | 误报合约率 = 「无漏洞却报出≥1类」占比；漏报合约率 = 「有漏洞却一类没报出」占比 |

⚠ **L1 ≠ L3，且方向相反**：模型只报出真漏洞里的一部分时，L1 的 FPR 可以很低（少报就少错），
而 L3 的**漏报合约率**会很高。安全工具的实际代价落在 **L3**，故 L3 与 L1 并列呈现。

⚠ **L1 的 FNR 与 micro-recall 互补**（`FNR = 1 − recall`），与 `metrics.micro_f1` 同源；
**L1 的 FPR 则不与任何已报指标互补**，是本次新增的信息。

用法：
    python scripts/error_rates.py                      # 全部有缓存的臂
    python scripts/error_rates.py --arms seed loss_focal
    python scripts/error_rates.py --no-write           # 只打印，不落盘
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch

import metrics   # 二分类四项的唯一事实来源（metrics.binary_prf；decisions §31）
from metrics import BINARY_NAME  # noqa: E402

BASE = Path("/home/saumarez/projects/deep-learning/SSM-HG")
VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]

# 默认统计的臂：正典①② + 干预臂 + 例外臂。**不含作废归档**（prior_badmetric / prior_dropout80）。
DEFAULT_ARMS = ["seed", "augmentation", "augmentation_dedup",
                "loss_focal", "loss_asl", "pw_unclamped", "neardup", "withbuggy"]
ARCHIVED_ARMS = ["prior_badmetric", "prior_dropout80", "prior_448pool"]


def _div(num: int, den: int):
    """安全除法：分母为 0 时返回 None（**不静默返回 0**——0 会被误读成「没有误报」）。"""
    return None if den == 0 else float(num) / float(den)


def confusion_per_class(y, p) -> dict:
    """逐类 (TP, FP, FN, TN)。`y`/`p` 为 `[N,7]` 的 0/1 数组。"""
    y_np = np.asarray(y).astype(int)
    p_np = np.asarray(p).astype(int)
    tp = (y_np * p_np).sum(axis=0)
    fp = ((1 - y_np) * p_np).sum(axis=0)
    fn = (y_np * (1 - p_np)).sum(axis=0)
    tn = ((1 - y_np) * (1 - p_np)).sum(axis=0)
    return {"TP": tp.tolist(), "FP": fp.tolist(), "FN": fn.tolist(), "TN": tn.tolist(),
            "support": (tp + fn).tolist(), "negatives": (fp + tn).tolist()}


def per_class_error_rates(y, p, names=None) -> dict:
    """L2 逐类 FPR / FNR（含 support 与负样本数，供判断该类的率是否可读）。

    `support=0`（该类无正样本）→ FNR 记 None；负样本为 0 → FPR 记 None。
    `names=None` 时**按输入列宽自适应**（7 列 → 七类名；1 列 → `vulnerable`）——
    二分类臂上仍按 `VULN_NAMES` 迭代会 IndexError（decisions §31）。
    """
    c = confusion_per_class(y, p)
    if names is None:
        names = list(VULN_NAMES) if len(c["TP"]) == len(VULN_NAMES) else [BINARY_NAME]
    fpr, fnr = [], []
    for i in range(len(names)):
        fpr.append(_div(c["FP"][i], c["FP"][i] + c["TN"][i]))
        fnr.append(_div(c["FN"][i], c["FN"][i] + c["TP"][i]))
    return {"names": list(names), "FPR": fpr, "FNR": fnr, **c}


def micro_error_rates(y, p) -> dict:
    """L1 标签对级（micro）FPR / FNR：把全部 `(合约, 类别)` 对汇总后统计。

    ⚠ 与逐类平均**不等价**：support 大的类在 micro 里权重更大（`uncheck` 主导主库）。
    """
    c = confusion_per_class(y, p)
    sFP, sTN, sFN, sTP = sum(c["FP"]), sum(c["TN"]), sum(c["FN"]), sum(c["TP"])
    return {"FPR": _div(sFP, sFP + sTN), "FNR": _div(sFN, sFN + sTP),
            "sum_FP": sFP, "sum_TN": sTN, "sum_FN": sFN, "sum_TP": sTP,
            "recall": _div(sTP, sTP + sFN), "precision": _div(sTP, sTP + sFP)}


def contract_level_rates(y, p) -> dict:
    """L3 合约级（安全工具的实际代价）：干净合约误报率、含漏洞合约漏报率。

    - **误报合约率** = 「真值全零 且 预测至少 1 类为正」/ 真值全零合约数（干净合约被误标的比例）。
    - **漏报合约率** = 「真值有正 但 预测全零」/ 真值有正合约数（**完全漏检**，一类都没报出）。
    - 另给 **全类覆盖率**（有漏洞合约的真值类被全部报出的比例）。

    📌 **本节同时就是「二分类视图」**：把 7 类预测与真值都塌成 `any(...)` 之后，本函数返回的
    `false_alarm_rate` / `miss_rate` **恰好等于二分类（"有没有漏洞"）的 FPR / FNR**，
    而 `binary_*` 四个字段是其配套的 P/R/F1/accuracy。**同一份输出，两种读法**——
    这正是「多分类 vs 二分类」在本任务上可直接对话的地方（`report_data.md` §2.3.1）。
    """
    y_np = np.asarray(y).astype(int)
    p_np = np.asarray(p).astype(int)
    y_any, p_any = y_np.any(axis=1), p_np.any(axis=1)
    n_clean, n_vuln = int((~y_any).sum()), int(y_any.sum())
    false_alarm = int((~y_any & p_any).sum())          # 干净合约被报出
    missed = int((y_any & ~p_any).sum())               # 有漏洞合约一类都没报出

    # 逐合约「真值类是否被全覆盖」（只在有漏洞的合约上算）
    covered_vuln = int(((y_np & ~p_np)[y_any].sum(axis=1) == 0).sum()) if n_vuln else 0
    # 二分类四项**委托给 metrics 单一事实来源**（`decisions.md` §31）：两处各自实现
    # "二分类 F1" 必然在退化约定上分叉（`None` vs `0.0`），正是 §28 那类静默分歧的温床。
    bp = metrics.binary_prf(y_any, p_any)
    return {
        "n_contracts": int(y_np.shape[0]),
        "n_clean": n_clean, "n_vuln": n_vuln,
        "false_alarm_contracts": false_alarm,
        "missed_contracts": missed,
        "false_alarm_rate": _div(false_alarm, n_clean),   # L3 误报率 = 二分类 FPR
        "miss_rate": _div(missed, n_vuln),                # L3 漏报率 = 二分类 FNR
        "vuln_partially_covered": n_vuln - covered_vuln,
        "full_cover_rate_on_vuln": _div(covered_vuln, n_vuln),
        "binary_precision": bp["precision"], "binary_recall": bp["recall"],
        "binary_f1": bp["f1"] if bp["f1"] is not None else 0.0,
        "binary_accuracy": bp["accuracy"],
    }


def summarize(y, p) -> dict:
    """三层口径一次算齐。"""
    return {"L1_micro": micro_error_rates(y, p),
            "L2_per_class": per_class_error_rates(y, p),
            "L3_contract": contract_level_rates(y, p)}


def seed_dir(runs_dir: Path, arm: str, seed: int) -> Path | None:
    """定位单个 run 目录——本仓存在**两种布局**，都要认：

    - 扁平（正典①）：`runs/seed0/`、`runs/seed1/`…（`--out-dir runs/seed{N}`）
    - 嵌套（其余全部臂）：`runs/<arm>/seed0/`…
    """
    for cand in (runs_dir / arm / f"seed{seed}", runs_dir / f"{arm}{seed}"):
        if (cand / "test_probs.pt").exists():
            return cand
    return None


def load_cache(runs_dir: Path, arm: str, seed: int):
    """读 run 目录下的 `test_probs.pt` 与 `thresholds.json`；缺失返回 (None, None)。"""
    d = seed_dir(runs_dir, arm, seed)
    if d is None:
        return None, None
    probs_f, thr_f = d / "test_probs.pt", d / "thresholds.json"
    blob = torch.load(probs_f, map_location="cpu")
    thr = None
    if thr_f.exists():
        thr = json.loads(thr_f.read_text()).get("best_threshold")
    return {"probs": blob["probs"].numpy(), "labels": blob["labels"].numpy(),
            "n": int(blob["probs"].shape[0])}, thr


def evaluate_arm(runs_dir: Path, arm: str, seeds=(0, 1, 2)) -> dict:
    """对一条臂的全部种子算三层口径（@0.5 与 @val_thr 双工作点），返回逐种子明细。"""
    per_seed = []
    for s in seeds:
        cache, thr = load_cache(runs_dir, arm, s)
        if cache is None:
            continue
        y = cache["labels"]
        entry = {"seed": s, "n_test": cache["n"], "val_threshold": thr}
        for tag, t in (("fixed_0.5", 0.5), ("val_thr", thr)):
            if t is None:
                continue
            entry[tag] = summarize(y, (cache["probs"] >= t).astype(int))
        per_seed.append(entry)
    return {"arm": arm, "n_seeds": len(per_seed), "seeds": per_seed}


def _mean_std(values):
    """None 感知的 mean±std（ddof=1）；全 None 返回 (None, None)。"""
    vs = [v for v in values if v is not None]
    if not vs:
        return None, None
    if len(vs) == 1:
        return float(vs[0]), 0.0
    return float(np.mean(vs)), float(np.std(vs, ddof=1))


def aggregate(arm_result: dict, tag: str) -> dict:
    """跨种子聚合（mean±std）到 L1 / L3 与逐类。"""
    out = {"L1_micro": {}, "L3_contract": {}, "L2_per_class": {}}
    for key in ("FPR", "FNR", "recall", "precision"):
        m, s = _mean_std([e[tag]["L1_micro"][key] for e in arm_result["seeds"] if tag in e])
        out["L1_micro"][key] = [m, s]
    for key in ("false_alarm_rate", "miss_rate", "full_cover_rate_on_vuln",
                "binary_precision", "binary_recall", "binary_f1", "binary_accuracy"):
        m, s = _mean_std([e[tag]["L3_contract"][key] for e in arm_result["seeds"] if tag in e])
        out["L3_contract"][key] = [m, s]
    for key in ("false_alarm_contracts", "missed_contracts", "n_clean", "n_vuln"):
        vals = [e[tag]["L3_contract"][key] for e in arm_result["seeds"] if tag in e]
        out["L3_contract"][key] = [float(np.mean(vals)) if vals else None,
                                   float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0]
    # 列数**由产物决定**：七类臂 7 列、二分类臂 1 列（按 VULN_NAMES 硬迭代会 IndexError）
    first = next((e[tag]["L2_per_class"] for e in arm_result["seeds"] if tag in e), None)
    n_cls = len(first["names"]) if first else 0
    for key in ("FPR", "FNR"):
        rows = []
        for ci in range(n_cls):
            m, s = _mean_std([e[tag]["L2_per_class"][key][ci]
                              for e in arm_result["seeds"] if tag in e])
            rows.append([m, s])
        out["L2_per_class"][key] = rows
    supports = [e[tag]["L2_per_class"]["support"] for e in arm_result["seeds"] if tag in e]
    out["L2_per_class"]["support"] = [float(np.mean([r[ci] for r in supports]))
                                      for ci in range(n_cls)] if supports else []
    out["L2_per_class"]["names"] = list(first["names"]) if first else []
    return out


def _fmt(v, nd=3):
    """(mean, std) → `0.123 ± 0.045`；None → `—`。"""
    if v is None or v[0] is None:
        return "—"
    return f"{v[0]:.{nd}f} ± {v[1]:.{nd}f}"


def print_markdown(all_results: dict, skipped: list[str]) -> None:
    """打印三张 markdown 表（L3 合约级 / L1 标签对级 / L2 逐类 FPR-FNR）。"""
    print("\n### L3 合约级 = 二分类视图（安全工具的实际代价；FPR/FNR 即「有没有漏洞」的误报/漏报率）\n")
    print("| 臂 | 工作点 | 误报率 FPR | 漏报率 FNR | 二分类 F1 | 二分类 P | 二分类 R | 误报数/干净数 | 漏报数/有漏洞数 |")
    print("|---|---|---|---|---|---|---|---|---|")
    for arm, r in all_results.items():
        for tag, label in (("fixed_0.5", "@0.5"), ("val_thr", "@val_thr")):
            a = aggregate(r, tag)["L3_contract"]
            if not a.get("false_alarm_rate"):
                continue
            print(f"| {arm} | {label} | {_fmt(a['false_alarm_rate'])} | {_fmt(a['miss_rate'])} | "
                  f"{_fmt(a['binary_f1'])} | {_fmt(a['binary_precision'])} | {_fmt(a['binary_recall'])} | "
                  f"{a['false_alarm_contracts'][0]:.1f}/{a['n_clean'][0]:.0f} | "
                  f"{a['missed_contracts'][0]:.1f}/{a['n_vuln'][0]:.0f} |")

    print("\n### L1 标签对级（micro，全部 (合约, 类别) 对汇总）\n")
    print("| 臂 | 工作点 | FPR（误报率） | FNR（漏报率） | micro-P | micro-R |")
    print("|---|---|---|---|---|---|")
    for arm, r in all_results.items():
        for tag, label in (("fixed_0.5", "@0.5"), ("val_thr", "@val_thr")):
            a = aggregate(r, tag)["L1_micro"]
            if a["FPR"][0] is None:
                continue
            print(f"| {arm} | {label} | {_fmt(a['FPR'])} | {_fmt(a['FNR'])} | "
                  f"{_fmt(a['precision'])} | {_fmt(a['recall'])} |")

    print("\n### L2 逐类 FPR / FNR（@val_thr）\n")
    print("| 类别 | " + " | ".join(f"{a} FPR | {a} FNR" for a in all_results) + " |")
    print("|---" * (1 + 2 * len(all_results)) + "|")
    # 行数按**最宽**的臂取；窄臂（二分类，仅 1 列）其余行留 `—` —— 列数不同的两条臂不能强行对齐。
    # 行名取**拥有该列的那些臂**的实际类名，不硬套 VULN_NAMES（否则二分类的唯一一行会被叫成
    # `access_control`，而它其实是 `vulnerable`）。
    aggs = {arm: aggregate(r, "val_thr")["L2_per_class"] for arm, r in all_results.items()}
    n_rows = max((len(a.get("names") or []) for a in aggs.values()), default=0)
    for ci in range(n_rows):
        cells = []
        for arm, a in aggs.items():
            names = a.get("names") or []
            if ci >= len(names):
                cells += ["—", "—"]
                continue
            cells.append(_fmt(a["FPR"][ci]) if a["FPR"] else "—")
            cells.append(_fmt(a["FNR"][ci]) if a["FNR"] else "—")
        row_name = next((a["names"][ci] for a in aggs.values() if ci < len(a.get("names") or [])),
                        f"class{ci}")
        print(f"| {row_name} | " + " | ".join(cells) + " |")

    if skipped:
        print(f"\n⚠ 无 `test_probs.pt` 缓存、**未统计**的臂：{', '.join(skipped)}")
        print("  （`evaluate.py` 会落盘该缓存；如需补齐，重跑对应臂的 evaluate 即可，分钟级、无需重训。）")


def main() -> None:
    ap = argparse.ArgumentParser(description="M5 误报率/漏报率统计（只读产物）")
    ap.add_argument("--runs-dir", default=str(BASE / "runs"))
    ap.add_argument("--arms", nargs="*", default=DEFAULT_ARMS)
    ap.add_argument("--seeds", nargs="*", type=int, default=[0, 1, 2])
    ap.add_argument("--out", default=str(BASE / "runs" / "error_rates.json"))
    ap.add_argument("--no-write", action="store_true", help="只打印，不落盘")
    args = ap.parse_args()

    runs_dir = Path(args.runs_dir)
    all_results, skipped = {}, []
    for arm in args.arms:
        if arm in ARCHIVED_ARMS:
            print(f"⚠ 跳过作废归档臂 `{arm}`（口径已作废，不得引用）。")
            continue
        r = evaluate_arm(runs_dir, arm, tuple(args.seeds))
        if r["n_seeds"] == 0:
            skipped.append(arm)
            continue
        all_results[arm] = r

    print_markdown(all_results, skipped)

    if not args.no_write:
        payload = {
            "note": "M5 误报率/漏报率（补充分析，不进主结果口径）；来源 = <runs>/<arm>/seed*/test_probs.pt",
            "arms": {a: {"n_seeds": r["n_seeds"], "seeds": r["seeds"]} for a, r in all_results.items()},
            "skipped_no_cache": skipped,
        }
        Path(args.out).write_text(json.dumps(payload, ensure_ascii=False, indent=1))
        print(f"\n已落盘：{args.out}")


if __name__ == "__main__":
    main()
