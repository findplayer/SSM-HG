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
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import run_guard  # noqa: E402

CANON_RUN = REPO / "runs" / "seed0"          # 正典基线（重训后，现行口径）
ABLATION_ROOT = REPO / "runs" / "ablation"

# M2 变体目录（`ablation_plan.md` §6.1/§6.3/§6.4）：**只改边 / 只改 `_cb.pt`**，
# 由 `scripts/build_graph_variant.py` 造，产物一律在 `products/<数据集>/graph_variants/<名>`。
VARIANT_ROOT = REPO / "products" / "alldata" / "graph_variants"

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
    # ---- 5.4.2 取值已裁定（2026-09-18，用户裁定采用计划 §3.1 的建议值）----
    # ⚠ 与上面的"去掉某输入/结构"类不同，这三项是**模型容量/正则强度**类：
    #   `--num-bases` 改变 RGCN 基分解的基矩阵个数 → **参数量随之变化**；
    #   报告时必须随附 `config.json::derived.parameter_report`，否则无法区分
    #   "该组件重要"与"模型变小了/变大了"（`ablation_plan.md` §3.1 已载此要求）。
    # ⚠ `--num-bases` 的**合法范围是 [1, num_relations] 即 [1, 5]**（`model.py:332`），
    #   而 **5 就是基线**（`model.py:19`：默认 = 关系数）。故计划里"取 10 检验过参数化"**在实现上不可行**
    #   （实测 `ValueError: num_bases must be in [1, 5], got 10`），"两端各一"的设计塌掉——
    #   合法上端恰是默认值。**改为在合法非默认区间取两端**：1 与 4（`model.py:19` 自己点名 4「仅作消融」），
    #   并补上计划候选里的 3，凑成 **1/3/4 vs 默认 5** 的剂量-反应。
    ("numbases1",      {"num_bases": 1},                       "RGCN 基分解 num_bases=1（所有关系共享一组基，最低容量端）"),
    ("numbases3",      {"num_bases": 3},                       "RGCN 基分解 num_bases=3（合法非默认区间的中点）"),
    ("numbases4",      {"num_bases": 4},                       "RGCN 基分解 num_bases=4（合法非默认区间的最高端；model.py:19 点名此值「仅作消融」）"),
    ("dropedge02",     {"drop_edge_prob": 0.2},                "DropEdge 概率 0.2（基线 0.0=关闭；与 prior/struct dropout 默认同档）"),
    # ---- 2026-09-18 补齐的 4 项（原「未跑 4 项」，开发方案见 ablation_plan §6）----
    # 层数：**L=2 就是基线**，故只跑 1 与 3（`--layers` 已登记 run_guard.IDENTITY_DEFAULTS）。
    ("layers1",        {"layers": 1},                          "RGCN 层数 L=1（基线 L=2；大纲 5.4.1 第 13 项）"),
    ("layers3",        {"layers": 3},                          "RGCN 层数 L=3（基线 L=2；大纲 5.4.1 第 13 项）"),
    # 两项 M2 变体：**只改 `--graph-dir`**（变体目录里装的才是变体图，见各目录的 variant.json）。
    # ⚠ **带 `_ss{seed}`**（2026-09-19 起）：正典的 `_cb.pt` 已是微调产物、**每个划分种子一套**，
    #   故这两个臂的变体也必须逐种子造（`cb_rev_ss{S}` / `cb_unlimited_ss{S}`），
    #   否则它们会带着**冻结**的 `_cb.pt` 去和**微调**的基线比 = 两个变量（`decisions.md` §37）。
    ("cb_unlimited",   {"graph_dir": "{variants}/cb_unlimited_ss{seed}"},
     "CALLBACK_RISK 每源节点出边**不设上限**（基线 4；大纲 5.4.1 第 5 项）"),
    ("cb_rev",         {"graph_dir": "{variants}/cb_rev_ss{seed}"},
     "额外反向关系 CALLBACK_RISK_REV（基线无；大纲 5.4.2 第 12 项，关系数 5→6）"),
    # 🔴 2026-09-19（§37）：`cb_ft`（微调 CodeBERT）**已升为正典**，不再是消融臂；
    #   与之配对的反向臂 `cb_frozen`（冻结 CodeBERT）进入本表 —— 对比关系不变，只是方向反转。
    ("cb_frozen",      {"graph_dir": "{frozen}"},
     "冻结 CodeBERT（正典=微调 CodeBERT；大纲 5.4.2 第 17 项，方向已反转）"),
]

# ---------------------------------------------------------------- 剂量-反应臂（**不进正典表**）
# 🔴 **为什么不放 ABLATIONS**：`ABLATIONS` 是**正典消融表**的臂集合，其规模（21 臂）被
#   `tests/test_collect_ablation.py`、`eval_results/ablation/collected*.md`、
#   `experiments/ablation_three_metric_table.md` 与 AGENTS.md **多处硬引用**；
#   往里加臂 = 同时改这些表的行数与全部「n/21 为负」类计数断言。
#   而 L_var 剂量-反应本身是**大纲之外的后处理**（AGENTS.md 改动原则：须先同步大纲与开发手册），
#   未经裁定就进正典臂表属流程越界。故单独列在这里，用 `--arms-file` 显式启用。
#
# **为什么该项值得补**：`no_lvar` 把 λ 置 0，但实测 λ·L_var 在训练中只占总损失的
#   **0.0003%–0.0054%**（`improvement_proposals.md` §4.1 逐 epoch 实测）⇒ 这一项在数值上
#   等于没加，故"关掉它"是构造性空操作（Δ +0.0045 = 纯噪声）。论文里**不得**由此写成
#   "L_var 无作用"，正确说法是「**本实验的 λ 取值使该项不产生可测影响**」。
DOSE_ARMS: list[tuple[str, dict, str]] = [
    ("lvar_dose_0.01", {"lambda_var": 0.01}, "L_var 剂量 λ=0.01（基线 0.001，×10）"),
    ("lvar_dose_0.1",  {"lambda_var": 0.1},  "L_var 剂量 λ=0.1（基线 0.001，×100）"),
    ("lvar_dose_1.0",  {"lambda_var": 1.0},  "L_var 剂量 λ=1.0（基线 0.001，×1000）"),
]

# 仍需人工定值、故**不预置**的项（避免我替用户拍板）。取到值后加进 ABLATIONS 并在描述里写「已裁定」。
PENDING_DECISION: list[tuple[str, str, str]] = [
    # `num_bases` 与 `drop_edge_prob` **已于 2026-09-18 裁定采用计划 §3.1 建议值**（见上方 ABLATIONS），
    # 故移出待定表；保留一行记录裁定，便于追溯"这两项为何是这两个值"。
    # ⚠ 原文误记为"取 1 与 10"（10 超出合法范围，见上方注释），2026-09-18 更正为 1 与 4。
    ("__decided__", "—", "已裁定：num_bases 取 1/3/4（对默认 5）、drop_edge_prob 取 0.2（2026-09-18）"),
]


def canonical_args(base_config: Path) -> dict:
    """基线的参数（`config.json::args`）。默认 `runs/seed0/`（① 主库正典）。

    ② 增强集传 `--base-config runs/augmentation/seed0/config.json`：两组结果集**各自独立完整**
    （`decisions.md` §23），故各用各的基线，**绝不混用**。
    """
    path = Path(base_config)
    if not path.exists():
        raise SystemExit(f"[ablation] 找不到基线 {path}；先跑该数据集的主实验或检查 runs/")
    args = json.loads(path.read_text(encoding="utf-8"))["args"]
    # 🔴 2026-09-19（§37）：正典的 `graph_dir` **含划分种子**（`graphs_ft/ss{S}`），
    #   因为微调编码器按划分种子各一套。故把它就地转成模板，由 `build_args` 逐 run 展开——
    #   否则**所有**开关臂都会停在 `ss0`，与 seed1/seed2 的划分对不上（dry-run 实测过）。
    #   ⚠ 模板化只对"正典是微调版"这一形态生效；冻结版正典（`products/<语料>/graphs`）不含
    #     `/ss<数字>` 后缀，正则不匹配 ⇒ 原样返回，行为与改动前逐字一致。
    m = re.fullmatch(r"(.+)/ss\d+", str(args.get("graph_dir", "")))
    if m:
        args["graph_dir"] = m.group(1) + "/ss{seed}"
    return args


def variants_root_of(base: dict) -> Path:
    """`{variants}` 的实际值 = 基线 `graph_dir` 的**兄弟目录** `graph_variants/`。

    这样 ①② 各自指向自己的变体区（`products/alldata/graph_variants` /
    `products/augmentation/graph_variants`），不必再传一个数据集开关。
    """
    return Path(base["graph_dir"]).resolve().parent / "graph_variants"


def frozen_graphs_of(base: dict) -> Path:
    """**冻结 CodeBERT 臂**的图目录 = 正典所在语料根下的 `graphs/`。

    2026-09-19 起正典是微调版（`products/<语料>/graphs_ft/ss{S}`，`decisions.md` §37），
    `graphs/` 是其**同级**目录，现在的身份就是「冻结臂」。
    派生而非写死，故 ①② 各自解析，不必再传语料开关。
    """
    return variants_root_of(base).parent.parent / "graphs"


def expand(value, seed: int, variants: Path, frozen: Path | None = None):
    """覆盖值里的 `{seed}` / `{variants}` / `{frozen}` 模板展开（仅字符串）。

    `{seed}` 用于"逐种子不同路径"（微调编码器每个划分种子一套，见 `ablation_plan.md` §6.4）；
    `{frozen}` 供 `cb_frozen` 臂指向冻结图目录。没有模板就只能开特例分支，反而更难审计。
    """
    if isinstance(value, str):
        if "{frozen}" in value and frozen is None:
            raise SystemExit("[ablation] 覆盖值用了 `{frozen}` 但未传 frozen 路径")
        return value.format(seed=seed, variants=variants, frozen=frozen)
    return value


def build_args(base: dict, override: dict, seed: int, item: str,
               root: Path, variants: Path) -> dict:
    """基线 + 唯一覆盖 + 记账键（seed/split_seed/out_dir）。

    `split_seed` 与 `seed` 同值：沿用主实验的「训练种子与划分种子同名」约定（`decisions.md` §16）。
    """
    frozen = frozen_graphs_of(base)
    # 基线侧也要展开：正典的 `graph_dir` 带 `{seed}` 模板（微调编码器逐划分种子一套，§37）
    args = {k: expand(v, seed, variants, frozen) for k, v in base.items()}
    args.update({k: expand(v, seed, variants, frozen) for k, v in override.items()})
    args["seed"] = seed
    args["split_seed"] = seed
    args["out_dir"] = str(root / item)
    args["overwrite"] = False
    return args


def resume_state(run_dir: Path) -> str:
    """一个 run 目录走到哪一步了——决定本次该重跑什么。**判据必须是"最后一步的产物"。**

    三态：
      `"done"`  —— `results.json` 在（evaluate 已完成）→ 整项跳过；
      `"eval"`  —— `config.json` 在而 `results.json` 不在 → 训练已完成、evaluate 未完成 → 只补 evaluate；
      `"train"` —— 其余（含目录不存在）→ 训练 + evaluate 全跑。

    ⚠ **不得用 `best.pt` 判"已完成"（2026-09-18 修）**：`best.pt` 是**训练中途**落盘的
    （每 epoch 刷新），而 `config.json` 由 `train.py` 在**训练全部结束后**才写（`train.py:624`）。
    故被外部打断（如 `wsl --shutdown`）的 run 会留下 `best.pt` + `last.pt` 却**没有**
    `config.json`/`results.json`。用 `best.pt` 判据会把它当"已完成"跳过 ⇒ `results.json`
    **永远补不上** ⇒ `--summarize` 只聚合到剩下的种子 ⇒ 产出 **n=2 的均值**却挂在"3 种子消融"
    名下（`summary.json` 的 `n` 字段会显形，但极易漏看）。这是本仓第三次栽在"不报错的错"上
    （§28 `.ravel()`、§29.4 标签源），故判据收敛成一个显式三态函数，而不是散在循环里。
    """
    if (run_dir / "results.json").exists():
        return "done"
    if (run_dir / "config.json").exists():
        return "eval"
    return "train"


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
    p.add_argument("--with-dose-arms", action="store_true",
                   help="把 `DOSE_ARMS`（L_var 剂量-反应）并入可选项。**默认关闭**——"
                        "它们不进正典消融表（行数被多处硬引用），且属大纲之外的后处理。")
    p.add_argument("--seeds", default="0,1,2", help="训练/划分种子（默认 0,1,2）。")
    p.add_argument("--base-config", default=str(CANON_RUN / "config.json"),
                   help="基线 config.json（① 默认 runs/seed0/；② 传 runs/augmentation/seed0/）。")
    p.add_argument("--root", default=str(ABLATION_ROOT),
                   help="产物根目录（① 默认 runs/ablation；② 建议 runs/ablation_aug）。")
    p.add_argument("--dry-run", action="store_true",
                   help="只打印矩阵与逐项断言结果，不执行。")
    p.add_argument("--keep-going", action="store_true", help="单项失败后继续。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    base = canonical_args(args.base_config)
    root, variants = Path(args.root), variants_root_of(base)
    seeds = [int(s) for s in args.seeds.split(",") if s.strip()]
    # 正典臂 + （可选）剂量-反应臂。剂量臂**默认不跑**，以免无意改动正典表的行数。
    all_items = list(ABLATIONS) + (list(DOSE_ARMS) if args.with_dose_arms else [])
    items = all_items
    if args.only:
        needles = [s.strip() for s in args.only.split(",") if s.strip()]
        items = [it for it in all_items if it[0] in needles]
        unknown = set(needles) - {it[0] for it in all_items}
        if unknown:
            hint = "" if args.with_dose_arms else "（剂量臂需加 --with-dose-arms）"
            raise SystemExit(f"[ablation] 未知项 {sorted(unknown)}{hint}；可选："
                             f"{[it[0] for it in all_items]}")
    if not items:
        raise SystemExit("[ablation] 没有匹配的消融项")

    print(f"[ablation] 基线 {args.base_config}；{len(items)} 项 × {len(seeds)} 种子 "
          f"= {len(items) * len(seeds)} 个 run；dry_run={args.dry_run}\n")

    # ---- 开跑前把每一项的"单变量"性质验一遍（这是本脚本存在的理由）----
    bad = []
    print(f"{'项':16s} {'唯一开关':34s} 断言")
    print("-" * 72)
    for item, override, _desc in items:
        probe = build_args(base, override, seeds[0], item, root, variants)
        # ⚠ 参照侧也要展开（`base` 的 `graph_dir` 是 `ss{seed}` 模板）：否则每个开关臂都会被
        #   误判为"多改了一个 graph_dir"。展开在 seed=0 上进行，与 probe 同种子，可直接对拍。
        ref = {k: expand(v, seeds[0], variants, frozen_graphs_of(base)) for k, v in base.items()}
        violations = verify_single_variable(ref, probe, override)
        flag = " ".join(f"--{k.replace('_', '-')} {v}" if not isinstance(v, bool)
                        else f"--{k.replace('_', '-')}" for k, v in override.items())
        print(f"{item:16s} {flag:34s} {'✅ 恰一个变量' if not violations else '❌ ' + violations[0]}")
        bad += [(item, v) for v in violations]
    if bad:
        raise SystemExit("\n[ablation] 有项不是单变量，已中止（不跑）。修矩阵后重试。")
    print()

    undecided = [(i, o, d) for i, o, d in PENDING_DECISION if "已裁定" not in d]
    for item, ov, desc in undecided:
        print(f"[ablation] ⏸ 待定值、未预置：{item:12s} {ov}  {desc}")
    if undecided:
        print()

    if args.dry_run:
        for item, override, desc in items:
            print(f"[{item}] {desc}")
            for s in seeds:
                a = build_args(base, override, s, item, root, variants)
                print(f"   seed{s} → {a['out_dir']}/seed{s}")
                print("   " + " ".join(argv_for_train(a)[2:]))
        print(f"\n[ablation] dry-run 结束：{len(items)} 项 × {len(seeds)} 种子")
        return

    failures: list[tuple[str, str]] = []
    t_start = time.perf_counter()
    for item, override, desc in items:
        for s in seeds:
            tag = f"{item}/seed{s}"
            a = build_args(base, override, s, item, root, variants)
            run_dir = root / item / f"seed{s}"
            state = resume_state(run_dir)
            if state == "done":
                print(f"[{tag}] 跳过：results.json 已存在", flush=True)
                continue
            t0 = time.perf_counter()
            if state == "eval":
                # 训练产物齐、只差 evaluate（上一轮 evaluate 失败或进程被腰斩在此处）
                print(f"[{tag}] 续跑：config.json 已在，只补 evaluate", flush=True)
            else:
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
                             "--summarize", "--runs-dir", str(root / item)],
                            cwd=REPO, capture_output=True, text=True)
        print(f"[{item}] summarize {'✓' if sm.returncode == 0 else '✗'}", flush=True)

    print(f"\n[ablation] 结束：用时 {time.perf_counter() - t_start:.1f}s；"
          f"产物 {root}", flush=True)
    for tag, err in failures:
        print(f"  ✗ {tag}: {err}", flush=True)
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
