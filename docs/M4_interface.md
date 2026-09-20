# M4 接口规范（scripts/model.py）

> 依据：论文开发手册第 9 章 + 开发计划 v4（2026-09-07）。
> 本文件只描述 `scripts/model.py` 对外接口与 M5 使用约定，不含论文协议扩展。
> 运行环境：conda base，`torch 2.0.1+cu118`（GPU；无 CUDA 时自动回退 CPU，行为一致）、`torch_geometric 2.7.0`。

## 1. 文件位置与依赖

- 实现：`SSM-HG/scripts/model.py`（唯一实现文件；另含纯函数 helper）。
- 测试：`SSM-HG/tests/test_model_smoke.py`（pytest / 可直接运行）。
- 依赖：`torch`、`torch_geometric.nn.{RGCNConv, GCNConv}`。不依赖 `torch_scatter`
  （自带 `_scatter_add` 用 `index_add_` 实现）。
- 运行：`python scripts/model.py`（自带随机数据 smoke test）。

## 2. 关系编号（固定，手册 7.7）

| 编号 | 关系 |
|---:|---|
| 0 | CFG_FLOW |
| 1 | AST_PARENT |
| 2 | AST_PARENT_SAME |
| 3 | DFG_DEP |
| 4 | CALLBACK_RISK |

`edge_type` 值域必须为 `[0, num_relations)`（`num_relations=5`）。

## 3. 输入契约

| 输入 | 形状/类型 | 来源 | 说明 |
| --- | --- | --- | --- |
| `x` | `[N, 128]` float | **`model.NodeFuser`**（输入为 M5 `load_graph` 的通道字典） | `x = NodeFuser(channels)`；`channels` 固定序 `(cb_func, cb_node, type_id, struct, sv)`，由 `_feat.pt`（schema v2）+ `_cb.pt` 组合。`_pyg.pt["x"]`（N×1 占位）**不使用、不回写**。置零类操作只能在 `NodeFuser` 的融合 Linear **之前**（见 `docs/M3_frontend_design.md` §3.2.1）。 |
| `edge_index` | `[2, E]` long | M5 加载 `*_pyg.pt` | 有向边（源→目标）。 |
| `edge_type` | `[E]` long | M5 加载 `*_pyg.pt` | 值域 `[0,5)`；GCN 分支忽略但不跳过校验。 |
| `batch`（可选） | `[N]` long | M5 DataLoader | PyG 语义：`batch[i]` = 节点 i 所属图编号，0 起连续。`None` = 单图。 |

## 4. 输出契约

单图（`batch=None`）：

```python
z, a, node_logits = model(x, edge_index, edge_type)
```

- `z`：`[C]`，图级 logits（**未 sigmoid**）。`C = num_classes`：主实验 **7**；
  `--head binary` 臂（`decisions.md` §31）为 **1**（单头「有没有漏洞」）——
  此时 `a` / `node_logits` / 全部主干张量与非输出头宽无关，**逐位不变**（机检于 `tests/test_binary_arm.py`）。
- `a`：`[N]`，节点可疑度 `sigmoid(node_logits)`，位于 `(0,1)`。
- `node_logits`：`[N]`，`a_head(h_v^(L))`（未 sigmoid），供 M5 的梯度显著性、解释分析。

批图（`batch` 给定）：`z` 为 `[B, C]`（主实验 `[B,7]`，`--head binary` 为 `[B,1]`）；
`a`/`node_logits` 仍为全部节点 `[ΣN]`；
Readout 按图归一化（每图独立 `denom`，见 `safe_readout`）。

调试（`return_intermediates=True`）返回字典：

```python
out = model(x, edge_index, edge_type, return_intermediates=True)
# 键：z, a, node_logits, h1, h2, alpha, hg
```

- `h1` / `h2`：第一 / 第二层传播后节点表示（`h2` = `h_v^(L)`）；
- `alpha`：节点注意力权重（单图归一化后和为 1）；
- `hg`：图级表示（单图 `[128]` / 批图 `[B,128]`）。

## 5. SSMHG 构造参数

```python
SSMHG(in_dim=128, hid=128, num_relations=5, num_bases=5,
      num_classes=7, dropout=0.3, conv_type="rgcn", use_meanpool=False)
```

- 主模型（默认）：RGCN 两层、`num_bases=5`（= 关系数）、h-based attention Readout。
- `num_classes`：由 `train.py --head` 决定（`multi`→7、`binary`→1，唯一事实来源是
  `metrics.head_num_classes`）。**`evaluate.py` / `diagnose.py` 必须从 checkpoint 的
  `config["derived"]` 回读**，不得使用模块常量——否则二分类臂的 `Linear(64,1)` 与
  `Linear(64,7)` 状态字典不匹配。
- `conv_type`：仅 `"rgcn"` / `"gcn"`。`"gat"` 抛 `ValueError`（普通 GAT 无法表达关系感知，
  不提供伪对齐消融；如需可另行实现 RGAT）。
- `num_bases`：必须满足 `1 <= num_bases <= num_relations`；`4` 仅作消融。
- `use_meanpool=True`：仅把 Readout 换成 `h.mean(0)`（单图）或逐图均值，不改传播与 `a`。
- 输入校验（forward 入口，快速失败）：`x` 为 `[N, in_dim]`；`edge_index` long 且 `[2,E]`；
  `edge_type` long 且长度 `=E`、非空时值域 `[0, num_relations)`；`batch` long 一维长 `N`。

## 6. Readout（大纲 4.4.1）

```
node_logits = a_head(h2);  a = sigmoid(node_logits)
单图： alpha = a / (a.sum() + 1e-6)
      hg    = (alpha.unsqueeze(-1) * h2).sum(0)     # 用 h2=h_v^(L)，绝不用输入 x
批图： denom = scatter_add(a, batch)                # 每图各自分母
      alpha = a / (denom[batch] + 1e-6)
      hg    = scatter_add(alpha.unsqueeze(-1) * h2, batch)   # [B, 128]
z = cls(hg)   # 128 -> 64 -> 7（批图为 [B,7]）
```

## 7. 纯函数 helper（M5 可直接 import）

### `validate_edge_types(edge_type, num_relations, n_edges=None) -> int`

校验 dtype / 长度 / 值域，返回边数 `E`。

### `apply_edge_mask(edge_index, edge_type, mask) -> (edge_index_masked, edge_type_masked)`

布尔 mask 同步过滤边，**不含随机逻辑**。M5 的 DropEdge 用法：

```python
from model import apply_edge_mask
keep = torch.rand(E, device=x.device) >= drop_prob     # 训练期
ei, et = apply_edge_mask(edge_index, edge_type, keep)
z, a, nl = model(x, ei, et)                             # 验证/推理不调用
```

### `safe_readout(h, node_logits, batch=None, use_meanpool=False, eps=1e-6) -> (hg, alpha, a)`

图级 Readout（含单图/批图、attention/meanpool），内部 `a = sigmoid(node_logits)`。

## 8. 空边 / 孤立节点

已在本机 PyG 2.7.0 实测（2026-09-07）：`RGCNConv(root_weight=True)` 与
`GCNConv(add_self_loops=True)` 对 `E=0` 空边、纯自环、孤立节点均输出有限值，
**无需自定义 linear_root fallback**（官方实现即受控路径）。若升级 PyG，请回归
`tests/test_model_smoke.py` 的 `test_empty_edges_*` / `test_isolated_self_loops`。

## 9. 梯度与数值稳定性

- `node_logits`/`a`/`h2` 均**不 detach**；`z.sum().backward()` 后各参数梯度非空且有限。
- 检查中间 `h2` 梯度时先 `h2.retain_grad()`（测试见 `test_gradient_flows_no_detach`）。
- `alpha` 分母恒加 `eps=1e-6`；极端 logits（饱和到 0/1）只产生有限输出，无 NaN/Inf。
- `a_v` 若长期塌缩为常数（`score_std < 0.05`，大纲 `改II` 日志字段名），由 M5 的 `L_var` 处理，模型不改公式。

## 10. M5 归属（本文件不实现）

| 功能 | 归属 |
| --- | --- |
| 加载 `*_pyg.pt`（结构）+ `*_feat.pt`（schema v2 通道字典）+ `*_cb.pt`（行对齐）并断言通道契约/哈希 | `dataset.py`（`load_graph`；不再有 `_feat_no-prior.pt` 变体文件，2026-09-12 前端化退役） |
| 标签匹配、边级消融（`--drop-edges`/`--drop-ast`＝删 relation 1+2，白名单校验） | `dataset.py` |
| 通道融合（Embedding+MLP → `h_v^(0)`，128 维） | `model.NodeFuser`（前端化后；`x = fuser(channels)`） |
| 批图 DataLoader（`batch` 向量） | `dataset.py`/`train.py` |
| 先验/结构 dropout（训练期逐图 Bernoulli(p)，**p=丢弃率**（2026-09-16 统一语义，见手册 §8.6；`sample_dropout_masks` 采样后传入 `NodeFuser`；eval 不置零） | `train.py` + `model.NodeFuser` |
| DropEdge（训练期，用 `apply_edge_mask`；eval 不丢边） | `train.py` |
| BCEWithLogitsLoss + `L_var = max(0, 0.1 - std(a))`（基于 `a`，非 logits；按图分组 population std） | `train.py` |
| `score_mean`/`score_std` 日志、早停（验证集 micro-F1） | `train.py` |
| 阈值双报告、节点排序/梯度显著性（用 `node_logits`） | `evaluate.py` |
| `config.json`：conv_type/num_relations/num_bases/hidden_dim/dropout/use_meanpool/AblationConfig/… | `train.py` |

## 11. 运行验证

```bash
cd /home/saumarez/projects/deep-learning/SSM-HG
python scripts/model.py                  # 随机数据 smoke test
python -m pytest tests/test_model_smoke.py -q   # 22 个用例
python tests/test_model_smoke.py         # 无 pytest 也可独立运行
```
