#!/usr/bin/env python3
import argparse
import ast as py_ast
import bisect
import json
import os
import re
from collections import defaultdict
from pathlib import Path


EXCLUDED_TOKENS = {
    "true",
    "false",
    "if",
    "else",
    "for",
    "while",
    "do",
    "break",
    "continue",
    "return",
    "require",
    "assert",
    "revert",
    "emit",
    "event",
    "mapping",
    "memory",
    "storage",
    "calldata",
    "view",
    "pure",
    "payable",
    "public",
    "private",
    "internal",
    "external",
    "constant",
    "immutable",
    "override",
    "virtual",
    "constructor",
    "fallback",
    "receive",
    "uint",
    "int",
    "address",
    "bool",
    "string",
    "bytes",
    "byte",
    "fixed",
    "ufixed",
    "now",
    "this",
    "super",
    "new",
    "delete",
    "returns",
    "function",
    "modifier",
    "struct",
    "enum",
    "contract",
    "interface",
    "library",
    "using",
    "import",
    "pragma",
    "msg",
    "block",
    "tx",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Build CFG-centered heterogeneous graphs.")
    parser.add_argument(
        "--ast-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/AST",
    )
    parser.add_argument(
        "--cfg-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/CFG",
    )
    parser.add_argument(
        "--dfg-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/DFG",
    )
    parser.add_argument(
        "--out-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/Heterogeneous graph ",
    )
    parser.add_argument(
        "--src-root",
        default="/home/saumarez/projects/deep-learning/SSM-HG/dataset/reentrancy_contract/sol_source",
    )
    return parser.parse_args()


def parse_src_range(src_field):
    if not src_field:
        return None
    parts = src_field.split(":")
    if len(parts) < 2:
        return None
    try:
        start = int(parts[0])
        length = int(parts[1])
    except ValueError:
        return None
    return start, start + length


def compute_line_starts(source_text):
    starts = [0]
    for idx, ch in enumerate(source_text):
        if ch == "\n":
            starts.append(idx + 1)
    return starts


def offset_to_line_col(line_starts, offset):
    line_idx = bisect.bisect_right(line_starts, offset) - 1
    line = line_idx + 1
    col = offset - line_starts[line_idx] + 1
    return line, col


def load_ast(ast_path):
    with open(ast_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    sources = data.get("sources", {})
    if not sources:
        return None, None, None
    source_key = next(iter(sources.keys()))
    ast_root = sources[source_key].get("AST")
    source_list = data.get("sourceList") or []
    source_name = source_list[0] if source_list else None
    if not source_name:
        source_name = ast_root.get("attributes", {}).get("absolutePath") if ast_root else None
    return ast_root, source_name, source_key


def walk_ast(ast_root):
    nodes = {}
    edges = []
    functions = []
    contracts = []

    def visit(node, parent_id=None, contract_name=None, function_ctx=None):
        node_id = node.get("id")
        node_type = node.get("name") or node.get("nodeType")
        attributes = node.get("attributes", {})
        src = node.get("src")

        if node_type == "ContractDefinition":
            contract_name = attributes.get("name")
            contracts.append({
                "id": node_id,
                "name": contract_name,
                "src": parse_src_range(src),
            })

        if node_type == "FunctionDefinition":
            raw_name = attributes.get("name", "")
            kind = attributes.get("kind")
            is_constructor = bool(attributes.get("isConstructor"))
            fn_name = raw_name
            if kind == "fallback" or (raw_name == "" and not is_constructor):
                fn_name = "fallback"
            elif kind == "constructor" or is_constructor or (raw_name and raw_name == contract_name):
                fn_name = "constructor"
            function_ctx = {
                "id": node_id,
                "name": fn_name,
                "kind": kind,
                "is_constructor": is_constructor,
                "contract": contract_name,
                "src": parse_src_range(src),
            }
            functions.append(function_ctx)

        nodes[node_id] = {
            "id": node_id,
            "type": node_type,
            "attributes": attributes,
            "src": parse_src_range(src),
            "contract": contract_name,
            "function": function_ctx["name"] if function_ctx else None,
            "function_kind": function_ctx["kind"] if function_ctx else None,
        }
        if parent_id is not None:
            edges.append((parent_id, node_id))

        for child in node.get("children", []) or []:
            visit(child, node_id, contract_name, function_ctx)

    visit(ast_root)
    return nodes, edges, functions, contracts


def find_source_file(src_root, source_name):
    if not source_name:
        return None
    source_path = Path(source_name)
    if source_path.is_absolute() and source_path.exists():
        return str(source_path)
    name = source_path.name if source_path.is_absolute() or "/" in source_name or "\\" in source_name else source_name
    candidates = list(Path(src_root).rglob(name))
    if not candidates:
        dataset_root = Path(src_root).parents[1]
        candidates = list(dataset_root.rglob(name))
    if not candidates:
        return None
    preferred = [p for p in candidates if "reentrancy_contract/sol_source" in str(p)]
    return str(preferred[0] if preferred else candidates[0])


def parse_cfg_dot(cfg_path):
    text = Path(cfg_path).read_text(encoding="utf-8", errors="ignore")
    node_pattern = re.compile(r"(\d+)\[label=\"(.*?)\"\];", re.S)
    edge_pattern = re.compile(r"(\d+)->(\d+);")
    nodes = {}
    for match in node_pattern.finditer(text):
        local_id = int(match.group(1))
        label = match.group(2)
        node_type_match = re.search(r"Node Type:\s*([A-Z_]+)", label)
        node_type = node_type_match.group(1) if node_type_match else "UNKNOWN"
        expr = None
        if "EXPRESSION:" in label:
            expr = extract_section(label, "EXPRESSION:", "IRs:")
        nodes[local_id] = {
            "local_id": local_id,
            "cfg_node_type": node_type,
            "label": label,
            "expression": expr,
        }
    edges = [(int(a), int(b)) for a, b in edge_pattern.findall(text)]
    return nodes, edges


def extract_section(label, start_marker, end_marker):
    start = label.find(start_marker)
    if start == -1:
        return None
    start += len(start_marker)
    end = label.find(end_marker, start)
    if end == -1:
        end = len(label)
    content = label[start:end]
    lines = [line.rstrip() for line in content.splitlines()]
    cleaned = "\n".join([line for line in lines if line.strip()])
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned if cleaned else None


def parse_cfg_filename(cfg_path):
    name = Path(cfg_path).name
    if ".sol-" not in name:
        return None, None
    after = name.split(".sol-", 1)[1]
    if "-" not in after:
        return None, None
    contract, rest = after.split("-", 1)
    func_sig = rest.rsplit(".dot", 1)[0]
    func_name = func_sig.split("(", 1)[0]
    return contract, func_name


def normalize_function_name(func_name, contract_name):
    if func_name is None:
        return None
    if func_name == "" or func_name == "receive":
        return "fallback"
    if func_name == contract_name:
        return "constructor"
    if func_name in {"constructor", "fallback"}:
        return func_name
    return func_name


def find_function_span(functions, contracts, contract_name, func_name):
    contract_span = None
    for contract in contracts:
        if contract["name"] == contract_name:
            contract_span = contract["src"]
            break

    if func_name == "slitherConstructorVariables":
        return contract_span

    for fn in functions:
        if fn["contract"] != contract_name:
            continue
        if func_name == "constructor":
            if fn["name"] == "constructor" or fn["kind"] == "constructor" or fn["is_constructor"]:
                return fn["src"]
            if fn["name"] == contract_name:
                return fn["src"]
        elif func_name == "fallback":
            if fn["name"] == "fallback" or fn["kind"] == "fallback" or fn["name"] == "":
                return fn["src"]
        else:
            if fn["name"] == func_name:
                return fn["src"]

    return contract_span


def find_expression_span(expr, source_text, span, cache=None):
    if not expr:
        return None
    cache_key = None
    if cache is not None:
        if span:
            cache_key = (expr, span[0], span[1])
        else:
            cache_key = (expr, None, None)
        if cache_key in cache:
            return cache[cache_key]
    spans_to_try = []
    if span:
        spans_to_try.append((span[0], span[1], True))
    spans_to_try.append((0, len(source_text), False))
    patterns = [expr, expr + ";"]

    for start, end, allow_ambiguous in spans_to_try:
        segment = source_text[start:end]
        for text in patterns:
            tokens = re.split(r"\s+", text.strip())
            if not tokens:
                continue
            regex = r"\s+".join(re.escape(tok) for tok in tokens)
            matches = list(re.finditer(regex, segment, re.S))
            if matches:
                if allow_ambiguous or len(matches) == 1:
                    match = matches[0]
                    result = (start + match.start(), start + match.end())
                    if cache is not None and cache_key is not None:
                        cache[cache_key] = result
                    return result
            expr_no_ws = re.sub(r"\s+", "", text)
            if not expr_no_ws:
                continue
            seg_no_ws_chars = []
            seg_map = []
            for idx, ch in enumerate(segment):
                if not ch.isspace():
                    seg_map.append(idx)
                    seg_no_ws_chars.append(ch)
            seg_no_ws = "".join(seg_no_ws_chars)
            positions = []
            pos = seg_no_ws.find(expr_no_ws)
            while pos != -1:
                positions.append(pos)
                pos = seg_no_ws.find(expr_no_ws, pos + 1)
            if positions:
                if allow_ambiguous or len(positions) == 1:
                    pos = positions[0]
                    orig_start = start + seg_map[pos]
                    orig_end = start + seg_map[pos + len(expr_no_ws) - 1] + 1
                    result = (orig_start, orig_end)
                    if cache is not None and cache_key is not None:
                        cache[cache_key] = result
                    return result
    if cache is not None and cache_key is not None:
        cache[cache_key] = None
    return None


def build_ast_mapping(ast_nodes, ast_edges, cfg_nodes_by_function):
    parent_map = {}
    for parent_id, child_id in ast_edges:
        parent_map[child_id] = parent_id

    ast_nodes_by_function = defaultdict(list)
    for node in ast_nodes.values():
        contract = node.get("contract")
        function = node.get("function")
        if contract and function is not None:
            ast_nodes_by_function[(contract, function)].append(node)

    anchor_ast_to_cfg = {}
    for func_key, cfg_nodes in cfg_nodes_by_function.items():
        ast_candidates = [n for n in ast_nodes_by_function.get(func_key, []) if n.get("src")]
        if not ast_candidates:
            continue
        for cfg in cfg_nodes:
            cfg_span = cfg.get("span")
            if not cfg_span:
                continue
            best_ast = None
            best_len = None
            for ast_node in ast_candidates:
                ast_span = ast_node["src"]
                if ast_span[0] <= cfg_span[0] and ast_span[1] >= cfg_span[1]:
                    span_len = ast_span[1] - ast_span[0]
                    if best_len is None or span_len < best_len:
                        best_len = span_len
                        best_ast = ast_node
            if best_ast and best_ast["id"] not in anchor_ast_to_cfg:
                anchor_ast_to_cfg[best_ast["id"]] = cfg["id"]

    ast_to_cfg = {}
    for ast_id in ast_nodes.keys():
        cur = ast_id
        while cur is not None and cur not in anchor_ast_to_cfg:
            cur = parent_map.get(cur)
        if cur is not None and cur in anchor_ast_to_cfg:
            ast_to_cfg[ast_id] = anchor_ast_to_cfg[cur]

    ast_edges_mapped = set()
    ast_edges_same = set()
    ast_unmapped_edges = 0
    for parent_id, child_id in ast_edges:
        src = ast_to_cfg.get(parent_id)
        dst = ast_to_cfg.get(child_id)
        if src is None or dst is None:
            ast_unmapped_edges += 1
            continue
        if src == dst:
            ast_edges_same.add((src, dst))
            continue
        ast_edges_mapped.add((src, dst))

    return ast_edges_mapped, ast_edges_same, ast_unmapped_edges


def parse_dfg(dfg_path):
    if not dfg_path or not os.path.exists(dfg_path):
        return {}, 0
    results = defaultdict(dict)
    current_contract = None
    current_function = None
    parse_errors = 0
    with open(dfg_path, "r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if line.startswith("Contract "):
                current_contract = line.split("Contract ", 1)[1].strip()
                current_function = None
                continue
            if line.startswith("Function "):
                fn_sig = line.split("Function ", 1)[1].strip()
                current_function = fn_sig.split("(", 1)[0]
                continue
            if not line.startswith("|") or line.startswith("| Variable"):
                continue
            if line.startswith("+"):
                continue
            if current_contract is None or current_function is None:
                continue
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if len(cells) < 2:
                continue
            var = cells[0]
            deps_raw = cells[1]
            try:
                try:
                    deps = json.loads(deps_raw)
                except Exception:
                    deps = py_ast.literal_eval(deps_raw)
                if not isinstance(deps, list):
                    deps = []
            except Exception:
                parse_errors += 1
                deps = []
            results[(current_contract, current_function)][var] = deps
    return results, parse_errors


def is_type_token(token):
    if token in EXCLUDED_TOKENS:
        return True
    if token.startswith("uint") and token[4:].isdigit():
        return True
    if token.startswith("int") and token[3:].isdigit():
        return True
    if token.startswith("bytes") and token[5:].isdigit():
        return True
    return False


def extract_tokens(expr):
    if not expr:
        return set()
    tokens = re.findall(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*", expr)
    return {tok for tok in tokens if not is_type_token(tok)}


def split_assignment(expr):
    if not expr:
        return None, None, None
    operators = ["+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "^=", "|=", "="]
    for op in operators:
        idx = expr.find(op)
        if idx == -1:
            continue
        if op == "=":
            prev = expr[idx - 1] if idx > 0 else ""
            next_ch = expr[idx + 1] if idx + 1 < len(expr) else ""
            if prev in ["=", "!", ">", "<"] or next_ch == "=":
                continue
        left = expr[:idx]
        right = expr[idx + len(op):]
        return left, right, op
    return None, None, None


def extract_def_use(expr):
    left, right, op = split_assignment(expr)
    if left is None:
        return set(), extract_tokens(expr)
    defs = extract_tokens(left)
    uses = extract_tokens(right)
    if op and op != "=":
        uses |= defs
    return defs, uses


def expand_var_keys(name):
    keys = {name}
    if "." in name:
        keys.add(name.split(".")[-1])
    return keys


def expand_token_keys(token):
    keys = {token}
    if "." in token and not token.startswith(("msg.", "block.", "tx.")):
        keys.add(token.rsplit(".", 1)[0])
    return keys


def build_dfg_edges(cfg_nodes_by_function, dfg_map):
    edges = set()
    for func_key, var_deps in dfg_map.items():
        nodes = cfg_nodes_by_function.get(func_key)
        if not nodes:
            continue
        def_index = defaultdict(set)
        use_index = defaultdict(set)
        for node in nodes:
            defs, uses = extract_def_use(node.get("expression"))
            for token in defs:
                for key in expand_token_keys(token):
                    def_index[key].add(node["id"])
            for token in uses:
                for key in expand_token_keys(token):
                    use_index[key].add(node["id"])
        for var, deps in var_deps.items():
            if not var:
                continue
            var_nodes = set()
            for key in expand_var_keys(var):
                var_nodes |= def_index.get(key, set())
            if not var_nodes:
                for key in expand_var_keys(var):
                    var_nodes |= use_index.get(key, set())
            if not var_nodes:
                continue
            for dep in deps:
                if not dep:
                    continue
                dep_nodes = set()
                for key in expand_var_keys(dep):
                    dep_nodes |= def_index.get(key, set())
                if not dep_nodes:
                    for key in expand_var_keys(dep):
                        dep_nodes |= use_index.get(key, set())
                if not dep_nodes:
                    continue
                for src in dep_nodes:
                    for dst in var_nodes:
                        if src != dst:
                            edges.add((src, dst))
    return edges


def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    ast_paths = sorted(Path(args.ast_dir).glob("*.json"))
    for ast_path in ast_paths:
        base = ast_path.stem
        cfg_paths = sorted(Path(args.cfg_dir).glob(f"{base}__*.dot"))
        if not cfg_paths:
            continue
        dfg_path = Path(args.dfg_dir) / f"{base}_dfg.txt"

        ast_root, source_name, _ = load_ast(str(ast_path))
        if not ast_root:
            continue
        ast_nodes, ast_edges, functions, contracts = walk_ast(ast_root)

        source_file = find_source_file(args.src_root, source_name)
        if not source_file:
            continue
        source_text = Path(source_file).read_text(encoding="utf-8", errors="ignore")
        line_starts = compute_line_starts(source_text)

        nodes = []
        cfg_edges = set()
        cfg_nodes_by_function = defaultdict(list)
        next_id = 1
        expr_span_cache = {}
        expr_span_total = 0
        expr_span_missing = 0

        for cfg_path in cfg_paths:
            contract_name, func_name = parse_cfg_filename(str(cfg_path))
            if not contract_name or func_name is None:
                continue
            func_name = normalize_function_name(func_name, contract_name)
            func_span = find_function_span(functions, contracts, contract_name, func_name)
            cfg_nodes, edges = parse_cfg_dot(str(cfg_path))

            local_to_global = {}
            for local_id, info in cfg_nodes.items():
                expr = info.get("expression")
                if expr:
                    expr_span_total += 1
                span = find_expression_span(expr, source_text, func_span, cache=expr_span_cache)
                if expr and span is None:
                    expr_span_missing += 1
                line_start = line_end = None
                if span:
                    line_start, _ = offset_to_line_col(line_starts, span[0])
                    line_end, _ = offset_to_line_col(line_starts, max(span[1] - 1, span[0]))
                global_id = next_id
                next_id += 1
                local_to_global[local_id] = global_id
                node = {
                    "id": global_id,
                    "cfg_node_type": info.get("cfg_node_type"),
                    "contract": contract_name,
                    "function": func_name,
                    "expression": expr,
                    "span": span,
                    "line_start": line_start,
                    "line_end": line_end,
                }
                nodes.append(node)
                cfg_nodes_by_function[(contract_name, func_name)].append(node)

            for src, dst in edges:
                if src in local_to_global and dst in local_to_global:
                    cfg_edges.add((local_to_global[src], local_to_global[dst]))

        ast_edges_mapped, ast_edges_same, ast_unmapped_edges = build_ast_mapping(
            ast_nodes,
            ast_edges,
            cfg_nodes_by_function,
        )
        dfg_map, dfg_parse_errors = parse_dfg(str(dfg_path))
        dfg_edges = build_dfg_edges(cfg_nodes_by_function, dfg_map)

        out = {
            "meta": {
                "source": source_name,
                "source_path": source_file,
                "cfg_node_count": len(nodes),
                "cfg_edge_count": len(cfg_edges),
                "ast_edge_count": len(ast_edges_mapped),
                "ast_same_cfg_edge_count": len(ast_edges_same),
                "ast_unmapped_edge_count": ast_unmapped_edges,
                "dfg_edge_count": len(dfg_edges),
                "dfg_parse_errors": dfg_parse_errors,
                "expr_span_total": expr_span_total,
                "expr_span_missing": expr_span_missing,
            },
            "nodes": nodes,
            "edges": {
                "CFG_FLOW": [{"source": s, "target": t} for s, t in sorted(cfg_edges)],
                "AST_PARENT": [{"source": s, "target": t} for s, t in sorted(ast_edges_mapped)],
                "AST_PARENT_SAME": [{"source": s, "target": t} for s, t in sorted(ast_edges_same)],
                "DFG_DEP": [{"source": s, "target": t} for s, t in sorted(dfg_edges)],
            },
        }

        out_path = Path(args.out_dir) / f"{base}_hetero.json"
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump(out, handle, ensure_ascii=True, indent=2)


if __name__ == "__main__":
    main()
