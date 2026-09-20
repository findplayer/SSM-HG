# M5 实验决议

> 版本：v5，2026-09-08（2026-09-12 补录 §11 划分门槛修订；凡与大纲 `研究点一细化大纲改II.docx` 冲突处，以大纲为准）
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

> **状态（2026-09-12）：本节与 §9.3 已被 §11–§12–§14 取代。** 主方案改为「固定种子 8:1:1 + 覆盖约束校正（`--strategy constrained`）+ 两级池去重（`--dedup source-sha1+address`）」，迭代分层仅保留为对照快照；现行划分：池 448、358/45/45、替换 18/16/12。以下旧决议仅存历史参考。

- 主方案：多标签迭代分层，比例 8:1:1。（**已废止**，见上）
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
- 截断上限默认 20，`--pos-weight-cap` 可调（`0`/负数 = 不截断）。消融（2026-09-14，`runs/pw_unclamped/`）：放开截断后稀有类（dos/front_running/time_manipulation）仍 F1≈0、arithmetic 反降（0.656→0.316）、固定 0.5 主指标 micro-F1 0.906→0.815，故**维持 cap=20**；结论见 `experiments/results.md` §1.8。
- 损失形状默认 `bce`；`--loss {focal,asl}` + `--focal-gamma/--asl-gamma-pos/--asl-gamma-neg/--asl-clip` 为消融开关，**共用同一 `pos_weight` 加权结构与 class_mask、同一分母 `B×active_class_count`**（唯一变量 = 调制因子；不采用 ASL 原文的按正样本数归一，以免损失尺度与 lr/早停混淆）。消融（2026-09-14，`runs/loss_focal/`、`runs/loss_asl/`）：验证阈值下 micro-F1 基线 0.9492 / focal 0.9503 / ASL 0.9481，逐种子差 ≤0.006（小于种子噪声）；ASL 固定 0.5 因负样本调制压零而崩溃（0.5672±0.1756）；稀有类三者在三种损失下仍 F1=0 → **维持 bce 为主实验口径**；结论见 `experiments/results.md` §1.10。
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
- 学习率调度：`ReduceLROnPlateau(mode="max", factor=0.5, patience=3)`，监控验证集 **micro-F1**（2026-09-12 由 macro-F1 改，见 §13 第 2 条；macro-F1 同步记录作参考）。
- 早停：验证集 **micro-F1** 连续 5 个 epoch 不提升（同上）。
- DropEdge 默认关闭；启用时必须在单图上先生成 mask，再拼接 batch，并同步过滤 `edge_index` 和 `edge_type`。
- DropEdge 启用时记录每图删除数量或比例；默认关闭不纳入主实验结论。
- 先验 dropout（4.1.4）：**已改为模型内实现（2026-09-12 P1 前端化，已实施）**——`model.NodeFuser.forward`
  在**融合 Linear 之前**按图 `Bernoulli(0.2)` 把该图 `sv` 通道乘 0（仅训练期；eval 不置零）；
  确定性去先验为独立配置项 `AblationConfig(ablate_sv=True)`（train/eval 一致）。两者共用同一掩码原语，
  由 `tests/test_frontend.py` 的 T1 无泄漏单测逐位验证；`_feat_no-prior.pt` 与「按图切换文件」整套设计**已退役**。

## 5. 阈值与评估

- 主阈值：在验证集搜索全局单一阈值 `0.20, 0.25, ..., 0.80`，目标为 **micro-F1**（2026-09-12 由 macro-F1 改，见 §13 第 2 条；macro-F1 同步记录作参考）。
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

> **状态（2026-09-12）：本节描述已过时。** `make_splits.py` 已按 §12/§14 实现（覆盖约束校正 + 两级去重，`--strategy constrained`），**不再需要** `iterative-stratification`（迭代分层仅作对照快照）；现行剩余差距仅 `metrics.py`、`train.py`、`evaluate.py` 与 M5 CI smoke。

截至 v5 决议：`model.py`、`dataset.py` 和 M4 smoke 已完成；`make_splits.py` 当前仍使用随机划分，必须改为迭代分层；`metrics.py`、`train.py`、`evaluate.py` 和 M5 CI smoke 尚未完成。当前环境未安装 `iterative-stratification`，因此在依赖安装并通过 API 校验前不得生成新的主实验 split。

### 9.3 阶段 A：依赖与迭代分层

> **状态（2026-09-12）：本阶段已被 §12（覆盖约束校正）与 §14（两级池去重）取代**，`iterative-stratification` 不再作为主方案依赖；以下旧计划仅存历史参考。

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
- 先验 dropout **已在模型内实现（2026-09-12 P1，已实施）**：`NodeFuser` 在**融合 Linear 之前**按图 Bernoulli(0.2) 把 `sv` 通道乘 0（仅训练期）；验证/测试不置零。**不再需要 `_feat_no-prior.pt`，也不再按图切换文件**（该设计已退役，旧特征已归档 `graphs/legacy_feat_pre_frontend/`）。

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
- `ReduceLROnPlateau(mode="max", factor=0.5, patience=3)` 监控验证 **micro-F1**（2026-09-12 由 macro-F1 改，见 §13）；连续 5 个 epoch 无提升早停。
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

> **状态（2026-09-12）：第 1 步已废止**（`make_splits.py` 已按 §12/§14 实现，不再依赖 `iterative-stratification`）；第 2 步的 `_feat_no-prior.pt` 已随前端化退役（先验 dropout 在 `model.NodeFuser` 内实现）；其余步骤仍为 M5 执行顺序参考。

1. ~~安装并校验 `iterative-stratification`，改造 `make_splits.py`，完成 split smoke。~~（已废止，见上）
2. 生成 `_feat_no-prior.pt`，补齐 batch/DropEdge helper 及测试。
3. 新建 `metrics.py`，实现 masked BCE、`L_var`、阈值扫描的纯函数测试。
4. 实现 `train.py`，先 `--limit-graphs 1`，再单 seed 小规模运行。
5. 实现 `evaluate.py`，完成阈值双报告和最佳验证概率保存。
6. 运行 seed 0，再运行 seeds 1/2，生成 `runs/summary.json`。
7. 最后开展消融、基线和外部数据评估；任何主方案结果不得在主实验完成前被消融设置替换。

---

## 11. 划分门槛修订（2026-09-12；**已被 §12 取代**——门槛由覆盖约束校正构造保证；本节保留为修订过程记录；以大纲 `改II` 5.1 为准）

- **口径修订**：大纲 5.1 第三条由“验证或内部测试划分中正样本少于 20 个则换种子”修订为：**验证集与内部测试集中的正样本合计少于该类正样本总数的30%，则更换随机种子重新划分**。取“合计”而非“逐划分”：逐划分 30% 会使 front_running 等低频类的 val+test 需求超过其池内全部正样本（数学上不可行）；“≥20 个”绝对门槛对池内 5/7 类同样不可达（该类正样本本身 <20）。
- **实现同步**（`scripts/make_splits.py`，纯增量）：`split_report.json` 增加逐种子×三划分逐类 support 与 `rule_check`（含 `min_pos_ratio=0.30` 的逐类 threshold/ok）；新增 `splits.csv`（列为 `seed,sample_id,split,y0..y6`；v5 §1 所述 `sample_id,split,y0..y6` 为单种子快照口径，现为三种子合一表）与 `split_metadata_seed{seed}.json`（参数、输入摘要、输出 sha256）；CLI 增 `--min-pos-ratio`（默认 0.30，替代原计划 `--min-pos 20`）。划分算法与三种子成员与重生成前**逐字节一致**（split_seed0/1/2 与 unmatched 的 sha256 校验通过）。
- **实测结果**：三种子均未达标——seed0 5/7 类不足（实际/需求下限：access_control 0/5、arithmetic 2/5、front_running 1/2、reentrancy 8/10、uncheck 9/16），seed1 6/7 类不足，seed2 6/7 类不足（明细见 `products/alldata/splits/split_report.json` 的 `rule_check`）。随机划分下 val+test 各占 10% 规模、类正样本期望占比 ≈20% < 30%，**换种子无法解决**。
- **待决策**：(a) 在 `make_splits.py` 增加覆盖率约束的分层重划模式（保证合计 ≥30% 达标，且保持唯一合约与 8:1:1 规模），或 (b) 按数据稀疏性在论文中以局限说明记录。**主划分种子**（论文固定报告用）随该决策一并选定。
- 说明：DIVE 外部测试子集的“每类 ≥20 正样本”抽样门槛（大纲 5.1 第六条）不在本次修订范围（DIVE 数据充足、门槛可行）。（本节“待决策”已由 §12 落地解决；保留为过程记录。）

---

## 12. 覆盖约束校正落地（A2 实施，2026-09-12）

> **本节为历史过程记录（预去重池 495，划分 396/50/49）**：2026-09-12 P1 两级池去重（§14）
> 把池改为 **448**、划分改为 **358/45/45**，替换数与支撑数字均已刷新。算法、约束与产物结构不变，
> 仅池规模与具体成员不同；引用现行数字请用 §14。

- **决策**：采纳 A2——在**固定种子随机划分**基础上施加**覆盖约束校正**（大纲 5.1 第三条新增半句为权威依据：验证集与内部测试集合计的每类正样本不少于该类正样本总数的30%，且两个划分各自至少包含每类正样本一次；校正通过少量确定性合约替换实现）。
- **算法**（完全确定性、可复现；`scripts/make_splits.py::refine_coverage`）：基线＝`sorted(pool)` + `Random(seed).shuffle` + 顺序切 396/50/49；缺口按（池内正样本数升序，类序）处理（稀有类优先）；换入＝按 train 顺序首个携带该类正样本的合约；换出＝从目标划分列表尾部向前首个 7 维全零合约（绝不换出正样本，代码断言）；放置＝放入该类当前较少的一侧（平局→val）；不可行时报错，由实验方按大纲更换种子。
- **接口与产物**：`--strategy {constrained(默认), random}`；**random 模式输出隔离**到 `<out-dir>/random_snapshot/`（仅对照/复现，不可能覆盖正典产物）；新增 `coverage_swaps_seed{seed}.txt`（换入/换出合约 ID + 7 维标签向量）；`split_report.json` 的 `rule_check` 增 C2（每划分每类 ≥1）与 `coverage_fix`（swaps_count/floor_fixes）；`split_metadata_seed*.json` 记录 strategy/constraints/algorithm；`split_seed*.json` 载荷保持 `{seed,ratio,train,val,test}` 四键不变（保证 random 模式逐字节复现旧快照）。
- **验收结果**（三种子，逐项与试算一致）：替换 18/19/17 个合约（占 495 的 3.4–3.8%；其中每划分下限修正 1/0/1）；eval 保留旧成员 81/80/82（99 中）；**eval 正样本合计 44/42/43（C1 需求 ≥42）**；C1/C2 全 7/7 类达标；同种子两次运行逐字节一致；random 快照与 A2 前旧产物内容逐字节一致；`pytest` 25 通过（含 3 个新增 split 用例）。
  - **2026-09-12 补注（P1 后）**：上述数字属**预去重口径**（池 495、划分 396/50/49）。经两级池去重后已刷新为池 448、划分 358/45/45、替换 18/16/12，见 §14。`--strategy random --dedup none` 的**划分成员仍逐字节可复现**（`split_seed*.json`、`splits.csv` 与既有 `random_snapshot/` 完全一致）；仅 `split_report.json` / `split_metadata_seed*.json` 多出 `dedup` 字段、并新增 `dedup_dropped.txt`（复现校验：2026-09-12，`diff -r` 仅报这几处）。
- **前后支撑对照**（OLD=随机基线，NEW=校正后；顺序 ac/ar/dos/fr/re/tm/un；单元=该类正样本数）：

| seed | eval OLD（val-test-合计） | eval NEW（val-test-合计） | train OLD | train NEW |
| --- | --- | --- | --- | --- |
| 0 | 0-0-0 / 0-2-2 / 1-2-3 / 1-0-1 / 4-4-8 / 0-2-2 / 4-5-9 | 3-2-5 / 3-2-5 / 1-2-3 / 1-1-2 / 5-5-10 / 1-2-3 / 8-8-16 | 15/13/3/3/24/3/42 | 10/10/3/2/22/2/35 |
| 1 | 3-0-3 / 1-1-2 / 1-0-1 / 0-0-0 / 3-3-6 / 1-1-2 / 4-4-8 | 3-2-5 / 3-2-5 / 1-1-2 / 1-1-2 / 5-5-10 / 1-1-2 / 8-8-16 | 12/13/5/4/26/3/43 | 10/10/4/2/22/3/35 |
| 2 | 0-2-2 / 1-1-2 / 0-2-2 / 1-0-1 / 4-3-7 / 1-0-1 / 6-5-11 | 3-2-5 / 3-2-5 / 1-2-3 / 1-1-2 / 5-5-10 / 1-1-2 / 8-8-16 | 13/13/4/3/25/4/40 | 10/10/3/2/22/3/35 |

- **主划分种子用途定位声明**：**seed0＝论文主实验与全部主结果的唯一划分**（固定报告；基线/消融默认使用 `split_seed0.json`/`splits.csv` 中 seed=0）；**seed1、seed2＝稳健性复核**（报告三种子均值±std，不单独作为主表结果；三者算法/约束/报告字段完全一致）；**`random_snapshot/`＝仅用于复现历史随机快照与对照分析**，不构成任何实验结果、不作为划分候选；划分算法或约束任何变更必须重跑 `make_splits.py` 并同步更新本声明。
- **论文写作须知**：校正只换出全零合约、换入稀有类正样本，扰动约 3.4–3.8%，其余成员与随机基线一致；eval 的类别先验被人为抬高（≈43% vs 池 26%），须在论文“数据划分”小节明示；front_running/time_manipulation 的 eval 支撑仍仅 1–2（数据天花板），结合 DIVE 逐类 PR-AUC 报告。
  - **P1 去重后口径（现行，2026-09-12 补）**：扰动 **18/16/12 个（占 448 的 4.0%/3.6%/2.7%）**；eval 正样本合计 42/41/41（占 eval 90 个的 ≈46.7%/45.6%/45.6%），**类别先验被抬高至 ≈46% vs 池 27.9%**——论文须用现行数字，引用预去重数字须注明口径。

---

## 13. P0 口径修正（2026-09-12，最小改动；主指标 / 叙事 / 支撑口径，一条合并决议）

> 依据：`docs/data_funnel.md`（由 `python scripts/audit_data_funnel.py` 生成，每个数字带产物出处；机器可读版 `products/alldata/splits/data_funnel.json`）。
> 事实前提：训练池 = **448 个源文件级样本**（591 源 → 581 图 → 剔 86 个 `buggy_*` = 495 → 两级去重丢 47，见 §14），池内正样本 125、全零 323、**多标签 1**；逐类池内正样本：access_control 15 / arithmetic 15 / dos 6 / front_running 4 / reentrancy 31 / time_manipulation 5 / uncheck 50。
> **本节数字已按 §14（2026-09-12 P1）刷新**；§14.2 列出刷新前后的逐项对照。

1. **主指标改 micro-F1**：同分布内部测试与 DIVE 外部测试均以 **micro-F1（标签对级）**为主指标；**macro-F1 降为参考指标**，且报告时必须注明其构成——池内 **3 个类的正样本 ≤6**（dos 6 / front_running 4 / time_manipulation 5；另 access_control、arithmetic 各 15），seed0 的 val/test 中支撑 ≤2 的类分别为 **3 / 5** 个（`split_report.json::rule_check`）。
2. **阈值搜索与早停目标改 val micro-F1**（协议形状不变）：阈值候选仍 0.2–0.8 步长 0.05、只在验证集选、tie 取较小阈值、双阈值报告；早停仍为连续 5 epoch 不提升，`ReduceLROnPlateau(mode=max, factor=0.5, patience=3)`；只把目标函数由 macro-F1 换成 micro-F1，macro-F1 同步记录作参考。**与上一轮“稀有类不在 val 单独调阈”合并为本条**：per-class 阈值仅作补充分析，不进主结果。
   - **补充分析已执行（2026-09-14，`scripts/calibrate.py` → `eval_results/calibration/`；结论见 `experiments/results.md` §1.9）**：① per-class 阈值确实抬 macro-F1（0.2455→0.3236）但压主指标 micro-F1（0.9492→0.8106）且 val→test 落差 +0.07（过拟合），**确证其只能留在补充分析、不进主结果**；② 实测连续分辨率阈值与 0.05 网格的 val micro-F1 **逐位相同** → 主协议阈值网格无分辨率损失，协议不需改；③ 全局阈值下温度缩放对 micro-F1 **数学等价于换阈值**（无收益），温度缩放的价值只在标定度量（ECE 0.175→0.067，T<1 证明欠置信）。
3. **逐类报告强制标注 support**：每类 Precision/Recall/F1 与 per-class PR-AUC 必须与该划分上的 support 同时给出；**support ≤2 的类，其 F1 只作描述性呈现，不得用于方法间比较结论**（全量数值可进附录）。
4. **多标签叙事降级为架构性声明**：保留“输出空间为七维 sigmoid 多标签、评估用标签对级 micro 计数”的架构性表述；**撤回“检测多类共存”的实证声明**（同分布池内多标签去重后仅 1 个）。
   **DIVE 前置核查结论（已完成）**：`DIVE/contract_labels.json` 21696 条中 **14789 条（68.2%）为 ≥2 类**，均匀 900 抽样多标签期望 **613.5**（`docs/data_funnel.md` §3）→ DIVE 不是单标签主导，**多标签的实证主张只在 DIVE 上提**，同分布不复述。措辞定稿：**架构性声明 + DIVE 外部证据**。同分布池内多标签样本去重后为 **1 个**（§14.1），不足以支撑共存主张。
5. **DIVE 抽样规模（连带项）**：均匀抽样下 front_running ≥20 的超几何概率：n=500 → 0.022、n=900 → 0.70、n=1100 → 0.936；大纲 5.1(6) 的「≥500 且每类 ≥20」在 500 规模下对 front_running 数学上不可达。**执行口径：n = 900（2026-09-12 P1 定稿，取代本条原先的 1000；见 §14.3）**，抽样清单与类别统计写入 `products/dive/splits/`。
6. **口径可追溯**：论文中出现的每个样本/标签数字一律取自 `docs/data_funnel.md`；其中 `846 → 591` 的差额 **255** 已逐条拆解为「同一 (项目目录, 文件名) 被多个类别文件夹重复收录」的计数之和（k=2/3/4 分别贡献 55/80/120，校验 Σ(k−1)=255）；**不得再出现无出处的数字**。
7. **C 补充实验**：维持上一轮触发条件，**推迟到 M5 首轮结果判定后再定**（本轮不启动）。
8. **口径注释防错位原则（必须遵守）**：**注解必须与被解释的指标同口径**。
   - **macro-F1 的“低支撑构成”注释** → 用**计算它的那个划分**的支撑（seed0 test：**5 个类 support ≤2**），回答“这个 macro-F1 由哪些稀疏类主导”；
   - **数据固有稀疏的“天花板”叙述** → 用**池级**支撑（**池内 3 个类正样本 ≤6**：dos 6 / front_running 4 / time_manipulation 5），回答“数据本身允许多高的分位数”；
   - 两个口径**都保留、各有用途，禁止互相借用**（本轮“3 个 vs 5 个”的分歧即源于口径混用）。
9. **口径绑定指纹与刷新义务（防文档/产物漂移）**：`docs/data_funnel.md` 与本节所有 val/test 支撑数字均绑定 `products/alldata/splits/split_seed{0,1,2}.json` 的 sha256（记录在 `data_funnel.json::binding.digests`）。**T-A 两级去重已于 2026-09-12 完成，本条刷新义务已履行**（新指纹与刷新后数字见 §14.2；旧数字属“预去重 splits”口径，已失效）。**今后任何划分产物变更（含去重口径、覆盖约束、种子）必须重复同一刷新链条**：① 重跑 `python scripts/audit_data_funnel.py`；② 刷新本节与 §14 的支撑数字；③ 刷新手册 §10.2/§10.5 的池规模与支撑注释；④ 刷新 `Todo_List.md`。未刷新即视为口径漂移，验收不通过。
10. **DIVE 抽样结果（n=1000 已作废；现行 n=900 见 §14.3）**：原固定 seed=0、n=1000 的一次试验得 front_running 31，**已因成本口径修订而作废**，仅存历史意义；现行协议为 **n=900**，实测逐类支撑见 §14.3（front_running=30 ≥20，attempt=1 闭案）。协议、停止规则与 id 清单写入 `products/dive/splits/sample_seed0.json`；命令：`python scripts/sample_dive_subset.py`。
    - 认识论口径：固定 seed 后抽样是**一次确定事件**，抽出后以**实测支撑**为准（概率只在抽样前有意义）；
    - 后备路径（固定，不得临场改）：实测 fr <20 → **n 单调升至 1100 重抽一次**（同一 rng 续抽，attempt=2）并披露停止规则；仍 <20 → fr 门槛降为**报告义务**（如实报数、不改口径）；
    - **禁止换 seed 重抽或反复重抽挑到达标样本**（选择偏倚）；调 n 是公开协议参数，允许但必须披露。

---

## 14. P1 落地（2026-09-12）：两级池去重 / DIVE n=900 / 关系数口径 / 消融开关

> 依据：大纲 5.1 第三条（去重与不跨划分）、5.1 第六条（DIVE 抽样）与 P1 逐条裁决。
> 数值出处：`docs/data_funnel.md` 与 `products/alldata/splits/split_report.json`。

### 14.1 两级池去重（T-A 落地，对应 §13 第 9 条的刷新义务）

- **依据**：大纲 5.1 第三条「对合约按唯一标识去重，唯一标识优先使用源码哈希，**并使用合约文件名、合约地址或项目标识**」＋「同一合约及其所有重复记录不跨划分」。
- **实现**：`scripts/make_splits.py::dedup_pool`，`--dedup source-sha1+address`（**默认**）；顺序固定「**先剔 buggy_*、再去重**」（反序会把“与 buggy 副本同内容的正常样本”连坐丢掉）；每级保留**相对源码路径字典序首个**（平局按 base 名），完全确定性。
- **实测**：池 495 → **448**（丢 47）：
  - level-1 `source-sha1`（内容字节相同）：丢 **46** 组，均为 `asd_X` / `nasd_X` 同址副本，且**全为全零样本**，不损信息；
  - level-2 `address`（`project_of_base` 相同）：丢 **1** —— `0x627fa62ccbb1c1b04ffaecd72a53e37fc0e17839` 的 `asd_`/`nasd_` 两份源码**字节不同（1847 vs 1842 字节）**，sha1 抓不到；但标签键就是项目前缀，两者标签恒等 `[0,0,0,0,1,0,1]`（**全库唯一的多标签样本**），seed0 下曾被拆到 **train / val**。
- **口径更正（重要）**：P1 交办时的表述「17 对跨划分重复里含被拆成 train/test 的多标签双份」需校正两点：① 跨划分的那一对是 **train/val**（不是 train/test）；② 它**不是字节级相同副本**，单靠 sha1 去重抓不到，**是 level-2 地址去重才消掉的**——若只做 level-1，本轮最实质的泄漏仍然存在。
- **结果**（三 seed）：池 448 = 125 正样本 + 323 全零，多标签 **1**；划分 **358/45/45**；C1+C2 **7/7 类达标**（替换 18/16/12 个，下限修正 1/0/0）；`rule_check` 新增两级不变量 `content_dedup_ok` / `address_dedup_ok`，三 seed **跨划分内容重复 0、地址重复 0**（构造性保证，不再依赖人工检查）。
- **产物**：`dedup_dropped.txt`（级别 + 组键 + 保留者）、`split_report.json::dedup`、`split_metadata_seed*.json::dedup`；`splits.csv` 1344 行（448×3）。
- `--dedup source-sha1` / `none` 保留：前者用于分离单级影响，后者仅用于复现去重前的历史产物（如 `random_snapshot/`）。

### 14.2 由 14.1 触发的口径刷新（§13 第 9 条链条，已履行）

| 口径 | 旧（预去重，495） | 新（448，现行） |
| --- | --- | --- |
| 池样本数 | 495 | **448** |
| 划分规模 | 396/50/49 | **358/45/45** |
| 正样本 / 全零 | 126 / 369 | **125 / 323** |
| 多标签样本 | 2 | **1** |
| 逐类池内正样本 | 15/15/6/4/**32**/5/**51** | 15/15/6/4/**31**/5/**50** |
| seed0 val / test 支撑 | 3/3/1/1/5/1/8、2/2/2/1/5/2/8 | **3/3/1/1/5/1/8、2/2/1/1/5/2/7** |
| seed0 val/test 支撑 ≤2 的类数 | 3 / 5 | **3 / 5**（未变） |

- §13 第 8 条防错位原则不变：macro-F1 的“低支撑构成”注释用**所属划分**口径（seed0 test：5 个类 ≤2）；数据固有稀疏的天花板叙述用**池级**（**3 个类正样本 ≤6**：dos 6 / front_running 4 / time_manipulation 5）——池级结论未因去重改变。
- 各 seed 支撑（顺序 ac/ar/dos/fr/re/tm/un）：seed1 val `3/3/1/1/5/1/8`、test `2/2/1/1/5/1/7`；seed2 val `3/2/1/1/5/1/8`、test `2/3/1/1/5/1/7`。
- 新指纹（sha256，完整值见 `docs/data_funnel.md` §5）：`split_seed0` `3de35729c8fbdbdf…`、`seed1` `060fb038bc22efb3…`、`seed2` `d9a14613e7c0b8d6…`。
- **已同步**：`docs/data_funnel.md`、`论文开发手册.md`（§7.7/§10.2/§10.5/§13）、`Todo_List.md`、`项目组织架构.md`；`tests/test_make_splits.py` 黄金值已改（含新增两级去重用例）。

### 14.3 DIVE 抽样规模改 n=900（取代 §13 第 5、10 条的 n=1000）

- **理由**：大纲 5.1(6) 只要求「不少于 500 个」且「每类 ≥20」；n=900 均匀抽样下 front_running 期望 22.0、P(≥20)=0.70，三条件自洽；同时省 10% 外部推理成本。写入大纲时附成本说明（全量 21696 ≈ 900 的 24 倍，约 38× 外推留作未来工作）。
- **实测**（`python scripts/sample_dive_subset.py`，seed=0、均匀无放回、一次确定事件）：**n=900，front_running=30 ≥20 → attempt=1 闭案**；逐类支撑 ac 682 / ar 378 / dos 136 / fr 30 / re 468 / tm 234 / un 246；多标签 614（68.2%，期望 613.5）、全零 105。
- **n=1000 的旧试验（fr=31）已作废**，仅存历史意义；现行产物 `products/dive/splits/sample_seed0.json`、`sample_report.json` 均对应 n=900。后备路径仍为「n 单调升至 1100 重抽一次；再不足则 report-only」，**禁止换 seed**。

### 14.4 关系数口径（论文 4 语义边 / 实现 5 物理关系）

| 编号 | 物理关系（`RELATION_NAMES`） | 论文语义边 | 实测边数 / 含边图数 |
| --- | --- | --- | --- |
| 0 | CFG_FLOW（`kind` ∈ seq/true/false） | CFG_FLOW | 71296 / 581 |
| 1 | AST_PARENT | AST_PARENT | 1957 / 481 |
| 2 | AST_PARENT_SAME | AST_PARENT（实现细分：多个 AST 节点落在同一 CFGNode） | 6035 / 563 |
| 3 | DFG_DEP | DFG_DEP | 146712 / 569 |
| 4 | CALLBACK_RISK | CALLBACK_RISK | 511 / 86 |

- 论文叙述 **4 类语义边**；实现保留 **5 个物理关系、`num_bases=5`**（**不做物理合并**：合并需重跑 M2 全量 581 图，收益为零）；若把 CFG_FLOW 三子类当独立关系则为 6 类（需新增 `kind→edge_type` 映射，当前不实现）。
- **2026-09-12 R5 修复后刷新**：DFG_DEP 146679 → **146712**（+33）、CALLBACK_RISK 509/85 → **511/86**（+2/+1）、边总数 226476 → **226511**；CFG_FLOW/AST_PARENT/AST_PARENT_SAME/节点数**不变**（71296/581、1957/481、6035/563、93551）。受影响的只有 §15.7 的 3 图，且**均不在池 448 / 划分内**。
- AST 专项：AST_PARENT + AST_PARENT_SAME 合计 7992 条 = 全部边的 3.53%，另有 **273811** 条 AST 父子关系因端点未映射到 CFGNode 未入图（丢弃率 **97.2%**）→ “语法从属”边几乎不承载信息，论文须给出该稀疏性统计并据此调整“四类边”的贡献表述（见 §15.8）。

### 14.5 边级消融开关（实现）

- `scripts/dataset.py`：`DROPPABLE_EDGES = frozenset(RELATION_NAMES)`（全部 5 个物理关系为白名单）、`DROP_AST = {1, 2}`；`resolve_drop_edges(drop_edges, drop_ast)` 做白名单校验，越界编号直接 `ValueError`（**加载时强制**，不再只是常量）；`Ablation.resolved_drop_edges()` 统一解析，`load_graph` 调用它。
- `--drop-ast` 语义固定为**删 relation 1+2**（AST_PARENT + AST_PARENT_SAME）；`python scripts/dataset.py --check <base> --drop-ast` 可直接观察（示例：`nasd_simple_dao__simple_dao` 28 → 23 边）。
- 论文/手册口径：`--drop-ast` = “去 AST 语义边”，不是“去 AST_PARENT 单边”。

---

## 15. 函数级 CodeBERT 通道缺口修复（2026-09-12；**M5 开始前最后一次特征数值变更**）

> 执行计划：`docs/cb_func_gapfix_plan.md`；缺口清单（可审计）：`products/alldata/splits/cb_func_gap.json`
> （修复前基线）与 `cb_func_gap_after.json`（修复后），生成脚本 `scripts/audit_cb_func_gap.py`。

### 15.1 问题与成因

- **实测（修复前）**：函数级通道（`_cb.pt::func`）有 **35195 / 93551 节点行（37.6%）** 取不到向量，
  涉及 **495/581 图**、5679 个去重键；节点级通道 **0 缺失**。不是回归：旧 `assemble_feat` 用同一句
  `.get(..., zeros)`，行为相同，只是此前不可观测（现已入 `_feat.pt::meta.cb_missing_rows`）。
- **成因（两类）**：① 继承函数在 Slither cfgdetail 里归到**派生合约**（`InvictusWhitelist._transferOwnership`），
  而 `_hetero.json::functions` 由 AST walk 按**定义处**登记（`Ownable._transferOwnership`）→ 键错位（4351 键/27290 行）；
  ② `walk_ast` 只收 `FunctionDefinition`，**不收 `ModifierDefinition`** → `modifier onlyOwner` 体节点完全无表项（778 键/5283 行）。
- 修正认识：受影响的不是“继承基合约的全部函数”，而是“以基合约名/修饰符名出现的那些键”（见 15.4 残留）。

### 15.2 修复（M2 侧函数表补登记，**不动 nodes/edges**）

- 在 `build_cfg_centered_hetero_graph.py` 的 `functions_out` 生成前增加**补登记**（仅当有 cfgdetail）：
  同名条目存在→补 `(派生合约, 函数名)`（alias，span 取定义处）；否则用 AST 里 `ModifierDefinition` 的
  src span 补 `kind=modifier`；仍无→计入 `meta.functions_unmatched*`（不静默）。
- **双重隔离（关键，否则会污染已冻结口径）**：补登记会把 `function_visibility`/`function_mutability` 填上，
  而 ① 节点元信息字段、② `build_callback_risk_edges()` 的 CALLBACK_RISK 边判定都读它。首轮重跑出现
  **18 图 edges 变化**（会动当时已冻结的 CALLBACK_RISK 509 边/85 图口径；R5 后为 **511/86**，见 §15.7）→ 两者均改为读**补登记前的快照**
  `fn_meta_table`。修复后全库对比备份：**`functions` 表变化，nodes/edges/meta 旧键零差异**。
- `--only <base>` 小样开关一并加入（小批回归用）。

### 15.3 结果与验证（全库 581 图）

| 项 | 值 |
| --- | --- |
| `functions` 表 | 14741 → **23139**（+8398 = alias 7705 + modifier 693） |
| 缺口 | 35195 行（37.6%）→ **2622 行（2.8%）**；涉及图 495 → 404 |
| `_pyg.pt` | **未变**（`convert_hetero_json_to_pyg.py` 不读 `functions`；且 nodes/edges/meta 旧键已逐字段证明未变） |
| `_cb.pt` 重建 | **全量 `--force` 重建**（≈55 min，`cb cache reused 0/581`） |
| **等价性** | 先用增量补丁 `--cb-patch`（7m25s，+8398 键）跑通，再全量重建；两者**全库 581 图三项指纹逐位相等** |
| 全库断言 | `load_graph` 含 `verify_channels="all"`（cb 双通道哈希）在 581 图上全部通过 |
| 回归 | `pytest tests/` 39 passed；无缺口图的 `combined_sha256` 不变 |

> **第三轮修复（R5 三图 AST 格式，§15.7）后最终口径：缺口 2356 行（2.52%）/ 382 图 / 475 键，全部为 `slitherConstructor*`（不可编码）→ 覆盖率 97.48%**；`functions` 23260。

### 15.4 残留（已记档；R2/R5 均已闭合）

> 待办与裁定入口：`docs/residual_gaps.md`（R1 合成作用域 / **R2 已闭合，§15.6** / R3 可见性元信息 / R4 cb 旁支 / **R5 已闭合，§15.7**）。

### 15.4.1 **口径更正：连带效应（2026-09-12 实测）**

先前记录「补登记只动函数级通道」**不完整**：M3 的可见性特征在 `m3_build_features.py:617` 有**表回退**
（`node.get("function_visibility") or fn.get("visibility")`），因此本次补登记**同时改变了结构通道的可见性 4 列**——
**27290 个节点（alias 类）从全 0 变为真实可见性**；修饰符类 5283 个仍为全 0（**语义正确**：Solidity 修饰符本就无 visibility）；
`function_visibility`/`function_mutability` **节点字段本身未变**（`fn_meta_table` 已隔离）。
结论：连带效应是**修正性**的，但属**结构通道变化**，必须在论文/手册中声明；本次变更因此同时影响
`cb_*` 与 `struct`（可见性 4 列）两类通道数值。

### 15.4.2 两类残留明细

- `none` 类 477 键 / 2362 行：**全部是 `slitherConstructorVariable/Constant`**（Slither 合成作用域，
  部署期状态变量初始化）——源码里没有对应函数体，**不可编码**，保留零向量 + 本节记档（非解析缺陷）。
  注：其中 6 行属 R5 的 3 张 AST 未解析图（严格归因应为“解析缺口”，已由 §15.7 修复）。
- `function` 类 73 键 / 260 行：0.4.x **老式继承构造函数**（`function Ownable()` 被继承后 Slither 用基合约名作函数名，
  表内记作 `constructor`）。**已于 §15.6 闭合**（69 键 / 240 行）；当时“产出 102 条别名但 0 命中”的根因也已在
  §15.6 查明（只改 `contract` 字段、未改 `function` 字段 → 条目落在错的键上），并非规则本身有误。

### 15.5 论文口径与影响

- **函数级通道覆盖率**：修复前 62.4% → 第一轮后 97.2% → 第二轮后 97.45% → **第三轮（§15.7）后 97.48%**
  （= 1 − 2356/93551 = 1 − 2.52%；残余 **全部是** `slitherConstructor*` 合成作用域，不可编码）；
  论文在“特征构建”处如实报告该覆盖率与残余口径。
- **通道消融可解释性**：修复前 `no-cb-func`/`--cb-channels` 消融只影响 62.4% 节点的输入（结论不可解释），
  现已基本干净——这是本次修复的主要论文收益。
- **时机**：M5（train/evaluate）尚未实现 → 本次变更**不使任何实验结论作废**；自本日后 `_feat.pt` 数值冻结，
  任何再变更必须重跑全链并刷新本节。
- **未一并处理的同源缺口（单独裁定）**：节点字段 `function_visibility`/`function_mutability` 对上述受影响节点
  仍为 `None`（M3 的“函数可见性 4 列”在其上恒为 0）。本次刻意不动（改的是**结构通道**，属另一条口径），
  已单独记录待裁。

### 15.6 **第二轮：老式继承构造函数闭合（R2，2026-09-12）**

- **触发**：`docs/residual_gaps.md` §R2 的只读排查（≈10 min，不改代码），共 4 步打印。
- **键形态定论（实测三例）**：0.4.x 的 `function Ownable() public {}` 被派生合约继承后，**Slither 的 CFG 用基合约名作函数名**
  → 节点键 = `(派生合约, 基合约名)`；而 `walk_ast` 见 `raw_name == 所在合约名` → 键 = `(基合约, "constructor")`。
  两者不同名，故规则①（同名 alias）抓不到。证据：`MintableToken.Ownable` 节点行 **378–380** 正是 `contract Ownable`（370 行）
  内的 `function Ownable() {`（378 行）；`MyAdvancedToken.token` → `contract token` 的 `function token(...)`；
  `SaleClockAuction.ClockAuction` → `contract ClockAuction` 的 `function ClockAuction(...)`。
- **上一轮空转的根因（已复现）**：旧实现只改 `contract` 字段（`dict(entry, contract=key[0])`），未改 `function` 字段
  → 条目仍落在 `(派生合约, "constructor")` 这个**错的键**上：既救不了请求键，又与既有 constructor 条目重键。
  小样先复现：该写法只新增 2 个键（应为 7 个）；补上 `function=name` 后新增 7 个键、既有条目零改写。
- **规则（现行）**：请求名 N 是**本文件声明的合约名** 且 `(N, "constructor")` 在表中且其 `kind == "constructor"`
  → `fn_table[(C, N)] = dict(fn_table[(N, "constructor")], contract=C, function=N)`（span 取基合约构造函数）。
  优先级：同名 alias ① > 老式构造 ③ > modifier ② > unmatched；命中计数写入 `meta.functions_reconciled_legacy_ctor`。
- **验收（全库 581 图）**：

| 项 | 值 |
| --- | --- |
| `functions` 表 | 23139 → **23241**（+102 条 = 69 个去重键 × 多图展开；命中 `legacy_ctor` 计数 3–…，其余经同名 alias 取到同 span） |
| 缺口 | 2622 行（2.8%）→ **2382 行（2.5%）**；涉及图 404 → **382** |
| nodes / edges / meta 旧键 | **581 图逐图指纹零差异**（`scripts/audit_graph_fingerprint.py --compare`；`functions` 变 53 图） |
| 无重复键 | 581 图 `functions` 的 `(contract, function)` **唯一性检查通过**（防上一轮“错键”隐患） |
| `_cb.pt` | 走 `--cb-patch`（**+102 func / +0 node**，重写 53/581，**1 m 08 s**）；与全量重建等价的既有证明适用（§15.3） |
| `_feat.pt` | 全量刷新 581 图（`--cb-patch` 同时写回） |
| 全库断言 | `load_graph`（`verify_channels="all"`）581 图通过，全库 cb 缺行 **2382**（与审计一致，现已降至 2356，见 §15.7） |
| 回归 | `pytest tests/` **39 passed** |

- **连带效应（必须声明）**：新别名条目的 `visibility` 继承自基合约构造函数（`public` 239 / `internal` 1），
  而 M3 的可见性特征有 `fn_table` 回退（`m3_build_features.py:617`）→ **240 个节点行**（53 图）的结构通道
  **可见性 4 列从全 0 变为 one-hot**（与 §15.4.1 同性质：只增不改、可解释）。节点字段仍为 `None`（`fn_meta_table` 隔离）。
  → 本次变更**同时**影响 `cb_func`（240 行）与 `struct`（可见性 4 列，240 行）两类通道数值。
- **去重/标签/划分不受影响**：划分只依赖标签与地址，不读图结构。

### 15.7 **第三轮：三图 AST 格式兼容（R5，2026-09-12，用户裁定 = A）**

- **问题**：581 图中 3 图（`asd_0x603fc324…`、`nasd_0x603fc324…`、`nasd_0x980358…`，9/13/9 节点，共 **31 节点**）
  的 `AST-raw/*.json` 是 **solc 0.8 风格**（子节点键 `nodes`、属性在节点顶层），而 `walk_ast` 只读
  `children`/`attributes` → **functions 表整表为空** → 这 31 行函数级通道全为零向量，且 `state_vars` 为空
  （连带 DFG 状态变量判定与 CALLBACK_RISK 判定失真）。
- **修法（最小改动 + 零改写保证）**：新增 `normalize_ast()`，在 `load_ast()` 读入时归一化新式节点；
  **老式节点（含 `attributes`/`children` 键）原样返回同一对象**，因此既有 578 图的解析路径不经任何新分支。
  另修 `walk_ast` 的分支顺序小缺陷：新式显式构造函数 `name=""` + `kind="constructor"` 曾被误判为 `fallback`
  （老式 AST 无此组合 → 对 578 图零行为变化）。单测 `tests/test_ast_normalize.py`（4 用例）覆盖两条保证。
- **验收（全库 581 图，逐图指纹）**：

| 项 | 结果 |
| --- | --- |
| `_hetero.json` | **仅 3 图** nodes/edges/meta/functions 变化；其余 **578 图零差异**（`scripts/audit_graph_fingerprint.py --compare`） |
| 3 图变化内容 | `functions` 0 → 5/7/7；`state_vars` 空 → 2/2/3；DFG_DEP 8→23、1→10、1→10（**+33**）；CALLBACK_RISK 0→2（一图）；12/12/13 个节点的 `function_visibility`/`function_mutability` 由 None 填实 |
| **AST_PARENT / SAME** | **仍为 0**（该 3 图的 AST 父子边 13/14/14 条**全部落不到 CFGNode 对**上——与另外 15 图同因，见 §15.8；故库级 AST 边数 1957/481、6035/563 **不变**） |
| 库级口径变化 | 边总数 226476 → **226511**；DFG_DEP → **146712**/569；CALLBACK_RISK → **511/86**；节点数 93551 不变 |
| 下游重跑 | M1 **仅这 3 图**变（`_m1.json`；库级 `total_raw_hits` 21567 → **21571**）→ PyG **仅 3 图**变（3.5 s）→ M3 `--cb-patch`（**func +19 / 0 node / 重写 3 图**，1 m 09 s）→ 全库断言通过 |
| 缺口 | 2382 → **2356 行（2.52%）/ 382 图 / 475 键**，**全部是 `slitherConstructor*`**（不可编码）→ 覆盖率 **97.48%**；`functions` 23241 → **23260** |
| 回归 | `pytest tests/` **43 passed**（新增 `tests/test_ast_normalize.py` 4 用例） |
| 影响面 | 这 3 图**均不在池 448 / 划分内**（`splits.csv` 无对应 `sample_id`）→ **不影响 M5 训练与评估**；只影响库级结构统计（已刷新 `docs/data_funnel.md`） |

- **工具/流程教训（已记入 `docs/residual_gaps.md` 与仓库记忆）**：① M1 全量刷新必须用**相对参数**
  （`--in-dir products/alldata/graphs --out-dir products/alldata/graphs`），否则 `meta.graph_path` 由相对变绝对、
  全库 581 个 `_m1.json` 字节全变（数值不变）；② 局部 `--pattern` 运行会**覆写**库级 `batch_summary.json`，
  之后必须补一次全量；③ `_feat.pt` 含 `meta.created_utc`，**每次 M3 运行都会改写全部 581 个文件字节**——
  验收“只有少数图变”必须看 `meta.channel_sha256`/`combined_sha256` 或 `_hetero.json` 指纹，不能看文件 sha256。

### 15.8 **附注（披露项，非缺陷待修）：AST 关系的映射丢弃率**

- 实测：AST 父子边共 281803 条，其中**只有 7992 条**（AST_PARENT 1957 + AST_PARENT_SAME 6035 = 全部边的
  3.53%）能映射成 CFG 节点对；**273811 条（97.2%）因端点未映射到 CFGNode 被丢弃**；另有 **18 图**
  （占 3.1%，含 R5 的 3 图）AST 边为 0（其中 11 图在池内、2972 节点）。
- 处置建议：**不改实现**（改映射规则会再次改变库级结构统计与 `_pyg.pt`，收益不明），但在论文数据描述与
  局限处**如实披露**：AST 关系在本实现中是高度过滤的子集（`meta.ast_unmapped_edge_count` 可复核），
  “四类边”的贡献叙述应据此调整；数字与生成方式见 `docs/data_funnel.md` §4（`audit_data_funnel.py` 自动刷新）。

---

## 16. M5 开发方案裁定（2026-09-12，用户确认「按推荐方式」）

> 依据：设计稿 `docs/M5_dev_plan.md`（M5 = `metrics.py` + `train.py` + `evaluate.py` + M5 CI smoke）。
> 本节记录设计过程中产生的**新口径裁定**，供实现时逐条对照；其余实现细节以设计稿为准。

1. **训练/划分种子语义（定稿）**：`train.py` 引入 `--seed`（**训练种子**：模型初始化、先验/结构 dropout、训练集打乱、DropEdge 随机流）与 `--split-seed`（读 `split_seed{split_seed}.json`，**默认 = `--seed`**）。主实验 = seed0/1/2，每个 seed 用**同名划分 × 同名训练种子**，`summary.json` 报三种子均值±std、主表固定 seed0。两类种子显式分离（`--split-seed` 独立可变），满足大纲 5.1「训练种子不改变划分」的可测性，同时支持「固定划分 seed0、变训练种子」的稳健性补充实验——两种口径共用同一套代码，只差 CLI 传参。
2. **批图 collate（定稿）**：自实现 collate，**不引入 PyG `Data`/`DataLoader`**——数据是自定义通道字典而非标准 `Data`，`NodeFuser` 接口即「批通道 + batch 向量」。拼接 = 通道沿节点维 cat + `edge_index` 加节点偏移 + `edge_type` cat + batch 向量 + labels stack；DropEdge 先逐图 mask 再 batch（`model.apply_edge_mask`），随机流 = `(train_seed, epoch, stable_graph_index)`。
3. **checkpoint 双模块**：`fuser`（NodeFuser）与 `model`（SSMHG）是两个独立模块，`best.pt`/`last.pt` 必须同时存两者 `state_dict`；恢复时从 config 的 `d_struct/struct_layout/ablate/...` 重建。
4. **维度回读**：`NodeFuser` 融合输入维 = `768*len(cb_channels) + 64 + D_struct + 1`（主配置 1631，`--cb-channels` 消融会改变该维，仅影响融合层自身）；`SSMHG(in_dim=...)` 接收 fuser 的**输出** h_v^(0) ∈ R^128，必须从 `fuser.hidden`（恒 128）回读，不得硬编码。~~原稿误写 `fuser.in_dim`~~（那是融合输入 1631，已更正为 `fuser.hidden`，2026-09-12 实现期发现）。
5. **阶段顺序**：A `metrics.py` → B `train.py` → C `evaluate.py` → D CI smoke → E 主实验（3 seed → `summary.json`）→ F 消融/基线 → G 跨数据集（阶段 5）。任何一项未过窄范围 smoke，不进入下一项。

## 17. 主实验结果（2026-09-13 执行记录）

> 3 种子主实验已跑通（CUDA/RTX 4070 Laptop，torch 2.0.1+cu118）：micro-F1（主指标）固定 0.5 = **0.9058±0.0397**、验证集阈值 = **0.9492±0.0145**（阈值 0.75/0.60/0.55）；macro-F1 参考 0.2300±0.0428；mAP 0.4139±0.1070。
> 完整明细（逐种子/逐类/训练时间与吞吐/产物清单）见 `experiments/results.md` §1，结果数字单一维护于此、本文不重复。

---

## 18. 过滤规则修订 + buggy_* 对照臂（2026-09-14）

> 触发：审查数据过滤链时发现 `delegatecall` 规则是**与标签相关的选择偏差**（非随机丢弃）。
> 本节记录改动、证据与两个口径的对照结果。**本节的裁定属"大纲之外的后处理"，已同步大纲与开发手册。**

### 18.1 问题：delegatecall 规则删掉的正是目标类样本本身

`generate_all_ast_cfg_dfg.sh` 原规则：

```bash
if grep -E 'delegatecall' "$solfile" | grep -qvE '0x[0-9a-fA-F]{40}'; then
    ... continue   # 含 delegatecall 且调用目标不是 0x 字面量地址 → 整个文件剔除
fi
```

命中 10 个文件（1 个 assembly>50 先短路、9 个 delegatecall）。其中**两个是正样本**：

| 文件 | 项目 | 标签 | 源码内自带的真值标注 |
| --- | --- | --- | --- |
| `asd_proxy/proxy.sol` | proxy | access_control | `// <yes> <report> ACCESS_CONTROL`、`@vulnerable_at_lines: 19` |
| `asd_FibonacciBalance/FibonacciBalance.sol` | FibonacciBalance | access_control | `@vulnerable_at_lines: 31,38` |

两者都是 SWC-112 的标准示例：**漏洞模式本身就是"delegatecall 到不可信/动态目标"**。
即规则命中的充要条件与目标类的语义高度重合——这不是"过滤了 1.7% 的样本"，而是**定向删除 access_control 类的定义性样本**。池级 access_control 仅 15 个正样本，删 2 个 = 13%。

**证据（重跑实测）**：这 9 个文件原样跑 raw 生成，`ast_failed=0 / cfg_failed=0 / dfg_failed=0 / cfgdetail_failed=0`——**零解析失败**。原规则是先验排除，不是对构建失败的响应。

### 18.2 处置

1. **规则改为仅记账、不再剔除**（`delegatecall_dynamic_binding` 仍计数进 `filter_report.txt`，新增 `delegatecall_dynamic_binding_filtered=0` 显式标注）。真正的构建失败由 `ast_failed/cfg_failed/dfg_failed/cfgdetail_failed` 记账。
2. **定向补跑 9 个文件**（raw → M2 → M1 → PyG → M3）。补跑时输出目录全部指向临时目录，再并入主产物区——**该脚本启动时会 `find … -delete` 清空 `AST-raw/CFG-raw/DFG-raw`**，直接在主目录跑会抹掉既有产物。
3. **确定性验证**：补跑前后对既有 2324 个产物（581×{hetero,m1,pyg,feat}）做 sha1 清单比对，**0 变化、0 缺失**；PyG 转换全量重跑后同样逐字节一致 → M2/M1/PyG/M3 全链确定性成立。

### 18.3 结果（正典口径）

| 量 | 修订前 | 修订后 |
| --- | --- | --- |
| 图数 | 581 | **590** |
| 非 buggy 图 | 495 | **500** |
| 池（两级去重后） | 448 | **453**（丢 47 = sha1 46 + 地址 1，与修订前同） |
| 池内正样本 | 125 | **127** |
| 逐类正样本 | access_control 15 / arithmetic 15 / dos 6 / front_running 4 / reentrancy 31 / time_manipulation 5 / uncheck 50 | **access_control 17** / 其余不变 |
| 划分规模 | 358/45/45 | **362/45/46** |
| 覆盖校正替换 | 18/16/12 | 17/15/15（下限修正 1/0/0） |

主指标随之刷新（旧数字存档于 `runs/prior_448pool/`）：

| 指标 | 旧 448 池 | 新 453 池 |
| --- | --- | --- |
| micro-F1 @0.5 | 0.9058±0.0397 | **0.8954±0.0211** |
| micro-F1 @val_thr | 0.9492±0.0145 | **0.9296±0.0090** |
| macro-F1 @0.5 | 0.2300±0.0428 | 0.1918±0.0728 |
| mAP | 0.4139±0.1070 | 0.2980±0.0127 |

差异幅度在种子噪声量级内（旧 std 0.0397 覆盖 0.9058→0.8954 的落差），但**这是不同划分下的不同实验，不得跨口径引用**。

### 18.4 buggy_* 对照臂（裁决：隔离，不替换正典）

- 开关：`make_splits.py --include-buggy`，**输出隔离**到 `products/alldata/splits/withbuggy_snapshot/`；训练/评估隔离到 `runs/withbuggy/`。沿用 `--strategy random` → `random_snapshot/` 已有的隔离先例，正典产物零改动（有单测锁死）。
- 规模：池 **497**（590 → 去重丢 93 = sha1 48 + 地址 45；43 个 buggy 项目的 asd_/nasd_ 双副本被地址级去重合并，故不是 590）、正样本 **171**、多标签 **45**。
- 关键读数与**警告**：对照臂 macro-F1 **0.7043±0.0695**、mAP **0.7574±0.0776**，相对正典（0.1918 / 0.2980）高得离谱——这是 45 条**七类全 1** 标签把每类 support 撑起来造成的**度量假象**，不是模型变好。
  - 佐证：这些 `buggy_N` 项目（43 个，86 文件，其中 76 个标签向量为 `(1,1,1,1,1,1,1)`）在上游被**复制进全部 7 个类别文件夹**（各文件夹 40–45 个），标签是全 1 是"文件夹归属"的产物，与具体注入特征不对应（与手册 §10.2.6、§6.3 既有结论一致）。
  - micro-F1 反而下降到 0.8727±0.0438：全 1 行在标签对级既贡献 TP 也贡献 FP。
- **口径约束**：本臂只作对照/稳健性材料；论文正表不得使用其 macro-F1/mAP，若引用必须同时给出 support 说明。

### 18.5 顺带澄清（写入论文数据描述）

- **两级去重不造成标签损失**：46 个 sha1 组 + 1 个地址组，**组内标签向量完全一致**（0 个不一致组）；被丢弃的 47 个文件里只有 1 个是正样本，其同标签孪生被保留。此前"去重丢掉了多标签合约"的怀疑不成立。
- **池级正样本远少于上游文件夹计数的主因是 buggy_* 剔除**，不是去重：86 个 buggy 文件承载了逐类朴素正样本的 84–95%（dos 82→6、front_running 80→4）。论文引用上游逐类文件数（88–190）时必须说明二者不是同一量（含 buggy 副本的文件夹记录数 vs 唯一合约正样本数）。

---

## 19. 并行第二数据集 `alldata_augmentation` 引入（2026-09-14）

### 19.1 决议

- **定位：并行的第二个数据集**（用户裁定，2026-09-14）——与 `alldata(readonly)` 并存，用于增强/类别不平衡对照，**不替换**主实验口径。
- **只读源 4 → 5**：新增 `alldata_augmentation/`（与 `alldata(readonly)`、`DIVE/`、`SolidiFI/`、`MVD-HG-dataset/` 同级）。
- **产物区 三 → 四区**：新增 `products/augmentation/{raw,graphs,splits}/`（**骨架已建，产物待生成**）。
- **`MVD-HG-dataset/` 恢复**（用户裁定）：该目录一度被删除，按裁定 `git restore` 恢复，工作区与 HEAD 一致。
  - 理由：`scripts/audit_data_funnel.py` 的 `MVD_ROOT` 指向它，「上游 MVD-HG-dataset → 主库 alldata」审计链与 `docs/data_funnel.md`（含 `846 → 591`、差额 255 逐条拆解）均依赖该目录；删除会使脚本报错、口径溯源断链。
  - **替代方案（未采纳）**：把上游段改指 `alldata_augmentation`——因新目录是扁平结构、**没有** `{类}_contract/` 分文件夹，「跨类别重复收录」这一审计口径整体不适用，需重写该段，成本高于恢复。

### 19.2 实测口径（可复核，`alldata_augmentation/`）

| 项 | 值 |
| --- | --- |
| `sol_source/` | **1780** 个 `.sol`，**扁平单层**（文件名形如 `<项目名>.sol` / `<地址>.sol`；含 `{类}__buggy_N.sol`） |
| `contract_labels.json` | **9026** 条 7 维 multi-hot，同类别序（reentrancy 下标 4） |
| 标签模式数 | **10** |
| 逐类正样本条目数 | access_control 1033 / arithmetic 1204 / dos 948 / front_running 1044 / reentrancy 971 / time_manipulation 870 / uncheck 1313 |
| 全零（无漏洞） | **6029**（占 66.8%） |

模式分布（`alldata(readonly)` 顺序）：

| 模式 | 含义 | 条数 |
| --- | --- | --- |
| `0000000` | 无漏洞 | 6029 |
| `1111111` | 七类全有 | 714 |
| `0000001` | 仅 uncheck | 548 |
| `0100000` | 仅 arithmetic | 439 |
| `0001000` | 仅 front_running | 330 |
| `1000000` | 仅 access_control | 319 |
| `0000100` | 仅 reentrancy | 257 |
| `0010000` | 仅 dos | 234 |
| `0000010` | 仅 time_manipulation | 105 |
| `0100011` | arithmetic+time_manipulation+uncheck | 51 |

**与主库的关系**：条目键交集 **648**，**交集上标签向量完全一致（0 条不一致）**；但互不为子集（`alldata(readonly)` 2002 条 ⊄ 9026 条），地址级交集仅 168。

### 19.3 谱系：已结案（2026-09-14，用户说明 + 审计复核）

生成流程（用户说明，与产物逐一复核一致）：

1. 源文件取自 `MVD-HG-dataset/{类}_contract_data_augmentation/sol_source/`；7 个目录间**同名 .sol 内容一致**者视为同一实体，重命名去歧义（`buggy_N.sol` → `{类}__buggy_N.sol`）后合并进扁平 `sol_source/`。
2. 标签按「7 个类目录中该键 `targets==1` 的并集」生成 7 元组。
3. 同名但内容不同者拟参考 `alldata(readonly)` 的标签。

审计实测（`8997/9026 = 99.7%` 严格等于上述并集规则）：

| 归因 | 条数 |
| --- | --- |
| == 上游逐类正并集（含 `{类}__buggy_N` 改名的键还原） | **8997** |
| 与并集不符（用户给了单类，并集为 2 类；集中在 `buggy_N0x<addr>_<C>_<f>.sol` 函数级文件，**单类更接近真值**） | 23 |
| 上游与 readonly 均无此键（`0x627fa62c…` 双前缀重复样本，标签与 readonly 逐位一致） | 6 |

- 结构对齐**无缺陷**：1780 源文件 ↔ 1780 stem ↔ 9026 标签条目，零孤儿、零悬空；每 stem ≥1 条、每条 stem 均有对应文件。
- 规则 ③（抄 readonly）**实际未触发**（0 条依赖它）：两数据集文件 stem 命名不同（0 个同名文件），但标签键有 648 个重合，且这 648 条在「并集 / readonly / aug」三者上完全一致。
- §19.2 初稿所述「1531 / 22939 / 5 条不一致」等差异，**已由改名规则解释**，不构成缺陷。

### 19.3.1 ⚠ 标注缺陷：`{类}__buggy_N` 落入规则空档（**启用前必须处置**）

- 规模：**298 个文件**（占 1780 的 16.7%）、**1162 条标签**。
- 这批文件**同名不同内容**：同一编号 `N` 在 7 个类目录里是 **7 个不同文件**（50 个编号上跨类内容一致者 **0** 个）。
- 上游对 `buggy_N-<合约>` 这个**键名**在**全部 7 个目录**都标 `targets=1`（基础目录与增强目录均如此）→ 并集规则把它推成 `1111111`，共 **714 条**。
- 但上游 `solidifi_labels.json` 记录真值：每个类目录中的 buggy 文件**只有本类注入**（access_control 337 / arithmetic 392 / dos 285 / front_running 348 / reentrancy 270 / time_manipulation 181 / uncheck 382，**全部单类**）。
- ⇒ **714 条 `1111111` 每条含 6 个虚假正样本**；根因是规则 ③ 的兜底只覆盖「readonly 有同名者」，而 buggy 文件在 readonly 中无对应，遂回落到并集。

影响量化（按 `solidifi_labels.json` + 本类目录 `targets` 修正后）：

| 类别 | 现行 | 修正后 | 虚高 |
| --- | --- | --- | --- |
| access_control | 1033 | 421 | 612（59%） |
| arithmetic | 1204 | 558 | 646（54%） |
| dos | 948 | 336 | 612（65%） |
| front_running | 1044 | 432 | 612（59%） |
| reentrancy | 971 | 359 | 612（63%） |
| time_manipulation | 870 | 224 | 646（74%） |
| uncheck | 1313 | 667 | 646（49%） |
| **合计** | **7383** | **2997** | **4386（59%）** |

修正后正样本 **2997 = 非零条目数**，即每条非零标签恰好一类——该数据集实为**单标签集**。

**处置：方案 A（按真值修正），2026-09-14 已裁定并执行。**

- 工具：`scripts/repair_augmentation_labels.py`（`--dry-run` 只看影响面；默认拒绝覆写已有输出，需 `--force`）。
- 规则（**窄规则**）：仅对 stem 形如 `{类}__buggy_<rest>` 的条目，取 `<MVD-HG-dataset>/{类}_contract_data_augmentation/contract_labels.json` 中键 `buggy_<rest>-<合约名>.sol` 的 `targets`，写成该类下标上的 one-hot；**其余条目原样保留**。
  - 为何不做更广的推广：`reentrancy__0x627fa62c…` / `uncheck__0x627fa62c…` 这 6 条虽是 `{类}__REST` 形式，但两份副本是**同一合约**的两个版本，上游标签互补（Token 在 uncheck、TokenBank 在 reentrancy），**并集才是真值**（与 `alldata(readonly)` 逐位一致）。判别标准是「同名**不同**内容」，而实测中同名不同内容**只发生在 `buggy_*` 上**（非 buggy 的同名文件跨目录内容 100% 一致）。
- 执行结果：**修正 765 条**，未解析 **0** 条，`solidifi_labels.json` 交叉校验**不一致 0** 条（按 `SOLIDIFI_ALIAS` 归一 `dos→denial_of_service`、`uncheck→unchecked_low_level_calls` 后比较）。
- 产物（**不写入只读源**，`alldata_augmentation/` 保持原样、两者并存备查）：
  - `products/augmentation/contract_labels_repaired.json`（与输入同 schema/同格式，可直接替换消费）
  - `products/augmentation/label_repair_report.json`（改动明细 + 逐类前后计数 + 校验结果）
- 独立复核：键集合不变（9026）；765 条改动**全部**落在 `__buggy_` stem 上；修正后**多标签条目 0**（每条非零恰一类）；合计正样本 **2997 = 非零条目数**。
- 被否决的方案：**B 剔除 298 文件**（损失 16.7% 样本，且这批文件是唯一携带 SolidiFI 注入真值的子集，剔除后该对照价值消失）；**C 仅标注**（§18.4 已证明此类标注会造成 macro-F1/mAP 度量假象，作为对照集不可用）。
- **口径约定**：`alldata_augmentation` 的**正典标签**自即日起为 `products/augmentation/contract_labels_repaired.json`；只读源中的原文件仅作生成过程留痕，**不得**直接用于训练/评估。

### 19.3.2 另有数据缺陷两处（**均继承自上游，非本次引入**）

1. **123 个双地址拼接文件名**：如 `0x0cbe050f…acc9` + `0x091f601d…59a4_Clue_Clue.sol`，文件内容是两份源文件首尾拼接（文件内 2 个 `pragma`、只定义 `Caller`，全文 **0 次**出现 `Clue`）。已在 `MVD-HG-dataset/uncheck_contract_data_augmentation/sol_source/` 找到同款原始文件 ⇒ 上游缺陷。
2. **779 条幽灵标签条目**：标签条目名在对应源文件中查无定义（最高频：`SafeMath` 205、`ERC20` 81、`Ownable` 52、`BasicToken` 46）。已确认上游 `uncheck_contract_data_augmentation/contract_labels.json` 同样含该键 ⇒ 上游缺陷。

### 19.4 对论文的影响

- 主表与阶段 F/G 结论**不变**（仍以 `alldata(readonly)` 口径，见 §17/§18）。
- 该集若入论文，**必须使用修正后标签**（`products/augmentation/contract_labels_repaired.json`）：修正前正样本 59% 为虚高，直接使用会复现 §18.4 `buggy_*` 对照臂同类的度量假象。
- 论文描述该数据集时，须写明其**单标签**性质（每条非零标签恰一类，修正前有 714 条 `1111111` 与 51 条 `0100011` 等多标签，均为 `{类}__buggy_N` 的并集产物）；这与主库的多标签叙事不同（主库池内多标签仅 1 条）。
- 该集分布（修正后：无漏洞 6029、各类 224–667）与主库现行池（§18.3：453，正样本 127、全零 326）仍差异很大，跨口径比较指标不可直接并列。

---

## 20. 第二数据集 M1–M5 全链（2026-09-15 执行记录）

> 按 `AGENTS.md` 的数据边界与 `decisions.md` §19 的裁定执行；**产物全部隔离在 `products/augmentation/` 与
> `runs/augmentation/`，主库 `products/alldata/` 与 `runs/seed*` 零改动**。

### 20.1 标签层语料化（代码改动，默认行为不变）

`dataset.py` 新增 `stem` 键模式与 `SSMHG_LABEL_FILE` / `SSMHG_LABEL_KEY_MODE` 环境回退
（显式参数 > 环境变量 > 主库默认），覆盖 8 个 `build_index` 调用点，避免"某个入口传了参数、
另一个没传"造成的静默错配。`project` 模式（主库）逐字节不变——`tests/test_make_splits.py::
test_refine_coverage_real_pool_golden` 一行未改且全绿即为证。

- **为何需要 `stem` 模式**：aug 语料的图 base 就是 `.sol` 词干，且 300 个词干含 `__`
  （如 `dos__buggy_25`）。沿用 `project_of_base`（`split("__")[0]`）会把这 300 个键切成
  `dos`/`uncheck`/… 七组：标签全部匹配不上，且 `dedup_pool` 的 level-2 会一次丢掉 293 个。
  实测 `stem` 模式下 **1774/1774 命中、0 unmatched**。

### 20.2 近重复检测与簇原子划分（新增工具 + 可选开关）

主库现行划分实测带**同源泄漏**（见 §18.5 的量化），为此新增 `scripts/near_dup_clusters.py`
与 `make_splits.py` 的 `--near-dup-clusters` / `--near-dup-mode {cluster,drop}`。

- **判据**：逐行 sha1 集合 → 倒排预筛（共享稀有行 ≥ 20、行出现文件数 ≤ 25）→ **Jaccard ≥ 0.6** → **全链接**聚类。
- **为何必须全链接**：初版用并查集（单链接）在主库上产出 **92 个成员的簇**，而簇内 **92% 的成员对
  Jaccard < 0.3（中位 0.11）**——那不是近重复，是同族合约（共享 ERC20 核心行）的链式串联。
  改全链接后同一阈值下最大簇降到 7～8，簇内 Jaccard 最低 0.84。**单链接会把"防泄漏"变成"错误合并"**。
  > ⚠ **该结论仅对"初版（未加 Jaccard 归一化）"成立**，且只约束"报告紧密孪生"这一用途。
  > 2026-09-15 补充：在**已加 Jaccard ≥0.6 过滤**的边集上做并查集，分量粒度可控（主库最大 15），
  > 且对**划分防泄漏**是必需手段——详见 §21。
- 实测规模：主库池 500（去重前）**60 簇 / 178 文件 / 最大簇 8**；aug 语料 1774 **125 簇 / 489 文件 / 最大簇 15**。
- `--near-dup-mode cluster` 把簇当**原子组**参与划分（`cluster_atomic_split` + 整簇覆盖校正），
  并在 `rule_check` 记录 `group_dedup_ok` / `cross_split_group_dups`；
  `drop` 为对照臂（簇内只留一份）。两者默认都不启用，主库正典划分不受影响。

### 20.3 `--workers` 并行：尝试失败，已记档（**本机勿用**）

为压缩 M3（CodeBERT）耗时，给 `m3_build_features.py` 加了可选 `--workers N`（默认 1 = 原行为）。
**数值正确性已证**（单进程 vs 2 workers：张量逐元素相同、`channel_sha256`/`combined_sha256` 相同；
字节差异仅 `meta.created_utc` 时间戳）。但**两次实现都在本机失败**：

| 实现 | 现象 | 根因 |
| --- | --- | --- |
| `fork` + 父进程预加载 CodeBERT（COW 省内存） | 3 张图 10 分钟零进展，全体 0% CPU，父/子进程均卡在 futex | 父进程导入 torch 后已起 OpenMP 线程池，**fork 出的子进程继承了处于加锁状态的互斥量** |
| `spawn`（改为子进程各自加载） | 跑到 850/1774 后停滞，`_cb.pt` 5 分钟零增长，**worker 全消失、父进程卡死 futex**，swap 已用 660MB | 本机 **7.8GB** 内存撑不住 4 份 CodeBERT（约 480MB+torch 运行时/worker），**worker 被 OOM 杀掉** |

- 结论：**本机 M3 只能用单进程**（`--workers 1`）。该开关保留（默认 1、行为不变、数值已验证一致），
  供内存充足的机器使用；`--help` 与手册 §3.2 已写明适用条件。
- 教训并入"本机资源"认知：M3 在小图上可吃满多核（3 图 30s / user 4m55s ≈ 10 核），
  但在 `buggy_24…` 一类图上只占 ~0.88 核、属 Python/IO 受限——**"看起来空着的核"不等于进程级并行就能加速**。

### 20.4 执行完成：M3（GPU）→ 两臂划分 → 3 种子训练（2026-09-15/16）

| 环节 | 结果 |
| --- | --- |
| M3 构建 | **GPU 全量重建**：1774 图 / 463,264 节点，22:27:41→23:16:51 = **49 分 10 秒**（0.60 图/秒），`cb_reused=0/1774` |
| 契约校验 | 1774 个 `_feat.pt` 的 `D_struct`/`struct_layout`/`schema_version`/`role_names` 与主库**逐字段相等**，不一致 0 |
| 划分·臂A | 连通分量簇原子：池 1774、1419/178 = 177、覆盖校正替换 **0**、跨划分近重复 **0/0/0** |
| 划分·臂B | 近重复去重：池 **1400**（丢 374）、1120/140/140、替换 0 |
| 训练/评估 | 3 种子 × 2 臂，全部 **CUDA**；臂A micro-F1@0.5 **0.9744±0.0128**、@val_thr **0.9847±0.0077**、mAP 0.9804；臂B 0.9786±0.0150 / 0.9850±0.0092 / 0.9844 |

完整数字、逐类 support/F1、计时与 5 项披露见 `results.md` §6。**主库 `products/alldata/` 与 `runs/seed*`、`runs/summary.json` 零改动**（mtime 仍为 2026-09-14，已复核）。

**两次本机事故与加固**（均因 WSL 虚拟机整机重启，见 §21.6）：① 原单进程 M3 在 20:31 被腰斩，留下 2 个 0 字节 `_cb.pt`/`_feat.pt`；
② 由此发现"仅判 `exists()` 会把残缺文件当已缓存""`torch.save` 直写目标路径会产生半截文件"两个真实缺陷，已修。

**M3 串行路径不打印中途进度**（只在收工时打印一行汇总），故运行期间只能用产物 mtime 监控——
长跑时不要误以为"日志没动就是卡住"。

---

## 21. 泄漏处置：连通分量原子划分（2026-09-15；**修订 §20.2 的"必须全链接"结论**）

### 21.1 触发

`results.md` §1.7.2 把主库现行划分的同源泄漏标为"待处置"。用 §20.2 的工具按**全链接簇原子**重划
后，泄漏**降低了约 90% 但没归零**（跨划分近重复对 seed0/1/2 = 8/7/5，最高 Jaccard 0.73）。
这与"防泄漏"的目标不符——判据说的是"≥0.6 的对不得跨划分"，而全链接做不到这件事。

### 21.2 根因：全链接是**贪心分组**，不是相似图的划分

`complete_linkage_clusters` 按 base 升序贪心插入：新成员只要与**已有簇内所有成员**都有边就并入。
两条都 ≥0.6 的边，可能因为插入次序而落进不同簇。于是"簇不跨划分"（已断言）**推不出**
"≥0.6 的对不跨划分"。

### 21.3 修订：对**划分防泄漏**这一用途，原子单位必须是连通分量

新增 `--cluster-mode {complete,components}`（默认 `complete`，**默认行为不变**）：

- `complete`（全链接）：定义"紧密孪生"（簇内每对都 ≥ 阈值），**用于报告**。
- `components`（并查集连通分量）：**用于划分防泄漏**。按定义分量之间不存在 ≥ 阈值边，
  故跨划分近重复对**恒为 0**——是可证性质，不是经验降幅。

**⚠ 与 §20.2 的关系（避免误读为自相矛盾）**：§20.2 拒绝并查集，针对的是**初版**
`union_find_clusters(pairs, bases, min_shared=20)`——它直接在**未归一化的共享行数**上串联，
才会产出 92 成员巨簇（簇内 92% 成员对 Jaccard < 0.3、中位 0.11）。那条批评**成立且保留**。
本节说的是**另一件事**：在**已经过 Jaccard ≥0.6 过滤**的边集上做并查集，分量粒度完全可控
（主库实测最大 15）。两个结论不冲突，前提不同。

### 21.4 实测（主库 453 池，逐种子跨划分近重复对）

| 划分 | seed0 / seed1 / seed2 | 最高 Jaccard | 覆盖约束 C1/C2 | 产物 |
| --- | --- | --- | --- | --- |
| 现行（随机 8:1:1 + 覆盖校正） | 69 / 68 / 76 | **1.00** | 7/7 | `products/alldata/splits/` |
| 全链接簇原子 | 8 / 7 / 5 | 0.73 | 7/7 | `…/neardup_clusters.json`（报告用） |
| **连通分量簇原子** | **0 / 0 / 0** | — | 7/7 | `…/neardup_snapshot/` |

粒度代价可接受：连通分量 58 个 / 覆盖 185/500 (37.0%) / **最大 15**（全链接为 60 / 178 (35.6%) / 最大 8）。
覆盖校正仍在三种子达标（替换 10/20/17 个，下限修正 0/1/0）。

**可复现**：`python scripts/near_dup_clusters.py --print --audit-split <seed0,seed1,seed2>
--audit-out <out.json>`（`split_leakage` 复用与检测**同一批**相似对，杜绝"检测一套阈值、审计另一套"）。
产物 `products/alldata/splits/leakage_audit_legacy.json`、`products/alldata/splits/neardup_snapshot/leakage_audit.json`。

### 21.5 零泄漏臂结果（`runs/neardup/`，对照臂，**不进主结果**）

同 §17/§1.2 的完全相同超参与语料，唯一变量 = 划分：

| 指标 | 现行（带泄漏） | 同纪律（零泄漏） | 差 |
| --- | --- | --- | --- |
| micro-F1 @0.5 | 0.8954 ± 0.0211 | 0.8561 ± 0.0379 | **−0.0394** |
| micro-F1 @val_thr | 0.9296 ± 0.0090 | 0.9397 ± 0.0095 | +0.0101 |
| macro-F1 @0.5 | 0.1918 ± 0.0728 | 0.1358 ± 0.0977 | −0.0561 |
| mAP | 0.2980 ± 0.0127 | 0.3033 ± 0.1451 | +0.0054 |

**结论**：泄漏的抬升集中在**固定 0.5 工作点（−3.9 点）**；`@val_thr` 与 mAP 基本不变。机制：泄漏使
模型在正样本上过度自信、把 0.5 附近的决策边界抬高，而阈值本身是在同样带泄漏的验证集上选的，
两侧同时抬高故相互抵消。**主库正典数字（§1.2）保持"带泄漏"口径不变**，该臂只作对照——
是否把零泄漏口径升为正典，待用户裁定。

### 21.6 附带修复（2026-09-15）

- `m3_build_features.py` 新增 `--device {cpu,cuda,auto}`（**默认 cpu，主库路径逐字节不变**）：
  CodeBERT 是 M3 长杆，CPU 实测 ~1.7 图/分。GPU 实测 **6.2×**（44.6 → 7.2 ms/节点），
  数值差 max|Δ| = 5.6e-05（相对 3.5e-06，float32 累加顺序差），输出一律回 CPU。
- 同文件缓存读写加固：`cache_usable()`（0 字节残缺文件**视为未缓存**）与 `atomic_torch_save()`
  （临时文件 + `os.replace`）。**动机是实测事故**：本机 WSL 虚拟机重启（`last -x reboot` 可见
  20:51/22:20/22:21 连续重启）在 20:31 腰斩了 M3，留下 **2 个 0 字节 `_cb.pt`/`_feat.pt`**；
  原实现的 `cb_path.exists()` 会把残缺文件当"已缓存"复用。
- `train.py` / `evaluate.py` 新增显式 `--label-file` / `--label-key-mode`（原来只能靠环境变量），
  并在读划分时**硬校验"划分内 base 是否都在标签索引里"**（键模式/标签文件错配时给可诊断报错，
  而非下游裸 `KeyError`）；`train.py` 把解析后的 `label_source`（路径 + sha256 + key_mode）记入 config。
  `evaluate.py` 的标签来源按 CLI → 环境变量 → **checkpoint 记录**回退，保证评估与训练同源。
- `near_dup_clusters.py` 抽出 `similar_pairs()`（`detect` 与泄漏审计共用同一判据）。

---

## 22. C1 覆盖约束在 aug 语料上**算术不可行**（2026-09-15/16；处置 = 关闭 C1、保留 C2）

### 22.1 触发

aug 语料按 8:1:1 + 连通分量簇原子划分时，覆盖约束校正抛
`RuntimeError: 覆盖约束校正失败：test 划分内无可换出的全零簇`。
原始报错看不出根因——它只在"换出机制耗尽"时才出现。

### 22.2 根因：C1 与语料的**正样本率**冲突（可证，与种子无关）

C1 要求：对每类 $i$，$\text{val}\cup\text{test}$ 内该类正样本数 $\ge$ 该类池内正样本数的 $r$ 倍（$r=0.30$）。
求和得必要条件 $\sum_i n_i \ge r\cdot P$（$P$ = 池内正样本总数）。
而 $\sum_i n_i$ 就是"$\text{val}\cup\text{test}$ 内样本的类别数之和"：

- **单标签**语料：每个样本最多贡献 1 ⇒ 上界 $=|\text{val}\cup\text{test}|=s\cdot N$（8:1:1 → $s=0.2$）。
  故 **C1 可行 ⟺ $r P \le s N$ ⟺ 正样本率 $P/N \le s/r = 0.667$**。
- 多标签语料上界放宽到 $7sN$，条件弱得多（主库仅 1 个多标签样本，实际按单标签口径）。

实测（`ratio=0.30`、8:1:1）：

| 语料 | 池 $N$ | 正样本率 | $\sum_i \text{req}_i$ | 上界 | 判定 |
| --- | --- | --- | --- | --- | --- |
| 主库 `alldata` | 500 | 26.0% | 43 | 102 | 可行（故一直正常） |
| **aug** | **1774** | **79.7%** | **427** | **357** | **★ 算术不可行** |

> 大纲原文的处置是"**换种子重划**"。此处可证其**无效**：427 > 357 与随机种子无关，
> 任何种子都不可能达标——结构性冲突，不是运气问题。

### 22.3 处置（本报告采用）

**aug 用 `--min-pos-ratio 0` 关闭 C1，保留 C2（每划分每类 ≥1）与簇原子性。**

依据：C1 的**目的**是保证 val/test 有足够正样本可支撑逐类指标，而该目的在 aug 上**由数据本身满足**：

| 类 | 池正 | train | val | test | val+test 占比 |
| --- | --- | --- | --- | --- | --- |
| access_control | 200 | 151 | 25 | 24 | 24.5% |
| arithmetic | 251 | 192 | 26 | 33 | 23.5% |
| dos | 143 | 108 | 17 | 18 | 24.5% |
| front_running | 171 | 136 | 21 | 14 | 20.5% |
| reentrancy | 182 | 144 | 24 | 14 | 20.9% |
| time_manipulation | 106 | 85 | **9** | **12** | 19.8% |
| uncheck | 361 | 293 | 34 | 34 | 18.8% |

最低支撑仍是 val 9 / test 12，**远高于**主库若干类的 support ≤2（decisions §13 的"仅描述性呈现"档）。
即：关掉 C1 不损害 aug 的逐类评估可靠性。且实测**覆盖校正替换数为 0**——划分即纯簇原子随机 8:1:1，
没有任何人工干预痕迹。

**未采纳的替代方案**：aug 改用 **7:1.5:1.5**（$s=0.3$）使可行条件变为 $P/N\le1$、恒成立，`rule_check` 可 7/7。
不采纳的理由：① 偏离大纲固定的 8:1:1；② 与主库比例不同会让两语料数字不再严格可比。
若审稿要求 C1 形式达标，可切该方案（一条 `--split 7:1.5:1.5` 即可，代价是重训）。

### 22.4 代码改动（`make_splits.py`）

`refine_coverage` 开头新增 **C1 可行性预检**：用"池内类别数最多的 $|\text{val}|+|\text{test}|$ 个样本的
类别数之和"作上界（保守但正确），`Σ req > 上界` 时直接抛可判死的 `RuntimeError` 并给出处置建议，
把原来那句迷惑的"无可换出的全零簇"换成根因。**可行路径行为不变**（主库 43 ≤ 102，四种子/三臂全部照旧，
`tests/test_make_splits.py` 4 用例与 golden 测试一行未改且全绿）。

---

## 23. 裁定：两组结果集**并存**（2026-09-16，用户裁定「同时保存两组结果」）

### 23.1 背景

主库 `alldata(readonly)` 的**独特可信合约**在三个类上已近枯竭（dos 6 / front_running 4 /
time_manipulation 5，池级），导致 4 个类在三种子上 F1 恒为 0、macro-F1 被压在 0.19；
而第二数据集 `alldata_augmentation` 逐类正样本 106–361、零泄漏、全链已跑通。
两组数字**不可比也不可混算**——它们回答的是不同问题。故裁定**并列保存**，任一方不得替换或并入另一方。

### 23.2 裁定内容

| | **结果集 ①：主库** | **结果集 ②：增强集** |
| --- | --- | --- |
| 语料 | `alldata(readonly)`（真实部署合约 + 注入样本，**剔除 `buggy_*`**） | `alldata_augmentation`（MVD-HG 论文增强集，**全量保留**） |
| 池 | **453**（590 图 − 90 buggy − 47 去重） | **1774**（0 精确重复、0 剔除） |
| 逐类正样本 | 17 / 15 / **6** / **4** / 31 / **5** / 50 | 200 / 251 / 143 / 171 / 182 / 106 / 361 |
| 标签结构 | 多标签（同分布池内实际仅 1 个多标签） | **单标签**（每条非零恰一类，多标签 2） |
| 泄漏 | 69/68/76 跨划分近重复对（已披露） | **0/0/0**（连通分量簇原子） |
| C1 覆盖约束 | 可行（43 ≤ 102） | **算术不可行**（427 > 357），已关 C1 保留 C2（§22） |
| **micro-F1 @0.5** | **0.8954 ± 0.0211** | **0.9744 ± 0.0128** |
| **micro-F1 @val_thr** | **0.9296 ± 0.0090** | **0.9847 ± 0.0077** |
| macro-F1 @0.5 | 0.1918 ± 0.0728 | 0.9123 ± 0.0466 |
| macro-F1 @val_thr | 0.2044 ± 0.0539 | 0.9415 ± 0.0305 |
| **mAP** | **0.2980 ± 0.0127** | **0.9804 ± 0.0090** |
| 产物 | `runs/{seed0,seed1,seed2}/`、`runs/summary.json` | `runs/augmentation/`、`runs/augmentation_dedup/` |

**回答的问题不同**：
- **结果集 ①** 回答「在真实部署合约（含天然极稀缺类）上能检出什么」——**宏观指标低是数据事实，不是方法失效**
  （reentrancy ROC-AUC 0.895、uncheck 0.829 证明模型有效；见 §1.7 失败模式 A–D）。
- **结果集 ②** 回答「训练信号充足时的能力上限」——**其数字不可反向解读为主库问题已解决**（§6.7 披露 5）。

### 23.3 三条例外臂（均**不进任一组结果集**，只作披露/稳健性）

| 臂 | 产物 | 用途 | 为何不进正表 |
| --- | --- | --- | --- |
| 主库·零泄漏 | `runs/neardup/` | 量化泄漏抬升（@0.5 −3.9 点） | 与 ① 只差划分口径，二者取一即可；① 为现行正典 |
| 主库·含 buggy | `runs/withbuggy/` | 量化全 1 标签的支撑效应 | macro/mAP 跳升是**度量假象**（micro 反降） |
| 增强集·近重复去重 | `runs/augmentation_dedup/` | 验证泄漏控制方式不改变结论（差 0.4 点） | 与 ② 只差泄漏控制口径；② 为保留全量者 |

### 23.4 修订「未裁定前不得混用」条款

此前 `AGENTS.md` 与手册中的 `alldata_augmentation` 条目写有「主实验口径不变；**未裁定前**不得替换或混入主库产物」。
本次裁定后语义更新为：**两组并存、各自独立完整**；仍**禁止**把两组合并成一个数字或跨组比较绝对值，
但**允许**在论文中并列呈现（各用各的表、各标各的 support）。

---

## 24. 复现口径：三个等级、最小入库集与实测证据（2026-09-16）

### 24.1 本仓库的复现定位

| 等级 | 含义 | 本仓库 | 依据 |
| --- | --- | --- | --- |
| **L1 逐位复现** | 重跑得到**一模一样**的数字 | **可达（特征与评估层）** | M3 实测 max\|Δ\|=0；evaluate 离线重算逐项相同（见 §24.3） |
| L2 统计复现 | 重跑落在报告方差内 | 可达 | 划分/超参/协议/代码版本全部锁定 |
| L3 可重建 | 从只读源+代码重建全部产物 | 可达 | 只读源在库、产物由脚本确定性生成 |

**L1 的边界**：**训练**环节不可 L1——主实验 `deterministic=False`（`runs/seed*/config.json::args` 实测），
CUDA 非确定性算子使重训无法逐位重合。故 L1 只在**特征构建**与**指标计算**两段成立；
训练结果的复现是 L2（`--deterministic` 可提升但非主实验默认，改动会换掉正典数字）。

### 24.2 入库策略（2026-09-16 起，"重算指标所需的最小集"）

| 类别 | 入库 | 排除 | 理由 |
| --- | --- | --- | --- |
| 划分 | `split_seed*.json`、`split_metadata_*`、`split_report.json`、`coverage_swaps_*`、`dedup_dropped.txt`、`splits.csv`、`leakage_audit.json` | — | **第一重要**：决定"报告的数字对应哪份数据"；`coverage_swaps` 是人工干预痕迹 |
| 训练记录 | `config.json`（含 `label_source` 指纹）、`log.txt`、`results.json`、`thresholds.json`、`summary.json`、`diagnosis.json` | — | 参数、过程、结果、诊断全链 |
| 权重 | **`best.pt`**、`val_best_probs.pt`、`test_probs.pt` | `last.pt` | 前者即 `evaluate.py` 全部输入 → **离线重算、无需重训**；`last.pt` 仅续训用且体积翻倍 |
| 语义锚点 | **`graphs/ir_cat.json`**、**`raw/filter_report.txt`** | 其余 `graphs/`、`raw/` | 冻结 IR 字典＝跨语料兼容锚点；过滤报告＝"为何只剩 N 个"的依据。两者仅几 KB |
| 特征/图 | — | `_feat.pt`/`_cb.pt`/`_hetero.json`/`_pyg.pt`（主库 15 GB） | 体积大且**确定性可再生**（§24.3 已验证） |
| 只读源 | `alldata(readonly)/`、`DIVE/`、`SolidiFI/`、`MVD-HG-dataset/`（历史已入库） | `alldata_augmentation/`（gitignore，可由 `MVD-HG-dataset/` 派生） | 真值输入必须在库 |

实测入库体积：权重与缓存 **114.9 MB / 69 文件**、单文件最大 4.77 MB。

### 24.3 实测证据（2026-09-16）

**① M3 特征逐位可重建**：主库图 `asd_simple_suicide__simple_suicide`，删除 `_cb.pt`/`_feat.pt` 后用
**默认 CPU** 重生成 →
`combined_sha256` 相同、逐通道 sha256 相同、`struct`/`type_id`/`sv` **逐元素相同**、
`_cb.pt` 的 CodeBERT 向量**最大数值差 0.000e+00**。

> ⚠ 这只在**同设备**成立：GPU 与 CPU 的同文本数值差 max\|Δ\|=5.6e-05（相对 3.5e-06，见 §21.6）。
> 故"重建设备"属于复现口径的一部分，跨设备重建**不是**逐位复现。

**② 指标离线可重算**：只保留入库集（`best.pt` + `val_best_probs.pt` + `test_probs.pt` + `config.json`，
删掉 `last.pt` 与 `results.json`）后跑 `evaluate.py --seed 0` →
micro-F1（双阈值）、macro-F1、`mAP`、逐类 AP 数组、逐类 support、验证集阈值**全部逐项相同**。

### 24.4 覆盖风险与防护（对应手册 §12 第 51 条）

四处默认输出目录全指向正典区：`train.py`→`runs`、`make_splits.py`→`products/alldata/splits`、
`m3_build_features.py`→`products/alldata/graphs`、`generate_all_ast_cfg_dfg.sh` **开工先 `find -delete` 清空目标目录**。
2026-09-16 起 `train.py` **默认拒绝覆盖**（`run_dir_conflict()`：参数与产出该目录的那次不同即报错退出，
需 `--overwrite`），补上了原先唯一无保护的覆盖点；其余三处仍**只靠显式传目录的约定**保护。

---

## 25. 消融准备：四处覆盖守卫 + 开关接线验证 + 阻断项（2026-09-16）

### 25.1 四处覆盖点全部加守卫（用户裁定「为三中的内容加同样的守卫」）

`results.md`/本文件此前只把 `train.py` 列为"唯一无保护的覆盖点"，实测**四处默认值全指向正典产物区**：

| 命令 | 默认输出 | 破坏方式 | 守卫 |
| --- | --- | --- | --- |
| `generate_all_ast_cfg_dfg.sh` | 主库 `raw/{AST,CFG,DFG}-raw` + `raw/logs` + `raw/filter_report.txt`（**六条路径**） | `find -delete` 清空目录（实测将删 27,129 个文件）+ **`> "$FILTER_REPORT"` 重写报告** | 任一非空/非空文件时要求 `SSMHG_ALLOW_WIPE=1`，否则 exit 2 并列出将清空清单 + 打印**六条路径全貌** |
| `make_splits.py` | `products/alldata/splits` | 静默重写 `split_seed*.json` 等 | `split_dir_conflict()` + `--overwrite` |
| `m3_build_features.py` | `products/alldata/graphs` | 外部语料特征写进主库目录 | `run_guard.corpus_conflict()` + `--overwrite` |
| `train.py` | `runs` | 同 `--seed` 覆盖 `runs/seed{N}/` | `run_dir_conflict()` + `--overwrite`（§24.4 已加） |

判定逻辑统一抽到新增的 **`scripts/run_guard.py`**（不分散在各 CLI 里，避免复制多份后各自烂掉），
并由 `tests/test_run_guard.py`（20 用例）锁死。

**实施中踩到并修掉一个真 bug**：实验自述里记的是**绝对路径**，而命令行常传**相对路径**，
直接比字符串会把"同一个目录"判成冲突（实测把同参数复跑误拒）。
故 `run_guard.canonical_args()` 对已知路径型参数统一 `Path(...).resolve()` 后再比——
**两侧都归一化**，故即使某参数不是真实路径（如 HF 模型 id）也只得到一致结果。
回归测试：`test_relative_and_absolute_same_dir_is_not_a_conflict`（train 与 make_splits 各一）。

**⚠ 2026-09-16 事故与修正（必须记）**：shell 守卫的**初版只检查 AST/CFG/DFG 三个目录，且位置在日志截断之后**。
我用它自测"部分覆盖环境变量"时，只改了 `AST_DIR/CFG_DIR/DFG_DIR/LOG_DIR/SRC_ROOT`、**漏改 `FILTER_REPORT`** →
`FILTER_REPORT` 落回主库默认路径，脚本"合法地"把全 0 报告写进了正典
`products/alldata/raw/filter_report.txt`（`total_source_files=591` → `0`）。已从 HEAD 逐字节恢复。
两处修正：① 守卫覆盖**全部六条路径**（含 `LOG_DIR` 与 `FILTER_REPORT`）；
② 守卫**前移到所有清空/截断动作之前**（`mkdir -p` 之后、`> "$AST_ERR"` 与 `find -delete` 之前）；
③ 拒绝时额外打印**六条路径全貌**，让"改了一半"一眼可见。
回归测试 `tests/test_run_guard.py::test_raw_script_refuses_and_touches_nothing`：
以默认路径跑一次，断言 exit 2 且 `filter_report.txt` / `ast_error.log` 的 sha1 **前后不变**。

> 教训："部分覆盖环境变量"是最可能的误用方式，而初版守卫恰好对它免疫——**守卫的覆盖面必须等于破坏面**，
> 且必须在**任何写动作之前**执行。这条同样适用于另外三个 CLI。

`m3_build_features.py` 的守卫判据是"out-dir 已有的 `_feat.pt` 与 in-dir 的输入图**完全不相交**"——
只要有交集就放行（断点续跑/增量补图/`--force` 全量重建都合法）。
**与 `--force` 语义不同**：`--force` 是重算向量，不改变语料归属。

### 25.2 消融开关接线验证（`tests/test_ablation_switches.py`，20 用例 + 2 skip + 1 xfail）

**为什么要单独验证**：消融的价值全在"只有一个变量在动"。若某开关其实是空操作，跑出的"结论"是假的，
且从指标数字上几乎发现不了。故逐个验证**作用机制**（扰动被剔除的通道 → 输出必须不变），
而非只验证"命令能跑通"。已机器验证：4 项边消融 + `--drop-ast` + 白名单拒绝、
`ablate_sv` / `cb_channels` 单通道 / `feat_groups base` 的列级掩码、`meanpool`（改变 z 且不增参数）、
`num_bases` / `hid`、`L_var` 复合式（由既有 `log.txt` 验证 `loss_total = loss_cls + λ·loss_var`，零新计算）。

### 25.3 ★ 阻断项：「关闭先验 Dropout」无法按意图表达（**待裁定**）

**实测**：`model.sample_dropout_masks` 返回 `rand < prior_p`，掩码**乘法**作用于 s_v（0=置零、1=保留），
故 `prior_p` 是**保留率**。两个后果：

1. 默认 `--prior-dropout 0.2` 实际**置零 80% 的图**；而大纲 4.1.4 与手册 §8.6 的**散文**写的是
   「以概率 **0.2** 把 $s_v$ **置 0**」（丢弃率 0.2）→ 默认强度**差 4 倍**，且 §1.2 全部结果都带这个口径。
   > 文档自身对这一点是**矛盾**的：同段又写"按图 Bernoulli(0.2)"（若 1=保留，则丢弃 0.8）。
   > 但下面这条在两种读法下都错。
2. `--prior-dropout 0` → `rand < 0` 恒 False → **每张图都置零**，**等价于 `--ablate-sv`**。
   即 5.4.1 的「关闭先验 Dropout」跑不出它该测的东西，会与另一项消融得出同一结果。

既有测试（`tests/test_frontend.py`）只验证了**机制**（mask=0 → sv 置零），从未验证**比率**，故未被发现。
现以 `xfail(strict=True)` 钉住（修好即报错，强制同步文档与结果）。

| 方案 | 做法 | 代价 |
| --- | --- | --- |
| A（推荐） | 修 `rand >= p`（丢弃率语义），**重跑全部结果** | 主库+增强集+各对照臂全部重训，`results.md` 数字全部刷新 |
| B | 保留实现，把参数定义为保留率并**同步大纲** | 偏离大纲 4.1.4 原文；第 10 项改 `--prior-dropout 1` 表"关闭"（语义别扭） |
| C | 只补 `--no-prior-dropout`，默认口径不动 | 现有结果不失效，但"默认 80% vs 大纲 20%"的背离仍在，须在论文披露 |

### 25.4 消融就绪盘点（详见 `experiments/ablation_plan.md`）

17 项（5.4.1 十一 + 5.4.2 六）中：**12 项可直接跑**（零重跑或秒级）、**1 项需先造 M2 变体**、
**1 项被 §25.3 阻断**、**3 项需开发**（CALLBACK_RISK_REV 无反向边开关、RGCN 层数硬编码两层、微调 CodeBERT 无路径）。
3 个开发项已用 `@pytest.mark.skip` 显式登记，**不会在 CI 里假绿**。

顺带实测两条对消融设计有用的事实：
- **`--callback-limit 4` 确实在截断**：全库 CALLBACK_RISK 源节点出边数分布 `{1:47, 2:62, 3:21, 4:70}`，
  最大恰为 4 且堆在 4；单图实测 limit=0 得 25 条边 vs 默认 20 条。故"上限 4 vs 不限"**不是空操作**，
  但影响面有限（全库 ~70 个节点）→ 预期指标变化很小。
- **M2 变体的空间代价可压到 0.15 GB**：`_cb.pt` 占主库图产物的 **14.6 GB / 15 GB**，而它只依赖源码文本、
  与边无关 → 变体可**软链复用**；`_feat.pt` 不可复用（M1 的 $s_v$ 依赖 CALLBACK_RISK 端点），
  但 `_cb.pt` 命中时 M3 不加载 CodeBERT，全库约 41 s。

---

## 26. `--prior-dropout` 语义修正：保留率 → **丢弃率**（2026-09-16，用户裁定方案 A）

### 26.1 问题（§25.3 的阻断项）

`model.sample_dropout_masks` 返回 `rand < p`，而掩码是**乘法**系数（1=保留、0=整通道置零），
故 `p` 实为**保留率**。大纲 4.1.4 与手册 §8.6 的散文写的是「以概率 0.2 把 $s_v$ **置 0**」（丢弃率）。
两个后果：

1. 默认 `--prior-dropout 0.2` 实际**置零 80% 的图**——与文档口径**差 4 倍**，且 §1.2 全部结果都带此口径；
2. `--prior-dropout 0` → 恒 False → **每图都置零 = 等价于 `--ablate-sv`**，使 5.4.1 的
   「关闭先验 Dropout」**跑不出它该测的东西**（会与另一项消融得出同一结果）。

**结构 dropout 共用同一函数**（`sample_dropout_masks` 同时返回 prior/struct 两路），故**同样反了**，
一并修正——手册 §8.6 对结构 dropout 的记载同样是丢弃率 0.2。

### 26.2 修正（四处同步：代码 / 参数名 / 文档 / 测试）

**统一约定（全仓）**：`Bernoulli(p)` / `--prior-dropout p` / `--struct-dropout p` 中的 `p` **一律是丢弃率**。

| 取值 | 语义 |
| --- | --- |
| `0` | **关闭**该 dropout（掩码恒 1，不置零） |
| `0.2`（默认） | 每个图以 **20%** 概率把该通道整幅置零 |
| `1` | 每个图都置零（"全丢"）；**不要用它表示"关闭"** |

⚠ 与 `--ablate-sv` 的区别：后者是**确定性**全零消融（train/eval 一致），与 `p=0`（随机正则**关闭**）
**不是一回事**；两者在 `NodeFuser` 共用同一乘法原语，但触发路径分离。

- **代码**：`model.sample_dropout_masks` 改为 `rand >= p`（`p=0/0.2/1` 实测置零 0.000/0.197/1.000）。
- **参数名**：`--prior-dropout` / `--struct-dropout` 保持不变（本就是 dropout 命名，现在名副其实）；
  顺手清掉 `--prior-dropout` 上一句残留的垃圾 help（原文只有 `help="消融 --prior-dropout 0。"`）。
- **文档**：手册 §8.6 新增「语义约定」段并记本次修正；§11/§12-53 同步；
  `docs/M3_frontend_design.md`、`docs/M4_interface.md`、`docs/M5_dev_plan.md` 的 `Bernoulli(0.2)` 全部
  统一为 **Bernoulli(p), p=丢弃率**。
- **测试**：`tests/test_ablation_switches.py` 删除原 `xfail(strict=True)`（修好后会 XPASS 导致 pytest 失败），
  改为 6 个正常断言：`p=0` 不置零 / `p=1` 全置零 / `p=0.2` 置零≈20% / 结构 dropout 同为丢弃率 /
  eval 不传掩码不置零 / `ablate_sv ≠ p=0`；另修正 `tests/test_frontend.py::test_sample_dropout_masks_shape_and_rate`
  （它原先断言的正是旧的"保留率"语义，是本次漏改的唯一测试文件）。

### 26.3 小 smoke（真实训练循环，`tests/smoke_prior_dropout.py`，504 次抽样）

| 检查 | 结果 |
| --- | --- |
| 训练期 `prior_p` 实际传入值 | `{0.2}` ✓ |
| 实测置零率（prior / struct） | 0.2183 / 0.2024 ✓ |
| 训练批前向（18 次）是否都带掩码 | 全部带 ✓ |
| **验证批前向（12 次）是否都不带掩码** | **全部不带 ✓（eval 不置零）** |
| `--prior-dropout 0` 时的置零率 | prior **0.0000** ✓（struct 保持 0.2024，因该轮未改 struct——也证明两开关独立） |

### 26.4 旧口径结果作废并归档

`--prior-dropout` 修正前训出的**全部结果作废，不得引用、不得与新数字混用**，
已 `git mv` 归档至 **`runs/prior_dropout80/`**（10 个臂 + `README.md` 说明为何作废）：
`seed{0,1,2}`、`neardup`、`withbuggy`、`augmentation`、`augmentation_dedup`、
`loss_focal`、`loss_asl`、`pw_unclamped`。
`runs/prior_448pool/`（更早的 448 池存档）同样带此口径，一并作废。

### 26.5 重跑结果（丢弃率 0.2 口径，现行正典）

重跑方式：**逐字复用归档 config 的原始参数**（只让代码语义变），覆盖 8 个臂 × 3 种子。

| 臂 | micro@0.5 新 | micro@0.5 旧 | Δ@0.5 | micro@val 新 | micro@val 旧 | Δ@val |
| --- | --- | --- | --- | --- | --- | --- |
| 主库 | **0.8489±0.0699** | 0.8954±0.0211 | **−0.0466** | **0.9389±0.0047** | 0.9296±0.0090 | +0.0093 |
| neardup | 0.8550±0.0731 | 0.8561±0.0379 | −0.0011 | 0.9333±0.0032 | 0.9397±0.0095 | −0.0064 |
| withbuggy | 0.8776±0.0329 | 0.8727±0.0438 | +0.0049 | 0.9057±0.0398 | 0.8950±0.0429 | +0.0107 |
| augmentation | 0.9739±0.0134 | 0.9744±0.0128 | −0.0005 | 0.9828±0.0053 | 0.9847±0.0077 | −0.0019 |
| augmentation_dedup | 0.9507±0.0624 | 0.9786±0.0150 | −0.0279 | 0.9752±0.0263 | 0.9850±0.0092 | −0.0098 |
| loss_focal | 0.8830±0.0118 | 0.9090±0.0312 | −0.0260 | 0.9389±0.0187 | 0.9503±0.0204 | −0.0114 |
| loss_asl | 0.4689±0.0457 | 0.5672±0.1756 | −0.0983 | 0.9431±0.0126 | 0.9481±0.0207 | −0.0050 |
| pw_unclamped | 0.7681±0.0733 | 0.8148±0.0797 | −0.0467 | 0.9358±0.0018 | 0.9439±0.0143 | −0.0081 |

**模式**：8 个臂里 **7 个的 `@0.5` 下降**（−0.0005 ~ −0.0983），且新口径的种子间 **std 普遍更大**
（主库 0.0699 vs 0.0211；augmentation_dedup 0.0624 vs 0.0150）。主库的早停也更早
（6/16/7 epoch vs 23/18/9）→ 指向"丢弃 80% 起了**更强正则**、稳定了固定 0.5 这个工作点"。
`@val_thr` 则涨跌互见（主库 +0.0093、withbuggy +0.0107，其余略降）。

> 单臂 3 种子下主库的 Δ=−0.0466 并不显著（Welch t≈1.11）——**判定见 §26.6**。

### 26.6 裁决：**维持 `--prior-dropout 0.2`，不返工到 80%**

用户设的条件是「如果置零 20% 的图效果不好，则需要返工为现在的 80%」。为判定该条件是否成立，
做了**同配对**的剂量-反应研究（主库，train seed {3,4,5} × split seed {0,1,2} = 9 配对点，
写入隔离目录 `runs/prior_dropout_study/`，不进正典；权重已删、目录仅 2.1 MB）：

| 配置 | micro@0.5 | micro@val_thr | macro@0.5 | mAP |
| --- | --- | --- | --- | --- |
| 丢 0%（关闭正则） | 0.8623±0.0579 | 0.9369±0.0137 | 0.1838±0.0765 | **0.3154** |
| **丢 20%（默认）** | 0.8834±0.0505 | 0.9348±0.0096 | 0.1946±0.0852 | 0.3133 |
| 丢 50% | **0.8892**±0.0396 | 0.9362±0.0110 | 0.1795±0.0905 | 0.3118 |
| 丢 80%（旧实现在效） | 0.8475±0.0613 | 0.9334±0.0136 | 0.1604±0.0781 | 0.3113 |
| 丢 100%（$s_v$ 恒零） | 0.8754±0.0443 | 0.9379±0.0108 | 0.1787±0.0645 | **0.3065** |
| `--ablate-sv`（确定性恒零） | 0.8751±0.0436 | 0.9375±0.0110 | 0.1789±0.0640 | 0.3085 |

**同配对差值（相对丢 20%，n=9）**：

| 对比 | Δ micro@0.5 | t |
| --- | --- | --- |
| 丢 0% | −0.0210 ± 0.0231 | −0.91 |
| 丢 50% | +0.0059 ± 0.0072 | +0.82 |
| **丢 80%** | **+0.0359 ± 0.0223** | **+1.61** |
| 丢 100% | −0.0079 ± 0.0124 | −0.64 |
| `--ablate-sv` | −0.0083 ± 0.0120 | −0.69 |

**结论**：

1. **维持 0.2——用户设的条件不成立**。丢 80% 相对丢 20% 的 micro@0.5 是 **+0.0359（即丢 20% 反而更好）**，
   t=1.61 **不显著**；丢 100% 更差（−0.0079，t=−0.64）。**没有任何证据支持"多丢更好"。**
2. **"丢 100% 会更好吗"——不会**。四个指标全部无显著差异，且 micro@0.5 与 mAP 的符号都向下。
   **mAP 随丢弃率单调下降**（相对丢 0%：−0.0021 / −0.0036 / −0.0041 / −0.0089，两端 |t|≈1.7–1.8）
   → 多丢先验对**排序指标**有轻微损害。$s_v$ 既非负担也非主力。
3. **机制等价性已验证**：丢 100% 与 `--ablate-sv` 的 micro@0.5 差 **+0.0003**（t=0.55）、mAP 差 −0.0020（t=−1.05）
   → "随机正则全丢" ≡ "确定性全丢"，两者是同一件事的两种表达。
4. **§26.5 表中"7/8 臂 @0.5 下降"的读数是种子噪声**。当时只有正典 3 种子（train seed 0/1/2），
   扩到 9 配对后方向反转。**单臂 3 种子不足以判定该量级（±0.05）的效应**，这个教训写进 §26.7。

### 26.7 教训

- **只改语义、不改"看法"**：我最初根据 3 种子的 8 臂表面模式下了"丢弃 80% 起了更强正则"的判断，
  扩样后反转。**噪声水平 ±0.05 的指标，n=3 的表面模式不可信**；判定差异须用**同配对**设计并 ≥9 点。
- 作废口径的**权重不必入库**：它与现行口径只差一个开关（`--prior-dropout 0.8`），
  保存 114 MB 二进制的收益远低于成本（尤其在本机 C 盘紧张的约束下）。**保留 JSON/text 即可**。
- 修语义会**连带改变下游结论**：§1.8（放开截断）与 §1.10（focal/ASL）在新口径下**方向翻转**
  （详见 `results.md` 对应小节，已据实重写并标注"需多种子复核"）。**口径变更不是只刷新数字，必须复核结论。**

---

## 27. §1.8/§1.10 的多种子复核（2026-09-17；**含对我自己判读的两次更正**）

### 27.1 为什么复核

修正 `--prior-dropout` 语义后，§1.8（放开 `pos_weight` 截断）与 §1.10（focal/ASL）的**结论方向在新口径的
3 种子读数下翻转**，我当时据实标注了「⚠ 需多种子复核」而**没有下新结论**——这是对的。

复核用与 §26.6 完全相同的**同配对**设计：基线直接复用 `runs/prior_dropout_study/drop20_ts{3,4,5}_ss{0,1,2}`，
三个臂各在同一批 9 个点上重跑（`runs/loss_study/`，隔离、不进正典；权重已删、目录 1.1 MB）。

### 27.2 §1.8：**旧结论成立，我中途的"方向翻转"标记是错的**

| 指标 | Δ（放开截断 − 基线） | t |
| --- | --- | --- |
| **micro-F1 @0.5** | **−0.0825 ± 0.0236** | **−3.50 ★显著变差** |
| micro-F1 @val_thr | +0.0010 | +0.32 |
| macro-F1 @val / @0.5 | −0.0311 / −0.0223 | −1.20 / −0.76 |
| mAP | +0.0090 | +0.61 |

逐类 ΔF1(@val_thr)：access **+0.000** / arith −0.050 / reentr −0.056 / uncheck −0.112 → **稀有类没有任何抬升**。

**结论**：3 种子下读到的"`access_control` 0.000→0.121"是**种子噪声**；「放开截断没有救活稀有类」
**成立**，且显著伤害固定 0.5 主指标。**撤回我在 `results.md` 里加的"方向翻转"标记。**

### 27.3 §1.10：**旧结论部分不成立——focal 是真实的小幅改进**

| 指标 | focal(γ=2) | ASL |
| --- | --- | --- |
| micro-F1 @0.5 | +0.0003 (t=+0.02) | **−0.3734 (t=−8.76 ★崩溃)** |
| **micro-F1 @val_thr** | **+0.0072 (t=+2.80 ★)** | +0.0066 (t=+1.70) |
| macro-F1 @val_thr | +0.0225 (t=+1.25) | **+0.0735 (t=+2.86 ★)** |
| mAP | +0.0514 (t=+1.96 边缘) | **+0.0915 (t=+3.31 ★)** |
| 逐类 @val_thr（reentr/uncheck/arith） | +0.109 / +0.038 / +0.011 | +0.144 / +0.185 / +0.185 |

- **focal 是本轮唯一「显著更好且不付代价」的**：`@val_thr` 显著 +0.0072、`mAP` +0.0514（边缘），
  而 `micro@0.5` **完全不受影响**（+0.0003）——即其收益**不来自"以主指标换参考指标"**。
  旧结论「两者都不胜出」**对 ASL 成立，对 focal 不成立**。
- **ASL 的收益与崩溃同源**（机制性）：负样本调制 `(p−0.05)^4` 把负样本梯度压到近零 → 概率整体膨胀
  → 对**不依赖阈值的 mAP 有利**（+0.0915 显著）、对**固定 0.5 致命**（−0.3734 显著）。这一条与我原来的
  机制解释一致，且量级在 n=9 下确认。

### 27.4 待裁定：主实验是否改用 focal？

**未擅自更改。** focal 的效应量级是 **+0.0072（`@val_thr` 主指标）**，方向一致且统计显著（n=9 配对），
但改它属**口径决策**——会再次作废全部结果（主库、增强集、各对照臂）。取舍：

| 方案 | 收益 | 代价 |
| --- | --- | --- |
| A. 维持 bce | 结果不动；focal 作为"改进线索"写入论文讨论 | 放弃 +0.0072（@val_thr）与 +0.0514（mAP） |
| B. 主实验改用 focal | 主指标 `@val_thr` 显著更好、mAP 提升、逐类有支撑类一致改善 | **全部结果作废重跑**（约 1 小时 GPU）+ 再次刷新全部文档与表格 |

**建议 A**：+0.0072 在论文主表里看不出差别（远小于种子间波动 ±0.02–0.07），却要付出"再次作废全部结果 +
与既有 `pos_weight`/标定等一组消融的可比性重建"的代价；**把 focal 作为「损失形状的改进方向」写入讨论更适合**。
若后续要冲指标，B 是现成的（一条命令 `--loss focal`）。

### 27.5 教训（第二次同类）

同 §26.7：**噪声 ±0.05–0.07 量级的指标，n=3 的表面模式不可信**。两天内我被同一坑咬了两次——
§26.5 的"7/8 臂下降"与 §1.8 的"抬出零"，两者在 n=9 配对下都反转/消失。
**规范：凡要下"某干预有效/无效"的结论，必须用同配对且 ≥9 点；3 种子只用于报 mean±std，不用于判方向。**

---

## 28. ★ `micro_f1` 实现口径修正：`.ravel()` 使 micro-F1 **退化为 accuracy**（2026-09-17）

### 28.1 缺陷

`scripts/metrics.py` 的 `micro_f1()` 与 `search_global_threshold()` 对输入调用了 `.ravel()`：

```python
f1_score(_as_numpy(y).ravel(), _as_numpy(p).ravel(), average="micro", zero_division=0)
```

`[N,7]` 展平成 1-D `{0,1}` 后，sklearn 的 `type_of_target` **从 `multilabel-indicator` 改判成 `binary`**，
而 `f1_score(average="micro")` 在 binary 下**恒等于逐样本 accuracy**（数学恒等：micro 在两类上平均
TP/FP/FN，等价于逐样本命中率）。**标签对级 F1 与准确率是两个量**，多标签稀疏场景下相差可达数十个点。

契约（模块 docstring 第 5 行）写的是「对 `(样本, 类)` **展平**后计算」——「展平」是**统计口径**
（把所有标签对汇总统计 TP/FP/FN），不是**数组操作**。实现者按字面理解写了 `.ravel()`，口径由此丢失。
**同一文件内 `macro_f1` / `per_class_prf` / `mean_average_precision` / `subset_accuracy` 都传二维数组，
全部正确**——所以这不是"整体口径错"，而是**一个函数退化成另一个量**，也因此长期未被察觉。

### 28.2 证据（三重，互相独立）

**证据一：分派分支可观测。** 同一组 `{0,1}` 数据：

| 输入形状 | `type_of_target` | `average="micro"` 的语义 |
| --- | --- | --- |
| `[N,7]` 二维 | `multilabel-indicator` | 标签对级 F1 ✅ |
| `.ravel()` 后 1-D | `binary` | **逐样本 accuracy** ❌ |

随机稀疏用例（200×7，正例率 0.15/0.10）：修复后 0.110193，与 `f1_score(y2d, p2d, "micro")` **逐位相等**；
旧实现 0.769286，与 accuracy **逐位相等**；两者差 0.659。

**证据二：24/24 个 run 的旧记录与 accuracy 逐位相等。** 用归档的 `val_best_probs.pt` + 与训练同源的
`dataset.build_index` 重算（阈值 0.5，**验证集**）：

| 臂/种子 | 旧记录 | accuracy | 真 micro-F1 | Δ(旧−真) |
| --- | --- | --- | --- | --- |
| main/s0 | 0.7968 | 0.7968 | **0.2381** | +0.5587 |
| main/s1 | 0.9048 | 0.9048 | **0.5000** | +0.4048 |
| main/s2 | 0.8508 | 0.8508 | **0.2295** | +0.6213 |
| augmentation/s0–s2 | 0.9695 / 0.9831 / 0.9912 | 同左 | 0.8889 / 0.9320 / 0.9646 | +0.081 / +0.051 / +0.027 |
| augmentation_dedup/s0–s2 | 0.9827 / 0.8786 / 0.9888 | 同左 | 0.9244 / 0.6270 / 0.9511 | +0.058 / +0.252 / +0.038 |
| loss_focal/s0–s2 | 0.9016 / 0.8921 / 0.8952 | 同左 | 0.4918 / 0.5000 / 0.3774 | +0.410 / +0.392 / +0.518 |
| loss_asl/s0–s2 | 0.4698 / 0.4603 / 0.5111 | 同左 | 0.1932 / 0.2056 / 0.1979 | +0.277 / +0.255 / +0.313 |
| pw_unclamped/s0–s2 | 0.7810 / 0.6984 / 0.8921 | 同左 | 0.2737 / 0.2636 / 0.4848 | +0.507 / +0.435 / +0.407 |
| neardup/s0–s2 | 0.7683 / 0.8413 / 0.9111 | 同左 | 0.2316 / 0.1667 / **0.0000** | +0.537 / +0.675 / +0.911 |
| withbuggy/s0–s2 | 0.9000 / 0.8543 / 0.8971 | 同左 | 0.8087 / 0.6577 / 0.7907 | +0.091 / +0.197 / +0.106 |

**旧记录与 accuracy 的最大绝对差 = 0.00e+00（24 个 run）**。恒等关系在真实数据上无一例外。

**证据三（最严重）：旧 `best.pt` 是「从未学过任何漏洞」的全负模型。** 归档 `seed0/log.txt` 的
val 轨迹（左）与重训后的同一条（右）：

| epoch | 旧 val_micro（实为 accuracy） | 旧 val_macro | 新 val_micro（真） | 新 val_macro |
| --- | --- | --- | --- | --- |
| 0 | 0.9302 | 0.0000 | 0.2381 | 0.1562 |
| 2 | 0.9302 | 0.0779 | 0.4390 | 0.2557 |
| 5 | 0.9302 | 0.0779 | 0.5075 | 0.3405 |
| 8 | —（已早停） | — | **0.5652** | 0.3591 |
| 13 | — | — | 0.5581 | 0.3537 |

旧口径下 `val_micro` **六个 epoch 冻结在 0.9302 一动不动**——那正是全判负预测器的负类基准率
（`1 − 正例率`），而 `val_macro` 起始为 **0.0000**（一个类都没预测出来）。因为"永不提升"，
`bad_epochs` 一路累加，`--early-stop-patience 5` 在第 6 epoch 触发；`improved = val_micro > best_micro`
在第 0 epoch 后就再没成立过，**被选中的 `best.pt` = epoch 0 的全负模型**。
这也解释了此前 §4.1 记录的**退化验证阈值**：`search_global_threshold` 遍历到最优点时
`max(prob)=0.567 < 0.60`，即**全判负点**被选为"最优阈值"——accuracy 0.9302，真 micro-F1 **为 0**。

> **一句话**：不是"数字算错了 0.6"，而是**连模型选择都错了**——正典结果出自一批未训练的退化权重。

### 28.3 影响半径

| 位置 | 后果 | 可否离线重算 |
| --- | --- | --- |
| `evaluate.py:109` 及全部报告位 | 报告的 micro-F1 全是 accuracy | ✅ 可用 `test_probs.pt` 重算 |
| `metrics.search_global_threshold`（阈值搜索目标） | 按 accuracy 选阈值 → 选中退化全负点 | ✅ 可重算 |
| `train.py:470-481`（LR 调度 / 早停 / `best.pt` 选择） | **全部 checkpoint 被错误目标选出** | ❌ **只能重训** |

`macro_f1` / `per_class_prf` / `mean_average_precision` / `subset_accuracy` **不受影响**（一直传二维）。
这解释了报告里一处长期反常：**micro-F1 高得离谱（0.85–0.97）而 macro-F1 低到 0.09–0.15、
mAP 只有 0.28** —— 现在自洽了：那个"高 micro"根本不是 micro。

### 28.4 修复（用户裁定后执行，2026-09-17）

1. **`scripts/metrics.py`**：新增 `_as_2d()`（一维输入视为单列，**严禁 ravel**），`micro_f1()` 与
   `search_global_threshold()` 改用它；顺带删掉 `search_global_threshold` 里一行未使用的
   `metric_fn` 死代码。模块 docstring 改为明确区分「统计口径的汇总」与「数组展平」，并写明禁用理由。
2. **`tests/test_metrics.py`**：原有 2 处用 `.ravel()` 写期望值的断言改为二维参照（**测试自身曾把 bug 锁成"正确行为"**，
   这是它能长期存活的原因之一）；新增 3 个回归锁：
   - 全判负时 micro-F1 **必须恰为 0**（而 accuracy 为 25/28）；
   - 随机稀疏多标签下 micro-F1 = sklearn 二维参照，且 **≠ accuracy**、**≠ `subset_accuracy`**；
   - 阈值搜索逐候选 = 二维 micro-F1，且 **argmax ≠ accuracy 的 argmax**（否则该测试对该 bug 无鉴别力）。
3. **全套测试**：`pytest tests/` **157 passed, 2 skipped**（2 skipped 为 §25.4 登记的待开发项）。

### 28.5 旧产物作废与归档

`runs/` 下全部现行产物移入 **`runs/prior_badmetric/`**（含 README 说明），沿用 `prior_dropout80` /
`prior_448pool` 的归档惯例。**注意 `run_guard` 拦不住这次**：它只比对**参数**，
而本修复不改任何 CLI 参数 → 会被判定为"同一次实验"并放行覆盖。**故必须先手工归档再重放。**
`runs/prior_badmetric/` 内**所有** micro-F1 数字均已作废；权重（`best.pt`/`last.pt`）**保留未删**
（无效但为诊断物证，且 `best.pt` 是 `evaluate.py` 唯一输入）。

### 28.6 重训

新增 `scripts/rerun_from_config.py`：以归档的 `config.json::args` 为**唯一事实来源**重建命令行，
逐参数与原跑一致（8 个正典臂 × 3 种子 + 2 个研究臂 × 81 配对 = **105 个 run**），
避免手工传 38 个参数时漏掉 `--label-key-mode stem` 之类的静默错误。
`--prune last` 剪除 `last.pt`（仅断点续训用，重放 10–60 秒级实验时无意义）。

**执行结果（2026-09-17）**：105 个 run（驱动 104 + 早先单跑 1），wall **2530.9 s ≈ 42 min**（GPU 串行；
主库 run 约 16–33 s、增强集约 120–156 s）。随后评估 24 个正典 run（97.4 s）+ 8 个臂 `--summarize` +
逐类诊断（主库与 3 个干预臂）+ 标定分析。研究臂权重按原惯例剪除（81 个 `best.pt`，仅留
`val_best_probs.pt` + JSON），`runs/` 净体积 354 MB。

**主库正典（`runs/summary.json`）**

| 指标 | 旧（坏口径） | 新（正确） |
| --- | --- | --- |
| micro-F1 @0.5 | 0.8489 ± 0.0699 | **0.4256 ± 0.0309** |
| micro-F1 @val_thr | 0.9389 ± 0.0047 | **0.4528 ± 0.0774** |
| macro-F1 @0.5 | 0.1469 ± 0.0936 | **0.2503 ± 0.0313** |
| macro-F1 @val_thr | 0.0967 ± 0.1284 | **0.2621 ± 0.0506** |
| mAP | 0.2804 ± **0.0963** | 0.3047 ± **0.0119** |
| 精确匹配 @0.5 | — | 0.543 ± 0.075 |

**三处结构性变化（比数字本身更重要）**

1. **旧结论「验证集阈值大幅提升主指标」（0.85→0.94）是退化假象。** 真口径下 `@val_thr` 仅比 `@0.5` 高 **+0.027**；
   旧口径那 `+0.090` 来自把阈值选到了**全判负点**。`decisions.md` 中一切"val 阈值救回主指标"的表述须据此重审。
2. **mAP 的标准差从 ±0.0963 塌到 ±0.0119（−88%）。** mAP 本身不受本 bug 影响（一直传二维），
   所以这个变化**纯粹来自模型选择的改善**——旧口径下三个种子被选中了退化程度各异的 epoch。这是
   「修复指标 = 修复训练控制流」的最直接量化证据。
3. **micro 大幅下降而 macro 大幅上升**（−0.423 / +0.103）。旧的"高 micro"是全判负预测器的 accuracy，
   它同时把 macro 压到近零；模型真正开始学习后两个指标才回到同一量级。**`access_control` 不再恒零**
   （F1@val_thr 0.229 ± 0.206），"4 类恒零"改为 **3 类**（dos / front_running / time_manipulation）。

**结论翻转清单（n=9 同配对，重训后重算；脚本 `scripts/paired_study_analysis.py`）**

| 旧结论 | 出处 | 新结论 |
| --- | --- | --- |
| `focal(γ=2)` 是"显著更好且不付代价"的干预：`@val_thr` +0.0072（t=+2.80 ★）、mAP +0.0514（t=+1.96 边缘） | §27.3 | **推翻**。`@val_thr` +0.0210（**t=+0.84 不显著**）、mAP **−0.0008（t=−0.05 零效应）**、`@0.5` +0.0242（t=+1.02）。逐种子方向也不一致 → **§27.4 原本的建议 A（维持 bce）反而是对的，只是当时理由错了** |
| 放开 `pos_weight` 截断仅在 `@0.5` 显著变差（−0.0825, t=−3.50），`@val_thr` 无影响（+0.0010, t=+0.32） | §27.2 / §1.8-d | **加强**。`@0.5` **−0.1405（t=−7.02）**、`@val_thr` **−0.0702（t=−3.31 由不显著变显著）**、mAP −0.0191 → **两个工作点上都显著更差，无一项改善** |
| ASL 的 mAP 显著更好（+0.0915, t=+3.31 ★）而 `@0.5` 崩溃（−0.3734, t=−8.76） | §27.3 | **部分推翻**。`@0.5` 崩溃更强（**t=−11.29**，精确匹配塌到 0.043）；**mAP 优势不再显著**（+0.0239, **t=+1.05**）→ "概率膨胀对排序指标有利"方向仍在、幅度不足以显著 |
| 泄漏不再是可判定效应：零泄漏臂 `neardup` 比现行划分臂**高** +0.0062 | §21 | **方向翻转**。正确指标下**低** −0.0810，符合"少泄漏 → 分数更低"的预期。⚠ 但 n=3 且区间重叠（0.3446+0.0829 > 0.4256−0.0309），**仍不足以判定**；欲定论须同配对 ≥9 点 |
| dropout 维持 0.2（mAP 随丢弃率单调下降） | §26.6 | **存活**。`drop20` 的 mAP 0.4524 最高，随丢弃率单调降（0.4524 → 0.4405 → 0.4063），`drop80` 双指标最差（−0.0413 t=−1.94 / −0.0461 t=−2.21） |

`report_conclusions.md` §7 的"临时最优设计"与 §7.2 两张 n=9 表**均基于坏指标选出的权重**，
已按其 §7.5 声明的效力边界作废，不再作为设计依据；设计选型以本节结论为准。

> ⚠ **本次修复暴露了一条比数字更重要的规范**：**凡是参与训练控制流（早停/调度/选点）的指标，
> 修改它就等于作废全部结果。** 因此"修指标"从来不是只改报告函数——`evaluate.py` 那条路径可以离线重算
> （`test_probs.pt` 缓存），`train.py` 这条不能。**判断一次口径修复的真实代价，先问"该指标有没有进控制流"。**

### 28.7 教训

1. **"展平"是有歧义的词，代码里必须写成数组形状契约。** 模块 docstring 写"展平后计算"，
   实现者就写了 `.ravel()`。凡是口径描述，应直接写**输入形状与分派预期**（"二维 `[N,7]`，
   走 `multilabel-indicator`"），而不是描述统计过程。
2. **测试会把 bug 固化成"正确行为"。** 两处断言直接复制了实现里的 `.ravel()` 当期望值，
   于是"与 sklearn 对照逐位相等"这一关卡反而保证了 bug 不被发现。
   **对照测试必须以口径定义书写，不能以实现书写。**
3. **`n=3` 的平均值会掩盖退化。** main/s1 的旧 micro-F1 是 0.9048（accuracy），
   看起来和 s0/s2 的 0.7968/0.8508 是同一量级；但真 micro-F1 分别是 0.2381/0.5000/0.2295。
   **平均值不是健康度指标**——须同时看 macro-F1 与逐类 support，二者长期反常一致指向此类缺陷。
4. **修复口径必须连带检查 `best.pt` 选择路径。** 若只改 `evaluate.py` 的报告函数，
   会得到"数字对了但模型仍是退化的"这一更隐蔽的错误状态。**判据：指标函数若参与了训练控制流
   （早停/调度/选点），修它 = 全部结果作废。**
5. **旧表自己就报过警，只是没人把相邻的列放在一起读。** `results.md` §1.3 的 seed0 行原为：

   | micro-F1(0.5) | macro-F1(0.5) | mAP | subset acc(0.5) | val 阈值 |
   | --- | --- | --- | --- | --- |
   | 0.7795 | 0.1071 | 0.1754 | **0.0000** | 0.60 |

   一个"micro-F1 = 0.78"的模型，在 46 个测试样本上**没有一条 7 维标签被完全预测对**（subset acc = 0），
   macro-F1 只有 0.107，mAP 0.175，而"最优"验证阈值 0.60 是**全判负的退化点**。
   这四件事互相印证、单独看都像噪声，**放在一行里就是自相矛盾**。
   → **规范：报告多标签结果时，主指标必须与 `subset_accuracy`、macro-F1、逐类 support 同表呈现。**
   指标间的一致性检查（此处：micro-F1 远高于 subset acc 又远高于 macro-F1）是最廉价、也最先能
   发现口径错误的关卡——它不需要任何额外计算，只需要把已有的列摆在一起看。

---

## 29. 指标口径的横向分解、语料标签结构、`diagnose.py` 标签源缺口（2026-09-17）

本节回答三个在 §28 之后浮现的问题，并为阶段 F/消融的使用铺路。

### 29.1 语料的标签结构：两套训练语料其实都是**单标签**

| 语料 | 池 | 含 0 标签 | 含 1 标签 | **含 ≥2 标签** | 标签矩阵正例率 |
| --- | --- | --- | --- | --- | --- |
| ① 主库（M5 实际池） | 453 | 326（71.9%） | 126（27.8%） | **1（0.2%）** | 4.04% |
| ② 增强集 | 1774 | 362（20.4%） | 1410（79.5%） | **2（0.1%）** | 11.39% |
| DIVE 外部测试 | 21696 | 2686（12.4%） | 4221（19.5%） | **14789（68.2%）** | — |

主库**图级池 590** 中本有 92 个多标签合约，但**全部落在被剔除的 `buggy_*` 集里**，
故进入 M5 的 453 池只剩 1 个。

**结论**：本项目「多标签」一词描述的是**输出空间**（7 个独立 sigmoid 判定），**不是标签共现**。
多标签叙事的实证依据是 **DIVE 的 68.2%**——与 §13「多标签叙事降级为架构性声明 + DIVE 外部证据」一致，
**本次是首次把该事实量化到池级**。
⚠ `report_data.md` §1.1 与 `results.md` §0 的「标签结构：多标签」一行容易被读成"标签共现"，
已在该处补注说明。

### 29.2 「多标签 vs 二分类」不是本任务上的真实分叉——但代价可以量化

模型本来就是 7 个二分类头共享主干，故两者不是二选一。真正可比的是**问法**：
把同一模型的输出按粗粒度重新计分（"有没有漏洞"vs"是哪一个"）：

| 问法 | ① 主库 test | ② 增强集 test |
| --- | --- | --- |
| 七类 micro-F1（"是哪一个"） | 0.4256 ± 0.0309 | 0.9347 ± 0.0172 |
| 塌成二分类 F1（"有没有"） | **0.7841 ± 0.0886** | **0.9892 ± 0.0106** |
| **差** | **0.359** | **0.055** |

**同一套代码、同一输出空间，代价从 0.36 掉到 0.055** ⇒ 主库那 0.36 **不是多标签造成的，是数据造成的**。

分解主库的 0.359：
- **只值 0.035** 来自"输出空间冗余"（去掉 3 个恒零类：0.4256 → **0.4601 ± 0.0380**）；
- **~0.32** 来自「在有信号的 4 个类里认对是哪一个」的真实难度。

**规范**：讨论"多标签是否更难"时，必须**同时给出两个语料的同一个分解**——
只看主库会误判为架构问题，只看增强集会误判为不存在问题。

### 29.3 一个反直觉读数：accuracy 在本任务上**有害**

主库 test：模型单元格 accuracy = **0.8872 ± 0.0190**，而**全判负基线 = 0.9348 ± 0.0000**。
**按准确率，训练过的模型比什么都不预测还差**（它预测正例换来召回，拉低了准确率）。
而 micro-F1 对全判负给 **0.0000**。

→ 两条推论：
1. **accuracy 在本任务上是有害指标**，任何以它为优化目标或报告口径的做法都会奖励退化解——
   §28 的缺陷正是如此（`.ravel()` 让 micro-F1 退化成 accuracy，早停随即在 6 个 epoch 内选走全负模型）。
2. **旧口径的 0.8489 离全判负基线（0.9348）其实不远**——它不是"接近 0.85 的性能"，
   而是"比什么都不做还差的模型"在 accuracy 上的读数。

### 29.4 `diagnose.py` 标签源缺口（**已修复**）

`scripts/diagnose.py` 原以 `build_index(Path(args.graph_dir))` 取标签，**不接受**
`--label-file`/`--label-key-mode`——即**硬编码主库标签源**。对第二语料跑时会拿主库标签去匹配
该语料的图 base，**全部对不上却不报错**（`index[b]` 只在训练集共现那一步用到，错了也只会得到
错位的诊断数字）。这是一个"不报错的错"，与 §28 里 `.ravel()` 的形态同类。

**修复**（对齐 `evaluate.py::eval_seed`）：
- 新增 `resolve_label_source(args, config)`：**CLI → 环境变量 `SSMHG_LABEL_FILE`/`SSMHG_LABEL_KEY_MODE`
  → checkpoint 记录的 `label_source`**；三者皆无时返回 `(None, None)`，**刻意不静默回退主库默认**。
- 新增 `--label-file`/`--label-key-mode` 参数。
- 索引后**硬校验** `split["val"]+split["test"]` 内 base 可解析，缺则 `SystemExit` 并给出示例 base。
- `runs_dir` 的打印改为按实际路径（原硬编码 `runs/seed{s}/`）。
- 新增 `tests/test_diagnose.py`（**5 用例**）钉住优先级规则。

**实测**：
- 增强集 + 不传标签参数 → 正确回退到 checkpoint 的 `label_source`（file=…repaired.json, mode=stem），
  逐类 test support `24,33,18,14,14,12,34` 与独立重算**逐位吻合**；
- 增强集 + 故意传 `--label-key-mode project` → 报错退出（退出码 1）：
  「划分内有 72/355 个合约不在标签索引中」+ 示例 base。
- `pytest tests/` **162 passed + 2 skipped**。

**副产物**：补跑增强集诊断 → `runs/augmentation/seed*/{diagnosis.json,test_probs.pt}` +
`runs/augmentation/diagnosis_summary.json`（此前该臂**没有任何诊断产物**）。

### 29.5 一条应加入报告规范的告警

旧 `report_data.md` §2.3 表里，`dos` 的 **ROC-AUC = 0.126**——**远差于随机（0.5）**。
恒定输出的退化模型恰好会让 AUC 落到 0.5 以下；重训后该值回到 **0.578**。

**规范：`ROC-AUC < 0.5` 应触发告警（"模型没在工作"），而不是当成"这个类学不好"。**
这正是 §28.7 教训 5 的同型问题的又一次实例——**指标间的不一致（此处 AUC 远低于 0.5）
比单看任何一个指标都更早、更廉价地暴露退化**。

---

## 30. 误报率 / 漏报率的三层口径（2026-09-17，新增分析层，**不改动任何主结果**）

**背景**：结论卷（§1–§8）全部用 micro-F1 / macro-F1 / mAP 表达，都是**分数**，回答"方法好不好"；
**不回答**"这个工具敢不敢上"。补一层运维口径（FPR / FNR）。

**产物**：`scripts/error_rates.py`（只读 `runs/**/seed*/test_probs.pt`，零重训、零 GPU）→
`runs/error_rates.json`；纯函数与恒等式由 `tests/test_error_rates.py`（9 例）锁住。
报告见 `experiments/report_conclusions.md` §9。

### 30.1 裁定：**必须三层同报，禁止只报一层**

多标签下"误报率"**没有唯一值**，三个口径互不相等（主库① test @val_thr 实测）：

| 层 | 定义 | ① @val_thr 实测 |
|---|---|---|
| L1 标签对级 | `FPR=ΣFP/(ΣFP+ΣTN)`、`FNR=ΣFN/(ΣFN+ΣTP)` | FPR 5.1% / FNR 49.2% |
| L2 逐类 | `FPR_c=FP_c/(FP_c+TN_c)`、`FNR_c=FN_c/(FN_c+TP_c)` | 见结论卷 §9.4 |
| L3 合约级 | 无漏洞却报出≥1类 / 有漏洞却一类没报出 | FPR 18.3% / FNR 30.6% |

**理由**：L1 与 L3 相差 **3.6 倍且方向相反**（少报 ⇒ L1 的 FPR 低、L3 的漏报率高）。
单报 L1 会得出"几乎没有误报"的**相反结论**。**安全工具的实际代价落在 L3**（被告警的是合约，不是标签对），
与本仓既有约定一致（手册 §10.2：DIVE 外部测试报「全零子集每类 FPR」）。

### 30.2 恒等式：**L3 合约级 ≡ 二分类（"有没有漏洞"）视图**

把 7 类真值与预测都塌成 `any(...)` 后，L3 的 `false_alarm_rate` / `miss_rate` **恒等于**二分类的 FPR / FNR。
已固化为测试 `test_l3_equals_collapsed_binary_view`；实算与 `report_data.md` §2.3.1 的独立算法
**逐位一致**（主库 @0.5 二分类 F1 = 0.7841、增强集 @0.5 = 0.9892）。

**推论（写入结论卷 §9.5）**：本仓**不需要"改成二分类"**——二分类视图一直是免费派生的。
七类相对二分类的 0.36 F1 差额，**约 2/3 是"把有漏洞的合约报成了别的类"**（① 主库 FP 中 63–65% 落在
已有漏洞的合约上），**这类错误在二分类里被整类免除**；涨的是"类别混淆被原谅"，不是检测能力。

### 30.3 不得引用本层的三条禁令

1. **不得**把 L1 的 FPR/FNR 与 `micro-F1` 之外的指标混算，或与 L3 互换使用。
2. **不得**跨结果集①②比较 FPR/FNR（§23 跨组禁比）；② 的干净合约仅 23 个，一个误报 = 4.3 个点、std ±0.105。
3. **不得**在 n=3 上对 FPR/FNR 差值下"干预有效"的结论（§26.7/§27.5 规范不变）。
   §9.2「阈值 0.5→val_thr 使漏报率翻倍」是**描述性读数**，不是已确立的效应。

### 30.4 一条记为候选、**尚未验证**的线索

现行阈值搜索目标是 **val micro-F1（标签对级）**，而部署代价是**合约级**的（§30.1）。
① 主库实测显示两个工作点在合约级上"漏报率翻倍"（14.7% → 30.6%）而 micro-F1 几乎不动（0.4256 → 0.4528）
→ **搜索目标与部署代价不一致**。§1.2 否证的是"换阈值不改目标"，**换目标**未测。
**记为候选，不当作结论**；若要做，须走 §28 的口径纪律（改 `metrics.search_global_threshold` 的
`metric` 分支 + 重跑 evaluate + 同配对复核）。

### 30.5 **裁定：「合约级二分类」是报告口径，不是训练口径**（2026-09-17）

**问题**（用户提出）：既然合约级二分类的数字更好看（§30.2），那把它用作**训练控制流**
（早停 / 学习率调度 / `best.pt` 选点 / 阈值搜索目标）是否也更占优？**裁定：否。**

**决定性证据（零重训，用 235 份 `val_best_probs.pt` + 106 份 `log.txt` + `test_probs.pt`）**：

| 预测器 | ① 主库 合约二分类 F1 | ① 主库 micro-F1 | ② 增强集 合约二分类 F1 | ② 增强集 micro-F1 |
|---|---|---|---|---|
| 真实模型 @val_thr | 0.723 | 0.453 | 0.990 | 0.955 |
| **恒报任意单一类**（7 类各试） | **0.620（七类完全相同）** | 0.030–0.209 | **0.930（同）** | 0.085–0.219 |
| 全判正 | 0.620 | 0.122 | 0.930 | 0.221 |

1. **判据饱和**：真实模型 vs 常量解只差 **0.103**（①）/ **0.060**（②）。可提升空间被压到几乎为零。
2. **判据对类别身份完全盲**：七个"恒报某一类"得**逐位相同**的分（`any()` 抹掉类别）。
3. **选择更不稳**：13 格阈值曲线上，二分类目标的不同取值 **9.4** vs micro 的 **12.3**、
   距最优 ≤0.01 的格点 **2.0** vs **1.2**、**2.8%** 的 run 整条曲线都在平台内。
   根因：val 只有 45 个合约，micro-F1 在 `45×7=315` 个格子上算，**负样本池大 12 倍**。
4. **早停现状并不差**：106 run × 21.3 epoch 中 `val_micro_f1` 有 **17.7** 个不同取值；
   早停选中位置 71.6%、末轮即最优仅 13.2%、末轮差 0.0286 ⇒ **早停确实在做功**。

> 🔴 **与 §1.1 的 `withbuggy` 假象同型**：常量解把按"合约是否有漏洞"聚合的指标撑到 0.62/0.93，
> 因为语料正样本率本身就高（① test 约 45%、② **87%**）。**凡此聚合口径都会被常量解刷分。**

**⚠ 边界（不得越界引用）**：以上证明的是**度量/判据**弱，**不是**"训练一个二分类模型"弱——
单头二分类的梯度来自 BCE 损失（每样本都有梯度），且能消掉 7 头共享主干下的极端不平衡（正样本率 4.0%→28.0%）。
**该问题本仓未测**，且**不是零重跑项**（需改 `model.py` 头数 + `dataset.py` 标签聚合 + 评估）。
若将来要测，须新开臂并遵守 §25 的目录守卫。

**连带更正的表述**：`report_conclusions.md` §9.5 原把"标注/采集成本"写成二分类的劣势（"改二分类不省成本"）。
**这是错的**——二分类标签 = `any(targets)`，**一行派生、零标注**（`alldata(readonly)/contract_labels.json`
的 7 维 `targets`；`MVD-HG-dataset/{类}_contract/contract_labels.json` 每类本就是标量 0/1）。
**该维度对两边都是 0，既不支持也不反对二分类。** 二分类在数据侧的真实优势只有一条：
正样本率 4.0% → 28.0%，消掉 oracle 上限问题（且已由 L3 免费拿到）。

---

## 31. 单头二分类实验臂（`--head binary`，2026-09-17）

**背景**：§30.5 裁定「合约级二分类是**报告口径**，不是训练口径」，但明确留了口子——
那份证据只覆盖**度量/判据**，**不覆盖"训一个二分类模型"**：

> 该问题**本仓未测**，且**不是零重跑项**（需改 `model.py` 头数 + `dataset.py` 标签聚合 + 评估）。
> **若将来要测，须新开臂并遵守 §25 的目录守卫。**

用户裁定补这个臂。它回答：**专门为「有没有漏洞」训练的模型，是否强于七类模型塌成 `any()` 的视图？**

### 31.1 头号约束：`[N,1]` 会**原样复现** §28 的 bug（实测）

```
type_of_target([[1],[0],...])       = 'binary'    ← 不是 multilabel-indicator
metrics.micro_f1(y[N,1], 全判负)    = 0.5         ← 真值应为 0.0（= accuracy）
metrics.micro_f1(y[N,7], 全判负)    = 0.0   ✓
```

已确认会踩雷的既有代码：`metrics` 的 `micro_f1` / `macro_f1` / `per_class_prf` /
`mean_average_precision`（`IndexError`）/ `subset_accuracy` / `search_global_threshold`
（后者会挑中 **accuracy 的 argmax**）、`paired_study_analysis.py:88-90`（直接
`f1_score(average="micro")`）、`aggregate_results.py` 的逐类表、`diagnose.py` 的逐类循环。

**对策（两道）**：

1. **多标签入口一律经 `_as_2d_multilabel()`**：`shape[1] < 2` 直接 `ValueError`，消息指向二分类 API。
   把**静默错算**换成**响亮报错**（§28.7 教训 5）。反向亦然：`_as_1d_binary()` 拒绝多列输入。
2. **二分类指标一律由混淆计数直接算**（`metrics.binary_counts` → `binary_prf`），
   **完全不经 sklearn 的 `average=` 分派**——从根上绕开该陷阱，而不是"绕对参数"。

**单一事实来源**：`error_rates.contract_level_rates` 的二分类四项**改为委托** `metrics.binary_prf`。
原先两处各算一遍"二分类 F1"，在退化约定上（`None` vs `0.0`）必然分叉——正是 §28 那类静默分歧。

### 31.2 设计：唯一变量 = 输出空间

| 维度 | 决定 |
|---|---|
| 规模 | **n=9 同配对**（train_seed 3/4/5 × split_seed 0/1/2），满足 §26.7/§27.5 |
| 唯一变量 | 头 7→1 + 标签 `any(targets)` + 损失单类 BCE + 控制流判据 |
| 语料 | ① 主库 + ② 增强集 |
| 控制流判据 | **val 二分类 AP**（阈值无关），非 val 二分类 F1 |

**「只换输出头」是逐位成立的，不是声明**（`tests/test_binary_arm.py` 机检）：
同 `torch.manual_seed` 下 `SSMHG(num_classes=7)` 与 `(num_classes=1)` 的
**12/12 共享张量逐位相同**（`cls` 最后创建、不影响初始化消耗），同一输入下 `a`（节点可疑度）
也逐位相同——**唯一差异是 `cls.2`（7 行 vs 1 行）**。

**先验侧零改动**：`s_v` 进入模型时就是 `(N,1)` **标量**（M1 的 7 类 `node_flags` 在 M3 前已丢弃），
`NodeFuser` 与 `L_var` 均与类别数无关。

**标签塌缩只发生在一处**：`dataset.stack_labels(samples, head)`。`build_index` / 标签文件 /
`split_seed*.json` / 通道哈希 / `_cb.pt` **全部保持 7 维不动** → 不碰任何已入库中间产物。

**判据为什么用 AP 而非 F1**：§9.6.1 已实测合约级 F1 被常量预测器刷到 0.62/0.93
（真实模型 0.723/0.990，**可提升空间只剩 0.10/0.06**）；用它做早停会让判据近乎平台化。
AP 阈值无关、动态范围大得多。**两列都记进 `log.txt`**（`val_binary_ap` 与 `val_binary_f1`），
以便事后审计「AP-argmax 与 F1-argmax 是否同一个 epoch」。

### 31.3 🔴 连带修掉一个 `run_guard` 的**静默覆盖洞**（本次最重要的一处基础设施修复）

`diff_args` 只比对**双方都有**的键（`run_guard.py` 原 docstring 的理由是"否则用新代码复跑旧实验会被全部误拒"）。
这对复跑是必需的，但**反方向没有防护**：

> `train.py --head binary --out-dir runs/prior_dropout_study/drop20_ts3_ss0`
> → 老自述无 `head` 键 → 差异为 **0** → `run_dir_conflict` 返回 None → **不加 `--overwrite` 也会覆盖掉
> 七类配对基线**。

这与 §28 那次「`run_guard` 拦不住，因为修复不改任何 CLI 参数」是**同一类失效**：守卫看不见新键。

**修法**：新增 `run_guard.IDENTITY_DEFAULTS`（当前仅 `{"head": "multi"}`），`diff_args` 在比对前
**先按默认值给缺失的一侧补齐**。三个后果都是想要的：
1. 新参数写进旧目录 → **报冲突**（洞补上）；
2. 复跑旧实验（新代码 + 默认值）→ **仍放行**（不误伤，`test_identity_default_still_allows_replaying_old_experiment`）；
3. `run_ablation.verify_single_variable` 对新键**不再误判"未生效"**（否则新臂的单变量断言会假失败）。

⚠ **登记义务**：将来任何"进入实验身份"的新 CLI 键**必须登记进 `IDENTITY_DEFAULTS`**，
否则同一漏洞会为新键重现。已加漂移守卫测试断言表内每个键都是 `train.py` 真实存在的开关。

### 31.4 臂布局与驱动

| 语料 | 臂 | 目录 |
|---|---|---|
| ① | 七类基线（重训取 test） | `runs/binary_arm/main_base/base_ts{T}_ss{S}/seed{T}/` |
| ① | 二分类 | `runs/binary_arm/main_bin/bin_ts{T}_ss{S}/seed{T}/` |
| ② | 七类基线 | `runs/binary_arm/aug_base/base_ts{T}_ss{S}/seed{T}/` |
| ② | 二分类 | `runs/binary_arm/aug_bin/bin_ts{T}_ss{S}/seed{T}/` |

**① 的基线为什么也要重训**：归档的 `runs/prior_dropout_study/drop20_ts*_ss*` 当初剪了权重，
**没有 `best.pt`、没有 `results.json`** → 不重训就**只能比 val**（§7.5 的边界）。重训 9 个 run ≈5 min，
换来 **test 上的 n=9 配对**。② 则既无基线也无 ts3/4/5，须一并新跑。

**驱动 = 新增 `scripts/run_study.py`**（不是扩展 `run_ablation.py`）：后者的身份是"3 种子消融矩阵
vs `runs/seed0`"，`split_seed` 绑死等于 `seed`，改它会危及既有 12 项消融。
新脚本**只 import 不复刻** `run_ablation` 的 `verify_single_variable` / `argv_for_train` / `argv_for_eval`。
它另加一条**同语料断言**：一对的两臂 `graph_dir` / `split_dir` / `label_file` / `label_key_mode`
必须逐字相同——跨语料就不叫"一对"（§29.4 的标签源缺口即此类静默失效）。

**实测单变量性**：`bin` vs 同配对 `base` 的 `diff_args` 恰为 `["head", "out_dir"]`（`out_dir` 属记账键）。

### 31.5 分析层与守卫（lockstep）

- `paired_study_analysis.py` 加 `--task` 无关的二分类族指标（`val_binary_ap` / `val_binary_f1@*` /
  `val_binary_fpr@val_thr` / `val_binary_fnr@val_thr` / `val_pos_rate`），**两条臂都算**。
  合法性来自恒等式 **`max_c p_c >= t ⇔ any_c(p_c >= t)`**（`metrics.contract_any_scores`，已机检）：
  两条臂在**同一阈值、同一规则**下可比，Δ 只归因于输出头。多标签族对二分类臂记 `None` → 打 `—`。
- `evaluate.py` 的 `compute_binary_report` **刻意不复用 `micro_f1` 键名**（键名一律 `binary_*`）：
  这样读 `test.fixed_0.5.micro_f1` 的下游在二分类臂上拿到 `KeyError`（响亮），
  而不是那个"单列下等于 accuracy"的假 micro-F1。`summarize` 遇混合 head 直接报错。
- `evaluate.py` 头宽**从 checkpoint 回读**并与 `cls.2.weight` 行数**交叉校验**——把"checkpoint 与 config
  不同源"变成一句可诊断的报错，而不是 `load_state_dict` 的尺寸 traceback。
- `diagnose.py` 按 `labels.shape[1]` 迭代、类名按 head 取；`val_thr` 增加 `thresholds.json` 回退
  （原先硬依赖 `results.json`，即硬依赖 evaluate 的执行顺序）。
- `error_rates.py` / `aggregate_results.py` 的逐类循环改为**列宽自适应**，并对二分类臂**明确跳过**
  （不静默产空表）。

### 31.6 测试

`tests/test_metrics.py` **+10 例**（全判负必须 F1=0 且 ≠ accuracy；多标签入口拒绝单列；
二分类函数拒绝多列；与 sklearn binary 口径逐位相等；常量分数 AP=正样本率；单类时 AP=None；
`max ⇔ any∘阈值` 等价性；`head_*` 助手拒绝未知取值）。
`tests/test_run_guard.py` **+4 例**（IDENTITY_DEFAULTS 三种情形 + 漂移守卫）。
新增 `tests/test_binary_arm.py`（6 例：12/12 张量逐位相同、主干输出相同、标签塌缩唯一入口、
C=1 的 `class_stats`/损失、端到端产物自洽且**不含多标签键**）。
`pytest tests/` **191 passed + 2 skipped**（本次之前 171）。

### 31.7 边界（不得越界引用）

1. **本臂回答的是"专门为二分类训练的模型是否更强"**，不是"把七类臂的头换成 1 维会怎样"。
   两条臂的**控制流判据不同**（AP vs 标签对 micro-F1）——这是**每个输出空间各用最合适的判据**，
   不是严格的"唯一变量镜像"。若要分离"输出头"与"判据"两个因素，须再加一个 `bin_f1` 配置。
2. **n=9 判方向**；本臂**不产出** 3 种子正典格式。
3. **不得**用本臂的 test 数字回头调参/调阈值。
4. `--head` 默认 `multi`，正典臂逐字节不变（`tests/test_binary_arm.py` 与 `run_study` 预检双重保障）。

### 31.8 实验结果（2026-09-17；n=9 同配对，`report_conclusions.md` §9.6.5）

**先说结论**：**二分类模型确实略强，但只强在"排序"这一环，且主库 test 上不足以判定。**

| 语料 | 指标 | 七类塌缩 | 二分类臂 | Δ（val / test） | t（val / test） |
|---|---|---|---|---|---|
| ① 主库 | **AP**（阈值无关） | 0.9237 / 0.8564 | **0.9572 / 0.8898** | **+0.0335 / +0.0334** | **+2.99 ★** / +1.18 |
| ① 主库 | F1 @0.5 | 0.8207 / 0.8017 | 0.8188 / 0.7923 | −0.0019 / −0.0094 | −0.07 / −0.42 |
| ① 主库 | F1 @val_thr | 0.8028 / 0.7353 | 0.8264 / 0.7807 | +0.0236 / +0.0453 | +0.74 / +1.42 |
| ① 主库 | FNR @val_thr | 0.2926 / 0.2926 | 0.1955 | −0.0971 | −1.65 |
| ② 增强集 | AP | 0.9980 / 0.9992 | 1.0000 / 0.9999 | +0.0020 / +0.0007 | **+3.09 ★ / +4.71 ★** |
| ② 增强集 | F1 @val_thr | 0.9813 / 0.9854 | 0.9989 / **0.9961** | +0.0176 / +0.0107 | **+4.75 ★ / +3.06 ★** |
| ② 增强集 | FNR @val_thr | 0.0231 | **0.0043** | −0.0188 | **−3.70 ★** |

证据本体：`experiments/binary_{main,aug}_paired.json`（val，`paired_study_analysis.py` 产出）；
test 由两侧 `test_probs.pt` 用同一口径（`contract_any_scores` + `binary_prf`）同配对重算。

**三条裁定**

1. **§30.5 的开口已闭合，但结论不是"二分类更好"**：二分类头改善的是**排序质量**
   （AP 四个点估计全部同向为正），**不是判决质量**（① 的 F1 在两个工作点、val 与 test 上全部无差异）。
   → **维持 §9.5 的裁定：不改主任务为二分类**；把本臂作为"输出空间消融"的证据写入论文。
2. **§9.6.1–9.6.3 与本节不矛盾**：前者否定的是"拿合约级二分类当**判据**"（常量解刷分、平台宽 1.7 倍），
   后者肯定的是"专门训的单头**模型**在排序上略优"。**两者不可互相引用**——判据仍不改，模型略优但不换主任务。
3. **② 的显著性要打折**：建立在 `AP 0.998 → 1.000` 的空间上，是"几乎完美者更接近完美"，
   不是"困难语料上更强"。② 的天花板效应事前已预告。

**provenance 两处须记**：
- `runs/binary_arm/` 36 个 run，wall 2665.5 s，0 失败；`micro_f1` 由 `--evaluate-only` 二次补齐
  （新增上报指标属评估层口径变更，零重训；二分类臂的 `micro_f1` 与 `binary_f1` 恒等，已逐 run 校验）。
- **自匹配陷阱**：`pgrep -f "run_study.py --keep-going"` 会匹配到等待脚本**自己的命令行**，
  使"等待进程退出"的循环永不结束。判进程是否存在应用更精确的模式（如 `pgrep -f "python scripts/run_study.py"`）。

---

## 32. 消融 5.4.2 两项取值裁定 + `num_bases` 计划建议的**实现性修正**（2026-09-18）

**背景**：`ablation_plan.md` §3.1 把 `num_bases` 与 `drop_edge_prob` 列为"取值待定、不替使用者拍板"。
用户裁定：**采用计划 §3.1 的建议值**。执行中发现计划对 `num_bases` 的建议**在实现上不可行**。

### 32.1 裁定与实际取值

| 项 | 计划候选 | 计划建议 | **实际执行** |
|---|---|---|---|
| `drop_edge_prob` | 0.1 / 0.2 / 0.5 | 0.2 | **0.2** ✅ 按建议 |
| `num_bases` | 1 / 3 / 10 | 1 与 10（两端各一） | **1、3、4**（见 §32.2） |

### 32.2 🔴 `num_bases` 的"取 10"不可行，且"两端各一"的设计本身塌了

计划的理由是「`10` > 关系数 5，检验过参数化是否有害」。**实测直接报错**：

```
ValueError: num_bases must be in [1, 5], got 10
```

根因（`model.py:332`）：`1 <= num_bases <= num_relations`（=5）。
`num_bases` 是 PyG `RGCNConv` 基分解的**基矩阵个数**，**基数的上界就是关系数**，取更大值无语义。

**第二层后果更值得记**：合法区间 `[1, 5]` 的**上端 5 恰好就是基线**
（`model.py:19`：「num_bases 默认 = num_relations(=5)」）→
**"两端各一"这个设计在合法区间内没有上端可用**，做了等于没做。
计划写这条时没有核对模型的参数约束，属"纸面设计未过实现核对"。

**处置**：在合法非默认区间 `{1,2,3,4}` 内取两端 **1 与 4**
（`model.py:19` 自己点名「num_bases=4 仅作消融」），并补上计划候选里的 **3**，
凑成 **1/3/4 vs 默认 5** 的**剂量-反应**——比原计划的两点设计信息量更大，且全部合法。

**执行痕迹**：`numbases10/seed{0,1,2}` 三个 run 训练失败（退出码 1）、只留空目录（已删）；
失败记录留在 `runs/ablation_round2.log`。矩阵里该项已替换并附注释说明约束。

### 32.3 描述性读数（**n=3，不是结论**）

参数量 `284,114(1) < 349,670(3) < 382,448(4) < 415,226(默认 5)`，而 test mAP 为
`0.3134 → 0.3301 → 0.3417 → 0.3047`：**三个非默认点单调上升，默认值 5 反而最低**。
⚠ 这些臂的 mAP std（±0.021–0.063）是正典（±0.0119）的 2–5 倍，且 n=3 判不了方向
（§26.7/§27.5）→ **记为"值得做同配对 ≥9 点验证"的线索，不当作结论**。
另：`num_bases` 是**容量类**消融（改基矩阵个数 → 参数量变），
与 `hid256` 同理，报告时必须随附 `parameter_report`，否则无法区分"该组件重要"与"模型变小了"。

### 32.4 规范（本次新增）

**凡在计划里写"取某值做消融"，必须先在代码里核对该参数的合法域与默认值**——
本次两条都属于"纸面看起来合理、实现上要么非法、要么等于没做"：
`num_bases=10` 越界，而合法上端等于基线。**取值待定的项应在开跑前先跑一次最小样验证可取。**

---

## 33. `_cb.pt` 存储膨胀 39 倍：CPU 路径的视图被整块序列化（2026-09-18）

### 33.1 现象与根因

盘点「未跑 4 项」时实测到 `_cb.pt` 的文件体积与内容严重不符：

```text
单图 asd_0x000c1000…__…：
  文件 100.19 MB
  func 通道 188 条：有效数据 0.58 MB，实际序列化 storage 39.28 MB
  node 通道 673 条：有效数据 2.07 MB，实际序列化 storage 105.15 MB
  样例张量 shape=(768,) numel=768，而 untyped_storage() = 224256 元素（= 292×768）
```

**根因**：`m3_build_features.encode()` 返回
`model(**ids).last_hidden_state[:, 0, :].cpu()[0]`。
该切片形状是 `[1, 768]`，但 **`.cpu()` 在输入已是 CPU 时是 no-op**，不产生拷贝——
于是 `out[0]` 是 `[1, seq_len, 768]` 隐藏态的一个**视图**，视图把它背后的**整块 storage**
一起交给 `torch.save`。每条目本应恰好 `768×4 = 3 KB`，实际按 `seq_len × 3 KB` 落盘。

**实测膨胀倍率**（桩模型复现，`tests/test_m3_cb_cache.py`）：

| 路径 | storage | 结果 |
| --- | --- | --- |
| CPU（`--device cpu`，**默认**） | 128×768 / 512×768 | **膨胀 ×128 / ×512** |
| CUDA（`--device cuda`） | 768 | 紧凑（`.cpu()` 是真拷贝） |

⇒ **只有 CPU 构建的缓存中招**。这解释了一个此前没被注意到的现象：
主库 `_cb.pt`（2026-09-12，CPU 构建）**14.61 GB**，而增强集 `_cb.pt`
（2026-09-15/16，`--device cuda --force` 重建）1774 图合计仅 1.28 GB 且**逐条已紧凑**。

### 33.2 处置：修代码 + 紧凑化存量（**只动主库**）

1. `encode()` 末尾改为 `return out[0].clone()`——**值逐位不变**，只是不再携带视图的 storage。
2. 新增 `scripts/recompact_cb_cache.py`：逐图 `load → 逐条 clone → 存临时文件 → 重载逐位比对 →
   `os.replace` 原子替换`。**先验证再替换**，任一环节不符即保留原文件、不改动。
3. **不处理增强集**：实测抽样 60 图、膨胀条目 0——它本就是紧凑的，动它没有任何收益。

**执行结果（2026-09-18）**：

| | 前 | 后 |
| --- | --- | --- |
| `products/alldata/graphs/*_cb.pt` | 15.586 GB | **0.403 GB**（×39） |
| `products/` 合计 | 20 GB | **4.5 GB** |
| 耗时 | — | 21.5 s（590/590 成功，失败 0） |

### 33.3 值中性的三重验证（`_cb.pt` 是已报告结果的输入，必须证明没动数值）

1. **逐文件**：脚本在 `os.replace` 前重载临时文件，断言键集合相等、**每条 `torch.equal`**。
2. **逐图全库**：用 `dataset.load_graph(..., verify_channels="all")` 复核全部 **590/590** 通过——
   它比对的是 `_feat.pt::meta::cb_sha256` 里**当初记录的哈希**，即"新文件反解出的通道矩阵"
   与"产出它时记录的值"逐位一致。这是独立于脚本自身断言的第二来源。
3. **端到端复算**：`evaluate.py --seed 0` 在紧凑化后重跑，得
   `micro@0.5 = 0.4262295082`、`@thr = 0.4166666667`、`mAP = 0.3008386684`——
   与紧凑化前记录在 `runs/seed0/results.json` 的值**逐位相同**。

`pytest tests/` **201 passed + 2 skipped**（新增 `tests/test_m3_cb_cache.py` 8 例）。

### 33.4 为什么它决定第 17 项（微调 CodeBERT）的可行性

微调编码器必须为每个划分种子另产一套 `_cb.pt`。不修则每种子 14.6 GB、三种子 44 GB——
**远超 C 盘 ≥30 GB 的硬规则**；修后每种子 0.38 GB、三种子约 1.1 GB。故本修复是第 17 项的**前置**。

### 33.5 教训

1. **「不报错的错」的第四例**：本次与 §28（`.ravel()`）、§29.4（`diagnose.py` 标签源）、
   §31.3（`run_guard` 漏新键）同类——**不抛异常、不改变任何数值、只吃磁盘**，
   靠"跑一遍看结果"永远发现不了，只能靠**不变量**：新增回归锁
   **「每条缓存向量的 `untyped_storage().nbytes()` 必须恰等于 `numel()*4`」**。
2. **同一份代码在 CPU 与 CUDA 上产出的文件不应有 39 倍的体积差**——
   `.cpu()` 是不是 no-op 取决于输入设备，这类"随运行设备漂移的产物"应在验收里显式核对体积。
3. **修了缺陷不等于要重跑**：本次是**纯存储格式**变化，用"逐位比对 + 已记录哈希 + 端到端复算"
   三重证明后，全部已报告结果**继续有效**，无需任何重训。判据是**产物字节变了、产物语义没变**。

---

## §34 补齐 4 项消融：代码改动与变体验收（2026-09-18）

`ablation_plan.md` §6 设计的 4 项（CALLBACK_RISK 上限 / REV / RGCN 层数 / 微调 CodeBERT）
在本日完成开发并开跑。本节记**代码与数据侧的改动和机器验收**；指标结果另记
`experiments/ablation_results.md` 与 `eval_results/ablation/collected*.md`。

### 34.1 代码改动（全部最小化，正典路径逐字节不变）

| 文件 | 改动 | 为什么必须这样改 |
| --- | --- | --- |
| `model.py` | `SSMHG(num_layers=2)`；逐层 `setattr(self,"conv{l}",…)` | **不能用 `nn.ModuleList`**：它把键名改成 `convs.0.*`，已有 `best.pt` 全部加载失败。`forward` 改为按层循环，保持旧序 `relu → (非末层) dropout`；`h1`=首层、`h2`=**末层**（Readout 用它），L=1 时二者同一张量 |
| `train.py` | `--layers {1,2,3}`（默认 2）；`num_relations_of(meta)` 从图产物回读；`derived["num_layers"]`；`_load_split_samples` 增 `num_relations` 跨图一致性断言 | 关系数是**模型宽度**的一部分（RGCN 的 `comp` 是 `[num_relations, num_bases]`），写死常量会让 REV 变体静默少一组基 |
| `evaluate.py` | `num_relations`/`num_layers` 一律从 `derived` 回读 | 与 `--head` 同一条教训（§31）：**不能读模块常量**，否则变体的 `load_state_dict` 尺寸不匹配 |
| `run_guard.py` | `IDENTITY_DEFAULTS` 增 `"layers": 2`；新增 `nonempty_out_dir()` | 不登记则「用新键写进旧目录」差异为 0、守卫放行、**无声覆盖**（§31.3 那个洞） |
| `dataset.py` | `sample_meta["num_relations"]`；另立 `RELATION_NAMES_EXT`（**仅显示用**） | `RELATION_NAMES` 必须**恒为 5**——`audit_data_funnel.py:382` 有 `assert len(...)==5`，它审计的是正典语料 |
| `build_cfg_centered_hetero_graph.py` | `--callback-rev`、`--overwrite` + **输出目录守卫**、`reverse_callback_edges()` | 原先**没有任何覆盖检查**而默认 `--out-dir` 就是正典语料目录（§6.5 的缺口） |
| `convert_hetero_json_to_pyg.py` | `RELATION_IDS` 增 `CALLBACK_RISK_REV: 5`；`num_relations_of(edges)` 按**实际出现的键**算 | 按常量表最大编号算会把**正典**也写成 6 ⇒ RGCN 多一组永远收不到消息的基（不报错） |
| `finetune_codebert.py`（新） | 阶段 1 微调编码器；`build_graph_variant.py`（新）造 3 类变体；`collect_ablation_results.py`（新）汇总；`run_remaining_ablations.sh`（新）串行队列 | 见 §34.3 |

### 34.2 M2 守卫（§6.5 缺口的处置）

`build_cfg_centered_hetero_graph.py` 的默认 `--out-dir` 是 `products/alldata/graphs`，
而它**没有任何覆盖检查**：不传 `--out-dir` 地跑一次变体参数，就会逐个改写 590 个正典
`_hetero.json`，而下游 `_m1/_pyg/_feat` **全部不同步且不报错**。

处置 = `run_guard.nonempty_out_dir()`：目标目录已有 `*_hetero.json` 时要求 `--overwrite`。
判据比 `train/make_splits/m3` 三处**更严**（那三处比的是自述文件：参数相同即放行）——
因为 M2 的产物**没有自述文件**可逐项对比，"参数相同"根本不能说明写进去的是同一套实验。
端到端验证：对正典目录直接跑 → 拒绝退出且原文件未被改动（`tests/test_m2_guard_and_rev.py`）。

### 34.3 三个变体的机器验收（**假设 → 事实**）

设计里的关键论据都是"读代码得到的假设"，故一律**算一遍再比对**，把它换成事实：

| 变体 | 断言 | 实测 |
| --- | --- | --- |
| `callback_rev` | `_feat.pt` 与正典**逐位相同**（证明 M1 确实看不见 REV） | **590/590 相同** ✓ |
| `callback_rev` | REV 边集 = CALLBACK_RISK 的**精确镜像**，逐图成立 | **590/590 成立**，总边 **514 == 514** ✓ |
| `callback_unlimited` | `_feat.pt` **至少有图变化**（否则是空操作） | **20/590 不同** ✓ |
| `callback_unlimited` | CALLBACK_RISK 边数 ≥ 正典，且截断候选 → 0 | 边 **514 → 1166**；截断 **652 → 0** ✓ |
| `cb_ft_ss{S}` | `_feat.pt` 三通道**逐位相同**（证明唯一变量就是 `_cb.pt`） | 单图抽验 struct/type_id/sv **全同** ✓ |
| `cb_ft_ss{S}` | `_cb.pt` **必须不同**（否则编码器没生效） | 单图抽验 **209/209 不同** ✓ |

> 🔴 **一处被实测推翻的先验**：`ablation_plan.md` §6.1 初稿写"影响面有限（仅约 70 个节点被截断），
> 预期该项指标变化很小"。实测被截断的**候选边**达 **652** 条，比实际建出的 514 条**还多**——
> "70 个节点"是节点数，每个被截断节点可有 5 条以上候选。按边计是翻倍量级，**不可预设为小效应**。

> 🔴 **一处写反的判据（本仓第 5 次"不报错的错"的变体）**：`build_graph_variant.py` 第一版对
> `callback_unlimited` 断言"**每一张** `_feat.pt` 都必须与正典不同"，于是一次**正确**的构建
> （570 同 / 20 异）被自己的脚本判为失败并中止。判据**太严**与**太松**一样是缺陷——
> 正确的判据是"至少有一张不同"（证明开关非空操作）+ 独立的边账核对。

### 34.4 「唯一变量」为什么要在**产物层**也成立

`train.py` 的守卫只能看到 `--graph-dir` 换了个路径，**看不到那个目录里装的是什么**——
这正是"看起来是消融、其实不是"能藏身的地方。故：

- 变体目录里凡**不该变**的产物一律**软链**（物理上是同一个文件，不可能是第二个变量）；
- 凡**该变**的都真算一遍，并与正典逐图比对（上表）；
- 每个变体目录写 `variant.json` 自述文件（含命令、复用清单、期望值）。

### 34.5 指标结果与训练消耗（2026-09-18 回填）

结果表由 `scripts/collect_ablation_results.py` **程序复算**（不手抄——本仓的消融计数已写错两次），
两组结果集**各自独立成表、不跨组比较**（§23）。产物 `eval_results/ablation/collected{,_aug}.md`。
**详细分析在 `experiments/ablation_results.md` §9**，此处只记裁定相关的那几条。

**① 主库 4 项读数**（3 种子 mean，同配对 t ↔ `runs/seed{s}`；n=3 描述性）：

| 臂 | Δmicro@0.5 | ΔmAP | 同配对 t(mAP) | 训练成本 |
|---|---|---|---|---|
| `layers1` | −0.1012★ | −0.0028 | −0.04 | 10.7 s（参数 ×0.76 ⚠混淆） |
| `layers3` | −0.0050 | −0.0021 | −0.04 | 18.8 s（参数 ×1.24、**慢 2.1×**） |
| `cb_rev` | −0.0619★ | −0.0588★ | −1.41 | 11.5 s |
| `cb_unlimited` | −0.0406★ | **+0.0338★** | +1.52 | 16.0 s |
| **`cb_ft`** | **+0.2797★** | **+0.4386★** | **+27.60** | GNN 9.6 s **+ 微调 848.5 s** |

**三条裁定**：

1. 🔴 **`cb_ft` 是全部 21 个消融臂里唯一越过 df=2 临界值 `|t|>4.303` 的臂**（其余 20 臂无一越过）。
   效应量 +0.24~+0.44 对噪声 ±0.01~±0.08（**4~37 倍**），且**逐类齐涨 + 三个结构性恒零类全部破零**
   （`dos` 0→0.400 三种子一致、`time_manipulation` 0→0.444、`front_running` 0→0.167）。
   → **建议对 `cb_ft` 做同配对 n≥9 复核**（本仓规范 §26.7/§27.5 的判方向门槛），
   **这是本批唯一值得动用该预算的一项**。⚠ 仍不得写成"已确立的效应"。
   ⚠ 须同时披露：编码器是在**训练标签**上监督微调的（任务特定表征，不是无监督改进），
   且 ② 上该编码器自身 `best_val_macro_f1=0.9854` ≈ 单独解完任务 ⇒ **② 的增益含饱和成分，
   `cb_ft` 的说服力全部来自 ①**。
2. **RGCN 层数 L=2 被数据支持**：L=1 明显不够（且 std ×3–8，是"跑不动"形态）、
   L=3 在噪声内（|t|≤0.21）却付 **参数 ×1.24、每 epoch 慢 2.1 倍**。**本批结论最干净的一项**。
   ⚠ L=1 同时把参数降到 0.76 倍 ⇒ "层数不够"与"模型变小"在本项内**不可分离**（同 §6.3 的容量混淆）。
3. **`cb_unlimited` 的 Δ 不可解读为效应**：该"变量"只在 **20/590**（①）与 **199/1774**（②）张图上成立，
   其余图放开上限**什么都没做** ⇒ Δ 被 ~90% 未受影响的图稀释，**真实效应量在 n=3 下不可测**。
   要判定须**只取受影响子集**分析（**本仓未做，是已知开口**）。论文里**不得**写"该上限不重要"。

**🔴 成本口径（本项与前 16 项的结构性差异之一）**：`cb_ft` **必须两段报**——
只报 GNN 段的 9.6 s 会把本项说成 4 项里**最便宜**的，而真实成本是 **9.6 + 848.5 = 858.1 s/种子**，
微调段占 **98.9%**。`collect_ablation_results.ft_cost_of()` 单列一段并配回归测试钉死语料维度。
⚠ ① 微调段 ss2 的 681 s 比 ss0/ss1（934/931 s）低 27%，三者跑的都是 5 epoch、序列数几乎相同
（8540/8665/8542）⇒ **差异来自 GPU 争用、非算法**，848.5 s 的均值**偏乐观**，单种子应按 ~930 s 计。

**② 增强集**（2026-09-19 02:41 跑完，`fail=0`；见 `ablation_results.md` §9.5、§10.6）：

| 臂 | Δmicro@0.5 | ΔmAP | 同配对 t(mAP) | 成本 |
|---|---|---|---|---|
| `cb_ft` | **+0.0554★** | **+0.0171★** | +6.45（micro t=**+11.97**） | GNN 43.9 s **+ 微调 3,797.3 s** |
| `cb_rev` | +0.0065 | +0.0065★ | **+9.61** ⚠ 天花板伪影 | 114.7 s |
| `layers1` | −0.0033 | +0.0068★ | +1.97 | 188.7 s |
| `cb_unlimited` | −0.0047 | +0.0029 | +1.42 | 127.2 s |
| `layers3` | **−0.0811★** | **−0.0502★** | −2.29 | 127.3 s |

**🔴 本批最重要的新结论：效应方向不跨语料迁移。** 5 项里**只有 `cb_ft` 方向一致**：

- **`layers3` 反向**：① 中性（−0.0050）vs ② **6/6 指标显著负**（三个种子全部低于正典）。
- **`cb_rev` 反向**：① 显著更差（ΔmAP −0.0588★）vs ② 略好（+0.0065★）。
- **`layers1` 不对称**：① 明显崩（−0.1012★）vs ② 无效应（−0.0033）。
- **`cb_unlimited` 不可比**：① 自身反号、② 全在噪声内（且**稀释问题同样存在**，变量只落在 199/1774=11.2% 图上）。

→ **不是两组互相矛盾，是同一干预在两个工作点上的正常表现**（①「信息饥饿」`micro@0.5` 0.4256；
②「接近饱和」0.9347 / `mAP` 0.9804）。**论文里只能写成「效应方向依赖语料所处的工作点」**，
**不得**写成"某组结论被另一组推翻"，**更不得**用 ② 宣传 ① 的问题已解决（§23）。

⚠ **两条必须随行披露的口径**：
1. **`cb_ft` 在 ② 上的说服力必须打折**：增益空间只有 0.9347→0.9901，而**编码器自己就训到
   `best_val_macro_f1` 0.9854/0.9938/0.9911** ⇒ 很大一部分是"编码器已经会了"。
   **本项的说服力全部来自 ①**。
2. 🔴 **`cb_rev` 的 t(mAP)=+9.61 是天花板伪影**：Δ 只有 **+0.0065（6.5‰）**，
   仅因正典 std 极小（±0.0041）而拿到高 t。**只看 t 会得出"加镜像边很有效"的荒谬结论**
   —— 本文所有「大 t + 小 Δ」组合一律按天花板伪影处理（§31.8 同类）。

⚠ 跨组**禁止**比较绝对值（§23）；本节表只为并列呈现，**两组的数字各自独立**。

---

## §35 开跑前掐掉的两个**静默错误**（2026-09-18，第三次同类教训）

两项都在"产物齐全、断言全过、不报任何错"的形态下产出**错误结论**。它们的共同点不是
"代码写错"，而是**判据选错**：用了一个"看起来等价、其实更弱"的信号当完成/匹配的依据。
§28（`.ravel()` 让 micro-F1 恒等于 accuracy）、§29.4（`diagnose.py` 标签源）之后的第三、四例。

### 35.1 续跑判据用 `best.pt`：被腰斩的 run 会被当成"已完成"

**现场**：`wsl --shutdown` 腰斩了 `runs/ablation_aug/layers3/seed2`，留下
`best.pt` / `last.pt` / `thresholds.json` / `val_best_probs.pt`，**没有** `config.json` / `results.json`。

**根因**：`run_ablation.py` 的跳过判据是 `best.pt 已存在`。但 `best.pt` 是**训练中途**落盘的
（每 epoch 刷新），而 `config.json` 由 `train.py` 在**训练全部结束后**才写（`train.py:624`）。
两者不同步 ⇒ 中断的 run 被当成完成。

**后果（为什么是静默）**：该 run 被永久跳过 ⇒ `results.json` 永远补不上 ⇒ `--summarize`
只聚合到剩下的种子 ⇒ 产出 **n=2 的均值**，却挂在"3 种子消融"名下。
`summary.json` 的 `n` 字段会显形，但没人会去逐项核对 n。

**处置**：判据收敛为三态显式函数 `run_ablation.resume_state()`，**以最后一步的产物为准**：

| 状态 | 判据 | 动作 |
| --- | --- | --- |
| `"done"` | `results.json` 在 | 整项跳过 |
| `"eval"` | `config.json` 在、`results.json` 不在 | **只补 evaluate**（不重训，省一次 GPU） |
| `"train"` | 其余（含目录不存在） | 训练 + evaluate 全跑 |

`run_study.py:192` 原先用 `config.json` 判完成——**同一 bug 类的较轻版本**（训练完成后
evaluate/diagnose 失败则该 run 永远跳过），已改为复用同一函数，避免两份判据漂移。
回归锁 `tests/test_resume_state.py`（6 例），其中一例直接断言"跳过分支所在代码里不得再出现 `best.pt`"。

**活体实例（2026-09-18 事后验收时抓到）**：对新增各臂的 `config.json` 做产出后再核
（`ablation_results.md` 验收第 1 条），② 那一组读出：

```
② layers3   seed0: ['layers'] | seed1: ['layers'] | seed2: 缺 config.json
```

`runs/ablation_aug/layers3/seed2/` 里是 `best.pt` / `last.pt` / `thresholds.json` /
`val_best_probs.pt` **四件齐、独缺 `config.json`** ——正是被判据误判的现场。
新判据读出 `resume_state = "train"`（seed0/seed1 均为 `"done"`），即它会被**正确补跑**。
⚠ 补跑**不在 `run_remaining_ablations.sh` 的步骤表里**（该项当时是用 `--only layers1,layers3`
单独跑的），故必须手工补：

```bash
python scripts/run_ablation.py --only layers3 --keep-going \
    --base-config runs/augmentation/seed0/config.json --root runs/ablation_aug
```

**这个实例值得单独记一笔**：判据缺陷不是"理论上可能漏种子"，而是本仓**已经真的漏了一个**。
若不修，② 的 `layers3` 会以 **n=2 的均值**混进最终结果表，而 `summary.json` 里那个
`"n": 2` 没有任何机制强制人看到。

### 35.2 🔴 编码器路径无语料维度：② 会静默复用 ① 微调出的编码器

**根因**：`finetune_codebert.py` 与 `build_graph_variant.py` 的编码器路径都是
`runs/codebert_ft/ss{S}/encoder`，**没有语料维度**；而队列是**先 `main` 后 `aug`**。

**失效链（全程不报错）**：
1. `main` 跑完，`runs/codebert_ft/ss{0,1,2}/encoder` 是**用 ① 主库微调**的编码器；
2. `aug` 的 `finetune` 步骤看到 `encoder/config.json` 在 ⇒ **跳过微调**；
3. `build_cb_ft` 拿**①的编码器**去重编码**②增强集**；
4. 各项验收**全部通过**——`assert_feat_identical`（结构三通道逐位不变）过、
   "反向抽样 40 图 `_cb.pt` 必须与原版不同"也过（确实不同，因为是另一个编码器）；
5. 产出的是一个**答非所问**的消融：它测的是"跨语料迁移编码器"，而不是"微调 CodeBERT"。

**处置**（两道，缺一不可）：
- **路径按语料隔离**：`runs/codebert_ft/<语料>/ss{S}/encoder`，由 `--graph-dir` 派生
  （`corpus_tag()` = `products/<语料>/graphs` 的父目录名）。写入侧
  `finetune_codebert.default_out_root()` 与读取侧 `build_graph_variant.default_encoder_dir()`
  **同源**，并有测试断言两者落点一致。
- **边车 + 硬校验**：微调时在 `encoder/corpus.json` 写 `{corpus, graph_dir, split_dir,
  label_file, label_key_mode, split_seed}`；`build_cb_ft` 读它并**硬失败**（`SystemExit`），
  缺边车也硬失败（不允许"先跑起来再说"、不允许手工补边车）。

回归锁 `tests/test_finetune_codebert.py` 新增 6 例：tag 派生、绝对路径同 tag、
**两个语料的默认编码器目录不得相同**、缺边车硬失败、**跨语料硬失败**、
队列脚本的跳过判据必须指向语料专属路径。

### 35.4 冻结 IR 字典：② 的目录里根本没有它（同类的第三处）

**发现**：`build_graph_variant.py` 的三处 M3 调用原先都传 `<语料>/graphs/ir_cat.json`。而
**`products/augmentation/graphs/ir_cat.json` 不存在**（实测 `find products -name ir_cat.json` 只有 ① 那一份）。

**为什么它没炸过**：`m3_build_features.py` 在 `--categories` 指向不存在的文件时**只打一行 WARNING**，
然后 `scan_categories(in_dir)` 回退全库扫描、`write_categories(out_dir)` 就地落盘——
于是 ② 的三个变体本会各自在被扫描的变体目录里落一份**重扫出来的** `ir_cat.json`。

**为什么这仍然要改（而不是"反正等价"）**：
- **② 的正典当初用的是 ① 的冻结字典**——证据是双向的：② 的 `graphs/` 里没有 `ir_cat.json`
  （若走就地扫描，`write_categories` 必然落盘），且 ② 的 `m3_gpu.log` 里**没有**那句 WARNING。
- 2026-09-18 实测：用 ② 自己的 1774 张图重扫，`ir_categories` 与 `call_modes` 与 ① 的锚点
  **逐项相同**，扫描节点数 **463264** 亦与 AGENTS.md 记载相符 ⇒ **两者数值等价**。
- 但"恰好等价"**不能当作依赖**：它依赖 ② 的图集不变、`truncate_categories` 的截断规则不变、
  频次序不变。变体的**单变量性**建立在这本字典上，必须显式固定它。
- 附带收益：少落一个多余文件、少一句 WARNING（WARNING 多了就会被无视，这正是"静默"的温床）。

**处置**：新增模块常量 `FROZEN_IR_CAT = products/alldata/graphs/ir_cat.json` 与
`frozen_categories()`（**带存在性硬校验**——缺了就 `SystemExit`，绝不让 m3 静默重扫），
三处调用全部改传它。① 的两个已建变体**不受影响**（① 的路本就是这份锚点），**无需重建**。
回归锁 `tests/test_m2_guard_and_rev.py` 新增 3 例。

**顺带更正 AGENTS.md 的一处不精确**：最小复现集写的是 `products/**/graphs/ir_cat.json`，
但实际**只有 ① 有**，且②的正典本就用①的。这符合"**冻结 IR 类别字典 = 跨语料语义锚点**"
（锚点只有一份）的原意，故**不补建 ② 的那份**（补建只会制造两个可能漂移的来源）。

### 35.3 通则（比两个具体修复更重要）

1. **完成判据必须是"最后一步的产物"**。中间产物（`best.pt`、中间 checkpoint、缓存文件）
   在时间轴上**早于**流程结束，用它判完成 = 把"跑到一半"读成"跑完了"。
2. **任何"跨实例复用"的路径都必须带实例维度**（语料/划分/模型），并且**由产物自述归属**
   （边车文件），下游**断言**它而不是相信约定。约定不会被机器检查，边车会被。
3. **`pgrep -f` 等待循环不得搜索会出现在自己命令行里的字符串**。本仓 §31 已记录该陷阱的
   **一个实例**（`run_study.py --keep-going`），但那条补救（换一个更具体的 pattern）只是
   针对那个实例、不是通则——本次等待 `run_remaining_ablations.sh main` 时**再次踩中**，
   因为脚本末尾还要跑 `... aug`，两个字符串都在自己命令行里。
   **通则：改为按 PID 等待**（`while kill -0 <pid>; do sleep N; done`），从根上消除自匹配。

### 35.5 同类第 4 例：汇总脚本**整臂静默消失**（2026-09-18，生成 ② 表时发现）

**现象**：`collect_ablation_results.py` 的 `arm_metrics()` 在**任一种子**缺 `results.json` 时
返回 `None`，而调用方是 `if m:` ——**直接跳过、不打印、不记账**。于是那一臂
**从汇总表里整臂消失**，表看起来完全正常，读者只会以为「这项没做」。

**触发场景是具体的、且当时就在眼前**：② 的 `layers3/seed2` 被外部打断
（留 `best.pt` 无 `config.json`，即 §35.1 的活体实例）⇒ ② 的表里**会没有 `layers3` 这一整行**。

**还有一层更隐蔽的**：只比对「目录里有什么」的话，**目录都还没建的臂连"丢弃"都不算**——
② 的 `cb_ft` 当时尚未开跑，表里只有 4 臂，而设计上是 5 臂，
**没有任何地方写着"应有 5 臂"**，读表的人**看不出少了哪一臂**。

**处置**（两处，缺一不可）：
1. `collect()` 记账 `dropped_arms`（产物不全）与 `missing_arms`（目录不存在），**两者措辞分开**
   ——对读者的含义不同（"跑坏了" vs "还没跑"）；
2. `GROUPS` 增 **`expect`：应有臂集合**（① 21 臂 = 16 开关 + 5 产物层；② 5 臂，
   **两者不同是设计使然**——前 16 项只在 ① 上跑），并在产物 md 顶部写
   **「本表不完整：应有 N 臂，实有 M 臂」**。

**🔴 为什么必须写进产物本身、不能只 print**：汇总 md 会被单独传阅/引用，
只打印到 stdout 的话**读表的人无从知道少了一臂**。这条与 §35.2 的 `corpus.json` 边车同源：
**让产物自述，不要让下游相信约定**。

回归锁 `tests/test_collect_ablation.py` 新增 4 例（含"无缺失时**不得**凭空报警"——
假警报会让人忽略真警报）。

**与 §35.3 通则的关系**：这**不是**新规则，是通则第 1、2 条在"汇总侧"的又一次现身——
**「产物不全」和「产物不存在」都会被静默读成「结果就是这样」**。

---

## §36 `cb_ft` 的 n=9 同配对复核：效应确认（2026-09-19，待办 B1 完成）

### 36.1 为什么做

`cb_ft`（微调 CodeBERT 后重编码 `_cb.pt`）是阶段 F **21 臂**消融中**唯一越过 df=2 临界值
`|t|>4.303`** 的一项（① Δmicro@0.5 +0.2797、t=+8.09、6/6 指标同向、三个结构性恒零类破零），
也是「瓶颈在输入表征质量、不在图结构」这一结论的**唯一证据来源**。但既有证据只有 **n=3**，
不满足 §26.7/§27.5 的判方向规范 ⇒ 列为本仓待办第 1 项（`ablation_results.md` §12.4）。

### 36.2 设计（驱动 `scripts/run_cbft_study.py`）

- **配对**：`ts ∈ {0,1,2} × ss ∈ {0,1,2}` = 9 对（两臂**同划分、同初始化**）
- **两臂**：`frozen`（`graph_dir=products/alldata/graphs`，即正典）与
  `cbft`（`graph_dir=products/alldata/graph_variants/cb_ft_ss{S}`）
- **唯一变量 = `graph_dir`**；产物 `runs/cbft_study/{frozen,cbft}_ts{T}_ss{S}/seed{T}/`
- **零微调**：三个编码器变体已存在（按**划分种子**微调 ⇒ 9 对只需 3 套编码器，故复用）
- **两臂同时新跑**（各 9 run）：不能复用 `runs/binary_arm/main_base` 当基线 ——
  它是 09-17 21:31 跑的，而 `train.py` 于 09-18 18:04 改过，**臂间代码版本不一致**是混淆变量。
- 执行：18 run、wall **250.2 s**、失败 0。

**三条开跑前断言**（不通过即不跑）：
1. **单变量**（复用 `run_ablation.verify_single_variable`）：18/18 恰差 `graph_dir`（冻结臂差 0 键）
2. **同语料**：两臂 `split_dir`/`label_file`/`label_key_mode`/`seed`/`split_seed` 逐字相同。
   🔴 **`graph_dir` 从语料键中移除** —— 它是本研究的**变量**（`run_study.CORPUS_KEYS` 含它，
   那是因为二分类研究的变量是 `head`）。这是本驱动与 `run_study.py` 的唯一实质差别。
3. **产物层单变量**（新增，590×3 图全量）：变体的 `_feat.pt` 三通道 sha256 与正典**全部相同**、
   `_cb.pt` 两通道**全部不同**、`_pyg.pt`/`_m1.json`/`_hetero.json` 均为**软链**。
   证据直接取自 `_feat.pt` schema v2 自带的 `meta.channel_sha256` / `meta.cb_sha256`，零重算。

### 36.3 结果：效应确认

**test 侧（n=9 同配对，论文主表口径）**

| 指标 | frozen | cbft | Δ（同配对） | t | |
|---|---|---|---|---|---|
| micro@0.5 | 0.4455±0.0417 | 0.6921±0.0331 | **+0.2466** ± 0.0621 | **+11.92** | ★ |
| micro@val_thr | 0.4486±0.0561 | 0.7580±0.0525 | **+0.3094** ± 0.0891 | **+10.42** | ★ |
| macro@0.5 | 0.2488±0.0566 | 0.5559±0.0911 | **+0.3070** ± 0.0915 | **+10.06** | ★ |
| macro@val_thr | 0.2315±0.0487 | 0.5161±0.0562 | **+0.2846** ± 0.0764 | **+11.18** | ★ |
| 精确匹配@0.5 | 0.5821±0.0562 | 0.8237±0.0202 | **+0.2415** ± 0.0610 | **+11.89** | ★ |
| mAP | 0.3170±0.0655 | 0.7536±0.0519 | **+0.4366** ± 0.0742 | **+17.66** | ★ |
| Buggy@0.5 | 0.7948±0.0716 | 0.9338±0.0311 | **+0.1390** ± 0.0775 | **+5.38** | ★ |
| Buggy@val_thr | 0.7112±0.1022 | 0.9033±0.0385 | **+0.1920** ± 0.0986 | **+5.84** | ★ |

**val 侧（n=9，`paired_study_analysis.py`，本仓惯例口径）**：`val_micro@0.5` +0.1906（t=+6.99）、
`val_micro@val_thr` +0.2582（t=**+12.94**）、`val_macro@0.5` +0.1953（t=+8.30）、
`val_mAP` +0.3330（t=+10.63）。落盘 `experiments/cbft_paired.json`。

**判据**：n=9 双尾 0.05 的判据是 `|t| ≳ 2.3`。**8/8 指标全部显著**，
且 `Δmicro@0.5`、`ΔmAP`、`ΔBuggy@0.5` 的 **9 个配对全部为正**（无单一配对撑起结论）。
⇒ **原 n=3 的表面模式在 n=9 下成立，不是噪声。**

### 36.4 🔴 附带发现：主实验**不是逐位可复现**的（重跑抖动 ≈ 0.012）

`ts∈{0,1,2}` 的用意之一是让 (0,0)/(1,1)/(2,2) 三对与正典配置完全相同、可对拍。
**原设想「应逐位相同」被实测推翻**：

| 对 | Δmicro@0.5（冻结臂 vs `runs/seed{s}`） |
|---|---|
| ts0_ss0 ↔ runs/seed0 | 0.0135 |
| ts1_ss1 ↔ runs/seed1 | **0.0000** |
| ts2_ss2 ↔ runs/seed2 | 0.0223 |

**根因不是代码改动**（argv 逐键相同、batch 组成逐位相同 —— 每 epoch 的
`samples_processed`/`graphs_processed` 完全一致），而是 **CUDA 归约顺序非确定性**：
RGCN 的 scatter/index_add 在 GPU 上归约顺序不定，`loss` 从 **epoch 0** 起就有 ~1e-9 的差异
（epoch 0–5 的 `val_micro_f1` 仍逐位相同），该差异经训练被混沌放大，
**早停落在不同 epoch**（实测 ts0_ss0：新 21 epoch / 正典 14 epoch，best epoch 15 vs 8）。

🔴 **本仓目前没有任何开关能让 GPU 训练逐位可复现**：`--deterministic`（`train.py:260` 注明
"非主实验默认"）只做 `torch.set_num_threads(1)` + `torch.manual_seed(seed)`（`train.py:348-350`），
**没有** `cudnn.deterministic` / `use_deterministic_algorithms`。

**意义**：(a) 这层抖动（≈0.012，约为正典种子间 std ±0.0309 的 **40%**）是 §26.7/§27.5
「必须同配对」规范之所以必要的又一个实证 —— 它**只能被配对消掉一部分**（同对两臂各自带一份）；
(b) 论文的局限陈述应写入此条；(c) 若要真正可复现，须扩 `--deterministic`，
但 ⚠ `torch_scatter` 的 CUDA `scatter_add` 未必有确定性实现，需先小样验证（**未做**）。

### 36.5 边界（引用本节数字时必须同时给出）

1. **编码器是在训练标签上监督微调的** —— 任务特定表征学习，**不是无监督改进**。
   论文须写明，否则会被读成"用了额外标签"。
2. **只测了 ① 主库**。② 未做（微调版在 ② 已达 0.9901、编码器自身 `val_macro_f1=0.9854`，
   增益含饱和成分）。
3. **重跑抖动的存在**（§36.4）⇒ 单次重跑的点估计不可当精确值，判读一律看**配对 Δ 与 t**。
4. ~~本节**不改正典、不改大纲**。~~ ✅ **2026-09-19 已裁定：升为正典，见 §37**（大纲已先改）。以下为该裁定前的原始陈述，保留以备查：
   大纲 `改II` §165 明文「CodeBERT 在本文主方案中默认冻结参数，不参与微调」，
   并把该项列为 5.4.2 可选消融 ⇒ 升为正典将直接违背大纲，须先改大纲。

---

## §37 裁定：**微调 CodeBERT 升为主设计**，冻结降为消融/对比（2026-09-19）

### 37.1 裁定与依据

用户裁定：**「微调 CodeBERT」改为主设计，「冻结 CodeBERT」降为消融/对比，①②两组语料同步改。**

依据是同日的 **n=9 同配对复核**（§36）：test 侧 **8/8 指标显著**（判据 `|t|≳2.3`），
`micro@0.5` **+0.2466（t=+11.92）**、`mAP` **+0.4366（t=+17.66）**、`Buggy@0.5` +0.1390（t=+5.38），
且 `Δmicro@0.5`/`ΔmAP`/`ΔBuggy@0.5` 的 **9 个配对全部为正**。

⚠ **本节取代大纲 `改II` 原第 165 段**（"CodeBERT 在本文主方案中默认冻结参数，不参与微调"）。
按 `AGENTS.md` 的权威顺序，**大纲已先行修改**（见 §37.8），本节记录实现侧的同步。

### 37.2 正典的新定义

| | 改前 | 改后 |
|---|---|---|
| 正典 `graph_dir` | `products/<语料>/graphs`（冻结 `_cb.pt`） | `products/<语料>/graphs_ft/ss{S}`（**微调** `_cb.pt`，**含划分种子**） |
| 消融臂 `cb_ft` | 微调（消融项） | **删除**（它现在是正典） |
| 新增消融臂 | — | **`cb_frozen`**（`graph_dir = products/<语料>/graphs`） |
| 大纲 5.4.2 该项 | 「微调 vs 冻结」 | 「冻结 vs 微调」——**变量方向反转，对比关系不变** |

**微调编码器按划分种子取**（微调只用该划分的 train 标签），故正典路径**含 `ss{S}`**，
`run_ablation` 里 `split_seed == seed` 的既有绑定在新定义下依然自洽。

### 37.3 目录重构：`graph_variants/cb_ft_ss{S}` → `graphs_ft/ss{S}`

🔴 **必须改名，不能沿用原路径**：`run_ablation.variants_root_of()` 用
**`graph_dir` 的父目录 + `graph_variants`** 推导变体根。若正典 `graph_dir` 落在
`graph_variants/cb_ft_ss{S}`，则推出 `…/graph_variants/graph_variants` —— **全线错位**。
改名后：正典 `graphs_ft/ss{S}` → 变体根 `graphs_ft/graph_variants/` ✓ 自洽。
（两者层级深度相同，故变体内部的相对软链 `../../graphs/…` 改名后仍解析正确，已实测。）

⚠ 历史 `config.json` 里记录的旧路径**不改写**；改为在 `products/<语料>/graph_variants/`
留**同名兼容软链** `cb_ft_ss{S} → ../graphs_ft/ss{S}`，使旧记录仍可解析、可重放。

### 37.4 🔴 连带必修：`graph_dir` 必须**逐划分种子**取（否则所有开关臂都错）

正典路径含 `ss{S}` 后，**每个开关臂的 `graph_dir` 也必须逐种子取**——
否则 `seed2` 会拿 `ss0` 的微调编码器去配 `split_seed2` 的划分。
dry-run 实测确认过这个错（21 臂全部停在 `ss0`）。

**处置**：`run_ablation.canonical_args()` 把正典 `graph_dir` 就地转成模板
（`…/graphs_ft/ss{seed}`，正则 `(.+)/ss\d+`，**只在匹配时生效** ⇒ 冻结版正典行为逐字不变）；
`build_args()` 对**基线侧与覆盖侧一并展开**；开跑前的单变量断言改用**同样展开过的参照**，
否则每个开关臂都会被误判为"多改了一个 `graph_dir`"。

### 37.5 🔴 障碍：`cb_rev` / `cb_unlimited` 的变体带的是**冻结** `_cb.pt`

这两个臂的变量也在 `graph_dir` 里，而它们既有的变体是在**冻结**编码器基础上造的
（实测：其 `_cb.pt` 是指向 `products/<语料>/graphs/` 的软链）。
正典换微调后若沿用，它们就会「边变了 + 编码器也不同」= **两个变量**。

**解法 = 新建 `cb_rev_ss{S}` / `cb_unlimited_ss{S}`**（脚本 `scripts/build_ft_edge_variants.py`），
**逐图分流**：

| 情形 | 判据（逐图实测） | 处置 |
|---|---|---|
| 边变体的 `_feat` 三通道 == 微调基座 | 节点特征未被边改动 | `_feat.pt`/`_cb.pt` **软链**自微调基座 |
| 否则 | 边改动**连带改了节点特征** | 只对这批图**真跑 M3**（微调编码器） |

结果是 **① `cb_rev` 590/590 走软链、`cb_unlimited` 570 软链 + 20 真跑**；
② 相应为 1774 软链 与 1575 + 199。全库重编码（① 10 min、② 46 min / 种子，合计约 5.6 h）被避免。

**三条断言**（全量逐图，不过即不留产物）：① 节点集与正典一致；② 边变体在**冻结**编码器下的
`_cb.pt` 与正典**逐位相同**（证明节点文本窗口未被边改动）；③ 真跑出的 `_cb.pt` 与微调基座**逐位相同**。

### 37.6 🔴 意外发现：**`cb_unlimited` 从来就不是纯边消融**

分流时发现：放开 CALLBACK_RISK 上限后，**恰好 20/590 图（①；② 为 199/1774）的
`_feat.sv`（先验分数 $s_v$）随之改变**，且与边改变的那批图**完全重合**（差集为 0）。
⇒ **边集变化经 M1 回流到了节点特征**：该臂的真实变量含「边」与「$s_v$」两个。
**这一点在旧设计下就已存在**，只是直到本次逐图断言才第一次被显式测出（已写进变体的
`variant.json::caveat`）。它与 §12.4 待办 #2 的「稀释」（变量只落在 3.4%/11.2% 的图上）
是两个独立的解释性缺陷，引用该臂读数时都须披露。

### 37.7 正典 run **不重训**，由 n=9 复核产物提升

`runs/cbft_study/cbft_ts{s}_ss{s}/seed{s}` 的配置**逐键等于**新定义下的正典
（`seed=s`、`split_seed=s`、`graph_dir=graphs_ft/ss{s}`、其余全默认）⇒ 直接提升为 `runs/seed{s}`（①）
与 `runs/augmentation/seed{s}`（② 用 `runs/ablation_aug/cb_ft/seed{s}`）。
`config.json` 的 `out_dir` 一并更正（它是记账键，每个驱动都会覆盖，但不能让它说谎），
并新增 `promoted_from` / `promoted_note` 字段保留来源。

### 37.8 大纲改动（最高权威，先行）

`研究点一细化大纲改II.docx` 共改 **9 段 + 补 1 段**（原文与替换文字见执行记录）：

| 段（按内容定位） | 改动 |
|---|---|
| 「CodeBERT在本文主方案中默认冻结参数，不参与微调。」 | → 默认**参与微调**（只用训练划分标签），冻结作为消融对照保留 |
| 冻结三条理由 (1)(2)(3) | 改写为**微调的对应说明**（一次性开销可控 / 小批量+梯度检查点 / 离线缓存可复现） |
| 4.3.2「送入冻结CodeBERT」、4.3.2 优势段、4.3.4 公式解释 | 去掉「冻结」定语 |
| 5.4.2 表项「微调CodeBERT vs 冻结CodeBERT」 | → 「**冻结**CodeBERT vs **微调**CodeBERT」 |
| 5.4.2 验证目标 | → 「冻结CodeBERT相对微调CodeBERT在验证集macro-F1上的损失」 |
| **新增**（4.5 训练策略内） | 编码器微调超参：5 epoch、编码器 lr 2e-5、头 lr 1e-3、wd 0.01、seq-batch 6、patience 2——**大纲原先完全没有这一行**，属**补齐**而非修改 |

原件备份：`研究点一细化大纲改II.docx.bak-20260919-微调升正典前`。

### 37.9 归档与代码改动

**归档**：旧正典与旧消融臂整体移入 `runs/prior_frozen/`（含 `README.md`，体例仿 `runs/prior_badmetric/`）。
`runs/cbft_study/` **原地保留**——它是 §36/§37 的证据本身。

**代码**（5 处）：
| 文件 | 改动 |
|---|---|
| `run_ablation.py` | 删 `cb_ft` 臂、加 `cb_frozen`；`cb_rev`/`cb_unlimited` 加 `_ss{seed}`；新增 `frozen_graphs_of()` 与 `{frozen}` 模板；`canonical_args()` 模板化 `graph_dir`；`build_args()` 展开基线侧；断言参照同步展开 |
| `collect_ablation_results.py` | `PRODUCT_5` 的 `cb_ft` → `cb_frozen`；`ft_cost_of()` 从"臂"改挂**正典行**（微调现在是正典的一部分） |
| `build_ft_edge_variants.py` | **新增**（§37.5） |
| `run_cbft_study.py` | 不改逻辑（使命已完成）；其 `ARMS["frozen"]` 注释里的"正典"字样已过时 |
| `dataset.py` 等的 `DEFAULT_GRAPH_DIR` | **不改**：正典路径含划分种子，单一默认值无法表达；直接跑 `train.py` 的默认值 = **冻结臂**，已在文档写明 |

### 37.10 边界与待办

1. **消融全部重跑**（78 run）：正典换了 ⇒ 每个臂的 Δ 都必须相对新正典重算，**一个都不能省**。
   图 / 划分 / 标签 / 微调编码器全部复用，只有 GNN 训练要重跑。
2. **编码器在训练标签上监督微调** —— 任务特定表征，**不是无监督改进**，论文须写明。
3. **其他研究臂未重跑**：`loss_study` / `prior_dropout_study` / `binary_arm` 的基线仍是冻结版正典，
   其结论需标注工作点。**不在本次范围**，属已知开口。
4. **重跑抖动**（§36.4）依然存在：≈0.012，约为种子间 std 的 40%。
5. `cb_unlimited` 的**双重缺陷**（稀释 + 非纯边，§37.6）在本轮之后仍然成立。

---

## 38. DIVE 外部测试（大纲 `改II` 5.1 第六条 / 5.2 层次一）+ `cb_unlimited` 零功效实测

### 38.1 本轮做了什么

消融全部跑完后（① 21 臂 ×3 + ② 21 臂 ×3 = 126 run），在 **DIVE** 上做跨数据集外部测试，
并把 ①② 内测与 DIVE 外部测试**三方并列**成表（`eval_results/dive/comparison.md`）。

**抽样规模不重抽**：沿用 §13 已冻结的协议（**seed=0、n=900**，`sample_seed0.json`；
逐类实测 support 682/378/136/**30**/468/234/246，多标签 614、全零 105）。
用户 2026-09-19 指示"不必用全部数据、与两组语料数量持平即可"——**n=900 正落在 ① 池 453
与 ② 池 1774 之间**，且该协议是大纲 5.1(6)「不少于 500」+「每类 ≥20」的唯一自洽解，
**改 n 需要重走停止规则并披露**，故不动。

### 38.2 新增两个脚本

| 脚本 | 职责 |
|---|---|
| `scripts/build_dive_external_set.py` | DIVE 的 stage → raw(Slither) → M2/M1/PyG → M3 → 边变体，五步可单跑、可重入 |
| `scripts/evaluate_external.py` | 外部测试推理与报告；`--matrix {main,aug}` 一次跑完 21 臂 ×3 种子 |

**编码器矩阵**（这是 DIVE 侧最容易做错的地方）：外部测试必须用**各语料自己微调的编码器**，
但**图结构只有一份**（边/节点与编码器无关）⇒ 布局是「一份结构 + 三套 `_cb.pt`」：

```
products/dive/graphs/                     结构 + 冻结 CodeBERT 特征（= cb_frozen 臂用，①②共用）
products/dive/graphs_ft/ss{S}/            ① 微调编码器重编码（结构三件套软链自 graphs/）
products/dive/graphs_ft_aug/ss{S}/        ② 微调编码器重编码
products/dive/graphs_ft{,_aug}/graph_variants/{cb_rev,cb_unlimited}_ss{S}/
```

目录层次与 `products/<语料>/graphs_ft/ss{S}` **逐字对应**，故 `run_ablation.variants_root_of()`
推出的变体根自洽。编码器一律经 `corpus.json` 边车**硬校验语料归属**（跨语料套用不报错、
只会静默产出错误特征，同 §37.5 的理由）。

🔴 **阈值纪律**：`evaluate_external.py` **只读**源语料 `thresholds.json` 的 `best_threshold`，
**绝不在 DIVE 上重搜**（大纲 5.1：DIVE 不参与任何模型选择）。缺该文件即 `SystemExit`。

### 38.3 `evaluate_external.py` 的对拍验收（**逐位一致**）

新增 `--selfcheck`：只在**该种子自己的内部测试划分**上评，标签源取自该 run 的 `label_source`
（不是 CLI 默认值），用来与 `evaluate.py` 的既有产物对拍。

实测 `runs/ablation/cb_frozen`（3 种子）：`micro@0.5` / `micro@val_thr` / `macro@0.5` / `mAP` /
`val_threshold` **以及逐类 F1（7 类）全部 Δ = 0.00e+00**，与 `results.json` 逐位相同。
⇒ 外部测试脚本与主评估脚本**同源可信**，DIVE 上的数字不是"另一套口径"。

### 38.4 🔴 实测发现：`cb_unlimited` 在①②上**都是零功效臂**（Δ 恰为 0 或近 0）

复核消融表时发现 ① 的 `cb_unlimited` 六个指标与正典**逐位相同**。逐层排查如下（这是本条的证据链）：

| 检查 | 结果 | 结论 |
|---|---|---|
| 变体目录 `variant.json` 自述 | `edges_from: graph_variants/callback_unlimited` | 路径没接错 |
| 变体 `_pyg.pt` vs 基线 | **20/590 图边集不同**（且是**超集**：0 条被删、仅新增） | 变体是真的 |
| 变体 `_feat.sv` | 同 20 图改变 | M1 先验确实回流了（§37.6） |
| 这 20 图在池内？ | **仅 9/453**（11 个是 `buggy_*`，已被池剔除） | 干预面小 |
| 两次训练的 `best.pt` md5 | **不同** | 确实重训了，不是复用 |
| 两次训练的 epoch-0 loss | 0.960**3248** vs 0.960**2375** | 训练输入确实不同 |
| 两次的 `test_probs.pt` | maxΔ = 0.051 / 0.021 / 0.012 | 概率确实变了 |
| 两次的**预测矩阵**（@0.5 与 @val_thr） | **翻转 0 / 322** | 差异全在阈值带内，**没有一个决策越过阈值** |

⇒ **不是 bug，是真实的零效应**：干预改了 9 张池内图、概率动了 ~0.01–0.05，
但 ① 的测试集只有 **46 合约 / 322 个标签对**，这点扰动一个决策都没推动。

② 侧同样：边改动 199/1774（全在池内），`Δmicro@0.5 = 0.0000`、`Δmicro@val_thr = +0.0011`
——② 已在天花板（正典 0.9901），**没有上升空间**。

**结论与写法**：`cb_unlimited` 的 Δ≈0 **不能**读作"CALLBACK_RISK 上限不重要"——
它是**没有功效**（no power）而非**没有效应**：① 干预面 9/453、② 天花板效应。
论文中该项必须写成「**本实验未能检验该问题**」，并随附上表的干预面计数。
（该项本就有 §37.6 记录的两个独立缺陷：稀释 + 非纯边。）

### 38.5 边界

1. DIVE 只做**一次性外部测试**，不参与训练/验证/早停/阈值/模型选择（大纲 5.1）。
2. ①② 与 DIVE 三列是**三套不同评测条件**，**禁止跨列比较绝对值**（§23）——
   `collect_dive_comparison.py` 表 2 的 Δ 一律**各减各列自己的正典**。
3. ③ DIVE 的类别先验与训练语料差异较大（多标签 68.2% vs ① 近 0、② 单标签），
   故并列报告**逐类 PR-AUC/mAP**（阈值无关）与**训练语料 vs DIVE 的正样本率**，
   以区分"先验变化"与"排序质量变化"（`改II` 5.5.1(2)）。
4. DIVE 全零标签合约 **105** 个，单独报告逐类 FPR 与合约级误报率（`改II` 5.5.1(3)）。
5. ①② 的 `micro@val_thr` 阈值来自**各自语料的验证集**，两者数值不同不影响可比性
   （同列内比较）。

### 38.6 🔴 执行中发现的真 bug：`stem` 标签键模式对 DIVE **全错**（已修）

**现象**：DIVE 图建好后，`build_index(..., key_mode="stem")` **匹配 0/890**——整个外部测试集是空的。

**根因**：`dataset.stem_key_of()` 只做 `str(contract_name).split("-", 1)[0]`。两个语料的标签命名不同：

| 语料 | 源文件 | 标签 `contract_name` | 旧实现给出 | 应为 |
| --- | --- | --- | --- | --- |
| ② 增强集 | `0x000c…f53.sol` | `0x000c…f53-C10Token.sol` | `0x000c…f53` ✓ | 同 |
| DIVE | `8263.sol` | `8263.sol` | **`8263.sol`** ✗ | `8263` |

DIVE 的标签名**没有 `-`** ⇒ `split` 返回整个字符串 ⇒ 键是 `"8263.sol"`，与图 base `8263`
一个都对不上。**手册 §10.2 第 9 条早就写明**「DIVE `contract_name` 形如 `8263.sol`」且 stem
模式取的就是 `.sol` 词干 —— 即原实现**没有兑现它自己的文档**。之所以一直没暴露：
② 是 stem 模式的唯一既有用户，而它 9026/9026 的标签名都带 `-`，恰好绕过。

**修复**（`dataset.stem_key_of`，一处）：取 `-` 前之后**再剥 `.sol` 后缀**。
两语料自此同一条规则：`Path(contract_name.split("-", 1)[0]).stem`。

**行为保持性已证**：对 ② 的 9026 条**逐条键不变**（0 条不同）⇒ ② 的全部既有结果零影响；
实测 ② `build_index` 仍为 1774/0 未匹配。新增回归锁 3 例（两种命名各一 + ② 逐条不变）。

**修复后 DIVE 实测**（890 图全部匹配）：

| 类 | 抽样时 | 解析后 | 差 |
| --- | --- | --- | --- |
| access_control | 682 | 675 | −7 |
| arithmetic | 378 | 375 | −3 |
| dos | 136 | 135 | −1 |
| **front_running** | **30** | **30** | **0** |
| reentrancy | 468 | 467 | −1 |
| time_manipulation | 234 | 231 | −3 |
| uncheck | 246 | 244 | −2 |

多标签 610（68.5%）、全零（正常合约）103。**每类仍 ≥20，大纲 5.1(6) 门槛继续达标**。
差额来自解析过滤（900 → 891 AST → 890 图；逐项见 `products/dive/raw/filter_report.txt`），
按大纲 5.1 第一条须按数据集分别计入透明性声明。

> ⚠ **教训同 §28/§29.4/§37.5**：这类错误**不崩溃**——它只是把数据集变空。
> 若不做"匹配数 == 图数"的显式校验，下一步会在空集上跑出 `nan` 或直接报"无样本"，
> 而**原因早已在两步之前**。故 `evaluate_external.py` 把"未匹配"做成**硬失败**而非警告。

### 38.7 执行事故：DIVE 变体构建首跑失败（两处，均已修）

**事故 1：`step_variants` 假设边变体目录已有 `_feat.pt`。**
`M2` 只产 `_hetero.json`/`_m1.json`/`_pyg.pt`；`_feat.pt` 是 **M3** 的产物。首版代码直接
`torch.load(edge_dir/"<n>_feat.pt")` ⇒ `FileNotFoundError`。①② 的同类变体之所以没这个问题，
是因为 `build_graph_variant.py` 在造变体时**顺手跑了 M3**（既有工具已内含这一步）。
**修**：`step_variants` 对每个边变体先跑一次 M3（冻结编码器即可——见下条），并用
`assert_must_feat` 断言 `must` 子集的三通道与边变体逐位相同。

**事故 2：等待脚本的 `rc=$?` 被 `$(date)` 吃掉。**
`echo "... rc=$? ..."` 里若含命令替换，`$?` 会变成**替换命令**的退出码（`date` 恒为 0）。
于是**整步失败却打印 `rc=0`**，而监视脚本正是以"`构建链全部结束` && rc=0"判断成功 ⇒
失败被静默吞掉。
**修**：先 `rc=$?` 存进变量，再拼字符串。⚠ **这个是通用的**——本仓所有"`echo ... $(...) ... $?`"
形态的日志都有同样的坑，写队列/监视脚本时必须先存后拼。

**顺带查清的两件事（都影响做法，不只是 bug 修复）：**

1. 🔴 **`_feat.pt` 不是"编码器无关"的**——张量三通道确实与编码器无关，但它的 `meta` 里记着
   `cb_sha256` / `combined_sha256`，**这两个随编码器变**（实测：冻结树与微调树同名文件的
   `cb_sha256` 不同）。故**不能**把冻结树算出的 `_feat.pt` 软链进微调树——那会留下
   "张量对、指纹错"的元数据。正确做法是 `_feat.pt` 与 `_cb.pt` **成对**处理（要么都软链自同一棵树、
   要么都由同一次 M3 产出）。已用 `verify_channels="all"` 对 **7 棵树全部抽检通过**验证。
2. 🔴 **`must` 子集必须一次性喂给 M3，不能逐图调用**。首版按图 `--only` 调用 ⇒ 每图都要
   重载 CodeBERT（~480 MB）+ 全目录扫描；DIVE 规模下不可接受。改为：把 `must` 的
   `_hetero.json`/`_m1.json` 软链进一个临时 `--in-dir`，**一次** M3 写进目标目录
   （M3 只读这两类文件，不需要 `_pyg.pt`）。⚠ 必须**先跑子集 M3、再补 `same` 的软链**——
   否则 `run_guard.corpus_conflict` 会因"out-dir 已有的 `_feat.pt` 与 in-dir 无同名项"判成跨语料而拒写。

**纪律**：这三条（`_feat.pt` 指纹随编码器变、子集要批量喂、软链顺序影响守卫）都不是
"知道原理就能想到"的，而是**跑一次才暴露**。记录在此，供 SolidiFI（阶段 G）直接复用。

### 38.8 复核阶段又查出两处 bug（都是"不报错、只是结果无意义"）

**bug A：单臂路径把三个种子都映到 `ss0` 那棵树。**
`evaluate_external.py --runs-dir` 原先从 `runs/<arm>/seed0/config.json` 读 `graph_dir`，
但**它记的是已展开的路径**（`.../graphs_ft/ss0`），对它调 `RA.expand` 是**空操作** ⇒
三个种子全落回 `ss0`，把 seed1/seed2 的模型配上了 **ss0 编码器**产出的特征。
`--matrix` 路径用的是 `RA.canonical_args()`（**带模板**），故**交付用的矩阵数字未受影响**；
受影响的是我用单臂路径做的几次**临时诊断**（其中一个数字 0.1173 曾写进交付文档，已更正为 **0.0282**）。
**修**：先把结尾 `ss<N>` 正则还原成模板再逐种子展开，并加断言"逐种子得到的树名必须恰是 ss0/ss1/ss2"。

**bug B：`--selfcheck` 把 DIVE 的图拿去配源语料的标签。**
自检的语义是"复现**源语料**自己的内部测试数字"，故必须用**源语料**的图目录；
原实现复用了 DIVE 的映射 ⇒ 46/46 全不匹配。
**修**：自检分支改为逐种子取 `args["graph_dir"]`（`ss<N>` → `ss{s}`）。
修后复算与 `evaluate.py` 既有产物**逐位相同**（`micro@0.5` 与 `mAP` 六位小数全等）。

**教训（与 §28/§29.4/§37.5/§38.6 同一族）**：这两处都**不会崩溃**——
A 产出的是"看起来正常的数字"，B 会在下游报一句"标签没匹配上"而原因在两步之前。
**可复用做法**：凡是"逐种子不同"的路径，**必须**在展开后加一条**形状断言**
（得到的目录名集合 == 期望集合），不能只看"跑通了"。

### 38.9 `.gitignore` 漏了四种新目录形态（约 16 GB 会被误纳入，已修）

`git status` 复查时发现：`products/` 下的 `graphs_ft/`、`graphs_ft_aug/`、`graph_variants/`、
`src_stage/` **不被任何忽略规则匹配**（原规则只有 `products/**/raw/*` 与 `products/**/graphs/*`），
于是它们全部列为未跟踪 ⇒ **`git add -A` 会一次性纳入约 16 GB**
（② 的 `graphs_ft` 单个就 5.0 GB；DIVE 侧另有 8.7 GB）。该缺口自 §37 引入 `graphs_ft` 时就存在。

**修法有一个坑（两种直觉写法都实测失败）**：

| 写法 | 结果 |
| --- | --- |
| `dir/` | 目录式排除，`!` 无法取反（AGENTS.md 早已记过这条） |
| `dir/*` | 把**子目录本身**也排除 ⇒ git 不再往里走 ⇒ `!variant.json` **永远不生效**（实测仍被忽略） |
| ✅ `dir/**` + `!dir/**/` + `!具体文件名` | 先排除全部内容、再把**目录**重新纳入，白名单生效 |

**现纳入范围**：各变体的 `variant.json`（变体自述文件：唯一变量、断言口径、软链/重跑分流）共 **41 个 / 164 KB**。
其余（特征张量、图、软链、抽样品源文件、构建日志）全部忽略。

⚠ SolidiFI（阶段 G）新增产物形态时**照此办理**——这条缺口是"新增目录形态但忘了补规则"，
不是一次性事故。

---

## §39 正典同步（2026-09-20）：文档与派生产物全面切换到微调 CodeBERT

### 39.1 裁定与范围

用户裁定：**「① 主库正典按微调 CodeBERT 计算，同步修改文档。」**

§37（2026-09-19）已把微调 CodeBERT 升为正典，但**只改了训练侧**（`runs/seed{s}` 由
`runs/cbft_study/cbft_ts{s}_ss{s}` 提升而来），**文档与派生产物全部停留在冻结口径**。
本节的执行范围 = 把两侧对齐。

### 39.2 🔴 同步前仓库里有两个"正典"数字并存（本次暴露的最严重一致性问题）

| 载体 | 同步前 | 同步后 | 说明 |
| --- | --- | --- | --- |
| `runs/seed*/results.json` | 0.7273/0.6667/0.7391 | **未变** | §37 提升时已换，是**新**的 |
| `runs/summary.json` | micro@0.5 **0.4256** | **0.7110** | 提升正典时**未重新 `--summarize`**，mtime 2026-09-17 早于 `results.json` 的 09-19 |
| `runs/error_rates.json` | 合约级 F1 **0.723**、误报 **18.3%**、漏报 **30.6%** | **0.942 / 2.62% / 8.02%** | 同上，mtime 2026-09-17 |
| `experiments/results.md` §0/§1/§6 | 0.4256 / 0.9347 | 见 §39.5 | 全文停留在冻结口径 |
| `AGENTS.md` 进度主表、`report_*` 两卷、`ablation_results.md` §9–§11 | 冻结口径 | 见 §39.5 | 同上 |

**根因**：§37 的"提升"只移动了 run 目录，**没有触发任何下游重算**。
`runs/summary.json` 与 `runs/error_rates.json` 都是**从 run 派生的**，派生源换了、派生文件没换，
于是同一个仓库里 `results.json` 说 0.7110、`summary.json` 说 0.4256。

⚠ **这不是笔误，是一个可复现的流程缺口**：`evaluate.py --summarize` 与 `error_rates.py`
都没有"输入比输出新就报警"的机制。凡是"换正典"或"重跑某个 run"的操作，**必须显式列出下游派生产物并重算**。
本次已把该清单写入 §39.5。

### 39.3 🔴 顺带发现：测试套件当前是红的（`metrics.buggy_f1` 有规格无实现）

`tests/test_metrics.py` 第 353–413 行有 **6 个用例**引用 `metrics.buggy_f1`，而 `scripts/metrics.py`
**没有这个函数**（HEAD 与工作树都没有）⇒ `pytest tests/test_metrics.py` **6 failed**。

该口径的定义（由测试钉死，非本次发明）：
> **有漏洞合约子集上的 micro-F1** = 按 `y.any(axis=1)` 切片后算 `micro_f1`。
> 动机：**干净合约上的误报会拉低 micro-F1，但不应该影响这个数**。

它与 §30 的**合约级二分类 F1** 是**两个不同的量**，仓内有专门用例锁住两者不相等
（`test_buggy_f1_differs_from_contract_binary_f1`）：

| 口径 | 粒度 | 干净合约上的误报 | 问的是 |
| --- | --- | --- | --- |
| `buggy_f1` | **标签对**，且只数有漏洞的合约 | **整段摘掉** | 「漏洞判得准不准」 |
| 合约级二分类 F1（§30 L3） | **合约**（`any` 塌缩） | 计入 FP | 「有没有报出至少一类」 |

**本次已补齐实现**（`scripts/metrics.py::buggy_f1`，返回 `{f1, n_rows_total, n_rows_masked, n_pos_pairs}`，
空子集返回 `None` 而非 `0.0`，单列 `[N,1]` 报错）。
`pytest tests/` 由「6 failed」变为 **268 passed + 2 skipped**。

> 🔴 **该函数的 6 个用例此前一直在失败**，也就是说：从测试被写下的那一刻起，
> `pytest tests/` 就是**红的**，而 `AGENTS.md` 的进度记录仍写着"全部通过"。
> ⚠ **教训（与 §28/§29.4/§35/§37.5/§38.6 同一族）**：这类缺口**不会崩**——
> 它只是让"测试通过"这句话变成假的。**进度类断言必须现场跑一遍再写。**

### 39.4 `tests/test_ablation_switches.py` 有 2 个**过期 skip**（假绿）

| 行 | skip 理由 | 实际状态 |
| --- | --- | --- |
| 298 | 「RGCN 层数 L=1/2/3 未实现：`model.SSMHG` 硬编码 conv1/conv2 两层」 | ❌ **已实现**：`model.py` 支持 `num_layers ∈ {1,2,3}`，`runs/ablation/layers1|layers3` 已跑完并入库 |
| 304 | 「微调 CodeBERT vs 冻结未实现：M3 只产出冻结嵌入缓存」 | ❌ **已实现且已是正典**：`scripts/finetune_codebert.py` + `tests/test_finetune_codebert.py`，`graphs_ft/ss{S}` |

两处 skip 使 `pytest` 报 **2 skipped**——本仓规范明令 **skip 登记不得"假绿"**，而这两条现在正是假绿。
**未在本次修**（属开发项，见 §39.6 待办 1）。

### 39.5 本次执行清单（全部零重训）

已做：

1. `python scripts/evaluate.py --summarize` → `runs/summary.json` 刷新为 **0.711023 / 0.729702 / mAP 0.758216**。
2. `python scripts/error_rates.py` → `runs/error_rates.json` 刷新（① 正典合约级 F1 **0.9435@0.5 / 0.9419@val_thr**、
   误报 **3.95% / 2.62%**、漏报 **6.43% / 8.02%**）。
3. `scripts/metrics.py::buggy_f1` 补齐实现（§39.3）。
4. 新增**单一权威数字载体** `experiments/canonical_ft_numbers.md`（程序生成：逐种子 + mean±std + 逐类 + 消耗 + 微调段成本）。
   此前全仓**没有任何一处**同时载有①②两语料的新正典逐类/逐种子数字，这正是 §39.2 那个缺口的土壤。
5. 文档同步：`results.md`、`report_data.md`、`ablation_results.md`、`ablation_plan.md`、`AGENTS.md`、
   `项目组织架构.md`、`report_conclusions.md`（结论卷另加 §0.5「口径变更影响清单」）。

⚠ **`experiments/ablation_results.md` 的同步有一处特别容易错**：该文里的**臂名已互换**——
文中旧「正典」= 今日 `cb_frozen`；文中旧臂 `cb_ft` = **今日正典**（已升格、不再是臂）。
照字面替换数字会得到完全相反的表。

### 39.6 仍未做（口径变更的**开口清单**，供后续裁定）

| # | 项 | 性质 | 代价 |
| --- | --- | --- | --- |
| 1 | `tests/test_ablation_switches.py` 两个过期 skip 改为真实测试 | 开发（小） | 分钟级 |
| 2 | 四条概率尺度干预线（`loss_study` / `prior_dropout_study`）在新正典上重算 | 重跑 | 每条线 ≈9 run；且 `prior_dropout_study` 同时是 §1.8/§1.10 的 n=9 基线，**必须连动** |
| 3 | 输出头臂 `runs/binary_arm/*` 在新正典上重跑 | 重跑 | 36 run |
| 4 | 三条对照臂（`neardup` / `withbuggy` / `augmentation_dedup`）在新正典上重跑 | 重跑 | 9 run |
| 5 | `②` 的 `runs/augmentation/summary.json`（工作树中被删除，未重建） | 决策 | 分钟级 |
| 6 | §0.5 A1：在新正典上重算「主库低分是数据事实」的证据链（逐类 AP / oracle 上限 / 恒零类） | 零重训 | 分钟级 |
| 7 | §0.5 A2：把「阈值目标与部署代价不一致」从"已观测代价"降级为"结构性隐患"（审计已实测：21 个 arm-seed 中 20 个为正、均值错位 +0.43） | 零重训 | 已完成测算，待落笔 |

⚠ **禁止**：把 B1/B2/B3/B4 四类臂的数字与新正典**并列比较**——它们跨两个编码器树，
比较结果会把「换了编码器」误读成「换了那个组件」。


### 39.7 🔴🔴 同步过程中发现：**§1.1 那条证据链是冻结编码器的产物，不是数据事实**

这是本次同步**最重要的实质发现**，比数字替换本身重要得多。

§1.1（`report_conclusions.md`）用三条证据论证「主库的低 macro-F1 / mAP **是数据事实、不是方法失效**」：
oracle-F1 低、稀有类排序弱（ROC-AUC 近随机）、概率尺度塌缩。**三条全部随正典更换而失效。**

同一套 `diagnosis.json` 字段，两个编码器对照（① test seed0）：

| 类（support） | 冻结臂 `cb_frozen` pos中位/neg中位 | **新正典** pos中位/neg中位 | 冻结臂 oracle-F1 / ROC-AUC | **新正典** oracle-F1 / ROC-AUC |
| --- | --- | --- | --- | --- |
| `dos`（1） | 0.128 / **0.126**（几乎重合） | **0.843 / 0.0011** | 0.087 / 0.533 | **0.500 / 0.956** |
| `front_running`（1） | 0.048 / **0.043**（几乎重合） | **0.622 / 0.0023** | 0.105 / 0.622 | **0.667 / 0.978** |
| `time_manipulation`（2） | 0.106 / 0.051 | **0.632 / 0.0007** | 0.250 / 0.795 | **1.000 / 1.000** |
| `access_control`（3） | 0.410 / 0.289 | **0.768 / 0.0112** | 0.182 / 0.481 | **0.500 / 0.884** |

（3 种子均值的 oracle-F1：`dos` 0.722、`front_running` 0.722、`time_manipulation` 0.651、`access_control` 0.633。）

**读法**：新正典下稀有类的**正样本概率中位数 0.62–0.84、负样本中位数 0.0007–0.0023**，
两类**几乎完全可分**。它们 F1 仍为 0 的直接原因是**单一全局阈值**（val 搜到 0.75 / 0.60 / 0.80）
高于 `front_running` / `time_manipulation` 的正样本中位数（0.62 / 0.63）⇒ **整类被判负**。
同一批权重在 **@0.5 下这三类的 F1 是 0.49 / 0.17 / 0.49，不是 0**。

🔴 **连带影响（比 §1.1 本身更大）**：§1.2「稀有类短板**无法由概率尺度类干预解决**——三条独立路径全部否证」
中，**`per-class` 阈值那一条的否证理由已经不存在了**（当年否证它是因为"micro 塌到 0.3532"，
但现在稀有类是**可分的**、全局阈值才是瓶颈）。**其余三条（放开截断 / 温度缩放 / focal·ASL）也都是在冻结工作点上测的。**

⚠ **但这不等于"per-class 阈值现在一定有效"**——它是一条**必须重做的实验**，不是一条已成立的结论。
本仓规范（§26.7/§27.5）要求 n≥9 同配对。

**可复用教训**：**「某指标低是数据事实」这类断言，必须与"当前模型工作点"绑定陈述。**
本仓出现过至少两次同类问题：§28 那次是"指标实现错"，这次是"工作点换了但结论没跟着换"。
两者的共同点是——**结论文字比它依赖的数字活得更久**。


---

## §40 口径同步收尾 + per-class 阈值重做 + GCN 基线（2026-09-20）

**触发**：用户指令——「修改 summary.json 及其他文档及总结中正典的描述和结论，改为微调的结果。
然后重做 per-class 阈值、补 GCN 基线，要求能得到 7 种漏洞各自的 F1 分数。」

### 40.1 三件事都做了，且都零重训（GCN 训练除外，6 run ≈ 2 分钟）

| # | 产物 | 说明 |
|---|---|---|
| 1 | `runs/summary.json`、`runs/augmentation/summary.json` 等 + 7 份文档 | 见 §40.2 / §40.6 |
| 2 | `eval_results/calibration{,_aug}/`（**重做**） | `calibrate.py` 在新正典上重跑；旧档归档至 `calibration/prior_frozen/` |
| 3 | `runs/baseline_gcn{,_aug}/` + `eval_results/per_class_f1.json` | GCN 基线（关系盲）+ 七类逐类 F1 汇总 |

### 40.2 🔴 `summary.json` 家族新增**口径戳**`provenance`（源头修，不是手改产物）

`evaluate.py::summarize` 现在会从各 seed 的 `config.json::args`（**只读，不加载权重**）推导并写入：

```json
"provenance": {"n_configs": 3, "encoder": "fine-tuned CodeBERT（§37 起正典）",
               "graph_dir_leaf": ["ss0","ss1","ss2"], "head": ["multi"]}
```

**为什么值得改代码而不是改 JSON**：§37 那次事故的形态就是「run 是新的、summary 是旧的」，
而 summary **自身无法自证**是哪一套正典 —— 读者只能靠数字反推。手改 JSON 会被下一次
`--summarize` 覆盖掉，所以在生成侧写死。判定依据取 `graph_dir` 含不含 `graphs_ft`；
出现**混合**编码器树时明确输出「⚠ 混合」而不是沉默。

### 40.3 per-class 阈值：**旧否证前提已消失，但新口径同样不能直接用**

- 未重做前的库存结论是「per-class 阈值把 micro 塌到 0.3532」→ **否证**。该前提在新正典下不成立。
- 重做实测（`eval_results/calibration/summary.json`，①）：micro **0.6851**（−0.0446）、
  macro **0.6363**（**+0.1377**）、合约级 F1 **0.9593**（**+0.0174**）；
  `front_running` **0.0000 → 0.6389**、`time_manipulation` **0.0000 → 0.3016**。
- 🔴 **但它不能进主结果**，理由是量化的、不是习惯性的：**val 上 `dos`/`front_running`/`time_manipulation`
  各只有 1 个正样本**，逐类调阈在其中近乎无约束。过拟合审计（`overfit_audit`）：
  val→test macro 落差 **0.034 / 0.161 / 0.025**、距 test-oracle 仍差 **0.090 / 0.257 / 0.154**，
  且逐种子选出的阈值极不稳定（`dos` 0.75/0.60/0.20、`reentrancy` 0.80/0.45/0.25）。
- ✅ **审计顺带给出一条比 F1 更值钱的结论**：test-**oracle** macro-F1 ≈ **0.80**，实际只兑现 **0.636**
  ⇒ **排序里带着的信息足够支撑 ~0.80 的 macro，瓶颈在"用一个全局阈值卡七类尺度差异极大的输出"**。
  这把 §39.7 的「稀缺类可分」推进到了可操作层面：**问题在阈值口径，不在表征，也不在样本量**。
- ② 上 per-class 阈值**无增益**（macro 0.9910 vs 全局 0.9924），从反面支持同一条判断。

### 40.4 🔴🔴 GCN 基线是**负面结果，须作者裁定如何写进论文**

设定：唯一变量 `--conv rgcn → gcn`，逐种子取匹配编码器树。① 3 种子 + ② 3 种子。

| 指标（①） | RGCN 正典 | GCN 基线 | 差异 |
|---|---|---|---|
| micro @0.5 | 0.7110±0.0389 | 0.5882±**0.1060** | −0.1228 |
| micro @val_thr | 0.7297±0.0675 | **0.7759**±0.0251 | **+0.0462（GCN 更高）** |
| mAP | 0.7582±0.0056 | 0.7430±**0.0462** | −0.0152 |
| 合约级 F1 @val_thr | **0.9419**±0.0385 | 0.8601±0.0616 | −0.0818 |

**读法与两个必须披露的混杂**：
1. GCN 的 `micro@val_thr` 名义更高，但 `@0.5` 崩得更多、std 是正典的 2.7 倍 ⇒ **n=3 判不了方向**。
2. 它的"高 micro"**是用误报换的**（合约级 F1 低 0.0818）—— 与 §30 的 L1/L3 落差同源。
3. 🔴 **混杂 1**：`GCNConv` **忽略 `edge_type`** ⇒ 它是"**关系盲**"，不是另一个 GCN 实现。
4. 🔴 **混杂 2**：参数量 **415,226 → 251,336（−39.5%）** ⇒ 差异混着"少了 4/5 的关系参数"。
5. ② 上正典逐类全胜（micro 0.9913 vs 0.9802），但 ② 已在天花板。

**与全仓证据一致**：把关系结构整个拿掉，**mAP 几乎不变**（0.7582 → 0.7430，在噪声内）；
而把编码器从微调换回冻结，mAP 掉到 **0.3186**。⇒ **再次指向「输入表征质量是唯一稳定有效的一维」**。

> ⚠ **这是一条"方法贡献被削弱"的结论**。可行的诚实写法是
> 「关系感知相对关系盲的增益在 n=3 下不显著；决定性因素是输入表征质量」，
> **但这是论文定位问题，须由作者裁定**，本文件不代作者下这个结论。
> 若作者要主张 RGCN 优势，**前置条件**是：参数量匹配的 GCN 对照 + n≥9 同配对。

### 40.5 🔴 顺带堵掉一个**硬规则级**的洞：`runs/codebert_ft/`（2.9 GB，单文件 498 MB）

- §37 起正典的微调编码器落在 `runs/codebert_ft/<语料>/ss{S}/encoder/`：**2.9 GB**，
  含 6 份 `pytorch_model.bin` 各 **498 MB**。
- `.gitignore` 里 `runs/**/*.pt` **只认 `.pt`** ⇒ `.bin` 全部漏网，`git add -A` 会一次性纳入，
  **直接撞 AGENTS.md「不要提交超过 100 MB 的文件」**。这是与 `graphs_ft/` 同类的**第二个洞**，
  且 AGENTS.md 与 `.gitignore` 两侧都从未提过它。
- **已修**：按 `graphs_ft` 同款写法（`dir/**` + `!dir/**/` + `!具体文件`）只纳入 4 类**自述/审计边车**
  （`corpus.json` 是编码器↔语料的硬校验锚点，缺它 `build_graph_variant.py` / `build_dive_external_set.py` 硬失败）。
  实测 `git add -A` 由 2.9 GB 降为 **30 个小文件**，全库无 >100 MB 待纳文件。
- **教训（写入 AGENTS.md）**：**「补 `.gitignore` 规则」与「改说明文字」是两件事**，两次都只做了前者；
  且触发点两次都是"发现某目录会被 `git add -A` 扫进去"，`runs/` 侧**从未做过同类排查**。
  新口径 = 新增产物形态时**必须**做三件事：`git check-ignore -v` 实测 + `git add -A --dry-run` 数文件并逐个查大小 + 更新说明。

### 40.6 文档同步审计：4 个独立审计 agent 的结果

派了 4 个**只读**审计 agent（结论卷/数据卷、总表与消融卷、根文档与手册、`runs` 与 `eval_results` 派生产物），
逐条报告。**已修**（本会话）：

| 类别 | 内容 |
|---|---|
| **派生产物重建**（agent 4 查出） | `runs/augmentation/summary.json`（**被删未重建**）、`runs/augmentation/diagnosis_summary.json`（同）、**`runs/diagnosis_summary.json` 是 09-17 冻结值且与自己同目录的 `seed*/diagnosis.json` 对不上**、`runs/ablation{,_aug}/*/diagnosis_summary.json` **42 个的 `seeds` 只有 `[2]`**（逐 seed 调用时每次覆写聚合文件 ⇒ n=1）、`runs/ablation/.gitkeep`（被删）。 | 
| **结论文档**（agent 1） | `report_conclusions.md`：§0 条 1（"数据事实"整条推翻）、§1.1 头注与推论、§1.2 表（路径 B 重做 + A/C 加冻结工作点限定）、§1.3、§1.6 整节重写、§2.2/§2.3、§3.1/§3.2 全部四条、§3.3 路线图、§4.2 #2（focal 已裁定）、§5.1/§5.2 #6、§7.2/§7.6、**§9.3/§9.4 两张 L1/L2 表整表重算**、§9.5 两条、§9.6.3、§9.6.5、磁盘数字。 |
| **消融卷**（agent 2） | `ablation_results.md`：② 的臂数/run 数**整片停留在「5 臂 / 78 run」旧态**（6 处，可被产物直接证伪）；两处 2026-09-20 当场新写但**本身不成立**的注（「micro@thr 离散仍最大」「结构结论不依赖数值」）。`ablation_plan.md`：**C 盘硬门槛误写 30 GB**（实为 8 GB，会影响开跑决策）、文件头与 §0 就绪表、M2 守卫「待实施」（**已实施**）。`results.md`：2.7 倍、3 处残留标记。 |
| **根文档/手册**（agent 3） | `AGENTS.md`：空间估算（20 GB/alldata-graphs 15 GB → 22 GB/630 MB）、`codebert_ft` 洞 + 自检口径、`variant.json` 计数、`best.pt` 白名单集体积（115 MB → 1.5 GB）、**语义锁死项补「正典 graph_dir」一行**、193→268 passed、37→32 GB。`论文开发手册.md`：头部「现行主实验」块、零泄漏臂与 ② 的数字、§3.2 路径表补 `graphs_ft`、DIVE 状态、`splits.csv` 行数、§10.2「论文须写 448」→453、§11.3 执行状态、§12 第 26/53 条。 |

**仍未做（登记在此，不静默）**：
- 计数类断言（`ablation_results.md` §6.1/§10.3/§11.x 的「12/16 反号」「16/21 为负」等）
  **新正典下已大面积失效**。我独立复算确认：**① 21 臂中 Δmicro@0.5<0 者 20/21、ΔmAP>0 者仅 1/21**
  ⇒ 「拿掉任何组件，排序变好、F1 变差」这一**叙事整体反转**（新正典下两者同向变差，
  即组件都是有正贡献的）。这是**结论级**改写，涉及 `ablation_results.md` 多节 + AGENTS.md，
  **须作者裁定后整节重写**，本次只加了标记与复算值。
- `runs/error_rates.md` 把 **3 个冻结臂与 2 个新正典臂并列在同一张表**且无工作点标注。
  根治须重跑 `loss_study`/`prior_dropout_study`（§39.6 待办 2）。
- `论文开发手册.md` §11.4 计时表、`Todo_List.md` 整体（~20% 同步度）、`项目组织架构.md`
  的 `.gitignore` 说明段与目录清单、`docs/M5_dev_plan.md` —— 已派 agent 处理，见下条。

### 40.7 开口清单（在 §39.6 基础上更新）

已完成：§39.6 的 (5)（`runs/augmentation/summary.json` 重建）、(6) 的**前置**（诊断线已全部刷新到新正典，
含 ① 的 `diagnosis_summary.json` —— §39.7 那条证据链现在具备重算的数据条件）。

仍未做（按性价比）：
1. **§39.6 (1)** 两个过期 `@pytest.mark.skip`（`tests/test_ablation_switches.py`）——当前 `2 skipped` 仍是假绿。
2. **§39.6 (2)(3)(4)** 重跑 `loss_study`+`prior_dropout_study`（≈54 run）、`binary_arm`（36 run）、
   三条对照臂（9 run）——**这三组结论全部还挂在冻结工作点上**。
3. **GCN 基线的 n≥9 复核 + 参数量匹配对照**（§40.4）。
4. **消融计数类断言的整节重写**（§40.6）。
5. `eval_results/ablation/collected{,_aug}.md` 的样板句未按 ② 适配（② 的 support 是 12–39，
   不是 ① 的 1–2，那句「单张图判对判错即可让 F1 跳 ±1.0」在 ② 上是错的）。
6. `products/**/graphs_ft` 等新形态在 `runs/` 侧**从未做过**同类 `.gitignore` 排查（规则已补，习惯未补）。

---

## §41 七类逐类 F1 的三口径对比表 + DIVE 的 mAP 不可复现（2026-09-20）

### 41.1 新增产物

`scripts/collect_three_caliber_tables.py`（**纯聚合层**：只搬运产物、只调 `metrics`，
不重实现任何指标）→ `experiments/per_class_three_caliber_tables.md`。

**6 张表 = 3 口径 × 2 工作点**（@0.5 / @源语料验证集阈值），每张 **46 行**：
① 主库正典 + ① 21 个消融臂 + ② 增强集正典 + ② 21 个消融臂 + DIVE（①模型 / ②模型）；
列 = 7 类 + 汇总；每格 3 种子 `mean±std`（ddof=1）。逐类 support 单列一张（按种子 `a/b/c`）。

数据来源：①/② 由各 run 的 `test_probs.pt` + `thresholds.json` 现算；
DIVE 读 `eval_results/dive/matrix_{main,aug}.json`（零重算）。

### 41.2 🔴 三口径并非三个独立的数：`macro` 的逐类格 ≡ `micro` 的逐类格

| 口径 | 逐类格 | 汇总列 |
|---|---|---|
| `micro` | 全测试集逐类 F1 | `metrics.micro_f1`（标签对级全局 F1） |
| `buggy` | **仅 `y.any(axis=1)` 的合约**上的逐类 F1 | `metrics.buggy_f1` |
| `macro` | **与 `micro` 逐格相同** | `metrics.macro_f1` |

**macro-F1 就是逐类 F1 的未加权平均** ⇒ 「macro 口径表」的正文与「micro 口径表」**逐位相同**，
差异只在汇总列。这是**数学恒等，不是重复计算**——保留它的价值仅在于让读者一眼看到汇总列的来源。
报告时若嫌冗余，可只出 micro/buggy 两套正文 + 一个 macro 汇总列。

⚠ 与 §30 的三条禁令一致：**`buggy` 口径（子集切片）≠「合约级二分类 F1」**（`any` 塌缩）。
后者把「有漏洞但报错了类」整类免罚，两者免罚方向相反，不得互换。

### 41.3 `evaluate_external.py` 增 `buggy_subset_prf`（纯增量）

DIVE 的 `matrix_*.json` 原先只有全量逐类 F1 与 `normal_subset_*`（干净合约 FPR），
**没有**漏洞子集口径。新增块与既有 `normal_subset_*` 对称：`buggy_subset_{0.5,val_thr}`
= `{n, buggy_f1, per_class, note}`，标量直接调 `metrics.buggy_f1`（**不另写实现**，§28 的教训）。

**DIVE 890 张图中 103 张全零** ⇒ 漏洞子集 **787** 张。⚠ 子集的逐类 support 与全量**逐位相同**
（干净合约七类真值全 0，切片不增减任何一类的正样本数）。

重跑：`matrix_main` 446.7 s、`matrix_aug` 415.7 s（各 22 臂 × 3 种子）。

### 41.4 🔴 DIVE 的 `mAP` 不可逐位复现（F1 可以）——GPU 末位不确定

重跑后按「同一臂同一种子的旧字段」对拍 09-19 的旧产物，结论**分裂**：

| 量 | 是否逐位相同 |
|---|---|
| 154 个逐类 F1 格（22 臂 × 7 类 @val_thr，对 `comparison.md` 表 3） | ✅ **0 格差异** |
| canon 全部 `micro_f1` / `macro_f1` / `per_class` / `subset_accuracy`（@0.5 与 @val_thr） | ✅ 逐位相同 |
| canon 的 `mAP` | ❌ **不同** |

为判定成因，在**同条件**下再跑一次 canon（`--runs-dir runs`，35.2 s），三次结果：

| 运行 | canon seed0 `mAP` |
|---|---|
| 2026-09-19（旧产物） | 0.410013975660806 |
| 本次矩阵重跑 | 0.410031329647214 |
| 本次单臂复核 | 0.410030999738092 |

⇒ **同条件重跑连自己都不复现，故不是代码差异**（已核对 `git diff HEAD -- scripts/metrics.py`：
`mean_average_precision` 仅入参校验改动，算法未动），而是
**GPU 推理（PyG RGCN 的 scatter/atomicAdd）末位不确定**：概率在末位漂移 ⇒
**阈值化后的 F1 稳健**（无翻转），而 **AP 用概率全序、不稳健**（漂移 ≈1.7e-5）。

**处置与含义**：
1. 引用 DIVE 的 `mAP` 时**须声明为单次运行值**；`micro/macro-F1` 可按「两次运行一致」表述。
2. 本表的 F1 主线**不受影响**。
3. `eval_results/dive/comparison.{json,md}` 已按新矩阵重生成以保一致：
   canon mAP 均值 0.397876 → **0.397866**（显示 4 位下不可见），**F1 列未变**。
4. ⚠ 这也意味着 `mAP` 不适合做**配对显著性检验的因变量**（噪声底比 F1 高一档）；
   而 §36 的 `cb_ft` n=9 复核同时报了 mAP，该结论的**方向**不受影响（效应量 +0.4366 远大于 1.7e-5），
   但若日后要做 mAP 的小效应判定，须先固定随机性（`torch.use_deterministic_algorithms` 或多次平均）。

---

## 39. 统计口径变更：主口径改为「最佳种子」（2026-09-20 用户裁定）

### 39.1 裁定内容

用户 2026-09-20 指示：**重新统计数据，采用数据集正典中效果最好的种子，而非平均指标**。

经 `AskUserQuestion` 两次裁定：

| 问题 | 裁定 |
| --- | --- |
| 「最好」按哪个指标判？ | **micro-F1@val_thr（论文主指标）** |
| 三组数字怎么摆？ | **最佳种子为主 + mean±std 附录** |

⇒ **① 取 seed2（正典 micro-F1@val_thr 0.7805）、② 取 seed1（1.0000）。**

### 39.2 两条必须写死的口径

1. **按主指标选种子**。若用 mAP 去挑种子、再拿它报 F1，就是口径错配——
   同一类问题本仓已在 `.ravel()`（§28）与 dropout 语义（§26）上栽过两次。
   ⚠ 这不是空谈：① 的三种指标**指向不同种子**——按 micro-F1@val_thr 是 seed2、
   按 mAP 是 seed0。故"按哪个指标选"必须显式声明。
2. **只从正典选一个种子，全部臂 + 内测列 + DIVE 列共用它**。
   - 若每个臂各挑自己的最佳种子 ⇒ 那是 **best-of-3**，臂间**不再可比**（比的是"谁运气好"）；
   - 若内测列与 DIVE 列用不同种子 ⇒ 同一行里"① 模型"其实是**两个不同的模型**。

### 39.3 代价与披露义务（**写论文时必须带上**）

本仓实测：**重跑抖动 ≈0.012，约为种子间 std 的 40%**（§36.4，根因 CUDA 归约顺序非确定性）。
故"最佳种子"里有相当一部分是**运气**。据此：

- **mean±std 表不作废**，降为**附录**保留（用户裁定），供答辩与质疑时取用；
- 「某干预有效/无效」的结论**仍然**必须同配对 ≥9 点（§26.7/§27.5）——
  **不得**用最佳种子的差值下这类结论；
- 已实测**换口径不改主结论**：DIVE 的"排序能力只保住 7.4%"在最佳种子下为 **6.8%**（§4.3 已记）。

### 39.4 代码改动

| 文件 | 改动 |
| --- | --- |
| `collect_ablation_results.py` | 新增 `best_seed_of()` / `render_best_seed()`；输出**表 A′/B′（最佳种子）为主口径**，原表 A–E 转为附录 |
| `collect_dive_comparison.py` | 新增逐种子明细载入；输出**表 1′.{micro@0.5, micro@val_thr, macro@0.5, mAP}**（四方并列、每语料单种子），原表 1/2 转附录 |

`best_seed_of()` 的实现与理由写在函数 docstring 里（含上述两条口径与代价），避免后人"简化"掉。

---

## 40. SolidiFI 层次二：合成注入节点排序评估（大纲 5.2 层次二）

### 40.1 新增脚本与产物

| 脚本 | 职责 | 产物 |
| --- | --- | --- |
| `map_solidifi_injections.py` | 注入位置（`buggy_logs/*.csv`）→ CFG 节点 | `products/solidifi/mapping/injection_nodes.json` |
| `evaluate_node_localization.py` | $s_v$/$a_v$/$g_v$ 的 P@k/R@k/IoU + 增量覆盖节点 | `eval_results/solidifi/node_localization_{main_seed2,aug_seed1}.json` |

图与特征由 `build_dive_external_set.py --dataset solidifi` 构建（该脚本 2026-09-20 泛化为同时服务
DIVE 与 SolidiFI——两者形态完全一样）。SolidiFI **不抽样**（全量 350），**不含 dos 类**（该组未注入），须披露。

### 40.2 🔴 事故：手册 §10.2 第 9 条的映射规则**按字面实现是错的**（已修，手册须同步）

**现象**：按手册写的「`loc` 落在 `line_start ≤ loc ≤ line_end` 的 CFGNode」实现后，
① 的三类分数 P@5 **全为 0**，且 18 个"注入节点"**全部是 ENTRYPOINT**。

**根因**：日志的 `loc` 是**注入代码块的首行**，`length` 给出块长。实测 `1_buggy_1`：

| 日志 | 源码实际内容 | 真正的漏洞语句 |
| --- | --- | --- |
| `loc=22, length=4` | 22–25 行：`function transferTo_txorigin7(...) {` / `require(tx.origin == ...);` / `to.call.value(amount);` / `}` | **第 23 行**（= loc+1） |
| `loc=67, length=4` | 67–70 行 | 第 68 行 |

⇒ **单点 `loc` 落在函数签名那一行，映射到 ENTRYPOINT**；而模型与先验的高分节点全是 EXPRESSION
⇒ 评估结果是**人为造出来的**。`length` 字段本就是为此提供的，**不用即错**。

**修**：改为**行域** `[loc, loc+length-1]` 与节点 `[line_start,line_end]` **求重叠**，仍取区间最小者。

**修后实测**：未映射率 **32.92% → 0.04%**（4/9369）；且**未映射率不再有类别偏差**
（修前 access_control 0% vs reentrancy 71.3%，修后各类均 ≈0%）——修前的评估**同时被类别偏倚污染**。

⚠ **手册 §10.2 第 9 条与大纲对应措辞须同步更正**（属"大纲没有的后处理"，按 AGENTS.md 须同步文档）。

### 40.3 结果（最佳种子：① seed2 / ② seed1；k = 5 / 10 / 10%·N）

**随机基线 P@k = 0.1090**（每合约 buggy 节点占比的均值，与 k 无关）——**必须先减基线才可读**。

| 语料 | k | $s_v$ P@k | $a_v$ P@k | $g_v$ P@k | $s_v$−随机 | $a_v$−随机 | $g_v$−随机 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ① 主库 | 5 | 0.0983 | 0.0406 | **0.1320** | −0.0107 | **−0.0684** | **+0.0230** |
| ① 主库 | 10 | 0.1040 | 0.0431 | 0.1097 | −0.0050 | −0.0659 | +0.0007 |
| ① 主库 | p10 | 0.1187 | 0.0591 | 0.0793 | +0.0097 | −0.0499 | −0.0297 |
| ② 增强集 | 5 | 0.0983 | 0.1091 | 0.0446 | −0.0107 | +0.0001 | −0.0644 |
| ② 增强集 | p10 | 0.1187 | 0.1485 | 0.0991 | +0.0097 | +0.0395 | −0.0099 |

**三条读数**：

1. **$s_v$ 两语料逐位相同**（0.0983/0.1040/0.1187）——静态先验与模型/编码器无关，这是一条**内部一致性检验**。
2. **$a_v$（模型分数）在 ① 上远低于随机**（−0.068 @5）、在 ② 上 ≈ 随机。
   ⇒ 大纲要求的那句话必须写：**「图传播未带来额外节点定位收益」**——这里甚至是**负收益**。
3. **$g_v$ 只在 ① 的 k=5 略高于随机**（+0.023），其余均低于随机。

**逐类（① 模型 P@5）**：只有 `arithmetic` 表现好（$g_v$ 0.416 / $a_v$ 0.284 / $s_v$ 0.144）；
`uncheck` 次之（$g_v$ 0.208）；**`access_control` 与 `front_running` 三类分数全为 0.000**；
`time_manipulation` 只有 $s_v$ 命中（0.240）。⇒ 定位能力**高度集中于 `arithmetic`**。

**增量覆盖节点**（$a_v$ 的 TopK 中 $s_v$ 排名在后 50% 的个数）：@5 = 1.39（①）/ 1.16（②）。
⇒ $a_v$ 确实引入了 $s_v$ 之外的节点，但**那些节点不是注入节点**（这正是 $a_v$ 低于随机的原因）。

### 40.4 ⚠ 一处必须披露的混淆：合约级预测正确率

| 模型 | 预测与真值标签集**完全相同**的合约数 |
| --- | --- |
| ① 模型 | **1 / 350** |
| ② 模型 | **300 / 350** |

① 模型只在 1 个合约上预测正确 ⇒ **大纲要求的"预测正确/错误分开统计"在此退化**
（349/350 全在"错误"子集里），须如实说明而不能假装做了分层。

根因与 DIVE 同源：① 的训练语料 326/453 是**全零合约**，模型学会了"基本啥都没有"，
而 SolidiFI 合约是**重度注入**的（每合约 17–45 处）。这是**类别先验错配**的又一次体现，
不是定位能力的独立证据。

### 40.5 诚实声明（大纲原文，须随结果进论文）

SolidiFI 是**语法级注入**，$s_v$ 在多数情况下会直接命中注入位置，故本评估主要反映**静态先验的准确性**，
而非图神经网络的深层逻辑发现能力。**不得**据此声称真实漏洞根因定位能力。
实测进一步显示：连静态先验都只在 `time_manipulation`/`uncheck`/`arithmetic` 上有效。
