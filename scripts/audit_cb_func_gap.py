#!/usr/bin/env python3
"""S0：函数级 CodeBERT 通道缺口清单（B1 修复前审计；2026-09-12）。

背景（`docs/cb_func_gapfix_plan.md`）：CFG 节点请求的 `(contract, function)` 键在
`_hetero.json::functions` 表里查不到 → `_cb.pt` 的 func 通道取零向量（node 通道无缺口）。

分类（每个缺失键）：
  1. `alias`      同名条目在表中存在、但 contract 不同（继承函数：Slither 归到派生合约，
                   AST 表归到定义合约）→ 键错位，可补登记；
  2. `legacy_ctor` 名字是本文件声明的合约名（0.4.x 老式构造函数 `function Ownable() public`，
                   被继承时 Slither 用基合约名当函数名）→ 可补登记（2026-09-12 已修，R2）；
  3. `modifier`   名字在同源文件里是 `modifier X` 定义（AST walk 只收 FunctionDefinition）；
  4. `function`   名字在同源文件里有 `function X(` 定义但表中无同名 → 需人工核查；
  5. `none`       源码里也找不到定义 → 不可编码，必须报出（停止条件）。

注：修复前基线 `cb_func_gap.json/md` 由**旧版 classify** 生成（无 `legacy_ctor` 类，该类键当时
归入 `function`）；本类名仅影响后续重跑的可读性，不改任何产物的口径。基线与 `_after` 快照并存备查，
无 tag 重跑会覆写历史基线，故加守卫（需 `--force`）。

输出：
  - `products/alldata/splits/cb_func_gap{tag}.json`（机器可读，含逐图/逐键明细）
  - `docs/cb_func_gap{tag}.md`（人读汇总）

运行（仓库根目录）：`python scripts/audit_cb_func_gap.py`（修复前基线）
     `python scripts/audit_cb_func_gap.py --tag _after`（修复后快照，两份并存备查）
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE = Path("/home/saumarez/projects/deep-learning/SSM-HG")
sys.path.insert(0, str(BASE / "scripts"))
import dataset  # noqa: E402

GRAPHS = Path(dataset.DEFAULT_GRAPH_DIR)
OUT_JSON = BASE / "products/alldata/splits/cb_func_gap.json"
OUT_MD = BASE / "docs/cb_func_gap.md"

def classify(name: str, source: str, same_name_contracts: list[str]) -> str:
    """缺失键分类（优先级：alias > legacy_ctor > modifier > function > none）。"""
    if same_name_contracts:
        return "alias"
    if re.search(r"(?m)^\s*(?:contract|interface|library)\s+" + re.escape(name) + r"\b", source):
        return "legacy_ctor"
    if re.search(r"(?m)^\s*modifier\s+" + re.escape(name) + r"\s*[\(\{]", source):
        return "modifier"
    if re.search(r"(?m)^\s*function\s+" + re.escape(name) + r"\s*\(", source):
        return "function"
    return "none"


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit missing (contract, function) keys.")
    parser.add_argument("--graph-dir", default=str(GRAPHS))
    parser.add_argument("--tag", default="",
                        help="输出文件名后缀（如 _after），用于并存修复前/后快照。")
    parser.add_argument("--force", action="store_true",
                        help="允许覆写已存在的历史快照（无 --tag 时默认拒绝覆写基线）。")
    parser.add_argument("--print", dest="print_only", action="store_true")
    args = parser.parse_args()
    graph_dir = Path(args.graph_dir)
    out_json = OUT_JSON.with_name(f"cb_func_gap{args.tag}.json")
    out_md = OUT_MD.with_name(f"cb_func_gap{args.tag}.md")
    if out_json.exists() and not (args.force or args.print_only):
        print(f"拒绝覆写已存在的快照 {out_json.name}（历史产物）；"
              f"如需覆盖请加 --force，或改用 --tag <后缀> 另存。", file=sys.stderr)
        return 2

    per_graph: dict[str, dict] = {}
    key_rows: dict[tuple[str, str], dict] = {}
    class_nodes = collections.Counter()
    class_keys = collections.Counter()
    total_nodes = total_missing_rows = 0

    for hetero in sorted(graph_dir.glob("*_hetero.json")):
        base = hetero.name.replace("_hetero.json", "")
        data = json.loads(hetero.read_text(encoding="utf-8"))
        table = {(f.get("contract"), f.get("function")) for f in data.get("functions", [])}
        by_name = collections.defaultdict(list)
        for c, f in table:
            by_name[f].append(c)

        source = ""
        src_path = data.get("meta", {}).get("source_path")
        if src_path and Path(src_path).exists():
            source = Path(src_path).read_text(encoding="utf-8", errors="ignore")

        missing_rows = collections.Counter()
        for node in data.get("nodes", []):
            total_nodes += 1
            key = (node.get("contract"), node.get("function"))
            if key in table:
                continue
            total_missing_rows += 1
            missing_rows[key] += 1
            if key not in key_rows:
                cls = classify(str(key[1]), source, by_name.get(key[1], []))
                key_rows[key] = {"contract": key[0], "function": key[1], "class": cls,
                                 "same_name_in_table": sorted(by_name.get(key[1], [])),
                                 "graphs": 0, "node_rows": 0}
                class_keys[cls] += 1
        if missing_rows:
            per_graph[base] = {
                "nodes": len(data.get("nodes", [])),
                "missing_rows": sum(missing_rows.values()),
                "keys": [[c, f] for c, f in sorted(missing_rows)],
            }
            # 逐键聚合按**图**累加一次（2026-09-12 修复：旧版在节点循环内累加，
            # 导致 per-key 的 graphs/node_rows 按行数重复计数；聚合口径不受影响）
            for key, cnt in missing_rows.items():
                key_rows[key]["graphs"] += 1
                key_rows[key]["node_rows"] += cnt
                class_nodes[key_rows[key]["class"]] += cnt

    payload = {
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "graphs_total": len(list(graph_dir.glob("*_hetero.json"))),
        "nodes_total": total_nodes,
        "missing_node_rows": total_missing_rows,
        "missing_rows_share": round(total_missing_rows / total_nodes, 4) if total_nodes else 0,
        "graphs_with_gap": len(per_graph),
        "keys_total": len(key_rows),
        "class_key_counts": dict(class_keys),
        "class_node_row_counts": dict(class_nodes),
        "keys": [dict(key=list(k), **v) for k, v in sorted(key_rows.items())],
        "graphs": per_graph,
    }
    action = {
        "alias": "补登记：按同名定义补 (派生合约, 函数名) 条目",
        "modifier": "补收集：AST walk 增收 ModifierDefinition（kind=modifier）",
        "function": "人工核查：同名定义存在但不入表",
        "none": "不可编码 → 计划停止条件，需裁定",
    }
    print(f"图 {payload['graphs_total']} / 节点 {total_nodes}；缺口 {total_missing_rows} 行"
          f"（{payload['missing_rows_share']:.1%}）/ {len(per_graph)} 图 / {len(key_rows)} 键")
    for cls, n in class_keys.most_common():
        print(f"  {cls:9s} 键 {n:3d}  节点行 {class_nodes[cls]:6d}  → {action[cls]}")

    if args.print_only:
        return
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")

    lines = ["# 函数级 CodeBERT 通道缺口清单（`scripts/audit_cb_func_gap.py` 生成，勿手改）", "",
             f"> 生成时间（UTC）：{payload['created_utc']}；修复计划：`docs/cb_func_gapfix_plan.md`（B1）", "",
             f"- 图 {payload['graphs_total']} / 节点 {total_nodes}；**缺口 {total_missing_rows} 行"
             f"（占节点 {payload['missing_rows_share']:.1%}）**，涉及 **{len(per_graph)} 图**、"
             f"{len(key_rows)} 个去重键。", "",
             "| 类别 | 键数 | 节点行 | 处置 |", "| --- | --- | --- | --- |"]
    for cls, n in class_keys.most_common():
        lines.append(f"| `{cls}` | {n} | {class_nodes[cls]} | {action[cls]} |")
    lines += ["", "## 逐键明细", "", "| contract | function | 类别 | 表中同名的合约 | 涉及图 | 节点行 |",
              "| --- | --- | --- | --- | --- | --- |"]
    for key, info in sorted(key_rows.items(), key=lambda kv: -kv[1]["node_rows"]):
        lines.append(f"| {key[0]} | {key[1]} | {info['class']} | "
                     f"{','.join(info['same_name_in_table']) or '—'} | {info['graphs']} | {info['node_rows']} |")
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"written: {out_json.relative_to(BASE)}")
    print(f"written: {out_md.relative_to(BASE)}")


if __name__ == "__main__":
    main()
