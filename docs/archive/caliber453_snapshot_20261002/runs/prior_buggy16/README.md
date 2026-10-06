# `runs/prior_buggy16/` —— **任务 2（池 497）16 轮编码器档**的归档（2026-09-25）

任务 2 的 `_buggy` 正典随 ① 主库**同步换代**（16 轮 → 20 轮）时，从正典路径改名前移过来的旧一代。
**一个字都没删、也没改**：其 `graph_dir` 仍是 `products/alldata/graphs_ft_buggy/cb_ft_ss{S}`、
编码器仍是 `runs/codebert_ft_buggy/ss{S}/encoder`，**两者都原地未动** ⇒ 仍可逐字重放。

## 原位置 ↔ 归档位置

| 原位置（换代后由新一代码占用） | 归档位置 | run 数 |
|---|---|---|
| `runs/buggy_canon/` | `prior_buggy16/buggy_canon/` | 3 |
| `runs/ablation_buggy/` | `prior_buggy16/ablation_buggy/` | 63（21 臂 × 3 种子） |
| `runs/baseline_arch_buggy/` | `prior_buggy16/baseline_arch_buggy/` | 9（3 架构 × 3 种子） |

## 换代理由（与 ① 不同，这条更硬）

`decisions.md` §43 起，`_buggy` 段的立论是「**池 497 vs 池 453** 的对照」。
但换代前两侧的 **epoch 预算一个是 16、一个是 5** ⇒ 实际是**双变量**：
「补回 `buggy_*` 带来的差异」与「编码器多训 11 轮带来的差异」混在一起，**不可分离**。
本次把两侧都对齐到 **20 轮**（且都不开 SWA，见下），才只剩「池」一个变量。

> ⚠ **不加 `--swa-start`**：① 的实测是 `swa.n_averaged = 0/0/2`、三种子 `selection` 全为 `best_epoch`
> （`decisions.md` §54.2）⇒ 本次增益来自 **epoch 预算**，与 SWA 无关。
> 为保持与 ① **逐字同口径**，`_buggy` 也不加——否则又引入一个新变量。

## 未随换代重跑的（实测不需要）

三条论文基线 `eval_results/baseline/{mvdhg,egfl,mando}_buggy/` 与 Slither **不读 CodeBERT 特征**：
MVD-HG 从 `.sol` 自建 compact AST、EGFL 走 `solc --bin` 反汇编（两者只用 `graph_dir` 取标签与源码路径），
MANDO 只读 `_pyg.pt` 与 `_feat.pt::type_id`（**结构通道**，与编码器无关）。
故换 20 轮编码器**不改变它们的任何输入**，无需重训。

## 入库口径

同 `runs/prior_canon37/`：`.gitignore` 加 `runs/prior_buggy16/**/best.pt`，其余（probs / json）入库。
