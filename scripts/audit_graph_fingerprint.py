#!/usr/bin/env python3
"""逐图指纹工具：验证「某次改动是否只影响了预期的那几张图」（只读，不写任何产物）。

背景（`docs/residual_gaps.md` / `experiments/decisions.md` §15）：M2 补登记、R2 legacy_ctor、R5 AST 格式兼容
三次修复都靠「全库 581 图逐图指纹」证明“只有 N 张图变化、其余逐位不变”。此前该比对是临时脚本，现固化为本工具，
使论文口径声明可复现。

用法（仓库根目录，conda base）：
  # ① 改动前：落盘基线
  python scripts/audit_graph_fingerprint.py --out /tmp/hetero_before.json
  # ② 跑改动（例如 python scripts/build_cfg_centered_hetero_graph.py）
  # ③ 改动后：与基线比对，打印变化的图与字段
  python scripts/audit_graph_fingerprint.py --compare /tmp/hetero_before.json

指纹字段（每图独立 sha256 前 16 位）：
  nodes       `_hetero.json::nodes`（节点元信息，含 span/行号/可见性）
  edges       五类边（CFG_FLOW/AST_PARENT/AST_PARENT_SAME/DFG_DEP/CALLBACK_RISK）的完整结构
  meta_old    上述五类边与节点相关的既有 meta 键（不含本次新增的计数键）
  functions   函数表（补登记目标）
  n_functions 函数表条数（便于人读）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
DEFAULT_GRAPH_DIR = BASE / "products/alldata/graphs"

# meta 键：与 nodes/edges 同源的既有口径（新增的补登记计数不参与比对）
OLD_META_KEYS = (
    "source", "source_path", "cfg_node_count", "cfg_edge_count", "cfg_seq_edge_count",
    "cfg_true_edge_count", "cfg_false_edge_count", "cfgdetail_missing", "cfgdetail_invalid",
    "ast_edge_count", "ast_same_cfg_edge_count", "ast_unmapped_edge_count", "dfg_edge_count",
    "dfg_parse_errors", "dfg_non_table_lines", "expr_span_total", "expr_span_missing",
    "ir_missing", "state_vars", "callback_risk_edge_count", "ext_call_node_count",
    "callback_max_edges", "callback_avg_edges", "callback_truncated_candidates",
)
FIELDS = ("nodes", "edges", "meta_old", "functions")


def _digest(obj) -> str:
    payload = json.dumps(obj, sort_keys=True, ensure_ascii=True).encode()
    return hashlib.sha256(payload).hexdigest()[:16]


def fingerprint(graph_dir: Path) -> dict[str, dict]:
    """对 `*_hetero.json` 逐图取四类指纹。"""
    out: dict[str, dict] = {}
    for path in sorted(graph_dir.glob("*_hetero.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        out[path.name.replace("_hetero.json", "")] = {
            "nodes": _digest(data["nodes"]),
            "edges": _digest(data["edges"]),
            "meta_old": _digest({k: data["meta"].get(k) for k in OLD_META_KEYS}),
            "functions": _digest(data["functions"]),
            "n_functions": len(data["functions"]),
        }
    return out


def compare(before: dict, after: dict, verbose: bool = True) -> int:
    """打印字段级差异；返回“有任意字段变化的图数”。"""
    if set(before) != set(after):
        only_before = sorted(set(before) - set(after))
        only_after = sorted(set(after) - set(before))
        print(f"图集合不一致：仅基线有 {len(only_before)}、仅现状有 {len(only_after)}")
        return max(len(only_before), len(only_after))
    changed: dict[str, list[str]] = {}
    for base in before:
        diff = [f for f in FIELDS if before[base][f] != after[base][f]]
        if diff:
            changed[base] = diff
    print(f"图 {len(before)}；有变化的图 {len(changed)}")
    for field in FIELDS:
        n = sum(1 for d in changed.values() if field in d)
        print(f"  {field:10s} 变化图数 {n}")
    if verbose:
        for base, diff in sorted(changed.items()):
            extra = ""
            if "functions" in diff:
                extra = f"  functions {before[base]['n_functions']} -> {after[base]['n_functions']}"
            print(f"  {base}  [{','.join(diff)}]{extra}")
    return len(changed)


def main() -> int:
    parser = argparse.ArgumentParser(description="逐图指纹：落盘基线或与基线比对（只读）。")
    parser.add_argument("--graph-dir", default=str(DEFAULT_GRAPH_DIR),
                        help="含 *_hetero.json 的目录。")
    parser.add_argument("--out", default=None, help="把当前逐图指纹写到该 JSON 路径。")
    parser.add_argument("--compare", default=None, help="与指定的基线指纹 JSON 比对（打印差异摘要）。")
    parser.add_argument("--quiet", action="store_true", help="比对时不逐图打印，只给汇总。")
    args = parser.parse_args()
    if not args.out and not args.compare:
        parser.error("至少给出 --out 或 --compare")

    current = fingerprint(Path(args.graph_dir))
    if args.out:
        Path(args.out).write_text(json.dumps(current, indent=1, sort_keys=True), encoding="utf-8")
        print(f"wrote {args.out}  graphs={len(current)}")
    if args.compare:
        before = json.loads(Path(args.compare).read_text(encoding="utf-8"))
        compare(before, current, verbose=not args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
