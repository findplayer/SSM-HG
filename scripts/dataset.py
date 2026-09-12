#!/usr/bin/env python3
"""M5 数据层（手册 10.2/12.3，2026-09-07）：_pyg.pt 结构 + _feat.pt(x) 组合、标签对齐、边级消融。

契约（语义锁死）：
  - `_pyg.pt` 只读（纯结构：edge_index/edge_type/元数据；其 `x` 为 N×1 占位、不回写）；
  - 模型输入 `x` 用 `*_feat.pt` 或 `*_feat_{variant}.pt`（MLP 后的 128 维 h_v^(0)），
    本层只组合、不再过 MLP，并断言 `x.shape[1]==128`；
  - 标签按**项目前缀**匹配（lower；剥前缀顺序先 nasd_ 后 asd_——nasd_ 含 asd_ 子串，
    先剥 asd_ 会把 nasd_xxx 误剥成 nxxx），项目内多合约 targets 取并集；
  - `load_graph` 断言 base 存在标签（第一道一致性防线，split 内缺标签直接报错）；
  - 边级消融：drop_edges ⊆ {0=CFG_FLOW, 3=DFG_DEP, 4=CALLBACK_RISK}，按 edge_type 过滤（零重跑）。

CLI：`python scripts/dataset.py --check <base>`（单图自检：N/E/type 分布/x 维度/标签）。
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import torch

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
LABEL_FILE = f"{BASE}/alldata(readonly)/contract_labels.json"
DEFAULT_GRAPH_DIR = f"{BASE}/Heterogeneous graphs"

# 关系编号固定（手册 7.7）：0=CFG_FLOW, 1=AST_PARENT, 2=AST_PARENT_SAME,
# 3=DFG_DEP, 4=CALLBACK_RISK；边级消融只允许删 0/3/4 三类主边。
RELATION_NAMES = {0: "CFG_FLOW", 1: "AST_PARENT", 2: "AST_PARENT_SAME",
                  3: "DFG_DEP", 4: "CALLBACK_RISK"}
DROPPABLE_EDGES = {0, 3, 4}


def strip_project_prefix(name: str) -> str:
    """项目名规范化：lower 并剥 asd_/nasd_ 前缀（先 nasd_ 后 asd_）。"""
    name = (name or "").lower()
    for prefix in ("nasd_", "asd_"):
        if name.startswith(prefix):
            name = name[len(prefix):]
    return name


def project_of_base(base: str) -> str:
    """图前缀 base（`<项目>__<合约>`）→ 规范化项目名（`__` 前第一段）。"""
    return strip_project_prefix(base.split("__", 1)[0])


def is_buggy_project(proj: str) -> bool:
    """是否 buggy_* 噪声项目（标签为每合约同款注入噪声，主实验剔除，见手册 10.2.6）。"""
    return proj.startswith("buggy_")


def build_proj_labels() -> dict[str, list[list[int]]]:
    """读主标签文件 → {规范化项目名: [targets, ...]}（同项目多条目保留，供取并集）。

    标签 `contract_name` 的 `-` 前部分是项目名（`send_loop-Refunder.sol` → `send_loop`），
    后部分是合约名而非文件名，不能与 meta.source 直接比对（手册 10.2.2）。
    """
    with open(LABEL_FILE, "r", encoding="utf-8") as handle:
        entries = json.load(handle)
    labels: dict[str, list[list[int]]] = defaultdict(list)
    for entry in entries:
        contract_name = entry.get("contract_name") or ""
        if "-" not in contract_name:
            continue
        project = strip_project_prefix(contract_name.split("-", 1)[0])
        labels[project].append([int(v) for v in entry.get("targets", [])])
    return dict(labels)


def build_index(graph_dir: Path | str = DEFAULT_GRAPH_DIR) -> tuple[dict[str, list[int]], list[str]]:
    """扫 `*_pyg.pt` → {base: 7 维标签（项目内多合约 targets 并集）}。

    返回 (index, unmatched)：未匹配到标签的 base 收集返回（供 make_splits 写
    unmatched_contracts.txt 透明性报告，不静默丢弃）。
    """
    proj_labels = build_proj_labels()
    index: dict[str, list[int]] = {}
    unmatched: list[str] = []
    for path in sorted(Path(graph_dir).glob("*_pyg.pt")):
        base = path.name.replace("_pyg.pt", "")
        targets_list = proj_labels.get(project_of_base(base))
        if not targets_list:
            unmatched.append(base)
            continue
        label = [0] * 7
        for targets in targets_list:
            for i, value in enumerate(targets[:7]):
                if value:
                    label[i] = 1
        index[base] = label
    return index, unmatched


@dataclass
class Ablation:
    """M5 消融配置（手册 12.3）。

    drop_edges ⊆ {0=CFG_FLOW, 3=DFG_DEP, 4=CALLBACK_RISK}：按 edge_type 过滤（零重跑）；
    feat_variant ∈ {None, 'no-prior', 'no-codebert'}：对应 `_feat_{variant}.pt`。
    """
    drop_edges: set[int] = field(default_factory=set)
    feat_variant: str | None = None


def load_graph(base: str, graph_dir: str = DEFAULT_GRAPH_DIR,
               ab: Ablation | None = None,
               index: dict[str, list[int]] | None = None) -> dict[str, Any]:
    """加载单图训练输入：_pyg.pt 结构 + _feat.pt(x) + 标签 + 边级消融。

    - 断言 base 存在标签（第一道一致性防线）；
    - 断言 x 为 (N,128) 且行数与 node_id 对齐（M3 语义锁死校验）；
    - 边级消融按 edge_type 过滤 edge_index/edge_type（同步，零重跑）。
    """
    ab = ab or Ablation()
    if index is not None:
        assert base in index, f"{base}: label missing (第一道一致性防线：split 内缺标签直接报错)"

    payload = torch.load(f"{graph_dir}/{base}_pyg.pt", map_location="cpu")
    feat_suffix = f"_{ab.feat_variant}" if ab.feat_variant else ""
    x = torch.load(f"{graph_dir}/{base}_feat{feat_suffix}.pt", map_location="cpu")
    assert x.dim() == 2 and x.shape[1] == 128, \
        f"{base}: x must be (N,128) (M3 未跑或语义破坏), got {tuple(x.shape)}"
    assert x.shape[0] == len(payload["node_id"]), \
        f"{base}: feat rows {x.shape[0]} != node_id rows {len(payload['node_id'])}"

    edge_index = payload["edge_index"]
    edge_type = payload["edge_type"]
    if ab.drop_edges:
        drop = torch.tensor(sorted(ab.drop_edges), dtype=torch.long)
        keep = ~torch.isin(edge_type, drop)
        edge_index, edge_type = edge_index[:, keep], edge_type[keep]

    label = torch.tensor(index[base] if index is not None else [0] * 7,
                         dtype=torch.float32)
    return {
        "x": x,
        "edge_index": edge_index,
        "edge_type": edge_type,
        "label": label,
        "name": base,
        "node_id": payload["node_id"],
        "contract": payload["contract"],
        "function": payload["function"],
        "expression": payload["expression"],
        "line_start": payload["line_start"],
    }


def parse_args() -> argparse.Namespace:
    """CLI：--check <base> 单图自检（打印 N/E/type 分布/x 维度/标签）。"""
    parser = argparse.ArgumentParser(description="M5 dataset layer (load/check single graph).")
    parser.add_argument("--check", default=None,
                        help="Base prefix of a single graph to inspect (e.g. nasd_simple_dao__simple_dao).")
    parser.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR,
                        help="Directory containing *_pyg.pt / *_feat.pt.")
    return parser.parse_args()


def main() -> None:
    """单图自检入口：`python scripts/dataset.py --check <base>`。"""
    args = parse_args()
    if not args.check:
        print("usage: python scripts/dataset.py --check <base>")
        return
    index, _ = build_index(args.graph_dir)
    graph = load_graph(args.check, graph_dir=args.graph_dir, index=index)
    type_dist = {}
    for t in graph["edge_type"].tolist():
        type_dist[t] = type_dist.get(t, 0) + 1
    print(f"name      : {graph['name']}")
    print(f"nodes     : {graph['x'].shape[0]}  x.dim : {tuple(graph['x'].shape)}")
    print(f"edges     : {graph['edge_index'].shape[1]}  edge_type dist: "
          f"{ {RELATION_NAMES.get(k, k): v for k, v in sorted(type_dist.items())} }")
    print(f"label     : {graph['label'].tolist()}")


if __name__ == "__main__":
    main()
