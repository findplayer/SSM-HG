#!/usr/bin/env python3
"""按臂聚合 `runs/**/results.json` → 直接输出可粘贴的 Markdown 表格。

**为什么需要**：`report_data.md`（数据卷）声明自己"由 `runs/**/results.json` 直接聚合"，
但此前这些表是**手工汇总**的——口径一变（如 2026-09-17 的 micro-F1 修复，`decisions.md` §28）
就得逐格重抄，抄错无处可查。本脚本让该声明成立：表 = 产物，可随时重生成、可逐位对照。

**臂的识别规则**（`results.json` 的路径 → 臂名）：
  `runs/seed{0,1,2}/results.json`              → `main`（正典① 主库）
  `runs/<臂>/seed{0,1,2}/results.json`         → `<臂>`（正典② / 干预臂 / 例外臂）
  `runs/<组>/<配置>/seed{0,1,2}/results.json`  → `<组>/<配置>`（研究臂，同配对设计）

默认**排除**作废归档（`prior_*` 目录）。要含它们用 `--include-archive`——但请注意
归档内的 micro-F1 全部是坏口径值。

用法（从仓库根目录运行）：
  python scripts/aggregate_results.py                     # 全部三张表
  python scripts/aggregate_results.py --section overview
  python scripts/aggregate_results.py --arms main,augmentation --section perclass
  python scripts/aggregate_results.py --only-dirs runs/prior_badmetric --include-archive
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]

# 产物目录名（出现即视为归档，默认排除）
ARCHIVE_PREFIX = "prior_"


def arm_of(results_path: Path, root: Path) -> str:
    """`results.json` 路径 → 臂名（见模块 docstring 的识别规则）。"""
    rel = results_path.relative_to(root)
    parts = rel.parts[:-2]                       # 去掉 '<seed>/results.json'
    if not parts:                                # runs/seed0/results.json
        return "main"
    return "/".join(parts)


def collect(root: Path, include_archive: bool) -> dict[str, list[dict]]:
    """{臂名: [每个 seed 的 results.json 内容]}（按臂名、seed 排序）。"""
    arms: dict[str, list[dict]] = {}
    for path in sorted(root.rglob("results.json")):
        rel = path.relative_to(root)
        if not include_archive and any(p.startswith(ARCHIVE_PREFIX) for p in rel.parts):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        arms.setdefault(arm_of(path, root), []).append(data)
    for runs in arms.values():
        runs.sort(key=lambda d: d.get("seed", 0))
    return arms


def ms(values: list[float], digits: int = 4) -> str:
    """mean ± std（ddof=1；n=1 时不报 std，避免单点伪装成有波动）。"""
    vals = [v for v in values if v is not None]
    if not vals:
        return "—"
    if len(vals) == 1:
        return f"{vals[0]:.{digits}f}"
    return f"{statistics.mean(vals):.{digits}f} ± {statistics.stdev(vals):.{digits}f}"


def get(data: dict, *keys, default=None):
    """安全取嵌套键（缺键返回 default，而不是抛 KeyError）。"""
    cur = data
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


# --------------------------------------------------------------------- 表格
def table_overview(arms: dict[str, list[dict]]) -> str:
    out = ["| 臂 | n | micro-F1 @0.5 | micro-F1 @val_thr | macro-F1 @0.5 | macro-F1 @val_thr | mAP | 精确匹配 @0.5 | val_thr |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for arm, runs in arms.items():
        out.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            arm, len(runs),
            ms([get(r, "test", "fixed_0.5", "micro_f1") for r in runs]),
            ms([get(r, "test", "val_threshold", "micro_f1") for r in runs]),
            ms([get(r, "test", "fixed_0.5", "macro_f1") for r in runs]),
            ms([get(r, "test", "val_threshold", "macro_f1") for r in runs]),
            ms([get(r, "mAP", "mAP") for r in runs]),
            ms([get(r, "test", "fixed_0.5", "subset_accuracy") for r in runs], 3),
            "/".join(f"{get(r, 'val_threshold', default=float('nan')):.2f}" for r in runs),
        ))
    return "\n".join(out)


def head_of_run(data: dict) -> str:
    """该 results.json 的输出头型（缺键 → `multi`，兼容引入 `--head` 之前的产物）。

    只认 `head` 键；`select_metric` 仅作旧产物的兜底判据（**不能用 `or` 链**——
    `select_metric` 的取值本身就是真值字符串，会把兜底短路掉）。
    """
    head = data.get("head")
    if head in ("multi", "binary"):
        return head
    return "binary" if data.get("select_metric") == "val_binary_ap" else "multi"


def table_perclass(arms: dict[str, list[dict]], mode: str) -> str:
    """逐类 F1（mean±std）@ 指定工作点；support 一并给出（口径要求，见 decisions §13）。

    ⚠ **仅对 `multi` 臂有意义**：二分类臂的 `test.*` 里没有 `per_class` 键（键名一律 `binary_*`），
    硬迭代 7 列会 IndexError。故此处**先剔除二分类臂并明确告知**，不静默产出空表。
    """
    skipped = [arm for arm, runs in arms.items() if head_of_run(runs[0]) == "binary"]
    if skipped:
        print(f"> ⚠ 逐类表跳过二分类臂（无 per-class 指标，键名为 binary_*）：{skipped}\n")
    arms = {arm: runs for arm, runs in arms.items() if head_of_run(runs[0]) != "binary"}
    if not arms:
        return "（本次没有可出逐类表的臂）"
    out = [f"| 臂 | " + " | ".join(VULN_NAMES) + " |",
           "| --- | " + " | ".join(["---"] * len(VULN_NAMES)) + " |"]
    for arm, runs in arms.items():
        cols = []
        for i in range(len(VULN_NAMES)):
            cols.append(ms([get(r, "test", mode, "per_class", "f1", default=[None] * 7)[i]
                            if get(r, "test", mode, "per_class", "f1") else None
                            for r in runs], 3))
        out.append(f"| {arm} | " + " | ".join(cols) + " |")
    # support 行（各臂同划分则相同，取第一个有值的臂标注）
    sup_arms = [(arm, runs) for arm, runs in arms.items()
                if get(runs[0], "test", mode, "per_class", "support")]
    for arm, runs in sup_arms[:1]:
        sup = get(runs[0], "test", mode, "per_class", "support")
        out.append(f"| _{arm} support_ | " + " | ".join(str(s) for s in sup) + " |")
    return "\n".join(out)


def table_timing(arms: dict[str, list[dict]], root: Path) -> str:
    """训练计时与吞吐（读 `config.json::timing`，与 `results.json` 同目录）。"""
    out = ["| 臂 | wall (s) | 数据加载 (s) | 训练 (s) | epoch 数 | graphs/s |",
           "| --- | --- | --- | --- | --- | --- |"]
    for arm, runs in arms.items():
        walls, loads, trains, epochs, gps = [], [], [], [], []
        for r in runs:
            seed = r.get("seed", 0)
            cfg = _find_config(root, arm, seed)
            t = (cfg or {}).get("timing") or {}
            walls.append(t.get("run_wall_seconds"))
            loads.append(t.get("data_load_seconds"))
            trains.append(t.get("train_seconds"))
            epochs.append(t.get("epochs_completed"))
            gps.append(t.get("graphs_per_second"))
        out.append(f"| {arm} | {ms([v for v in walls if v is not None], 1)} | "
                   f"{ms([v for v in loads if v is not None], 1)} | "
                   f"{ms([v for v in trains if v is not None], 1)} | "
                   f"{ms([v for v in epochs if v is not None], 0)} | "
                   f"{ms([v for v in gps if v is not None], 0)} |")
    return "\n".join(out)


def _find_config(root: Path, arm: str, seed: int) -> dict | None:
    """按臂名找回该 seed 的 `config.json`（`main` 臂在 root 下，其余在 arm 子目录下）。"""
    base = root if arm == "main" else root / arm
    path = base / f"seed{seed}" / "config.json"
    if not path.exists():
        hits = sorted(base.glob(f"**/seed{seed}/config.json"))
        if not hits:
            return None
        path = hits[0]
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--only-dirs", default="runs",
                   help="扫描根目录（逗号分隔多个；默认 runs）。")
    p.add_argument("--arms", default="",
                   help="只输出这些臂（逗号分隔子串匹配；默认全部）。")
    p.add_argument("--section", default="all",
                   choices=["all", "overview", "perclass", "timing", "binary"])
    p.add_argument("--mode", default="val_threshold",
                   choices=["val_threshold", "fixed_0.5"], help="逐类表的工作点。")
    p.add_argument("--include-archive", action="store_true",
                   help="包含 prior_* 作废归档（其 micro-F1 为坏口径值，仅供对照）。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    arms: dict[str, list[dict]] = {}
    roots = []
    for d in args.only_dirs.split(","):
        root = Path(d.strip())
        if not root.is_absolute():
            root = (REPO / root).resolve()
        roots.append(root)
        for arm, runs in collect(root, args.include_archive).items():
            arms.setdefault(arm, []).extend(runs)
    if args.arms:
        needles = [s.strip() for s in args.arms.split(",") if s.strip()]
        arms = {a: r for a, r in arms.items() if any(n in a for n in needles)}
    if not arms:
        raise SystemExit("[aggregate] 没有找到 results.json")

    # 二分类臂**本来就没有** micro_f1（decisions §31），不得报成"未跑 evaluate.py"
    missing = [a for a, r in arms.items()
               if head_of_run(r[0]) != "binary"
               and get(r[0], "test", "fixed_0.5", "micro_f1") is None]
    if missing:
        print(f"> ⚠ 以下臂的 results.json 缺 micro_f1（未跑 evaluate.py？）：{missing}\n")
    binary_arms = [a for a, r in arms.items() if head_of_run(r[0]) == "binary"]
    if binary_arms and args.section in ("all", "binary"):
        print("### 二分类臂总览（head=binary；键名 binary_*）\n")
        print("| 臂 | n | F1 @0.5 | F1 @val_thr | P @val_thr | R @val_thr | FPR @val_thr | FNR @val_thr | AP | val_thr |")
        print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for arm in binary_arms:
            runs = arms[arm]
            print("| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                arm, len(runs),
                ms([get(r, "test", "fixed_0.5", "binary_f1") for r in runs], 3),
                ms([get(r, "test", "val_threshold", "binary_f1") for r in runs], 3),
                ms([get(r, "test", "val_threshold", "binary_precision") for r in runs], 3),
                ms([get(r, "test", "val_threshold", "binary_recall") for r in runs], 3),
                ms([get(r, "test", "val_threshold", "binary_FPR") for r in runs], 3),
                ms([get(r, "test", "val_threshold", "binary_FNR") for r in runs], 3),
                ms([get(r, "AP", "AP") for r in runs], 3),
                "/".join(f"{get(r, 'val_threshold', default=float('nan')):.2f}" for r in runs),
            ))
        print()

    root = roots[0]
    if args.section in ("all", "overview"):
        print("### 总览\n")
        print(table_overview(arms), "\n")
    if args.section in ("all", "perclass"):
        print(f"### 逐类 F1 @ {args.mode}\n")
        print(table_perclass(arms, args.mode), "\n")
        print("> support 为各臂该工作点下的测试集逐类正样本数；support≤2 的类仅描述性呈现"
              "（`decisions.md` §13）。\n")
    if args.section in ("all", "timing"):
        print("### 训练计时与吞吐\n")
        print(table_timing(arms, root), "\n")


if __name__ == "__main__":
    main()
