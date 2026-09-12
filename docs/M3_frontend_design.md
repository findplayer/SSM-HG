# M3 前端化设计稿（P1 第 2 条，**已实施并验收，2026-09-12**）

> 状态：**已实施并验收（2026-09-12）**：R1–R11 + Q6–Q9 全部裁定完毕（均按推荐）。
> 实施结果：M3 全量 581 图 **41 s**（`_cb.pt` 复用、未加载 CodeBERT）；全库 581 图通道断言+哈希校验通过（15.7 s）；
> **T2 冻结等价回归逐位相等（maxdiff 0，5 图抽查）**；T1/T5 等 13 个新用例通过，`pytest tests/` **39 passed**；
> `NodeFuser` 参数量 **209,472**（`d_struct=30`）。**发现并已修复（2026-09-12 三轮）**：cb 函数级通道曾缺行
> **35195/93551（37.6%）** → 第一轮（alias+modifier 补登记）**2622 行（2.8%）** → 第二轮（老式继承构造函数别名）
> **2382 行（2.55%）** → 第三轮（三图 solc 0.8 风格 AST 兼容，R5）**2356 行（2.52%，覆盖率 97.48%）**；
> 残余**全部是** Slither 合成作用域 `slitherConstructor*`（2356 行，不可编码）。
> 另：第三轮刷新了库级结构统计（边 226476 → **226511**、DFG **146712**、CALLBACK_RISK **511/86**、M1 raw hits **21571**）。
> 见 `experiments/decisions.md` §15（§15.6/§15.7/§15.8）与 `docs/residual_gaps.md`。
> 实施前不得修改 `model.py` / `dataset.py` / `m3_build_features.py` /
> `论文开发手册.md` §8.x / `experiments/decisions.md` §4、§9.4 / 大纲 4.3.1、4.3.4。
> 触发：P1 裁决第 2 条「M3 前端化 (a)：Embedding+MLP 移入 `model.py`；`_feat.pt` 改存拼接前通道
> （规则向量 / 类型 id / s_v）；语义锁重定义为通道级哈希；先验 dropout 0.2 在模型内对 s_v 列置零」。
> 相关文件：`scripts/m3_build_features.py`、`scripts/dataset.py`、`scripts/model.py`、`docs/M4_interface.md`、
> `论文开发手册.md` §8.6–8.9 / §10.1、`experiments/decisions.md` §4 / §9.4。

## 0. 本轮裁定摘要（2026-09-12，已并入本稿；实施时逐条对照）

| # | 议题 | 裁定 | 落点 |
| - | --- | --- | --- |
| R1 | 特征消融前移模型侧 | **是**，但必须分两层：**确定性消融 = 配置**（train/eval 一致）/ **训练期 dropout = 正则**（仅 train）；两者正交、触发路径分离，**严禁混用** | §3.2、§4 |
| R2 | 文件级预生成变体 | `_feat_no-prior` / `_feat_grp-*` / `_feat_{variant}` **整套退役**（前端化的红利） | §2.2、§6 |
| R3 | 结构特征 dropout | **整通道（整列）置零、按图 Bernoulli(0.2)**，非 elementwise | §3.2 |
| R4 | 先验 dropout 的置零位置 | 必须在**融合 Linear 之前**（通道级）；融合之后置零**无效且禁止**；须有**无泄漏单测**（§5 T1） | §3.2、§5 |
| R5 | 旧 `_feat.pt` | **留档**，挪隔离目录（同 `random_snapshot/` 先例）；冻结-可学习对比改用 `--freeze-fuser`，不回头读旧文件 | §6.3 |
| R6 | 结构与初始化 | `Embedding(9,64) + Linear(D,128)` **沿用原冻结投影的结构与默认初始化分布**；单一变量＝可学习性；`--fuser-init-seed` **独立于划分/训练种子** | §3.2 |
| R7 | 通道哈希 | **逐通道 sha256（`_feat.pt` 三个：struct / type_id / sv）**；浮点用 `tobytes()` 字节级哈希；断言失败**报具体通道名** | §2.4、§4 |
| R8 | schema 版本 | `_feat.pt::schema_version` 进 dataset 断言 | §2.2、§4 |
| R9 | `s_v` 归一化 | **留在数据侧**（M1 已做全图 min-max → `s_v∈[0,1]`）；**模型内不做任何数据统计**，防 train/eval 不一致 | §3.2、§4 |
| R10 | 参数量 | `NodeFuser` 参数**计入总参数量报告**（448 样本下新增可学习参数＝过拟合风险变量，必须进验收表） | §3.3、§5 |
| R11 | 输出维度 | **`NodeFuser` 输出恒为 128**（M4 `d=128`、大纲 4.4 对外接口不动；前端化＝内蕊置换） | §3.2、§5 |

---

## 1. 现状与问题（为什么要动）

现状（`m3_build_features.py::assemble_feat`，2026-09-12）：

```text
parts = [cb_func(768), cb_node(768), type_emb(64), struct(D_struct), sv(1)]   # 拼接
mlp   = nn.Linear(concat_dim, 128)        # torch.manual_seed(SEED) 后**随机初始化一次**
_feat.pt = mlp(concat)                    # (N,128)，训练时不更新
```

即：`_feat.pt` 是「随机初始化、冻结的线性投影」后的 128 维向量，其中节点类型嵌入是
`nn.Embedding(9,64)` 的**随机冻结**表（同样只受 `SEED` 控制）。

由此产生三个与大纲不符或工程上不可行的问题：

| # | 问题 | 依据 / 后果 |
| - | --- | --- |
| P1 | 类型嵌入**不可学习**，与大纲「每类节点对应一个**可学习**嵌入向量，维度 d₁=64」冲突 | 大纲 4.3.1 |
| P2 | 「对结构特征施加普通 Dropout，默认概率 0.2」**无实现路径** | 大纲 4.3.4：结构通道已被压在 MLP 之后，无法单独 dropout |
| P3 | 先验 Dropout（0.2 置零 s_v）只能靠**重跑 M3 出 `_feat_no-prior.pt` + 按图切文件**实现 | 大纲 4.1.4/4.3.x：必须先全量产出变体文件；且「按图切换文件」把随机性外置到脚本常量 `SEED` 与 torch 版本上（换环境/换 torch 版本，`_feat.pt` 数值即变，哈希不可复现） |

**结论**：三处根因是同一个——把「特征融合」放在了 M3（离线、冻结、随机）里。把融合前移到模型内即可一次性兑现 4.3.1 与 4.3.4，并让先验 dropout 回归「模型内、训练期、按图」的正常实现。

**退役项（明确）**：`_feat_no-prior.pt` 及其「按图切换 + 种子等价性」整套设计**整体退役**（decisions §4、§9.4 需改写）；`assemble_feat` 里的 `torch.manual_seed(seed)` 与随机 `Embedding/Linear` **删除**。

---

## 2. 新数据契约（产物侧）

### 2.1 `_pyg.pt`（**完全不动**）

保持只读纯结构：`x` 仍为 N×1 占位、`edge_index` / `edge_type` / `node_id` / `contract` / `function` /
`expression` / `line_start` / `label` 一律不改、不重算。**不涉及 M2 重跑。**

### 2.2 `_feat.pt`（M3 输出，**改存通道**，不再是张量）

改为 `torch.save` 的 **dict**（保持「每图一个文件、行序对齐 `node_id`」）：

```python
{
  "schema_version": 2,                      # ★ 进 dataset 断言（R8）
  "struct":  Tensor(N, D_struct) float32,   # 规则/结构向量（build_struct_features 原样：可见性/布尔/外呼/位置/IR 列）
  "type_id": Tensor(N,)          int64,     # 节点角色索引，取值 [0, 9)，顺序 = ROLE_NAMES（锁死）
  "sv":      Tensor(N, 1)        float32,   # M1 先验分数（N×1 独立通道；语义不变；归一化已在 M1 完成）
  "meta": {
    "D_struct": int, "role_names": [...], "feat_groups": "all",
    "channel_sha256": {"struct": "<sha256>", "type_id": "...", "sv": "..."},   # ★ 逐通道三个 sha（R7）
    "combined_sha256": "<按固定通道序 dtype+shape+字节 拼接后的总体 sha，供一行比对>",
    "created_utc": "...", "codebert": "microsoft/codebert-base", "torch": "2.0.1+cpu"
  }
}
```

要点：
- `_feat.pt` **不含** CodeBERT 通道（裁定口径：三通道 = 规则向量 / 类型 id / s_v）；
- **归一化归属（R9）**：`s_v` 的全图 min-max 已由 **M1**（`m1_runner`）完成 → `s_v ∈ [0,1]`；`_feat.pt`
  **原样转存**，M3/模型**不得再做任何统计**（不 min-max、不标准化、不 batch 统计）；
- **不再产出任何变体文件（R2）**：`_feat_no-prior.pt`、`_feat_grp-*.pt`、`_feat_{variant}.pt` 全部退役；
- 行序 = `_pyg.pt::node_id` 顺序，`N` 必须与 `node_id` 等长。

### 2.3 `_cb.pt`（中间缓存，**保持现状**，M3 复用 581/581）

`{"func": {"<contract>::<function>": Tensor(768)}, "node": {"<node_id>": Tensor(768)}}` 不变；
它仍是「可离线缓存、避免重复编码」的载体，由 `dataset.py` 在加载时**行对齐**成本图的两条语义通道。

### 2.4 语义锁重定义为**逐通道字节级哈希**（R7）

旧锁「`_feat.pt` 必须是 (N,128)」作废，改为：

> **模型输入 = 通道字典**（`_feat.pt` 三通道 + `_cb.pt` 两通道）；每个数据通道各自带一个 `sha256`，
> 取 **`tensor.contiguous().view(torch.uint8)` 即 `tobytes()` 的原始字节**，故为**字节级**判据：
> 任何数值漂移（含跨 torch 版本）都会改变哈希。

- 固定通道序（与现状拼接顺序一致，锁死）：
  `[cb_func(768), cb_node(768), type_emb(64), struct(D_struct), sv(1)]`；
  `type_emb` 是模型参数、**不在**数据通道哈希内。
- `_feat.pt::meta.channel_sha256` **逐通道三个 sha**（struct / type_id / sv，R7）+ 一个 `combined_sha256`
  （按通道序 `dtype + shape + 字节` 拼接后取 sha，供一行比对）；run 配置记 `combined_sha256`。
- **断言失败必须报具体通道名**（如 `channel mismatch: sv (expected abc…, got def…)`），禁止只报“哈希不符”。
- `_cb.pt` 两通道是否纳入指纹：见 §7-Q6（建议纳入；只在 `--verify-channel-hash` 时重算，
  避免每个 epoch 重复哈希 0.6 GB）。
- 哈希计算不依赖任何 RNG（M3 不再有 `manual_seed`）；`torch` 版本、CodeBERT 权重来源、`D_struct`
  一并写入 `meta`，与哈希一起用于跳环境比对。

---

## 3. 接口设计

### 3.1 `dataset.py`（组合层，不做任何融合）

```python
@dataclass
class GraphSample:
    channels: dict[str, torch.Tensor]   # 固定序：cb_func, cb_node, type_id, struct, sv
    edge_index: Tensor; edge_type: Tensor; label: Tensor; name: str; meta: dict

def load_graph(base, graph_dir=..., ab: Ablation | None = None,
               index: dict[str, list[int]] | None = None) -> GraphSample
```

- **只组合**：读 `_pyg.pt`（结构）+ `_feat.pt`（三通道）+ `_cb.pt`（两语义通道），按固定序拼成通道字典；
  **不跑 MLP、不做任何线性投影、不改 dtype**。
- **本层不做任何置零/掩码（R1）**：确定性配置层（`--ablate-sv`/`--feat-groups`/`--cb-channels`）**也在
  `NodeFuser` 内**执行——与训练期 dropout **共用同一个掩码原语**，否则两条路径分叉，§5-T1 的逐位
  相等断言无法成立。dataset 返回的永远是**未掩码的原始通道**。
- 边级消融仍在 `dataset.py`（按 `edge_type` 过滤，零重跑），与本次改动无关。
- 特征级消融全前移到模型侧（**已裁定，R1/R2**）：`struct` 列组置零（原 `--feat-groups`）、
  `cb_func`/`cb_node` 通道剔除（原 `--variant no-cb-func`/`no-cb-node`/`no-codebert`）均为通道级操作，
  **零重跑**；`_feat_grp-*.pt` / `_feat_{variant}.pt` 文件级变体**全部退役**，主目录不再出现任何 `_feat_*` 变体文件。

### 3.2 `model.py`（新增前端模块，融合与正则都在这里）

**R11：`NodeFuser` 输出恒为 128**：对内是内蕊置换，对外接口（M4 `d=128`、大纲 4.4）**不动**。

```python
class NodeFuser(nn.Module):
    """通道字典 → h_v^{(0)} ∈ R^{N×128}（大纲 4.3.1/4.3.3/4.3.4 的落点）。

    结构与初始化沿用原冻结投影（R6）：Embedding(9,64) + Linear(D,128)、PyTorch 默认初始化分布、
    同一初始化 seed 口径；**唯一变量是可学习性**（requires_grad=True，可用 --freeze-fuser 关掉）。
    模型内不做任何数据统计（R9）：无 BatchNorm、无 batch 级标准化、无 min-max。
    """
    def __init__(self, d_struct, n_roles=9, type_dim=64, hidden=128,
                 ablate: AblationConfig = AblationConfig(),   # ★ 配置层（确定性）
                 prior_dropout=0.2, struct_dropout=0.2,       # ★ 正则层（仅 train）
                 fuser_init_seed=20260905):                   # ★ 独立于划分/训练种子（R6）
        ...
    def forward(self, ch: dict[str, Tensor], *,
                prior_mask: Tensor | None = None,    # (G,) 0/1 逐图；None = 不置零
                struct_mask: Tensor | None = None) -> Tensor:   # (G,) 0/1 逐图；None = 不置零
        # ① 配置层：_ablate(ch)         —— 确定性，train/eval 一致
        # ② 正则层：_mask_channels(...)  —— 仅 training=True 时传入 mask，随机
        # ③ x = cat([cb_func, cb_node, type_emb(type_id), struct, sv], dim=1)
        # ④ h = proj(x)                 —— ★ 此处之后禁止任何掩码/置零（R4）
        return h
```

#### 3.2.1 置零在计算图中的**精确位置**（R4，实施红线）

```text
ch(cb_func, cb_node, type_id, struct, sv)
  ├─ ① 配置层掩码（确定性）：sv 恒零 / struct 列组置零 / 通道剔除      ← 融合前
  ├─ ② 正则层掩码（随机，仅训练期，按图）：sv 乘 0/1、struct 乘 0/1    ← 融合前
  ├─ ③ torch.cat([...])  →  张量 x ∈ R^{N×D}
  └─ ④ h = proj(x)   ← ★★ 置零只能发生在 ④ 之前；④ 之后任何置零都无效、禁止
```

| 开关 | 语义层 | 作用张量 | 位置 | train | eval |
| --- | --- | --- | --- | --- | --- |
| `--ablate-sv`（原 `--no-prior`） | **配置**（确定性） | `sv` 通道 `(N,1)` 乘 0 | `cat` 前 | 恒零 | 恒零（一致） |
| `--feat-groups base/base+sem` | **配置**（确定性） | `struct` 通道 `(N,D)` 列组置 0 | `cat` 前 | 生效 | 生效（一致） |
| `--cb-channels`（cb 通道消融） | **配置**（确定性） | 通道子集剔除/置零 | `cat` 前 | 生效 | 生效（一致） |
| **先验 dropout**（大纲 4.1.4） | **正则**（随机） | `sv` 通道 `(N,1)` 乘图级 0/1 | `cat` 前 | 每图 Bernoulli(0.2) | 关闭（不置零） |
| **结构 dropout**（大纲 4.3.4） | **正则**（随机） | `struct` 通道 `(N,D)` 乘图级 0/1（**整通道**，R3） | `cat` 前 | 每图 Bernoulli(0.2) | 关闭（不置零） |

**为何必须在融合前**：`proj` 是满秩线性变换，拼接后 `sv` 的标量会被混进 128 维的每一维；此时再置零
任何输出位置都**不能去掉先验信息**，dropout 名存实亡，先验正则/消融的实验结论会**变成假的**（比不做
更坏，因为从表面数字上看不出异常）。故「融合前置零」是硬约束。备选写法「通道独立投影后置零 sv 段」
需逐通道投影且无偏置才与前式等价，**本方案不采用**。

**两层隔离规则（R1，严禁混用）**：

1. `--ablate-sv` **不是** `--prior-dropout 1.0`：前者 train/eval 一致、无随机、进 `ablation` 配置；
   后者仅训练期、每图独立随机、eval 必须关闭；
2. 确定性消融**不得**只在训练期生效；正则**不得**在 eval 生效（eval 置零图数必须为 0）；
3. 触发路径与记录分离（config 分别写 `ablation` 与 `prior_dropout/struct_dropout`），
   但**共用同一个掩码原语** `_mask_channels(ch, {"sv": mask, "struct": mask})`——共用是刻意的：
   它使「恒零」与「随机置零」在 sv 上是**同一个操作**，从而使 §5-T1 的逐位相等断言可证；
4. 掩码在 batch 拼接**之前逐图**采样（可追溯到 `seed + epoch + stable_graph_index`）；
   一个 batch 内共享同一掩码 = 错。

#### 3.2.2 其余约定

- `NodeFuser` 是**所有图共享**的一组参数（与 RGCN 一起训练、一起存 checkpoint）；不做 per-graph 实例
  （参数量会随图数膨胀）。
- `--freeze-fuser`（R5/R6 的对照组）：`requires_grad=False` + 同 `fuser_init_seed`，用于复现旧
  「随机冻结投影」行为并与归档文件做等价性回归（§5-T2）。
- `sv` 是**数据**（`requires_grad=False`）：置零只切断该图的 sv→proj 通路，不影响其他通道的梯度。
- RGCN 及其下游（`a_head`、`node_logits`、`L_var`）**接口不变**：输入仍是
  `(x=h_v^{(0)}, edge_index, edge_type)`。

### 3.3 `train.py` / `evaluate.py`（受影响的调用点）

- batch 组装时先逐图采样 `prior_mask` / `struct_mask`，再偏移拼接；`NodeFuser` 在 RGCN 之前调用一次。
- `config.json` / `results.json` 记录：`schema_version`、`channel_sha256`（含 `combined_sha256`）、`d_struct`、
  `fuser_init_seed`、`prior_dropout`、`struct_dropout`、`ablation`（确定性配置）、`cb_channels`；
- **参数量报告（R10）**：`fuser_params` / `rgcn_params` / `total_params`，并单列 `fuser_learnable_params`
  （`--freeze-fuser` 时为 0），在 `results.json` 与论文「模型规模」处同时给出——448 样本下新增可学习
  参数是**过拟合风险变量**，必须与指标一起读；按实测 `D_struct=30`（可见性 4+布尔 14+外呼 5+位置 1+IR 6）
  估算：`D = 768×2 + 64 + 30 + 1 = 1631`，`NodeFuser ≈ 9×64 + 1631×128 + 128 ≈ 0.21 M`
  （以运行时 `meta.D_struct` 为准，实现时先打印再写入配置）；
- 日志新增：`prior_dropout_active_graphs` / `struct_dropout_active_graphs`（实际按图置零数，便于验收）。
- 训练/eval 模式差异**显式**：`fuser.train()/eval()` 只决定**正则层**（是否采样两个 mask）；
  **配置层**（`--ablate-sv` / `--feat-groups` / `--cb-channels`）在两种模式下完全一致。

---

## 4. `dataset.py` 断言清单（加载即校验，失败要能定位到单一契约）

1. `_feat.pt` 必须是 **dict** 且含 `schema_version` / `struct` / `type_id` / `sv` / `meta`；
   若仍是 Tensor（旧格式）→ 报错并提示「旧格式已归档到 `graphs/legacy_feat_pre_frontend/`，请重跑
   `python scripts/m3_build_features.py`」。
2. `schema_version == EXPECTED_SCHEMA_VERSION`（当前 **2**，R8）——版本不符直接报错，不做兼容分支。
3. `type_id.dtype == int64` 且 `0 <= type_id < len(ROLE_NAMES)`；`ROLE_NAMES` 顺序与 M3 一致（读 `meta` 比对）。
4. `struct.dim() == 2` 且 `struct.shape[1] == meta["D_struct"]`；`sv.shape == (N, 1)`。
5. 四者行数 `== len(_pyg.pt::node_id)`（行序对齐锁）。
6. **`sv` 值域断言 `0 <= sv <= 1`（R9）**：归一化已在 M1 完成，此处只验证不重做；越界即报错。
7. `_cb.pt` 存在且能按 `contract::function` / `node_id` 取到行；缺行时用零向量且**计数并上报**
   （沿用现状行为，但必须可在日志里看到缺行数，不静默为零）。
8. `cb_func.shape == cb_node.shape == (N, 768)`；dtype 与 `_cb.pt` 一致（float32）。
9. 拼接后 `proj` 的输入维度 == `768*len(cb_channels) + type_dim + D_struct + 1`（否则报错，防错位）。
10. 标签断言（沿用）：`base in index` 否则报错。
11. **逐通道哈希校验（R7）**：`--verify-channel-hash` 时重算三个通道 sha256（`tobytes()` 字节级）
    并与 `meta.channel_sha256` 逐通道比对；**失败时报具体通道名**与期望/实际值；`combined_sha256` 不符时
    逐通道定位到底哪个通道漂了（即先比 combined、再比三个通道，输出差异名单）。
12. （若 §7-Q6 取 A）`_cb.pt` 两通道 sha 同步校验，报 `cb_func` / `cb_node` 通道名。

---

## 5. 验收与回归计划

### 5.1 强制门（不过不得进入下一步；语义正确性用机器验证）

| 编号 | 项 | 判据 |
| --- | --- | --- |
| **T1** | **无泄漏单测（最重要）** | 同一 batch、固定 `struct_mask=全 1`：<br>`fuser(ch, prior_mask=m)` **逐位等于** `fuser(_zero_sv(ch,m), prior_mask=None)`（`torch.equal`，非 allclose）<br>—— 其中 `_zero_sv(ch,m)` 把 mask=0 的图的 `sv` 通道**预先换成全零**。<br>**反例守卫**：若实现把置零放在 `proj` 之后，该等式必然不成立 → 同一用例同时是「位置正确性」的机器验证；<br>推论（必须为真）：`fuser(ch, prior_mask=全0)` ≡ `fuser(_zero_sv(ch,全0), prior_mask=None)` ≡ `--ablate-sv` 在同样输入上的输出。 |
| **T2** | **冻结等价性回归（重构无副作用）** | `--freeze-fuser --fuser-init-seed=20260905` 重算抽样图（建议 5 图、全节点）与**归档的 legacy `_feat.pt`** 逐位比对（本环境 torch 2.0.1+cpu 下预期 `torch.equal` 为真；跨环境改记 `max|Δ|` 并注明环境）——验证「单一变量＝可学习性」而非重构改变数值 |
| **T3** | M3 确定性 | 同输入两次运行，三个逐通道 sha256 与 `combined_sha256` **完全相同**；M3 不再有 `manual_seed`/RNG |
| **T4** | 全量断言 | M3 全量重跑后，`dataset.load_graph` 对 581 图全部通过 §4 断言（含 schema/值域/维度） |
| **T5** | 前端形状/梯度 | `NodeFuser` 输出恒为 `(N,128)`（R11）；反向后 `type_emb.weight` 与 `proj.weight` 梯度非空 |

### 5.2 两层语义与行为

| 项 | 判据 |
| --- | --- |
| 先验 dropout（正则） | 训练模式首 epoch：被置零图占比 ≈ 0.2（容差 ±0.1，seed 固定可复现）；**eval 模式置零图数 = 0** |
| 结构 dropout（正则） | 训练模式：被置零图占比 ≈ 0.2、且**整通道**被零（非 elementwise）；eval 模式无零；列宽不变 |
| 配置层一致性 | `--ablate-sv` / `--feat-groups` / `--cb-channels` 下 **train 与 eval 输出逐位一致**（无随机、无模式差异） |
| 混用拦截 | 不存在「用 dropout=1.0 代替 `--ablate-sv`」或「确定性置零只在 train 生效」的实现；两者配置项互斥校验（同时给时报错或明示叠加语义） |
| 掩码粒度 | 同一 batch 内不同图的掩码独立（构造 G=2 用例：一图 drop、一图不 drop，输出分别与各自真值分支逐位相等） |

### 5.3 消融与产物

| 项 | 判据 |
| --- | --- |
| 消融零重跑 | `cb_channels` 三种组合与 `feat_groups=base/base+sem` **只影响通道，不产任何新文件**；`_feat_*.pt` 变体产物数 = **0**（R2） |
| 参数量报告（R10） | `results.json` 同时输出 `fuser_params` / `rgcn_params` / `total_params` / `fuser_learnable_params`（`--freeze-fuser` 时为 0）；与指标同表报告 |
| 归档完整性 | `legacy_feat_pre_frontend/` 文件数 = 旧集（581 主特征 + 现存变体）；归档后主目录不再有 `_feat.pt` 旧格式文件 |
| 与旧数字的关系 | 旧 `_feat.pt`（随机冻结投影）与新高斯可学习前端**不可比**；M4 smoke 需重跑，旧结果仅作历史记录 |

---

## 6. 影响面与成本

### 6.1 需要改 / 不需要改

- **需要改**：`m3_build_features.py`（`assemble_feat` → `build_channels`：删 MLP/Embedding/`manual_seed`，
  改存三通道 + 逐通道 sha + `schema_version`；删 `--variant no-prior` 与 `_feat_grp-*` 变体产出）、
  `dataset.py`（`load_graph` 返回通道字典 + §4 断言）、`model.py`（`NodeFuser`）、`docs/M4_interface.md`、
  `论文开发手册.md` §8.6–8.9/§10.1/§10.4、`experiments/decisions.md` §4/§9.4、`Todo_List.md`、`项目组织架构.md`。
- **不需要改**：`_pyg.pt` 与 M1/M2 全链路（**无 M2 重跑**）、`_cb.pt` 内容、边级消融、标签与划分、
  RGCN 及其下游接口。

### 6.2 M3 重跑范围与耗时预估（本节请确认）

| 项 | 范围 | 预估 | 说明 |
| --- | --- | --- | --- |
| M3 全量重建 `_feat.pt` | **581 图全部** | **≤ 60 s** | `_cb.pt` **复用 581/581、不重跑 CodeBERT**；`build_channels` 比现状更轻（无 MLP/Embedding），历史同类全量耗时 ≈ **57 s** |
| 三通道 sha256 | 581 图 | +2–5 s | struct/type_id/sv 体积小（3 通道合计 ≪ 0.1 GB） |
| （若 Q6 取 A）`_cb.pt` 两通道 sha | 581 图 | +2–3 s（可选，默认不算） | 两通道合计 ≈ 0.6 GB，仅在 `--verify-channel-hash` 或构建时算一次 |
| 旧特征归档 | 581 文件（+现存变体） | 秒级 | 移动而非拷贝，磁盘净增 ≈ 0 |
| M4 smoke 重跑 | `tests/test_model_smoke.py`（22 用例）+ 新增 T1/T5 用例 | 秒级 | 前端接口变更后必须重跑 |
| `train.py` / `evaluate.py` | — | 尚未实现 | 无额外成本（开工时直接按新接口写） |

> 总成本量级：**一次 M3 全量（约 1 分钟） + 测试秒级**；不需要重跑 M1/M2/CodeBERT。

### 6.3 旧文件归档（R5）

- 位置：`products/alldata/graphs/legacy_feat_pre_frontend/`（与 `splits/random_snapshot/` 同一先例：
  **隔离目录、不进正典路径、不参与任何实验**）；`.gitignore` 已忽略 `products/**/graphs/` → 不会入库。
- **执行顺序硬约束：先归档、再重跑 M3**（否则旧 `_feat.pt` 被覆盖，T2 失去比对标量）。
- 内容：旧 `_feat.pt` × 581 + 现存变体（`_feat_no-prior.pt`、`_feat_grp-*.pt` 等小样）。
- `decisions` 记一行（归档位置 + 日期 + 原因 + 如何复现旧数值：`--freeze-fuser --fuser-init-seed=20260905`）。
- 旧文件**只用于 T2 回归与审计**；冻结-可学习对比一律在新架构内用 `--freeze-fuser` 做（不回头读旧文件）。

### 6.4 大纲

大纲 4.3.1「可学习嵌入」与 4.3.4「结构特征 Dropout 0.2」**由本方案直接兑现**（且 R3 取整通道、
与大纲“置零”字面一致），**无需改大纲**；4.1.4/4.3.x 关于先验 dropout「以概率 0.2 将当前样本所有节点的
s_v 置零」也由模型内实现直接兑现。

---

## 7. 待裁决策点（全文，一轮裁完）

> 格式：Q = 问题；【选项】；【影响】；【推荐】；【状态】。**Q1–Q9 全部已裁定（2026-09-12）**；
> Q6–Q9 按推荐采纳（2026-09-12，用户确认「按你的推荐」）：Q6=A（cb 两通道纳入指纹）、Q7=B（不保留
> 过渡开关）、Q8=A（init seed 沿用 20260905）、Q9=A（T2 为强制门）。

**Q1 — 特征级消融是否全部前移到模型侧（退役 `_feat_{variant}.pt` / `_feat_grp-*.pt`）？**
- 【选项】A 全前移到模型侧（通道级掩码）；B 保留文件级预生成变体；
- 【影响】A：产物数 -N、无重跑、语义统一、且与先验 dropout 共用同一掩码原语（可被 T1 机器验证）；
  B：保留旧路径但两套口径并存，存在“用哪一套”的漂移风险；
- 【推荐】A；【状态】**已裁定 = A（R1/R2）**。

**Q2 — 结构特征 Dropout 形式？**
- 【选项】A elementwise `nn.Dropout`；B 整通道置零、按图 Bernoulli(0.2)；
- 【影响】A：改变方法语义（大纲 4.3.4 的“置零”原义是整向量置零）、且与旧「按图切换文件」的等价性论证不一致，
  若采用需回写大纲；B：与 s_v 置零同构、与按图语义一致、实现简单；
- 【推荐】B；【状态】**已裁定 = B（R3）**。

**Q3 — 前端参数共享？**
- 【选项】A 所有图共享一个 `NodeFuser`；B 每图/每形态一个实例；
- 【影响】A：参数量固定、与 RGCN 同存 checkpoint；B：参数量随图数膨胀、无法训练；
- 【推荐】A；【状态】**已裁定 = A（§3.2.2）**。

**Q4 — 旧 `_feat.pt` 如何处置？**
- 【选项】A 直接覆盖；B 归档到隔离目录；
- 【影响】A：丢失 T2（冻结等价性回归）的比对标量，重构风险不可证伪；B：零成本、可回溯，与 `random_snapshot/` 先例一致；
- 【推荐】B；【状态】**已裁定 = B（R5，§6.3）**。

**Q5 — `type_id` 嵌入的冻结口径？**
- 【选项】A 只提供可学习嵌入；B 可学习 + `--freeze-fuser` 开关；
- 【影响】A：无法做「冻结 vs 可学习」对比（大纲 4.3.1 只要求可学习，但审稿常问“增益来自容量还是可学习”）；
  B：一个 flag 的代价，在前端化后天然可做，且使 T2 可执行；
- 【推荐】B；【状态】**已裁定 = B（R5/R6）**。

**Q6 — `_cb.pt` 两通道是否纳入通道指纹？**
- 【选项】A 纳入（`combined_sha256` 覆盖 5 个数据通道）；B 不纳入（只有 `_feat.pt` 三通道 sha）；
- 【影响】A：能抓到最易漂移的一侧（CodeBERT 前向、跨 torch 版本），代价是重算时多哈希 ≈ 0.6 GB（≈ 2–3 s，
  只在构建时或 `--verify-channel-hash` 算一次）；B：便宜但漏检——`_feat.pt` 三通道不变、模型输入仍可能变了；
- 【推荐】**A**；【状态】**已裁定 = A**（`meta.cb_sha256` 记 cb 两通道 + `combined_sha256` 覆盖五通道；
  cb 两通道只在构建时或 `--verify-channel-hash` 重算，三个便宜通道默认每次加载校验）。详见 §2.4。

**Q7 — 是否保留 `--emit-legacy-feat` 过渡开关？**
- 【选项】A 保留（过渡期仍能产旧格式）；B 不保留；
- 【影响】A：多一条代码路径＋多一套口径（正是本稿要消除的东西）；且旧文件已归档、可随时用 `--freeze-fuser` 复现；
  B：代码单一、口径唯一；
- 【推荐】**B**；【状态】**已裁定 = B**。

**Q8 — `--fuser-init-seed` 取值？**
- 【选项】A 沿用旧 `SEED = 20260905`；B 另取新值；
- 【影响】A：可直接执行 T2（冻结等价性逐位比对），把「重构无副作用」变成可验证事实；
  B：避免新旧数字表面可比，但放弃 T2，且“单一变量＝可学习性”失去证据；
- 【推荐】**A**；【状态】**已裁定 = A**（该 seed 仅控初始化，**独立于划分种子与训练种子**）。

**Q9 — T2（冻结等价性）是否作为强制门？**
- 【选项】A 强制（不过不得合并）；B 仅记录不阻断；
- 【影响】A：多一道机器可验证的重构护栏；代价 = 跑 5 图；B：重构可能悄悄改数而无人知晓；
- 【推荐】**A**；【状态】**已裁定 = A**（T2 进 `tests/`，随 `pytest tests/` 一起跑）。

> 确认后按「M3 改 + 逐通道哈希与 T3/T4 验收 → dataset 断言 → model 前端 + T1/T2/T5 → 最后 train/evaluate」
> 的顺序实施；每步单独跑 smoke，不一次性改完再验证。
