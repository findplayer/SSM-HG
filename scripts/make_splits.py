#!/usr/bin/env python3
"""M5 数据划分（手册 10.2，2026-09-07）：唯一合约 8:1:1，产出 `splits/`。

设计（对齐大纲 5.1 / 手册 10.2）：
  - 以**唯一合约（图）**为划分单位，`random.Random(seed)` 打乱（固定种子可复现）；
  - 同一合约绝不跨划分（防泄漏）；
  - 标签匹配键 = 项目前缀并集（复用 dataset.build_index，不重复标签逻辑）；
  - 主实验**剔除 buggy_* 噪声项目**（asd_buggy_*/nasd_buggy_*：每合约同款注入噪声标签，
    与具体注入特征不对应），剔除明细写入 unmatched_contracts.txt 单独一节；
    “含 buggy_*”的对照实验由后续消融脚本另行组合，不改变本文件输出；
  - 匹配不上的图写入 unmatched_contracts.txt 记录并报告（不静默丢弃）。

产物（均写入 `splits/`）：
  - split_seed{seed}.json   {"seed":..,"ratio":..,"train":[...],"val":[...],"test":[...]}
  - split_report.json       每类正/负样本、正负比、唯一合约、多标签、全 0、三划分数量
  - unmatched_contracts.txt 匹配失败列表 + buggy_* 剔除明细

CLI：`python scripts/make_splits.py --seeds 0,1,2 --split 0.8,0.1,0.1`
"""

from __future__ import annotations

import argparse
import json
import random
from collections import Counter
from pathlib import Path

from dataset import BASE, build_index, is_buggy_project, project_of_base

VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]


def parse_args() -> argparse.Namespace:
    """CLI：--seeds / --split / --graph-dir / --out-dir（默认 splits/）。"""
    parser = argparse.ArgumentParser(description="Split unique contracts into train/val/test (8:1:1).")
    parser.add_argument("--seeds", default="0,1,2",
                        help="Comma-separated random seeds (default 0,1,2).")
    parser.add_argument("--split", default="0.8,0.1,0.1",
                        help="Train/val/test ratio, must sum to 1.")
    parser.add_argument("--graph-dir", default=f"{BASE}/Heterogeneous graphs",
                        help="Directory containing *_pyg.pt.")
    parser.add_argument("--out-dir", default=f"{BASE}/splits",
                        help="Output directory for split files.")
    return parser.parse_args()


def main() -> None:
    """主流程：建索引 → 剔除 buggy_* → 逐种子 8:1:1 → 写 splits/ 三件套。"""
    args = parse_args()
    seeds = [int(s) for s in args.seeds.split(",")]
    ratio = [float(r) for r in args.split.split(",")]
    if len(ratio) != 3 or abs(sum(ratio) - 1.0) > 1e-9:
        raise ValueError(f"--split must be 3 numbers summing to 1, got {args.split}")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    index, unmatched = build_index(Path(args.graph_dir))
    included = {base for base in index if not is_buggy_project(project_of_base(base))}
    buggy_excluded = sorted(set(index) - included)
    unmatched = sorted(unmatched)

    # ---- 1) 划分文件 ----
    split_sizes: dict[str, dict[str, int]] = {}
    for seed in seeds:
        order = sorted(included)
        rng = random.Random(seed)
        rng.shuffle(order)
        total = len(order)
        n_train = int(round(total * ratio[0]))
        n_val = int(round(total * ratio[1]))
        train = order[:n_train]
        val = order[n_train:n_train + n_val]
        test = order[n_train + n_val:]
        assert len(train) + len(val) + len(test) == total, "split sizes mismatch"
        payload = {"seed": seed, "ratio": ratio,
                   "train": train, "val": val, "test": test}
        path = out_dir / f"split_seed{seed}.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        split_sizes[str(seed)] = {"train": len(train), "val": len(val), "test": len(test)}
        print(f"seed{seed}: train {len(train)} / val {len(val)} / test {len(test)}  "
              f"(total {total})")

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
    report = {
        "unique_contracts": len(included),
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
    }
    (out_dir / "split_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

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

    print(f"included {len(included)} | buggy_excluded {len(buggy_excluded)} "
          f"| unmatched {len(unmatched)}")
    print(f"wrote: {out_dir}/split_seed*.json, split_report.json, unmatched_contracts.txt")


if __name__ == "__main__":
    main()
