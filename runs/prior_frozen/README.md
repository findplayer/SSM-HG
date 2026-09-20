# `runs/prior_frozen/` —— 「冻结 CodeBERT 为正典」时代的归档（2026-09-19）

## 为什么会有这个目录

2026-09-19 用户裁定：**把「微调 CodeBERT」升为主设计，把「冻结 CodeBERT」降为消融/对比**
（`experiments/decisions.md` §37）。依据是同日完成的 **n=9 同配对复核**（§36，`runs/cbft_study/`）：
微调带来 test 侧 **8/8 指标显著**提升（`micro@0.5` **+0.2466，t=+11.92**；`mAP` +0.4366，t=+17.66），
且 `Δmicro@0.5`/`ΔmAP`/`ΔBuggy@0.5` 的 **9 个配对全部为正**。

**正典定义变了 ⇒ 旧正典数字全部作废**，故整体归档于此。这与 §28（`.ravel()` 修复）
时的 `runs/prior_badmetric/` 是同一处置方式。

> ⚠ **本目录内所有指标数字一律不得引用**：它们的分母（正典）已换成微调版，
> 冻结版现在是 `runs/ablation/{,aug}cb_frozen/` 这一**消融臂**。

## 目录内容

| 子目录 | 原位置 | 归档时的身份 |
|---|---|---|
| `seed{0,1,2}/` | `runs/seed{0,1,2}/` | ① 主库**冻结版正典**（3 种子） |
| `augmentation/seed{0,1,2}/` | `runs/augmentation/seed{0,1,2}/` | ② 增强集冻结版正典 |
| `ablation/` | `runs/ablation/` | ① 在冻结正典上跑的 **21 个消融臂** |
| `ablation_aug/` | `runs/ablation_aug/` | ② 在冻结正典上跑的 **5 个消融臂** |

每个 run 目录保留 `config.json` / `log.txt` / `results.json` / `thresholds.json` /
`diagnosis.json` / `val_best_probs.pt` / `test_probs.pt` / `best.pt`。

⚠ `config.json::args.graph_dir` 里记录的 `…/graph_variants/cb_ft_ss{S}` 路径在本次改动中
**已改名为 `…/graphs_ft/ss{S}`**；为不篡改历史记录，另在 `products/<语料>/graph_variants/`
下留了同名**兼容软链**指向新位置，故这些 config 仍可解析、可重放。

## 未归档、仍现行的内容

- `runs/cbft_study/` —— **n=9 复核的原始产物**，是 §36/§37 两节裁定的证据本身，**原地保留**
- `runs/codebert_ft/` —— 微调编码器（`<语料>/ss{S}/encoder/`），新正典仍在用它
- `runs/loss_study/`、`runs/prior_dropout_study/`、`runs/binary_arm/` —— 其他研究臂，
  **不在本次重跑范围**。⚠ 它们的基线是冻结版正典，其结论需在文档中标注工作点（见 `decisions.md` §37）
