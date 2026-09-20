#!/usr/bin/env python3
"""构造消融用的**图变体目录**（`ablation_plan.md` §6.1 / §6.3 / §6.4）。

三个变体各自"缺什么补什么"，**其余全部软链复用**——这是让「唯一变量」在**产物层面**
也成立的做法：变体目录里凡是软链的东西，物理上与正典是同一个文件，不可能是第二个变量。

| 变体 | 真产物 | 软链复用 | 唯一变量 |
| --- | --- | --- | --- |
| `callback_rev` | `_hetero.json`、`_pyg.pt`、`_feat.pt`(重算后**断言与正典逐位相同**) | `_m1.json`、`_cb.pt` | 多一类**反向关系** CALLBACK_RISK_REV |
| `callback_unlimited` | `_hetero.json`、`_m1.json`、`_pyg.pt`、`_feat.pt` | `_cb.pt` | CALLBACK_RISK 出边**上限 4 → 不限** |
| `cb_ft_ss{S}` | `_cb.pt`(新编码器)、`_feat.pt`(断言与正典逐位相同) | `_hetero.json`、`_m1.json`、`_pyg.pt` | CodeBERT **微调后**重编码 |

**为什么 `callback_rev` 也要真算一遍 `_feat.pt` 而不是直接软链**：设计上的论据是
"`priori_scoring` 只读 `CFG_FLOW` 与 `CALLBACK_RISK` 两个键，REV 写在第三个键下所以 M1 看不见它"。
但这只是**读代码得到的假设**——真正能证明"M1 确实没看见"的，是**算一遍再逐位比对**。
多花约 40 秒，把假设换成事实（`_cb.pt` 已软链，M3 不加载 CodeBERT）。

⚠ 每个变体目录都写 `variant.json` **自述文件**：`train.py` 的守卫只能看到 `--graph-dir`
换了个路径，**看不到那个目录里装的是什么**——这正是"看起来是消融、其实不是"能藏身的地方。

用法（从仓库根目录运行）：
  python scripts/build_graph_variant.py --variant callback_rev --dataset alldata
  python scripts/build_graph_variant.py --variant cb_ft --dataset alldata --split-seed 0

产物：`products/<数据集>/graph_variants/<变体>/`（`cb_ft` 带 `_ss{S}` 后缀）。
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import run_guard                                                        # noqa: E402

# 数据集 → 输入路径。`src_root` 是 M2 解析源码用的根（与产物里的 meta.source_path 同源）。
DATASETS = {
    "alldata": {
        "raw": "products/alldata/raw",
        "graphs": "products/alldata/graphs",
        "variants": "products/alldata/graph_variants",
        "src_root": "alldata(readonly)/alldata_sol_source",
    },
    "augmentation": {
        "raw": "products/augmentation/raw",
        "graphs": "products/augmentation/graphs",
        "variants": "products/augmentation/graph_variants",
        "src_root": "alldata_augmentation/sol_source",
    },
}
VARIANTS = ("callback_rev", "callback_unlimited", "cb_ft")
CHANNELS = ("func", "node")

# 冻结 IR 类别字典 = **跨语料语义锚点**（AGENTS.md「数据边界」）。**①②的正典用的都是这一份**：
#   - ① 自己的 `products/alldata/graphs/ir_cat.json` 就是它；
#   - ② 的 graphs 目录里**没有** `ir_cat.json`，且其 `m3_gpu.log` 里**没有**"categories 不存在 →
#     回退全库扫描"的 WARNING ⇒ 它当初传的就是这份（若是就地扫描，`write_categories` 会落盘）。
# 2026-09-18 实测：拿 ② 自己的 1774 张图重扫，`ir_categories` 与 `call_modes` 与这份**逐项相同**
# （扫描节点数 463264 亦与 AGENTS.md 记载相符），故"传锚点"与"就地重扫"**数值等价**。
# 但仍显式传锚点，理由有二：① 去掉 m3 那句 WARNING 并在变体目录里少落一个多余文件；
# ② 与"正典到底是怎么建的"保持一致——变体的单变量性依赖这一点，不能靠"恰好等价"。
FROZEN_IR_CAT = REPO / "products" / "alldata" / "graphs" / "ir_cat.json"


def frozen_categories() -> Path:
    """冻结 IR 字典路径（带存在性硬校验：缺了就让 m3 静默重扫 = 语义锚点漂移）。"""
    if not FROZEN_IR_CAT.exists():
        raise SystemExit(
            f"[variant] 🔴 找不到冻结 IR 字典 {FROZEN_IR_CAT}；"
            f"它是跨语料语义锚点，缺了 m3 会**静默回退全库扫描**（只打一行 WARNING），"
            f"IR 列宽/类别语义可能漂移。请先恢复该文件。")
    return FROZEN_IR_CAT


def run(argv: list[str], label: str) -> None:
    """跑一步并回显耗时；失败即中止（变体目录半成品没有任何价值，宁可早停）。"""
    t0 = time.perf_counter()
    proc = subprocess.run(argv, cwd=REPO, capture_output=True, text=True)
    tail = "\n".join((proc.stdout or proc.stderr or "").strip().splitlines()[-3:])
    print(f"  [{label}] {'✓' if proc.returncode == 0 else '✗'} "
          f"{time.perf_counter() - t0:.1f}s  {tail}", flush=True)
    if proc.returncode != 0:
        raise SystemExit(f"[variant] {label} 失败（退出码 {proc.returncode}）：\n"
                         f"{(proc.stderr or proc.stdout)[-3000:]}")


def link(src: Path, dst: Path) -> None:
    """软链。用**相对路径**（`os.path.relpath` 算），使变体目录整体可搬移、且不依赖绝对前缀。"""
    dst.unlink(missing_ok=True)
    dst.symlink_to(os.path.relpath(src.resolve(), dst.parent.resolve()))


def load_channels(feat_path: Path):
    """`_feat.pt` 的三通道张量（structure 类型/结构/sv）。"""
    payload = torch.load(feat_path, map_location="cpu")
    return {k: payload[k] for k in ("struct", "type_id", "sv") if k in payload}


def assert_feat_identical(variant_dir: Path, canon_dir: Path, expect_same: bool,
                          graph_names: list[str], label: str) -> dict:
    """变体 `_feat.pt` 与正典**逐图逐张量**比对（这是"唯一变量"的机器证明）。

    返回 `{"same": …, "diff": …, "total": …}`——**返回值不是可有可无的**：调用方要把它写进
    `variant.json`。原先只打印不返回，于是审计记录里只剩一句「已断言」，没有一个数字
    （`callback_rev` 第一版就是这样，事后不得不从产物反推补写）。
    """
    same = diff = 0
    for name in graph_names:
        a = load_channels(variant_dir / f"{name}_feat.pt")
        b = load_channels(canon_dir / f"{name}_feat.pt")
        if set(a) != set(b) or any(not torch.equal(a[k], b[k]) for k in a):
            diff += 1
        else:
            same += 1
    # `expect_same=True`（cb_rev / cb_ft）→ **每一张都必须逐位相同**（多一张不同就是动了不该动的通道）。
    # `expect_same=False`（cb_unlimited）→ **至少要有图变了**（否则这个开关是空操作），
    #   ⚠ **不能要求"每张都变"**：`--callback-limit` 只截断**出边多于上限**的源节点，
    #   全库只有约 70 个节点被截断，故绝大多数图本就不该变（实测主库 20/590 变）。
    #   第一版把判据写成"全部都要变"，于是把一次**正确**的构建判成了失败——判据写反
    #   与判据太松一样危险。
    ok = (diff == 0) if expect_same else (diff > 0)
    verb = ("逐位相同（逐图，全部）" if expect_same
            else "**必须至少有一张不同**（部分不同 = 正常）")
    print(f"  [{label}] _feat.pt vs 正典 {verb}：{same} 同 / {diff} 异 "
          f"{'✓' if ok else '✗'}", flush=True)
    if not ok:
        raise SystemExit(
            f"[variant] {label}: _feat.pt 比对失败（{same} 同 / {diff} 异）——"
            + ("说明变体动了不该动的通道，本项将不再是单变量消融。" if expect_same
               else "一张都没变，说明这个开关在当前语料上是**空操作**，跑它没有意义。"))
    return {"same": same, "diff": diff, "total": len(graph_names)}


def edge_stats(vdir: Path, graphs: Path, names: list[str]) -> dict:
    """变体 vs 正典的 CALLBACK_RISK 边账（`ablation_plan.md` §6.1 的本项特有验收）。

    判据有两条，缺一不可：
      - 变体总边数 **严格 ≥** 正典（`--callback-limit 0` 只会**多**建边，不会少）；
      - 正典里 `callback_truncated_candidates > 0` 的图，在变体里必须 **= 0**。
    只看总数不够：总数相等也可能是"这里多、那里少"，而后者说明变了别的规则。
    """
    total_c = total_v = trunc_c = trunc_v = changed = 0
    for name in names:
        c = json.loads((graphs / f"{name}_hetero.json").read_text(encoding="utf-8"))["meta"]
        v = json.loads((vdir / f"{name}_hetero.json").read_text(encoding="utf-8"))["meta"]
        total_c += c.get("callback_risk_edge_count", 0)
        total_v += v.get("callback_risk_edge_count", 0)
        trunc_c += c.get("callback_truncated_candidates", 0)
        trunc_v += v.get("callback_truncated_candidates", 0)
        changed += int(v.get("callback_risk_edge_count", 0) != c.get("callback_risk_edge_count", 0))
    out = {"callback_edges_canon": total_c, "callback_edges_variant": total_v,
           "truncated_canon": trunc_c, "truncated_variant": trunc_v,
           "graphs_with_more_edges": changed}
    ok = total_v >= total_c and trunc_v == 0
    print(f"  [cb_unlimited] CALLBACK_RISK 边 {total_c} → {total_v}"
          f"（{changed}/{len(names)} 张图有变化）；截断候选 {trunc_c} → {trunc_v} "
          f"{'✓' if ok else '✗'}", flush=True)
    if not ok:
        raise SystemExit(f"[variant] callback_unlimited 边账不达标：{out}")
    return out


def write_variant_json(vdir: Path, payload: dict) -> None:
    payload = {"created": time.strftime("%Y-%m-%d"), **payload}
    (vdir / "variant.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def rev_edge_stats(vdir: Path, names: list[str]) -> dict:
    """`CALLBACK_RISK_REV` 是不是 `CALLBACK_RISK` 的**精确镜像**——逐图计数比对。

    这是本项唯一变量的直接证据：反向边**不多不少**，且关系数确实 5→6。
    只断言 `_feat.pt` 相同是不够的——那只能证明 M1/M3 没看见 REV，
    **不能**证明 REV 本身建对了（一条都没建出来时它同样"逐位相同"）。
    """
    fwd = rev = 0
    exact = 0
    for name in names:
        meta = json.loads((vdir / f"{name}_hetero.json").read_text(encoding="utf-8"))["meta"]
        f, r = meta.get("callback_risk_edge_count", 0), meta.get("callback_rev_edge_count", 0)
        fwd += f
        rev += r
        exact += int(f == r)
    return {"callback_edges_fwd": fwd, "callback_edges_rev": rev,
            "graphs_with_exact_mirror": exact, "graphs_total": len(names)}


def build_callback_rev(ds: dict, vdir: Path, force: bool) -> None:
    """§6.3：多一类反向关系（关系数 5→6）。**M1 与 M3 的语义通道都不受影响**。"""
    graphs, raw = Path(ds["graphs"]), Path(ds["raw"])
    print(f"[variant] callback_rev → {vdir}", flush=True)
    run([sys.executable, "scripts/build_cfg_centered_hetero_graph.py",
         "--ast-dir", f"{raw}/AST-raw", "--cfg-dir", f"{raw}/CFG-raw",
         "--dfg-dir", f"{raw}/DFG-raw", "--src-root", ds["src_root"],
         "--out-dir", str(vdir), "--callback-rev"], "M2")
    run([sys.executable, "scripts/convert_hetero_json_to_pyg.py",
         "--in-dir", str(vdir), "--out-dir", str(vdir)], "PyG")
    names = sorted(p.name[: -len("_hetero.json")] for p in vdir.glob("*_hetero.json"))
    for name in names:                                  # M1 的输入（REV 不在它读的键里）
        link(graphs / f"{name}_m1.json", vdir / f"{name}_m1.json")
        link(graphs / f"{name}_cb.pt", vdir / f"{name}_cb.pt")
    run([sys.executable, "scripts/m3_build_features.py",
         "--in-dir", str(vdir), "--out-dir", str(vdir), "--m1-dir", str(vdir),
         "--categories", str(frozen_categories()), "--device", "cuda"], "M3")
    feat = assert_feat_identical(vdir, graphs, expect_same=True, graph_names=names, label="cb_rev")
    stats = rev_edge_stats(vdir, names)
    if stats["graphs_with_exact_mirror"] != stats["graphs_total"] or stats["callback_edges_rev"] == 0:
        raise SystemExit(f"[variant] cb_rev 的镜像不成立（{stats}）——"
                         f"REV 必须是 CALLBACK_RISK 的逐图精确反向，且不得为空。")
    print(f"  [cb_rev] 镜像逐图成立 {stats['graphs_with_exact_mirror']}/{stats['graphs_total']}；"
          f"正向边 {stats['callback_edges_fwd']} == 反向边 {stats['callback_edges_rev']} ✓", flush=True)
    write_variant_json(vdir, {
        "variant": "callback_rev", "derived_from": str(graphs),
        "only_variable": "edges += CALLBACK_RISK_REV（CALLBACK_RISK 的精确镜像）",
        "commands": ["build_cfg_centered_hetero_graph.py --callback-rev",
                     "convert_hetero_json_to_pyg.py", "m3_build_features.py"],
        "reuse": {"_m1.json": "symlink", "_cb.pt": "symlink",
                  "splits": "products/<数据集>/splits（复用，不重建）"},
        "expect": {"num_relations": 6,
                   "_feat.pt": f"与正典逐位相同（{feat['same']}/{feat['total']} 图）",
                   "edge_stats": stats},
    })


def build_callback_unlimited(ds: dict, vdir: Path, force: bool) -> None:
    """§6.1：CALLBACK_RISK 出边上限 4 → 不限。**`_feat.pt` 必须变**（+0.5 先验命中集变大）。"""
    graphs, raw = Path(ds["graphs"]), Path(ds["raw"])
    print(f"[variant] callback_unlimited → {vdir}", flush=True)
    run([sys.executable, "scripts/build_cfg_centered_hetero_graph.py",
         "--ast-dir", f"{raw}/AST-raw", "--cfg-dir", f"{raw}/CFG-raw",
         "--dfg-dir", f"{raw}/DFG-raw", "--src-root", ds["src_root"],
         "--out-dir", str(vdir), "--callback-limit", "0"], "M2")
    run([sys.executable, "scripts/m1_runner.py",
         "--in-dir", str(vdir), "--out-dir", str(vdir)], "M1")
    run([sys.executable, "scripts/convert_hetero_json_to_pyg.py",
         "--in-dir", str(vdir), "--out-dir", str(vdir)], "PyG")
    names = sorted(p.name[: -len("_hetero.json")] for p in vdir.glob("*_hetero.json"))
    for name in names:
        link(graphs / f"{name}_cb.pt", vdir / f"{name}_cb.pt")
    run([sys.executable, "scripts/m3_build_features.py",
         "--in-dir", str(vdir), "--out-dir", str(vdir), "--m1-dir", str(vdir),
         "--categories", str(frozen_categories()), "--device", "cuda"], "M3")
    feat = assert_feat_identical(vdir, graphs, expect_same=False, graph_names=names, label="cb_unlimited")
    stats = edge_stats(vdir, graphs, names)
    write_variant_json(vdir, {
        "variant": "callback_unlimited", "derived_from": str(graphs),
        "only_variable": "CALLBACK_RISK 每源节点出边上限 4 → 0(=不限)",
        "commands": ["build_cfg_centered_hetero_graph.py --callback-limit 0",
                     "m1_runner.py", "convert_hetero_json_to_pyg.py", "m3_build_features.py"],
        "reuse": {"_cb.pt": "symlink", "splits": "products/<数据集>/splits（复用，不重建）"},
        "expect": {"callback_limit": 0, "expected_default": 4,
                   "_feat.pt": f"部分图与正典不同（{feat['diff']}/{feat['total']} 图有变化）",
                   "edge_stats": stats},
    })


def default_encoder_dir(graphs_dir: Path, split_seed: int) -> Path:
    """微调编码器的默认位置：`runs/codebert_ft/<语料>/ss{S}/encoder`。

    ⚠ **必须带语料维度**（2026-09-18 修）：原先是 `runs/codebert_ft/ss{S}/encoder`，
    ①②两个语料**共用同一个路径**。而队列是先 `main` 后 `aug`，于是 `aug` 那一步会看到
    `main` 留下的编码器而**跳过微调**，接着拿**①训练出的编码器**去重编码**②增强集**——
    产物齐全、`_cb.pt` 确实与原版不同（`assert_feat_identical` 与反向抽样都会通过），
    **全程不报错**，只是这项消融答的根本不是它要问的问题。
    与 §28 `.ravel()`、§29.4 标签源同类：错误不体现在崩溃上，而体现在"数字看着挺正常"。
    故路径按语料隔离，并在 `build_cb_ft` 里对边车做**硬校验**（见下）。
    """
    corpus = Path(graphs_dir).resolve().parent.name          # products/<语料>/graphs → <语料>
    return REPO / "runs" / "codebert_ft" / corpus / f"ss{split_seed}" / "encoder"


def build_cb_ft(ds: dict, vdir: Path, encoder: Path, split_seed: int, force: bool) -> None:
    """§6.4：用**微调后**的编码器重跑 M3。结构三通道必须逐位不变。"""
    graphs = Path(ds["graphs"])
    print(f"[variant] cb_ft_ss{split_seed} → {vdir}（编码器 {encoder}）", flush=True)
    if not (encoder / "config.json").exists():
        raise SystemExit(f"[variant] 找不到微调编码器 {encoder}；先跑 scripts/finetune_codebert.py")
    # 🔴 语料归属硬校验：跨语料套用编码器**不会报错**，只会静默产出一个错误的消融。
    want = Path(graphs).resolve().parent.name
    marker = encoder / "corpus.json"
    if not marker.exists():
        raise SystemExit(
            f"[variant] 🔴 编码器 {encoder} 缺 `corpus.json` 边车，无法确认它属于哪个语料。\n"
            f"  该边车由 2026-09-18 之后的 `finetune_codebert.py` 写出；请重建编码器"
            f"（旧编码器一律作废，不要手工补边车）。")
    got = json.loads(marker.read_text(encoding="utf-8"))
    if got.get("corpus") != want:
        raise SystemExit(
            f"[variant] 🔴 编码器与语料不匹配：{encoder} 是用「{got.get('corpus')}」微调的，"
            f"本变体属于「{want}」。\n"
            f"  跨语料套用不会报错，只会静默产出一个'看起来正常'的错误消融——故此处硬失败。\n"
            f"  重跑：bash scripts/run_remaining_ablations.sh {'main' if want == 'alldata' else 'aug'}")
    names = sorted(p.name[: -len("_hetero.json")] for p in graphs.glob("*_hetero.json"))
    for name in names:                                  # 结构侧全部复用：本项**只准**动 _cb.pt
        for suffix in ("_hetero.json", "_m1.json", "_pyg.pt"):
            link(graphs / f"{name}{suffix}", vdir / f"{name}{suffix}")
    run([sys.executable, "scripts/m3_build_features.py",
         "--in-dir", str(vdir), "--out-dir", str(vdir), "--m1-dir", str(vdir),
         "--categories", str(frozen_categories()), "--codebert", str(encoder),
         "--device", "cuda"], "M3(微调编码器)")
    feat = assert_feat_identical(vdir, graphs, expect_same=True, graph_names=names, label="cb_ft")
    # "反向验收"：编码器若没生效，_cb.pt 会与原版逐位相同——那才是失败。
    # ⚠ **必须全量比对，不能抽样**（2026-09-18 改）：原先只查 `names[:40]`，而同一函数里
    #   `assert_feat_identical` 是**全量**的——两侧证据强度不对称。更关键的是，这一条是
    #   "编码器确实生效"的**唯一**证据（`_feat.pt` 相同只证明结构没被动，对编码器只字未提），
    #   拿 40/40 去支撑"全库 590 张都换了编码器"是抽样外推，而全量比对的代价只是多读一遍盘。
    changed = 0
    for name in names:
        a = torch.load(vdir / f"{name}_cb.pt", map_location="cpu")
        b = torch.load(graphs / f"{name}_cb.pt", map_location="cpu")
        if any(not torch.equal(a[ch][k], b[ch][k]) for ch in CHANNELS for k in a[ch]):
            changed += 1
    print(f"  [cb_ft] _cb.pt vs 正典（**全量** {len(names)} 图）：不同的有 {changed} 个 "
          f"{'✓' if changed == len(names) else '✗'}", flush=True)
    if changed == 0:
        raise SystemExit("[variant] cb_ft: 变体 `_cb.pt` 与正典完全相同——微调没有生效，"
                         "本项会退化成一次重复实验。")
    if changed != len(names):
        raise SystemExit(f"[variant] cb_ft: 只有 {changed}/{len(names)} 张图的 `_cb.pt` 变了——"
                         f"编码器应当作用于**每一张**图（M3 对全库统一重编码），"
                         f"部分不同说明重编码没跑全，本项不是单变量消融。")
    write_variant_json(vdir, {
        "variant": "cb_ft", "split_seed": split_seed, "derived_from": str(graphs),
        "encoder": str(encoder),
        "only_variable": "CodeBERT 微调后重编码（结构/类型/s_v 三通道逐位不变，已断言）",
        "commands": ["finetune_codebert.py", "m3_build_features.py --codebert <encoder>"],
        "reuse": {"_hetero.json": "symlink", "_m1.json": "symlink", "_pyg.pt": "symlink",
                  "splits": "products/<数据集>/splits（复用，不重建）"},
        "expect": {"_feat.pt": f"与正典逐位相同（{feat['same']}/{feat['total']} 图）",
                   "_cb.pt": f"与正典**不同**（{changed}/{len(names)} 图，全量比对）",
                   "encoder_corpus": got.get("corpus")},
    })


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--variant", required=True, choices=VARIANTS)
    p.add_argument("--dataset", required=True, choices=sorted(DATASETS))
    p.add_argument("--split-seed", type=int, default=0, help="仅 cb_ft 用（每种子一套编码器）。")
    p.add_argument("--encoder", default=None,
                   help="仅 cb_ft 用；默认 runs/codebert_ft/<语料>/ss{S}/encoder（按语料隔离）。")
    p.add_argument("--overwrite", action="store_true",
                   help="允许写入一个**已装有 _hetero.json 的**变体目录（默认拒绝）。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    ds = DATASETS[args.dataset]
    name = f"cb_ft_ss{args.split_seed}" if args.variant == "cb_ft" else args.variant
    vdir = REPO / ds["variants"] / name
    # 与 M2 同构的守卫：变体目录里**只允许**装本次变体的产物，重跑须显式 --overwrite。
    conflict = run_guard.nonempty_out_dir(vdir, "*_hetero.json")
    if conflict and not args.overwrite:
        raise SystemExit(run_guard.guard_message(
            str(vdir), [conflict],
            "变体重建请加 `--overwrite`（本脚本会先清空该目录再重建）。"))
    if vdir.exists():                                   # 只清变体目录本身，**绝不上溯**
        for entry in vdir.iterdir():
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry)
            else:
                entry.unlink()
    vdir.mkdir(parents=True, exist_ok=True)

    t0 = time.perf_counter()
    if args.variant == "callback_rev":
        build_callback_rev(ds, vdir, args.overwrite)
    elif args.variant == "callback_unlimited":
        build_callback_unlimited(ds, vdir, args.overwrite)
    else:
        encoder = Path(args.encoder) if args.encoder else default_encoder_dir(
            Path(ds["graphs"]), args.split_seed)
        build_cb_ft(ds, vdir, encoder, args.split_seed, args.overwrite)
    print(f"[variant] 完成：{vdir}（用时 {time.perf_counter() - t0:.1f}s）", flush=True)


if __name__ == "__main__":
    main()
