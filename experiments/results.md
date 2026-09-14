# M5 实验结果记录

> 定位：集中记录 M5 各阶段实验的**执行结果**（命令、环境、超参、产物、指标、计时）。
> 分工：**决议/口径裁定** → `experiments/decisions.md`；**论文口径数字溯源** → `docs/data_funnel.md`；**本文**只记录「某次实验怎么跑、跑出什么」，每个数字标注产物出处（`runs/`、`eval_results/`）。
> 更新规则：每次实验跑完，在对应小节追加/覆盖记录，并同步更新产物路径；`best.pt`/`last.pt`/`val_best_probs.pt` 等 checkpoint 已被 `.gitignore` 排除，JSON/text 记录纳入版本管理。

---

## 1. 主实验（阶段 E：MVD-HG 内部测试，3 种子）

### 1.1 实验设置

- **命令**（仓库根目录，`python scripts/…`）：
  ```bash
  python scripts/train.py --seed {0,1,2} --epochs 200 --batch-size 32
  python scripts/evaluate.py --seed {0,1,2}
  python scripts/evaluate.py --summarize
  ```
- **环境**：`cuda`（NVIDIA RTX 4070 Laptop）、torch 2.0.1+cu118、python 3.11.3、torch_num_threads 12（出处 `runs/seed*/config.json::environment`）。
- **超参**（主实验未传任何覆盖，均取默认，出处 `config.json::args`）：lr=1e-4、weight_decay=1e-4、batch_size=32、max epochs=200、prior_dropout=0.2、struct_dropout=0.2、model_dropout=0.3、lambda_var=1e-3、tau_var=0.1、num_bases=5、hid=128、conv=rgcn、scheduler_patience=3、early_stop_patience=5、drop_edge_prob=0.0、cb_channels=`cb_func,cb_node`、feat_groups=`all`。
- **模型维度**（出处 `config.json::derived`）：D_struct=30、fuser 融合输入维=1631、fuser 输出（=SSMHG 输入）维=128、num_relations=5、num_classes=7；参数量 fuser 209,472 + RGCN 205,754 = **415,226**。
- **划分**：train 358 / val 45 / test 45（每 seed，`split_seed == seed`）；主种子 **seed0**（用途定位见 `decisions.md` §12）；训练种子与划分种子同名（`decisions.md` §16）。
- **标签序**（固定）：`access_control, arithmetic, dos, front_running, reentrancy, time_manipulation, uncheck`（reentrancy 下标 4）。
- **训练集逐类正样本** `train_pos`：seed0 `[10,10,4,2,21,2,35]`；seed1/2 `[10,10,4,2,21,3,35]`（全 7 类均含正样本，无 skipped class）。
- **口径**：主指标 **micro-F1（标签对级）**；macro-F1 为参考；阈值只在验证集搜索（0.20–0.80 步长 0.05，目标 val micro-F1，tie 取小）；测试集双报告（固定 0.5 + 验证集阈值）；support≤2 的类仅描述性呈现（`decisions.md` §13）。

### 1.2 汇总结果（`runs/summary.json`，3 种子 mean±std，ddof=1）

| 指标 | 固定 0.5 | 验证集阈值 | 备注 |
| --- | --- | --- | --- |
| **micro-F1（主）** | **0.9058 ± 0.0397** | **0.9492 ± 0.0145** | 阈值 0.75 / 0.60 / 0.55 |
| macro-F1（参考） | 0.2300 ± 0.0428 | 0.2455 ± 0.0720 | |
| mAP | 0.4139 ± 0.1070 | — | 不依赖阈值，仅一份 |

### 1.3 逐种子明细（`runs/seed*/results.json`）

| seed | 划分 | val 阈值 | micro-F1(0.5) | micro-F1(val) | macro-F1(0.5) | macro-F1(val) | mAP | subset acc(0.5) | subset acc(val) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0（主） | seed0 | 0.75 | 0.8603 | 0.9333 | 0.1846 | 0.2054 | 0.3203 | 0.4889 | 0.6000 |
| 1 | seed1 | 0.60 | 0.9238 | 0.9524 | 0.2356 | 0.2024 | 0.3909 | 0.6444 | 0.6667 |
| 2 | seed2 | 0.55 | 0.9333 | 0.9619 | 0.2697 | 0.3286 | 0.5306 | 0.6444 | 0.7556 |

### 1.4 逐类指标（随 support）

**逐类 support（test）与 PR-AUC（AP，来自 `results.json::mAP.ap`）**：

| 类别 | support seed0/1/2 | AP seed0 | AP seed1 | AP seed2 |
| --- | --- | --- | --- | --- |
| access_control | 2 / 2 / 2 | 0.0763 | 0.2500 | 0.1623 |
| arithmetic | 2 / 2 / 3 | 0.8333 | 1.0000 | 0.8333 |
| dos | 1 / 1 / 1 | 0.0909 | 0.0233 | 0.0222 |
| front_running | 1 / 1 / 1 | 0.0833 | 0.0244 | 1.0000 |
| reentrancy | 5 / 5 / 5 | 0.6904 | 0.9667 | 1.0000 |
| time_manipulation | 2 / 1 / 1 | 0.1458 | 0.0588 | 0.2000 |
| uncheck | 7 / 7 / 7 | 0.3217 | 0.4132 | 0.4962 |

> support≤2 的类（access_control、arithmetic、dos、front_running、time_manipulation，视 seed）其 F1/AP **仅描述性呈现、不进方法间比较结论**（`decisions.md` §13）。

**主种子 seed0 逐类 P/R/F1（双阈值，随 support）**：

| 类别 | support | P(0.5) | R(0.5) | F1(0.5) | P(0.75) | R(0.75) | F1(0.75) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| access_control | 2 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| arithmetic | 2 | 0.3333 | 1.0000 | 0.5000 | 1.0000 | 0.5000 | 0.6667 |
| dos | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| front_running | 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| reentrancy | 5 | 0.3077 | 0.8000 | 0.4444 | 0.4444 | 0.8000 | 0.5714 |
| time_manipulation | 2 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| uncheck | 7 | 0.2500 | 0.5714 | 0.3478 | 0.3333 | 0.1429 | 0.2000 |

**七类逐类 F1（三种子全量，双阈值；来源 `runs/seed*/results.json::test.{fixed_0.5,val_threshold}.per_class`）**

固定 0.5：

| 类别 | support (s0/s1/s2) | F1 s0 | F1 s1 | F1 s2 | F1 mean±std |
| --- | --- | --- | --- | --- | --- |
| access_control | 2 / 2 / 2 | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| arithmetic | 2 / 2 / 3 | 0.5000 | 0.6667 | 0.8000 | 0.6556 ± 0.1503 |
| dos | 1 / 1 / 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| front_running | 1 / 1 / 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| reentrancy | 5 / 5 / 5 | 0.4444 | 0.6667 | 0.5882 | 0.5664 ± 0.1127 |
| time_manipulation | 2 / 1 / 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| uncheck | 7 / 7 / 7 | 0.3478 | 0.3158 | 0.5000 | 0.3879 ± 0.0984 |

验证集阈值（0.75 / 0.60 / 0.55）：

| 类别 | F1 s0 | F1 s1 | F1 s2 | F1 mean±std |
| --- | --- | --- | --- | --- |
| access_control | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| arithmetic | 0.6667 | 0.6667 | 0.8000 | 0.7111 ± 0.0770 |
| dos | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| front_running | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| reentrancy | 0.5714 | 0.7500 | 1.0000 | 0.7738 ± 0.2153 |
| time_manipulation | 0.0000 | 0.0000 | 0.0000 | 0.0000 ± 0.0000 |
| uncheck | 0.2000 | 0.0000 | 0.5000 | 0.2333 ± 0.2517 |

**Macro-F1（七类逐类 F1 的未加权平均，zero_division=0；来源 `runs/summary.json`）**

| 口径 | s0 | s1 | s2 | mean±std |
| --- | --- | --- | --- | --- |
| 固定 0.5 | 0.1846 | 0.2356 | 0.2697 | 0.2300 ± 0.0428 |
| 验证集阈值 | 0.2054 | 0.2024 | 0.3286 | 0.2455 ± 0.0720 |

> macro-F1 七类等权，access_control / dos / front_running / time_manipulation 四类在三个种子恒为 F1=0，直接把宏平均压在 ~0.23 附近；micro-F1 高是因为它按标签对计数、被 uncheck(7)+reentrancy(5) 及其负样本主导。

### 1.5 训练时间与吞吐（`runs/seed*/config.json::timing`，§11.4 口径）

| seed | run_wall(s) | data_load(s) | train(s) | validation(s) | epochs | graphs/s | best val micro-F1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 40.8 | 31.5 | 7.4 | 0.4 | 19（早停@18） | 924.2 | 0.9556 |
| 1 | 16.3 | 9.3 | 6.0 | 0.4 | 11（早停@10） | 659.7 | 0.9492 |
| 2 | 16.0 | 11.5 | 3.2 | 0.2 | 9（早停@8） | 1002.7 | 0.9587 |

> `graphs_per_second = train_graphs / train_seconds`，只含 optimizer loop（不含验证/checkpoint/IO）；跨工具比较以 `train_seconds` 为准。seed0 的 `data_load_seconds` 31.5 s 为首次冷加载（581 图索引 + 358/45 图特征进内存），seed1/2 约 9–11 s 系 OS 页缓存命中。

### 1.6 产物清单与复现

- 每 seed：`runs/seed{N}/` 下 `config.json`（参数+派生量+环境+timing）、`log.txt`（epoch JSONL）、`best.pt`/`last.pt`（fuser+model+optimizer，双模块）、`results.json`（双阈值+逐类+mAP）、`thresholds.json`（全候选扫描）、`val_best_probs.pt`（best epoch 的 val probs，供 evaluate 复用）。
- 汇总：`runs/summary.json`（3 种子 mean±std，主种子 seed0）。
- 诊断（2026-09-14 新增，脚本 `scripts/diagnose.py`）：每 seed `diagnosis.json`（逐类混淆/ROC-AUC/AP/oracle/标定/共现）、`test_probs.pt`（test 推理缓存，供复现免重复推理）；跨种子 `runs/diagnosis_summary.json`。
- 版本管理：`*.pt` checkpoint 已被 `.gitignore` 排除；`config.json`/`log.txt`/`results.json`/`thresholds.json`/`summary.json`/`diagnosis*.json` 等 JSON/text 记录纳入版本管理。

### 1.7 逐类诊断与改进线索（`runs/seed*/diagnosis.json` + `runs/diagnosis_summary.json`）

为解释 macro-F1 / mAP 偏低，新增 `scripts/diagnose.py` 做逐类深度诊断（只读产物、写诊断 JSON，不参与训练/阈值/主结果）。根因按影响排序：**① 数据稀缺（度量级）→ ② 欠置信/标定 → ③ 弱分离**。

**表 1.7-a 七类根因证据（支撑列 = 主种子 seed0；ROC-AUC/AP/oracle-F1 列 = 3 种子 mean）**

| 类别 | 池级正样本 | train_pos | test_pos | 真实负正比 | pos_weight(截断20) | ROC-AUC | AP | oracle-F1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| access_control | 15 | 10 | 2 | 34.8 | 20.0 | 0.756 | 0.163 | 0.297 |
| arithmetic | 15 | 10 | 2 | 34.8 | 20.0 | 0.988 | 0.889 | 0.867 |
| dos | 6 | 4 | 1 | 88.5 | 20.0 | 0.273 | 0.046 | 0.085 |
| front_running | 4 | 2 | 1 | 178.0 | 20.0 | 0.614 | 0.369 | 0.401 |
| reentrancy | 31 | 21 | 5 | 16.0 | 16.05 | 0.955 | 0.886 | 0.879 |
| time_manipulation | 5 | 2 | 2 | 178.0 | 20.0 | 0.775 | 0.135 | 0.232 |
| uncheck | 50 | 35 | 7 | 9.2 | 9.23 | 0.767 | 0.410 | 0.504 |

- 池级正样本 = train+val+test 合计（seed0）；上游 MVD-HG-dataset 各类源文件 88–190（`splits/data_funnel.json`），经 buggy 剔除 + 两级去重 + 多标签并集后池级仅剩 4–50，稀有类（dos 6 / front_running 4 / time_manipulation 5）从根上就极稀缺。
- oracle-F1 = 该类别遍历阈值的单类最佳 F1（与全局阈值无关），是该类的**可达上限**；dos/front_running/time_manipulation 上限仅 0.09–0.40 → 即便排序满分，test_pos=1 时命中即 1、未命中即 0，F1 天然不稳定。
- ROC-AUC 高但 F1=0 = 排序尚可但绝对概率塌缩（欠置信）；ROC-AUC 低 = 排序就没学会（如 dos 0.273）。

**表 1.7-b 正样本预测概率（主种子 seed0，标定/欠置信证据；`diagnosis.json::prob_stats.pos_probs_sorted`）**

| 类别 | test_pos | 正样本预测概率（降序） | 负样本 mean | 全局阈值命中 |
| --- | --- | --- | --- | --- |
| dos | 1 | 0.223 | 0.161 | 0/1 |
| front_running | 1 | 0.105 | 0.074 | 0/1 |
| time_manipulation | 2 | 0.074, 0.044 | 0.040 | 0/2 |
| access_control | 2 | 0.312, 0.311 | 0.317 | 0/2 |
| reentrancy | 5 | 0.968, 0.930, 0.869, 0.841, 0.229 | 0.316 | 4/5 |
| uncheck | 7 | 0.808, 0.734, 0.625, 0.569, 0.480, 0.461, 0.276 | 0.430 | 4/7 |
| arithmetic | 2 | 0.863, 0.574 | 0.235 | 2/2 |

> 关键证据：dos/front_running/time_manipulation 的正样本被排在类内负样本之前（ROC-AUC 0.27–0.78），但**绝对概率仅 0.04–0.22**，任何合理阈值（0.2–0.8）都命中不了 → 失败本质是「logits 尺度塌缩/欠置信」，而非完全没学到。access_control 是另一型：正样本 0.31 ≈ 负样本 0.32（ROC-AUC 0.58≈随机），且固定 0.5 下 FP=9（误报）。

**失败模式归类**

| 模式 | 类别 | 证据 | 机制 |
| --- | --- | --- | --- |
| A 欠置信/尺度塌缩 | dos、front_running、time_manipulation | 正样本概率 0.04–0.22、全局阈值零命中 | train_pos 2–4、真实负正比 88–178× 但 `pos_weight=min(neg/pos,20)` 截到 20× → BCE 在 350+ 负样本压力下对稀有类保守（logits 被压小）。dos 还叠加排序弱（ROC-AUC 0.27） |
| B 误报/混淆 | access_control | 0.5 下 TP=0、FP=9，pos≈neg（0.31 vs 0.32） | 模型把它和某高频模式混淆（标签共现矩阵七类基本独立，非多标签共现所致） |
| C 弱分离但可学 | uncheck | pos 0.57 vs neg 0.43、FP=12@0.5、oracle 0.50 | 有信号，但负样本近邻太多 |
| D 正常 | arithmetic、reentrancy | ROC-AUC 0.988 / 0.955 | 证明模型与特征整体有效，问题集中在稀有类数据与标定，不是全局失效 |

**改进思路（建议，待裁定，未执行）**

1. **先看天花板**：报告 oracle-F1 作为每类可达上限；test_pos≤2 的类 F1 结论天然不稳定，沿用 §13「仅描述性呈现」。dos/front_running/time_manipulation 即便理想模型天花板也仅 0.09–0.40。
2. **加权/损失**：`pos_weight` 截断 20 是欠置信的直接嫌疑 → 消融 `min(neg/pos, ∞)`（放开截断）或换 focal loss / ASL 不对称损失，预期把稀有类正样本 logits 抬过阈值。**（已实测放开截断，见 §1.8：未救活稀有类、反伤 arithmetic、固定 0.5 主指标 0.906→0.815，故维持 cap=20；下一步转向 focal/ASL 或标定。）**
3. **标定/阈值**：全局阈值（按 micro-F1 选）对稀有类天然不利 → 补 per-class 阈值分析（仅补充，不进主结果），或 temperature scaling 校标定。
4. **数据侧**：dos/front_running/time_manipulation 池级仅 4–6 正样本是根因 → 阶段 G 的 DIVE/SolidiFI 迁移补充样本、或图级数据增强；否则论文明确声明三类受样本量限制。
5. **消融定位**（阶段 F）：`--drop-edges`/`--drop-ast`/`--ablate-sv`/`--feat-groups` 观察 access_control 的 FP 与稀有类欠置信是否随某特征/边下降。

### 1.8 pos_weight 截断消融（放开截断，2026-09-14）

对 §1.7 改进思路 #2 的**实测检验**：`pos_weight=min(neg/pos,20)` 的截断被列为稀有类欠置信的直接嫌疑，本实验放开截断验证。

- **实现**：`train.py` 新增 `--pos-weight-cap`（默认 20.0；`0`=不截断，即 `pos_weight_c=neg_c/pos_c`）。放开截断命令：
  ```bash
  python scripts/train.py --seed {0,1,2} --pos-weight-cap 0 --out-dir runs/pw_unclamped
  python scripts/evaluate.py --seed {0,1,2} --runs-dir runs/pw_unclamped
  python scripts/evaluate.py --summarize --runs-dir runs/pw_unclamped
  python scripts/diagnose.py --runs-dir runs/pw_unclamped
  ```
- **实际受影响的类只有 5 个**（真实负正比 >20）：access_control/arithmetic 34.8、dos 88.5、front_running/time_manipulation 178.0；uncheck（9.23）与 reentrancy（16.05）本就不被截断、**权重未变**，其指标波动只能归因于训练随机性，不可归因于本消融。
- 除 pos_weight 外，环境/超参/划分与主实验完全一致（3 种子）。

**表 1.8-a 汇总对比（3 种子 mean±std；基线 = §1.2，放开 = `runs/pw_unclamped/summary.json`）**

| 指标 | 基线（cap=20） | 放开截断 | Δ |
| --- | --- | --- | --- |
| micro-F1 固定 0.5（主） | **0.9058 ± 0.0397** | 0.8148 ± 0.0797 | **−0.091** |
| micro-F1 验证阈值 | 0.9492 ± 0.0145 | 0.9439 ± 0.0143 | −0.005 |
| macro-F1 固定 0.5 | 0.2300 ± 0.0428 | 0.1955 ± 0.0380 | −0.035 |
| macro-F1 验证阈值 | 0.2455 ± 0.0720 | 0.2420 ± 0.0892 | −0.003 |
| mAP | 0.4139 ± 0.1070 | 0.4294 ± 0.1783 | +0.016（方差大，seed2 0.63 拉高） |

**表 1.8-b 逐类 F1 对比（固定 0.5，3 种子 mean±std）**

| 类别 | 基线 F1 | 放开 F1 | Δ | 权重是否变化 |
| --- | --- | --- | --- | --- |
| access_control | 0.0000 ± 0.0000 | 0.0667 ± 0.1155 | +0.067 | 20→34.8 |
| arithmetic | 0.6556 ± 0.1503 | 0.3159 ± 0.0941 | **−0.340** | 20→34.8 |
| dos | 0.0000 ± 0.0000 | 0.0000 ± 0.0000 | 0 | 20→88.5 |
| front_running | 0.0000 ± 0.0000 | 0.0000 ± 0.0000 | 0 | 20→178 |
| reentrancy | 0.5664 ± 0.1127 | 0.5015 ± 0.1431 | −0.065 | 未变（噪声） |
| time_manipulation | 0.0000 ± 0.0000 | 0.0196 ± 0.0340 | +0.020 | 20→178 |
| uncheck | 0.3879 ± 0.0984 | 0.4650 ± 0.0184 | +0.077 | 未变（噪声） |

**表 1.8-c 受影响 5 类的机制证据（主种子 seed0；来源 `runs/{seed0,pw_unclamped/seed0}/diagnosis.json`）**

| 类别 | pos_weight 基线→放开 | 正样本概率 基线→放开 | 负样本 mean 基线→放开 | FP@0.5 基线→放开 | ROC-AUC 基线→放开 |
| --- | --- | --- | --- | --- | --- |
| access_control | 20→34.8 | 0.31→0.41 | 0.32→0.41 | 9→13 | 0.58→0.60 |
| arithmetic | 20→34.8 | 0.72→0.70 | 0.23→0.32 | 4→6 | 0.988→0.977 |
| dos | 20→88.5 | 0.22→0.44 | 0.16→0.32 | 0→6 | 0.773→0.773 |
| front_running | 20→178 | 0.10→0.23 | 0.07→0.20 | 0→0 | 0.75→0.68 |
| time_manipulation | 20→178 | 0.07/0.04→0.34/0.17 | 0.04→0.16 | 0→0 | 0.779→0.814 |

**结论（对 §1.7 改进思路 #2 的否定）**

1. **放开截断没有救活稀有类**：dos/front_running/time_manipulation 三 seed 仍 F1≈0。正样本绝对概率确被抬升（0.05–0.22 → 0.17–0.44），但仍低于 0.5 与验证集阈值；且 test_pos=1–2 下命中即 1、未命中即 0，本质是**样本量与排序上限**（oracle-F1 0.09–0.40），不是权重截断。
2. **放开截断反伤 arithmetic**（F1 0.656→0.316）：34.8× 权重使算术类过预测，FP@0.5 由 4→6、负样本 mean 0.23→0.32。
3. **uncheck/reentrancy 的波动是噪声**：二者权重未变，其 F1 变化（+0.077 / −0.065）不可归因于本消融，说明 3 种子下 F1 本身有 ±0.06–0.08 的随机涨落。
4. **净效应**：固定 0.5 下主指标 micro-F1 0.906→0.815（过预测 → FP 增加）、macro-F1 同步下降；验证集阈值下基本持平（阈值自适应吸收过预测）。→ **维持 `pos_weight` 截断 20 为主实验口径**；欠置信改进应转向**标定**（temperature scaling / per-class 阈值，仅补充不进主结果）与**数据侧**（阶段 G DIVE/SolidiFI 补稀有类样本），而非放开 pos_weight。

- **产物**：`runs/pw_unclamped/seed{0,1,2}/`（config.json 记 `pos_weight_cap`、results.json、diagnosis.json）+ `summary.json` + `diagnosis_summary.json`。

---

## 2. 消融（阶段 F，待执行）

5.4.1 必要消融（11 项）与 5.4.2 可选消融（6 项）→ `eval_results/ablation/`。未开始。

## 3. 基线（阶段 F，待执行）

Slither 规则七维命中 / CodeBERT 序列 / GCN（`conv_type="gcn"`）→ `eval_results/baseline/`。未开始。

## 4. DIVE 外部测试（阶段 G，待执行）

一次性评估，不参与训练/验证/早停/阈值/模型选择；用主种子 seed0 的 `best.pt` + 验证集阈值；M3 必须传 `--categories products/alldata/graphs/ir_cat.json` 冻结 IR 字典。→ `eval_results/dive/`。未开始。

## 5. SolidiFI 层次二（阶段 G，待执行）

a_v/s_v/g_v 三分数 + a_v 增量覆盖节点统计 → `eval_results/solidifi/`。未开始。
