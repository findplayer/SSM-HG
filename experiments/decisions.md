# M5 实验决议

> 版本：v5，2026-09-08
> 适用范围：MVD-HG 图级七类多标签主实验、内部消融与效率记录。

## 0. v5 对外部建议的审查结论

本版吸收了对数值稳定性、数据划分可复现性、DropEdge 图归属和训练可观测性的合理建议；不因 AI 建议本身改变论文大纲已经锁定的主实验协议。

- **采纳为硬性实现要求**：class-masked BCE 的活动类分母；按图 population std 的 `L_var`；先单图生成 DropEdge mask 后 batch；split 依赖、模块、API 和版本校验；零正类、梯度、图归属、阈值隔离的 smoke/unit 测试；保存验证集概率和训练统计。
- **部分采纳**：增加 `--deterministic`，但只作为可复现性开关，不作为主实验默认值；记录它对性能和运行配置的影响。增加 `train_graphs_processed`，但同时区分“本 epoch”和“累计”口径，避免字段含义含混。
- **不纳入主方案**：对 `pos_weight` 加平滑项。大纲明确为 `neg/pos` 并截断 20，加入 alpha 会改变损失定义；如有必要只能作为独立敏感性实验。
- **纠正具体错误**：发行包名 `iterative-stratification` 不等于 Python 导入名。实现应校验发行包元数据，并导入实际 API（当前环境通常为 `iterstrat.ml_stratifiers.MultilabelStratifiedShuffleSplit`）；二者任一缺失或 API 不兼容都必须失败，不能回退随机划分。
- **边界澄清**：`L_var` 的 epsilon 只用于数值保护，单节点图的标准差语义仍为 0；不能用 `sqrt(clamp(var, 1e-12))` 把单节点图变成非零标准差。DropEdge 的随机性以运行 seed 和样本/epoch 的稳定索引可追溯即可，不要求把每个 mask 固化成数据集文件。
- **不把工程便利误写成科学结论**：`reproduce.sh`、保存验证概率、deterministic 模式属于复现与审计能力，不改变模型、划分、指标或主结果。

v5 的执行优先级是：先实现并测试数据划分与损失，再实现训练闭环，最后实现评估、汇总和消融；任何一项未通过窄范围 smoke，不进入下一项。

## 1. 数据划分

- 主方案：多标签迭代分层，比例 8:1:1。
- 实现：固定版本的 `iterative-stratification`，记录包版本、算法版本、seed 和划分比例。
- 样本单位：`dataset.build_index()` 产生的图前缀。不得仅凭 `asd_`/`nasd_` 前缀合并样本；若未来按内容哈希成对约束，必须作为独立实验报告。
- 旧随机划分保留为可追溯对照，不作为主结果。
- 每个 split 输出逐类正样本 support；无正样本类别保留在标签向量中，并在评估中标记 `support=0`、跳过 AP。
- 依赖缺失时直接报错，不静默回退随机划分。
- 安装包名为 `iterative-stratification`；代码必须验证实际模块/API 和版本，不能只检查字符串包名。每次 run 另保存 split metadata，避免全局文件被不同实验覆盖。
- 生成 `splits.csv`，列为 `sample_id, split, y0..y6`；同时在每个 `runs/seedN/config.json` 保存 split 算法、版本、seed 和文件摘要。

## 2. 图级损失

- 标签顺序固定为：`access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`。
- 只使用训练集统计 `pos_c` 和 `neg_c`。
- 若 `pos_c > 0`：`pos_weight_c = min(neg_c / pos_c, 20)`。
- 若 `pos_c == 0`：使用 `class_mask[c] = 0` 从逐元素 BCE 的分子和分母中排除该类别，不使用 `pos_weight=0`。
- 若所有类别均为 zero-positive，直接报错。
- 记录 active/skipped 类别、`pos_c`、`neg_c` 和最终权重。
- 必须有 zero-positive 合成测试：该类 loss 被排除、训练无 NaN、日志显示 skipped 类别。

逐元素形式：

```text
bce = binary_cross_entropy_with_logits(logits, targets, reduction="none")
weighted = bce * (targets * pos_weight + (1 - targets))
weighted = weighted * class_mask
loss_cls = weighted.sum() / (batch_size * active_class_count)
```

这里的 `targets` 是 0/1，因此正样本项和负样本项不会被错误混合。

## 3. 方差保持损失

- `tau = 0.1`，`lambda_var = 1e-3`。
- 在每个图内部计算 `a = sigmoid(node_logits)` 的方差和标准差。
- 使用 population standard deviation，即等价于 `torch.std(a, unbiased=False)`；单节点图的 std 定义为 0，不产生 NaN。
- 计算过程不 `detach()`，必须能把梯度传回 `node_logits`、`a_head` 和 GNN。
- batch 图使用 `batch` 索引或等价的 `index_add_` 分组；不得把不同图的节点混合计算。
- 必须测试单节点图 `std == 0`、多图分别计算、反向后 `a_head` 和 GNN 梯度非空。

## 4. 优化与正则

- 优化器：AdamW。
- 初始学习率：`1e-4`。
- 权重衰减：`1e-4`。
- 梯度裁剪：`max_norm=1.0`。
- 最大 epoch：`200`。
- 学习率调度：`ReduceLROnPlateau(mode="max", factor=0.5, patience=3)`，监控验证集 macro-F1。
- 早停：验证集 macro-F1 连续 5 个 epoch 不提升。
- DropEdge 默认关闭；启用时必须在单图上先生成 mask，再拼接 batch，并同步过滤 `edge_index` 和 `edge_type`。
- DropEdge 启用时记录每图删除数量或比例；默认关闭不纳入主实验结论。
- 先验 dropout：训练时按图以 0.2 概率切换到 `_feat_no-prior.pt`；验证/测试使用 `_feat.pt`。不在 128 维 `h_v^(0)` 上随机清零模拟先验 dropout。

## 5. 阈值与评估

- 主阈值：在验证集搜索全局单一阈值 `0.20, 0.25, ..., 0.80`，目标为 macro-F1。
- 并列时选较小阈值，规则固定且偏向召回。
- 测试集报告固定阈值 0.5 和验证集选择阈值两套结果。
- per-class 阈值只作补充分析，不进入主结果。
- AP/mAP 对 zero-positive 类跳过，并报告 `ap_classes_used`。
- 保存全部候选阈值及其验证集指标到 `runs/seedN/thresholds.json`，包括 tie 的最终选择依据。

## 6. 随机性与运行产物

- 每个 seed 设置 Python、NumPy、PyTorch 和 CUDA seed；DataLoader worker 使用可追溯的 `seed + worker_id`。
- 默认主实验 seeds 为 `[0, 1, 2]`，报告 mean +/- std；资源允许时增加 3、4。
- checkpoint 至少保存 `model_state_dict`、`optimizer_state_dict`、epoch、best metric、config 和 seed。
- 每个 epoch 的 `log.txt` 写一行 JSONL，包含：
  `epoch, loss_total, loss_cls, loss_var, mask_mean, mask_std, val_macro_f1, val_micro_f1, lr, epoch_seconds`。
- `config.json`、`results.json` 保存 split、模型、损失、随机性、环境和计时配置。
- 可选保存验证集概率和每个 seed 的预测文件，服务于阈值敏感性分析；不改变主训练协议。

## 7. 计时口径

- 使用 `time.perf_counter()`，不要使用 wall-clock 日期时间计算间隔。
- 记录：`run_wall_seconds`、`data_load_seconds`、`train_seconds`、`validation_seconds`、`epoch_seconds_mean`、`graphs_per_second`。
- epoch JSONL 另记录 `samples_processed`、`graphs_processed` 和当前 `lr`；显卡可用时记录 `gpu_mem_allocated`，不可用时写 `null`。
- 同时记录 device、torch version、CUDA version（如有）、线程数、batch size、训练图数、节点数、边数和完成 epoch 数。
- `train_seconds` 表示 optimizer training loop 的累计时间；`run_wall_seconds` 包含数据加载、训练、验证、checkpoint 和结果写盘。
- 与其他工具比较时，优先比较相同数据、相同 batch、相同设备和相同计时边界下的 `train_seconds` 与吞吐量；耗时不替代准确率指标。
- `graphs_per_second = train_graphs / train_seconds`，只统计 optimizer training loop，不包含验证、checkpoint 或 I/O。GPU 内核计时需同步设备后再读时钟。

## 8. 不纳入主方案的建议

AMP、warmup、top-k checkpoint、ensemble、把极少数类别直接移出七类任务，均不纳入第一版主实验。它们可以作为独立效率、稳定性或敏感性实验，不能改变主实验协议。CI smoke 必须覆盖 split、dataset/batch、model backward、train one-step 和 eval threshold；完整 3-seed 训练不纳入每次 PR CI。

不要求批图和逐图结果浮点逐位相等；验收关注图归属、形状、有限值、梯度连通性和明确的数值容差。

## 9. M5 v5 详细开发计划

### 9.1 目标与不变项

M5 的目标是完成图级七类多标签分类的训练、验证、测试、阈值选择、三种子汇总和可追溯实验记录。M1 先验只作为 M3 输入特征，`a_v` 只作为节点可疑度/解释信号；不得把节点分数当作节点真值，也不得把验证集或测试集统计用于训练损失。

固定不变项：标签顺序为 `access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`；主划分 8:1:1；主 seeds 为 `[0,1,2]`；模型默认 RGCN、两层、hidden=128、5 类关系、`num_bases=5`；主阈值只从验证集选择一个全局阈值；测试同时报告 0.5 和验证集阈值。

### 9.2 当前实现差距

截至 v5 决议：`model.py`、`dataset.py` 和 M4 smoke 已完成；`make_splits.py` 当前仍使用随机划分，必须改为迭代分层；`metrics.py`、`train.py`、`evaluate.py` 和 M5 CI smoke 尚未完成。当前环境未安装 `iterative-stratification`，因此在依赖安装并通过 API 校验前不得生成新的主实验 split。

### 9.3 阶段 A：依赖与迭代分层

修改 `scripts/make_splits.py`：

1. 校验发行包 `iterative-stratification` 的元数据版本，并导入 `iterstrat.ml_stratifiers` 的实际 API；检查 `MultilabelStratifiedShuffleSplit` 可用。包缺失、模块缺失、API 不兼容或版本不符合记录要求时直接报错。
2. 以 `dataset.build_index()` 返回的图前缀为唯一样本单位，先剔除已定义的 `buggy_*` 项目，再对多热标签做两阶段迭代分层：先划出 10% test，再从剩余 90% 划出相当于总量 10% 的 val，得到 80/10/10。每次划分都固定 `random_state=seed`，并断言三集合互斥、全覆盖且样本数正确。
3. 保留旧随机划分为明确命名的对照，不覆盖主 split，也不允许隐式回退。
4. 输出 `split_seed{seed}.json`、`splits.csv`、`split_report.json`、`split_metadata_seed{seed}.json` 和 `unmatched_contracts.txt`。metadata 至少包含发行包名、导入模块/API、版本、seed、比例、算法参数、输入样本摘要和输出文件摘要。
5. 报告每个 split 的逐类 support、zero-positive 类、多标签样本、全零样本、buggy 剔除数和 unmatched 数。

验收：同一环境同一 seed 的 CSV 字节级一致；不同 seed 的划分允许不同；缺包测试必须失败而非随机回退；三集合无交集且并集等于纳入样本。

### 9.4 阶段 B：数据层与 batch/DropEdge

保持 `scripts/dataset.py` 的职责边界：加载 `_pyg.pt` 结构和 128 维 `_feat.pt`，执行标签对齐及边级消融，不在此处重复 MLP。新增或补齐训练侧 batch helper：

- 每个图在进入 batch 前生成自己的 DropEdge keep mask；mask 只作用于该图的本地边，并通过 `model.apply_edge_mask` 同步过滤 `edge_index` 与 `edge_type`。
- 之后再做节点偏移和 batch 拼接。验证、测试默认不丢边。
- 若开启 DropEdge，使用 `seed + epoch + stable_graph_index` 生成可追溯随机流，并记录每 epoch 的删除边数/比例；默认关闭。
- 先验 dropout 不在 128 维向量上随机清零，而是训练时按图以 0.2 概率加载对应的 `_feat_no-prior.pt`；验证和测试始终使用 `_feat.pt`。运行主实验前必须批量生成该变体。

验收：双图 toy case 中不存在跨图边；相同 seed/epoch/样本顺序产生相同 mask；不同图的 mask 互不污染；DropEdge=0 与不启用时保持结构一致。

### 9.5 阶段 C：损失函数与训练基础设施

新建 `scripts/train.py`，先实现可独立单测的纯函数，再接训练循环。

**类别统计与 masked BCE**

- 仅用训练集统计 `pos_c`、`neg_c`。
- `pos_c>0` 时 `pos_weight_c=min(neg_c/pos_c,20)`；不加平滑项。
- `pos_c==0` 时 `class_mask[c]=0`，从逐元素 BCE 的分子和分母同时排除；若所有类均为 zero-positive，直接报错。
- `loss_cls = weighted.sum() / (batch_size * active_class_count)`，并断言 active 类数大于 0。
- 配置和日志记录 `active/skipped classes`、`train_pos`、`train_neg`、`pos_weight` 和分母口径。不得用 `pos_weight=0` 代替 mask。

**按图 `L_var`**

- `a=sigmoid(node_logits)`，按 `batch` 分组计算 population std；等价于 `torch.std(unbiased=False)`。
- 推荐用 `sum`、`sum of squares` 和节点计数计算，`var` 做非负 clamp 后开方；对 `n==1` 显式返回 std=0，对 `n==0` 直接报错。
- epsilon 仅防止浮点负零或池化分母问题，不改变单节点 std=0 的语义。
- 计算不 detach，`loss_total=loss_cls+1e-3*mean(relu(0.1-std))` 的梯度必须连到 `a_head` 和 GNN。

**训练循环**

- AdamW，lr=`1e-4`，weight decay=`1e-4`，梯度裁剪 max-norm=1.0，最多 200 epoch。
- `ReduceLROnPlateau(mode="max", factor=0.5, patience=3)` 监控验证 macro-F1；连续 5 个 epoch 无提升早停。
- 每 epoch 记录 JSONL：loss 三项、mask mean/std、val macro/micro-F1、lr、epoch_seconds、epoch/累计 graphs processed、samples processed、DropEdge 统计和 GPU memory（无 GPU 为 null）。
- 用 `time.perf_counter()` 记录 `data_load_seconds`、`train_seconds`、`validation_seconds`、`run_wall_seconds`、平均 epoch 时间和 graphs/sec；`train_seconds` 仅含 optimizer loop。
- 默认普通随机训练即可；`--deterministic` 开启完整确定性设置并写入 config，同时记录可能的性能代价，不把它强行设为主实验默认。

产物：`runs/seedN/{config.json,log.txt,best.pt,last.pt,results.json,val_best_probs.pt}`。checkpoint 至少包含模型、优化器、epoch、best metric、config 和 seed。

### 9.6 阶段 D：指标、阈值和评估

新建 `scripts/metrics.py`，只实现指标纯函数，不依赖 dataset/model；新建 `scripts/evaluate.py`，只负责加载 checkpoint、推理和写报告。

- `metrics.py` 提供 macro/micro-F1、每类 precision/recall/F1、mAP/AP、support 统计和全局阈值扫描。
- 阈值候选为 `0.20,0.25,...,0.80`，只在 val 上计算 macro-F1；并列取较小值。保存全部候选值、指标和 tie 选择理由。
- zero-positive 类保留在七维标签中，报告 `support=0`，跳过该类 AP，并记录 `ap_classes_used`。
- 测试只使用训练完成后的模型和 val 选出的单一阈值；报告固定 0.5 与选择阈值两套结果，不用 test 调阈值。
- 保存最佳 checkpoint 的验证概率，避免为阈值敏感性分析重复推理；这属于复现便利，不改变协议。
- `evaluate.py` 写每个 seed 的结果，并汇总 `runs/summary.json` 的三 seed mean +/- std；消融和规则/序列/GCN 等基线写入 `eval_results/`，不污染主结果。

### 9.7 阶段 E：测试与 CI smoke

新增窄范围测试，优先保证失败能定位到单一契约：

1. split：同 seed 可复现、三集合互斥全覆盖、缺依赖显式失败、逐类 support 正确。
2. loss：zero-positive 类被排除且无 NaN；分母为 `B*active_class_count`；pos_weight 截断 20。
3. `L_var`：单节点 std=0；多图分别计算；反向后 `a_head` 与 GNN 梯度非空。
4. dataset/batch：边偏移正确、无跨图边、DropEdge 同步过滤且同 seed 可复现。
5. train：`--limit-graphs 1` 完成 forward/backward、checkpoint 保存和恢复，日志字段齐全。
6. evaluate：只用 val 选阈值；test 同时输出 0.5 和 val threshold；zero-positive AP 跳过。

现有 M4 的 22 个 smoke 用例继续保留；完整三 seed 训练不进入 PR CI。

### 9.8 阶段 F：复现实验、消融与最终验收

可新增 `scripts/reproduce.sh`，读取指定 `runs/seedN/config.json`、split metadata 和 `splits.csv`，先检查输入摘要与当前文件一致，再复现实验。它是工程辅助工具，不得修改主协议或静默安装依赖。

M5 v5 完成标准：主 split 由经 API 校验的迭代分层生成；单图和 batch 训练 smoke 全绿；三 seed 均可完成或明确记录资源阻塞；每个 run 有 checkpoint、配置、JSONL 日志、阈值明细、验证概率和结果；summary 报告 mean +/- std；消融严格区分特征、边、模型和数据范围；论文所需的样本数、support、损失、阈值、设备和计时信息均可从产物恢复。

## 10. v5 实施顺序

1. 安装并校验 `iterative-stratification`，改造 `make_splits.py`，完成 split smoke。
2. 生成 `_feat_no-prior.pt`，补齐 batch/DropEdge helper 及测试。
3. 新建 `metrics.py`，实现 masked BCE、`L_var`、阈值扫描的纯函数测试。
4. 实现 `train.py`，先 `--limit-graphs 1`，再单 seed 小规模运行。
5. 实现 `evaluate.py`，完成阈值双报告和最佳验证概率保存。
6. 运行 seed 0，再运行 seeds 1/2，生成 `runs/summary.json`。
7. 最后开展消融、基线和外部数据评估；任何主方案结果不得在主实验完成前被消融设置替换。
