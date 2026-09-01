#!/usr/bin/env python3
"""Batch runner for M1 anchor detection.

This script turns *_hetero.json graphs into a stable M1 output format:

  {
    "meta": {...},
    "node_flags": {...},
    "node_scores": {...},
    "exclusive_labels": {...},
    "exclusive_node_flags": {...},
    "summary": {...}
  }

Raw seven-way flags are preserved for debugging. Exclusive labels are derived
with the fixed arbitration order defined in anchor_detectors.py.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from anchor_detectors import (
    VULN_CLASSES,
    GraphContext,
    compute_anchor_flags,
    compute_anchor_flags_exclusive,
    compute_anchor_score,
    resolve_anchor_label,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Batch run M1 anchor detection on *_hetero.json files.")
    parser.add_argument(
        "--in-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/Heterogeneous graph",
        help="Directory containing *_hetero.json files.",
    )
    parser.add_argument(
        "--out-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/Heterogeneous graph-M1",
        help="Directory where M1 JSON outputs will be written.",
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
    return str(node_id)


def count_hits(flags: dict[str, bool]) -> int:
    return sum(1 for value in flags.values() if value)


def build_meta(ctx: GraphContext, graph_path: Path, output_path: Path) -> dict[str, Any]:
    return {
        "version": "m1-anchor-v1",
        "graph_path": str(graph_path),
        "output_path": str(output_path),
        "source_path": graph_path.resolve().as_posix(),
        "node_count": len(ctx.nodes),
        "cfg_edge_count": sum(len(v) for v in ctx.adj_cfg.values()),
        "state_var_count": len(ctx.state_vars),
        "exclusive_priority": list(VULN_CLASSES),
    }


def build_summary(raw_flags: dict[str, dict[str, bool]], exclusive_flags: dict[str, dict[str, bool]], exclusive_labels: dict[str, str | None]) -> dict[str, Any]:
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
        "unlabeled_nodes": label_hist.get(None, 0),
    }


def run_one(graph_path: Path, out_dir: Path, force: bool = False) -> dict[str, Any]:
    ctx = GraphContext.from_json_file(graph_path)

    raw_node_flags: dict[str, dict[str, bool]] = {}
    node_scores: dict[str, float] = {}
    exclusive_labels: dict[str, str | None] = {}
    exclusive_node_flags: dict[str, dict[str, bool]] = {}

    for node_id in ctx.nodes:
        node_key = as_node_key(node_id)
        raw_flags = compute_anchor_flags(node_id, ctx)
        raw_node_flags[node_key] = raw_flags
        node_scores[node_key] = compute_anchor_score(node_id, ctx)
        exclusive_labels[node_key] = resolve_anchor_label(raw_flags)
        exclusive_node_flags[node_key] = compute_anchor_flags_exclusive(node_id, ctx)

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
    }


def main() -> None:
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

    summary_path = out_dir / "batch_summary.json"
    aggregate = {
        "input_dir": str(in_dir),
        "output_dir": str(out_dir),
        "file_count": len(summaries),
        "total_nodes": sum(item["nodes"] for item in summaries),
        "total_raw_hits": sum(item["raw_hits"] for item in summaries),
        "total_exclusive_hits": sum(item["exclusive_hits"] for item in summaries),
        "files": summaries,
    }
    with open(summary_path, "w", encoding="utf-8") as handle:
        json.dump(aggregate, handle, ensure_ascii=False, indent=2)

    print(f"Processed files: {len(summaries)}")
    print(f"Output dir: {out_dir}")
    print(f"Batch summary: {summary_path}")


if __name__ == "__main__":
    main()