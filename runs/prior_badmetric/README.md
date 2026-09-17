# 归档：坏指标口径下的全部产物（2026-09-17）

**归档原因**：`scripts/metrics.py` 的 `micro_f1()` 与 `search_global_threshold()` 对输入调用了
`.ravel()`，把 `[N,7]` 展平成 1-D `{0,1}`。sklearn 的 `type_of_target` 因此把问题**从
`multilabel-indicator` 改判成 `binary`**，而 `f1_score(average="micro")` 在 binary 下
**恒等于逐样本 accuracy**（数学恒等）。后果：

1. `evaluate.py` 报告的全部 micro-F1 实为 accuracy（主库 seed0@0.5 记 0.7795，真值 0.1839）；
2. `search_global_threshold` 按 accuracy 选阈值 → seed0 选到**退化点**（全判负，
   `max(prob)=0.567 < 0.60`），该点 accuracy 0.9302 而真 micro-F1 为 0；
3. `train.py` 据此做 LR 调度、早停与 `best.pt` 选择 → **全部 checkpoint 都是被错误目标选出的**。

故第 3 条**无法离线重算**，只能重训。本目录保存重训前的全部产物以备审计。

**已修**：`scripts/metrics.py`（去 `.ravel()` + 新增 `_as_2d()` 守卫）、`tests/test_metrics.py`
（3 个回归锁：全判负 micro-F1 必须为 0；micro-F1 ≠ accuracy；阈值 argmax ≠ accuracy argmax）。
`tests/` 157 passed, 2 skipped。见 `experiments/decisions.md` §28。

## 保留内容

- 全量元数据：`config.json` / `log.txt` / `results.json` / `thresholds.json` / `diagnosis.json`
- `val_best_probs.pt` / `test_probs.pt`（推理缓存 —— `report_conclusions.md` §7.2 两张 n=9
  同配对表即由研究臂的 `val_best_probs.pt` 离线重算得到，删掉该证据即不可复现）
- `best.pt` / `last.pt`：**保留未删**。权重本身是无效的（被坏指标选出），但它们是
  「坏指标如何改变模型选择」这一诊断的原始物证，且 `best.pt` 是 `evaluate.py` 的唯一输入。
  删除需人工裁定。

## 重放方式

```bash
python scripts/rerun_from_config.py --archive-root runs/prior_badmetric --dry-run
```

以本目录各 `config.json::args` 为唯一事实来源重建命令行，逐参数与原跑一致。

| 子目录 | 内容 |
| --- | --- |
| `seed{0,1,2}/` | 正典①主库（池 453，多标签） |
| `augmentation{,_dedup}/` | 正典②增强集（池 1774/1400，单标签） |
| `loss_focal/ loss_asl/ pw_unclamped/` | 干预臂（§1.2 三条否证路径的原始证据） |
| `neardup/ withbuggy/` | 例外/对照臂 |
| `loss_study/` | 27 = 9 配对 × 3 配置（`pw0`/`focal`/`asl`），§1.8/§1.10 多种子复核 |
| `prior_dropout_study/` | 54 = 9 配对 × 6 配置，先验 dropout 剂量-反应 |
| `summary.json` `diagnosis_summary.json` | 顶层聚合（含坏指标值，已随之作废） |

⚠ 本目录内**所有** micro-F1 数字均已作废，不得引用。旧口径先例另见 `../prior_dropout80/`
（保留率语义 bug）与 `../prior_448pool/`（448 池口径）。
