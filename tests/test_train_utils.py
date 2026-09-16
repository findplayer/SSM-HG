"""M5 训练纯函数单测（手册 12.6 / `docs/M5_dev_plan.md` §7：loss / L_var / batch / train-one-step）。

覆盖（失败定位到单一契约）：
  - class_stats：pos_weight 截断 20；零正类 class_mask=0 且 pos_weight=0；全零正类报错；
  - masked_weighted_bce：分母 = B×active_count；零正类被显式排除；无 NaN；
  - per_graph_population_std：单节点 std=0；两图分组分别计算（与 torch.std(unbiased=False) 一致）；
    空图报错；
  - collate：节点偏移正确、无跨图边、batch 向量与 labels 形状正确；DropEdge 同步过滤且同 seed 可复现；
  - train-one-step：合成批图前向+反向后 a_head 与 GNN 梯度非空。

运行：pytest tests/test_train_utils.py -q
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pytest
import torch
import torch.nn.functional as F

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from dataset import CHANNEL_ORDER, GraphSample, collate  # noqa: E402
from model import AblationConfig, sample_dropout_masks  # noqa: E402
from train import (build_fuser_model, class_stats,  # noqa: E402
                   masked_weighted_bce, per_graph_population_std,
                   run_dir_conflict)


# ---------------------------------------------------------------- 覆盖保护
def _cfg(tmp_path: Path, **args) -> Path:
    """造一个 <tmp>/seed0/config.json，返回 run_dir。"""
    import json
    run_dir = tmp_path / "seed0"
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "config.json").write_text(
        json.dumps({"args": args, "split_seed": args.get("split_seed", 0)},
                   ensure_ascii=False), encoding="utf-8")
    return run_dir


def test_run_dir_conflict_missing_dir_is_none(tmp_path):
    """目录不存在（首次运行）不得报冲突。"""
    from train import run_dir_conflict as f
    assert f(tmp_path / "seed0", argparse.Namespace(a=1), 0) is None


def test_run_dir_conflict_same_args_is_none(tmp_path):
    """逐项同参（复跑）不得报冲突——否则会把正常复现挡在门外。"""
    from train import run_dir_conflict as f
    run_dir = _cfg(tmp_path, lr=1e-4, epochs=200, split_seed=0)
    assert f(run_dir, argparse.Namespace(lr=1e-4, epochs=200), 0) is None


@pytest.mark.parametrize("key,old,new", [
    ("lr", 1e-4, 1e-3),                       # 换超参 = 另一次实验
    ("split_dir", "/a/splits", "/b/splits"),  # 换划分臂（消融最常见）
    ("graph_dir", "/a/graphs", "/b/graphs"),  # 换数据集
])
def test_run_dir_conflict_detects_arg_change(tmp_path, key, old, new):
    from train import run_dir_conflict as f
    run_dir = _cfg(tmp_path, **{key: old})
    msg = f(run_dir, argparse.Namespace(**{key: new}), 0)
    assert msg is not None and key in msg, msg


def test_run_dir_conflict_detects_split_seed_change(tmp_path):
    """换划分种子同样必须拦——划分不同就不是同一份结果。"""
    from train import run_dir_conflict as f
    run_dir = _cfg(tmp_path, lr=1e-4)
    msg = f(run_dir, argparse.Namespace(lr=1e-4), 2)
    assert msg is not None and "split_seed" in msg, msg


def test_run_dir_conflict_ignores_keys_absent_from_old_config(tmp_path):
    """老 config.json 没有的新键不得算冲突（否则新版本会拒绝复跑旧实验）。"""
    from train import run_dir_conflict as f
    run_dir = _cfg(tmp_path, lr=1e-4, split_seed=0)
    # 本次多了老配置没记录的 `overwrite` 与 `新开关`
    assert f(run_dir, argparse.Namespace(lr=1e-4, overwrite=True, brand_new_flag=7), 0) is None


def test_run_dir_conflict_unparseable_config(tmp_path):
    """中断残留的坏 config.json 必须报冲突（宁可疑、不可无声覆盖）。"""
    from train import run_dir_conflict as f
    run_dir = tmp_path / "seed0"
    run_dir.mkdir(parents=True)
    (run_dir / "config.json").write_text("{ 半截", encoding="utf-8")
    assert f(run_dir, argparse.Namespace(a=1), 0) is not None

LAYOUT = {"visibility": 4, "bool": 14, "call_mode": 5, "position": 1, "ir": 6}


def _sample(n, seed, name="g", edge_index=None, edge_type=None):
    g = torch.Generator().manual_seed(seed)
    channels = {
        "cb_func": torch.randn(n, 768, generator=g),
        "cb_node": torch.randn(n, 768, generator=g),
        "type_id": torch.randint(0, 9, (n,), generator=g),
        "struct": torch.randn(n, 30, generator=g),
        "sv": torch.rand(n, 1, generator=g),
    }
    if edge_index is None:
        edge_index = torch.stack([torch.arange(n - 1), torch.arange(1, n)])
        edge_type = torch.zeros(n - 1, dtype=torch.long)
    elif edge_type is None:
        edge_type = torch.zeros(edge_index.shape[1], dtype=torch.long)
    label = torch.zeros(7)
    label[0] = 1.0
    return GraphSample(channels=channels, edge_index=edge_index, edge_type=edge_type,
                       label=label, name=name, node_id=list(range(n)), meta={"n_nodes": n})


# ----------------------------------------------------------------- 损失 / 类别统计
def test_class_stats_pos_weight_truncated_and_zero_positive_masked():
    labels = torch.zeros(100, 7)
    labels[:1, 0] = 1.0      # class0: 1 pos / 99 neg → 99 → 截断 20
    labels[:2, 1] = 1.0      # class1: 2 pos / 98 neg → 49 → 截断 20
    labels[:10, 2] = 1.0     # class2: 10 pos / 90 neg → 9（不截断）
    pos_weight, class_mask, active, train_pos, train_neg = class_stats(labels)
    assert float(pos_weight[0]) == pytest.approx(20.0)
    assert float(pos_weight[1]) == pytest.approx(20.0)
    assert float(pos_weight[2]) == pytest.approx(9.0)
    assert int(class_mask.sum()) == 3 and active == 3
    for c in range(3, 7):
        assert float(class_mask[c]) == 0.0 and float(pos_weight[c]) == 0.0, \
            "零正类必须用 class_mask=0（且 pos_weight=0），不得静默进入损失"
    assert int(train_pos[0]) == 1 and int(train_neg[0]) == 99


def test_masked_weighted_bce_denominator_and_excludes_masked_classes():
    B, C = 4, 7
    torch.manual_seed(0)
    z = torch.randn(B, C)
    labels = torch.zeros(B, C)
    labels[:, 0] = 1.0
    labels[0, 1] = 1.0
    pos_weight, class_mask, active, _, _ = class_stats(labels)
    loss = masked_weighted_bce(z, labels, pos_weight, class_mask)
    assert torch.isfinite(loss)
    # 手工重算：分母 = B × active_count，分子 = Σ bce·(pos_weight 加权)·class_mask
    bce = F.binary_cross_entropy_with_logits(z, labels, reduction="none")
    weight = labels * pos_weight + (1.0 - labels)
    expected = (bce * weight * class_mask).sum() / (B * active)
    assert float(loss) == pytest.approx(float(expected))
    # 被 mask 的类（2..6）其任何梯度贡献应为 0：把 z 在被 mask 类上的值改大，loss 不变
    z2 = z.clone()
    z2[:, 2:] += 100.0
    loss2 = masked_weighted_bce(z2, labels, pos_weight, class_mask)
    assert float(loss) == pytest.approx(float(loss2))


def test_masked_weighted_bce_all_zero_positive_raises():
    labels = torch.zeros(5, 7)
    pos_weight, class_mask, active, _, _ = class_stats(labels)
    assert active == 0
    with pytest.raises(ValueError):
        masked_weighted_bce(torch.randn(5, 7), labels, pos_weight, class_mask)


def test_focal_and_asl_degenerate_to_bce_and_are_finite():
    """focal(gamma=0) 与 asl(g_pos=g_neg=0, clip=0) 必须**逐位等于** bce；三者均不得 NaN/Inf。

    退化等价是这三条损失共用同一加权结构的可证伪校验：调制因子的默认参数取中性值时，
    唯一差异项消失，损失必须精确回到 bce（含 class_mask 与分母口径）。
    """
    B, C = 8, 7
    torch.manual_seed(0)
    z = torch.randn(B, C) * 3.0
    labels = torch.zeros(B, C)
    labels[:2, 0] = 1.0
    labels[0, 1] = 1.0
    labels[:3, 4] = 1.0
    pos_weight, class_mask, _, _, _ = class_stats(labels)

    base = masked_weighted_bce(z, labels, pos_weight, class_mask)              # loss="bce"
    focal0 = masked_weighted_bce(z, labels, pos_weight, class_mask,
                                 loss="focal", focal_gamma=0.0)
    asl0 = masked_weighted_bce(z, labels, pos_weight, class_mask, loss="asl",
                               asl_gamma_pos=0.0, asl_gamma_neg=0.0, asl_clip=0.0)
    # 容差用相对误差：bce 分支走 F.binary_cross_entropy_with_logits（log-sum-exp），
    # focal/asl 分支走 softplus 分解，float32 下两者有 ~1e-7 量级的表示差异（非语义差异）。
    assert float(focal0) == pytest.approx(float(base), rel=1e-6)
    assert float(asl0) == pytest.approx(float(base), rel=1e-6)

    # 非退化参数：有限、正、且 focal/asl 小于 bce（调制因子 ∈(0,1) → 只可能调小）
    for kw in [dict(loss="focal", focal_gamma=2.0),
               dict(loss="asl", asl_gamma_pos=1.0, asl_gamma_neg=4.0, asl_clip=0.05)]:
        v = masked_weighted_bce(z, labels, pos_weight, class_mask, **kw)
        assert torch.isfinite(v) and float(v) > 0.0
        assert float(v) < float(base)

    # 极端 logits（±80）不产生 NaN/Inf（logsigmoid/softplus 表达的目的）
    ze = torch.full((B, C), 80.0)
    ze[::2] = -80.0
    for kw in [dict(), dict(loss="focal", focal_gamma=2.0),
               dict(loss="asl", asl_gamma_pos=1.0, asl_gamma_neg=4.0, asl_clip=0.05)]:
        assert torch.isfinite(masked_weighted_bce(ze, labels, pos_weight, class_mask, **kw))

    with pytest.raises(ValueError):
        masked_weighted_bce(z, labels, pos_weight, class_mask, loss="nope")


# ----------------------------------------------------------------- L_var
def test_per_graph_population_std_single_node_and_two_graphs():
    # 单节点 → std≈0（开方内 eps 防 NaN，前向值 ≈0）
    assert float(per_graph_population_std(torch.tensor([0.5]), torch.tensor([0]), 1)) < 1e-3
    # 两图分组：图0 有 0.1/0.9（多节点，与 torch.std(unbiased=False) 一致）、图1 有 0.5（单节点 ≈0）
    a = torch.tensor([0.1, 0.9, 0.5])
    batch = torch.tensor([0, 0, 1])
    std = per_graph_population_std(a, batch, 2)
    assert float(std[0]) == pytest.approx(float(a[batch == 0].std(unbiased=False)))
    assert float(std[1]) < 1e-3


def test_per_graph_population_std_empty_raises():
    with pytest.raises(ValueError):
        per_graph_population_std(torch.tensor([]), torch.tensor([], dtype=torch.long), 0)


def test_per_graph_population_std_grad_flows():
    a = torch.tensor([0.2, 0.7, 0.4], requires_grad=True)
    std = per_graph_population_std(a, torch.tensor([0, 0, 1]), 2)
    std.sum().backward()
    assert a.grad is not None and bool(a.grad.abs().sum() > 0), "L_var 必须保留 autograd"


# ----------------------------------------------------------------- collate / batch
def test_collate_node_offset_and_no_cross_graph_edges():
    g0 = _sample(2, seed=0, edge_index=torch.tensor([[0], [1]]))
    g1 = _sample(3, seed=1, edge_index=torch.tensor([[0], [2]]))
    channels, ei, et, batch, labels = collate([g0, g1], training=False)
    assert ei.tolist() == [[0, 2], [1, 4]], "图1 的边必须加节点偏移 2"
    assert et.tolist() == [0, 0]
    assert batch.tolist() == [0, 0, 1, 1, 1]
    assert labels.shape == (2, 7)
    assert channels["sv"].shape == (5, 1)
    assert tuple(channels) == CHANNEL_ORDER


def test_collate_dropedge_reproducible_and_consistent():
    samples = [_sample(6, seed=0), _sample(7, seed=1)]   # 各有 5/6 条链边
    g1 = torch.Generator().manual_seed(42)
    g2 = torch.Generator().manual_seed(42)
    c1 = collate(samples, drop_edge_prob=0.5, generator=g1, training=True)
    c2 = collate(samples, drop_edge_prob=0.5, generator=g2, training=True)
    assert torch.equal(c1[1], c2[1]) and torch.equal(c1[2], c2[2]), "同 seed DropEdge 必须可复现"
    assert c1[1].shape[1] == c1[2].shape[0], "edge_index 列数必须等于 edge_type 长度（同步过滤）"
    # DropEdge=0 与不启用（training=False）结构一致
    full = collate(samples, drop_edge_prob=0.0, training=True)
    no_drop = collate(samples, training=False)
    assert torch.equal(full[1], no_drop[1]) and torch.equal(full[2], no_drop[2])


# ----------------------------------------------------------------- train one-step
def test_train_one_step_forward_backward_gradients():
    samples = [_sample(3, seed=0, name="g0"), _sample(4, seed=1, name="g1")]
    cfg = argparse.Namespace(seed=0, prior_dropout=0.2, struct_dropout=0.2,
                             model_dropout=0.3, hid=128, num_bases=5,
                             conv="rgcn", meanpool=False)
    fuser, model = build_fuser_model({"D_struct": 30, "struct_layout": LAYOUT},
                                     AblationConfig(), cfg)
    channels, ei, et, batch, labels = collate(samples, training=True)
    B = len(samples)
    gen = torch.Generator().manual_seed(0)
    pm, sm = sample_dropout_masks(B, prior_p=0.2, struct_p=0.2, generator=gen)
    x = fuser(channels, prior_mask=pm, struct_mask=sm, batch=batch)
    z, a, _ = model(x, ei, et, batch=batch)
    assert a.shape == (7,) and z.shape == (2, 7)
    pos_weight, class_mask, active, _, _ = class_stats(labels)
    loss_cls = masked_weighted_bce(z, labels, pos_weight, class_mask)
    loss_var = torch.relu(0.1 - per_graph_population_std(a, batch, B)).mean()
    (loss_cls + 1e-3 * loss_var).backward()
    # a_head 与 GNN 梯度非空
    assert model.a_head.weight.grad is not None and model.a_head.weight.grad.abs().sum() > 0
    assert any(p.grad is not None and p.grad.abs().sum() > 0 for p in model.conv1.parameters())
    assert any(p.grad is not None and p.grad.abs().sum() > 0 for p in model.conv2.parameters())
    assert fuser.proj.weight.grad is not None and fuser.proj.weight.grad.abs().sum() > 0
