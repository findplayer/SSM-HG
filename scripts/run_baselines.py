#!/usr/bin/env python3
"""5.3 三条论文基线的跑批驱动：**离线建图 → 训练/评估**（子进程 + preflight + 断点续跑）。

链条（三条各自）：
    MVD-HG : `baseline_mvdhg_build.py`（外部仓库建图，与 seed **无关**）→ `baseline_mvdhg.py`
    EGFL   : `baseline_egfl_build.py`（solc --bin → 反汇编，与 seed **无关**）→ `baseline_egfl.py`
    MANDO  : 无离线步（直接吃正典 `graphs_ft/ss{S}`）→ `baseline_mando.py`

🔴 **不跑 `diagnose.py`**：三条基线自己写 `test_probs.pt`（那是 SSMHG 专属链路才需要的），
故链条只有两段。`diagnose` 缺席在这里**不会**造成整列 `—`。

用法（仓库根目录）：
    python scripts/run_baselines.py --dry-run
    python scripts/run_baselines.py --baselines egfl --seeds 0 --smoke
    python scripts/run_baselines.py --baselines egfl,mvdhg,mando --seeds 0,1,2
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402

SEEDS = (0, 1, 2)
# 名称 → (离线构建脚本, 训练脚本)；None = 无离线步
PIPELINE = {
    "mvdhg": ("scripts/baseline_mvdhg_build.py", "scripts/baseline_mvdhg.py"),
    "egfl": ("scripts/baseline_egfl_build.py", "scripts/baseline_egfl.py"),
    "mando": (None, "scripts/baseline_mando.py"),
}
LOG_DIR = REPO / "products/alldata/raw/logs"


def preflight(names: list[str], split_seed: int) -> None:
    """四条硬前置。任一不满足即退出——**不带着错误配置开跑**。"""
    split = B.load_split(REPO / "products/alldata/splits", split_seed)
    print(f"[preflight] 划分 OK：train {len(split['train'])} / val {len(split['val'])}"
          f" / test {len(split['test'])}")
    # ① out_dir 不得与正典 runs/seed{S} 相交
    for name in names:
        d = REPO / "eval_results/baseline" / name
        assert not str(d).startswith(str(REPO / "runs")), f"out_dir 落在正典区：{d}"
    # ② 正典图产物齐（三条基线都读它）
    gdir = REPO / f"products/alldata/graphs_ft/ss{split_seed}"
    n = len(list(gdir.glob("*_pyg.pt")))
    assert n >= 450, f"图产物不足：{gdir} 只有 {n} 个 _pyg.pt"
    print(f"[preflight] 图产物 OK：{gdir}（{n} 个 _pyg.pt）")
    # ③ 外部仓库 import 冒烟（MVD-HG 的 9 个模块必须在伪 argv 下 import 成功）
    if "mvdhg" in names:
        sys.path.insert(0, str(REPO / "scripts"))
        import baseline_mvdhg_build as MB
        m = MB._import_mvdhg(B.feature_root("mvdhg"), 40)
        assert m.config.create_corpus_mode != "create_corpus_txt", \
            "🔴 create_corpus_mode 不得是 create_corpus_txt（会清空输入 AST）"
        print("[preflight] MVD-HG 外部仓库 import OK（create_corpus_mode=generate_all）")
    # ④ 离线特征齐（已建过的才检查——首次跑时由 build 步负责产出）
    for name in names:
        root = B.feature_root(name)
        if (root / "feat").exists():
            got = len(list((root / "feat").glob("*.pt")))
            print(f"[preflight] {name} 离线特征：{got} 个 feat/*.pt（缺的会在 build 步补齐）")
        else:
            print(f"[preflight] {name} 离线特征：尚未建（{root / 'feat'}）")


def run_step(name: str, script: str, argv: list[str], log: Path, dry: bool) -> int:
    cmd = [sys.executable, script, *argv]
    print(f"\n=== [{name}] {script} {' '.join(argv)}", flush=True)
    if dry:
        print(f"    （dry-run）日志 → {log.relative_to(REPO)}")
        return 0
    log.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(f"\n===== {time.strftime('%F %T')} {' '.join(cmd)} =====\n")
        fh.flush()
        # 🔴 **必须显式传 `env=dict(os.environ)`，不能用默认的 `env=None`**（2026-09-22 实测）。
        # 本脚本 import 了 torch（经 `baseline_common`），torch 在 import 期会设
        # `KMP_INIT_AT_FORK=FALSE` / `KMP_DUPLICATE_LIB_OK=True`；此后若用默认继承方式 fork，
        # 子进程的 Intel OpenMP 初始化就崩，报的是
        # 「mkl-service + Intel(R) MKL: MKL_THREADING_LAYER=INTEL is incompatible with
        #  libgomp-….so.1」——**报错完全指向 MKL，与真正根因无关**，且
        # `torch` / `numpy` / 任何一条训练命令**手工跑都正常**，只有经本驱动跑才 rc=1。
        # 实测：`env=None` 连跑 5 次 rc 全 1；`env=dict(os.environ)` 连跑 5 次 rc 全 0。
        r = subprocess.run(cmd, cwd=str(REPO), stdout=fh, stderr=subprocess.STDOUT,
                           env=dict(os.environ))
    print(f"    rc={r.returncode}  {time.time() - t0:.0f}s → {log.relative_to(REPO)}", flush=True)
    return r.returncode


def main() -> int:
    ap = argparse.ArgumentParser(description="5.3 三基线跑批驱动")
    ap.add_argument("--baselines", default="mvdhg,egfl,mando")
    ap.add_argument("--seeds", default="0,1,2")
    ap.add_argument("--split-seed", type=int, default=None)
    ap.add_argument("--steps", default="build,train",
                    help="逗号分隔：build（离线）/ train（训练+评估）。")
    ap.add_argument("--build-args", default="", help="传给离线脚本的额外参数（空格分隔）。")
    ap.add_argument("--train-args", default="", help="传给训练脚本的额外参数（空格分隔）。")
    ap.add_argument("--smoke", action="store_true", help="冒烟：离线 --limit 8，训练 --smoke。")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only-missing", action="store_true",
                    help="已有 test_probs.pt 的 (基线, 种子) 跳过训练。")
    args = ap.parse_args()

    names = [n.strip() for n in args.baselines.split(",") if n.strip()]
    seeds = [int(s) for s in args.seeds.split(",") if s.strip()]
    steps = {s.strip() for s in args.steps.split(",") if s.strip()}
    for n in names:
        if n not in PIPELINE:
            raise SystemExit(f"未知基线 {n}；可选 {sorted(PIPELINE)}")
    split_seed = args.split_seed

    preflight(names, 0 if split_seed is None else split_seed)

    extra_build = args.build_args.split()
    extra_train = args.train_args.split()
    failures = []
    for name in names:
        build_script, train_script = PIPELINE[name]
        # ---- build（与 seed 无关，只跑一次）----
        if "build" in steps and build_script:
            argv = list(extra_build)
            if args.smoke:
                argv += ["--limit", "8"]
            rc = run_step(name, build_script, argv, LOG_DIR / f"baseline_{name}_build.log",
                          args.dry_run)
            if rc != 0:
                failures.append((name, "build", rc))
                continue
        # ---- train（逐种子）----
        if "train" in steps:
            for s in seeds:
                if args.only_missing and (REPO / "eval_results/baseline" / name /
                                          f"seed{s}" / "test_probs.pt").exists():
                    print(f"[{name}] seed{s} 已有产物，跳过（--only-missing）")
                    continue
                argv = ["--seed", str(s), *extra_train]
                if split_seed is not None:
                    argv += ["--split-seed", str(split_seed)]
                if args.smoke:
                    argv += ["--smoke"]
                rc = run_step(name, train_script, argv,
                              LOG_DIR / f"baseline_{name}_seed{s}.log", args.dry_run)
                if rc != 0:
                    failures.append((name, f"train seed{s}", rc))

    print("\n===== 汇总 =====")
    if failures:
        for f in failures:
            print(f"  ✗ {f[0]} / {f[1]}：rc={f[2]}")
        return 1
    print("  全部成功")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
