#!/usr/bin/env python3
"""消融汇总脚本的**纯函数**回归锁（2026-09-18）。

本脚本是最终结果表的**唯一出处**（不手抄——本仓的消融计数已写错两次），
故它的三个易错点值得钉死：

  1. `dig()` 的分隔符：指标路径的键名**自身含点**（`fixed_0.5`），按 `.` 切会静默变 "—"；
  2. `paired_t()` 的配对语义：n=3 时 t 无定义/样本不足的分支必须返回 None 而不是崩；
  3. `ft_cost_of()` 的**语料隔离**路径：写错只会静默返回 None，
     于是 `cb_ft` 的成本被整段漏掉（这项是两段式的，漏掉微调段会低估一个数量级）。

运行：`pytest tests/test_collect_ablation.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_ablation_results as C  # noqa: E402


# ------------------------------------------------------------------ dig
def test_dig_splits_on_slash_not_dot():
    """🔴 回归锁：`fixed_0.5` 本身含点，只能用 `/` 作分隔符。"""
    payload = {"test": {"fixed_0.5": {"micro_f1": 0.4}}}
    assert C.dig(payload, "test/fixed_0.5/micro_f1") == 0.4
    # 用 `.` 当分隔符会切成 `fixed_0` + `5`，静默返回 None ⇒ 整列变 "—"
    assert C.dig(payload, "test.fixed_0.5.micro_f1") is None


def test_dig_missing_key_is_none():
    assert C.dig({"a": 1}, "a/b/c") is None
    assert C.dig({}, "x") is None


# ------------------------------------------------------------------ paired_t
def _arm(vals: dict) -> dict:
    return {"per_seed": {s: {"micro_0.5": v} for s, v in vals.items()}}


def test_paired_t_matches_hand_computation():
    """三对差全为 +0.1 ⇒ 均值 +0.1、std 0 ⇒ t 无定义（返回 None），别崩也别报 inf。"""
    canon = _arm({0: 0.4, 1: 0.5, 2: 0.6})
    arm = _arm({0: 0.5, 1: 0.6, 2: 0.7})
    out = C.paired_t(arm, canon, "micro_0.5")
    assert out["delta_mean"] == 0.1 and out["delta_std"] == 0.0
    assert out["t"] is None and out["n"] == 3


def test_paired_t_sign_and_value():
    """差为 +0.1/+0.2/+0.3 ⇒ 均值 +0.2、样本 std 0.1 ⇒ t = 0.2/(0.1/√3) ≈ 3.464。"""
    canon = _arm({0: 0.4, 1: 0.4, 2: 0.4})
    arm = _arm({0: 0.5, 1: 0.6, 2: 0.7})
    out = C.paired_t(arm, canon, "micro_0.5")
    assert out["delta_mean"] == 0.2
    assert abs(out["t"] - 3.464) < 0.01


def test_paired_t_uses_only_complete_pairs():
    """缺一个种子 ⇒ n=2（仍可算），缺到只剩 1 个 ⇒ None（不硬凑）。"""
    canon = _arm({0: 0.4, 1: 0.5, 2: 0.6})
    arm = _arm({0: 0.5, 1: 0.6})
    assert C.paired_t(arm, canon, "micro_0.5")["n"] == 2
    assert C.paired_t(_arm({0: 0.5}), canon, "micro_0.5") is None


def test_paired_t_none_when_metric_absent():
    canon = _arm({0: 0.4, 1: 0.5, 2: 0.6})
    assert C.paired_t(_arm({0: 0.5, 1: 0.6, 2: 0.7}), canon, "no_such_metric") is None


# ------------------------------------------------------------------ 两段式成本
def test_ft_cost_is_attached_to_canon_not_to_an_arm():
    """🔴 微调是**正典**的一部分（`decisions.md` §37），成本必须挂在**正典行**上。

    改前：`ft_cost_of(group, arm)` 只对 `cb_ft` 臂返回非 None——那时微调是**可选消融项**。
    改后：`cb_ft` 升为正典、`cb_frozen` 取代它的消融位，故签名收成 `ft_cost_of(group)`，
    由 `collect()` 挂到 `canon["ft_cost"]`。

    本测试钉两件事：① 签名确实是 1 个参数（防止回退成按臂查）；
    ② **真实产物**上正典确实带上了这一段——微调是小时级、GNN 是秒级，
    漏掉它会把总成本低估一个数量级。
    """
    import inspect
    assert len(inspect.signature(C.ft_cost_of).parameters) == 1, \
        "微调成本属于正典，不再按臂查询"
    for group in C.GROUPS:
        assert "ft_cost" in inspect.getsource(C.collect), "正典行必须挂上 ft_cost"
        ft = C.ft_cost_of(group)
        if ft is None:                        # 该语料尚未微调（如未跑）——不算失败
            continue
        assert ft["wall_s_total"] and ft["wall_s_total"] > 0
        assert all(v["corpus"] for v in ft["per_seed"].values()), \
            "微调 config 必须记 corpus（按语料隔离编码器，见 §37.5）"


# ------------------------------------------------------------------ 整臂丢弃必须记账
def test_incomplete_arm_is_recorded_not_silently_dropped():
    """🔴 回归锁：产物不全的臂**必须留在 `dropped_arms` 里**，不能静默消失。

    `arm_metrics` 缺任一种子就返回 `None`，原先调用方 `if m:` 直接跳过 ⇒
    该臂**从表里整臂消失且不报任何错**。触发场景很具体：run 被外部打断
    （留下 `best.pt` 却无 `results.json`，`decisions.md` §35.1）。
    少一臂的汇总表看起来完全正常，读者只会以为「这项没做」。
    """
    import inspect
    src = inspect.getsource(C.collect)
    assert "dropped.append" in src, "缺产物时必须记账，不能 continue 掉"
    assert "dropped_arms" in src, "账要进返回值，才能写进产物自身"


def test_render_markdown_discloses_dropped_arms():
    """🔴 汇总 md 会被单独传阅 ⇒ 「本表不完整」必须写在**产物自己身上**，
    只打印到 stdout 的话读表的人无从知道少了一臂。"""
    data = {"title": "T", "canon": None, "arms": {}, "dropped_arms": ["layers3"]}
    md = C.render_markdown("main", data)
    assert "本表不完整" in md and "layers3" in md


def test_render_markdown_silent_when_complete():
    """没有丢弃项时**不得**凭空加警告（假警报会让人忽略真警报）。"""
    data = {"title": "T", "canon": None, "arms": {}, "dropped_arms": [],
            "missing_arms": [], "n_expected": 0}
    assert "本表不完整" not in C.render_markdown("main", data)


def test_expected_arm_sets_are_explicit_and_aligned():
    """🔴 `expect` 必须**显式列出**应有臂，且 **① ② 逐臂对齐**（各 21 臂）。

    只比对"目录里有什么"的话，**目录都没建的臂会被当成不存在**——
    既不是丢弃也不是缺失，连警告都没有（历史上 ② 的 `cb_ft` 正是这样：
    表里 4 臂、设计上 5 臂，读表的人看不出少了哪一臂）。

    ⚠ 沿革：② 原先只跑**产物层 5 臂**（当时的设计是"前 16 项开关只在 ① 上跑"），
    2026-09-19 的 §37 重跑把开关类 16 项一并补上 ⇒ 两组语料**从此逐臂对齐**。
    本断言从"非对称"改为"对齐"，正是那次扩表在测试层的留痕。
    """
    assert len(C.GROUPS["main"]["expect"]) == 21, "① 应有 21 臂（16 开关 + 5 产物层）"
    assert len(C.GROUPS["aug"]["expect"]) == 21, "② 同样 21 臂（§37 起两组对齐）"
    assert set(C.GROUPS["aug"]["expect"]) == set(C.GROUPS["main"]["expect"]), \
        "①② 必须逐臂同名，否则三方并列表会对不齐"
    # 无重复（重复会让 `len(expect)` 冒充臂数）
    for g, cfg in C.GROUPS.items():
        assert len(set(cfg["expect"])) == len(cfg["expect"]), g
    # 臂名必须与驱动脚本的 ABLATIONS 完全一致（驱动加臂而汇总没加 = 静默漏报一臂）
    import run_ablation as RA
    assert set(C.GROUPS["main"]["expect"]) == {n for n, _o, _d in RA.ABLATIONS}


def test_render_markdown_reports_expected_vs_actual_count():
    """「应有 N 臂、实有 M 臂」是读者唯一能看出缺口的数字，必须写进产物。"""
    data = {"title": "T", "canon": None, "arms": {"a": {}}, "dropped_arms": [],
            "missing_arms": ["cb_ft"], "n_expected": 5}
    md = C.render_markdown("aug", data)
    assert "应有 5 臂，实有 1 臂" in md and "cb_ft" in md


def test_ft_root_is_corpus_scoped():
    """🔴 编码器根目录**必须带语料维度**（`decisions.md` §35.2）。

    写错/写成共用的 `runs/codebert_ft` 时 `ft_cost_of` 只会静默返回 None，
    `cb_ft` 的成本被整段漏掉——而这一项是两段式的，只报 GNN 段会把小时级的微调
    说成秒级，给出"这项很便宜"的错误印象。
    """
    assert C.FT_ROOT["main"] == "runs/codebert_ft/alldata"
    assert C.FT_ROOT["aug"] == "runs/codebert_ft/augmentation"
    assert C.FT_ROOT["main"] != C.FT_ROOT["aug"]
