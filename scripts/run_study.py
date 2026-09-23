#!/usr/bin/env python3
"""n=9 **同配对**研究臂驱动（decisions §31）：一次性产出四组臂，供配对比较。

**为什么需要它**：本仓规范（`decisions.md` §26.7/§27.5）要求「凡下干预有效/无效的结论，
必须用**同配对 ≥9 点**」——即 `(训练种子 ts, 划分种子 ss)` 的 9 个组合，同一对里
同划分、同初始化。但**既有工具做不到**：`run_ablation.py` 把 `split_seed` 绑死等于 `seed`
（它服务的是 3 种子消融矩阵），两个既有研究臂（`loss_study` / `prior_dropout_study`）是**手工跑**的。
手工 `for` 循环正是 `run_ablation.py:5-12` 记录的失效模式（漏一个 `--label-key-mode` 会静默产错标签）。

**本脚本不做两件事**（越界即失去意义）：
  1. **不重新实现单变量断言**——直接复用 `run_ablation.verify_single_variable` / `argv_for_train` /
     `argv_for_eval`（同一实现、两个驱动）。
  2. **不让一对的两臂跨语料**——开跑前断言 `graph_dir` / `split_dir` / `label_file` /
     `label_key_mode` 两臂**逐字相同**。跨语料就不是「一对」（§29.4 的标签源缺口即此类静默失效）。

用法（从仓库根目录运行）：
  python scripts/run_study.py --dry-run                    # 只断言 + 打印 36 个 run 的命令行
  python scripts/run_study.py --only main_bin --only-pairs 3:0   # 小样验证（1 个 run）
  python scripts/run_study.py                              # 全部（≈46 分钟 GPU）

产物：`runs/binary_arm/{main,aug}_{base,bin}/<cfg>_ts{T}_ss{S}/seed{T}/`
      （train → evaluate → diagnose 三件套齐全，含 `best.pt` / `results.json` / `test_probs.pt`）
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

import run_ablation  # noqa: E402  （只借用其单变量断言与 argv 构造，不复制实现）
import run_guard     # noqa: E402

ROOT = REPO / "runs" / "binary_arm"
PAIRS = [(t, s) for t in (3, 4, 5) for s in (0, 1, 2)]      # n=9 同配对

# 每项 = (study 名, 输出子目录, 配置名前缀, 事实来源 config.json, 唯一覆盖键)
# 事实来源刻意选**与配对基线完全同源的那份 config**：① 用该对归档的 drop20 叶子，
# ② 用 augmentation 正典叶子（它带着 `label_key_mode=stem` 这个**静默失效高发项**）。
STUDIES: dict[str, dict] = {
    "main_base": dict(
        sub="main_base", cfg="base", override={},
        base=lambda t, s: f"runs/prior_dropout_study/drop20_ts{t}_ss{s}/seed{t}/config.json"),
    "main_bin": dict(
        sub="main_bin", cfg="bin", override={"head": "binary"},
        base=lambda t, s: f"runs/prior_dropout_study/drop20_ts{t}_ss{s}/seed{t}/config.json"),
    "aug_base": dict(
        sub="aug_base", cfg="base", override={},
        base=lambda t, s: "runs/augmentation/seed0/config.json"),
    "aug_bin": dict(
        sub="aug_bin", cfg="bin", override={"head": "binary"},
        base=lambda t, s: "runs/augmentation/seed0/config.json"),
}

# 一对的两臂必须逐字相同的语料键（缺一即不是"一对"）
CORPUS_KEYS = ("graph_dir", "split_dir", "label_file", "label_key_mode")

PAIR_OF = {                       # 每一项的配对伙伴（用于跨语料断言）
    "main_base": "main_bin", "main_bin": "main_base",
    "aug_base": "aug_bin", "aug_bin": "aug_base",
}


def load_base(path: str) -> dict:
    p = REPO / path
    if not p.exists():
        raise SystemExit(f"[study] 找不到事实来源 {p}")
    return json.loads(p.read_text(encoding="utf-8"))["args"]


def leaf_dir(study: str, t: int, s: int) -> Path:
    """本对的**叶子目录**（`train.py` 会在其下再建 `seed{t}/`）。

    命名 `…_ts{T}_ss{S}` 是 `paired_study_analysis.LEAF_RE` 的硬要求——它靠这个名字
    把两臂按 `(ts, ss)` 配上对。**每个 (t,s) 一个叶子**，否则 9 对会撞进同一目录。
    """
    spec = STUDIES[study]
    return ROOT / spec["sub"] / f"{spec['cfg']}_ts{t}_ss{s}"


def build_args(base: dict, study: str, t: int, s: int) -> dict:
    """基线 + 唯一覆盖 + 记账键（`seed`/`split_seed`/`out_dir`/`overwrite`）。"""
    spec = STUDIES[study]
    args = dict(base)
    args.update(spec["override"])
    args["seed"] = t
    args["split_seed"] = s
    args["out_dir"] = str(leaf_dir(study, t, s))
    args["overwrite"] = False
    return args


def argv_for_diagnose(args: dict) -> list[str]:
    """diagnose.py 的命令行（产出 `test_probs.pt` 与 `diagnosis.json`）。

    2026-09-21：实现**移到 `run_ablation.argv_for_diagnose`**（与 `argv_for_train`/
    `argv_for_eval` 并列，三者形状一致），此处**委托**过去，保持一份实现。
    起因：`run_ablation.py` 原先的 train→evaluate 两步链**不含 diagnose**，
    产出的 run 缺 `test_probs.pt` ⇒ 三口径逐类表读不到（整列 `—`、不报错）。
    本函数名字与签名不变，`run_ablation_n9.py` 等既有调用方**无需改动**。
    """
    return run_ablation.argv_for_diagnose(args)


def preflight(study: str, pairs: list[tuple[int, int]]) -> None:
    """开跑前把「单变量」与「同语料」两条断言一次验完；不通过就退出、不跑。"""
    print(f"{'study':10s} {'pair':7s} {'唯一开关':22s} 断言")
    print("-" * 78)
    bad: list[str] = []
    for t, s in pairs:
        base = load_base(STUDIES[study]["base"](t, s))
        args = build_args(base, study, t, s)
        override = STUDIES[study]["override"]

        violations = run_ablation.verify_single_variable(base, args, override)
        flag = " ".join(f"--{k.replace('_', '-')} {v}" for k, v in override.items()) or "（无，基线臂）"

        # 同语料断言：与配对伙伴的语料键必须逐字相同
        peer = PAIR_OF[study]
        pbase = load_base(STUDIES[peer]["base"](t, s))
        pargs = build_args(pbase, peer, t, s)
        mism = [k for k in CORPUS_KEYS if args.get(k) != pargs.get(k)]

        state = "✅ 恰一个变量 + 同语料" if not violations and not mism else \
                "❌ " + (violations[0] if violations else f"与 {peer} 语料不一致：{mism}")
        print(f"{study:10s} {t}:{s:<5d} {flag:22s} {state}")
        if violations or mism:
            bad.append(f"{study} {t}:{s} → {violations or mism}")
    if bad:
        raise SystemExit("\n[study] 预检未通过，已中止（不跑）：\n  " + "\n  ".join(bad))
    print()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="只跑这些 study（逗号分隔；默认全部）。")
    ap.add_argument("--only-pairs", default="", help="只跑这些对，如 `3:0,4:1`。")
    ap.add_argument("--dry-run", action="store_true", help="只断言 + 打印命令行，不执行。")
    ap.add_argument("--keep-going", action="store_true", help="单个 run 失败后继续。")
    ap.add_argument("--skip-diagnose", action="store_true",
                    help="跳过 diagnose.py（不产 test_probs.pt；error_rates 会看不到该臂）。")
    ap.add_argument("--evaluate-only", action="store_true",
                    help="跳过训练，只重跑 evaluate.py（+diagnose.py）。用于评估层口径变更后"
                         "统一补齐已有 run 的产物（如新增一个上报指标），零重训。")
    args = ap.parse_args()

    studies = list(STUDIES)
    if args.only:
        want = [x.strip() for x in args.only.split(",") if x.strip()]
        unknown = set(want) - set(STUDIES)
        if unknown:
            raise SystemExit(f"[study] 未知 study {sorted(unknown)}；可选 {studies}")
        studies = want
    pairs = PAIRS
    if args.only_pairs:
        pairs = [tuple(int(v) for v in p.split(":")) for p in args.only_pairs.split(",")]

    print(f"[study] 根目录 {ROOT}；{len(studies)} 个 study × {len(pairs)} 对 = "
          f"{len(studies) * len(pairs)} 个 run；dry_run={args.dry_run}\n")
    for st in studies:
        preflight(st, pairs)

    if args.dry_run:
        for st in studies:
            for t, s in pairs:
                base = load_base(STUDIES[st]["base"](t, s))
                a = build_args(base, st, t, s)
                print(f"[{st} {t}:{s}] → {leaf_dir(st, t, s)}/seed{t}")
                # dry-run 必须**如实反映将要执行哪几步**，否则它作为"开工前核对"就失去意义
                if not args.evaluate_only:
                    print("   [train] " + " ".join(run_ablation.argv_for_train(a)[2:]))
                print("   [eval]  " + " ".join(run_ablation.argv_for_eval(a)[2:]))
                if not args.skip_diagnose:
                    print("   [diag]  " + " ".join(argv_for_diagnose(a)[2:]))
        print(f"\n[study] dry-run 结束：{len(studies) * len(pairs)} 个 run"
              f"（evaluate_only={args.evaluate_only}）")
        return

    failures: list[tuple[str, str]] = []
    t0 = time.perf_counter()
    for st in studies:
        for t, s in pairs:
            tag = f"{st}/{t}:{s}"
            a = build_args(load_base(STUDIES[st]["base"](t, s)), st, t, s)
            run_seed_dir = leaf_dir(st, t, s) / f"seed{t}"
            # 三态续跑判据与 run_ablation 共用一处实现（判据必须是**最后一步的产物**）。
            # 原先只看 `config.json`：训练完成后 evaluate/diagnose 失败的话，该 run 会被
            # **永远跳过**、`results.json` 补不上，而 `--summarize` 会照常出 n<9 的均值。
            state = run_ablation.resume_state(run_seed_dir)
            if state == "done" and not args.evaluate_only:
                print(f"[{tag}] 跳过：results.json 已存在（要重跑请先归档该目录）", flush=True)
                continue
            if args.evaluate_only and not (run_seed_dir / "best.pt").exists():
                print(f"[{tag}] 跳过：--evaluate-only 但无 best.pt", flush=True)
                continue
            # "eval" = 训练产物齐、只差下游 → 不重训
            steps = [] if (args.evaluate_only or state == "eval") \
                else [("train", run_ablation.argv_for_train(a))]
            steps.append(("eval", run_ablation.argv_for_eval(a)))
            if not args.skip_diagnose:
                steps.append(("diagnose", argv_for_diagnose(a)))
            for name, argv in steps:
                r = subprocess.run(argv, cwd=REPO, capture_output=True, text=True)
                if r.returncode != 0:
                    tail = (r.stderr or r.stdout or "")[-600:]
                    print(f"[{tag}] ❌ {name} 失败：\n{tail}", flush=True)
                    failures.append((f"{tag}/{name}", tail))
                    break
                print(f"[{tag}] {name} ok  {r.stdout.strip().splitlines()[-1][:110] if r.stdout.strip() else ''}",
                      flush=True)
            else:
                continue
            if not args.keep_going:
                break

    wall = time.perf_counter() - t0
    print(f"\n[study] 结束：{len(studies) * len(pairs)} 个 run，wall {wall:.1f}s，失败 {len(failures)}")
    if failures:
        raise SystemExit(f"[study] 有 {len(failures)} 处失败：{[f[0] for f in failures]}")


if __name__ == "__main__":
    main()
