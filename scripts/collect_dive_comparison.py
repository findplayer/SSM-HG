#!/usr/bin/env python3
"""**三方并列**汇总：① 主库内测 / ② 增强集内测 / DIVE 外部测试，逐消融臂对照。

**为什么单独一个脚本**：`collect_ablation_results.py` 只管**同分布**两组（①②各自独立、并列呈现），
而外部测试引入了第三个维度（**换数据集**），且 DIVE 上的数字来自另一个脚本
（`evaluate_external.py`）、另一套 JSON。三方并列需要的对齐规则（按臂名 + 逐语料的正典基线）
放在这里，避免把 `collect_ablation_results.py` 越改越杂。

**三方各自的"正典"不同，Δ 必须各减各的**：
  - ① 内测的 Δ 相对 `runs/seed*`（① 的微调正典）
  - ② 内测的 Δ 相对 `runs/augmentation/seed*`
  - DIVE(①模型) 的 Δ 相对 **① 模型在 DIVE 上的成绩**（`matrix_main` 的 `canon`）
  - DIVE(②模型) 的 Δ 相对 **② 模型在 DIVE 上的成绩**（`matrix_aug` 的 `canon`）
  🔴 **不得跨列比较绝对值**（`decisions.md` §23）：①② 与 DIVE 是三套不同的评测条件。

用法（从仓库根目录运行）：
  python scripts/collect_dive_comparison.py
产物：`eval_results/dive/comparison.{json,md}`
"""
from __future__ import annotations

import json

import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

OUT_DIR = REPO / "eval_results" / "dive"
INTERNAL = {"main": REPO / "eval_results" / "ablation" / "collected.json",
            "aug": REPO / "eval_results" / "ablation" / "collected_aug.json"}
EXTERNAL = {"main": OUT_DIR / "matrix_main.json", "aug": OUT_DIR / "matrix_aug.json"}

# 三方表格用到的指标：`collected.json` 的键 → `matrix_*.json` 的键
METRIC_MAP = {
    "micro@0.5": ("micro_0.5", "micro_f1@0.5"),
    "micro@val_thr": ("micro_thr", "micro_f1@val_thr"),
    "macro@0.5": ("macro_0.5", "macro_f1@0.5"),
    "mAP": ("mAP", "mAP"),
}
VULN = ["access_control", "arithmetic", "dos", "front_running",
        "reentrancy", "time_manipulation", "uncheck"]


def fmt(block: dict | None) -> str:
    """`{mean,std,n}` → `0.7110±0.0389`；缺数据 → `—`。"""
    if not block or block.get("mean") is None:
        return "—"
    return f"{block['mean']:.4f}±{block['std']:.4f}"


def delta(a: dict | None, base: dict | None) -> float | None:
    if not a or not base or a.get("mean") is None or base.get("mean") is None:
        return None
    return a["mean"] - base["mean"]


def load_internal(path: Path) -> dict:
    d = json.loads(path.read_text(encoding="utf-8"))
    return {"canon": d["canon"]["stats"], "arms": {k: v["stats"] for k, v in d["arms"].items()},
            "canon_per_class": d["canon"].get("per_class"),
            "per_class": {k: v.get("per_class") for k, v in d["arms"].items()},
            # 逐种子明细供「最佳种子」口径用（`collected.json` 的 `per_seed` 是 {seed: {指标: 值}}）
            "canon_per_seed": d["canon"]["per_seed"],
            "per_seed": {k: v["per_seed"] for k, v in d["arms"].items()}}


def load_external(path: Path) -> dict:
    d = json.loads(path.read_text(encoding="utf-8"))
    out = {"canon": None, "arms": {}, "canon_per_class": None, "per_class": {},
           "prior": None, "normal": None, "canon_per_seed": {}, "per_seed": {}}
    for k, v in d["arms"].items():
        s = v.get("summary")
        out["per_seed"][k] = {str(r["seed"]): {
            "micro_f1@val_thr": r["test"]["source_val_threshold"]["micro_f1"],
            "micro_f1@0.5": r["test"]["fixed_0.5"]["micro_f1"],
            "macro_f1@val_thr": r["test"]["source_val_threshold"]["macro_f1"],
            "macro_f1@0.5": r["test"]["fixed_0.5"]["macro_f1"],
            "mAP": r["mAP"]["mAP"]} for r in (v.get("per_seed") or [])}
        (out.__setitem__("canon", s) if k == "canon" else out["arms"].__setitem__(k, s))
        pc = (s or {}).get("per_class")
        (out.__setitem__("canon_per_class", pc) if k == "canon"
         else out["per_class"].__setitem__(k, pc))
        if k == "canon" and v.get("per_seed"):
            out["canon_per_seed"] = out["per_seed"]["canon"]
            out["prior"] = v["per_seed"][0]["prior"]
            out["normal"] = {"n": s["normal_subset_n"],
                             "per_class_FPR@val_thr": s["normal_subset_per_class_FPR@val_thr"],
                             "contract_FPR@val_thr": s["contract_FPR@val_thr"],
                             "contract_FPR@0.5": s["contract_FPR@0.5"]}
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    internal = {g: load_internal(p) for g, p in INTERNAL.items() if p.exists()}
    external = {g: load_external(p) for g, p in EXTERNAL.items() if p.exists()}
    missing = [str(p) for p in list(INTERNAL.values()) + list(EXTERNAL.values()) if not p.exists()]
    if missing:
        print(f"[cmp] ⚠ 缺 {len(missing)} 份输入，将只渲染已有的部分：\n  " + "\n  ".join(missing))

    import run_ablation as RA
    desc = {n: d for n, _ov, d in RA.ABLATIONS}
    arms = sorted(set().union(*[set(v["arms"]) for v in list(internal.values()) +
                                list(external.values())]))

    result = {"created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
              "inputs": {**{f"internal_{k}": str(v.relative_to(REPO)) for k, v in INTERNAL.items()},
                         **{f"external_{k}": str(v.relative_to(REPO)) for k, v in EXTERNAL.items()}},
              "canon": {g: v.get("canon") for g, v in {**internal, **external}.items()},
              "arms": {}}

    L = []
    A = L.append
    A("# 三方并列：① 主库 / ② 增强集 / DIVE 外部测试（逐消融臂）")
    A("")
    A("> 🔴 **禁止跨列比较绝对值**（`decisions.md` §23）：三列是**三套不同的评测条件**"
      "（不同数据、不同划分、不同类别先验）。可比的只有**同列内的 Δ**（相对该列自己的正典）。")
    A("")
    # ---- 主口径：最佳种子（用户 2026-09-20 裁定）----
    # 🔴 **每个语料只选一个种子，内测列与 DIVE 列共用**：否则同一行里"① 模型"在内测列
    #    和 DIVE 列其实是两个不同的模型，Δ 与结论都不成立。
    #    判据 = 该语料**正典**在**主指标 micro-F1@val_thr** 上最高的那个种子（口径见
    #    `collect_ablation_results.best_seed_of` 的说明）。
    def _k(src: dict, grp: str) -> str:
        cps = src.get(grp, {}).get("canon_per_seed") or {}
        key = "micro_thr" if src is internal else "micro_f1@val_thr"
        return max(cps, key=lambda x: cps[x][key]) if cps else "0"

    k = {"main": _k(internal, "main"), "aug": _k(internal, "aug")}

    def _pick(grp: str, name: str, label: str, src: dict) -> str:
        ps = (src.get(grp, {}).get("canon_per_seed") if name == "canon"
              else src.get(grp, {}).get("per_seed", {}).get(name)) or {}
        row = ps.get(k[grp])
        if not row:
            return "—"
        return f"{row[METRIC_MAP[label][0 if src is internal else 1]]:.4f}"

    A("---")
    A("")
    A("# 主口径：最佳种子（用户 2026-09-20 裁定）")
    A("")
    A(f"> 🔴 **每语料一个种子，内测列与 DIVE 列共用**：① 用 **seed{k['main']}**、"
      f"② 用 **seed{k['aug']}**（判据 = 该语料**正典**在 micro-F1@val_thr 上最高）。")
    A("> 共用是必须的——否则同一行里「① 模型」在内测列与 DIVE 列会是**两个不同的模型**。")
    A("> ⚠ 单种子无方差；重跑抖动 ≈0.012（约种子间 std 的 40%，`decisions.md` §36.4）")
    A("> ⇒ **不得**据此下「某干预有效」的结论。mean±std 见**附录**。")
    A("")
    for label in ("micro@0.5", "micro@val_thr", "macro@0.5", "mAP"):
        A(f"### 表 1′.{label}（**最佳种子** ① seed{k['main']} / ② seed{k['aug']}）")
        A("")
        A("| 臂 | ① 主库内测 | ② 增强集内测 | DIVE（①模型） | DIVE（②模型） |")
        A("| --- | --- | --- | --- | --- |")
        A(f"| **正典** | {_pick('main','canon',label,internal)} | "
          f"{_pick('aug','canon',label,internal)} | "
          f"{_pick('main','canon',label,external)} | {_pick('aug','canon',label,external)} |")
        for name in arms:
            A(f"| {name} | {_pick('main',name,label,internal)} | {_pick('aug',name,label,internal)}"
              f" | {_pick('main',name,label,external)} | {_pick('aug',name,label,external)} |")
        A("")
    A("---")
    A("")
    A("# 附录：3 种子 mean±std（保留——单种子无方差，见上）")
    A("")
    A("## 表 1：主指标 micro-F1@val_thr（3 种子 mean±std）")
    A("")
    A("| 臂 | 变量 | ① 主库内测 | ② 增强集内测 | DIVE（①模型） | DIVE（②模型） |")
    A("| --- | --- | --- | --- | --- | --- |")
    A(f"| **正典** | 微调 CodeBERT + 全部组件 | "
      f"{fmt(internal.get('main', {}).get('canon', {}).get('micro_thr'))} | "
      f"{fmt(internal.get('aug', {}).get('canon', {}).get('micro_thr'))} | "
      f"{fmt(external.get('main', {}).get('canon', {}).get('micro_f1@val_thr'))} | "
      f"{fmt(external.get('aug', {}).get('canon', {}).get('micro_f1@val_thr'))} |")
    for name in arms:
        A(f"| {name} | {desc.get(name, '—')} | "
          f"{fmt(internal.get('main', {}).get('arms', {}).get(name, {}).get('micro_thr'))} | "
          f"{fmt(internal.get('aug', {}).get('arms', {}).get(name, {}).get('micro_thr'))} | "
          f"{fmt(external.get('main', {}).get('arms', {}).get(name, {}).get('micro_f1@val_thr'))} | "
          f"{fmt(external.get('aug', {}).get('arms', {}).get(name, {}).get('micro_f1@val_thr'))} |")
    A("")
    A("## 表 2：Δ 相对**该列自己的正典**（同列内可比；★ = |Δ| > 该列正典的种子间 std）")
    A("")
    A("| 臂 | Δ① 主库 | Δ② 增强集 | ΔDIVE(①模型) | ΔDIVE(②模型) |")
    A("| --- | --- | --- | --- | --- |")
    for name in arms:
        cells = []
        for grp, src in (("main", internal), ("aug", internal),
                         ("main", external), ("aug", external)):
            km = "micro_thr" if src is internal else "micro_f1@val_thr"
            d = delta(src.get(grp, {}).get("arms", {}).get(name, {}).get(km),
                      src.get(grp, {}).get("canon", {}).get(km))
            std = (src.get(grp, {}).get("canon", {}).get(km) or {}).get("std")
            mark = "★" if (d is not None and std and abs(d) > std) else ""
            cells.append("—" if d is None else f"{d:+.4f}{mark}")
        A(f"| {name} | " + " | ".join(cells) + " |")
    A("")

    # ---- 表 3：DIVE 逐类 F1 ----
    A("## 表 3：DIVE 逐类 F1@源语料验证集阈值（3 种子 mean±std；support 见注）")
    A("")
    for g, label in (("main", "① 模型"), ("aug", "② 模型")):
        e = external.get(g, {})
        pc = e.get("canon_per_class")
        if not pc:
            continue
        # ⚠ 外部报告的键是 `source_val_threshold`（阈值来自**源语料**验证集）；
        #   内测的键是 `val_threshold`。两者不同名，写错只会让整表变「—」而不报错。
        wp = "source_val_threshold"
        sup = pc[wp]["per_seed_support"]
        A(f"### {label} → DIVE")
        A("")
        A("| 类 | 正典 F1 | " + " | ".join(
            f"{n} F1" for n in arms if e.get("per_class", {}).get(n)) + " |")
        A("| --- | --- | " + " | ".join("---" for n in arms if e.get("per_class", {}).get(n)) + " |")
        for c in VULN:
            row = [f"{pc[wp]['f1'][c]['mean']:.4f}±{pc[wp]['f1'][c]['std']:.4f}"]
            for n in arms:
                apc = e["per_class"].get(n)
                row.append(f"{apc[wp]['f1'][c]['mean']:.4f}" if apc else "—")
            A(f"| {c} | " + " | ".join(row) + " |")
        A("")
        A(f"support（s0/s1/s2）：" + "；".join(
            f"{c}={sup['0'][i]}/{sup['1'][i]}/{sup['2'][i]}" for i, c in enumerate(VULN)))
        A("")

    # ---- 表 3b：🔴 逐类 AP vs 随机基线（**判定"排序质量是否跨数据集存活"的唯一口径**）----
    A("## 表 3b：🔴 DIVE 逐类 PR-AUC 与**随机基线**的对照（阈值无关）")
    A("")
    A("> **随机排序器的期望 AP 恰好等于该类正样本率** —— 故「AP 高」本身不说明任何事，")
    A("> **必须减去先验**才知道排序有没有信息。**这是本报告最重要的一张表**：")
    A("> 它把「F1 掉了」拆成「先验变了」与「排序退化了」两件事。")
    A("")
    for g, label in (("main", "① 模型"), ("aug", "② 模型")):
        e = external.get(g, {})
        cs = e.get("canon", {})
        if not cs:
            continue
        base = e["prior"]["dive_test_pos_rate"]
        ap = cs.get("per_class_AP", {})
        A(f"### {label} → DIVE")
        A("")
        A("| 类 | DIVE 正样本率（=随机 AP） | 逐类 AP | AP − 随机 | 判定 |")
        A("| --- | --- | --- | --- | --- |")
        for i, c in enumerate(VULN):
            m = (ap.get(c) or {}).get("mean")
            if m is None:
                A(f"| {c} | {base[i]:.3f} | — | — | 该种子 support=0 |")
                continue
            d = m - base[i]
            verdict = "✅ 有信息" if d > 0.05 else ("≈ 与随机不可分" if d > -0.05 else "❌ 低于随机")
            A(f"| {c} | {base[i]:.3f} | {m:.4f} | {d:+.4f} | {verdict} |")
        mm = (cs.get("mAP") or {}).get("mean")
        bm = sum(base) / len(base)
        A(f"| **mAP** | **{bm:.3f}** | **{mm:.4f}** | **{mm - bm:+.4f}** | |")
        A("")

    # ---- 表 4：先验与正常合约 ----
    for g, label in (("main", "① 模型"), ("aug", "② 模型")):
        e = external.get(g, {})
        if not e.get("prior"):
            continue
        A(f"## 表 4：DIVE 类别先验 vs 训练语料 + 正常合约假阳性（{label}）")
        A("")
        pr, nm = e["prior"], e["normal"]
        A("| 类 | DIVE 正样本率 | 训练语料正样本率 | Δ | DIVE test support | 正常合约逐类 FPR |")
        A("| --- | --- | --- | --- | --- | --- |")
        for i, c in enumerate(VULN):
            A(f"| {c} | {pr['dive_test_pos_rate'][i]:.4f} | "
              f"{(pr['source_train_pos_rate'] or [float('nan')]*7)[i]:.4f} | "
              f"{(pr['delta'] or [float('nan')]*7)[i]:+.4f} | {pr['dive_test_support'][i]} | "
              f"{(nm['per_class_FPR@val_thr'][i] or {}).get('mean', float('nan')):.4f} |")
        A("")
        A(f"正常合约（七类全 0）**{nm['n']}** 个；合约级误报率 @val_thr = "
          f"{fmt(nm['contract_FPR@val_thr'])}、@0.5 = {fmt(nm['contract_FPR@0.5'])}")
        A("")

    result["markdown"] = "\n".join(L)
    result["arms"] = {n: {"desc": desc.get(n, ""),
                          "internal": {g: {k: internal.get(g, {}).get("arms", {}).get(n, {}).get(v)
                                           for k, v in METRIC_MAP.items()} for g in internal},
                          "external": {g: {k: external.get(g, {}).get("arms", {}).get(n, {}).get(v)
                                           for k, v in METRIC_MAP.items()} for g in external}}
                       for n in arms}
    (OUT_DIR / "comparison.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT_DIR / "comparison.md").write_text(result["markdown"], encoding="utf-8")
    print(f"[cmp] 已写 {OUT_DIR / 'comparison.json'} 与 comparison.md（{len(arms)} 臂）")


if __name__ == "__main__":
    main()
