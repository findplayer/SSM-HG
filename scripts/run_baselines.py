#!/usr/bin/env python3
"""5.3 三条论文基线的跑批驱动：**离线建图 → 训练/评估**（子进程 + preflight + 断点续跑）。

链条（每条各自）：
    MVD-HG : `baseline_mvdhg_build.py`（外部仓库建图，与 seed **无关**）→ `baseline_mvdhg.py`
    EGFL   : `baseline_egfl_build.py`（solc --bin → 反汇编，与 seed **无关**）→ `baseline_egfl.py`
    MANDO  : 无离线步（直接吃正典图）→ `baseline_mando.py`

🔴 **不跑 `diagnose.py`**：三条基线自己写 `test_probs.pt`（那是 SSMHG 专属链路才需要的），
故链条只有两段。`diagnose` 缺席在这里**不会**造成整列 `—`。

🔴 **正典由 `--layout` 决定，四条路径一起换**（`baseline_common.LAYOUTS` 是唯一真源）：
    canon37 → 池 453（`graphs_ft/ss{S}` + `splits/`），默认，产物 `eval_results/baseline/<name>/`
    buggy   → 池 497（`graphs_ft_buggy/cb_ft_ss{S}` + `splits/withbuggy_snapshot/`），
              产物 `eval_results/baseline/<name>_buggy/`
布局知识**只放在这里**与 `LAYOUTS`，每个子进程都拿到**显式**的四条路径（不靠默认值），
且子进程内部还会用 `baseline_common.check_layout()` 再复核一次「四者同正典」。

⚠ **两段正典的特征约定不同，是有意的、且必须随结果披露**：
`canon37` 的三条基线**三种子用的都是 `graphs_ft/ss0`**（历史事实，已在库的产物如此），
而 `buggy` 段用与 `--split-seed` **配对的** `cb_ft_ss{S}`（与 `runs/buggy_canon/seed{S}` 同款）。
原因是 `_cb.pt` 的 CodeBERT 节点行**逐张量随 `ss` 变**（实测 ss0/ss1/ss2 全不同），
故「配对」才是本仓 `AGENTS.md` 语义锁死项要求的写法。两段各自内部可比，**跨段不可比**。

用法（仓库根目录）：
    python scripts/run_baselines.py --dry-run
    python scripts/run_baselines.py --layout buggy --dry-run
    python scripts/run_baselines.py --baselines egfl --seeds 0 --smoke
    python scripts/run_baselines.py --layout buggy --baselines mvdhg,egfl --seeds 0,1,2
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
# 名字 → (离线构建脚本|None, 训练脚本, 该臂的**正典训练参数**)
#
# 🔴 训练参数逐臂**写死在这里**，不再靠 `--train-args` 手敲。原先那套参数只存在于
#    `products/alldata/raw/logs/baseline_{chain,regen}.log` 的日志行里，换正典时极易漏抄
#    或抄错（而抄错**不会报错**——只会让「某基线更弱」变成训练配置削的，正是 §46.3 决议 5 要防的）。
#    `--early-stop-patience 20` 对三臂一致（正典是 5，见 §46.3 决议 5）；
#    batch 形态因显存/耗时逐臂不同（EGFL 的 seq_len 下整批反代会 OOM；MANDO 的 HGT
#    每步开销与样本数几乎无关，累积形式反而慢 3.3 倍）——理由逐条见该表的 §0 第 3 条。
PIPELINE = {
    "mvdhg": ("scripts/baseline_mvdhg_build.py", "scripts/baseline_mvdhg.py",
              ["--early-stop-patience", "20", "--batch-size", "4", "--accum-steps", "8"]),
    "egfl": ("scripts/baseline_egfl_build.py", "scripts/baseline_egfl.py",
             ["--early-stop-patience", "20", "--batch-size", "4", "--accum-steps", "8"]),
    # 敏感性臂：同一份离线特征、同一结构，**唯一变量 = lr**（1e-4 → 2e-3，EGFL 论文的默认值）。
    # ⚠ 它不在 `--baselines` 默认值里（默认仍是三条），但**必须在 PIPELINE 里**：
    # 否则它只能手敲，而手敲的那次就没有人替它管 `--feature-suffix`/`--out-dir`
    # ⇒ 会把 497 池的 lr 臂写进正典的 `egfl_ownlr/`。
    "egfl_ownlr": (None, "scripts/baseline_egfl.py",
                   ["--early-stop-patience", "20", "--batch-size", "4", "--accum-steps", "8",
                    "--lr", "0.002"]),
    "mando": (None, "scripts/baseline_mando.py",
              ["--early-stop-patience", "20", "--batch-size", "32", "--accum-steps", "1"]),
}
DEFAULT_BASELINES = "mvdhg,egfl,mando"


def log_dir(layout: str) -> Path:
    """日志根。🔴 **按 layout 分目录**——否则 buggy 的命令行会追加进 canon 的日志文件里
    （`run_step` 用 `"a"` 追加），把"某产物是哪次跑出来的"这条唯一线索污染掉。"""
    base = REPO / "products/alldata/raw/logs"
    return base if layout == B.DEFAULT_LAYOUT else base / f"baseline_{layout}"


def preflight(names: list[str], layout: str, seeds: list[int]) -> dict:
    """硬前置。任一不满足即退出——**不带着错误配置开跑**。"""
    L = B.LAYOUTS[layout]
    # ① 划分：**逐种子**核对（原先只查一个 split_seed，seed1/2 缺图也照样通过）
    for s in seeds:
        split = B.load_split(REPO / L["split_dir"], s)
        print(f"[preflight] 划分 OK（layout={layout} ss{s}）：train {len(split['train'])}"
              f" / val {len(split['val'])} / test {len(split['test'])}")
    # ② 图产物：**逐种子**核对该种子的图目录
    for s in seeds:
        gdir = REPO / L["graph_dir"].format(S=s)
        n = len(list(gdir.glob("*_pyg.pt"))) if gdir.exists() else 0
        assert n >= L["n_pyg_min"], (
            f"图产物不足：{gdir} 只有 {n} 个 _pyg.pt（{layout} 要求 ≥{L['n_pyg_min']}）。"
            f"⚠ buggy 布局的文件名是 `cb_ft_ss{{S}}`，不是 `ss{{S}}`——别把 canon37 的路径套上来")
        print(f"[preflight] 图产物 OK（ss{s}）：{gdir}（{n} 个 _pyg.pt）")
    # ③ 产物目录不得落在正典 `runs/`
    for name in names:
        d = REPO / L["out_dir"].format(name=name)
        assert not str(d.resolve()).startswith(str(REPO / "runs")), f"out_dir 落在正典区：{d}"
    print(f"[preflight] 产物根 OK：{REPO / L['out_dir'].format(name='<name>')}")
    # ④ 外部仓库 import 冒烟（MVD-HG 的 9 个模块必须在伪 argv 下 import 成功）
    if "mvdhg" in names:
        import baseline_mvdhg_build as MB
        m = MB._import_mvdhg(B.feature_root("mvdhg", L["feature_suffix"]), 40)
        assert m.config.create_corpus_mode != "create_corpus_txt", \
            "🔴 create_corpus_mode 不得是 create_corpus_txt（会清空输入 AST）"
        print("[preflight] MVD-HG 外部仓库 import OK（create_corpus_mode=generate_all）")
    # ⑤ 离线特征齐（已建过的才检查——首次跑时由 build 步负责产出）
    for name in names:
        root = B.feature_root(name, L["feature_suffix"])
        if (root / "feat").exists():
            got = len(list((root / "feat").glob("*.pt")))
            print(f"[preflight] {name} 离线特征：{got} 个 feat/*.pt（缺的会在 build 步补齐）")
        else:
            print(f"[preflight] {name} 离线特征：尚未建（{root / 'feat'}）")
    return L


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
    ap.add_argument("--layout", choices=sorted(B.LAYOUTS), default=B.DEFAULT_LAYOUT,
                    help="正典：canon37 = §37 正典（池 453）；buggy = 任务 2 新正典（池 497）。"
                         "四条路径（图/划分/特征根/产物）由它**一起**决定。")
    ap.add_argument("--baselines", default=DEFAULT_BASELINES)
    ap.add_argument("--seeds", default="0,1,2")
    ap.add_argument("--split-seed", type=int, default=None,
                    help="覆盖划分种子；默认 = 每个训练种子自己的 S（本仓要求 ss{S} 与 S 配对）。")
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
    # 🔴 `split_seed` 的默认是**每种子各自的 S**（`resolve_split_seed` 的语义），
    # 不是「固定成第一个」。本仓的语义锁死项要求 `ss{S}` 与 `--split-seed S` 配对，
    # 拿一个固定 split_seed 去跑 3 个训练种子会静默地让 seed1/2 用 seed0 的划分。
    explicit_split_seed = args.split_seed

    L = preflight(names, args.layout, seeds)
    LOGS = log_dir(args.layout)

    extra_build = args.build_args.split()
    extra_train = args.train_args.split()
    failures = []
    for name in names:
        build_script, train_script, canon_train = PIPELINE[name]
        # ---- build（与 seed 无关，只跑一次；用 split_seed=0 的图目录取源码即可）----
        if "build" in steps and build_script:
            bs = 0 if explicit_split_seed is None else explicit_split_seed
            argv = ["--graph-dir", str(REPO / L["graph_dir"].format(S=bs)),
                    "--split-dir", str(REPO / L["split_dir"]),
                    "--split-seed", str(bs),
                    "--feature-suffix", L["feature_suffix"],
                    *extra_build]
            if args.smoke:
                argv += ["--limit", "8"]
            rc = run_step(name, build_script, argv,
                          LOGS / f"baseline_{name}_build.log", args.dry_run)
            if rc != 0:
                failures.append((name, "build", rc))
                continue
        # ---- train（逐种子）----
        if "train" in steps:
            for s in seeds:
                out_dir = REPO / L["out_dir"].format(name=name)
                if args.only_missing and (out_dir / f"seed{s}" / "test_probs.pt").exists():
                    print(f"[{name}] seed{s} 已有产物，跳过（--only-missing）")
                    continue
                split_seed = s if explicit_split_seed is None else explicit_split_seed
                argv = ["--seed", str(s),
                        "--split-seed", str(split_seed),
                        "--graph-dir", str(REPO / L["graph_dir"].format(S=split_seed)),
                        "--split-dir", str(REPO / L["split_dir"]),
                        "--out-dir", str(out_dir),
                        "--feature-suffix", L["feature_suffix"],
                        *canon_train, *extra_train]
                if args.smoke:
                    argv += ["--smoke"]
                rc = run_step(name, train_script, argv,
                              LOGS / f"baseline_{name}_seed{s}.log", args.dry_run)
                if rc != 0:
                    failures.append((name, f"train seed{s}", rc))

    print("\n===== 汇总 =====")
    if failures:
        for f in failures:
            print(f"  ✗ {f[0]} / {f[1]}：rc={f[2]}")
        return 1
    print(f"  全部成功（layout={args.layout}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
