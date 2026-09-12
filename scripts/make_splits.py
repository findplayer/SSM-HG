#!/usr/bin/env python3
"""M5 数据划分（手册 10.2，2026-09-07）：唯一合约 8:1:1，产出 `products/alldata/splits/`。

设计（对齐大纲 5.1 / 手册 10.2）：
  - 以**唯一合约（图）**为划分单位，`random.Random(seed)` 打乱（固定种子可复现）；
  - 同一合约绝不跨划分（防泄漏）；
  - 标签匹配键 = 项目前缀并集（复用 dataset.build_index，不重复标签逻辑）；
  - 主实验**剔除 buggy_* 噪声项目**（asd_buggy_*/nasd_buggy_*：每合约同款注入噪声标签，
    与具体注入特征不对应），剔除明细写入 unmatched_contracts.txt 单独一节；
    “含 buggy_*”的对照实验由后续消融脚本另行组合，不改变本文件输出；
  - **两级池去重**（大纲 5.1 第三条「唯一标识优先使用源码哈希，并使用合约文件名、合约地址
    或项目标识」；2026-09-12 P1 落地，`--dedup source-sha1+address` 默认）：在**剔除 buggy_*
    之后、划分之前**执行，每级都是「同组只保留相对源码路径字典序首个」（确定性，与文件系统
    枚举顺序无关）：
      - level-1 `source-sha1`：源码文件内容 sha1 相同 → 同一份源码的副本（46 组）；
      - level-2 `address`：`project_of_base`（剥 asd_/nasd_ 前缀后小写）相同 → 同一合约的
        另一份源码副本。此级的必要性：`build_index` 的标签键本就是项目前缀，同项目样本
        **标签向量必然相同**；两份源码字节可能不同（实测 0x627fa62c… 组 1847 vs 1842 字节），
        sha1 抓不到，而它们一旦分入不同划分就是实打实的标签泄漏（seed0 下正是全库唯一
        多标签样本被拆到 train/val）。
    两级丢弃样本均写入 `dedup_dropped.txt` 与 `split_report.json::dedup`，不静默丢弃；
    顺序固定「先剔 buggy_*、再去重」：反序会把“与 buggy 副本同内容的正常样本”一并丢掉。
    去重后仍会**逐种子校验**两级不变量（同 sha1 / 同地址不得跨划分），写入
    `split_report.json::rule_check::seeds.*.*_dedup_ok`。`--dedup source-sha1` 仅做第一级；
    `--dedup none` 仅用于复现去重前的历史产物（如 `random_snapshot/`）。
  - 匹配不上的图写入 unmatched_contracts.txt 记录并报告（不静默丢弃）；
  - **覆盖约束校正**（大纲 5.1 第三条 2026-09-12 新增半句，`--strategy constrained` 默认）：
    在固定种子随机划分基础上施加覆盖约束——C1 验证集与内部测试集合计的每类正样本 ≥
    该类正样本总数的 `--min-pos-ratio`（默认 0.30）；C2 两个划分各自每类正样本 ≥
    `MIN_POS_PER_SPLIT`（=1）；校正通过少量**确定性合约替换**实现（换入稀有类正样本携带者、
    换出全零合约），不可行时报错并由实验方按大纲更换种子；
  - `--strategy random`＝旧随机划分快照，**输出隔离**到 `<out-dir>/random_snapshot/`（仅作
    对照/复现，不可能覆盖正典产物）。

产物（`--strategy constrained` 写入 `products/alldata/splits/`；random 模式写同名文件到隔离子目录）：
  - split_seed{seed}.json   {"seed":..,"ratio":..,"train":[...],"val":[...],"test":[...]}
                            （载荷保持四键不变，保证 random 模式可逐字节复现旧快照）
  - splits.csv              seed,sample_id,split,y0..y6（1485 行 = 495×3）
  - split_report.json       每类正/负样本、正负比、唯一合约、多标签、全 0、三划分数量，
                            另含逐种子×三划分逐类 support、C1/C2 检查（rule_check）与替换统计
  - coverage_swaps_seed{seed}.txt  覆盖校正替换清单（换入/换出合约 ID + 各自 7 维标签向量）
  - split_metadata_seed{seed}.json  参数、策略/约束、输入摘要与输出文件 sha256
  - unmatched_contracts.txt 匹配失败列表 + buggy_* 剔除明细
  - dedup_dropped.txt      两级池去重丢弃清单（被丢 base + 级别 + 组键 + 保留 base）

CLI：`python scripts/make_splits.py --strategy constrained --seeds 0,1,2 --split 0.8,0.1,0.1 --min-pos-ratio 0.30`
     （`--dedup source-sha1+address` 默认；`--dedup source-sha1` / `none` 见上）
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import platform
import random
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

from dataset import BASE, build_index, is_buggy_project, project_of_base

VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]

# C2：每个划分（val/test）中每类正样本的下限（大纲 5.1 覆盖约束校正，2026-09-12）
MIN_POS_PER_SPLIT = 1

# 池去重（大纲 5.1 第三条）；ALDDATA_SRC 为主库源码根（只读）
ALDDATA_SRC = Path(f"{BASE}/alldata(readonly)/alldata_sol_source")
DEDUP_MODES = ("source-sha1+address", "source-sha1", "none")
DEDUP_LEVELS = {"source-sha1+address": ("source-sha1", "address"),
                "source-sha1": ("source-sha1",), "none": ()}


def sha1_file(path: Path | str, chunk_size: int = 1 << 20) -> str:
    """流式 sha1（大文件不整读进内存）。"""
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(chunk_size)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def source_path_of(base: str, graph_dir: Path | str) -> Path:
    """图前缀 → 源码文件路径：先读 `<base>_hetero.json` 的 meta.source_path，再按目录拼接。

    两条路径都不存在即抛 FileNotFoundError（**不静默跳过**：去重规则依赖每个样本的源码内容）。
    """
    meta_path = Path(graph_dir) / f"{base}_hetero.json"
    if meta_path.exists():
        src = json.loads(meta_path.read_text(encoding="utf-8")).get("meta", {}).get("source_path")
        if src and Path(src).exists():
            return Path(src)
    proj, _, stem = base.partition("__")
    cand = ALDDATA_SRC / proj / f"{stem}.sol"
    if cand.exists():
        return cand
    raise FileNotFoundError(f"{base}: 找不到源码文件（试过 {meta_path} 的 meta.source_path 与 {cand}）")


def dedup_pool(bases: list[str] | set[str], graph_dir: Path | str,
               levels: tuple[str, ...] = ("source-sha1", "address"),
               source_of=None) -> tuple[list[str], list[dict], dict]:
    """两级池去重（大纲 5.1 第三条「唯一标识优先源码哈希，并可使用合约地址/项目标识」）。

    level-1 `source-sha1`：按源码文件内容 sha1 分组；
    level-2 `address`：按 `project_of_base`（剥 asd_/nasd_ 前缀后小写）分组——标签键即项目
    前缀，同组样本标签向量必然相等，字节可能不同（sha1 抓不到）；
    每级均为「同组保留**相对源码路径字典序首个**（平局再按 base 名）」，逐级串行，完全确定性。
    返回 (kept 升序列表, dropped 明细[base/level/group_key/kept], stats)。
    `source_of` 可注入（便于单测用临时目录，不需要真实产物）。
    """
    source_of = source_of or (lambda b: source_path_of(b, graph_dir))
    ordered = sorted(bases)
    hash_of: dict[str, str] = {}
    rel_of: dict[str, str] = {}
    for base in ordered:
        path = Path(source_of(base))
        hash_of[base] = sha1_file(path)
        try:
            rel_of[base] = path.relative_to(BASE).as_posix()
        except ValueError:
            rel_of[base] = path.as_posix()

    kept = ordered
    dropped: list[dict] = []
    level_stats: dict[str, dict] = {}
    for level in levels:
        groups: dict[str, list[str]] = defaultdict(list)
        for base in kept:
            key = hash_of[base] if level == "source-sha1" else project_of_base(base)
            groups[key].append(base)
        next_kept: list[str] = []
        dup_groups = 0
        for key, items in groups.items():
            items.sort(key=lambda b: (rel_of[b], b))
            next_kept.append(items[0])
            if len(items) > 1:
                dup_groups += 1
            for dup in items[1:]:
                dropped.append({"base": dup, "level": level, "group_key": key,
                                "kept": items[0], "kept_source": rel_of[items[0]],
                                "dropped_source": rel_of[dup]})
        kept = sorted(next_kept)
        level_stats[level] = {"groups": len(groups), "duplicate_groups": dup_groups,
                              "dropped": sum(1 for d in dropped if d["level"] == level)}
    dropped.sort(key=lambda d: (d["level"], d["base"]))
    stats = {"levels": level_stats, "hash_of": hash_of, "rel_of": rel_of,
             "rule": "按唯一标识（源码 sha1 → 项目标识/地址）分组，同组保留相对源码路径字典序首个"}
    return kept, dropped, stats


def class_pos_counts(bases: list[str], index: dict[str, list[int]]) -> list[int]:
    """统计给定合约集合中七类的正样本数（顺序与 VULN_NAMES 一致）。"""
    counts = [0] * len(VULN_NAMES)
    for base in bases:
        for i, value in enumerate(index[base]):
            counts[i] += value
    return counts


def refine_coverage(train: list[str], val: list[str], test: list[str],
                    index: dict[str, list[int]], ratio: float,
                    per_split: int = MIN_POS_PER_SPLIT
                    ) -> tuple[list[str], list[str], list[str], dict]:
    """覆盖约束校正（大纲 5.1，2026-09-12）：在随机划分基础上做最小确定性替换。

    约束：C1 每类 val+test 正样本合计 ≥ ceil(ratio × 池内该类正样本数)；
          C2 val 与 test 各自每类正样本 ≥ per_split。
    规则（完全确定性，可复现）：缺口按（池内正样本数升序，类序）处理（稀有类优先）；
    换入＝按 train 顺序取第一个携带该类正样本的合约；换出＝从目标划分列表尾部向前取
    第一个 7 维全零合约（绝不换出正样本）；放置＝放入该类当前较少的一侧（平局→val）。
    不可行时抛 RuntimeError（由实验方按大纲更换种子重划）。
    返回 (train, val, test, stats)，stats 含 swaps_count/floor_fixes/swaps[(换入, 换出)]。
    """
    train, val, test = list(train), list(val), list(test)
    pool = train + val + test
    pos = class_pos_counts(pool, index)
    req = [math.ceil(ratio * pos[i] - 1e-9) for i in range(len(VULN_NAMES))]
    swaps: list[tuple[str, str]] = []
    floor_fixes = 0

    def count(arr: list[str], i: int) -> int:
        return sum(1 for b in arr if index[b][i])

    def swap_in(i: int, target: list[str], which: str) -> None:
        carrier = next((b for b in train if index[b][i] > 0), None)
        if carrier is None:
            raise RuntimeError(f"覆盖约束校正失败：训练集内无 {VULN_NAMES[i]} 正样本可换入")
        evicted = None
        for k in range(len(target) - 1, -1, -1):
            if not any(index[target[k]]):
                evicted = target.pop(k)
                break
        if evicted is None:
            raise RuntimeError(f"覆盖约束校正失败：{which} 划分内无可换出的全零合约")
        train.remove(carrier)
        target.append(carrier)
        train.append(evicted)
        swaps.append((carrier, evicted))

    # C1 配额修正（稀有类优先）
    for i in sorted(range(len(VULN_NAMES)), key=lambda i: (count(pool, i), i)):
        while count(val, i) + count(test, i) < req[i]:
            if count(val, i) <= count(test, i):
                swap_in(i, val, "val")
            else:
                swap_in(i, test, "test")

    # C2 每划分下限修正
    for i in range(len(VULN_NAMES)):
        for target, which in ((val, "val"), (test, "test")):
            if count(target, i) < per_split:
                swap_in(i, target, which)
                floor_fixes += 1

    # 校验（构造性保证；失败即报错，按大纲更换种子）
    for i, name in enumerate(VULN_NAMES):
        if count(val, i) + count(test, i) < req[i]:
            raise RuntimeError(f"覆盖约束校正失败：{name} 合计未达标")
        if count(val, i) < per_split or count(test, i) < per_split:
            raise RuntimeError(f"覆盖约束校正失败：{name} 未满足每划分 ≥{per_split}")
    for _, evicted in swaps:
        assert not any(index[evicted]), "换出的必须是全零合约"
    return train, val, test, {
        "swaps_count": len(swaps),
        "floor_fixes": floor_fixes,
        "swaps": [[carrier, evicted] for carrier, evicted in swaps],
    }


def make_split_for_seed(seed: int, included: set[str], index: dict[str, list[int]],
                        ratio: list[float], strategy: str,
                        min_pos_ratio: float) -> tuple[list[str], list[str], list[str], dict]:
    """为单个 seed 生成划分：固定种子随机基线（+ 可选覆盖约束校正）。

    返回 (train, val, test, coverage_stats)；strategy="random" 时 coverage_stats 为零值。
    """
    order = sorted(included)
    random.Random(seed).shuffle(order)
    total = len(order)
    n_train = int(round(total * ratio[0]))
    n_val = int(round(total * ratio[1]))
    train = order[:n_train]
    val = order[n_train:n_train + n_val]
    test = order[n_train + n_val:]
    assert len(train) + len(val) + len(test) == total, "split sizes mismatch"
    stats = {"swaps_count": 0, "floor_fixes": 0, "swaps": []}
    if strategy == "constrained":
        train, val, test, stats = refine_coverage(train, val, test, index, min_pos_ratio)
    return train, val, test, stats


def parse_args() -> argparse.Namespace:
    """CLI：--strategy / --seeds / --split / --min-pos-ratio / --graph-dir / --out-dir。"""
    parser = argparse.ArgumentParser(description="Split unique contracts into train/val/test (8:1:1).")
    parser.add_argument("--strategy", choices=["constrained", "random"], default="constrained",
                        help="constrained=固定种子随机划分+覆盖约束校正（主方案，默认）；"
                             "random=旧随机划分快照，输出隔离到 <out-dir>/random_snapshot/（仅对照/复现）。")
    parser.add_argument("--seeds", default="0,1,2",
                        help="Comma-separated random seeds (default 0,1,2).")
    parser.add_argument("--split", default="0.8,0.1,0.1",
                        help="Train/val/test ratio, must sum to 1.")
    parser.add_argument("--min-pos-ratio", type=float, default=0.30,
                        help="大纲 5.1（2026-09-12 修订）门槛：验证集+内部测试集每类正样本 "
                             "≥ 该类正样本总数的该比例（默认 0.30，替代旧 ≥20 个口径）。")
    parser.add_argument("--dedup", choices=list(DEDUP_MODES), default="source-sha1+address",
                        help="池级去重口径（大纲 5.1 第三条）：source-sha1+address=两级去重"
                             "（源码内容 sha1 → 项目标识/地址，默认，剔 buggy_* 之后、划分之前）；"
                             "source-sha1=只按源码内容；none=不去重（仅用于复现去重前历史产物）。")
    parser.add_argument("--graph-dir", default=f"{BASE}/products/alldata/graphs",
                        help="Directory containing *_pyg.pt.")
    parser.add_argument("--out-dir", default=f"{BASE}/products/alldata/splits",
                        help="Output directory for split files.")
    return parser.parse_args()


def main() -> None:
    """主流程：建索引 → 剔除 buggy_* → 逐种子 8:1:1（默认加覆盖约束校正）→ 写 splits/ 全套。"""
    args = parse_args()
    seeds = [int(s) for s in args.seeds.split(",")]
    ratio = [float(r) for r in args.split.split(",")]
    if len(ratio) != 3 or abs(sum(ratio) - 1.0) > 1e-9:
        raise ValueError(f"--split must be 3 numbers summing to 1, got {args.split}")

    out_dir = Path(args.out_dir)
    if args.strategy == "random":
        out_dir = out_dir / "random_snapshot"      # 输出隔离：random 永不触碰正典产物
        print(f"[random 对照模式] 输出隔离至 {out_dir}（不覆盖正典划分）")
    out_dir.mkdir(parents=True, exist_ok=True)

    index, unmatched = build_index(Path(args.graph_dir))
    pre_dedup = {base for base in index if not is_buggy_project(project_of_base(base))}
    buggy_excluded = sorted(set(index) - pre_dedup)
    unmatched = sorted(unmatched)

    # ---- 0) 两级池去重（大纲 5.1 第三条；剔 buggy_* 之后、划分之前）----
    kept, dropped, dedup_stats = dedup_pool(pre_dedup, args.graph_dir,
                                            levels=DEDUP_LEVELS[args.dedup])
    included = set(kept)
    hash_of = dedup_stats["hash_of"]
    dedup = {
        "mode": args.dedup,
        "rule": dedup_stats["rule"],
        "order": "先剔除 buggy_*，再去重（反序会连坐丢掉与 buggy 副本同内容的正常样本）",
        "pool_before_dedup": len(pre_dedup),
        "pool_after_dedup": len(included),
        "dropped_count": len(dropped),
        "levels": dedup_stats["levels"],
        "dropped": dropped,
    }

    # ---- 1) 划分文件（默认 constrained：随机基线 + 覆盖约束校正）----
    split_sizes: dict[str, dict[str, int]] = {}
    splits_by_seed: dict[int, dict[str, list[str]]] = {}
    coverage_by_seed: dict[int, dict] = {}
    for seed in seeds:
        train, val, test, coverage_stats = make_split_for_seed(
            seed, included, index, ratio, args.strategy, args.min_pos_ratio)
        total = len(included)
        payload = {"seed": seed, "ratio": ratio,
                   "train": train, "val": val, "test": test}
        path = out_dir / f"split_seed{seed}.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        split_sizes[str(seed)] = {"train": len(train), "val": len(val), "test": len(test)}
        splits_by_seed[seed] = {"train": train, "val": val, "test": test}
        coverage_by_seed[seed] = coverage_stats
        fix_note = (f"，覆盖校正替换 {coverage_stats['swaps_count']} 个"
                    f"（下限修正 {coverage_stats['floor_fixes']}）"
                    if args.strategy == "constrained" else "，随机快照（无校正）")
        print(f"seed{seed}: train {len(train)} / val {len(val)} / test {len(test)}  "
              f"(total {total}){fix_note}")

    # ---- 2) 统计报告 ----
    per_class = [[0, 0] for _ in range(7)]      # [pos, neg]
    multi_label = 0
    all_zero = 0
    for base in sorted(included):
        label = index[base]
        n_hit = sum(label)
        if n_hit == 0:
            all_zero += 1
        if n_hit > 1:
            multi_label += 1
        for i, value in enumerate(label):
            per_class[i][0] += 1 if value == 1 else 0
            per_class[i][1] += 0 if value == 1 else 1

    # ---- 2b) 覆盖约束审核（C1 合计 ≥ ratio×该类正样本；C2 每划分每类 ≥ MIN_POS_PER_SPLIT）----
    rule_check: dict = {
        "rule": "C1：val+test 每类正样本合计 ≥ min_pos_ratio×该类正样本数；"
                "C2：val 与 test 各自每类正样本 ≥ min_pos_per_split",
        "min_pos_ratio": args.min_pos_ratio,
        "min_pos_per_split": MIN_POS_PER_SPLIT,
        "strategy": args.strategy,
        "basis": "pool per-class positives（train+val+test 合计）",
        "authority": "大纲 5.1 第三条（2026-09-12：30% 合计口径 + 覆盖约束校正半句）",
        "seeds": {},
    }
    def dedup_invariants(split: dict[str, list[str]]) -> dict:
        """两级去重不变量逐种子校验：同源码 sha1 / 同项目标识（地址）不得跨划分。"""
        out: dict = {}
        for level in ("content", "address"):
            seen: dict[str, str] = {}
            cross: list[list[str]] = []
            for split_name in ("train", "val", "test"):
                for base in split[split_name]:
                    if level == "content":
                        key = hash_of.get(base)
                        shown = key[:12] if key else None
                    else:
                        key = shown = project_of_base(base)
                    if key is None:
                        continue
                    if key in seen and seen[key] != split_name:
                        cross.append([seen[key], split_name, shown])
                    seen[key] = split_name
            out[f"{level}_dedup_ok"] = not cross
            out[f"cross_split_{level}_dups"] = cross
        return out

    for seed in seeds:
        split = splits_by_seed[seed]
        counts = {name: class_pos_counts(split[name], index)
                  for name in ("train", "val", "test")}
        per_class_rule: dict = {}
        failed: list[str] = []
        for i, name in enumerate(VULN_NAMES):
            pos_total = per_class[i][0]
            val_test = counts["val"][i] + counts["test"][i]
            threshold = args.min_pos_ratio * pos_total
            c1_ok = val_test >= threshold - 1e-9
            c2_ok = (counts["val"][i] >= MIN_POS_PER_SPLIT
                     and counts["test"][i] >= MIN_POS_PER_SPLIT)
            per_class_rule[name] = {
                "pool_pos": pos_total,
                "train_pos": counts["train"][i],
                "val_pos": counts["val"][i],
                "test_pos": counts["test"][i],
                "val_test_pos": val_test,
                "threshold": round(threshold, 4),
                "c1_ok": c1_ok,
                "c2_ok": c2_ok,
                "ok": c1_ok and c2_ok,
            }
            if not (c1_ok and c2_ok):
                failed.append(name)
        stats = coverage_by_seed.get(seed, {"swaps_count": 0, "floor_fixes": 0})
        rule_check["seeds"][str(seed)] = {
            "per_class": per_class_rule,
            "n_classes_failed": len(failed),
            "failed_classes": failed,
            "passed": not failed,
            **dedup_invariants(split),
            "coverage_fix": {"swaps_count": stats["swaps_count"],
                             "floor_fixes": stats["floor_fixes"]},
        }

    report = {
        "strategy": args.strategy,
        "unique_contracts": len(included),
        "dedup": dedup,
        "multi_label_contracts": multi_label,
        "all_zero_contracts": all_zero,
        "buggy_excluded_graphs": len(buggy_excluded),
        "unmatched_graphs": len(unmatched),
        "per_class": {
            name: {"pos": per_class[i][0], "neg": per_class[i][1],
                   "neg_pos_ratio": (round(per_class[i][1] / per_class[i][0], 4)
                                     if per_class[i][0] else None)}
            for i, name in enumerate(VULN_NAMES)
        },
        "split_sizes": split_sizes,
        "rule_check": rule_check,
    }
    (out_dir / "split_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    # ---- 2c) 划分元数据（防全局文件被覆盖；记录输入摘要与输出 sha256）----
    pool_digest = hashlib.sha256("\n".join(sorted(included)).encode("utf-8")).hexdigest()
    for seed in seeds:
        split_path = out_dir / f"split_seed{seed}.json"
        metadata = {
            "seed": seed,
            "ratio": ratio,
            "strategy": args.strategy,
            "constraints": {"min_pos_ratio": args.min_pos_ratio,
                            "min_pos_per_split": MIN_POS_PER_SPLIT},
            "dedup": {"mode": args.dedup, "pool_before_dedup": len(pre_dedup),
                      "pool_after_dedup": len(included), "dropped_count": len(dropped),
                      "levels": dedup_stats["levels"], "rule": dedup_stats["rule"]},
            "algorithm": (
                "固定种子基线：random.Random(seed) 打乱 sorted(pool) 后顺序切"
                "（n_train=round(N·r0)，n_val=round(N·r1)）；"
                "覆盖约束校正：缺口按（池内正样本数升序，类序）处理，换入=train 顺序首个"
                "该类正样本携带者，换出=目标划分尾部首个全零合约，放置入选该类较少一侧"
                "（平局→val）；完全确定性，同环境同 seed 可复现"
                if args.strategy == "constrained" else
                "random.Random(seed) 打乱 sorted(pool) 后顺序切片（旧随机快照，隔离输出，仅对照）"),
            "imports": ["random.Random（stdlib）", "math.ceil", "dataset.build_index",
                        "dataset.is_buggy_project", "dataset.project_of_base",
                        "hashlib.sha1（源码内容去重）"],
            "python_version": platform.python_version(),
            "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "inputs": {
                "graph_dir": str(Path(args.graph_dir).resolve()),
                "label_source": f"{BASE}/alldata(readonly)/contract_labels.json"
                                "（经 dataset.build_index 合并为项目前缀并集）",
                "n_pool": len(included),
                "n_pool_before_dedup": len(pre_dedup),
                "n_dedup_dropped": len(dropped),
                "n_buggy_excluded": len(buggy_excluded),
                "n_unmatched": len(unmatched),
                "pool_digest_sha256": pool_digest,
            },
            "outputs": {
                "split_file": split_path.name,
                "sha256": hashlib.sha256(split_path.read_bytes()).hexdigest(),
                "sizes": split_sizes[str(seed)],
            },
        }
        (out_dir / f"split_metadata_seed{seed}.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    # ---- 2c') 覆盖校正替换清单（换入/换出合约 ID + 标签向量；透明性报告）----
    if args.strategy == "constrained":
        for seed in seeds:
            stats = coverage_by_seed[seed]
            lines = [
                f"覆盖约束校正替换清单 seed{seed}（C1: val+test 每类 ≥ "
                f"{args.min_pos_ratio:.0%}×该类正样本；C2: val/test 各自每类 ≥ {MIN_POS_PER_SPLIT}）",
                f"替换数: {stats['swaps_count']}（其中每划分下限修正 {stats['floor_fixes']}）",
                "说明：IN=由 train 换入 val/test 的稀有类正样本携带者；OUT=被换回 train 的全零合约",
                "",
            ]
            for carrier, evicted in stats["swaps"]:
                lines.append(f"IN   {carrier}  {index[carrier]}")
                lines.append(f"OUT  {evicted}  {index[evicted]}")
            (out_dir / f"coverage_swaps_seed{seed}.txt").write_text(
                "\n".join(lines) + "\n", encoding="utf-8")

    # ---- 2d) splits.csv（seed,sample_id,split,y0..y6；论文附录与外部复核用）----
    with (out_dir / "splits.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["seed", "sample_id", "split"] + [f"y{i}" for i in range(7)])
        for seed in seeds:
            split = splits_by_seed[seed]
            for split_name in ("train", "val", "test"):
                for base in split[split_name]:
                    writer.writerow([seed, base, split_name]
                                    + [int(v) for v in index[base]])

    # ---- 3) 透明性报告 ----
    lines = [
        f"标签匹配失败（未进入划分，请人工核查）: {len(unmatched)}",
    ]
    lines += [f"  {base}" for base in unmatched]
    lines += [
        "",
        f"主实验剔除 buggy_* 噪声项目: {len(buggy_excluded)} 图",
        "（每合约同款注入噪声标签，与具体注入特征不对应；含 buggy_* 的对照实验由消融脚本另行组合）",
    ]
    lines += [f"  {base}" for base in buggy_excluded]
    (out_dir / "unmatched_contracts.txt").write_text("\n".join(lines) + "\n",
                                                     encoding="utf-8")

    # ---- 3b) 池去重丢弃清单（透明性；不在报告里静默吞掉）----
    lv = ", ".join(f"{k}(组 {v['duplicate_groups']}/丢 {v['dropped']})"
                   for k, v in dedup_stats["levels"].items()) or "未启用"
    dropped_lines = [
        f"池去重丢弃清单（--dedup {args.dedup}）：池 {len(pre_dedup)} → {len(included)}，"
        f"丢弃 {len(dropped)}；逐级：{lv}",
        "规则：按唯一标识分组（level-1 源码内容 sha1 → level-2 项目标识/地址），"
        "同组保留相对源码路径字典序首个（平局按 base 名）；顺序固定「先剔 buggy_*、再去重」。",
        "说明：同组样本标签向量相同（level-1 源码字节相同；level-2 标签键即项目前缀），"
        "故不损信息；两级均不得跨划分（逐种子校验写入 split_report.json::rule_check）。",
        "",
    ]
    for item in dropped:
        dropped_lines.append(f"DROP[{item['level']}]  {item['base']}  key={str(item['group_key'])[:16]}  "
                             f"→  KEEP {{{item['kept']}}}")
    if not dropped:
        dropped_lines.append("（无：本轮未启用去重或池内无同内容副本）")
    (out_dir / "dedup_dropped.txt").write_text("\n".join(dropped_lines) + "\n",
                                               encoding="utf-8")

    for seed in seeds:
        status = rule_check["seeds"][str(seed)]
        detail = "C1+C2 全部达标" if status["passed"] else "未达标: " + ",".join(status["failed_classes"])
        print(f"rule check seed{seed}: {7 - status['n_classes_failed']}/7 类达标"
              f"（C1 val+test ≥ {args.min_pos_ratio:.0%}×该类正样本；"
              f"C2 每划分 ≥ {MIN_POS_PER_SPLIT}；{detail}）"
              f" | 跨划分重复：内容 {len(status['cross_split_content_dups'])}、"
              f"地址 {len(status['cross_split_address_dups'])}")
    lv = ", ".join(f"{k}={v['dropped']}" for k, v in dedup_stats["levels"].items()) or "未启用"
    print(f"dedup({args.dedup}): 池 {len(pre_dedup)} → {len(included)}（丢弃 {len(dropped)}；{lv}）")
    print(f"included {len(included)} | buggy_excluded {len(buggy_excluded)} "
          f"| unmatched {len(unmatched)}")
    extra = ", coverage_swaps_seed*.txt" if args.strategy == "constrained" else ""
    print(f"wrote: {out_dir}/split_seed*.json, splits.csv, split_report.json, "
          f"split_metadata_seed*.json{extra}, dedup_dropped.txt, unmatched_contracts.txt")


if __name__ == "__main__":
    main()
