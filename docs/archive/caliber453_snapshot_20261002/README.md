# 池 453 口径文档快照（2026-10-02）

## 这是什么

本目录是 **2026-10-02 池 453 数据删除之前**，仓库中所有仍以池 453 为口径的 Markdown 文档的**逐字快照**。

## 为什么要留这一份

本仓有过两套实验口径：

- **池 453** —— 590 图 → 剔除 90 个 `buggy_*` → 两级去重丢 47 → **453**（train/val/test = 362/45/46）。原为 §37 正典。
- **池 497** —— 590 图 → 两级去重丢 93 → **497**（含 `buggy_*`，train/val/test = 398/50/49）。2026-10-01 由 `研究点一细化大纲改II.docx`（最高权威）定为**现行正典**。

2026-10-01 的裁定原文是「池 497 升为正典，池 453 降为对照口径，**路径一律不改、原地保留**」。

**但 2026-10-02，因 C 盘空间告急（硬规则：任何时候必须 > 8 GB），用户裁定把池 453 的数据整体删除**，释放约 10 GB。删除清单见 `runs/_del453_manifest_20261002.txt` 与 `runs/_del453_manifest_20261002b.txt`。

删除内容包括：`runs/seed{0,1,2}/`、`runs/ablation{,_n9}/`、`runs/arch_n9/`、`runs/binary_arm/`、`runs/perclass_arm/`、`runs/cbft_study/`、`runs/neardup/`、`runs/prior_canon37/`、`runs/codebert_ft/`、`products/alldata/graphs_ft/`、`products/alldata/graphs_ft_p2/`、`products/alldata/splits/` 根下的划分文件、`eval_results/calibration/`、`eval_results/baseline/` 下非 `_buggy` 的基线目录，以及两批清单中的其余条目。

**后果：** 池 453 的数字**不再可复算**。本目录保留的文本是它们**唯一的明文出处**——引用这些数字时只能取这里的冻结值，且必须同时说明该口径的数据已删除。

## 里面有什么

32 个文件，覆盖当时全部含池 453 内容的文档：

- **现行指引类**（后续已按「只留池 497」改写）：`项目组织架构.md`、`论文开发手册.md`、`Todo_List.md`、`docs/{results_tables_index,baseline_dev_plan,M5_dev_plan,M3_frontend_design,cb_func_gapfix_plan}.md`
- **冻结结果报告**（后续已按「453 段落标注为已删除」改写）：`experiments/` 下的 22 份
- 程序生成物：`docs/data_funnel.md`、`eval_results/dive/comparison.md`
- 其他：`log.md`、`runs/prior_buggy16/README.md`

## 引用须知

1. **这些数字不可复算** —— 生成它们的输入已删除。
2. **跨口径不可相减** —— 池 453 的 test 集是 46 个合约，池 497 是 49 个，**不是同一个测试集**。两段的 micro-F1 / macro-F1 / mAP 都不能直接相减或排名。
3. **现行正典是池 497** —— 论文与大纲一律引用池 497 的数字；池 453 只作为「降级前的旧口径」被提及。
