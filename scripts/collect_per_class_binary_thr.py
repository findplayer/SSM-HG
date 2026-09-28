#!/usr/bin/env python3
"""**主库两条谱系 ×（正典 + 21 个消融臂）**的逐类 binary-F1 @逐类验证集阈值表。

用户 2026-09-27 指令：「输出主库正典（含 `buggy_*`）和逐个消融选项的逐类 binary-F1@逐类
验证集阈值 + micro-F1@逐类验证集阈值 + macro-F1@逐类验证集阈值 的表格」。

**这张表回答什么**：把「七类共享一个阈值」换成「每类各自一个阈值（只在 val 上按该类自身的
F1 选）」之后，**每个消融选项在七个类上分别是什么读数**。它相对
`experiments/ablation_three_metric_table.md`（全局 `val_threshold` 工作点）的**唯一新增信息**
就是「阈值逐类独立」这一件事——列名与行名都对齐那张表。

🔴 **不重实现任何指标、不重搜任何阈值**（本仓最忌讳「同一语义两处实现」，见 §28 的教训）：
  - 逐类 P/R/F1 ← `metrics.per_class_prf`（唯一事实来源）
  - micro-F1 / macro-F1 ← `metrics.micro_f1` / `metrics.macro_f1`
  - 逐类阈值 ← **`calibrate.per_class_thresholds`**（仓库里 per-class 阈值的唯一实现，
    `eval_results/calibration/` 的存量产物即出自它；`collect_baseline_tables._pc_pairs`
    与 `collect_perclass_arm` 走的也是这一条路）
  - 应用阈值 ← `calibrate.apply_per_class`
  - 消融臂的策展文本（层 / 变量说明）← `collect_ablation_three_metric.LAYERS`（同一份，不抄第二份）

两条硬机检（**默认执行，不通过即拒绝出表**）：
  ① **对拍**：canon37 正典那一行的 7 个逐类格 + micro + macro，必须与存量审计产物
     `eval_results/calibration/summary.json::test_schemes.per_class_threshold` **逐位相同**
     （容差 1e-6）⇒ 证明本脚本没有第二套 per-class 阈值实现。
  ② **恒等式**：每行每种子的 `metrics.macro_f1` 必须**逐位等于**其 7 个逐类 F1 的算术平均
     （`zero_division=0` 下二者数学恒等）⇒ 一旦分叉，说明类序或 zero 处理被改动过。

⚠ **两条谱系的 test 集不是同一个**（池 453 剔除了全部 `buggy_*`；池 497 含它们）⇒
**两表之间的数字不得相减**。表内跨行可比（同池同划分同种子）。

用法（仓库根目录）：
    python scripts/collect_per_class_binary_thr.py              # 只打印（含机检）
    python scripts/collect_per_class_binary_thr.py --write      # 落盘 md + json
    python scripts/collect_per_class_binary_thr.py --no-check   # 跳过机检（仅在确知对拍对象过期时）
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
import metrics                                   # noqa: E402
import calibrate as CAL                          # noqa: E402
import collect_ablation_three_metric as ATM      # noqa: E402  # 复用 LAYERS 策展文本

NAMES = metrics.VULN_NAMES
SEEDS = (0, 1, 2)
OUT_MD = REPO / "experiments" / "per_class_binary_thr_ablation.md"
OUT_JSON = REPO / "eval_results" / "per_class_binary_thr.json"

POOLS: tuple[dict, ...] = (
    {
        "key": "canon37",
        "table_no": 1,
        "pool_label": "① §37 谱系",
        "pool_desc": "池 **453**，已剔除全部 `buggy_*`；train/val/test = 362/45/46",
        "canon": "runs/seed{seed}",
        "arm": "runs/ablation/{arm}/seed{seed}",
        "calib_ref": "eval_results/calibration/summary.json",
    },
    {
        "key": "buggy",
        "table_no": 2,
        "pool_label": "② 任务2 谱系",
        "pool_desc": "池 **497**，**含** `buggy_*` 合成注入合约；train/val/test = 398/50/49",
        "canon": "runs/buggy_canon/seed{seed}",
        "arm": "runs/ablation_buggy/{arm}/seed{seed}",
        "calib_ref": None,
    },
)


# ------------------------------------------------------------------ 读取与计算
def read_run(run_tmpl: str, seed: int) -> dict | None:
    """一个 run 在**逐类验证集阈值**工作点下的读数。

    返回 `{per_class_f1[7], macro_from_pc, micro, macro, support[7], thresholds{类名→t}}`；
    产物缺失返回 None（**不静默回退到别的来源**）。
    """
    rd = REPO / run_tmpl.format(seed=seed)
    tp, vp = rd / "test_probs.pt", rd / "val_best_probs.pt"
    if not (tp.exists() and vp.exists()):
        return None
    dt = torch.load(tp, map_location="cpu")
    dv = torch.load(vp, map_location="cpu")
    y = dt["labels"].numpy().astype(int)
    p = dt["probs"].numpy()
    vy = dv["labels"].numpy().astype(int)
    vpp = dv["probs"].numpy()
    th = CAL.per_class_thresholds(vpp, vy)["thresholds"]     # **只在 val 上选**
    pred = CAL.apply_per_class(p, th)
    prf = metrics.per_class_prf(y, pred, names=NAMES)
    f1 = [float(v) for v in prf["f1"]]
    return {
        "per_class_f1": f1,
        "macro_from_pc": float(np.mean(f1)),
        "micro": metrics.micro_f1(y, pred),
        "macro": metrics.macro_f1(y, pred),
        "support": y.sum(axis=0).astype(int).tolist(),
        "n_test": int(y.shape[0]),
        "thresholds": {n: float(th[n]) for n in NAMES},
    }


def collect(tmpl: str) -> list[dict]:
    return [r for r in (read_run(tmpl, s) for s in SEEDS) if r is not None]


def _ms(vals, nd=6) -> dict:
    """mean±std(ddof=1)。⚠ 默认 **6 位**（同 `collect_per_class_f1._ms`）——表格显示时才降到 4 位；
    对拍一律走**未舍入**的逐种子原始值（`_raw_*`），绝不用这里的舍入值（曾因此误报 7 处差异）。"""
    v = [float(x) for x in vals if x is not None]
    if not v:
        return {"mean": None, "std": None, "n": 0}
    return {"mean": round(float(np.mean(v)), nd),
            "std": round(float(np.std(v, ddof=1)), nd) if len(v) > 1 else 0.0,
            "n": len(v)}


def entry(raw: list[dict]) -> dict:
    """一行 = 一个（臂 × 池），跨种子 mean±std(ddof=1)。"""
    return {
        "n_seeds": len(raw),
        "per_class_f1": {n: _ms([r["per_class_f1"][i] for r in raw]) for i, n in enumerate(NAMES)},
        "micro": _ms([r["micro"] for r in raw]),
        "macro": _ms([r["macro"] for r in raw]),
        "micro_per_seed": [float(r["micro"]) for r in raw],   # 不 round：对拍要用真值
        "macro_per_seed": [float(r["macro"]) for r in raw],
        "support": ([float(np.mean([r["support"][i] for r in raw])) for i in range(len(NAMES))]
                    if raw else None),
        "n_test": (int(raw[0]["n_test"]) if raw else None),
        "thresholds": {n: {"mean": round(float(np.mean([r["thresholds"][n] for r in raw])), 4),
                           "per_seed": [r["thresholds"][n] for r in raw],
                           "range": round(float(max(r["thresholds"][n] for r in raw)
                                                 - min(r["thresholds"][n] for r in raw)), 4)}
                       for n in NAMES} if raw else None,
    }


# ------------------------------------------------------------------ 机检
def check_identity(all_rows: dict) -> list[str]:
    """恒等式：`macro_f1` ≡ 7 个逐类 F1 的算术平均（本脚本内部一致性）。"""
    bad = []
    for pool, rows in all_rows.items():
        for r in rows:
            for s, (pc, mac) in enumerate(zip(r["_raw_pc"], r["_raw_macro"])):
                if abs(mac - float(np.mean(pc))) > 1e-9:
                    bad.append(f"{pool}/{r['arm']}/seed{s}: macro {mac:.12f} != mean(逐类) "
                               f"{float(np.mean(pc)):.12f}")
    return bad


def check_against_calibration(all_rows: dict) -> list[str]:
    """对拍：canon37 正典行 ↔ `eval_results/calibration/summary.json`（存量审计产物）。"""
    bad: list[str] = []
    ref_p = REPO / "eval_results/calibration/summary.json"
    row = next((r for r in all_rows.get("canon37", []) if r["arm"] == "canon"), None)
    if row is None:
        return ["canon37 正典行缺失"]
    if not ref_p.exists():
        return [f"缺对拍对象 {ref_p}"]
    sc = json.loads(ref_p.read_text(encoding="utf-8"))["test_schemes"]["per_class_threshold"]
    # 🔴 一律用**未舍入**的逐种子原始值取均值：存量产物是 6 位舍入值，若拿本脚本的显示值
    #    （4 位）来比就会误报 7 处「差异」（2026-09-27 首次运行踩到）。
    for i, n in enumerate(NAMES):
        a = float(np.mean([pc[i] for pc in row["_raw_pc"]]))
        b = sc["per_class_f1"][n]["mean"]
        if abs(a - b) > 1e-6:
            bad.append(f"canon37/{n}: 复算 {a:.6f} != 存量 {b:.6f}")
    for key, mine, b in (("micro", row["micro_per_seed"], sc["micro_f1"]["mean"]),
                         ("macro", row["macro_per_seed"], sc["macro_f1"]["mean"])):
        a = float(np.mean(mine))
        if abs(a - b) > 1e-6:
            bad.append(f"canon37/{key}: 复算 {a:.6f} != 存量 {b:.6f}")
    return bad


# ------------------------------------------------------------------ 渲染
def fmt(ms) -> str:
    if not ms or ms.get("mean") is None:
        return "—"
    return f"{ms['mean']:.4f}±{ms['std']:.4f}"


def table_block(pool: dict, rows: list[dict]) -> list[str]:
    out = [f"## 表 {pool['table_no']} —— {pool['pool_label']}（{pool['pool_desc']}）", "",
           "| 层 | 臂 | 变量（唯一改动） | " + " | ".join(NAMES)
           + " | micro-F1 | macro-F1 |",
           "|---|---|---|" + "---|" * (len(NAMES) + 2)]
    for r in rows:
        out.append(f"| {r['layer']} | {r['arm_disp']} | {r['var']} | "
                   + " | ".join(fmt(r["per_class_f1"][n]) for n in NAMES)
                   + f" | {fmt(r['micro'])} | {fmt(r['macro'])} |")
    sup = next((r["support"] for r in rows if r.get("support")), None)
    if sup:
        n_test = next((r["n_test"] for r in rows if r.get("n_test")), None)
        # 🔴 低支持警告必须**按池自适应**：池 453 的 `dos`/`front_running` 只有 1 个正样本，
        #    池 497 最低也有 6.3 —— 把表 1 的那句警告原样搬到表 2 会造出一个不存在的限制。
        lo = [f"{n} {v:.0f}" for n, v in zip(NAMES, sup) if v <= 2]
        out += ["", "> 测试集逐类 support（3 种子均值"
                + (f"；test 合约数 {n_test}" if n_test else "") + "）："
                + "、".join(f"{n} {v:.1f}" for n, v in zip(NAMES, sup))
                + "。⚠ 逐类 support 之和 **≠** test 合约数（多标签，一个合约可含多类）。"]
        if lo:
            out += ["> 🔴 **本表的低支持类是 " + "、".join(lo) + "**（3 种子均值 ≤2）——这些类上单类 F1 "
                    "一次翻转就能差 0.5 以上 ⇒ **跨臂 Δ 在它们上不可解读**，只能当「有没有报出来」看。"]
        else:
            out += ["> 本表逐类 support 均 **≥3**（最低 " + f"{min(sup):.1f}" + "）"
                    "⇒ 单类 F1 的翻转敏感性低于池 453 那张表；但 n=3 的 std 仍不作方向性判据"
                    "（须同配对 ≥9 点）。"]
    return out


def render(all_rows: dict, entries: dict) -> str:
    doc: list[str] = [
        "# 逐类 binary-F1 @逐类验证集阈值：主库两条谱系的正典 + 逐个消融选项",
        "",
        "> 🔴 **本文件由 `scripts/collect_per_class_binary_thr.py` 程序生成，不要手改。**",
        "> 生成：`python scripts/collect_per_class_binary_thr.py --write`；"
        "复算（含两条机检）：`python scripts/collect_per_class_binary_thr.py`。",
        "",
        "## 0. 口径（先读，否则整张表会读反）",
        "",
        "| 项 | 本表取值 |",
        "| --- | --- |",
        "| **每一格** | 「该合约**是否含第 c 类**漏洞」这个**独立二分类问题**的 F1"
        "（`metrics.per_class_prf`，7 类各自成题、互不影响） |",
        "| **判决阈值** | $t_c$ **逐类各一个**，**只在验证集**上按该类自身的 F1 选"
        "（候选 0.20–0.80 步长 0.05，并列取小；`calibrate.per_class_thresholds`） |",
        "| **micro-F1** | 标签对级全局 F1（阈值逐类不同 ⇒ **不是**任何单点工作点的 micro） |",
        "| **macro-F1** | 7 类 F1 的**未加权平均**——与表内 7 个逐类格**逐位恒等**（已机检） |",
        "| **种子聚合** | 3 种子 mean±std（**ddof=1**） |",
        "",
        "🔴 **本表与主口径不是一个工作点**：现行主口径是「七类共享一个 `val_threshold`」"
        "（见 `experiments/ablation_three_metric_table.md`）。换成逐类阈值后"
        "**macro 升、micro 降**（正典：macro +0.0484 / micro −0.0417，见 `experiments/p1_gains.md`）"
        "⇒ 它是**并列口径**，不得作为「更好的主口径」引用。",
        "",
        "🔴 **逐类阈值的过拟合已量化**：主库 val 每类只有 1–3 个正样本，`dos` 的阈值三种子"
        "极差达 0.55，val→test 落差最大 0.16（审计见 `eval_results/calibration/summary.json::"
        "overfit_audit` 与 `experiments/gcn_baseline_and_per_class_f1.md` §3）。**本表的 std 里"
        "同时含「模型种子」与「阈值抖动」两个来源**，别把 std 读成纯模型方差。",
        "",
        "⚠ **两条谱系的 test 集不同**（表 1 池 453 **已剔除**全部 `buggy_*`；表 2 池 497 **含**它们，"
        "且 `buggy_*` 是 100% 正例的合成注入合约）⇒ **两表之间不得相减**；表内跨行可比"
        "（同池、同划分、同训练种子）。",
        "",
    ]
    for pool in POOLS:
        rows = entries[pool["key"]]
        doc += table_block(pool, rows)
        doc += [""]
    doc += [
        "## 机检（每次生成都跑，不通过即拒绝出表）",
        "",
        "① **对拍**：表 1「正典」行的 7 个逐类格 + micro + macro，与存量审计产物",
        "`eval_results/calibration/summary.json::test_schemes.per_class_threshold` **逐位相同**",
        "（容差 1e-6）⇒ 本脚本没有第二套 per-class 阈值实现。",
        "",
        "② **恒等式**：每行每种子的 `metrics.macro_f1` **逐位等于**其 7 个逐类 F1 的算术平均"
        "（`zero_division=0` 下数学恒等）⇒ 类序与 zero 处理未被改动。",
        "",
        "⚠ 表 2（pool 497）**无存量审计产物可比**（`eval_results/calibration/` 只有池 453 的），"
        "故只有机检 ② 覆盖它——这是本表在两条谱系上唯一的**非对称**。",
        "",
        "## 三条读表须知",
        "",
        "1. **消融的「层」与「变量」两列**逐字取自 `collect_ablation_three_metric.LAYERS`"
        "（与 `ablation_three_metric_table.md` 同源），**不是**本脚本另写的一份。",
        "2. **n=3 只作描述性读数**：判「干预有效/无效」须同配对 ≥9 点"
        "（`decisions.md` §26.7/§27.5；n=9 见 `experiments/ablation_n9_results.md`）。",
        "3. **正典行的微调编码器档 = 20 轮**（`runs/seed{S}` / `runs/buggy_canon/seed{S}`），"
        "与表内全部消融臂同代；若换正典须重跑本脚本。",
        "4. **与 `experiments/ablation_three_metric_table.md` 的关系**：两张表的**行名、层名、"
        "臂集合完全相同**，唯一差别是**工作点**——那张表 = 七类共享一个 `val_threshold`，"
        "本表 = 阈值逐类各一。⇒ 想回答「某消融在某一类上到底怎样」时用本表；"
        "想报论文主口径（micro@val_thr）时用那张表。**两表数字不得互相替代**。",
        "",
    ]
    return "\n".join(doc) + "\n"


# ------------------------------------------------------------------ 主流程
def build() -> tuple[dict, dict]:
    """→ (`all_rows` 逐池行列表, `entries` 逐池表格行)。`all_rows` 含原始逐种子读数（供机检）。"""
    all_rows: dict[str, list] = {}
    entries: dict[str, list] = {}
    for pool in POOLS:
        rows = []
        canon_raw = collect(pool["canon"])
        if canon_raw:
            e = entry(canon_raw)
            e.update({"arm": "canon", "layer": "—",
                      "arm_disp": "**正典**",
                      "var": "**微调 CodeBERT + 全部组件**",
                      "_raw_pc": [r["per_class_f1"] for r in canon_raw],
                      "_raw_macro": [r["macro"] for r in canon_raw]})
            rows.append(e)
        for layer, arm, var in ATM.LAYERS:
            raw = collect(pool["arm"].replace("{arm}", arm))
            if not raw:
                rows.append({"arm": arm, "layer": layer, "arm_disp": f"`{arm}`", "var": var,
                             "per_class_f1": {n: _ms([]) for n in NAMES},
                             "micro": _ms([]), "macro": _ms([]), "support": None,
                             "thresholds": None, "_raw_pc": [], "_raw_macro": []})
                continue
            e = entry(raw)
            e.update({"arm": arm, "layer": layer, "arm_disp": f"`{arm}`", "var": var,
                      "_raw_pc": [r["per_class_f1"] for r in raw],
                      "_raw_macro": [r["macro"] for r in raw]})
            rows.append(e)
        entries[pool["key"]] = rows
        all_rows[pool["key"]] = rows
    return all_rows, entries


def main() -> int:
    ap = argparse.ArgumentParser(description="逐类 binary-F1 @逐类验证集阈值（正典 + 消融）")
    ap.add_argument("--write", action="store_true", help="落盘 md + json")
    ap.add_argument("--no-check", action="store_true", help="跳过机检（默认执行）")
    args = ap.parse_args()

    all_rows, entries = build()
    doc = render(all_rows, entries)
    print(doc)

    if not args.no_check:
        bad = check_identity(all_rows) + check_against_calibration(all_rows)
        if bad:
            print("\n🔴 机检失败，拒绝落盘：")
            for b in bad:
                print("   -", b)
            return 1
        print("\n[机检] ✅ 恒等式（macro ≡ 逐类平均）逐位成立；"
              "✅ 表 1 正典行与 eval_results/calibration/summary.json 逐位相同")

    if args.write:
        OUT_MD.write_text(doc, encoding="utf-8")
        payload = {
            "note": "逐类 binary-F1 @逐类验证集阈值；正典 + 21 个消融臂 × 两条谱系。"
                    "阈值由 calibrate.per_class_thresholds 只在 val 上选；"
                    "指标由 metrics.per_class_prf/micro_f1/macro_f1 计算（本脚本不重实现）。"
                    "两池 test 集不同，不得相减。",
            "workpoint": "per_class_val_threshold",
            "pools": {p["key"]: {"canon_run": p["canon"], "arm_run": p["arm"],
                                 "calib_ref": p["calib_ref"]} for p in POOLS},
            "classes": NAMES,
            "rows": {k: [{kk: vv for kk, vv in r.items() if not kk.startswith("_")}
                         for r in v] for k, v in all_rows.items()},
        }
        OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
        OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"\n已落盘：{OUT_MD}\n已落盘：{OUT_JSON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
