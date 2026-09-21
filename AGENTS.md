# SSM-HG 项目约定

CFG 中心异构图 + RGCN 的智能合约七类漏洞多标签检测，流水线为 M1–M5。

只能读取该目录下的内容，不允许越界！！！目录地址： /home/saumarez/projects/deep-learning/SSM-HG

> 唯一例外：**只读**的磁盘空间检查（`df -h /mnt/c`、只读 PowerShell 查询、`fsutil` 查询），见「磁盘空间（硬规则）」。除此之外一律不得越界；该例外**只读**，不得在仓库外写入、删除或改名任何东西。

## 权威文档（冲突时按此优先级）

1. `研究点一细化大纲改II.docx` —— 论文大纲，最高权威
2. `论文开发手册.md` —— 实施细节（§3.2 路径速查、§12 常见错误清单）
3. `experiments/decisions.md` —— M5 实验决议 v5（部分条目已被大纲 `改II` 取代，冲突时以大纲为准）

实现前先读对应章节，不要凭常识补全设计。

## 运行环境

- 一律在 **conda base** 环境运行：slither 0.11.5、solc-select、python 3.11、torch 2.0.1+cu118（GPU 版，RTX 4070；无 CUDA 时自动回退 CPU）、torch_geometric 2.7.0（含 torch-scatter/sparse/cluster 的 CUDA 扩展）、transformers 4.29.2。
- 训练/推理设备：`train.py`/`evaluate.py` 自动 `cuda if available else cpu`，数据经 `collate(..., device=...)` 上设备、模型 `.to(device)`；无 GPU 时行为与 CPU 版完全一致。
- 脚本统一**从仓库根目录**运行：`python scripts/xxx.py`。不要 `cd scripts`，也不要从根目录直接 `import` 脚本。
- 测试：`pytest tests/ -q`，或 `python tests/test_model_smoke.py`。
- 批量运行前先 `--help` 或显式传参确认，不要依赖默认路径盲跑。

## 磁盘空间（硬规则）

- **C 盘可用空间任何时候必须 ≥ 8 GB** —— 深度学习程序、WSL、Claude Code 三者共同受此约束。低于阈值时**先回收、再干活**，不得「先跑起来再说」。

## 终端与输出

- 输出可能很长的命令一律截断或先落盘：`... 2>&1 | tail -50`；大批量脚本的输出重定向到对应数据集的 `raw/logs/`（如 `products/alldata/raw/logs/`），再用 `tail` / `grep` 按需查看。不要把全量进度直接打印到终端。
- Git 的长输出命令一律加 `--no-pager`（如 `git --no-pager log --oneline -20`），避免进入 `less` 分页器等待按键。
- 不要运行交互式命令（需要 y/n、密码、分页器）。必要时改用非交互参数（如 `-y`、`--yes`）。
- 长跑脚本会触发"命令可能在等待输入"的自动通知，每次通知都会把整段终端输出重新注入上下文。因此长跑任务要减少输出量，并避免在运行期间反复读取产物。

## 数据边界（硬规则）

- 只读、绝不写入或改名（共 5 个）：`alldata(readonly)/`、`alldata_augmentation/`、`DIVE/`、`SolidiFI/`、`MVD-HG-dataset/`。
  - 其中 **`alldata_augmentation/` 已在 `.gitignore` 中**（2026-09-14）：它只读、可由 `MVD-HG-dataset` 派生重建，不纳入版本管理——「提交全部」不会把它扫进去。其余 4 个只读源历史上已入库，不在忽略之列。
- 中间产物只能写到 `products/<数据集>/` 以及 `runs/`、`eval_results/`。
  🔴 **各区的形态（2026-09-20 补全，§37/§38 起不再只是三件套）**：
  `products/alldata/{raw, graphs, graphs_ft/ss{S}, graph_variants, splits}`、
  `products/augmentation/{raw, graphs, graphs_ft/ss{S}, graph_variants, splits}`、`products/dive/…`（同上 + `graphs_ft_aug/ss{S}`、`src_stage/`）、
  `products/solidifi/…`。**把新特征写进 `graphs_ft/ss{S}` 不算越界**——那正是 §37 的正典产物区。
  🔴 **2026-09-21（任务2）新增形态**：`products/alldata/graphs_ft_buggy/cb_ft_ss{S}/`（**含 `buggy_*` 的新池 497
  划分**对应的编码器特征树）、`runs/codebert_ft_buggy/ss{S}/encoder/`（其编码器）、
  `runs/codebert_ft_probe/ss2/`（epoch 探针，隔离）、`runs/buggy_canon/seed{S}/`（新正典的 GNN 产物）、
  `eval_results/baseline/`（传统工具基线）、`eval_results/ensemble/`（多种子集成）。
  这些**一律另开目录、绝不覆盖** §37 正典的 `graphs_ft/`、`runs/codebert_ft/`、`runs/seed{0,1,2}/`。
- `alldata_augmentation/` 是 **MVD-HG 论文增强集**，与 `alldata(readonly)` **并行的第二个数据集**（2026-09-14 置入）：1780 个**扁平** `.sol` + 9026 条 7 维标签（同类别序）。**2026-09-16 裁定：两组结果集并存**（`decisions.md` §23、总表 `results.md` §0）——① 主库（池 453，真实部署合约、含天然极稀缺类）与 ② 增强集（池 1774，单标签、正样本充足）**各自独立完整、并列呈现**；**禁止**跨组比较绝对值、**禁止**合并成一个数字、**禁止**用 ② 的数字宣称 ① 的问题已解决。
- ⚠ **该集的标签必须用修正版**：只读源里的 `contract_labels.json` 有 298 个 `{类}__buggy_N`（同名不同内容）被并集规则推成 `1111111`，正样本 59% 虚高。**正典标签 = `products/augmentation/contract_labels_repaired.json`**（`scripts/repair_augmentation_labels.py` 生成，逐类 7383→2997）；只读源原文件仅留痕。该集是**单标签**数据集（每条非零恰一类），勿套用主库多标签叙事。详见 `experiments/decisions.md` §19.3.1。
- 路径含空格/括号（`alldata(readonly)/`、`DIVE/Source codes/`），命令中必须加引号；产物区 `products/…` 无空格。
- `products/alldata/raw/` 与 `products/alldata/graphs/` 存放约 581 个合约的批量产物（原 `raw/`、`Heterogeneous graphs/`，2026-09-12 迁入），不要整目录列举或全量读取，按需读单个文件。
- 不要提交超过 100 MB 的文件。`DIVE/Code-based.csv`（147 MB）已在 `.gitignore` 中，仅保留在本地。
- **复现所需的最小集必须入库**（2026-09-16 起，此前被整目录忽略是错的）：
  - `products/**/raw/filter_report.txt`（样本过滤透明性声明）与 `products/alldata/graphs/ir_cat.json`（**冻结 IR 类别字典 = 跨语料语义锚点**，几 KB）——两者的父目录仍是内容式忽略 + `!` 白名单纳入，改动 `.gitignore` 时**不要**把父目录改回目录式忽略（目录式排除无法用 `!` 取反）。
  - ⚠ **`.gitignore` 的忽略规则按目录形态枚举，新增形态必须同步补规则**（2026-09-20）：
    原规则只覆盖 `raw/` 与 `graphs/`。§37 起新增了 `graphs_ft/`、`graphs_ft_aug/`、
    `graph_variants/`、`src_stage/` 四种形态，**不被任何规则匹配** ⇒ `git status` 全部列为未跟踪、
    `git add -A` 会一次性纳入**约 16 GB**（② `graphs_ft` 单个 5.0 GB）。
    **写法有坑**：`dir/*` 与 `dir/` 都**不能**配合 `!` 白名单（前者把子目录本身也排除，
    git 不再往里走；后者的目录式排除无法取反）。可用写法 = `dir/**` + `!dir/**/`（尾斜杠 = 仅目录）
    再 `!` 具体文件名。现只纳入各变体的 `variant.json`（自述文件，**40 个 / 内容合计 31 KB**，
    2026-09-20 实测；旧载「41 个 / 164 KB」计数与体积都不准）。
    SolidiFI（阶段 G）新增产物时照此办理。
  - 🔴 **第二个洞（2026-09-20 发现并已补）**：`runs/codebert_ft/`（§37 正典的**微调编码器**）
    同样**不被任何规则匹配** —— 实测 **2.9 GB**，含 6 份 `pytorch_model.bin` 各 **498 MB**
    （单文件即超本文「不提交超过 100 MB 的文件」硬规则）。根因：上面那条 `runs/**/*.pt` **只认 `.pt`**，
    `.bin`/`tokenizer.json`/`vocab.json` 全部漏网。**已按 `graphs_ft` 的同款写法补规则**，
    只纳入 4 类自述/审计边车（`corpus.json` 是「编码器属于哪个语料」的硬校验锚点，
    `build_graph_variant.py` / `build_dive_external_set.py` 缺它即硬失败）⇒ `git add -A` 由
    2.9 GB 降为 **30 个小文件**。权重可由 `scripts/finetune_codebert.py` 重建（① 848 s/种子、② 3797 s/种子）。
  - 🔴 **第三个洞（2026-09-21 发现并已补）**：字面量规则**在新形态上必然失效**。
    任务2 新增了 `products/alldata/graphs_ft_buggy/`、`runs/codebert_ft_buggy/`、
    `runs/codebert_ft_probe/` 三个目录，**字面量规则 `graphs_ft` / `runs/codebert_ft/` 一个都匹配不到**
    ⇒ `git add -A --dry-run` 实测 **42 个文件 / 958.5 MB**，其中两份 `pytorch_model.bin` 各 **475 MB**。
    **修法 = 把字面量改成前缀通配**：`products/**/graphs_ft*/**`、`runs/codebert_ft*/**`
    （连带旧的 `graphs_ft_aug` 也被覆盖，规则反而更少）。修后实测 **34 个文件 / 1.02 MB**。
    ⇒ **结论（写进习惯）**：**凡给某类目录写忽略规则，一律用前缀通配而不是字面量**——
    本仓同一形态已连踩三次（`graphs_ft` → `codebert_ft` → 本轮），三次根因都是"新增了一个同前缀目录"。
  - 🔴 **自检口径（三次同类洞的教训）**：**「补 `.gitignore` 规则」与「改本段/`项目组织架构.md` 的说明文字」是两件事**，
    前两次都只做了前者。**新增任何产物目录形态时，必须同时做三件事**：
    (a) `git check-ignore -v <新目录下的样本文件>` 实测被忽略（**不能只看规则存在**）；
    (b) `git add -A --dry-run` 数一遍实际纳入的文件，并对每个文件查大小，确认没有 >100 MB；
    (c) 更新本段与 `项目组织架构.md` 的 `.gitignore` 说明。
    只做 (a) 仍会漏 —— `runs/` 侧从未做过同类排查，`codebert_ft` 就是这么漏的；
    而**做 (b) 才抓到了第三次**（前两次都是事后才发现）⇒ **(b) 是三步里唯一能兜住字面量失效的一步**。
    ⚠ **该字典只有一份（在 ① 下）**，原文写的 `products/**/graphs/ir_cat.json` 不精确（2026-09-18 更正）：② 的 `graphs/` 里**没有**它，② 的正典当初传的就是 ① 这份（证据见 `decisions.md` §35.4）。**不要给 ② 补建**——那会造出两个可能漂移的来源。所有变体构建一律经 `build_graph_variant.frozen_categories()` 取它（缺文件即硬失败，避免 m3 静默回退全库扫描）。
  - `runs/**/best.pt`（`evaluate.py` 的唯一权重输入）+ `val_best_probs.pt`/`test_probs.pt`（推理缓存）→ 使已报告指标可**离线重算、无需重训**；全库 **约 1.5 GB / 1125 个文件**（§38 后 run 数增至 150+；2026-09-16 时为 115 MB / 24 run）、单文件 ≤4.77 MB。`last.pt` 仍排除（仅断点续训用，入库会使体积翻倍）。

## 语义锁死项（最容易写错）

- 🔴 **正典训练输入（2026-09-19 §37 起）= `products/<语料>/graphs_ft/ss{S}`**（微调 CodeBERT）。
  ⚠ **路径含划分种子**：`ss{S}` **必须**与 `--split-seed S` 配对（否则 `seed2` 会拿 `ss0` 的编码器配 `split_seed2`）。
  `products/<语料>/graphs` 是**冻结**编码器树，**现仅作 `cb_frozen` 消融臂输入，不得再写作正典**。
  这是本仓第三次全量作废的根因，凡涉及"正典 graph_dir"一律以本行为准。
- 标签顺序固定：`access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`（reentrancy 下标为 4）。
- `_pyg.pt` 是只读的纯结构（`x` 为 N×1 占位，永不改写）；`_feat.pt` = M3 的**拼接前通道字典**（schema v2：`struct`/`type_id`/`sv` + 逐通道 sha256），是唯一模型输入载体；融合（Embedding+MLP）与全部掩码在 `model.NodeFuser`，`dataset.py` 只负责组合（含 `_cb.pt` 行对齐）、不再过 MLP、不重算、不做掩码。
- M1 的 $s_v$ 是输入特征，不是标签；$a_v$ 是节点可疑度/解释信号，不是节点真值。
- `CALLBACK_RISK` 是启发式边，不是真实跨合约调用图；主实验默认保留，不得降级为节点特征。
- 训练与推理的 Dropout、先验 dropout 行为不同，不要混用。
- M5 划分：唯一合约、固定种子 8:1:1 + **覆盖约束校正**（`--strategy constrained` 默认；`random` 隔离输出到 `random_snapshot/`）：C1 验证+内部测试合计每类正样本 ≥ 该类正样本总数的30%，C2 val/test 各自每类 ≥1；三种子构造达标（2026-09-12，去重后替换 18/16/12 个，见 `coverage_swaps_seed*.txt` 与 `split_report.json`；预去重 18/19/17 见 decisions §12 历史记录）；主种子 seed0（用途定位见 `experiments/decisions.md` §12）；**训练种子与划分种子分离**。
- 阈值只在验证集搜索；测试集同时报告固定 0.5 与验证集阈值两套结果。
- 消融分层：边消融在 `dataset.py` 按 edge_type 过滤（`--drop-edges`/`--drop-ast`，零重跑）；特征消融（去 $s_v$/CodeBERT 单通道/结构分组）在 `model.NodeFuser` 的 `AblationConfig`（通道级、零重跑，无文件变体）；模型消融走 `model.py`/`train.py` 开关。仅 CALLBACK_RISK 上限 4/不限制变体需重跑 M2（`--callback-limit 0`）。
- 跨数据集（DIVE/SolidiFI）M3 必须传 `--categories products/alldata/graphs/ir_cat.json` 冻结 IR 字典，否则列宽/类别语义漂移、与已训练模型不兼容。
- **输出头 `--head {multi,binary}`**（默认 `multi`，正典臂逐字节不变；见 `decisions.md` §31）：
  - `binary` = 单头「有没有漏洞」：头 7→1、标签 `any(targets)`、损失单类 BCE、早停/调度判据改 **val 二分类 AP**。
    **标签塌缩只发生在 `dataset.stack_labels` 一处**——`build_index`/划分/标签文件/通道哈希全部保持 7 维不动。
    输入特征、`s_v` 先验（本就是 `(N,1)` 标量）、边、结构**逐字不变** ⇒ 唯一变量是输出空间
    （同 seed 下 12/12 共享张量逐位相同，机检于 `tests/test_binary_arm.py`）。
  - 🔴 **`[N,1]` 的 `type_of_target` 是 `binary`**，`average="micro"` 随即**恒等于 accuracy**——即 §28 换个入口重现。
    故：多标签入口经 `_as_2d_multilabel()` **对单列报错**、二分类入口对多列报错；二分类指标一律
    **由混淆计数直接算**（`metrics.binary_*`），完全不经 sklearn 的 `average=` 分派；
    `evaluate.compute_binary_report` 键名一律 `binary_*`（读 `micro_f1` 会 KeyError 而非拿到 accuracy）。
  - **新增身份类 CLI 键必须登记进 `run_guard.IDENTITY_DEFAULTS`**（有漂移守卫测试），否则"用新键写进旧目录"
    会被守卫放行并**无声覆盖**（§31.3 修掉的那个洞）。
  - 配对分析用 `val_binary_*` 族（**两条臂都算**），合法性来自 `max_c p_c >= t ⇔ any_c(p_c >= t)`（已机检）。

## 改动原则

- **最小化修改，只改必要部分**：不重构无关代码。
- 若进行大纲没有的后处理，必须输出明确理由，并同步修改大纲和开发手册。
- 审查外部或 AI 建议时：先判断是否与大纲冲突；合理的吸收，不合理的明确反驳并给出理由，不要照单全收。
- 全量重跑代价高（M2 全量重跑会带动下游 581 个图）。能用 `--only <图前缀>` 或 `--variant` 小样验证就先小样验证。
- 等批量脚本跑完再校验产物：脚本会先删旧文件再逐个重生成，中途读取会得到"缺失/归零"的假象。
- **换数据集/做消融必须改道输出目录，四处默认值全指向正典区**，且**四处均已有守卫**（2026-09-16，逻辑统一在
  `scripts/run_guard.py`，测试 `tests/test_run_guard.py`）：
  `train.py`→`runs`、`make_splits.py`→`products/alldata/splits`、`m3_build_features.py`→`products/alldata/graphs`
  三者在"本次参数与产出该目录的那次不同"时报错退出（需 `--overwrite`）；
  `generate_all_ast_cfg_dfg.sh` **开工先 `find -delete` 清空目标目录**，故目标非空时要求 `SSMHG_ALLOW_WIPE=1`（否则 exit 2）。
  消融一律**新开 `--out-dir`**（如 `runs/ablation/<item>`），不要加 `--overwrite`。安全模板见手册 §12 第 51 条。

## 记录与沟通

- 回复与文档统一使用中文。
- 实验决议与口径变化写入 `experiments/decisions.md`；接口变更同步 `docs/M4_interface.md`；目录结构变化同步 `项目组织架构.md` 与 `论文开发手册.md` §3.2。开发计划变更同步 `论文开发手册.md`；
- 需要裁定的要给出几种方案的区别、优劣、产物差异、对论文的影响，便于裁定。
- 提交前确认没有把只读数据源或超过 100 MB 的文件加入提交。

## 当前进度

- 见 `log.md`（开发手册及项目组织架构修改日志、当前进度）。