"""
priori_scoring.py  —  M1 漏洞语义引导锚点检测
=================================================
对大纲 §4.1.2 七类漏洞实现锚点布尔判定函数,并在此基础上提供:
  - compute_anchor_flags(node_id, ctx)  → dict[str, bool]
    - compute_anchor_score(node_id, ctx)  → float  (供 M1 全图归一化)
  - GraphContext                         数据类,封装 Slither JSON 解析结果

依赖:Python ≥ 3.9,无第三方包(纯标准库 + 数据类)

注意:VULN_CLASSES 是七类报告顺序,EXCLUSIVE_RULE_PRIORITY 是互斥仲裁顺序,
两者不同;m1_runner 的 meta.exclusive_priority 记录的是后者(2026-09-05 修正)。
"""

from __future__ import annotations

import re
import json
import logging
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# 节点类型常量(与 M2 保持一致,大纲 §4.2.1)
# ---------------------------------------------------------------------------
NT_ENTRY       = "ENTRY"
NT_CONDITION   = "CONDITION"
NT_ASSIGNMENT  = "ASSIGNMENT"
NT_CALL        = "CALL"
NT_STATE_WRITE = "STATE_WRITE"
NT_RETURN      = "RETURN"
NT_OTHER       = "OTHER"

# BFS 最大深度(DoS / front-running 图上下文检测,大纲明确为 ≤2)
BFS_MAX_DEPTH = 2

# ---------------------------------------------------------------------------
# GraphContext  —  封装单份 Slither JSON 所需的全部查询接口
# ---------------------------------------------------------------------------

@dataclass
class GraphContext:
    """从 Slither JSON 解析出的图上下文,供所有锚点函数共享。

    Attributes
    ----------
    nodes : dict[str|int, dict]
        node_id → node_dict。字段包括 'expression', 'cfg_node_type',
        'is_unchecked' 等。node_id 保持 JSON 原始类型(int 或 str)。
    adj_cfg : dict[str|int, list[str|int]]
        CFG_FLOW 有向出边邻接表。自环(AST_PARENT_SAME)在构造时过滤。
    state_vars : set[str]
        合约级状态变量名集合(统一小写),用于 front-running 白名单。
    bool_consumed_nodes : set[str|int]
        返回值 bool 已被 require/assert/if 消费的节点 id 集合。
    """

    nodes: dict[str | int, dict] = field(default_factory=dict)
    adj_cfg: dict[str | int, list] = field(default_factory=dict)
    adj_cfg_rev: dict[str | int, list] = field(default_factory=dict)
    state_vars: set[str] = field(default_factory=set)
    # 状态变量原始大小写名集合(Solidity 标识符大小写敏感,局部变量小写遮蔽不能命中)
    state_vars_case: set[str] = field(default_factory=set)
    bool_consumed_nodes: set[str | int] = field(default_factory=set)
    # CALLBACK_RISK 边的 source ∪ target（external_callback 辅助信号，+0.5 分）
    external_callback_nodes: set[str | int] = field(default_factory=set)
    # 合约 pragma 是否 < 0.8：pre-0.8 编译器无内置溢出检查，算术锚点全量命中
    pre_0_8: bool = False
    # (contract, function) → 函数体内含具备重入能力外部调用（跨函数重入检测用）
    functions_with_capable_call: set = field(default_factory=set)

    # ------------------------------------------------------------------
    # 工厂方法
    # ------------------------------------------------------------------

    @classmethod
    def from_slither_json(cls, slither_data: dict) -> "GraphContext":
        """解析 Slither JSON 顶层结构,构造 GraphContext。

        兼容:
          - contracts[0].cfg_nodes + contracts[0].cfg_edges  (标准格式)
          - 顶层 cfg_nodes + sons 字段                       (简化格式)
        """
        ctx = cls()

        # ---- 1. 定位节点/边列表 ----------------------------------------
        contracts = slither_data.get("contracts") or []
        first_contract: dict = contracts[0] if contracts else slither_data

        raw_nodes: list[dict] = (
            first_contract.get("cfg_nodes")
            or first_contract.get("nodes")
            or slither_data.get("cfg_nodes")
            or slither_data.get("nodes")
            or []
        )
        raw_edges: list[dict] = (
            first_contract.get("cfg_edges")
            or first_contract.get("edges")
            or slither_data.get("cfg_edges")
            or slither_data.get("edges")
            or []
        )

        # ---- 2. 构建 nodes 映射 ----------------------------------------
        for n in raw_nodes:
            nid = n.get("id") if "id" in n else n.get("node_id")
            if nid is None:
                continue
            ctx.nodes[nid] = n

        # ---- 3. 构建 adj_cfg -------------------------------------------
        #  方式 A:从 edges 列表(标准格式)
        for e in raw_edges:
            etype = str(e.get("edge_type") or e.get("type") or "")
            # 只保留 CFG_FLOW 类边;忽略 AST_PARENT / DFG_DEP
            if "CFG" not in etype.upper() and "FLOW" not in etype.upper():
                continue
            src = e.get("src") if "src" in e else e.get("source")
            dst = e.get("dst") if "dst" in e else e.get("target")
            if src is None or dst is None or src == dst:   # 过滤自环
                continue
            ctx.adj_cfg.setdefault(src, []).append(dst)

        #  方式 B:从 node.sons 字段(简化 JSON 格式)
        if not ctx.adj_cfg:
            for nid, n in ctx.nodes.items():
                for son in n.get("sons", []):
                    if son != nid:  # 过滤自环
                        ctx.adj_cfg.setdefault(nid, []).append(son)

        #  反向邻接(dos 祖先检测用)
        ctx.adj_cfg_rev = _build_rev_adj(ctx.adj_cfg)

        # ---- 4. 状态变量白名单 -----------------------------------------
        ctx.state_vars = load_state_vars_from_slither_json(slither_data)
        ctx.state_vars_case = load_state_vars_case_from_slither_json(slither_data)

        # ---- 5. 布尔消费预计算 -----------------------------------------
        ctx.bool_consumed_nodes = _build_bool_consumed_set(ctx.nodes)

        return ctx

    @classmethod
    def from_hetero_json(cls, hetero_data: dict) -> "GraphContext":
        """解析 M2 输出的 *_hetero.json,构造 GraphContext。

        兼容 build_cfg_centered_hetero_graph.py 当前输出:
          - 顶层 meta / nodes / edges
          - nodes[i] 形如 {id, cfg_node_type, contract, function,
            expression, span, line_start, line_end, ...}
          - edges 形如 {CFG_FLOW: [...], AST_PARENT: [...], ...}
        """
        ctx = cls()

        raw_nodes = hetero_data.get("nodes") or []
        raw_edges = hetero_data.get("edges") or {}

        for node in raw_nodes:
            normalized = _normalize_hetero_node(node)
            node_id = normalized.get("id")
            if node_id is None:
                continue
            ctx.nodes[node_id] = normalized

        ctx.adj_cfg = _build_cfg_adj_from_hetero_edges(raw_edges)
        ctx.adj_cfg_rev = _build_rev_adj(ctx.adj_cfg)
        ctx.external_callback_nodes = _build_callback_nodes_from_edges(raw_edges)
        ctx.state_vars = load_state_vars_from_slither_json(hetero_data)
        if not ctx.state_vars:
            ctx.state_vars = load_state_vars_from_source(hetero_data)
        meta_sv = (hetero_data.get("meta") or {}).get("state_vars") or []
        ctx.state_vars_case = {str(sv).strip() for sv in meta_sv if str(sv).strip()}
        ctx.bool_consumed_nodes = _build_bool_consumed_set(ctx.nodes)
        # 预计算含重入能力外部调用的函数集合(跨函数重入锚点用)
        ctx.functions_with_capable_call = {
            (n.get("contract"), n.get("function"))
            for n in ctx.nodes.values()
            if _is_reentrancy_capable_call(str(n.get("expression") or ""),
                                           str(n.get("ir") or ""))
        }
        return ctx

    @classmethod
    def from_any_json(cls, data: dict) -> "GraphContext":
        """自动识别并解析旧 Slither JSON 或当前 *_hetero.json。"""
        if isinstance(data.get("edges"), dict) and "nodes" in data:
            return cls.from_hetero_json(data)
        return cls.from_slither_json(data)

    @classmethod
    def from_json_file(cls, path: str | Path) -> "GraphContext":
        """从 JSON 文件加载上下文：自动识别 hetero/legacy 格式，并解析源码
        pragma 填充 pre_0_8（无 pragma 按 0.8.x 处理，与生成流水线一致）。
        """
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        ctx = cls.from_any_json(data)
        ctx.pre_0_8 = detect_pre_0_8(_resolve_source_path(data.get("meta"), path))
        return ctx

    # ------------------------------------------------------------------
    # 查询辅助
    # ------------------------------------------------------------------

    def get_expr(self, node_id: Any) -> str:
        """返回节点 expression 字符串,缺失时返回空串(空安全)。"""
        node = self.nodes.get(node_id, {})
        return str(node.get("expression") or node.get("expr") or "")

    def get_ir(self, node_id: Any) -> str:
        """返回节点 SlithIR 文本,缺失时返回空串(空安全)。"""
        node = self.nodes.get(node_id, {})
        return str(node.get("ir") or "")

    def get_node_type(self, node_id: Any) -> str:
        """返回 cfg_node_type,缺失时返回 OTHER。"""
        node = self.nodes.get(node_id, {})
        return str(
            node.get("cfg_node_type")
            or node.get("node_type")
            or NT_OTHER
        ).upper()

    def is_unchecked(self, node_id: Any) -> bool:
        """节点是否处于 unchecked{} 块。"""
        node = self.nodes.get(node_id, {})
        return bool(
            node.get("is_unchecked")
            or node.get("in_unchecked_block")
        )

    def successors_bfs(
        self,
        start_id: Any,
        max_depth: int = BFS_MAX_DEPTH,
    ) -> list[tuple[Any, int]]:
        """沿 CFG_FLOW 出边 BFS,返回 [(node_id, depth), ...] 列表。

        - 不包含 start_id 自身(depth=0)。
        - adj_cfg 已在构造时去除自环,此处无需再判断。
        """
        visited: set = {start_id}
        queue: deque[tuple[Any, int]] = deque([(start_id, 0)])
        result: list[tuple[Any, int]] = []
        while queue:
            cur, depth = queue.popleft()
            if depth > 0:
                result.append((cur, depth))
            if depth >= max_depth:
                continue
            for nxt in self.adj_cfg.get(cur, []):
                if nxt not in visited:
                    visited.add(nxt)
                    queue.append((nxt, depth + 1))
        return result

    def predecessors_bfs(
        self,
        start_id: Any,
        max_depth: int = 10,
    ) -> list[tuple[Any, int]]:
        """沿 CFG_FLOW 反向(前驱) BFS,返回 [(node_id, depth), ...] 列表。

        用于判断节点是否位于循环体内(CFG 祖先含循环控制节点)。
        """
        visited: set = {start_id}
        queue: deque[tuple[Any, int]] = deque([(start_id, 0)])
        result: list[tuple[Any, int]] = []
        while queue:
            cur, depth = queue.popleft()
            if depth > 0:
                result.append((cur, depth))
            if depth >= max_depth:
                continue
            for prv in self.adj_cfg_rev.get(cur, []):
                if prv not in visited:
                    visited.add(prv)
                    queue.append((prv, depth + 1))
        return result


def _normalize_hetero_node(node: dict) -> dict:
    """把 *_hetero.json 节点扁平化成 M1 规则可消费的格式。"""
    attributes = node.get("attributes") or {}
    raw_type = node.get("cfg_node_type") or node.get("type") or attributes.get("type")
    expression = _extract_node_expression(node, attributes)
    normalized = dict(node)
    normalized["cfg_node_type"] = _normalize_cfg_node_type(raw_type, expression)
    normalized["raw_cfg_node_type"] = raw_type
    normalized["expression"] = expression
    if "id" in normalized:
        normalized["id"] = normalized["id"]
    normalized["contract"] = node.get("contract")
    normalized["function"] = node.get("function")
    normalized["line_start"] = node.get("line_start")
    normalized["line_end"] = node.get("line_end")
    normalized["span"] = node.get("span")
    return normalized


def _extract_node_expression(node: dict, attributes: dict[str, Any] | None = None) -> str:
    """从 hetero 节点的多种字段里提取表达式文本。"""
    candidate_fields = (
        node.get("expression"),
        node.get("expr"),
        node.get("label"),
        node.get("name"),
    )
    for value in candidate_fields:
        if isinstance(value, str) and value.strip():
            return value.strip()

    attributes = attributes or node.get("attributes") or {}
    if isinstance(attributes, dict):
        for key in ("expression", "expr", "label", "value", "text", "name"):
            value = attributes.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return ""


def _normalize_cfg_node_type(raw_type: Any, expression: str = "") -> str:
    """把 hetero 节点类型归一成 M1 使用的有限类型集合。"""
    if raw_type is None:
        raw_type = ""
    node_type = str(raw_type).upper().strip()
    expr = expression or ""

    if not node_type:
        return NT_OTHER
    if node_type in {NT_ENTRY, NT_CONDITION, NT_ASSIGNMENT, NT_CALL, NT_STATE_WRITE, NT_RETURN}:
        return node_type
    if any(token in node_type for token in ("ENTRY", "START")):
        return NT_ENTRY
    if any(token in node_type for token in ("RETURN", "EXIT")):
        return NT_RETURN
    if any(token in node_type for token in ("IF", "CONDITION", "LOOP", "FOR", "WHILE", "DO_WHILE")):
        return NT_CONDITION
    if any(token in node_type for token in ("CALL", "SEND", "TRANSFER", "LOW_LEVEL")):
        return NT_CALL
    if any(token in node_type for token in ("ASSIGN", "STATE_WRITE")):
        return NT_ASSIGNMENT
    if node_type == "EXPRESSION":
        if _RE_ASSIGN_LHS.match(expr.strip()):
            return NT_ASSIGNMENT
        if _RE_LOWLEVEL_CALL.search(expr) or _RE_SEND.search(expr) or _RE_TRANSFER.search(expr):
            return NT_CALL
    return NT_OTHER


def _build_cfg_adj_from_hetero_edges(edges: Any) -> dict[str | int, list]:
    """从 *_hetero.json 的 edges 字典中提取 CFG_FLOW 邻接表。"""
    adj_cfg: dict[str | int, list] = {}
    if not isinstance(edges, dict):
        return adj_cfg

    cfg_edges = edges.get("CFG_FLOW") or []
    for edge in cfg_edges:
        if not isinstance(edge, dict):
            continue
        src = edge.get("source") if "source" in edge else edge.get("src")
        dst = edge.get("target") if "target" in edge else edge.get("dst")
        if src is None or dst is None or src == dst:
            continue
        adj_cfg.setdefault(src, []).append(dst)
    return adj_cfg


def _build_rev_adj(adj_cfg: dict[str | int, list]) -> dict[str | int, list]:
    """从正向邻接表构建反向(前驱)邻接表。"""
    rev: dict[str | int, list] = {}
    for src, dsts in adj_cfg.items():
        for dst in dsts:
            rev.setdefault(dst, []).append(src)
    return rev


def _build_callback_nodes_from_edges(edges: Any) -> set:
    """从 *_hetero.json 的 CALLBACK_RISK 边收集 source ∪ target 节点集合。

    大纲 4.1.3 步骤 2:external_callback 辅助信号(+0.5 分)只覆盖
    CALLBACK_RISK 高置信外部调用节点及其实际连接的入口节点。
    """
    callback_nodes: set = set()
    if not isinstance(edges, dict):
        return callback_nodes
    for edge in edges.get("CALLBACK_RISK") or []:
        if not isinstance(edge, dict):
            continue
        src = edge.get("source")
        dst = edge.get("target")
        if src is not None:
            callback_nodes.add(src)
        if dst is not None:
            callback_nodes.add(dst)
    return callback_nodes


def _extract_state_vars_from_source_text(source_text: str) -> set[str]:
    """从 Solidity 源码里回填合约级状态变量名。

    这里采用保守启发式，只收集函数体之前的顶层声明行，适合当前
    数据集里状态变量集中出现在 contract 开头的情况。
    """
    state_vars: set[str] = set()
    if not source_text:
        return state_vars

    contract_body = source_text
    if "{" in source_text:
        contract_body = source_text.split("{", 1)[1]

    head, _, _ = contract_body.partition("function ")
    head = head.partition("modifier ")[0]
    head = head.partition("event ")[0]

    line_patterns = (
        re.compile(r"^\s*(?:mapping\s*\([^;]+\)|(?:uint|int|bool|address|string|bytes(?:\d+)?)\b[\w\s\[\](),]*)\b(?:public|private|internal|external)?\s*(?P<name>[A-Za-z_]\w*)\s*(?:=|;)", re.IGNORECASE),
        re.compile(r"^\s*(?P<name>[A-Za-z_]\w*)\s*=\s*[^;]+;\s*$"),
    )

    for raw_line in head.splitlines():
        line = raw_line.split("//", 1)[0].strip()
        if not line.endswith(";"):
            continue
        if "(" in line and "mapping" not in line.lower():
            continue
        for pattern in line_patterns:
            match = pattern.match(line)
            if match:
                name = match.group("name").strip()
                if name:
                    state_vars.add(name.lower())
                break

    return state_vars


def load_state_vars_from_source(slither_data: dict) -> set[str]:
    """从 *_hetero.json 的 source_path / source_text 回填状态变量。"""
    candidates: list[str] = []
    meta = slither_data.get("meta") if isinstance(slither_data, dict) else None
    if isinstance(meta, dict):
        for key in ("source_text", "source_code", "source"):
            value = meta.get(key)
            if isinstance(value, str) and value.strip():
                candidates.append(value)

        source_path = meta.get("source_path")
        if isinstance(source_path, str) and source_path.strip():
            try:
                source_file = Path(source_path)
                if source_file.exists():
                    candidates.append(source_file.read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                pass

    for text in candidates:
        state_vars = _extract_state_vars_from_source_text(text)
        if state_vars:
            return state_vars
    return set()


# ---------------------------------------------------------------------------
# pragma 版本检测(pre-0.8 合约算术锚点用)
# ---------------------------------------------------------------------------

_PRAGMA_SOLIDITY_RE = re.compile(r"pragma\s+solidity\s*([^;]+);", re.IGNORECASE)
_SOLC_VERSION_TOKEN_RE = re.compile(r"0\.(\d+)(?:\.\d+)?")


def _resolve_source_path(meta: Any, json_path: str | Path | None) -> Path | None:
    """把 hetero meta.source_path 解析成存在的文件路径。

    source_path 相对仓库根;json 文件位于 Heterogeneous graphs/ 下,
    因此按 cwd、json 目录、json 上级目录三个基准依次尝试。
    """
    if not isinstance(meta, dict):
        return None
    source = meta.get("source_path")
    if not isinstance(source, str) or not source.strip():
        return None
    candidates = [Path(source)]
    if json_path is not None:
        json_dir = Path(json_path).resolve().parent
        candidates.append(json_dir / source)
        candidates.append(json_dir.parent / source)
    for candidate in candidates:
        try:
            if candidate.is_file():
                return candidate
        except OSError:
            continue
    return None


def detect_pre_0_8(source_path: Path | None) -> bool:
    """判断合约 pragma 是否允许 pre-0.8 编译器(算术运算无内置溢出检查)。

    - 无 pragma:流水线按手册回退 0.8.x 编译 → 视为 0.8+,返回 False。
    - 约束内出现的最高次版本号 < 8 → 返回 True。
    """
    if source_path is None:
        return False
    try:
        head = source_path.read_text(encoding="utf-8", errors="ignore")[:4096]
    except OSError:
        return False
    match = _PRAGMA_SOLIDITY_RE.search(head)
    if not match:
        return False
    minors = [int(m) for m in _SOLC_VERSION_TOKEN_RE.findall(match.group(1))]
    if not minors:
        return False
    return max(minors) < 8


# ---------------------------------------------------------------------------
# 公共正则(模块级编译,全函数复用)
# ---------------------------------------------------------------------------

# reentrancy / access_control / uncheck_return 共用
_RE_SEND          = re.compile(r"\.send\s*\(", re.IGNORECASE)
_RE_TRANSFER      = re.compile(r"\.transfer\s*\(", re.IGNORECASE)
_RE_LOWLEVEL_CALL = re.compile(
    r"\.call(?:\.value\s*\(|\.gas\s*\(|\s*\(|\{[^}]*\}\s*\()",
    re.IGNORECASE,
)
# call.value(...) / call{..., value: ...} 的数额参数提取与零字面量判断
_RE_CALL_VALUE_ARG   = re.compile(r"\.call\s*\.value\s*\(\s*([^)]*?)\s*\)", re.IGNORECASE)
_RE_CALL_VALUE_BRACE = re.compile(r"\.call\s*\{[^{}]*?\bvalue\s*:\s*([^,}]+)", re.IGNORECASE)
_ZERO_VALUE          = re.compile(
    r"^\s*(?:0|0x0+)\s*(?:(?:wei|szabo|finney|ether)\b)?\s*$", re.IGNORECASE
)
_RE_SELFDESTRUCT  = re.compile(r"\bselfdestruct\s*\(", re.IGNORECASE)
_RE_SUICIDE       = re.compile(r"\bsuicide\s*\(", re.IGNORECASE)
_RE_TX_ORIGIN     = re.compile(r"\btx\.origin\b", re.IGNORECASE)
# 单参数 ETH 转账/发送:beneficiary.transfer(x) / beneficiary.send(x)。
# 括号内出现逗号是 ERC20 代币转账(token.transfer(to, amount)),不算特权资金外流。
_RE_SINGLE_ARG_TRANSFER = re.compile(
    r"(?P<beneficiary>[A-Za-z_]\w*(?:\.\w+)*)\s*\.\s*(?:transfer|send)\s*\((?P<args>[^)]*)\)",
    re.IGNORECASE,
)
_RE_MSG_SENDER    = re.compile(r"\bmsg\.sender\b", re.IGNORECASE)
_RE_OWNER         = re.compile(r"\bowner\b", re.IGNORECASE)
_RE_ROLES         = re.compile(
    r"\b(?:roles?|admin|operator|minter|burner|authorized|whitelist)\b",
    re.IGNORECASE,
)

# arithmetic
_RE_BINARY_OP = re.compile(
    r"Binary\s*\(\s*[+\-*/%]\s*\)",   # SlithIR 明确格式
    re.IGNORECASE,
)
_RE_IR_BINARY_OPS = re.compile(
    r"\b(?:ADD|SUB|MUL|DIV|MOD|EXP)\b",   # SlithIR 指令类别关键词（大纲 4.1.2）
    re.IGNORECASE,
)
# 复合赋值(+ = - = * = / = %=)与自增自减(i++/++i),pre-0.8 下同样可能溢出
_RE_COMPOUND_ARITH = re.compile(r"[+\-*/%]=")
_RE_INCDEC         = re.compile(r"(?:\+\+|--)\s*[A-Za-z_]|\w\s*(?:\+\+|--)")
# 外部调用类 IR 关键词（词边界匹配，避免 MSG.SENDER 之类子串误判）
_RE_IR_EXT_CALL = re.compile(
    r"\b(?:LOW_LEVEL_CALL|SEND|TRANSFER|HIGH_LEVEL_CALL)\b", re.IGNORECASE
)
_RE_ARITH_EXPR = re.compile(
    r"\b\w[\w.\[\]]*\s*(?:\+|-|\*|/|%)\s*\w",  # 高级 IR / expression 中的运算符
)

# time_manipulation
_RE_TIMESTAMP = re.compile(r"\bblock\.timestamp\b|\bnow\b", re.IGNORECASE)

# front_running:提取赋值 LHS(排除比较 ==)
_RE_ASSIGN_LHS = re.compile(
    r"^(?P<lhs>[A-Za-z_][\w.\[\]]*)\s*(?:<<=|>>=|\+=|-=|\*=|/=|%=|&=|\|=|\^=|=(?!=))",
)

# uncheck_return:bool 消费检测
_RE_BOOL_CONSUMED = re.compile(
    r"(?:require|assert|if)\s*\(\s*!?\s*(?:[A-Za-z_]\w*)",
    re.IGNORECASE,
)
_RE_BOOL_ASSIGN_LHS = re.compile(
    r"(?:bool\s+)?\(?\s*(?P<varname>[A-Za-z_]\w*)\s*\)?\s*=",
)
# require/assert/if 内联消费低层调用返回值:require(token.send(...)) / if(!addr.send(...))
_RE_INLINE_CHECKED = re.compile(r"^\s*(?:require|assert|if)\s*\(", re.IGNORECASE)


# ---------------------------------------------------------------------------
# 内部辅助:构造 bool_consumed_nodes 集合
# ---------------------------------------------------------------------------

def _build_bool_consumed_set(nodes: dict) -> set:
    """静态双遍扫描:找出返回值 bool 已被消费的 low-level call 节点 id。

    遍历 1:收集所有 require/assert/if(...varname...) 中出现的变量名。
    遍历 2:send/call 节点的赋值 LHS 若命中上述变量名 → 标记为"已消费"。

    说明:这是单函数内的静态粗筛,不追踪跨节点 def-use;
    跨节点情形由 is_anchor_uncheck_return 的图模式检测补充。
    """
    consumed_varnames: dict[tuple[Any, Any], set[str]] = {}
    for node in nodes.values():
        function_key = (node.get("contract"), node.get("function"))
        function_names = consumed_varnames.setdefault(function_key, set())
        expr = str(node.get("expression") or "")
        # 抓取 require/assert/if 括号内第一个标识符
        inner = re.search(
            r"(?:require|assert|if)\s*\(\s*!?\s*([A-Za-z_]\w*)",
            expr,
            re.IGNORECASE,
        )
        if inner:
            function_names.add(inner.group(1).lower())
            continue
        # Slither 的 IF 节点 expression 只有条件本身(无 if 关键字):
        # 形如 "ok" 或 "!ok" 的裸标识符条件也视为消费了该布尔变量。
        node_type = str(node.get("raw_cfg_node_type")
                        or node.get("cfg_node_type")
                        or node.get("type")
                        or "").upper()
        if node_type == "IF" and re.fullmatch(r"!?\s*[A-Za-z_]\w*", expr.strip()):
            function_names.add(expr.strip().lstrip("!").strip().lower())

    consumed_ids: set = set()
    for nid, node in nodes.items():
        expr = str(node.get("expression") or "")
        if not (_RE_SEND.search(expr) or _RE_LOWLEVEL_CALL.search(expr)):
            continue
        m = _RE_BOOL_ASSIGN_LHS.search(expr)
        function_key = (node.get("contract"), node.get("function"))
        if m and m.group("varname").lower() in consumed_varnames.get(function_key, set()):
            consumed_ids.add(nid)

    return consumed_ids


# ---------------------------------------------------------------------------
# ① reentrancy
# ---------------------------------------------------------------------------

def _is_nonzero_value_arg(arg_text: str) -> bool:
    """数额参数是否非 0 字面量(call.value(0) / call{value: 0} 不会触发重入)。"""
    return not bool(_ZERO_VALUE.match(arg_text or ""))


def _is_reentrancy_capable_call(expr: str, ir: str = "") -> bool:
    """外部调用节点是否具备触发重入的能力。

    触发方式(DAO 范式):合约向外部地址带 ETH 的底层调用,或对其它合约函数的
    高层调用(如 ERC20 token.transfer),被调用方执行期间可重入本合约。
    .send(/.transfer( 只转发 2300 gas,无法有效重入,不算重入锚点;
    call.value(0)/call{value: 0} 无价值转移,也不算。
    """
    for match in _RE_CALL_VALUE_ARG.finditer(expr):
        if _is_nonzero_value_arg(match.group(1)):
            return True
    for match in _RE_CALL_VALUE_BRACE.finditer(expr):
        if _is_nonzero_value_arg(match.group(1)):
            return True
    if re.search(r"\bHIGH_LEVEL_CALL\b", ir):
        return True
    return False


def _lhs_is_state_var(expr: str, ctx: "GraphContext") -> bool:
    """赋值 LHS 是否命中状态变量(供 front_running 与重入状态写入共用)。

    裸标识符赋值(acc = Acc[x])严格按原始大小写匹配(局部变量 acc 不是状态变量 Acc);
    带成员/下标的写入(acc.balance -= x)是写存储,基变量允许大小写不敏感匹配。
    """
    match = _RE_ASSIGN_LHS.match((expr or "").strip())
    if not match:
        return False
    lhs_raw = match.group("lhs")
    lhs_orig = re.split(r"[\[\(.]", lhs_raw)[0]
    lhs_base = lhs_orig.lower()
    has_member = "[" in lhs_raw or "." in lhs_raw
    if ctx.state_vars_case:
        if lhs_orig in ctx.state_vars_case:
            return True
        return has_member and lhs_base in ctx.state_vars
    if ctx.state_vars:
        return lhs_base in ctx.state_vars
    return bool(_RACE_VAR_PATTERNS.search(expr))


def _is_state_var_write(node_id: Any, ctx: "GraphContext") -> bool:
    """节点是否为状态变量写入(重入判定用,不受 RHS 字面量限制)。

    如 credit[msg.sender] = 0 这类"调用后清零"写入也是重入模式的一部分。
    """
    return _lhs_is_state_var(ctx.get_expr(node_id), ctx)


def has_state_write_predecessor(node_id: Any, ctx: "GraphContext", max_depth: int = 10) -> bool:
    """同函数内 CFG 前驱(有限深度)是否存在状态写入节点。"""
    node = ctx.nodes.get(node_id) or {}
    fn_key = (node.get("contract"), node.get("function"))
    for pred_id, _ in ctx.predecessors_bfs(node_id, max_depth=max_depth):
        pred = ctx.nodes.get(pred_id) or {}
        if (pred.get("contract"), pred.get("function")) != fn_key:
            continue
        if _is_state_var_write(pred_id, ctx):
            return True
    return False


def has_state_write_after(node_id: Any, ctx: "GraphContext", max_depth: int = 10) -> bool:
    """同函数内 CFG 后继(有限深度)是否存在状态写入节点。"""
    node = ctx.nodes.get(node_id) or {}
    fn_key = (node.get("contract"), node.get("function"))
    for succ_id, _ in ctx.successors_bfs(node_id, max_depth=max_depth):
        succ = ctx.nodes.get(succ_id) or {}
        if (succ.get("contract"), succ.get("function")) != fn_key:
            continue
        if _is_state_var_write(succ_id, ctx):
            return True
    return False


# 简单内部调用表达式(如 withdrawReward(recipient) / mint(100))
_RE_INTERNAL_CALL_NAME = re.compile(r"^[A-Za-z_]\w*\s*\(")


def _internal_call_name(expr: str) -> str | None:
    """从 expression 提取内部调用的函数名;非简单内部调用返回 None。"""
    match = _RE_INTERNAL_CALL_NAME.match((expr or "").strip())
    if not match:
        return None
    return match.group(0)[:-1].strip()


def _node_is_reentrancy_capable_call(node: dict, ctx: "GraphContext") -> bool:
    """节点(含跨函数情形)是否具备触发重入的能力。

    1. 表达式级:call.value 非 0 / call{value:} 非 0 / ir 含 HIGH_LEVEL_CALL;
    2. 跨函数(SWC-107):内部调用指向"体内含重入能力外部调用"的函数
       (如 getFirstWithdrawalBonus → withdrawReward → recipient.call.value)。
    """
    expr = str(node.get("expression") or "")
    ir = str(node.get("ir") or "")
    if _is_reentrancy_capable_call(expr, ir):
        return True
    called = _internal_call_name(expr)
    contract = node.get("contract")
    if contract is not None and called is not None:
        return (contract, called) in ctx.functions_with_capable_call
    return False


def is_anchor_reentrancy(expr: str, ir: str = "", node_id: Any = None, ctx: "GraphContext | None" = None) -> bool:
    """检测重入漏洞锚点:带值外部调用,且调用时用户余额等状态仍可被利用。

    触发方式(对齐 MVD-HG 标注器):合约向外部地址带 ETH 的底层调用(或高层调用),
    仅当"调用前已写入状态且调用后不再写入"(CEI 顺序正确)时才是安全模式;
    其余情形——调用前无任何写入、调用后才写入(如 credit[msg.sender] = 0)、
    或跨函数(内部调用链)延迟写入——都构成重入风险。
    """
    if not expr and not ir:
        return False
    if ctx is not None and node_id is not None:
        node = ctx.nodes.get(node_id)
        if node is None or not _node_is_reentrancy_capable_call(node, ctx):
            return False
        # 安全条件:调用前已写状态 且 调用后无状态写入(CEI 正确)
        safe = has_state_write_predecessor(node_id, ctx) and not has_state_write_after(node_id, ctx)
        return not safe
    if not _is_reentrancy_capable_call(expr, ir):
        return False
    # 纯正则粗筛模式(ctx=None):无法判断调用前后状态,保守命中
    return True


# ---------------------------------------------------------------------------
# ② arithmetic
# ---------------------------------------------------------------------------

def is_anchor_arithmetic(expr: str, ir: str = "", is_in_unchecked: bool = False, pre_0_8: bool = False) -> bool:
    """检测算术溢出漏洞锚点:无溢出检查的算术运算。

    触发方式:
      - Solidity <0.8 编译器默认不做溢出检查,任何二元/复合/自增自减运算
        都可能溢出(pre_0_8=True 时全量命中);
      - Solidity >=0.8 编译器默认检查,只有 unchecked{} 块内的运算才有风险
        (is_in_unchecked=True 时命中)。

    Parameters
    ----------
    expr : str
        节点 expression 文本。
    ir : str
        节点 SlithIR 文本(M2 补全后由调用方传入)。
    is_in_unchecked : bool
        由调用方通过 ctx.is_unchecked(node_id) 传入。
    pre_0_8 : bool
        由调用方通过 ctx.pre_0_8 传入(从源码 pragma 解析)。
    """
    if not expr and not ir:
        return False
    if not (is_in_unchecked or pre_0_8):
        return False
    return bool(
        _RE_BINARY_OP.search(expr)
        or _RE_IR_BINARY_OPS.search(ir)
        or _RE_ARITH_EXPR.search(expr)
        or _RE_COMPOUND_ARITH.search(expr)
        or _RE_INCDEC.search(expr)
    )


# ---------------------------------------------------------------------------
# ③ access_control
# ---------------------------------------------------------------------------

def is_anchor_access_control(
    expr: str,
    node_id: Any = None,
    ctx: "GraphContext | None" = None,
) -> bool:
    """检测访问控制漏洞锚点:未经鉴权的特权操作。

    触发方式:
      - 用 tx.origin 做权限判断(可被钓鱼绕过,SmartBugs tx-origin 模式);
      - selfdestruct/suicide 销毁合约;
      - 向非 msg.sender 的接收方单参数 transfer/send(特权资金外流;
        给调用方退款 msg.sender.transfer(...) 是正常行为,不算)。
    说明:node_id/ctx 为兼容旧调用签名保留,当前规则不使用函数级上下文。
    """
    if not expr:
        return False
    if _RE_TX_ORIGIN.search(expr):
        return True
    if _RE_SELFDESTRUCT.search(expr) or _RE_SUICIDE.search(expr):
        return True
    for match in _RE_SINGLE_ARG_TRANSFER.finditer(expr):
        if "," in match.group("args"):
            continue  # 多参数是 ERC20 代币转账(token.transfer(to, amount))
        beneficiary = match.group("beneficiary").lower()
        if not beneficiary.endswith("msg.sender"):
            return True
    return False


# ---------------------------------------------------------------------------
# ④ uncheck_return
# ---------------------------------------------------------------------------

def is_anchor_uncheck_return(
    expr: str,
    node_id: Any = None,
    ctx: "GraphContext | None" = None,
) -> bool:
    """检测未检查返回值漏洞锚点:send/call 返回值未被消费。

    触发方式:低层调用 .send()/.call() 返回 bool,失败不会回滚;若返回值
    未被 require/assert/if 消费,调用方会误以为转账成功。

    检测模式(按优先级):
    1. 内联消费:调用直接嵌在 require/assert/if(...) 条件里 → 已检查。
    2. 图模式(ctx 非 None):
       - 节点是 IF 节点(调用结果作为分支条件)→ 已检查;
       - 否则查 node_id 是否在预计算的 bool_consumed_nodes 集合中。
    3. 纯正则模式(ctx=None):expression 自身未内联布尔消费。

    典型命中(未检查):
      - "addr.call.value(x)()"          (无后续 require(success))
      - "token.send(amount)"             (忽略了返回值)
    非命中(已检查):
      - "bool ok = addr.call(data); require(ok);"
      - "require(token.send(msg.sender, amount))"
      - "if (addr.call.value(x)()) {...}"
    """
    if not expr:
        return False
    if not (_RE_SEND.search(expr) or _RE_LOWLEVEL_CALL.search(expr)):
        return False

    # 内联消费:require/assert/if(...) 直接包住调用
    if _RE_INLINE_CHECKED.match(expr):
        return False

    if ctx is not None and node_id is not None:
        # IF 节点:低层调用作为分支条件,返回值已被消费
        node = ctx.nodes.get(node_id) or {}
        raw_type = str(node.get("raw_cfg_node_type")
                       or node.get("cfg_node_type")
                       or node.get("type")
                       or "").upper()
        if raw_type == "IF":
            return False
        # 图模式:不在已消费集合 → 命中(未检查)
        return node_id not in ctx.bool_consumed_nodes

    # 纯正则模式:expression 本身未内联布尔消费
    return not bool(_RE_BOOL_CONSUMED.search(expr))


# ---------------------------------------------------------------------------
# ⑤ dos(CFG 反向 BFS,深度 ≤ 10)
# ---------------------------------------------------------------------------

# 循环/条件节点类型关键词（按原始 Slither 枚举名判断：含 LOOP 或旧格式 WHILE/FOR/DO_WHILE；
# 普通 IF 不是循环，不能算入）
_LOOP_NODE_TYPES: frozenset[str] = frozenset(
    {"LOOP", "WHILE", "FOR", "DO_WHILE"}
)
# 循环"条件"节点类型（dos 锚点 1 专用）：图中 Slither 0.11.5 枚举名为 IFLOOP
# （无下划线），旧格式为 IF_LOOP/WHILE/FOR/DO_WHILE；
# STARTLOOP/ENDLOOP（init/step，如 i=0、i++）不是比较式，
# 若也按"非常量界"判会把每个 for 循环的 init/step 误打成无界循环（2026-09-05 修复；
# 注意不要写成仅含下划线版 IF_LOOP，否则 IFLOOP 节点一个都匹配不到）。
_LOOP_CONDITION_NODE_TYPES: frozenset[str] = frozenset(
    {"IFLOOP", "IF_LOOP", "WHILE", "FOR", "DO_WHILE"}
)
# call 类节点类型关键词
_CALL_NODE_TYPES: frozenset[str] = frozenset(
    {"CALL", "EXTERNAL_CALL", "LOW_LEVEL_CALL"}
)


def _is_call_like(node_type: str, expr: str, ir: str = "") -> bool:
    """辅助:节点是否为外部 call(类型/expression/ir 任一命中)。"""
    return (
        any(kw in node_type for kw in _CALL_NODE_TYPES)
        or bool(_RE_LOWLEVEL_CALL.search(expr))
        or bool(_RE_SEND.search(expr))
        or bool(_RE_TRANSFER.search(expr))
        or bool(_RE_IR_EXT_CALL.search(ir))
    )


def _is_loop_like(node_type: str) -> bool:
    """辅助:节点是否为循环控制节点(BEGIN_LOOP/IFLOOP/END_LOOP/WHILE 等)。

    只按原始节点类型判断:含 LOOP,或旧格式 WHILE/FOR/DO_WHILE;
    普通 IF 不命中(否则条件语句会被误判为循环)。
    """
    return any(kw in (node_type or "").upper() for kw in _LOOP_NODE_TYPES)


def _is_loop_condition_like(node_type: str) -> bool:
    """辅助:节点是否为循环条件节点(IFLOOP/IF_LOOP 或旧格式 WHILE/FOR/DO_WHILE)。

    仅供 dos 锚点 1(无界循环)使用:只有条件节点才有"条件是否常量界"的概念;
    图中的 STARTLOOP/ENDLOOP(init/step)不是循环条件(2026-09-05 修复)。
    """
    return any(kw in (node_type or "").upper() for kw in _LOOP_CONDITION_NODE_TYPES)


# 循环条件为常量界的纯比较(i < 32 / i <= 350):界固定,不算无界循环
_RE_CONSTANT_BOUND_COND = re.compile(
    r"^\s*[A-Za-z_]\w*\s*(?:<=|>=|==|!=|<|>)\s*(?:0x[0-9a-fA-F]+|\d+)(?:\s*(?:wei|szabo|finney|ether))?\s*$",
    re.IGNORECASE,
)
# 状态数组 push:listAddresses.push(...) → 数组无界增长(gas DoS)
_RE_PUSH_ASSIGN = re.compile(r"^(?P<base>[A-Za-z_]\w*)\s*\.\s*push\s*\(")
# 动态数组 length 自增:array.length += 1 / array.length++ / array.length = array.length + 1
# （数组无界增长 → gas DoS；2026-09-05 补 dos_number 模式，旧版只认 .push()）
_RE_LENGTH_INCR = re.compile(
    r"^(?P<base>[A-Za-z_]\w*)\s*\.\s*length\s*(?:\+\+|\+=\s*\d+|=\s*(?P=base)\s*\.\s*length\s*\+\s*\d+)\s*;?\s*$",
    re.IGNORECASE,
)
# 单参数 send:beneficiary.send(x)。退款/付款给第三方合约可能意外 revert → DoS
_RE_SINGLE_ARG_SEND = re.compile(
    r"(?P<beneficiary>[A-Za-z_]\w*(?:\.\w+)*)\s*\.\s*send\s*\((?P<args>[^)]*)\)",
    re.IGNORECASE,
)


def is_anchor_dos(
    node_id: Any,
    ctx: GraphContext,
) -> bool:
    """检测 DoS 漏洞锚点(四类触发方式)。

    1. 无界循环(gas DoS):循环条件节点(类型含 LOOP)的条件不是常量界
       (如 i<numbers、i<_tos.length、while(true)),随数据/参数增长耗尽 gas。
    2. 循环内对状态数组的无界增长(push 追加或 length 自增,如
       listAddresses.push(msg.sender)、array.length += 1)。
    3. 向非 msg.sender 接收方的 send(意外 revert / 退款 DoS)。
    4. 循环体内的外部调用:调用可被外部合约 revert 导致意外回滚,
       或循环内多次调用放大 gas 消耗。
    """
    if not ctx.nodes:
        return False

    cur_type = ctx.get_node_type(node_id)   # 已 .upper()
    expr     = ctx.get_expr(node_id)
    ir       = ctx.get_ir(node_id)
    raw_type = str((ctx.nodes.get(node_id) or {}).get("raw_cfg_node_type")
                   or (ctx.nodes.get(node_id) or {}).get("cfg_node_type")
                   or "")

    # 锚点 1:循环条件非常量界(无界循环)。
    # 只对循环条件节点判定（IFLOOP）：图中 STARTLOOP（init，如 i = 0）与
    # ENDLOOP（step，如 i++）的 expression 不是比较式，旧实现会把每个
    # for 循环的 init/step 误打成无界循环（2026-09-05 修复）。
    if _is_loop_condition_like(raw_type) and expr:
        if not _RE_CONSTANT_BOUND_COND.match(expr.strip()):
            return True

    # 锚点 2:循环内对状态数组的无界增长
    #   (a) listAddresses.push(msg.sender)                （push 追加）
    #   (b) array.length += 1 / array.length++ / array.length = array.length + 1
    #       （动态数组 length 自增，2026-09-05 补 dos_number 模式，旧版只认 push）
    grow_base = ""
    if expr:
        push_match = _RE_PUSH_ASSIGN.match(expr.strip())
        if push_match:
            grow_base = push_match.group("base")
        else:
            len_match = _RE_LENGTH_INCR.match(expr.strip())
            if len_match:
                grow_base = len_match.group("base")
    grow_is_state = (
        grow_base in ctx.state_vars_case
        if ctx.state_vars_case
        else grow_base.lower() in ctx.state_vars
    )
    if grow_base and grow_is_state:
        for anc_id, _ in ctx.predecessors_bfs(node_id, max_depth=10):
            anc = ctx.nodes.get(anc_id) or {}
            anc_type = str(anc.get("raw_cfg_node_type")
                           or anc.get("cfg_node_type")
                           or anc.get("type")
                           or "")
            if _is_loop_like(anc_type):
                return True

    # 锚点 3:向非 msg.sender 的 send(意外 revert / 退款 DoS)
    for match in _RE_SINGLE_ARG_SEND.finditer(expr or ""):
        if "," in match.group("args"):
            continue  # 多参数不是 ETH 单笔转账
        beneficiary = match.group("beneficiary").lower()
        if not beneficiary.endswith("msg.sender"):
            return True

    # 锚点 4:循环体内的外部调用
    if not _is_call_like(cur_type, expr, ir):
        return False

    for anc_id, _ in ctx.predecessors_bfs(node_id, max_depth=10):
        anc = ctx.nodes.get(anc_id) or {}
        anc_type = str(anc.get("raw_cfg_node_type")
                       or anc.get("cfg_node_type")
                       or anc.get("type")
                       or "")
        if _is_loop_like(anc_type):
            return True

    return False


# ---------------------------------------------------------------------------
# ⑥ front_running(状态变量白名单 + 节点类型过滤)
# ---------------------------------------------------------------------------

# 竞态变量正则兜底(白名单为空时使用)
_RACE_VAR_PATTERNS = re.compile(
    r"\b(?:price|balance|amount|bid|offer|deadline|nonce|pending"
    r"|lastPrice|currentPrice|winner|highestBid|highestBidder"
    r"|reward|bonus|fee|rate|allowance)\b",
    re.IGNORECASE,
)
# 纯字面量 RHS(数字/hex/带单位金额/字符串/address(0)):常量写入不受交易顺序影响
# （2026-09-05 补 address(0)：owner = address(0) 与 owner = 100 同属常量写入，
#   不构成 TOD；旧版会把它当竞态写入误报）
_RE_PURE_LITERAL = re.compile(
    r"^\s*(?:-?\d+(?:\.\d+)?(?:\s*(?:wei|szabo|finney|ether))?|0x[0-9a-fA-F]+|\"[^\"]*\"|'[^']*'|address\(\s*0\s*\))\s*$",
    re.IGNORECASE,
)

# ASSIGNMENT / STATE_WRITE 节点类型集合
_WRITE_NODE_TYPES: frozenset[str] = frozenset(
    {"ASSIGNMENT", "STATE_WRITE"}
)


def is_anchor_front_running(
    node_id: Any,
    ctx: GraphContext,
) -> bool:
    """检测前跑漏洞锚点:竞态状态变量赋值节点。

    大纲 §4.1.2:状态写入节点(竞态变量赋值)→ 竞态状态变量、用户提交参数。

    判定流程:
      1. 节点 cfg_node_type 必须为 ASSIGNMENT 或 STATE_WRITE。
         若 M2 未保留 cfg_node_type(返回 OTHER),此步跳过,降级为纯正则。
      2. 从 expression 中解析赋值 LHS 的基变量名(剥离 mapping/array 下标)。
      3. 排除纯时间戳赋值:若 RHS 为 now / block.timestamp,则归属
         time_manipulation 而非 front_running,避免重叠误报。
      4. 优先使用 ctx.state_vars 白名单精确命中;
         白名单为空时降级为 _RACE_VAR_PATTERNS 正则兜底。
    """
    if not ctx.nodes:
        return False

    node_type = ctx.get_node_type(node_id)   # 已 .upper()
    expr      = ctx.get_expr(node_id)

    if not expr:
        return False

    # 步骤 1:类型过滤
    if node_type != NT_OTHER and node_type not in _WRITE_NODE_TYPES:
        return False

    # 步骤 2:解析 LHS 基变量名
    m = _RE_ASSIGN_LHS.match(expr.strip())
    if not m:
        return False

    # 步骤 3:排除纯时间戳赋值(= now / = block.timestamp)
    # 这类节点归 time_manipulation,不归 front_running
    rhs = expr[m.end():].strip()
    if _RE_TIMESTAMP.search(rhs):
        return False
    if re.fullmatch(r"(?:true|false)", rhs, re.IGNORECASE):
        return False
    # 步骤 3b:纯字面量赋值(如 price = 100)不构成交易顺序依赖
    if _RE_PURE_LITERAL.match(rhs):
        return False

    # 步骤 4:命中判断(状态变量匹配规则见 _lhs_is_state_var)
    return _lhs_is_state_var(expr, ctx)


# ---------------------------------------------------------------------------
# ⑦ time_manipulation
# ---------------------------------------------------------------------------

def is_anchor_time_manipulation(expr: str) -> bool:
    """检测时间操控漏洞锚点:block.timestamp / now 读取。

    大纲 §4.1.2:block.timestamp 读取 → 依赖时间的条件判断、锁时间变量。
    大纲参考 JSON 节点 3 示例:"LastMsg.Time = now"。
    """
    if not expr:
        return False
    return bool(_RE_TIMESTAMP.search(expr))


def is_state_write_after_external_call(node_id: Any, ctx: GraphContext) -> bool:
    """重入锚点补充:外部调用(或指向含重入能力调用函数的内部调用)之后
    同一函数内仍有状态写入的节点。

    节点自身是状态变量写入(不受 RHS 字面量限制,如 credit[msg.sender] = 0),
    且其 CFG 祖先(同函数内、深度 ≤ 10)存在具备重入能力的调用节点
    (见 _node_is_reentrancy_capable_call)。
    """
    if not _is_state_var_write(node_id, ctx):
        return False
    node = ctx.nodes.get(node_id) or {}
    fn_key = (node.get("contract"), node.get("function"))
    for anc_id, _ in ctx.predecessors_bfs(node_id, max_depth=10):
        anc = ctx.nodes.get(anc_id) or {}
        if (anc.get("contract"), anc.get("function")) != fn_key:
            continue
        if _node_is_reentrancy_capable_call(anc, ctx):
            return True
    return False


# ---------------------------------------------------------------------------
# 辅助:加载状态变量白名单
# ---------------------------------------------------------------------------

def load_state_vars_from_slither_json(slither_data: dict) -> set[str]:
    """从 Slither JSON 元数据提取合约级状态变量名(统一小写)。

    兼容四种格式:
    0. meta.state_vars 列表(*_hetero.json M2 补全后,优先)
    1. 顶层 state_variables 列表
    2. contracts[i].state_variables 列表
    3. fallback:从 cfg_nodes 的 state_variables_written 字段推断
    """
    state_vars: set[str] = set()

    def _harvest(lst: list) -> None:
        """从候选列表提取状态变量名（统一小写）加入 state_vars。"""
        for sv in lst:
            if isinstance(sv, dict):
                name = sv.get("name") or sv.get("variable_name") or ""
            else:
                name = str(sv)
            name = name.strip()
            if name:
                state_vars.add(name.lower())

    # 格式 0
    meta = slither_data.get("meta") if isinstance(slither_data, dict) else None
    if isinstance(meta, dict):
        meta_sv = meta.get("state_vars")
        if isinstance(meta_sv, (list, tuple, set)):
            _harvest(list(meta_sv))
            if state_vars:
                return state_vars

    # 格式 1
    if "state_variables" in slither_data:
        _harvest(slither_data["state_variables"])
        return state_vars

    # 格式 2
    for contract in slither_data.get("contracts", []):
        _harvest(contract.get("state_variables", []))

    # 格式 3(fallback)
    if not state_vars:
        nodes_list = (
            slither_data.get("cfg_nodes")
            or slither_data.get("nodes")
            or []
        )
        for node in nodes_list:
            for sv in node.get("state_variables_written", []):
                name = sv if isinstance(sv, str) else sv.get("name", "")
                name = name.strip()
                if name:
                    state_vars.add(name.lower())

    return state_vars


def load_state_vars_case_from_slither_json(slither_data: dict) -> set[str]:
    """同 load_state_vars_from_slither_json,但保留原始大小写。

    用于区分状态变量 Acc 与局部变量 acc(大小写敏感匹配)。
    """
    state_vars: set[str] = set()

    def _harvest(lst: list) -> None:
        """从候选列表提取状态变量名（保留原始大小写）加入 state_vars。"""
        for sv in lst:
            if isinstance(sv, dict):
                name = sv.get("name") or sv.get("variable_name") or ""
            else:
                name = str(sv)
            name = name.strip()
            if name:
                state_vars.add(name)

    meta = slither_data.get("meta") if isinstance(slither_data, dict) else None
    if isinstance(meta, dict):
        meta_sv = meta.get("state_vars")
        if isinstance(meta_sv, (list, tuple, set)):
            _harvest(list(meta_sv))
            if state_vars:
                return state_vars

    if "state_variables" in slither_data:
        _harvest(slither_data["state_variables"])
        return state_vars

    for contract in slither_data.get("contracts", []):
        _harvest(contract.get("state_variables", []))

    if not state_vars:
        nodes_list = (
            slither_data.get("cfg_nodes")
            or slither_data.get("nodes")
            or []
        )
        for node in nodes_list:
            for sv in node.get("state_variables_written", []):
                name = sv if isinstance(sv, str) else sv.get("name", "")
                name = name.strip()
                if name:
                    state_vars.add(name)

    return state_vars


# ---------------------------------------------------------------------------
# 统一入口
# ---------------------------------------------------------------------------

#: 七类漏洞标签(顺序与大纲 §4.1.2 保持一致)
VULN_CLASSES: tuple[str, ...] = (
    "reentrancy",
    "arithmetic",
    "access_control",
    "uncheck_return",
    "dos",
    "front_running",
    "time_manipulation",
)


def compute_anchor_flags(
    node_id: Any,
    ctx: GraphContext,
) -> dict[str, bool]:
    """计算单节点七类漏洞锚点布尔标志。

    Parameters
    ----------
    node_id : Any
        节点 id,类型与 ctx.nodes 中的 key 一致。
    ctx : GraphContext
        已构造的图上下文。

    Returns
    -------
    dict[str, bool]
        key = 漏洞类名(见 VULN_CLASSES),value = 是否命中锚点。
    """
    expr      = ctx.get_expr(node_id)
    ir        = ctx.get_ir(node_id)
    unchecked = ctx.is_unchecked(node_id)

    return {
        "reentrancy":        is_anchor_reentrancy(expr, ir, node_id=node_id, ctx=ctx)
                             or is_state_write_after_external_call(node_id, ctx),
        "arithmetic":        is_anchor_arithmetic(expr, ir=ir, is_in_unchecked=unchecked,
                                                  pre_0_8=ctx.pre_0_8),
        "access_control":    is_anchor_access_control(expr, node_id=node_id, ctx=ctx),
        "uncheck_return":    is_anchor_uncheck_return(expr, node_id=node_id, ctx=ctx),
        "dos":               is_anchor_dos(node_id, ctx),
        "front_running":     is_anchor_front_running(node_id, ctx),
        "time_manipulation": is_anchor_time_manipulation(expr),
    }


def compute_anchor_score(
    node_id: Any,
    ctx: GraphContext,
) -> float:
    """计算节点原始先验分数(raw,未归一化)。

    大纲 §4.1.3 打分算法:
      1. 命中一类记 +1;external_callback 命中记 +0.5;
      2. 同一节点多类命中则累加;
      3. 全图 min-max 归一化由 m1_runner 层完成(全 0 时保持 0);
      4. 无 DFG 反向一跳传播、无其他后处理。
    """
    flags = compute_anchor_flags(node_id, ctx)
    raw = float(sum(1 for value in flags.values() if value))
    if node_id in ctx.external_callback_nodes:
        raw += 0.5
    return raw


def detect_all_anchors(ctx: GraphContext) -> dict[Any, dict[str, bool]]:
    """对 ctx 中所有节点批量检测锚点,返回 {node_id: flags_dict}。"""
    return {nid: compute_anchor_flags(nid, ctx) for nid in ctx.nodes}


# ---------------------------------------------------------------------------
# 互斥仲裁层
# ---------------------------------------------------------------------------

# 互斥输出的优先级:越靠前越优先保留。
# 规则原则:
#   1) 先保留时序/状态写入类的更具体命中;
#   2) 再保留外部调用类命中;
#   3) 最后保留图结构类命中。
EXCLUSIVE_RULE_PRIORITY: tuple[str, ...] = (
    "time_manipulation",
    "arithmetic",
    "front_running",
    "reentrancy",
    "access_control",
    "uncheck_return",
    "dos",
)


def resolve_anchor_label(flags: dict[str, bool]) -> str | None:
    """把七类布尔命中仲裁成单一标签。

    说明:
    - 保留原始 compute_anchor_flags 作为多标签诊断结果。
    - 下游训练/统计若要求互斥标签,使用本函数的结果。
    """
    for label in EXCLUSIVE_RULE_PRIORITY:
        if flags.get(label):
            return label
    return None


def compute_anchor_flags_exclusive(
    node_id: Any,
    ctx: GraphContext,
) -> dict[str, bool]:
    """生成单标签互斥版 flags:每个节点最多保留一个 True。"""
    raw_flags = compute_anchor_flags(node_id, ctx)
    winner = resolve_anchor_label(raw_flags)
    if winner is None:
        return {name: False for name in VULN_CLASSES}
    return {name: (name == winner) for name in VULN_CLASSES}


def detect_all_anchors_exclusive(ctx: GraphContext) -> dict[Any, dict[str, bool]]:
    """批量生成互斥版锚点标注。"""
    return {nid: compute_anchor_flags_exclusive(nid, ctx) for nid in ctx.nodes}
