# 归档：`--prior-dropout` 语义修正**之前**的全部结果（2026-09-16）

**口径已作废，不得引用、不得与新数字混用。** 保留仅为可回溯与"必要时返工"。

## 为什么作废

`model.sample_dropout_masks` 当时返回 `rand < p` 且掩码**乘法**作用于通道（0=置零、1=保留），
故 `p` 实为**保留率**：默认 `--prior-dropout 0.2` 实际把 **80%** 的图的 $s_v$ 整通道置零，
而大纲 4.1.4 与手册 §8.6 写的是**丢弃率 0.2**。结构 dropout 共用同一函数，同样反了。

后果：本目录全部结果是在"丢弃 80%"（而非文档所载的 20%）下训出的 —— **配置与文档不符**。

## 修正

`sample_dropout_masks` 改为**丢弃率**语义（`rand < p` 即丢弃）：

| 取值 | 语义 |
| --- | --- |
| `--prior-dropout 0.2`（默认） | 每个图以 **20%** 概率把该图 $s_v$ 整通道置零 |
| `--prior-dropout 0` | **关闭**随机先验 dropout（不置零） |
| `--prior-dropout 1` | 每个图都置零（"全丢"）；**不要用它表示"关闭"** |

⚠ 与 `--ablate-sv` 的区别：后者是**确定性**全零消融（train/eval 一致），
与 `--prior-dropout 0`（随机正则关闭）**不是一回事**。

修正后重跑的结果在上一级 `runs/`。决议见 `experiments/decisions.md` §26。

## 权重已移除（2026-09-16）

本目录**不含 `best.pt`/`last.pt`**：本口径整体作废（见上），且它与"当前正典"仅差一个开关——
`--prior-dropout 0.8` 即可在约 10 分钟内**精确重现**本口径的统计行为
（新版 `p` 是丢弃率，故 `0.8` ≡ 旧实现的有效行为）。

保留的是全部 JSON/text：`config.json`（参数）、`log.txt`（逐 epoch）、`results.json`（双阈值+逐类+mAP）、
`thresholds.json`、`summary.json`、`diagnosis.json`、`val_best_probs.pt`/`test_probs.pt`（推理缓存，体积小）。
移除权重的直接原因：**本机 C 盘可用空间低于 20 GB 硬阈值**（见 `AGENTS.md` 磁盘空间规则），
不应为已作废口径保留 114 MB 二进制。
