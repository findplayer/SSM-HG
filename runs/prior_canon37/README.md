# `runs/prior_canon37/` —— **§37 谱系 5 轮编码器档**的归档（2026-09-25）

本目录是**编码器换代**（`experiments/encoder_promotion_gate.md` 三门前全过）时，
从正典路径上**改名前移**过来的旧一代产物。**一个字都没删、也没改**——
所有 `config.json` 里的 `graph_dir` / `encoder_dir` 仍是**绝对/相对原路径**，
而它们指向的**编码器（`runs/codebert_ft/`）与图树（`products/alldata/graphs_ft/`）原地未动**，
故本目录里的每个 run 仍可用 `scripts/rerun_from_config.py` 逐字重放。

> **为什么用 `prior_` 前缀**：`scripts/aggregate_results.py:35` 的 `ARCHIVE_PREFIX = "prior_"`
> 会按路径段把它自动排除在汇总之外（与既有的 `runs/prior_frozen/` 同一约定）。
> 这是选它而不是 `runs/_archive/` 的原因——后者不匹配该前缀，旧一代会被混进同一张表。
> ⚠ 另外 `.gitignore` 的 `runs/codebert_ft*/**` 是**路径前缀**匹配，
> `runs/_archive/codebert_ft/...` 会让 2.9 GB 的 `.bin` 漏网；本方案**从不归档编码器**，故无此问题。

## 原位置 ↔ 归档位置

| 原位置（换代后由**新一代码**占用） | 归档位置 | run 数 | 说明 |
|---|---|---|---|
| `runs/seed0/` `runs/seed1/` `runs/seed2/` | `prior_canon37/seed{S}/` | 3 | 5 轮档正典 GNN 产物 |
| `runs/summary.json` `runs/diagnosis_summary.json` | `prior_canon37/_runroot/` | 2 | `runs/` **根**下的跨种子聚合（不属于任何 seed） |
| `runs/cbft_study/` | `prior_canon37/cbft_study/` | 18 | 冻结 vs 微调的 n=9 配对研究 |
| `runs/ablation/` | `prior_canon37/ablation/` | 63 | 21 臂 × 3 种子（n=3，对角线） |
| `runs/ablation_n9/` | `prior_canon37/ablation_n9/` | 153 | 同配对 ≥9 点（21 臂 × 6 非对角 + 3 剂量臂 × 9） |
| `runs/arch_n9/` | `prior_canon37/arch_n9/` | 63 | 架构基线族 GCN/GAT/SAGE + 参数量匹配对照，n=9 |
| `runs/perclass_arm/` | `prior_canon37/perclass_arm/` | 45 | 7 个独立二分类器 + ANY_union，2 个 cap |
| `runs/baseline_gcn/` | `prior_canon37/baseline_gcn/` | 3 | 逐类 F1 表读的 GCN 对照臂（n=3） |

**未归档（不受本次换代影响）**：所有 `graph_dir = products/<语料>/graphs`（冻结树）或
`products/augmentation/...`（② 增强集）的 run —— 如 `loss_study`、`loss_asl`、`loss_focal`、
`pw_unclamped`、`neardup`、`withbuggy`、`prior_dropout*`、`ablation_aug`、`ablation_n9_aug`。
**冻结编码器与 ② 增强集都没换代**（用户 2026-09-25 裁定），故它们原样留在 `runs/` 下。


## 🔴 不得用 `rerun_from_config.py` 直接重放本目录

换代是 `mv`（原地改名），所以归档里的 `config.json::args.out_dir` **仍写着原正典路径**
（如 `runs/seed0`）。而 `scripts/rerun_from_config.py` 按该字段**回填重放目标**
⇒ **直接重放本目录会写到 `runs/seed{S}`，也就是正在服役的现行正典。**

⚠ 本 README 开头说的「仍可逐字重放」指的是**语义上**可重放（输入路径都还在），
**不是**指可以直接把这个工具指过来。要重放必须先把 `out_dir` 改到别处。

同理：`runs/prior_canon37/seed{S}/config.json::args.graph_dir` 指向的
`products/alldata/graphs_ft/ss{S}`（旧 5 轮树）**仍在原位**，所以重放的**输入**没问题；
有问题的是**输出**。

## 为什么「两代并存、旧的一律不删」

本仓 2026-09-21 已就此立规：删掉旧一代就是删掉对照臂。本次尤其需要它——
`experiments/decisions.md` 的 **§55 逐单元格 before/after 对照表**（覆盖全部指标 × 3 种子，
**含下降的格子**）就是拿本目录的数字与新正典逐格相减得到的。**没有本目录，那张表无法复核。**

## 入库口径

`.gitignore` 对本目录加了一行 `runs/prior_canon37/**/best.pt`（放在 `!runs/**/best.pt` **之后**），
口径与 `runs/ablation_n9*` 一致：**`test_probs.pt` / `val_best_probs.pt` / `config.json` /
`results.json` / `thresholds.json` / `diagnosis.json` 全部入库，权重 `best.pt` 排除**。
理由同那一条：全部指标都能由 probs 缓存**离线重算**。
