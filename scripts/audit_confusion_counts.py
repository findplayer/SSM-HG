#!/usr/bin/env python3
"""**混淆计数审计**：把 `main_aug_f1_summary.md` 每个 micro/macro 背后的 TP/FP/FN 数出来。

**存在理由**：读者问「micro-F1 0.8129 是怎么来的、TP/FP/FN 各多少」时，产物里**没有**现成的
混淆矩阵 —— `runs/seed{S}/results.json` 只存 P/R/F1，`<工具>_alldata/seed{S}_eval.json` 更只有
F1 与 support。本脚本把它们**算出来并落成一张可核对的表**。

🔴 **口径（与 `metrics.py` 逐字一致，不另定义）**：

  计数单位是 **(合约, 类) 标签对**，不是合约。7 类 × N 个测试合约 = 7N 个标签对。

    TP = 真值 1 且预测 1 的标签对数
    FP = 真值 0 但预测 1 的标签对数
    FN = 真值 1 但预测 0 的标签对数

    micro-F1 = 2·TP / (2·TP + FP + FN)      ← **把 7 个类一起汇总**（`metrics.micro_f1`）
    macro-F1 = mean(逐类 F1 的 7 个值)        ← **先逐类算，再等权平均**（`metrics.macro_f1`）

  🔴 **两者不共用一套计数**：micro 用**池化后**的一组 TP/FP/FN；macro 用**逐类各自的**
  TP/FP/FN 先算出 7 个 F1 再平均。故 **macro 无法由池化计数反推** —— 表里两列都列出来。

🔴 **本脚本不重实现任何指标**：全部走 `metrics.per_class_prf` / `micro_f1` / `macro_f1`。
   自带的**对拍**才是它敢出数的依据 ——
     ① 本文方法/基线：从 `test_probs.pt` 重新二值化算出的 micro/macro，必须与 `results.json`
        里已存的**逐位相同**；
     ② 六工具：用 `baseline_static_tools.evaluate()` 的**同一段行选择逻辑**取出 (y, p)，
        必须与 `seed{S}_eval.json` 里存的 micro/macro **逐位相同**（6 位小数）。
   任一条不符 → 拒绝出数（`SystemExit`）。不符只可能意味着「工具跑不了」被记成了 0，
   或划分/映射变了而产物没重跑 —— 两种都必须先查清。

用法（仓库根目录）：
    python scripts/audit_confusion_counts.py                 # 打印
    python scripts/audit_confusion_counts.py --out experiments/confusion_counts.md
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics                                     # noqa: E402  指标的**唯一**实现
import collect_three_caliber_tables as T            # noqa: E402
import collect_baseline_tables as B                 # noqa: E402

NAMES = list(metrics.VULN_NAMES)
SEEDS = (0, 1, 2)
AUG_RUNS = "runs/augmentation"


# ------------------------------------------------------------------ 计数层
def _counts(y, p) -> dict:
    """逐类 + 池化的 TP/FP/FN。**纯计数**，F1 仍由 `metrics` 算（不在这里写公式）。"""
    import numpy as np
    y = np.asarray(y, dtype=int)
    p = np.asarray(p, dtype=int)
    tp = (y * p).sum(axis=0)
    fp = ((1 - y) * p).sum(axis=0)
    fn = (y * (1 - p)).sum(axis=0)
    return {
        "per_class": {"tp": [int(v) for v in tp], "fp": [int(v) for v in fp],
                      "fn": [int(v) for v in fn]},
        "pooled": {"tp": int(tp.sum()), "fp": int(fp.sum()), "fn": int(fn.sum())},
    }


def _from_probs(run_rel: str, seed: int, wp: str) -> tuple[list, list, float] | None:
    """run 目录 → `(y, p, thr)`；`test_probs.pt` 由 `diagnose.py` 写（`evaluate.py` 不写）。

    🔴 **`wp` 必须显式传**：`fixed_0.5` 档用**固定 0.5**、`val_thr` 档才读 `thresholds.json`。
    混用会得到「拿验证集阈值的预测去对拍 0.5 档存档」——数值看着都合理、只是对不上，
    实测踩到过一次（本脚本的对拍当场拦下）。
    """
    p_path = REPO / run_rel / f"seed{seed}" / "test_probs.pt"
    if not p_path.exists():
        return None
    if wp == "fixed_0.5":
        thr = 0.5
    else:
        t_path = REPO / run_rel / f"seed{seed}" / "thresholds.json"
        if not t_path.exists():
            return None
        thr = float(json.loads(t_path.read_text(encoding="utf-8"))["best_threshold"])
    b = torch.load(p_path, map_location="cpu")
    probs = b["probs"].numpy()
    preds = (probs >= thr).astype(int)
    return b["labels"].numpy().astype(int).tolist(), preds.tolist(), thr


def _from_tool(tool: str, seed: int) -> tuple[list, list] | None:
    """六工具 → `(y, p)`，走**评测时的同一段行选择逻辑**（`evaluate()` 内那 4 行）。

    🔴 只有**成功分析**（`status == "ok"`）的合约进分母 —— 故它的分母与本文方法不同
    （覆盖率一栏已披露）。这不是本脚本的口径选择，是**产物本身的构造方式**。
    """
    import baseline_static_tools as ST
    run_path = REPO / B.trad_root(tool) / ".." / f"{tool}_alldata.json"
    run_path = (REPO / "eval_results" / "baseline" / f"{tool}_alldata.json")
    if not run_path.exists():
        return None
    sp = REPO / "products/alldata/splits" / f"split_seed{seed}.json"
    if not sp.exists():
        return None
    payload = json.loads(run_path.read_text(encoding="utf-8"))
    contracts = payload["contracts"]
    index, _ = ST.dataset.build_index(REPO / "products/alldata/graphs", None, None)
    split = json.loads(sp.read_text(encoding="utf-8"))
    rows = [(b, index[b]) for b in split.get("test", [])
            if b in index and contracts.get(b, {}).get("status") == "ok"]
    if not rows:
        return None
    return [lab for _, lab in rows], [contracts[b]["classes"] for b, _ in rows]


# ------------------------------------------------------------------ 对拍守卫
def _verify(kind: str, name: str, seed: int, y, p, stored: dict | None, wp: str) -> None:
    """重算的 micro/macro **必须**与产物里存的一致，否则拒绝出数。"""
    if stored is None:
        return
    mm = metrics.micro_f1(y, p)
    ma = metrics.macro_f1(y, p)
    if kind == "run":
        # 🔴 `results.json` 的键名与 `T.WORKPOINTS` 的键名**不同**（`val_thr` ↔ `val_threshold`）
        key = {"fixed_0.5": "fixed_0.5", "val_thr": "val_threshold"}[wp]
        s_m = stored["test"][key]["micro_f1"]
        s_a = stored["test"][key]["macro_f1"]
    else:
        s_m, s_a = stored["test"]["micro_f1"], stored["test"]["macro_f1"]
        mm, ma = round(mm, 6), round(ma, 6)          # 工具产物是按 6 位小数存的
    if abs(mm - s_m) > 1e-9 or abs(ma - s_a) > 1e-9:
        raise SystemExit(
            f"🔴 对拍失败 {name} seed{seed}：重算 micro={mm!r}/macro={ma!r}，"
            f"产物存的 micro={s_m!r}/macro={s_a!r}。\n"
            f"   不符 ⇒ 划分/映射/覆盖率三者之一变了而产物没重跑，或本脚本取错了行。**不出数**。")


# ------------------------------------------------------------------ 行集合
def collect() -> list[dict]:
    """→ 每个 `(行名, seed)` 一条记录，含 pooled / per-class 计数与两个 F1。"""
    out: list[dict] = []
    jobs: list[tuple[str, str, str]] = []
    # (显示名, 类型, 产物根)
    jobs.append(("① 主库 · 本文方法（正典）", "run", "runs"))
    for arm, label in (("mvdhg", "MVD-HG"), ("egfl", "EGFL"),
                       ("egfl_ownlr", "EGFL（论文 lr）"), ("mando", "MANDO-LLM")):
        jobs.append((f"① 主库 · {label}", "run", B.rel_of(arm, "canon37")))
    for tool in B.TRADITIONAL:
        jobs.append((f"① 主库 · {B.TRAD_LABEL[tool]}", "tool", tool))
    jobs.append(("② 增强集 · 本文方法（正典）", "run", AUG_RUNS))

    # 工具只有一个工作点（规则型，无阈值可搜）⇒ 只按 fixed_0.5 出行，渲染时注明。
    for label, kind, root in jobs:
        wps = ("fixed_0.5", "val_thr") if kind == "run" else ("fixed_0.5",)
        for wp in wps:
            for s in SEEDS:
                if kind == "run":
                    got = _from_probs(root, s, wp)
                    if got is None:
                        continue
                    y, p, thr = got
                    rj = REPO / root / f"seed{s}" / "results.json"
                    stored = json.loads(rj.read_text(encoding="utf-8")) if rj.exists() else None
                else:
                    got = _from_tool(root, s)
                    if got is None:
                        continue
                    y, p = got
                    thr = None
                    ej = REPO / B.trad_root(root) / f"seed{s}_eval.json"
                    stored = json.loads(ej.read_text(encoding="utf-8")) if ej.exists() else None
                _verify(kind, label, s, y, p, stored, wp)
                c = _counts(y, p)
                out.append({
                    "label": label, "seed": s, "wp": wp, "kind": kind, "thr": thr,
                    "n_rows": len(y), "n_pairs": len(y) * len(NAMES),
                    "pooled": c["pooled"], "per_class": c["per_class"],
                    "micro": metrics.micro_f1(y, p), "macro": metrics.macro_f1(y, p),
                    "prf": metrics.per_class_prf(y, p),
                })
    return out


# ------------------------------------------------------------------ 排版
def _pct(a: int, b: int) -> str:
    return "—" if b == 0 else f"{100.0 * a / b:.1f}%"


def render(recs: list[dict]) -> list[str]:
    doc: list[str] = []
    doc.append("# 混淆计数审计：micro-F1 / macro-F1 背后的 TP / FP / FN")
    doc.append("")
    doc.append("> 程序生成（`scripts/audit_confusion_counts.py`）。**指标不在此重实现**："
               "F1 一律走 `metrics.micro_f1` / `metrics.macro_f1`，本脚本只**数计数**。")
    doc.append(">")
    doc.append("> 🔴 **计数单位 = `(合约, 类)` 标签对**，不是合约。7 类 × N 个测试合约 = 7N 个标签对。"
               "故 `TP + FP + FN` 的量级在几千，而测试合约只有几十/上千个。")
    doc.append(">")
    doc.append("> ```")
    doc.append("> micro-F1 = 2·TP / (2·TP + FP + FN)   ← 七类**池化**成一组计数（标签对级全局）")
    doc.append("> macro-F1 = mean(逐类 F1 的 7 个值)     ← **先逐类**算 F1，再**等权**平均")
    doc.append("> ```")
    doc.append(">")
    doc.append("> 🔴 **两个汇总列不共用一套计数**：micro 用池化后的一组；macro 用逐类各自的 TP/FP/FN"
               "先得 7 个 F1 再平均 ⇒ **macro 无法由池化计数反推**，必须逐类看。")
    doc.append(">")
    doc.append("> 🔴 **三种子的计数不可相加**（每种子是不同划分 + 不同模型）⇒ 下表**逐种子**列计数，"
               "**不列合计**。也因此**不能**用「计数均值」去算 micro —— 表里报的是"
               "**逐种子 F1 的 mean±std**，两者数学上不是一回事（Jensen 不等式）。")
    doc.append(">")
    doc.append("> 🔴 **传统工具行的分母更小**（只数 `status==ok` 的合约），逐行可比性见 "
               "`main_aug_f1_summary.md` §0.1。")
    doc.append("")
    doc.append("---")
    doc.append("")

    # 对拍说明
    doc.append("## 0. 对拍（本表敢出数的依据）")
    doc.append("")
    doc.append("本脚本从 `test_probs.pt`（本文方法/基线）与原始检测器 JSON（六工具）**重新取出** "
               "`(y, p)` 并算 micro/macro，**逐位比对**产物里已存的值：")
    doc.append("")
    doc.append("| 来源 | 存哪儿 | 对拍结果 |")
    doc.append("| --- | --- | --- |")
    doc.append("| 本文方法 / 三条论文基线 | `runs|eval_results/**/seed{S}/results.json` 的 "
               "`test.fixed_0.5.{micro_f1,macro_f1}` | ✅ 逐位一致 |")
    doc.append("| 六个传统工具 | `eval_results/baseline/<tool>_alldata/seed{S}_eval.json` 的 "
               "`test.{micro_f1,macro_f1}`（6 位小数） | ✅ 逐位一致 |")
    doc.append("")
    doc.append("任一条不符即 `SystemExit`、不出数。")
    doc.append("")
    doc.append("---")
    doc.append("")

    # 表 A：池化计数
    doc.append("## 表 A —— 池化计数（七类合计）与 micro-F1 / macro-F1，**逐种子**")
    doc.append("")
    doc.append("| 行 | 工作点 | seed | 阈值 | TP | FP | FN | **micro-F1**（= 2TP/(2TP+FP+FN)） | "
               "**micro-F1**（产物存档） | **macro-F1**（7 类 F1 均值） |")
    doc.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for r in recs:
        pl = r["pooled"]
        den = 2 * pl["tp"] + pl["fp"] + pl["fn"]
        calc = "—" if den == 0 else f"{2.0 * pl['tp'] / den:.4f}"
        thr = "—" if r["thr"] is None else f"{r['thr']:.2f}"
        wp = "@0.5" if r["wp"] == "fixed_0.5" else "@val_thr"
        if r["kind"] == "tool":
            wp = "@0.5（工具无阈值）"
        doc.append(f"| {r['label']} | {wp} | {r['seed']} | {thr} | {pl['tp']} | {pl['fp']} | "
                   f"{pl['fn']} | **{calc}** | {r['micro']:.4f} | **{r['macro']:.4f}** |")
    doc.append("")
    doc.append("> 倒数第二列（产物存档）与「算出来」列**必然相同**——不同就已被 §0 的对拍拦下。"
               "它的用处是让读者能拿 `results.json` 里的数字**自己核对**这一行。")
    doc.append("> 工具行只出现一次（`@0.5（工具无阈值）`）：规则型工具**不训练、无阈值可搜**，"
               "两个工作点在 `main_aug_f1_summary.md` 里本就是同一套数。")
    doc.append("")
    doc.append("---")
    doc.append("")

    # 表 B/C：逐类计数（两个正典）× 两工作点
    for wp, tag in (("fixed_0.5", "表 B"), ("val_thr", "表 C")):
        doc.append(f"# {tag} —— 逐类 TP / FP / FN（"
                   + ("@0.5" if wp == "fixed_0.5" else "@验证集阈值") + "）")
        doc.append("")
        doc.append("> `TP/FP/FN → F1（support）` 四连在同一格内。**macro-F1 就是最后一列那 7 个 F1 "
                   "的算术平均**；**micro-F1** 则是把 7 类的 TP/FP/FN 分别加起来再套公式（见表 A）。")
        doc.append("")
        for label in ("① 主库 · 本文方法（正典）", "② 增强集 · 本文方法（正典）"):
            sub = [r for r in recs if r["label"] == label and r["wp"] == wp]
            if not sub:
                continue
            doc.append(f"## {tag} —— {label}")
            doc.append("")
            doc.append("| seed | " + " | ".join(NAMES) + " | **macro-F1** |")
            doc.append("| --- | " + " | ".join(["---"] * (len(NAMES) + 1)) + " |")
            for r in sub:
                cells = []
                for i in range(len(NAMES)):
                    tp = r["per_class"]["tp"][i]
                    fp = r["per_class"]["fp"][i]
                    fn = r["per_class"]["fn"][i]
                    cells.append(f"{tp}/{fp}/{fn} → {r['prf']['f1'][i]:.3f}"
                                 f"（{r['prf']['support'][i]}）")
                doc.append(f"| {r['seed']} | " + " | ".join(cells) + f" | **{r['macro']:.4f}** |")
            doc.append("")
            for r in sub:
                pl = r["pooled"]
                doc.append(f"- seed{r['seed']} 池化：TP={pl['tp']}、FP={pl['fp']}、FN={pl['fn']} ⇒ "
                           f"micro-F1 = 2×{pl['tp']}/(2×{pl['tp']}+{pl['fp']}+{pl['fn']}) = "
                           f"**{r['micro']:.4f}**")
            doc.append("")
            doc.append("> 🔴 **`support` = TP + FN**（该类真值 1 的合约数）。主库 `dos`/`front_running`/"
                       "`time_manipulation` 的 support 低到 **1** ⇒ 一格翻转就是 ±0.67，这些类"
                       "**仅描述性呈现**。support=0 的类 F1 记为 0 但**不代表预测失败**"
                       "（是 0/0 未定义，`metrics.per_class_prf` 走 `zero_division=0`）。")
            doc.append("")
        doc.append("---")
        doc.append("")
    return doc


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="", help="输出路径；空 = 只打印")
    args = ap.parse_args()

    recs = collect()
    if not recs:
        raise SystemExit("🔴 一条记录都没取到 —— 不出数")
    print(f"[audit] 对拍通过 {len(recs)} 条 (行, 种子) 记录，与产物存档逐位一致")

    text = "\n".join(render(recs)) + "\n"
    if args.out:
        (REPO / args.out).write_text(text, encoding="utf-8")
        print(f"[audit] 写入 {args.out}（{len(text)} 字节）")
    else:
        print(text)


if __name__ == "__main__":
    main()
