# SSM-HG 项目约定

CFG 中心异构图 + RGCN 的智能合约七类漏洞多标签检测，流水线为 M1–M5。

只能读取该目录下的内容，不允许越界！！！目录地址： /home/saumarez/projects/deep-learning/SSM-HG

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

## 终端与输出

- 输出可能很长的命令一律截断或先落盘：`... 2>&1 | tail -50`；大批量脚本的输出重定向到对应数据集的 `raw/logs/`（如 `products/alldata/raw/logs/`），再用 `tail` / `grep` 按需查看。不要把全量进度直接打印到终端。
- Git 的长输出命令一律加 `--no-pager`（如 `git --no-pager log --oneline -20`），避免进入 `less` 分页器等待按键。
- 不要运行交互式命令（需要 y/n、密码、分页器）。必要时改用非交互参数（如 `-y`、`--yes`）。
- 长跑脚本会触发"命令可能在等待输入"的自动通知，每次通知都会把整段终端输出重新注入上下文。因此长跑任务要减少输出量，并避免在运行期间反复读取产物。

## 数据边界（硬规则）

- 只读、绝不写入或改名（共 5 个）：`alldata(readonly)/`、`alldata_augmentation/`、`DIVE/`、`SolidiFI/`、`MVD-HG-dataset/`。
  - 其中 **`alldata_augmentation/` 已在 `.gitignore` 中**（2026-09-14）：它只读、可由 `MVD-HG-dataset` 派生重建，不纳入版本管理——「提交全部」不会把它扫进去。其余 4 个只读源历史上已入库，不在忽略之列。
- 中间产物只能写到 `products/<数据集>/`（`products/alldata/{raw,graphs,splits}`、`products/augmentation/{raw,graphs,splits}`、`products/dive/…`、`products/solidifi/…`）以及 `runs/`、`eval_results/`。
- `alldata_augmentation/` 是 **MVD-HG 论文增强集**，与 `alldata(readonly)` **并行的第二个数据集**（2026-09-14 置入）：1780 个**扁平** `.sol` + 9026 条 7 维标签（同类别序）。**2026-09-16 裁定：两组结果集并存**（`decisions.md` §23、总表 `results.md` §0）——① 主库（池 453，真实部署合约、含天然极稀缺类）与 ② 增强集（池 1774，单标签、正样本充足）**各自独立完整、并列呈现**；**禁止**跨组比较绝对值、**禁止**合并成一个数字、**禁止**用 ② 的数字宣称 ① 的问题已解决。
- ⚠ **该集的标签必须用修正版**：只读源里的 `contract_labels.json` 有 298 个 `{类}__buggy_N`（同名不同内容）被并集规则推成 `1111111`，正样本 59% 虚高。**正典标签 = `products/augmentation/contract_labels_repaired.json`**（`scripts/repair_augmentation_labels.py` 生成，逐类 7383→2997）；只读源原文件仅留痕。该集是**单标签**数据集（每条非零恰一类），勿套用主库多标签叙事。详见 `experiments/decisions.md` §19.3.1。
- 路径含空格/括号（`alldata(readonly)/`、`DIVE/Source codes/`），命令中必须加引号；产物区 `products/…` 无空格。
- `products/alldata/raw/` 与 `products/alldata/graphs/` 存放约 581 个合约的批量产物（原 `raw/`、`Heterogeneous graphs/`，2026-09-12 迁入），不要整目录列举或全量读取，按需读单个文件。
- 不要提交超过 100 MB 的文件。`DIVE/Code-based.csv`（147 MB）已在 `.gitignore` 中，仅保留在本地。
- **复现所需的最小集必须入库**（2026-09-16 起，此前被整目录忽略是错的）：
  - `products/**/raw/filter_report.txt`（样本过滤透明性声明）与 `products/**/graphs/ir_cat.json`（**冻结 IR 类别字典 = 跨语料语义锚点**，几 KB）——两者的父目录仍是内容式忽略 + `!` 白名单纳入，改动 `.gitignore` 时**不要**把父目录改回目录式忽略（目录式排除无法用 `!` 取反）。
  - `runs/**/best.pt`（`evaluate.py` 的唯一权重输入）+ `val_best_probs.pt`/`test_probs.pt`（推理缓存）→ 使已报告指标可**离线重算、无需重训**；全库 115 MB、单文件 4.77 MB。`last.pt` 仍排除（仅断点续训用，入库会使体积翻倍）。

## 语义锁死项（最容易写错）

- 标签顺序固定：`access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`（reentrancy 下标为 4）。
- `_pyg.pt` 是只读的纯结构（`x` 为 N×1 占位，永不改写）；`_feat.pt` = M3 的**拼接前通道字典**（schema v2：`struct`/`type_id`/`sv` + 逐通道 sha256），是唯一模型输入载体；融合（Embedding+MLP）与全部掩码在 `model.NodeFuser`，`dataset.py` 只负责组合（含 `_cb.pt` 行对齐）、不再过 MLP、不重算、不做掩码。
- M1 的 $s_v$ 是输入特征，不是标签；$a_v$ 是节点可疑度/解释信号，不是节点真值。
- `CALLBACK_RISK` 是启发式边，不是真实跨合约调用图；主实验默认保留，不得降级为节点特征。
- 训练与推理的 Dropout、先验 dropout 行为不同，不要混用。
- M5 划分：唯一合约、固定种子 8:1:1 + **覆盖约束校正**（`--strategy constrained` 默认；`random` 隔离输出到 `random_snapshot/`）：C1 验证+内部测试合计每类正样本 ≥ 该类正样本总数的30%，C2 val/test 各自每类 ≥1；三种子构造达标（2026-09-12，去重后替换 18/16/12 个，见 `coverage_swaps_seed*.txt` 与 `split_report.json`；预去重 18/19/17 见 decisions §12 历史记录）；主种子 seed0（用途定位见 `experiments/decisions.md` §12）；**训练种子与划分种子分离**。
- 阈值只在验证集搜索；测试集同时报告固定 0.5 与验证集阈值两套结果。
- 消融分层：边消融在 `dataset.py` 按 edge_type 过滤（`--drop-edges`/`--drop-ast`，零重跑）；特征消融（去 $s_v$/CodeBERT 单通道/结构分组）在 `model.NodeFuser` 的 `AblationConfig`（通道级、零重跑，无文件变体）；模型消融走 `model.py`/`train.py` 开关。仅 CALLBACK_RISK 上限 4/不限制变体需重跑 M2（`--callback-limit 0`）。
- 跨数据集（DIVE/SolidiFI）M3 必须传 `--categories products/alldata/graphs/ir_cat.json` 冻结 IR 字典，否则列宽/类别语义漂移、与已训练模型不兼容。

## 改动原则

- **最小化修改，只改必要部分**：不重构无关代码。
- 若进行大纲没有的后处理，必须输出明确理由，并同步修改大纲和开发手册。
- 审查外部或 AI 建议时：先判断是否与大纲冲突；合理的吸收，不合理的明确反驳并给出理由，不要照单全收。
- 全量重跑代价高（M2 全量重跑会带动下游 581 个图）。能用 `--only <图前缀>` 或 `--variant` 小样验证就先小样验证。
- 等批量脚本跑完再校验产物：脚本会先删旧文件再逐个重生成，中途读取会得到"缺失/归零"的假象。
- **换数据集/做消融必须改道输出目录，四处默认值全指向正典区**（2026-09-16 起 `train.py` 已默认拒绝覆盖）：
  `train.py`→`runs`、`make_splits.py`→`products/alldata/splits`、`m3_build_features.py`→`products/alldata/graphs`、
  `generate_all_ast_cfg_dfg.sh` **开工先 `find -delete` 清空目标目录**（用默认目录跑＝删掉主库 raw 产物）。
  安全模板见手册 §12 第 51 条。

## 记录与沟通

- 回复与文档统一使用中文。
- 实验决议与口径变化写入 `experiments/decisions.md`；接口变更同步 `docs/M4_interface.md`；目录结构变化同步 `项目组织架构.md` 与 `论文开发手册.md` §3.2。开发计划变更同步 `论文开发手册.md`；
- 需要裁定的要给出几种方案的区别、优劣、产物差异、对论文的影响，便于裁定。
- 提交前确认没有把只读数据源或超过 100 MB 的文件加入提交。

## 当前进度（2026-09-15）

- **★ 2026-09-16 裁定：两组结果集并存**（`decisions.md` §23、总表 `results.md` §0）。两组**各自独立完整、并列呈现，禁止跨组比较绝对值或合并成一个数字**：

  | | ① 主库 `alldata(readonly)` | ② 增强集 `alldata_augmentation` |
  | --- | --- | --- |
  | 池 | **453**（590 − 90 buggy − 47 去重） | **1774**（0 剔除） |
  | 逐类正样本 | 17/15/**6**/**4**/31/**5**/50 | 200/251/143/171/182/106/361 |
  | 标签结构 | 多标签 | **单标签** |
  | 跨划分近重复对 | 69/68/76（已披露） | **0/0/0** |
  | micro-F1 @0.5 | **0.8954±0.0211** | **0.9744±0.0128** |
  | micro-F1 @val_thr | **0.9296±0.0090** | **0.9847±0.0077** |
  | mAP | **0.2980±0.0127** | **0.9804±0.0090** |

  ① 回答「真实部署合约（含天然极稀缺类）上能检出什么」，宏观指标低是**数据事实**、非方法失效；② 回答「训练信号充足时的能力上限」，**不得**解读为 ① 的问题已解决。三条例外臂（`runs/neardup/`、`runs/withbuggy/`、`runs/augmentation_dedup/`）均不进两表。
- 已完成：M1–M4；`scripts/` 中 `dataset.py`、`make_splits.py` 已实现（2026-09-12：覆盖约束校正 `--strategy constrained`（默认）+ `coverage_swaps_seed*.txt`、`splits.csv`、split metadata；三种子 C1/C2 构造达标，主种子 seed0）。
- **2026-09-16 第二数据集 `alldata_augmentation` M1–M5 全链跑通（见 `experiments/results.md` §6）**。产物隔离在 `products/augmentation/`、`runs/augmentation{,_dedup}/`；**主库数字与产物零改动**。
  - 语料：池 **1774**（0 精确重复、0 buggy 剔除、0 标签未匹配；全零 362、多标签 2、**单标签**语料），逐类正样本 106–361。**M3 在 GPU 上全量重建**（`--device cuda --force`，1774 图 49 分 10 秒，`cb_reused=0/1774`）。
  - 跨语料契约逐项相等（`D_struct=30`、`struct_layout`、schema v2、role_names），不一致 0 个；节点合计 463,264。
  - **两臂均零泄漏**（连通分量簇原子 0/0/0；近重复去重按构造 0），覆盖校正替换 **0** 次：
    | 臂 | 池 | micro-F1@0.5 | micro-F1@val_thr | macro-F1@val_thr | mAP |
    | --- | --- | --- | --- | --- | --- |
    | **簇原子（正表）** | 1774 | **0.9744±0.0128** | **0.9847±0.0077** | 0.9415±0.0305 | 0.9804±0.0090 |
    | 近重复去重 | 1400 | 0.9786±0.0150 | 0.9850±0.0092 | 0.9416±0.0420 | 0.9844±0.0116 |
  - **C1 在 aug 上算术不可行**（正样本率 79.7% > 66.7% = s/r，与种子无关），已 `--min-pos-ratio 0` 关闭 C1、保留 C2；
    该语料每类 val/test support ≥8（最低 time_manipulation val 9 / test 12），C1 的目的由数据本身满足。证明与替代方案见 `decisions.md` §22。
  - 计时（`config.json::timing`，跨工具对比用，GPU）：簇原子臂 3 种子 wall 348.3 s / train 258.4 s、graphs/s 579–630。
  - **披露 5 项**（`results.md` §6.7）：去注释源使 `_cb.pt` 文本口径与主库不同；aug 的 M3 在 GPU 构建；单标签语料勿套多标签叙事；C1 关闭；该语料显著更"易"（0.97 vs 主库 0.86），不能解读为主库问题已解决。
- **2026-09-15 泄漏处置（见 `experiments/decisions.md` §21）**：主库现行划分的同源泄漏已量化并给出可证零泄漏对照臂。
  - 现行划分跨划分近重复对 seed0/1/2 = **69/68/76**（最高 Jaccard **1.00**）→ §1.2 的 micro-F1 0.8954 **含泄漏**。
  - 新增 `near_dup_clusters.py --cluster-mode {complete,components}`：`complete`（默认，全链接）报"紧密孪生"；
    **`components`（连通分量）用于划分防泄漏，跨划分近重复对可证恒为 0**（主库实测 0/0/0，C1/C2 仍 7/7 达标，
    分量最大 15）。⚠ §20.2"必须全链接、不能用并查集"仅对**未加 Jaccard 归一化的初版**成立，勿误读为矛盾。
  - **零泄漏对照臂 `runs/neardup/`（划分 `products/alldata/splits/neardup_snapshot/`）**：
    micro-F1@0.5 **0.8561±0.0379**（现行 0.8954±0.0211，**−3.9 点**）、@val_thr 0.9397±0.0095（+0.0101）、
    mAP 0.3033（+0.0054）。结论：泄漏的抬升集中在**固定 0.5 工作点**；**主库正典数字口径不变**，
    是否升为正典待裁定。
  - 审计入口：`python scripts/near_dup_clusters.py --print --audit-split <seed0,seed1,seed2> --audit-out <out.json>`。
- **2026-09-15 M3 设备与缓存加固**：`m3_build_features.py` 新增 `--device {cpu,cuda,auto}`（**默认 cpu，主库路径逐字节不变**），
  GPU 实测 **6.2×**（44.6→7.2 ms/节点）、数值差 max|Δ|=5.6e-05；新增 `cache_usable()`（0 字节残缺文件视为未缓存）
  与 `atomic_torch_save()`（临时文件 + `os.replace`）——**因本机 WSL 整机会重启**（2026-09-15 20:31 腰斩 M3，留下 2 个 0 字节缓存）。
  `train.py`/`evaluate.py` 新增显式 `--label-file`/`--label-key-mode` + 划分内 base 标签硬校验；`train.py` 把
  `label_source`（路径+sha256+key_mode）记入 config；`evaluate.py` 按 CLI→环境变量→**checkpoint 记录**回退，保证同源。
- 已完成（2026-09-12）：M5 主体 `scripts/{metrics,train,evaluate}.py` 落地，train/evaluate/summary 全链路 smoke 通过（`pytest tests/` 现行 **97 passed**）。
- **3 种子主实验（2026-09-14 现行口径，CUDA/RTX 4070 Laptop）**：micro-F1（主指标，标签对级）固定 0.5 = **0.8954±0.0211**、验证集阈值 = **0.9296±0.0090**；macro-F1（参考）0.1918±0.0728；mAP = 0.2980±0.0127。语料口径：590 图 → 剔 90 buggy → 池 **453**（正 127、全零 326）。**2026-09-13 的旧数字（581 图 / 池 448 / micro-F1 0.9058±0.0397）已存档于 `runs/prior_448pool/`，两者不可跨口径混用。** 改动与对照臂见 `experiments/decisions.md` §18。
- **2026-09-14 过滤规则修订 + 对照臂**：`generate_all_ast_cfg_dfg.sh` 的 `delegatecall 动态绑定` 规则改为**仅记账、不再剔除**（原规则系统性删掉 SWC-112 访问控制样本本身；恢复 9 个文件、图 581→590、access_control 池级 15→17）；新增 `make_splits.py --include-buggy`（含 buggy 对照臂，隔离到 `withbuggy_snapshot/` + `runs/withbuggy/`）与 `--buggy-policy`；新增 `scripts/near_dup_clusters.py` 近重复簇检测（主库现行划分实测带同源泄漏：seed0 test↔train 17 对、最高 Jaccard 0.98）。阶段 F（消融/基线）与 G（DIVE/SolidiFI）待执行；`alldata_augmentation` 第二数据集的 M1–M5 全链待跑（产物区 `products/augmentation/`）。
- 2026-09-12 目录重构（方案 B）：数据集产物统一迁入 `products/<数据集>/`；脚本默认路径、.gitignore 与文档已同步；`products/{dive,solidifi}/`、`runs/`、`eval_results/{ablation,baseline,dive,solidifi}/` 已建。
- 2026-09-14 并行第二数据集：新增只读源 `alldata_augmentation/`（MVD-HG 论文增强集；1780 扁平 `.sol` + 9026 条 7 维标签），只读源 4→5；新增 `products/augmentation/{raw,graphs,splits}/` 空骨架，产物区 三→四区。**2026-09-16 该集已全链跑通并裁定与主库结果集并存**（见下方 09-16 条目与 `decisions.md` §23）。`MVD-HG-dataset/` 删除后已恢复，审计链与 `docs/data_funnel.md` 保持有效。决议见 `experiments/decisions.md` §19。
- 目录与状态详情见 `项目组织架构.md` 末节。
