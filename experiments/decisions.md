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
