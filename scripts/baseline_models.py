#!/usr/bin/env python3
"""5.3 三条论文基线的**模型定义**（纯 `nn.Module`，无 IO、可单测）。

| 类 | 来源 | 相对原文的改动 |
|---|---|---|
| `MVDHGRGCN` | `MVD-HG/contract_classification/contract_classification_model.py` **忠实副本** | `Linear(8→1)+Sigmoid` → `Linear(8→7)` 无 sigmoid |
| `EGFLNet` | `EGFL/Networks/egfl_net.py` 的 **PyTorch 等价改写** | `Dense(100→1)+sigmoid` → `Linear(100→7)` 无 sigmoid |
| `MandoHGT` | `MANDO-LLM/sco_models/model_hgt.py` 的 **PyG `HGTConv` 版** | `out_size 2→7`（CE→BCEWithLogits） |

三条基线一律**输出 logits**（不 sigmoid）——`BCEWithLogitsLoss` 的输入是 logits，
「何时变概率」只在推理侧一处决定（见 `baseline_common.infer_multilabel`）。
"""

from __future__ import annotations

import math

import torch
import torch.nn as nn
import torch.nn.functional as F


# ===========================================================================
# 一、MVD-HG（忠实复刻其 RGCN 4 层 + 逐合约均值池化）
# ===========================================================================
class MVDHGRGCN(nn.Module):
    """`contract_classification_model` 的等价实现。

    结构逐字照抄 `contract_classification_model.py:13-38`：
      `RGCNConv(300→64→32→16→8, num_relations=3)`，每层后 `Dropout(0.1)` 再 `ReLU`；
    池化照 `:40-56`：**逐 contract 节点均值 → 跨 contract 平均**。

    **改动只有一处**：末尾 `Linear(8→1)+Sigmoid` → `Linear(8→7)`（无 sigmoid）。
    它原本还把标签 `OR` 塌成 1 维（`:57-60`），那是「文件级二分类」的写法；
    我们保留 7 维标签，由 `BCEWithLogitsLoss` 逐类监督 —— 这是大纲 5.3 [411] 的要求。

    ⚠ `dropout` 保持它的 `config.dropout_pro=0.1`（不是正典的 0.3）：复现优先，
    该差异记入 `results.json::reconstruction_notes`。
    """

    def __init__(self, in_dim: int = 300, hidden=(64, 32, 16, 8),
                 num_relations: int = 3, num_classes: int = 7, dropout: float = 0.1):
        super().__init__()
        from torch_geometric.nn import RGCNConv
        dims = (in_dim, *hidden)
        self.convs = nn.ModuleList([
            RGCNConv(dims[i], dims[i + 1], num_relations) for i in range(len(hidden))])
        self.dropout = nn.Dropout(p=dropout)
        self.act = nn.ReLU()
        self.final_linear = nn.Linear(hidden[-1], num_classes)

    def encode(self, x, edge_index, edge_type):
        for conv in self.convs:
            x = conv(x, edge_index, edge_type)
            x = self.dropout(x)
            x = self.act(x)
        return x

    def forward(self, x, edge_index, edge_type, groups: list[list[torch.Tensor]]):
        """`groups[b]` = 第 b 个样本的**逐合约节点下标列表**（全局行号）。

        返回 `[B, num_classes]` logits。逐合约均值 → 跨合约平均（与它的 `:47-56` 同义）。
        """
        h = self.encode(x, edge_index, edge_type)
        vecs = []
        for g in groups:
            per_contract = [h[idx].mean(0) for idx in g if idx.numel() > 0]
            if not per_contract:
                per_contract = [h.new_zeros(h.shape[1])]
            vecs.append(torch.stack(per_contract, 0).mean(0))
        return self.final_linear(torch.stack(vecs, 0))


# ===========================================================================
# 二、EGFL（按论文重实现；其提交版 TF 代码无法直接运行）
# ===========================================================================
class _Swish(nn.Module):
    def forward(self, x):
        return x * torch.sigmoid(x)


class _GLU(nn.Module):
    def forward(self, x):
        a, b = x.chunk(2, dim=1)
        return a * torch.sigmoid(b)


class _FeedForward(nn.Module):
    """`egfl_net.py:242-278`：`Linear(d→d*4)+Swish+Drop → Linear(d*4→d)+Drop`。"""

    def __init__(self, dim: int, mult: int = 4, dropout: float = 0.0):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(dim, dim * mult), _Swish(), nn.Dropout(dropout),
            nn.Linear(dim * mult, dim), nn.Dropout(dropout))

    def forward(self, x):
        return self.net(x)


class _PreNorm(nn.Module):
    """`egfl_net.py:226-240`：先 LayerNorm 再作用 fn。"""

    def __init__(self, dim, fn):
        super().__init__()
        self.norm = nn.LayerNorm(dim)
        self.fn = fn

    def forward(self, x, **kw):
        return self.fn(self.norm(x), **kw)


class _Scale(nn.Module):
    """`egfl_net.py:210-224`：`fn(x) * scale`。"""

    def __init__(self, scale, fn):
        super().__init__()
        self.scale = scale
        self.fn = fn

    def forward(self, x, **kw):
        return self.fn(x, **kw) * self.scale


class _RelPosAttention(nn.Module):
    """`egfl_net.py:31-142` 的**相对位置多头注意力**（无 einops）。

    逐字对齐原文：
      `inner_dim = dim_head * heads * 4/5`（原文写的是**浮点** `512.0`，Keras 会报错；
      这里取 `int(...)` = 512）；`heads_eff = int(heads * 4/5)` = 8；
      `to_q: Linear(dim, inner, bias=False)`、`to_kv: Linear(dim, 2*inner, bias=False)`；
      `dots = q·k * scale`；`dist = clip(i-j, ±P) + P`；
      `pos = q · rel_emb(dist) * scale`；`attn = softmax(dots + pos)`；`to_out(attn·v)`。
      `scale = dim_head ** -0.5`。原文 `max_pos_emb=512` ⇒ 表长 `2P+1 = 1025`。

    🔴 **键维分块（唯一实现层面的偏离，数学上恒等）**：原文的 `dots` 是 `[B,h,L,L]`，
    在 `L=8192` 时单个 batch 就要 `8×8192²×4B = 2 GB`（原文默认 `SEQ_LEN=8000`，
    在那个规模下这份代码在任何 8 GB 卡上都跑不动）。这里按**键维**分块累加 softmax，
    峰值显存降为 `L × chunk`，**结果与整块算法逐位等价**（在线 softmax 的标准做法）。
    """

    def __init__(self, dim: int, heads: int = 10, dim_head: int = 64,
                 dropout: float = 0.0, max_pos_emb: int = 512, key_chunk: int = 512):
        super().__init__()
        self.heads = int(heads * 4 / 5)                     # 原文对 heads 也乘 4/5
        self.dim_head = dim_head
        self.inner_dim = int(dim_head * heads * 4 / 5)
        self.scale = dim_head ** -0.5
        self.max_pos_emb = max_pos_emb
        self.key_chunk = key_chunk
        self.to_q = nn.Linear(dim, self.inner_dim, bias=False)
        self.to_kv = nn.Linear(dim, self.inner_dim * 2, bias=False)
        self.to_out = nn.Linear(self.inner_dim, dim)
        self.rel_pos_emb = nn.Embedding(2 * max_pos_emb + 1, dim_head)
        self.dropout = nn.Dropout(dropout)

    def _bias(self, q, dist):
        """`dist[B,h,L,R]` → 位置偏置 `[B,h,L,R]`（`q·rel_emb(dist) * scale`）。

        🔴 **峰值显存就是这里**：`rel_pos_emb(dist)` 会实体化 `[B,h,L,R,dim_head]`。
        原实现（整块、`key_chunk` = 全序列）在 `L=8192, B=4` 下要 8.6e9 float = 34 GB
        ——这正是本模型**在 8 GB 卡上跑 L=8192 时第二个 OOM 点**（第一个是 `dots`）。
        故 `R` 由 `forward` 按显存预算自适应收缩（见那里的注释）。
        """
        w = self.rel_pos_emb(dist)                          # [B,h,L,R,dim_head]
        return torch.einsum("bhld,bhlrd->bhlr", q, w) * self.scale

    def _chunk_for(self, B: int, L: int, budget_mb: int = 192) -> int:
        """按显存预算选**键块**大小：让 `[B,h,L,C,dim_head]` 的实体化不超过 `budget_mb`。

        这块张量是唯一随 `L·C` 增长的中介，`dots`/`acc` 都比它小一个量级。
        取 8 的下界避免块数爆炸；上界 `key_chunk`（构造参数）保留原实现语义。
        """
        per = max(1, B * self.heads * L * self.dim_head * 4)      # 单列键的字节数
        c = int(budget_mb * 1024 * 1024 / per)
        return max(8, min(self.key_chunk, c))

    def forward(self, x):
        B, L, _ = x.shape
        q = self.to_q(x).view(B, L, self.heads, self.dim_head).transpose(1, 2)
        kv = self.to_kv(x).view(B, L, 2, self.heads, self.dim_head).permute(2, 0, 3, 1, 4)
        k, v = kv[0], kv[1]                                 # [B,h,L,dh]

        seq = torch.arange(L, device=x.device)
        base = (seq[:, None] - seq[None, :]).clamp(-self.max_pos_emb, self.max_pos_emb)
        base = base + self.max_pos_emb                      # [L,L] ∈ [0, 2P]

        # 在线 softmax：逐键块累加（数学恒等，显存 O(L·chunk)）
        m = torch.full((B, self.heads, L), -float("inf"), device=x.device, dtype=q.dtype)
        denom = torch.zeros_like(m)
        acc = torch.zeros(B, self.heads, L, self.dim_head, device=x.device, dtype=q.dtype)
        chunk = self._chunk_for(B, L)
        for s in range(0, L, chunk):
            e = min(s + chunk, L)
            dots = torch.einsum("bhid,bhjd->bhij", q, k[:, :, s:e]) * self.scale
            dots = dots + self._bias(q, base[:, s:e].unsqueeze(0).unsqueeze(0)
                                     .expand(B, self.heads, L, e - s))
            m_new = torch.maximum(m, dots.amax(-1))
            p = torch.exp(dots - m_new.unsqueeze(-1))
            corr = torch.exp(m - m_new)
            acc = acc * corr.unsqueeze(-1) + torch.einsum("bhij,bhjd->bhid", p, v[:, :, s:e])
            denom = denom * corr + p.sum(-1)
            m = m_new
        out = acc / denom.clamp_min(1e-12).unsqueeze(-1)
        out = out.transpose(1, 2).reshape(B, L, self.inner_dim)
        return self.dropout(self.to_out(out))


class _ConformerConvModule(nn.Module):
    """`egfl_net.py:304-361`。

    🔴 **照抄而非「修好」**：原文的 `DepthwiseLayer`（深度卷积）**整段被注释掉了**
    （`:346-349`），实际只剩「LN → 1×1 Conv(2·inner) → GLU → BN → Swish → 1×1 Conv(dim) → Drop」。
    `Rearrange("b n c -> b c n")` 配 `kernel_size=1` 等价于对通道做逐位置 MLP。
    我们复刻这个**实际形态**——恢复 depthwise conv 就不是复现而是发明了。
    """

    def __init__(self, dim: int, expansion_factor: int = 2, dropout: float = 0.0,
                 kernel_size: int = 31):
        super().__init__()
        inner = dim * expansion_factor
        self.norm = nn.LayerNorm(dim)
        self.expand = nn.Conv1d(dim, inner * 2, 1)
        self.glu = _GLU()
        self.bn = nn.BatchNorm1d(inner)
        self.act = _Swish()
        self.project = nn.Conv1d(inner, dim, 1)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):                                   # x: [B,L,C]
        y = self.norm(x).transpose(1, 2)                    # → [B,C,L]
        y = self.glu(self.expand(y))
        y = self.bn(y)
        y = self.act(y)
        y = self.project(y)
        return self.dropout(y).transpose(1, 2)


class _ConformerBlock(nn.Module):
    """`egfl_net.py:364-442`：`ff1→attn→conv→ff2`，`ff1/ff2/attn` 带残差、**`conv` 无残差**。"""

    def __init__(self, dim: int, dim_head: int = 64, heads: int = 10, ff_mult: int = 4,
                 conv_expansion_factor: int = 2, conv_kernel_size: int = 31,
                 dropout: float = 0.0):
        super().__init__()
        self.ff1 = _Scale(0.5, _PreNorm(dim, _FeedForward(dim, ff_mult, dropout)))
        self.attn = _PreNorm(dim, _RelPosAttention(dim, heads, dim_head, dropout))
        self.conv = _ConformerConvModule(dim, conv_expansion_factor, dropout, conv_kernel_size)
        self.ff2 = _Scale(0.5, _PreNorm(dim, _FeedForward(dim, ff_mult, dropout)))
        self.post_norm = nn.LayerNorm(dim)

    def forward(self, x):
        x = self.ff1(x) + x
        x = self.attn(x) + x
        x = self.conv(x)                                    # ★ 原文此处无残差
        x = self.ff2(x) + x
        return self.post_norm(x)


class EGFLNet(nn.Module):
    """`egfl_net.py:490-525` 的 PyTorch 版，**唯一改动 = 输出头**。

    序列分支：`Embedding(V,256) → Conv1d(256→200,k=5,relu,pad=2) → Dropout(0.5)
              → ConformerBlock(256) → 时间维 mean(=GAP) → Dense(256,relu)+门控`
    图分支：`Dense(256,relu)+门控`（输入是**外部预计算的 256 维**，见下）
    融合：`cat(512) → Linear(100,relu) → Dropout(0.5) → Linear(7)`

    ⚠ **两处与原代码的必要偏离**（都记入 `results.json::reconstruction_notes`）：
      ① 原代码把 `CNN_LAYER_DIM=200` 的卷积输出直接送进 `ConformerBlock(EMBEDDING_LAYER_DIM=256)`，
         残差处维度冲突 —— **这份提交版代码按原样跑不起来**（Keras 会抛 Dimensions must be equal）。
         我们让 Conformer 全程跑在 256 维（与论文「维度 200」的写法一致的是另一条 `--egfl-no-proj` 路线）。
      ② 图分支的 256 维输入是**作者未开源的 `cfg_graph`**（`Weights_CFG_SimOp/` 空目录），
         本仓按论文重建（`baseline_egfl_build.py`：块内 opcode 词向量平均 → BFS 展平）。
    """

    def __init__(self, vocab_size: int = 1000, emb_dim: int = 256, cnn_dim: int = 200,
                 dim_head: int = 64, heads: int = 10, ff_mult: int = 4,
                 graph_dim: int = 256, hidden: int = 100, dropout: float = 0.5,
                 num_classes: int = 7):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, emb_dim, padding_idx=0)
        self.conv1 = nn.Conv1d(emb_dim, cnn_dim, kernel_size=5, padding=2)
        self.conv_proj = nn.Linear(cnn_dim, emb_dim)         # 见 docstring 偏离 ①
        self.emb_dropout = nn.Dropout(dropout)
        self.conformer = _ConformerBlock(emb_dim, dim_head, heads, ff_mult, dropout=dropout)

        self.graph_fc = nn.Linear(graph_dim, emb_dim)
        self.graph_gate = nn.Linear(emb_dim, 1)

        self.seq_fc = nn.Linear(emb_dim, emb_dim)
        self.seq_gate = nn.Linear(emb_dim, 1)

        self.head = nn.Sequential(
            nn.Linear(emb_dim * 2, hidden), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(hidden, num_classes))

    def forward(self, tokens: torch.Tensor, gvec: torch.Tensor) -> torch.Tensor:
        """`tokens [B,L] long`（0=pad）、`gvec [B,256] float` → `[B,7]` logits。"""
        mask = (tokens != 0).unsqueeze(-1).to(torch.float32)          # [B,L,1]
        e = self.embedding(tokens)                                   # [B,L,256]
        y = F.relu(self.conv1(e.transpose(1, 2))).transpose(1, 2)    # [B,L,200]
        y = self.conv_proj(y)
        y = self.emb_dropout(y)
        y = self.conformer(y)
        # GlobalAveragePooling1D 的等价物：**只对非 pad 位置取平均**
        # （原文对 pad 也平均，那是它的实现细节；我们按有效长度平均，避免 padding 稀释表征。
        #  这条偏离同样记入 reconstruction_notes。）
        denom = mask.sum(1).clamp_min(1.0)
        seq_vec = (y * mask).sum(1) / denom                          # [B,256]

        s = F.relu(self.seq_fc(seq_vec)) * torch.sigmoid(self.seq_gate(seq_vec))
        g = F.relu(self.graph_fc(gvec)) * torch.sigmoid(self.graph_gate(gvec))
        return self.head(torch.cat([s, g], dim=1))


# ===========================================================================
# 三、MANDO-LLM（用 PyG 的 HGTConv 替代原 dgl 实现）
# ===========================================================================
class MandoHGT(nn.Module):
    """`model_hgt.py` 的 PyG 版（`HGTVulGraphClassifier`，`:435-630`）。

    与 dgl 原版的逐项对应：
      `HGTLayer` ⟷ `HGTConv` —— per-(srctype,etype,dsttype) 的 k/q/v 线性 ✓、
      `relation_att/relation_msg/relation_pri` ⟷ PyG 的 `k_rel/v_rel/p_rel` ✓、
      `edge_softmax(norm_by='dst')` ⟷ PyG 的按目标结点 softmax ✓、
      `multi_update_all(cross_reducer='mean')` ⟷ PyG 的 mean 聚合 ✓、
      `skip(α=sigmoid(skip)) + a_linear + LayerNorm` ⟷ PyG 的 `skip`/`out_lin` ✓。
    规模照它的默认值与实测 checkpoint：**2 层、hidden 128、heads 8**。

    合约级读数照 `:601-605`：**对全图节点隐层取均值** → `classify`。
    唯一改动 = `out_size 2→7`（CE → BCEWithLogits）。

    ⚠ **节点类型取 9 类语义角色**（`dataset.ROLE_NAMES`），不是 1 类。理由：MANDO-LLM 的
    「异构图 transformer」核心就是**每种节点类型独立的 K/Q/V**；只用 1 类会把它退化成
    「带 5 组关系参数的 RGCN + 逐关系 softmax」，丢掉该算子的本质。它的原图节点类型来自
    slither 的 CFG 节点种类，本仓最近似的现成类比物就是 `_feat.pt::type_id` 的 9 类角色。
    """

    def __init__(self, metadata, in_dim: int = 128, hidden: int = 128,
                 num_layers: int = 2, heads: int = 8, num_classes: int = 7,
                 dropout: float = 0.3):
        super().__init__()
        from torch_geometric.nn import HGTConv
        self.metadata = metadata
        self.node_types = list(metadata[0])
        self.adapt = nn.ModuleDict({nt: nn.Linear(in_dim, hidden) for nt in self.node_types})
        self.convs = nn.ModuleList([
            HGTConv(hidden, hidden, metadata, heads=heads) for _ in range(num_layers)])
        self.norms = nn.ModuleList([nn.LayerNorm(hidden) for _ in range(num_layers)])
        self.dropout = nn.Dropout(dropout)
        self.classify = nn.Linear(hidden, num_classes)

    def forward(self, x_dict, edge_index_dict, batch_index: torch.Tensor | None = None):
        """`batch_index[ΣN]` = 每个节点属于哪个图（`None` = 单图）。返回 `[B,7]` logits。

        🔴 **`batch_index` 的顺序契约**：必须与 `torch.cat([h[nt] for nt in node_types])`
        **同序** —— 即「先按节点类型分组、类型内再按图」，`x_dict[nt]` 的排布也必须是
        「该类型下 图0 的节点、图1 的节点、…」。这是异构批图的唯一正确拼法：
        每个类型各自连续编号，`edge_index_dict` 里各类型的下标也相应地加**该类型**的累计偏移
        （不是全局节点偏移——异构图的边索引是**类型内**下标）。
        """
        h = {nt: F.relu(self.adapt[nt](x_dict[nt])) for nt in self.node_types}
        for conv, norm in zip(self.convs, self.norms):
            h = conv(h, edge_index_dict)
            h = {nt: self.dropout(F.relu(norm(h[nt]))) for nt in self.node_types}
        # 合约向量 = 全图节点隐层均值（照 `:601-605` 的 `hiddens[node_list].mean(0)`）
        all_h = torch.cat([h[nt] for nt in self.node_types], dim=0)
        if batch_index is None:
            return self.classify(all_h.mean(0, keepdim=True))
        n_graphs = int(batch_index.max().item()) + 1
        acc = torch.zeros(n_graphs, all_h.shape[1], device=all_h.device, dtype=all_h.dtype)
        cnt = torch.zeros(n_graphs, 1, device=all_h.device, dtype=all_h.dtype)
        acc.index_add_(0, batch_index, all_h)
        cnt.index_add_(0, batch_index, torch.ones_like(all_h[:, :1]))
        return self.classify(acc / cnt.clamp_min(1.0))


__all__ = ["MVDHGRGCN", "EGFLNet", "MandoHGT"]
