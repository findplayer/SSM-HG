#!/usr/bin/env python3
"""M4：RGCN/GCN 两层消息传递 + 节点可疑度 + 图级 Readout（大纲 4.4，手册第 9 章 / 开发计划 v4）。

契约（与 M5 dataset/train 对齐，2026-09-07）：
  - 输入 x 来自 M3 `_feat.pt`（N×128 的 h_v^(0)）；`_pyg.pt` 只提供 edge_index/edge_type 与元数据，
    `_pyg.pt["x"]`（N×1 占位）不被使用、也不回写。
  - 关系编号固定（手册 7.7）：0=CFG_FLOW, 1=AST_PARENT, 2=AST_PARENT_SAME, 3=DFG_DEP, 4=CALLBACK_RISK。
  - 单图 forward(x, edge_index, edge_type) -> (z[num_classes], a[N], node_logits[N])；
    batch 图 forward(..., batch=[N]) -> z[B, num_classes]，a/node_logits 仍按节点返回；Readout 按图归一化。
  - return_intermediates=True 时返回 dict：{z,a,node_logits,h1,h2,alpha,hg}，供调试与单测。
  - Readout 使用第二层传播结果 h2（= h_v^(L)），绝不用输入 x（曾为易错点，验收见 tests）。
  - conv_type 仅 "rgcn"/"gcn"：GCN 忽略 edge_type（非关系感知消融基线）；普通 GAT 不提供。
  - num_bases 默认 = num_relations(=5)；num_bases=4 仅作消融。
  - DropEdge / 先验 dropout / L_var / 训练日志均属 M5（train.py/dataset.py），本文件不实现；
    仅提供纯工具 apply_edge_mask（M5 同步过滤边用）。

空边与孤立节点（已在本机 PyG 2.7.0 实测验证，2026-09-07）：
  - RGCNConv(root_weight=True) 与 GCNConv(add_self_loops=True) 对 E=0 空边、纯自环、孤立节点
    均正常输出有限值——官方实现即受控路径，无需自定义 linear_root fallback；
    若将来升级 PyG 导致行为变化，回归入口在 tests/test_model_smoke.py 的空边用例。
"""

from __future__ import annotations

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch_geometric.nn import GCNConv, RGCNConv

# 关系编号固定（手册 7.7 / convert_hetero_json_to_pyg.py 的 RELATION_IDS）
RELATION_NAMES = {
    0: "CFG_FLOW",
    1: "AST_PARENT",
    2: "AST_PARENT_SAME",
    3: "DFG_DEP",
    4: "CALLBACK_RISK",
}
EPS = 1e-6          # attention 归一化分母保护（大纲 4.4.1 的 ε）
HID_DIM = 128       # 手册 9.1：隐藏维度 d=128（与 M3 的 h_v^(0) 维度一致）


def _scatter_add(src: torch.Tensor, index: torch.Tensor, dim_size: int) -> torch.Tensor:
    """index_add_ 实现 scatter_add（不依赖 torch_scatter）。

    参数：
      src:      [N, ...] 待聚合张量。
      index:    [N] torch.long，聚合桶编号（0 起）。
      dim_size: 输出第 0 维长度（= 图数 B）。
    返回：聚合结果 [dim_size, ...]。
    """
    out = torch.zeros((dim_size,) + tuple(src.shape[1:]), dtype=src.dtype, device=src.device)
    return out.index_add_(0, index, src)


def validate_edge_types(edge_type, num_relations: int, n_edges: int | None = None) -> int:
    """校验 edge_type：torch.long、长度 == 边数、值域 [0, num_relations)。返回边数 E。

    即使 conv_type="gcn"（忽略 edge_type）也执行该校验，避免 RGCN/GCN 数据契约分叉。
    """
    if not isinstance(edge_type, torch.Tensor) or edge_type.dtype != torch.long:
        raise ValueError(
            "edge_type must be a torch.long tensor, got "
            f"dtype={getattr(edge_type, 'dtype', type(edge_type).__name__)}"
        )
    e = int(edge_type.numel())
    if n_edges is not None and e != n_edges:
        raise ValueError(f"edge_type length {e} != edge_index edges {n_edges}")
    if e > 0:
        lo, hi = int(edge_type.min()), int(edge_type.max())
        if lo < 0 or hi >= num_relations:
            raise ValueError(
                f"edge_type out of range [0, {num_relations - 1}], got min={lo} max={hi}"
            )
    return e


def apply_edge_mask(edge_index: torch.Tensor, edge_type: torch.Tensor,
                    mask: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    """纯函数：按同一布尔 mask 同步过滤 edge_index 与 edge_type（DropEdge 由 M5 调用）。

    - 不执行随机采样、不改变节点编号；
    - mask 长度必须等于边数 E；
    - M5 训练期按 mask 过滤后把新的 edge_index/edge_type 传入 forward。
    """
    if not isinstance(mask, torch.Tensor) or mask.dtype != torch.bool:
        raise ValueError("mask must be a torch.bool tensor")
    if mask.dim() != 1 or int(mask.numel()) != int(edge_index.shape[1]):
        raise ValueError(
            f"mask must be 1-D of length E={int(edge_index.shape[1])}, "
            f"got shape={tuple(mask.shape)}"
        )
    keep = mask.nonzero(as_tuple=False).squeeze(1)          # [K] long，K 可为 0
    return edge_index[:, keep], edge_type[keep]


def safe_readout(h: torch.Tensor, node_logits: torch.Tensor, batch: torch.Tensor | None = None,
                 use_meanpool: bool = False, eps: float = EPS) -> tuple[torch.Tensor, torch.Tensor]:
    """图级 Readout（大纲 4.4.1）：返回 (hg, alpha, a)。a = sigmoid(node_logits)。

    单图（batch=None）：alpha = a / (a.sum() + eps)；hg = Σ alpha·h（h 是传播后的 h_v^(L)，不是输入 x）。
    批图（batch 给定，PyG 语义，[N] long）：分母与聚合都按图 scatter；hg 形状 [B, D]。
    use_meanpool=True 时仅替换图表示为 h.mean（单图）或逐图均值，不改变 a 的计算。
    """
    a = torch.sigmoid(node_logits)                           # [N]
    if use_meanpool:
        if batch is None:
            hg = h.mean(dim=0)                               # [D]
            alpha = torch.full_like(a, 1.0 / float(a.numel()))
        else:
            b_size = int(batch.max()) + 1
            cnt = _scatter_add(torch.ones_like(a), batch, b_size)      # [B]
            hg = _scatter_add(h, batch, b_size) / cnt.unsqueeze(-1)    # [B, D]
            alpha = torch.ones_like(a) / cnt[batch]                    # [N]
        return hg, alpha, a
    if batch is None:
        denom = a.sum()
        alpha = a / (denom + eps)
        hg = (alpha.unsqueeze(-1) * h).sum(dim=0)            # [D]
    else:
        b_size = int(batch.max()) + 1
        denom = _scatter_add(a, batch, b_size)               # [B] 每图 a 之和
        alpha = a / (denom[batch] + eps)                     # [N] 按图归一化
        hg = _scatter_add(alpha.unsqueeze(-1) * h, batch, b_size)      # [B, D]
    return hg, alpha, a


class SSMHG(nn.Module):
    """M4 主模型：两层图消息传递 → 节点可疑度 a_v → 基于 h_v^(L) 的注意力 Readout → 图级 logits。

    公式（大纲 4.4.1 / 手册 9.2~9.3）：
      h_v^(l+1) = σ(W0 h_v^(l) + Σ_r Σ_{u∈N_r(v)} (1/c) W_r h_u^(l))   （RGCN 两层）
      node_logits_v = w^T h_v^(L)；a_v = σ(node_logits_v)
      α_v = a_v / (Σ_u a_u + ε)；h_G = Σ_v α_v h_v^(L)；z_G = MLP(h_G)
    先验 s_v 只经 M3 的 h_v^(0) 进入，本模型不显式使用（grep 不应命中 s_v/prior/m1）。
    训练期 DropEdge/先验 dropout/L_var 属 M5；本模型 forward 内不做随机丢边或先验置零。
    """

    def __init__(self, in_dim: int = HID_DIM, hid: int = HID_DIM, num_relations: int = 5,
                 num_bases: int = 5, num_classes: int = 7, dropout: float = 0.3,
                 conv_type: str = "rgcn", use_meanpool: bool = False):
        super().__init__()
        if conv_type not in ("rgcn", "gcn"):
            raise ValueError(
                f"conv_type must be 'rgcn' or 'gcn', got {conv_type!r}; "
                "plain GAT is excluded (it cannot express relation-aware message passing); "
                "implement RGAT separately if needed."
            )
        if not (1 <= num_bases <= num_relations):
            raise ValueError(f"num_bases must be in [1, {num_relations}], got {num_bases}")
        if in_dim <= 0 or hid <= 0 or num_classes <= 0:
            raise ValueError("in_dim/hid/num_classes must all be positive")

        self.in_dim = int(in_dim)
        self.hid = int(hid)
        self.num_relations = int(num_relations)
        self.num_bases = int(num_bases)
        self.num_classes = int(num_classes)
        self.dropout = float(dropout)
        self.conv_type = conv_type
        self.use_meanpool = bool(use_meanpool)

        if conv_type == "rgcn":
            # root_weight=True：空边/孤立节点时仍保留节点自身变换项（PyG 2.7.0 官方行为）
            self.conv1 = RGCNConv(in_dim, hid, num_relations, num_bases=num_bases,
                                  root_weight=True)
            self.conv2 = RGCNConv(hid, hid, num_relations, num_bases=num_bases,
                                  root_weight=True)
        else:  # gcn：忽略 edge_type，同构基线（add_self_loops=True 保证孤立节点可更新）
            self.conv1 = GCNConv(in_dim, hid)
            self.conv2 = GCNConv(hid, hid)
        self.a_head = nn.Linear(hid, 1)                      # 节点可疑度 logits
        self.cls = nn.Sequential(nn.Linear(hid, 64), nn.ReLU(), nn.Linear(64, num_classes))

    def forward(self, x: torch.Tensor, edge_index: torch.Tensor, edge_type: torch.Tensor,
                batch: torch.Tensor | None = None,
                return_intermediates: bool = False):
        """前向：两层消息传递 → node_logits/a → h_v^(L)-based Readout → 图级 logits。

        参数：
          x                  [N, in_dim] float，M3 `_feat.pt` 的 h_v^(0)。
          edge_index         [2, E] torch.long。
          edge_type          [E] torch.long，值域 [0, num_relations)；GCN 分支忽略但不跳过校验。
          batch              可选 [N] torch.long（PyG 语义：节点所属图编号，0 起连续）；None=单图。
          return_intermediates   True 时返回 dict{z,a,node_logits,h1,h2,alpha,hg}。
        返回：
          (z, a, node_logits)：
            - z：单图 [num_classes] / 批图 [B, num_classes]（图级 logits，未 sigmoid）；
            - a / node_logits：[N]（节点可疑度与其 logits，均不 detach；L_var 由 M5 基于 a 计算）。
        """
        # ---- 输入校验（v4：严格 dtype/shape/值域，快速失败）----
        if not isinstance(x, torch.Tensor) or x.dim() != 2 or x.shape[1] != self.in_dim:
            got = tuple(x.shape) if isinstance(x, torch.Tensor) else type(x).__name__
            raise ValueError(f"x must be (N,{self.in_dim}) tensor, got {got}")
        if not isinstance(edge_index, torch.Tensor) or edge_index.dtype != torch.long:
            raise ValueError(
                "edge_index must be a torch.long tensor, got "
                f"dtype={getattr(edge_index, 'dtype', type(edge_index).__name__)}"
            )
        if edge_index.dim() != 2 or edge_index.shape[0] != 2:
            raise ValueError(f"edge_index must be [2,E] long, got shape={tuple(edge_index.shape)}")
        n_edges = int(edge_index.shape[1])
        validate_edge_types(edge_type, self.num_relations, n_edges=n_edges)
        n_nodes = int(x.shape[0])
        if batch is not None and (
            not isinstance(batch, torch.Tensor) or batch.dtype != torch.long
            or batch.dim() != 1 or batch.numel() != n_nodes
        ):
            raise ValueError(
                "batch must be a 1-D torch.long tensor of length N (PyG semantics), "
                f"got dtype={getattr(batch, 'dtype', type(batch).__name__)} "
                f"shape={tuple(batch.shape) if isinstance(batch, torch.Tensor) else None}"
            )

        # ---- 两层消息传递（第二层输出记为 h2 = h_v^(L)）----
        if self.conv_type == "rgcn":
            h1 = F.relu(self.conv1(x, edge_index, edge_type))
            h1 = F.dropout(h1, p=self.dropout, training=self.training)
            h2 = F.relu(self.conv2(h1, edge_index, edge_type))
        else:  # gcn：edge_type 已被校验但本分支不使用
            h1 = F.relu(self.conv1(x, edge_index))
            h1 = F.dropout(h1, p=self.dropout, training=self.training)
            h2 = F.relu(self.conv2(h1, edge_index))

        # ---- 节点可疑度（不 detach；M5 的 L_var 基于 a，node_logits 供解释/调试）----
        node_logits = self.a_head(h2).squeeze(-1)            # [N]
        a = torch.sigmoid(node_logits)                       # [N] in (0,1)

        # ---- 图级 Readout（h-based；单图 [D]，批图 [B,D]）----
        hg, alpha, _ = safe_readout(h2, node_logits, batch=batch,
                                    use_meanpool=self.use_meanpool, eps=EPS)
        z = self.cls(hg)                                     # 单图 [C] / 批图 [B, C]

        if return_intermediates:
            return {
                "z": z,
                "a": a,
                "node_logits": node_logits,
                "h1": h1,
                "h2": h2,
                "alpha": alpha,
                "hg": hg,
            }
        return z, a, node_logits


def _smoke() -> None:
    """随机数据 smoke test（开发计划 v4：独立验证入口，`python scripts/model.py`）。"""
    torch.manual_seed(0)
    N, D, R, C = 9, 128, 5, 7

    def make_graph(seed: int = 0):
        g = torch.Generator().manual_seed(seed)
        ei = torch.randint(0, N, (2, 12), generator=g)
        et = torch.randint(0, R, (12,), generator=g)
        return ei, et

    x = torch.randn(N, D)
    ei, et = make_graph()

    # 1) 基础组合：rgcn/gcn × attention/meanpool，前向+反向
    for conv in ("rgcn", "gcn"):
        for meanpool in (False, True):
            m = SSMHG(conv_type=conv, use_meanpool=meanpool)
            m.eval()
            z, a, nl = m(x, ei, et)
            assert z.shape == (C,), f"{conv}/{meanpool}: z {tuple(z.shape)}"
            assert a.shape == (N,) and nl.shape == (N,), f"{conv}/{meanpool}: a/nl"
            assert bool((a > 0).all() and (a < 1).all()), "a out of (0,1)"
            assert bool(torch.isfinite(z).all() and torch.isfinite(a).all()
                        and torch.isfinite(nl).all()), "non-finite output"
            m.train()
            z2, a2, _ = m(x, ei, et)
            (z2.sum() + a2.sum()).backward()
            assert all(
                p.grad is not None and bool(torch.isfinite(p.grad).all())
                for p in m.parameters() if p.requires_grad
            ), f"{conv}/{meanpool}: missing/NaN grad"
            m.zero_grad()
            print(f"[smoke] conv={conv} meanpool={meanpool}: shapes+backward ok")

    # 2) num_bases 5/4
    for bases in (5, 4):
        m = SSMHG(num_bases=bases).eval()
        z, a, _ = m(x, ei, et)
        assert z.shape == (C,) and a.shape == (N,)
        print(f"[smoke] num_bases={bases}: ok")

    # 3) Readout 硬约束：hg == h2-based；≠ x-based；改边后 z 变化
    m = SSMHG().eval()
    out = m(x, ei, et, return_intermediates=True)
    hg, h2, alpha = out["hg"], out["h2"], out["alpha"]
    assert torch.allclose(hg, (alpha.unsqueeze(-1) * h2).sum(0), atol=1e-5), \
        "hg != h2-based readout"
    wrong = (alpha.unsqueeze(-1) * x).sum(0)
    assert not torch.allclose(hg, wrong, atol=1e-3), \
        "hg equals x-based readout — propagation not used"
    z0 = out["z"]
    keep = torch.arange(ei.shape[1] - 1)          # 删除最后一条边
    zp, _, _ = m(x, ei[:, keep], et[keep])
    assert not torch.allclose(z0, zp, atol=1e-4), "edge perturbation did not change z"
    print("[smoke] readout is h2-based + edge perturbation changes z: ok")

    # 4) 极端图：单节点空边 / 多节点空边 / 纯自环孤立 / 重复边
    cases = [
        ("single-node no-edge",
         torch.randn(1, D), torch.empty((2, 0), dtype=torch.long),
         torch.empty(0, dtype=torch.long)),
        ("multi-node no-edge",
         torch.randn(5, D), torch.empty((2, 0), dtype=torch.long),
         torch.empty(0, dtype=torch.long)),
        ("isolated (self-loops)",
         torch.randn(5, D), torch.arange(5, dtype=torch.long).repeat(2, 1),
         torch.zeros(5, dtype=torch.long)),
        ("duplicate edges",
         torch.randn(4, D),
         torch.tensor([[0, 0, 1, 1, 0], [1, 2, 2, 1, 2]]),
         torch.tensor([0, 0, 1, 3, 4])),
    ]
    for name, xx, eei, eet in cases:
        mm = SSMHG().eval()
        zz, aa, _ = mm(xx, eei, eet)
        assert zz.shape == (C,) and aa.shape == (xx.shape[0],)
        assert bool(torch.isfinite(zz).all() and torch.isfinite(aa).all())
        print(f"[smoke] {name}: ok")

    # 5) 越界/非法输入应快速失败
    def expect_error(fn, substr: str):
        try:
            fn()
        except (ValueError, AssertionError) as exc:
            assert substr.lower() in str(exc).lower(), f"msg mismatch: {exc}"
            return
        raise AssertionError(f"expected error containing {substr!r}")

    m = SSMHG().eval()
    expect_error(lambda: SSMHG(conv_type="gat"), "conv_type")
    expect_error(lambda: SSMHG(num_bases=6), "num_bases")
    expect_error(lambda: SSMHG(num_bases=0), "num_bases")
    expect_error(lambda: m(x[:, :64], ei, et), "x must be")
    expect_error(lambda: m(x, ei.float(), et), "edge_index must be")
    expect_error(lambda: m(x, ei, et.float()), "edge_type must be")
    et_bad = et.clone(); et_bad[0] = R          # 越界
    expect_error(lambda: m(x, ei, et_bad), "out of range")
    print("[smoke] invalid inputs rejected: ok")

    # 6) 批图 vs 单图等价（按图归一化）
    xb = torch.randn(5, D)
    eib = torch.tensor([[0, 2, 3], [1, 3, 4]])   # 图A:0-1；图B:2-3-4（全局节点号）
    etb = torch.tensor([0, 0, 3])
    bch = torch.tensor([0, 0, 1, 1, 1])
    mb = SSMHG().eval()
    zb, ab, _ = mb(xb, eib, etb, batch=bch)
    assert zb.shape == (2, C) and ab.shape == (5,), (zb.shape, ab.shape)
    # 逐图前向等价：A=xb[0:2]，边(0,1)；B=xb[2:5]，边(0,1),(1,2) 局部
    za, _, _ = mb(xb[0:2], torch.tensor([[0], [1]]), torch.tensor([0]))
    zbb, _, _ = mb(xb[2:5], torch.tensor([[0, 1], [1, 2]]), torch.tensor([0, 3]))
    assert torch.allclose(zb[0], za, atol=1e-5) and torch.allclose(zb[1], zbb, atol=1e-5), \
        "batch graph output != per-graph forward"
    print("[smoke] batch == per-graph (per-graph normalization): ok")

    print("[smoke] ALL PASSED")


if __name__ == "__main__":
    _smoke()
