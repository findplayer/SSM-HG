#!/usr/bin/env python3
"""同图**架构基线族**（大纲 `改II` 5.3 的 EGFL 行 / §40.4 的开口项）。

**它回答什么**：把关系感知的 RGCN 换成**关系盲**的 GCN / GAT / GraphSAGE，
指标掉多少？大纲 5.3 表里 EGFL 那一行的作用正是「**验证异构图边类型是否必要**」——
本脚本把这条做成**同图、同特征、同划分、同超参**的对照：**唯一变量 = `--conv`**。

🔴 **三条必须随结果一起报的口径**：
  1. **三个基线全是"关系盲"**（`model.py` 的 `forward` 不把 `edge_type` 传给它们，
     已由 `tests/test_model_smoke.py::test_non_rgcn_convs_ignore_edge_type` 机检）。
     故结论只能写成「**关系感知 vs 关系盲**」，**不得**写成「RGCN 比 GAT 强」——
     那是把"少了 4/5 的关系参数"读成"算子更好"。
  2. **参数量不匹配**（§40.4 已实测 GCN 比正典少 39.5%）。本脚本把每个臂的参数量一并报出，
     **没有它就无法区分"组件重要"与"模型变小了"**。要在论文里主张 RGCN 优势，
     前置条件是**参数量匹配**的对照（本脚本不做参数搜索，只如实报数）。
  3. **n=3**。本仓规范（`decisions.md` §26.7/§27.5）：**n=3 不得判方向**。
     故本脚本的输出是**描述性的**；要下"有效/无效"的结论须 n≥9 同配对。

用法（从仓库根目录运行）：
  python scripts/run_arch_baselines.py --dry-run
  python scripts/run_arch_baselines.py --convs gat sage
  python scripts/run_arch_baselines.py --graph-root products/alldata/graphs_ft_buggy \\
      --split-dir products/alldata/splits/withbuggy_snapshot     # 在任务2 的新正典上跑

产物：`<runs-root>/<conv>/seed{S}/` + `summary.json`（`runs-root` 默认 `runs/baseline_arch`）。
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

import run_ablation as RA                                          # noqa: E402  复用 argv/单变量断言
import run_guard                                                   # noqa: E402

DEFAULT_CONVS = ("gcn", "gat", "sage")
SEEDS = (0, 1, 2)


def graph_dir_for(graph_root: str, seed: int) -> str:
    """逐种子取编码器树。**路径含划分种子**是 §37 的硬约束（AGENTS.md 语义锁死项）。

    两种命名都认：`<root>/ss{S}`（正典 `graphs_ft/`）与 `<root>/cb_ft_ss{S}`（变体根）。
    """
    for cand in (f"{graph_root}/ss{seed}", f"{graph_root}/cb_ft_ss{seed}"):
        if (REPO / cand).exists():
            return cand
    raise SystemExit(f"🔴 {graph_root} 下找不到 seed{seed} 的编码器树"
                     f"（试过 ss{seed} / cb_ft_ss{seed}）——路径含划分种子是硬约束")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--convs", nargs="*", default=list(DEFAULT_CONVS))
    ap.add_argument("--seeds", type=int, nargs="*", default=list(SEEDS))
    ap.add_argument("--graph-root", default="products/alldata/graphs_ft",
                    help="编码器树根（默认 §37 正典；任务2 传 products/alldata/graphs_ft_buggy）")
    ap.add_argument("--split-dir", default="products/alldata/splits")
    ap.add_argument("--base-config", default="runs/seed0/config.json",
                    help="基线 config（**唯一变量 = --conv** 的参照）")
    ap.add_argument("--runs-root", default="runs/baseline_arch")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    base = RA.canonical_args(REPO / args.base_config)
    runs_root = REPO / args.runs_root
    t0 = time.perf_counter()
    results = {}
    for conv in args.convs:
        for seed in args.seeds:
            gdir = graph_dir_for(args.graph_root, seed)
            out_dir = f"{args.runs_root}/{conv}"
            train_args = dict(base)
            train_args.update({"conv": conv, "seed": seed, "split_seed": seed,
                               "graph_dir": gdir, "split_dir": args.split_dir,
                               "out_dir": out_dir, "overwrite": False})
            # 🔴 单变量断言：相对基线，差异**恰为**这些键。
            # ⚠ `split_dir` **不能**写进 expected：基线 config 里它已经等于本脚本要传的值
            #   （`diff_args` 按内容比，不是按"命令行有没有出现"），写进去会被判成
            #   "预期覆盖的键未生效"。`graph_dir` 也别写固定值——基线的 `graph_dir` 是
            #   **带 `{seed}` 占位符的模板**（`run_ablation` 的约定），逐种子代入后必然不同。
            expected = {"conv": conv, "out_dir": out_dir}
            if str(base.get("graph_dir")) != gdir:
                expected["graph_dir"] = gdir          # seed0 的基线 graph_dir 恰等于本臂 ⇒ 不算变化
            if str(base.get("split_dir")) != args.split_dir:
                expected["split_dir"] = args.split_dir
            violations = RA.verify_single_variable(base, train_args, expected)
            if violations:
                raise SystemExit(f"🔴 {conv}/seed{seed} 不是单变量对照：{violations}")
            if args.dry_run:
                print(f"[{conv} seed{seed}] graph_dir={gdir} → {out_dir}")
                continue
            for name, argv in (("train", RA.argv_for_train(train_args)),
                               ("eval", RA.argv_for_eval(train_args))):
                print(f"\n=== [{(time.perf_counter() - t0) / 60:.1f} min] {conv}/seed{seed}/{name} ===",
                      flush=True)
                if subprocess.run(argv, cwd=str(REPO)).returncode != 0:
                    raise SystemExit(f"🔴 {conv}/seed{seed}/{name} 失败")
            results.setdefault(conv, []).append(seed)
        if not args.dry_run:
            subprocess.run([sys.executable, "scripts/evaluate.py", "--summarize",
                            "--runs-dir", f"{args.runs_root}/{conv}"], cwd=str(REPO), check=True)
    if args.dry_run:
        return 0

    print("\n[arch-baselines] 参数量（**必须随结果一起报**，见模块 docstring 口径 2）：")
    for conv in args.convs:
        cfg = REPO / args.runs_root / conv / "seed0" / "config.json"
        if cfg.exists():
            d = json.loads(cfg.read_text(encoding="utf-8"))
            pr = (d.get("derived") or {}).get("parameter_report") or {}
            print(f"  {conv:5s} total={pr.get('total')}  conv_type={(d.get('args') or {}).get('conv')}")
    print(f"\n完成，用时 {(time.perf_counter() - t0) / 60:.1f} min → {args.runs_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
