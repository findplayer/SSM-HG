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
