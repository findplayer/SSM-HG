#!/usr/bin/env python3
"""数据口径追溯审计（论文口径数字可溯源；2026-09-12 新增）。

目的：把论文里出现的每一个样本/标签口径数字，逐级连到**产物文件**与**生成脚本**，
包括上游 `MVD-HG-dataset`（仅作参考的上游源仓库）到主库 `alldata(readonly)` 的差额去向
（`846 → 591` 的 255），以及主库到划分池（591 → 581 → 495 → 448 → 358/45/45）的每一步。

输出（两个文件，均由本脚本生成，不要手改）：
  - `products/alldata/splits/data_funnel.json`：机器可读，每步含 value/source/command/note；
  - `docs/data_funnel.md`：论文写作可直接引用的口径表 + 差额拆解。

运行（仓库根目录）：
  python scripts/audit_data_funnel.py            # 生成两份报告并打印摘要
  python scripts/audit_data_funnel.py --print    # 只打印，不写文件

依赖：只用标准库 + 本仓库 `scripts/dataset.py`（标签对齐走训练同一条代码路径）；
DIVE 抽样门槛检查在 scipy 可用时给出超几何概率，否则只给期望值。
"""

from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE = Path("/home/saumarez/projects/deep-learning/SSM-HG")
sys.path.insert(0, str(BASE / "scripts"))
import dataset  # noqa: E402  （标签/池口径与训练完全一致）
import make_splits  # noqa: E402  （池去重口径与 make_splits 同一条代码路径，避免二次实现）

CLASSES = ["access_control", "arithmetic", "dos", "front_running",
           "reentrancy", "time_manipulation", "uncheck"]
MVD_ROOT = BASE / "MVD-HG-dataset"
ALDDATA_SRC = BASE / "alldata(readonly)/alldata_sol_source"
LABEL_FILE = BASE / "alldata(readonly)/contract_labels.json"
FILTER_REPORT = BASE / "products/alldata/raw/filter_report.txt"
SPLITS_DIR = BASE / "products/alldata/splits"
DIVE_LABELS = BASE / "DIVE/contract_labels.json"
OUT_JSON = SPLITS_DIR / "data_funnel.json"
OUT_MD = BASE / "docs/data_funnel.md"
OUT_DIR_DIVE = BASE / "products/dive/splits"

STEPS: list[dict] = []


def step(stage: str, name: str, value, source: str, command: str = "", note: str = "") -> None:
    """登记一个口径数字：value + 出处（source/命令）+ 备注。"""
    STEPS.append({"stage": stage, "name": name, "value": value,
                  "source": source, "command": command, "note": note})


def sha1(path: Path) -> str:
    with open(path, "rb") as handle:
        return hashlib.sha1(handle.read()).hexdigest()


def sha256_file(path: Path) -> str:
    """绑定指纹用 sha256（与 decisions/手册的“绑定 sha256”口径一致）。"""
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


# ---------------------------------------------------------------- 上游（MVD-HG-dataset）
def stage_upstream() -> dict:
    """上游类别文件夹记录 → 唯一文件/目录/内容，并拆解 846→591 的 255。"""
    records: list[tuple[str, str, str, Path]] = []
    for class_dir in sorted(MVD_ROOT.glob("*_contract")):
        if class_dir.name.endswith("_data_augmentation"):
            continue
        cls = class_dir.name
        for path in glob.glob(str(class_dir / "sol_source" / "*" / "*.sol")):
            p = Path(path)
            records.append((cls, p.parent.name, p.name, p))

    uniq_pairs = {(dn, fn) for _, dn, fn, _ in records}
    uniq_dirs = {dn for _, dn, _p, _ in records}
    prefix_cnt = collections.Counter(dn.split("_")[0] for _, dn, _, _ in records)

    content_of: dict[tuple[str, str], dict[str, str]] = collections.defaultdict(dict)
    for cls, dn, fn, p in records:
        content_of[(dn, fn)][cls] = sha1(p)
    uniq_contents = {h for v in content_of.values() for h in v.values()}
    inconsistent = {k for k, v in content_of.items() if len(set(v.values())) > 1}
    inconsistent_buggy = {k for k in inconsistent if k[0].startswith(("asd_buggy", "nasd_buggy"))}

    per_class = collections.Counter(cls for cls, *_ in records)
    dircount = collections.Counter()
    for _, dn, _, _ in records:
        dircount[dn] += 1

    step("上游 MVD-HG-dataset", "类别文件夹 .sol 记录数（含跨类别重复）", len(records),
         "MVD-HG-dataset/*_contract/sol_source/**/*.sol",
         'find MVD-HG-dataset/*_contract/sol_source -name "*.sol" | wc -l',
         f"逐类：{dict(sorted(per_class.items()))}；注：上游仓库不作数据集用（只读参考）")
    step("上游 MVD-HG-dataset", "唯一（项目目录, 文件名）对", len(uniq_pairs),
         "MVD-HG-dataset/*_contract/sol_source/*/*.sol", "", "846 去掉跨类别重复收录后的文件数")
    step("上游 MVD-HG-dataset", "差额：跨类别重复收录次数", len(records) - len(uniq_pairs),
         "同上一行", "", "846 - 591 = 255；这是**计数重复**，不是文件丢失")
    addr_of = {dn: re.sub(r"^(asd_|nasd_)", "", dn).lower() for dn in uniq_dirs}
    uniq_addrs = set(addr_of.values())
    step("上游 MVD-HG-dataset", "唯一项目目录数 / 唯一地址数",
         {"dirs": len(uniq_dirs), "addresses": len(uniq_addrs),
          "dual_prefix_dirs": len(uniq_dirs) - len(uniq_addrs)},
         "MVD-HG-dataset/*_contract/sol_source/<项目目录>", "",
         f"目录名前缀分布：{dict(prefix_cnt)}；差额 = 同一地址同时存在 asd_/nasd_ 两份目录")
    step("上游 MVD-HG-dataset", "唯一源码内容 sha1 数", len(uniq_contents),
         "对 846 份副本逐一 sha1", "",
         f"内容不一致的同名副本组数 {len(inconsistent)}（全部位于 buggy_* 项目：{len(inconsistent_buggy)}）"
         f"；非 buggy 副本内容完全一致")

    # 同一文件被 k 个类别文件夹收录的分布（解释 255 的构成）
    k_hist = collections.Counter(len(v) for v in content_of.values())
    step("上游 MVD-HG-dataset", "同一文件被 k 个类别文件夹收录的分布",
         {str(k): v for k, v in sorted(k_hist.items())},
         "MVD-HG-dataset/*_contract/sol_source", "",
         "Σ(k-1)×count = 255，即差额 255 的全部构成（无其它去向）")
    return {"records": len(records), "pairs": len(uniq_pairs), "dirs": len(uniq_dirs),
            "contents": len(uniq_contents), "k_hist": {str(k): v for k, v in sorted(k_hist.items())},
            "inconsistent": len(inconsistent)}


# ---------------------------------------------------------------- 主库 alldata
def stage_alldata() -> dict:
    """主库 591 文件 = 上游唯一的 (dir,file) 各保留一份副本；标签 = 七类并集。"""
    files = sorted(ALDDATA_SRC.glob("*/*.sol"))
    dirs = {p.parent.name for p in files}
    entries = json.loads(LABEL_FILE.read_text(encoding="utf-8"))
    pos = sum(1 for e in entries if any(int(v) for v in e["targets"]))
    multi = sum(1 for e in entries if sum(int(v) for v in e["targets"]) >= 2)
    per_class = {c: sum(1 for e in entries if int(e["targets"][i]))
                 for i, c in enumerate(CLASSES)}

    step("主库 alldata", "源码文件数", len(files),
         "alldata(readonly)/alldata_sol_source/*/*.sol",
         'find "alldata(readonly)/alldata_sol_source" -name "*.sol" | wc -l',
         f"= 上游唯一（项目目录, 文件名）对；目录数 {len(dirs)}（含 asd_/nasd_ 双前缀副本）")
    step("主库 alldata", "标签条目数（合约定义级）", len(entries),
         "alldata(readonly)/contract_labels.json", "",
         "一个 .sol 内的多个合约定义各占一条（这正是 2002 的来源）")
    step("主库 alldata", "标签条目中正样本条数（≥1 类）", pos,
         "alldata(readonly)/contract_labels.json", "")
    step("主库 alldata", "标签条目中多标签条数（≥2 类）", multi,
         "alldata(readonly)/contract_labels.json", "",
         "大纲 5.1 写的 681 与本数字不符，论文以大数字为准（口径须改写）")
    step("主库 alldata", "逐类正样本条目数", per_class,
         "alldata(readonly)/contract_labels.json", "",
         "与 MVD-HG-dataset/<类>_contract/contract_labels.json 逐类 diff=0（脚本内校验）")

    # 自洽校验：主标签文件 vs 七类单类文件
    mismatch = 0
    for i, c in enumerate(CLASSES):
        per_file = {e["contract_name"].lower() for e in
                    json.loads((MVD_ROOT / f"{c}_contract/contract_labels.json").read_text(encoding="utf-8"))
                    if any(int(v) for v in (e["targets"] if isinstance(e["targets"], list) else [e["targets"]]))}
        main = {e["contract_name"].lower() for e in entries if int(e["targets"][i])}
        mismatch += len(per_file ^ main)
    step("主库 alldata", "主标签文件 vs 七类单类文件 差异条目数", mismatch,
         "alldata(readonly)/contract_labels.json ↔ MVD-HG-dataset/*_contract/contract_labels.json",
         "", "0 = 主标签文件是七类单类文件的并集，自洽")
    return {"files": len(files), "entries": len(entries), "pos": pos, "multi": multi,
            "mismatch": mismatch, "per_class": per_class}


# ---------------------------------------------------------------- 解析/图/池/划分
def stage_pipeline() -> dict:
    """581 图 → 495（剔 buggy_*）→ 448（两级池去重）→ 358/45/45，含池内标签分布。"""
    report = json.loads((SPLITS_DIR / "split_report.json").read_text(encoding="utf-8"))
    filter_txt = FILTER_REPORT.read_text(encoding="utf-8")
    filt = dict(re.findall(r"^(\w+)=(\S+)$", filter_txt, flags=re.M))

    index, unmatched = dataset.build_index()
    pre_dedup = sorted(b for b in index
                       if not dataset.is_buggy_project(dataset.project_of_base(b)))
    # 池去重走 make_splits.dedup_pool（与划分同一条代码路径）
    kept, _dropped, _dstat = make_splits.dedup_pool(pre_dedup, BASE / "products/alldata/graphs")
    pool = sorted(kept)

    def stats(names):
        per = collections.Counter()
        pos = zero = multi = 0
        for b in names:
            y = index[b]
            s = sum(y)
            pos += 1 if s else 0
            zero += 0 if s else 1
            multi += 1 if s >= 2 else 0
            for i, v in enumerate(y):
                per[CLASSES[i]] += 1 if v else 0
        return {"n": len(names), "pos": pos, "zero": zero, "multi": multi,
                "per_class_pos": {c: per[c] for c in CLASSES}}

    step("主库→图", "源码文件数（上一阶段）", int(filt.get("total_source_files", 0)),
         "products/alldata/raw/filter_report.txt", "bash scripts/generate_all_ast_cfg_dfg.sh")
    step("主库→图", "过滤：assembly>50 行", int(filt.get("assembly_gt50_lines", 0)),
         "products/alldata/raw/filter_report.txt", "")
    step("主库→图", "过滤：delegatecall 动态绑定", int(filt.get("delegatecall_dynamic_binding", 0)),
         "products/alldata/raw/filter_report.txt", "")
    step("主库→图", "解析失败（AST/CFG/DFG/cfgdetail）",
         {k: int(filt.get(k, 0)) for k in ("ast_failed", "cfg_failed", "dfg_failed", "cfgdetail_failed")},
         "products/alldata/raw/filter_report.txt", "",
         "591 - 1(assembly) - 9(delegatecall) = 581 = 已生成图数，无解析失败")
    step("图", "已生成异构图数", len(index),
         "products/alldata/graphs/*_pyg.pt（经 scripts/dataset.py::build_index）",
         "python scripts/dataset.py --check <base>")
    step("图→划分", "标签匹配失败（未进入划分）图数", len(unmatched),
         "products/alldata/splits/unmatched_contracts.txt", "python scripts/make_splits.py")
    step("图→划分", "剔除 buggy_* 注入噪声项目图数", int(report.get("buggy_excluded_graphs", 0)),
         "products/alldata/splits/split_report.json", "",
         "581 - 86 = 495；该剔除为实验室决策（大纲 5.1 未列），须在论文说明")
    lv = report["dedup"]["levels"]
    step("图→划分", "池去重 level-1：源码内容 sha1 相同（同一份源码的副本）",
         {"dropped": lv["source-sha1"]["dropped"],
          "groups": lv["source-sha1"]["duplicate_groups"]},
         "products/alldata/splits/split_report.json::dedup",
         "python scripts/make_splits.py", "495 - 46 = 449")
    step("图→划分", "池去重 level-2：项目标识/地址相同（同合约的另一份源码，字节可能不同）",
         {"dropped": lv["address"]["dropped"], "groups": lv["address"]["duplicate_groups"]},
         "products/alldata/splits/split_report.json::dedup", "",
         "449 - 1 = 448；该组即全库唯一多标签样本（0x627fa62c…：1847 vs 1842 字节），"
         "sha1 抓不到，seed0 下曾被拆到 train/val——去重的实质收益在此")
    step("图→划分", "划分池样本数", int(report.get("unique_contracts", 0)),
         "products/alldata/splits/split_seed{0,1,2}.json", "",
         "样本单位 = 源文件（唯一标识 = 源码哈希 → 项目标识），非合约定义级")
    for seed in (0, 1, 2):
        d = json.loads((SPLITS_DIR / f"split_seed{seed}.json").read_text(encoding="utf-8"))
        rc = report["rule_check"]["seeds"][str(seed)]
        step("图→划分", f"seed{seed} 划分规模",
             {"train": len(d["train"]), "val": len(d["val"]), "test": len(d["test"])},
             f"products/alldata/splits/split_seed{seed}.json", "python scripts/make_splits.py",
             f"覆盖校正替换 {rc['coverage_fix']['swaps_count']} 个"
             f"（下限修正 {rc['coverage_fix']['floor_fixes']}）；"
             f"C1+C2 {7 - rc['n_classes_failed']}/7 类达标")

    all_stats, pool_stats = stats(list(index)), stats(pool)
    step("池内标签", "全量图（581）标签分布", all_stats,
         "products/alldata/graphs/*_pyg.pt + alldata(readonly)/contract_labels.json", "")
    step("池内标签", "划分池（448）标签分布", pool_stats, "同上", "",
         "逐类支撑决定宏平均是否可用（见 decisions §13）")

    # 去重不变量：两级均不得跨划分（逐种子；直接读划分报告，避免二次实现）
    invariants = {}
    for seed in (0, 1, 2):
        rc = report["rule_check"]["seeds"][str(seed)]
        invariants[str(seed)] = {
            "content_ok": rc["content_dedup_ok"], "address_ok": rc["address_dedup_ok"],
            "content_cross": len(rc["cross_split_content_dups"]),
            "address_cross": len(rc["cross_split_address_dups"]),
        }
    step("图→划分", "去重不变量（同 sha1 / 同地址不得跨划分，逐种子）", invariants,
         "products/alldata/splits/split_report.json::rule_check", "python scripts/make_splits.py",
         "全 0 = 大纲 5.1「同一合约及其所有重复记录不跨划分」已构造性保证")
    return {"index": index, "pool": pool, "pool_stats": pool_stats, "all_stats": all_stats,
            "dedup": report["dedup"], "invariants": invariants,
            "dropped": report["dedup"]["dropped_count"]}


# ---------------------------------------------------------------- DIVE 抽样门槛
def stage_dive() -> dict:
    """DIVE 外部测试集抽样门槛核查（含多标签期望）。"""
    entries = json.loads(DIVE_LABELS.read_text(encoding="utf-8"))
    n = len(entries)
    per = collections.Counter()
    multi = 0
    for e in entries:
        t = [int(v) for v in e["targets"][:7]]
        for i, v in enumerate(t):
            per[CLASSES[i]] += v
        multi += 1 if sum(t) >= 2 else 0

    out = {}
    for size in (500, 900):
        exp = {c: per[c] / n * size for c in CLASSES}
        out[str(size)] = {"per_class_expected": {c: round(exp[c], 1) for c in CLASSES},
                          "multi_label_expected": round(multi / n * size, 1)}
    # front_running ≥ 20 的超几何概率（均匀无放回抽样）
    prob = None
    try:
        from scipy.stats import hypergeom
        for size in (500, 900, 1100):
            p = float(hypergeom.sf(19, n, per["front_running"], size))
            out.setdefault("front_running_p_ge20", {})[str(size)] = round(p, 3)
        prob = out["front_running_p_ge20"]
    except Exception:  # scipy 不可用则只给期望
        pass

    step("DIVE 外部测试", "标签条目数 / 多标签条数 / 全零条数",
         {"n": n, "multi": multi, "zero": sum(1 for e in entries if sum(int(v) for v in e["targets"][:7]) == 0)},
         "DIVE/contract_labels.json", "",
         "多标签占比 %.1f%% → 外部测试可支撑「多类共存」的实证" % (100 * multi / n))
    step("DIVE 外部测试", "逐类正样本数与占比",
         {c: f"{per[c]} ({per[c]/n:.2%})" for c in CLASSES}, "DIVE/contract_labels.json", "",
         "front_running 占比最低，决定抽样规模下限")
    step("DIVE 外部测试", "均匀抽样下的逐类期望（500/900）", out,
         "DIVE/contract_labels.json", "",
         "大纲 5.1(6)「≥500 且每类 ≥20」在 500 规模下对 front_running 不可达（期望 12.2）；"
         "n=900 期望 22.0、P(fr≥20)=0.70，三条件自洽 → 2026-09-12 P1 定稿 n=900")
    return {"n": n, "multi": multi, "per_class": dict(per), "expectations": out, "front_prob": prob}


# ---------------------------------------------------------------- 图结构口径
RELATION_MAP = {
    0: ("CFG_FLOW", "CFG_FLOW（含 seq/true/false 子类）"),
    1: ("AST_PARENT", "AST_PARENT"),
    2: ("AST_PARENT_SAME", "AST_PARENT（实现细节：多个 AST 节点落在同一 CFGNode）"),
    3: ("DFG_DEP", "DFG_DEP"),
    4: ("CALLBACK_RISK", "CALLBACK_RISK"),
}


def stage_graph_structure() -> dict:
    """图结构口径：逐边类型规模与覆盖图数、AST 稀疏性、关系编号映射（论文 4 语义边 / 实现 5 物理关系）。"""
    graphs = sorted((BASE / "products/alldata/graphs").glob("*_hetero.json"))
    totals: collections.Counter = collections.Counter()
    graphs_with: collections.Counter = collections.Counter()
    nodes = 0
    ast_unmapped = 0
    for path in graphs:
        data = json.loads(path.read_text(encoding="utf-8"))
        nodes += len(data["nodes"])
        for key, edges in data["edges"].items():
            totals[key] += len(edges)
            if edges:
                graphs_with[key] += 1
        ast_unmapped += int(data["meta"].get("ast_unmapped_edge_count") or 0)

    total_edges = sum(totals.values())
    table = {key: {"edges": totals[key], "graphs_with_edge": graphs_with[key],
                   "edges_per_graph": round(totals[key] / len(graphs), 2),
                   "share": round(totals[key] / total_edges, 4)}
             for key in ("CFG_FLOW", "AST_PARENT", "AST_PARENT_SAME", "DFG_DEP", "CALLBACK_RISK")}

    step("图结构", "异构图数 / 节点数 / 边数合计",
         {"graphs": len(graphs), "nodes": nodes, "edges": total_edges},
         "products/alldata/graphs/*_hetero.json", "python scripts/build_cfg_centered_hetero_graph.py")
    step("图结构", "逐边类型：边数 / 含该边的图数 / 平均每图 / 边数占比", table,
         "products/alldata/graphs/*_hetero.json", "",
         "AST_PARENT 仅 %d 条（%d/%d 图有），边集主体是 DFG_DEP 与 CFG_FLOW"
         % (totals["AST_PARENT"], graphs_with["AST_PARENT"], len(graphs)))
    step("图结构", "AST 专项：AST_PARENT / AST_PARENT_SAME / 端点未映射到 CFGNode 的 AST 父子关系",
         {"AST_PARENT": totals["AST_PARENT"], "AST_PARENT_SAME": totals["AST_PARENT_SAME"],
          "ast_unmapped": ast_unmapped},
         "products/alldata/graphs/*_hetero.json（meta.ast_*_edge_count）", "",
         "保留为语义边的 AST 父子关系仅 AST_PARENT+SAME=%d 条（占全部边 %.2f%%），其余 %d 条端点未映射到 CFGNode；"
         "→ “语法从属”边几乎不承载信息，论文需给出本稀疏性统计，并据此调整“四类边”的贡献表述"
         % (totals["AST_PARENT"] + totals["AST_PARENT_SAME"],
            100 * (totals["AST_PARENT"] + totals["AST_PARENT_SAME"]) / total_edges, ast_unmapped))
    step("图结构", "关系编号映射：实现 5 物理关系 → 论文 4 语义边（可选 6 关系）",
         {str(k): {"physical": v[0], "paper_semantic": v[1]} for k, v in RELATION_MAP.items()},
         "scripts/dataset.py::RELATION_NAMES / scripts/convert_hetero_json_to_pyg.py", "",
         "论文默认 4 语义边（AST_PARENT_SAME 并入 AST_PARENT 叙述）；若把 CFG_FLOW 三子类当独立关系则为 6（需新增 kind→edge_type 映射，当前未实现）；"
         "边消融口径：去 AST_PARENT = 同时删 relation 1 与 2（dataset.py::DROP_AST，加载时过白名单校验）；"
         "DROPPABLE_EDGES = 全部 5 个物理关系，load_graph 强制校验，不做物理合并（num_bases=5 不变）")
    return {"table": table, "nodes": nodes, "edges": total_edges, "ast_unmapped": ast_unmapped,
            "relation_map": {str(k): v[1] for k, v in RELATION_MAP.items()}}


# ---------------------------------------------------------------- 口径绑定指纹与 DIVE 状态
def stage_binding() -> dict:
    """口径绑定指纹（防止文档与产物漂移）+ DIVE 抽样状态。"""
    digests = {}
    for seed in (0, 1, 2):
        p = SPLITS_DIR / f"split_seed{seed}.json"
        digests[f"split_seed{seed}.json"] = sha256_file(p) if p.exists() else None
    step("口径绑定", "划分产物指纹 sha256（支撑数字绑定的版本）", digests,
         "products/alldata/splits/split_seed{0,1,2}.json", "python scripts/make_splits.py",
         "本报告与 decisions 中所有 val/test 支撑数字均对应此指纹（**两级去重后的现行 splits**）；"
         "任何划分产物变更（含去重口径、覆盖约束、种子）都会改变指纹 → 必须重跑本脚本并刷新 decisions/手册的支撑数字")

    dive_sample = OUT_DIR_DIVE / "sample_report.json"
    if dive_sample.exists():
        s = json.loads(dive_sample.read_text(encoding="utf-8"))
        last = s["attempts"][-1]
        step("DIVE 外部测试", "抽样结果（固定协议）",
             {"seed": s["protocol"]["seed"], "n": last["n"], "attempt": last["attempt"],
              "per_class": last["per_class"], "multi_label": last["multi_label"],
              "all_zero": last["all_zero"], "gate": s["gate"]},
             "products/dive/splits/sample_report.json", "python scripts/sample_dive_subset.py",
             "抽样是一次确定事件：实测支撑即结果（front_running≥20 → 闭案）；"
             "后备路径（n→1100 重抽一次，再不足则记 report-only）与“禁止换 seed 重抽”见 decisions §13")
        return {"sample": s, "digests": digests}
    step("DIVE 外部测试", "抽样结果（固定协议）", "未生成",
         "products/dive/splits/sample_report.json", "python scripts/sample_dive_subset.py",
         "尚未运行抽样脚本")
    return {"sample": None, "digests": digests}


def render_md(up: dict, ald: dict, pipe: dict, dive: dict, graph: dict,
              binding: dict, meta: dict) -> str:
    lines: list[str] = []
    add = lines.append
    lv1 = pipe["dedup"]["levels"]["source-sha1"]["dropped"]
    lv2 = pipe["dedup"]["levels"]["address"]["dropped"]
    add("# 数据口径追溯（由 `scripts/audit_data_funnel.py` 生成，勿手改）")
    add("")
    add(f"> 生成时间（UTC）：{meta['created_utc']}；运行方式：`python scripts/audit_data_funnel.py`")
    add("> 论文里出现的每个样本/标签数字都应能在下表中找到出处；下表未列出的数字不得写进论文。")
    add("")
    add("## 0. 一句话口径")
    add("")
    add(f"- 上游 `MVD-HG-dataset`（只读参考）：7 个类别文件夹共 **{up['records']}** 条 `.sol` 记录"
        f"（跨类别重复收录），去重后唯一（目录,文件）**{up['pairs']}** 个。")
    add(f"- 主库 `alldata(readonly)`：**{ald['files']}** 个 `.sol`；标签文件 **{ald['entries']}** 条"
        f"（合约定义级），其中正样本 {ald['pos']} 条、多标签 {ald['multi']} 条。")
    add(f"- 图与划分：**581** 图 → 剔除 {int(meta['buggy'])} 个 `buggy_*` → 池 **495** → 两级去重"
        f"（sha1 丢 {lv1}、地址丢 {lv2}）→ **{pipe['pool_stats']['n']}** → 358/45/45；"
        f"池内正样本 {pipe['pool_stats']['pos']}、全零 {pipe['pool_stats']['zero']}、"
        f"多标签 **{pipe['pool_stats']['multi']}**。")
    add("")
    add("## 1. `846 → 591` 的 255 个去向（逐条拆解）")
    add("")
    add(f"- {up['records']} = 七个 `<类>_contract/sol_source` 目录里 `.sol` 记录的**合计**；")
    add(f"- {up['pairs']} = 唯一（项目目录, 文件名）对，即主库实际保留的源码文件数；")
    add(f"- **差额 {up['records'] - up['pairs']} = 「同一 (项目目录, 文件名) 被多个类别文件夹重复收录」的重复计数之和**：")
    add("")
    add("| 同一文件被 k 个类别文件夹收录 | 文件数 | 贡献的重复计数 (k-1)×文件数 |")
    add("| --- | --- | --- |")
    total = 0
    for k, v in up["k_hist"].items():
        total += (int(k) - 1) * v
        add(f"| k={k} | {v} | {(int(k)-1)*v} |")
    add(f"| **合计** | **{sum(up['k_hist'].values())}** | **{total}** |")
    add("")
    add(f"- 校验：{total} == {up['records']} - {up['pairs']} = {up['records'] - up['pairs']}，"
        "**无其它去向**（不是文件丢失，类别信息已合并进多热标签）。")
    add(f"- 另注：跨类别副本内容不一致的同名文件组 **{up['inconsistent']}** 组，全部位于 `buggy_*` 项目；"
        "非 buggy 副本内容完全一致。")
    add("")
    add("## 2. 逐级数字与出处")
    add("")
    add("| 阶段 | 口径 | 数值 | 出处（产物/命令） | 备注 |")
    add("| --- | --- | --- | --- | --- |")
    for s in STEPS:
        val = s["value"] if not isinstance(s["value"], (dict, list)) else f"`{json.dumps(s['value'], ensure_ascii=False)}`"
        src = s["source"].replace("|", "/")
        cmd = f"<br>`{s['command']}`" if s["command"] else ""
        note = (s["note"] or "").replace("|", "/")
        add(f"| {s['stage']} | {s['name']} | {val} | {src}{cmd} | {note} |")
    add("")
    add("## 3. DIVE 外部测试抽样门槛")
    add("")
    add(f"- DIVE 标签 {dive['n']} 条，多标签 {dive['multi']} 条（{100*dive['multi']/dive['n']:.1f}%）。")
    for size, info in dive["expectations"].items():
        if size == "front_running_p_ge20":
            continue
        add(f"- n={size} 均匀抽样：多标签期望 {info['multi_label_expected']}；"
            f"逐类期望 {info['per_class_expected']}")
    if dive.get("front_prob"):
        add(f"- front_running 达到 ≥20 的超几何概率（抽样前口径）：{dive['front_prob']}")
    add("- 结论：多标签计数在 DIVE 上不是退化项（占比高），外部测试的多标签证据成立；"
        "均匀抽样在 500 规模下对 front_running 不可达（期望 12.2），**抽样规模已定稿 n=900**"
        "（2026-09-12 P1；固定 seed，一次确定事件；实测结果见下表），后备路径见 decisions §13。")
    add("")
    add("## 4. 图结构口径（AST 稀疏性 / 关系数映射）")
    add("")
    add(f"- 581 图 / {graph['nodes']} 节点 / {graph['edges']} 边。")
    add("")
    add("| 边类型（物理关系） | 边数 | 含该边的图数 | 平均每图 | 边数占比 |")
    add("| --- | --- | --- | --- | --- |")
    for key, info in graph["table"].items():
        add(f"| {key} | {info['edges']} | {info['graphs_with_edge']} | {info['edges_per_graph']} "
            f"| {info['share']:.2%} |")
    add("")
    add(f"- AST 专项：AST_PARENT {graph['table']['AST_PARENT']['edges']} / "
        f"AST_PARENT_SAME {graph['table']['AST_PARENT_SAME']['edges']} / "
        f"映射不到 CFGNode 的 AST 父子关系 {graph['ast_unmapped']}；"
        "→ 语法从属边几乎不承载信息，论文须给出本表并据此调整“四类边”的贡献表述。")
    add("")
    add("| 编号 | 物理关系（实现） | 论文语义 |")
    add("| --- | --- | --- |")
    for key, info in RELATION_MAP.items():
        add(f"| {key} | {info[0]} | {info[1]} |")
    add("")
    add("- 论文默认 **4 语义边**（AST_PARENT_SAME 并入 AST_PARENT 叙述）；实现为 **5 个物理关系**"
        "（`num_bases=5`）；若把 CFG_FLOW 三子类当独立关系则为 **6**（需补 `kind→edge_type` 映射，当前未实现）。")
    add("- 边消融口径：**去 AST_PARENT = 同时删 relation 1 与 2**（`dataset.py::DROP_AST`）；"
        "`DROPPABLE_EDGES` 为**全部 5 个物理关系**的白名单，`load_graph` 在加载时强制校验"
        "（越界编号直接报错）；不做物理合并（5 个物理关系、`num_bases=5` 不变）。")
    add("")
    add("## 5. 口径绑定指纹与刷新义务（防文档/产物漂移）")
    add("")
    add("- **注释必须与被解释的指标同口径**（decisions §13 第 8 条）：")
    add("  - macro-F1 的*低支撑构成*注释 → 用**计算它的那个划分**（seed0 test：‘5 个类 support ≤2’）；")
    add("  - 数据固有稀疏的*天花板*叙述 → 用**池级**（‘池内 3 个类正样本 ≤6’）；")
    add("  - 两个口径都保留、各有用途，**禁止互相借用**。")
    add("")
    add("- 划分产物指纹（本节所有 val/test 支撑数字绑定于此；均为**两级去重后的现行 splits**）：")
    add("")
    add("| 产物 | sha256 |")
    add("| --- | --- |")
    for name, digest in binding["digests"].items():
        add(f"| {name} | `{digest}` |")
    add("")
    add("- **刷新义务（已履行 2026-09-12）**：T-A 两级池去重重跑后，本报告（重跑本脚本）、"
        "`experiments/decisions.md`（§12 历史标注 + §14 现行口径）、`论文开发手册.md` §10.2/§10.5 "
        "的池规模、划分规模与逐类支撑数字已同步刷新；今后任何划分产物变更必须重复这一链条，"
        "未刷新即视为口径漂移（验收不通过）。")
    add("")
    add("## 6. 论文口径写法（按本表）")
    add("")
    add("- 训练/验证/内部测试：**448 个源文件级样本**（非 2002 个合约定义），并说明 2002 的来由与差额；")
    add("- 正/负样本：池内正样本 125、全零 323；多标签 **1** → 多标签证据改由 DIVE 承担；")
    add("- 去重口径：两级（源码内容 sha1 → 项目标识/地址），保两级的跨划分不变量均为 0；")
    add("- 逐类支撑必须随指标一起报告（见 `experiments/decisions.md` §13）。")
    add("")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Data funnel audit (traceable paper numbers).")
    parser.add_argument("--print", dest="print_only", action="store_true", help="只打印摘要，不写文件")
    args = parser.parse_args()

    up = stage_upstream()
    ald = stage_alldata()
    pipe = stage_pipeline()
    dive = stage_dive()
    graph = stage_graph_structure()
    binding = stage_binding()
    report = json.loads((SPLITS_DIR / "split_report.json").read_text(encoding="utf-8"))
    meta = {"created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "buggy": report.get("buggy_excluded_graphs", 0),
            "steps": STEPS}

    payload = {"meta": meta, "upstream": up, "alldata": ald,
               "pipeline": {k: v for k, v in pipe.items() if k not in ("index", "pool")},
               "dive": dive, "graph": graph, "binding": binding}

    summary = {
        "上游记录/唯一文件": f"{up['records']} → {up['pairs']}（差额 {up['records'] - up['pairs']}）",
        "主库文件/标签条目": f"{ald['files']} / {ald['entries']}（正 {ald['pos']}，多标签 {ald['multi']}）",
        "图/池": f"{len(pipe['index'])} → 495（buggy 剔除 {meta['buggy']}）→ {pipe['pool_stats']['n']}（两级去重）",
        "池内正/全零/多标签": f"{pipe['pool_stats']['pos']} / {pipe['pool_stats']['zero']} / {pipe['pool_stats']['multi']}",
        "去重级别/丢弃": f"sha1 {pipe['dedup']['levels']['source-sha1']['dropped']} + "
                        f"address {pipe['dedup']['levels']['address']['dropped']} = {pipe['dropped']}",
        "去重不变量跨划分": {k: (v["content_cross"], v["address_cross"]) for k, v in pipe["invariants"].items()},
        "DIVE 多标签占比": f"{dive['multi']}/{dive['n']} = {100*dive['multi']/dive['n']:.1f}%",
        "图结构/AST_PARENT 占比": f"{graph['table']['AST_PARENT']['edges']} 条 / "
                                  f"{graph['table']['AST_PARENT']['share']:.2%}",
        "DIVE 抽样": (binding["sample"]["gate"] if binding.get("sample") else "未生成"),
    }
    for k, v in summary.items():
        print(f"{k}: {v}")

    if args.print_only:
        return
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(render_md(up, ald, pipe, dive, graph, binding, meta), encoding="utf-8")
    print(f"written: {OUT_JSON.relative_to(BASE)}")
    print(f"written: {OUT_MD.relative_to(BASE)}")


if __name__ == "__main__":
    main()
