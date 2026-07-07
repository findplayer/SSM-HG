#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

import torch
from torch_geometric.data import HeteroData


def parse_args():
    parser = argparse.ArgumentParser(description="Batch convert hetero JSON graphs to PyG HeteroData.")
    parser.add_argument(
        "--in-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/Heterogeneous graph ",
        help="Directory containing *_hetero.json files.",
    )
    parser.add_argument(
        "--out-dir",
        default="/home/saumarez/projects/deep-learning/SSM-HG/2026test/test_ast_generate/Heterogeneous graph-PyG",
        help="Directory to write .pt PyG files.",
    )
    return parser.parse_args()


def build_type_vocab(nodes: List[Dict]) -> Dict[str, int]:
    vocab = {}
    for node in nodes:
        node_type = node.get("cfg_node_type") or "UNKNOWN"
        if node_type not in vocab:
            vocab[node_type] = len(vocab)
    return vocab


def tensorize_nodes(nodes: List[Dict], type_vocab: Dict[str, int]) -> Tuple[Dict[int, int], torch.Tensor, torch.Tensor]:
    id_to_index = {}
    original_ids = []
    features = []

    for idx, node in enumerate(nodes):
        node_id = int(node.get("id"))
        id_to_index[node_id] = idx
        original_ids.append(node_id)

        node_type_id = type_vocab.get(node.get("cfg_node_type") or "UNKNOWN", -1)
        line_start = node.get("line_start")
        line_end = node.get("line_end")
        span = node.get("span")
        expression = node.get("expression") or ""

        line_start_v = float(line_start if line_start is not None else -1)
        line_end_v = float(line_end if line_end is not None else -1)
        has_span_v = 1.0 if isinstance(span, list) and len(span) == 2 else 0.0
        span_len_v = float((span[1] - span[0]) if has_span_v else 0.0)
        expr_len_v = float(len(expression))

        features.append([
            float(node_type_id),
            line_start_v,
            line_end_v,
            has_span_v,
            span_len_v,
            expr_len_v,
        ])

    x = torch.tensor(features, dtype=torch.float32) if features else torch.empty((0, 6), dtype=torch.float32)
    node_ids = torch.tensor(original_ids, dtype=torch.long) if original_ids else torch.empty((0,), dtype=torch.long)
    return id_to_index, x, node_ids


def tensorize_edges(edge_list: List[Dict], id_to_index: Dict[int, int]) -> torch.Tensor:
    pairs = []
    for edge in edge_list:
        src = edge.get("source")
        dst = edge.get("target")
        if src not in id_to_index or dst not in id_to_index:
            continue
        pairs.append((id_to_index[src], id_to_index[dst]))

    if not pairs:
        return torch.empty((2, 0), dtype=torch.long)
    return torch.tensor(pairs, dtype=torch.long).t().contiguous()


def convert_one(json_path: Path, out_dir: Path):
    data = json.loads(json_path.read_text(encoding="utf-8"))

    nodes = data.get("nodes", [])
    edges = data.get("edges", {})
    meta = data.get("meta", {})

    type_vocab = build_type_vocab(nodes)
    id_to_index, x, node_ids = tensorize_nodes(nodes, type_vocab)

    pyg_data = HeteroData()
    pyg_data["cfg_node"].x = x
    pyg_data["cfg_node"].node_id = node_ids

    # Keep raw string attributes for traceability.
    pyg_data["cfg_node"].contract = [node.get("contract") for node in nodes]
    pyg_data["cfg_node"].function = [node.get("function") for node in nodes]
    pyg_data["cfg_node"].expression = [node.get("expression") for node in nodes]

    cfg_flow = tensorize_edges(edges.get("CFG_FLOW", []), id_to_index)
    ast_parent = tensorize_edges(edges.get("AST_PARENT", []), id_to_index)
    ast_parent_same = tensorize_edges(edges.get("AST_PARENT_SAME", []), id_to_index)
    dfg_dep = tensorize_edges(edges.get("DFG_DEP", []), id_to_index)

    pyg_data[("cfg_node", "CFG_FLOW", "cfg_node")].edge_index = cfg_flow
    pyg_data[("cfg_node", "AST_PARENT", "cfg_node")].edge_index = ast_parent
    pyg_data[("cfg_node", "AST_PARENT_SAME", "cfg_node")].edge_index = ast_parent_same
    pyg_data[("cfg_node", "DFG_DEP", "cfg_node")].edge_index = dfg_dep

    pyg_data.graph_name = json_path.stem
    pyg_data.meta = meta
    pyg_data.cfg_node_type_vocab = type_vocab

    out_name = json_path.name.replace("_hetero.json", "_pyg.pt")
    out_path = out_dir / out_name
    torch.save(pyg_data, out_path)

    return {
        "file": json_path.name,
        "out": out_path.name,
        "num_nodes": int(node_ids.numel()),
        "cfg_edges": int(cfg_flow.shape[1]),
        "ast_edges": int(ast_parent.shape[1]),
        "ast_same_edges": int(ast_parent_same.shape[1]),
        "dfg_edges": int(dfg_dep.shape[1]),
    }


def main():
    args = parse_args()
    in_dir = Path(args.in_dir)
    out_dir = Path(args.out_dir)

    out_dir.mkdir(parents=True, exist_ok=True)

    json_files = sorted(in_dir.glob("*_hetero.json"))
    if not json_files:
        print(f"No input files found in: {in_dir}")
        return

    summaries = []
    for json_path in json_files:
        summaries.append(convert_one(json_path, out_dir))

    total_nodes = sum(s["num_nodes"] for s in summaries)
    total_cfg = sum(s["cfg_edges"] for s in summaries)
    total_ast = sum(s["ast_edges"] for s in summaries)
    total_ast_same = sum(s.get("ast_same_edges", 0) for s in summaries)
    total_dfg = sum(s["dfg_edges"] for s in summaries)

    print(f"Converted files: {len(summaries)}")
    print(f"Output dir: {out_dir}")
    print(f"Total nodes: {total_nodes}")
    print(f"Total CFG edges: {total_cfg}")
    print(f"Total AST edges: {total_ast}")
    print(f"Total AST same-cfg edges: {total_ast_same}")
    print(f"Total DFG edges: {total_dfg}")


if __name__ == "__main__":
    main()
