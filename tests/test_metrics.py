"""M5 指标层单测（手册 12.4；纯函数、零数据依赖）。

覆盖（关卡 = 合成边界无 NaN、与 sklearn 对照逐位相等、zero-positive 跳过、tie 取小）：
  1. micro/macro-F1 对合成边界（全 0 预测、全 1 预测、含空标签类）无 NaN、zero_division=0，
     且与 sklearn 对照逐位相等；
  1b. **回归锁（2026-09-17，decisions §28）**：micro-F1 必须走 `multilabel-indicator` 分支，
     不得因数组被展平而退化为逐样本 accuracy —— 全判负须为 0（而非 0.90+ 的 accuracy），
     阈值搜索的 argmax 须与 accuracy 的 argmax 分离；
  2. per_class_prf 在含 support=0 类时返回该 support=0 且 F1=0，不除零；
  3. mean_average_precision 跳过 zero-positive 类、ap_classes_used 计数正确、单类数据 AP=1.0；
  4. search_global_threshold 在单调场景选到正确阈值；并列时取较小阈值；候选列表完整。

运行：pytest tests/test_metrics.py -q
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest
import torch
from sklearn.metrics import (average_precision_score, f1_score,
                             precision_score, recall_score)

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics  # noqa: E402
from metrics import (VULN_NAMES, binary_preds, macro_f1,  # noqa: E402
                     mean_average_precision, micro_f1, per_class_prf,
                     search_global_threshold, subset_accuracy)

N_CLS = len(VULN_NAMES)


def _y(rows):
    return torch.tensor(rows, dtype=torch.float32)


def _p(rows):
    return torch.tensor(rows, dtype=torch.float32)


# ----------------------------------------------------------------- 1) F1 边界与 sklearn 对照
def test_micro_macro_f1_boundaries_no_nan_and_sklearn_match():
    y = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0]])
    for preds in (_p([[0] * 7] * 3), _p([[1] * 7] * 3)):
        y_np, p_np = y.numpy(), preds.numpy()
        # ⚠ 参照必须用二维接口：`.ravel()` 会让 sklearn 走 binary 分支 → micro 变成 accuracy
        assert micro_f1(y, preds) == pytest.approx(
            f1_score(y_np, p_np, average="micro", zero_division=0))
        assert macro_f1(y, preds) == pytest.approx(
            f1_score(y_np, p_np, average="macro", zero_division=0))
        assert not np.isnan(micro_f1(y, preds)) and not np.isnan(macro_f1(y, preds))


def test_micro_f1_matches_sklearn_random():
    g = torch.Generator().manual_seed(0)
    y = (torch.rand(20, 7, generator=g) < 0.3).float()
    p = (torch.rand(20, 7, generator=g) < 0.4).int()
    assert micro_f1(y, p) == pytest.approx(
        f1_score(y.numpy(), p.numpy(), average="micro", zero_division=0))
    assert macro_f1(y, p) == pytest.approx(
        f1_score(y.numpy(), p.numpy(), average="macro", zero_division=0))


# ------------------------------------------------- 1b) 回归：micro-F1 不得退化为 accuracy（§28）
def test_micro_f1_all_negative_preds_is_zero_not_accuracy():
    """全判负时标签对级 micro-F1 必须恰为 0，而逐样本 accuracy 可以很高。

    这是 2026-09-17 修复的回归锁：旧实现 `.ravel()` 使 sklearn 把问题当 binary，
    `average="micro"` 恒等于 accuracy，于是「全判负」被打成 0.9048 这种高分。
    """
    y = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0],
            [0, 0, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0]])
    p = _p([[0] * 7] * 4)
    assert micro_f1(y, p) == pytest.approx(0.0)
    # 逐样本 accuracy 显著非零（4×7=28 格，仅 3 个正例被漏 → 25/28）→ 二者必须是不同的量
    assert float((y.numpy() == p.numpy()).mean()) == pytest.approx(25 / 28)
    assert micro_f1(y, p) != pytest.approx(float((y.numpy() == p.numpy()).mean()))


def test_micro_f1_stays_multilabel_and_differs_from_accuracy():
    """随机稀疏多标签下：micro-F1 = sklearn 二维参照，且**不等于** accuracy。

    稀疏正例（p=0.15）使全局 TP/FP/FN 与逐样本命中率必然分离 —— 若哪天有人再把
    输入展平，本断言会立刻失败。同时锁住 micro-F1 与 subset_accuracy（精确匹配）互不相等。
    """
    g = torch.Generator().manual_seed(0)
    y = (torch.rand(200, N_CLS, generator=g) < 0.15).float()
    p = (torch.rand(200, N_CLS, generator=g) < 0.10).int()
    ref = f1_score(y.numpy(), p.numpy(), average="micro", zero_division=0)
    assert micro_f1(y, p) == pytest.approx(ref)
    acc = float((y.numpy() == p.numpy()).mean())
    assert micro_f1(y, p) < acc - 0.5          # 实测 0.110 vs 0.769，留足裕度
    assert micro_f1(y, p) != pytest.approx(subset_accuracy(y, p))


def test_binary_preds_threshold_inclusive():
    probs = torch.tensor([[0.2, 0.5, 0.8]])
    assert torch.equal(binary_preds(probs, 0.5), torch.tensor([[0, 1, 1]]))


# ----------------------------------------------------------------- 2) 逐类 P/R/F1（support=0）
def test_per_class_prf_zero_support_class_not_divide_by_zero():
    y = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0]])
    p = _y([[1, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0]])
    out = per_class_prf(y, p)
    assert out["names"] == VULN_NAMES
    assert out["support"][0] == 1 and out["support"][1] == 1
    assert out["support"][2] == 0 and out["f1"][2] == 0.0
    assert out["precision"][2] == 0.0 and out["recall"][2] == 0.0
    # class0: 预测正确 1/1 → P=R=F1=1
    assert out["f1"][0] == pytest.approx(1.0)
    assert all(not np.isnan(v) for v in out["f1"] + out["precision"] + out["recall"])


# ----------------------------------------------------------------- 3) mAP / per-class PR-AUC
def test_mean_average_precision_skips_zero_positive_and_single_class_ap_is_one():
    probs = torch.tensor([[0.1], [0.2], [0.9], [0.8]])
    y = torch.tensor([[0], [0], [1], [1]])
    # 扩展为 7 列：class0 有正样本，其余 6 类无正样本
    P = torch.cat([probs, torch.zeros(4, 6)], dim=1)
    Y = torch.cat([y, torch.zeros(4, 6, dtype=torch.long)], dim=1)
    out = mean_average_precision(P, Y)
    assert out["ap_classes_used"] == 1
    assert out["skipped"] == VULN_NAMES[1:]
    assert out["ap"][0] == pytest.approx(1.0)
    assert out["mAP"] == pytest.approx(1.0)
    assert all(v is None for v in out["ap"][1:])
    # 对照 sklearn 单列 AP
    ref = average_precision_score(Y[:, 0].numpy(), P[:, 0].numpy())
    assert out["ap"][0] == pytest.approx(ref)


def test_mean_average_precision_all_zero_positive():
    probs = torch.rand(5, 7)
    y = torch.zeros(5, 7)
    out = mean_average_precision(probs, y)
    assert out["ap_classes_used"] == 0 and out["mAP"] == 0.0
    assert out["skipped"] == VULN_NAMES


# ----------------------------------------------------------------- 4) 阈值扫描
def test_search_global_threshold_monotonic_selects_separator():
    probs = torch.tensor([[0.55], [0.45], [0.55], [0.45]])
    y = torch.tensor([[1], [0], [1], [0]])
    P = torch.cat([probs, torch.zeros(4, 6)], dim=1)
    Y = torch.cat([y, torch.zeros(4, 6, dtype=torch.long)], dim=1)
    out = search_global_threshold(P, Y)
    assert out["best_threshold"] == pytest.approx(0.50)
    assert out["best_micro_f1"] == pytest.approx(1.0)
    assert out["metric"] == "micro_f1"
    # 候选完整（0.20..0.80 步长 0.05，共 13 个）
    assert [c["threshold"] for c in out["candidates"]] == \
        [round(0.20 + 0.05 * i, 2) for i in range(13)]
    assert all(set(c) == {"threshold", "micro_f1", "macro_f1"} for c in out["candidates"])


def test_search_global_threshold_tie_breaks_to_smaller_threshold():
    # 全部预测为负 → 所有候选 micro-F1 相同（0）→ 取最小阈值 0.20
    probs = torch.zeros(3, 7) + 0.1
    y = torch.ones(3, 7)
    out = search_global_threshold(probs, y)
    assert out["best_threshold"] == pytest.approx(0.20)
    assert out["best_micro_f1"] == pytest.approx(0.0)


def test_search_global_threshold_objective_is_true_micro_f1():
    """阈值搜索的目标必须是**二维** micro-F1，不是 accuracy（§28 修复的第二处）。

    逐候选与 `f1_score(Y2d, preds2d, average="micro")` 对照，并断言 argmax 就是该目标；
    最后断言最优阈值 ≠ accuracy 最优阈值，否则本测试对该 bug 无鉴别力。
    """
    g = torch.Generator().manual_seed(3)
    Y = (torch.rand(60, N_CLS, generator=g) < 0.12).float()
    P = torch.rand(60, N_CLS, generator=g) * 0.6 + 0.2     # 覆盖 0.2~0.8，让阈值真正起作用
    out = search_global_threshold(P, Y)
    Yn, Pn = Y.numpy(), P.numpy()
    for c in out["candidates"]:
        preds = (Pn >= c["threshold"]).astype(int)
        assert c["micro_f1"] == pytest.approx(
            f1_score(Yn, preds, average="micro", zero_division=0))
    vals = [(c["micro_f1"], c["threshold"]) for c in out["candidates"]]
    best = max(v for v, _ in vals)
    assert out["best_micro_f1"] == pytest.approx(best)
    assert out["best_threshold"] == pytest.approx(min(t for v, t in vals if v == best))
    accs = [float((Yn == (Pn >= c["threshold"]).astype(int)).mean())
            for c in out["candidates"]]
    best_acc_t = out["candidates"][int(np.argmax(accs))]["threshold"]
    assert out["best_threshold"] != pytest.approx(best_acc_t)


def test_subset_accuracy_exact_match():
    y = _y([[1, 0, 0, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0, 0]])
    p = _y([[1, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0]])
    assert subset_accuracy(y, p) == pytest.approx(0.5)


# --------------------------------------------------------------------------- 5) 二分类臂
# `--head binary`（decisions §31）。这一节的存在理由只有一个：
# **`[N,1]` 的 type_of_target 是 'binary'，`average="micro"` 随即恒等于 accuracy（§28）**。
# 那个 bug 让 105 个 run 作废过一次，所以这里既锁"新函数算得对"，也锁"老函数会报错"。

def _b(n_pos: int, n: int = 10):
    """`[n]` 二分类标签：前 n_pos 个为 1。"""
    return np.array([1] * n_pos + [0] * (n - n_pos), dtype=int)


def test_binary_prf_all_negative_is_zero_not_accuracy():
    """🔴 §28 的回归锁：全判负必须 F1=0，**不是** accuracy。"""
    y = _b(4, 10)                      # 40% 正
    p = np.zeros(10, dtype=int)        # 全判负
    r = metrics.binary_prf(y, p)
    assert r["f1"] == 0.0
    assert r["recall"] == 0.0
    assert r["accuracy"] == pytest.approx(0.6)     # ← 同数据的 accuracy
    assert r["f1"] != pytest.approx(r["accuracy"])  # ← 二者绝不能相等
    assert metrics.binary_f1(y, p) == 0.0
    assert r["FNR"] == 1.0 and r["FPR"] == 0.0


def test_multilabel_entrypoints_reject_single_column():
    """同一份 `[N,1]` 数据，多标签函数必须**报错**而不是静默给出 accuracy。"""
    y2 = _b(4, 10).reshape(-1, 1).astype(float)
    p2 = np.zeros_like(y2)
    for fn, args in (("micro_f1", (y2, p2)), ("macro_f1", (y2, p2)),
                     ("per_class_prf", (y2, p2)), ("subset_accuracy", (y2, p2)),
                     ("mean_average_precision", (y2.astype(float), y2)),
                     ("search_global_threshold", (y2, y2))):
        with pytest.raises(ValueError, match="多标签输入"):
            getattr(metrics, fn)(*args)
    # 反例对照：同样的数据在 [N,7] 形状下 micro_f1 正常为 0（不是 accuracy）
    y7 = np.zeros((10, 7)); y7[np.arange(4), 0] = 1
    assert metrics.micro_f1(y7, np.zeros((10, 7))) == 0.0


def test_binary_functions_reject_multi_column():
    """反向守卫：把 7 列送进二分类函数同样是调用方 bug，必须报错而非静默取第 0 列。"""
    y7 = np.zeros((5, 7), dtype=int); y7[0, 0] = 1
    for fn in ("binary_counts", "binary_prf", "binary_f1", "binary_average_precision"):
        with pytest.raises(ValueError, match="二分类输入"):
            getattr(metrics, fn)(y7, y7)
    with pytest.raises(ValueError, match="二分类输入"):
        metrics.search_global_threshold_binary(y7, y7)


def test_binary_prf_matches_sklearn_binary_reference():
    """计数实现必须**对**（不只是"与 §28 不同"）：与 sklearn 的 binary 口径逐位相等。"""
    rng = np.random.default_rng(0)
    y = (rng.random(200) < 0.3).astype(int)
    p = (rng.random(200) < 0.4).astype(int)
    r = metrics.binary_prf(y, p)
    assert r["precision"] == pytest.approx(precision_score(y, p, zero_division=0))
    assert r["recall"] == pytest.approx(recall_score(y, p, zero_division=0))
    assert r["f1"] == pytest.approx(f1_score(y, p, zero_division=0))
    assert r["accuracy"] == pytest.approx((y == p).mean())


def test_binary_average_precision_constant_scores_equals_pos_rate():
    """常量分数 → AP = 正样本率。这就是 §9.6.1 里「常量预测器」的基线，故必须可复算。"""
    y = _b(3, 10)
    const = np.full(10, 0.5)
    assert metrics.binary_average_precision(const, y)["AP"] == pytest.approx(0.3)


def test_binary_average_precision_undefined_on_single_class():
    """val 全正/全负时 AP 无定义 → `None`（**不静默给 0.5**）。"""
    p = np.linspace(0, 1, 10)
    assert metrics.binary_average_precision(p, np.ones(10, dtype=int))["AP"] is None
    assert metrics.binary_average_precision(p, np.zeros(10, dtype=int))["AP"] is None


def test_contract_any_scores_equivalent_to_any_after_threshold():
    """🔑 配对比较的合法性所在：`max_c p_c >= t  ⇔  any_c(p_c >= t)`（对全部候选阈值）。"""
    rng = np.random.default_rng(1)
    probs = rng.random((60, 7))
    scores = metrics.contract_any_scores(probs)
    for t in metrics.THRESHOLD_CANDIDATES:
        assert np.array_equal(scores >= t, (probs >= t).any(axis=1))
    # 与 max 不同：mean 不满足该等价性，不得用作塌缩函数
    assert not np.array_equal(probs.mean(axis=1) >= 0.4, (probs >= 0.4).any(axis=1))


def test_contract_any_is_identity_on_single_column():
    """`[N,1]` 上是恒等（二分类臂自身走同一函数，不特殊分支）。"""
    x = np.array([[0.2], [0.8], [0.5]])
    assert np.array_equal(metrics.contract_any_scores(x), x.reshape(-1))
    y = np.array([[1], [0], [1]])
    assert np.array_equal(metrics.contract_any_labels(y), y.reshape(-1))


def test_search_binary_threshold_objective_is_f1_not_accuracy():
    """阈值扫描的目标必须是二分类 F1，且**并列取较小阈值**（与七类臂同协议）。"""
    y = _b(4, 10)
    p = torch.tensor([0.9, 0.8, 0.7, 0.6, 0.55, 0.45, 0.4, 0.3, 0.2, 0.1])
    out = metrics.search_global_threshold_binary(p, torch.tensor(y))
    assert out["metric"] == "binary_f1"
    assert len(out["candidates"]) == 13
    vals = [(c["f1"], c["threshold"]) for c in out["candidates"]]
    best = max(v for v, _ in vals)
    assert out["best_binary_f1"] == pytest.approx(best)
    assert out["best_threshold"] == pytest.approx(min(t for v, t in vals if v == best))
    # 全判负的候选阈值必须给 0（真实 0，不是 accuracy）
    assert out["candidates"][0]["f1"] >= 0.0


def test_head_helpers_reject_unknown_head():
    assert metrics.head_num_classes("multi") == 7
    assert metrics.head_num_classes("binary") == 1
    assert metrics.head_names("binary") == (metrics.BINARY_NAME,)
    assert metrics.head_names("multi") == tuple(metrics.VULN_NAMES)
    with pytest.raises(ValueError):
        metrics.head_num_classes("multiclass")


def test_micro_f1_counts_matches_sklearn_two_dimensional():
    """计数式 micro-F1 与 sklearn 的二维实现**逐位相等**——证明它与七类臂是同一个指标，
    因而二分类臂报 `micro_f1` 不是"换个名字"，而是同一量在 `C==1` 下的取值。"""
    rng = np.random.default_rng(7)
    for n, c in ((60, 7), (40, 3), (25, 1), (10, 1)):
        y = (rng.random((n, c)) < 0.3).astype(int)
        p = (rng.random((n, c)) < 0.4).astype(int)
        if c == 1:
            # 单列：sklearn 的 average="micro" 会退化成 accuracy，故只与**二分类 F1** 对照
            assert metrics.micro_f1_counts(y, p) == pytest.approx(
                f1_score(y.ravel(), p.ravel(), zero_division=0))
            assert metrics.micro_f1_counts(y, p) == pytest.approx(metrics.binary_f1(y, p))
        else:
            assert metrics.micro_f1_counts(y, p) == pytest.approx(metrics.micro_f1(y, p))
            assert metrics.micro_f1_counts(y, p) == pytest.approx(
                f1_score(y, p, average="micro", zero_division=0))


def test_micro_f1_counts_accepts_single_column_without_guard_error():
    """它是二分类臂的路径，**不得**像多标签入口那样拒绝单列（且值必须不是 accuracy）。"""
    y = _b(4, 10).reshape(-1, 1)
    p = np.zeros((10, 1), dtype=int)
    assert metrics.micro_f1_counts(y, p) == 0.0
    assert metrics.micro_f1_counts(y, p) != pytest.approx((y == p).mean())
    with pytest.raises(ValueError):
        metrics.micro_f1(y, p)          # 对照：多标签入口仍然报错


# --------------------------------------------------- 6) 补充口径：buggy_f1（有漏洞合约子集）
def test_buggy_f1_matches_manual_slice():
    """定义就是「按 `y.any(axis=1)` 切片后算 micro_f1」，须与手工切片**逐位相等**。"""
    rng = np.random.default_rng(11)
    y = (rng.random((30, N_CLS)) < 0.25).astype(int)
    p = (rng.random((30, N_CLS)) < 0.35).astype(int)
    m = y.any(axis=1)
    out = metrics.buggy_f1(y, p)
    assert out["f1"] == pytest.approx(micro_f1(y[m], p[m]))
    assert out["n_rows_total"] == 30
    assert out["n_rows_masked"] == int(m.sum())
    assert out["n_pos_pairs"] == int(y.sum())


def test_buggy_f1_equals_micro_when_no_clean_contracts():
    """没有干净合约时，子集 == 全集 ⇒ 两口径必须相等（这也是 ② 上两者接近的原因）。"""
    y = np.zeros((8, N_CLS), dtype=int)
    y[:, 0] = 1
    p = np.zeros((8, N_CLS), dtype=int)
    p[:5, 0] = 1
    assert metrics.buggy_f1(y, p)["f1"] == pytest.approx(micro_f1(y, p))


def test_buggy_f1_removes_false_alarms_on_clean_contracts():
    """**本口径的动机**：干净合约上的误报拉低 micro-F1，但不应影响 buggy_f1。"""
    y = np.zeros((4, N_CLS), dtype=int)
    y[0, 0] = 1                       # 唯一一张有漏洞合约
    p = np.zeros((4, N_CLS), dtype=int)
    p[0, 0] = 1                       # 判对了
    p[1:, 0] = 1                      # 在 3 张干净合约上全误报
    assert micro_f1(y, p) < 1.0
    assert metrics.buggy_f1(y, p)["f1"] == pytest.approx(1.0)


def test_buggy_f1_empty_subset_is_none_not_zero():
    """全零划分（无正样本）⇒ `None`，**不得**返回 0.0（0.0 会被读成"模型很差"）。"""
    y = np.zeros((6, N_CLS), dtype=int)
    p = (np.random.default_rng(3).random((6, N_CLS)) < 0.5).astype(int)
    out = metrics.buggy_f1(y, p)
    assert out["f1"] is None
    assert out["n_rows_masked"] == 0
    assert out["n_rows_total"] == 6


def test_buggy_f1_rejects_single_column():
    """单列 `[N,1]` 走 sklearn 会退化成 accuracy（§28 那个让 105 个 run 作废的 bug）
    ⇒ 必须**响亮报错**，不得静默算错。"""
    with pytest.raises(ValueError):
        metrics.buggy_f1(np.zeros((10, 1), dtype=int), np.zeros((10, 1), dtype=int))


def test_buggy_f1_differs_from_contract_binary_f1():
    """两个数**不是**同一个：子集 micro-F1（标签对级）vs 合约级二分类 F1。"""
    y = np.zeros((6, N_CLS), dtype=int)
    y[0, 0] = 1
    y[1, 1] = 1
    p = np.zeros((6, N_CLS), dtype=int)
    p[0, 0] = 1                       # 合约级判对、标签对级也判对
    p[2, 2] = 1                       # 干净合约上的误报：合约级算错，标签对级已被子集摘掉
    buggy = metrics.buggy_f1(y, p)["f1"]
    cbin = metrics.binary_prf(metrics.contract_any_labels(y),
                              metrics.contract_any_scores(p) >= 0.5)["f1"]
    assert buggy != pytest.approx(cbin)
