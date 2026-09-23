#!/usr/bin/env python3
"""消融 **n=9 同配对网格**补跑驱动（`ablation_results.md` §12.4 之后的第一项收尾）。

**为什么要它**：阶段 F 的 21 臂消融是 **n=3**（`ts = ss = 0,1,2` 的**对角线**），而本仓规范
（`decisions.md` §26.7/§27.5，两天内同类教训两次）要求：**凡下「某干预有效/无效」的结论，
必须同配对 ≥9 点**。§36 用 `ts ∈ {0,1,2} × ss ∈ {0,1,2}` 的 3×3 网格把 `cb_ft` 那一项补到 n=9
并**确认了效应**（test 侧 8/8 指标显著）；本脚本把**同一设计**推广到其余各臂。

🔴 **它只补 6 对、不重跑 9 对**（省掉 1/3 算力）。依据是一条**实测**，不是假设：
  现行代码把已跑的对角 run **逐位复现**（2026-09-21 实测 3/3 抽检：`base ts0_ss0`、
  `meanpool ts0_ss0`、`base ts1_ss2`；`results.json` 的 38 个字段里**只有 `timing.infer_seconds`
  不同**，而那是墙钟、非指标）⇒ 09-19 的旧 run 与现行代码**行为等价**，可与本轮新跑的非对角
  run 混用，不引入"臂间代码版本不一致"的混淆（§36 正是为躲这个混淆而把两臂同时重跑的）。
  ⚠ 该等价性由 **`--verify-reuse` 在开跑前对每一个拟复用的 run 逐键对拍 config** 再验一次，
    不靠上面那一次三例抽检 —— 抽检只证明"当时等价"，逐键对拍证明"这一个 run 就是这个配置"。

**复用的三个来源（全部只读，绝不写）**：
  1. **对角臂 run**：`runs/ablation{,_aug}/<item>/seed{S}`（`ts = ss = S`，已跑）；
  2. **① 的 9 对基线**：`runs/cbft_study/cbft_ts{T}_ss{S}`（§36 的 `cbft` 臂）。它的 `graph_dir`
     是软链 `graph_variants/cb_ft_ss{S} → graphs_ft/ss{S}`，**数据与正典逐字节相同**；
     已实测其对角 `cbft_ts{S}_ss{S}` 与论文正典 `runs/seed{S}` 的 test 指标**逐位相同**。
  3. **② 的对角基线**：`runs/augmentation/seed{S}`。
  ⇒ 故**需要新跑**的只有：各臂的 6 个非对角对 + ② 基线的 6 个非对角对。

**产物**：`runs/ablation_n9/<item>/ts{T}_ss{S}/seed{T}/`（①）、`runs/ablation_n9_aug/…`（②）。
**绝不**覆盖 `runs/ablation*` / `runs/cbft_study` / `runs/augmentation` / `runs/seed*`。

**每对两步**：`train.py` → `evaluate.py` → `diagnose.py`（第三步产 `test_probs.pt`，
汇总脚本靠它离线复算，故**不可省**；`ablation_results.md` 的教训：漏掉产物层会让下游静默缺列）。

用法（从仓库根目录运行）：
  python scripts/run_ablation_n9.py --dry-run                          # 断言 + 列出全部 run 与复用判定
  python scripts/run_ablation_n9.py --only meanpool --only-pairs 1:2   # 小样（1 个 run）
  python scripts/run_ablation_n9.py --group main                       # 只跑 ①（约 16 min）
  python scripts/run_ablation_n9.py                                    # ①② 全跑（② 约 1.6 h）
  python scripts/run_ablation_n9.py --with-dose-arms                   # 并入 L_var 剂量臂
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

import run_ablation as RA                                          # noqa: E402  唯一实现来源
import run_guard                                                   # noqa: E402
import run_study                                                   # noqa: E402  只借 argv_for_diagnose

# n=9 的同配对网格：训练种子 × 划分种子（**训练种子与划分种子分离**，AGENTS.md）
PAIRS: list[tuple[int, int]] = [(t, s) for t in (0, 1, 2) for s in (0, 1, 2)]

# 比对时忽略的记账键（它们按定义逐 run 不同，不构成"配置不同"）
BOOKKEEPING_DIFF_PREFIXES = ("out_dir:", "seed:", "split_seed:", "overwrite:")

# ---------------------------------------------------------------- 两组结果集
# ① 与 ② **各自独立完整**（`decisions.md` §23）：各用各的基线 config、各写各的产物根，**不混用**。
GROUPS: dict[str, dict] = {
    "main": {
        "title": "① 主库 alldata(readonly)",
        "base_config": "runs/seed0/config.json",
        "diag_root": "runs/ablation",            # 对角复用来源
        "new_root": "runs/ablation_n9",          # 非对角新跑
        "arch_root": "runs/arch_n9",             # 架构基线族另开根（**不进消融表**）
        # ① 的 9 对基线已由 §36 备齐（cf. 模块 docstring 来源 2）
        "baseline_leaves": ("runs/cbft_study", "cbft"),
        "baseline_diag": None,                   # 不需要：9 对全在 leaves 里
    },
    "aug": {
        "title": "② 增强集 alldata_augmentation",
        "base_config": "runs/augmentation/seed0/config.json",
        "diag_root": "runs/ablation_aug",
        "new_root": "runs/ablation_n9_aug",
        "arch_root": "runs/arch_n9_aug",
        "baseline_leaves": None,                 # ② 无 §36 那样的现成 9 对基线
        "baseline_diag": "runs/augmentation/seed{seed}",
    },
}

BASELINE_ITEM = "_base"      # 基线在非对角时的叶目录名（下划线开头 ⇒ 不会与消融臂重名）

# ---------------------------------------------------------------- 架构基线族（**不进消融表**）
# 大纲 `改II` 5.3 的 EGFL 行（「验证异构图边类型是否必要」）。§40.4 明载：
#   要主张 RGCN 优势，**前置条件是「参数量匹配的对照 + n≥9 同配对」**。
#   本集补的正是 **n≥9 那一半**；**参数量匹配那一半需要另一套设计**（改宽度/层数把参数对齐），
#   本脚本**不做**、留待作者裁定 —— 做了就等于替作者选定"用哪个旋钮补参数"。
# ⚠ 三条必须随结果一起报的口径（`run_arch_baselines.py` 的 docstring 已详述）：
#   ① 三个基线全是**关系盲**（`model.py` 不把 `edge_type` 传给它）⇒ 结论只能写
#      「关系感知 vs 关系盲」，**不得**写成「RGCN 比 GAT 强」；
#   ② **参数量不匹配**（§40.4 实测 GCN 比正典少 39.5%）⇒ 必须随附 `derived.parameter_report`；
#   ③ 基线臂 `rgcn` **就是本组的 `_base`**（全开关默认）⇒ 不需要另跑。
ARCH_ARMS: list[tuple[str, dict, str]] = [
    ("conv_gcn",  {"conv": "gcn"},  "GCN（关系盲；大纲 5.3 的 EGFL 行）"),
    ("conv_gat",  {"conv": "gat"},  "GAT（关系盲）"),
    ("conv_sage", {"conv": "sage"}, "GraphSAGE（关系盲）"),
]


def is_arch(item: str) -> bool:
    """该臂属于**架构基线族**（产物另开根目录，汇总另起一节）。"""
    return item.startswith("conv_")


# ---------------------------------------------------------------- 参数量匹配对照（**有意的双键**）
# `ablation_results.md` §12.4 第 3 项（`hid256` 的同参数量版）与 §40.4（"要主张 RGCN 优势，
# 前置条件是**参数量匹配的对照** + n≥9 同配对"）要的都是同一件事：**把参数量对齐**。
#
# 🔴 **这些臂是"两个键一起动"，与上面 21 臂的"恰一个键"不同 —— 是有意的**。
#   `verify_single_variable` 的语义是"**恰为声明的那组键**"（实现是集合相等，不是 |keys|==1），
#   故这些臂仍受该断言保护：**声明外的键一个都不许动**。变的是**读法**：
#   它们**不能**读成"某个组件的作用"，只能读成**在参数量对齐下、那一组结构差异的作用**。
#   论文里必须把这一组差异**写全**（下表的"变量"列），否则读者会把 2 个变量读成 1 个。
#
# 宽度是按**二分求解**得到的：让 `SSMHG` 的 rgcn 部分参数 = 正典的 205,754
# （正典 total = 415,226，其中 fuser 209,472 不随 hid/layers/num_bases 变）。
# 实测残差：gcn +92（0.02%）、gat −302（0.07%）、sage +516（0.12%）、hid256 版 +8,536（2.1%）。
# ⚠ `hid256` 在合法旋钮下**无法**精确对齐正典：L=1/B=5 给 423,521、L=2/B=1 给 423,762 已是最接近的两个；
#   取 **L=2/B=1**（保住深度＝正典的 2 层，改的是"基的个数"）。
PM_ARMS: list[tuple[str, dict, str]] = [
    ("hid256_pm", {"hid": 256, "num_bases": 1},
     "hid256 的同参数量版（423,762 = 正典 1.021×；**变量 = 宽度 128→256 + 基 5→1**，深度不变）"),
    ("gcn_pm",  {"conv": "gcn",  "hid": 366},
     "GCN 参数量匹配（hid=366 → 415,318 ≈ 正典；**变量 = 算子 + 宽度**）"),
    ("gat_pm",  {"conv": "gat",  "hid": 364},
     "GAT 参数量匹配（hid=364 → 414,924 ≈ 正典；**变量 = 算子 + 宽度**）"),
    ("sage_pm", {"conv": "sage", "hid": 250},
     "SAGE 参数量匹配（hid=250 → 415,742 ≈ 正典；**变量 = 算子 + 宽度**）"),
]


def is_pm(item: str) -> bool:
    """该臂属于**参数量匹配对照**（产物落在架构族同根下，汇总另起一节）。"""
    return item.endswith("_pm")


def base_args(gkey: str) -> dict:
    """该组的基线参数（`config.json::args`，`graph_dir` 已模板化为 `ss{seed}`）。"""
    return RA.canonical_args(REPO / GROUPS[gkey]["base_config"])


def variants_of(base: dict) -> Path:
    return RA.variants_root_of(base)


def expanded_base(gkey: str, seed: int) -> dict:
    """基线参数在**该种子**下展开后的样子（`{seed}`/`{variants}`/`{frozen}` 全部代入）。

    参照侧也必须展开：否则每个臂都会被误判成"多改了一个 `graph_dir`"（`run_ablation` 同款注释）。
    """
    base = base_args(gkey)
    return {k: RA.expand(v, seed, variants_of(base), RA.frozen_graphs_of(base))
            for k, v in base.items()}


def arm_args(gkey: str, item: str, override: dict, t: int, s: int, out_dir) -> dict:
    """一组消融臂在配对 `(t, s)` 下的完整参数。

    🔴 `seed = t`（训练种子：初始化/dropout/打乱/DropEdge）、`split_seed = s`（划分种子：
    读 `split_seed{S}.json` 与 `graphs_ft/ss{S}` 编码器树）。两者**分离**是本设计的全部要害：
    正是它让"同划分、不同初始化"的配对成为可能。
    """
    base = base_args(gkey)
    variants = variants_of(base)
    frozen = RA.frozen_graphs_of(base)
    args = {k: RA.expand(v, s, variants, frozen) for k, v in base.items()}
    args.update({k: RA.expand(v, s, variants, frozen) for k, v in override.items()})
    args["seed"] = t
    args["split_seed"] = s
    args["out_dir"] = str(out_dir)
    args["overwrite"] = False
    return args


def new_leaf(gkey: str, item: str, t: int, s: int) -> Path:
    """非对角（或不可复用时）的叶目录：`<root>/<item>/ts{T}_ss{S}`（`train.py` 再建 `seed{T}/`）。

    架构基线族走 `arch_root`，与消融臂**分开存**——两张表回答两个不同的问题
    （「拿掉某个输入/结构会怎样」vs「换个关系盲算子会怎样」），混在一个目录里迟早会被混读。
    """
    g = GROUPS[gkey]
    root = g["arch_root"] if (is_arch(item) or is_pm(item)) else g["new_root"]
    return REPO / root / item / f"ts{t}_ss{s}"


def baseline_run_dir(gkey: str, t: int, s: int) -> tuple[Path, bool]:
    """基线的 run 目录 + 是否复用。

    ① 用 §36 的 `cbft_ts{T}_ss{S}`（9 对齐全，全部复用）；
    ② 对角复用 `runs/augmentation/seed{S}`，非对角落在 `runs/ablation_n9_aug/_base/ts{T}_ss{S}`。
    """
    g = GROUPS[gkey]
    if g["baseline_leaves"]:
        root, cfg = g["baseline_leaves"]
        return REPO / root / f"{cfg}_ts{t}_ss{s}" / f"seed{t}", True
    if t == s:
        return REPO / g["baseline_diag"].format(seed=s), True
    return new_leaf(gkey, BASELINE_ITEM, t, s) / f"seed{t}", False


def arm_run_dir(gkey: str, item: str, t: int, s: int) -> tuple[Path, bool]:
    """臂的 run 目录 + 是否复用（对角且产物在 ⇒ 复用旧跑；否则新开非对角叶目录）。"""
    if t == s:
        cand = REPO / GROUPS[gkey]["diag_root"] / item / f"seed{t}"
        if (cand / "results.json").exists():
            return cand, True
    return new_leaf(gkey, item, t, s) / f"seed{t}", False


def reuse_violations(run_dir: Path, want_args: dict) -> list[str]:
    """拟复用的 run 是否**就是**这个配置：逐键对拍 `config.json::args`，忽略记账键。

    为什么必须做：复用的前提是"旧 run 与现行代码等价"，而等价性只在这一个 run 的配置
    与本次要跑的配置**逐键相同**时才成立。少一个键（如旧 run 早于 `--layers`）就会静默
    把两个不同配置当成同一对 —— 这正是本仓反复栽的"不报错的错"。
    """
    cfg = run_dir / "config.json"
    if not cfg.exists():
        return [f"{run_dir} 无 config.json"]
    stored = json.loads(cfg.read_text(encoding="utf-8"))["args"]
    # 记账键按定义就不同：把 want 侧换成 stored 侧的值再比，等于"忽略这些键"
    want = dict(want_args)
    for k in ("out_dir", "seed", "split_seed"):
        want[k] = stored.get(k, want.get(k))
    return [d for d in run_guard.diff_args(stored, want)
            if not d.startswith(BOOKKEEPING_DIFF_PREFIXES)]


# ---------------------------------------------------------------- 计划（两个脚本共用）
def items_for(with_dose: bool, with_arch: bool = False, with_pm: bool = False) -> list[tuple[str, dict, str]]:
    """本次纳入的臂：正典 21 臂（`run_ablation.ABLATIONS`）+ 可选的三组扩充。

    - **剂量臂**（`DOSE_ARMS`）**默认关闭**：大纲之外的后处理，且 `ABLATIONS` 的 21 臂计数被
      `tests/test_collect_ablation.py` 等多处硬引用（`run_ablation.DOSE_ARMS` 的注释已载理由）。
    - **架构基线族**（`ARCH_ARMS`）**默认关闭**：属大纲 5.3 的对比方法、不属 5.4 消融，
      且报告口径不同（关系盲 / 参数量不匹配），故另开根目录与另起一节。
    - **参数量匹配对照**（`PM_ARMS`）**默认关闭**：**有意的双键**对照（见其表上注释），
      回答的是 §12.4 第 3 项与 §40.4 的"参数量对齐"前置条件。
    """
    items = list(RA.ABLATIONS)
    if with_dose:
        items += list(RA.DOSE_ARMS)
    if with_arch:
        items += list(ARCH_ARMS)
    if with_pm:
        items += list(PM_ARMS)
    return items


def plan(gkey: str, items, pairs) -> list[dict]:
    """本组本次要跑的**全部条目**（含被复用的），每个条目自带 `reuse` 与 `violations`。

    基线作为 `item = BASELINE_ITEM`、`override = {}` 的条目一并返回 ——
    这样"9 对是否齐"由**同一个函数**回答，不必在驱动与汇总两处各判一次（两处必然漂移）。
    """
    out: list[dict] = []
    for item, override, desc in [(BASELINE_ITEM, {}, "基线（全开关默认）")] + list(items):
        for t, s in pairs:
            if item == BASELINE_ITEM:
                run_dir, reuse = baseline_run_dir(gkey, t, s)
            else:
                run_dir, reuse = arm_run_dir(gkey, item, t, s)
            args = arm_args(gkey, item, override, t, s, run_dir.parent)
            viol = reuse_violations(run_dir, args) if reuse else []
            out.append({"group": gkey, "item": item, "override": override, "desc": desc,
                        "t": t, "s": s, "run_dir": run_dir, "reuse": reuse,
                        "reuse_violations": viol, "args": args})
    return out


# ---------------------------------------------------------------- 预检
def preflight(entries: list[dict]) -> list[str]:
    """两条断言 + 一条清点，不通过就退出、不跑。

    1. **单变量**：每个臂相对该组基线恰差 `override` 的那一个键（复用 `run_ablation` 的实现，
       **不复制**——复制出来的第二份断言迟早与第一份漂移）；
    2. **复用资格**：拟复用的 run 的 config 与本配置逐键相同（忽略记账键）；
    3. 清点：复用 / 新跑 各多少个 run。
    """
    bad: list[str] = []
    print(f"{'组':5s} {'臂':16s} {'配对':7s} {'唯一开关':30s} 复用判定")
    print("-" * 88)
    for e in entries:
        gkey, item, t, s = e["group"], e["item"], e["t"], e["s"]
        ref = expanded_base(gkey, s)
        if item != BASELINE_ITEM:
            v = RA.verify_single_variable(ref, e["args"], e["override"])
            # 打印**展开后**的值（`{frozen}`/`{variants}` 原样打印会看不出到底指哪棵树）
            variants = variants_of(base_args(gkey))
            frozen = RA.frozen_graphs_of(base_args(gkey))
            flag = " ".join(
                (f"--{k.replace('_', '-')}" if val is True else
                 f"--{k.replace('_', '-')} "
                 f"{RA.expand(val, s, variants, frozen) if isinstance(val, str) else val}")
                for k, val in e["override"].items())
            if v:
                bad.append(f"{gkey}/{item} ts{t}_ss{s} 非单变量：{v[0]}")
        else:
            flag = "（基线臂）"
            # 基线臂相对基线**应当零差异**（除记账键）—— 反向断言，防"基线臂其实带了开关"
            d = [x for x in run_guard.diff_args(ref, e["args"])
                 if not x.startswith(BOOKKEEPING_DIFF_PREFIXES)]
            if d:
                bad.append(f"{gkey}/{item} ts{t}_ss{s} 基线臂竟有差异：{d}")
        if e["reuse"] and e["reuse_violations"]:
            bad.append(f"{gkey}/{item} ts{t}_ss{s} 复用资格不成立：{e['reuse_violations']}")
            verdict = "❌ 配置不符"
        elif e["reuse"]:
            verdict = "♻ 复用"
        else:
            verdict = "▶ 新跑"
        print(f"{gkey:5s} {item:16s} {f'{t}:{s}':7s} {flag:30s} {verdict}")
    n_re = sum(1 for e in entries if e["reuse"])
    print(f"\n[清点] 共 {len(entries)} 个条目：复用 {n_re}、新跑 {len(entries) - n_re}")
    return bad


# ---------------------------------------------------------------- 主循环
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", choices=["main", "aug", "both"], default="both")
    ap.add_argument("--only", default="", help="只跑这些臂（逗号分隔；默认全部 21 臂）。")
    ap.add_argument("--only-pairs", default="", help="只跑这些对，如 `1:2,0:1`（默认 9 对）。")
    ap.add_argument("--with-dose-arms", action="store_true",
                    help="并入 `run_ablation.DOSE_ARMS`（L_var 剂量-反应）。**默认关闭**。")
    ap.add_argument("--with-arch-arms", action="store_true",
                    help="并入 `ARCH_ARMS`（GCN/GAT/SAGE 架构基线族，§40.4 的 n≥9 那一半）。"
                         "产物落 `runs/arch_n9{,_aug}`，与消融臂分开。**默认关闭**。")
    ap.add_argument("--with-pm-arms", action="store_true",
                    help="并入 `PM_ARMS`（参数量匹配对照：hid256 同参数量版 + 三个参数匹配的算子）。"
                         "⚠ 这是**有意的双键**对照，不能读成「单个组件的作用」。**默认关闭**。")
    ap.add_argument("--dry-run", action="store_true", help="只断言 + 打印，不执行。")
    ap.add_argument("--keep-going", action="store_true", help="单个 run 失败后继续。")
    ap.add_argument("--skip-preflight", action="store_true",
                    help="跳过预检（**只在确信配置未变时用**；跳过后无任何单变量与复用保障）。")
    args = ap.parse_args()

    gkeys = ["main", "aug"] if args.group == "both" else [args.group]
    items = items_for(args.with_dose_arms, args.with_arch_arms, args.with_pm_arms)
    if args.only:
        needles = [x.strip() for x in args.only.split(",") if x.strip()]
        items = [it for it in items if it[0] in needles]
        unknown = set(needles) - {it[0] for it in items}
        if unknown:
            raise SystemExit(f"[n9] 未知臂 {sorted(unknown)}（可选：{[it[0] for it in items]}）")
    pairs = PAIRS
    if args.only_pairs:
        pairs = [tuple(int(v) for v in p.split(":")) for p in args.only_pairs.split(",")]

    entries: list[dict] = []
    for gk in gkeys:
        entries += plan(gk, items, pairs)
    print(f"[n9] 分组 {gkeys}；{len(items)} 臂 × {len(pairs)} 对 + 基线 = "
          f"{len(entries)} 个条目；dry_run={args.dry_run}\n")

    if not args.skip_preflight:
        bad = preflight(entries)
        if bad:
            raise SystemExit("\n[n9] 预检未通过，已中止（不跑）：\n  " + "\n  ".join(bad))
        print()
    if args.dry_run:
        for e in entries:
            tag = "♻" if e["reuse"] else "▶"
            print(f"{tag} [{e['group']}/{e['item']} {e['t']}:{e['s']}] → "
                  f"{e['run_dir'].relative_to(REPO)}")
        print(f"\n[n9] dry-run 结束：{len(entries)} 个条目，"
              f"其中新跑 {sum(1 for e in entries if not e['reuse'])}")
        return 0

    failures: list[tuple[str, str]] = []
    t0 = time.perf_counter()
    done = 0
    for e in entries:
        tag = f"{e['group']}/{e['item']}/{e['t']}:{e['s']}"
        if e["reuse"]:
            continue                       # 复用：一个字都不写
        run_dir = e["run_dir"]
        state = RA.resume_state(run_dir)
        run_seed_dir = run_dir                 # `resume_state` 收的就是 <leaf>/seed{T}
        if state == "done":
            print(f"[{tag}] 跳过：results.json 已存在", flush=True)
            continue
        steps = [] if state == "eval" else [("train", RA.argv_for_train(e["args"]))]
        steps += [("eval", RA.argv_for_eval(e["args"])),
                  ("diagnose", run_study.argv_for_diagnose(e["args"]))]
        ok = True
        for name, argv in steps:
            r = subprocess.run(argv, cwd=REPO, capture_output=True, text=True)
            if r.returncode != 0:
                tail = (r.stderr or r.stdout or "")[-500:]
                failures.append((f"{tag}/{name}", tail))
                print(f"[{tag}] ✗ {name} 退出码 {r.returncode}", flush=True)
                ok = False
                break
        if not ok:
            if not args.keep_going:
                break
            continue
        # `last.pt` 只服务断点续训；这些 run 是分钟级的，留着白占一倍体积（`run_ablation` 同）
        (run_seed_dir / "last.pt").unlink(missing_ok=True)
        done += 1
        print(f"[{tag}] ✓ {time.perf_counter() - t0:6.1f}s  {e['desc']}", flush=True)

    print(f"\n[n9] 结束：新跑 {done} 个 run，wall {(time.perf_counter() - t0) / 60:.1f} min，"
          f"失败 {len(failures)}")
    for tag, err in failures:
        print(f"  ✗ {tag}: {err}", flush=True)
    if failures:
        return 1
    print("[n9] 下一步：python scripts/collect_ablation_n9.py --group both")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
