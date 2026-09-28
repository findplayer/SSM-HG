#!/usr/bin/env python3
"""微调 CodeBERT 的 **n=9 同配对**复核驱动（待办 B1；`ablation_results.md` §12.4 第 1 项）。

**为什么需要它**：`cb_ft` 是阶段 F 全部 **21 臂**消融里**唯一越过 df=2 临界值 `|t|>4.303`**
的一项（① Δmicro@0.5 **+0.2797**、t=+8.09、6/6 指标同向为正、三个结构性恒零类全部破零），
也是「瓶颈在输入表征质量、不在图结构」这一结论的唯一证据来源。但既有证据只有 **n=3**，
而本仓规范（`decisions.md` §26.7/§27.5）要求：**凡下「干预有效/无效」的结论必须同配对 ≥9 点**。

**本脚本不做三件事**（越界即失去意义）：

  1. **不重新实现单变量断言**——直接 import 复用 `run_ablation` 的
     `verify_single_variable` / `argv_for_train` / `argv_for_eval` / `resume_state`
     （同 `run_study.py` 的既定做法，`decisions.md` §31.4）。
  2. **不复刻微调**——微调编码器树已存在（`products/alldata/graphs_ft_p2/cb_ft_ss{0,1,2}`），
     本脚本**只读**它（零微调 = 原估的 3×848 s 全部省掉）。
  3. **不碰正典**——产物全部落在 `runs/cbft_study/`；`runs/seed{0,1,2}` 与 `products/` 均**只读**。

**与 `run_study.py`（二分类研究）的唯一实质差别**：本研究的**变量就是 `graph_dir` 本身**
（冻结 `products/alldata/graphs` vs 微调正典树 `graphs_ft_p2/cb_ft_ss{S}`），
故「一对两臂同语料」断言**必须排除 `graph_dir`** —— 它是变量，不是语料键
（`run_study.CORPUS_KEYS` 把它含在内，是二分类研究的情形：那里的变量是 `head`）。
语料同一性由 `split_dir` / `label_file` / `label_key_mode` / `seed` / `split_seed` 五键保证。

⚠ **`ts ∈ {0,1,2}` 的额外用意**：`cbft` 臂取的就是正典树，故 (0,0)/(1,1)/(2,2) 三对在配置上
与 `runs/seed{0,1,2}` **完全相同** ⇒ 可把 `cbft` 臂与正典对拍，**量化主实验的"重跑抖动"**
（`--check-repro`）。
🔴 实测该抖动**不为零**（GPU 非确定性，见 `check_repro` 的 docstring）——
本节最初以为会"逐位复现"，实测推翻；这层噪声的量级本身是论文局限陈述的一条实证。

用法（从仓库根目录运行）：
  python scripts/run_cbft_study.py --dry-run              # 只断言 + 打印 18 条命令行
  python scripts/run_cbft_study.py --only-pairs 0:0       # 小样验证（1 对 = 2 个 run）
  python scripts/run_cbft_study.py                        # 全部 9 对（= 18 run）

产物：`runs/cbft_study/{frozen,cbft}_ts{T}_ss{S}/seed{T}/`（train → evaluate → diagnose 三件套）。

分析（本脚本之外）：
  # 验证集侧 —— 本仓 n=9 惯例口径（`paired_study_analysis.py` 只读 val_best_probs.pt）
  python scripts/paired_study_analysis.py --group runs/cbft_study \\
      --baseline-dir runs/cbft_study --baseline-cfg frozen \\
      --json-out experiments/cbft_paired.json
  # ⚠ 该工具报的是**验证集**指标；论文主表是 **test**，须另读两侧 results.json 的 test 字段。
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

import run_ablation  # noqa: E402  （只借用其断言与 argv 构造，不复制实现）
import run_guard     # noqa: E402
import run_study     # noqa: E402  （只借用其 argv_for_diagnose，避免两处各写一份）

ROOT = REPO / "runs" / "cbft_study"
BASE_CONFIG = REPO / "runs" / "seed0" / "config.json"      # ① 主库正典（当前口径）
PAIRS = [(t, s) for t in (0, 1, 2) for s in (0, 1, 2)]     # n=9 同配对

# 两条臂：`cfg` 名会进叶目录名，必须是 `paired_study_analysis.LEAF_RE` 认得的 `<cfg>_ts{T}_ss{S}`
ARMS: dict[str, dict] = {
    "frozen": dict(note="冻结 CodeBERT（正典，graph_dir=products/alldata/graphs）"),
    "cbft":   dict(note="微调 CodeBERT 后重编码（graph_dir=正典树本身 `graphs_ft_p2/cb_ft_ss{S}`）"),
}
BASELINE_CFG = "frozen"

# 一对两臂必须逐字相同的**语料键**。
# 🔴 与 `run_study.CORPUS_KEYS` 的唯一差别：**不含 `graph_dir`** —— 本研究的变量就是它。
#    改动这一行等于改掉本研究的立论基础，故写死在此、不参数化。
CORPUS_KEYS = ("split_dir", "label_file", "label_key_mode")
# 除语料键外，还须同值的配对键（它们决定"是不是同一对"）
PAIR_KEYS = ("seed", "split_seed")


def load_base() -> dict:
    """正典参数（`runs/seed0/config.json::args`）。

    必须是 train.py 自己产出的 config —— `argv_for_train` **没有键白名单**
    （除 `overwrite` 外每个键都转成 `--<key>`），手写的 dict 会把无关键喂给 argparse。
    """
    if not BASE_CONFIG.exists():
        raise SystemExit(f"[cbft] 找不到正典基线 {BASE_CONFIG}")
    return json.loads(BASE_CONFIG.read_text(encoding="utf-8"))["args"]


def variants_root(base: dict) -> Path:
    """变体区 = 基线 `graph_dir` 的兄弟目录 `graph_variants/`（复用 `run_ablation` 的约定）。"""
    return run_ablation.variants_root_of(base)


def override_of(arm: str, base: dict, split_seed: int) -> dict:
    """该臂的**唯一变量**。

    ⚠ 变体按**划分种子**取（`cb_ft_ss{S}`）：微调用的训练标签来自该划分的训练集，
    故编码器只依赖 `split_seed`、不依赖训练种子 —— 这正是 9 对只需 3 套编码器的原因。

    🔴 **2026-09-25 修掉一处静默漂移（本脚本写于"冻结=正典"时期）**：
      原实现 `frozen` 臂返回 `{}`（继承基线 `graph_dir`）——在写脚本时基线就是冻结树
      `products/alldata/graphs`，故当时正确。**§37（2026-09-19）把微调树升为正典后**，
      基线 `graph_dir` 变成 `graphs_ft/ss{S}`（现为 `graphs_ft_p2/cb_ft_ss{S}`），
      于是 `frozen` 臂**悄悄不再冻结**，变成了正典的副本 ——
      「冻结 vs 微调」的对照实际是「微调 vs 微调」，**不报错、结论失真**。
      现改为**显式**取冻结树（`…/<语料>/graphs`，由 `run_ablation.frozen_graphs_of` 派生），
      与 `ARMS["frozen"]` 的注释一致。
    ⚠ `cbft` 臂**直接取正典树**（不再经 `graph_variants/cb_ft_ss{S}` 这层副本）：
      §36 原设计用"逐字节相同的副本树"，靠**实测**确认对角与正典指标逐位相同；
      直接取正典树使这条等价性**由构造成立**，`run_ablation_n9.py` 的 9 对基线
      因而不必再依赖一次可失败的对拍。单变量性质改由 `check_artifacts()` 对**冻结树 ↔ 正典树**断言。
    """
    if arm == BASELINE_CFG:                       # frozen：冻结编码器树，与正典只差 _cb.pt
        return {"graph_dir": str(run_ablation.frozen_graphs_of(base))}
    if arm == "cbft":                             # cbft：正典本身（微调编码器树）
        # 🔴 必须走 `canonical_args` 的模板化，**不能**直接用 `base["graph_dir"]`：
        #   config 里记的是已展开的 `…/cb_ft_ss0`，直接拿会让 ss1/ss2 也去读 ss0 的编码器
        #   （与划分种子错配、且**不报错** —— 本仓已三次全量作废的同一形态）。
        tmpl = run_ablation.canonical_args(BASE_CONFIG)["graph_dir"]     # `…/cb_ft_ss{seed}`
        return {"graph_dir": tmpl.format(seed=split_seed)}
    raise SystemExit(f"[cbft] 未知臂 {arm}；可选 {sorted(ARMS)}")


def leaf_dir(arm: str, t: int, s: int) -> Path:
    """本对的叶子目录（`train.py` 会在其下再建 `seed{t}/`）。

    命名 `…_ts{T}_ss{S}` 是 `paired_study_analysis.LEAF_RE` 的硬要求——它靠这个名字
    把两条臂按 `(ts, ss)` 配上对，且 run 目录固定取 `<leaf>/seed<ts>`。
    """
    return ROOT / f"{arm}_ts{t}_ss{s}"


def build_args(base: dict, arm: str, t: int, s: int) -> dict:
    """基线 + 唯一覆盖 + 记账键（`seed`/`split_seed`/`out_dir`/`overwrite`）。"""
    args = dict(base)
    args.update(override_of(arm, base, s))
    args["seed"] = t               # 训练种子：初始化 / dropout / 打乱 / DropEdge
    args["split_seed"] = s         # 划分种子：读 split_seed{S}.json
    args["out_dir"] = str(leaf_dir(arm, t, s))
    args["overwrite"] = False
    return args


# --------------------------------------------------------------- 开跑前断言

def check_artifacts(base: dict, split_seeds=(0, 1, 2)) -> list[str]:
    """**产物层**单变量：冻结树与正典树逐图比对，三通道相同、CodeBERT 两通道全不同。

    为什么值得在开跑前做：`graph_dir` 一换，训练侧看到的是一整套文件。
    只断言"命令行差一个键"并不能证明**磁盘上**差的也只有 `_cb.pt`——
    变体构建脚本若悄悄多改了别的东西，本断言是唯一能拦住它的地方。
    证据藏在 `_feat.pt` schema v2 自带的 `meta.channel_sha256`（struct/type_id/sv）
    与 `meta.cb_sha256`（cb_func/cb_node）里，故无需重算张量、逐文件读 meta 即可（590 图）。

    🔴 **2026-09-25 改了比较对象**：原设计比「正典 vs `graph_variants/cb_ft_ss{S}` 副本树」，
    但 §37 之后正典自己就是微调树 ⇒ 那个比较退化成"微调 vs 微调"，**证明不了本研究要证的事**。
    现在比「**冻结树** `…/<语料>/graphs` ↔ **正典树**」，这才是"冻结 vs 微调"的单变量证据。
    ⚠ 正典树逐划分种子一套，故仍按 `split_seeds` 循环取 `…/cb_ft_ss{S}`（经 `canonical_args` 模板化）。
    """
    import torch  # 局部 import：只在本断言需要

    frozen = run_ablation.frozen_graphs_of(base)
    canon_tmpl = run_ablation.canonical_args(BASE_CONFIG)["graph_dir"]     # `…/cb_ft_ss{seed}`
    bad: list[str] = []
    for ss in split_seeds:
        canon = Path(canon_tmpl.format(seed=ss)).resolve()
        if not canon.is_dir():
            bad.append(f"{canon} 不存在")
            continue
        frozen_feats = sorted(frozen.glob("*_feat.pt"))
        canon_feats = sorted(canon.glob("*_feat.pt"))
        if len(canon_feats) != len(frozen_feats):
            bad.append(f"正典(ss{ss}) 图数 {len(canon_feats)} != 冻结 {len(frozen_feats)}")
            continue

        sym_bad, ch_same, cb_diff, n = [], 0, 0, 0
        for f in canon_feats:
            # 结构侧必须是软链（复用冻结树，不是拷贝）——拷贝会让"结构未变"失去可证性
            for suffix in ("_pyg.pt", "_m1.json", "_hetero.json"):
                p = canon / f.name.replace("_feat.pt", suffix)
                if p.exists() and not p.is_symlink():
                    sym_bad.append(f"{p.name}({suffix})")
            cm = torch.load(f, map_location="cpu")["meta"]
            fm = torch.load(frozen / f.name, map_location="cpu")["meta"]
            n += 1
            if cm["channel_sha256"] == fm["channel_sha256"]:
                ch_same += 1
            if cm["cb_sha256"] != fm["cb_sha256"]:
                cb_diff += 1

        if sym_bad:
            bad.append(f"正典(ss{ss}) 有 {len(sym_bad)} 个结构文件不是软链，例：{sym_bad[:3]}")
        if ch_same != n:
            bad.append(f"正典(ss{ss}) 三通道相同的图只有 {ch_same}/{n}（应为 {n}）")
        if cb_diff != n:
            bad.append(f"正典(ss{ss}) CodeBERT 通道不同的图只有 {cb_diff}/{n}（应为 {n}）")
    return bad


def preflight(pairs: list[tuple[int, int]], artifact_check: bool = True) -> None:
    """单变量 + 同语料 + 产物层，三条断言一次验完；不通过就退出、不跑。"""
    base = load_base()
    print(f"{'pair':7s} {'层':6s} 断言")
    print("-" * 78)
    bad: list[str] = []

    for t, s in pairs:
        fargs = build_args(base, "frozen", t, s)
        cargs = build_args(base, "cbft", t, s)

        # 1) 单变量：每臂相对正典恰差 override 的那一个键（冻结臂恰差 0 个）
        for arm, a in (("frozen", fargs), ("cbft", cargs)):
            ov = override_of(arm, base, s)
            # ⚠ 逐键剔除「覆盖值**恰等于**基线值」的那些（按解析后的绝对路径比）。
            #   成因：`cbft` 取的就是正典树本身，故 **ss=0 时它与基线逐字相同**，不构成"变化"；
            #   若不剔除，`verify_single_variable` 会判「预期覆盖的键未生效」而误报。
            #   与 `run_arch_baselines.py:96`（`if str(base.get("graph_dir")) != gdir`）同一处理。
            expected = {k: v for k, v in ov.items()
                        if k not in base
                        or str(Path(str(v)).resolve()) != str(Path(str(base[k])).resolve())}
            v = run_ablation.verify_single_variable(base, a, expected)
            flag = "（无，基线臂）" if arm == BASELINE_CFG else f"--graph-dir {Path(a['graph_dir']).name}"
            print(f"{t}:{s:<5d} {'单变量':6s} {arm:7s} {flag:34s} "
                  f"{'✅' if not v else '❌ ' + v[0]}")
            if v:
                bad.append(f"{arm} {t}:{s} 单变量 → {v}")

        # 2) 同语料：两臂的语料键 + 配对键必须逐字相同（graph_dir 是变量，刻意不在其中）
        mism = [k for k in CORPUS_KEYS + PAIR_KEYS if fargs.get(k) != cargs.get(k)]
        print(f"{t}:{s:<5d} {'同语料':6s} frozen ↔ cbft{'':22s} "
              f"{'✅' if not mism else '❌ ' + str(mism)}")
        if mism:
            bad.append(f"{t}:{s} 同语料 → {mism}")

    # 3) 产物层：只做一次（与 pair 无关，只取决于 split_seed）
    if artifact_check:
        art = check_artifacts(base)
        print(f"{'产物层':7s} {'':6s} _feat 三通道相同 / _cb 全不同 / 结构软链 "
              f"{'✅' if not art else '❌ ' + art[0]}")
        bad += art
    else:
        print("⚠ 产物层断言已跳过（--skip-artifact-check）：命令行单变量成立，但磁盘上是否只差 "
              "_cb.pt 未验")

    if bad:
        raise SystemExit("\n[cbft] 预检未通过，已中止（不跑）：\n  " + "\n  ".join(bad))
    print()


def canon_std_micro05() -> float | None:
    """当前正典 `runs/seed{0,1,2}` 的 test micro@0.5 **种子间标准差**（总体 std，n=3）。

    🔴 原实现是写死的 `CANON_STD_MICRO05 = 0.0309`（2026-09-25 之前那一代正典的实测值）。
    编码器换代后这个常数**语义即失效**——门槛会偏松或偏紧，而它决定"重跑抖动算不算异常"，
    是个**判决阈值**。故改为现算；正典未跑齐或字段缺失时返回 `None`，
    调用方降级为"不判噪声级"并**明说**，绝不静默套用一个过期门槛。
    """
    vals: list[float] = []
    for s in (0, 1, 2):
        p = REPO / "runs" / f"seed{s}" / "results.json"
        if not p.exists():
            return None
        try:
            vals.append(json.loads(p.read_text(encoding="utf-8"))["test"]["fixed_0.5"]["micro_f1"])
        except (KeyError, json.JSONDecodeError):
            return None
    m = sum(vals) / len(vals)
    return (sum((v - m) ** 2 for v in vals) / len(vals)) ** 0.5


def check_repro() -> list[str]:
    """复现性对拍：`cbft` 臂对角 (s,s) ↔ 正典 `runs/seed{s}` —— 度量**重跑抖动**。

    🔴 **本函数的最初设计是错的，此处按实测更正（2026-09-19）**：
    原设想"(0,0)/(1,1)/(2,2) 与正典配置相同 ⇒ 应逐位相同"，实测**不成立**。原因不是代码改动，
    而是 **GPU 非确定性**：本仓主实验**不带 `--deterministic`**（`train.py:260` 注明"非主实验默认"），
    RGCN 的 scatter/index_add 在 CUDA 上归约顺序不定，故 `loss` 从 epoch 0 起就有 ~1e-9 的差异；
    该差异经训练被混沌放大，**早停落在不同 epoch**（实测 ts0_ss0：新 21 epoch / 正典 14 epoch，
    best epoch 15 vs 8）。⇒ **同配置重跑 ≠ 逐位复现，而是带一层"重跑噪声"。**

    故本函数的正确用法是**量化**这层噪声（它对论文的局限陈述有独立价值），
    只在 |Δ| 远超正典种子间 std 时才判为"疑似真改了取值"而非噪声。

    🔴 **2026-09-25 换了比较对象**：`cbft` 臂现在**直接取正典树**（见 `override_of`），
    故 `cbft_ts{s}_ss{s}` 与 `runs/seed{s}` 是**同配置的两次运行** —— 这正是"重跑抖动"的定义。
    （原实现比的是 `frozen` 臂；在那之前 frozen 因漂移而等于正典，故也能测抖动，
    修好漂移后它变成"冻结 vs 微调"，拿它测抖动就没有意义了。）
    """
    bad: list[str] = []
    noise: list[float] = []
    std = canon_std_micro05()
    if std is None:
        print("⚠ 正典 runs/seed{0,1,2} 未跑齐 ⇒ 无法现算种子间 std，本次**不判**噪声级\n")
    for s in (0, 1, 2):
        a = ROOT / f"cbft_ts{s}_ss{s}" / f"seed{s}" / "results.json"
        b = REPO / "runs" / f"seed{s}" / "results.json"
        if not a.exists() or not b.exists():
            print(f"cbft_ts{s}_ss{s} ↔ runs/seed{s}  — 未跑（跳过）")
            continue
        da = json.loads(a.read_text(encoding="utf-8"))["test"]
        db = json.loads(b.read_text(encoding="utf-8"))["test"]
        d = abs(da["fixed_0.5"]["micro_f1"] - db["fixed_0.5"]["micro_f1"])
        noise.append(d)
        if std is None:
            print(f"cbft_ts{s}_ss{s} ↔ runs/seed{s}  Δmicro@0.5 = {d:.4f}（无现算门槛可比）")
            continue
        verdict = "噪声级" if d < std else "⚠ 超过正典种子间 std，须查因"
        print(f"cbft_ts{s}_ss{s} ↔ runs/seed{s}  Δmicro@0.5 = {d:.4f}"
              f"（正典种子间 std {std:.4f}，现算）→ {verdict}")
        if d >= 3 * std:
            bad.append(f"cbft_ts{s}_ss{s}: Δmicro@0.5={d:.4f}，远超种子间 std，疑似取值改动而非噪声")
    if noise:
        print(f"重跑抖动实测：n={len(noise)}，|Δmicro@0.5| = "
              f"{min(noise):.4f}–{max(noise):.4f}（均值 {sum(noise)/len(noise):.4f}）")
    return bad


# --------------------------------------------------------------- 主循环

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only-pairs", default="", help="只跑这些对，如 `0:0,1:2`。")
    ap.add_argument("--dry-run", action="store_true", help="只断言 + 打印命令行，不执行。")
    ap.add_argument("--keep-going", action="store_true", help="单个 run 失败后继续。")
    ap.add_argument("--evaluate-only", action="store_true",
                    help="跳过训练，只重跑 evaluate.py（+diagnose.py）；零重训。")
    ap.add_argument("--skip-artifact-check", action="store_true",
                    help="跳过产物层断言（读 590×2 个 _feat.pt，约 30–60 s）。")
    ap.add_argument("--check-repro", action="store_true",
                    help="跑完后对拍：冻结臂 (s,s) 与正典 runs/seed{s}，量化「重跑抖动」"
                         "（GPU 非确定性，**不为零**；只在远超种子间 std 时才判为异常）。")
    args = ap.parse_args()

    pairs = PAIRS
    if args.only_pairs:
        pairs = [tuple(int(v) for v in p.split(":")) for p in args.only_pairs.split(",")]

    print(f"[cbft] 根目录 {ROOT}；{len(ARMS)} 臂 × {len(pairs)} 对 = {len(ARMS) * len(pairs)} 个 run；"
          f"dry_run={args.dry_run}\n")

    preflight(pairs, artifact_check=not args.skip_artifact_check)

    if args.dry_run:
        base = load_base()
        for arm in ARMS:
            for t, s in pairs:
                a = build_args(base, arm, t, s)
                print(f"[{arm} {t}:{s}] → {leaf_dir(arm, t, s)}/seed{t}")
                if not args.evaluate_only:
                    print("   [train] " + " ".join(run_ablation.argv_for_train(a)[2:]))
                print("   [eval]  " + " ".join(run_ablation.argv_for_eval(a)[2:]))
                print("   [diag] " + " ".join(run_study.argv_for_diagnose(a)[2:]))
        print(f"\n[cbft] dry-run 结束：{len(ARMS) * len(pairs)} 个 run"
              f"（evaluate_only={args.evaluate_only}）")
        return

    failures: list[tuple[str, str]] = []
    t0 = time.perf_counter()
    for arm in ARMS:
        for t, s in pairs:
            tag = f"{arm}/{t}:{s}"
            a = build_args(load_base(), arm, t, s)
            run_seed_dir = leaf_dir(arm, t, s) / f"seed{t}"
            state = run_ablation.resume_state(run_seed_dir)
            if state == "done" and not args.evaluate_only:
                print(f"[{tag}] 跳过：results.json 已存在（要重跑请先归档该目录）", flush=True)
                continue
            if args.evaluate_only and not (run_seed_dir / "best.pt").exists():
                print(f"[{tag}] 跳过：--evaluate-only 但无 best.pt", flush=True)
                continue
            steps = [] if (args.evaluate_only or state == "eval") \
                else [("train", run_ablation.argv_for_train(a))]
            steps.append(("eval", run_ablation.argv_for_eval(a)))
            steps.append(("diagnose", run_study.argv_for_diagnose(a)))
            for name, argv in steps:
                r = subprocess.run(argv, cwd=REPO, capture_output=True, text=True)
                if r.returncode != 0:
                    tail = (r.stderr or r.stdout or "")[-600:]
                    print(f"[{tag}] ❌ {name} 失败：\n{tail}", flush=True)
                    failures.append((f"{tag}/{name}", tail))
                    break
                last = r.stdout.strip().splitlines()[-1][:110] if r.stdout.strip() else ""
                print(f"[{tag}] {name} ok  {last}", flush=True)
            else:
                # 训练产物 `last.pt` 只在断点续训时有用，按既有惯例剪除（`run_ablation` 同）
                (run_seed_dir / "last.pt").unlink(missing_ok=True)
                continue
            if not args.keep_going:
                break

    wall = time.perf_counter() - t0
    print(f"\n[cbft] 结束：{len(ARMS) * len(pairs)} 个 run，wall {wall:.1f}s，失败 {len(failures)}")

    # 对拍放在跑完之后：它读的是本次刚产出的 results.json
    if args.check_repro:
        print("\n[cbft] 重跑抖动对拍（冻结臂 (s,s) ↔ 正典 runs/seed{s}）：")
        bad = check_repro()
        if bad:
            raise SystemExit("\n[cbft] 对拍异常，须查因：\n  " + "\n  ".join(bad))

    if failures:
        raise SystemExit(f"[cbft] 有 {len(failures)} 处失败：{[f[0] for f in failures]}")


if __name__ == "__main__":
    main()
