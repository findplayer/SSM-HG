#!/usr/bin/env python3
"""消融 n=9 网格的**纯函数**回归锁（2026-09-21）。

为什么不测"跑得对不对"而测这些：n=9 的全部价值在于**配对**（同 `(ts, ss)` 才配得上对）。
配对错了不会报错 —— 只会安静地算出一个**看着合理但无意义**的 t。故把三处易错点钉死：

  1. `plan()` 的**配对与复用判定**：每个臂必须恰好 9 对；对角复用旧跑、非对角新开目录；
     ① 的基线（`cbft_study`）9 对**全复用**、② 的基线对角复用/非对角新跑。
  2. `t_crit(n)` 的 **n 依赖**：跑批中途某些臂只有 3 对，用 n=9 的门槛去标注它们会**过度标注**
     （df 越小临界值越大）。`_star()` 必须按行取该行自己的 n。
  3. 三组扩充臂的**默认关闭**与**归属**：剂量臂/架构族/参数匹配对照默认都不进；
     架构族与 `*_pm` 必须落 `arch_root`（与消融臂**分开存**，否则两张表会被混读）。

运行：`pytest tests/test_ablation_n9.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import collect_ablation_n9 as C     # noqa: E402
import run_ablation_n9 as R9        # noqa: E402


# ------------------------------------------------------------------ 臂集合
def test_default_items_are_exactly_the_21_canon_arms():
    """不带任何 `--with-*-arms` 时，臂集合必须**逐字等于** `run_ablation.ABLATIONS`。

    这条锁住的是"扩充臂不许偷偷进正典消融表"：21 这个数被多处文档与
    `tests/test_collect_ablation.py` 硬引用，静默 +3 会让那些计数全部失真。
    """
    got = [it[0] for it in R9.items_for(False)]
    assert got == [it[0] for it in R9.RA.ABLATIONS]
    assert len(got) == 21


def test_expansion_sets_are_opt_in_and_disjoint():
    """三组扩充**默认都不进**，且**新增的那部分**两两不重叠。

    ⚠ 比的是**新增部分**（`dose - base` 等），不是三个返回集本身 ——
    `items_for` 返回的是**累积集**（都含 21 个基础臂），直接比会把基础臂当成"重叠"。
    """
    base = {it[0] for it in R9.items_for(False)}
    dose = {it[0] for it in R9.items_for(True)}
    arch = {it[0] for it in R9.items_for(False, True)}
    pm = {it[0] for it in R9.items_for(False, False, True)}
    e_dose, e_arch, e_pm = dose - base, arch - base, pm - base
    assert e_dose == {it[0] for it in R9.RA.DOSE_ARMS}
    assert e_arch == {it[0] for it in R9.ARCH_ARMS}
    assert e_pm == {it[0] for it in R9.PM_ARMS}
    # 三组**新增项**互不重叠（否则同一条目会被跑两次、写两个目录）
    assert not (e_dose & e_arch) and not (e_dose & e_pm) and not (e_arch & e_pm)


def test_arch_and_pm_are_classified():
    assert all(R9.is_arch(it[0]) for it in R9.ARCH_ARMS)
    assert all(R9.is_pm(it[0]) for it in R9.PM_ARMS)
    assert not any(R9.is_arch(it[0]) or R9.is_pm(it[0]) for it in R9.RA.ABLATIONS)


def test_pm_arms_are_declared_two_key():
    """`*_pm` 是**有意的双键**对照 ⇒ 每项必须**恰好声明 2 个键**。

    少于 2 就说明"参数量对齐"没做（对齐必然要动第二个旋钮）；多于 2 则变量太多、
    读者无法归因。这条锁住的是 `PM_ARMS` 表上那段注释与代码不漂移。
    """
    for item, override, _desc in R9.PM_ARMS:
        assert len(override) == 2, f"{item} 声明了 {len(override)} 个键，应为 2"


# ------------------------------------------------------------------ 配对与复用
def _plan(gk):
    return R9.plan(gk, R9.items_for(False), R9.PAIRS)


def test_plan_has_nine_pairs_per_arm_plus_baseline():
    ents = _plan("main")
    n_arm = len(R9.RA.ABLATIONS)
    assert len(ents) == (n_arm + 1) * 9
    # 每个 (臂, 配对) 恰好一次
    keys = [(e["item"], e["t"], e["s"]) for e in ents]
    assert len(keys) == len(set(keys))
    assert {(e["t"], e["s"]) for e in ents} == set(R9.PAIRS)


def test_diagonal_is_reused_and_offdiagonal_is_new():
    """对角（`ts == ss`）复用旧跑、非对角新开目录 —— 这是"只补 6 对"的全部依据。"""
    for e in _plan("main"):
        if e["item"] == R9.BASELINE_ITEM:
            continue
        if e["t"] == e["s"]:
            # 对角：指向 runs/ablation{,_aug}/<item>/seed{S}
            assert e["reuse"] is True, f"{e['item']} {e['t']}:{e['s']} 对角却要新跑"
            assert e["run_dir"].parent.name == e["item"]
        else:
            assert e["reuse"] is False, f"{e['item']} {e['t']}:{e['s']} 非对角却判为复用"
            assert e["run_dir"].parent.name == f"ts{e['t']}_ss{e['s']}"


def test_main_baseline_is_fully_reused_from_cbft_study():
    """① 的 9 对基线来自 §36 的 `cbft_study`，**零新跑**（论文正典即由它的对角提升而来）。"""
    base = [e for e in _plan("main") if e["item"] == R9.BASELINE_ITEM]
    assert len(base) == 9
    assert all(e["reuse"] for e in base)
    assert all(e["run_dir"].parent.parent.name == "cbft_study" for e in base)


def test_aug_baseline_reuses_diagonal_only():
    """② 没有现成的 9 对基线 ⇒ 对角复用正典、非对角必须新跑（且落在本组自己的根下）。"""
    base = [e for e in _plan("aug") if e["item"] == R9.BASELINE_ITEM]
    assert len(base) == 9
    for e in base:
        if e["t"] == e["s"]:
            assert e["reuse"] and e["run_dir"].parent.name == "augmentation"
        else:
            assert not e["reuse"]
            assert "ablation_n9_aug" in str(e["run_dir"])


def test_arch_arms_go_to_arch_root_not_ablation_root():
    """架构族与 `*_pm` 必须与消融臂**分开存**（否则两张口径不同的表会被混读）。"""
    items = R9.items_for(False, True, True)
    for e in R9.plan("main", items, [(0, 1)]):
        if e["item"] == R9.BASELINE_ITEM:
            continue
        s = str(e["run_dir"])
        if R9.is_arch(e["item"]) or R9.is_pm(e["item"]):
            assert "/arch_n9/" in s, f"{e['item']} 落到了 {s}"
        else:
            assert "/ablation_n9/" in s, f"{e['item']} 落到了 {s}"


# ------------------------------------------------------------------ 显著性标注
def test_t_crit_is_n_dependent_and_monotone():
    """n 越小临界值越大 —— 用 n=9 的门槛标注 n=3 的行会**过度标注**。"""
    vals = [C.t_crit(n) for n in range(3, 11)]
    assert all(a > b for a, b in zip(vals, vals[1:])), vals
    assert C.t_crit(9) == C.T_CRIT_9
    assert C.t_crit(3) == C.T_CRIT_3


def test_star_respects_row_n():
    """同一个 |t| = 3.0：在 n=9 下该标星（3.0 > 2.306），在 n=3 下**不该**（3.0 < 4.303）。"""
    assert C._star(3.0, 9) != ""
    assert C._star(3.0, 3) == ""
    assert C._star(-3.0, 9) != ""        # 双向
    assert C._star(None, 9) == ""
    assert C._star(1.0, 9) == ""


def test_star_rejects_the_old_hardcoded_threshold():
    """回归锁：`|t| = 3.5` 在 n=3 下**曾经**会被旧的写死门槛（2.306）误标为显著。"""
    assert C._star(3.5, 3) == ""
    assert C._star(3.5, 9) != ""


# ------------------------------------------------------------------ graph_dir 的逐种子模板化
def test_canonical_args_templates_both_encoder_tree_naming_forms(tmp_path):
    """🔴 回归锁（2026-09-21 发现并修）：`canonical_args` 必须同时认 `ss{S}` 与 `cb_ft_ss{S}`。

    原正则 `(.+)/ss\\d+` 对 `products/alldata/graphs_ft_buggy/cb_ft_ss0` **不匹配**
    （该段是 `cb_ft_ss0`，不含字面 `/ss`）⇒ `graph_dir` 原样返回 ⇒ 逐种子展开后
    **seed1/seed2 静默拿到 ss0 的编码器**，与划分种子错配。这正是 AGENTS.md 点名的
    「本仓第三次全量作废的根因」同一形态，且**不报错**，故必须有机检。
    """
    import json

    def canon(graph_dir: str) -> str:
        cfg = tmp_path / "config.json"
        cfg.write_text(json.dumps({"args": {"graph_dir": graph_dir}}), encoding="utf-8")
        return R9.RA.canonical_args(cfg)["graph_dir"]

    # §37 正典形态 → 模板化
    assert canon("/x/graphs_ft/ss0") == "/x/graphs_ft/ss{seed}"
    # 任务2 的 buggy 树形态（`cb_ft_` 前缀）→ **同样**必须模板化，且**保留前缀**
    assert canon("/x/graphs_ft_buggy/cb_ft_ss0") == "/x/graphs_ft_buggy/cb_ft_ss{seed}"
    assert canon("/x/graphs_ft_buggy/cb_ft_ss2") == "/x/graphs_ft_buggy/cb_ft_ss{seed}"
    # 冻结版正典（无 `ss<数字>` 后缀）→ 原样返回，行为与引入模板前逐字一致
    assert canon("/x/graphs") == "/x/graphs"
    # 展开后逐种子必须不同（否则就是本测试要防的那个错）
    tmpl = canon("/x/graphs_ft_buggy/cb_ft_ss0")
    assert {tmpl.format(seed=s) for s in (0, 1, 2)} == {
        "/x/graphs_ft_buggy/cb_ft_ss0", "/x/graphs_ft_buggy/cb_ft_ss1",
        "/x/graphs_ft_buggy/cb_ft_ss2"}
