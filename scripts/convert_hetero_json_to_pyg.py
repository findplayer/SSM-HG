#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import torch


def parse_args():
    """解析 CLI 参数：--in-dir/--out-dir（默认均为 products/alldata/graphs）。"""
    parser = argparse.ArgumentParser(description="Batch convert hetero JSON graphs to PyG dict files (*_pyg.pt).")
    base = "/home/saumarez/projects/deep-learning/SSM-HG"
    parser.add_argument(
        "--in-dir",
        default=f"{base}/products/alldata/graphs",
        help="Directory containing *_hetero.json files.",
    )
    parser.add_argument(
        "--out-dir",
        default=f"{base}/products/alldata/graphs",
        help="Directory to write .pt PyG files (same dir as *_hetero.json by default).",
    )
    return parser.parse_args()


# 关系编号固定（手册 7.7）：0=CFG_FLOW, 1=AST_PARENT, 2=AST_PARENT_SAME, 3=DFG_DEP, 4=CALLBACK_RISK；
# 5=CALLBACK_RISK_REV **仅 `--callback-rev` 变体存在**（大纲改II 第 160/220 行；
# 「若添加反向边则按实际关系数统计」⇒ 它是**独立关系**，不是"同一关系加反向边"）。
RELATION_IDS = {
    "CFG_FLOW": 0,
    "AST_PARENT": 1,
    "AST_PARENT_SAME": 2,
    "DFG_DEP": 3,
    "CALLBACK_RISK": 4,
    "CALLBACK_RISK_REV": 5,
}
# 正典语料的关系数（无 REV 键时的兜底）
DEFAULT_NUM_RELATIONS = 5


def num_relations_of(edges: dict) -> int:
    """关系数 = 1 + **实际出现在该图 edges 里的**已知关系最大编号。

    🔴 **不能按 `RELATION_IDS` 的最大编号（恒 6）算**：正典语料没有 `CALLBACK_RISK_REV` 键，
    按常量算会把它也写成 6 ⇒ RGCN 多出一组**永远收不到消息的基**。这不会报错，
    只会静默改变参数量与初始化（`decisions.md` §28/§31.3 同一类"不报错的错"）。

    ⚠ 判据是「**键存在**」而非「边非空」：变体图里有的图可能一条 REV 边都没有（该图本就
    没有 CALLBACK_RISK 边），但整个语料的关系空间必须一致——否则同一语料里
    `num_relations` 会在 5/6 之间摇摆，训练侧的一致性断言会直接拒绝。
    """
    known = [RELATION_IDS[k] for k in edges if k in RELATION_IDS]
    return (1 + max(known)) if known else DEFAULT_NUM_RELATIONS


def convert_one(json_path: Path, out_dir: Path):
    """单个 _hetero.json → _pyg.pt dict（x 为 N×1 占位，M3 后替换 128 维）。

    遇到未知节点 id 的边时删除残留产物并抛错（结构损坏快速失败）。
    """
    data = json.loads(json_path.read_text(encoding="utf-8"))

    nodes = data.get("nodes", [])
    edges = data.get("edges", {})

    id_to_index = {str(node["id"]): idx for idx, node in enumerate(nodes)}

    edge_pairs = []
    edge_types = []
    rel_counts = {}
    dropped_edges = 0
    for rel_name, rel_id in RELATION_IDS.items():
        count = 0
        for edge in edges.get(rel_name, []) or []:
            src = edge.get("source")
            dst = edge.get("target")
            if str(src) not in id_to_index or str(dst) not in id_to_index:
                dropped_edges += 1
                continue
            edge_pairs.append((id_to_index[str(src)], id_to_index[str(dst)]))
            edge_types.append(rel_id)
            count += 1
        rel_counts[rel_name] = count

    num_nodes = len(nodes)
    payload = {
        # M3 之后替换成 128 维 h_v^(0)
        "x": torch.zeros(num_nodes, 1, dtype=torch.float32),
        # 关系数由图产物自述（训练/评估侧 `meta.get("num_relations", 5)` 回读）。
        # ⚠ 正典 `_pyg.pt` 早于本字段，**不因这次改动而变**（那两个分支都不含 REV 键，
        #   值仍为 5，且旧文件靠 `.get` 兜底）——本字段只在**新建**的产物里出现。
        "num_relations": num_relations_of(edges),
        "edge_index": (
            torch.tensor(edge_pairs, dtype=torch.long).t().contiguous()
            if edge_pairs
            else torch.empty((2, 0), dtype=torch.long)
        ),
        "edge_type": (
            torch.tensor(edge_types, dtype=torch.long)
            if edge_types
            else torch.empty((0,), dtype=torch.long)
        ),
        "node_id": [node["id"] for node in nodes],
        "contract": [node.get("contract") for node in nodes],
        "function": [node.get("function") for node in nodes],
        "expression": [node.get("expression") for node in nodes],
        "line_start": [node.get("line_start") for node in nodes],
        "label": torch.zeros(7),   # M5 再填多热标签
    }

    if dropped_edges:
        stale_output = out_dir / json_path.name.replace("_hetero.json", "_pyg.pt")
        stale_output.unlink(missing_ok=True)
        raise ValueError(f"{json_path}: dropped {dropped_edges} edges with unknown node IDs")

    out_name = json_path.name.replace("_hetero.json", "_pyg.pt")
    out_path = out_dir / out_name
    torch.save(payload, out_path)

    result = {"file": json_path.name, "out": out_path.name, "num_nodes": num_nodes}
    result["dropped_edges"] = dropped_edges
    result.update({f"{name}_edges": count for name, count in rel_counts.items()})
    return result


def main():
    """批量转换全部 *_hetero.json 并打印各关系边总数（回归用）。"""
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

    print(f"Converted files: {len(summaries)}")
    print(f"Output dir: {out_dir}")
    print(f"Total nodes: {sum(s['num_nodes'] for s in summaries)}")
    for rel_name in RELATION_IDS:
        print(f"Total {rel_name} edges: {sum(s.get(f'{rel_name}_edges', 0) for s in summaries)}")


if __name__ == "__main__":
    main()
