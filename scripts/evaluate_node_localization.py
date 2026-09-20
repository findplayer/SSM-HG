#!/usr/bin/env python3
"""**SolidiFI 层次二**：合成注入漏洞上的**节点排序评估**（大纲 `改II` 5.2 层次二 / 5.5.1）。

三类分数**必须同时报告**（大纲原文），故本脚本对每个合约同时算：

| 分数 | 来源 | 含义 |
| --- | --- | --- |
| $s_v$ | `_m1.json::node_scores` | **静态先验**（M1 规则打分） |
| $a_v$ | `model.forward` 的第 2 个返回值 | **模型**的节点可疑度（图传播之后的） |
| $g_v$ | `|∂z_{G,k}/∂h_v^{(L)}|` | **梯度显著性**（推理期解释，不参与训练） |

指标：**Precision@k / Recall@k / IoU**，$k \in \{5, 10, \lceil 0.1N \rceil\}$。

**梯度显著性的类别归属**（大纲 5.2 新增，本脚本按此实现）：
注入**单一类别**时取该类别的 $g_{v,k}$；注入**多个类别**时取**所有真实注入类别上的最大值**。
另**分开统计**"模型预测正确"与"模型预测错误"的样本（大纲要求区分），因为后者若混在一起，
会让"定位能力"这件事被"分类能力"污染。

⚠ **$g_{v,k}$ 的向量→标量**：$h_v$ 是向量，$|\cdot|$ 在此取 **L2 范数**（对嵌入维求模）。
这是本脚本的**实现选择**（大纲只写了 $|\partial z/\partial h|$），已在 `decisions.md` 中记录。

🔴 **诚实声明**（大纲原文，须随结果一起进论文）：SolidiFI 是**语法级注入**，
$s_v$ 在大多数情况下会**直接命中**注入位置，故本评估主要反映**静态先验的准确性**，
而非图神经网络的深层逻辑发现能力。**不得**据此声称真实漏洞根因定位能力。

用法（从仓库根目录运行）：
  python scripts/evaluate_node_localization.py --corpus main
  python scripts/evaluate_node_localization.py --corpus main --all-seeds
产物：`eval_results/solidifi/node_localization_{main,aug}.json`
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import evaluate as EV                                                   # noqa: E402
import metrics                                                          # noqa: E402
from dataset import Ablation, build_index, collate, load_graph          # noqa: E402

VULN = ["access_control", "arithmetic", "dos", "front_running",
        "reentrancy", "time_manipulation", "uncheck"]
MAPPING = REPO / "products" / "solidifi" / "mapping" / "injection_nodes.json"
SOLIDIFI_GRAPHS = REPO / "products" / "solidifi" / "graphs"
LABELS = REPO / "SolidiFI" / "contract_labels.json"
OUT_DIR = REPO / "eval_results" / "solidifi"
# 语料 → (正典 run 根, 它在 SolidiFI 上的特征树)
CORPORA = {
    "main": (REPO / "runs", REPO / "products" / "solidifi" / "graphs_ft"),
    "aug": (REPO / "runs" / "augmentation", REPO / "products" / "solidifi" / "graphs_ft_aug"),
}
# 语料 → 按「最佳种子」口径 ① seed2 / ② seed1（用户 2026-09-20 裁定）
BEST_SEED = {"main": 2, "aug": 1}


# ------------------------------------------------------------------ 指标
def topk_indices(scores: np.ndarray, k: int) -> np.ndarray:
    """取分数最高的 k 个**下标**（k > N 时取全部）。并列不特殊处理（`argpartition` 的稳定序即可）。"""
    k = min(k, scores.size)
    if k <= 0:
        return np.empty(0, dtype=int)
    return np.argpartition(-scores, k - 1)[:k]


def prf_at_k(scores: np.ndarray, buggy: set[int], k: int) -> dict:
    """单个合约、单个 k 的 P@k / R@k / IoU。`buggy` 为空时返回 None（不计入均值）。"""
    if not buggy:
        return {"k": k, "P": None, "R": None, "IoU": None, "hit": None}
    top = set(int(i) for i in topk_indices(scores, k))
    hit = len(top & buggy)
    union = len(top | buggy)
    return {"k": k,
            "P": hit / max(1, len(top)),
            "R": hit / len(buggy),
            "IoU": hit / union if union else None,
            "hit": hit}


def grad_salience(model, x, ei, et, n_nodes: int, classes: list[int]) -> np.ndarray:
    """$g_{v,k}$：对**每个真实注入类别** k 求 `|∂z_{G,k}/∂h_v^{(L)}|`，再取各类别的**最大值**。

    向量→标量取 **L2 范数**（对嵌入维）。梯度是**推理期**的量，不参与训练、不改任何权重。
    """
    out = model(x, ei, et, batch=None, return_intermediates=True)
    h2 = out["h2"]
    z = out["z"]
    if z.dim() == 1:                       # 单图：[num_classes]
        z = z.unsqueeze(0)
    g = np.zeros(n_nodes, dtype=np.float64)
    for k in classes:
        if k >= z.shape[1]:
            continue
        (grad,) = torch.autograd.grad(z[0, k], h2, retain_graph=True, allow_unused=True)
        if grad is None:
            continue
        g = np.maximum(g, grad.detach().norm(dim=-1).cpu().numpy())
    model.zero_grad(set_to_none=True)
    return g


def sidecar_of(graph_dir: Path, base: str) -> dict:
    """`_m1.json` 的 `node_scores` → 按 `_pyg.pt` 行序对齐的 `s_v` 数组。"""
    m1 = json.loads((graph_dir / f"{base}_m1.json").read_text(encoding="utf-8"))
    ns = m1["node_scores"]
    p = torch.load(graph_dir / f"{base}_pyg.pt", map_location="cpu")
    return np.asarray([float(ns[str(int(i))]) for i in p["node_id"]], dtype=np.float64)


def mean_of(rows: list[dict], key: str):
    vals = [r[key] for r in rows if r.get(key) is not None]
    return {"mean": round(statistics.mean(vals), 6), "std": round(statistics.stdev(vals), 6)
            if len(vals) > 1 else 0.0, "n": len(vals)} if vals else {"mean": None, "std": None, "n": 0}


def evaluate(seed: int, corpus: str, limit: int = 0) -> dict:
    runs_root, tree = CORPORA[corpus]
    run_dir = runs_root / f"seed{seed}"
    graph_dir = tree / f"ss{seed}"
    if not graph_dir.exists():
        raise SystemExit(f"[node] 找不到 SolidiFI 特征树 {graph_dir}；"
                         f"先跑 build_dive_external_set.py --dataset solidifi")
    ckpt = torch.load(run_dir / "best.pt", map_location="cpu")
    config = ckpt["config"]
    if EV.head_of(config) != "multi":
        raise SystemExit(f"[node] {run_dir} 不是七类多标签臂")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    fuser, model = EV.rebuild_models(config, ckpt)
    fuser.to(device).eval()
    model.to(device).eval()

    mapping = json.loads(MAPPING.read_text(encoding="utf-8"))["per_contract"]
    index, unmatched = build_index(graph_dir, label_file=str(LABELS), key_mode="stem")
    ab = EV._load_ablation(config)

    rows, skipped = [], []
    bases = sorted(mapping)
    for base in (bases[:limit] if limit else bases):
        if base not in index:
            skipped.append({"base": base, "why": "标签未匹配"})
            continue
        rec = mapping[base]
        buggy = set(rec["buggy_nodes"])
        if not buggy:
            skipped.append({"base": base, "why": "无可用注入节点（全部映射失败）"})
            continue
        s = load_graph(base, graph_dir=str(graph_dir), ab=ab, index=index, verify_channels="cheap")
        channels, ei, et, batch, _labels = collate([s], training=False, device=device, head="multi")
        x = fuser(channels, batch=batch)
        x = x.detach().requires_grad_(True)          # ← 梯度显著性必须对 h_v^(0) 之后的图求
        with torch.enable_grad():
            z, a, _nl = model(x, ei, et, batch=batch)
            probs = torch.sigmoid(z).detach().cpu().numpy().reshape(-1)
            a_np = a.detach().cpu().numpy().reshape(-1)
            true_cls = [VULN.index(c) for c in rec["classes_from_label"]]
            g_np = grad_salience(model, x, ei, et, int(x.shape[0]), true_cls)
        pred = {VULN[i] for i, v in enumerate(probs >= 0.5) if v}
        # k 的**标签**与**数值**分开：第三个是「节点数的 10%」，逐合约不同，
        # 若用数值当键会得到 "16"/"21" 这类各不相同、无法跨合约聚合的键（首版就是这么炸的）。
        k_specs = [("5", 5), ("10", 10), ("p10", max(1, math.ceil(0.1 * len(a_np))))]
        s_np = sidecar_of(graph_dir, base)          # `_m1.json` 的静态先验（**只读一次**）
        # `a_v` 的增量覆盖节点：TopK 里有几个**不是** s_v 的高分节点（s_v 排名在 50% 之后）
        s_rank = np.argsort(np.argsort(-s_np))      # 0 = s_v 最高
        half = len(s_rank) / 2.0
        inc = {}
        for lbl, k in k_specs:
            top = topk_indices(a_np, k)
            inc[lbl] = int((s_rank[top] >= half).sum())
        rows.append({
            "base": base, "n_nodes": len(a_np), "n_buggy": len(buggy),
            "classes_true": rec["classes_from_label"], "classes_pred": sorted(pred),
            "pred_correct": pred == set(rec["classes_from_label"]),
            "s_v": {lbl: prf_at_k(s_np, buggy, k) for lbl, k in k_specs},
            "a_v": {lbl: prf_at_k(a_np, buggy, k) for lbl, k in k_specs},
            "g_v": {lbl: prf_at_k(g_np, buggy, k) for lbl, k in k_specs},
            "incremental_nodes": inc,
            "probs": {VULN[i]: round(float(v), 4) for i, v in enumerate(probs)},
        })

    def agg(subset: list[dict]) -> dict:
        out = {"n_contracts": len(subset)}
        for name in ("s_v", "a_v", "g_v"):
            out[name] = {lbl: {m: mean_of([r[name][lbl] for r in subset], m)
                               for m in ("P", "R", "IoU")}
                         for lbl in ("5", "10", "p10")}
        return out

    kk = [5, 10, "p10"]
    result = {
        "corpus": corpus, "seed": seed, "run_dir": str(run_dir.relative_to(REPO)),
        "graph_dir": str(graph_dir.relative_to(REPO)),
        "n_contracts_total": len(bases), "n_evaluated": len(rows), "skipped": skipped,
        "labels_unmatched": len(unmatched),
        "all": agg(rows),
        "pred_correct_subset": agg([r for r in rows if r["pred_correct"]]),
        "pred_wrong_subset": agg([r for r in rows if not r["pred_correct"]]),
        "incremental_nodes_mean": {k: round(statistics.mean(
            [r["incremental_nodes"][k] for r in rows]), 4) for k in ("5", "10", "p10")} if rows else {},
        "per_contract": rows,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    return result


def main() -> None:
    ap = argparse.ArgumentParser(description="SolidiFI 层次二：节点排序评估")
    ap.add_argument("--corpus", default="main", choices=sorted(CORPORA))
    ap.add_argument("--seed", type=int, default=-1, help="默认按最佳种子口径（① seed2 / ② seed1）")
    ap.add_argument("--all-seeds", action="store_true", help="三个种子各跑一遍")
    ap.add_argument("--limit", type=int, default=0, help="小样探针：只评前 N 个合约")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    seeds = (0, 1, 2) if args.all_seeds else (
        [args.seed] if args.seed >= 0 else [BEST_SEED[args.corpus]])
    results = []
    for s in seeds:
        t0 = time.perf_counter()
        r = evaluate(s, args.corpus, args.limit)
        r["wall_seconds"] = round(time.perf_counter() - t0, 1)
        a = r["all"]["a_v"]["5"]["P"]["mean"]
        sv = r["all"]["s_v"]["5"]["P"]["mean"]
        print(f"[node] {args.corpus} seed{s}: 评了 {r['n_evaluated']}/{r['n_contracts_total']} 合约；"
              f"P@5  s_v={sv if sv is None else round(sv, 4)} "
              f"a_v={a if a is None else round(a, 4)} "
              f"g_v={r['all']['g_v']['5']['P']['mean']}", flush=True)
        results.append(r)

    out = Path(args.out) if args.out else OUT_DIR / f"node_localization_{args.corpus}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = results[0] if len(results) == 1 else {"corpus": args.corpus, "runs": results}
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[node] → {out}")


if __name__ == "__main__":
    main()
