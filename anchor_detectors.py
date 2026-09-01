"""
anchor_detectors.py  —  M1 漏洞语义引导锚点检测
=================================================
对大纲 §4.1.2 七类漏洞实现锚点布尔判定函数,并在此基础上提供:
  - compute_anchor_flags(node_id, ctx)  → dict[str, bool]
  - compute_anchor_score(node_id, ctx)  → float  (用于后续 BFS 衰减)
  - GraphContext                         数据类,封装 Slither JSON 解析结果

依赖:Python ≥ 3.9,无第三方包(纯标准库 + 数据类)
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
    state_vars: set[str] = field(default_factory=set)
    bool_consumed_nodes: set[str | int] = field(default_factory=set)

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

        # ---- 4. 状态变量白名单 -----------------------------------------
        ctx.state_vars = load_state_vars_from_slither_json(slither_data)

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
        ctx.state_vars = load_state_vars_from_slither_json(hetero_data)
        if not ctx.state_vars:
            ctx.state_vars = load_state_vars_from_source(hetero_data)
        ctx.bool_consumed_nodes = _build_bool_consumed_set(ctx.nodes)
        return ctx

    @classmethod
    def from_any_json(cls, data: dict) -> "GraphContext":
        """自动识别并解析旧 Slither JSON 或当前 *_hetero.json。"""
        if isinstance(data.get("edges"), dict) and "nodes" in data:
            return cls.from_hetero_json(data)
        return cls.from_slither_json(data)

    @classmethod
    def from_json_file(cls, path: str | Path) -> "GraphContext":
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return cls.from_any_json(data)

    # ------------------------------------------------------------------
    # 查询辅助
    # ------------------------------------------------------------------

    def get_expr(self, node_id: Any) -> str:
        """返回节点 expression 字符串,缺失时返回空串(空安全)。"""
        node = self.nodes.get(node_id, {})
        return str(node.get("expression") or node.get("expr") or "")

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


def _normalize_hetero_node(node: dict) -> dict:
    """把 *_hetero.json 节点扁平化成 M1 规则可消费的格式。"""
    attributes = node.get("attributes") or {}
    raw_type = node.get("cfg_node_type") or node.get("type") or attributes.get("type")
    expression = _extract_node_expression(node, attributes)
    normalized = dict(node)
    normalized["cfg_node_type"] = _normalize_cfg_node_type(raw_type, expression)
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
# 公共正则(模块级编译,全函数复用)
# ---------------------------------------------------------------------------

# reentrancy / access_control / uncheck_return 共用
_RE_SEND          = re.compile(r"\.send\s*\(", re.IGNORECASE)
_RE_TRANSFER      = re.compile(r"\.transfer\s*\(", re.IGNORECASE)
_RE_LOWLEVEL_CALL = re.compile(
    r"\.call(?:\.value\s*\(|\.gas\s*\(|\s*\(|\{[^}]*\}\s*\()",
    re.IGNORECASE,
)
_RE_SELFDESTRUCT  = re.compile(r"\bselfdestruct\s*\(", re.IGNORECASE)
_RE_MSG_SENDER    = re.compile(r"\bmsg\.sender\b", re.IGNORECASE)
_RE_OWNER         = re.compile(r"\bowner\b", re.IGNORECASE)
_RE_ROLES         = re.compile(
    r"\b(?:roles?|admin|operator|minter|burner|authorized|whitelist)\b",
    re.IGNORECASE,
)

# arithmetic
_RE_BINARY_OP = re.compile(
    r"Binary\s*\(\s*[+\-*/]\s*\)",   # SlithIR 明确格式
    re.IGNORECASE,
)
_RE_ARITH_EXPR = re.compile(
    r"\b\w[\w.\[\]]*\s*(?:\+|-|\*|/)\s*\w",  # 高级 IR / expression 中的运算符
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
    consumed_varnames: set[str] = set()
    for node in nodes.values():
        expr = str(node.get("expression") or "")
        # 抓取 require/assert/if 括号内第一个标识符
        inner = re.search(
            r"(?:require|assert|if)\s*\(\s*!?\s*([A-Za-z_]\w*)",
            expr,
            re.IGNORECASE,
        )
        if inner:
            consumed_varnames.add(inner.group(1).lower())

    consumed_ids: set = set()
    for nid, node in nodes.items():
        expr = str(node.get("expression") or "")
        if not (_RE_SEND.search(expr) or _RE_LOWLEVEL_CALL.search(expr)):
            continue
        m = _RE_BOOL_ASSIGN_LHS.search(expr)
        if m and m.group("varname").lower() in consumed_varnames:
            consumed_ids.add(nid)

    return consumed_ids


# ---------------------------------------------------------------------------
# ① reentrancy
# ---------------------------------------------------------------------------

def is_anchor_reentrancy(expr: str) -> bool:
    """检测重入漏洞锚点:以 ETH 转账为核心的外部调用。

    大纲 §4.1.2:LowLevelCall / Send / Transfer → ETH 数额变量、
    余额映射、接收方地址。

    精化规则(避免普通 ERC-20 transfer 误报):
      1. 低级 call(含 .call.value / .call{value:} 形式)→ 无条件命中;
         这是最典型的重入向量。
      2. .send( 或 .transfer( 需额外满足其中一个条件:
           a. 接收方含 msg.sender(向调用者回款,高风险)
           b. 接收方含 address(this) 或 payable(显式以太转账语义)
         否则不命中,避免将 ERC-20 token transfer 误判为重入锚点。

    典型命中:
      - "msg.sender.call.value(_am)()"       (大纲参考节点 9)
      - "addr.call{value: x}(data)"
      - "msg.sender.transfer(balance)"       (向调用者转 ETH)
      - "payable(owner).send(amount)"
    不命中:
      - "arr[i].transfer(amount)"            (ERC-20,无 msg.sender/payable)
      - "token.send(amount)"                 (ERC-20,非 ETH 发送)
    """
    if not expr:
        return False

    # 规则 1:低级 call 无条件命中
    if _RE_LOWLEVEL_CALL.search(expr):
        return True

    # 规则 2:send / transfer 需满足 ETH 语义线索
    if _RE_SEND.search(expr) or _RE_TRANSFER.search(expr):
        has_eth_receiver = bool(
            _RE_MSG_SENDER.search(expr)                          # 向调用者
            or re.search(r"\bpayable\s*\(", expr, re.IGNORECASE)  # 显式 payable
            or re.search(r"\baddress\s*\(\s*this\s*\)", expr, re.IGNORECASE)
        )
        return has_eth_receiver

    return False


# ---------------------------------------------------------------------------
# ② arithmetic
# ---------------------------------------------------------------------------

def is_anchor_arithmetic(expr: str, is_in_unchecked: bool = False) -> bool:
    """检测算术溢出漏洞锚点:unchecked{} 块内的 Binary(+,-,*,/)。

    大纲 §4.1.2:Solidity 0.8+ 默认有溢出检查;只有在 unchecked{}
    块内的运算才真正存在溢出风险,因此以此为强判据。

    检测逻辑:
      - SlithIR 明确格式 "Binary(+)" 等 → 无论 unchecked 均为候选
        (SlithIR 层面已经是中间表示,保守处理)
      - 高级 expression 字符串含算术操作符 → 仅在 is_in_unchecked=True
        时命中,避免对普通 0.8+ 安全运算的大量误报

    Parameters
    ----------
    expr : str
    is_in_unchecked : bool
        由调用方通过 ctx.is_unchecked(node_id) 传入。
    """
    if not expr:
        return False
    if _RE_BINARY_OP.search(expr):
        return True
    if is_in_unchecked and _RE_ARITH_EXPR.search(expr):
        return True
    return False


# ---------------------------------------------------------------------------
# ③ access_control
# ---------------------------------------------------------------------------

def is_anchor_access_control(expr: str) -> bool:
    """检测访问控制漏洞锚点:危险操作 AND 权限变量共现。

    大纲 §4.1.2:Transfer / selfdestruct 附近出现 msg.sender / owner。
    策略:同一 expression 中必须同时包含:
      - 危险操作:selfdestruct / .transfer( / low-level call
      - 权限标识:msg.sender / owner / admin / roles 等

    单独出现任一侧均不命中,要求共现以降低误报。

    典型命中:
      - "selfdestruct(owner)"
      - "msg.sender.transfer(balance)"
      - "if (msg.sender == owner) selfdestruct(addr)"
    """
    if not expr:
        return False
    has_danger = bool(
        _RE_SELFDESTRUCT.search(expr)
        or _RE_TRANSFER.search(expr)
        or _RE_LOWLEVEL_CALL.search(expr)
    )
    has_auth = bool(
        _RE_MSG_SENDER.search(expr)
        or _RE_OWNER.search(expr)
        or _RE_ROLES.search(expr)
    )
    return has_danger and has_auth


# ---------------------------------------------------------------------------
# ④ uncheck_return
# ---------------------------------------------------------------------------

def is_anchor_uncheck_return(
    expr: str,
    node_id: Any = None,
    ctx: "GraphContext | None" = None,
) -> bool:
    """检测未检查返回值漏洞锚点:send/call 返回值未被消费。

    大纲 §4.1.2:Send / LowLevelCall → 返回值 bool 变量是否被消费。

    检测模式(按优先级):
    1. **图模式**(推荐,ctx 非 None):
       检查 node_id 是否不在预计算的 bool_consumed_nodes 集合中。
       该集合在 GraphContext 构造时通过双遍扫描建立。
    2. **纯正则模式**(ctx=None,快速粗筛):
       expression 自身不含 require/assert/if 对布尔消费的迹象。

    典型命中(未检查):
      - "addr.call.value(x)()"          (无后续 require(success))
      - "token.send(amount)"             (忽略了返回值)
    非命中(已检查):
      - "bool ok = addr.call(data); require(ok);"
    """
    if not expr:
        return False
    if not (_RE_SEND.search(expr) or _RE_LOWLEVEL_CALL.search(expr)):
        return False

    if ctx is not None and node_id is not None:
        # 图模式:不在已消费集合 → 命中(未检查)
        return node_id not in ctx.bool_consumed_nodes

    # 纯正则模式:expression 本身未内联布尔消费
    return not bool(_RE_BOOL_CONSUMED.search(expr))


# ---------------------------------------------------------------------------
# ⑤ dos(CFG BFS,深度 ≤ 2)
# ---------------------------------------------------------------------------

# 循环/条件节点类型关键词
_LOOP_NODE_TYPES: frozenset[str] = frozenset(
    {"CONDITION", "IF", "LOOP", "FOR", "WHILE", "DO_WHILE"}
)
# call 类节点类型关键词
_CALL_NODE_TYPES: frozenset[str] = frozenset(
    {"CALL", "EXTERNAL_CALL", "LOW_LEVEL_CALL"}
)


def _is_call_like(node_type: str, expr: str) -> bool:
    """辅助:节点是否为外部 call(类型或 expression 任一命中)。"""
    return (
        any(kw in node_type for kw in _CALL_NODE_TYPES)
        or bool(_RE_LOWLEVEL_CALL.search(expr))
        or bool(_RE_SEND.search(expr))
        or bool(_RE_TRANSFER.search(expr))
    )


def _is_loop_like(node_type: str) -> bool:
    """辅助:节点是否为循环/条件控制节点。"""
    return any(kw in node_type for kw in _LOOP_NODE_TYPES)


def is_anchor_dos(
    node_id: Any,
    ctx: GraphContext,
) -> bool:
    """检测 DoS 漏洞锚点:循环体内含外部 call。

    大纲 §4.1.2:循环体内 External Call → 循环变量、数组长度。
    策略(CFG_FLOW 图 BFS,深度 ≤ 2):

    方向 A —— 当前节点是 CONDITION/LOOP:
        BFS 后继链中出现 CALL 类节点 → 命中。
        ("循环入口后续有 external call",最典型场景)

    方向 B —— 当前节点是 CALL:
        BFS 后继链中出现 LOOP/CONDITION 类节点 → 命中。
        ("call 后跳回循环控制节点",表明仍在循环体内)

    两个方向均可命中,任一返回 True 即为锚点。
    """
    if not ctx.nodes:
        return False

    cur_type = ctx.get_node_type(node_id)   # 已 .upper()
    expr     = ctx.get_expr(node_id)

    is_cur_call = _is_call_like(cur_type, expr)
    is_cur_loop = _is_loop_like(cur_type)

    if not (is_cur_call or is_cur_loop):
        return False

    # 方向 A:循环节点 → 后继含 call
    if is_cur_loop:
        for succ_id, _ in ctx.successors_bfs(node_id, max_depth=BFS_MAX_DEPTH):
            succ_type = ctx.get_node_type(succ_id)
            succ_expr = ctx.get_expr(succ_id)
            if _is_call_like(succ_type, succ_expr):
                return True

    # 方向 B:call 节点 → 后继含循环(表明处于循环体内)
    if is_cur_call:
        for succ_id, _ in ctx.successors_bfs(node_id, max_depth=BFS_MAX_DEPTH):
            succ_type = ctx.get_node_type(succ_id)
            if _is_loop_like(succ_type):
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
    lhs_raw  = m.group("lhs")
    lhs_base = re.split(r"[\[\(.]", lhs_raw)[0].lower()

    # 步骤 3:排除纯时间戳赋值(= now / = block.timestamp)
    # 这类节点归 time_manipulation,不归 front_running
    rhs = expr[m.end():].strip()
    if _RE_TIMESTAMP.search(rhs):
        return False
    if re.fullmatch(r"(?:true|false)", rhs, re.IGNORECASE):
        return False

    # 步骤 4:命中判断
    if ctx.state_vars:
        return lhs_base in ctx.state_vars

    # fallback
    return bool(_RACE_VAR_PATTERNS.search(expr))


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


# ---------------------------------------------------------------------------
# 辅助:加载状态变量白名单
# ---------------------------------------------------------------------------

def load_state_vars_from_slither_json(slither_data: dict) -> set[str]:
    """从 Slither JSON 元数据提取合约级状态变量名(统一小写)。

    兼容三种格式:
    1. 顶层 state_variables 列表
    2. contracts[i].state_variables 列表
    3. fallback:从 cfg_nodes 的 state_variables_written 字段推断
    """
    state_vars: set[str] = set()

    def _harvest(lst: list) -> None:
        for sv in lst:
            if isinstance(sv, dict):
                name = sv.get("name") or sv.get("variable_name") or ""
            else:
                name = str(sv)
            name = name.strip()
            if name:
                state_vars.add(name.lower())

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
    unchecked = ctx.is_unchecked(node_id)

    return {
        "reentrancy":        is_anchor_reentrancy(expr),
        "arithmetic":        is_anchor_arithmetic(expr, is_in_unchecked=unchecked),
        "access_control":    is_anchor_access_control(expr),
        "uncheck_return":    is_anchor_uncheck_return(expr, node_id=node_id, ctx=ctx),
        "dos":               is_anchor_dos(node_id, ctx),
        "front_running":     is_anchor_front_running(node_id, ctx),
        "time_manipulation": is_anchor_time_manipulation(expr),
    }


def compute_anchor_score(
    node_id: Any,
    ctx: GraphContext,
    beta: float = 0.5,   # 大纲默认衰减系数,此处仅用于接口文档
) -> float:
    """计算节点聚合先验分数 s_v ∈ [0, 1]。

    s_v = 命中锚点类数 / 7。

    后续 M1 BFS 扩散时按 s_prop = s_v × β^depth 衰减;
    衰减由调用方(BFS 循环)逐深度施加,不在此函数内计算。

    Parameters
    ----------
    node_id : Any
    ctx : GraphContext
    beta : float
        距离衰减系数(大纲 §4.1.4 默认 0.5)。此函数不使用该参数,
        仅作接口文档占位,确保与 BFS 层的调用约定对齐。
    """
    flags     = compute_anchor_flags(node_id, ctx)
    hit_count = sum(1 for v in flags.values() if v)
    return hit_count / len(VULN_CLASSES)


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
