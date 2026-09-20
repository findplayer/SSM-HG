#!/usr/bin/env python3
"""按 `config.json::args` **原样重放**一次实验（2026-09-17，指标口径修复后重训用）。

**为什么需要这个脚本**
`runs/` 下每个 run 都留有产出它的那次调用的全量参数（`train.py` 写的 `config.json::args`）。
指标层修复（`decisions.md` §28：`micro_f1` 与 `search_global_threshold` 的 `.ravel()` 使
sklearn 走 `binary` 分支、micro-F1 退化为 accuracy）**不改动任何 CLI 参数**，因此
`run_guard` 会判定「与产出该目录的那次是同一次实验」并**放行覆盖** —— 这正是它本该拦住的
场景。故重训前必须先把旧产物**移到归档目录**，再用本脚本从归档的 `config.json` 重建命令行：
以自述文件为唯一事实来源，避免手工抄 38 个参数时抄错，也保证「重放」与「原跑」逐参数相同。

**为什么不手工写循环**
臂间差异散落在 4~5 个键上（`loss` / `pos_weight_cap` / `graph_dir` / `split_dir` /
`label_file` / `label_key_mode`），8 个正典臂 × 3 种子 + 2 个研究臂 × 81 个配对，
手抄极易漏传 `--label-key-mode stem`（augmentation 语料必须）而静默跑出错误结果。

**权重剪除**
`last.pt` 只用于断点续训；重放的是 10~60 秒级的实验，续训无意义，剪掉可省一半体积。
`--prune {none,last,all}`：`all` 连 `best.pt` 一并删（研究臂沿用旧惯例：只留
`val_best_probs.pt` 供离线重算，不留权重）。

用法（从仓库根目录运行）：
  python scripts/rerun_from_config.py --archive-root runs/prior_badmetric --dry-run
  python scripts/rerun_from_config.py --archive-root runs/prior_badmetric --prune last
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TRAIN_PY = REPO / "scripts" / "train.py"
EVAL_PY = REPO / "scripts" / "evaluate.py"

# 重放时不传给命令行的键：`overwrite` 是控制流开关（归档后目标目录已空，无需覆盖授权），
# 其余键一律照传，任何新增参数都会自然进入 argv。
SKIP_KEYS = frozenset({"overwrite"})


def build_argv(args_map: dict, script: Path = TRAIN_PY) -> list[str]:
    """`config.json::args` → 命令行 argv（顺序固定按字典序，便于对照复现）。"""
    argv = [sys.executable, str(script)]
    for key in sorted(args_map):
        if key in SKIP_KEYS:
            continue
        value = args_map[key]
        flag = "--" + key.replace("_", "-")
        if isinstance(value, bool):
            if value:                       # store_true：False 即不传
                argv.append(flag)
        elif value is None:                 # 未指定 → 交给 argparse 默认值
            continue
        else:
            argv += [flag, str(value)]
    return argv


def find_configs(root: Path) -> list[Path]:
    """归档目录下全部 `config.json`（按路径排序 → 运行顺序稳定可复现）。"""
    return sorted(p for p in root.rglob("config.json")
                  if p.parent.name.startswith("seed"))


def run_dir_of(args_map: dict) -> Path:
    """与 `train.py` 同一条规则：`<out_dir>/seed<seed>`。"""
    return Path(args_map["out_dir"]) / f"seed{args_map['seed']}"


def prune_weights(run_dir: Path, mode: str) -> list[str]:
    """按 `mode` 剪除权重，返回被删的文件名。"""
    if mode == "none":
        return []
    names = ["last.pt"] if mode == "last" else ["last.pt", "best.pt"]
    removed: list[str] = []
    for name in names:
        target = run_dir / name
        if target.exists():
            target.unlink()
            removed.append(name)
    return removed


def build_eval_argv(args_map: dict) -> list[str]:
    """`config.json::args` → `evaluate.py` 的 argv。

    评估必须与训练**同源**：标签文件、键模式、图目录、划分目录全部照搬训练那次，
    否则会"用错标签评估对的权重"而得到看似合理的错误数字。
    """
    argv = [sys.executable, str(EVAL_PY),
            "--runs-dir", str(args_map["out_dir"]),
            "--seed", str(args_map["seed"]),
            "--graph-dir", str(args_map["graph_dir"]),
            "--split-dir", str(args_map["split_dir"])]
    for key in ("label_file", "label_key_mode"):
        if args_map.get(key):
            argv += ["--" + key.replace("_", "-"), str(args_map[key])]
    return argv


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--archive-root", required=True,
                   help="归档目录（内含各臂的 config.json，即重放的事实来源）。")
    p.add_argument("--only", default="",
                   help="只重放路径含该子串的 run（逗号分隔多选，用于分批/续跑）。")
    p.add_argument("--prune", choices=["none", "last", "all"], default="last",
                   help="成功后剪除权重：none=全留；last=删 last.pt（默认）；all=连 best.pt 也删。")
    p.add_argument("--evaluate", action="store_true",
                   help="训练后接着跑 evaluate.py（写 results.json + test_probs.pt）。"
                        "正典臂需要；研究臂只看 val，不需要。")
    p.add_argument("--evaluate-only", action="store_true",
                   help="跳过训练，只按 config.json 重建并执行 evaluate.py —— 评估参数"
                        "（graph_dir/split_dir/label_file/label_key_mode）与训练同源，避免手抄。")
    p.add_argument("--summarize", action="store_true",
                   help="每个臂评估完调用 `evaluate.py --summarize` 刷新该臂的 summary.json。"
                        "需与 --evaluate-only 同用（summary 是跨种子聚合，按 out_dir 去重后跑一次）。")
    p.add_argument("--dry-run", action="store_true", help="只打印计划，不执行。")
    p.add_argument("--keep-going", action="store_true", help="单个 run 失败后继续（默认立即停止）。")
    p.add_argument("--log", default="", help="总日志路径；省略则只打印到终端。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.archive_root)
    if not root.exists():
        raise SystemExit(f"[rerun] 归档目录不存在：{root}")
    configs = find_configs(root)
    if args.only:
        needles = [s.strip() for s in args.only.split(",") if s.strip()]
        configs = [c for c in configs if any(n in str(c) for n in needles)]
    if not configs:
        raise SystemExit("[rerun] 没有匹配的 config.json")

    print(f"[rerun] 归档 {root}：{len(configs)} 个 run；prune={args.prune} "
          f"evaluate={args.evaluate} dry_run={args.dry_run}", flush=True)
    started = time.perf_counter()
    failures: list[tuple[str, str]] = []
    out_dirs: set[str] = set()          # 已评估过的臂（out_dir），用于 --summarize 去重
    total = len(configs)

    for i, cfg_path in enumerate(configs, 1):
        record = json.loads(cfg_path.read_text(encoding="utf-8"))
        args_map = record.get("args") or {}
        if not args_map:
            failures.append((str(cfg_path), "config.json 缺 args"))
            continue
        run_dir = run_dir_of(args_map)
        tag = cfg_path.parent.relative_to(root)

        # ---- 仅评估模式：不训练，直接按 config 重建 evaluate.py 的命令 ----
        if args.evaluate_only:
            if args.dry_run:
                print(f"[{i}/{total}] {tag}\n    " + " ".join(build_eval_argv(args_map)[2:]),
                      flush=True)
                continue
            if not (run_dir / "best.pt").exists():
                failures.append((str(tag), f"{run_dir}/best.pt 不存在，无法评估"))
                print(f"[{i}/{total}] {tag} ✗ 缺 best.pt", flush=True)
                if not args.keep_going:
                    break
                continue
            ev = subprocess.run(build_eval_argv(args_map), cwd=REPO,
                                capture_output=True, text=True)
            if ev.returncode != 0:
                failures.append((str(tag) + " [evaluate]", (ev.stderr or ev.stdout)[-800:]))
                print(f"[{i}/{total}] {tag} ✗ evaluate 退出码 {ev.returncode}", flush=True)
                if not args.keep_going:
                    break
                continue
            out_dirs.add(str(args_map["out_dir"]))
            print(f"[{i}/{total}] {tag} ✓ 已评估", flush=True)
            continue

        argv = build_argv(args_map)
        if args.dry_run:
            shown = " ".join(argv[2:])
            print(f"[{i}/{total}] {tag}\n    → {run_dir}\n    {shown}", flush=True)
            continue
        if run_dir.exists() and (run_dir / "config.json").exists():
            print(f"[{i}/{total}] {tag} → 跳过：{run_dir} 已有 config.json（先归档再重放）",
                  flush=True)
            failures.append((str(tag), f"{run_dir} 已存在，拒绝覆盖"))
            continue

        t0 = time.perf_counter()
        proc = subprocess.run(argv, cwd=REPO, capture_output=True, text=True)
        wall = time.perf_counter() - t0
        if proc.returncode != 0:
            failures.append((str(tag), (proc.stderr or proc.stdout)[-800:]))
            print(f"[{i}/{total}] {tag} ✗ 退出码 {proc.returncode}（{wall:.1f}s）", flush=True)
            if not args.keep_going:
                break
            continue

        tail = ""
        if (run_dir / "log.txt").exists():
            lines = (run_dir / "log.txt").read_text(encoding="utf-8").strip().splitlines()
            if lines:
                row = json.loads(lines[-1])
                # 二分类臂（--head binary）的日志里 `val_micro_f1` 是 **None**（该量无定义），
                # 直接格式化会 TypeError；改用该臂真正的判据（val_binary_ap）。decisions §31
                if row.get("val_micro_f1") is None:
                    key = "val_binary_ap" if "val_binary_ap" in row else "val_micro_f1"
                else:
                    key = "val_micro_f1"
                val = row.get(key, float("nan"))
                tail = (f"{key}={'nan' if val is None else f'{val:.4f}'} "
                        f"epoch={row.get('epoch')}")

        if args.evaluate:
            ev = subprocess.run(build_eval_argv(args_map), cwd=REPO,
                                capture_output=True, text=True)
            if ev.returncode != 0:
                failures.append((str(tag) + " [evaluate]", (ev.stderr or ev.stdout)[-800:]))
                print(f"[{i}/{total}] {tag} ✗ evaluate 退出码 {ev.returncode}", flush=True)
                if not args.keep_going:
                    break
                continue
            out_dirs.add(str(args_map["out_dir"]))

        removed = prune_weights(run_dir, args.prune)
        note = f" 剪除 {','.join(removed)}" if removed else ""
        print(f"[{i}/{total}] {tag} ✓ {wall:5.1f}s {tail}{note}", flush=True)

    # ---- 收尾：每臂刷新一次 summary.json（跨种子聚合，按 out_dir 去重）----
    if args.summarize and not args.dry_run:
        for out_dir in sorted(out_dirs):
            sm = subprocess.run([sys.executable, str(EVAL_PY), "--runs-dir", out_dir,
                                 "--summarize"], cwd=REPO, capture_output=True, text=True)
            state = "✓" if sm.returncode == 0 else f"✗ 退出码 {sm.returncode}"
            print(f"[summarize] {out_dir} {state}", flush=True)
            if sm.returncode != 0:
                failures.append((f"summarize {out_dir}", (sm.stderr or sm.stdout)[-800:]))

    elapsed = time.perf_counter() - started
    n_done = 0 if args.dry_run else total - len(failures)
    summary = {"archive_root": str(root), "n_runs": total, "n_done": n_done,
               "elapsed_seconds": round(elapsed, 1),
               "failures": [{"tag": t, "error": e} for t, e in failures]}
    print(f"\n[rerun] 完成 {n_done}/{total}，用时 {elapsed:.1f}s", flush=True)
    for tag, err in failures:
        print(f"  ✗ {tag}: {err}", flush=True)
    if args.log:
        Path(args.log).write_text(json.dumps(summary, ensure_ascii=False, indent=2),
                                  encoding="utf-8")
    if failures and not args.dry_run:
        sys.exit(1)


if __name__ == "__main__":
    main()
