#!/usr/bin/env python3
"""研究臂的**同配对**分析：逐配对算 Δ，再报 mean ± std 与配对 t。

**为什么必须同配对**（`decisions.md` §26.7/§27.5，两天内同类教训两次）：
噪声 ±0.05–0.07 量级的指标，**n=3 的表面模式不可信**。研究臂的叶目录命名为
`<配置>_ts<训练种子>_ss<划分种子>`，同一 `(ts, ss)` 就是同一对（同划分、同初始化），
**配对比较消掉划分与初始化的方差**，才看得见真实效应。

**指标从哪来**：`val_best_probs.pt`（该 run 最优 epoch 的**验证集**概率）+ 与训练同源的
标签/划分 + `thresholds.json` 的 `best_threshold`。全程**不需要权重、不需要重训**——
这也是 `decisions.md` §24.2 把这两个缓存纳入入库最小集的原因。

用法（从仓库根目录运行）：
  # 损失形状：loss_study 的三配置 vs 先验 dropout 研究里的 drop20 基线
  python scripts/paired_study_analysis.py --group runs/loss_study \
      --baseline-dir runs/prior_dropout_study --baseline-cfg drop20

  # 先验 dropout 剂量-反应：各剂量 vs drop20
  python scripts/paired_study_analysis.py --group runs/prior_dropout_study \
      --baseline-dir runs/prior_dropout_study --baseline-cfg drop20
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from sklearn.metrics import f1_score  # noqa: E402

import dataset  # noqa: E402

LEAF_RE = re.compile(r"^(?P<cfg>.+)_ts(?P<ts>\d+)_ss(?P<ss>\d+)$")


def leaf_runs(group: Path, cfg: str | None = None) -> dict[tuple[str, int, int], Path]:
    """{(配置名, ts, ss): run 目录}；run 目录 = `<leaf>/seed<ts>`。

    ⚠ 键**必须含配置名**：同一目录下不同配置共用同一批 `(ts, ss)` 配对，
    只用 `(ts, ss)` 作键会让后遍历的配置**覆盖**先前的（实测把 asl/focal 全吞掉）。
    """
    found: dict[tuple[str, int, int], Path] = {}
    for leaf in sorted(group.iterdir()):
        if not leaf.is_dir():
            continue
        m = LEAF_RE.match(leaf.name)
        if not m:
            continue
        name = m.group("cfg")
        if cfg is not None and name != cfg:
            continue
        run = leaf / f"seed{m.group('ts')}"
        if (run / "val_best_probs.pt").exists():
            found[(name, int(m.group("ts")), int(m.group("ss")))] = run
    return found


def _labels_for(run: Path) -> np.ndarray:
    """按该 run 的 `config.json` 取 val 标签（与训练同源：同一标签文件、同一键模式）。"""
    cfg = json.loads((run / "config.json").read_text(encoding="utf-8"))["args"]
    index, _ = dataset.build_index(cfg["graph_dir"], label_file=cfg["label_file"],
                                   key_mode=cfg["label_key_mode"])
    split = json.loads((Path(cfg["split_dir"]) / f"split_seed{cfg['split_seed']}.json")
                       .read_text(encoding="utf-8"))
    return np.array([index[b] for b in split["val"]])


def head_of(run: Path) -> str:
    """该 run 的输出头型（缺键 → `multi`，兼容引入 `--head` 之前的产物）。"""
    cfg = json.loads((run / "config.json").read_text(encoding="utf-8"))
    return (cfg.get("args", {}).get("head") or cfg.get("derived", {}).get("head") or "multi")


def val_metrics(run: Path) -> dict[str, float]:
    """该 run 的验证集指标（概率缓存 + 同源标签，无需权重）。

    **两族指标**（decisions §31）：
      - `val_binary_*`：**两条臂都算**——把七类塌成 `any(targets)` 后与二分类臂同口径。
        等价性靠 `max_c p_c >= t ⇔ any_c(p_c >= t)`（`metrics.contract_any_scores`），
        故两条臂在**同一阈值、同一规则**下可比，Δ 只归因于输出头。
      - `val_micro/macro/mAP`：**只对 `multi` 臂有意义**；二分类臂上置 `None`，
        打印为 `—`（**不是 0**——0 会被读成"指标很差"）。
    """
    probs = torch.load(run / "val_best_probs.pt", map_location="cpu")
    if isinstance(probs, dict):
        probs = probs["probs"]
    p = probs.numpy()
    y = _labels_for(run)                       # 恒 [N,7]（标签索引是事实来源）
    thr = json.loads((run / "thresholds.json").read_text(encoding="utf-8"))["best_threshold"]
    out: dict[str, float | None] = {}

    # ---- 二分类族（两臂共用；显式塌缩，绝不走 average="micro"——单列会退化成 accuracy，§28）----
    yb = metrics_().contract_any_labels(y)
    pb = metrics_().contract_any_scores(p)
    out["val_binary_ap"] = metrics_().binary_average_precision(pb, yb)["AP"]
    out["val_pos_rate"] = float(np.mean(yb))
    for tag, t in (("val_binary_f1@0.5", 0.5), ("val_binary_f1@val_thr", thr)):
        r = metrics_().binary_prf(yb, (pb >= t).astype(int))
        out[tag] = r["f1"] if r["f1"] is not None else 0.0
    r = metrics_().binary_prf(yb, (pb >= thr).astype(int))
    out["val_binary_fpr@val_thr"] = r["FPR"]
    out["val_binary_fnr@val_thr"] = r["FNR"]

    # ---- 多标签族（仅 multi 臂）----
    if head_of(run) == "multi":
        for tag, t in (("val_micro@0.5", 0.5), ("val_micro@val_thr", thr)):
            out[tag] = float(f1_score(y, (p >= t).astype(int), average="micro", zero_division=0))
        out["val_macro@0.5"] = float(f1_score(y, (p >= 0.5).astype(int),
                                              average="macro", zero_division=0))
        out["val_mAP"] = _val_map(p, y)
    else:
        # 二分类臂上这些量无定义。**不调用** f1_score —— [N,1] 会静默退化成 accuracy（§28）。
        out["val_micro@0.5"] = None
        out["val_micro@val_thr"] = None
        out["val_macro@0.5"] = None
        out["val_mAP"] = None
    out["thr"] = float(thr)
    return out


_METRICS_MOD = None


def metrics_():
    """延迟导入 `metrics`（避免与顶部的 sklearn 导入顺序纠缠）。"""
    global _METRICS_MOD
    if _METRICS_MOD is None:
        sys.path.insert(0, str(REPO / "scripts"))
        import metrics as _m  # noqa: E402
        _METRICS_MOD = _m
    return _METRICS_MOD


def _val_map(probs: np.ndarray, y: np.ndarray) -> float:
    """macro AP（仅 support>0 的类）—— 与 `metrics.mean_average_precision` 同口径。"""
    return float(metrics_().mean_average_precision(probs, y)["mAP"])


def paired_t(deltas: list[float]) -> float:
    """配对 t = mean / (std/√n)（ddof=1）；n<2 或 std=0 时返回 0。"""
    if len(deltas) < 2:
        return 0.0
    sd = statistics.stdev(deltas)
    if sd == 0:
        return 0.0
    return statistics.mean(deltas) / (sd / len(deltas) ** 0.5)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--group", required=True, help="研究臂目录（叶 = `<配置>_tsT_ssS`）。")
    p.add_argument("--baseline-dir", required=True, help="基线所在目录。")
    p.add_argument("--baseline-cfg", required=True, help="基线配置名（如 drop20）。")
    p.add_argument("--metrics", default="val_micro@0.5,val_mAP",
                   help="要报 Δ 的指标（逗号分隔）。多标签族（仅 multi 臂有值）：val_micro@0.5 / "
                        "val_micro@val_thr / val_macro@0.5 / val_mAP；"
                        "二分类族（**两臂都有值**，decisions §31）：val_binary_ap / "
                        "val_binary_f1@0.5 / val_binary_f1@val_thr / val_binary_fpr@val_thr / "
                        "val_binary_fnr@val_thr / val_pos_rate。")
    p.add_argument("--json-out", default="", help="把结果落盘为 JSON（便于贴进文档）。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    group = (REPO / args.group) if not Path(args.group).is_absolute() else Path(args.group)
    base_dir = (REPO / args.baseline_dir) if not Path(args.baseline_dir).is_absolute() \
        else Path(args.baseline_dir)

    baseline = leaf_runs(base_dir, args.baseline_cfg)
    arms = leaf_runs(group)
    metrics_wanted = [s.strip() for s in args.metrics.split(",") if s.strip()]
    if not baseline:
        raise SystemExit(f"[paired] 基线为空：{base_dir} 下没有 {args.baseline_cfg}_ts*_ss*")
    if not arms:
        raise SystemExit(f"[paired] 组为空：{group}")

    # 基线缓存（每个配对只算一次）；配对键统一为 (ts, ss)
    base_vals = {(ts, ss): val_metrics(run)
                 for (_cfg, ts, ss), run in baseline.items()}

    by_cfg: dict[str, list[tuple[str, int, int]]] = {}
    for key in arms:
        by_cfg.setdefault(key[0], []).append(key)

    print(f"基线 {args.baseline_cfg}（{len(baseline)} 个配对）← {base_dir}")
    print(f"组 {group}\n")
    header = "| 配置 | n | " + " | ".join(
        f"{m} | Δ({m}) | t" for m in metrics_wanted) + " |"
    print(header)
    print("| --- | --- | " + " | ".join(["---"] * (3 * len(metrics_wanted))) + " |")

    result: dict = {"baseline": {"dir": str(base_dir), "cfg": args.baseline_cfg,
                                 "n": len(baseline)}, "arms": {}}
    for cfg in sorted(by_cfg):
        full = by_cfg[cfg]
        keys = sorted(k for k in full if (k[1], k[2]) in base_vals)
        if not keys:
            print(f"| {cfg} | 0 | （无与基线共享的配对） |")
            continue
        cells = []
        entry: dict = {"n": len(keys), "pairings": [f"ts{t}_ss{s}" for _c, t, s in keys]}
        arm_vals = {k: val_metrics(arms[k]) for k in keys}      # 每配对只算一次
        for m in metrics_wanted:
            pairs_m = [(arm_vals[k].get(m), base_vals[(k[1], k[2])].get(m)) for k in keys]
            usable = [(a, b) for a, b in pairs_m if a is not None and b is not None]
            if not usable:
                # 该指标在此臂上无定义（如 multi 指标之于 binary 臂）→ 打 `—`，不崩、不假装 0
                cells.append("— | — | —")
                entry[m] = {"arm_mean": None, "delta_mean": None, "delta_std": None,
                            "t": None, "n": 0, "note": "该指标在此臂上无定义"}
                continue
            deltas = [a - b for a, b in usable]
            vals = [a for a, _ in usable]
            mean_d = statistics.mean(deltas)
            std_d = statistics.stdev(deltas) if len(deltas) > 1 else 0.0
            t = paired_t(deltas)
            cells.append(f"{statistics.mean(vals):.4f} | "
                         f"{mean_d:+.4f} ± {std_d:.4f} | {t:+.2f}")
            entry[m] = {"arm_mean": round(statistics.mean(vals), 6),
                        "delta_mean": round(mean_d, 6), "delta_std": round(std_d, 6),
                        "t": round(t, 3), "n": len(usable)}
        print(f"| **{cfg}** | {len(keys)} | " + " | ".join(cells) + " |")
        result["arms"][cfg] = entry

    print("\n> Δ = 该配置 − 基线，**同配对**（同划分、同训练种子）。t 为配对 t 统计量；"
          "|t|≳2.3（n=9，双尾 0.05）方可称显著。n=3 的表面模式不可信（§26.7/§27.5）。")
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(result, ensure_ascii=False, indent=2),
                                       encoding="utf-8")
        print(f"\n→ {args.json_out}")


if __name__ == "__main__":
    main()
