#!/usr/bin/env python3
"""把消融各臂的 `results.json` 汇成**三张可比表**（含训练消耗与配对 t），并落盘 JSON + Markdown。

三张表回答三个不同的问题，**不可互相替代**：
  - 表 A **绝对值**（mean±std）：这一臂本身是多少；
  - 表 B **Δ 相对正典**（★ = |Δ| 超过正典种子间 std）：这个差比种子间噪声大吗；
  - 表 C **同配对 t**：在**同一划分、同一数据**下，这个差稳定同号吗。
`paired_t()` 能成立是因为 `run_ablation.build_args` 把 `split_seed` 绑成等于 `seed`，
故臂的 `seed{s}` 与正典 `runs/seed{s}` 是天然配对。

**为什么要有它**：`evaluate.py --summarize` 只汇总 `test` 的 micro/macro，而本项要看的
「精确匹配（subset accuracy）」「mAP」「训练消耗」分散在 `results.json` 与 `config.json::timing` 里；
手工从十几个目录里抄数既慢又**正是错数的来源**（本仓的消融计数已写错两次，见 `ablation_results.md` §6）。
故一律**程序复算、不手抄**。

两组结果集**各自独立成表**（`decisions.md` §23）：① 主库与 ② 增强集**不跨组比较、不合并**。

用法（从仓库根目录运行）：
  python scripts/collect_ablation_results.py                    # 两组都出
  python scripts/collect_ablation_results.py --group main       # 只出 ①

产物：`eval_results/ablation/collected{,_aug}.{json,md}`
"""

from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

# 组 → (正典 runs 目录模板, 消融根, 显示名, **应有臂集合**)
#
# 🔴 `expect` 不是装饰：只比对"目录里有什么"的话，**一个目录都还没建的臂会被当成不存在**
# （既不是"丢弃"也不是"缺失"，连警告都没有）——② 的 `cb_ft` 就是这样：
# 表里只有 4 臂，而设计上是 5 臂，读表的人**看不出少了哪一臂**。
# 有了 `expect`，缺席的臂会被显式记进 `missing_arms` 并写进产物自身。
#
# ⚠ **① 与 ② 的 `expect` 不同是设计使然、不是遗漏**：前 16 项（开关类）**只在 ① 上跑**
# （`ablation_plan.md` §6；② 只跑变量落在产物层的那 4 项 / 5 臂）。
# 若将来给 ② 补跑开关类消融，**必须同步扩这张表**，否则新臂会以"缺失"之名被持续误报。
SWITCH_16 = ("dfg_dep", "cfg_flow", "ast_parent", "callback_risk",
             "cb_node_only", "cb_func_only", "meanpool", "no_lvar", "no_prior_drop",
             "feat_base", "feat_base_sem", "hid256",
             "numbases1", "numbases3", "numbases4", "dropedge02")
# ⚠ 2026-09-19（§37）：`cb_ft`（微调 CodeBERT）**已升为正典**，不再是臂；
#   取而代之的是反向臂 `cb_frozen`（冻结 CodeBERT）。臂数仍为 5，与 `expect` 一致。
PRODUCT_5 = ("layers1", "layers3", "cb_unlimited", "cb_rev", "cb_frozen")

GROUPS = {
    "main": {
        "canon": "runs/seed{s}",
        "arms": "runs/ablation",
        "title": "① 主库 alldata(readonly)",
        "expect": SWITCH_16 + PRODUCT_5,          # 21 臂
    },
    "aug": {
        "canon": "runs/augmentation/seed{s}",
        "arms": "runs/ablation_aug",
        "title": "② 增强集 alldata_augmentation",
        # ⚠ 2026-09-19（§37）起 ② 与 ① **同为 21 臂**：原先只跑产物层 5 臂是当时的设计
        #   （"前 16 项只在 ① 上跑"），本次重跑把开关类 16 项一并补上，两组语料从此**逐臂对齐**。
        "expect": SWITCH_16 + PRODUCT_5,         # 21 臂
    },
}
SEEDS = (0, 1, 2)

# 表里的指标：键 → (取自 results.json 的路径, 显示名)
# ⚠ 路径必须写全：`fixed_0.5` / `val_threshold` 都在 **`test` 之下**（`mAP` 才在顶层）。
# 写错不会报错，只会让整列变成 "—"——这正是本脚本要消灭的那类"不报错的错"。
# 逐类明细（表 D 用）：`results.json` 已带 P/R/F1/support，零重算。
# ⚠ 逐类值**必须与 support 同时给出** —— support=1 的类，单张图判对判错即可让 F1 跳 ±1.0。
PER_CLASS_WP = {"fixed_0.5": "test/fixed_0.5/per_class",
                "val_threshold": "test/val_threshold/per_class"}

METRICS = {
    "micro_0.5": ("test/fixed_0.5/micro_f1", "micro-F1@0.5"),
    "micro_thr": ("test/val_threshold/micro_f1", "micro-F1@val_thr"),
    "macro_0.5": ("test/fixed_0.5/macro_f1", "macro-F1@0.5"),
    "macro_thr": ("test/val_threshold/macro_f1", "macro-F1@val_thr"),
    "subset_0.5": ("test/fixed_0.5/subset_accuracy", "精确匹配@0.5"),
    "mAP": ("mAP/mAP", "mAP"),
}


def dig(payload: dict, path: str):
    """按 `/` 逐级取键。

    🔴 **不能用 `.` 作分隔符**：本仓的键名**自身含点**（`fixed_0.5`、`val_threshold`
    没有但 `0.5` 有），按 `.` 切会把 `fixed_0.5` 切成 `fixed_0` + `5` 两段，
    于是整列静默变成 "—"（本脚本第一版就是这么错的）。
    """
    cur = payload
    for key in path.split("/"):
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def _per_class_of(payload: dict) -> dict:
    """单个 run 的**逐类明细**（两个工作点各自的 f1/precision/recall/support）。

    `results.json` 已带这些字段（`evaluate.py` 落的 `per_class`），故**零重算**。
    标注纪律：逐类值**必须与 support 同时给出**（`AGENTS.md`「语义锁死项」）——
    support=1 的类，一张图判对判错就足以让该类的 F1 跳 ±1.0。
    """
    out = {}
    for wp, path in PER_CLASS_WP.items():
        pc = dig(payload, path)
        out[wp] = {k: list(pc[k]) for k in ("f1", "precision", "recall", "support")}
        out[wp]["names"] = list(pc["names"])
    return out


def _agg_per_class(pcs: list[dict]) -> dict:
    """逐类跨种子聚合。

    ⚠ **support 不跨种子平均**：每个种子用的是**自己那套划分**，test 集不同 ⇒ support 不同。
    故 support 按种子原样保留（`per_seed_support`），F1 才取 mean±std。
    又因**同一 seed 下所有臂共用同一划分**，support 与臂无关 —— 渲染时只需列一次。
    """
    out = {}
    for wp in PER_CLASS_WP:
        names = pcs[0][wp]["names"]
        # 键用**真实种子号**（不是 enumerate 的序号）——渲染侧按种子号取，两边必须同一约定
        block = {"names": names,
                 "per_seed_support": {s: list(p[wp]["support"]) for s, p in zip(SEEDS, pcs)},
                 "f1": {}, "precision": {}, "recall": {}}
        for i, cname in enumerate(names):
            for m in ("f1", "precision", "recall"):
                vals = [p[wp][m][i] for p in pcs]
                block[m][cname] = {"mean": statistics.mean(vals),
                                   "std": statistics.stdev(vals) if len(vals) > 1 else 0.0}
        out[wp] = block
    return out


def arm_metrics(arm_dir: Path) -> dict | None:
    """一个臂的 3 种子指标 + 训练消耗。缺任何一个种子就返回 None（不半报告）。"""
    per_seed, timings, pcs = {}, [], []
    for s in SEEDS:
        rp = arm_dir / f"seed{s}" / "results.json"
        cp = arm_dir / f"seed{s}" / "config.json"
        if not rp.exists():
            return None
        payload = json.loads(rp.read_text(encoding="utf-8"))
        per_seed[s] = {k: dig(payload, path) for k, (path, _) in METRICS.items()}
        pcs.append(_per_class_of(payload))
        if cp.exists():
            cfg = json.loads(cp.read_text(encoding="utf-8"))
            timings.append(cfg.get("timing") or {})
    out = {"dir": str(arm_dir.relative_to(REPO)), "per_seed": per_seed, "stats": {},
           "per_class": _agg_per_class(pcs) if len(pcs) == len(SEEDS) else None}
    for key in METRICS:
        vals = [per_seed[s][key] for s in SEEDS if per_seed[s][key] is not None]
        out["stats"][key] = {
            "mean": round(statistics.mean(vals), 6) if vals else None,
            "std": round(statistics.stdev(vals), 6) if len(vals) > 1 else None,
            "n": len(vals),
        }
    if timings:
        out["cost"] = {
            "wall_s_mean": round(statistics.mean(t.get("run_wall_seconds", 0) for t in timings), 1),
            "train_s_mean": round(statistics.mean(t.get("train_seconds", 0) for t in timings), 1),
            "epoch_s_mean": round(statistics.mean(t.get("epoch_seconds_mean", 0) for t in timings), 4),
            "epochs_mean": round(statistics.mean(t.get("epochs_completed", 0) for t in timings), 1),
            "graphs_per_s_mean": round(statistics.mean(
                t.get("graphs_per_second", 0) for t in timings), 1),
        }
    return out


# 微调编码器的根目录：**按语料隔离**（`decisions.md` §35.2）。路径写错只会静默返回 None，
# 于是 `cb_ft` 的成本被整段漏掉——故这里与 `finetune_codebert.default_out_root` 保持同一约定。
FT_ROOT = {"main": "runs/codebert_ft/alldata", "aug": "runs/codebert_ft/augmentation"}


def ft_cost_of(group: str) -> dict | None:
    """**微调段消耗**——它不在 GNN run 的 `config.json` 里。

    ⚠ 2026-09-19（§37）：微调已升为**正典**的一部分，故本段成本归属于**正典行**，
    而非某个消融臂（原先挂在 `cb_ft` 臂上，现该臂已不存在）。

    架构是**两段式**（微调 CodeBERT → 用新编码器重编码 M3 → 再训 GNN）。
    只报 GNN 那一段的 wall 会把总成本**低估一个数量级**（微调是小时级、GNN 是秒级），
    给出一个"这套方法很便宜"的错误印象。故单列一段，并把重编码的规模（序列数）一并记下。
    """
    per_seed = {}
    for s in SEEDS:
        cp = REPO / FT_ROOT[group] / f"ss{s}" / "config.json"
        if not cp.exists():
            continue
        c = json.loads(cp.read_text(encoding="utf-8"))
        per_seed[s] = {
            "wall_s": (c.get("timing") or {}).get("wall_seconds"),
            "best_epoch": c.get("best_epoch"),
            "best_val_macro_f1": c.get("best_val_macro_f1"),
            "n_train_sequences": c.get("n_train_sequences"),
            "corpus": c.get("corpus"),
        }
    if not per_seed:
        return None
    walls = [v["wall_s"] for v in per_seed.values() if v.get("wall_s")]
    return {
        "per_seed": per_seed,
        "wall_s_mean": round(statistics.mean(walls), 1) if walls else None,
        "wall_s_total": round(sum(walls), 1) if walls else None,
        "note": "微调段（stage-1 编码器），不含下游 GNN；两段相加才是本项真实成本",
    }


def params_of(arm_dir: Path) -> dict | None:
    cp = arm_dir / "seed0" / "config.json"
    if not cp.exists():
        return None
    return (json.loads(cp.read_text(encoding="utf-8")).get("derived") or {}).get("parameter_report")


def collect(group: str) -> dict:
    cfg = GROUPS[group]
    canon = _canon_metrics(cfg["canon"])
    if canon is not None:
        # 微调是**正典**的一部分（§37）：挂到正典行，否则这段成本在表里无处安放
        canon["ft_cost"] = ft_cost_of(group)
    arms, dropped = {}, []
    for arm_dir in sorted((REPO / cfg["arms"]).glob("*")):
        if not arm_dir.is_dir():
            continue
        m = arm_metrics(arm_dir)
        if not m:
            # 🔴 **必须记账，不能静默跳过**：`arm_metrics` 缺任一种子就返回 None，
            # 原先调用方 `if m:` 直接 continue ⇒ 该臂**从表里整臂消失、且不报任何错**。
            # 这正是本仓反复栽的那一类（§35.1 续跑判据、§28 `.ravel()`）：
            # 少一个臂的汇总表看起来完全正常，读者只会以为"这项没跑"或"这项不存在"。
            # 典型触发场景：run 被外部打断（如 `wsl --shutdown`），留下 best.pt 却无 results.json。
            dropped.append(arm_dir.name)
            continue
        m["params"] = params_of(arm_dir)
        m["paired"] = {k: paired_t(m, canon, k) for k in METRICS} if canon else {}
        arms[arm_dir.name] = m
    # 目录**根本没建**的臂：不是"丢弃"（那是有产物但不全），是"还没跑"。
    # 两者对读者的含义不同，故分开记账、分开措辞。
    missing = [n for n in cfg["expect"] if n not in arms and n not in dropped]
    if dropped:
        print(f"⚠ [{group}] 以下臂**因子种子不全被整臂丢弃**（表里看不到它们）：{dropped}\n"
              f"   → 这不是「该项不存在」，是「产物不全」。补齐后重跑本脚本。\n"
              f"   → 查哪个种子缺：`ls {' '.join(dropped)}/seed*/results.json`", flush=True)
    if missing:
        print(f"⚠ [{group}] 以下臂**尚未产出**（目录都不存在）：{missing}\n"
              f"   → 本表按设计应有 {len(cfg['expect'])} 臂，现只有 {len(arms)} 臂。", flush=True)
    return {"title": cfg["title"], "canon": canon, "arms": arms,
            "dropped_arms": dropped, "missing_arms": missing,
            "n_expected": len(cfg["expect"])}


def _canon_metrics(pattern: str) -> dict | None:
    """正典臂的目录布局是 `runs/seed{s}`（**seed 目录直接在根下**），与消融的
    `<arm>/seed{s}` 不同，故单列一个入口。"""
    per_seed, pcs = {}, []
    for s in SEEDS:
        rp = REPO / pattern.format(s=s) / "results.json"
        if not rp.exists():
            return None
        payload = json.loads(rp.read_text(encoding="utf-8"))
        per_seed[s] = {k: dig(payload, path) for k, (path, _) in METRICS.items()}
        pcs.append(_per_class_of(payload))
    stats = {}
    for key in METRICS:
        vals = [per_seed[s][key] for s in SEEDS if per_seed[s][key] is not None]
        stats[key] = {"mean": round(statistics.mean(vals), 6) if vals else None,
                      "std": round(statistics.stdev(vals), 6) if len(vals) > 1 else None,
                      "n": len(vals)}
    return {"dir": pattern, "per_seed": per_seed, "stats": stats,
            "per_class": _agg_per_class(pcs) if len(pcs) == len(SEEDS) else None}


def fmt(value, std=None, digits=4) -> str:
    if value is None:
        return "—"
    return f"{value:.{digits}f}" + (f"±{std:.{digits}f}" if std is not None else "")


def delta(arm: dict, canon: dict, key: str):
    a = (arm.get("stats", {}).get(key) or {}).get("mean")
    c = (canon.get("stats", {}).get(key) or {}).get("mean")
    return None if a is None or c is None else round(a - c, 6)


def paired_t(arm: dict, canon: dict, key: str) -> dict | None:
    """同配对 Δ 与配对 t。

    **为什么消融臂可以直接配对**：`run_ablation.py` 把 `split_seed` 绑成等于 `seed`
    （`build_args` 里 `args["split_seed"] = seed`），故臂的 `seed{s}` 与正典的 `runs/seed{s}`
    **同划分、同数据**——配对比较消掉划分方差，这正是 §26.7/§27.5 要求的做法。

    ⚠ n=3 时 df=2，`|t| > 4.303` 才是 p<0.05；但**本仓规范是"判方向须 n≥9"**
    （噪声 ±0.05–0.07 量级，n=3 的表面模式不可信）。故 t 只作**描述性**呈现，
    不因 t 大就下"干预有效"的结论——与表 B 的 ★ 同级，都是"值得复核"的信号。
    """
    ds = []
    for s in SEEDS:
        a = (arm.get("per_seed", {}).get(s) or {}).get(key)
        c = (canon.get("per_seed", {}).get(s) or {}).get(key)
        if a is None or c is None:
            continue
        ds.append(a - c)
    if len(ds) < 2:
        return None
    mean = statistics.mean(ds)
    sd = statistics.stdev(ds)
    t = None if sd == 0 else round(mean / (sd / (len(ds) ** 0.5)), 3)
    return {"delta_mean": round(mean, 6), "delta_std": round(sd, 6),
            "t": t, "n": len(ds)}


def mark(value, thresh) -> str:
    """超出正典种子间 std 的差值标 ★（**只表示"值得复核"，n=3 不足以判定方向**）。"""
    if value is None or thresh is None:
        return ""
    return "★" if abs(value) > thresh else ""


# ------------------------------------------------------------------ 最佳种子口径（2026-09-20 用户裁定）
def best_seed_of(canon: dict) -> str:
    """「效果最好的种子」= **正典**在**主指标 micro-F1@val_thr** 上最高的那个种子。

    🔴 两条口径，缺一不可：
      1. **按论文主指标选**（micro-F1@val_thr）——若用 mAP 去挑种子、却拿它报 F1，
         就是口径错配（同一件事本仓已在 `.ravel()` 与 dropout 语义上栽过两次）；
      2. **只从正典选一个，然后全部臂共用它** —— 若每个臂各挑自己的最佳种子，
         得到的其实是「best-of-3」，**臂间不再可比**，且会系统性虚高。

    ⚠ 已知代价（论文须披露）：本仓实测**重跑抖动 ≈0.012，约为种子间 std 的 40%**
      （`decisions.md` §36.4）。故"最佳种子"里有相当一部分是运气，
      **不得**据最佳种子的差值下「某干预有效」的结论——那种结论仍须同配对 ≥9 点。
      故 mean±std 表**保留为附录**，不作废。
    """
    return max(canon["per_seed"], key=lambda s: canon["per_seed"][s]["micro_thr"])


def render_best_seed(canon: dict, arms: dict, k: str, names: list[str]) -> list[str]:
    """按**单一最佳种子**出表（用户 2026-09-20 裁定为主口径）。"""
    out = [f"> 🔴 **本节按「最佳种子」口径**：第 **{k}** 号种子（判据 = **正典**在 "
           f"micro-F1@val_thr 上最高，即 {canon['per_seed'][k]['micro_thr']:.4f}）。",
           f"> **正典与全部 {len(arms)} 个臂一律取该种子**，故表内可比。",
           "> ⚠ 单种子**无方差**可言，且重跑抖动 ≈0.012（约为种子间 std 的 40%，`decisions.md` §36.4）",
           "> ⇒ **不得**据此下「某干预有效/无效」的结论；mean±std 与同配对 t 见**附录**。", ""]
    out += [f"## 表 A′：绝对值（**最佳种子 seed{k}**）", "",
            "| 臂 | " + " | ".join(names) + " |", "| --- | " + " | ".join("---" for _ in METRICS) + " |"]
    for label, arm in [("**正典**", canon)] + sorted(arms.items()):
        ps = arm["per_seed"].get(k)
        if not ps:
            out.append(f"| {label} | " + " | ".join("—" for _ in METRICS) + " |")
            continue
        out.append(f"| {label} | " + " | ".join(f"{ps[key]:.4f}" for key in METRICS) + " |")
    cps = canon["per_seed"].get(k, {})
    out += ["", f"## 表 B′：Δ 相对正典（**最佳种子 seed{k}**）", "",
            "| 臂 | " + " | ".join(f"Δ{n}" for n in names) + " |",
            "| --- | " + " | ".join("---" for _ in METRICS) + " |"]
    for label, arm in sorted(arms.items()):
        ps = arm["per_seed"].get(k)
        if not ps:
            out.append(f"| {label} | " + " | ".join("—" for _ in METRICS) + " |")
            continue
        out.append(f"| {label} | " + " | ".join(f"{ps[key] - cps[key]:+.4f}" for key in METRICS) + " |")
    out += [""]
    return out


def render_markdown(group: str, data: dict) -> str:
    """两张表：**绝对值**（各臂 mean±std）与 **Δ**（相对正典，超 std 标 ★）。

    拆开是因为混在一张表里时，正典行填的是绝对值、其余行填的是 Δ，同一列两种语义——
    读者极易把 "+0.03" 当成绝对值。本仓对"口径混用"的教训已经够多。
    """
    canon = data["canon"]
    names = [n for _, n in METRICS.values()]
    lines = [f"# 消融结果汇总：{data['title']}", ""]
    # 产物不全的臂要**写在产物自己身上**：汇总 md 会被单独传阅/引用，
    # 只打印到 stdout 的话，读表的人无从知道"少了一臂"。
    dropped = data.get("dropped_arms") or []
    missing = data.get("missing_arms") or []
    if dropped or missing:
        n_exp, n_got = data.get("n_expected"), len(data["arms"])
        parts = [f"> 🔴 **本表不完整：应有 {n_exp} 臂，实有 {n_got} 臂。**"]
        if dropped:
            parts.append(f"> **因子种子不全被整臂丢弃**：`{'`、`'.join(dropped)}`"
                         f"——产物不全（典型原因是 run 被外部打断：留下 `best.pt` 却无 "
                         f"`results.json`，见 `decisions.md` §35.1）。")
        if missing:
            parts.append(f"> **目录都不存在（尚未产出）**：`{'`、`'.join(missing)}`。")
        parts.append("> ⚠ 缺的臂**不是「该项不存在」**。**引用本表前请先补齐并重跑本脚本。**")
        lines += parts + [""]
    if canon is None:
        return "\n".join(lines + ["⚠ 正典基线缺失，无法出表。"])
    k = best_seed_of(canon)
    lines += ["---", "", "# 主口径：最佳种子（用户 2026-09-20 裁定）", ""]
    lines += render_best_seed(canon, data["arms"], k, names)
    lines += ["---", "", "# 附录：3 种子 mean±std（保留——单种子无方差，见上）", ""]
    lines += ["## 表 A：绝对值（3 种子 mean±std）", "",
              "| 臂 | " + " | ".join(names) + " | 训练 wall(s) | epoch 数 | 参数量 |",
              "| --- | " + " | ".join("---" for _ in METRICS) + " | --- | --- | --- |"]
    for label, arm in [("**正典**", canon)] + sorted(data["arms"].items()):
        cells = [fmt(arm["stats"][k]["mean"], arm["stats"][k]["std"]) for k in METRICS]
        cost, pr = arm.get("cost") or {}, arm.get("params") or {}
        # 正典是**两段式**（§37 起）：GNN 那段 wall 之外还要单列微调段，
        # 否则整套方法的成本被低估一个数量级（微调小时级 vs GNN 秒级）
        ft = arm.get("ft_cost") or {}
        wall = cost.get("wall_s_mean", "—")
        if ft.get("wall_s_mean") is not None:
            wall = f"{wall} (+微调 {ft['wall_s_mean']})"
        lines.append(f"| {label} | " + " | ".join(cells)
                     + f" | {wall} | {cost.get('epochs_mean', '—')} "
                       f"| {pr.get('total_params', '—')} |")
    lines += ["", "## 表 B：Δ 相对正典（★ = |Δ| 超过正典的种子间 std）", "",
              "| 臂 | " + " | ".join(f"Δ{n}" for n in names) + " |",
              "| --- | " + " | ".join("---" for _ in METRICS) + " |"]
    stds = {k: canon["stats"][k]["std"] for k in METRICS}
    ordered = sorted(data["arms"].items(),
                     key=lambda kv: (delta(kv[1], canon, "micro_0.5") or 0.0))
    for name, arm in ordered:
        cells = []
        for k in METRICS:
            d = delta(arm, canon, k)
            cells.append("—" if d is None else f"{d:+.4f}{mark(d, stds[k])}")
        lines.append(f"| {name} | " + " | ".join(cells) + " |")

    # ---- 表 C：配对 t ----
    # 与表 B 分开呈现，因为两者回答**不同的问题**：表 B 问"这个差比种子间噪声大吗"，
    # 表 C 问"在**同一划分、同一初始化**下，这个差稳定同号吗"。混在一张表里最容易
    # 让读者把 t 值当成效应量——故只列 t，Δ 的数值一律回表 B 看。
    lines += ["", "## 表 C：同配对 t（臂 seed{s} ↔ 正典 runs/seed{s}，同划分同数据）", "",
              "| 臂 | " + " | ".join(f"t({n})" for n in names) + " |",
              "| --- | " + " | ".join("---" for _ in METRICS) + " |"]
    for name, arm in ordered:
        cells = []
        for k in METRICS:
            pt = (arm.get("paired") or {}).get(k)
            t = (pt or {}).get("t")
            cells.append("—" if t is None else f"{t:+.2f}")
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    # ---- 表 D/E：逐类明细 ----
    # support **与臂无关**（同一 seed 下所有臂共用同一划分），故只在表头列一次，不重复 21 遍；
    # 而它又**逐种子不同**（每个种子一套划分），故按 `s0/s1/s2` 三个数并列，不做平均。
    canon_pc = (canon or {}).get("per_class") or {}
    for wp, wname in (("fixed_0.5", "@0.5"), ("val_threshold", "@val_thr")):
        blk = canon_pc.get(wp)
        if not blk:
            lines += ["", f"⚠ 表 D-{wname} 缺失：正典无 `per_class` 数据。"]
            continue
        names_c, sup = blk["names"], blk["per_seed_support"]
        lines += ["", f"## 表 D-{wname}：逐类 F1（test，3 种子 mean±std）", "",
                  "**support（逐种子 s0/s1/s2；与臂无关，同一 seed 共用同一划分）**："
                  + "；".join(f"{c}=" + "/".join(str(sup[s][i]) for s in SEEDS)
                              for i, c in enumerate(names_c)), "",
                  "| 臂 | " + " | ".join(names_c) + " |",
                  "| --- | " + " | ".join("---" for _ in names_c) + " |"]
        for label, arm in [("**正典**", canon)] + ordered:
            b = ((arm or {}).get("per_class") or {}).get(wp)
            cells = ["—"] * len(names_c) if not b else \
                [fmt(b["f1"][c]["mean"], b["f1"][c]["std"]) for c in names_c]
            lines.append(f"| {label} | " + " | ".join(cells) + " |")

    blk = canon_pc.get("val_threshold")
    if blk:
        names_c = blk["names"]
        lines += ["", "## 表 E：逐类 Precision / Recall（test @val_thr，3 种子 mean±std）", ""]
        for m, mname in (("precision", "Precision"), ("recall", "Recall")):
            lines += [f"**{mname}**", "",
                      "| 臂 | " + " | ".join(names_c) + " |",
                      "| --- | " + " | ".join("---" for _ in names_c) + " |"]
            for label, arm in [("**正典**", canon)] + ordered:
                b = ((arm or {}).get("per_class") or {}).get("val_threshold")
                cells = ["—"] * len(names_c) if not b else \
                    [fmt(b[m][c]["mean"], b[m][c]["std"]) for c in names_c]
                lines.append(f"| {label} | " + " | ".join(cells) + " |")
            lines.append("")
        lines += ["⚠ 逐类值**必须与 support 同时读**（见表 D-@val_thr 表头）："
                  "`dos`/`front_running` 等类的 test support 只有 1–2，"
                  "**单张图判对判错即可让该类 F1 跳 ±1.0**，故这些类的 std 常达 ±0.3～±0.5。"
                  "`—` = 该臂无 per_class 数据。", ""]

    lines += ["",
              "⚠ n=3 时 df=2，**|t| > 4.303 才是 p<0.05**；但本仓规范是"
              "**判方向须 n≥9 同配对**（噪声 ±0.05–0.07 量级，n=3 的表面模式不可信，"
              "`decisions.md` §26.7/§27.5）。故 t 与 ★ 同级——**值得复核，不是结论**。"
              "⚠ t 无定义（`—`）= 三个配对差完全相同且为 0，或样本不足 2。", ""]
    lines += ["", "**正典的种子间 std（判 ★ 的阈值）**：" + "；".join(
        f"{name} ±{stds[k]:.4f}" for k, name in
        [(k, n) for k, (_, n) in METRICS.items()] if stds[k] is not None), "",
        "⚠ 全部为 **n=3 描述性**读数：正典 micro-F1@0.5 的 std 达 ±0.03 量级，"
        "3 种子**判不了** ±0.05 的效应；下「干预有效/无效」的结论须另做同配对 ≥9 点"
        "（`decisions.md` §26.7/§27.5）。★ 只表示**值得复核**，不是效应。", ""]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", choices=["main", "aug", "both"], default="both")
    args = ap.parse_args()
    groups = ["main", "aug"] if args.group == "both" else [args.group]
    out_dir = REPO / "eval_results" / "ablation"
    out_dir.mkdir(parents=True, exist_ok=True)
    for g in groups:
        data = collect(g)
        suffix = "" if g == "main" else "_aug"
        (out_dir / f"collected{suffix}.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        md = render_markdown(g, data)
        (out_dir / f"collected{suffix}.md").write_text(md, encoding="utf-8")
        print(md)
        print(f"\n[collect] 已写 {out_dir}/collected{suffix}.{{json,md}}\n")


if __name__ == "__main__":
    main()
