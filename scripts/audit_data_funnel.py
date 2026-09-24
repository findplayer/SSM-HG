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

BASE = Path(__file__).resolve().parents[1]  # 仓库根（scripts/ 的上一级）；从任意 cwd 运行都成立
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


def redundancy_total(k_hist: dict) -> int:
    """Σ(k-1)×count：同一文件被多个类别文件夹重复收录所贡献的计数差额。

    纯函数，登记（stage_upstream）与渲染（render_md）共用，避免两处各算一遍而漂移。
    键可能是 str（已序列化）或 int（内存态）。
    """
    return sum((int(k) - 1) * v for k, v in k_hist.items())


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

    step("上游 MVD-HG-dataset", "类别文件夹 .sol 记录数（含跨类别重复）", len(records),
         "MVD-HG-dataset/*_contract/sol_source/**/*.sol",
         'find MVD-HG-dataset/*_contract/sol_source -name "*.sol" | wc -l',
         f"逐类：{dict(sorted(per_class.items()))}；注：上游仓库不作数据集用（只读参考）。"
         "**键为上游类别文件夹名（`<类>_contract`）**，统计口径是「该文件夹下的 .sol 记录数」；"
         "与下一阶段「主库逐类正样本条目数」**不是同一量**（文件夹记录数 vs 标签条目数），勿直接对比")
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
    assert redundancy_total(k_hist) == len(records) - len(uniq_pairs), \
        f"Σ(k-1)×count {redundancy_total(k_hist)} != {len(records)} - {len(uniq_pairs)}"
    step("上游 MVD-HG-dataset", "同一文件被 k 个类别文件夹收录的分布",
         {str(k): v for k, v in sorted(k_hist.items())},
         "MVD-HG-dataset/*_contract/sol_source", "",
         f"Σ(k-1)×count = {redundancy_total(k_hist)}，即差额 {len(records) - len(uniq_pairs)}"
         " 的全部构成（无其它去向）")
    return {"records": len(records), "pairs": len(uniq_pairs), "dirs": len(uniq_dirs),
            "contents": len(uniq_contents), "k_hist": {str(k): v for k, v in sorted(k_hist.items())},
            "inconsistent": len(inconsistent)}


# ---------------------------------------------------------------- 主库 alldata
def stage_alldata() -> dict:
    """主库 591 文件 = 上游唯一的 (dir,file) 各保留一份副本；标签 = 七类并集。"""
    files = sorted(ALDDATA_SRC.glob("*/*.sol"))
    dirs = {p.parent.name for p in files}
    entries = json.loads(LABEL_FILE.read_text(encoding="utf-8"))
    for e in entries:
        assert len(e["targets"]) == len(CLASSES), \
            f"targets 长度 {len(e['targets'])} != {len(CLASSES)}（列序即语义，禁止列宽漂移）"
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
    # 口径：逐类比较「主标签文件里第 i 类为正的合约名集合」↔「单类文件里任一类别为正的合约名集合」。
    # 左侧按第 i 类取，右侧按“有任一正标签”取（不做逐类归一）——这是**刻意从严**：单类文件里
    # 若混入只对别的类为正的合约，会被计入 mismatch，从而能抓出跨类别串类，比“两侧都按第 i 类取”更强。
    mismatch = 0
    for i, c in enumerate(CLASSES):
        per_file = {e["contract_name"].lower() for e in
                    json.loads((MVD_ROOT / f"{c}_contract/contract_labels.json").read_text(encoding="utf-8"))
                    if any(int(v) for v in (e["targets"] if isinstance(e["targets"], list) else [e["targets"]]))}
        main = {e["contract_name"].lower() for e in entries if int(e["targets"][i])}
        mismatch += len(per_file ^ main)
    step("主库 alldata", "主标签文件 vs 七类单类文件 差异条目数", mismatch,
         "alldata(readonly)/contract_labels.json ↔ MVD-HG-dataset/*_contract/contract_labels.json",
         "", "0 = 逐类自洽（且单类文件无跨类串类）；对称差口径见脚本内注释，为刻意从严的比较方式")
    return {"files": len(files), "entries": len(entries), "pos": pos, "multi": multi,
            "mismatch": mismatch, "per_class": per_class}


# ---------------------------------------------------------------- 解析/图/池/划分
def stage_pipeline() -> dict:
    """581 图 → 495（剔 buggy_*）→ 448（两级池去重）→ 358/45/45，含池内标签分布。"""
    report = json.loads((SPLITS_DIR / "split_report.json").read_text(encoding="utf-8"))
    if not FILTER_REPORT.exists():
        raise FileNotFoundError(f"缺过滤报告 {FILTER_REPORT}（决定 591→581 的口径来源，不能缺失）")
    filt = dict(re.findall(r"^(\w+)=(\S+)$", FILTER_REPORT.read_text(encoding="utf-8"), flags=re.M))
    # 所有取用的键都必须真实存在：`.get(k, 0)` 会把「解析失败」伪装成「数字为 0」写进论文表
    need = ("total_source_files", "assembly_gt50_lines", "delegatecall_dynamic_binding",
            "ast_failed", "cfg_failed", "dfg_failed", "cfgdetail_failed")
    missing_keys = [k for k in need if k not in filt]
    if missing_keys:
        raise ValueError(f"无法从 {FILTER_REPORT} 解析出 {missing_keys}；该文件为 `key=value` 单行格式，"
                         "解析失败即口径不明，不应用默认值掩盖")

    index, unmatched = dataset.build_index()
    pre_dedup = sorted(b for b in index
                       if not dataset.is_buggy_project(dataset.project_of_base(b)))
    # 池去重走 make_splits.dedup_pool（与划分同一条代码路径）
    kept, _dropped, _dstat = make_splits.dedup_pool(pre_dedup, BASE / "products/alldata/graphs")
    pool = sorted(kept)
    # 漏斗不变量（任一步口径漂移即报错，不静默）
    n_buggy = int(report.get("buggy_excluded_graphs", 0))
    assert len(index) - n_buggy == len(pre_dedup), \
        f"{len(index)} - {n_buggy} != {len(pre_dedup)}"
    # 去重逐级钉死：中间量（level-1 之后、level-2 之前的池规模）必须单独成立，
    # 否则「sha1 丢 45 + 地址丢 2」（和仍为 47）会让 448 依旧通过、而文档里的 449 已经错了。
    lv = report["dedup"]["levels"]
    lv1, lv2 = lv["source-sha1"]["dropped"], lv["address"]["dropped"]
    n_after_lv1 = len(pre_dedup) - lv1
    assert lv1 + lv2 == int(report["dedup"]["dropped_count"]), \
        f"逐级丢弃 {lv1}+{lv2} != dropped_count {report['dedup']['dropped_count']}（去重级别可能增删）"
    assert lv["source-sha1"]["groups"] == n_after_lv1, \
        f"level-1 组数 {lv['source-sha1']['groups']} != {len(pre_dedup)} - {lv1} = {n_after_lv1}"
    assert n_after_lv1 - lv2 == len(pool), f"{n_after_lv1} - {lv2} != {len(pool)}"
    assert len(pool) == int(report["unique_contracts"]), \
        f"pool {len(pool)} != report.unique_contracts {report['unique_contracts']}"

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

    n_src, n_asm, n_dyn = (int(filt["total_source_files"]),
                           int(filt["assembly_gt50_lines"]), int(filt["delegatecall_dynamic_binding"]))
    step("主库→图", "源码文件数（上一阶段）", n_src,
         "products/alldata/raw/filter_report.txt", "bash scripts/generate_all_ast_cfg_dfg.sh")
    step("主库→图", "过滤：assembly>50 行", n_asm,
         "products/alldata/raw/filter_report.txt", "")
    step("主库→图", "过滤：delegatecall 动态绑定", n_dyn,
         "products/alldata/raw/filter_report.txt", "")
    step("主库→图", "解析失败（AST/CFG/DFG/cfgdetail）",
         {k: int(filt[k]) for k in ("ast_failed", "cfg_failed", "dfg_failed", "cfgdetail_failed")},
         "products/alldata/raw/filter_report.txt", "",
         # 差额从两个真实数字相减得出（不写死分解式）：过滤器规则增删后这里仍自洽
         f"{n_src} - {n_src - len(index)}(被过滤) = {len(index)} = 已生成图数，无解析失败；"
         f"其中 assembly>50 行 {n_asm} 个；delegatecall 动态绑定 {n_dyn} 个"
         "（2026-09-14 起仅记账、不再剔除——原规则系统性删掉 SWC-112 访问控制样本本身）")
    step("图", "已生成异构图数", len(index),
         "products/alldata/graphs/*_pyg.pt（经 scripts/dataset.py::build_index）",
         "python scripts/dataset.py --check <base>")
    step("图→划分", "标签匹配失败（未进入划分）图数", len(unmatched),
         "products/alldata/splits/unmatched_contracts.txt", "python scripts/make_splits.py")
    step("图→划分", "剔除 buggy_* 注入噪声项目图数", n_buggy,
         "products/alldata/splits/split_report.json", "",
         f"{len(index)} - {n_buggy} = {len(pre_dedup)}；"
         "该剔除为实验室决策（大纲 5.1 未列），须在论文说明")
    step("图→划分", "池去重 level-1：源码内容 sha1 相同（同一份源码的副本）",
         {"dropped": lv1, "groups": lv["source-sha1"]["duplicate_groups"]},
         "products/alldata/splits/split_report.json::dedup",
         "python scripts/make_splits.py", f"{len(pre_dedup)} - {lv1} = {n_after_lv1}")
    step("图→划分", "池去重 level-2：项目标识/地址相同（同合约的另一份源码，字节可能不同）",
         {"dropped": lv2, "groups": lv["address"]["duplicate_groups"]},
         "products/alldata/splits/split_report.json::dedup", "",
         f"{n_after_lv1} - {lv2} = {len(pool)}；该组即全库唯一多标签样本"
         "（0x627fa62c…：1847 vs 1842 字节），sha1 抓不到，seed0 下曾被拆到 train/val"
         "——去重的实质收益在此")
    step("图→划分", "划分池样本数", len(pool),
         "products/alldata/splits/split_seed{0,1,2}.json", "",
         "样本单位 = 源文件（唯一标识 = 源码哈希 → 项目标识），非合约定义级；"
         "与 split_report.json::unique_contracts 逐次运行校验相等（脚本内断言）")
    split_sizes: dict[str, dict] = {}
    for seed in (0, 1, 2):
        d = json.loads((SPLITS_DIR / f"split_seed{seed}.json").read_text(encoding="utf-8"))
        sizes = {"train": len(d["train"]), "val": len(d["val"]), "test": len(d["test"])}
        assert sum(sizes.values()) == len(pool), f"seed{seed} 划分规模之和 != 池规模 {len(pool)}"
        split_sizes[str(seed)] = sizes
        rc = report["rule_check"]["seeds"][str(seed)]
        step("图→划分", f"seed{seed} 划分规模", sizes,
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
            "dropped": report["dedup"]["dropped_count"],
            "pre_dedup_n": len(pre_dedup), "buggy": n_buggy, "split_sizes": split_sizes,
            # 漏斗起点：以 `*_pyg.pt`（可训练样本）为口径的图数。与 stage_graph_structure 的
            # `*_hetero.json` 图数是**两个来源**，main 里断言相等（孤立 _hetero.json / 缺 .pt 即报错）
            "n_graphs_indexed": len(index),
            "report": report}


# ------------------------------------------------- 上游类别文件夹记录数 ≠ 正例数（三层漏斗）
def stage_class_folder_vs_labels(index: dict[str, list[int]], pool: list[str]) -> dict:
    """逐类拆解「类别文件夹记录数 → 上游自己标注的正例数」，并与本仓池正例对拍。

    动机（2026-09-23）：`MVD-HG-dataset/<类>_contract/sol_source/` 的目录数（88–190）常被
    误读为「MVD-HG 该类数据集的正例数」。它只是**源码池记录数**，有三层虚高：
      ① 跨类别重复收录（同一文件进多个类文件夹，合计 255 条重复计数）；
      ② `buggy_*` 注入副本被复制进**全部 7 个文件夹**（每类 40–45 条）；
      ③ **文件夹归属 ≠ 标签** —— 文件夹里的部署合约，上游自己的单类标签文件
         `<类>_contract/contract_labels.json` 判它们**没有**该类漏洞。
    本函数把 ①→②→③ 逐类钉死，并断言 ⑤ == ⑥（上游标签剔 buggy 后的唯一正例 == 本仓池该类正例）。

    参数由 main 传入 `stage_pipeline()` 的 `index`/`pool`，标签键走 `scripts/dataset.py`
    与训练**同一条代码路径**（`strip_project_prefix` / `project_of_base`），不二次实现。
    """
    rows: list[dict] = []
    for i, cls in enumerate(CLASSES):
        class_dir = MVD_ROOT / f"{cls}_contract"
        records = len(glob.glob(str(class_dir / "sol_source" / "*" / "*.sol")))
        folder_keys = {dataset.strip_project_prefix(p.name)
                       for p in (class_dir / "sol_source").iterdir() if p.is_dir()}
        entries = json.loads((class_dir / "contract_labels.json").read_text(encoding="utf-8"))
        pos_keys: set[str] = set()
        neg_keys: set[str] = set()
        for e in entries:
            name = str(e.get("contract_name") or "")
            if "-" not in name:
                continue
            targets = e["targets"]
            # 单类文件的 targets 是标量 0/1；若哪天变成 list，说明拿错了文件（手册 §12 第 17 条）
            assert not isinstance(targets, list), (
                f"{class_dir.name}/contract_labels.json 的 targets 应为单类标量，出现 list——"
                "疑似把七维主标签文件当单类文件读，拒绝继续")
            key = dataset.strip_project_prefix(name.split("-", 1)[0])
            (pos_keys if int(targets) == 1 else neg_keys).add(key)

        nonbuggy = {k for k in folder_keys if not k.startswith("buggy_")}
        pos_nonbuggy = {k for k in pos_keys if not k.startswith("buggy_")}
        only_neg = {k for k in nonbuggy if k in neg_keys and k not in pos_keys}
        pool_pos = {dataset.project_of_base(b) for b in pool if index[b][i] == 1}
        # 不变量 1：每个非 buggy 项目键都被上游明确判过 0 或 1，无“未标注”的第三态
        assert only_neg | pos_nonbuggy == nonbuggy, (
            f"{cls}：③+⑤={len(only_neg)}+{len(pos_nonbuggy)} != 非 buggy 键 {len(nonbuggy)}"
            f"（残差 {sorted(nonbuggy - only_neg - pos_nonbuggy)[:5]}）——上游标签覆盖出现空洞")
        # 不变量 2：上游标签（剔 buggy）的唯一正例 == 本仓 453 池该类正例（逐类恒等）
        assert pos_nonbuggy == pool_pos, (
            f"{cls}：上游标签正例 {len(pos_nonbuggy)} != 本仓池正例 {len(pool_pos)}；"
            f"仅在标签 {sorted(pos_nonbuggy - pool_pos)[:5]}；仅在池 {sorted(pool_pos - pos_nonbuggy)[:5]}")
        rows.append({"class": cls, "folder_records": records,
                     "nonbuggy_keys": len(nonbuggy), "labeled_negative": len(only_neg),
                     "labeled_positive": len(pos_nonbuggy), "pos_nonbuggy": len(pos_nonbuggy),
                     "pool_pos": len(pool_pos), "buggy_positive_keys": len(pos_keys - pos_nonbuggy)})

    sums = {k: sum(r[k] for r in rows)
            for k in ("folder_records", "nonbuggy_keys", "labeled_negative",
                      "labeled_positive", "pos_nonbuggy", "pool_pos", "buggy_positive_keys")}
    step("上游类别文件夹 × 上游单类标签文件",
         "文件夹记录数 → 剔除 buggy → 上游标签正例 → 本仓池正例（逐类）",
         {r["class"]: [r["folder_records"], r["nonbuggy_keys"], r["labeled_negative"],
                       r["labeled_positive"], r["pool_pos"]] for r in rows},
         "MVD-HG-dataset/<类>_contract/{sol_source,contract_labels.json}"
         " ↔ products/alldata/splits/split_seed0.json + alldata(readonly)/contract_labels.json",
         "", "五列依次为 ①文件夹 .sol 记录数（含跨类重复）②非 buggy 项目键 ③其中上游标签判 **0** "
         "④其中上游标签判 **1** ⑤本仓 453 池正例；脚本内断言 ②=③+④ 且 ④=⑤ 逐类成立。"
         "⚠ 另有一个**含 buggy 的正例数**（= ④ + 被判 1 的 buggy 项目键，逐类 40/45/40/40/40/45/45 个）"
         "在本数据上**恰好恒等于 ③**（因 `非buggy键 = buggy正例键 + 2×④`），故不单列以免误导")
    step("上游类别文件夹 × 上游单类标签文件", "⑤ 上游标签正例（剔 buggy）与 ⑥ 本仓池正例 恒等类数",
         f"{sum(1 for r in rows if r['pos_nonbuggy'] == r['pool_pos'])}/{len(rows)}",
         "同上一行", "", "7/7 = 本仓多标签池是上游标签的忠实投影，多标签改造未丢/未造正例")
    return {"rows": rows, "sums": sums, "identity_classes": sum(1 for r in rows if r["pos_nonbuggy"] == r["pool_pos"])}


# ---------------------------------------------------------------- DIVE 抽样门槛
def stage_dive() -> dict:
    """DIVE 外部测试集抽样门槛核查（含多标签期望）。"""
    if not DIVE_LABELS.exists():
        raise FileNotFoundError(f"缺 DIVE 标签 {DIVE_LABELS}（外部测试门槛无法评估，不能静默跳过）")
    entries = json.loads(DIVE_LABELS.read_text(encoding="utf-8"))
    n = len(entries)
    if n == 0:
        raise ValueError(f"{DIVE_LABELS} 为空")
    per = collections.Counter()
    multi = 0
    for e in entries:
        t = [int(v) for v in e["targets"]]
        assert len(t) == len(CLASSES), f"targets 长度 {len(t)} != {len(CLASSES)}（列序即语义，须先对齐）"
        for i, v in enumerate(t):
            per[CLASSES[i]] += v
        multi += 1 if sum(t) >= 2 else 0

    out = {}
    for size in (500, 900):
        exp = {c: per[c] / n * size for c in CLASSES}
        out[str(size)] = {"per_class_expected": {c: round(exp[c], 1) for c in CLASSES},
                          "multi_label_expected": round(multi / n * size, 1)}
    # front_running ≥ 20 的超几何概率（均匀无放回抽样）
    # 边界：该类正样本为 0 时超几何无定义（sf 会报错或恒 0）→ 显式记 0 并注明不可达
    prob = None
    if per["front_running"] > 0:
        try:
            from scipy.stats import hypergeom
            for size in (500, 900, 1100):
                p = float(hypergeom.sf(19, n, per["front_running"], size))
                out.setdefault("front_running_p_ge20", {})[str(size)] = round(p, 3)
            prob = out["front_running_p_ge20"]
        except Exception:  # scipy 不可用则只给期望
            pass
    else:
        out["front_running_p_ge20"] = {str(s): 0.0 for s in (500, 900, 1100)}
        out["front_running_p_ge20_note"] = "DIVE 内 front_running 正样本为 0，≥20 不可达（P=0）"

    step("DIVE 外部测试", "标签条目数 / 多标签条数 / 全零条数",
         {"n": n, "multi": multi, "zero": sum(1 for e in entries if sum(int(v) for v in e["targets"]) == 0)},
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
# 物理关系名的**单一事实来源**是 dataset.RELATION_NAMES（{编号: 名}）；此处只保留论文侧的语义注解。
# 注意不要用 enumerate(RELATION_NAMES)（那是 dict，迭代得到的是编号而非名字）。
PAPER_SEMANTIC = {
    0: "CFG_FLOW（含 seq/true/false 子类）",
    1: "AST_PARENT",
    2: "AST_PARENT（实现细节：多个 AST 节点落在同一 CFGNode）",
    3: "DFG_DEP",
    4: "CALLBACK_RISK",
}
assert len(dataset.RELATION_NAMES) == 5, f"物理关系数变了：{dataset.RELATION_NAMES}"
assert set(PAPER_SEMANTIC) == set(dataset.RELATION_NAMES), (PAPER_SEMANTIC, dataset.RELATION_NAMES)
EDGE_TYPES: tuple[str, ...] = tuple(dataset.RELATION_NAMES[k] for k in sorted(dataset.RELATION_NAMES))
RELATION_MAP = {k: (dataset.RELATION_NAMES[k], PAPER_SEMANTIC[k]) for k in sorted(dataset.RELATION_NAMES)}


def accumulate_graph_structure(graphs: list[Path]) -> dict:
    """逐 `_hetero.json` 累计边类型规模 / 覆盖图数 / 节点数 / AST 未映射数（纯读，可单测）。

    边类型键**必须是物理关系名**（`dataset.RELATION_NAMES` 的值）。若键对不上（例如换成编号），
    `Counter` 的默认值会让后续查表静默返回 0、产出一张“全 0 表”；故此处直接报错而非容忍。
    """
    totals: collections.Counter = collections.Counter()
    graphs_with: collections.Counter = collections.Counter()
    nodes = 0
    ast_unmapped = 0
    for path in graphs:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        edges_by_type = data.get("edges")
        if not isinstance(edges_by_type, dict):
            raise ValueError(f"{Path(path).name} 缺 edges 字段（期望 {{边类型: 边列表}}）")
        unknown = set(edges_by_type) - set(EDGE_TYPES)
        if unknown:
            raise ValueError(f"{Path(path).name} 出现未知边类型键 {sorted(unknown)}；"
                             f"期望 {list(EDGE_TYPES)}（dataset.RELATION_NAMES）")
        nodes += len(data.get("nodes", []))
        for key, edges in edges_by_type.items():
            totals[key] += len(edges)
            if edges:
                graphs_with[key] += 1
        ast_unmapped += int(data.get("meta", {}).get("ast_unmapped_edge_count") or 0)
    return {"totals": totals, "graphs_with": graphs_with, "nodes": nodes,
            "ast_unmapped": ast_unmapped, "n_graphs": len(graphs)}


def stage_graph_structure() -> dict:
    """图结构口径：逐边类型规模与覆盖图数、AST 稀疏性、关系编号映射（论文 4 语义边 / 实现 5 物理关系）。"""
    graphs = sorted((BASE / "products/alldata/graphs").glob("*_hetero.json"))
    acc = accumulate_graph_structure(graphs)
    totals, graphs_with = acc["totals"], acc["graphs_with"]
    nodes, ast_unmapped = acc["nodes"], acc["ast_unmapped"]

    total_edges = sum(totals.values())
    table = {key: {"edges": totals[key], "graphs_with_edge": graphs_with[key],
                   "edges_per_graph": round(totals[key] / len(graphs), 2),
                   "share": round(totals[key] / total_edges, 4)}
             for key in EDGE_TYPES}
    assert sum(v["edges"] for v in table.values()) == total_edges, "逐边类型表未覆盖全部边"

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
            "graphs": acc["n_graphs"],
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
              binding: dict, meta: dict, folder: dict) -> str:
    lines: list[str] = []
    add = lines.append
    lv1 = pipe["dedup"]["levels"]["source-sha1"]["dropped"]
    lv2 = pipe["dedup"]["levels"]["address"]["dropped"]
    n_all = pipe["n_graphs_indexed"]      # 漏斗起点：以 *_pyg.pt 计的图数（§0 用）
    n_pool = pipe["pool_stats"]["n"]
    s = folder["sums"]                    # §0 与 §3 共用，避免两处各算一遍而漂移
    # 三个划分种子规模一致（make_splits 固定比例）→ 写成 train/val/test 三元组
    sizes = {tuple(sorted(v.items())) for v in pipe["split_sizes"].values()}
    assert len(sizes) == 1, f"三种子划分规模不一致，不能合并书写：{pipe['split_sizes']}"
    s0 = pipe["split_sizes"]["0"]
    split_str = f"{s0['train']}/{s0['val']}/{s0['test']}"
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
    add(f"- 图与划分：**{n_all}** 图 → 剔除 {meta['buggy']} 个 `buggy_*` → 池 **{pipe['pre_dedup_n']}** → 两级去重"
        f"（sha1 丢 {lv1}、地址丢 {lv2}）→ **{n_pool}** → {split_str}；"
        f"池内正样本 {pipe['pool_stats']['pos']}、全零 {pipe['pool_stats']['zero']}、"
        f"多标签 **{pipe['pool_stats']['multi']}**。")
    add(f"- 上游类别文件夹的 **88–190 不是正例数**：其中 {s['folder_records'] - s['nonbuggy_keys']} 条是 "
        f"`buggy_*` 副本，另有 {s['labeled_negative']} 个非 buggy 项目键被上游**自己的**单类标签文件判为"
        f"**负例**；按上游标签算的正例 = **{s['labeled_positive']}**，与本仓 {n_pool} 池正例 "
        f"**{folder['identity_classes']}/{len(folder['rows'])} 逐类恒等**（详见 §3）。")
    add("")
    add("## 1. `846 → 591` 的 255 个去向（逐条拆解）")
    add("")
    add(f"- {up['records']} = 七个 `<类>_contract/sol_source` 目录里 `.sol` 记录的**合计**；")
    add(f"- {up['pairs']} = 唯一（项目目录, 文件名）对，即主库实际保留的源码文件数；")
    add(f"- **差额 {up['records'] - up['pairs']} = 「同一 (项目目录, 文件名) 被多个类别文件夹重复收录」的重复计数之和**：")
    add("")
    add("| 同一文件被 k 个类别文件夹收录 | 文件数 | 贡献的重复计数 (k-1)×文件数 |")
    add("| --- | --- | --- |")
    total = redundancy_total(up["k_hist"])
    for k, v in up["k_hist"].items():
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
        val = (str(s["value"]) if not isinstance(s["value"], (dict, list))
               else f"`{json.dumps(s['value'], ensure_ascii=False)}`")
        # 单元格内不得出现裸 `|`（会截断 Markdown 表格）；dict 经 json.dumps 后同样可能带 `|`，一并转义
        src = s["source"].replace("|", "/")
        cmd = f"<br>`{s['command']}`" if s["command"] else ""
        note = (s["note"] or "").replace("|", "/")
        add(f"| {s['stage']} | {s['name']} | {val.replace('|', '/')} | {src}{cmd} | {note} |")
    add("")
    add("## 3. 类别文件夹记录数 ≠ 正例数（两级虚高，2026-09-23）")
    add("")
    add("> 动机：`MVD-HG-dataset/<类>_contract/sol_source/` 的**目录数**（88–190）常被误读为"
        "「MVD-HG 该类数据集的正例数」。它只是**源码池记录数**，有两级虚高；"
        "与「本仓池正例 4–50」**不是同一量在缩水**，而是两个不同的量在对照。")
    add("")
    add("| 漏洞类 | ① 文件夹 `.sol` 记录数 | ② 其中非 `buggy_*` 项目键 | "
        "③ 上游自己的标签判 **0** | ④ 上游自己的标签判 **1** | ⑤ 本仓 453 池正例 |")
    add("| --- | --- | --- | --- | --- | --- |")
    for r in folder["rows"]:
        add(f"| {r['class']} | {r['folder_records']} | {r['nonbuggy_keys']} | {r['labeled_negative']} | "
            f"**{r['labeled_positive']}** | **{r['pool_pos']}** |")
    s = folder["sums"]
    add(f"| **合计** | **{s['folder_records']}** | **{s['nonbuggy_keys']}** | **{s['labeled_negative']}** | "
        f"**{s['labeled_positive']}** | **{s['pool_pos']}** |")
    add("")
    add("- 不变量 1（脚本内断言）：**② = ③ + ④ 逐类成立，无残差** ⇒ 类别文件夹里每个非 `buggy_*` 项目键，"
        "都被上游**自己的**单类标签文件明确判为 0 或 1，不存在「未标注」的第三态。")
    add(f"- 不变量 2（脚本内断言）：**④ = ⑤ 逐类恒等（{folder['identity_classes']}/{len(folder['rows'])}）** "
        "⇒ 本仓 453 池是上游标签的**忠实投影**，多标签改造既未丢正例、也未造正例。")
    add("- 两层虚高的来源：①→② 是 `buggy_*` 注入副本（45 个项目被**复制进全部 7 个文件夹**，"
        f"每类 40–45 条，合计 {s['folder_records'] - s['nonbuggy_keys']} 条记录）；"
        "②→③ 是**文件夹归属 ≠ 标签**——类别文件夹里收进来的部署合约，上游自己的标签文件判它们"
        f"**没有**该类漏洞（access_control：74 个非 buggy 键里 {folder['rows'][0]['labeled_negative']} 个判 0）。")
    add("- ⇒ 论文里若要引用上游的「88–190」，**必须**写成「`<类>_contract` 文件夹的 `.sol` 记录数"
        "（含跨类重复与非 buggy 部署合约）」，**不得**写成「该类正例数」；"
        "以上游自己发布的标签为准，两边逐类正例**相同**。")
    buggy_pos = "/".join(str(r["buggy_positive_keys"]) for r in folder["rows"])
    add(f"- 🔴 **与 MVD-HG 论文 Table 1 的对应（2026-09-23 核对）**：该表「Contract-Origin files」逐类 "
        f"= 114/120/92/88/142/100/190，**与本表第 ① 列逐位相同** ⇒ 论文列的正是**语料文件数（正+负）**，"
        f"**论文从未把它写成「正例数」**。其每类正例 = ④ + 被判 1 的 buggy 项目键（逐类 {buggy_pos} 个）"
        f"，即 **57/60/46/44/71/50/95**；**剔注入样本后 = ④ = ⑤，与本仓逐类相同**。详见 "
        f"`experiments/decisions.md` §51.5。")
    add("")
    add("## 4. DIVE 外部测试抽样门槛")
    add("")
    add(f"- DIVE 标签 {dive['n']} 条，多标签 {dive['multi']} 条（{100*dive['multi']/dive['n']:.1f}%）。")
    for size, info in dive["expectations"].items():
        if size in ("front_running_p_ge20", "front_running_p_ge20_note"):
            continue
        add(f"- n={size} 均匀抽样：多标签期望 {info['multi_label_expected']}；"
            f"逐类期望 {info['per_class_expected']}")
    if dive.get("front_prob"):
        add(f"- front_running 达到 ≥20 的超几何概率（抽样前口径）：{dive['front_prob']}")
    add("- 结论：多标签计数在 DIVE 上不是退化项（占比高），外部测试的多标签证据成立；"
        "均匀抽样在 500 规模下对 front_running 不可达（期望 12.2），**抽样规模已定稿 n=900**"
        "（2026-09-12 P1；固定 seed，一次确定事件；实测结果见下表），后备路径见 decisions §13。")
    add("")
    add("## 5. 图结构口径（AST 稀疏性 / 关系数映射）")
    add("")
    add(f"- {graph['graphs']} 图 / {graph['nodes']} 节点 / {graph['edges']} 边"
        "（本节全部来自 `*_hetero.json`；与 §0 的 `*_pyg.pt` 图数相等，脚本内断言）。")
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
    add("## 6. 口径绑定指纹与刷新义务（防文档/产物漂移）")
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
    add("## 7. 论文口径写法（按本表）")
    add("")
    add(f"- 训练/验证/内部测试：**{n_pool} 个源文件级样本**（非 {ald['entries']} 个合约定义），"
        f"并说明 {ald['entries']} 的来由与差额；")
    add(f"- 正/负样本：池内正样本 {pipe['pool_stats']['pos']}、全零 {pipe['pool_stats']['zero']}；"
        f"多标签 **{pipe['pool_stats']['multi']}** → 多标签证据改由 DIVE 承担；")
    add("- 去重口径：两级（源码内容 sha1 → 项目标识/地址），保两级的跨划分不变量均为 0；")
    add("- 逐类支撑必须随指标一起报告（见 `experiments/decisions.md` §13）。")
    add("- 🔴 与 MVD-HG 对比时，**上游的「88–190」只能写成「类别文件夹的 `.sol` 记录数」**，"
        "不得写成「该类正例数」——它是文件夹记录数，而以上游自己发布的标签为准，两边逐类正例相同"
        "（§3 表，`experiments/decisions.md` §51）。")
    add("")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Data funnel audit (traceable paper numbers).")
    parser.add_argument("--print", dest="print_only", action="store_true", help="只打印摘要，不写文件")
    args = parser.parse_args()

    up = stage_upstream()
    ald = stage_alldata()
    pipe = stage_pipeline()
    # 依赖 pipe 的 index/pool（标签键走 dataset 同一条代码路径），故在 stage_pipeline 之后调用
    folder = stage_class_folder_vs_labels(pipe["index"], pipe["pool"])
    dive = stage_dive()
    graph = stage_graph_structure()
    # 两个图数来源必须一致：`*_pyg.pt`（漏斗/划分口径）与 `*_hetero.json`（边结构口径）。
    # 不等即说明有孤立 _hetero.json 或缺失 .pt，此时任何“N 图”的写法都会有两套数字。
    assert pipe["n_graphs_indexed"] == graph["graphs"], (
        f"可训练图数({pipe['n_graphs_indexed']} = *_pyg.pt) != 异构图数({graph['graphs']} = *_hetero.json)；"
        "先查 products/alldata/graphs/ 下是否有孤立 _hetero.json 或缺失 .pt")
    binding = stage_binding()
    report = pipe["report"]  # 与 stage_pipeline 同一次读取，避免两份来源漂移
    meta = {"created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "buggy": pipe["buggy"],
            "steps": STEPS}

    payload = {"meta": meta, "upstream": up, "alldata": ald,
               "pipeline": {k: v for k, v in pipe.items() if k not in ("index", "pool", "report")},
               "class_folder_funnel": folder,
               "dive": dive, "graph": graph, "binding": binding}

    summary = {
        "上游记录/唯一文件": f"{up['records']} → {up['pairs']}（差额 {up['records'] - up['pairs']}）",
        "主库文件/标签条目": f"{ald['files']} / {ald['entries']}（正 {ald['pos']}，多标签 {ald['multi']}）",
        "图/池": f"{pipe['all_stats']['n']} → {pipe['pre_dedup_n']}（buggy 剔除 {meta['buggy']}）"
                 f"→ {pipe['pool_stats']['n']}（两级去重）",
        "池内正/全零/多标签": f"{pipe['pool_stats']['pos']} / {pipe['pool_stats']['zero']} / {pipe['pool_stats']['multi']}",
        "去重级别/丢弃": f"sha1 {pipe['dedup']['levels']['source-sha1']['dropped']} + "
                        f"address {pipe['dedup']['levels']['address']['dropped']} = {pipe['dropped']}",
        "去重不变量跨划分": {k: (v["content_cross"], v["address_cross"]) for k, v in pipe["invariants"].items()},
        "DIVE 多标签占比": f"{dive['multi']}/{dive['n']} = {100*dive['multi']/dive['n']:.1f}%",
        "图结构/AST_PARENT 占比": f"{graph['table']['AST_PARENT']['edges']} 条 / "
                                  f"{graph['table']['AST_PARENT']['share']:.2%}",
        "上游文件夹记录→标签正例→池正例": (
            f"{folder['sums']['folder_records']} → {folder['sums']['pos_nonbuggy']} → "
            f"{folder['sums']['pool_pos']}（恒等 {folder['identity_classes']}/7 类）"),
        "DIVE 抽样": (binding["sample"]["gate"] if binding.get("sample") else "未生成"),
    }
    for k, v in summary.items():
        print(f"{k}: {v}")

    if args.print_only:
        return
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text(render_md(up, ald, pipe, dive, graph, binding, meta, folder), encoding="utf-8")
    print(f"written: {OUT_JSON.relative_to(BASE)}")
    print(f"written: {OUT_MD.relative_to(BASE)}")


if __name__ == "__main__":
    main()
