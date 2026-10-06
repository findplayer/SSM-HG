#!/usr/bin/env python3
"""**权威数字载体**：逐种子 / 逐类 / 消耗 —— `experiments/canonical_ft_numbers.md`。

🔴 **为什么必须先有这个脚本**（2026-09-25 补，根因修复）：
  该文件长期被 `项目组织架构.md`、`collect_p1_gains.py`、`log.md`、`论文开发手册.md`
  标注为「**程序生成的权威出处**」，但**全仓没有任何脚本写它**（`grep -rn` 实测）——
  它是**手写**的。后果在 2026-09-25 编码器换代时暴露：正典从 5 轮档换成 20 轮档后，
  它**不会自动刷新**，于是继续以「权威出处」的名义发出**整代旧数字**
  （micro@0.5 0.7110 vs 实际 0.8129、mAP 0.7582 vs 0.8952）。
  ⇒ 本脚本把「程序生成」这句话**变成真的**。

🔴 **每一行的定义都经过机检**（不是从旧文件反推的猜测）：拿**旧正典**
  `runs/prior_canon37/seed{S}` 跑本脚本，逐格复现旧文件的数值（含 `cbin_f1_05` = 0.9756、
  `buggy_sub_05` = 0.7273/0.6923/0.7727）——**逐位一致**后才定的这套映射。

行的来源（**唯一事实来源**，不重实现指标）：
  - `results.json`   ← `train.py`/`evaluate.py` 写：`val_threshold`、`test.{fixed_0.5,val_threshold}`、`mAP`、`timing`
  - `error_rates.json` ← `scripts/error_rates.py` 写（**注意：它自己会重算，与 `results.json` 独立**）
  - `test_probs.pt`  ← `diagnose.py` 写：`buggy_sub_*`（**vuln 子集**口径，见下）与 `n_clean/n_vuln`
  - 编码器 `config.json` ← `finetune_codebert.py` 写：`timing.wall_seconds`/`best_epoch`/`best_val_macro_f1`/`n_train_sequences`

⚠ **`buggy_sub_*` 的名字有误导性**：它不是"`buggy_*` 合约子集"，而是
  **「有漏洞合约」子集**（`labels.any()` 为真的那部分）上的 micro-F1。
  ① 的池 453 里根本没有 `buggy_*`（那 90 个被剔除了）⇒ 该行名字纯属历史遗留。
  `buggy_sub_n_*` = 该子集的合约数 = `n_vuln`。

用法（仓库根目录）：
    python scripts/collect_canonical_numbers.py            # 打印
    python scripts/collect_canonical_numbers.py --write    # 落盘 experiments/canonical_ft_numbers.md
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "experiments" / "canonical_ft_numbers.md"
SEEDS = (0, 1, 2)
NAMES = ["access_control", "arithmetic", "dos", "front_running",
         "reentrancy", "time_manipulation", "uncheck"]

# 语料 → 配置。`arm` 是 `error_rates.json::arms` 里的键名（① 叫 `seed`、② 叫 `augmentation`）。
CORPORA = [
    {
        # 🔴 2026-10-01 口径对调：本语料的 run 目录 `runs/` 是**池 453**，故其角色由
        #    「① 主库（正典）」降为**对照口径**；路径字段一律未改（`runs`、`graphs_ft_p2/…`）。
        #    ⚠ `canon_tree` / `encoders` 两处写的是**编码器档位轴**（20 轮 / 5 轮），该轴上
        #    20 轮**仍是现行正典**（与池无关），故保留 —— 只把「现行正典」点明为「编码器档」。
        "title": "① 对照口径（池 453）alldata(readonly)",
        "runs": "runs", "arm": "seed", "enc_corpus": "alldata",
        "canon_tree": "products/alldata/graphs_ft_p2/cb_ft_ss{S}（20 轮档，2026-09-25 换代后的现行**编码器档**）",
        "encoders": [("runs/codebert_ft_p2", "**新正典（20 轮）**"),
                     ("runs/codebert_ft/alldata", "消融档（5 轮，§37 旧正典）")],
    },
    {
        "title": "② 增强集 alldata_augmentation",
        "runs": "runs/augmentation", "arm": "augmentation", "enc_corpus": "augmentation",
        "canon_tree": "products/augmentation/graphs_ft/ss{S}（5 轮档；**② 本次未换代**）",
        "encoders": [("runs/codebert_ft/augmentation", "现行正典（5 轮，本次未换代）")],
    },
]


def _read_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _vuln_micro(probs: np.ndarray, labels: np.ndarray, thr: float) -> tuple[float, int]:
    """**「有漏洞合约」子集**上的 micro-F1 与该子集规模（= `buggy_sub_*` / `buggy_sub_n_*`）。

    ⚠ 名字是历史遗留：与 `buggy_*` 合约无关（① 的池里没有它们）。
    """
    m = (labels >= 0.5).any(1)
    y, p = labels[m].astype(int), (probs[m] >= thr).astype(int)
    tp = int(((p == 1) & (y == 1)).sum())
    fp = int(((p == 1) & (y == 0)).sum())
    fn = int(((p == 0) & (y == 1)).sum())
    den = 2 * tp + fp + fn
    return (2 * tp / den if den else 0.0), int(m.sum())


def _pair(rows: list[tuple[str, list[float]]]) -> list[str]:
    """把逐种子读数渲染成表行（末列 = 3 种子 mean±std，ddof=1）。"""
    out = []
    for name, vals in rows:
        a = np.array(vals, dtype=float)
        mean = a.mean()
        std = a.std(ddof=1) if a.size > 1 else 0.0
        out.append(f"| {name} | " + " | ".join(f"{v:.4f}" for v in vals)
                   + f" | {mean:.4f} ± {std:.4f} |")
    return out


def _seed_rows(cfg: dict, per_seed: list[dict]) -> list[tuple[str, list[float]]]:
    """逐种子表的全部行（顺序与旧文件一致，便于逐格对照）。"""
    def col(path):
        return [float(_dig(s, path)) for s in per_seed]

    return [
        ("thr",                col("thr")),
        ("n",                  col("n")),
        ("micro_05",           col("micro_05")),
        ("macro_05",           col("macro_05")),
        ("subset_05",          col("subset_05")),
        ("buggy_sub_05",       col("buggy_sub_05")),
        ("buggy_sub_n_05",     col("buggy_sub_n_05")),
        ("cbin_f1_05",         col("cbin_f1_05")),
        ("cbin_P_05",          col("cbin_P_05")),
        ("cbin_R_05",          col("cbin_R_05")),
        ("cbin_FPR_05",        col("cbin_FPR_05")),
        ("cbin_FNR_05",        col("cbin_FNR_05")),
        ("cbin_acc_05",        col("cbin_acc_05")),
        ("L1_FPR_05",          col("L1_FPR_05")),
        ("L1_FNR_05",          col("L1_FNR_05")),
        ("micro_thr",          col("micro_thr")),
        ("macro_thr",          col("macro_thr")),
        ("subset_thr",         col("subset_thr")),
        ("buggy_sub_thr",      col("buggy_sub_thr")),
        ("buggy_sub_n_thr",    col("buggy_sub_n_thr")),
        ("cbin_f1_thr",        col("cbin_f1_thr")),
        ("cbin_P_thr",         col("cbin_P_thr")),
        ("cbin_R_thr",         col("cbin_R_thr")),
        ("cbin_FPR_thr",       col("cbin_FPR_thr")),
        ("cbin_FNR_thr",       col("cbin_FNR_thr")),
        ("cbin_acc_thr",       col("cbin_acc_thr")),
        ("L1_FPR_thr",         col("L1_FPR_thr")),
        ("L1_FNR_thr",         col("L1_FNR_thr")),
        ("mAP",                col("mAP")),
        ("n_clean",            col("n_clean")),
        ("n_vuln",             col("n_vuln")),
    ]


def _dig(s: dict, path: str) -> float:
    cur = s
    for k in path.split("."):
        cur = cur[k]
    return cur


def collect_corpus(cfg: dict, er: dict) -> tuple[list[str], dict]:
    """一个语料的全部读数：逐种子 + 逐类 + 消耗。返回 (markdown 行, 原始读数)。"""
    runs_root = REPO / cfg["runs"]
    arm = (er.get("arms") or {}).get(cfg["arm"]) or {}
    er_seeds = {int(s["seed"]): s for s in (arm.get("seeds") or [])}

    per_seed, raw = [], {}
    for s in SEEDS:
        res = _read_json(runs_root / f"seed{s}" / "results.json")
        if res is None:
            raise SystemExit(f"🔴 缺 {runs_root}/seed{s}/results.json —— 先跑 train/evaluate")
        e = er_seeds.get(s)
        if e is None:
            raise SystemExit(f"🔴 `runs/error_rates.json` 里没有 arm={cfg['arm']!r} seed={s} 的读数 —— "
                             f"先跑 `python scripts/error_rates.py`")
        probs_p = runs_root / f"seed{s}" / "test_probs.pt"
        if not probs_p.exists():
            raise SystemExit(f"🔴 缺 {probs_p} —— `test_probs.pt` 只由 `diagnose.py` 写")
        d = torch.load(probs_p, map_location="cpu")
        pr, y = d["probs"].numpy(), d["labels"].numpy()
        thr = float(res["val_threshold"])
        t05, tth = res["test"]["fixed_0.5"], res["test"]["val_threshold"]
        b05 = e["fixed_0.5"]["L3_contract"]
        bth = e["val_thr"]["L3_contract"]
        l05 = e["fixed_0.5"]["L1_micro"]
        lth = e["val_thr"]["L1_micro"]
        sub05, nv05 = _vuln_micro(pr, y, 0.5)
        subth, nvth = _vuln_micro(pr, y, thr)
        row = {
            "thr": thr, "n": float(e["n_test"]),
            "micro_05": t05["micro_f1"], "macro_05": t05["macro_f1"], "subset_05": t05["subset_accuracy"],
            "buggy_sub_05": sub05, "buggy_sub_n_05": float(nv05),
            "cbin_f1_05": b05["binary_f1"], "cbin_P_05": b05["binary_precision"],
            "cbin_R_05": b05["binary_recall"], "cbin_FPR_05": b05["false_alarm_rate"],
            "cbin_FNR_05": b05["miss_rate"], "cbin_acc_05": b05["binary_accuracy"],
            "L1_FPR_05": l05["FPR"], "L1_FNR_05": l05["FNR"],
            "micro_thr": tth["micro_f1"], "macro_thr": tth["macro_f1"], "subset_thr": tth["subset_accuracy"],
            "buggy_sub_thr": subth, "buggy_sub_n_thr": float(nvth),
            "cbin_f1_thr": bth["binary_f1"], "cbin_P_thr": bth["binary_precision"],
            "cbin_R_thr": bth["binary_recall"], "cbin_FPR_thr": bth["false_alarm_rate"],
            "cbin_FNR_thr": bth["miss_rate"], "cbin_acc_thr": bth["binary_accuracy"],
            "L1_FPR_thr": lth["FPR"], "L1_FNR_thr": lth["FNR"],
            "mAP": res["mAP"]["mAP"],
            "n_clean": float(b05["n_clean"]), "n_vuln": float(b05["n_vuln"]),
        }
        per_seed.append(row)
        raw[s] = {"results": res, "probs": pr, "labels": y}

    L: list[str] = [f"# {cfg['title']}", ""]
    L += [f"> 程序生成（`scripts/collect_canonical_numbers.py`）。正典输入树 = `{cfg['canon_tree']}`。", ""]
    L += ["## A. 逐种子", "", "| 量 | seed0 | seed1 | seed2 | 3 种子 mean±std |",
          "| --- | --- | --- | --- | --- |"]
    L += _pair(_seed_rows(cfg, per_seed))

    # ---- B. 逐类 ----
    L += ["", "## B. 逐类（3 种子 mean±std；support 逐种子）", ""]
    ap = [raw[s]["results"]["mAP"]["ap"] for s in SEEDS]
    for wp, disp in (("fixed_0.5", "@0.5"), ("val_threshold", "@thr")):
        L += [f"**{disp}**", "",
              "| 类 | support s0/s1/s2 | F1 | Precision | Recall | AP s0/s1/s2 |",
              "| --- | --- | --- | --- | --- | --- |"]
        for ci, name in enumerate(NAMES):
            sup = [raw[s]["results"]["test"][wp]["per_class"]["support"][ci] for s in SEEDS]
            def ms(key):
                a = np.array([raw[s]["results"]["test"][wp]["per_class"][key][ci] for s in SEEDS], float)
                return f"{a.mean():.4f}±{a.std(ddof=1):.4f}"
            L.append(f"| {name} | {'/'.join(str(x) for x in sup)} | {ms('f1')} | {ms('precision')} | "
                     f"{ms('recall')} | " + "/".join(f"{ap[s][ci]:.4f}" for s in SEEDS) + " |")
        L.append("")

    # ---- C. 训练消耗 ----
    L += ["", "## C. 训练消耗与微调段", ""]
    for s in SEEDS:
        c = raw[s]["results"]
        cfgj = _read_json(runs_root / f"seed{s}" / "config.json") or {}
        t = cfgj.get("timing") or {}
        der = (cfgj.get("derived") or {})
        L.append(f"- seed{s}: wall {t.get('run_wall_seconds')} s / train {t.get('train_seconds')} s / "
                 f"epoch 均 {t.get('epoch_seconds_mean')} s / epochs {t.get('epochs_completed')} / "
                 f"graphs_per_s {t.get('graphs_per_second')}")
        if s == 0 and der:
            L.append(f"  - 参数量：{der.get('parameter_report')}")
            L.append(f"  - 维度：{der.get('dim_report')}")
    return L, {"per_seed": per_seed, "raw": raw}


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 experiments/canonical_ft_numbers.md")
    ap.add_argument("--write", action="store_true", help="落盘（默认只打印）")
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    er = _read_json(REPO / "runs" / "error_rates.json")
    if er is None:
        raise SystemExit("🔴 缺 runs/error_rates.json —— 先跑 `python scripts/error_rates.py`")

    doc: list[str] = [
        "",
        "> 🔴 **本文件由 `scripts/collect_canonical_numbers.py` 程序生成，不要手改。**",
        "> 生成时间点的**口径归属**即表内数字的口径；**换代后必须重跑本脚本**（这是它过去漂移的根因：",
        "> 该文件曾被标为「程序生成」却实为手写，2026-09-25 编码器换代后继续发出整代旧数字）。",
        "> ⚠ `buggy_sub_*` 的名字是历史遗留：它是**「有漏洞合约」子集**上的 micro-F1，",
        "> 与 `buggy_*` 合约无关（① 的池里没有它们）。",
        "",
    ]
    for cfg in CORPORA:
        L, _ = collect_corpus(cfg, er)
        doc += L + [""]

    # ---- D. 微调段消耗 ----
    doc += ["---", "", "## D. 微调段消耗（stage-1 编码器；不含下游 GNN）", "",
            "| 语料 | 档 | 逐种子 wall (s) | mean (s) | 合计 (s) | best_epoch | best_val_macro_f1 | n_train_seq |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for cfg in CORPORA:
        for root, label in cfg["encoders"]:
            ws, be, bf, ns = [], [], [], []
            for s in SEEDS:
                c = _read_json(REPO / root / f"ss{s}" / "config.json")
                if c is None:
                    ws.append(None); continue
                ws.append((c.get("timing") or {}).get("wall_seconds"))
                be.append(c.get("best_epoch")); bf.append(c.get("best_val_macro_f1"))
                ns.append(c.get("n_train_sequences"))
            if any(w is None for w in ws):
                continue
            a = np.array(ws, float)
            doc.append(f"| {cfg['enc_corpus']} | {label} | " + " / ".join(f"{w:.1f}" for w in ws)
                       + f" | **{a.mean():.1f}** | {a.sum():.1f} | "
                       + " / ".join(str(x) for x in be) + " | "
                       + " / ".join(f"{x:.4f}" for x in bf) + " | "
                       + " / ".join(str(x) for x in ns) + " |")
    doc += ["", "⚠ **两段相加才是本项真实成本**（编码器微调 + 下游 GNN），只报 GNN 段会把总成本低估两个数量级。",
            "⚠ **① 的两档都在表里**：20 轮档 = 现行正典；5 轮档 = §37 旧正典（现为消融档，run 归档于 `runs/prior_canon37/`）。", ""]

    text = "\n".join(doc) + "\n"
    if args.write:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"[canon] 已写 {args.out}（{len(text)} 字符）")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
