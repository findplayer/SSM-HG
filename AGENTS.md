# SSM-HG 项目约定

CFG 中心异构图 + RGCN 的智能合约七类漏洞多标签检测，流水线为 M1–M5。

## 权威文档（冲突时按此优先级）

1. `研究点一细化大纲改II.docx` —— 论文大纲，最高权威
2. `论文开发手册.md` —— 实施细节（§3.2 路径速查、§12 常见错误清单）
3. `experiments/decisions.md` —— M5 实验决议 v5（部分条目已被大纲 `改II` 取代，冲突时以大纲为准）

实现前先读对应章节，不要凭常识补全设计。

## 运行环境

- 一律在 **conda base** 环境运行：slither 0.11.5、solc-select、python 3.11、torch 2.0.1（CPU 版）、torch_geometric 2.7.0、transformers 4.29.2。
- 脚本统一**从仓库根目录**运行：`python scripts/xxx.py`。不要 `cd scripts`，也不要从根目录直接 `import` 脚本。
- 测试：`pytest tests/ -q`，或 `python tests/test_model_smoke.py`。
- 批量运行前先 `--help` 或显式传参确认，不要依赖默认路径盲跑。

## 终端与输出

- 输出可能很长的命令一律截断或先落盘：`... 2>&1 | tail -50`；大批量脚本的输出重定向到对应数据集的 `raw/logs/`（如 `products/alldata/raw/logs/`），再用 `tail` / `grep` 按需查看。不要把全量进度直接打印到终端。
- Git 的长输出命令一律加 `--no-pager`（如 `git --no-pager log --oneline -20`），避免进入 `less` 分页器等待按键。
- 不要运行交互式命令（需要 y/n、密码、分页器）。必要时改用非交互参数（如 `-y`、`--yes`）。
- 长跑脚本会触发"命令可能在等待输入"的自动通知，每次通知都会把整段终端输出重新注入上下文。因此长跑任务要减少输出量，并避免在运行期间反复读取产物。

## 数据边界（硬规则）

- 只读、绝不写入或改名：`alldata(readonly)/`、`DIVE/`、`SolidiFI/`、`MVD-HG-dataset/`。
- 中间产物只能写到 `products/<数据集>/`（`products/alldata/{raw,graphs,splits}`、`products/dive/…`、`products/solidifi/…`）以及 `runs/`、`eval_results/`。
- 路径含空格/括号（`alldata(readonly)/`、`DIVE/Source codes/`），命令中必须加引号；产物区 `products/…` 无空格。
- `products/alldata/raw/` 与 `products/alldata/graphs/` 存放约 581 个合约的批量产物（原 `raw/`、`Heterogeneous graphs/`，2026-09-12 迁入），不要整目录列举或全量读取，按需读单个文件。
- 不要提交超过 100 MB 的文件。`DIVE/Code-based.csv`（147 MB）已在 `.gitignore` 中，仅保留在本地。

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

## 记录与沟通

- 回复与文档统一使用中文。
- 实验决议与口径变化写入 `experiments/decisions.md`；接口变更同步 `docs/M4_interface.md`；目录结构变化同步 `项目组织架构.md` 与 `论文开发手册.md` §3.2。开发计划变更同步 `论文开发手册.md`；
- 需要裁定的要给出几种方案的区别、优劣、产物差异、对论文的影响，便于裁定。
- 提交前确认没有把只读数据源或超过 100 MB 的文件加入提交。

## 当前进度（2026-09-12）

- 已完成：M1–M4；`scripts/` 中 `dataset.py`、`make_splits.py` 已实现（2026-09-12：覆盖约束校正 `--strategy constrained`（默认）+ `coverage_swaps_seed*.txt`、`splits.csv`、split metadata；三种子 C1/C2 构造达标，主种子 seed0）。
- 待实现：`scripts/metrics.py`、`scripts/train.py`、`scripts/evaluate.py`（M5）。
- 2026-09-12 目录重构（方案 B）：数据集产物统一迁入 `products/<数据集>/`；脚本默认路径、.gitignore 与文档已同步；`products/{dive,solidifi}/`、`runs/`、`eval_results/{ablation,baseline,dive,solidifi}/` 已建。
- 目录与状态详情见 `项目组织架构.md` 末节。
