# 研究点一收尾日志

最后整理：2026-09-30

## 1. 项目状态

- M1-M5 已完成，主实验、两代消融、三条论文基线、六个传统工具、DIVE 外部评估和 SolidiFI 层次二评估均已形成现行产物。
- 现行结果、逐类表格、混淆计数和传统工具报告均已写入 `experiments/`；引用数字时以对应程序生成报告为准——**正典（池 497，现行默认口径）**的数字见 `experiments/buggy_canon_summary.md` 等现行产物，`experiments/canonical_ft_numbers.md` 是**对照口径（池 453）**的权威出处。
- 现行目录、正典路径、历史归档和资料分层以 `项目组织架构.md` 为唯一导航；实施命令以 `论文开发手册.md` 为准。

## 2. 未闭合事项

- DIVE 的 20-30 例 FN/FP 人工检查尚未完成。
- 编码器全量重微调（P2）尚未执行；相关探针和风险记录见 `experiments/improvement_proposals.md`。
- 增强集上的论文基线和传统工具没有统一评测结果，不能从主库结果外推；裁定和影响见 `experiments/decisions.md` 及相关总表。
- **2026-10-01 口径对调（用户裁定）**：池 497（含全部 `buggy_*`）升为**正典（默认口径）**，池 453 降为**对照口径**。代码侧 `scripts/baseline_common.py::LAYOUTS` 已同步（新增 `DEFAULT_LAYOUT = buggy`）；**但 `experiments/` 下按旧口径生成的报告与表格、以及相关口径戳与测试尚未重跑或更新**，引用前须核对口径。

以上事项不改变已冻结主实验的复现口径。后续如继续研究，应新建实验记录和输出目录，不覆盖现行正典。

## 3. 归档记录

- `docs/archive/development_log_full_20260930.md`：本次精简前的完整开发日志。
- `docs/archive/AGENTS_full_20260930.md`：本次精简前的完整代理约定。
- `docs/archive/README.md`：归档说明、资料分层和收尾状态。

历史日志不再追加开发流水账；新的决议写入 `experiments/decisions.md`，新的目录变化同步 `项目组织架构.md`，必要的收尾事实才记录在本文件。
