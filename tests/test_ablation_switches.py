#!/usr/bin/env python3
"""消融开关**接线验证**（2026-09-16）：证明每个开关真的接到了数据/模型上。

**为什么必须单独验证**：消融实验的全部价值在于"只有一个变量在动"。若某个开关其实是空操作
（例如 `--drop-edges` 没真的删边、`--ablate-sv` 没真正置零），跑出来的"消融结论"就是假的，
而且从指标数字上**几乎发现不了**。故在开跑前逐个验证**作用机制**，而不是只验证"命令能跑通"。

覆盖大纲 `改II` 5.4.1 必要消融 11 项 + 5.4.2 可选消融 6 项：

| 消融项 | 本文件如何验证 | 状态 |
| --- | --- | --- |
| 去 DFG_DEP / CFG_FLOW / AST_PARENT / CALLBACK_RISK | `load_graph(Ablation)` 后目标边类型消失、其余不变 | ✅ |
| CALLBACK_RISK 上限 4 vs 不限 | 需重跑 M2（`--callback-limit 0`）；本文件只做边数实测记录 | ⚠ 见 `experiments/ablation_plan.md` |
| 去函数级 / 去节点级 CodeBERT | `cb_channels` 单通道下扰动被剔除通道 → 输出不变 | ✅ |
| meanpool 替换 a_v 加权 | `use_meanpool=True` 改变 z 且不增参数 | ✅ |
| 关闭 L_var | 由既有 `runs/*/log.txt` 验证 `loss_total = loss_cls + λ·loss_var`（零新计算） | ✅ |
| 关闭先验 Dropout | `--prior-dropout 0` 不置零；`0.2` 置零≈20%；与 `--ablate-sv` 不同 | ✅ |
| 结构特征分组 (a)(b)(c) | `feat_groups` 下扰动非保留组列 → 输出不变 | ✅ |
| 结构 dropout | 与先验 dropout **共用** `sample_dropout_masks`，同为丢弃率 | ✅ |
| num_bases / 隐藏维 | 构造成功且确实改变参数量/维度 | ✅ |
| DropEdge | 已在 `test_train_utils.py::test_collate_dropedge_*` 覆盖 | ✅ |
| RGCN 层数 L=1/2/3 | **未实现**（`SSMHG` 硬编码两层） | ❌ 需开发 |
| 微调 CodeBERT | **未实现**（M3 冻结缓存，无微调路径） | ❌ 需开发 |

运行：`pytest tests/test_ablation_switches.py -q`
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from dataset import Ablation, load_graph  # noqa: E402
from model import (AblationConfig, NodeFuser, SSMHG,  # noqa: E402
                   sample_dropout_masks)

# 实物图：9 节点，且五类边齐全（CFG_FLOW 7 / AST_PARENT 1 / AST_PARENT_SAME 4 /
# DFG_DEP 15 / CALLBACK_RISK 1）——边消融测试需要每类都有边，否则断言是空转的。
GRAPH = "nasd_simple_dao__simple_dao"
GDIR = str(REPO / "products/alldata/graphs")
# 物理关系编号（dataset.RELATION_NAMES）：0=CFG_FLOW 1=AST_PARENT 2=AST_PARENT_SAME
# 3=DFG_DEP 4=CALLBACK_RISK
CFG_FLOW, AST_PARENT, AST_PARENT_SAME, DFG_DEP, CALLBACK_RISK = 0, 1, 2, 3, 4


def _sample(ab: Ablation | None = None):
    return load_graph(GRAPH, graph_dir=GDIR, ab=ab or Ablation())


def _types(sample) -> set[int]:
    return {int(t) for t in sample.edge_type.tolist()}


def _perturb_zero(ch: dict, key: str) -> dict:
    """返回通道副本：把某个通道整幅置零（用于构造 ablate_sv 的等价参照）。"""
    out = {k: (v.clone() if torch.is_tensor(v) else v) for k, v in ch.items()}
    out[key] = torch.zeros_like(out[key])
    return out


def _fuser(ablate: AblationConfig) -> NodeFuser:
    """同一签名 + 固定 FUSER_INIT_SEED ⇒ 两次构造权重逐位相同，可直接比输出。"""
    s = _sample()
    return NodeFuser(int(s.meta["D_struct"]), dict(s.meta["struct_layout"]), ablate=ablate)


def _perturb(ch: dict, key: str, col: int | None = None) -> dict:
    """返回通道副本：把某个通道（或结构特征的某一列）整体加一个大扰动。"""
    out = {k: (v.clone() if torch.is_tensor(v) else v) for k, v in ch.items()}
    t = out[key]
    if col is None:
        out[key] = t + 5.0
    else:
        t = t.clone()
        t[:, col] = t[:, col] + 5.0
        out[key] = t
    return out


# ============================================================ 边消融（5.4.1 前 4 项）
def test_baseline_graph_has_all_five_edge_types():
    """前置条件：测试图必须五类边齐全，否则下面的"删掉某类"断言可能空转。"""
    assert _types(_sample()) == {CFG_FLOW, AST_PARENT, AST_PARENT_SAME, DFG_DEP, CALLBACK_RISK}


@pytest.mark.parametrize("drop,expect_gone", [
    ({DFG_DEP}, {DFG_DEP}),            # 去 DFG_DEP
    ({CFG_FLOW}, {CFG_FLOW}),          # 去 CFG_FLOW
    ({CALLBACK_RISK}, {CALLBACK_RISK}),  # 去 CALLBACK_RISK
    ({}, set()),                       # 空消融 = 不改动
])
def test_edge_ablation_removes_exactly_the_target_type(drop, expect_gone):
    have = _types(_sample())
    now = _types(_sample(Ablation(drop_edges=set(drop))))
    assert have - now == expect_gone, f"drop={drop} 实际删掉 {have - now}"


def test_drop_ast_removes_relation_1_and_2_only():
    """`--drop-ast` 等价于删 relation 1+2（AST_PARENT + AST_PARENT_SAME），不动其余。"""
    have = _types(_sample())
    now = _types(_sample(Ablation(drop_ast=True)))
    assert have - now == {AST_PARENT, AST_PARENT_SAME}


def test_drop_edges_rejects_out_of_whitelist():
    with pytest.raises(ValueError):
        _sample(Ablation(drop_edges={99}))


# ============================================================ 特征消融（配置层）
def test_ablate_sv_zeroes_the_sv_channel():
    """`--ablate-sv`：扰动 s_v 不得再影响 h_v^(0)（否则该消融是空操作）。"""
    ch = _sample().channels
    off, on = _fuser(AblationConfig()), _fuser(AblationConfig(ablate_sv=True))
    with torch.no_grad():
        assert not torch.equal(off(ch), off(_perturb(ch, "sv"))), "基线应受 s_v 影响"
        assert torch.equal(on(ch), on(_perturb(ch, "sv"))), "ablate_sv 后 s_v 必须无效"


@pytest.mark.parametrize("keep_key,drop_key", [
    ("cb_node", "cb_func"),      # 去函数级 CodeBERT
    ("cb_func", "cb_node"),      # 去节点级局部 CodeBERT
])
def test_cb_channels_single_channel_ignores_the_other(keep_key, drop_key):
    ch = _sample().channels
    f = _fuser(AblationConfig(cb_channels=(keep_key,)))
    with torch.no_grad():
        assert torch.equal(f(ch), f(_perturb(ch, drop_key))), \
            f"{drop_key} 应已被剔除，扰动它不该改变输出"
        assert not torch.equal(f(ch), f(_perturb(ch, keep_key))), \
            f"{keep_key} 应仍参与，扰动它必须改变输出"


def test_feat_groups_base_zeroes_non_base_struct_columns():
    """`--feat-groups base`：扰动非 base 组（列 11 起 = sem/cb/pos）不得影响输出。

    掩码布局见 `model.struct_group_keep_mask`：0–3 可见性 + 4–10 bool 前段 = base；
    11 起为 sem/cb/pos 组。
    """
    ch = _sample().channels
    all_f, base_f = _fuser(AblationConfig(feat_groups="all")), _fuser(AblationConfig(feat_groups="base"))
    with torch.no_grad():
        assert not torch.equal(all_f(ch), all_f(_perturb(ch, "struct", 11))), \
            "feat_groups=all 时列 11 应有效"
        assert torch.equal(base_f(ch), base_f(_perturb(ch, "struct", 11))), \
            "feat_groups=base 时列 11 必须被置零"
        # base 组内部（列 0）两设置都应受影响
        assert not torch.equal(base_f(ch), base_f(_perturb(ch, "struct", 0)))


def test_feat_groups_keeps_column_width_unchanged():
    """列宽不变（R2）：分组消融只置零、不裁列。"""
    f_all, f_base = _fuser(AblationConfig(feat_groups="all")), _fuser(AblationConfig(feat_groups="base"))
    assert f_all.in_dim == f_base.in_dim


# ============================================================ 模型消融
def _mini_batch():
    s = _sample()
    n = s.channels["sv"].shape[0]
    return s, torch.zeros(n, dtype=torch.long)


def test_meanpool_changes_readout_without_adding_params():
    """meanpool 替换 a_v 加权：z 改变、参数量不变（否则不是"替换"而是"改结构"）。"""
    s, batch = _mini_batch()
    x = torch.randn(s.channels["sv"].shape[0], 16)
    torch.manual_seed(0)
    m_att = SSMHG(in_dim=16, hid=16, use_meanpool=False)
    torch.manual_seed(0)
    m_mean = SSMHG(in_dim=16, hid=16, use_meanpool=True)
    assert m_mean.use_meanpool is True
    with torch.no_grad():
        z_att = m_att(x, s.edge_index, s.edge_type, batch)[0]
        z_mean = m_mean(x, s.edge_index, s.edge_type, batch)[0]
    assert z_att.shape == z_mean.shape
    assert not torch.allclose(z_att, z_mean), "meanpool 必须改变读数方式"
    n_att = sum(p.numel() for p in m_att.parameters())
    n_mean = sum(p.numel() for p in m_mean.parameters())
    assert n_att == n_mean, "meanpool 不应增删参数"


def test_num_bases_changes_parameter_count():
    s, _ = _mini_batch()
    torch.manual_seed(0)
    m5 = SSMHG(in_dim=16, hid=16, num_bases=5)
    torch.manual_seed(0)
    m1 = SSMHG(in_dim=16, hid=16, num_bases=1)
    assert sum(p.numel() for p in m1.parameters()) < sum(p.numel() for p in m5.parameters())


def test_hidden_dim_flag_is_wired():
    torch.manual_seed(0)
    assert SSMHG(in_dim=16, hid=256).hid == 256


# ============================================================ 关闭 L_var（零新计算）
@pytest.mark.parametrize("run_dir", ["runs/seed0", "runs/neardup/seed0", "runs/augmentation/seed0"])
def test_lambda_var_composition_matches_logged_losses(run_dir):
    """由既有 runs 日志验证 loss 复合式：`loss_total = loss_cls + λ·loss_var`。

    这等价于"λ=0 时方差项消失"，且**不产生任何新计算**（读已落盘的日志）。
    """
    d = REPO / run_dir
    cfg_p, log_p = d / "config.json", d / "log.txt"
    if not cfg_p.exists() or not log_p.exists():
        pytest.skip(f"{run_dir} 无产物（该臂未跑）")
    lam = float(json.loads(cfg_p.read_text(encoding="utf-8"))["args"]["lambda_var"])
    rows = [json.loads(x) for x in log_p.read_text(encoding="utf-8").splitlines() if x.strip()]
    assert rows, f"{run_dir}/log.txt 为空"
    worst = max(abs(r["loss_total"] - (r["loss_cls"] + lam * r["loss_var"])) for r in rows)
    assert worst < 1e-5, f"{run_dir}: |loss_total-(loss_cls+λ·loss_var)| 最大 {worst:.2e}"


# ============================================================ 先验/结构 dropout（丢弃率语义）
# 2026-09-16 修正：`p` 由「保留率」改为「丢弃率」（与大纲 4.1.4 / 手册 §8.6 的散文一致）。
# 修正前 p=0.2 实际置零 80% 的图、p=0 每图都置零；该口径下全部结果已作废并归档
# `runs/prior_dropout80/`，见 `experiments/decisions.md` §26。
def _drop_rate(p: float, n: int = 20000) -> float:
    """采样掩码（乘性系数：1=保留、0=整通道置零）→ 实际**置零**比例。"""
    m, s = sample_dropout_masks(n, prior_p=p, struct_p=p,
                                generator=torch.Generator().manual_seed(0))
    return float((m == 0).float().mean())   # 两路独立采样，不要求逐位相同


def test_prior_dropout_default_zeroes_about_20_percent():
    """默认 `--prior-dropout 0.2` ⇒ 约 **20%** 的图被置零（丢弃率语义）。"""
    assert _drop_rate(0.2) == pytest.approx(0.2, abs=0.02)


def test_prior_dropout_zero_disables_dropout():
    """★ `--prior-dropout 0` ⇒ **关闭**（掩码恒 1，一个图都不置零）。"""
    m, _ = sample_dropout_masks(512, prior_p=0.0, struct_p=0.0,
                                generator=torch.Generator().manual_seed(0))
    assert torch.all(m == 1), "丢弃率 0 必须表示「不丢弃」"


def test_prior_dropout_one_zeroes_every_graph():
    """`--prior-dropout 1` ⇒ 每图都置零（"全丢"）。**不应用它表示"关闭"**——那是 0 的语义。"""
    assert _drop_rate(1.0) == 1.0


def test_struct_dropout_shares_the_same_semantics():
    """结构 dropout 与先验 dropout **共用 `sample_dropout_masks`**，故必须同为丢弃率。

    手册 §8.6 对结构 dropout 的记载同样是「默认 0.2」的丢弃率，故此处一并钉住。
    """
    for p in (0.0, 0.2, 1.0):
        _, s = sample_dropout_masks(20000, prior_p=0.5, struct_p=p,
                                    generator=torch.Generator().manual_seed(0))
        assert float((s == 0).float().mean()) == pytest.approx(p, abs=0.02), \
            f"struct_p={p} 的置零比例应为 {p}"


def test_eval_mode_does_not_zero_sv():
    """eval/推理**不置零**：调用方不传掩码（`prior_mask=None`），s_v 原值直通。

    与训练期的区别在于**调用方是否传掩码**（见 `train.py`：验证分支不调用
    `sample_dropout_masks`），故此处验证"不传掩码 ⇒ s_v 有效"。
    """
    ch = _sample().channels
    f = _fuser(AblationConfig())                      # ablate_sv=False
    with torch.no_grad():
        assert not torch.equal(f(ch), f(_perturb(ch, "sv"))), \
            "不传掩码时 s_v 必须有效（eval 不置零）"


def test_ablate_sv_is_not_the_same_as_prior_dropout_zero():
    """★ `--ablate-sv`（确定性全零）与 `--prior-dropout 0`（关闭随机正则）**不是一回事**。

    - `ablate_sv=True`：s_v **恒零**，等价于把 s_v 通道预先置零；
    - `prior_dropout=0`：掩码恒 1 ⇒ s_v **原值参与**（与完全不传掩码等价）。
    两者输出必须不同，且各自与对应的参照一致。
    """
    ch = _sample().channels
    f_ablate = _fuser(AblationConfig(ablate_sv=True))
    f_keep = _fuser(AblationConfig())                 # prior_dropout=0 等价于此（掩码恒 1）
    ones = torch.ones(1)
    with torch.no_grad():
        out_ablate = f_ablate(ch)
        out_keep = f_keep(ch)
        # ablate_sv ≡ 把 sv 预先置零后再走不置零路径
        ref_ablate = f_keep(_perturb_zero(ch, "sv"))
        # prior_dropout=0 ≡ 掩码恒 1（此路径与不传掩码逐位相同）
        assert torch.equal(out_keep, f_keep(ch, prior_mask=ones))
    assert not torch.allclose(out_ablate, out_keep), "两者必须不同（否则消融项重复）"
    assert torch.equal(out_ablate, ref_ablate), "ablate_sv 必须等价于 sv 预先置零"


# ============================================================ 未实现项（显式记录，不进 CI 假绿）
@pytest.mark.skip(reason="RGCN 层数 L=1/2/3（5.4.2）未实现：model.SSMHG 硬编码 conv1/conv2 两层，"
                         "需新增 --layers 开关与对应前向；见 experiments/ablation_plan.md")
def test_rgcn_num_layers_is_not_implemented():
    pass


@pytest.mark.skip(reason="微调 CodeBERT vs 冻结（5.4.2）未实现：M3 只产出冻结嵌入缓存，无微调路径；"
                         "见 experiments/ablation_plan.md")
def test_codebert_finetune_is_not_implemented():
    pass
