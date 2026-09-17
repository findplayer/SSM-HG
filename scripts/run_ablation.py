#!/usr/bin/env python3
"""阶段 F 消融驱动：按**显式矩阵**跑 5.4.1 + 5.4.2 的可直接执行项。

**为什么需要这个脚本、而不是照计划里的 shell 模板手敲**
消融的全部价值在于「**只有一个变量在动**」（`experiments/ablation_plan.md` §7 验收第 1 条）。
手敲 `for S in 0 1 2; do python scripts/train.py ... <FLAG>; done` 时，
漏一个 `--graph-dir`、把 `--split-seed $S` 写成 `--split-seed 0`、或**顺手多带一个开关**，
都会静默产出"看起来是消融、其实是另一个实验"的结果——而且**不会报错**。
（本仓已两次栽在这类"不报错的错"上：§28 的 `.ravel()`、§29.4 的 `diagnose.py` 标签源。）

故本脚本以**正典 `runs/seed0/config.json::args` 为唯一基线**，对每项**只覆盖一个键**，
并在开跑前用 `run_guard.diff_args` **断言差异恰为该键**——不满足就报错退出，不跑。

用法（从仓库根目录运行）：
  python scripts/run_ablation.py --dry-run              # 打印矩阵 + 逐项断言结果
  python scripts/run_ablation.py --only dfg_dep         # 只跑一项（小样验证）
  python scripts/run_ablation.py                        # 跑全部（约 30 分钟 GPU）

产物：`runs/ablation/<item>/seed{0,1,2}/` + `runs/ablation/<item>/summary.json`。
`eval_results/ablation/` 的对照表由后续步骤产出（本脚本只到 summary）。
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

import run_guard  # noqa: E402

CANON_RUN = REPO / "runs" / "seed0"          # 正典基线（重训后，现行口径）
ABLATION_ROOT = REPO / "runs" / "ablation"

# 与基线无关、每项都要改的键（不算"第二个变量"）
BOOKKEEPING = frozenset({"seed", "split_seed", "out_dir", "overwrite"})

# ------------------------------------------------------------------ 消融矩阵
# 每项 = (item 名, 唯一覆盖键, 覆盖值, 说明)。**键必须恰为一个**，否则开跑前报错。
# 依据：大纲 `改II` 5.4.1（必要 11 项）+ 5.4.2（可选 6 项）中**开关已存在**的部分。
ABLATIONS: list[tuple[str, dict, str]] = [
    # ---- 5.4.1 必要消融 ----
    ("dfg_dep",        {"drop_edges": "3"},                    "去 DFG_DEP（物理关系 3）"),
    ("cfg_flow",       {"drop_edges": "0"},                    "去 CFG_FLOW（物理关系 0）"),
    ("ast_parent",     {"drop_ast": True},                     "去 AST_PARENT（关系 1+2，--drop-ast）"),
    ("callback_risk",  {"drop_edges": "4"},                    "去 CALLBACK_RISK（物理关系 4）"),
    ("cb_node_only",   {"cb_channels": "cb_node"},             "去函数级 CodeBERT（只留节点级）"),
    ("cb_func_only",   {"cb_channels": "cb_func"},             "去节点级 CodeBERT（只留函数级）"),
    ("meanpool",       {"meanpool": True},                     "meanpool 替换 a_v 加权 readout"),
    ("no_lvar",        {"lambda_var": 0.0},                    "关闭 L_var（方差正则项）"),
    ("no_prior_drop",  {"prior_dropout": 0.0},                 "关闭先验 Dropout（丢弃率语义，见 decisions §26）"),
    ("feat_base",      {"feat_groups": "base"},                "结构特征分组 (a) base"),
    ("feat_base_sem",  {"feat_groups": "base+sem"},            "结构特征分组 (b) base+sem"),
    # ---- 5.4.2 可选消融（开关已存在者）----
    ("hid256",         {"hid": 256},                           "隐藏维度 256（基线 128）"),
]

# 需人工定值、故**不预置**的项（避免我替用户拍板）：
PENDING_DECISION = [
    ("num_bases", "--num-bases", "默认 5（= 关系数）。**取值待定**：3 / 10 / 其他？"),
    ("dropedge", "--drop-edge-prob", "默认 0.0（关闭）。**取值待定**：0.1 / 0.2 / 0.5？"),
]


def canonical_args() -> dict:
    """正典基线参数（`runs/seed0/config.json::args`，现行重训口径）。"""
    path = CANON_RUN / "config.json"
    if not path.exists():
        raise SystemExit(f"[ablation] 找不到正典基线 {path}；先跑主实验或检查 runs/")
    return json.loads(path.read_text(encoding="utf-8"))["args"]


def build_args(base: dict, override: dict, seed: int, item: str) -> dict:
    """基线 + 唯一覆盖 + 记账键（seed/split_seed/out_dir）。

    `split_seed` 与 `seed` 同值：沿用主实验的「训练种子与划分种子同名」约定（`decisions.md` §16）。
    """
    args = dict(base)
    args.update(override)
    args["seed"] = seed
    args["split_seed"] = seed
    args["out_dir"] = str(ABLATION_ROOT / item)
    args["overwrite"] = False
    return args


def verify_single_variable(base: dict, args: dict, override: dict) -> list[str]:
    """断言 `args` 相对 `base` 的差异**恰为 `override` 的那一个键**。返回违规描述（空 = 通过）。"""
    diffs = run_guard.diff_args(base, args)
    changed = {d.split(":", 1)[0] for d in diffs}
    expected = set(override.keys())
    unexpected = changed - expected - BOOKKEEPING
    if unexpected:
        return [f"除 {sorted(expected)} 外还改了 {sorted(unexpected)}：{diffs}"]
    if changed & expected != expected:
        return [f"预期覆盖的键未生效：{sorted(expected - changed)}（diffs={diffs}）"]
    return []


def argv_for_train(args: dict) -> list[str]:
    """与 `rerun_from_config.build_argv` 同一约定：从 args 字典重建命令行。"""
    argv = [sys.executable, str(REPO / "scripts" / "train.py")]
    for key in sorted(args):
        if key == "overwrite":
            continue
        value = args[key]
        flag = "--" + key.replace("_", "-")
        if isinstance(value, bool):
            if value:
                argv.append(flag)
        elif value is None:
            continue
        else:
            argv += [flag, str(value)]
    return argv


def argv_for_eval(args: dict) -> list[str]:
    argv = [sys.executable, str(REPO / "scripts" / "evaluate.py"),
            "--runs-dir", args["out_dir"], "--seed", str(args["seed"]),
            "--graph-dir", args["graph_dir"], "--split-dir", args["split_dir"]]
    for key in ("label_file", "label_key_mode"):
        if args.get(key):
            argv += ["--" + key.replace("_", "-"), str(args[key])]
    return argv


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--only", default="", help="只跑这些项（逗号分隔；默认全部）。")
    p.add_argument("--seeds", default="0,1,2", help="训练/划分种子（默认 0,1,2）。")
    p.add_argument("--dry-run", action="store_true",
                   help="只打印矩阵与逐项断言结果，不执行。")
    p.add_argument("--keep-going", action="store_true", help="单项失败后继续。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    base = canonical_args()
    seeds = [int(s) for s in args.seeds.split(",") if s.strip()]
    items = ABLATIONS
    if args.only:
        needles = [s.strip() for s in args.only.split(",") if s.strip()]
        items = [it for it in ABLATIONS if it[0] in needles]
        unknown = set(needles) - {it[0] for it in ABLATIONS}
        if unknown:
            raise SystemExit(f"[ablation] 未知项 {sorted(unknown)}；可选："
                             f"{[it[0] for it in ABLATIONS]}")
    if not items:
        raise SystemExit("[ablation] 没有匹配的消融项")

    print(f"[ablation] 基线 {CANON_RUN / 'config.json'}；{len(items)} 项 × {len(seeds)} 种子 "
          f"= {len(items) * len(seeds)} 个 run；dry_run={args.dry_run}\n")

    # ---- 开跑前把每一项的"单变量"性质验一遍（这是本脚本存在的理由）----
    bad = []
    print(f"{'项':16s} {'唯一开关':34s} 断言")
    print("-" * 72)
    for item, override, _desc in items:
        probe = build_args(base, override, seeds[0], item)
        violations = verify_single_variable(base, probe, override)
        flag = " ".join(f"--{k.replace('_', '-')} {v}" if not isinstance(v, bool)
                        else f"--{k.replace('_', '-')}" for k, v in override.items())
        print(f"{item:16s} {flag:34s} {'✅ 恰一个变量' if not violations else '❌ ' + violations[0]}")
        bad += [(item, v) for v in violations]
    if bad:
        raise SystemExit("\n[ablation] 有项不是单变量，已中止（不跑）。修矩阵后重试。")
    print()

    for item, ov, desc in PENDING_DECISION:
        print(f"[ablation] ⏸ 待定值、未预置：{item:12s} {ov}  {desc}")
    print()

    if args.dry_run:
        for item, override, desc in items:
            print(f"[{item}] {desc}")
            for s in seeds:
                a = build_args(base, override, s, item)
                print(f"   seed{s} → {a['out_dir']}/seed{s}")
                print("   " + " ".join(argv_for_train(a)[2:]))
        print(f"\n[ablation] dry-run 结束：{len(items)} 项 × {len(seeds)} 种子")
        return

    failures: list[tuple[str, str]] = []
    t_start = time.perf_counter()
    for item, override, desc in items:
        for s in seeds:
            tag = f"{item}/seed{s}"
            a = build_args(base, override, s, item)
            run_dir = ABLATION_ROOT / item / f"seed{s}"
            if (run_dir / "best.pt").exists():
                print(f"[{tag}] 跳过：best.pt 已存在", flush=True)
                continue
            t0 = time.perf_counter()
            tr = subprocess.run(argv_for_train(a), cwd=REPO, capture_output=True, text=True)
            if tr.returncode != 0:
                failures.append((tag, f"train: {(tr.stderr or tr.stdout)[-500:]}"))
                print(f"[{tag}] ✗ train 退出码 {tr.returncode}", flush=True)
                if not args.keep_going:
                    break
                continue
            ev = subprocess.run(argv_for_eval(a), cwd=REPO, capture_output=True, text=True)
            if ev.returncode != 0:
                failures.append((tag, f"evaluate: {(ev.stderr or ev.stdout)[-500:]}"))
                print(f"[{tag}] ✗ evaluate 退出码 {ev.returncode}", flush=True)
                if not args.keep_going:
                    break
                continue
            # last.pt 仅断点续训用；消融 run 是 30 秒级的，续训无意义，留着白占一倍体积
            (run_dir / "last.pt").unlink(missing_ok=True)
            print(f"[{tag}] ✓ {time.perf_counter() - t0:5.1f}s  {desc}", flush=True)
        # 每项收尾：刷新 summary.json
        sm = subprocess.run([sys.executable, str(REPO / "scripts" / "evaluate.py"),
                             "--summarize", "--runs-dir", str(ABLATION_ROOT / item)],
                            cwd=REPO, capture_output=True, text=True)
        print(f"[{item}] summarize {'✓' if sm.returncode == 0 else '✗'}", flush=True)

    print(f"\n[ablation] 结束：用时 {time.perf_counter() - t_start:.1f}s；"
          f"产物 {ABLATION_ROOT}", flush=True)
    for tag, err in failures:
        print(f"  ✗ {tag}: {err}", flush=True)
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
