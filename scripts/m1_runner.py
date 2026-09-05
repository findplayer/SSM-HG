#!/usr/bin/env python3
"""M1 锚点检测批量执行器。

把每个 *_hetero.json 转成稳定的 M1 输出格式：

  {
    "meta": {...},          # 含 exclusive_priority（实际仲裁顺序）
    "node_flags": {...},    # 七键布尔（主产物）
    "node_scores": {...},   # 全图 min-max 归一化后的 s_v（主产物）
    "exclusive_labels": {...},
    "exclusive_node_flags": {...},  # 以上两者为调试辅助
    "summary": {...}
  }

注意：exclusive 系列只是把七类压成互斥单标签的调试辅助，论文主线不用。
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from priori_scoring import (
    EXCLUSIVE_RULE_PRIORITY,
    VULN_CLASSES,
    GraphContext,
    compute_anchor_flags,
    compute_anchor_flags_exclusive,
    compute_anchor_score,
    resolve_anchor_label,
)


def parse_args() -> argparse.Namespace:
    """解析 CLI 参数：--in-dir/--out-dir（默认 Heterogeneous graphs）、--pattern、--force。"""
    parser = argparse.ArgumentParser(description="Batch run M1 anchor detection on *_hetero.json files.")
    base = "/home/saumarez/projects/deep-learning/SSM-HG"
    parser.add_argument(
        "--in-dir",
        default=f"{base}/Heterogeneous graphs",
        help="Directory containing *_hetero.json files.",
    )
    parser.add_argument(
        "--out-dir",
        default=f"{base}/Heterogeneous graphs",
        help="Directory where M1 JSON outputs (*_m1.json) will be written (same dir by default).",
    )
    parser.add_argument(
        "--pattern",
        default="*_hetero.json",
        help="Glob pattern used to select input graphs.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing output files.",
    )
    return parser.parse_args()


def as_node_key(node_id: Any) -> str:
    """节点 id → 字符串键。

    JSON 对象键只能是字符串，node_flags/scores/labels 的键统一用本函数转换，
    保证与 hetero.json 节点 id（int）一一对应（str(nid) 约定，2026-09-05 审计）。
    """
    return str(node_id)


def count_hits(flags: dict[str, bool]) -> int:
    """统计一个节点七类 flags 中命中的类别数（raw 分数基础）。"""
    return sum(1 for value in flags.values() if value)


def minmax_normalize(scores: dict[str, float]) -> dict[str, float]:
    """全图 min-max 归一化 → s_v ∈ [0,1]（大纲 4.1.3 步骤 3）。

    边界情形（2026-09-05 修复）：
      - 全 0：全部保持 0；
      - 仅一个非 0 值：该节点归一化为 1.0，其余保持 0。
        旧实现 high==low 时整体清零，会把单命中图的唯一先验信号抹掉。
    """
    if not scores:
        return scores
    values = list(scores.values())
    low = min(values)
    high = max(values)
    if high <= 1e-12:                     # 全 0
        return {key: 0.0 for key in scores}
    if high - low <= 1e-12:               # 仅一个非 0 值
        return {key: (1.0 if value > 0 else 0.0) for key, value in scores.items()}
    return {key: (value - low) / (high - low) for key, value in scores.items()}


def build_meta(ctx: GraphContext, graph_path: Path, output_path: Path) -> dict[str, Any]:
    """构造 _m1.json 的 meta 段。

    exclusive_priority 记录实际仲裁顺序 EXCLUSIVE_RULE_PRIORITY（不是 VULN_CLASSES）；
    graph_path_abs 为图的绝对路径（2026-09-05 由 source_path 改名）。
    """
    return {
        "version": "m1-anchor-v1",
        "graph_path": str(graph_path),
        "output_path": str(output_path),
        "graph_path_abs": graph_path.resolve().as_posix(),
        "node_count": len(ctx.nodes),
        "cfg_edge_count": sum(len(v) for v in ctx.adj_cfg.values()),
        "state_var_count": len(ctx.state_vars),
        "exclusive_priority": list(EXCLUSIVE_RULE_PRIORITY),
    }


def build_summary(raw_flags: dict[str, dict[str, bool]], exclusive_flags: dict[str, dict[str, bool]], exclusive_labels: dict[str, str | None]) -> dict[str, Any]:
    """构造 _m1.json 的 summary 段：节点命中总数、重叠直方图、七类命中与互斥标签直方图。"""
    total_nodes = len(raw_flags)
    nodes_with_hits = 0
    overlap_hist = Counter()
    raw_class_hits = Counter()
    label_hist = Counter()

    for node_id, flags in raw_flags.items():
        hit_count = count_hits(flags)
        if hit_count > 0:
            nodes_with_hits += 1
        overlap_hist[str(hit_count)] += 1
        for label, hit in flags.items():
            if hit:
                raw_class_hits[label] += 1

        label = exclusive_labels.get(node_id)
        if label is not None:
            label_hist[label] += 1

    exclusive_nodes = sum(1 for flags in exclusive_flags.values() if count_hits(flags) > 0)

    return {
        "total_nodes": total_nodes,
        "nodes_with_any_raw_hit": nodes_with_hits,
        "nodes_with_exclusive_hit": exclusive_nodes,
        "raw_overlap_histogram": dict(sorted(overlap_hist.items(), key=lambda item: int(item[0]))),
        "raw_class_hits": {label: raw_class_hits.get(label, 0) for label in VULN_CLASSES},
        "exclusive_label_histogram": {label: label_hist.get(label, 0) for label in VULN_CLASSES},
        "unlabeled_nodes": total_nodes - exclusive_nodes,
    }


def run_one(graph_path: Path, out_dir: Path, force: bool = False) -> dict[str, Any]:
    """处理单个图：锚点判定 → 打分 → min-max 归一化 → 写 _m1.json，返回汇总项。"""
    ctx = GraphContext.from_json_file(graph_path)

    raw_node_flags: dict[str, dict[str, bool]] = {}
    raw_scores: dict[str, float] = {}
    exclusive_labels: dict[str, str | None] = {}
    exclusive_node_flags: dict[str, dict[str, bool]] = {}

    for node_id in ctx.nodes:
        node_key = as_node_key(node_id)
        raw_flags = compute_anchor_flags(node_id, ctx)
        raw_node_flags[node_key] = raw_flags
        raw_scores[node_key] = compute_anchor_score(node_id, ctx)
        exclusive_labels[node_key] = resolve_anchor_label(raw_flags)
        exclusive_node_flags[node_key] = compute_anchor_flags_exclusive(node_id, ctx)

    # 全图 min-max 归一化（大纲 4.1.3 步骤 3，不做 DFG 反向一跳传播）
    node_scores = minmax_normalize(raw_scores)

    out_dir.mkdir(parents=True, exist_ok=True)
    output_path = out_dir / graph_path.name.replace("_hetero.json", "_m1.json")
    if output_path.exists() and not force:
        raise FileExistsError(f"Output exists: {output_path}")

    payload = {
        "meta": build_meta(ctx, graph_path, output_path),
        "node_flags": raw_node_flags,
        "node_scores": node_scores,
        "exclusive_labels": exclusive_labels,
        "exclusive_node_flags": exclusive_node_flags,
    }
    payload["summary"] = build_summary(raw_node_flags, exclusive_node_flags, exclusive_labels)

    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)

    return {
        "input": graph_path.name,
        "output": output_path.name,
        "nodes": len(ctx.nodes),
        "raw_hits": payload["summary"]["nodes_with_any_raw_hit"],
        "exclusive_hits": payload["summary"]["nodes_with_exclusive_hit"],
        "raw_class_hits": payload["summary"]["raw_class_hits"],
    }


def main() -> None:
    """批量入口：扫描 *_hetero.json → run_one → 聚合 batch_summary.json（含七类命中节点数与命中图数）。"""
    args = parse_args()
    in_dir = Path(args.in_dir)
    out_dir = Path(args.out_dir)

    json_files = sorted(in_dir.glob(args.pattern))
    if not json_files:
        print(f"No input files found in: {in_dir} (pattern={args.pattern})")
        return

    summaries = []
    for json_path in json_files:
        summaries.append(run_one(json_path, out_dir, force=args.force))

    # 全库七类命中节点数与命中图数（论文统计口径，2026-09-05 新增；
    # 此前 batch 层只有 total_raw_hits/total_exclusive_hits 两个恒等总量）。
    total_class_hits = Counter()
    class_hit_graphs = Counter()
    for item in summaries:
        for label, count in item.get("raw_class_hits", {}).items():
            total_class_hits[label] += count
            if count > 0:
                class_hit_graphs[label] += 1

    summary_path = out_dir / "batch_summary.json"
    aggregate = {
        "input_dir": str(in_dir),
        "output_dir": str(out_dir),
        "file_count": len(summaries),
        "total_nodes": sum(item["nodes"] for item in summaries),
        "total_raw_hits": sum(item["raw_hits"] for item in summaries),
        "total_exclusive_hits": sum(item["exclusive_hits"] for item in summaries),
        "total_class_hits": dict(total_class_hits),
        "class_hit_graphs": dict(class_hit_graphs),
        "files": summaries,
    }
    with open(summary_path, "w", encoding="utf-8") as handle:
        json.dump(aggregate, handle, ensure_ascii=False, indent=2)

    print(f"Processed files: {len(summaries)}")
    print(f"Output dir: {out_dir}")
    print(f"Batch summary: {summary_path}")


if __name__ == "__main__":
    main()