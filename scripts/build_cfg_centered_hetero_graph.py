#!/usr/bin/env python3
import argparse
import ast as py_ast
import bisect
import json
import os
import re
import sys
from collections import defaultdict, deque
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
    """解析 CLI 参数：AST/CFG/DFG 目录、输出目录、源码根、callback 上限。"""
    parser = argparse.ArgumentParser(description="Build CFG-centered heterogeneous graphs.")
    base = "/home/saumarez/projects/deep-learning/SSM-HG"
    parser.add_argument(
        "--ast-dir",
        default=f"{base}/raw/AST-raw",
        help="Directory containing AST *.json files (output of generate_all_ast_cfg_dfg.sh).",
    )
    parser.add_argument(
        "--cfg-dir",
        default=f"{base}/raw/CFG-raw",
        help="Directory containing per-function CFG *.dot files.",
    )
    parser.add_argument(
        "--dfg-dir",
        default=f"{base}/raw/DFG-raw",
        help="Directory containing *_dfg.txt files.",
    )
    parser.add_argument(
        "--out-dir",
        default=f"{base}/Heterogeneous graphs",
        help="Directory to write *_hetero.json (and later *_m1.json / *_pyg.pt).",
    )
    parser.add_argument(
        "--src-root",
        default=f"{base}/alldata(readonly)/alldata_sol_source",
        help="Read-only root of the Solidity source files used to resolve source paths.",
    )
    parser.add_argument(
        "--callback-limit",
        type=int,
        default=4,
        help="Max CALLBACK_RISK edges per external-call node (0 = unlimited).",
    )
    return parser.parse_args()


def parse_src_range(src_field):
    """把 AST 的 src 字段 "start:length" 解析成 (start, end) 偏移区间；非法返回 None。"""
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
    """每行首字符偏移列表（供偏移→行号二分）。"""
    starts = [0]
    for idx, ch in enumerate(source_text):
        if ch == "\n":
            starts.append(idx + 1)
    return starts


def offset_to_line_col(line_starts, offset):
    """字符偏移 → (行号, 列号)，行号从 1 开始。"""
    line_idx = bisect.bisect_right(line_starts, offset) - 1
    line = line_idx + 1
    col = offset - line_starts[line_idx] + 1
    return line, col


def load_ast(ast_path):
    """读 combined-json AST 文件，返回 (AST 根, 源文件名, sourceKey)。"""
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
    """遍历 AST 收集节点/边/函数表/合约表/状态变量。

    scope 机制（file→contract→body）用于老版 AST 无 stateVariable 键时的
    状态变量回退：contract 直接作用域内的 VariableDeclaration 算状态变量，
    进入 Function/Modifier/Event/Struct/Enum 后 scope="body" 不再收集。
    """
    nodes = {}
    edges = []
    functions = []
    contracts = []
    state_vars = set()

    def visit(node, parent_id=None, contract_name=None, function_ctx=None, scope="file"):
        """递归访问 AST 节点，收集节点/边/函数表/合约表/状态变量。"""
        node_id = node.get("id")
        node_type = node.get("name") or node.get("nodeType")
        attributes = node.get("attributes", {})
        src = node.get("src")

        if node_type == "ContractDefinition":
            contract_name = attributes.get("name")
            scope = "contract"
            contracts.append({
                "id": node_id,
                "name": contract_name,
                "src": parse_src_range(src),
            })

        if node_type in ("FunctionDefinition", "ModifierDefinition",
                         "EventDefinition", "StructDefinition", "EnumDefinition"):
            scope = "body"

        if node_type == "VariableDeclaration":
            is_state = (bool(attributes.get("stateVariable"))
                        if "stateVariable" in attributes
                        else scope == "contract")
            if is_state:
                state_var_name = attributes.get("name")
                if state_var_name:
                    state_vars.add(state_var_name)

        if node_type == "FunctionDefinition":
            raw_name = attributes.get("name", "")
            kind = attributes.get("kind")
            is_constructor = bool(attributes.get("isConstructor"))
            if not kind:
                kind = ("constructor" if (is_constructor or (raw_name and raw_name == contract_name))
                        else "fallback" if raw_name == ""
                        else "function")
            visibility = attributes.get("visibility")
            if not visibility:
                for vis in ("public", "internal", "private", "external"):
                    if attributes.get(vis):
                        visibility = vis
                        break
            state_mutability = attributes.get("stateMutability")
            if not state_mutability:
                state_mutability = ("view" if attributes.get("constant")
                                    else "payable" if attributes.get("payable")
                                    else "nonpayable")
            fn_name = raw_name
            if kind in ("fallback", "receive"):
                fn_name = kind
            elif raw_name == "" and not is_constructor:
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
                "visibility": visibility,
                "state_mutability": state_mutability,
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
            visit(child, node_id, contract_name, function_ctx, scope)

    visit(ast_root)
    return nodes, edges, functions, contracts, state_vars





def find_source_file(src_root, source_name):
    """在只读源码根下按文件名定位源文件；同名多候选时 stderr 告警（兜底路径）。"""
    if not source_name:
        return None
    source_path = Path(source_name)
    if source_path.is_absolute() and source_path.exists():
        return str(source_path)
    name = source_path.name if source_path.is_absolute() or "/" in source_name or "\\" in source_name else source_name
    candidates = list(Path(src_root).rglob(name))
    if not candidates:
        return None
    # 同名 .sol 出现在多个项目目录时，rglob 顺序不定；主路径已用 base 还原相对
    # 路径规避，这里只作兜底并告警便于审计（2026-09-05 新增）。
    if len(candidates) > 1:
        print(f"WARNING: multiple source files match '{name}': "
              f"{[str(c) for c in candidates]} -> use {candidates[0]}",
              file=sys.stderr)
    return str(candidates[0])


def parse_cfg_dot(cfg_path):
    """解析 Slither CFG dot（仅回退路径使用）：节点 label 提取类型/表达式/IR，边提取 id 对。"""
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
        ir = None
        if "EXPRESSION:" in label:
            expr = extract_section(label, "EXPRESSION:", "IRs:")
        if "IRs:" in label:
            ir = extract_section(label, "IRs:", "\x00")   # 取到结尾
        nodes[local_id] = {
            "local_id": local_id,
            "cfg_node_type": node_type,
            "label": label,
            "expression": expr,
            "ir": ir,
        }
    edges = [(int(a), int(b)) for a, b in edge_pattern.findall(text)]
    return nodes, edges


def extract_section(label, start_marker, end_marker):
    """从 dot label 中截取标记之间的文本并去空白；end_marker="\x00" 表示取到结尾。"""
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
    """从 dot 文件名解析 (合约名, 函数名)。

    dot 文件名为 `<项目>__<合约>.sol-<函数签名>.dot`，取 `.sol-` 后第一段为
    合约名、`(` 前为函数名（签名部分丢弃）。无法解析返回 (None, None)。
    """
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
    """把 dot 文件名里的函数名归一成 AST 函数表口径。

    空名→fallback；与合约同名的旧式构造器→constructor；其余原样。
    """
    if func_name is None:
        return None
    if func_name == "":
        return "fallback"
    if func_name == contract_name:
        return "constructor"
    if func_name in {"constructor", "fallback"}:
        return func_name
    return func_name


def find_function_span(functions, contracts, contract_name, func_name):
    """在 AST 函数表中定位函数的源码区间；找不到回退到合约区间。"""
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
            # dot 文件名里的函数名可能带前导下划线（如 _addWhitelistAdmin），
            # 与 AST 函数表（addWhitelistAdmin）不一致时做一次去下划线回退。
            if fn["name"] == func_name or fn["name"] == func_name.lstrip("_"):
                return fn["src"]

    return contract_span


def find_expression_span(expr, source_text, span, cache=None):
    """在源码中定位表达式文本的偏移区间。

    span 给定则优先在函数区间内模糊匹配；否则全文要求唯一命中。
    cache 键为 (expr, span)（或 (expr, None, None)）——cfgdetail 回填路径
    传 cache=None 以免同表达式跨函数错配（2026-09-05）。
    """
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
    """把 AST 边映射到 CFG 节点对：按包含关系选最短 AST 锚点，未映射边计数。

    返回 (映射边集合, 同节点边集合, 未映射边数)。
    """
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
    """解析 Slither data-dependency 表。

    返回 ({(contract,function): {var: [deps]}}, 解析失败行数, 非表噪声行数)；
    合同级变量行键为 (contract, None)，供跨函数数据流使用。
    """
    if not dfg_path or not os.path.exists(dfg_path):
        return {}, 0, 0
    results = defaultdict(dict)
    current_contract = None
    current_function = None
    parse_errors = 0
    # 非表行计数（2026-09-05 新增）：Slither 依赖表里夹带的递归函数名、
    # 代码片段、告警文本等噪声行，写入图 meta 用于审计表格式健康度。
    non_table_lines = 0
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
            # 表行都以 | 开头；+--- 是表边框分隔线（表的一部分）在此跳过；
            # 其余非空行（solc 命令日志、INFO 行等）才是依赖表的真正噪声
            if not line.startswith("|"):
                if line and not line.startswith("+"):
                    non_table_lines += 1
                continue
            if line.startswith("| Variable"):
                continue
            if current_contract is None:
                continue
            # 合同级变量行（current_function 为 None）也保留，键为 (contract, None)
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
    return results, parse_errors, non_table_lines


def is_type_token(token):
    """token 是否为类型/关键字（EXCLUDED_TOKENS 或 uintN/intN/bytesN）。"""
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
    """从表达式提取标识符 token（含 a.b 成员链），过滤类型/关键字。"""
    if not expr:
        return set()
    tokens = re.findall(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*", expr)
    return {tok for tok in tokens if not is_type_token(tok)}


def split_assignment(expr):
    """把表达式拆成 (LHS, RHS, 运算符)；比较/等号跳过，非赋值返回 (None,None,None)。"""
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
    """从表达式提取 (defs, uses)：赋值 LHS 为 defs，RHS 为 uses；复合赋值两边同计。"""
    left, right, op = split_assignment(expr)
    if left is None:
        return set(), extract_tokens(expr)
    defs = extract_tokens(left)
    uses = extract_tokens(right)
    if op and op != "=":
        uses |= defs
    return defs, uses


def expand_var_keys(name):
    """变量名 → 匹配键集合（原名 + 成员名回退，如 Contract.var → var）。"""
    keys = {name}
    if "." in name:
        keys.add(name.split(".")[-1])
    return keys


def expand_token_keys(token):
    """token → 匹配键集合：原名 + base 键 + 成员名回退键（msg./block./tx. 前缀除外）。

    用于 DFG def/use 索引，让 "self.credit" 依赖与变量 credit 互连
    （2026-09-05 新增成员名回退；this.balance→balance 属正确语义）。
    """
    keys = {token}
    if "." in token and not token.startswith(("msg.", "block.", "tx.")):
        # base 键（如 self.credit → "self"）
        keys.add(token.rsplit(".", 1)[0])
        # 成员名回退键（如 self.credit → "credit"）：与局部/状态变量的纯名字键
        # 对齐，让 "x.credit" 依赖与变量 credit 互连（2026-09-05 新增）。
        # msg./block./tx. 前缀已在上面排除（sender/value/origin 不是用户变量）。
        # 注意 this.balance → "balance" 属于正确语义（读取合约余额）。
        keys.add(token.rsplit(".", 1)[-1])
    return keys


def build_dfg_edges(cfg_nodes_by_function, dfg_map, state_vars=None):
    """由 Slither data-dependency 表重建 DFG_DEP 边。

    - 状态变量（名字命中 state_vars，或带 "Contract.var" 前缀）在**合同级**
      建立 def/use 索引，支持跨函数数据流（如构造函数写入、其他函数读取）；
    - 局部变量在函数内建立索引，避免不同函数同名局部变量误连；
    - 每个 (var, deps) 行：src = dep 的定义节点（无定义则使用节点），
      dst = var 的定义节点（无定义则使用节点），src != dst 才连边。
    """
    state_vars = state_vars or set()
    state_vars_norm = {str(s).lower() for s in state_vars}

    nodes_by_contract = defaultdict(list)
    for key, nodes in cfg_nodes_by_function.items():
        nodes_by_contract[key[0]].extend(nodes)

    def build_index(nodes):
        """为节点列表建 def/use 索引：键经 expand_token_keys 展开。"""
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
        return def_index, use_index

    def is_state_var(name):
        """名字（含 Contract.var 前缀/成员）末段是否命中状态变量。"""
        return name.rsplit(".", 1)[-1].lower() in state_vars_norm

    fn_index_cache = {}
    contract_index_cache = {}

    def fn_index(func_key):
        """函数级 def/use 索引（带缓存，空函数返回空索引）。"""
        if func_key not in fn_index_cache:
            nodes = cfg_nodes_by_function.get(func_key)
            fn_index_cache[func_key] = build_index(nodes) if nodes else (defaultdict(set), defaultdict(set))
        return fn_index_cache[func_key]

    def contract_index(contract):
        """合同级 def/use 索引（带缓存，跨函数数据流用）。"""
        if contract not in contract_index_cache:
            contract_index_cache[contract] = build_index(nodes_by_contract.get(contract, []))
        return contract_index_cache[contract]

    edges = set()
    for func_key, var_deps in dfg_map.items():
        contract = func_key[0]
        nodes = cfg_nodes_by_function.get(func_key)
        if not nodes and func_key[1] is None:
            # 合同级变量行：锚定到 slitherConstructorVariables 合成函数节点
            nodes = cfg_nodes_by_function.get((contract, "slitherConstructorVariables"))
        if not nodes:
            continue
        fdef, fuse = fn_index(func_key)
        cdef, cuse = contract_index(contract)
        for var, deps in var_deps.items():
            if not var:
                continue
            var_keys = expand_var_keys(var)
            if is_state_var(var):
                vdef = set().union(*(cdef.get(k, set()) for k in var_keys))
                vuse = set().union(*(cuse.get(k, set()) for k in var_keys))
            else:
                vdef = set().union(*(fdef.get(k, set()) for k in var_keys))
                vuse = set().union(*(fuse.get(k, set()) for k in var_keys))
            if not vdef and not vuse:
                continue
            # dst 取 var 的全部定义+使用节点（状态变量为合同级，捕获跨函数 def→use 数据流）
            dsts = vdef | vuse
            for dep in deps:
                if not dep:
                    continue
                dep_keys = expand_var_keys(dep)
                if is_state_var(dep):
                    ddef = set().union(*(cdef.get(k, set()) for k in dep_keys))
                    duse = set().union(*(cuse.get(k, set()) for k in dep_keys))
                else:
                    ddef = set().union(*(fdef.get(k, set()) for k in dep_keys))
                    duse = set().union(*(fuse.get(k, set()) for k in dep_keys))
                if not ddef and not duse:
                    continue
                srcs = ddef or duse
                for src in srcs:
                    for dst in dsts:
                        if src != dst:
                            edges.add((src, dst))
    return edges


# ---------------------------------------------------------------------------
# CALLBACK_RISK（大纲 4.2.2，保守回调风险先验，8 步算法）
# ---------------------------------------------------------------------------

RE_EXT_CALL_TEXT = re.compile(
    r"\.\s*call\s*(?:\{|\(|\.)|\.\s*send\s*\(|\.\s*transfer\s*\(", re.IGNORECASE
)
RE_TRANSFER_TEXT = re.compile(r"\.\s*transfer\s*\(", re.IGNORECASE)
RE_IR_EXT_CALL = re.compile(r"\b(?:LOW_LEVEL_CALL|SEND|TRANSFER)\b", re.IGNORECASE)
# 余额映射**写入**判定（2026-09-05 第四轮修复）：
# SlithIR 的读取形态是 `REF -> balances[x]`，写入形态是
# `balances[x] (uint256) := TMP` 或 `REF (->balances) := TMP`。
# 旧正则 \b(?:balances?|mapping)\b 不区分方向，把读取也判成“余额映射更新”，
# 抬高 CALLBACK_RISK（实测 rubixi 节点 16 的 ir 同时含读/写两种形态）。
# “mapping”是 Solidity 类型关键字，不出现在 IR 指令文本中，故删除该分支。
RE_BALANCE_MAPPING = re.compile(
    r"\(\s*->\s*balances?\s*\)\s*:=|"          # (->balances) := 指针写
    r"\b(?:balances?)\s*(?:\[[^\]\n]*\])?\s*(?:\([^)]*\))?\s*:=",  # balances[x] (...) := 普通写
    re.IGNORECASE,
)


def node_is_external_call(node):
    """节点是否为外部调用（expression 正则或 ir 含 LOW_LEVEL_CALL/SEND/TRANSFER）。"""
    expr = node.get("expression") or ""
    ir = node.get("ir") or ""
    if RE_EXT_CALL_TEXT.search(expr):
        return True
    return bool(RE_IR_EXT_CALL.search(ir))


def node_is_state_write(node, state_vars_lower):
    """节点是否为状态写入（CALLBACK_RISK 步骤 4 用）。

    三种判据：expression 含 .transfer(；赋值 LHS token 命中状态变量；
    ir 命中余额映射**写入**形态正则（读取 `-> balances[x]` 不算，2026-09-05）。
    """
    expr = node.get("expression") or ""
    ir = node.get("ir") or ""
    if RE_TRANSFER_TEXT.search(expr):
        return True
    left, _, _ = split_assignment(expr)
    if left is not None:
        for token in extract_tokens(left):
            if token.lower() in state_vars_lower or token.rsplit(".", 1)[-1].lower() in state_vars_lower:
                return True
    return bool(RE_BALANCE_MAPPING.search(ir))


def node_has_transfer_or_balance(node):
    """节点是否含转账或余额映射写入（CALLBACK_RISK 入口过滤步骤 5 用）。"""
    expr = node.get("expression") or ""
    ir = node.get("ir") or ""
    if RE_TRANSFER_TEXT.search(expr):
        return True
    return bool(RE_BALANCE_MAPPING.search(ir))


def has_state_write_successor(
    start_id, adj, node_by_id, state_vars_lower, function_key, max_depth=10
):
    """沿 CFG_FLOW 后继（同函数内，有限深度）查找状态写入节点。"""
    visited = {start_id}
    queue = deque([(start_id, 0)])
    while queue:
        cur, depth = queue.popleft()
        for nxt in adj.get(cur, []):
            if nxt in visited:
                continue
            visited.add(nxt)
            node = node_by_id.get(nxt)
            if node is None or (node.get("contract"), node.get("function")) != function_key:
                continue
            if node_is_state_write(node, state_vars_lower):
                return True
            if depth + 1 < max_depth:
                queue.append((nxt, depth + 1))
    return False


def build_callback_risk_edges(nodes, cfg_edges, fn_table, state_vars, callback_limit):
    """大纲 4.2.2 八步：外部调用节点 → 满足条件的入口节点（单向）。

    返回 (callback_edges, truncated_candidates, ext_call_node_count)。
    """
    node_by_id = {node["id"]: node for node in nodes}
    state_vars_lower = {str(sv).lower() for sv in state_vars}

    adj = defaultdict(list)
    fn_node_ids = defaultdict(set)
    for node in nodes:
        fn_node_ids[(node.get("contract"), node.get("function"))].add(node["id"])
    for src, dst in cfg_edges:
        adj[src].append(dst)

    # 步骤 1：收集外部调用节点 V_ext
    ext_nodes = [node for node in nodes if node_is_external_call(node)]

    # 步骤 2：收集入口节点 V_entry（ENTRY_POINT/ENTRYPOINT 且 visibility/kind 满足）
    # Slither 0.11.5 的 NodeType 枚举名是 ENTRYPOINT（无下划线），两种都接受。
    entry_nodes = []
    for node in nodes:
        if node.get("cfg_node_type") not in ("ENTRY_POINT", "ENTRYPOINT"):
            continue
        fn = fn_table.get((node.get("contract"), node.get("function")))
        if not fn:
            continue
        visibility = (fn.get("visibility") or "").lower()
        kind = (fn.get("kind") or "").lower()
        if visibility in {"public", "external"} or kind in {"receive", "fallback"}:
            entry_nodes.append(node)

    # 步骤 5：入口过滤（禁止连接函数体只有状态读取/事件发射/普通算术的入口）
    qualified_entries = []
    for entry in entry_nodes:
        fn = fn_table.get((entry.get("contract"), entry.get("function"))) or {}
        kind = (fn.get("kind") or "").lower()
        fn_ids = fn_node_ids.get((entry.get("contract"), entry.get("function")), set())
        fn_nodes = [node_by_id[i] for i in fn_ids if i in node_by_id]
        has_state_write = any(node_is_state_write(n, state_vars_lower) for n in fn_nodes)
        has_transfer_balance = any(node_has_transfer_or_balance(n) for n in fn_nodes)
        has_ext_call = any(node_is_external_call(n) for n in fn_nodes)
        if kind in ("receive", "fallback"):
            ok = has_state_write or has_transfer_balance or has_ext_call
        else:
            ok = has_transfer_balance or has_ext_call
        if not ok:
            continue
        # 步骤 7 优先级：receive/fallback > 含转账或余额映射更新的入口 > 其他
        if kind in ("receive", "fallback"):
            priority = 0
        elif has_transfer_balance:
            priority = 1
        else:
            priority = 2
        qualified_entries.append((priority, entry))
    qualified_entries.sort(key=lambda item: item[0])

    # 步骤 3+4+6+7：调用方过滤、调用后状态写入检查、建边（单向）、稀疏化
    callback_edges = set()
    truncated = 0
    ext_call_node_count = len(ext_nodes)
    for ext in ext_nodes:
        fn = fn_table.get((ext.get("contract"), ext.get("function"))) or {}
        mutability = (fn.get("stateMutability") or "").lower()
        if mutability in ("view", "pure"):
            continue
        function_key = (ext.get("contract"), ext.get("function"))
        if not has_state_write_successor(
            ext["id"], adj, node_by_id, state_vars_lower, function_key, max_depth=10
        ):
            continue
        # 回调只可能重新进入当前合约的公开入口。
        cands = [
            entry for _, entry in qualified_entries
            if entry.get("contract") == ext.get("contract")
        ]
        limit = callback_limit if callback_limit > 0 else len(cands)
        truncated += max(0, len(cands) - limit)
        for entry in cands[:limit]:
            callback_edges.add((ext["id"], entry["id"]))

    return callback_edges, truncated, ext_call_node_count


def main():
    """主流程：逐 AST 文件构建 CFG 中心异构图，写入 Heterogeneous graphs/。

    CFG 来源优先 cfgdetail（含 seq/true/false 分支类型），缺失回退 dot 解析。
    """
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    ast_paths = sorted(Path(args.ast_dir).glob("*.json"))
    skipped_no_cfg = 0
    for ast_path in ast_paths:
        base = ast_path.stem
        cfg_paths = sorted(Path(args.cfg_dir).glob(f"{base}__*.dot"))
        cfgdetail_path = Path(args.cfg_dir) / f"{base}__cfgdetail.json"
        cfgdetail_missing = not cfgdetail_path.exists()
        cfgdetail_invalid = False
        # 无 dot 且无 cfgdetail 才提前跳过；cfgdetail 损坏（invalid）在此处尚未检测，
        # 由下方解析后 `if not cfg_paths and not cfg_functions` 分支统一处理并计数。
        if not cfg_paths and cfgdetail_missing:
            continue
        if cfgdetail_missing:
            cfg_functions = None
        else:
            try:
                cfg_functions = json.loads(
                    cfgdetail_path.read_text(encoding="utf-8")
                ).get("functions", [])
            except (OSError, json.JSONDecodeError, AttributeError):
                cfg_functions = None
                cfgdetail_invalid = True
        if not cfg_paths and not cfg_functions:
            skipped_no_cfg += 1
            continue
        dfg_path = Path(args.dfg_dir) / f"{base}_dfg.txt"

        ast_root, source_name, _ = load_ast(str(ast_path))
        if not ast_root:
            continue
        ast_nodes, ast_edges, functions, contracts, state_vars = walk_ast(ast_root)

        rel_guess = Path(args.src_root) / (base.replace("__", "/") + ".sol")
        source_file = str(rel_guess) if rel_guess.exists() else find_source_file(args.src_root, source_name)
        if not source_file:
            continue
        source_text = Path(source_file).read_text(encoding="utf-8", errors="ignore")
        line_starts = compute_line_starts(source_text)

        # 函数表（contract, function）→ 元信息 + 起止行号（手册 7.5）
        fn_table = {}
        for fn in functions:
            span = fn.get("src")
            start_line = end_line = None
            if span:
                start_line, _ = offset_to_line_col(line_starts, span[0])
                end_line, _ = offset_to_line_col(line_starts, max(span[1] - 1, span[0]))
            key = (fn.get("contract"), fn.get("name"))
            if key not in fn_table:
                fn_table[key] = {
                    "contract": fn.get("contract"),
                    "function": fn.get("name"),
                    "visibility": fn.get("visibility"),
                    "stateMutability": fn.get("state_mutability"),
                    "kind": fn.get("kind"),
                    "start_line": start_line,
                    "end_line": end_line,
                }
        functions_out = list(fn_table.values())

        nodes = []
        cfg_edges = set()
        cfg_edge_kinds = {}
        cfg_nodes_by_function = defaultdict(list)
        next_id = 1
        expr_span_cache = {}
        expr_span_total = 0
        expr_span_missing = 0
        ir_missing = 0

        if cfg_functions:
            # 用 dump_cfg.py 的 cfgdetail（含 seq/true/false 分支类型）替代 dot 解析
            for f in cfg_functions:
                contract_name, raw_func_name = f["contract"], f["function"]
                func_name = normalize_function_name(raw_func_name, contract_name)
                local_to_global = {}
                for nd in f["nodes"]:
                    global_id = next_id
                    next_id += 1
                    local_to_global[nd["local_id"]] = global_id
                    expr = nd.get("expression")
                    ir = nd.get("ir")
                    if expr:
                        expr_span_total += 1
                    if expr and not ir:
                        ir_missing += 1
                    # cfgdetail 节点自带 line_start/line_end，span 只用于缺行号回填；
                    # 回退匹配不共享缓存：缓存键只有 (expr, None, None)，同一表达式
                    # 出现在多个函数时会错配到第一个函数（2026-09-05 修复）。
                    # dot 回退路径的缓存键含 func_span，不受影响。
                    span = find_expression_span(expr, source_text, None, cache=None)
                    line_start = nd.get("line_start")
                    line_end = nd.get("line_end")
                    if (line_start is None or line_end is None) and span:
                        line_start, _ = offset_to_line_col(line_starts, span[0])
                        line_end, _ = offset_to_line_col(line_starts, max(span[1] - 1, span[0]))
                    if expr and span is None:
                        expr_span_missing += 1
                    fn_meta = fn_table.get((contract_name, func_name)) or {}
                    node = {
                        "id": global_id,
                        "cfg_node_type": nd.get("cfg_node_type"),
                        "contract": contract_name,
                        "function": func_name,
                        "expression": expr,
                        "ir": ir,
                        "is_unchecked": bool(nd.get("is_unchecked")),
                        "span": span,
                        "line_start": line_start,
                        "line_end": line_end,
                        "function_visibility": fn_meta.get("visibility"),
                        "function_mutability": fn_meta.get("stateMutability"),
                    }
                    nodes.append(node)
                    cfg_nodes_by_function[(contract_name, func_name)].append(node)
                for e in f["edges"]:
                    s = local_to_global.get(e["source"])
                    t = local_to_global.get(e["target"])
                    if s and t:
                        cfg_edges.add((s, t))
                        cfg_edge_kinds[(s, t)] = e.get("kind", "seq")
        else:
            for cfg_path in cfg_paths:
                contract_name, func_name = parse_cfg_filename(str(cfg_path))
                if not contract_name or func_name is None:
                    continue
                func_name = normalize_function_name(func_name, contract_name)
                # dot 文件名的函数名可能带前导下划线，与 AST 函数表不一致时回退
                if ((contract_name, func_name) not in fn_table
                        and (contract_name, func_name.lstrip("_")) in fn_table):
                    func_name = func_name.lstrip("_")
                func_span = find_function_span(functions, contracts, contract_name, func_name)
                cfg_nodes, edges = parse_cfg_dot(str(cfg_path))

                local_to_global = {}
                for local_id, info in cfg_nodes.items():
                    expr = info.get("expression")
                    ir = info.get("ir")
                    if expr:
                        expr_span_total += 1
                    if expr and not ir:
                        ir_missing += 1
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
                    fn_meta = fn_table.get((contract_name, func_name)) or {}
                    node = {
                        "id": global_id,
                        "cfg_node_type": info.get("cfg_node_type"),
                        "contract": contract_name,
                        "function": func_name,
                        "expression": expr,
                        "ir": ir,
                        "is_unchecked": bool(info.get("is_unchecked")),
                        "span": span,
                        "line_start": line_start,
                        "line_end": line_end,
                        "function_visibility": fn_meta.get("visibility"),
                        "function_mutability": fn_meta.get("stateMutability"),
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
        dfg_map, dfg_parse_errors, dfg_non_table_lines = parse_dfg(str(dfg_path))
        dfg_edges = build_dfg_edges(cfg_nodes_by_function, dfg_map, state_vars)

        cfg_seq_edge_count = sum(
            1 for s, t in cfg_edges if cfg_edge_kinds.get((s, t), "seq") == "seq"
        )
        cfg_true_edge_count = sum(
            1 for s, t in cfg_edges if cfg_edge_kinds.get((s, t)) == "true"
        )
        cfg_false_edge_count = sum(
            1 for s, t in cfg_edges if cfg_edge_kinds.get((s, t)) == "false"
        )

        callback_edges, callback_truncated, ext_call_node_count = build_callback_risk_edges(
            nodes, cfg_edges, fn_table, state_vars, args.callback_limit
        )
        callback_edge_counts = defaultdict(int)
        for src, _ in callback_edges:
            callback_edge_counts[src] += 1
        callback_max_edges = max(callback_edge_counts.values(), default=0)
        # 分母为全部外部调用节点（含被调用上限截断、未产出边的候选），
        # 因此平均含 0，与论文"平均每个外部调用节点的保守风险边数"口径一致。
        callback_avg_edges = (
            round(len(callback_edges) / ext_call_node_count, 4) if ext_call_node_count else 0.0
        )

        out = {
            "meta": {
                "source": source_name,
                "source_path": source_file,
                "cfg_node_count": len(nodes),
                "cfg_edge_count": len(cfg_edges),
                "cfg_seq_edge_count": cfg_seq_edge_count,
                "cfg_true_edge_count": cfg_true_edge_count,
                "cfg_false_edge_count": cfg_false_edge_count,
                "cfgdetail_missing": cfgdetail_missing,
                "cfgdetail_invalid": cfgdetail_invalid,
                "ast_edge_count": len(ast_edges_mapped),
                "ast_same_cfg_edge_count": len(ast_edges_same),
                "ast_unmapped_edge_count": ast_unmapped_edges,
                "dfg_edge_count": len(dfg_edges),
                "dfg_parse_errors": dfg_parse_errors,
                "dfg_non_table_lines": dfg_non_table_lines,
                "expr_span_total": expr_span_total,
                "expr_span_missing": expr_span_missing,
                "ir_missing": ir_missing,
                "state_vars": sorted(state_vars),
                "callback_risk_edge_count": len(callback_edges),
                "ext_call_node_count": ext_call_node_count,
                "callback_max_edges": callback_max_edges,
                "callback_avg_edges": callback_avg_edges,
                "callback_truncated_candidates": callback_truncated,
            },
            "functions": functions_out,
            "nodes": nodes,
            "edges": {
                "CFG_FLOW": [
                    {"source": s, "target": t, "kind": cfg_edge_kinds.get((s, t), "seq")}
                    for s, t in sorted(cfg_edges)
                ],
                "AST_PARENT": [{"source": s, "target": t} for s, t in sorted(ast_edges_mapped)],
                "AST_PARENT_SAME": [{"source": s, "target": t} for s, t in sorted(ast_edges_same)],
                "DFG_DEP": [{"source": s, "target": t} for s, t in sorted(dfg_edges)],
                "CALLBACK_RISK": [
                    {"source": s, "target": t} for s, t in sorted(callback_edges)
                ],
            },
        }

        out_path = Path(args.out_dir) / f"{base}_hetero.json"
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump(out, handle, ensure_ascii=True, indent=2)

    print(f"Processed {len(ast_paths)} AST files, {skipped_no_cfg} skipped (no CFG dot & no cfgdetail)")


if __name__ == "__main__":
    main()
