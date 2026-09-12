# M5 详细开发方案（工程可行性设计）

> 版本：v1，2026-09-12
> 依据优先级：`研究点一细化大纲改II.docx`（4.5 / 5.1 / 5.2 / 5.3 / 5.4）＞ `experiments/decisions.md` v5（§1–§15）＞ `论文开发手册.md` §10/§11/§12。冲突以大纲为准。
> 本文是**实施前的设计稿**，落地时若与决议/手册冲突，以决议/手册为准；本文补充的是决议未展开的工程细节（批图 collate、组装、种子语义、耗时估算）。

---

## 0. 目标、范围与阶段划分

M5 的核心交付物是三件脚本 + M5 CI smoke，完成「图级七类多标签分类」的端到端训练、验证、测试、阈值选择、三种子汇总与可追溯实验记录：

| 阶段 | 内容 | 交付物 | 关卡（不通过不进下一步） |
| --- | --- | --- | --- |
| A | 指标层 | `scripts/metrics.py` + `tests/test_metrics.py` | 合成边界无 NaN、与 sklearn 对照一致 |
| B | 训练闭环 | `scripts/train.py` + `tests/test_train_utils.py` | `--limit-graphs 1` 前向/反向/checkpoint 全绿 |
| C | 评估 | `scripts/evaluate.py` + `tests/test_evaluate.py` | 阈值只读 val、双报告、zero-positive 跳过 |
| D | M5 CI smoke | 6 类窄范围测试 | 全部通过，失败定位到单一契约 |
| E | 主实验 | `runs/seed{0,1,2}/` + `runs/summary.json` | 三种子均值±std、日志字段齐全 |
| F | 消融/基线 | `eval_results/{ablation,baseline}/` | 5.4.1/5.4.2 表有结果、零重跑分层正确 |
| G | 跨数据集（**阶段 5**） | `eval_results/{dive,solidifi}/` | DIVE 一次性、SolidiFI 三分数 |

阶段 A–E 是 **M5 本体**（本文主体）；F、G 依赖 M5 跑通后执行，本文给出可执行路线与关键口径，但不阻塞 M5 本体。

> 边界：DIVE 只做一次性外部测试，不参与训练/验证/早停/阈值/模型选择；SolidiFI 只做层次二合成注入节点覆盖评估。两者均不进入 `runs/`。

---

## 1. 现状盘点（M5 启动前的既定事实）

**已完成并验收**（M1–M4 + 数据/划分）：

- `scripts/dataset.py`：`build_index(graph_dir) -> (index, unmatched)`、`load_graph(base, graph_dir, ab, index, verify_channels) -> GraphSample`、`Ablation(drop_edges, drop_ast)`；`GraphSample` 含 `channels`（通道字典，固定序 `cb_func,cb_node,type_id,struct,sv`）、`edge_index/edge_type`、`label[7]`、`name`、`node_id`、`meta`。
- `scripts/model.py`：`NodeFuser`（通道字典 → `h_v^(0)`∈R^{N×128}，`ablate` 确定性 / `prior_dropout`+`struct_dropout` 逐图随机分层，`proj` 之前置零）、`SSMHG`（两层 RGCN，`forward(x, edge_index, edge_type, batch) -> (z, a, node_logits)`）、`sample_dropout_masks(G, prior_p, struct_p, generator) -> (prior, struct)`、`apply_edge_mask(edge_index, edge_type, mask)`、`safe_readout`、`AblationConfig`、`parameter_report`。
- `scripts/make_splits.py`：固定种子 8:1:1 + 覆盖约束校正（C1 合计≥30%、C2 每划分每类≥1）+ 两级池去重；产物齐备：`split_seed{0,1,2}.json`（载荷四键 `{seed,ratio,train,val,test}`）、`splits.csv`（1345 行 = 448×3 + 表头）、`split_report.json`、`coverage_swaps_seed*.txt`、`split_metadata_seed*.json`、`dedup_dropped.txt`、`unmatched_contracts.txt`。
- **数据事实**（已核实，用于本方案的估算）：581 图 / 93551 节点 / 226511 边；训练池 448（358/45/45）；标签序 `access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`（reentrancy 下标 4）；`D_struct=30`、`struct_layout={"visibility":4,"bool":14,"call_mode":5,"position":1,"ir":6}`、IR 类别 6 类、`NodeFuser` 融合 Linear 输入维 = `768*2 + 64 + 30 + 1 = 1631`。

**待实现**（本文设计对象）：`metrics.py`、`train.py`、`evaluate.py`、M5 CI smoke。

---

## 2. 关键工程约束与语义锁死（实现时逐条对照，最容易写错）

1. **标签顺序固定**：`access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`。`dataset.py` 的 `VULN_NAMES`/`model.py` 的 `num_classes=7` 与本方案硬编码顺序必须一致，不得重排。
2. **`_pyg.pt` 只读**：纯结构（`edge_index/edge_type/node_id` + N×1 占位 `x`），永不回写；`_feat.pt` = **拼接前通道字典**（schema v2），融合与**全部掩码**只在 `model.NodeFuser`。`dataset.py` 只组合，不融合、不掩码、不重算。
3. **Dropout 分层（train/eval 行为不同）**：
   - 训练期正则：`prior_dropout=0.2`、`struct_dropout=0.2`，`model.sample_dropout_masks` 逐图采样 → 随 `batch` 传入 `NodeFuser`（`proj` 之前）；eval 传 `None`（不置零）。
   - 确定性消融：`AblationConfig(ablate_sv / feat_groups / cb_channels)`，train/eval 一致。
   - 两者共用同一乘法原语，但语义严格分层，不得混用。
4. **主指标 micro-F1（标签对级）**；macro-F1 为参考，报告时注明支撑构成；逐类 F1 与 per-class PR-AUC **必须随 support** 同时给出，support≤2 的类仅描述性呈现、不进比较结论。
5. **阈值与早停目标都是 val micro-F1**（2026-09-12 口径）；阈值候选 `0.20,0.25,...,0.80` 只在验证集选，tie 取较小阈值；测试集双报告（固定 0.5 + 验证集阈值），不用 test 调阈值。
6. **零正类用 class-mask，不用 `pos_weight=0`**：`pos_c>0` → `pos_weight_c=min(neg_c/pos_c,20)`（无平滑）；`pos_c==0` → `class_mask[c]=0` 从逐元素 BCE 的分子和分母同时排除；全部零正类直接报错。
7. **`L_var` 按图 population std**（`torch.std(unbiased=False)` 等价），单节点图 std=0、n==0 报错；计算不 detach，梯度必须连到 `a_head` 与 GNN；`L_var = (1/B)Σ max(0, 0.1 - std(a^{(i)}))`，`lambda_var=1e-3`。
8. **种子分离**：划分种子（=make_splits 的 seed）与训练种子（=模型初始化/dropout/数据打乱）独立。主划分固定 seed0（见 §8 裁定）。
9. **CALLBACK_RISK 默认保留为边**，不降级为节点特征；主实验不重跑 M2。
10. **`s_v` 是输入特征，`a_v` 是解释信号**：`s_v` 只在 NodeFuser 作为输入通道，`a_v` 不参与训练损失外的任何节点真值监督。
11. **训练/推理的 dropout 行为不同**（模型 `dropout=0.3` 由 `model.training` 自动切换；先验/结构 dropout 由掩码是否传 `None` 切换）。

---

## 3. 总体架构与数据流

```
make_splits.py ──> split_seed{seed}.json  (已就绪，M5 只读)
dataset.load_graph ──> GraphSample(channels, edge_index, edge_type, label, ...)

train.py（一个 batch 的前向+反向）:
  collate([GraphSample×B]) ──> {channels(ΣN), edge_index(2,ΣE'), edge_type(ΣE'), batch(ΣN), labels(B,7)}
        │  （含训练期 DropEdge：先逐图 mask 再偏移拼接）
        ▼
  x = fuser(channels, prior_mask=(B,), struct_mask=(B,), batch=batch)   # 融合前置零
        ▼
  z, a, node_logits = model(x, edge_index, edge_type, batch)
        ▼
  loss_cls = masked_weighted_bce(z, labels, pos_weight, class_mask, active_count)
  loss_var = per_graph_population_std(a, batch).mean();  loss_total = loss_cls + 1e-3*relu(0.1-std).mean()
        ▼
  opt.zero_grad(); loss_total.backward(); clip_grad_norm_(1.0); opt.step()
```

三脚本依赖方向：`train.py`/`evaluate.py` → `model`+`dataset`+`metrics`；`metrics.py` 不 import `dataset`/`model`（纯函数，可独立单测）。

---

## 4. 阶段 A：`scripts/metrics.py`（指标层，纯函数）

只实现指标与阈值扫描的**纯函数**，不依赖 `dataset`/`model`，供 train/evaluate/ablation 三处共用。

### 4.1 函数契约

```python
VULN_NAMES = ["access_control", "arithmetic", "dos", "front_running",
              "reentrancy", "time_manipulation", "uncheck"]

def binary_preds(probs: torch.Tensor, thr: float) -> torch.Tensor: ...
    # probs[N,7] float → (probs >= thr).to(int64)  [N,7]

def micro_f1(y: torch.Tensor, p: torch.Tensor) -> float: ...
    # 标签对级：f1_score(y.ravel(), p.ravel(), average="micro", zero_division=0)
    # 主指标；sklearn f1_score(average="micro") 即标签对级 micro 计数

def macro_f1(y: torch.Tensor, p: torch.Tensor) -> float: ...
    # 参考指标；f1_score(average="macro", zero_division=0)

def per_class_prf(y: torch.Tensor, p: torch.Tensor, names=VULN_NAMES) -> dict:
    # precision_recall_fscore_support 每类 P/R/F1/support（含 support=0 类，F1=0 且标注 support）

def mean_average_precision(probs: torch.Tensor, y: torch.Tensor) -> dict:
    # 逐类 average_precision_score；对 support=0 的类跳过，返回 {"mAP": float, "ap": [7], "ap_classes_used": int, "skipped": [...]}

def subset_accuracy(y: torch.Tensor, p: torch.Tensor) -> float: ...
    # 可选：exact_match / N

def search_global_threshold(probs_val, y_val, candidates=(0.20,0.25,...,0.80),
                            metric="micro_f1") -> dict:
    # 只在 val 上扫描；目标 micro-F1（主）与 macro-F1（参考）都记录；
    # 并列取较小阈值；返回 {"best_threshold", "best_micro_f1", "candidates": [{thr, micro_f1, macro_f1}...],
    #                       "tie_break": "并列取较小阈值（偏向召回）"}
```

### 4.2 口径要点

- micro-F1 用**展平后**的 `(样本,类)` 对计算——即 sklearn `average="micro"`；不逐类平均，不额外做 label 组合。
- mAP 口径 = **macro AP**（仅对 `support>0` 的类求平均，返回 `ap_classes_used` 供报告）；同时可附 macroPR-AUC（同一函数返回 `ap` 列表即可覆盖）。
- 阈值扫描只计算，不落盘（落盘在 train/evaluate 侧写 `thresholds.json`）；`search_global_threshold` 返回全部候选指标与 tie 依据。

### 4.3 测试（`tests/test_metrics.py`，纯函数、零数据依赖）

1. `micro_f1`/`macro_f1` 对合成边界（全 0 预测、全 1 预测、空标签类）无 NaN、zero_division=0，与 sklearn 对照逐位相等。
2. `per_class_prf` 在含 support=0 类时返回该 support=0 且 F1=0，不除零。
3. `mean_average_precision` 跳过 zero-positive 类，`ap_classes_used` 计数正确；合成单类数据 AP=1.0。
4. `search_global_threshold`：单调场景选到正确阈值；**并列时取较小阈值**；候选列表完整。

---

## 5. 阶段 B：`scripts/train.py`（训练闭环）

只 import `model`、`dataset`、`metrics`、`sklearn`、stdlib。

### 5.1 模型组装（从数据 meta 读取维度，不硬编码 D_struct）

```python
# 用第一个图的 meta 统一读取；全库断言一致（便宜：只读 meta）
d_struct = int(meta["D_struct"])                    # 30
struct_layout = meta["struct_layout"]               # {"visibility":4,...,"ir":6}
fuser = NodeFuser(d_struct, struct_layout, ablate=ablation_config,
                  prior_dropout=cfg.prior_dropout, struct_dropout=cfg.struct_dropout)
model = SSMHG(in_dim=fuser.hidden, hid=cfg.hid, num_relations=5,
              num_bases=cfg.num_bases, num_classes=7, dropout=cfg.dropout,
              conv_type=cfg.conv_type, use_meanpool=cfg.use_meanpool)
```

> 关键点：`fuser` 与 `model` 是**两个独立模块**，checkpoint 必须同时保存两者 `state_dict`（否则恢复后输入维错位）。

### 5.2 数据加载与批图 collate（本方案自实现，不用 PyG Data）

**加载策略**：CPU 单进程，把 split 内全部 train/val/test 的 `GraphSample` 一次性 `load_graph` 进内存（`data_load_seconds` 计时）。估算：train 358 图 ≈ 5.76 万节点，cb 双通道约 `57600×768×2×4B ≈ 354 MB`，struct 约 7 MB，合计 < 500 MB，CPU RAM 无压力。val/test 各 45 图 ≈ 0.7 万节点。

**collate（一次 batch）**：

```python
def collate(samples, drop_edge_prob=0.0, generator=None, training=True):
    # 1) 训练期 DropEdge：先对每个单图生成 keep mask 再过滤（decisions §9.4，绝不跨图）
    #    可追溯随机流：generator 由 (train_seed, epoch, stable_graph_index) 构造
    # 2) 拼接通道字典：type_id/sv/struct/cb_* 沿节点维 cat
    # 3) edge_index 加节点偏移，edge_type cat
    # 4) batch 向量 [ΣN]（每图节点数复制图编号）；labels = stack [B,7]
```

- **不引入 `torch_geometric.data.Data` / DataLoader**：数据是自定义通道字典，非标准 Data；自实现 collate 更直接、完全确定、无 worker 复杂度。理由与替代方案见 §11。
- **DropEdge 默认关闭**（`--drop-edge-prob 0`），开启时先逐图 mask 再 batch，并记录每图删除比例。
- 训练集每 epoch 打乱一次（`random.Random(seed).shuffle` 或 `torch.Generator` 固定种子），按 `batch_size=32` 顺序切块。

### 5.3 损失

**类别统计（只用训练集）**：

```python
train_pos = label矩阵.sum(0)                        # [7]
train_neg = N_train - train_pos                     # [7]
pos_weight[c] = min(train_neg[c]/train_pos[c], 20) if train_pos[c]>0 else 0.0
class_mask[c] = 1.0 if train_pos[c]>0 else 0.0
active_count = int(class_mask.sum())                # 断言 >0，否则报错
```

**masked weighted BCE**（decisions §2 逐元素形式，无平滑项）：

```python
bce = F.binary_cross_entropy_with_logits(z, labels, reduction="none")   # [B,7]
weighted = bce * (labels * pos_weight + (1 - labels))                    # pos_weight [7] 广播
weighted = weighted * class_mask
loss_cls = weighted.sum() / (labels.shape[0] * active_count)
```

**per-graph `L_var`**（decisions §3，population std，保留梯度）：

```python
def per_graph_population_std(a, batch, B):
    # a:[ΣN], batch:[ΣN]；sum/sum-of-squares/count 分组，var=clamp(m2-mean²,0)，sqrt
    # n==1 → std=0；n==0 → 报错；不 detach
loss_var = torch.relu(0.1 - per_graph_population_std(a, batch, B)).mean()
loss_total = loss_cls + 1e-3 * loss_var              # lambda_var=1e-3
```

### 5.4 训练循环

- 优化器 `AdamW(fuser.parameters()+model.parameters(), lr=1e-4, weight_decay=1e-4)`；`clip_grad_norm_(1.0)`；`max_epoch=200`。
- 调度 `ReduceLROnPlateau(mode="max", factor=0.5, patience=3)` 监控 **val micro-F1**。
- 早停：val micro-F1 连续 5 epoch 不提升；best 以 val micro-F1 最高为准。
- 每 epoch：`model.train()` → 打乱 train → 逐 batch（采样 dropout 掩码 + DropEdge → forward → loss → backward）；`model.eval()` → val 全量 forward（不采样掩码、不丢边）→ 收集 val probs/labels → `metrics.search_global_threshold` 临时算 micro-F1（早停/调度目标），并同步记 macro-F1。
- 日志 JSONL（每 epoch 一行，decisions §6/§7，字段名用 `改II` 的 `score_mean/score_std`）：
  `epoch, loss_total, loss_cls, loss_var, score_mean, score_std, val_macro_f1, val_micro_f1, lr, epoch_seconds, samples_processed, graphs_processed, gpu_mem_allocated`（CPU 写 null）。
- 计时 `time.perf_counter()`：`data_load_seconds / train_seconds（仅 optimizer loop 累计）/ validation_seconds / run_wall_seconds / epoch_seconds_mean / graphs_per_second(=train_graphs/train_seconds)`。

### 5.5 checkpoint 与产物（`runs/seed{seed}/`）

- `best.pt` / `last.pt`：`{model_state_dict, fuser_state_dict, optimizer_state_dict, epoch, best_micro_f1, config, seed}`。
- `config.json`：argparse 全量快照 + 派生量（`d_struct`、`fuser.in_dim`、`pos_weight`、`class_mask`、`active/skipped classes`、`train_pos/train_neg`、`parameter_report(...)`、split 文件摘要、环境/timing 字段）。
- `log.txt`：每 epoch 一行 JSONL。
- `val_best_probs.pt`：best epoch 的 val `{probs, labels, sample_ids}`（供阈值敏感性，避免重复推理）。
- `results.json` / `thresholds.json`：见 §6（由 evaluate 侧或 train 侧在 best 后写 `thresholds.json` 全候选 + tie 依据）。
- `run_wall_seconds` 等计时字段在结束写入 `config.json`/`results.json`，不重复写进每个 epoch 行。

### 5.6 CLI 参数表

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--seed` | 0 | 训练种子（初始化/dropout/打乱） |
| `--split-seed` | =`--seed` | 读 `split_seed{split_seed}.json`（见 §8 种子裁定） |
| `--epochs` | 200 | 最大 epoch |
| `--batch-size` | 32 | 批图数 |
| `--lr / --weight-decay` | 1e-4 / 1e-4 | AdamW |
| `--lambda-var` | 1e-3 | L_var 系数（消融 `--lambda-var 0`） |
| `--tau-var` | 0.1 | L_var τ |
| `--prior-dropout / --struct-dropout` | 0.2 / 0.2 | 训练期正则（消融 `--prior-dropout 0`） |
| `--model-dropout` | 0.3 | SSMHG dropout |
| `--scheduler-patience / --early-stop-patience` | 3 / 5 | ReduceLROnPlateau / 早停 |
| `--drop-edge-prob` | 0.0 | DropEdge（默认关，先逐图 mask 再 batch） |
| `--limit-graphs` | 0 | 小样：只取前 N 个 train 图（smoke） |
| 消融透传 | — | `--drop-edges 3` / `--drop-ast`（dataset.Ablation）；`--conv gcn`、`--meanpool`、`--num-bases 4`、`--hid 256`（model）；`--ablate-sv`、`--cb-channels cb_node`、`--feat-groups base`（AblationConfig） |
| `--deterministic` | False | 完整确定性开关（非主实验默认，记录性能代价） |
| `--graph-dir / --out-dir` | products/alldata/{graphs,splits} / runs | 路径 |

### 5.7 smoke（`--limit-graphs 1`，decisions §9.5/§9.7）

`python scripts/train.py --seed 0 --limit-graphs 1 --epochs 2` 完成：forward/backward 无 NaN、checkpoint 保存+恢复逐位一致、日志字段齐全、`a_head` 与 GNN 梯度非空。测试固化到 `tests/test_train_utils.py`（见 §7）。

---

## 6. 阶段 C：`scripts/evaluate.py`（纯评估）

只 import `model`、`dataset`、`metrics`。职责：加载 checkpoint、推理、写报告；不承载数据/指标实现。

### 6.1 主实验（MVD-HG 内部测试）

1. 读 `runs/seed{seed}/best.pt` + `config.json` → 重建 `fuser`+`model`（从 config 的 `d_struct/struct_layout/ablate/...`），`model.eval()`。
2. **阈值搜索**：加载 val 图 → 前向得 val probs → `metrics.search_global_threshold`（候选 0.2–0.8，目标 val micro-F1，tie 取小）→ 写 `thresholds.json`（全候选 + tie 依据）。**只读 val**；若 train 已存 `val_best_probs.pt` 则复用（可选项：优先读该文件，缺省重算）。
3. **测试双报告**：加载 test 图 → 前向得 test probs → 固定 0.5 与验证集阈值两套 `binary_preds` → 各算 micro-F1（主）/macro-F1（参考，附 support 构成）/每类 P/R/F1（随 support）/mAP + `ap_classes_used`/subset accuracy。
4. 写 `runs/seed{seed}/results.json`：两套阈值结果 + 逐类 support + 阈值 + 计时/环境。

### 6.2 `runs/summary.json`（三种子汇总）

聚合 seed0/1/2 的 `results.json` → 每指标 `mean ± std`；同时保留逐种子明细与划分种子声明（主种子 seed0）。写入 `runs/summary.json`。

### 6.3 `--task ablation|baseline` → `eval_results/`

复用同一评估管线，指定 checkpoint/config 与消融/基线开关，输出到 `eval_results/{ablation,baseline}/`（不进 `runs/`）。基线与消融见 §9。

---

## 7. 阶段 D：M5 CI smoke（decisions §9.7，6 类窄范围测试）

新增 `tests/test_metrics.py`、`tests/test_train_utils.py`、`tests/test_evaluate.py`，失败信息定位到单一契约；完整 3-seed 训练**不进**每次 PR CI。

1. **split**（`tests/test_make_splits.py` 已有，补）：同 seed 可复现、三集合互斥且并集=池、逐类 support 正确。
2. **loss**：zero-positive 类被排除且无 NaN；分母 = `B*active_class_count`；`pos_weight` 截断 20；全零正类报错。
3. **L_var**：单节点 std=0；多图分别计算（两图 std 各自正确，不与 batch 混算）；反向后 `a_head` 与 GNN 梯度非空。
4. **dataset/batch**：边偏移正确、无跨图边；DropEdge 同步过滤 `edge_index`/`edge_type` 且同 seed 可复现；先验 dropout 掩码按图展开（`test_frontend.py` 已有 T1，训练侧再补 collate 归属）。
5. **train**：`--limit-graphs 1` 完成 forward/backward、checkpoint 保存+恢复、日志字段齐全。
6. **evaluate**：只用 val 选阈值；test 同时输出 0.5 与 val threshold；zero-positive AP 跳过且 `ap_classes_used` 正确。

---

## 8. 阶段 E：主实验执行与种子裁定

### 8.1 种子语义（**已裁定**，2026-09-12 用户确认「按推荐方式」）

文档存在两处口径，需明确定案后再批量：

- 口径一（decisions §12 声明）：`seed0＝主划分`，`seed1/2＝稳健性复核`，报告三种子均值±std → 三个 **划分种子** × 各自训练种子。
- 口径二（大纲 5.1「训练种子与划分种子分离」字面）：划分**固定 seed0**，3 个 **训练种子** 0/1/2 的均值±std。

**裁定（现行）**：`train.py --seed N` 同时读 `split_seed{N}.json` 并以 N 为训练种子，即 **seed0/1/2 = 三个划分 × 各自训练种子**，`summary.json` 报三种子均值±std、主表固定 seed0。理由：与 decisions §12「seed0 主划分、seed1/2 稳健性复核、报告三种子均值±std」最一致，也与 §9.1「主 seeds [0,1,2]」吻合。工程上用 `--split-seed`（默认=`--seed`）把两种种子**显式分离**，既满足「训练种子不改变划分」的可测性，又支持未来「固定划分 seed0、变训练种子」的稳健性补充实验——两种口径共用同一套代码，只差 CLI 传参，故无需提前锁死。

### 8.2 执行命令序列（主实验）

```bash
# 三 seed（每个 = 划分 seed + 训练 seed 同名）
python scripts/train.py --seed 0 --epochs 200 --batch-size 32
python scripts/train.py --seed 1 --epochs 200 --batch-size 32
python scripts/train.py --seed 2 --epochs 200 --batch-size 32
# 评估（读各自 best.pt + val 选阈值 + test 双报告）
python scripts/evaluate.py --seed 0
python scripts/evaluate.py --seed 1
python scripts/evaluate.py --seed 2
# 汇总
python scripts/evaluate.py --summarize        # 写 runs/summary.json
```

### 8.3 耗时估算（CPU，torch 2.0.1）

train 358 图/5.76 万节点/约 14 万边，batch=32 → 约 12 batch/epoch；两层 RGCN 每 batch ~5 千节点，CPU 前向+反向约 0.5–2 s/batch → 约 10–20 s/epoch（含 val）；早停通常在 50–100 epoch → **单 seed 约 10–30 分钟，三 seed 约 1–1.5 小时**。可行性确认。若后续装 CUDA 版 torch（RTX 4070 存在），直接复用同脚本。

---

## 9. 阶段 F：消融与基线（依赖 M5 主实验跑通）

复用 `Todo_List.md` §12.8 的映射表（**零重跑分层**：边=dataset、特征=NodeFuser、模型=开关；仅 CALLBACK_RISK 上限 4/不限制需重跑 M2）。

**5.4.1 必要消融（11 项）**：

| 变体 | 实现位置（零重跑除非标注） |
| --- | --- |
| 去 DFG_DEP / CFG_FLOW / AST_PARENT / CALLBACK_RISK | dataset `--drop-edges 3/0/4`、`--drop-ast`（=删 relation 1+2） |
| CALLBACK_RISK 上限 4 vs 不限制 | **重跑 M2** `--callback-limit 0` + 下游同步（唯一需要重跑项） |
| 去函数级 / 节点级 CodeBERT | model `AblationConfig(cb_channels=("cb_node",) / ("cb_func",))` |
| meanpool 替换 a_v 加权 | model `use_meanpool=True` |
| 关闭 L_var / 关闭先验 Dropout | train `--lambda-var 0` / `--prior-dropout 0` |
| 结构特征分组 (a)(b)(c) | model `feat_groups=base/base+sem/all`，报告 0.3pp 判定 |

**5.4.2 可选消融（6 项）**：CALLBACK_RISK_REV（重跑 M2 加反边）、L=1/2/3（model 加 `num_layers`）、num_bases、hid 128/256、DropEdge、微调 vs 冻结 CodeBERT。

**基线**（统一七维多标签 + BCE 训练，两种设定 MVD-HG 内部测试 + DIVE）：Slither 规则基线（`_m1.json` node_flags 图级聚合：任一节点命中该类→图命中，输出七维 0/1）、CodeBERT 序列、GCN（`conv_type="gcn"`）。GAT 需另行实现 RGAT，不作主实验硬依赖。

产物写 `eval_results/{ablation,baseline}/`，**不污染 `runs/` 主结果**；任何消融结果不得在主实验完成前替换主方案。

---

## 10. 阶段 G（阶段 5）：DIVE 外部测试 + SolidiFI 层次二

### 10.1 DIVE 外部测试（一次性，不参与任何模型选择）

1. **数据构建**（raw/graphs/features 待生成）：`generate_all_ast_cfg_dfg.sh` 已参数化（`SRC_ROOT` 等）；只处理 `sample_seed0.json` 的 **900** 个 id（把对应源文件拷入临时目录作 `SRC_ROOT`）；过滤统计写 `products/dive/raw/filter_report.txt`（按数据集、**按漏洞类别**报告被过滤数量与占比）。
2. **M3 特征**：`m3_build_features.py` **必须传 `--categories products/alldata/graphs/ir_cat.json`** 冻结 IR 字典，否则 IR one-hot 列宽/语义漂移、`NodeFuser` 输入维错位。
3. **标签/命名**：DIVE 产物前缀无 `项目__` 段（如 `8263_hetero.json`），标签按文件名 stem 匹配 `DIVE/contract_labels.json`（已剔 Bad Randomness，七维直接用）——需为 DIVE 扩展一个按 stem 建索引的加载路径（不复用 `dataset.build_index` 的项目前缀逻辑）。
4. **评估口径**（手册 10.5 层次一 + 5.5.1）：用主实验 `seed0` 的 `best.pt` + 验证集阈值；报告 MVD-HG→DIVE 的 micro-F1/macro-F1/每类 F1 变化、每类 PR-AUC（不依赖阈值，先验失配下更稳）、**DIVE 全零标签子集每类 FPR**、20–30 例 FN/FP 人工检查归类、归因分层（标注口径/先验/solc 版本/预处理过滤/真实泛化）。**不得用 DIVE 结果回头调参/调阈值**。结果写 `eval_results/dive/`。

### 10.2 SolidiFI 层次二（合成注入节点覆盖）

1. **映射**：`buggy_logs/*.csv` 的 `loc` 落到 SlithIR CFGNode（`line_start ≤ loc ≤ line_end`，多节点取行区间最小者）；映射不上的样本剔除并报告数量/占比。
2. **三分数**：`a_v`（模型）、`s_v`（`_m1.json` 先验）、`g_v,k`（梯度显著性，`autograd.grad` 对 `h2`，类别归属按注入类别；多注入类分别算或取 max，预测正确/错误分开统计）——各自 `Precision@k / Recall@k / IoU`。
3. **a_v 增量覆盖节点**：a_v 的 TopK 中「s_v 排名在 50% 之后」的节点数，接近 0 即说明图传播未带来超出静态规则的定位收益。
4. 诚实声明：SolidiFI 是语法级注入，结果主要反映 s_v，不代表真实根因定位。结果写 `eval_results/solidifi/`。

---

## 11. 风险、工程取舍与已裁定项

1. **批图方式（自实现 collate vs PyG DataLoader）**：本方案选自实现 collate——数据是自定义通道字典而非标准 `Data`，`NodeFuser` 已设计为「批通道 + batch 向量」接口；自实现可完全确定、无 worker 复杂度、CPU 单进程足够。**代价**：放弃 DataLoader 的并行预取与 worker seed（decisions §6 的 `seed+worker_id` 仅在有 worker 时才适用，CPU 单进程不涉及）。若后续要 GPU/多进程，再包一层 DataLoader，接口不变。
2. **训练/划分种子语义**：见 §8.1，**已裁定**——口径一/二共用代码，`--split-seed` 显式分离，默认 `--split-seed == --seed`（记录于 `experiments/decisions.md` §16）。
3. **checkpoint 双模块**：`fuser` 与 `model` 是独立模块，漏存其一即恢复失败——已列为 smoke 断言。
4. **val 只有 45 图、多类 support=1**：val micro-F1 会因单图翻转而抖动，早停/阈值选择在极小集上敏感；按手册记录 train/val 差距，不据此调协议。测试集 support≤2 的类仅描述性呈现。
5. **CPU 训练耗时**：见 §8.3，单 seed 约 10–30 分钟，可行；不引入 AMP/warmup/ensemble（decisions §8 不纳入主方案）。
6. **`NodeFuser` 输入维 1631** 固定由 `D_struct=30`/`cb_channels=2`/`type_dim=64` 决定；`--cb-channels` 消融会改变 `proj.in_features`，必须从 `fuser.in_dim` 回读传给 `SSMHG(in_dim=...)`，不得硬编码 128/1631。

---

## 12. 验收清单（对齐手册 §10.7 / §13）

- [ ] 训练无 NaN；`loss_total/loss_cls/loss_var/score_mean/score_std` 每 epoch 有日志。
- [ ] val micro-F1 随 epoch 上升，连续 5 epoch 不提升自动早停（macro-F1 同步记录）。
- [ ] 阈值只在 val 选（0.2–0.8，目标 val micro-F1，tie 取小）；固定 0.5 与搜索阈值双报告。
- [ ] pos_weight 按训练集计算并截断 20；零正类用 class-mask（非 pos_weight=0）；全零正类报错。
- [ ] 逐类 F1 与 per-class PR-AUC 随 support 报告；support≤2 的类仅描述性呈现。
- [ ] 3 种子跑完，`runs/summary.json` 报均值±标准差；每 run 有 config/log/best.pt/last.pt/results/thresholds/val_best_probs.pt。
- [ ] 论文口径数字全部取自 `docs/data_funnel.md`；多标签主张按「架构性声明 + DIVE 外部证据」。
- [ ] 消融 5.4.1/5.4.2 与基线在 MVD-HG 内部测试 + DIVE 两设定评估，写 `eval_results/`，不污染 `runs/`。
- [ ] M5 CI smoke 覆盖 split/loss/L_var/batch/train-one-step/eval-threshold；完整 3-seed 训练不进 CI。
