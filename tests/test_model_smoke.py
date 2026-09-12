#!/usr/bin/env python3
"""M4 smoke/单元测试（开发计划 v4 第八节 CI 清单）。

运行方式（从仓库根目录）：
  python -m pytest tests/test_model_smoke.py -v
  或直接 `python tests/test_model_smoke.py`（不依赖 pytest 也可独立跑）。

覆盖：
  - 基础组合：rgcn/gcn × attention/meanpool；num_bases=5/4；GAT 拒绝。
  - 输入校验：x/edge_index/edge_type 的 dtype/shape/值域错误。
  - 极端图：单节点、空边、孤立（纯自环）、重复边、极端 logits。
  - Readout 硬约束：hg == h2-based；≠ x-based；改边后输出变化。
  - 梯度：z.sum().backward() 后各参数有有限梯度（无 detach 断流）。
  - apply_edge_mask / safe_readout 纯函数。
  - 批图 vs 单图等价（按图归一化）。
"""

from __future__ import annotations

import sys
from pathlib import Path

import torch

# 从仓库根运行：把 scripts/ 加入 sys.path（与 `python scripts/xxx.py` 的解析约定一致）
_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "scripts"))

from model import (SSMHG, EPS, apply_edge_mask, safe_readout, validate_edge_types)  # noqa: E402

N, D, R, C = 9, 128, 5, 7


def make_data(seed: int = 0, n: int = N, dim: int = D, e: int = 12):
    """构造合法随机图数据（边不越界、edge_type 在 [0,R)）。"""
    g = torch.Generator().manual_seed(seed)
    x = torch.randn(n, dim, generator=g)
    ei = torch.randint(0, n, (2, e), generator=g)
    et = torch.randint(0, R, (e,), generator=g)
    return x, ei, et


# ---------- 基础组合 ----------

def test_rgcn_attention_shapes():
    x, ei, et = make_data()
    m = SSMHG().eval()
    z, a, nl = m(x, ei, et)
    assert z.shape == (C,)
    assert a.shape == (N,) and nl.shape == (N,)
    assert bool((a > 0).all() and (a < 1).all())
    assert bool(torch.isfinite(z).all() and torch.isfinite(a).all())


def test_all_combos_forward_and_backward():
    for conv in ("rgcn", "gcn"):
        for meanpool in (False, True):
            x, ei, et = make_data()
            m = SSMHG(conv_type=conv, use_meanpool=meanpool).train()
            z, a, nl = m(x, ei, et)
            assert z.shape == (C,) and a.shape == (N,) and nl.shape == (N,)
            (z.sum() + a.sum()).backward()
            for p in m.parameters():
                if p.requires_grad:
                    assert p.grad is not None and bool(torch.isfinite(p.grad).all()), \
                        f"{conv}/{meanpool}: grad missing/NaN"


def test_num_bases_4_and_5():
    x, ei, et = make_data()
    for bases in (4, 5):
        m = SSMHG(num_bases=bases).eval()
        z, a, _ = m(x, ei, et)
        assert z.shape == (C,) and a.shape == (N,)


def test_gat_rejected():
    try:
        SSMHG(conv_type="gat")
    except ValueError as exc:
        assert "conv_type" in str(exc)
    else:
        raise AssertionError("gat should be rejected")


def test_invalid_num_bases_rejected():
    for bad in (0, 6, -1):
        try:
            SSMHG(num_bases=bad)
        except ValueError as exc:
            assert "num_bases" in str(exc)
        else:
            raise AssertionError(f"num_bases={bad} should be rejected")


# ---------- 输入校验 ----------

def test_x_shape_errors():
    x, ei, et = make_data()
    m = SSMHG().eval()
    for bad in (x[:, :64], x[0], x.unsqueeze(0)):
        try:
            m(bad, ei, et)
        except ValueError as exc:
            assert "x must be" in str(exc)
        else:
            raise AssertionError("bad x should be rejected")


def test_edge_index_errors():
    x, ei, et = make_data()
    m = SSMHG().eval()
    try:
        m(x, ei.float(), et)
    except ValueError as exc:
        assert "edge_index must be" in str(exc)
    else:
        raise AssertionError("float edge_index should be rejected")
    try:
        m(x, ei[0], et)
    except ValueError as exc:
        assert "edge_index must be" in str(exc)
    else:
        raise AssertionError("1-D edge_index should be rejected")


def test_edge_type_errors():
    x, ei, et = make_data()
    m = SSMHG().eval()
    # dtype 错误
    try:
        m(x, ei, et.float())
    except ValueError as exc:
        assert "edge_type must be" in str(exc)
    else:
        raise AssertionError("float edge_type should be rejected")
    # 长度错误
    try:
        m(x, ei, et[:-1])
    except ValueError as exc:
        assert "length" in str(exc)
    else:
        raise AssertionError("mismatched edge_type length should be rejected")
    # 值域越界
    et_bad = et.clone(); et_bad[0] = R
    try:
        m(x, ei, et_bad)
    except ValueError as exc:
        assert "out of range" in str(exc)
    else:
        raise AssertionError("out-of-range edge_type should be rejected")


def test_batch_validation():
    x, ei, et = make_data(n=6)
    m = SSMHG().eval()
    for bad in (torch.zeros(5, dtype=torch.long), torch.zeros(6), torch.zeros(6, dtype=torch.long).unsqueeze(1)):
        try:
            m(x[:6], ei.clamp_max(5), et, batch=bad)
        except ValueError:
            pass
        else:
            raise AssertionError("bad batch should be rejected")


# ---------- 极端图 ----------

def test_single_node_no_edge():
    x = torch.randn(1, D)
    ei = torch.empty((2, 0), dtype=torch.long)
    et = torch.empty(0, dtype=torch.long)
    m = SSMHG().eval()
    z, a, nl = m(x, ei, et)
    assert z.shape == (C,) and a.shape == (1,) and nl.shape == (1,)
    assert bool(torch.isfinite(z).all() and torch.isfinite(a).all() and 0 < a < 1)


def test_empty_edges_multi_node():
    x = torch.randn(5, D)
    ei = torch.empty((2, 0), dtype=torch.long)
    et = torch.empty(0, dtype=torch.long)
    m = SSMHG().eval()
    z, a, _ = m(x, ei, et)
    assert z.shape == (C,) and a.shape == (5,)
    assert bool(torch.isfinite(z).all() and torch.isfinite(a).all())


def test_isolated_self_loops():
    x = torch.randn(5, D)
    ei = torch.arange(5, dtype=torch.long).repeat(2, 1)
    et = torch.zeros(5, dtype=torch.long)
    m = SSMHG().eval()
    z, a, _ = m(x, ei, et)
    assert z.shape == (C,) and a.shape == (5,)
    assert bool(torch.isfinite(z).all() and torch.isfinite(a).all())


def test_duplicate_edges():
    x = torch.randn(4, D)
    ei = torch.tensor([[0, 0, 1, 1, 0], [1, 2, 2, 1, 2]])
    et = torch.tensor([0, 0, 1, 3, 4])
    m = SSMHG().eval()
    z, a, _ = m(x, ei, et)
    assert z.shape == (C,) and a.shape == (4,)
    assert bool(torch.isfinite(z).all() and torch.isfinite(a).all())


def test_extreme_logits_no_nan():
    """放大 a_head 权重模拟极端 logits。

    float32 下 sigmoid 饱和为精确 0.0/1.0 属预期；真正要防的是 NaN/Inf，
    以及 a 全饱和时 eps 分母保护仍使 hg/alpha 有限（注意力塌缩由 M5 L_var 监控）。
    """
    x, ei, et = make_data()
    m = SSMHG().eval()
    with torch.no_grad():
        m.a_head.weight.data.mul_(100.0)
        m.a_head.bias.data.zero_()
    z, a, nl = m(x, ei, et)
    assert bool(torch.isfinite(z).all() and torch.isfinite(a).all() and torch.isfinite(nl).all())
    assert bool((a >= 0).all() and (a <= 1).all()), "a out of [0,1]"
    # 直接经 safe_readout 检验极小/极大 logits 的归一化（全饱和时仍有限）
    for scale in (1e-6, 1e6):
        hg, alpha, a2 = safe_readout(torch.randn(5, D), torch.full((5,), scale))
        assert bool(torch.isfinite(hg).all() and torch.isfinite(alpha).all())
        assert bool(torch.isfinite(a2).all())
    # 全部 logits 极小（a 全塌到 ~0）：分母 +eps 仍使输出有限
    hg0, alpha0, _ = safe_readout(torch.randn(5, D), torch.full((5,), -100.0))
    assert bool(torch.isfinite(hg0).all() and torch.isfinite(alpha0).all())


# ---------- Readout 硬约束 ----------

def test_readout_is_h2_based():
    x, ei, et = make_data()
    m = SSMHG().eval()
    out = m(x, ei, et, return_intermediates=True)
    hg, h2, alpha = out["hg"], out["h2"], out["alpha"]
    # 1) 严格等价：hg == Σ alpha·h2
    assert torch.allclose(hg, (alpha.unsqueeze(-1) * h2).sum(0), atol=1e-5)
    # 2) ≠ x-based（非退化随机样本下）
    wrong = (alpha.unsqueeze(-1) * x).sum(0)
    assert not torch.allclose(hg, wrong, atol=1e-3), "hg equals x-based readout — bug"
    # 3) 改边后输出变化（证明传播生效）
    z0 = out["z"]
    keep = torch.arange(ei.shape[1] - 1)
    zp, _, _ = m(x, ei[:, keep], et[keep])
    assert not torch.allclose(z0, zp, atol=1e-4), "edge perturbation did not change z"


def test_return_intermediates_structure():
    x, ei, et = make_data()
    m = SSMHG().eval()
    out = m(x, ei, et, return_intermediates=True)
    for key in ("z", "a", "node_logits", "h1", "h2", "alpha", "hg"):
        assert key in out
    assert out["h1"].shape == (N, D) and out["h2"].shape == (N, D)
    assert out["hg"].shape == (D,)
    # 默认三元组不受影响
    z, a, nl = m(x, ei, et)
    assert torch.allclose(z, out["z"]) and torch.allclose(a, out["a"])


# ---------- 梯度 ----------

def test_gradient_flows_no_detach():
    x, ei, et = make_data()
    m = SSMHG().eval()
    z, a, nl = m(x, ei, et)
    assert z.requires_grad and a.requires_grad and nl.requires_grad
    z.sum().backward(retain_graph=True)
    for name, p in m.named_parameters():
        if p.requires_grad:
            assert p.grad is not None, f"no grad for {name}"
    # 中间表示 h2 的梯度（retain_grad 路径）
    x2, ei2, et2 = make_data(seed=7)
    m2 = SSMHG().train()
    out = m2(x2, ei2, et2, return_intermediates=True)
    out["h2"].retain_grad()
    out["z"].sum().backward()
    assert out["h2"].grad is not None and bool(torch.isfinite(out["h2"].grad).all())


# ---------- 纯函数 ----------

def test_apply_edge_mask_sync():
    x, ei, et = make_data(e=10)
    mask = torch.tensor([True, False, True] + [False] * 7)
    ei_m, et_m = apply_edge_mask(ei, et, mask)
    assert ei_m.shape == (2, 2) and et_m.shape == (2,)
    assert torch.equal(ei_m, ei[:, mask])
    assert torch.equal(et_m, et[mask])
    # 全 False → 空边
    ei_e, et_e = apply_edge_mask(ei, et, torch.zeros(10, dtype=torch.bool))
    assert ei_e.shape == (2, 0) and et_e.numel() == 0
    # 长度不符报错
    try:
        apply_edge_mask(ei, et, torch.ones(5, dtype=torch.bool))
    except ValueError:
        pass
    else:
        raise AssertionError("mask length mismatch should raise")


def test_validate_edge_types():
    et = torch.tensor([0, 4])
    assert validate_edge_types(et, 5, n_edges=2) == 2
    try:
        validate_edge_types(et, 5, n_edges=3)
    except ValueError:
        pass
    else:
        raise AssertionError("length mismatch should raise")
    try:
        validate_edge_types(torch.tensor([5]), 5)
    except ValueError:
        pass
    else:
        raise AssertionError("out-of-range should raise")


def test_safe_readout_attention():
    h = torch.randn(5, D)
    nl = torch.randn(5)
    hg, alpha, a = safe_readout(h, nl)
    assert hg.shape == (D,) and alpha.shape == (5,) and a.shape == (5,)
    assert torch.allclose(hg, (alpha.unsqueeze(-1) * h).sum(0), atol=1e-6)
    assert torch.allclose(alpha.sum(), torch.tensor(1.0), atol=1e-5)
    # meanpool
    hg_m, _, _ = safe_readout(h, nl, use_meanpool=True)
    assert torch.allclose(hg_m, h.mean(0), atol=1e-6)
    # 批图：每图 alpha 之和 == 1
    hb = torch.randn(6, D)
    nlb = torch.randn(6)
    bch = torch.tensor([0, 0, 0, 1, 1, 1])
    hgb, alphab, _ = safe_readout(hb, nlb, batch=bch)
    assert hgb.shape == (2, D)
    per = torch.zeros(2)
    per = per.index_add_(0, bch, alphab)
    assert torch.allclose(per, torch.ones(2), atol=1e-5)


# ---------- 批图 vs 单图 ----------

def test_batch_equals_per_graph():
    x = torch.randn(5, D)
    ei = torch.tensor([[0, 2, 3], [1, 3, 4]])   # 图A:0-1；图B:2-3-4
    et = torch.tensor([0, 0, 3])
    bch = torch.tensor([0, 0, 1, 1, 1])
    for conv in ("rgcn", "gcn"):
        m = SSMHG(conv_type=conv).eval()
        zb, ab, _ = m(x, ei, et, batch=bch)
        assert zb.shape == (2, C) and ab.shape == (5,)
        za, _, _ = m(x[0:2], torch.tensor([[0], [1]]), torch.tensor([0]))
        zbb, _, _ = m(x[2:5], torch.tensor([[0, 1], [1, 2]]), torch.tensor([0, 3]))
        assert torch.allclose(zb[0], za, atol=1e-5), conv
        assert torch.allclose(zb[1], zbb, atol=1e-5), conv


def test_batch_meanpool():
    x = torch.randn(5, D)
    ei = torch.tensor([[0, 2, 3], [1, 3, 4]])
    et = torch.tensor([0, 0, 3])
    bch = torch.tensor([0, 0, 1, 1, 1])
    ma = SSMHG(use_meanpool=True).eval()
    zb, _, _ = ma(x, ei, et, batch=bch)
    assert zb.shape == (2, C)
    # 等价逐图均值
    za, _, _ = ma(x[0:2], torch.tensor([[0], [1]]), torch.tensor([0]))
    zbb, _, _ = ma(x[2:5], torch.tensor([[0, 1], [1, 2]]), torch.tensor([0, 3]))
    assert torch.allclose(zb[0], za, atol=1e-5)
    assert torch.allclose(zb[1], zbb, atol=1e-5)


# ---------- 独立运行入口（无 pytest 时）----------

def _run_all() -> None:
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    for name, fn in tests:
        fn()
        print(f"[ok] {name}")
    print(f"ALL {len(tests)} TESTS PASSED")


if __name__ == "__main__":
    _run_all()
