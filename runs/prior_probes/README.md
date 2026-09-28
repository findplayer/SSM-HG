# `runs/prior_probes/` —— epoch 探针的**边车归档**（2026-09-25）

`runs/codebert_ft_probe/`（epoch 探针，只含 ss2）曾被整体移到此处。
该目录的作用是回答「① 的编码器是不是被 `--epochs 5` 截断了」，
结论已落在 `experiments/decisions.md` §42 与 §54.2、`experiments/improvement_round1_results.md`。

## 为什么只留边车、不留权重

`.gitignore` 早已按同一判据把 `runs/codebert_ft*/**/pytorch_model.bin` 排除
（**权重可由 `scripts/finetune_codebert.py` 重建**）。本次磁盘回收沿用这条判据：
**只丢 498 MB 的权重，保留全部能承载结论的 JSON 边车**：

| 保留 | 大小 | 作用 |
|---|---|---|
| `ss2/config.json` | 3.1 KB | **探针的结论本体**：`epochs_log` 逐轮 val macro-F1、早停点 |
| `ss2/encoder/config.json` | 701 B | HF 配置（层数/宽度） |
| `ss2/encoder/corpus.json` | 352 B | 「该编码器属于哪个语料」的硬校验锚点 |
| `ss2/encoder/{special_tokens_map,tokenizer_config}.json` | 1.6 KB | 分词器配置 |

同时删除的还有 `tokenizer.json` / `vocab.json` / `merges.txt`（合计 3.4 MB/seed）——
它们是**基座 CodeBERT 自带的词表**，与探针结论无关。

⚠ **代价（知情）**：不能再拿这份权重重跑 M3。可接受——探针本来就不供 M3，
任何下游都不读它。

`runs/codebert_ft_probe16/`（`--epochs 16` 三划分种子）**原地保留**，只删了 3 个权重，
理由同上。它的 `ss{S}/config.json` 同样留着逐轮曲线。
