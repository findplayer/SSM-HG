#!/usr/bin/env python3
"""任务 2 管道：把被剔除的 `buggy_*` 补回池、重划 8:1:1，重微调编码器 → 重编码 → 重训 → 聚合。

**为什么写成脚本而不是手敲一串命令**：本流水线有 4 步、每步都有**硬前置**，
且每一步失败都会在下游表现为"结果不对"而不是"报错"。手敲正是本仓反复记录的失效模式
（`run_ablation.py` 开头那段：漏一个 `--split-dir` 就会静默拿另一套划分训练）。

**四个划分种子键必须处处一致**（`AGENTS.md` 语义锁死项）：
  `--split-dir products/alldata/splits/withbuggy_snapshot`（池 497）
  + `--graph-dir products/alldata/graphs_ft_buggy/cb_ft_ss{S}`（**路径含划分种子**）
  + `--split-seed S` + `--seed S`
否则 seed2 会拿 ss0 的编码器配 split_seed2——**不报错、只是结果无意义**。

🔴 **本臂相对正典变了两件事，不是一件**（论文里必须写清，否则是口径混淆）：
  1. **数据**：池 453 → 497（补回 44 个去重后的 `buggy_*`，其中绝大多数标签是七类全 1）；
  2. **划分**：8:1:1 重新划（test 从 46 → 49，**test 集换了** ⇒ 新旧数字**不可直接相减**）。
  （第 3 件：编码器 epoch 预算 5 → 16，见 `experiments/improvement_round1_results.md` §1。）

用法（从仓库根目录运行）：
  python scripts/run_buggy_canon.py --dry-run          # 只打印命令行
  python scripts/run_buggy_canon.py --steps variant    # 只造图变体
  python scripts/run_buggy_canon.py                    # 全部

产物：`products/alldata/graphs_ft_buggy/cb_ft_ss{S}/`、`runs/buggy_canon/seed{S}/`、
      `runs/buggy_canon/summary.json`
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

SPLIT_DIR = "products/alldata/splits/withbuggy_snapshot"
VARIANT_ROOT = "products/alldata/graphs_ft_buggy"
ENCODER_ROOT = "runs/codebert_ft_buggy"
RUNS_DIR = "runs/buggy_canon"
SEEDS = (0, 1, 2)
STEPS = ("variant", "train", "eval", "diagnose", "summarize")


def graph_dir_of(seed: int) -> str:
    return f"{VARIANT_ROOT}/cb_ft_ss{seed}"


def commands(seed: int, steps: tuple[str, ...]) -> list[tuple[str, list[str]]]:
    out: list[tuple[str, list[str]]] = []
    if "variant" in steps:
        out.append(("variant", [sys.executable, "scripts/build_graph_variant.py",
                                "--variant", "cb_ft", "--dataset", "alldata",
                                "--split-seed", str(seed),
                                "--encoder", f"{ENCODER_ROOT}/ss{seed}/encoder",
                                "--variants-root", VARIANT_ROOT]))
    if "train" in steps:
        out.append(("train", [sys.executable, "scripts/train.py",
                              "--seed", str(seed), "--split-seed", str(seed),
                              "--graph-dir", graph_dir_of(seed),
                              "--split-dir", SPLIT_DIR,
                              "--out-dir", RUNS_DIR]))
    if "eval" in steps:
        out.append(("eval", [sys.executable, "scripts/evaluate.py",
                             "--seed", str(seed),
                             "--graph-dir", graph_dir_of(seed),
                             "--split-dir", SPLIT_DIR,
                             "--runs-dir", RUNS_DIR]))
    # 🔴 **diagnose 不是可选项**：`test_probs.pt`（test 推理缓存）与 `diagnosis.json` 是
    #   `diagnose.py` 写的，**`evaluate.py` 不写**。三口径逐类表（`collect_three_caliber_tables.py`）、
    #   汇总卷（`collect_buggy_canon_summary.py`）、误报/漏报率（`error_rates.py`）
    #   **全都只读 `test_probs.pt`** ⇒ 少了这一步，下游不是报错而是**整列缺失**。
    #   （本仓既有惯例亦然：`run_ablation.py` / `run_study.py` 都是 train → evaluate → diagnose 三件套。）
    if "diagnose" in steps:
        out.append(("diagnose", [sys.executable, "scripts/diagnose.py",
                                 "--seed", str(seed),
                                 "--graph-dir", graph_dir_of(seed),
                                 "--split-dir", SPLIT_DIR,
                                 "--runs-dir", RUNS_DIR]))
    return out


def preflight() -> None:
    """开工前把"静默失效"的四条硬前置逐个查一遍，缺一条就停。"""
    problems: list[str] = []
    split_dir = REPO / SPLIT_DIR
    for s in SEEDS:
        if not (split_dir / f"split_seed{s}.json").exists():
            problems.append(f"缺划分 {SPLIT_DIR}/split_seed{s}.json")
        enc = REPO / ENCODER_ROOT / f"ss{s}" / "encoder" / "config.json"
        if not enc.exists():
            problems.append(f"缺编码器 {ENCODER_ROOT}/ss{s}/encoder（先跑微调队列）")
        else:
            marker = enc.parent / "corpus.json"
            if not marker.exists():
                problems.append(f"编码器 {ENCODER_ROOT}/ss{s} 缺 corpus.json 边车")
            else:
                corpus = json.loads(marker.read_text(encoding="utf-8")).get("corpus")
                if corpus != "alldata":
                    problems.append(f"编码器 {ENCODER_ROOT}/ss{s} 的语料是 {corpus!r}，应为 alldata")
    # 正典产物**只读**：本臂绝不写 runs/seed{0,1,2} 或 products/alldata/graphs_ft/
    if str(REPO / RUNS_DIR) in ("", str(REPO)):
        problems.append("RUNS_DIR 不能是仓库根")
    if problems:
        raise SystemExit("🔴 前置检查未通过：\n  - " + "\n  - ".join(problems))
    print("[preflight] ✓ 划分 3 份、编码器 3 套、语料归属 alldata —— 全部就位")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--steps", nargs="*", default=list(STEPS), choices=list(STEPS))
    ap.add_argument("--seeds", type=int, nargs="*", default=list(SEEDS))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-preflight", action="store_true",
                    help="仅在变体尚未构建时用（variant 步之后才需要编码器以外的检查）")
    args = ap.parse_args()

    steps = tuple(s for s in STEPS if s in args.steps)
    if args.dry_run:
        for seed in args.seeds:
            for name, cmd in commands(seed, steps):
                print(f"[{name} ss{seed}] " + " ".join(cmd))
        return 0

    if not args.skip_preflight:
        preflight()

    t0 = time.perf_counter()
    for seed in args.seeds:
        for name, cmd in commands(seed, steps):
            print(f"\n=== [{(time.perf_counter() - t0) / 60:.1f} min] ss{seed}/{name} ===",
                  flush=True)
            proc = subprocess.run(cmd, cwd=str(REPO))
            if proc.returncode != 0:
                raise SystemExit(f"🔴 ss{seed}/{name} 失败（exit {proc.returncode}）")

    if "summarize" in steps:
        print("\n=== summarize ===", flush=True)
        subprocess.run([sys.executable, "scripts/evaluate.py", "--summarize",
                        "--runs-dir", RUNS_DIR], cwd=str(REPO), check=True)
    print(f"\n完成，用时 {(time.perf_counter() - t0) / 60:.1f} min → {RUNS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
