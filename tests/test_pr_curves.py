"""PR 曲线层单测（2026-10-10 新增；纯函数 + 路径解析，**零真实产物依赖**）。

覆盖（关卡 = 与 `mean_average_precision` 同源、support=0 跳过、展平口径、路径模板）：
  1. `metrics.pr_curve` 的逐类 `ap` 必须与 `mean_average_precision` **逐位相等**
     —— 它是薄封装，不是第二份实现（本仓「同一语义两处实现」的教训）；
  2. support=0 的类**跳过并记入 `skipped`**，不返回空数组冒充；
  3. micro 的 `ap` 必须等于**展平后**（标签对级）的 sklearn AP —— 这是与主指标
     micro-F1 同口径的**唯一**不失真做法；
  4. `prevalence` = 正类占比（PR 空间的随机基线是**水平线**，不是对角线）；
  5. `plot_pr_curves.path_of` 的模板解析（`{seed}` 与 `{arm}` 必须一次 format 完成，
     分两次会 KeyError —— 初版踩过）。

运行：pytest tests/test_pr_curves.py -q
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest
from sklearn.metrics import average_precision_score

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics  # noqa: E402
import plot_pr_curves as P  # noqa: E402

NAMES = list(metrics.VULN_NAMES)


def _toy(seed: int = 0):
    """合成七类数据：**逐类正例率刻意不等**（模拟真实稀有类），末类 support=0。

    🔴 正例率必须不等：若七类同率，micro（标签对级）与 macro（逐类平均）会**恰好相等**，
    `test_micro_is_label_pair_level` 的最后一条断言就恒真、测不出东西（初版即如此）。
    分数也刻意留噪（不完美可分），否则所有 AP 都撞到 1.0。
    """
    rng = np.random.default_rng(seed)
    rates = np.array([0.10, 0.45, 0.30, 0.08, 0.50, 0.20, 0.0])
    y = (rng.random((40, 7)) < rates).astype(int)
    y[:, 6] = 0                                    # 末类全零 ⇒ support=0
    p = np.clip(y * 0.45 + rng.random((40, 7)) * 0.75, 0, 1)
    return p, y


def test_ap_matches_mean_average_precision():
    """① 逐类 AP 与 `mean_average_precision` 逐位相等（薄封装，不许分叉）。"""
    p, y = _toy()
    c = metrics.pr_curve(p, y, names=NAMES)
    m = metrics.mean_average_precision(p, y, names=NAMES)
    for i, n in enumerate(NAMES):
        if m["ap"][i] is None:
            assert n not in c["classes"]            # 跳过类不进 classes
            continue
        assert c["classes"][n]["ap"] == pytest.approx(m["ap"][i], abs=1e-12)


def test_support_zero_skipped_not_faked():
    """② support=0 的类必须进 `skipped`，且不产出曲线点。"""
    p, y = _toy()
    c = metrics.pr_curve(p, y, names=NAMES)
    assert c["skipped"] == [NAMES[6]]
    assert NAMES[6] not in c["classes"]
    assert set(c["classes"]) == set(NAMES[:6])
    for n, d in c["classes"].items():
        assert len(d["precision"]) == len(d["recall"]) > 0
        assert d["support"] > 0


def test_micro_is_label_pair_level():
    """③ micro AP/曲线 = 展平后的标签对级（与主指标 micro-F1 同口径）。"""
    p, y = _toy(3)
    c = metrics.pr_curve(p, y, names=NAMES)
    flat_ap = average_precision_score(y.ravel().astype(int), p.ravel())
    assert c["micro"]["ap"] == pytest.approx(flat_ap, abs=1e-12)
    # 展平后的 PR 点数应显著多于单类（单类 ≤ 样本数，展平 = 7*40 个对）
    assert len(c["micro"]["precision"]) > max(
        len(d["precision"]) for d in c["classes"].values())
    # micro 的 AP 与「逐类 AP 的算术平均」不是同一个数（口径不同，不可互引）
    per_class_mean = float(np.mean([d["ap"] for d in c["classes"].values()]))
    assert abs(c["micro"]["ap"] - per_class_mean) > 1e-9


def test_prevalence_is_horizontal_baseline():
    """④ prevalence = 正类占比（PR 的随机基线是水平线，不是对角线）。"""
    p, y = _toy(1)
    c = metrics.pr_curve(p, y, names=NAMES)
    assert c["micro"]["prevalence"] == pytest.approx(float(y.mean()), abs=1e-12)
    for n, d in c["classes"].items():
        i = NAMES.index(n)
        assert d["prevalence"] == pytest.approx(float(y[:, i].mean()), abs=1e-12)


def test_mean_curve_interpolates_on_common_grid():
    """⑥ 平均曲线 = 各种子在公共 recall 网格上插值后平均；support=0 的类返回 None。

    ⚠ 这条曲线的**合法前提**必须一起测出来：三种子 test 集不同，故它只能在 recall 轴上
    平均（不能在概率上平均）。这里用「单种子 ⇒ 平均曲线 = 该种子曲线重采样」来锁住口径。
    """
    p, y = _toy(5)
    c = metrics.pr_curve(p, y, names=NAMES)
    mc = P.mean_curve({0: c}, None)
    assert mc["n_seeds"] == 1
    assert mc["recall"] is P.GRID and len(mc["precision"]) == len(P.GRID)
    assert mc["recall"][0] == 0.0 and mc["recall"][-1] == 1.0
    assert np.all((mc["precision"] >= 0) & (mc["precision"] <= 1))
    # 单种子 ⇒ 平均值就是插值本身：恰好落在网格点上时须与原始曲线一致（同 recall 取最大 P）
    for gr, gp in zip(mc["recall"], mc["precision"]):
        hit = [(r, q) for r, q in zip(c["micro"]["recall"], c["micro"]["precision"])
               if abs(r - gr) < 1e-12]
        if hit:
            assert gp == pytest.approx(max(q for _r, q in hit), abs=1e-12)
    # support=0 的类没有曲线 ⇒ None（不返回全零数组冒充）
    assert P.mean_curve({0: c}, NAMES[6]) is None
    assert P.mean_curve({}, None) is None
    # 两种子 ⇒ 逐点等于两条插值曲线的算术平均
    c2 = metrics.pr_curve(*_toy(6), names=NAMES)
    a, b = P.mean_curve({0: c}, None), P.mean_curve({1: c2}, None)
    both = P.mean_curve({0: c, 1: c2}, None)
    assert np.allclose(both["precision"], (a["precision"] + b["precision"]) / 2, atol=1e-12)


def test_path_of_renders_both_placeholders():
    """⑤ 路径模板：`{seed}` 与 `{arm}` 同时存在于 base 模板 ⇒ 必须一次 format。"""
    for layout, canon_prefix, base_prefix in (("buggy", "runs/buggy_canon/seed2",
                                               "eval_results/baseline/mvdhg_buggy/seed2"),
                                              ("canon37", "runs/seed2",
                                               "eval_results/baseline/mvdhg/seed2")):
        c = P.path_of(layout, "canon", 2).relative_to(REPO).as_posix()
        b = P.path_of(layout, "mvdhg", 2).relative_to(REPO).as_posix()
        assert c == f"{canon_prefix}/test_probs.pt"
        assert b == f"{base_prefix}/test_probs.pt"
    assert P.path_of("buggy", "canon", 0).name == "test_probs.pt"
