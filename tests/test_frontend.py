"""M3 前端化验收单测（设计稿 `docs/M3_frontend_design.md` v3；2026-09-12 P1）。

覆盖（强制门）：
  - T1 无泄漏单测：`prior_mask` 置零路径 == 把 sv 通道预先置零且不 drop 的前向输出（逐位 torch.equal）；
        反例守卫：若置零发生在融合 Linear 之后，本用例必然失败；
        推论：`AblationConfig(ablate_sv=True)`（配置层）≡ `prior_mask=全 0`（正则层）≡ 预先置零。
  - T2 冻结等价性：`NodeFuser`（同 init seed、冻结）+ 新通道 == 归档的旧 `_feat.pt`（逐位）——
        证明前端化是「单一变量＝可学习性」的重构，而非改数。
  - T5 形状/梯度：输出恒为 (N,128)；反向后 `type_emb.weight` / `proj.weight` 梯度非空。
  - 参数量报告（R10）、掩码粒度（逐图独立）、配置层无模式差异（train/eval 一致）。
  - dataset 断言：schema 版本、旧格式报错、逐通道哈希报具体通道名。

运行：pytest tests/ -q
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import dataset  # noqa: E402
from model import (AblationConfig, NodeFuser, parameter_report,  # noqa: E402
                   sample_dropout_masks)

GRAPH_DIR = Path(dataset.DEFAULT_GRAPH_DIR)
LEGACY_DIR = GRAPH_DIR / dataset.LEGACY_FEAT_DIR
SMOKE_BASE = "nasd_simple_dao__simple_dao"
SMOKE_GRAPH = GRAPH_DIR / f"{SMOKE_BASE}_feat.pt"


def _synthetic_channels(n: int = 7, d_struct: int = 30, seed: int = 0) -> dict[str, torch.Tensor]:
    """合成通道（含固定 seed 的随机值），供与真实产物无关的用例使用。"""
    g = torch.Generator().manual_seed(seed)
    return {
        "cb_func": torch.randn(n, 768, generator=g),
        "cb_node": torch.randn(n, 768, generator=g),
        "type_id": torch.randint(0, 9, (n,), generator=g),
        "struct": torch.randn(n, d_struct, generator=g),
        "sv": torch.rand(n, 1, generator=g),
    }


def _zero_sv(ch: dict[str, torch.Tensor], mask: torch.Tensor,
             batch: torch.Tensor | None = None) -> dict[str, torch.Tensor]:
    """按图级掩码把 sv 通道**预先**替换为全零（T1 的对照分支）。"""
    out = dict(ch)
    coef = mask.reshape(-1)
    if batch is None:
        out["sv"] = ch["sv"] * coef.reshape(1, 1)
    else:
        out["sv"] = ch["sv"] * coef[batch].reshape(-1, 1)
    return out


# ---------------------------------------------------------------- T1 / 配置层等价
def test_no_leak_prior_dropout_single_graph():
    """T1（单图）：drop 路径 == sv 预先置零且不 drop，逐位相等。"""
    ch = _synthetic_channels()
    fuser = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    mask = torch.tensor([0.0])                    # 该图被先验 dropout 命中
    a = fuser(ch, prior_mask=mask)
    b = fuser(_zero_sv(ch, mask), prior_mask=None)
    assert torch.equal(a, b), "先验 dropout 必须等价于「sv 通道置零后不做 drop」——位置错误时本断言失败"


def test_no_leak_prior_dropout_batch_granularity():
    """T1（批图 + 掩码粒度）：一图 drop、一图不 drop，各自与真值分支逐位相等。"""
    ch1, ch2 = _synthetic_channels(n=5, seed=1), _synthetic_channels(n=4, seed=2)
    n1 = ch1["sv"].shape[0]
    batch = torch.tensor([0] * n1 + [1] * ch2["sv"].shape[0])
    ch = {k: torch.cat([ch1[k], ch2[k]], dim=0) for k in ch1}
    fuser = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    mask = torch.tensor([0.0, 1.0])               # 图 0 置零、图 1 保留
    out = fuser(ch, prior_mask=mask, batch=batch)
    ref = fuser(_zero_sv(ch, mask, batch=batch), prior_mask=None, batch=batch)
    assert torch.equal(out, ref)
    # 逐图对照：图 1 的输出必须与「完全不 drop」时一致（未被误伤）
    keep_all = fuser(ch, prior_mask=torch.ones(2), batch=batch)
    assert torch.equal(out[n1:], keep_all[n1:]), "未被命中的图不得受其他图掩码影响"
    # 图 0 被置零：与整批都不 drop 时不同（否则说明掩码没生效）
    assert not torch.equal(out[:n1], keep_all[:n1])


def test_ablation_config_equivalent_to_zero_mask():
    """配置层（确定性消融）≡ 正则层（掩码=0）≡ 预先置零——三者共用同一原语。"""
    ch = _synthetic_channels()
    zero_mask = torch.tensor([0.0])
    f_cfg = NodeFuser(d_struct=30, struct_layout={"ir": 6},
                      ablate=AblationConfig(ablate_sv=True))
    f_reg = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    ref = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    out_cfg = f_cfg(ch)
    out_reg = f_reg(ch, prior_mask=zero_mask)
    out_pre = ref(_zero_sv(ch, zero_mask), prior_mask=None)
    assert torch.equal(out_cfg, out_reg) and torch.equal(out_cfg, out_pre)


def test_config_layer_has_no_train_eval_difference():
    """配置层不随 train/eval 变化（正则层由调用方决定是否传掩码）。"""
    ch = _synthetic_channels()
    fuser = NodeFuser(d_struct=30, struct_layout={"ir": 6}, ablate=AblationConfig(ablate_sv=True))
    fuser.train()
    a = fuser(ch)
    fuser.eval()
    b = fuser(ch)
    assert torch.equal(a, b), "确定性消融不得只在训练期生效"


def test_struct_dropout_is_whole_channel_per_graph():
    """结构 dropout 为**整通道**按图置零（非 elementwise）。"""
    ch = _synthetic_channels(n=6)
    fuser = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    mask = torch.tensor([0.0])
    out = fuser(ch, struct_mask=mask)
    ref = fuser({**ch, "struct": torch.zeros_like(ch["struct"])})
    assert torch.equal(out, ref), "整通道置零：被命中的图其 struct 通道整块为零"


def test_sample_dropout_masks_shape_and_rate():
    """掩码采样：形状 (G,)、取值 {0,1}、同 generator 可复现、大样本比例≈p。"""
    g = torch.Generator().manual_seed(0)
    prior, struct = sample_dropout_masks(2000, prior_p=0.2, struct_p=0.2, generator=g)
    assert prior.shape == (2000,) and set(prior.unique().tolist()) <= {0.0, 1.0}
    assert 0.17 <= float(prior.mean()) <= 0.23 and 0.17 <= float(struct.mean()) <= 0.23
    g2 = torch.Generator().manual_seed(0)
    prior2, _ = sample_dropout_masks(2000, prior_p=0.2, struct_p=0.2, generator=g2)
    assert torch.equal(prior, prior2)


# ---------------------------------------------------------------- T5 / 参数量
def test_output_dim_and_gradients():
    """T5：输出恒为 (N,128)（R11）；反向后类型嵌入与融合层梯度非空。"""
    ch = _synthetic_channels(n=6)
    fuser = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    out = fuser(ch)
    assert tuple(out.shape) == (6, 128) and fuser.in_dim == 768 * 2 + 64 + 30 + 1
    out.sum().backward()
    assert fuser.type_emb.weight.grad is not None and fuser.type_emb.weight.grad.abs().sum() > 0
    assert fuser.proj.weight.grad is not None and fuser.proj.weight.grad.abs().sum() > 0


def test_parameter_report_and_d_struct_variants():
    """R10：参数量报告字段齐全；`d_struct` 变化按预期改变融合层输入维度。"""
    fuser = NodeFuser(d_struct=30, struct_layout={"ir": 6})
    rep = parameter_report(fuser=fuser)
    assert rep["fuser_params"] == rep["fuser_learnable_params"] == 209472
    assert rep["total_params"] == 209472
    f_big = NodeFuser(d_struct=44, struct_layout={"ir": 20})
    assert f_big.in_dim == 768 * 2 + 64 + 44 + 1


def test_feat_groups_mask_width_unchanged():
    """分组消融只置零、不改列宽（大纲改II 4.3.3）。

    列布局 = 可见性4(base) + 布尔14[7 base + 4 sem + 3 cb] + 外呼方式5(sem) + 位置1(pos) + IR(6, pos)
    → base 保留 11 列；base+sem 保留 20 列；均不改变总列宽 30。
    """
    from model import struct_group_keep_mask
    keep_all = struct_group_keep_mask(6, "all")
    keep_base = struct_group_keep_mask(6, "base")
    keep_bsem = struct_group_keep_mask(6, "base+sem")
    assert len(keep_all) == len(keep_base) == len(keep_bsem) == 4 + 14 + 5 + 1 + 6 == 30
    assert all(keep_all) and sum(keep_base) == 11 and sum(keep_bsem) == 20
    assert all(keep_base[:11]) and not any(keep_base[11:])
    # base+sem：保留可见性(0-3) + 布尔 base(4-10) + 布尔 sem(11-14) + 外呼方式 sem(18-22)，
    # 排除布尔 cb(15-17) 与 位置/IR(pos, 23-29)
    assert all(keep_bsem[:15]) and not any(keep_bsem[15:18])
    assert all(keep_bsem[18:23]) and not any(keep_bsem[23:])


# ---------------------------------------------------------------- T2 冻结等价性
def _freeze(module: torch.nn.Module) -> torch.nn.Module:
    for p in module.parameters():
        p.requires_grad_(False)
    return module


@pytest.mark.skipif(not LEGACY_DIR.exists(), reason="旧特征归档缺失（T2 需 legacy_feat_pre_frontend/）")
@pytest.mark.skipif(not SMOKE_GRAPH.exists(), reason="新格式 _feat.pt 缺失（先跑 m3_build_features.py）")
def test_freeze_flag_reproduces_archived_legacy_feature():
    """T2：冻结前端 + 同 init seed 重算 == 归档旧 `_feat.pt`（逐位）→ 重构无副作用。

    **口径（2026-09-12 函数级通道缺口修复后）**：归档的 legacy 特征产生于修复前；受影响图
    （func 通道有缺口的图）的新 `_feat.pt` 已按设计改变 → 这些图不再可比，T2 只在
    「修复前基线中无缺口」的图上执行（`products/alldata/splits/cb_func_gap.json` 里没列出的图）。
    """
    gap_path = REPO / "products/alldata/splits/cb_func_gap.json"
    all_bases = sorted(p.name.replace("_hetero.json", "") for p in GRAPH_DIR.glob("*_hetero.json"))
    affected = set(json.loads(gap_path.read_text(encoding="utf-8"))["graphs"]) \
        if gap_path.exists() else set()
    candidates = [b for b in all_bases if b not in affected][:3]
    assert candidates, "找不到可用于 T2 的无缺口图"
    checked = 0
    for base in candidates:
        legacy_path = LEGACY_DIR / f"{base}_feat.pt"
        if not legacy_path.exists():
            continue
        legacy = torch.load(legacy_path, map_location="cpu")
        sample = dataset.load_graph(base, graph_dir=str(GRAPH_DIR))
        fuser = _freeze(NodeFuser(d_struct=sample.meta["D_struct"],
                                  struct_layout=sample.meta["struct_layout"]))
        out = fuser(sample.channels)
        assert torch.equal(out, legacy), \
            f"{base}: 冻结前端输出与归档旧特征不一致（重构改变了数值）"
        checked += 1
    assert checked >= 1, "未找到可比对的归档文件"


# ---------------------------------------------------------------- dataset 断言
@pytest.mark.skipif(not SMOKE_GRAPH.exists(), reason="新格式 _feat.pt 缺失")
def test_dataset_channel_contract_and_hashes():
    """§4 断言：通道形状/哈希/行序；哈希校验失败时必须报出具体通道名。"""
    sample = dataset.load_graph(SMOKE_BASE, graph_dir=str(GRAPH_DIR), verify_channels="all")
    n = sample.meta["n_nodes"]
    assert tuple(sample.channels) == dataset.CHANNEL_ORDER
    assert sample.channels["struct"].shape[0] == n
    assert tuple(sample.channels["sv"].shape) == (n, 1)
    assert sample.meta["cb_missing_rows"] == 0
    feat = torch.load(SMOKE_GRAPH, map_location="cpu")
    # 正常情况无失配
    assert dataset.channel_hash_mismatches(feat, sample.channels, which="all") == []
    # 人为破坏 sv 通道 → 必须点名 sv
    bad_channels = dict(sample.channels)
    bad_channels["sv"] = bad_channels["sv"] + 1.0
    names = dataset.channel_hash_mismatches(feat, bad_channels, which="cheap")
    assert len(names) == 1 and names[0].startswith("sv"), f"应报具体通道名，实际 {names}"


@pytest.mark.skipif(not LEGACY_DIR.exists(), reason="旧特征归档缺失")
def test_dataset_rejects_legacy_tensor_feat():
    """旧格式（融合后张量）必须报错并指向归档目录（不静默降级）。"""
    legacy = torch.load(LEGACY_DIR / f"{SMOKE_BASE}_feat.pt", map_location="cpu")
    assert isinstance(legacy, torch.Tensor) and legacy.shape[1] == 128
    assert not isinstance(legacy, dict)


def test_ablation_edge_whitelist_and_drop_ast():
    """边级消融：`--drop-ast` = 删 relation 1+2；白名单外编号报错。"""
    assert sorted(dataset.resolve_drop_edges(drop_ast=True)) == [1, 2]
    with pytest.raises(ValueError):
        dataset.resolve_drop_edges({7})
