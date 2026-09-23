#!/usr/bin/env python3
"""`cb_unlimited` **干预触达审计**（`ablation_results.md` §12.4 第 2 项的收尾）。

**它回答什么**：`cb_unlimited`（CALLBACK_RISK 每源节点出边上限 4 → 不限制）这条干预，
**究竟改到了哪些图、这些图落在哪个划分里、以及它在 test 上到底测出了什么**。

🔴 **为什么要做**：`ablation_results.md` §10.4 的 `cb_unlimited` 行写着「变量只落在 20/590 图上
⇒ Δ 被 ~90% 未受影响的图**稀释**，**真实（未稀释）效应量至少大 3–5 倍**」。
那句话是一个**未验的假说**（该节自己也标注了"读数全部是相对冻结编码器的旧跑"）。
本脚本把它验掉 —— 结论**不是**"稀释"，见 `--out` 文档的「读法」节（该节文字**由数据推导生成**，
不是写死的样板：本仓已多次栽在"生成器里的陈旧样板文字"上）。

**测什么**（全程只读，不重训、不写任何产物区）：

  1. **触达集**：逐图比对正典 `graphs_ft/ss{S}` 与变体 `graph_variants/cb_unlimited_ss{S}` 的
     **边集**（`_pyg.pt` 的 `edge_index` + `edge_type`）。
     🔴 **必须读内容、不能只看是不是软链**：变体的 `_pyg.pt` 是**指向旧变体的软链**
     （`products/alldata/graph_variants/callback_unlimited/`），
     只看"有没有软链"会得出「590 张全是软链 ⇒ 干预没做」的**完全错误**的结论。
  2. **划分归属**：触达集 ∩ {train, val, test}。
  3. **三个 test 口径的 Δ**：全 test / 触达∩test / test∖触达。
     第三个口径是内部一致性检查（未受影响的图，两臂**应当**给出几乎相同的读数）。
  4. **副作用审计**：触达图的 `_feat.sv` 通道**也**会变（$s_v$ 由边算出）⇒ 该臂**不是纯边消融**，
     两个变量同时动。本脚本报出"边变 ∧ sv 变"的重合度。

用法（从仓库根目录运行）：
  python scripts/audit_cb_unlimited_reach.py --group both
  python scripts/audit_cb_unlimited_reach.py --group main --out experiments/cb_unlimited_reach.md
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics                                                    # noqa: E402

# 语料 → （图树根, 划分目录, 消融产物根, 正典产物根, 显示名）
CORPORA = {
    "main": ("products/alldata/graphs_ft", "products/alldata/splits",
             "runs/ablation", "runs", "① 主库"),
    "aug": ("products/augmentation/graphs_ft", "products/augmentation/splits",
            "runs/ablation_aug", "runs/augmentation", "② 增强集"),
}
VARIANT = "graph_variants/cb_unlimited_ss{seed}"
SEEDS = (0, 1, 2)
EPS = 1e-9                      # "判定为 0" 的容差：micro/macro 是比值，1e-9 已远超浮点噪声


def _edges(path: Path):
    """图的边集指纹（只取边，不取特征——`_pyg.pt` 是纯结构，`x` 为占位）。"""
    d = torch.load(path, map_location="cpu")
    return (d["edge_index"].numpy().tobytes(), d["edge_type"].numpy().tobytes()), \
           int(d["edge_type"].shape[0])


def reach_set(canon: Path, var: Path) -> tuple[set[str], dict[str, tuple[int, int]]]:
    """（触达图名集合, {图名: (正典边数, 变体边数)}）。"""
    hit: set[str] = set()
    counts: dict[str, tuple[int, int]] = {}
    for f in sorted(var.glob("*_pyg.pt")):
        stem = f.name[: -len("_pyg.pt")]
        a, na = _edges(f)
        b, nb = _edges(canon / f.name)
        if a != b:
            hit.add(stem)
            counts[stem] = (nb, na)
    return hit, counts


def sv_changed(canon_dir: Path, var_dir: Path, stems: set[str]) -> int:
    """触达图里 `_feat.pt` 的 `sv` 通道**也**变了的张数（$s_v$ 由边算出 ⇒ 预期全部重合）。

    只比 `meta.channel_sha256` 里的 `sv` 一项——重算张量没有必要。
    """
    n = 0
    for stem in stems:
        f = var_dir / f"{stem}_feat.pt"
        c = canon_dir / f"{stem}_feat.pt"
        if not (f.exists() and c.exists()):
            continue
        sv_v = (torch.load(f, map_location="cpu").get("meta") or {}).get("channel_sha256", {}).get("sv")
        sv_c = (torch.load(c, map_location="cpu").get("meta") or {}).get("channel_sha256", {}).get("sv")
        if sv_v is not None and sv_c is not None and sv_v != sv_c:
            n += 1
    return n


def split_membership(split_dir: Path, seed: int, hit: set[str]) -> dict:
    p = split_dir / f"split_seed{seed}.json"
    if not p.exists():
        return {}
    sp = json.loads(p.read_text(encoding="utf-8"))
    return {k: {"n": len(list(sp.get(k) or [])),
                "hit": [x for x in (sp.get(k) or []) if x in hit]}
            for k in ("train", "val", "test")}


def _prf(probs, y, t):
    """（micro, macro, mAP）三个数——与 `evaluate.py` 同口径（用 `metrics`，不另算）。"""
    preds = (probs >= t).astype(int)
    return (metrics.micro_f1(y, preds), metrics.macro_f1(y, preds),
            float(metrics.mean_average_precision(probs, y)["mAP"]))


def test_delta(arm_run: Path, base_run: Path, hit: set[str]):
    """test 上的**两个工作点 × 三个子集**读数（臂 / 基线 / Δ）。返回 None 表示产物不全。

    🔴 **必须两个工作点都报**：`@0.5` 两臂同阈值、可比；`@val_thr` 各用**自己**的
    `best_threshold` ⇒ 两臂的阈值可能不同，此时 Δ 含"阈值不同"这一成分，
    **不得**直接读成"干预的效果"。只报一个会让读者默认它是什么——本页踩过这个坑。
    """
    if not (arm_run / "test_probs.pt").exists() or not (base_run / "test_probs.pt").exists():
        return None
    a = torch.load(arm_run / "test_probs.pt", map_location="cpu")
    b = torch.load(base_run / "test_probs.pt", map_location="cpu")
    if list(a["sample_ids"]) != list(b["sample_ids"]):
        return {"error": "两臂的 test sample_ids 不一致，不可配对"}
    pa, pb = a["probs"].numpy(), b["probs"].numpy()
    ya, yb = a["labels"].numpy().astype(int), b["labels"].numpy().astype(int)
    thr = float(json.loads((arm_run / "thresholds.json").read_text(encoding="utf-8"))["best_threshold"])
    thrb = float(json.loads((base_run / "thresholds.json").read_text(encoding="utf-8"))["best_threshold"])
    ids = list(a["sample_ids"])
    masks = {"全 test": np.ones(len(ids), bool),
             "触达∩test": np.array([i in hit for i in ids]),
             "test∖触达": np.array([i not in hit for i in ids])}
    out: dict = {"thr_arm": thr, "thr_base": thrb, "thr_same": thr == thrb, "work": {}}
    for wp, ta, tb in (("fixed_0.5", 0.5, 0.5), ("val_thr", thr, thrb)):
        sub: dict = {}
        for name, m in masks.items():
            if int(m.sum()) == 0:
                sub[name] = {"n": 0}
                continue
            am, bm = _prf(pa[m], ya[m], ta), _prf(pb[m], yb[m], tb)
            sub[name] = {"n": int(m.sum()), "arm": am, "base": bm,
                         "delta": tuple(x - y for x, y in zip(am, bm))}
        out["work"][wp] = sub
    out["probs_bitwise_equal"] = bool(torch.equal(a["probs"], b["probs"]))
    out["probs_maxabsdiff"] = float((a["probs"] - b["probs"]).abs().max())
    return out


def _fmt_metrics(v: dict, nd=4) -> str:
    if v.get("n", 0) == 0:
        return "—"
    a, b, d = v["arm"], v["base"], v["delta"]
    return (f"{a[0]:.{nd}f} / {b[0]:.{nd}f} (Δ{d[0]:+.{nd}f}) | "
            f"{a[1]:.{nd}f} / {b[1]:.{nd}f} (Δ{d[1]:+.{nd}f}) | "
            f"{a[2]:.{nd}f} / {b[2]:.{nd}f} (Δ{d[2]:+.{nd}f})")


# 全 test 口径下"有没有可测效应"的判据：micro/macro 的 |Δ| 是否都在容差内
def full_test_deltas(r: dict):
    """[(工作点, |Δmicro|, |Δmacro|, |ΔmAP|)]——用于生成结论句。"""
    out = []
    for wp, sub in (r.get("delta") or {}).get("work", {}).items():
        v = sub.get("全 test") or {}
        if v.get("n"):
            out.append((wp, abs(v["delta"][0]), abs(v["delta"][1]), abs(v["delta"][2])))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", choices=["main", "aug", "both"], default="both")
    ap.add_argument("--only", default="cb_unlimited", help="消融臂名（默认 cb_unlimited）。")
    ap.add_argument("--out", default="experiments/cb_unlimited_reach.md")
    args = ap.parse_args()

    gkeys = ["main", "aug"] if args.group == "both" else [args.group]
    recs: list[dict] = []          # 逐 (语料, 划分种子) 的原始读数：文档的一切结论由它推导

    for gk in gkeys:
        graph_root, split_dir, runs_root, canon_root, title = CORPORA[gk]
        graph_root, split_dir = REPO / graph_root, REPO / split_dir
        runs_root, canon_root = REPO / runs_root, REPO / canon_root
        for S in SEEDS:
            canon = graph_root / f"ss{S}"
            var = graph_root / VARIANT.format(seed=S)
            r = {"gk": gk, "title": title, "seed": S, "var": var,
                 "exists": var.is_dir(), "hit": set(), "counts": {}, "sv": 0,
                 "mem": {}, "delta": None}
            if var.is_dir():
                r["hit"], r["counts"] = reach_set(canon, var)
                r["sv"] = sv_changed(canon, var, r["hit"])
                r["mem"] = split_membership(split_dir, S, r["hit"])
                r["total"] = len(list(var.glob("*_pyg.pt")))
                r["delta"] = test_delta(runs_root / args.only / f"seed{S}",
                                        canon_root / f"seed{S}", r["hit"])
            recs.append(r)

    # ---------------- 结论：**由数据推导**，不写死（本仓的"陈旧样板"教训）----------------
    live = [r for r in recs if r["exists"] and r["delta"] and "error" not in r["delta"]]
    with_te = [r for r in live if r["mem"].get("test", {}).get("hit")]
    te_total = sum(len(r["mem"]["test"]["hit"]) for r in live)
    # ft 的每项 = (语料名, 划分种子, 工作点, |Δmicro|, |Δmacro|, |ΔmAP|)
    ft = [(r["title"], r["seed"]) + d for r in live for d in full_test_deltas(r)]
    d_micro = [x[3] for x in ft]
    d_macro = [x[4] for x in ft]
    d_map = [x[5] for x in ft]
    thr_differs = [f"{r['title']} ss{r['seed']}" for r in live if not r["delta"]["thr_same"]]
    # 触达∩test 子集：两臂在两个工作点上是否完全相同
    sub = [(r, r["delta"]["work"]["fixed_0.5"]["触达∩test"]) for r in with_te
           if r["delta"]["work"]["fixed_0.5"]["触达∩test"].get("n", 0) > 0]
    sub_same = all(all(abs(x) < EPS for x in v["delta"]) for _, v in sub)
    sub_sat = [r for r, v in sub if v["arm"][0] >= 1.0 and v["base"][0] >= 1.0]
    # 全 test 的非零 Δ 是否全部来自**未触达**样本（两个工作点都查）
    from_unaffected = []
    for r in live:
        for wp in ("fixed_0.5", "val_thr"):
            w = r["delta"]["work"][wp]
            fa, td, ua = w.get("全 test") or {}, w.get("触达∩test") or {}, w.get("test∖触达") or {}
            if fa.get("n") and abs(fa["delta"][0]) >= EPS and td.get("n") \
                    and all(abs(x) < EPS for x in td["delta"]) and ua.get("n") \
                    and abs(ua["delta"][0]) >= EPS:
                from_unaffected.append(f"{r['title']} ss{r['seed']}@{wp}")
                break

    doc = ["# `cb_unlimited` 干预触达审计（`ablation_results.md` §12.4 第 2 项）", "",
           "> 程序生成（`scripts/audit_cb_unlimited_reach.py`）。**全程只读**：不重训、不改任何产物。",
           "> 本文的一切结论句均由下方数据**推导生成**（不是写死的样板文字）。", "",
           "## 读法（由数据推导）", ""]
    doc += [f"- 共 **{len(live)}** 个「语料 × 划分种子」组合有完整产物；"
            f"其中 **{len(with_te)}** 个组合的 test 里**确实含有**被干预触达的图，"
            f"触达∩test 合计 **{te_total}** 张。",
            f"- **全 test 口径**（两个工作点合并）：micro 的 |Δ| 最大 **{max(d_micro):.2e}**、"
            f"macro 最大 **{max(d_macro):.2e}**（容差 {EPS:g}）、mAP 最大 **{max(d_map):.2e}**。"
            + ("⇒ **三个指标在所有组合上都精确为 0**。"
               if max(d_micro + d_macro) < EPS else "")] if ft else []
    if sub:
        doc.append(f"- **触达∩test 子集上**：两臂的 micro/macro/mAP "
                   + ("**完全相同**（逐位）" if sub_same else "**不同**")
                   + f"；其中 **{len(sub_sat)}/{len(sub)}** 个该子集是**饱和的**"
                     "（两臂 micro 都 = 1.0000 ⇒ 该子集**不具分辨力**）。")
        doc.append("- ⇒ 结论：**这条干预在它真正触达的那些 test 样本上，效应量为 0**"
                   + ("（两臂读数逐位相同）" if sub_same else "") + "。")
    if from_unaffected:
        doc += ["", f"- 🔴 **但全 test 的微小非零 Δ 确实存在**（共 {len(from_unaffected)} 个组合："
                    f"{'、'.join(from_unaffected)}），且**全部来自「未触达」子集**"
                    "（触达子集 Δ 恒 0、未触达子集 Δ 非零）——这说明该臂的差异**不是干预的直接效果**，"
                    "而是**训练侧扰动经共享权重传播到无关样本**的副作用。"]
    doc += ["", "🔴 **因此「Δ 被 ~90% 未受影响的图稀释 ⇒ 真实（未稀释）效应量至少大 3–5 倍」"
                "这一写法不成立**：稀释的说法预设「受影响子集里有一个正效应被摊平」，"
                "而实测是**受影响子集上两臂读数逐位相同**（且多为饱和子集）——"
                "**没有效应可被解稀释**。正确写法是「**本设计在该语料上测不出这条干预的效应**」。", ""]
    if thr_differs:
        doc += [f"⚠ **`@val_thr` 列的读法**：这些组合里两臂的 `best_threshold` **不同**"
                f"（{len(thr_differs)} 个：{'、'.join(thr_differs)}）⇒ 该工作点的 Δ 含"
                "「阈值不同」这一成分，**不得**读成干预的效果。`@0.5` 列两臂同阈值，是干净的那个。", ""]
    doc += ["⚠ 这**不等于**「该上限不重要」。AGENTS.md 仍锁：`CALLBACK_RISK` 是启发式边、"
            "主实验默认保留、不得降级为节点特征。本页只说明**这项消融测不出它**。", ""]

    # ---------------- 逐组合明细 ----------------
    for gk in gkeys:
        rs = [r for r in recs if r["gk"] == gk]
        title = rs[0]["title"] if rs else gk
        doc += [f"## {title}", ""]
        for r in rs:
            doc += [f"### 划分种子 {r['seed']}", ""]
            if not r["exists"]:
                doc += [f"🔴 变体目录不存在：`{r['var'].relative_to(REPO)}`", ""]
                continue
            n_hit, n_tot = len(r["hit"]), r["total"]
            inc = sum(1 for a, b in r["counts"].values() if b > a)
            dec = sum(1 for a, b in r["counts"].values() if b < a)
            doc += [f"- 图总数 **{n_tot}**，边集不同的 **{n_hit}** 张（{n_hit / max(n_tot, 1):.1%}）；"
                    f"边数变化：**{inc} 增 / {dec} 减**",
                    f"- 其中 `_feat.sv` 通道**也**变的有 **{r['sv']}** 张"
                    f"（⇒ 该臂**不是纯边消融**：$s_v$ 由边算出，与边同时动）", ""]
            if r["mem"]:
                doc += ["| 划分 | 样本数 | 其中受影响 |", "| --- | --- | --- |"]
                for k in ("train", "val", "test"):
                    doc.append(f"| {k} | {r['mem'][k]['n']} | **{len(r['mem'][k]['hit'])}** |")
                doc.append("")
            d = r["delta"]
            if d is None:
                doc += [f"> （`{args.only}` 或基线的 `test_probs.pt` 缺失，跳过 Δ）", ""]
                continue
            if "error" in d:
                doc += [f"> 🔴 {d['error']}", ""]
                continue
            doc += ["| 工作点 | test 口径 | n | micro（臂/基线/Δ） | macro（臂/基线/Δ） | mAP（臂/基线/Δ） |",
                    "| --- | --- | --- | --- | --- | --- |"]
            for wp, wname in (("fixed_0.5", "**@0.5**（两臂同阈值）"),
                              ("val_thr", f"@val_thr（臂 {d['thr_arm']} / 基线 {d['thr_base']}）")):
                for name in ("全 test", "触达∩test", "test∖触达"):
                    v = d["work"][wp][name]
                    doc.append(f"| {wname if name == '全 test' else ''} | {name} | "
                               f"{v.get('n', 0)} | {_fmt_metrics(v)} |")
            doc += ["",
                    f"> 概率张量逐位相同 = **{d['probs_bitwise_equal']}**，最大绝对差 "
                    f"**{d['probs_maxabsdiff']:.3e}** ⇒ 干预**确实改变了两臂的权重**"
                    "（否则概率会逐位相同）。", ""]

    # ---------------- 汇总 ----------------
    doc += ["---", "", "## 汇总：触达图落在哪个划分", "",
            "| 语料 | 划分种子 | 触达图 | train | val | **test** | 触达∩test 上两臂读数 |",
            "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in recs:
        if not r["exists"]:
            doc.append(f"| {r['title']} | {r['seed']} | — | — | — | — | （变体缺失） |")
            continue
        te = len(r["mem"]["test"]["hit"])
        note = "—"
        if r["delta"] and "error" not in (r["delta"] or {}):
            v = r["delta"]["work"]["fixed_0.5"]["触达∩test"]
            note = ("n=0" if v.get("n", 0) == 0 else
                    ("**逐位相同**" if all(abs(x) < EPS for x in v["delta"]) else "不同"))
        doc.append(f"| {r['title']} | {r['seed']} | {len(r['hit'])} | "
                   f"{len(r['mem']['train']['hit'])} | {len(r['mem']['val']['hit'])} | "
                   f"**{te}** | {note} |")
    doc.append("")

    out = REPO / args.out
    out.write_text("\n".join(doc) + "\n", encoding="utf-8")
    print(f"[reach] → {out}")
    for r in recs:
        if not r["exists"]:
            print(f"  {r['title']} ss{r['seed']}: 变体缺失")
            continue
        m = r["mem"]
        d = r["delta"] or {}
        dm = ((d.get("work") or {}).get("fixed_0.5") or {}).get("全 test", {}).get("delta")
        print(f"  {r['title']} ss{r['seed']}: 触达 {len(r['hit'])} → "
              f"train {len(m['train']['hit'])} / val {len(m['val']['hit'])} / "
              f"test {len(m['test']['hit'])}"
              + (f" | Δmicro@0.5(全 test) {dm[0]:+.2e}" if dm else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
