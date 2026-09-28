#!/usr/bin/env python3
"""**编码器换代闸门**：旧编码器（`--epochs 5 --patience 2`，§37 正典）vs
新编码器（`--epochs 20 --patience 4 --swa-start 16`，P2）在**下游 GNN** 上的同划分配对比较。

**它不产生任何新数字**：两侧都只读既有 `results.json`，本脚本只做「配对 + 判闸 + 写结论」。

🔴 **为什么必须在 GNN 阶段判、不在编码器自己的头上判**：
编码器微调时挂的那个 `Linear(768,7)` 头在阶段 2 会被**丢弃**（`finetune_codebert.py::CodeBertContract`），
它存在的唯一理由是给编码器提供合约级梯度。⇒ 编码器 val macro-F1 高**不蕴含**下游 F1 高。
（实测：探针 ss0 的编码器 val macro-F1 = **0.9466**，而整套 GNN 的 test macro 只有 0.46–0.55。
 这个落差本身是要在论文里正面回答的问题：「那图到底买了什么？」）

🔴 **判据选择**：micro-F1 的 bootstrap 95% CI 宽达 **0.34–0.40**（46 个 test 合约 / 21 个正标签对）
⇒ 在 micro 上 |Δ| < 0.1 **先天测不出来**，用它当判据等于掷硬币。故主判据取
**mAP**（阈值无关）与 **macro-F1@val_thr**，两者都报 micro 但**不拿 micro 下结论**。

三道门（全过才算「稳定提升」）：
  **G1 方向**：3/3 个划分种子在 mAP 与 macro@val_thr 上都不劣于旧（`new >= old`）。
  **G2 幅度**：两个主判据的 mean Δ 都 > 0，且**至少一个** > `--min-gain`（默认 0.02，
              约为正典 mAP 跨种子 std ±0.0056 的 4 倍）。
  **G3 上游**：3/3 个种子的编码器 `best_val_macro_f1` 都高于旧，且 mean Δ > 0.10。
              （若上游没真变好，下游的 Δ 就是噪声——这一门是给 G1/G2 兜底的归因门。）

⚠ **一处已知不对称（必须写进论文的对比说明）**：旧正典 `runs/seed{S}` 建于 `--deterministic` 修好
之前（实测 `config.json::args.deterministic = False`），新侧（换代后就位于 `runs/seed{S}`，
原先落在 `runs/p2_canon/seed{S}`）开了
`--deterministic`。该差异只影响**可复现性**、不构成质量优势，且噪声加在**旧侧**，
故「新的赢」这一方向不会被它制造出来；但「新的输」时不能拿它当借口。

用法（仓库根目录）：
    python scripts/check_encoder_promotion.py                        # 只打印
    python scripts/check_encoder_promotion.py --out experiments/encoder_promotion_gate.md

退出码：0 = 三道门全过；1 = 有门未过；3 = 产物未齐（P2 还在跑），不下结论。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

# (JSON 路径, 显示名, 是否主判据)
METRICS = [
    ("mAP/mAP", "mAP", True),
    ("test/val_threshold/macro_f1", "test macro@val_thr", True),
    ("test/val_threshold/micro_f1", "test micro@val_thr", False),
    ("test/fixed_0.5/macro_f1", "test macro@0.5", False),
    ("test/fixed_0.5/micro_f1", "test micro@0.5", False),
]


def _dig(obj: dict, path: str):
    cur = obj
    for k in path.split("/"):
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur


def _load_results(runs_root: str, seed: int) -> dict | None:
    p = REPO / runs_root / f"seed{seed}" / "results.json"
    if not p.exists():
        return None
    with p.open(encoding="utf-8") as fh:
        return json.load(fh)


def _enc_cfg(enc_root: str, seed: int) -> dict:
    """编码器 `config.json`（finetune_codebert.py 写的记录）。

    ⚠ 字段位置**两层都有**：`epochs`/`patience`/`swa_start` 在 `args` 下，
    而 `best_val_macro_f1`/`best_epoch`/`selection_metric` 在**顶层**——
    只认一层会静默拿到 `None`（本脚本首版就踩到，实测 `—`）。
    """
    p = REPO / enc_root / f"ss{seed}" / "config.json"
    if not p.exists():
        return {}
    with p.open(encoding="utf-8") as fh:
        cfg = json.load(fh)
    a = cfg.get("args", {})
    return {
        "epochs": a.get("epochs"),
        "patience": a.get("patience"),
        "swa_start": a.get("swa_start"),
        "best_epoch": cfg.get("best_epoch", a.get("best_epoch")),
        "best_val_macro_f1": cfg.get("best_val_macro_f1", a.get("best_val_macro_f1")),
        "swa": cfg.get("swa"),
    }


def _enc_best(enc_cfg: dict) -> float | None:
    v = enc_cfg.get("best_val_macro_f1")
    return None if v is None else float(v)


def _mean(xs: list[float]) -> float:
    return sum(xs) / len(xs) if xs else float("nan")


def _fmt(x: float | None, nd: int = 4) -> str:
    return "—" if x is None else f"{x:.{nd}f}"


def build_rows(seeds, old_root, new_root):
    """返回 (rows, pending)：rows 逐种子逐指标，pending = 缺失的 (root, seed) 列表。"""
    rows, pending = [], []
    for s in seeds:
        o, n = _load_results(old_root, s), _load_results(new_root, s)
        if o is None:
            pending.append((old_root, s))
        if n is None:
            pending.append((new_root, s))
        row = {"seed": s, "old": o, "new": n}
        rows.append(row)
    return rows, pending


def main() -> int:
    ap = argparse.ArgumentParser(description="编码器换代闸门（旧 5 轮 vs 新 20 轮，下游 GNN 配对）")
    # 🔴 2026-09-25 换代落地后，新一代替换到了正典路径 `runs/seed{S}`，
    #   旧一代归档到 `runs/prior_canon37/seed{S}`。故两个默认值**对调**，
    #   本脚本仍可原样重跑做审计（它读的是既有 `results.json`，不产新数字）。
    ap.add_argument("--old-runs-root", default="runs/prior_canon37",
                    help="旧正典 GNN 产物根（含 seed{S}/results.json）")
    ap.add_argument("--new-runs-root", default="runs", help="新编码器 GNN 产物根")
    ap.add_argument("--old-encoder-root", default="runs/codebert_ft/alldata",
                    help="旧编码器根（含 ss{S}/config.json）——**未随换代改名**，仍是旧 5 轮档")
    ap.add_argument("--new-encoder-root", default="runs/codebert_ft_p2", help="新编码器根")
    ap.add_argument("--seeds", type=int, nargs="+", default=[0, 1, 2])
    ap.add_argument("--min-gain", type=float, default=0.02, help="G2 的幅度阈值")
    ap.add_argument("--enc-min-gain", type=float, default=0.10, help="G3 的幅度阈值")
    ap.add_argument("--out", default=None, help="写 markdown（默认只打印）")
    args = ap.parse_args()

    rows, pending = build_rows(args.seeds, args.old_runs_root, args.new_runs_root)

    L: list[str] = []
    L.append("# 编码器换代闸门：旧 `--epochs 5` vs 新 `--epochs 20`\n")
    L.append(f"旧 = `{args.old_runs_root}/seed{{S}}`（`graphs_ft/ss{{S}}`，§37 旧正典编码器）  ")
    L.append(f"新 = `{args.new_runs_root}/seed{{S}}`（`graphs_ft_p2/cb_ft_ss{{S}}`，现行正典编码器）  ")
    L.append("同划分、同训练种子，**唯一变量 = 编码器**；两侧都读既有 `results.json`，本脚本不产新数字。\n")
    L.append("> ⚠ 本次提升的实质是 **epoch 预算（5 → 20 + 按 val macro-F1 早停）**，"
             "**不是 SWA**——实测 `n_averaged = 0/0/2`、三种子 `selection` 全为 `best_epoch`。\n")

    if pending:
        L.append("> ⚠ **产物未齐，本表不下结论**。缺失：")
        for root, s in pending:
            L.append(f"> - `{root}/seed{s}/results.json`")
        L.append("")
        print("\n".join(L))
        if args.out:
            (REPO / args.out).write_text("\n".join(L) + "\n", encoding="utf-8")
        return 3

    # ---- 主表：逐种子 × 逐指标 ----
    L.append("## 一、逐种子配对\n")
    L.append("| 种子 | " + " | ".join(f"{name} 旧 | 新 | Δ" for _, name, _ in METRICS) + " |")
    L.append("|---" * (1 + 3 * len(METRICS)) + "|")
    deltas: dict[str, list[float]] = {p: [] for p, _, _ in METRICS}
    for row in rows:
        cells = [str(row["seed"])]
        for path, _, _ in METRICS:
            o, n = _dig(row["old"], path), _dig(row["new"], path)
            if o is None or n is None:
                cells += [_fmt(o), _fmt(n), "—"]
                continue
            d = float(n) - float(o)
            deltas[path].append(d)
            sign = "+" if d >= 0 else ""
            cells += [_fmt(o), _fmt(n), f"**{sign}{d:.4f}**"]
        L.append("| " + " | ".join(cells) + " |")

    means = {p: _mean(v) for p, v in deltas.items()}
    mean_cells = [f"— | — | **{'+' if means[p] >= 0 else ''}{means[p]:.4f}**" for p, _, _ in METRICS]
    L.append("| **均值 Δ** | " + " | ".join(mean_cells) + " |")
    L.append("")

    # ---- 下降格明细（2026-09-25 加）----
    # 🔴 **为什么单列这一节**：用户裁定「整表换 + 逐格对照」——正典位置的数字一律换成新代
    #   （正典只能有一个），但**下降的格子必须在报告里显式可见**，否则等于事后择优。
    #   本节就是那张对照表的"下行"部分，供 `decisions.md` §55 直接引用。
    L.append("## 一之二、🔴 下降格明细（**全部列出，不做任何筛选**）\n")
    down: list[str] = []
    for row in rows:
        for path, name, _ in METRICS:
            o, n = _dig(row["old"], path), _dig(row["new"], path)
            if o is None or n is None:
                continue
            d = float(n) - float(o)
            if d < 0:
                down.append(f"| seed{row['seed']} | {name} | {_fmt(o)} | {_fmt(n)} | **{d:.4f}** |")
    if down:
        L.append(f"**共 {len(down)} 格下降**（总格数 {len(rows) * len(METRICS)}）：\n")
        L.append("| 种子 | 指标 | 旧 | 新 | Δ |")
        L.append("|---|---|---|---|---|")
        L += down
        L.append("")
        L.append("> ⚠ 这些格子**仍按新正典取值**（正典只能有一个；单元格级择优会让一张表混两代）。"
                 "列在这里是为了让读者知道哪几格退了一点，而不是把它们藏起来。\n")
    else:
        L.append("无下降格。\n")

    # ---- 方向计数（全过 = 3/3 不劣）----
    L.append("## 二、G1 方向：逐指标「不劣」种子数\n")
    L.append("| 指标 | 不劣种子数 | 主判据 |")
    L.append("|---|---|---|")
    dir_ok: dict[str, bool] = {}
    for path, name, primary in METRICS:
        v = deltas[path]
        k = sum(1 for d in v if d >= 0)
        dir_ok[path] = (k == len(args.seeds)) and len(v) == len(args.seeds)
        L.append(f"| {name} | {k}/{len(v)} | {'✅' if primary else '—'} |")
    L.append("")

    # ---- 编码器侧（G3）----
    L.append("## 三、G3 上游：编码器自身 val macro-F1（**只作归因门，不是结论**）\n")
    L.append("⚠ 该头在阶段 2 被丢弃，其绝对值**不代表**下游能力（见脚本 docstring）。\n")
    L.append("| 种子 | 旧 best_val_macro_f1 | 新 best_val_macro_f1 | Δ | 旧配置 | 新配置 | 新选点 |")
    L.append("|---|---|---|---|---|---|---|")
    enc_delta: list[float] = []
    enc_ok = 0
    for s in args.seeds:
        co = _enc_cfg(args.old_encoder_root, s)
        cn = _enc_cfg(args.new_encoder_root, s)
        o, n = _enc_best(co), _enc_best(cn)

        def _spec(c: dict) -> str:
            if not c:
                return "—"
            return f"ep{c.get('epochs')}/pat{c.get('patience')}/swa{c.get('swa_start') or '关'}"

        swa = cn.get("swa") or {}
        sel = f"{swa.get('selection', '—')}"
        if swa.get("swa_val_macro_f1") is not None:
            sel += f"（SWA val {swa['swa_val_macro_f1']:.4f}，n={swa.get('n_averaged')}）"
        if o is None or n is None:
            L.append(f"| {s} | {_fmt(o)} | {_fmt(n)} | — | {_spec(co)} | {_spec(cn)} | {sel} |")
            continue
        d = n - o
        enc_delta.append(d)
        enc_ok += 1 if d > 0 else 0
        L.append(f"| {s} | {_fmt(o)} | {_fmt(n)} | **{'+' if d >= 0 else ''}{d:.4f}** | "
                 f"{_spec(co)} | {_spec(cn)} | {sel} |")
    enc_mean = _mean(enc_delta)
    L.append(f"| **均值** | — | — | **{'+' if enc_mean >= 0 else ''}{enc_mean:.4f}** | — | — | — |")
    L.append("")

    # ---- 判闸 ----
    prim = [(p, n) for p, n, pr in METRICS if pr]
    g1 = all(dir_ok[p] for p, _ in prim)
    g2_dir = all(means[p] > 0 for p, _ in prim)
    g2_mag = any(means[p] > args.min_gain for p, _ in prim)
    g2 = g2_dir and g2_mag
    g3 = (enc_ok == len(args.seeds)) and (enc_mean > args.enc_min_gain)

    L.append("## 四、判闸\n")
    L.append("| 门 | 判据 | 实测 | 结果 |")
    L.append("|---|---|---|---|")
    L.append(f"| **G1 方向** | mAP 与 macro@val_thr 都 3/3 不劣 | "
             + "；".join(f"{n} {'3/3' if dir_ok[p] else '未达 3/3'}" for p, n in prim)
             + f" | {'✅ 过' if g1 else '❌ 未过'} |")
    L.append(f"| **G2 幅度** | 两主判据 mean Δ > 0，且至少一个 > {args.min_gain} | "
             + "；".join(f"{n} {means[p]:+.4f}" for p, n in prim)
             + f" | {'✅ 过' if g2 else '❌ 未过'} |")
    L.append(f"| **G3 上游** | 编码器 3/3 提升且 mean Δ > {args.enc_min_gain} | "
             f"{enc_ok}/{len(args.seeds)}；mean {enc_mean:+.4f} | {'✅ 过' if g3 else '❌ 未过'} |")
    L.append("")

    if g1 and g2 and g3:
        L.append("### 裁定：**三道门全过 ⇒ 升级为正典**\n")
        L.append("按用户 2026-09-24 裁定：新编码器升为正典，**旧编码器下沉为消融臂**。"
                 "报告时按**三档阶梯**写：冻结 CodeBERT / **5 轮**（旧正典，其 run 已归档于 "
                 "`runs/prior_canon37/seed{S}`；**不另设名为 `cb_ft5` 的臂**）/ "
                 "**20 轮**（现行正典）——⚠ **不得写成「20 轮 + SWA」**，"
                 "实测 SWA 一次都没被选中（见本表第三节）。")
        L.append("")
        L.append("🔴 **2026-09-25 换代已落地**：新一代替换到正典路径 `runs/seed{S}`，"
                 "旧一代归档到 `runs/prior_canon37/`（`decisions.md` §55）。"
                 "本节的「旧」侧默认值即指向该归档根 ⇒ 本表可**随时重跑复核**。")
    elif g1 and not g2:
        L.append("### 裁定：**G1 过、G2 未过 ⇒ 不升正典，降为并列臂**\n")
        L.append("理由：把全部下游结果作废，只换一个**测不出幅度**的差异，是净亏。"
                 "改以「编码器 epoch 预算的敏感性」并列报告，正典不动。")
    else:
        L.append("### 裁定：**未过 ⇒ 不升正典**\n")
        L.append("G1 未过意味着方向都不一致（部分种子变差）⇒ 下游差异被噪声主导，"
                 "按用户裁定的前置条件「确实上升」不成立。")

    body = "\n".join(L)
    print(body)
    if args.out:
        (REPO / args.out).write_text(body + "\n", encoding="utf-8")
        print(f"\n[gate] 已写入 {args.out}")

    return 0 if (g1 and g2 and g3) else 1


if __name__ == "__main__":
    sys.exit(main())
