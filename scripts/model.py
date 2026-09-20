#!/usr/bin/env python3
"""M4：前端通道融合（NodeFuser）+ RGCN/GCN 两层消息传递 + 节点可疑度 + 图级 Readout
（大纲 4.3.1/4.3.3/4.3.4/4.4，手册第 9 章 / 开发计划 v4）。

契约（与 M5 dataset/train 对齐，2026-09-12 前端化后）：
  - **前端 `NodeFuser`**（本文件）：接收 `dataset.load_graph` 返回的**通道字典**
    `{cb_func, cb_node, type_id, struct, sv}` → 输出 `h_v^(0)` ∈ R^{N×128}（与大纲 4.4 的 d=128、
    M4 原有接口**完全一致**，对内是内蕊置换；设计稿 `docs/M3_frontend_design.md` §3.2）。
    类型嵌入自此**可学习**（4.3.1）；结构与先验 dropout 在 `NodeFuser` 内实现（4.3.4/4.1.4），
    **置零只能发生在融合 Linear 之前**（R4；`proj` 之后任何掩码都无效），有逐位相等单测把守。
  - 输入 x 为 `NodeFuser` 输出或等价 128 维张量；`_pyg.pt` 只提供 edge_index/edge_type 与元数据，
    `_pyg.pt["x"]`（N×1 占位）不被使用、也不回写；`_feat.pt` 只存三通道（不再含融合结果）。
  - 关系编号固定（手册 7.7）：0=CFG_FLOW, 1=AST_PARENT, 2=AST_PARENT_SAME, 3=DFG_DEP, 4=CALLBACK_RISK。
  - 单图 forward(x, edge_index, edge_type) -> (z[num_classes], a[N], node_logits[N])；
    batch 图 forward(..., batch=[N]) -> z[B, num_classes]，a/node_logits 仍按节点返回；Readout 按图归一化。
  - return_intermediates=True 时返回 dict：{z,a,node_logits,h1,h2,h_layers,alpha,hg}，供调试与单测。
  - Readout 使用**末层**传播结果 h2（= h_v^(L)），绝不用输入 x（曾为易错点，验收见 tests）。
  - 层数 L 可配（`num_layers` ∈ {1,2,3}，默认 2 = 正典；大纲 5.4.1 第 13 项）。
    **L=2 的 state_dict 键名与旧版逐字相同**（故不用 `nn.ModuleList`），既有 `best.pt` 全部可加载。
  - conv_type 仅 "rgcn"/"gcn"：GCN 忽略 edge_type（非关系感知消融基线）；普通 GAT 不提供。
  - num_bases 默认 = num_relations(=5)；num_bases=4 仅作消融。
  - DropEdge / L_var / 训练日志均属 M5（train.py）；本文件提供纯工具 apply_edge_mask（M5 同步过滤边用）
    与 `sample_dropout_masks`（逐图正则掩码采样），不含训练循环。

空边与孤立节点（已在本机 PyG 2.7.0 实测验证，2026-09-07）：
  - RGCNConv(root_weight=True) 与 GCNConv(add_self_loops=True) 对 E=0 空边、纯自环、孤立节点
    均正常输出有限值——官方实现即受控路径，无需自定义 linear_root fallback；
    若将来升级 PyG 导致行为变化，回归入口在 tests/test_model_smoke.py 的空边用例。
"""

from __future__ import annotations

from dataclasses import dataclass

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
EPS = 1e-6          # attention 归一化分母补护（大纲 4.4.1 的 ε）
HID_DIM = 128       # 手册 9.1：隐藏维度 d=128（与 M3 的 h_v^(0) 维度一致）

# ---------------------------------------------------------------------------
# 前端（NodeFuser）：通道字典 → h_v^(0)。设计稿 docs/M3_frontend_design.md §3.2（R1–R11/Q1–Q9）
# ---------------------------------------------------------------------------
FUSER_INIT_SEED = 20260905   # ★ 仅控初始化，**独立于划分种子与训练种子**（R6/Q8；沿用旧 M3 的 SEED）
TYPE_EMB_DIM = 64            # 类型嵌入维度（大纲 4.3.1）
CHANNEL_ORDER = ("cb_func", "cb_node", "type_id", "struct", "sv")   # 固定拼接序（锁死）
# 结构特征 18 项 → 四组（大纲改II 4.3.3）。列布局 = 可见性4 + 布尔14 + 外呼方式5 + 位置1 + IR 类别 N
STRUCT_GROUP_SETS = {
    "all": {"base", "sem", "cb", "pos"},
    "base": {"base"},
    "base+sem": {"base", "sem"},
}


def struct_group_keep_mask(ir_categories_len: int, feat_groups: str = "all") -> list[bool]:
    """结构特征各列是否保留的布尔掩码（未选中组置 0；列宽不变）。

    feat_groups ∈ {all, base, base+sem}，对应大纲改II 4.3.3 的 (c)(a)(b) 三设置。
    2026-09-12 前端化：从 M3 移入本文件（特征级消融全部在模型侧做，零重跑）。
    """
    groups = (
        ["base"] * 4                                 # 1 函数可见性
        + ["base"] * 7 + ["sem"] * 4 + ["cb"] * 3    # 2-11,13；14-16（#12 不在本段）
        + ["sem"] * 5                                # 12 外呼方式 one-hot
        + ["pos"]                                    # 17 归一化位置
        + ["pos"] * int(ir_categories_len)           # 18 IR 类别 one-hot
    )
    allowed = STRUCT_GROUP_SETS.get(feat_groups, STRUCT_GROUP_SETS["all"])
    return [g in allowed for g in groups]


@dataclass
class AblationConfig:
    """特征级**确定性消融**（配置层，R1）：train/eval 行为一致、无随机、进 config.json。

    - `ablate_sv=True`：`s_v` 通道恒零（原 `--no-prior` / `_feat_no-prior.pt`，现已退役）；
    - `feat_groups`：结构特征分组（未选组列置零，列宽不变）；
    - `cb_channels`：参与拼接的 CodeBERT 通道子集（默认两通道；消融时影响 `proj` 输入维度）。
    ★ 与训练期正则（`prior_dropout`/`struct_dropout`）**正交**：后者仅训练期、逐图随机、eval 关闭。
    """
    ablate_sv: bool = False
    feat_groups: str = "all"
    cb_channels: tuple[str, ...] = ("cb_func", "cb_node")


class NodeFuser(nn.Module):
    """通道字典 → h_v^{(0)} ∈ R^{N×128}（大纲 4.3.1/4.3.3/4.3.4；设计稿 §3.2）。

    结构与初始化沿用原冻结投影（R6，单一变量＝可学习性）：
      `type_emb = nn.Embedding(9, 64)`；`proj = nn.Linear(768*len(cb_channels) + 64 + D_struct + 1, 128)`，
      均用 PyTorch 默认初始化分布；`init_seed` 控制初始化 RNG，独立于划分/训练种子。
    ★ **置零的唯一合法位置**：`proj` 之前（`cat` 之前或按列段乘掩码）。`proj` 之后禁止任何掩码/置零（R4）。
    ★ 模型内不做任何数据统计（R9）：无 BatchNorm、无 batch 级标准化；`s_v` 归一化在数据侧（M1）。
    """

    def __init__(self, d_struct: int, struct_layout: dict[str, int] | None = None,
                 ablate: AblationConfig | None = None, n_roles: int = 9,
                 type_dim: int = TYPE_EMB_DIM, hidden: int = HID_DIM,
                 prior_dropout: float = 0.2, struct_dropout: float = 0.2,
                 init_seed: int = FUSER_INIT_SEED):
        super().__init__()
        self.ablate = ablate or AblationConfig()
        self.d_struct = int(d_struct)
        self.struct_layout = dict(struct_layout or {})
        self.hidden = int(hidden)
        self.type_dim = int(type_dim)
        self.prior_dropout = float(prior_dropout)      # 正则层（仅训练期，外部采样掩码）
        self.struct_dropout = float(struct_dropout)
        self.cb_channels = tuple(self.ablate.cb_channels)
        self.init_seed = int(init_seed)
        # 结构分组掩码（确定性）；persistent=False：不进 state_dict（由 config 完全决定）
        ir_len = int(self.struct_layout.get("ir", 0))
        self.register_buffer(
            "struct_keep",
            torch.tensor(struct_group_keep_mask(ir_len, self.ablate.feat_groups), dtype=torch.float32),
            persistent=False)
        # ★ 初始化（顺序固定：Embedding → Linear；与旧冻结投影同分布，供 T2 冻结等价回归）
        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(self.init_seed)
            self.type_emb = nn.Embedding(n_roles, self.type_dim)
            self.proj = nn.Linear(
                768 * len(self.cb_channels) + self.type_dim + self.d_struct + 1, self.hidden)

    @property
    def in_dim(self) -> int:
        """融合 Linear 的输入维度（同时进 config，防错位）。"""
        return int(self.proj.in_features)

    def _expand(self, mask: torch.Tensor | None, batch: torch.Tensor | None,
                n: int) -> torch.Tensor | None:
        """(G,) 0/1 图级掩码 → (N,1) 系数列（batch=None 视为单图）。"""
        if mask is None:
            return None
        coef = mask.detach().to(dtype=torch.float32).reshape(-1)
        if batch is None:
            assert coef.numel() == 1, "单图掩码长度必须为 1"
            return coef.reshape(1, 1).expand(n, 1)
        assert coef.numel() == int(batch.max()) + 1, "掩码长度必须等于图数 G"
        return coef[batch].reshape(n, 1)

    def forward(self, ch: dict[str, torch.Tensor], *, prior_mask: torch.Tensor | None = None,
                struct_mask: torch.Tensor | None = None,
                batch: torch.Tensor | None = None) -> torch.Tensor:
        """通道字典 → h_v^{(0)}。

        `prior_mask` / `struct_mask`：**(G,) 0/1 图级掩码**，仅训练期由 `sample_dropout_masks`
        逐图采样后传入；验证/推理传 None（不置零）。两者与 `AblationConfig` 共用**同一乘法原语**，
        使「恒零（配置）」与「随机置零（正则）」在 sv 上逐位同构（§5-T1 机器验证）。
        """
        sv = ch["sv"]
        struct = ch["struct"]
        n = int(sv.shape[0])
        # ① 配置层（确定性，train/eval 一致）
        if self.ablate.ablate_sv:
            sv = torch.zeros_like(sv)
        if self.ablate.feat_groups != "all":
            struct = struct * self.struct_keep.to(device=struct.device, dtype=struct.dtype)
        # ② 正则层（随机，仅训练期；掩码在 cat 之前作用）
        sv_coef = self._expand(prior_mask, batch, n)
        if sv_coef is not None:
            sv = sv * sv_coef
        st_coef = self._expand(struct_mask, batch, n)
        if st_coef is not None:
            struct = struct * st_coef
        # ③ 拼接（固定序）  ④ 融合 —— ★ proj 之后禁止任何掩码/置零
        x = torch.cat([ch[c] for c in self.cb_channels]
                      + [self.type_emb(ch["type_id"]), struct, sv], dim=1)
        return self.proj(x)


def sample_dropout_masks(n_graphs: int, *, prior_p: float, struct_p: float,
                         generator: torch.Generator | None = None) -> tuple[torch.Tensor, torch.Tensor]:
    """训练期逐图采样正则掩码（(G,) 0/1）——**必须按图独立**，调用方可用
    `seed + epoch + stable_graph_index` 构造 generator 以保可追溯。验证/测试不得调用本函数。

    **语义：`p` 是「丢弃率」（2026-09-16 修正，与大纲 4.1.4 / 手册 §8.6 的散文一致）。**
    返回的掩码是**乘性系数**（1=保留、0=整通道置零），故以 `p` 概率取 0、以 `1-p` 概率取 1：

    | `p` | 语义 |
    | --- | --- |
    | `0` | **关闭**该 dropout（掩码恒 1，不置零） |
    | `0.2`（默认） | 每个图以 **20%** 概率把该通道整幅置零 |
    | `1` | 每个图都置零（"全丢"）；**不要用它表示"关闭"** |

    ⚠ 与 `AblationConfig(ablate_sv=True)` 的区别：后者是**确定性**全零消融（train/eval 一致），
    与 `p=0`（随机正则**关闭**）**不是一回事**；两者在 `NodeFuser` 中共用同一乘法原语，
    但触发路径分离（配置层 vs 正则层），且只有正则层随 `training` 开关。

    ⚠ 历史（本次修正前）：实现为 `rand < p`，使 `p` 成了**保留率**——默认 0.2 实际置零 **80%** 的图，
    且 `p=0` 会**每图都置零**（等价于 `--ablate-sv`，使「关闭先验 Dropout」这一消融无法表达）。
    该口径下的全部结果已作废，归档于 `runs/prior_dropout80/`，见 `experiments/decisions.md` §26。
    """
    prior = (torch.rand(n_graphs, generator=generator) >= prior_p).to(torch.float32)
    struct = (torch.rand(n_graphs, generator=generator) >= struct_p).to(torch.float32)
    return prior, struct


def parameter_report(**modules: nn.Module) -> dict[str, int]:
    """参数量报告（R10）：如 `parameter_report(fuser=fuser, rgcn=model)` →
    `{fuser_params, fuser_learnable_params, rgcn_params, rgcn_learnable_params, total_params, total_learnable_params}`。
    448 样本下新增可学习参数是过拟合风险变量，必须与指标同表报告。
    """
    out: dict[str, int] = {}
    total = total_learn = 0
    for name, module in modules.items():
        params = list(module.parameters())
        p = sum(t.numel() for t in params)
        q = sum(t.numel() for t in params if t.requires_grad)
        out[f"{name}_params"] = p
        out[f"{name}_learnable_params"] = q
        total += p
        total_learn += q
    out["total_params"] = total
    out["total_learnable_params"] = total_learn
    return out


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
    """M4 主模型：L 层图消息传递 → 节点可疑度 a_v → 基于 h_v^(L) 的注意力 Readout → 图级 logits。

    公式（大纲 4.4.1 / 手册 9.2~9.3）：
      h_v^(l+1) = σ(W0 h_v^(l) + Σ_r Σ_{u∈N_r(v)} (1/c) W_r h_u^(l))   （RGCN，L 层，默认 2）
      node_logits_v = w^T h_v^(L)；a_v = σ(node_logits_v)
      α_v = a_v / (Σ_u a_u + ε)；h_G = Σ_v α_v h_v^(L)；z_G = MLP(h_G)
    先验 s_v 只经 M3 的 h_v^(0) 进入，本模型不显式使用（grep 不应命中 s_v/prior/m1）。
    训练期 DropEdge/先验 dropout/L_var 属 M5；本模型 forward 内不做随机丢边或先验置零。
    """

    def __init__(self, in_dim: int = HID_DIM, hid: int = HID_DIM, num_relations: int = 5,
                 num_bases: int = 5, num_classes: int = 7, dropout: float = 0.3,
                 conv_type: str = "rgcn", use_meanpool: bool = False, num_layers: int = 2):
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
        # 层数消融（大纲 5.4.1 第 13 项）：1 / 2 / 3，**默认 2 即正典**。
        # 上界 3 与手册 9.1 的两层设计一致，不引入更深堆叠（过平滑）。
        if not (1 <= num_layers <= 3):
            raise ValueError(f"num_layers must be in [1, 3], got {num_layers}")

        self.in_dim = int(in_dim)
        self.hid = int(hid)
        self.num_relations = int(num_relations)
        self.num_bases = int(num_bases)
        self.num_classes = int(num_classes)
        self.dropout = float(dropout)
        self.conv_type = conv_type
        self.use_meanpool = bool(use_meanpool)
        self.num_layers = int(num_layers)

        # 🔴 逐层用 `setattr(self, f"conv{l}", …)` 而**不用 `nn.ModuleList`**：
        # ModuleList 会把键名改成 `convs.0.*`，使全部已训练 `best.pt`（以及正典臂的
        # 逐位复现）加载失败。现有命名 `conv1.*` / `conv2.*` 必须原样保留。
        for layer in range(1, self.num_layers + 1):
            layer_in = self.in_dim if layer == 1 else self.hid
            setattr(self, f"conv{layer}", self._make_conv(layer_in, self.hid))
        # L=1 时**显式**保留 `conv2 = None`：`state_dict()` 跳过 None（不注册），
        # 同时让 `hasattr(model, "conv2")` 仍为真，避免下游按属性名取层时炸出 AttributeError。
        if self.num_layers < 2:
            self.conv2 = None
        if self.num_layers < 3:
            self.conv3 = None

        self.a_head = nn.Linear(hid, 1)                      # 节点可疑度 logits
        self.cls = nn.Sequential(nn.Linear(hid, 64), nn.ReLU(), nn.Linear(64, num_classes))

    def _make_conv(self, in_dim: int, out_dim: int) -> nn.Module:
        """建一层消息传递（RGCN 关系感知 / GCN 同构基线）。参数与旧版逐字相同。"""
        if self.conv_type == "rgcn":
            # root_weight=True：空边/孤立节点时仍保留节点自身变换项（PyG 2.7.0 官方行为）
            return RGCNConv(in_dim, out_dim, self.num_relations,
                            num_bases=self.num_bases, root_weight=True)
        # gcn：忽略 edge_type，同构基线（add_self_loops=True 保证孤立节点可更新）
        return GCNConv(in_dim, out_dim)

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

        # ---- L 层消息传递（末层输出记为 h2 = h_v^(L)）----
        # 算子顺序与旧版两层实现**逐字一致**：每层 `relu(conv_l(·))`，**非末层**接一次 dropout
        # （旧版即 `relu → dropout → relu`，即 dropout 只加在非末层）。故 L=2 时前向逐位不变。
        h = x
        h_layers: list[torch.Tensor] = []
        for layer in range(1, self.num_layers + 1):
            conv = getattr(self, f"conv{layer}")
            h = (conv(h, edge_index, edge_type) if self.conv_type == "rgcn"   # gcn 分支不用 edge_type
                 else conv(h, edge_index))
            h = F.relu(h)
            if layer < self.num_layers:
                h = F.dropout(h, p=self.dropout, training=self.training)
            h_layers.append(h)
        # h1 = 首层输出（旧版语义：**已过 dropout**）、h2 = 末层输出 = h_v^(L)（Readout 用它）。
        # L=1 时两者是**同一个张量**（单层没有"非末层"，故无 dropout）。
        h1, h2 = h_layers[0], h_layers[-1]

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
                "h_layers": h_layers,     # 逐层输出（长度 = num_layers；L=2 时 = [h1, h2]）
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
