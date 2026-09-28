# 结果表格文件索引（文件 · 表 · 用途 · 引用须知）

> **定位**：本文件是**索引**，不是数字来源。它回答「哪个文件里有哪张表、这张表回答什么问题、
> 它是不是程序生成的、引用前必须知道什么」。**表里的数字一律以产物与 §1 的权威源为准。**
>
> 编制日期 **2026-09-26**。口径基准：① 主库 `alldata(readonly)` / ② 增强集 `alldata_augmentation`；
> ① 现行正典 = **微调 CodeBERT 20 轮档**（`products/alldata/graphs_ft_p2/cb_ft_ss{S}`）。
>
> 收录口径：**含实验结果表格**的文档（含 `.md` 外的登记产物入口）。设计/规则/状态表
> （`docs/M4_interface.md`、`论文开发手册.md`、`Todo_List.md` 等）**也列出但标注「非结果表」**，
> 以免读者误当数字源。

---

## 0. 三条通用读表规则（所有文件都适用）

1. **①/② 两组结果集不可比、不可合并、不可相减**（`decisions.md` §23）。跨组比较是读表第一大坑。
2. **n=3 只作描述性**。重跑抖动实测 ≈0.012，种子间 std ≈0.0675 ⇒ |Δ| < 0.012 **先天不可判定**；
   要下方向性结论须**同配对 ≥9 点**（`decisions.md` §26.7/§27.5）。
3. **逐类 F1 必须与 support 同读**。① 主库 test 逐类正样本只有 1–7（`dos`/`front_running` 各 1），
   单类 F1 一次翻转差 0.67 ⇒ support ≤2 的类**仅描述性呈现、不进方法间比较**（大纲 5.1/5.2）。

---

## 1. ⭐ 权威数字来源（先看这几个，其余都是二次呈现）

| 权威源 | 权威性声明出处 | 生成方式 |
| --- | --- | --- |
| `研究点一细化大纲改II.docx` | `AGENTS.md`「权威文档（冲突时按此优先级）」第 1 位 = **最高权威** | 人写 |
| **`experiments/canonical_ft_numbers.md`** | `项目组织架构.md`：「全仓新口径数字的**权威出处**」（2026-09-20） | ✅ `scripts/collect_canonical_numbers.py --write`。🔴 **缺 `runs/error_rates.json` 直接 `SystemExit`** |
| **`runs/error_rates.json`**（+ `runs/error_rates.md`） | `log.md`「两份权威源」；合约级 F1 / 误报率 / 漏报率的唯一出处 | ✅ `scripts/error_rates.py`（零重训；⚠ 见 §6-(3)） |
| `experiments/decisions.md` | `项目组织架构.md`「决议与口径裁定（**权威**）」 | 人写（**含 120+ 张表，很多结果的原始落点**） |
| `experiments/results.md` | `项目组织架构.md`「实验结果记录（**权威**；数字与产物冲突时以产物为准）」 | 人写 |
| `docs/data_funnel.md` | 自述：「**论文里出现的每个样本/标签数字都应能在下表中找到出处；下表未列出的数字不得写进论文**」 | ✅ `scripts/audit_data_funnel.py` |
| `experiments/report_data.md` | `项目组织架构.md` 明标「由 runs/ 产物直接聚合，**非权威**」 | 手写汇编 |

---

## 2. 一页速查

### `experiments/`（结果表主区）

| 文件 | 行数 | 表数 | 程序生成 | 生成脚本 | 语料 | 一句话用途 |
| --- | --- | --- | --- | --- | --- | --- |
| `results.md` | 1081 | ~33 | ❌ 手写 | — | ①② | M5 各阶段执行记录（命令/环境/超参/指标/计时），**数字权威但部分小节未随换代刷新** |
| `canonical_ft_numbers.md` | 170 | 7 | ✅ | `collect_canonical_numbers.py` | ①② | **权威数字载体**：逐种子 / 逐类 / 消耗 |
| `per_class_three_caliber_tables.md` | 656 | 13 | ✅ | `collect_three_caliber_tables.py` | ①②+DIVE | 逐类 F1 × 三口径（micro/buggy/macro）× 两工作点 |
| `per_class_three_caliber_tables_buggy.md` | 374 | 13 | ✅ | 同上 | ① 池 497 | 同上，但正典 = `runs/buggy_canon`（含 `buggy_*`） |
| `per_class_binary_thr_ablation.md` | 98 | 3 | ✅ | `collect_per_class_binary_thr.py --write` | ① 池 453 / 池 497 | **逐类 binary-F1 @逐类验证集阈值**：正典 + 21 个消融臂（两池各一表），末两列 micro/macro 同工作点 |
| `baseline_three_caliber_tables.md` | 725 | **28+** | ✅ | `collect_baseline_tables.py` | ① 池 453 / 池 497 | **大纲 5.3 对比表主表**：本文方法 + 三论文基线 + 六传统工具 |
| `main_aug_f1_summary.md` | 151 | 7 | ✅ | `collect_main_aug_f1_summary.py`（`--check` 逐格对拍） | ①② | **两语料同表**：① 与 ② 各一行 + **`micro-F1` 与 `macro-F1` 两列并排**；② 上基线/工具的 `—` = **未跑**（§4 逐条点名） |
| `confusion_counts.md` | 164 | 6 | ✅ | `audit_confusion_counts.py`（**自带对拍**） | ①② | **micro/macro 背后的 TP/FP/FN**：池化计数（表 A）+ ① ② 逐类计数（表 B/C，两工作点） |
| `traditional_tools_results.md`（+`.json`） | 347 | 12 | ✅ | `collect_traditional_tools.py` | ① | 六工具的**读表前提**：检测项→七类映射、能力边界、覆盖率、成本 |
| `ablation_results.md` | 1561 | ~30 | ❌ 手写 | （`aggregate_results.py` 出数） | ①② | 消融 **n=3 第一代**完整记录（21 臂） |
| `ablation_n9_results.md` | 133 | 6 | ✅ | `collect_ablation_n9.py` | ⚠ **仅 ②** | 消融 **n=9 同配对**复核：哪些 n=3 读数翻了 |
| `ablation_three_metric_table.md` | 364 | 13 | ✅ | `collect_ablation_three_metric.py --write` | ①② | 消融三口径（Micro/Buggy×2/Macro/mAP）四张主表 |
| `dive_external_results.md` | 519 | ~17 | ❌ 手写（`collect_dive_comparison.py` 复算数） | — | ①→DIVE | DIVE 外部测试 + 三方并列，**整代表格仍是 5 轮档** |
| `buggy_canon_summary.md` | 113 | 6 | ✅ | `collect_buggy_canon_summary.py` | ① 池 497 | 补回 `buggy_*` 后的新正典，含**标签假象**的 `clean_only` 诊断列 |
| `gcn_baseline_and_per_class_f1.md` | 221 | 5 | ❌ 手写（数据源程序生成） | `collect_per_class_f1.py --check` | ①② | 逐类 F1 三工作点 + 关系盲 GCN 基线（负面结果） |
| `perclass_arm_results.md` | 82 | 4 | ✅ | `collect_perclass_arm.py` | ① | 7 个独立二分类器 vs 七维共享：**共享是否压制稀有类** |
| `p1_gains.md` | 78 | 3 | ✅ | `collect_p1_gains.py` | ① | P1 三笔零重训头寸：替代工作点 / 多种子集成 / bootstrap CI |
| `improvement_proposals.md` | 236 | 9 | ❌ 手写 | — | ① | 诊断与建议（含「建议是否高于噪声底线」判定） |
| `improvement_round1_results.md` | 245 | 9 | ❌ 手写 | — | ① | 上表的**执行记录**（含 epoch 探针、Slither 实测） |
| `report_conclusions.md` | 1206 | ~25 | ❌ 手写 | — | ①② | **结论卷**（分析建议，非决议）：该关哪些实验线 |
| `report_data.md` | 711 | ~18 | ❌ 手写 | — | ①② | **数据卷**（非权威汇编） |
| `cb_unlimited_reach.md` | 94 | 4 | ✅ | `audit_cb_unlimited_reach.py` | ① | `cb_unlimited` 干预触达审计（效应量为 0 的证据） |
| `encoder_promotion_gate.md` | 61 | 4 | ✅ ⚠ **缺「程序生成」抬头** | `check_encoder_promotion.py --out` | ① | 编码器换代闸门：5 轮 vs 20 轮逐种子配对 |
| `decisions.md` | 4758 | **120+** | ❌ 手写 | — | ①② | **决议卷**：口径裁定；⚠ **含大量真实结果表**（许多结果的原始落点） |
| `ablation_plan.md` | 722 | ~10 | ❌ 手写 | — | — | 消融**计划**（**非结果表**，仅状态/开关矩阵） |

### `eval_results/`（5 份**全部**程序生成）

| 文件 | 行数 | 表数 | 生成脚本 | 一句话用途 |
| --- | --- | --- | --- | --- |
| `ablation/collected.md` | 270 | 6 | `collect_ablation_results.py` | 消融汇总 ①（**第一代 n=3**，最佳种子 + 3 种子 + Δ + 配对 t + 逐类） |
| `ablation/collected_aug.md` | 270 | 6 | 同上 | 同构，语料 = ② 增强集 |
| `bootstrap/main.md` | 16 | 1 | `oof_bootstrap.py` | 合约级 bootstrap 95% CI + 按 support 加权 macro |
| `dive/comparison.md` | 277 | ~12 | `collect_dive_comparison.py` | 三方并列（①内测/②内测/DIVE(①)/DIVE(②)），**DIVE 两列永久停在 5 轮档** |
| `ensemble/cbft_study_cbft.md` | 14 | 1 | `ensemble_eval.py` | 同划分多种子概率集成（结论：未获益） |

### `docs/`

| 文件 | 行数 | 表数 | 程序生成 | 性质 |
| --- | --- | --- | --- | --- |
| `data_funnel.md` | 152 | 5 | ✅ `audit_data_funnel.py` | **结果/口径数字表**：846→591 拆解、逐级出处+复现命令、图结构口径 |
| `cb_func_gap.md` | **5696** | 2 | ✅ `audit_cb_func_gap.py` | **修复前**缺口快照（缺口 37.6%）；🔴 不得当现行数字 |
| `cb_func_gap_after.md` | 489 | 2 | ✅ 同上（`--tag _after`） | **现行**缺口快照（2.52%） |
| `M5_dev_plan.md` | 382 | 3 | ❌ | 设计稿（**非结果表**）；§0 前有旧 448 池作废警告 |
| `baseline_dev_plan.md` | 126 | 2 | ❌ | 5.3 基线接入计划（**非结果表**）+ 实测坑清单 |
| `M3_frontend_design.md` | 389 | 7 | ❌ | M3 设计稿（**非结果表**，头部夹带实测数字） |
| `M4_interface.md` | 153 | 3 | ❌ | 接口规范（**0 个结果数字**） |
| `residual_gaps.md` | 131 | 2 | ❌ | 缺口待办 + 数据出处表 |
| `cb_func_gapfix_plan.md` | 150 | 3 | ❌ | 缺口修复执行计划 |

### 仓库根 / `runs/`

| 文件 | 行数 | 表数 | 性质 |
| --- | --- | --- | --- |
| `log.md` | 1189 | 8 | 开发日志，**唯一「日志里夹带结果表」**的文件（含换代代价、五工具解析陷阱、SolidiFI 6/6）；**当前状态以它为准** |
| `论文开发手册.md` | 1577 | 12 | **非结果表**（规则/路径/映射）；结果数字在开头第 16–65 行引用块 |
| `Todo_List.md` | 651 | 5 | **非结果表**（任务/状态）；§12.7.1 是 5.3 对比实验的大纲原文重列 |
| `项目组织架构.md` | 497 | **0** | **无表**，但是「哪些文件是程序生成」的索引入口 |
| `runs/error_rates.md` | 47 | 3 | **权威源之一**：L3 合约级二分类 / L1 标签对级 micro / L2 逐类 FPR-FNR |
| `runs/error_rates_ablation_aug.md` | 108 | 3 | ② 与消融臂的同三层口径表 |
| `runs/prior_*/README.md`（6 个） | 27–58 | 小表 | 各**作废/归档口径**说明 + 位置对照（`prior_badmetric`/`dropout80`/`frozen`/`canon37`/`buggy16`/`probes`） |

---

## 3. 分组详解

### A. 主结果与总表

- **`results.md` §0 两组结果集总表** —— 全仓最常被引用的表：① 主库 vs ② 增强集（池/逐类正样本/
  标签结构/近重复对/六项指标/划分/产物/计时）并排。**① 已按 20 轮档逐格刷新；② 未换代、逐位未变。**
- 其余小节（§1.2 汇总 / §1.3 逐种子 / §1.4 逐类 / §1.5 计时 / §1.7 逐类诊断 / §1.8–§1.10 干预 /
  §6 第二数据集）**多数未逐格刷新** ⇒ 引用前回产物核对。
- **`main_aug_f1_summary.md`** —— `results.md` §0 那张总表的**逐类展开版**：同样两语料并排，
  但列换成 **7 类逐类 F1 + `micro-F1` + `macro-F1`**，并把 5.3 的基线/工具一并铺进同一网格。
  它是「一张表回答 ② 上基线是多少」的唯一落点（答案是**没跑**，§4 点名）。
  ⚠ 与 `results.md` §0 的六项指标**不重复**：那张汇总口径，这张逐类 + 两列汇总。

### B. 逐类三口径（程序生成，最可复现的一族）

- 三口径 = `micro`（全测试集标签对级）/ `buggy`（仅 `y.any()` 合约子集）/ `macro`（7 类未加权平均）。
- 🔴 **表 1–6 = 最佳种子（① seed1 / ② seed1）单种子、无方差**；表 7–12 才是 3 种子 mean±std。
- 🔴 **`macro` 表与 `micro` 表的逐类格逐位相同** —— macro 就是那 7 个数的平均，**恒等不是重复**。
- 🔴 `buggy` 段的池是 **497**（test 49），与 ① 的 46 **不是同一测试集**，两边数字**不可相减**。
- **`per_class_binary_thr_ablation.md`**（2026-09-27 新增）= **逐类阈值工作点**的消融版：
  正典 + 21 臂 ×（池 453 / 池 497）。它与 `ablation_three_metric_table.md` 的**行名、层名、臂集合完全相同**，
  唯一差别是**工作点**（那张表 = 七类共享一个 `val_threshold`；本表 = 阈值逐类各一）⇒
  两表数字**不得互相替代**；本表的 micro/macro **不是**任何单点工作点的读数。两条机检见该文末。

### C. 消融（三代并存，务必分清）

| 代 | 产物 | 报告 | n | 能回答什么 |
| --- | --- | --- | --- | --- |
| 第一代 | `runs/ablation{,_aug}/` → `eval_results/ablation/collected{,_aug}.{json,md}` | `ablation_results.md` | 3 | 只作历史留痕 |
| 第二代 | `runs/ablation_n9{,_aug}/` | `ablation_n9_results.md` | **9** | 哪些 n=3 结论翻了（**实测 6 个臂符号翻转**） |
| 第三代 | `runs/ablation_buggy/` | `per_class_three_caliber_tables_buggy.md` | 3 | 池 497 上的消融（**含标签假象**） |

- `ablation_three_metric_table.md` 是**独立于上述三代**的三口径复算，含 §1.3「本测试集对大多数
  消融项**没有检出力**」的量化。
- 🔴 `ablation_results.md` 是**双重旧口径**（n=3 **且** 5 轮档编码器），**只作历史留痕**。

### D. 5.3 对比实验

- **主表 = `baseline_three_caliber_tables.md`**（两段两个正典：§一 池 453 / §三 池 497）。
  含：逐类 support、图与特征来源、训练成本、**合约级二分类口径（含平凡下限与净技能）**、
  表 1–14（§一）、表 15–28（§三）。口径声明与逐行声明**全部在文末「附」**。
- **`traditional_tools_results.md`** = 六工具的**读表前提**（映射尺 / 能力边界 / 覆盖率 / 成本），
  数字本身在主表的六行里。
- 🔴 报告口径里 **GCN / CodeBERT 文本基线已作废**（大纲 5.3 表里既无 CodeBERT、也无 GCN/GAT）。

### E. DIVE 外部测试

- `dive_external_results.md`（分析） + `eval_results/dive/comparison.{json,md}`（数据）。
- 🔴 **`comparison` 是「混代」artifact**：内测两列已随 2026-09-25 换代重算，**DIVE 两列仍是换代前旧树**；
  用户已裁定 DIVE 21 臂矩阵**不重跑** ⇒ DIVE 列**永久停在 5 轮档**。
- 🔴 旧代 ① DIVE 特征树（`products/dive/graphs_ft/ss{S}`）已**原地覆盖、不可重建**，
  旧读数只存在于 `matrix_main.json` / `matrix_aug.json`。
- 最重要的单张表 = **表 3b（逐类 PR-AUC vs 随机基线）**：把「F1 掉了」拆成「先验变了」与「排序退化了」。

### F. 诊断 / 稳健性 / 补充口径

- `gcn_baseline_and_per_class_f1.md`：逐类 F1 三工作点 + per-class 阈值的**过拟合审计**；§4 是
  一个**必须诚实报告的负面结果**（关系感知 vs 关系盲在 ① 上分不开）。
- `perclass_arm_results.md`：7 个独立二分类器臂；关键读数是 **§2 净技能**（二分类口径平凡下限 0.62
  vs 七维 0.12 ⇒ **两个口径的数字不可互比**）。
- `p1_gains.md` / `improvement_*.md`：零重训的三笔头寸与执行记录。
- `cb_unlimited_reach.md`：结论是「**本设计在该语料上测不出这条干预的效应**」。
- `encoder_promotion_gate.md`：换代闸门 G1/G2/G3；⚠ 提升的实质是 **epoch 预算（5→20）**，
  **不是 SWA**（实测 `n_averaged = 0/0/2`，选点全是 `best_epoch`）。

### G. 数据与口径溯源

- `docs/data_funnel.md`：**写进论文的每个样本/标签数字的唯一出处**。
- `docs/cb_func_gap{,_after}.md`：函数级 CodeBERT 通道缺口的前后快照。
- `runs/error_rates.{json,md}`：三层错误率（L1 标签对级 / L2 逐类 / L3 合约级）。

### H. 归档与草稿区（**不入库**）

- `runs/prior_*/`：六代作废/归档口径的产物与 README（**完整保留、可审计**，`aggregate_results.py`
  按 `prior_` 前缀自动排除）。
- `runs/_snap/`：分析中途的临时件（换代前后对照快照、事实清单等），`.gitignore` 第 64 行排除。
- `runs/_tools_work/`：传统工具的源码副本与中间产物，`.gitignore` 第 70 行排除。

---

## 4. 🔴 引用前必读（按陷阱聚类，不按文件）

| 陷阱 | 涉及文件 | 要点 |
| --- | --- | --- |
| **换代横幅（5 轮 → 20 轮，2026-09-25）** | `results.md`、`report_data.md`、`ablation_results.md`、`dive_external_results.md`、`论文开发手册.md`、`docs/M5_dev_plan.md` | 只有 `canonical_ft_numbers.md` + `runs/error_rates.json` 是现行；其余多数仍是旧代 |
| **四代作废口径** | 全部 | 448 池 / dropout-80 语义 / 坏指标 `.ravel()` / 冻结编码器 —— 各代归档见 `runs/prior_*` |
| **单种子无方差** | `per_class_*` 表 1–6、`baseline_*` 表 1–8、`dive_external_results.md` | 最佳种子口径**不得**据以下「某干预有效」结论 |
| **跨段/跨列不可相减** | `baseline_three_caliber_tables.md`（池 453 vs 497）、`per_class_*_buggy.md`（46 vs 49）、`dive/comparison.md`（四列四种条件） | 可比的只有**同列/同段内的 Δ** |
| **标签假象** | `buggy_canon_summary.md`、`per_class_three_caliber_tables_buggy.md`、`report_conclusions.md` | `buggy_*` 标签绝大多数七类全 1 ⇒ 全报有漏洞即可满分 |
| **逐类阈值是「并列口径」不是主口径** | `per_class_binary_thr_ablation.md`、`baseline_three_caliber_tables.md`（表 1/15）、`gcn_baseline_and_per_class_f1.md`、`p1_gains.md`、`perclass_arm_results.md` | 换逐类阈值后 **macro 升、micro 降**；① 主库 val 每类仅 1–3 正样本（`dos` 阈值三种子极差 0.55）⇒ 其 std 含**阈值抖动**、不得读成纯模型方差 |
| **`—` 有三种成因** | `traditional_tools_results.md`、`baseline_three_caliber_tables.md`、`main_aug_f1_summary.md` | (a) 工具不提供该检测项；(b) 整行不可评估；(c) **尚未评测**。**真实 0 一律保留**。⚠ `main_aug_f1_summary.md` 的 `—` **只有 (c) 一种**（② 上基线/工具整块未跑，§4 逐条点名）⇒ 两张表的 `—` **不可互相套用读法** |
| **覆盖率不是随机缺失** | `traditional_tools_results.md`、`log.md` | 真实池 0.4.x 38% 含漏洞 / 0.5.x **0%** ⇒ Securify 可分析集恰好全是干净合约 |
| **程序生成 ≠ 可重跑** | 见 §6-(1) | 五个 `collect_*.py` 的 `--out` 默认空串（只打印），两个还要 `--write` |

---

## 5. 「文件在盘上」不等于「可重跑复现」

以下脚本**默认不落盘**，重跑必须显式带参数（这是本索引最容易踩的坑）：

| 脚本 | 落盘条件 | 复现命令 |
| --- | --- | --- |
| `collect_three_caliber_tables.py` | `--out` 默认 `""` | `--out experiments/per_class_three_caliber_tables.md` |
| `collect_baseline_tables.py` | `--out` 默认 `""` | `--out experiments/baseline_three_caliber_tables.md [--with-buggy]` |
| `collect_perclass_arm.py` | `--out` 默认 `""` | `--out experiments/perclass_arm_results.md` |
| `collect_p1_gains.py` | `--out` 默认 `""` | `--out experiments/p1_gains.md` |
| `collect_ablation_three_metric.py` | `--out` 有默认，但需 `--write` | `--write` |
| `collect_canonical_numbers.py` | 需 `--write` | `--write` |
| `check_encoder_promotion.py` | `--out` 默认 `None` | `--out experiments/encoder_promotion_gate.md` |
| `collect_per_class_binary_thr.py` | 需 `--write`（另落 `eval_results/per_class_binary_thr.json`） | `--write` |
| `collect_main_aug_f1_summary.py` | `--out` 默认 `""`；另有 `--check`（**建议先跑**） | `--check` → `--out experiments/main_aug_f1_summary.md` |
| `audit_confusion_counts.py` | 无（**只打印**），另需 `--out` | `--out experiments/confusion_counts.md` |
| `aggregate_results.py` / `audit_graph_fingerprint.py` | **从不落盘**（仅 stdout / 仅只读） | 不要期待有对应文件 |

另有两份文档曾**长期自称「程序生成」实为手写**（`canonical_ft_numbers.md`、`ablation_three_metric_table.md`），
2026-09-25 才补上生成脚本 ⇒ **换代后必须重跑这两个脚本**。

---

## 6. 三处已核实的不一致 / 待办（供作者裁定）

1. ⚠ **`ablation_n9_results.md` 只渲染了 ②，① 的表没进报告**（本次实测）：
   `eval_results/ablation/n9_main.json` 存在且完好（`group='main'`、9 对齐全、31 臂、
   `baseline_missing=[]`），而报告正文只有「## ② 增强集」一节；报告 mtime（2026-09-25 17:07:59）
   与 `n9_summary.json`（`group='aug'`）**同一时刻**、而 `n9_main.json` mtime 是 2026-09-21
   ⇒ 极可能是上次按 `--group aug` 跑的。补法：`python scripts/collect_ablation_n9.py --group both`
   （⚠ 会**同时改写** `--out` 与 `--json-out` 两个默认目标，重跑前先确认）。
2. ⚠ **`runs/error_rates.md` / `error_rates_ablation_aug.md` 没有脚本落盘点**（本次实测）：
   `scripts/error_rates.py` 只 `print()` markdown、`--out` 只写 `.json`；`runs/_p5_collect.sh`
   也只调 json ⇒ 这两份 `.md` 是 **stdout 重定向**的产物，**与 json 无自动同步保证**。
   引用一律以 `runs/error_rates.json` 为准。
3. ⚠ **`canonical_ft_numbers.md` 的「C. 训练消耗」是项目符号而非表格**（§A/§B/§D 都是表格）。
   是否有意为之**未确认** —— 若要求「程序生成」格式统一，此处格式不齐。

---

## 7. 与既有文档的分工

- **本文件**：哪个文件有哪张表 + 引用须知（索引层）。
- `项目组织架构.md`：目录结构与状态（**哪些文件是程序生成的索引入口**，0 张表）。
- `docs/data_funnel.md`：**样本/标签数字**的出处。
- `experiments/decisions.md`：口径裁定与决议。
- `log.md`：当前状态（`Todo_List.md` 顶部明示「当前状态以 `log.md` 为准」）。

> 若本文件与上述任一冲突，**以它们为准**并回报修正本文件。
