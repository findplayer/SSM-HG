#!/usr/bin/env python3
"""M3：节点特征**通道**构建（手册第 8 章；2026-09-12 前端化后：本文件不再做融合）。

产物契约（schema v2，见 `docs/M3_frontend_design.md` v3 定稿）：
  - `{base}_cb.pt`   CodeBERT 双通道缓存（函数级 512 / 节点级 128；函数内共享、按 text sha 复用）；
  - `{base}_feat.pt` **通道字典**（不再是张量）：
        {"schema_version": 2, "struct": N×D_struct float32, "type_id": N int64, "sv": N×1 float32,
         "meta": {D_struct, struct_layout, role_names, channel_sha256{struct,type_id,sv},
                  cb_sha256{cb_func,cb_node}, combined_sha256, torch, codebert, created_utc}}
    行序 = nodes 顺序（第 i 行 ↔ _pyg.pt node_id[i]）。

已落地（2026-09-05）：
  - A1~A3  骨架与 CLI、数据加载与「节点行序契约」、类别字典预扫描（ir_cat.json）；
  - A4     节点局部窗口 build_node_window（手册 8.7 原样）；
  - A5     CodeBERT 双通道缓存：函数级 512（函数内共享）+ 节点级 128 → {base}_cb.pt；
  - A6/A7  9 角色类型索引与 18+1 结构特征（s_v 独立通道）；
  - A8/A9  原 assemble+MLP → {base}_feat.pt（128 维）。

2026-09-12 P1 前端化（承重墙；设计稿 `docs/M3_frontend_design.md` v3，R1–R11 + Q6–Q9 已裁定）：
  - **融合（Embedding+MLP）移入 `scripts/model.py::NodeFuser`**：类型嵌入自此**可学习**（大纲 4.3.1），
    结构/先验 dropout 在模型内实现（4.3.3/4.3.4）；先验 dropout（正则）与确定性消融（配置）共用同一
    通道掩码原语，且**只能发生在融合 Linear 之前**（见设计稿 §3.2.1）；
  - 本文件**删除** `torch.manual_seed` / `nn.Embedding` / `nn.Linear`：M3 变为纯确定性（无 RNG），
    同图重跑**逐位一致**；初始化 seed 交由模型侧 `FUSER_INIT_SEED`（默认 20260905）；
  - **文件级变体退役**（R2）：`_feat_no-prior` / `_feat_grp-*` / `_feat_{variant}` 不再产出；
    特征级消融一律在模型侧做（通道级，零重跑）；
  - 新增**逐通道字节级 sha256**（R7，`tobytes()`）+ `combined_sha256`（Q6=A：含 cb 两通道）
    + schema 版本（R8）；旧格式 `_feat.pt` 已归档至 `graphs/legacy_feat_pre_frontend/`（供 T2 回归）。

语义锁死（2026-09-12 重定义）：
  - `_feat.pt` = **拼接前通道**（struct / type_id / sv），唯一模型输入的存储载体；
  - `_pyg.pt` 只读、绝不写回；`_cb.pt` 为中间缓存；
  - `dataset.py` 只组合（含 `_cb.pt` 行对齐），**不做任何掩码/置零**；融合与掩码全在模型前端。

历史记录（A1~A12 期间的修复与口径澄清，保留备查）：
  - 复核修复（2026-09-05，全库扫描驱动）：INT_CALL 补 ir 含 INTERNAL_CALL 的成员内部调用；
    循环体判定对齐 M1 dos 锚点④口径（CFG 反向 10 跳、同函数、不含自身）；
    classify_call_mode / node_involves_call_return 的 .call 判定改 EXT_CALL_RE 同形态；
    node_has_ext_call 补内建转账 IR 指令（`SEND dest:` / `Transfer dest:`）。
  - 口径澄清（2026-09-12 抽查审计，零行为改动）：`node_has_ext_call`（8.3 角色 EXT_CALL / 8.5 #2）
    是**节点语义口径**，宽于 7.6 的 CALLBACK_RISK 源集合（内建 send/transfer 仍计为外部调用节点，
    但**不作为** CALLBACK_RISK 源节点）；结构特征编号与手册 8.5 对齐。
  - 大纲改II 对齐：结构特征 = 18 项（`s_v` 移出清单、仍作独立通道）；分组消融三设置
    {all, base, base+sem} 与两个 CodeBERT 单通道消融 **均移动到模型侧**。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import torch

# 通道契约（CB_DIM/ROLE_NAMES/SCHEMA_VERSION/哈希）由 dataset.py 统一持有，
# 生产侧与消费侧共用同一份定义，避免口径分叉（设计稿 §2.4/§4）。
from dataset import (CB_DIM, ROLE_NAMES, SCHEMA_VERSION,  # noqa: E402
                     channel_sha256, combined_sha256)

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
CODEBERT = "microsoft/codebert-base"          # A5 使用
# 2026-09-12 前端化：原 SEED / TYPE_EMB_DIM / HID_DIM 随融合迁移到 scripts/model.py
# （NodeFuser 的 FUSER_INIT_SEED=20260905 与 type_dim=64 / hidden=128），本文件已无任何 RNG。
# cfg_node_type 枚举容错：统一大写并去下划线后比对（Slither 0.11.5 为无下划线名；
# 旧版 IF_LOOP/BEGIN_LOOP/END_LOOP 规范化后等同 IFLOOP/BEGINLOOP/ENDLOOP）
LOOP_CONTROL_TYPES = {"IFLOOP", "BEGINLOOP", "WHILE", "FOR", "DO_WHILE", "STARTLOOP", "ENDLOOP"}
CONDITION_TYPES = {"IF", "IFLOOP"}
ENTRY_TYPES = {"ENTRYPOINT"}
ASSIGN_RE = re.compile(r"(?<![=!<>])=(?!=)|[+\-*/%]=")
# 状态变量写判定（LHS：sv 后可选下标/成员，再接赋值符；大小写敏感，成员/下标形态另做不敏感回退）
WRITE_RE_TMPL = r"(?<![A-Za-z0-9_]){sv}(?:\s*\[[^\]\n]*\])?(?:\s*\.[A-Za-z_]\w*)?\s*[+\-*/%]?=(?!=)"
# 外部调用正则（与手册 7.6 一致）
EXT_CALL_RE = re.compile(r"\.\s*call\s*(\{|\(|\.)|\.\s*send\s*\(|\.\s*transfer\s*\(")

# A3：固定类别字典（手册 8.5 #1 / #12）。可见性 4 类；外呼方式 5 类（call/send/transfer/低级调用/其他）。
VISIBILITY_ORDER = ["public", "external", "internal", "private"]
CALL_MODE_ORDER = ["call", "send", "transfer", "low_level", "other"]
CAT_VERSION = "m3-categories-v1"
MAX_IR_CATEGORIES = 20                        # 前 19 类 + OTHER（手册 8.5 #18 末句）


def parse_args() -> argparse.Namespace:
    """解析 CLI：目录默认 products/alldata/graphs；--only 单图；--scan-only 只扫字典；--force。"""
    parser = argparse.ArgumentParser(
        description="M3 节点特征初始化（A1~A3：数据加载契约 + 类别字典预扫描）。")
    parser.add_argument(
        "--in-dir",
        default=f"{BASE}/products/alldata/graphs",
        help="Directory containing *_hetero.json files.",
    )
    parser.add_argument(
        "--out-dir",
        default=f"{BASE}/products/alldata/graphs",
        help="Directory for M3 outputs (_cb.pt / _feat.pt channels).",
    )
    parser.add_argument(
        "--m1-dir",
        default=f"{BASE}/products/alldata/graphs",
        help="Directory containing *_m1.json files (node_scores).",
    )
    parser.add_argument(
        "--pattern",
        default="*_hetero.json",
        help="Glob pattern used to select input graphs.",
    )
    parser.add_argument(
        "--only",
        default=None,
        help="Only process the graph with this exact base prefix (e.g. nasd_simple_dao__simple_dao).",
    )
    parser.add_argument(
        "--cb-patch",
        action="store_true",
        help="增量补 cb 缓存：保留已有向量，只补缺失的 func/node 键（函数级通道缺口修复 S5；"
             "不重编全量）。",
    )
    parser.add_argument(
        "--codebert",
        default=CODEBERT,
        help="CodeBERT model id or LOCAL weights directory (e.g. /path/to/codebert-base); "
             "default microsoft/codebert-base.",
    )
    parser.add_argument(
        "--scan-only",
        action="store_true",
        help="Only scan all graphs and write products/alldata/graphs/ir_cat.json, then exit.",
    )
    parser.add_argument(
        "--categories",
        default=None,
        help="冻结的 IR 类别字典文件路径（默认 <out-dir>/ir_cat.json）。**跨数据集（DIVE/SolidiFI）"
             "必须传入主库 products/alldata/graphs/ir_cat.json**：否则会对新数据集重新扫描生成"
             "字典，导致 IR 列宽/类别语义与训练好的模型不一致（NodeFuser 输入维度错位）。",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing outputs / re-scan categories.",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# A3：类别归类（供全库扫描与后续 one-hot 共用同一分类器）
# ---------------------------------------------------------------------------

def classify_ir_category(ir_text: str | None) -> str:
    """从 SlithIR 文本归纳指令类别（手册 8.5 #18）。

    规则（优先级从高到低，避免被首行变量声明淹没）：
      - 含 `CONDITION` → CONDITION（条件判定 IR）；
      - 含 `LOW_LEVEL_CALL` / `HIGH_LEVEL_CALL` / `SOLIDITY_CALL` → 对应调用类；
      - 含赋值（`:=` 或 `=`）→ ASSIGNMENT；
      - 其余（空 IR / 纯变量声明 / 不可识别）→ OTHER。
    """
    if not ir_text or not ir_text.strip():
        return "OTHER"
    text = ir_text
    if "CONDITION" in text:
        return "CONDITION"
    if "LOW_LEVEL_CALL" in text:
        return "LOW_LEVEL_CALL"
    if "HIGH_LEVEL_CALL" in text:
        return "HIGH_LEVEL_CALL"
    if "SOLIDITY_CALL" in text:
        return "SOLIDITY_CALL"
    if ":=" in text or re.search(r"(?<![=!<>])=(?!=)", text):
        return "ASSIGNMENT"
    return "OTHER"


def classify_call_mode(expression: str | None, ir_text: str | None) -> str:
    """外部调用方式 one-hot 类别（手册 8.5 #12，按实际调用机制归类）。

    优先级：低层调用（ir LOW_LEVEL_CALL）→ low_level；高层调用（ir HIGH_LEVEL_CALL，
    含 ERC20 `token.transfer(...)` 这类具名函数调用）→ call；内建转账指令
    `addr.transfer(x)` / `addr.send(x)`（expression 必含对应文本）→ transfer / send；
    其余 .call 形态 → call；无外呼 → other。

    注意 .call 判定必须用与 EXT_CALL_RE 一致的形态（`.call{`/`.call(`/`.call.`），
    不能用 `".call" in expression` 子串匹配——会把 `requests[i].callbackAddr = ...`
    这类普通成员赋值误判为 call（2026-09-05 全库扫描发现 2 例）。
    """
    ir_text = ir_text or ""
    if "LOW_LEVEL_CALL" in ir_text:
        return "low_level"
    if "HIGH_LEVEL_CALL" in ir_text:
        return "call"
    # 内建转账指令兜底（8.5 #12：内建 addr.transfer/send → transfer/send），
    # 与 node_has_ext_call 的 ir 兜底口径一致（2026-09-07 补；当前全库 expression
    # 均存在、0 数据影响，防御性对齐防止 expression 缺失时 #12 归 other 而 #2 为真）。
    if re.search(r"\bTransfer\s+dest:", ir_text):
        return "transfer"
    if re.search(r"\bSEND\s+dest:", ir_text):
        return "send"
    expression = expression or ""
    if ".transfer(" in expression:
        return "transfer"
    if ".send(" in expression:
        return "send"
    if re.search(r"\.\s*call\s*(?:\{|\(|\.)", expression):
        return "call"
    return "other"


def scan_categories(hetero_dir: Path, pattern: str) -> tuple[Counter, Counter, int]:
    """全库扫描 *_hetero.json，统计 IR 指令类别与外呼方式频次。

    返回 (ir_counter, call_mode_counter, node_count)。只读 nodes[].ir / expression，
    不加载源码、不做任何解码，纯 JSON 扫描（A3 预扫描）。
    """
    ir_counter: Counter = Counter()
    call_counter: Counter = Counter()
    node_count = 0
    for graph_path in sorted(hetero_dir.glob(pattern)):
        graph = json.loads(graph_path.read_text(encoding="utf-8"))
        for node in graph.get("nodes", []):
            node_count += 1
            ir_counter[classify_ir_category(node.get("ir"))] += 1
            call_counter[classify_call_mode(node.get("expression"), node.get("ir"))] += 1
    return ir_counter, call_counter, node_count


def truncate_categories(counter: Counter) -> list[str]:
    """按频次降序截断 IR 类别字典：最多前 19 类 + OTHER（共 ≤20 类，手册 8.5 #18 末句）。"""
    ordered = [category for category, _ in counter.most_common() if category != "OTHER"]
    if len(ordered) > MAX_IR_CATEGORIES - 1:
        ordered = ordered[: MAX_IR_CATEGORIES - 1]
    if "OTHER" not in ordered:
        ordered.append("OTHER")
    return ordered


def categories_path(out_dir: Path) -> Path:
    """类别字典文件路径：products/alldata/graphs/ir_cat.json。"""
    return out_dir / "ir_cat.json"


def write_categories(out_dir: Path, ir_counter: Counter, call_counter: Counter,
                     scope: str, force: bool = False) -> dict[str, Any]:
    """把扫描结果写成 ir_cat.json（含版本/scope/类别列表与频次统计）。"""
    ir_categories = truncate_categories(ir_counter)
    payload = {
        "version": CAT_VERSION,
        "scope": scope,
        "ir_categories": ir_categories,
        "visibility": VISIBILITY_ORDER,
        "call_modes": CALL_MODE_ORDER,
        "ir_category_stats": dict(ir_counter.most_common()),
        "call_mode_stats": dict(call_counter.most_common()),
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    path = categories_path(out_dir)
    if path.exists() and not force:
        raise FileExistsError(f"Categories file exists: {path} (use --force to re-scan)")
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return payload


def load_categories_file(path: Path) -> dict[str, Any] | None:
    """读冻结类别字典文件（--categories；跨数据集复用主库字典用）；不存在返回 None。"""
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# A4~A9：窗口文本 / CodeBERT 双通道 / 角色与结构特征 / assemble+MLP
# ---------------------------------------------------------------------------

def build_node_window(lines: list[str], node: dict[str, Any],
                      fn_start: int | None, fn_end: int | None) -> str:
    """节点级局部窗口文本（手册 8.7 build_node_window 原样）。

    - 缺 line_start：退化为 expression（无则空串）；
    - 多行（end>start）：取本行起至 end+1 行（0-based 切片 lo=max(0,s-1), hi=min(len,e+1)）；
    - 单行：上 1 行 + 本行 + 下 1 行（lo=max(0,s-2), hi=min(len,s+1)）。
    fn_start/fn_end 保留为签名兼容（手册 8.7），窗口计算不依赖函数边界。
    """
    if node.get("line_start") is None:
        return node.get("expression") or ""
    s = int(node["line_start"])
    e = int(node.get("line_end") or s)
    if e > s:                                   # 多行语句：全部行 + 前后各 1 行
        lo, hi = max(0, s - 1), min(len(lines), e + 1)
    else:                                       # 单行：上 1 行、本行、下 1 行
        lo, hi = max(0, s - 2), min(len(lines), s + 1)
    return "\n".join(lines[lo:hi])


def encode(text: str, tok: Any, model: Any, max_len: int) -> "torch.Tensor":
    """CodeBERT 编码一段文本 → [CLS] 向量（空文本返回 zeros(768)，不调模型）。"""
    if not text:
        return torch.zeros(CB_DIM)
    ids = tok(text, truncation=True, max_length=max_len, return_tensors="pt")
    with torch.no_grad():
        out = model(**ids).last_hidden_state[:, 0, :].cpu()
    return out[0]


def load_codebert(name: str = CODEBERT) -> tuple[Any, Any]:
    """加载并冻结 codebert（AutoTokenizer + AutoModel，eval 模式）。

    name 可为 HF 模型 id（默认 microsoft/codebert-base）或**本地权重目录**路径；
    网络不可达时建议传入本地目录（--codebert <dir>），A5 即可离线跑通。
    """
    from transformers import AutoModel, AutoTokenizer
    tok = AutoTokenizer.from_pretrained(name)
    model = AutoModel.from_pretrained(name).eval()
    for param in model.parameters():
        param.requires_grad = False
    return tok, model


def build_cb_cache(data: dict[str, Any], cb_path: Path, tok: Any, model: Any,
                   force: bool) -> tuple[dict[str, Any], bool]:
    """为一张图生成/复用 _cb.pt（A5）。

    返回 (cache, reused)。cache = {"func": {"contract::function": Tensor768},
    "node": {str(id): Tensor768}}。函数级同函数共享；节点级窗口文本按 sha 复用编码。
    已有文件且未 --force → 直接读回复用（断点续跑）。
    """
    if cb_path.exists() and not force:
        return torch.load(cb_path, map_location="cpu"), True
    nodes = data["nodes"]
    fn_table = data["fn_table"]
    src_lines = data["src_lines"]
    func_cache: dict[str, torch.Tensor] = {}
    node_cache: dict[str, torch.Tensor] = {}
    text_cache: dict[str, torch.Tensor] = {}

    for (contract, function), fn in fn_table.items():
        fs, fe = fn.get("start_line"), fn.get("end_line")
        if fs is None or fe is None:
            text = ""
        else:
            text = "\n".join(src_lines[int(fs) - 1:int(fe)])
        func_cache[f"{contract}::{function}"] = encode(text, tok, model, 512)

    for node in nodes:
        key = (node.get("contract"), node.get("function"))
        fn = fn_table.get(key)
        text = build_node_window(src_lines, node, fn.get("start_line") if fn else None,
                                 fn.get("end_line") if fn else None)
        if text not in text_cache:
            text_cache[text] = encode(text, tok, model, 128)
        node_cache[str(node["id"])] = text_cache[text]

    cache = {"func": func_cache, "node": node_cache}
    cb_path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(cache, cb_path)
    return cache, False


def patch_cb_cache(data: dict[str, Any], cb_path: Path, tok: Any, model: Any) -> dict[str, int]:
    """**增量**补 cb 缓存（2026-09-12 函数级通道缺口修复 S5；不重编已有向量）。

    与 `build_cb_cache` 的差别：保留文件中已有的 `func`/`node` 向量**逐位不变**，只对**缺失**键
    按同一文本口径补编码（函数源码 512 token / 节点窗口 128 token）；无新增则不重写文件。
    预期收益：全量强制重建 ≈ 70 min（实测单图 7.9 s × 581），本路径只编新增函数键 ≈ 5 min。
    返回 {"func_added", "func_total", "node_added", "node_total", "rewritten"}。
    """
    cache = torch.load(cb_path, map_location="cpu")
    func_cache, node_cache = cache["func"], cache["node"]
    nodes, fn_table, src_lines = data["nodes"], data["fn_table"], data["src_lines"]
    text_cache: dict[str, torch.Tensor] = {}

    func_added = 0
    for (contract, function), fn in fn_table.items():
        key = f"{contract}::{function}"
        if key in func_cache:
            continue
        fs, fe = fn.get("start_line"), fn.get("end_line")
        text = "" if fs is None or fe is None else "\n".join(src_lines[int(fs) - 1:int(fe)])
        func_cache[key] = encode(text, tok, model, 512)
        func_added += 1

    node_added = 0
    for node in nodes:
        key = str(node["id"])
        if key in node_cache:
            continue
        fn = fn_table.get((node.get("contract"), node.get("function")))
        text = build_node_window(src_lines, node, fn.get("start_line") if fn else None,
                                 fn.get("end_line") if fn else None)
        if text not in text_cache:
            text_cache[text] = encode(text, tok, model, 128)
        node_cache[key] = text_cache[text]
        node_added += 1

    rewritten = bool(func_added or node_added)
    if rewritten:
        torch.save({"func": func_cache, "node": node_cache}, cb_path)
    return {"func_added": func_added, "func_total": len(func_cache),
            "node_added": node_added, "node_total": len(node_cache), "rewritten": rewritten}


# ---- 语义角色 / 结构特征小谓词 -----------------------------------------

def norm_node_type(node: dict[str, Any]) -> str:
    """cfg_node_type 规范化：大写并去下划线（兼容 ENTRY_POINT / ENTRYPOINT、IF_LOOP / IFLOOP）。"""
    return str(node.get("cfg_node_type") or "").upper().replace("_", "")


def has_assignment(expression: str | None) -> bool:
    """expression 是否含赋值运算符（= 或 +=、-= 等复合赋值）。"""
    return bool(expression and ASSIGN_RE.search(expression))


def lhs_tail(expression: str | None) -> str:
    """返回表达式首个 '=' 之前的部分（≈ LHS），用于成员/下标回退判定。"""
    if not expression:
        return ""
    idx = ASSIGN_RE.search(expression)
    return expression[: idx.start()] if idx else expression


def is_state_write(expression: str | None, state_vars: list[str]) -> bool:
    """LHS 命中状态变量的写入（8.5 #4）。

    大小写敏感精确匹配；若 LHS 含下标/成员（[...] 或 .），再按基变量做大小写不敏感回退
    （与 M1 6.3 的“成员/下标写入按基变量回退”一致，纯裸名仍大小写敏感防 acc/Acc）。
    """
    expression = expression or ""
    if not state_vars:
        return False
    for sv in state_vars:
        if re.search(WRITE_RE_TMPL.format(sv=re.escape(sv)), expression):
            return True
    if "[" in lhs_tail(expression) or "." in lhs_tail(expression):
        for sv in state_vars:
            if re.search(WRITE_RE_TMPL.format(sv=re.escape(sv)), expression, re.IGNORECASE):
                return True
    return False


def is_state_read(expression: str | None, state_vars: list[str]) -> bool:
    """expression 使用位出现状态变量（8.5 #5；大小写敏感 + 下标/成员形态不敏感回退）。"""
    expression = expression or ""
    if not state_vars:
        return False
    for sv in state_vars:
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(sv)}(?!\w)", expression):
            return True
    if "[" in expression or "." in expression:
        for sv in state_vars:
            if re.search(rf"(?<![A-Za-z0-9_]){re.escape(sv)}(?!\w)", expression, re.IGNORECASE):
                return True
    return False


def node_has_ext_call(node: dict[str, Any]) -> bool:
    """节点是否为外部调用（8.3 角色 / 8.5 #2 结构特征）。

    **本判定是“节点语义口径”，宽于 7.6 的 CALLBACK_RISK 源集合**（`改II` 4.2.2 的
    收窄只针对 CALLBACK_RISK 源节点，不改变节点角色与结构特征）：
      - expression 命中 EXT_CALL_RE（`.call{`/`.call(`/`.call.`、`.send(`、`.transfer(`）；
      - ir 含 LOW_LEVEL_CALL / HIGH_LEVEL_CALL（具名外部调用，如 ERC20 `token.transfer`）；
      - ir 含内建转账指令（`SEND dest:` / `Transfer dest:`，Slither 0.11.5 打印形态，
        expression 缺失时兜底）。
    即：仅转发 2300 gas 的内建 `addr.send(...)` / `addr.transfer(...)` 仍算外部调用节点
    （大纲 4.3.3 #12 的“外部调用方式 one-hot”本就含 send/transfer），但**不作为**
    CALLBACK_RISK 源节点（见 `build_cfg_centered_hetero_graph.RE_EXT_CALL_TEXT`）。
    """
    if EXT_CALL_RE.search(node.get("expression") or ""):
        return True
    ir = node.get("ir") or ""
    return ("LOW_LEVEL_CALL" in ir or "HIGH_LEVEL_CALL" in ir
            or bool(re.search(r"\b(?:SEND|Transfer)\s+dest:", ir)))


def node_has_transfer(node: dict[str, Any]) -> bool:
    """是否含转账操作（.transfer/.send/call.value，8.5 #3）。"""
    expression = node.get("expression") or ""
    return ".transfer(" in expression or ".send(" in expression or "call.value" in expression


def node_is_condition(node: dict[str, Any]) -> bool:
    """是否为条件判断节点（type IF/IFLOOP 或 expression 含 require/assert，8.5 #6）。"""
    if norm_node_type(node) in CONDITION_TYPES:
        return True
    expression = node.get("expression") or ""
    return "require(" in expression or "assert(" in expression


def node_has_arith(node: dict[str, Any]) -> bool:
    """是否含算术运算（expression 运算符 或 ir 含 ADD/SUB/MUL/DIV/SDIV/MOD，8.5 #7）。"""
    expression = node.get("expression") or ""
    if re.search(r"[+\-*/%]", expression):
        return True
    return bool(re.search(r"\b(ADD|SUB|MUL|DIV|SDIV|MOD|EXP)\b", node.get("ir") or ""))


def node_uses_timestamp(node: dict[str, Any]) -> bool:
    """是否使用 block.timestamp / now（8.5 #8）。"""
    expression = node.get("expression") or ""
    return "block.timestamp" in expression or bool(re.search(r"\bnow\b", expression))


def node_uses_msg(node: dict[str, Any]) -> bool:
    """是否使用 msg.sender / tx.origin（8.5 #9）。"""
    expression = node.get("expression") or ""
    return "msg.sender" in expression or "tx.origin" in expression


def node_involves_call_return(node: dict[str, Any]) -> bool:
    """是否涉及调用返回值（.send/低级 .call 会返回 bool，8.5 #10，与 6.3 uncheck_return 判定一致）。

    .call 判定用与 EXT_CALL_RE/M1 _RE_LOWLEVEL_CALL 同形态的匹配，
    避免 `x.callbackAddr` 子串误判（2026-09-05 全库扫描发现 2 例）。
    """
    expression = node.get("expression") or ""
    return bool(re.search(r"\.\s*send\s*\(", expression)
                or re.search(r"\.\s*call\s*(?:\{|\(|\.)", expression))


def classify_node_role(node: dict[str, Any], state_vars: list[str]) -> str:
    """节点 → 9 种语义角色之一（8.3；唯一索引，顺序 EXT>RETURN>STATE_WRITE>ASSIGNMENT>
    INT_CALL>CONDITION>ENTRY>STATE_READ>OTHER）。"""
    ntype = norm_node_type(node)
    expression = node.get("expression") or ""
    ir_text = node.get("ir") or ""
    if node_has_ext_call(node):
        return "EXT_CALL"
    if ntype == "RETURN":
        return "RETURN"
    if is_state_write(expression, state_vars):
        return "STATE_WRITE"
    if has_assignment(expression):
        return "ASSIGNMENT"
    if (re.search(r"(?<![.\w])[A-Za-z_]\w*\s*\(", expression)
            or "INTERNAL_CALL" in ir_text):
        return "INT_CALL"
    if ntype in CONDITION_TYPES or "CONDITION" in ir_text:
        return "CONDITION"
    if ntype in ENTRY_TYPES:
        return "ENTRY"
    if is_state_read(expression, state_vars):
        return "STATE_READ"
    return "OTHER"


def build_adjacency(data: dict[str, Any]) -> tuple[dict[int, list[int]], dict[int, list[int]]]:
    """由 edges.CFG_FLOW 构建同图前向/反向邻接（A7 的 CFG 后继/祖先遍历用）。"""
    adj_out: dict[int, list[int]] = {}
    adj_in: dict[int, list[int]] = {}
    for node in data["nodes"]:
        node_id = int(node["id"])
        adj_out.setdefault(node_id, [])
        adj_in.setdefault(node_id, [])
    for edge in data["cfg_edges"]:
        source, target = int(edge["source"]), int(edge["target"])
        adj_out.setdefault(source, []).append(target)
        adj_in.setdefault(target, []).append(source)
    return adj_out, adj_in


def reach_flag(start: int, adjacency: dict[int, list[int]], max_depth: int,
               node_map: dict[int, dict[str, Any]], fn_of: dict[int, str],
               predicate, include_self: bool = False) -> bool:
    """沿邻接（前向=出边/反向=入边）BFS 至多 max_depth 跳，是否有节点满足 predicate。

    只探同函数节点（跨函数视为不可达，8 步回调约束同源：不跨函数传播）。
    """
    from collections import deque
    start_fn = fn_of.get(start)
    if include_self and predicate(node_map[start]):
        return True
    seen = {start}
    queue = deque([(start, 0)])
    while queue:
        current, depth = queue.popleft()
        if depth >= max_depth:
            continue
        for nxt in adjacency.get(current, []):
            if nxt in seen:
                continue
            seen.add(nxt)
            if fn_of.get(nxt) != start_fn:
                continue
            if predicate(node_map.get(nxt, {})):
                return True
            queue.append((nxt, depth + 1))
    return False


def in_loop_body(node_id: int, adj_in: dict[int, list[int]], node_map: dict[int, dict[str, Any]],
                 fn_of: dict[int, str]) -> bool:
    """节点是否位于循环体内（8.5 #11）。

    口径与 M1 dos 锚点④一致：沿 CFG 反向 10 跳内同函数**祖先**含循环控制节点
    （不含自身——循环头 IFLOOP/STARTLOOP/ENDLOOP 本身不算“体内”），跨函数不传播。
    """
    pred = lambda nd: norm_node_type(nd) in LOOP_CONTROL_TYPES
    return reach_flag(node_id, adj_in, 10, node_map, fn_of, pred, include_self=False)


def build_struct_features(data: dict[str, Any], ir_categories: list[str],
                          adj_out: dict[int, list[int]], adj_in: dict[int, list[int]],
                          node_map: dict[int, dict[str, Any]], fn_of: dict[int, str]) -> list[list[float]]:
    """构造每节点结构特征行（8.5：除 s_v 外共 44 列 = 上界，行序 = nodes 顺序）。

    列布局（s_v 独立，不入本张量）：可见性4(#1) + 布尔14(#2-#11、#13-#16)
    + 外呼方式5(#12) + 归一化位置1(#17) + IR one-hot(#18，上界 20 类、当前 6 类)。
    行内注释的 #编号 与手册 8.5 表格编号一致。
    """
    state_vars = data["state_vars"]
    fn_table = data["fn_table"]
    rows: list[list[float]] = []
    for node in data["nodes"]:
        node_id = int(node["id"])
        expression = node.get("expression") or ""
        ir_text = node.get("ir") or ""
        fn = fn_table.get((node.get("contract"), node.get("function")))
        ext = node_has_ext_call(node)

        # 可见性 one-hot（4）
        visibility = node.get("function_visibility") or (fn.get("visibility") if fn else None)
        vis_row = [1.0 if visibility == v else 0.0 for v in VISIBILITY_ORDER]

        # 布尔 14 项（顺序见注释）
        write = is_state_write(expression, state_vars)
        loop = in_loop_body(node_id, adj_in, node_map, fn_of)
        consumed = False
        if node_involves_call_return(node):
            # 深度 3 的紧窗口：只把调用后紧邻的 require/assert/IF 节点当“消费”，
            # 避免把更下游无关的条件语句误判为消费（全库 3→10 跳仅 5 例翻转，
            # 均为 send/call 之后 4~5 跳的无关条件，紧窗口更准）。
            pred_cons = lambda nd: (nd.get("expression") and
                                    ("require(" in nd.get("expression") or "assert(" in nd.get("expression")
                                     or norm_node_type(nd) in CONDITION_TYPES))
            consumed = reach_flag(node_id, adj_out, 3, node_map, fn_of, pred_cons)
        post_write = reach_flag(node_id, adj_out, 10, node_map, fn_of,
                                lambda nd: is_state_write(nd.get("expression"), state_vars))
        entry_fn = False
        if fn and norm_node_type(node) in ENTRY_TYPES:
            entry_fn = (fn.get("visibility") in ("public", "external")
                        or fn.get("kind") in ("receive", "fallback"))
        bool_row = [
            1.0 if ext else 0.0,                                    # #2 外部调用
            1.0 if node_has_transfer(node) else 0.0,                # #3 转账
            1.0 if write else 0.0,                                  # #4 写状态
            1.0 if (is_state_read(expression, state_vars) and not write) else 0.0,  # #5 读状态
            1.0 if node_is_condition(node) else 0.0,                # #6 条件节点
            1.0 if node_has_arith(node) else 0.0,                   # #7 算术
            1.0 if node_uses_timestamp(node) else 0.0,              # #8 block.timestamp/now
            1.0 if node_uses_msg(node) else 0.0,                    # #9 msg.sender/tx.origin
            1.0 if node_involves_call_return(node) else 0.0,        # #10 调用返回值
            1.0 if loop else 0.0,                                   # #11 循环体内
            1.0 if consumed else 0.0,                               # #13 返回值被消费
            1.0 if post_write else 0.0,                             # #14 后继同函数状态写
            1.0 if entry_fn else 0.0,                               # #15 入口函数 ENTRY
            1.0 if (ext and loop) else 0.0,                         # #16 循环内外呼
        ]

        # 外呼方式 one-hot（5）
        mode = classify_call_mode(expression, ir_text)
        mode_row = [1.0 if mode == m else 0.0 for m in CALL_MODE_ORDER]

        # 归一化位置（1）
        line_start = node.get("line_start")
        if line_start is None or fn is None or fn.get("start_line") is None or fn.get("end_line") is None:
            pos = 0.5
        else:
            fs = int(fn["start_line"])
            fe = int(fn["end_line"])
            pos = (int(line_start) - fs) / (fe - fs + 1e-6)
            pos = min(max(pos, 0.0), 1.0)

        # IR 类别 one-hot（20）
        cat = classify_ir_category(ir_text)
        if cat in ir_categories:
            cat_idx = ir_categories.index(cat)
        else:
            cat_idx = ir_categories.index("OTHER") if "OTHER" in ir_categories else len(ir_categories) - 1
        ir_row = [0.0] * len(ir_categories)
        ir_row[cat_idx] = 1.0

        rows.append(vis_row + bool_row + mode_row + [pos] + ir_row)
    return rows


# 结构特征 18 项 → 四组（大纲改II 4.3.3）。列布局见 build_struct_features：
# 可见性4(base) + 布尔14[#2-#8=base(7)、#9-#11=sem(3)、#13=sem(1)、#14-#16=cb(3)]
#   + 外呼方式5(sem, #12) + 归一化位置1(pos, #17) + IR one-hot(pos, #18)。
# 2026-09-12 前端化：分组掩码已移动到模型侧（`scripts/model.py::struct_group_keep_mask`，
# 供 `NodeFuser` 做确定性消融，零重跑）；本文件只记录 struct_layout 供模型拼掩码。
STRUCT_LAYOUT = {
    "visibility": len(VISIBILITY_ORDER),
    "bool": 14,
    "call_mode": len(CALL_MODE_ORDER),
    "position": 1,
    # "ir": <len(ir_categories)>，运行时按图填入
}


def build_channels(data: dict[str, Any], categories: dict[str, Any],
                   cb: dict[str, Any]) -> dict[str, Any]:
    """构建**拼接前通道**（schema v2）：struct / type_id / sv + meta（逐通道 sha）。

    本函数**不做融合**（无 Embedding/MLP、无 RNG）；行序 = nodes 顺序
    （`_feat.pt` 第 i 行 ↔ `_pyg.pt` node_id[i]）。特征级消融（分组/通道）一律在模型侧做。
    与旧 `assemble_feat` 的通道构造逐位一致（旧路径的 MLP 已移至 `model.py::NodeFuser`）。
    """
    nodes = data["nodes"]
    state_vars = data["state_vars"]
    adj_out, adj_in = build_adjacency(data)
    node_map = {int(node["id"]): node for node in nodes}
    fn_of = {int(node["id"]): str(node.get("function")) for node in nodes}

    role_idx = [ROLE_NAMES.index(classify_node_role(node, state_vars)) for node in nodes]
    ir_categories = list(categories.get("ir_categories", []))
    struct_rows = build_struct_features(data, ir_categories, adj_out, adj_in, node_map, fn_of)
    struct = torch.tensor(struct_rows, dtype=torch.float32)            # N×D_struct（IR 列数可变）
    type_id = torch.tensor(role_idx, dtype=torch.long)                # N（索引 [0,9)，序=ROLE_NAMES）
    sv = torch.tensor([[data["s_v"][str(node["id"])]] for node in nodes], dtype=torch.float32)  # N×1

    func_vecs = torch.stack([
        cb["func"].get(f"{node.get('contract')}::{node.get('function')}", torch.zeros(CB_DIM))
        for node in nodes
    ])
    node_vecs = torch.stack([cb["node"].get(str(node["id"]), torch.zeros(CB_DIM)) for node in nodes])

    hashes = {name: channel_sha256(t) for name, t in
              (("cb_func", func_vecs), ("cb_node", node_vecs), ("type_id", type_id),
               ("struct", struct), ("sv", sv))}
    layout = dict(STRUCT_LAYOUT)
    layout["ir"] = len(ir_categories)
    return {
        "schema_version": SCHEMA_VERSION,
        "struct": struct,
        "type_id": type_id,
        "sv": sv,
        "meta": {
            "D_struct": int(struct.shape[1]) if struct.numel() else 0,
            "struct_layout": layout,
            "role_names": list(ROLE_NAMES),
            "channel_sha256": {k: hashes[k] for k in ("struct", "type_id", "sv")},
            "cb_sha256": {k: hashes[k] for k in ("cb_func", "cb_node")},
            "combined_sha256": combined_sha256(hashes),
            "torch": torch.__version__,
            "codebert": CODEBERT,
            "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        },
    }


# 2026-09-12 前端化：assemble_feat（旧「拼接+MLP→128 维」路径）已随融合迁移删除。
# 融合与全部特征掩码（ablate_sv / feat_groups / cb_channels）在 `model.NodeFuser` 内完成；
# 本文件只产拼接前通道（build_channels），不再有 Embedding/MLP/RNG。


def cb_path_for(out_dir: Path, base: str) -> Path:
    """CodeBERT 缓存路径：products/alldata/graphs/{base}_cb.pt。"""
    return out_dir / f"{base}_cb.pt"


def feat_path_for(out_dir: Path, base: str) -> Path:
    """特征路径：{base}_feat.pt（schema v2 通道字典；不再有变体文件，R2）。"""
    return out_dir / f"{base}_feat.pt"


_CB_CACHE: dict[str, tuple[Any, Any]] = {}


def get_codebert(name: str = CODEBERT) -> tuple[Any, Any]:
    """惰性加载并缓存 CodeBERT：仅当**需要生成** `_cb.pt` 时调用。

    `_cb.pt` 全部命中时（全量重跑的常态）完全不加载模型 → 更快，且不依赖网络。
    """
    if name not in _CB_CACHE:
        _CB_CACHE[name] = load_codebert(name)
    return _CB_CACHE[name]


def process_graph(graph_path: Path, data: dict[str, Any], categories: dict[str, Any],
                  out_dir: Path, force: bool, codebert: str, only: bool,
                  cb_patch: bool = False) -> dict[str, Any]:
    """处理单图：cb 缓存（A5）→ 写通道字典 _feat.pt（schema v2）。

    `cb_patch=True`（S5 缺口修复）：**不重编已有向量**，只补缺失的 func/node 键（见 `patch_cb_cache`），
    再照常构建 `_feat.pt`；与 `--force` 的区别是后者会把该图全部向量重算一遍（≈ 7.9 s/图）。
    """
    base = graph_path.name.replace("_hetero.json", "")
    cb_path = cb_path_for(out_dir, base)
    patch_stats: dict[str, int] | None = None
    if cb_patch and cb_path.exists() and not force:
        tok, model = get_codebert(codebert)
        patch_stats = patch_cb_cache(data, cb_path, tok, model)
        cb = torch.load(cb_path, map_location="cpu")
        reused = True
    else:
        tok = model = None
        if force or not cb_path.exists():
            tok, model = get_codebert(codebert)
        cb, reused = build_cb_cache(data, cb_path, tok, model, force)
    payload = build_channels(data, categories, cb)

    n = len(data["nodes"])
    assert payload["struct"].shape[0] == n, f"{base}: struct rows != nodes"
    assert payload["type_id"].shape[0] == n, f"{base}: type_id rows != nodes"
    assert payload["sv"].shape == (n, 1), f"{base}: sv shape {tuple(payload['sv'].shape)}"
    assert payload["meta"]["D_struct"] == payload["struct"].shape[1], f"{base}: D_struct mismatch"

    feat_path = feat_path_for(out_dir, base)
    out_dir.mkdir(parents=True, exist_ok=True)
    torch.save(payload, feat_path)
    if only:
        print(f"[m3] {base}: struct={tuple(payload['struct'].shape)} "
              f"type_id={tuple(payload['type_id'].shape)} sv={tuple(payload['sv'].shape)}  "
              f"cb_reused={reused}  cb_func={len(cb['func'])} cb_node={len(cb['node'])}")
        print(f"[m3] combined_sha256={payload['meta']['combined_sha256']}")
        print(f"[m3] channel_sha256={payload['meta']['channel_sha256']}")
    return {"base": base, "nodes": n, "feat": feat_path.name, "cb_reused": reused,
            "cb_patch": patch_stats,
            "combined_sha256": payload["meta"]["combined_sha256"]}


# ---------------------------------------------------------------------------
# A2：数据加载与「节点行序契约」
# ---------------------------------------------------------------------------

def load_graph(hetero_path: Path, m1_path: Path) -> dict[str, Any]:
    """加载一张图的 M3 输入，建立行序契约所需索引。

    返回 dict：
      - nodes  按文件顺序的节点表（_feat.pt 第 i 行 ↔ nodes[i]["id"] ↔ _pyg.pt node_id[i]）
      - meta   hetero meta
      - fn_table  {(contract, function): functions 表项}
      - s_v    {str(id): float}，来自 _m1.json node_scores（缺省 0.0）
      - src_lines  源码按行（meta.source_path，缺行容错）
    """
    graph = json.loads(hetero_path.read_text(encoding="utf-8"))
    m1 = json.loads(m1_path.read_text(encoding="utf-8")) if m1_path.exists() else {}
    nodes = graph.get("nodes", [])
    meta = graph.get("meta", {})
    fn_table = {(f["contract"], f["function"]): f for f in graph.get("functions", [])}
    scores = m1.get("node_scores", {}) if isinstance(m1, dict) else {}
    s_v = {str(node["id"]): float(scores.get(str(node["id"]), 0.0)) for node in nodes}
    source_path = meta.get("source_path")
    src_lines: list[str] = []
    if source_path and Path(source_path).exists():
        src_lines = Path(source_path).read_text(encoding="utf-8", errors="ignore").splitlines()
    return {
        "nodes": nodes,
        "meta": meta,
        "fn_table": fn_table,
        "s_v": s_v,
        "src_lines": src_lines,
        "cfg_edges": graph.get("edges", {}).get("CFG_FLOW", []),
        "state_vars": meta.get("state_vars", []),
    }


def print_graph_overview(data: dict[str, Any]) -> None:
    """打印单图加载摘要（A2 验收：节点 id / s_v / contract.function 与 _m1.json 逐一对齐）。"""
    nodes = data["nodes"]
    s_v = data["s_v"]
    print(f"  node_count={len(nodes)}  cfg_node_count={data['meta'].get('cfg_node_count')}  "
          f"state_vars={data['meta'].get('state_vars')}")
    for node in nodes:
        node_id = node["id"]
        func = f"{node.get('contract')}.{node.get('function')}"
        print(f"    id={node_id:<4} s_v={s_v[str(node_id)]:<6} "
              f"type={node.get('cfg_node_type'):<12} {func}")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def resolve_graphs(in_dir: Path, pattern: str, only: str | None) -> list[Path]:
    """解析待处理图列表：--only 精确前缀，否则按 pattern 全量。"""
    if only:
        matches = sorted(in_dir.glob(f"{only}_hetero.json"))
        return matches
    return sorted(in_dir.glob(pattern))


def main() -> None:
    """入口：--scan-only 全库字典；--only 单图加载摘要；其余在后续 A4+ 阶段接入。"""
    args = parse_args()
    in_dir = Path(args.in_dir)
    out_dir = Path(args.out_dir)
    m1_dir = Path(args.m1_dir)

    # A3：先保证类别字典存在（--scan-only 只做这一步）
    if args.scan_only:
        ir_counter, call_counter, node_count = scan_categories(in_dir, args.pattern)
        payload = write_categories(out_dir, ir_counter, call_counter, scope="all", force=args.force)
        print(f"Scanned {node_count} nodes; wrote {categories_path(out_dir)}")
        print(f"  IR categories ({len(payload['ir_categories'])}): {payload['ir_categories']}")
        print(f"  call modes: {payload['call_modes']}")
        return

    cat_path = Path(args.categories) if args.categories else categories_path(out_dir)
    categories = load_categories_file(cat_path)
    if categories is None:
        if args.categories:
            print(f"[m3] WARNING: --categories {cat_path} 不存在 → 回退全库扫描；"
                  f"跨数据集（DIVE/SolidiFI）必须传入主库 products/alldata/graphs/ir_cat.json，"
                  f"否则 IR 列宽/类别语义漂移、与已训练模型不兼容")
        # 字典缺失：为保证全库 one-hot 一致，总是做全库扫描（A3 已生成后通常不触发）
        ir_counter, call_counter, _ = scan_categories(in_dir, args.pattern)
        categories = write_categories(out_dir, ir_counter, call_counter, scope="all")
        print(f"[m3] categories not found; scanned full library and wrote ir_cat.json (scope=all)")

    graph_files = resolve_graphs(in_dir, args.pattern, args.only)
    if not graph_files:
        print(f"No input files found in: {in_dir} (pattern={args.pattern})")
        return

    results = []
    total_nodes = 0
    for graph_path in graph_files:
        m1_path = m1_dir / graph_path.name.replace("_hetero.json", "_m1.json")
        data = load_graph(graph_path, m1_path)
        total_nodes += len(data["nodes"])
        if args.only:
            base = graph_path.name.replace("_hetero.json", "")
            print(f"[m3] overview of {base}:")
            print_graph_overview(data)
            expected = {str(node["id"]) for node in data["nodes"]}
            assert set(data["s_v"]) == expected, "s_v keys must equal node id string set"
        result = process_graph(graph_path, data, categories,
                               out_dir, force=args.force, codebert=args.codebert,
                               only=bool(args.only), cb_patch=args.cb_patch)
        results.append(result)
        if args.only:
            print("[m3] node windows (A4 check):")
            for node in data["nodes"]:
                fn = data["fn_table"].get((node.get("contract"), node.get("function")))
                text = build_node_window(data["src_lines"], node,
                                         fn.get("start_line") if fn else None,
                                         fn.get("end_line") if fn else None)
                print(f"    id={node['id']:<4} lines={node.get('line_start')}-{node.get('line_end')} "
                      f"| {text!r}")
            role_counter = Counter(classify_node_role(node, data["state_vars"])
                                   for node in data["nodes"])
            print("[m3] role distribution (A6 check):",
                  {role: role_counter[role] for role in ROLE_NAMES if role_counter[role]})

    print(f"[m3] processed {len(graph_files)} graph(s), {total_nodes} node(s); "
          f"schema=v{SCHEMA_VERSION}; feat_dir={out_dir}")
    if not args.only:
        reused = sum(1 for r in results if r["cb_reused"])
        print(f"[m3] cb cache reused for {reused}/{len(results)} graphs (resume OK); "
              f"wrote {len(results)} _feat.pt channel dicts (no variant files)")
        if args.cb_patch:
            fa = sum((r["cb_patch"] or {}).get("func_added", 0) for r in results)
            na = sum((r["cb_patch"] or {}).get("node_added", 0) for r in results)
            rw = sum(1 for r in results if (r["cb_patch"] or {}).get("rewritten"))
            print(f"[m3] cb patch: func +{fa} , node +{na} ; rewritten files {rw}/{len(results)}")


if __name__ == "__main__":
    main()
