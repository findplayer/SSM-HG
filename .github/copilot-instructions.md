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

- 输出可能很长的命令一律截断或先落盘：`... 2>&1 | tail -50`；大批量脚本的输出重定向到 `raw/logs/`，再用 `tail` / `grep` 按需查看。不要把全量进度直接打印到终端。
- Git 的长输出命令一律加 `--no-pager`（如 `git --no-pager log --oneline -20`），避免进入 `less` 分页器等待按键。
- 不要运行交互式命令（需要 y/n、密码、分页器）。必要时改用非交互参数（如 `-y`、`--yes`）。
- 长跑脚本会触发"命令可能在等待输入"的自动通知，每次通知都会把整段终端输出重新注入上下文。因此长跑任务要减少输出量，并避免在运行期间反复读取产物。

## 数据边界（硬规则）

- 只读、绝不写入或改名：`alldata(readonly)/`、`DIVE/`、`SolidiFI/`、`MVD-HG-dataset/`。
- 中间产物只能写到 `raw/`、`Heterogeneous graphs/`、`splits/`、`runs/`、`eval_results/`。
- 路径含空格（`Heterogeneous graphs/`、`alldata(readonly)/`、`DIVE/Source codes/`），命令中必须加引号。
- `raw/` 与 `Heterogeneous graphs/` 存放约 581 个合约的批量产物，不要整目录列举或全量读取，按需读单个文件。
- 不要提交超过 100 MB 的文件。`DIVE/Code-based.csv`（147 MB）已在 `.gitignore` 中，仅保留在本地。

## 语义锁死项（最容易写错）

- 标签顺序固定：`access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`（reentrancy 下标为 4）。
- `_pyg.pt` 是只读的纯结构（`x` 为 N×1 占位，永不改写）；`_feat.pt` = M3 经 MLP 后的 128 维 $h_v^{(0)}$，是唯一模型输入特征；`dataset.py` 只负责组合，不再过 MLP、不重算。
- M1 的 $s_v$ 是输入特征，不是标签；$a_v$ 是节点可疑度/解释信号，不是节点真值。
- `CALLBACK_RISK` 是启发式边，不是真实跨合约调用图；主实验默认保留，不得降级为节点特征。
- 训练与推理的 Dropout、先验 dropout 行为不同，不要混用。
- M5 划分：唯一合约、固定种子 8:1:1，val 与内部测试每类正样本 ≥20，否则换种子重划；**训练种子与划分种子分离**。
- 阈值只在验证集搜索；测试集同时报告固定 0.5 与验证集阈值两套结果。
- 消融分层：边消融在 `dataset.py` 按 edge_type 过滤（零重跑）；特征消融跑 M3 `--variant`（复用 `_cb.pt`）；模型消融走 `model.py`/`train.py` 开关。

## 改动原则

- **最小化修改，只改必要部分**：不重构无关代码。
- 若进行大纲没有的后处理，必须输出明确理由，并同步修改大纲和开发手册。
- 审查外部或 AI 建议时：先判断是否与大纲冲突；合理的吸收，不合理的明确反驳并给出理由，不要照单全收。
- 全量重跑代价高（M2 全量重跑会带动下游 581 个图）。能用 `--only <图前缀>` 或 `--variant` 小样验证就先小样验证。
- 等批量脚本跑完再校验产物：脚本会先删旧文件再逐个重生成，中途读取会得到"缺失/归零"的假象。

## 记录与沟通

- 回复与文档统一使用中文。
- 实验决议与口径变化写入 `experiments/decisions.md`；接口变更同步 `docs/M4_interface.md`；目录结构变化同步 `项目组织架构.md`。
- 提交前确认没有把只读数据源或超过 100 MB 的文件加入提交。

## 当前进度（2026-09-12）

- 已完成：M1–M4；`scripts/` 中 `dataset.py`、`make_splits.py` 已实现。
- 待实现：`scripts/metrics.py`、`scripts/train.py`、`scripts/evaluate.py`（M5）。
- 目录与状态详情见 `项目组织架构.md` 末节。
