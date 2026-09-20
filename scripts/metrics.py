#!/usr/bin/env python3
"""M5 指标层（手册 10.5 / 12.4；大纲改II 5.2）：图级七类多标签指标与阈值扫描的**纯函数**。

契约（与 train/evaluate/ablation 三处共用；**不得 import dataset/model**，可独立单测）：
  - 主指标 **micro-F1（标签对级）**：把全部 `(样本, 类)` 标签对汇总后统计全局 TP/FP/FN 再算 F1，
    即 sklearn `f1_score(average="micro")`；不逐类平均、不额外做标签组合。macro-F1 为参考指标，
    报告时须注明支撑构成。
    ⚠ 「汇总标签对」是**统计口径**，**不是**把数组 `.ravel()` 后送 sklearn ——展平会把
    `type_of_target` 从 `multilabel-indicator` 改判成 `binary`，`average="micro"` 随即退化为
    逐样本准确率（数学恒等）。输入须保持 `[N,7]` 二维，见 `_as_2d` 与其回归测试。
  - 逐类 P/R/F1 与 per-class PR-AUC **必须随 support 同时给出**；support=0 的类保留（F1=0、support=0，
    不除零）；support≤2 的类仅描述性呈现、不进比较结论（由 evaluate 侧标注，本层只返回原始值）。
  - mAP 口径 = **macro AP**（仅对 support>0 的类求平均），返回 `ap_classes_used` 供报告；跳过类记入
    `skipped`（不静默吞掉）。
  - `search_global_threshold` 只在验证集调用：候选 0.20~0.80 步长 0.05，目标 **val micro-F1**
    （2026-09-12 由 macro-F1 改），并列取**较小阈值**（`>=` 下较小阈值更偏向召回）；val macro-F1 同步
    记录作参考。只计算不落盘（落盘由 train/evaluate 侧写 `thresholds.json`）。

阈值口径（大纲 5.2 / 手册 10.5）：固定 0.5 与验证集搜索阈值**双报告**；测试集不参与阈值选择；
稀有类不在验证集单独调阈（per-class 阈值仅补充分析，不进主结果）。

二分类口径（`--head binary` 臂，decisions §31）
  - **与多标签函数严格分流，不得混用**。多标签函数经 `_as_2d_multilabel` 校验：收到单列
    `[N,1]` 一律 `ValueError`；二分类函数经 `_as_1d_binary` 校验：收到多列一律 `ValueError`。
  - 这不是洁癖，是因为 `type_of_target([N,1]) == 'binary'`，而 `average="micro"` 在 binary 下
    **恒等于逐样本 accuracy**（`decisions.md` §28 的原 bug）。实测：`micro_f1([N,1] 全判负) == 0.5`
    而真值为 0。**静默错算过一次（105 个 run 作废），故此处改为响亮报错。**
  - 二分类指标一律**由混淆计数直接算**（`binary_counts`），不经 sklearn 的
    `average=` 分派——从根上绕开该陷阱。
  - 早停/调度判据用 **`binary_average_precision`（AP，阈值无关）**；报告工作点用
    `search_global_threshold_binary`（扫 val 二分类 F1）。**两者是两件事，不要混。**

CLI：无（纯函数库，无 main）。
"""

from __future__ import annotations

import numpy as np
import torch
from sklearn.metrics import (average_precision_score, f1_score,
                             precision_recall_fscore_support)

# 标签顺序固定（锁死；与 dataset.VULN_NAMES / model num_classes=7 一致，不得重排）
VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]

# 全局阈值扫描候选（大纲 5.2：0.2 ~ 0.8，步长 0.05；只用验证集）
THRESHOLD_CANDIDATES = tuple(round(0.20 + 0.05 * i, 2) for i in range(13))  # 0.20..0.80


def _as_numpy(t) -> np.ndarray:
    """torch.Tensor → numpy（detach + cpu）；numpy 原样转回 np.asarray。"""
    if isinstance(t, torch.Tensor):
        return t.detach().cpu().numpy()
    return np.asarray(t)


def _as_2d(t) -> np.ndarray:
    """保证 [N, C] 二维（一维输入视为单列 N×1）。

    ⚠ **严禁 ravel 后再送 sklearn**：`[N,7]` 展平成 1-D `{0,1}` 会把 sklearn 的
    `type_of_target` 从 `multilabel-indicator` 改判成 `binary`，而 `average="micro"`
    在 binary 下**恒等于逐样本 accuracy**（数学恒等），使标签对级 F1 退化成准确率。
    2026-09-17 修复，见 `experiments/decisions.md` §28。
    """
    a = _as_numpy(t)
    if a.ndim == 1:
        a = a.reshape(-1, 1)
    return a


def _as_2d_multilabel(t, fn: str) -> np.ndarray:
    """**多标签专用**入参：`[N, C]` 且 `C >= 2`；单列一律报错。

    🔴 存在的理由：`_as_2d` 会把一维变成 `[N,1]`，而 **`type_of_target([N,1]) == 'binary'`**
    ——sklearn 按**形状**分派，`average="micro"` 随即退化为逐样本 accuracy。
    实测 `micro_f1([N,1], 全判负) == 0.5`（真值 0.0）。这正是 §28 那个让 105 个 run 作废的 bug，
    只是换了个触发路径。**故此处必须响亮报错，不能静默算错**（§28.7 教训 5）。
    """
    a = _as_2d(t)
    if a.shape[1] < 2:
        raise ValueError(
            f"{fn} 需要多标签输入 [N, C>=2]，收到 {a.shape}。"
            "单列 [N,1] 会被 sklearn 判为 'binary'，average=\"micro\" 会退化成 accuracy"
            "（decisions §28）。二分类任务请用 binary_prf / binary_average_precision / "
            "search_global_threshold_binary。")
    return a


def _as_1d_binary(t, fn: str) -> np.ndarray:
    """**二分类专用**入参：`[N]` 或 `[N,1]` → 一维 `[N]`；多列一律报错。

    与 `_as_2d_multilabel` 对称：把 7 列输入送进二分类函数是调用方 bug，须报错而非静默取 `any()`。
    """
    a = _as_numpy(t)
    if a.ndim == 2 and a.shape[1] != 1:
        raise ValueError(
            f"{fn} 需要二分类输入 [N] 或 [N,1]，收到 {a.shape}。"
            "多列（如 [N,7]）请先用 any(axis=1) 显式塌成二分类，或改用多标签函数。")
    return a.reshape(-1)


def _safe_div(num: int, den: int):
    """安全除法：分母为 0 时返回 **None**（不返回 0——0 会被读成「没有误报/漏报」）。"""
    return None if den == 0 else float(num) / float(den)


def binary_preds(probs: torch.Tensor, thr: float) -> torch.Tensor:
    """概率 [N,7] → 0/1 预测 [N,7]（`>= thr` 为 1）。"""
    return (probs >= thr).to(torch.int64)


def micro_f1(y, p) -> float:
    """主指标：标签对级 micro-F1（sklearn `average="micro"`，zero_division=0）。

    语义 = 把全部 `(样本, 类)` 标签对展平后统计全局 TP/FP/FN 再算 F1；**不是**逐样本
    准确率，也**不是**精确匹配率（后者见 `subset_accuracy`）。二者按定义可相差数十个点
    （稀有类多时 micro-F1 远低于准确率），不得混用。
    """
    return float(f1_score(_as_2d_multilabel(y, "micro_f1"),
                          _as_2d_multilabel(p, "micro_f1"),
                          average="micro", zero_division=0))


def macro_f1(y, p) -> float:
    """参考指标：macro-F1（zero_division=0；报告时须注明支撑构成）。"""
    return float(f1_score(_as_2d_multilabel(y, "macro_f1"),
                          _as_2d_multilabel(p, "macro_f1"),
                          average="macro", zero_division=0))


def per_class_prf(y, p, names=VULN_NAMES) -> dict:
    """逐类 precision / recall / F1 / support（含 support=0 类：F1=0、support=0，不除零）。

    返回 {names, precision, recall, f1, support}，各为长度 7 的列表（顺序与 names 一致）。
    """
    y_np, p_np = _as_2d_multilabel(y, "per_class_prf"), _as_2d_multilabel(p, "per_class_prf")
    pr, rc, f1, sup = precision_recall_fscore_support(y_np, p_np, zero_division=0)
    return {
        "names": list(names),
        "precision": [float(v) for v in pr],
        "recall": [float(v) for v in rc],
        "f1": [float(v) for v in f1],
        "support": [int(v) for v in sup],
    }


def mean_average_precision(probs, y, names=VULN_NAMES) -> dict:
    """per-class PR-AUC 与 mAP（macro AP，仅对 support>0 的类求平均）。

    返回 {"mAP": float, "ap": [7]（跳过类为 None）, "ap_classes_used": int, "skipped": [names]}。
    support=0 的类跳过该类 AP 并记入 skipped（不除零、不静默）。
    """
    y_np, p_np = _as_2d_multilabel(y, "mean_average_precision"), \
        _as_2d_multilabel(probs, "mean_average_precision")
    ap: list = [None] * len(names)
    skipped: list[str] = []
    used = 0
    for c in range(len(names)):
        yc = y_np[:, c]
        if int(yc.sum()) == 0:
            skipped.append(names[c])
            continue
        ap[c] = float(average_precision_score(yc, p_np[:, c]))
        used += 1
    used_values = [v for v in ap if v is not None]
    mAP = float(np.mean(used_values)) if used_values else 0.0
    return {"mAP": mAP, "ap": ap, "ap_classes_used": used, "skipped": skipped}


def subset_accuracy(y, p) -> float:
    """可选：精确匹配率（整条 7 维标签全等 / 样本数）。"""
    y_np, p_np = _as_2d_multilabel(y, "subset_accuracy"), \
        _as_2d_multilabel(p, "subset_accuracy")
    n = y_np.shape[0]
    if n == 0:
        return 0.0
    return float((y_np == p_np).all(axis=1).sum()) / n


def search_global_threshold(probs_val, y_val,
                            candidates=THRESHOLD_CANDIDATES,
                            metric: str = "micro_f1") -> dict:
    """全局阈值扫描（**只在验证集**）：候选 0.20~0.80 步长 0.05，目标 val micro-F1。

    `metric` 决定按 micro_f1（默认，主）还是 macro_f1 选；无论选哪个，micro/macro 两套都记录。
    并列（指标值精确相等）时取**较小阈值**（`>=` 下更偏向召回）。
    返回全部候选指标与 tie 依据，供 evaluate/train 侧落盘 `thresholds.json`。
    """
    y_np, p_np = _as_2d_multilabel(y_val, "search_global_threshold"), \
        _as_2d_multilabel(probs_val, "search_global_threshold")
    best_threshold = None
    best_value = -float("inf")
    best_micro = best_macro = None
    scanned: list[dict] = []
    for thr in candidates:                      # 升序遍历 → 并列自然保留较小阈值
        preds = (p_np >= thr).astype(int)
        mif = float(f1_score(y_np, preds, average="micro", zero_division=0))
        maf = float(f1_score(y_np, preds, average="macro", zero_division=0))
        scanned.append({"threshold": thr, "micro_f1": mif, "macro_f1": maf})
        value = mif if metric == "micro_f1" else maf
        if value > best_value:                  # 严格大于才更新 → tie 取更小阈值
            best_value = value
            best_threshold = thr
            best_micro, best_macro = mif, maf
    return {
        "metric": metric,
        "best_threshold": best_threshold,
        f"best_{metric}": best_value,
        "best_micro_f1": best_micro,
        "best_macro_f1": best_macro,
        "candidates": scanned,
        "tie_break": "并列取较小阈值（`>=` 下更偏向召回）",
    }


# --------------------------------------------------------------- 二分类层（--head binary）
# ⚠ 本层的每个函数都**只接受 [N] / [N,1]**（多列报错），且**一律由混淆计数直接算**——
#   不经 sklearn 的 `average=` 分派，从根上绕开 `type_of_target([N,1])=='binary'` 的陷阱（§28）。

BINARY_NAME = "vulnerable"      # 二分类臂的唯"类"名，供报告/诊断层复用


HEADS = ("multi", "binary")


def head_num_classes(head: str) -> int:
    """`--head` → 输出头宽度（`multi`=7、`binary`=1）。未知取值报错，不静默回退。

    **本函数是 head→宽度的唯一事实来源**：`train.py` / `evaluate.py` 都从这里取，
    避免两处各写一份 `7 if ... else 1` 而漂移（§28 的教训就是"同一语义两处实现"）。
    """
    if head not in HEADS:
        raise ValueError(f"未知 head={head!r}（应为 {HEADS}）")
    return len(VULN_NAMES) if head == "multi" else 1


def contract_any_labels(labels):
    """`[N,C]` 标签 → `[N]` 的 `any(axis=1)`（`C==1` 时恒等）——「有没有漏洞」的真值。

    分析层把七类臂塌成二分类视图的**唯一入口**（显式，不隐藏）。
    """
    a = _as_numpy(labels)
    return a.reshape(-1) if a.ndim == 1 or a.shape[1] == 1 else a.any(axis=1)


def contract_any_scores(probs):
    """`[N,C]` 概率 → `[N]` 的逐行 `max`（`C==1` 时恒等）——「有没有漏洞」的分数。

    🔑 **等价性（本条使二分类臂与七类臂的塌缩视图可直接配对）**：对任意全局阈值 `t`，
        `any_c(p_c >= t)  <=>  max_c p_c >= t`
    故「先按类阈值化再 any」与「先 max 再阈值化」在 @0.5 / @val_thr 两个工作点上**逐位等价**。
    已由 `tests/test_metrics.py` 机检。注意**不可**用 `mean`：它与 `any` 不等价。
    """
    a = _as_numpy(probs)
    return a.reshape(-1) if a.ndim == 1 or a.shape[1] == 1 else a.max(axis=1)


def buggy_f1(y, p) -> dict:
    """**补充口径：有漏洞合约子集上的 micro-F1**（智能合约文献常称 Buggy-F1）。

    ⚠ 与 MANDO-HGT 表格里那一列是否同义，**须与原文核对后再写进论文**；本节只钉死本仓的定义。

    定义就是「按 `y.any(axis=1)` 切片后算 `micro_f1`」——把**干净合约上的误报整段摘掉**，
    只回答「在真正有漏洞的合约上，七类标签判得准不准」。动机见
    `tests/test_metrics.py::test_buggy_f1_removes_false_alarms_on_clean_contracts`。

    🔴 **与合约级二分类 F1（`binary_prf(contract_any_labels(y), contract_any_scores(p)>=t)`）
    不是同一个数**，两者必须分列呈现、不得互换（`decisions.md` §30 三条禁令之一）：

    | 口径 | 分子/分母的粒度 | 干净合约上的误报 | 问的是 |
    |---|---|---|---|
    | `buggy_f1` | **标签对**，且只数有漏洞的合约 | 被**整段摘掉** | 「漏洞判得准不准」 |
    | 合约级二分类 F1 | **合约**（`any` 塌缩） | 计入 FP | 「有没有报出至少一类」 |

    前者是**上界性质**的读数（干净合约再乱报也不扣分），后者才对应部署代价。
    两者的差 = 「干净合约上的误报」+「把有漏洞的合约报成了别的类」在子集内的残留。

    `f1` 在子集为空（无任何有漏洞合约）时记 `None`——**不记 0.0**（0.0 会被读成"模型很差"）。
    单列 `[N,1]` 一律报错（走 sklearn 会退化成 accuracy，§28）。

    返回 `{"f1", "n_rows_total", "n_rows_masked", "n_pos_pairs"}`。
    """
    y2 = _as_2d_multilabel(y, "buggy_f1")
    p2 = _as_2d_multilabel(p, "buggy_f1")
    if y2.shape != p2.shape:
        raise ValueError(f"buggy_f1 的 y 与 p 形状不一致：{y2.shape} vs {p2.shape}")
    mask = y2.any(axis=1)
    n_masked = int(mask.sum())
    f1 = None if n_masked == 0 else micro_f1(y2[mask], p2[mask])
    return {"f1": f1,
            "n_rows_total": int(y2.shape[0]),
            "n_rows_masked": n_masked,
            "n_pos_pairs": int(y2.sum())}


def head_names(head: str) -> tuple:
    """`--head` → 输出空间的类名元组（`multi`→7 类固定序；`binary`→单元素）。

    报告层与诊断层据此决定表头/行数，**不各自硬编码 7**（否则二分类臂一跑就 IndexError）。
    """
    head_num_classes(head)          # 校验取值
    return tuple(VULN_NAMES) if head == "multi" else (BINARY_NAME,)


def binary_counts(y, p) -> dict:
    """二分类混淆计数（正类 = 1）。返回 TP/FP/FN/TN 与 support/n。"""
    y1 = _as_1d_binary(y, "binary_counts").astype(int)
    p1 = _as_1d_binary(p, "binary_counts").astype(int)
    tp = int(((y1 == 1) & (p1 == 1)).sum())
    fp = int(((y1 == 0) & (p1 == 1)).sum())
    fn = int(((y1 == 1) & (p1 == 0)).sum())
    tn = int(((y1 == 0) & (p1 == 0)).sum())
    return {"TP": tp, "FP": fp, "FN": fn, "TN": tn,
            "support": tp + fn, "n": tp + fp + fn + tn}


def binary_prf(y, p) -> dict:
    """二分类 precision / recall / F1 / accuracy / FPR / FNR（**由计数直接算**）。

    分母为 0 的项记 `None`（不记 0——0 会被读成「没有误报/漏报」），与 `error_rates._div` 同约定。
    - `FPR = FP/(FP+TN)`（干净合约被误报的比例）；`FNR = FN/(FN+TP)`（正合约被漏掉的比例）。
    - ⚠ **不是** `micro_f1`：后者在单列输入上等于 accuracy（§28）。
    """
    c = binary_counts(y, p)
    tp, fp, fn, tn = c["TP"], c["FP"], c["FN"], c["TN"]
    prec = _safe_div(tp, tp + fp)
    rec = _safe_div(tp, tp + fn)
    if c["support"] == 0:
        f1 = None                                   # 全无正样本 → F1 无定义
    elif prec is None or prec + rec == 0:
        f1 = 0.0                                    # 有正样本却一个没报出 → 有意义的 0（非无定义）
    else:
        f1 = 2 * prec * rec / (prec + rec)
    return {"precision": prec, "recall": rec, "f1": f1,
            "accuracy": _safe_div(tp + tn, c["n"]),
            "FPR": _safe_div(fp, fp + tn), "FNR": _safe_div(fn, fn + tp),
            "support": c["support"], "n": c["n"], **c}


def micro_f1_counts(y, p) -> float:
    """标签对级 micro-F1 的**计数式**实现（**不经 sklearn 的 `average=` 分派**）。

    与 `micro_f1()` 是**同一个指标定义**（全局 TP/FP/FN 汇总），但 ① 不依赖 sklearn 按**形状**
    分派任务类型，② 对 `[N,1]` 也成立。第 ② 条正是二分类臂能报 `micro_f1` 的依据：
    **`C == 1` 时本函数恒等于二分类 F1**（`2TP/(2TP+FP+FN)`，两者是同一式子的两种叫法）。

    ⚠ 与 `micro_f1()` 的分工：多标签臂走 `micro_f1()`（保持与既有结果逐位一致）；
    二分类臂走本函数（`[N,1]` 会让前者的 `average="micro"` 退化成 accuracy，§28）。
    两者在二维输入上的一致性由 `tests/test_metrics.py` 逐位对照钉住。
    """
    y_np = _as_numpy(y).astype(int)
    p_np = _as_numpy(p).astype(int)
    if y_np.ndim == 1:
        y_np = y_np.reshape(-1, 1)
    if p_np.ndim == 1:
        p_np = p_np.reshape(-1, 1)
    tp = int((y_np * p_np).sum())
    fp = int(((1 - y_np) * p_np).sum())
    fn = int((y_np * (1 - p_np)).sum())
    if tp == 0:
        return 0.0                      # 一个正样本都没报出 → 0（有意义），不是 0/0
    return 2.0 * tp / (2.0 * tp + fp + fn)


def binary_f1(y, p) -> float:
    """二分类 F1 的**标量**形式（分母为 0 时返回 0.0，供阈值扫描作目标函数用）。

    报告请用 `binary_prf`（它保留 `None` 语义）；本函数只给"可比较的标量"。
    """
    v = binary_prf(y, p)["f1"]
    return 0.0 if v is None else float(v)


def binary_average_precision(probs, y) -> dict:
    """二分类 AP（PR-AUC，**阈值无关**）——`--head binary` 臂的**早停/调度判据**。

    返回 `{"AP": float|None, "support": int, "n": int}`；全负或全正时 AP 无定义 → `None`
    （**不静默给 0.5**）。为什么用它而非 val F1 做判据：合约级 F1 在低支撑语料上被常量预测器
    刷到 0.62/0.93（真实模型 0.723/0.990，可提升空间只剩 0.10/0.06），动态范围过小会让早停选错点
    （`report_conclusions.md` §9.6.1）。
    """
    y1 = _as_1d_binary(y, "binary_average_precision").astype(int)
    p1 = _as_1d_binary(probs, "binary_average_precision")
    if y1.sum() == 0 or y1.sum() == len(y1):
        return {"AP": None, "support": int(y1.sum()), "n": int(len(y1))}
    return {"AP": float(average_precision_score(y1, p1)),
            "support": int(y1.sum()), "n": int(len(y1))}


def search_global_threshold_binary(probs_val, y_val,
                                   candidates=THRESHOLD_CANDIDATES) -> dict:
    """二分类阈值扫描（**只在验证集**）：候选 0.20~0.80 步长 0.05，目标 val 二分类 F1。

    与 `search_global_threshold` 同构（升序遍历 + 严格大于才更新 ⇒ 并列取**较小阈值**），
    但**目标换成二分类 F1**、且不做 micro/macro 分派。返回结构与之对齐，便于报告层复用。

    ⚠ 本函数给出的是**报告用的工作点**，**不是**早停判据（早停用 `binary_average_precision`）。
    """
    y1 = _as_1d_binary(y_val, "search_global_threshold_binary").astype(int)
    p1 = _as_1d_binary(probs_val, "search_global_threshold_binary")
    best_threshold = None
    best_value = -float("inf")
    scanned: list[dict] = []
    for thr in candidates:                      # 升序遍历 → 并列自然保留较小阈值
        preds = (p1 >= thr).astype(int)
        f1 = binary_f1(y1, preds)
        scanned.append({"threshold": thr, "f1": f1})
        if f1 > best_value:                     # 严格大于才更新 → tie 取更小阈值
            best_value = f1
            best_threshold = thr
    return {
        "metric": "binary_f1",
        "best_threshold": best_threshold,
        "best_binary_f1": best_value,
        "candidates": scanned,
        "tie_break": "并列取较小阈值（`>=` 下更偏向召回）",
    }
