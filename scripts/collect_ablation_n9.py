#!/usr/bin/env python3
"""消融 **n=9 同配对**结果的汇总卷（`run_ablation_n9.py` 的下游，**不重训、只读产物**）。

**它回答的问题**：把「某干预有效/无效」的判据从 **n=3** 换成 **n=9** 之后，
`ablation_results.md` 里那些读数**哪些还站得住、哪些翻了**。

**为什么不能直接扩用 `collect_ablation_results.py`**：那个脚本的配对是「臂的 `seed{s}`
↔ 正典 `runs/seed{s}`」，即**只有 3 对**（`ablation_results.md` §12.4 已把它列为开口）。
本脚本走 `ts ∈ {0,1,2} × ss ∈ {0,1,2}` 的 **3×3 网格**，配对数 **9**，
且基线取**同 `(ts, ss)` 的那一对**（同划分、同初始化）⇒ 配对比较能消掉划分与初始化的方差。

🔴 **四条必须随结果一起报的口径**：
  1. **判方向的门槛**：n=9 ⇒ df=8 ⇒ 双侧 p<0.05 的临界值 **|t| > 2.306**。
     n=3（df=2）的临界值是 **4.303** —— 换 n 会改变门槛，这正是 n=3 判不了方向的原因。
  2. **多重比较**：本页同时检验 **臂数 × 6 指标** 个假设（21 臂 = **126 个**；带 `--with-dose-arms` /
     `--with-arch-arms` / `--with-pm-arms` 时更多，**分母从实际臂数算、不写死**）⇒ 单看 `|t|>2.306`
     必有假阳性（126 个时期望约 6 个）。故本页对"显著"的标注给出 **Bonferroni 参考阈值**，并要求
     **同号对数 ≥8/9** 与 **同指标族内多处一致** 才建议当作结论（本仓既有纪律：§26.7/§27.5）。
     ⚠ **`★` 是"该格自己那个指标"的 t**（与右侧 `t(micro@val_thr)` 列**不是同一个数**）——
     某臂可以 Δmicro@0.5 带 ★ 而主指标的 t 不到 1（`cb_node_only` 实测如此）。
  3. **`support ≤ 2` 的类只作描述性呈现**（`decisions.md` §13）——宏观 F1 的读数受此限制。
  4. 🔴 **`同号` 列里的 `=0` 不是「干预没作用」**（2026-09-21 实测纠正）：本表的 6 个指标是
     **阈值型（@0.5 / @val_thr）+ 排序型（mAP）**，而本仓 test 逐类 AP 是**很粗的有理数**
     （support 仅个位数）⇒ **不同的概率向量可以给出完全相同的读数**。实测 ① 全部 35 个 `=0`
     配对（横跨 13 个臂）两侧的 `test_probs.pt` **都逐位不同**（如 `no_prior_drop` 0:0
     最大绝对差 4.9e-2、322/322 元素全变）。要判「干预是否生效」须看**概率本身**，不能看这一列。

**指标来源**：各 run 的 `results.json`（`evaluate.py` 产物），与 `collect_ablation_results.py`
**同源同口径**（用它的 `dig()` 取值，不另写一份解析）。故本页的**对角 3 对**
与 `eval_results/ablation/collected*.md` 的 Δ **应当逐位一致** —— 本脚本把它作为一条**自检**输出。

用法（从仓库根目录运行）：
  python scripts/collect_ablation_n9.py --group both
  python scripts/collect_ablation_n9.py --group main --out experiments/ablation_n9_results.md
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_ablation_results as CAR                            # noqa: E402  复用 dig()
import paired_study_analysis as PSA                               # noqa: E402  复用 paired_t()
import run_ablation_n9 as R9                                      # noqa: E402  计划与复用规则的唯一来源

# 判方向（mean ± std → t）的指标。键 = 显示名，值 = `results.json` 里的 `/` 路径
# ⚠ 路径分隔符必须是 `/`：`fixed_0.5` 自身含点，用 `.` 切会静默变 "—"（`test_collect_ablation.py` 的回归锁）
METRICS: dict[str, str] = {
    "micro@0.5":     "test/fixed_0.5/micro_f1",
    "micro@val_thr": "test/val_threshold/micro_f1",
    "macro@0.5":     "test/fixed_0.5/macro_f1",
    "macro@val_thr": "test/val_threshold/macro_f1",
    "subset@0.5":    "test/fixed_0.5/subset_accuracy",
    "mAP":           "mAP/mAP",
}
HEADLINE = "micro@val_thr"      # 主表口径：本仓主表工作点（阈值只在验证集搜）

T_CRIT_9 = 2.306                # df=8，双侧 p<0.05
T_CRIT_3 = 4.303                # df=2，双侧 p<0.05（n=3 的旧门槛，仅作对照）
# 重跑抖动：同条件重跑同一 run 的读数波动上界（本仓实测 ≈0.012，`decisions.md` §36.4，
# 约为种子间 std 的 40%）。用于把"符号翻转"分成「幅度可观的翻转」与「噪声之间的翻转」——
# 二者的证据强度差一个量级，并列呈现会被读成同样可信（2026-09-21 加，起因见 ② 那 9 个翻转）。
REPRO_JITTER = 0.012
N_TESTS = len(R9.RA.ABLATIONS) * len(METRICS)      # 多重比较的分母

# df → 双侧 p<0.05 的 t 临界值。**必须按 n 取**：跑批中途某些臂只有 3 对，
# 用 n=9 的门槛去标它们会**过度标注**（df 越小、临界值越大、越不该说"显著"）。
T_CRIT_BY_DF = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571,
                6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228}


def t_crit(n: int) -> float:
    """n 个配对的临界值；df = n-1；df>10 用正态近似 1.96（保守方向即可，仅作标注）。"""
    return T_CRIT_BY_DF.get(n - 1, 1.96)


def _load(run_dir: Path):
    p = run_dir / "results.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def value(res: dict | None, path: str):
    return None if res is None else CAR.dig(res, path)


def cost_of(run_dir: Path):
    c = run_dir / "config.json"
    if not c.exists():
        return None
    return (json.loads(c.read_text(encoding="utf-8")).get("timing") or {}).get("run_wall_seconds")


def params_of(run_dir: Path):
    """参数量（`derived.parameter_report.total_params`）。

    🔴 **架构基线族必须随结果报它**：§40.4 实测 GCN 比正典少 39.5% 的参数，
    没有这一列就无法区分「该组件重要」与「模型变小了」（`ablation_plan.md` §3.1 的要求）。
    ⚠ 键名是 `total_params`，**不是** `total` —— `run_arch_baselines.py` 的摘要行读的是后者，
      于是它一直打印 `total=None`（本次顺手记下，未改那支脚本的行为）。
    """
    c = run_dir / "config.json"
    if not c.exists():
        return None
    pr = ((json.loads(c.read_text(encoding="utf-8")).get("derived") or {})
          .get("parameter_report") or {})
    return pr.get("total_params")


def _param_of(g: dict, item: str):
    """（臂参数量, 相对基线的倍数）——倍数缺失时返回 '—'。"""
    p = (g["arms"].get(item) or {}).get("params")
    return p if p is not None else "—", _ratio(p, g.get("baseline_params"))


def collect_group(gkey: str, items, pairs) -> dict:
    """一组的全部读数：逐 (臂, 配对) 的 arm/base 值与 Δ，再按指标聚合。"""
    entries = R9.plan(gkey, items, pairs)
    by_key = {(e["item"], e["t"], e["s"]): e for e in entries}
    out: dict = {"group": gkey, "title": R9.GROUPS[gkey]["title"], "pairs": pairs,
                 "arms": {}, "baseline_missing": [], "arm_missing": []}

    # ---- 基线自身的绝对值（9 对 mean±std）----
    base_vals: dict[str, list[float]] = {m: [] for m in METRICS}
    base_cost: list[float] = []
    base_params = None
    for t, s in pairs:
        e = by_key[(R9.BASELINE_ITEM, t, s)]
        res = _load(e["run_dir"])
        if res is None:
            out["baseline_missing"].append(f"{e['run_dir']}")
            continue
        if base_params is None:
            base_params = params_of(e["run_dir"])
        for m, path in METRICS.items():
            v = value(res, path)
            if v is not None:
                base_vals[m].append(v)
        c = cost_of(e["run_dir"])
        if c is not None:
            base_cost.append(c)
    out["baseline_params"] = base_params
    out["baseline"] = {m: (statistics.mean(v), statistics.stdev(v) if len(v) > 1 else 0.0, len(v))
                       for m, v in base_vals.items()}
    out["baseline_cost"] = (statistics.mean(base_cost), len(base_cost)) if base_cost else (None, 0)

    # ---- 逐臂 ----
    for item, override, desc in items:
        rec: dict = {"desc": desc, "override": {k: str(v) for k, v in override.items()},
                     "delta": {}, "arm_abs": {}, "cost": None, "n": 0, "diag_delta": {},
                     "params": None}
        deltas: dict[str, list[float]] = {m: [] for m in METRICS}
        arm_vals: dict[str, list[float]] = {m: [] for m in METRICS}
        costs: list[float] = []
        for t, s in pairs:
            a = _load(by_key[(item, t, s)]["run_dir"])
            b = _load(by_key[(R9.BASELINE_ITEM, t, s)]["run_dir"])
            if a is None or b is None:
                out["arm_missing"].append(f"{gkey}/{item}/{t}:{s}")
                continue
            if rec["params"] is None:
                rec["params"] = params_of(by_key[(item, t, s)]["run_dir"])
            rec["n"] += 1
            for m, path in METRICS.items():
                va, vb = value(a, path), value(b, path)
                if va is None or vb is None:
                    continue
                deltas[m].append(va - vb)
                arm_vals[m].append(va)
                # 对角（ts == ss）单独留一份：用于与 n=3 表自检
                if t == s:
                    rec["diag_delta"][m] = va - vb
            c = cost_of(by_key[(item, t, s)]["run_dir"])
            if c is not None:
                costs.append(c)

        for m in METRICS:
            d = deltas[m]
            if not d:
                continue
            mean, sd = statistics.mean(d), (statistics.stdev(d) if len(d) > 1 else 0.0)
            rec["delta"][m] = {"mean": mean, "std": sd, "n": len(d),
                               "t": PSA.paired_t(d),
                               "n_pos": sum(1 for x in d if x > 0),
                               "n_neg": sum(1 for x in d if x < 0),
                               # Δ **恰好为 0** 的对数：本仓确有构造性空操作臂（如 `cb_unlimited`）
                               "n_zero": sum(1 for x in d if x == 0),
                               "values": d}
            av = arm_vals[m]
            rec["arm_abs"][m] = {"mean": statistics.mean(av),
                                 "std": statistics.stdev(av) if len(av) > 1 else 0.0, "n": len(av)}
        rec["cost"] = (statistics.mean(costs), len(costs)) if costs else (None, 0)
        out["arms"][item] = rec
    return out


def _fmt(v, nd=4, dash="—"):
    return dash if v is None else f"{v:+.{nd}f}"


def _abs(v, nd=4, dash="—"):
    return dash if v is None else f"{v:.{nd}f}"


def _star(t: float | None, n: int, n_tests: int | None = None) -> str:
    """显著性标注：★ = 过该 n 下的 p<0.05 临界值；★★ = 另过 Bonferroni 参考阈值。

    🔴 **`t` 是"这一格自己那个指标的 t"，不是主指标那个**（主指标只多印一列 `t(...)` 给人看）。
    故 Δmicro@0.5 上的 `★` 说的是「micro@0.5 这一列显著」，**不得**读成"主指标显著"。
    两者的 t 可以差很远（如 `cb_node_only`：Δmicro@0.5 带 ★，而 Δmicro@val_thr 的 t 只有 −0.81）。
    """
    if t is None:
        return ""
    a = abs(t)
    if a <= t_crit(n):
        return ""
    # Bonferroni：把 α=0.05 摊到全部检验上，再用正态近似折算成 t 阈值（保守，仅作参考）。
    # ⚠ **分母随实际检验数变**：本页的臂集合是可扩充的（`--with-dose-arms` / `--with-arch-arms`
    #   / `--with-pm-arms`），21 臂是 126 个检验、31 臂是 186 个 —— 写死 126 会让"★★"在
    #   扩充页面上**偏松**（门槛该更高反而没高）。故由调用方传入实际检验数。
    k = N_TESTS if n_tests is None else n_tests
    z = 3.9 if k >= 100 else 3.3
    return "★★" if a > z else "★"


def _sign_cell(d: dict) -> str:
    """同号列：`a+/b−`，并在有"Δ 恰好为 0"的对时补上 `/c=0`。

    为什么单列 `=0`：Δ **恰好等于 0** 与"Δ 是个很小的数"是两种不同的读数，混在一起会被
    读成"效应很小"。单列出来，读者才知道有多少对是**读数完全相同**。

    🔴 **但 `=0` 不等于「干预没生效」（2026-09-21 实测纠正）**：本列原先的注释把成因
    写成"构造性空操作臂"（`cb_unlimited` 只触达 20/590 图等），听上去像"模型没被改动"。
    实测**推翻了**这个读法：① 的 **全部 35 个 `=0` 配对**（横跨 13 个臂）里，
    两侧的 `test_probs.pt` **都逐位不同**（如 `no_prior_drop` 的 0:0 最大绝对差 4.9e-2、
    322/322 个元素都变），只是**报出来的指标看不见**。原因是本表的指标是
    **阈值型（@0.5 / @val_thr）+ 排序型（mAP）**：
      - `mAP` 只看**排序**，且本仓 test 的逐类 AP 是**很粗的有理数**
        （`no_prior_drop` 0:0 实测 `[0.5159, 1.0, 0.3333, 0.5, 1.0, 1.0, 1.0]`，support 只有个位数）
        ⇒ 两个**不同**的概率向量可以给出**完全相同**的 AP；
      - `@0.5`/`@val_thr` 是**判定**，只要没有元素跨过阈值就完全一样。
    ⇒ 正确读法：**`=0` = 「本表这 6 个指标对该配对的差异不敏感」，不是「该干预没有作用」**。
      要判"干预是否真的生效"，须看**概率向量本身**（或换更细的指标），不能看这一列。
    """
    s = f"{d['n_pos']}+/{d['n_neg']}−"
    if d.get("n_zero"):
        s += f"/{d['n_zero']}=0"
    return s


def _delta_table(arms: dict, n_tests: int | None = None) -> list[str]:
    """Δ 主表（一个子集一行表）。

    `n_tests` = 本页**总共**检验了多少个假设（供 Bonferroni 参考阈值用）。留空则按本表
    `臂数 × 指标数` 估。⚠ 传入**本页全部臂**才是对的：`--with-arch-arms` 等扩充臂
    与消融臂在同一页、同一批读数上被判显著，属同一个多重比较家族。
    """
    k = len(arms) * len(METRICS) if n_tests is None else n_tests
    L = ["| 臂 | " + " | ".join(f"Δ{m}" for m in METRICS) + " | t(" + HEADLINE + ") | 同号 |",
         "| --- | " + " | ".join("---" for _ in METRICS) + " | --- | --- |"]
    for item, rec in arms.items():
        cells = []
        for m in METRICS:
            d = rec["delta"].get(m)
            cells.append("—" if not d else f"{_fmt(d['mean'])}{_star(d['t'], d['n'], k)}")
        hd = rec["delta"].get(HEADLINE)
        tstr = "—" if not hd else f"{hd['t']:+.2f}"
        L.append(f"| {item} | " + " | ".join(cells) + f" | {tstr} | "
                 f"{'—' if not hd else _sign_cell(hd)} |")
    L += ["",
          f"> 标注：`★` = |t| 超过**该行 n 对应的**双侧 p<0.05 临界值（n=9 ⇒ df=8 ⇒ {T_CRIT_9}；"
          f"n=3 ⇒ df=2 ⇒ {T_CRIT_3}）；`★★` = 另过 Bonferroni 参考阈值（本页 {k} 个检验折算）。"
          f"🔴 **`★` 是「这一格自己那个指标」的 t**，与右侧 `t({HEADLINE})` 列**不是同一个数**——"
          f"例如某臂可以 Δmicro@0.5 带 ★ 而主指标的 t 只有 −0.81（`cb_node_only` 实测如此）。"
          f"`同号` 列 = Δ 为正 / 为负（/ 恰好为 0）的配对个数（`9+/0−` 表示 9 对**全部**同向）。"
          "🔴 **`=0` 只表示「本表这 6 个指标对该配对的差异不敏感」，不表示「干预没作用」**——"
          "实测 ① 全部 35 个 `=0` 配对（横跨 13 个臂）两侧的 `test_probs.pt` **都逐位不同**；"
          "指标是阈值型（@0.5/@val_thr）+ 排序型（mAP），而本仓 test 的逐类 AP 是**很粗的有理数**"
          "（support 仅个位数）⇒ 不同概率可以给出相同 AP。要判「干预是否生效」须看概率本身。"
          "⚠ **n < 9 的行不看显著性**——它们只是跑批中途的中间态。", ""]
    return L


def _abs_table(arms: dict, base_params=None) -> list[str]:
    """绝对值表（9 对 mean±std）——与 Δ 表配套：Δ 小可能因为"两臂都低"或"两臂都高"。"""
    L = ["| 臂 | " + " | ".join(METRICS) + " | 参数量 | 相对正典 |", "| --- | "
         + " | ".join("---" for _ in METRICS) + " | --- | --- |"]
    for item, rec in arms.items():
        cells = []
        for m in METRICS:
            a = rec["arm_abs"].get(m)
            cells.append("—" if not a else f"{a['mean']:.4f}±{a['std']:.4f}")
        p = rec.get("params")
        L.append(f"| {item} | " + " | ".join(cells) + f" | {p or '—'} | {_ratio(p, base_params)} |")
    L.append("")
    return L


def _ratio(p, base=None) -> str:
    return "—" if not p or not base else f"{p / base:.3f}×"


def group_section(g: dict, doc: list[str]) -> None:
    gk = g["group"]          # 供下面几处"按组给不同措辞"用（不得删：删了会在运行时报 NameError）
    # ⚠ `GROUPS[...]["title"]` **已经带 ①② 前缀**（`run_ablation_n9.py:65/75`），
    #   此处**不得**再加一个 —— 否则标题印成「## ① ① 主库 …」（2026-09-21 实测到并修）。
    doc += [f"## {g['title']}（n={g['baseline'][HEADLINE][2]} 对）", ""]
    if g["baseline_missing"]:
        doc += [f"🔴 **基线缺 {len(g['baseline_missing'])} 个配对**：{g['baseline_missing'][:3]} …", ""]
    # ---- 基线绝对值 ----
    b = g["baseline"]
    doc += ["**基线（同 `(ts, ss)` 配对，全开关默认）自身的绝对值**：", "",
            "| 指标 | mean ± std |", "| --- | --- |"]
    for m in METRICS:
        if m in b:
            doc.append(f"| {m} | {_abs(b[m][0])} ± {_abs(b[m][1])} |")
    if g["baseline_cost"][0] is not None:
        doc += ["", f"> 基线单 run wall（evaluate 侧）：**{g['baseline_cost'][0]:.1f} s**"
                    f"（n={g['baseline_cost'][1]}）。"]
    doc.append("")

    # ⚠ **只留有读数的臂**：扩充臂（架构族 / `*_pm`）在 `items_for` 里对**两组都**声明，
    #   但实际只跑了 ①（`runs/arch_n9_aug/` 为空）。若照声明渲染，② 会印出**整张 `—` 表**——
    #   读者无法区分「跑过但缺数据」与「压根没跑」这两种完全不同的情况（2026-09-21 实测到）。
    #   故按"有无 Δ 读数"过滤，并在缺整组时打一行显式说明（见下）。
    def _has_data(r: dict) -> bool:
        return bool(r.get("delta"))

    # ⚠ 同上：臂集合是**按声明**建的（`--with-dose-arms` 等对两组都声明），
    #   而实际跑批可能只覆盖一组（剂量臂只跑了 ①、架构族只跑了 ①）
    #   ⇒ 照声明渲染会印出**整行 `—`**，读者分不清「跑了但缺数据」与「没跑」。
    #   故 5.4 主表也按"有无 Δ 读数"过滤，缺的单独打一行说明（2026-09-21 实测到并修）。
    abl_declared = {i: r for i, r in g["arms"].items() if not R9.is_arch(i) and not R9.is_pm(i)}
    abl = {i: r for i, r in abl_declared.items() if _has_data(r)}
    abl_missing = [i for i, r in abl_declared.items() if not _has_data(r)]
    arch_declared = {i: r for i, r in g["arms"].items() if R9.is_arch(i)}
    pm_declared = {i: r for i, r in g["arms"].items() if R9.is_pm(i)}
    arch = {i: r for i, r in arch_declared.items() if _has_data(r)}
    pm = {i: r for i, r in pm_declared.items() if _has_data(r)}
    # Bonferroni 的分母 = **本组实际检验的全部假设数**（臂数 × 指标数），三张子表共用。
    # 不写死 126：臂集合随 `--with-*-arms` 变，写死会让扩充页面的 `★★` 偏松。
    n_tests = len(g["arms"]) * len(METRICS)
    if n_tests > N_TESTS:
        # 模块级 `N_TESTS` 只作默认；实测超出时打一行提醒（便于发现"加了臂但没同步说明"）
        print(f"[n9-summary] ⚠ {g['group']}: 实际检验数 {n_tests} > 模块默认 {N_TESTS}"
              f"（Bonferroni 阈值已按 {n_tests} 计算）")

    # ---- 主表：Δ（9 对配对）----
    doc += ["### 5.4 消融臂：Δ 相对同配对基线（9 对 mean±std，配对 t）", ""] \
        + _delta_table(abl, n_tests)
    doc += [f"### 5.4 消融臂：绝对值（9 对 mean±std；基线 = {g.get('baseline_params') or '—'} 参数）", ""] \
        + _abs_table(abl, g.get("baseline_params"))
    if abl_missing:
        doc += ["", f"> ⚠ **本组有 {len(abl_missing)} 个已声明的臂没有读数**（未渲染，**不是「跑了但缺数据」**）："
                    f"{'、'.join(f'`{i}`' for i in abl_missing)}。"
                    f"剂量臂（L_var）与架构族、`*_pm` 对照**只跑了 ①**；② 若需要须先跑对应驱动。"]

    # ---- n=3 vs n=9 对照（本页最重要的分析）----
    doc += ["### n=3（对角）vs n=9（全网格）：结论翻转检查", "",
            f"> 参照列 = **只取对角 3 对**（`ts = ss`）的 Δ 均值，即现有 n=3 表的读数"
            f"（`eval_results/ablation/collected*.md`）。判据列 = 9 对。",
            f"> 🔴 n=3 的临界值是 |t|>{T_CRIT_3}、n=9 是 |t|>{T_CRIT_9} —— **门槛随 n 变**，这就是"
            "「n=3 判不了方向」的算术原因。", "",
            f"| 臂 | Δ{HEADLINE}（n=3 对角） | Δ{HEADLINE}（n=9） | t(n=9) | 同号 | 读法 |",
            "| --- | --- | --- | --- | --- | --- |"]
    flips = []
    flips_negligible = []
    for item, rec in abl.items():
        hd = rec["delta"].get(HEADLINE)
        d3 = rec["diag_delta"].get(HEADLINE)
        if hd is None or d3 is None:
            continue
        t9 = hd["t"]
        n3_mean = d3
        # 🔴 「符号翻转」要分两种（2026-09-21 加）：
        #   若**两侧的 Δ 都在重跑抖动以内**（本仓实测 ≈0.012，`decisions.md` §36.4），
        #   那这个"翻转"是**噪声之间的翻转**，与幅度可观的翻转**性质完全不同**，不得并列宣称。
        #   反例：② 增强集的基线饱和在 0.986–0.995，21 臂的 |Δ| 全在 0.005 内
        #   ⇒ 会机械地报出 9 个"翻转"，但每一个都是 ±0.005 量级的噪声。
        negligible = max(abs(n3_mean), abs(hd["mean"])) <= REPRO_JITTER
        if (n3_mean > 0) != (hd["mean"] > 0):
            if negligible:
                verdict = "⚪ 符号翻转（**两侧均在抖动内**，不可解读）"
                flips_negligible.append(item)
            else:
                verdict = "🔴 **符号翻转**"
                flips.append(item)
        elif abs(t9) > t_crit(hd["n"]):
            verdict = "✅ n=9 显著"
        else:
            verdict = "○ 两者都判不了"
        doc.append(f"| {item} | {_fmt(n3_mean)} | {_fmt(hd['mean'])} | {t9:+.2f} | "
                   f"{_sign_cell(hd)} | {verdict} |")
    if flips:
        doc += ["", f"> 🔴 **符号翻转的臂（{len(flips)} 个）**：{'、'.join(flips)} —— "
                    "这些就是「n=3 的表面模式不可信」的直接证据，论文里**不得**按 n=3 的符号写结论。"]
    if flips_negligible:
        doc += ["", f"> ⚪ **另外 {len(flips_negligible)} 个臂的「翻转」发生在重跑抖动以内**"
                    f"（两侧 |Δ| 均 ≤ {REPRO_JITTER}，本仓实测抖动，`decisions.md` §36.4）："
                    f"{'、'.join(flips_negligible)}。它们不是「结论翻了」，而是**两侧都测不出效应、符号只是噪声朝向** ⇒ 既不能当成翻转、也不能当成「没翻转」，**只能记作「该臂在本组不可分辨」**。",
                    "", f"> ⚠ 判据是 `max(|Δ_n3|, |Δ_n9|) ≤ {REPRO_JITTER}`；换数字即可改变分组，"
                        f"故本条只用于**防止把噪声报成翻转**，不用于宣称任何方向的结论。"]
    doc.append("")

    # ---- 参数量匹配对照（§12.4 第 3 项 + §40.4 的前置条件）----
    if pm:
        doc += ["### 参数量匹配对照（**有意的双键**，不得读成单个组件的作用）", "",
                "🔴 这些臂**同时动两个键**（宽度/基/算子），目的是**把参数量对齐到正典**后再比 —— "
                "因为\"该组件重要\"与\"模型变大/变小了\"在参数量不对齐时**不可分离**（§6.3、§40.4）。"
                "故读法只能是「**在参数量对齐下，这一组结构差异的作用**」，"
                "论文里必须把变量写全。", ""]
        doc += _delta_table(pm, n_tests)
        doc += ["| 臂 | 变量 | 参数量 | 相对正典 |", "| --- | --- | --- | --- |"]
        for item, rec in pm.items():
            pr, ratio = _param_of(g, item)
            var = "、".join(f"`--{k.replace('_', '-')}={v}`" for k, v in rec["override"].items())
            doc.append(f"| {item} | {var} | {pr} | {ratio} |")
        doc.append("")
    elif pm_declared:
        doc += [f"> ⚠ **本组未跑参数量匹配对照**（{len(pm_declared)} 个臂已声明但无读数，"
                f"`runs/arch_n9{'_aug' if gk == 'aug' else ''}/` 下没有对应产物）—— "
                f"**不是「跑了但缺数据」，是没跑**。故本节不渲染。", ""]

    # ---- 架构基线族（口径不同，另起一节）----
    if arch:
        doc += ["### 5.3 架构基线族的 n=9（**与消融表口径不同，勿混读**）", "",
                "🔴 基线臂 `rgcn` 就是本页的 `_base`。**三条必读**："
                "① 三个基线全是**关系盲**（`edge_type` 不传给它）⇒ 只能说「关系感知 vs 关系盲」，"
                "**不得**说「RGCN 比 GAT 强」；② **参数量不匹配**（§40.4 实测 GCN 比正典少 39.5%），"
                "故差异混着「少了 4/5 的关系参数」；③ 参数量见下（`derived.parameter_report.total_params`）。", ""]
        doc += _delta_table(arch, n_tests)
        doc += ["| 臂 | 参数量 | 相对正典 |", "| --- | --- | --- |"]
        for item in arch:
            pr = _param_of(g, item)
            doc.append(f"| {item} | {pr[0]} | {pr[1]} |")
        doc.append("")
    elif arch_declared:
        doc += [f"> ⚠ **本组未跑架构基线族**（{len(arch_declared)} 个臂已声明但无读数，"
                f"`runs/arch_n9{'_aug' if gk == 'aug' else ''}/` 下没有对应产物）—— "
                f"**不是「跑了但缺数据」，是没跑**。故本节不渲染。"
                f"（① 的架构族 n=9 见上一节；② 若需要，须先跑 `run_ablation_n9.py --group aug "
                f"--with-arch-arms`。）", ""]

    # ---- 逐对明细（仅列 n=9 显著的臂）----
    sig = [(i, r) for i, r in abl.items()
           if (r["delta"].get(HEADLINE) or {}).get("t") is not None
           and abs(r["delta"][HEADLINE]["t"]) > t_crit(r["delta"][HEADLINE]["n"])]
    if sig:
        doc += ["### 逐对明细（仅 n=9 显著的臂，指标 = " + HEADLINE + "）", ""]
        for item, rec in sig:
            d = rec["delta"][HEADLINE]
            doc += [f"**{item}**（Δ = {_fmt(d['mean'])} ± {_abs(d['std'])}，t = {d['t']:+.2f}，"
                    f"n = {d['n']}）：", "",
                    "| 配对 (ts:ss) | " + " | ".join(f"{t}:{s}" for t, s in g["pairs"]) + " |",
                    "| --- | " + " | ".join("---" for _ in g["pairs"]) + " |",
                    "| Δ | " + " | ".join(_fmt(x) for x in d["values"]) + " |", ""]
    if g["arm_missing"]:
        doc += [f"🔴 **缺产物的 (臂, 配对) 共 {len(g['arm_missing'])} 处**："
                f"{g['arm_missing'][:5]} …（n<9 的臂其 t 不可比，见上表的 `n`）", ""]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", choices=["main", "aug", "both"], default="both")
    ap.add_argument("--with-dose-arms", action="store_true")
    ap.add_argument("--with-arch-arms", action="store_true",
                    help="并入架构基线族（GCN/GAT/SAGE）；产物在 `runs/arch_n9{,_aug}`。")
    ap.add_argument("--with-pm-arms", action="store_true",
                    help="并入参数量匹配对照（`*_pm`）；同样在 `runs/arch_n9{,_aug}` 下。")
    ap.add_argument("--out", default="experiments/ablation_n9_results.md")
    ap.add_argument("--json-out", default="eval_results/ablation/n9_summary.json")
    args = ap.parse_args()

    gkeys = ["main", "aug"] if args.group == "both" else [args.group]
    items = R9.items_for(args.with_dose_arms, args.with_arch_arms, args.with_pm_arms)
    groups = [collect_group(gk, items, R9.PAIRS) for gk in gkeys]

    doc = ["# 消融 n=9 同配对复核（`ts × ss` 3×3 网格）", "",
           "> 程序生成（`scripts/collect_ablation_n9.py`）。上游驱动：`scripts/run_ablation_n9.py`。", "",
           "🔴 **本页要回答的唯一问题**：把判据从 **n=3** 换成 **n=9** 之后，"
           "`ablation_results.md` 里的读数**哪些还站得住、哪些翻了**。", "",
           "**设计**：9 对 = `ts ∈ {0,1,2} × ss ∈ {0,1,2}`（**训练种子 × 划分种子**，两者分离）。"
           "同一 `(ts, ss)` 上臂与基线**同划分、同初始化** ⇒ 配对比较消掉划分与初始化的方差。", "",
           "🔴 **复用的三个来源**（详见 `run_ablation_n9.py` 的模块 docstring）："
           "对角臂 run 取 `runs/ablation{,_aug}/<item>/seed{S}`；① 的 9 对基线取 "
           "`runs/cbft_study/cbft_ts{T}_ss{S}`（**论文正典 `runs/seed{S}` 正是由它的对角提升而来**，"
           "见其 `config.json::promoted_from`）；② 的对角基线取 `runs/augmentation/seed{S}`。"
           "复用的合法性由**逐 run 逐键对拍 config** 在开跑前验证。", "",
           f"**多重比较**：本页检验 **{len(items)} 臂 × {len(METRICS)} 指标 = {N_TESTS} 个**假设 "
           f"⇒ 单看 `|t|>{T_CRIT_9}` 期望有约 {N_TESTS * 0.05:.0f} 个假阳性。"
           f"故 `★★` 标注另给 Bonferroni 参考阈值，且**建议只把「同号 ≥8/9 且指标族内多处一致」"
           "的项当作结论**（本仓纪律 §26.7/§27.5）。", ""]

    for g in groups:
        group_section(g, doc)

    doc += ["---", "",
            "## 附：口径速查", "",
            f"- 判方向门槛：n=9 ⇒ df=8 ⇒ |t| > {T_CRIT_9}；n=3 ⇒ df=2 ⇒ |t| > {T_CRIT_3}。",
            "- `support ≤ 2` 的类只作描述性呈现、不进方法间比较结论（`decisions.md` §13）。",
            "- ①② **各自独立完整、不跨组比较**（`decisions.md` §23）。",
            "- 本页**不重训**：全部读数来自各 run 的 `results.json`（`evaluate.py` 产物）。", ""]

    out = REPO / args.out
    out.write_text("\n".join(doc) + "\n", encoding="utf-8")
    print(f"[n9-summary] → {out}")

    # JSON 落盘：Δ 的 values 是逐对明细，供后续复算方差/做图
    jout = REPO / args.json_out
    jout.parent.mkdir(parents=True, exist_ok=True)
    jout.write_text(json.dumps(groups, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[n9-summary] → {jout}")

    # 控制台摘要：只打有信息量的（显著 / 翻转）
    for g in groups:
        print(f"\n=== {g['title']}（基线 n={g['baseline'][HEADLINE][2]}）===")
        for item, rec in g["arms"].items():
            d = rec["delta"].get(HEADLINE)
            if not d:
                continue
            mark = _star(d["t"], d["n"])
            if mark:
                print(f"  {item:16s} Δ{HEADLINE} {d['mean']:+.4f} t={d['t']:+.2f} "
                      f"{d['n_pos']}+/{d['n_neg']}− {mark}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
