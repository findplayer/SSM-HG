#!/usr/bin/env python3
# 用法：python scripts/dump_cfg.py <合约.sol> <输出.json>
# 作用：用 Slither API 导出每个函数的 CFG 节点（含 IR）与带类型边（seq/true/false）
import json, re, sys
from slither.slither import Slither
from slither.core.cfg.node import NodeType

def unchecked_line_ranges(source_text):
    """花括号深度计数，返回 unchecked{} 块的行区间列表 [(start, end), ...]。"""
    ranges = []
    start = None
    depth = 0
    for line_number, line in enumerate(source_text.splitlines(), 1):
        if start is None and re.search(r"\bunchecked\s*\{", line):
            start = line_number
            depth = 0
        if start is not None:
            depth += line.count("{") - line.count("}")
        if start is not None and depth <= 0:
            ranges.append((start, line_number))
            start = None
            depth = 0
    return ranges


def is_in_unchecked(lines, ranges):
    """节点行集合是否落在任一 unchecked 区间内。"""
    return any(start <= line <= end for line in lines for start, end in ranges)


def main():
    """用 Slither API 导出每函数 CFG 节点（含 IR/行号/unchecked）与带类型边（seq/true/false）到 JSON。"""
    target, out_path = sys.argv[1], sys.argv[2]
    slither = Slither(target)
    source_text = open(target, encoding="utf-8", errors="ignore").read()
    unchecked_ranges = unchecked_line_ranges(source_text)
    functions = []
    for contract in slither.contracts:
        for func in list(contract.functions) + list(contract.modifiers):
            if not func.nodes:
                continue
            nodes, edges, idmap = [], [], {}
            for n in func.nodes:
                idmap[n.node_id] = len(nodes)
                lines = set()
                for span in n.source_mapping.lines:
                    if isinstance(span, (tuple, list)):
                        # tuple 是 (start, end) 行区间：展开中间行，避免只取两端
                        # 导致多行节点 is_unchecked 判定与行号窗口缺失
                        # （2026-09-05 修复）。
                        vals = [ln for ln in span if isinstance(ln, int) and ln >= 0]
                        if len(vals) == 2 and vals[0] <= vals[1]:
                            lines.update(range(vals[0], vals[1] + 1))
                        else:
                            lines.update(vals)
                    elif isinstance(span, int) and span >= 0:
                        lines.add(span)
                lines = sorted(lines)
                nodes.append({
                    "local_id": len(nodes),
                    "cfg_node_type": n.type.name,
                    "expression": str(n.expression) if n.expression else None,
                    "ir": "\n".join(str(ir) for ir in n.irs),
                    "line_start": min(lines) if lines else None,
                    "line_end": max(lines) if lines else None,
                    "is_unchecked": is_in_unchecked(lines, unchecked_ranges),
                })
            for n in func.nodes:
                sons = [s for s in n.sons if s.node_id in idmap]
                for i, son in enumerate(sons):
                    kind = "seq"
                    if n.type in (NodeType.IF, NodeType.IFLOOP):
                        kind = "true" if i == 0 else "false"
                    edges.append({"source": idmap[n.node_id],
                                  "target": idmap[son.node_id], "kind": kind})
            # receive/fallback 的 func.name 可能是空串：这里显式命名，避免构图脚本
            # 把 receive() 误归一成 fallback，与 AST 函数表失配（2026-09-05 修复）。
            if func.is_receive:
                func_out_name = "receive"
            elif func.is_fallback:
                func_out_name = "fallback"
            else:
                func_out_name = func.name
            functions.append({
                "contract": contract.name,
                "function": func_out_name,
                "visibility": str(func.visibility),
                "kind": ("constructor" if func.is_constructor
                         else "fallback" if func.is_fallback
                         else "receive" if func.is_receive
                         else "function"),
                "nodes": nodes,
                "edges": edges,
            })
    total_nodes = sum(len(f["nodes"]) for f in functions)
    line_missing = sum(
        1 for f in functions for n in f["nodes"] if n.get("line_start") is None
    )
    out = {
        "meta": {"nodes": total_nodes, "line_missing": line_missing},
        "functions": functions,
    }
    if line_missing > 0:
        print(f"WARNING: {line_missing}/{total_nodes} nodes lack line numbers "
              f"(srcmap unavailable for the selected solc version?)", file=sys.stderr)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
