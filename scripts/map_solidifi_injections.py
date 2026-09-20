#!/usr/bin/env python3
"""把 SolidiFI 的**注入位置**（`buggy_logs/*.csv` 的行号）映射到 **SlithIR CFGNode**（大纲 `改II` 5.2 层次二）。

**为什么需要它**：SolidiFI 给的是**语法级注入的行号**（`loc,length,bug type,approach`），
而模型输出的是**节点级**可疑度 $a_v$。两者必须先对齐，才能做 P@k/R@k/IoU。

**映射规则**（大纲 5.2 / 手册 §10.2 第 9 条，逐字）：
  按 `loc` 落到 `line_start ≤ loc ≤ line_end` 的 CFGNode；
  **多节点命中取行区间最小者**（`line_end - line_start` 最小；并列取节点 id 小者）；
  映射不上的注入**剔除并报告数量与占比**（不静默丢弃）。

**类归属（`bug type` → 本文七类）**：映射表见下。它**不是猜的**——用它对 350 个合约反推
合约级标签，与 `SolidiFI/contract_labels.json` **逐条完全一致（350/350）**，
故可证这就是生成本数据集标签的那张表。⚠ SolidiFI **不含 `dos`**（该组未注入），须披露。

**节点下标 vs 节点 id**：产物里的 `node_index` 是 **`_pyg.pt` / `_feat.pt` 的行下标**
（$a_v$ 就是这个顺序，第 i 个元素 ↔ `node_id[i]`）；`node_id` 是 CFG 里的原始编号。
两者**不等价**（已有实测：`node_id` 在本语料里恰好是 1..N，但**不得**依赖这一点）。

用法（从仓库根目录运行）：
  python scripts/map_solidifi_injections.py
产物：`products/solidifi/mapping/injection_nodes.json`
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

SOLIDIFI = REPO / "SolidiFI"
LABELS = SOLIDIFI / "contract_labels.json"
LOGS = SOLIDIFI / "buggy_logs"
GRAPHS = REPO / "products" / "solidifi" / "graphs"
OUT = REPO / "products" / "solidifi" / "mapping" / "injection_nodes.json"

VULN = ["access_control", "arithmetic", "dos", "front_running",
        "reentrancy", "time_manipulation", "uncheck"]

# `bug type`（SolidiFI 词表，9 种取值）→ 本文七类。
# 复合类型（`Re+AC0-erntrancy` / `Unhandled+AC0-Exceptions`）里的 `+AC0` 是 SolidiFI 的
# 访问控制变体后缀，按其**主体类型**归类；该归类已被"反推 350/350 全对"证实。
BUGTYPE_TO_CLASS = {
    "tx.origin": "access_control",
    "Overflow-Underflow": "arithmetic",
    "TOD": "front_running",
    "Re-erntrancy": "reentrancy",
    "Re+AC0-erntrancy": "reentrancy",
    "Timestamp-Dependency": "time_manipulation",
    "Unhandled-Exceptions": "uncheck",
    "Unchecked-Send": "uncheck",
    "Unhandled+AC0-Exceptions": "uncheck",
}
# `1_buggy_1.sol` → `1_BugLog_1.csv`（前缀 + `_buggy_` → `_BugLog_`）
LOG_OF_STEM = lambda stem: re.sub(r"_buggy_", "_BugLog_", stem)


def map_range(lo: int, hi: int, line_start: list, line_end: list) -> tuple[int | None, int]:
    """注入**行域** `[lo, hi]` → (最佳节点下标, 重叠候选数)。取行区间**最小**者；并列取下标小者。

    🔴 **为什么是"行域"而不是单个 `loc`**（2026-09-20 实测更正，`decisions.md` §40）：
    日志的 `loc` 是**注入代码块的首行**，`length` 给出块的长度 ⇒ 块覆盖 `loc .. loc+length-1`。
    实测 `1_buggy_1`：日志 `loc=22,length=4` → 源码 22–25 行是
    `function transferTo_txorigin7(...) {` / `require(tx.origin == owner_txorigin7);` / `to.call.value(amount);` / `}`
    —— **`loc` 那一行是函数签名，真正的漏洞语句在 `loc+1`**。
    若只按单点 `loc` 落点（手册 §10.2 第 9 条的原始措辞），命中的是 **ENTRYPOINT 节点**：
    实测 `1_buggy_1` 的 18 个"注入节点"**全部是 ENTRYPOINT**，而模型/先验的高分节点全是 EXPRESSION
    ⇒ 三类分数 P@5 全为 0，评估结果是**人为造出来的**。`length` 字段本就是为此提供的，不用即错。
    """
    best, best_span, n = None, None, 0
    for i, (a, b) in enumerate(zip(line_start, line_end)):
        if a is None or b is None:
            continue
        overlap = min(b, hi) - max(a, lo)
        if overlap < 0:                      # 不重叠（端点相接触不算——行域是闭区间）
            continue
        n += 1
        span = b - a
        if best_span is None or span < best_span:
            best, best_span = i, span
    return best, n


def main() -> None:
    ap = argparse.ArgumentParser(description="SolidiFI 注入位置 → CFG 节点映射")
    ap.add_argument("--graphs", default=str(GRAPHS))
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    graphs = Path(args.graphs)
    bases = sorted(p.name[: -len("_pyg.pt")] for p in graphs.glob("*_pyg.pt"))
    if not bases:
        raise SystemExit(f"[map] {graphs} 下没有 `_pyg.pt`——先跑 "
                         f"`build_dive_external_set.py --dataset solidifi`")
    # 标签文件的 `contract_name` 带 `.sol`（`1_buggy_1.sol`），而图 base 是 stem（`1_buggy_1`）
    labels = {Path(e["contract_name"]).stem: e["targets"]
              for e in json.loads(LABELS.read_text("utf-8"))}

    absent = [b for b in bases if b not in labels]
    if absent:
        raise SystemExit(f"[map] {len(absent)}/{len(bases)} 张图在标签文件里找不到，例：{absent[:5]}")

    per, agg = {}, collections.Counter()
    for base in bases:
        p = torch.load(graphs / f"{base}_pyg.pt", map_location="cpu")
        nid = list(p["node_id"])
        # ⚠ `_pyg.pt` **只有 `line_start`**，`line_end` 在 `_hetero.json` 里
        #   （大纲的判据是 `line_start ≤ loc ≤ line_end`，两个都要）。
        #   两者的节点顺序必须逐位一致——不一致就直接停，绝不按位置硬凑。
        h = json.loads((graphs / f"{base}_hetero.json").read_text(encoding="utf-8"))
        if [n["id"] for n in h["nodes"]] != nid:
            raise SystemExit(f"[map] {base}: `_hetero.json` 与 `_pyg.pt` 的节点顺序不一致——不能按位置对齐")
        ls = [n["line_start"] for n in h["nodes"]]
        le = [n["line_end"] for n in h["nodes"]]
        log = LOGS / f"{LOG_OF_STEM(base)}.csv"
        if not log.exists():
            raise SystemExit(f"[map] {base} 找不到注入日志 {log}")
        inj, unmapped = [], []
        for row in csv.DictReader(log.open(encoding="utf-8")):
            loc = int(row["loc"])
            bt = row["bug type"].strip()
            cls = BUGTYPE_TO_CLASS.get(bt)
            if cls is None:
                raise SystemExit(f"[map] {base}: 未知 bug type {bt!r}——"
                                 f"请先确认它属于本文哪一类（不得猜）")
            length = int(row["length"])
            lo, hi = loc, loc + max(0, length - 1)
            idx, n = map_range(lo, hi, ls, le)
            rec = {"loc": loc, "length": length, "line_lo": lo, "line_hi": hi,
                   "bug_type": bt, "class": cls}
            if idx is None:
                unmapped.append(rec)
                agg["unmapped"] += 1
            else:
                inj.append({**rec, "node_index": idx, "node_id": int(nid[idx]),
                            "line_start": ls[idx], "line_end": le[idx], "n_candidates": n})
                agg["mapped"] += 1
                if n > 1:
                    agg["multi_candidate"] += 1
        buggy = sorted({r["node_index"] for r in inj})
        true_cls = sorted({VULN[i] for i, x in enumerate(labels[base]) if x})
        # 自校验：日志推出的类别集合必须与合约标签一致（不一致说明映射表或样本有问题）
        log_cls = sorted({r["class"] for r in inj} | {r["class"] for r in unmapped})
        per[base] = {"n_nodes": len(nid), "injections": inj, "unmapped": unmapped,
                     "buggy_nodes": buggy, "n_buggy_nodes": len(buggy),
                     "classes_from_log": log_cls, "classes_from_label": true_cls,
                     "classes_consistent": log_cls == true_cls}
        agg["contracts"] += 1
        if not per[base]["classes_consistent"]:
            agg["class_mismatch"] += 1

    payload = {
        "protocol": {
            "rule": "注入**行域** [loc, loc+length-1] 与 CFGNode 的 [line_start,line_end] **重叠**者；"
                    "多命中取行区间最小者（并列取下标小者）。"
                    "⚠ 用行域而非单点 loc：loc 是注入块首行（函数签名），漏洞语句在 loc+1",
            "why_range": "见 decisions.md §40：只按单点 loc 会全部命中 ENTRYPOINT，评估结果作废",
            "unmapped": "剔除并报告数量与占比（大纲 5.2 层次二）",
            "bugtype_to_class": BUGTYPE_TO_CLASS,
            "note": "SOLIDiFI 不含 dos 类（该组未注入）",
        },
        "summary": dict(agg),
        "unmapped_ratio": round(agg["unmapped"] / max(1, agg["mapped"] + agg["unmapped"]), 6),
        "per_contract": per,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"[map] {agg['contracts']} 合约；注入 {agg['mapped'] + agg['unmapped']} 条："
          f"映射成功 {agg['mapped']}、失败 {agg['unmapped']} "
          f"（{100 * payload['unmapped_ratio']:.2f}%）")
    print(f"[map] 多候选命中 {agg['multi_candidate']} 条；类别自校验不一致 {agg['class_mismatch']} 个")
    print(f"[map] → {out}")
    if agg["class_mismatch"]:
        bad = [b for b, v in per.items() if not v["classes_consistent"]][:5]
        raise SystemExit(f"[map] 🔴 {agg['class_mismatch']} 个合约的日志类别与标签不符，例：{bad}")


if __name__ == "__main__":
    main()
