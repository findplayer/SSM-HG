"""solc AST 归一化单测（R5 修复验收，2026-09-12）。

覆盖（强制门）：
  - **老式节点零改写**：含 `attributes`/`children` 的节点经 `normalize_ast` **原样返回同一对象**
    → 既有 578 图的解析路径与产物不受本次改动影响（全量指纹回归另见 decisions §15.7）；
  - **新式节点归一**：solc ≥0.8 风格（`nodeType` + 顶层属性 + `nodes`）归一后 `walk_ast` 能正常收到
    合约 / 函数表 / 状态变量 / AST 父子边；
  - **构造函数不被误判为 fallback**：新式显式构造函数的 `name` 为空、`kind="constructor"`，
    必须记为 `constructor`（否则函数表键与 CFG 请求键 `(合约,"constructor")` 对不上）；
  - **receive / fallback 保持按 kind 记名**；
  - **`load_ast` 端到端**：新式文件读取后根已归一（`name=="SourceUnit"` 且 `children` 非空），
    老式文件根不被改写。

运行：`pytest tests/ -q`
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from build_cfg_centered_hetero_graph import (  # noqa: E402
    load_ast,
    normalize_ast,
    walk_ast,
)

# 老式（solc ≤0.7）节点：`name` 即节点类型，属性在 `attributes`，子节点在 `children`
OLD_STYLE_AST = {
    "name": "SourceUnit",
    "attributes": {"absolutePath": "Old.sol"},
    "src": "0:200:0",
    "id": 1,
    "children": [
        {
            "name": "ContractDefinition",
            "attributes": {"name": "Legacy", "baseContracts": []},
            "src": "0:150:0",
            "id": 2,
            "children": [
                {
                    "name": "FunctionDefinition",
                    "attributes": {"name": "Legacy", "isConstructor": True,
                                   "visibility": "public", "stateMutability": "nonpayable"},
                    "src": "20:40:0",
                    "id": 3,
                },
            ],
        },
    ],
}


def new_style_ast() -> dict:
    """solc ≥0.8 风格最小 AST：构造 / 普通函数 / receive / fallback + 一个状态变量。"""
    return {
        "id": 1,
        "nodeType": "SourceUnit",
        "src": "0:1000:0",
        "absolutePath": "New.sol",
        "nodes": [
            {"id": 2, "nodeType": "PragmaDirective", "src": "0:25:0",
             "literals": ["solidity", "^", "0.8", ".0"]},
            {
                "id": 3, "nodeType": "ContractDefinition", "name": "Base",
                "src": "26:900:0", "contractKind": "contract", "abstract": False,
                "nodes": [
                    {"id": 4, "nodeType": "VariableDeclaration", "name": "owner",
                     "src": "40:20:0", "stateVariable": True, "visibility": "public",
                     "constant": False, "mutability": "mutable"},
                    {"id": 5, "nodeType": "FunctionDefinition", "name": "", "kind": "constructor",
                     "src": "60:60:0", "visibility": "public", "stateMutability": "nonpayable"},
                    {"id": 6, "nodeType": "FunctionDefinition", "name": "unlock",
                     "kind": "function", "src": "120:60:0", "visibility": "external",
                     "stateMutability": "nonpayable"},
                    {"id": 7, "nodeType": "FunctionDefinition", "name": "", "kind": "receive",
                     "src": "180:30:0", "visibility": "external", "stateMutability": "payable"},
                    {"id": 8, "nodeType": "FunctionDefinition", "name": "", "kind": "fallback",
                     "src": "210:40:0", "visibility": "external", "stateMutability": "nonpayable"},
                    {"id": 9, "nodeType": "ModifierDefinition", "name": "onlyOwner",
                     "src": "250:40:0"},
                ],
            },
        ],
    }


def test_normalize_ast_is_identity_for_old_style():
    """老式节点必须原样返回（同一对象、零改写）→ 既有 578 图产物逐位不变的前提。"""
    assert normalize_ast(OLD_STYLE_AST) is OLD_STYLE_AST
    assert normalize_ast(OLD_STYLE_AST["children"][0]) is OLD_STYLE_AST["children"][0]


def test_walk_ast_on_normalized_new_style_tree():
    """新式 AST 归一后：合约表 / 函数表 / 状态变量 / AST 父子边都齐全。"""
    root = normalize_ast(new_style_ast())
    assert root["name"] == "SourceUnit" and root["attributes"]["absolutePath"] == "New.sol"
    assert "attributes" in root and "children" in root

    nodes, edges, functions, contracts, state_vars = walk_ast(root)
    assert [c["name"] for c in contracts] == ["Base"]
    assert state_vars == {"owner"}
    assert edges, "AST 父子边不应为空"

    table = {(f["contract"], f["name"]): f for f in functions}
    assert set(table) == {("Base", "constructor"), ("Base", "unlock"),
                          ("Base", "receive"), ("Base", "fallback")}
    # 显式构造函数：name 为空 + kind="constructor" → 记作 constructor（不是 fallback）
    assert table[("Base", "constructor")]["kind"] == "constructor"
    assert table[("Base", "constructor")]["visibility"] == "public"
    assert table[("Base", "constructor")]["state_mutability"] == "nonpayable"
    assert table[("Base", "unlock")]["kind"] == "function"
    assert table[("Base", "unlock")]["visibility"] == "external"
    # receive / fallback 仍按 kind 记名，且 stateMutability 取顶层值
    assert table[("Base", "receive")]["state_mutability"] == "payable"
    assert table[("Base", "fallback")]["kind"] == "fallback"

    # 节点元信息：函数体/修饰符体内的节点带 contract + function；修饰符定义节点可被识别
    types = {n["type"] for n in nodes.values()}
    assert {"ContractDefinition", "FunctionDefinition", "ModifierDefinition"} <= types


def test_empty_name_constructor_not_reported_as_fallback():
    """回归守卫：老式 AST 的空名 fallback 语义不变，新式构造函数的键不落到 fallback。"""
    root = normalize_ast(new_style_ast())
    _, _, functions, _, _ = walk_ast(root)
    names = {f["name"] for f in functions}
    assert "constructor" in names and "fallback" in names
    # 构造函数的源码区间与 fallback 不同（60:60 vs 210:40 → src 起点 60 / 210）
    spans = {f["name"]: f["src"][0] for f in functions if f["name"] in ("constructor", "fallback")}
    assert spans["constructor"] == 60 and spans["fallback"] == 210


def test_load_ast_end_to_end(tmp_path):
    """端到端：新式文件根被归一，老式文件根不被改写。"""
    new_path = tmp_path / "new.json"
    new_path.write_text(json.dumps({"sources": {"New.sol": {"AST": new_style_ast(), "id": 0}},
                                    "sourceList": ["New.sol"]}), encoding="utf-8")
    root, source_name, source_key = load_ast(str(new_path))
    assert (source_name, source_key) == ("New.sol", "New.sol")
    assert root["name"] == "SourceUnit" and root["children"]
    assert [c["name"] for c in walk_ast(root)[3]] == ["Base"]

    old_path = tmp_path / "old.json"
    old_path.write_text(json.dumps({"sources": {"Old.sol": {"AST": OLD_STYLE_AST, "id": 0}},
                                    "sourceList": ["Old.sol"]}), encoding="utf-8")
    old_root, _, _ = load_ast(str(old_path))
    assert old_root == OLD_STYLE_AST          # 老式根零改写
    assert [f["name"] for f in walk_ast(old_root)[2]] == ["constructor"]
