#!/usr/bin/env python3
"""构建 **DIVE 外部测试集**的图与特征（大纲 `改II` 5.1 第六条 / 5.2 层次一「跨数据集」）。

**为什么需要它**：`products/dive/` 此前只有抽样清单（`splits/`），`raw/`、`graphs/` 皆空。
消融跑完后要在 DIVE 上做外部测试，就得把同一套 M1–M3 在 DIVE 的 900 张图上跑一遍。
本脚本把这条链固化下来，使产物**可复现、可审计、可重入**（而不是一串口头敲过的命令）。

**抽样协议已冻结**（`sample_dive_subset.py`，`decisions.md` §13）：seed=0、n=900、逐类 support 见
`sample_report.json`。本脚本**不重新抽样**，只消费 `splits/sample_seed0.json` 的 `selected.ids`。

**编码器矩阵（本脚本的核心）**：外部测试用的是**各语料自己微调的编码器**——
① 的模型配 ① 的编码器、② 的模型配 ② 的编码器。但**图结构只有一份**（DIVE 的边/节点与编码器无关），
故布局是「一份结构 + 三套 `_cb.pt`」：

```
products/dive/
  src_stage/                      抽样的 900 个 .sol（从只读源拷入，供 M2 解析源码）
  raw/{AST-raw,CFG-raw,DFG-raw,logs,filter_report.txt}
  graphs/                         结构 + **冻结** CodeBERT 特征（= `cb_frozen` 臂用）
      <base>_{hetero.json,m1.json,pyg.pt,cb.pt,feat.pt}
  graphs_ft/ss{S}/                **① 微调**编码器重编码（结构软链自 graphs/）
  graphs_ft_aug/ss{S}/            **② 微调**编码器重编码
  graphs_ft/graph_variants/{cb_rev,cb_unlimited}_ss{S}/      边变体 × ① 编码器
  graphs_ft_aug/graph_variants/{cb_rev,cb_unlimited}_ss{S}/  边变体 × ② 编码器
```

目录层次与 `products/<语料>/graphs_ft/ss{S}` **逐字对应**，故 `run_ablation.variants_root_of()`
（用「`graph_dir` 的父目录 + `graph_variants`」推导变体根）推出的路径自洽。

🔴 **冻结 IR 字典必须复用**（`products/alldata/graphs/ir_cat.json`）：不传的话 M3 会为 DIVE
就地重扫生成新字典 → IR 列宽/类别语义与训练好的模型不一致（`AGENTS.md`「数据边界」）。
本脚本一律经 `build_graph_variant.frozen_categories()` 取它（缺文件即硬失败）。

**外部测试的三条纪律**（`AGENTS.md` / 大纲）：
  1. DIVE **只读**，绝不写入或改名；
  2. DIVE 不参与任何模型选择——编码器是**别的语料**训练出来的，本脚本不重训、不调参；
  3. 阈值只从**源语料的验证集**取（由 `evaluate_external.py` 从 `runs/*/thresholds.json` 读），
     绝不在 DIVE 上重新搜阈值。

用法（从仓库根目录运行）：
  python scripts/build_dive_external_set.py --steps stage --limit 20   # 小样计时探针
  python scripts/build_dive_external_set.py --steps stage,raw
  python scripts/build_dive_external_set.py --steps graphs,features,variants
  python scripts/build_dive_external_set.py --steps all
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

SPLIT_SEEDS = (0, 1, 2)
# 边变体 → M2 的开关。与 `products/<语料>/graph_variants/` 下的名字逐字一致。
EDGE_VARIANTS = {"cb_rev": ["--callback-rev"], "cb_unlimited": ["--callback-limit", "0"]}
CHANNELS = ("struct", "type_id", "sv")

# ---------------------------------------------------------------------------------------
# 数据集配置（2026-09-20 起本脚本同时服务 DIVE 与 SolidiFI——两者**形态完全一样**：
# 都是"外部语料、要建图+建三套编码器特征、要用冻结 IR 字典"）。差别只有三处，都在下表里。
# ---------------------------------------------------------------------------------------
DATASETS = {
    "dive": {
        "product": "dive",
        "src": REPO / "DIVE" / "Source codes",
        "label": REPO / "DIVE" / "contract_labels.json",
        # 抽样子集清单（DIVE 协议：seed=0/n=900，见 decisions §13）；`None` = 全量
        "sample": REPO / "products" / "dive" / "splits" / "sample_seed0.json",
        "ft_aug": True,          # ② 的特征树另立一棵（DIVE 的编码器矩阵需要）
    },
    "solidifi": {
        "product": "solidifi",
        "src": REPO / "SolidiFI" / "buggy_contracts",
        "label": REPO / "SolidiFI" / "contract_labels.json",
        "sample": None,          # 层次二用**全部 350 个**，不抽样
        "ft_aug": True,
    },
}
DS = "dive"                              # 由 `--dataset` 设置；下面是它的派生路径

DIVE = SRC_STAGE = RAW = GRAPHS = FT_MAIN = FT_AUG = SAMPLE = DIVE_SRC = LABEL_FILE = None
ENCODER_TREES: dict = {}


def use_dataset(name: str) -> None:
    """按数据集名重绑模块级路径常量（`--dataset` 调用；默认 dive 以保持既有行为不变）。"""
    global DS, DIVE, SRC_STAGE, RAW, GRAPHS, FT_MAIN, FT_AUG, SAMPLE, DIVE_SRC, LABEL_FILE, ENCODER_TREES
    if name not in DATASETS:
        raise SystemExit(f"[dive] 未知数据集 {name}；可选 {sorted(DATASETS)}")
    cfg = DATASETS[name]
    DS = name
    DIVE = REPO / "products" / cfg["product"]
    SRC_STAGE = DIVE / "src_stage"
    RAW = DIVE / "raw"
    GRAPHS = DIVE / "graphs"
    FT_MAIN = DIVE / "graphs_ft"          # ① alldata 的微调编码器
    FT_AUG = DIVE / "graphs_ft_aug"       # ② augmentation 的微调编码器
    SAMPLE = cfg["sample"]
    DIVE_SRC = cfg["src"]
    LABEL_FILE = cfg["label"]
    # 语料 → 特征树。键与 `runs/codebert_ft/<语料>/` 对应。
    ENCODER_TREES = {"alldata": FT_MAIN, "augmentation": FT_AUG}


def run(argv: list[str], label: str, env: dict | None = None, quiet: bool = False) -> None:
    """跑一步并回显耗时；失败即中止（半成品没有价值，宁可早停）。"""
    t0 = time.perf_counter()
    proc = subprocess.run(argv, cwd=REPO, capture_output=True, text=True, env=env)
    out = (proc.stdout or "") + (proc.stderr or "")
    tail = "\n".join(out.strip().splitlines()[-3:])
    print(f"  [{label}] {'✓' if proc.returncode == 0 else '✗'} "
          f"{time.perf_counter() - t0:.1f}s  {tail}", flush=True)
    if proc.returncode != 0:
        raise SystemExit(f"[dive] {label} 失败（退出码 {proc.returncode}）：\n{out[-3000:]}")
    if not quiet:
        return


def link(src: Path, dst: Path) -> None:
    """建**相对**软链（相对路径才能让目录整体搬移后仍解析）。"""
    dst.unlink(missing_ok=True)
    dst.symlink_to(os.path.relpath(src.resolve(), dst.parent.resolve()))


def selected_ids(limit: int = 0) -> list[str]:
    """要处理的源文件 stem 列表。

    - 配了 `sample` 的数据集（DIVE）：读抽样清单，`3` → `3.sol`（协议已冻结，**不重抽**）；
    - 没配的（SolidiFI）：**全量**扫源目录（350 个，层次二不抽样）。
    """
    if SAMPLE is None:
        stems = sorted(p.stem for p in DIVE_SRC.glob("*.sol"))
    else:
        stems = [str(i) for i in json.loads(SAMPLE.read_text(encoding="utf-8"))["selected"]["ids"]]
    return stems[:limit] if limit else stems


# --------------------------------------------------------------------------- 1. stage
def step_stage(limit: int = 0) -> None:
    """把抽样的源文件拷入 `src_stage/`（只读源 → 可写产物区；**只读不改源**）。

    ⚠ 必须**拷贝**而不是就地指 `DIVE/Source codes`：`generate_all_ast_cfg_dfg.sh` 会
    `find "$SRC_ROOT" -name '*.sol'` 扫全部 22330 个文件，而协议只要 900 个。
    """
    ids = selected_ids(limit)
    SRC_STAGE.mkdir(parents=True, exist_ok=True)
    missing = [i for i in ids if not (DIVE_SRC / f"{i}.sol").exists()]
    if missing:
        raise SystemExit(f"[dive] 源目录缺 {len(missing)} 个文件，例：{missing[:5]}")
    copied = reused = 0
    for i in ids:
        src, dst = DIVE_SRC / f"{i}.sol", SRC_STAGE / f"{i}.sol"
        if dst.exists() and dst.stat().st_size == src.stat().st_size:
            reused += 1
            continue
        shutil.copy2(src, dst)
        copied += 1
    print(f"[dive] stage：{len(ids)} 个源文件 → {SRC_STAGE}（新拷 {copied} / 复用 {reused}）", flush=True)


# --------------------------------------------------------------------------- 2. raw
def step_raw() -> None:
    """M1/M2 前端：Slither → AST / CFG / DFG（`generate_all_ast_cfg_dfg.sh`）。

    🔴 六条环境变量**必须全部**指向 DIVE 产物区。该脚本开工即 `find -delete` 清空四个目录
    并截断 `FILTER_REPORT`，漏改任何一条就会毁掉**主库**的正典产物
    （2026-09-16 事故：漏改 `FILTER_REPORT`，主库过滤报告被写成全 0）。
    故这里显式传满六条，并加 `SSMHG_ALLOW_WIPE=1`（目标目录非空时报错退出，重入时需要）。
    """
    env = dict(os.environ)
    env.update({
        "SRC_ROOT": str(SRC_STAGE),
        "AST_DIR": str(RAW / "AST-raw"),
        "CFG_DIR": str(RAW / "CFG-raw"),
        "DFG_DIR": str(RAW / "DFG-raw"),
        "LOG_DIR": str(RAW / "logs"),
        "FILTER_REPORT": str(RAW / "filter_report.txt"),
        "SSMHG_ALLOW_WIPE": "1",
    })
    # 自卫：确认六条路径都在 products/dive 下（任何一个漏改都会指向主库正典区）
    stray = [k for k in ("SRC_ROOT", "AST_DIR", "CFG_DIR", "DFG_DIR", "LOG_DIR", "FILTER_REPORT")
             if k != "SRC_ROOT" and not env[k].startswith(str(DIVE))]
    if stray or not env["SRC_ROOT"].startswith(str(DIVE)):
        raise SystemExit(f"[dive] 🔴 raw 步骤的路径越界：{stray}；本步骤只准写 products/dive/")
    run(["bash", "scripts/generate_all_ast_cfg_dfg.sh"], "raw(Slither→AST/CFG/DFG)", env=env)


# --------------------------------------------------------------------------- 3. graphs
def step_graphs(callback_args: list[str] | None = None, out_dir: Path | None = None,
                label: str = "M2") -> None:
    """M2 异构图 + M1 锚点 + PyG 转换。`callback_args` 非空时产出**边变体**。"""
    out = out_dir or GRAPHS
    out.mkdir(parents=True, exist_ok=True)
    run([sys.executable, "scripts/build_cfg_centered_hetero_graph.py",
         "--ast-dir", str(RAW / "AST-raw"), "--cfg-dir", str(RAW / "CFG-raw"),
         "--dfg-dir", str(RAW / "DFG-raw"), "--out-dir", str(out),
         "--src-root", str(SRC_STAGE), "--overwrite", *(callback_args or [])], label)
    run([sys.executable, "scripts/m1_runner.py",
         "--in-dir", str(out), "--out-dir", str(out), "--force"], f"{label}+M1")
    run([sys.executable, "scripts/convert_hetero_json_to_pyg.py",
         "--in-dir", str(out), "--out-dir", str(out)], f"{label}+PyG")


# --------------------------------------------------------------------------- 4. features
def step_features(limit: int = 0) -> None:
    """三套 M3 特征：冻结编码器 → `graphs/`；① ② 微调编码器 → 各自 `graphs_ft*/ss{S}/`。

    ⚠ 冻结那一套直接写在 `graphs/` 里（结构产物本来就在那儿）；微调那两套只把
    `_cb.pt`/`_feat.pt` 写进新目录，**结构三件套软链**自 `graphs/`——这样"唯一变量是编码器"
    在**产物层面**成立（软链的东西物理上就是同一个文件）。
    """
    import build_graph_variant as bgv

    cats = bgv.frozen_categories()
    if limit:
        # 小样探针：只对前 N 张图跑冻结编码器的 M3，用来量单图耗时（不进微调树）
        bases = sorted(p.name[: -len("_hetero.json")] for p in GRAPHS.glob("*_hetero.json"))
        t0 = time.perf_counter()
        for n in bases[:limit]:
            run([sys.executable, "scripts/m3_build_features.py",
                 "--in-dir", str(GRAPHS), "--out-dir", str(GRAPHS), "--m1-dir", str(GRAPHS),
                 "--categories", str(cats), "--only", n, "--device", "cuda", "--force"],
                f"M3({n})")
        dt = time.perf_counter() - t0
        print(f"[dive] 探针：{min(limit, len(bases))} 图 {dt:.1f}s → "
              f"{dt / max(1, min(limit, len(bases))):.1f}s/图；900 图约 "
              f"{dt / max(1, min(limit, len(bases))) * 900 / 60:.0f} 分钟", flush=True)
        return
    run([sys.executable, "scripts/m3_build_features.py",
         "--in-dir", str(GRAPHS), "--out-dir", str(GRAPHS), "--m1-dir", str(GRAPHS),
         "--categories", str(cats), "--device", "cuda"], "M3(冻结编码器)")

    names = sorted(p.name[: -len("_hetero.json")] for p in GRAPHS.glob("*_hetero.json"))
    print(f"[dive] features：结构 {len(names)} 图；开始 ①② 微调编码器重编码", flush=True)
    for corpus, tree in ENCODER_TREES.items():
        for ss in SPLIT_SEEDS:
            encoder = REPO / "runs" / "codebert_ft" / corpus / f"ss{ss}" / "encoder"
            if not (encoder / "config.json").exists():
                raise SystemExit(f"[dive] 找不到微调编码器 {encoder}")
            # 语料归属硬校验（照抄 build_graph_variant.build_cb_ft 的理由：
            # 跨语料套用编码器**不报错**，只会静默产出一个"看起来正常"的错误特征）
            marker = encoder / "corpus.json"
            got = json.loads(marker.read_text(encoding="utf-8")) if marker.exists() else {}
            if got.get("corpus") != corpus:
                raise SystemExit(f"[dive] 🔴 编码器 {encoder} 的 corpus.json 说它是 "
                                 f"「{got.get('corpus')}」，与预期「{corpus}」不符")
            vdir = tree / f"ss{ss}"
            vdir.mkdir(parents=True, exist_ok=True)
            for n in names:
                for suffix in ("_hetero.json", "_m1.json", "_pyg.pt"):
                    link(GRAPHS / f"{n}{suffix}", vdir / f"{n}{suffix}")
            run([sys.executable, "scripts/m3_build_features.py",
                 "--in-dir", str(vdir), "--out-dir", str(vdir), "--m1-dir", str(vdir),
                 "--categories", str(cats), "--codebert", str(encoder),
                 "--device", "cuda"], f"M3({corpus} ss{ss})")
            assert_feat_same(vdir, GRAPHS, names, f"{corpus}/ss{ss}")
            write_variant_json(vdir, {
                "variant": f"dive_{corpus}_ft", "split_seed": ss,
                "derived_from": str(GRAPHS), "encoder": str(encoder),
                "only_variable": "CodeBERT 微调后重编码（结构/类型/s_v 三通道逐位不变，已断言）",
                "reuse": {"_hetero.json": "symlink", "_m1.json": "symlink", "_pyg.pt": "symlink"},
                "expect": {"_feat.pt": "与 graphs/ 逐位相同", "_cb.pt": "与 graphs/ 不同"},
            })


def assert_feat_same(vdir: Path, base: Path, names: list[str], label: str) -> None:
    """微调树的三通道必须与 `graphs/` **逐位相同**（证明只换了编码器，结构一点没动）。"""
    import torch
    bad = []
    for n in names:
        a = torch.load(vdir / f"{n}_feat.pt", map_location="cpu")
        b = torch.load(base / f"{n}_feat.pt", map_location="cpu")
        if not all(torch.equal(a[ch], b[ch]) for ch in CHANNELS):
            bad.append(n)
            if len(bad) > 5:
                break
    if bad:
        raise SystemExit(f"[dive] {label}: {len(bad)}+ 张图的 _feat.pt 三通道与 graphs/ 不同 "
                         f"（例：{bad[:5]}）——结构被改动了，本树不是「只换编码器」")
    print(f"  [{label}] 三通道逐位相同 {len(names)}/{len(names)} ✓", flush=True)


# --------------------------------------------------------------------------- 5. variants
def step_variants() -> None:
    """边变体 × 编码器：每个编码器树各造 `cb_rev_ss{S}` / `cb_unlimited_ss{S}`。

    逐图分流（照 `build_ft_edge_variants.py` 的已证做法）：三通道未被边改动者**软链**微调基座，
    被改动者只对那批图**真跑 M3**。理由：`callback_unlimited` 放开上限后先验 $s_v$ 会变
    （① 20/590、② 199/1774，见 `decisions.md` §37），那批图的 `_feat.pt` 不能软链。
    """
    # ⚠ 这个目录是**长期产物**，不是临时目录——边变体的 `_hetero/_m1/_pyg` 都从它软链出去，
    #   删掉它会让 12 棵变体树的软链全部悬空（2026-09-19 首版在结尾 `rmtree` 了它，
    #   于是 `_pyg.pt` 全断，加载时报 FileNotFoundError）。名字按语料约定取 `graph_variants/`，
    #   与 `products/<语料>/graph_variants/` 同构。
    structures = {name: GRAPHS.parent / "graph_variants" / name for name in EDGE_VARIANTS}
    cats = build_graph_variant_cats()
    # M2 变体只依赖 DIVE 的 raw，与编码器无关 → 只造一次
    for name, cargs in EDGE_VARIANTS.items():
        done = len(list(structures[name].glob("*_feat.pt"))) if structures[name].exists() else 0
        if done >= 890:                       # 可重入：结构侧已建成则整段跳过（省 ~40 min）
            print(f"  [M2({name})] 已有 {done} 个 _feat.pt，跳过重建", flush=True)
            same, _must = partition_by_channels(structures[name], GRAPHS, name)
            continue
        step_graphs(cargs, structures[name], label=f"M2({name})")
        # 🔴 **边变体也要真跑一遍 M3** 才有 `_feat.pt`（M2 只产 `_hetero/_m1/_pyg`）。
        #   本步用**冻结**编码器即可：`_feat.pt` 的三通道（struct/type_id/sv）与编码器无关
        #   （`_cb.pt` 是独立文件）——`build_graph_variant.assert_feat_identical` 已在 ①② 上证过。
        #   这里顺带**复刻 `build_graph_variant` 对 `callback_rev` 的断言**：反向关系写在
        #   第三个键下，`priori_scoring` 只读 CFG_FLOW/CALLBACK_RISK ⇒ 三通道应逐位不变。
        #   （2026-09-19 首跑漏了这一步，`FileNotFoundError: ..._feat.pt`，见 decisions §38.7。）
        run([sys.executable, "scripts/m3_build_features.py",
             "--in-dir", str(structures[name]), "--out-dir", str(structures[name]),
             "--m1-dir", str(structures[name]), "--categories", str(cats), "--device", "cuda"],
            f"M3({name} 结构侧)")
        same, _must = partition_by_channels(structures[name], GRAPHS, name)
        if name == "cb_rev":
            print(f"  [cb_rev] 三通道 vs 正典：相同 {same}/890 —— "
                  f"REV 写在第三个键下，M1 看不见它，故**必须**全同", flush=True)
    # ---- 逐 (编码器树 × 边变体) 组合 ----
    # 🔴 **只对 `must` 子集跑一次 M3，不逐图调用**（首版按图调用 → 每图都要重载 CodeBERT
    #    + 全目录扫描，DIVE 规模下不可接受）。`must` 集合**只由边/M1 决定、与编码器无关**，
    #    R 故同一语料的 3 个划分种子共用同一份名单。
    # 🔴 **`must` 图的 `_cb.pt` 必须由本次 M3 自己产出**（不能软链）：`_feat.pt` 的 meta 里
    #    记着 `cb_sha256`/`combined_sha256`，**它们随编码器变**（已实测：冻结 vs 微调两棵树
    #    同名文件的 `cb_sha256` 不同）。软链会留下"张量对、指纹错"的元数据。
    for corpus, tree in ENCODER_TREES.items():
        encoder = None
        for ss in SPLIT_SEEDS:
            ft = tree / f"ss{ss}"
            for vname in EDGE_VARIANTS:
                encoder = REPO / "runs" / "codebert_ft" / corpus / f"ss{ss}" / "encoder"
                vdir = tree / "graph_variants" / f"{vname}_ss{ss}"
                shutil.rmtree(vdir, ignore_errors=True)       # 清掉半成品，保证可重入
                vdir.mkdir(parents=True, exist_ok=True)
                edge = structures[vname]
                same, must = partition_by_channels(edge, ft, f"{corpus}/ss{ss} {vname}")
                if vname == "cb_rev" and must:
                    print(f"  ⚠ [cb_rev] 本应 0 图改变（REV 写在第三个键下、M1 看不见它），"
                          f"实测 {len(must)} 图——与 ①② 的证据不符，须复查", flush=True)
                names_all = sorted(p.name[: -len("_feat.pt")] for p in ft.glob("*_feat.pt"))
                # ① 结构三件套（**全部**图，一律取自边变体）
                for n in names_all:
                    for suffix in ("_hetero.json", "_m1.json", "_pyg.pt"):
                        link(edge / f"{n}{suffix}", vdir / f"{n}{suffix}")
                # ② `must` 子集**先**跑 M3 —— 此刻 vdir 里还没有任何 `_feat.pt`，
                #    `run_guard.corpus_conflict` 才不会把"子集 in-dir vs 全量 out-dir"误判成跨语料。
                #    （2026-09-19 首修时把 same 的软链放在这一步**之前**，于是真被守卫拒了。）
                if must:
                    stage = DIVE / "_must_stage"
                    shutil.rmtree(stage, ignore_errors=True)
                    stage.mkdir(parents=True)
                    for n in must:
                        for suffix in ("_hetero.json", "_m1.json"):
                            link(edge / f"{n}{suffix}", stage / f"{n}{suffix}")
                    run([sys.executable, "scripts/m3_build_features.py",
                         "--in-dir", str(stage), "--out-dir", str(vdir), "--m1-dir", str(stage),
                         "--categories", str(cats), "--codebert", str(encoder),
                         "--device", "cuda", "--force"],
                        f"M3({vname} 子集 {corpus} ss{ss} {len(must)} 图)")
                    shutil.rmtree(stage, ignore_errors=True)
                    assert_must_feat(vdir, edge, must, f"{corpus}/ss{ss} {vname}")
                # ③ `same` 从微调基座成对软链（`_feat.pt` 与 `_cb.pt` 必须同源：meta 里记着 cb_sha256）
                for n in same:
                    link(ft / f"{n}_feat.pt", vdir / f"{n}_feat.pt")
                    link(ft / f"{n}_cb.pt", vdir / f"{n}_cb.pt")
                write_variant_json(vdir, {
                    "variant": vname, "split_seed": ss, "corpus": corpus,
                    "derived_from": str(ft), "edge_source": str(edge), "encoder": str(encoder),
                    "only_variable": "边（结构三件套来自边变体）+ 编码器来自本语料微调版",
                    "symlinked_from_ft": len(same), "m3_rerun": len(must),
                    "note": ("本臂变量不止「边」：这 %d 张图的先验 s_v 随边改动，"
                             "M3 已用本树编码器真跑（decisions.md §37）" % len(must)) if must else
                            "边改动未触及任何图的节点特征 ⇒ 纯边消融",
                })


def assert_must_feat(vdir: Path, edge: Path, must: list[str], label: str) -> None:
    """`must` 图的 `_feat.pt` 必须与**边变体**的三通道逐位相同（证明 M3 真读了变体结构）。

    这条是本组合"确实用了边变体的图"的唯一直接证据——否则 M3 万一读了别处的
    `_hetero.json`，产物照样齐全、照样安静。
    """
    import torch
    bad = []
    for n in must:
        a = torch.load(vdir / f"{n}_feat.pt", map_location="cpu")
        b = torch.load(edge / f"{n}_feat.pt", map_location="cpu")
        if not all(torch.equal(a[ch], b[ch]) for ch in CHANNELS):
            bad.append(n)
            if len(bad) > 5:
                break
    if bad:
        raise SystemExit(f"[dive] {label}: {len(bad)}+ 张 must 图的 _feat.pt 与边变体不同"
                         f"（例：{bad[:5]}）——M3 没读到变体结构？")
    print(f"  [{label}] must 子集三通道与边变体一致 {len(must)}/{len(must)} ✓", flush=True)


def build_graph_variant_cats() -> Path:
    import build_graph_variant as bgv
    return bgv.frozen_categories()


def partition_by_channels(edge_dir: Path, base_dir: Path, label: str) -> tuple[list[str], list[str]]:
    """逐图比较 `_feat.pt` 三通道：返回 (可软链自基座, 须用本树编码器重跑 M3)。"""
    import torch
    names = sorted(p.name[: -len("_feat.pt")] for p in edge_dir.glob("*_feat.pt"))
    same, must = [], []
    for n in names:
        e = torch.load(edge_dir / f"{n}_feat.pt", map_location="cpu")
        b = torch.load(base_dir / f"{n}_feat.pt", map_location="cpu")
        (same if all(torch.equal(e[ch], b[ch]) for ch in CHANNELS) else must).append(n)
    print(f"  [{label}] 三通道与正典：相同 {len(same)} / 不同 {len(must)}", flush=True)
    return same, must


def write_variant_json(vdir: Path, payload: dict) -> None:
    """变体目录自述文件（`train.py` 的守卫只能看到路径变了，看不到里面装的是什么）。"""
    payload = dict(payload)
    payload["created_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    (vdir / "variant.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="构建 DIVE 外部测试集的图与特征")
    p.add_argument("--steps", default="all",
                   help="逗号分隔：stage,raw,graphs,features,variants,all")
    p.add_argument("--dataset", default="dive", choices=sorted(DATASETS),
                   help="要构建哪个外部数据集（默认 dive，保持既有行为不变）")
    p.add_argument("--limit", type=int, default=0, help="小样探针：只用前 N 个抽样文件")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    use_dataset(args.dataset)
    steps = (["stage", "raw", "graphs", "features", "variants"]
             if args.steps == "all" else [s.strip() for s in args.steps.split(",") if s.strip()])
    unknown = [s for s in steps if s not in ("stage", "raw", "graphs", "features", "variants")]
    if unknown:
        raise SystemExit(f"[dive] 未知步骤 {unknown}；可选 stage/raw/graphs/features/variants/all")
    if args.limit:
        print(f"[dive] ⚠ 小样模式 --limit {args.limit}：产物**不是**协议集，"
              f"跑完请删掉 products/dive/{{src_stage,raw,graphs}} 再跑全量", flush=True)
    for s in steps:
        print(f"\n[dive] ===== 步骤 {s} =====", flush=True)
        if s == "stage":
            step_stage(args.limit)
        elif s == "raw":
            step_raw()
        elif s == "graphs":
            step_graphs()
        elif s == "features":
            step_features(args.limit)
        elif s == "variants":
            step_variants()
    print(f"\n[dive] 完成：{','.join(steps)}", flush=True)


if __name__ == "__main__":
    main()
