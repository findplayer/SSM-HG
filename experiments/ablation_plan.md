# 消融实验执行计划（阶段 F；2026-09-16 准备完成 → 2026-09-17 按重训后口径更新 → **2026-09-17 首跑完成**）

> ✅ **结果与数据见 `experiments/ablation_results.md`**（首轮 12 项 × 3 种子 = 36 run、793.0 s、失败 0；
> 单变量验收 12/12 通过）。**累计现行：①②各 21 臂 × 3 种子 = 126 run、失败 0**（`decisions.md` §38）。
> ⚠ 该文是 **n=3 描述性**结果、**不作方向性结论**（§7 验收清单已载此纪律）。
> 本文仍是**执行计划**（命令、目录、就绪盘点）；**原「未跑 4 项」已全部落地**，见 §0 与 §3/§3.1 的 🔴 注。

> 🔴🔴 **2026-09-19 重大变更：本文的「正典」定义已改变，§6.4 的定位随之反转（`decisions.md` §37）。**
> 用户裁定把「**微调 CodeBERT**」**升为主设计**、把「冻结 CodeBERT」降为消融/对比
> （依据是 §36 的 n=9 同配对复核：test 侧 8/8 指标显著，`micro@0.5` +0.2466，t=+11.92）。
> 因此：
> - **本文 §6.4「第 17 项：微调 CodeBERT vs 冻结」已执行完毕，且该项已不再是消融项** ——
>   它现在是正典本身。消融表里的对应项反转为 **`cb_frozen`**（冻结）。
> - 大纲 `改II` 5.4.2 已同步反转；**全部消融臂已相对新正典重跑**（① 21×3 + ② 21×3 = **126 run**、失败 0；
>   旧载「② 5×3 = 78 run」是 2026-09-19 首稿的计数，② 后由 5 臂扩到 21 臂与 ① 逐臂对齐，见 `decisions.md` §38）。
> - 本文其余内容（命令、目录、就绪盘点）作为**当时的执行记录**保留，**不再代表现行口径**；
>   现行口径见 `decisions.md` §37、`ablation_results.md` 与 `eval_results/ablation/collected*.md`。

> 🔴 **2026-09-20 口径刷新：本文引用的「正典」指标数字，凡属冻结编码器口径的一律已作废。**
> 现行值（test；逐位出处 `experiments/canonical_ft_numbers.md` 与 `runs/error_rates.json`）：
> ① micro-F1@0.5 **0.7110±0.0389**、micro-F1@val_thr **0.7297±0.0675**、macro-F1@0.5 **0.6091±0.0751**、
> macro-F1@val_thr **0.4986±0.0452**、mAP **0.7582±0.0056**、合约级二分类 F1@val_thr **0.9419±0.0385**
> （合约级误报率 **2.62%** / 漏报率 **8.02%**）；② micro-F1@0.5 **0.9901±0.0100**、mAP **0.9975±0.0025**。
> ⚠ **池大小（① 453）、划分、训练超参、参数量（415,226）与语料构成均未变**——变的只有编码器。

> 依据：大纲 `改II` 5.4.1 必要消融（11 项）+ 5.4.2 可选消融（6 项），共 **17 项**。
> 本文只做**准备与配方**：每项的确切命令、输出目录、前置条件、就绪状态、验收项。
> 决议与缺口记于 `experiments/decisions.md` §25；开关接线由 `tests/test_ablation_switches.py` 机器验证。
>
> 🔴 **2026-09-17 更新要点**（因 `metrics.micro_f1` 修复 + 全量重训，`decisions.md` §28）：
> 1. **基线换了**：正典 `runs/seed{0,1,2}/` 已用修正后的 micro-F1 重训，**它就是"全开关默认"的对照组**，仍无需重跑。
> 2. **工期上调**：早停不再在 6 epoch 内触发，单种子 wall 由 10–15 s 升至 **≈30 s**，12 项 × 3 种子 ≈ **20 分钟**（原估 15 分钟）。
> 3. **正典 std 收窄**：micro-F1@0.5 的种子间 std 由 ±0.0699 → **±0.0309**。判定纪律**不变**（仍须同配对 ≥9 点，§26.7/§27.5）。
>    （⚠ 2026-09-20：该 **±0.0309** 为**冻结编码器**口径，已作废；§37 新正典下为 **±0.0389**。）
> 4. **新增驱动脚本** `scripts/run_ablation.py`：把 §2 的模板固化为矩阵，并在开跑前**断言每项只改了一个开关**（见 §0.1）。
> 5. **补齐了 5.4.2 的 6 项**——此前计划只列了 5.4.1 的 11 项，5.4.2 散落在 `Todo_List.md`。见 §3.1。

## 0. 就绪总览（2026-09-17 复核）

| 状态 | 项数 | 说明 |
| --- | --- | --- |
| ✅ **已跑完** | **21 臂 / 126 run** | 见 §3 与 §3.1 的矩阵；结果与数据见 `ablation_results.md`（首轮 16 项配置 = 48 run、≈19 min；§38 后 ① 21×3 + ② 21×3 = **126 run**、失败 0） |
| ✅ **取值已裁定** | 0 | `num_bases`→1/3/4、`drop_edge_prob`→0.2（2026-09-18 用户裁定采用本计划建议值；`num_bases` 因实现约束修正，见 §3.1） |
| ⚠️ **需先造 M2 变体** | **0**（原 1） | CALLBACK_RISK 上限 4 vs 不限制——变体 `products/alldata/graph_variants/callback_unlimited` 已建成、臂 `cb_unlimited` 已跑（2026-09-20 复核） |
| ✅ **已解除阻断** | **1** | 「关闭先验 Dropout」——`--prior-dropout` 已于 2026-09-16 修正为**丢弃率**语义，`--prior-dropout 0` 现为「关闭」 |
| ✅ **需开发** | **0**（原 3） | 三项**均已落地并跑完**（2026-09-20 复核）：`--callback-rev`（臂 `cb_rev`）、`--layers`（臂 `layers1` / `layers3`）、`finetune_codebert.py`（**已升为正典本身**，见 `decisions.md` §37） |

**结论（2026-09-18 更新）：大纲 17 项中 13 项已跑完并记录 = 16 个配置**（`ablation_results.md`）——
「项」与「配置」不是同一个计数，**勿混用**：第 11 项（特征分组）去掉了正典已含的 `all` 只剩 2 个配置，
第 14 项（`num_bases`）按剂量-反应扩成 1/3/4 共 3 个配置 ⇒ 13 项 = 11×1 + 1×2 + 1×3 = **16 个配置**。
~~余下 **4 项**：1 项需造 M2 变体（CALLBACK_RISK 上限）、3 项需开发（CALLBACK_RISK_REV / RGCN 层数 / 微调 CodeBERT）。~~
🔴 **余下 0 项**（2026-09-20 更正）——四项已分别落地为 `cb_unlimited` / `cb_rev` / `layers1`+`layers3`，
「微调 CodeBERT」更已升为正典本身（§37）。

> 🔴 **2026-09-20 复核：上表「需造 M2 变体 1 项 + 需开发 3 项」已全部落地，本计划的就绪盘点归零。**
> 四项分别落在 `runs/ablation{,_aug}/` 下的 `cb_unlimited`、`cb_rev`、`layers1`/`layers3` 四个臂上；
> 唯一的例外是**微调 CodeBERT**——它已由消融项**升为正典本身**（§37），消融表里的对应项反转为 `cb_frozen`。
> 故**大纲 17 项已全部跑完**——按 §3 的「项/配置」计数法展开为 **20 个配置 / 21 个臂**
> （计数已逐目录复算，见 `ablation_results.md` §1；⚠ 本仓的消融计数**已写错两次**，引用前请复算）；
> ① 与 ② **各 21 臂 × 3 种子 = 63 run**（合计 126 run、失败 0，`decisions.md` §38）。
> 本文 §3–§3.1 的 16 项矩阵、§5 与 §6 的「未跑项」清单及其命令，均为**当时的执行记录**，不再代表现行状态。

> 🔴 **2026-09-18 补：未跑 4 项的开发方案已成文，见 §6**（含一个改变可行性判断的前置发现：
> `_cb.pt` 有 **35 倍存储膨胀**，第 17 项从「磁盘不可行」变为「约 1.1 GB」；§6.0）。
> 同时更正 §5 的划分配方（**不得重建划分，必须复用基线划分**）与新增一项安全缺口（**M2 无覆盖守卫**，§6.5）。

### 0.1 驱动脚本与"单变量"断言（新增，2026-09-17）

```bash
python scripts/run_ablation.py --dry-run          # 打印矩阵 + 逐项断言
python scripts/run_ablation.py --only meanpool --seeds 0   # 小样
python scripts/run_ablation.py                    # 全量（36 个 run）
```

**它存在的理由**：消融的全部价值在于「只有一个变量在动」（§7 验收第 1 条）。手敲
`for S in 0 1 2; do python scripts/train.py ... <FLAG>; done` 时，漏一个 `--graph-dir`、
把 `--split-seed $S` 写成 `--split-seed 0`、或**顺手多带一个开关**，都会静默产出
"看起来是消融、其实是另一个实验"的结果，而且**不会报错**。
（本仓已两次栽在这类"不报错的错"上：§28 的 `.ravel()`、§29.4 的 `diagnose.py` 标签源。）

脚本以**正典 `runs/seed0/config.json::args` 为唯一基线**，对每项只覆盖一个键，
开跑前用 `run_guard.diff_args` **断言差异恰为该键**，不满足即中止。

**冒烟实测（2026-09-17）**：`--only meanpool --seeds 0` → 29.5 s 完成；
从**产物**独立复核 `runs/ablation/meanpool/seed0/config.json` vs 正典，除记账键外差异
**恰为 `meanpool: False → True`** 一条。该 seed0 已保留（全量跑时驱动会跳过，省一次）。

## 1. 目录约定（避免覆盖正典，全部走 `run_guard`）

```text
runs/ablation/<item>/seed{0,1,2}/     # 训练产物（train.py --out-dir runs/ablation/<item>）
runs/ablation/<item>/summary.json     # 3 种子汇总（evaluate.py --summarize）
eval_results/ablation/<item>.json     # 汇总后的对照表（人工/diagnose 产出）
products/alldata/graph_variants/<name>/   # 仅 M2 类消融需要的图变体（见 §2）
```

**`train.py` / `make_splits.py` / `m3_build_features.py` 默认拒绝覆盖**：`--out-dir` 指向已有实验且参数不同时会报错退出，
需 `--overwrite` 才覆盖。消融一律**新开 `--out-dir`**，不要加 `--overwrite`。

## 2. 共享前置（所有消融项都相同）

主实验口径不变：池 453、划分 `products/alldata/splits/`、
超参取 `runs/seed0/config.json::args` 的默认值。**每条命令只改一个开关**，其余全部保持默认。

> 🔴 **正典路径已于 2026-09-19 变更（`decisions.md` §37），本节以下命令块是那时的执行记录，按现行口径已不再正确。**
> 变更点：正典 `graph_dir` 由 `products/alldata/graphs`（**冻结** `_cb.pt`）改为
> **`products/alldata/graphs_ft/ss{S}`（微调）**——**路径含划分种子 ⇒ 必须逐种子展开**，
> 不能写成固定路径；`products/<语料>/graphs` 现在对应的是**消融臂 `cb_frozen`**，不再是正典。
> 消融臂还需逐种子取编码器树（`canonical_args()` 已把 `graph_dir` 模板化，见 §37.5）。
> 另：`graph_variants/cb_ft_ss{S}` 已**改名**为 `graphs_ft/ss{S}`（理由见 §37.3），
> 旧路径只留兼容软链，**新命令不要再用**。
> 本节的**数字与臂清单仍是有效记录**（§3/§3.1 的 16 项矩阵、§5/§6 的未跑项），只是命令模板须按上述改写。

```bash
# 模板：<ITEM>=消融名，<FLAG>=该消融唯一的那个开关
for S in 0 1 2; do
  python scripts/train.py  --seed $S --split-seed $S \
      --graph-dir products/alldata/graphs --split-dir products/alldata/splits \
      --out-dir runs/ablation/<ITEM> <FLAG>
  python scripts/evaluate.py --seed $S --graph-dir products/alldata/graphs \
      --split-dir products/alldata/splits --runs-dir runs/ablation/<ITEM>
done
python scripts/evaluate.py --summarize --runs-dir runs/ablation/<ITEM>
```

单种子 wall **≈30 s**（GPU，2026-09-17 重训后实测：epoch 数由 6–7 升至 14–23），
故 **12 项配置 × 3 种子 ≈ 20 分钟**。**对照组不需要重跑**：正典 `runs/seed{0,1,2}/` 即"全开关默认"的基线
（已按修正后的 micro-F1 重训，`decisions.md` §28）。

> 上表的 `for` 循环是**人工执行的模板**，仅供理解；实际开跑请用 `scripts/run_ablation.py`（§0.1）——
> 它会断言每项只改一个开关，并在每个 run 成功后剪除 `last.pt`（36 个 run 可省 ≈180 MB）。

## 3. 5.4.1 必要消融（11 项）

| # | 消融项 | 唯一开关 | 状态 |
| --- | --- | --- | --- |
| 1 | 去 DFG_DEP | `--drop-edges 3` | ✅ |
| 2 | 去 CFG_FLOW | `--drop-edges 0` | ✅ |
| 3 | 去 AST_PARENT | `--drop-ast`（= relation 1+2） | ✅ |
| 4 | 去 CALLBACK_RISK | `--drop-edges 4` | ✅ |
| 5 | CALLBACK_RISK 上限 4 vs 不限制 | M2 变体，见 §5 | ⚠️ |
| 6 | 去函数级 CodeBERT | `--cb-channels cb_node` | ✅ |
| 7 | 去节点级局部 CodeBERT | `--cb-channels cb_func` | ✅ |
| 8 | meanpool 替换 $a_v$ 加权 | `--meanpool` | ✅ |
| 9 | 关闭 $L_{var}$ | `--lambda-var 0` | ✅ |
| 10 | **关闭先验 Dropout** | `--prior-dropout 0` | ✅（语义已修正） |
| 11 | 节点结构特征分组 | `--feat-groups base` / `base+sem` / `all` | ✅ |

**物理关系编号**（`dataset.RELATION_NAMES`）：`0=CFG_FLOW 1=AST_PARENT 2=AST_PARENT_SAME 3=DFG_DEP 4=CALLBACK_RISK`。
`--drop-ast` 按 relation 1+2 口径执行（大纲 12-26 要求）。

### 3.1 5.4.2 可选消融（**2026-09-17 补录**——此前本计划只列了 5.4.1，5.4.2 散在 `Todo_List.md`）

| # | 消融项 | 唯一开关 | 状态 |
| --- | --- | --- | --- |
| 12 | CALLBACK_RISK_REV（加反向边） | 无（M2 缺 `--callback-rev`） | ❌ 需开发 |
| 13 | RGCN 层数 L=1/2/3 | 无（`SSMHG` 硬编码 `conv1`/`conv2`） | ❌ 需开发 |
| 14 | **`num_bases` 不同取值** | `--num-bases`（默认 5 = 关系数） | ✅ **已跑：1/3/4**（2026-09-18 裁定；⚠ 见下方修正） |
| 15 | **隐藏维度 128/256** | `--hid`（默认 128） | ✅ `hid256` 已入矩阵 |
| 16 | **DropEdge** | `--drop-edge-prob`（默认 0.0 = 关） | ✅ **已跑：0.2**（2026-09-18 裁定） |

> 🔴 **修正（2026-09-18）：第 14 项原定的"取 10"从来不可行，且"两端各一"的设计本身塌了。**
> `model.py:332` 硬约束 `1 <= num_bases <= num_relations`（=5）——实测 `--num-bases 10` 直接报错
> `ValueError: num_bases must be in [1, 5], got 10`。更要紧的是第二层：**合法上端 5 恰好就是基线**
> （`model.py:19`），所以"两端各一"在合法区间内**没有上端可用**。
> **实际取值 = 合法非默认区间 `{1,2,3,4}` 的两端 1 与 4**（`model.py:19` 自己点名 4「仅作消融」），
> 并补计划候选里的 3，凑成 **1/3/4 vs 默认 5** 的剂量-反应。结果见 `ablation_results.md` §6.4。
| 17 | 微调 vs 冻结 CodeBERT | 无（M3 只产出冻结嵌入缓存） | ❌ 需开发 |

**两项"取值待定"的理由**：大纲 5.4.2 只写了"不同取值"，**没有指定数值**。
我不替使用者拍板——取值会直接决定该消融测的是什么，属设计决策。可选项：

| 项 | 候选 | 取舍 |
| --- | --- | --- |
| `num_bases` | 1 / 3 / 10 | `1` = 所有关系共享一组基（退化到近 GCN）；`3` 与默认 5 差一档；`10` > 关系数 5，检验"过参数化是否有害"。**建议 1 与 10**（两端各一，信息量最大） |
| `drop_edge_prob` | 0.1 / 0.2 / 0.5 | 图小（池 453、单图节点数不等），0.5 可能过强。**建议 0.2**（与 prior/struct dropout 默认同档，便于横向比较） |

给定值后加进 `scripts/run_ablation.py::ABLATIONS` 即可（一行），驱动会自动做单变量断言。

> ⚠ **`num_bases` 与 `hid` 有一个共同陷阱**：它们是**模型容量**类消融，与"去掉某个输入/结构"
> 类消融（边、通道）性质不同——容量变化会同时改变参数量与优化难度。
> 报告时必须**随附 `config.json::derived.parameter_report` 的参数量**，否则无法区分
> "该组件重要"与"模型变小了/变大了"。

### 第 11 项的三设置判定（大纲 8.5 / 4.3.3）

三设置 = `all`（c）/ `base+sem`（b）/ `base`（a）。**判定规则：若 (c) 相对 (b) 的验证集 macro-F1 提升 < 0.3 个百分点，
则考虑把 CALLBACK_RISK 辅助组与位置/指令组降级为可选。** 需从三次 `--feat-groups` 的 `runs/ablation/feat-*/summary.json`
取 `val` 侧 macro-F1 逐种子比较，写进 `eval_results/ablation/feat-groups.json`。
> 注意：`all` 设置即正典 `runs/`，可直接复用，无需重跑（省 1/3 机时）。

## 4. ✅ 原阻断项已解除：「关闭先验 Dropout」现已可跑（2026-09-16 修正）

> **状态**：`sample_dropout_masks` 已由「保留率」改为**丢弃率**语义（`rand >= p`），
> `--prior-dropout 0` = **关闭**、`1` = 全丢、默认 `0.2` 置零约 20% 的图；结构 dropout 共用同一函数、一并修正。
> 全部既有结果已作废重跑，见 `decisions.md` §26。**第 10 项现按 `--prior-dropout 0` 执行即可**。
> 另附裁决：**维持默认 0.2、不返工 80%**（n=9 同配对剂量-反应研究，见 §26.6）。

<details><summary>修正前的原始记录（备查）</summary>

### 原阻断描述：「关闭先验 Dropout」当时无法按意图表达

**实测**（`tests/test_ablation_switches.py::test_prior_dropout_*`）：

- `sample_dropout_masks` 返回 `rand < prior_p`，掩码**乘法**作用于 s_v（0=置零，1=保留），
  故 `prior_p` 是**保留率**、不是丢弃率。
- 后果一：默认 `--prior-dropout 0.2` 实际**置零 80% 的图**，而大纲 4.1.4 / 手册 §8.6 的散文写的是
  「以概率 **0.2** 把 $s_v$ **置 0**」（丢弃率 0.2）→ **默认强度差 4 倍**，且现有全部结果都带这个口径。
- 后果二：`--prior-dropout 0` 会把**每张图**的 s_v 置零，**等价于 `--ablate-sv`**（5.4.1 的另一项）。
  即"关闭先验 Dropout"这一项**跑不出它该测的东西**，两个不同消融会得出同一结果。

**处置待裁定**（`decisions.md` §25）。三种方案：

| 方案 | 做法 | 代价 |
| --- | --- | --- |
| A（推荐） | 修 `rand >= p`（丢弃率语义），**重跑全部结果** | 主库+增强集+各对照臂全部重训 ≈ 1–2 小时 GPU；`results.md` 数字全部刷新 |
| B | 保留实现，把参数定义为保留率并**同步大纲** | 偏离大纲 4.1.4 原文；第 10 项改为 `--prior-dropout 1` 表示"关闭"（语义别扭） |
| C | 只修第 10 项的表达（新增 `--no-prior-dropout`），默认口径不动 | 现有结果不失效，但"默认 80% 置零 vs 大纲 20%"的背离仍在，须在论文披露 |

**（已裁定：维持 0.2，见 `decisions.md` §26.6。）**

</details>

## 5. M2 变体类（第 5 项 + 可选的 REV）

`build_cfg_centered_hetero_graph.py` 的 `--callback-limit`（默认 4，`0`=不限制）只影响 **CALLBACK_RISK 边**，
不影响节点集/函数表/CodeBERT 输入文本。故变体**只需重建图与 M1 分数**，`_cb.pt` 可整体软链复用：

```bash
V=products/alldata/graph_variants/callback_unlimited
mkdir -p "$V"
python scripts/build_cfg_centered_hetero_graph.py \
  --ast-dir products/alldata/raw/AST-raw --cfg-dir products/alldata/raw/CFG-raw \
  --dfg-dir products/alldata/raw/DFG-raw --src-root "alldata(readonly)/alldata_sol_source" \
  --out-dir "$V" --callback-limit 0
python scripts/m1_runner.py --in-dir "$V" --out-dir "$V"
python scripts/convert_hetero_json_to_pyg.py --in-dir "$V" --out-dir "$V"
# ★ 软链复用 14.6 GB 的 _cb.pt（文本通道与边无关）；_feat.pt 不可复用——M1 的 s_v 依赖 CALLBACK_RISK 端点
for f in products/alldata/graphs/*_cb.pt; do ln -sf "$PWD/$f" "$V/$(basename "$f")"; done
python scripts/m3_build_features.py --in-dir "$V" --out-dir "$V" --m1-dir "$V" \
  --categories products/alldata/graphs/ir_cat.json          # _cb.pt 命中 → 不加载 CodeBERT，全库约 41 s
```

> 🔴 **更正（2026-09-18）：划绝不重建，必须复用基线划分。**
> 本节初稿写的是 `make_splits.py --graph-dir "$V" --out-dir "$V/splits"`——**这是错的**。
> 消融的全部价值是「只有一个变量在动」，而重建划分会引入第二个变量（划分本身）。
> 该变体**只改边、不改节点集与合约集**，故 `products/alldata/splits/split_seed{S}.json`
> 对它是完全合法的输入：直接 `--split-dir products/alldata/splits`。
> 训练驱动里 `--graph-dir "$V"` 就是那**唯一**一个变量（`run_ablation.py` 的单变量断言照常生效）。

**实测依据（本项确实不是空操作）**：全库 CALLBACK_RISK 源节点出边数分布 `{1:47, 2:62, 3:21, 4:70}`，
最大值恰为 4 且在 4 处堆积；对 `asd_0x0e5632fe…` 单图实测 `--callback-limit 0` 得 **25** 条边
（每节点 5 条）vs 默认 **20** 条（每节点 4 条）→ 截断**确实发生**。

> ✅ **实测更正（2026-09-18，变体建成后）**：本项初稿写的"**影响面有限（仅约 70 个节点被截断）、
> 预期指标变化很小**"**低估了**。全库逐图核对（`products/alldata/graph_variants/callback_unlimited/variant.json`）：
>
> | | 正典（limit=4） | 变体（limit=0） |
> | --- | --- | --- |
> | CALLBACK_RISK 总边数 | **514** | **1166**（×2.27） |
> | `callback_truncated_candidates` 合计 | **652** | **0** |
> | `_feat.pt` 与正典不同的图 | — | **20 / 590** |
>
> 即被截断的候选边（652）比建出来的边（514）**还多**。"只有约 70 个节点"是**节点数**，
> 而每个被截断节点的候选可达 5 条以上——按边计的影响是翻倍量级。故本项的效应不应预设为"很小"。

`CALLBACK_RISK_REV`（5.4.2）需要 M2 **新增反向边开关**（当前无此开关），属开发项，见 §6。

## 6. 未跑 4 项：开发方案（2026-09-18 设计）

四项 = **1 项造 M2 变体**（第 5 项 CALLBACK_RISK 上限）+ **3 项需开发**
（第 12 项 CALLBACK_RISK_REV、第 13 项 RGCN 层数、第 17 项微调 CodeBERT）。
四项的共同约束不变：**唯一变量**、**新开 `--out-dir`**、**复用基线划分**、**不与正典混用口径**。

> 执行顺序建议：**6.2（RGCN 层数，最便宜、零数据依赖）→ 6.3（REV，只需重建 `_pyg.pt`）
> → 6.1（上限，需重建 `_feat.pt`）→ 6.0+6.4（微调，最贵且依赖 6.0 的修复）**。
> 理由：先把不需要造数据的做完，把唯一需要重训编码器的一项放最后，避免长时间占盘。

---

### 6.0 🔴 前置发现：`_cb.pt` 有 39 倍存储膨胀 —— **已修复并紧凑化（2026-09-18）**

**执行状态：已完成**（代码修复 + 存量紧凑化 + 三重值中性验证 + 回归测试），详见 `decisions.md` §33。
本项是第 17 项能否在磁盘上成立的前提，故前置。

实测（`asd_0x000c100050e98c91f9114fa5dd75ce6869bf4f53__…`，2026-09-18）：

```text
_cb.pt 文件 100.19 MB
  func 通道: 188 条，有效数据 0.58 MB，实际序列化 storage 39.28 MB
  node 通道: 673 条，有效数据 2.07 MB，实际序列化 storage 105.15 MB
  样例张量: shape=(768,) numel=768，而 untyped_storage() = 224256 元素（= 292×768）
```

**根因**：`m3_build_features.encode()` 返回 `out[0]`，其中
`out = model(**ids).last_hidden_state[:, 0, :].cpu()`。**在 CPU 上 `.cpu()` 是 no-op**，
故 `out[0]` 是 `[1, seq_len, 768]` 隐藏态的一个**视图**——视图把它背后的**整块 storage**
一起序列化进文件。每条目本应恰好 `768×4 = 3 KB`，实际按 `seq_len × 3 KB` 落盘。

> 🔴 **更正（2026-09-18）：本膨胀只发生在 CPU 路径。**
> 查证时发现增强集 `_cb.pt`（1774 图合计 1.28 GB）**逐条已是紧凑的**，与主库的 14.61 GB 反差极大。
> 原因：增强集的 M3 是 `--device cuda --force` 重建的，**CUDA 上 `.cpu()` 是真拷贝**，
> 拷贝的只是 `[:, 0, :]` 那一行 ⇒ storage 恰为 768。桩模型实测：`cpu → 膨胀 ×128`、`cuda → 紧凑`。
> ⇒ **只有 CPU 构建的主库缓存中招**；且这说明"产物体积不该随运行设备漂移"本身也是一个缺陷。

**已完成的处置**：

| 项 | 结果 |
| --- | --- |
| `encode()` 修复 | 末尾 `.clone()`（**值逐位不变**） |
| 主库紧凑化 | `products/alldata/graphs/*_cb.pt` **15.586 GB → 0.403 GB**（×39，590/590 成功，21.5 s） |
| 增强集 | **不动**（抽样 60 图、膨胀条目 0，本已紧凑） |
| `products/` 合计 | 20 GB → **4.5 GB** |
| 值中性验证 | 三重：逐文件 `torch.equal` / 全库 `verify_channels="all"` **590/590** / `evaluate.py --seed 0` 复算**逐位相同** |
| 回归锁 | `tests/test_m3_cb_cache.py`（8 例）钉死「每条缓存 `storage == numel*4`」 |

⚠ **C 盘可用仍显示 37 GB**：WSL 内部已释放 14 GB（`df /` 40G→26G），但 `ext4.vhdx` **非稀疏**，
释放的块不会自动还给 Windows——需按 `AGENTS.md`「磁盘空间」的手工步骤（`fstrim` + `wsl --manage --set-sparse`）
才会体现在 `/mnt/c`，且该步骤**必须由你在 Windows 侧执行**（会关闭整个 WSL）。

**为什么它决定第 17 项**：微调编码器必须另产一套 `_cb.pt`。不修则每个划分种子
14.6 GB（三个种子 44 GB，**超 C 盘硬规则**）；修后每个种子 0.38 GB（三个种子合计 ≈1.1 GB）。

---

### 6.1 第 5 项：CALLBACK_RISK 上限 4（默认）vs 不限（`--callback-limit 0`）

**缺什么**：什么都不缺——`build_cfg_centered_hetero_graph.py --callback-limit`（`model.py` 之外唯一开关）已存在。缺的是**一套合法的图变体与一个守卫**。

**为什么它确实不是空操作**（已实测）：全库 CALLBACK_RISK 源节点出边数分布 `{1:47, 2:62, 3:21, 4:70}`，**最大值恰为 4 且在 4 处堆积**；单图 `--callback-limit 0` 实测得 25 条边（每节点 5 条）vs 默认 20 条（每节点 4 条）→ 截断确实发生，但受影响节点仅约 70 个（**预期效应小，须以实测为准**）。

**变体链**（`—` 表示软链复用）：

| 步骤 | 命令 | 产物 | 是否可复用正典 |
| --- | --- | --- | --- |
| M2 | `build_cfg_centered_hetero_graph.py --out-dir $V --callback-limit 0` | `_hetero.json` | ❌ 必须重算 |
| M1 | `m1_runner.py --in-dir $V --out-dir $V` | `_m1.json` | ❌ **必须重算** |
| PyG | `convert_hetero_json_to_pyg.py --in-dir $V --out-dir $V` | `_pyg.pt` | ❌ 需重算（边改） |
| cb 缓存 | `for f in products/alldata/graphs/*_cb.pt; do ln -sf …; done` | `_cb.pt` | ✅ **可软链** |
| M3 | `m3_build_features.py --in-dir $V --out-dir $V --m1-dir $V --categories products/alldata/graphs/ir_cat.json` | `_feat.pt` | ❌ **必须重算** |
| 划分 | `--split-dir products/alldata/splits` | — | ✅ **复用，不重建**（见 §5 更正） |

**三项不能复用的理由（逐条已核实，不是"保险起见"）**：

1. **`_cb.pt` 可软链**：`build_cb_cache` 只读 `nodes` / `fn_table` / `src_lines`——**完全不用边**。故 CodeBERT 文本口径与边无关。
2. **`_feat.pt` 不可复用**：`priori_scoring._build_callback_nodes_from_edges` 取
   `edges["CALLBACK_RISK"]` 的 **source ∪ target** 作 `external_callback +0.5` 的命中集合。
   `limit 4 → 不限` 会让**更多入口节点**成为 target ⇒ 集合变大 ⇒ `s_v` 变 ⇒ `struct/sv` 通道变。
   （这条与 §6.3 的 REV 形成对照：REV 不改这个集合，故 REV 能复用 `_feat.pt`。）
3. **划分不用动**：变体只改边，**节点集与合约集逐个不变**（`--callback-limit` 只影响 `cands[:limit]`），
   故基线 `split_seed{S}.json` 对它是合法输入。

**训练**：

```bash
for S in 0 1 2; do
  python scripts/train.py --seed $S --split-seed $S \
    --graph-dir products/alldata/graph_variants/callback_unlimited \
    --split-dir products/alldata/splits \
    --out-dir runs/ablation_callback/cb_unlimited
  python scripts/evaluate.py --seed $S --runs-dir runs/ablation_callback/cb_unlimited \
    --graph-dir products/alldata/graph_variants/callback_unlimited \
    --split-dir products/alldata/splits
done
python scripts/evaluate.py --summarize --runs-dir runs/ablation_callback/cb_unlimited
```

**单变量断言的口径（须写进产物，否则不可复核）**：`train.py` 侧与正典的差异**只有 `graph_dir` 一项**，
而「`graph_dir` 里装的是 limit=0 的图」这件事**不在 train 的 CLI 里**——这正是"看起来是消融、
其实不是"能藏身的地方。故**必须在变体目录写自述文件** `$V/variant.json`：

```json
{"variant": "callback_unlimited",
 "derived_from": "products/alldata/graphs",
 "commands": ["build_cfg_centered_hetero_graph.py … --callback-limit 0", "m1_runner.py …", "…"],
 "callback_limit": 0, "expected_default": 4,
 "reuse": {"_cb.pt": "symlink", "splits": "products/alldata/splits"},
 "created": "2026-…"}
```

**验收（本项特有）**：变体与正典的 `_pyg.pt` 节点数逐图相等、`edge_type` 取值域仍为 `[0,5)`、
**CALLBACK_RISK 边数严格 ≥ 正典**且增量集中在原先被截断的源节点上。

**成本**：M2 ≈ 数分钟（**590 图单进程，实测值待记录**）+ M1/PyG/M3 ≈ 2 分钟 +
训练 3 × ≈30 s ≈ 2 分钟。磁盘：`_feat.pt` ≈ 60 MB + `_pyg.pt` ≈ 10 MB + `_hetero/_m1.json` ≈ 160 MB。

---

### 6.2 第 13 项：RGCN 层数 L = 1 / 2 / 3

**缺什么**：`SSMHG.__init__` 硬编码 `self.conv1` / `self.conv2`，`forward` 亦写死两层。

**唯一变量**：`num_layers`。**L=2 就是正典**（`runs/seed{0,1,2}/`），故本项只需跑 **L=1 与 L=3**（6 个 run），不重跑 L=2。

**设计（关键约束：L=2 必须逐位不变）**：

1. `model.SSMHG.__init__(..., num_layers: int = 2)`。**默认 2 必须与现状逐位一致**——
   包括 **`state_dict` 的键名**（`conv1.*` / `conv2.*`），否则已有 `best.pt` 全部加载失败。
   故**不用 `nn.ModuleList`**（会改名成 `convs.0.*`），而是在 L≥2 时保留 `self.conv1` / `self.conv2`
   原名，L≥3 时用 `setattr(self, f"conv{i}", …)` 追加 `conv3`…；L=1 时 `self.conv2 = None`
   （`nn.Module` 允许，`state_dict()` 跳过 `None`）。
2. `forward` 改为按层循环，且**层间算子顺序逐字保持**：现状是
   `relu → dropout → relu`，即 **dropout 只加在非末层**。循环写成
   「每层 `relu(conv_l(h))`，`l < L-1` 时接一次 dropout」即与现状逐位等价。
3. `h1` / `h2` 两个中间量的语义保持：`h1` = 第一层输出、`h2` = **末层**输出（Readout 用的是 `h2`，
   docstring 已锁死「绝不用输入 x」）。L≥3 时另加 `h_layers` 列表；L=1 时 `h1 is h2`（同张量）。
   `tests/test_model_smoke.py::test_return_intermediates_structure` 断言两组键存在，须保持通过。
4. `train.py` 新增 `--layers`（choices `1,2,3`，default `2`）→ `build_fuser_model` 透传；
   `derived["num_layers"]` 记入 config。
5. `evaluate.py`：`num_layers=int(d.get("num_layers", 2))`，与 `hid`/`num_bases` **同一回读模式**
   （**不能读模块常量**——那条教训已写在 `evaluate.py:85-93` 的 `--head` 注释里）。
6. 🔴 **`run_guard.IDENTITY_DEFAULTS` 必须登记 `"layers": 2`**。否则「拿新键 `--layers 3` 写进旧目录」
   会因"该键在旧侧不存在"而差异为 0、守卫放行、**无声覆盖**——这正是 §31.3 修掉的那个洞，
   而 `tests/test_run_guard.py` 的漂移守卫只断言"表里的键真实存在"，**不会**发现"新键没登记"。

**成本**：2 个配置 × 3 种子 = **6 个 run ≈ 3 分钟**。磁盘 ≈ 90 MB。**零数据依赖，可立即开工。**

**验收（本项特有）**：
- `pytest tests/` 全绿，且**新增一条**：`num_layers=2` 的 `state_dict` 键集合与修改前**完全相同**、
  同 seed 前向输出**逐位相同**；
- `num_layers=3` 的 `state_dict` 含 `conv3.*` 且 `conv1/conv2` 名不变；
- 参数量随 L 单调增，且 `parameter_report` 入 `config.json::derived`（容量类消融的既有要求，§3.1）。

---

### 6.3 第 12 项：CALLBACK_RISK_REV（反向关系）

**大纲原文（`改II` 第 160 行）**：

> 「CALLBACK_RISK 默认以单向边实现，即从外部调用节点指向可重入入口节点；如需反向信息，
> 可在消融实验中**额外添加反向关系 CALLBACK_RISK_REV**，不作为默认设置。」

**大纲原文（第 220 行）**：

> 「…若添加反向边则**按实际关系数统计**。」

⇒ **设计按"独立关系"落地，不是"同一关系加反向边"**：新增关系编号 **5 = `CALLBACK_RISK_REV`**，
`num_relations` 由 5 → **6**。这不是可自由发挥处，是大纲点名的口径。

**为什么这一项比第 5 项便宜得多**：`priori_scoring` 里**只有两处读边**——
`_build_cfg_adj_from_hetero_edges`（只读 `CFG_FLOW`）与 `_build_callback_nodes_from_edges`
（只读 `CALLBACK_RISK` 这一个键）。REV 边写在**另一个键** `CALLBACK_RISK_REV` 下，
**M1 完全看不见它** ⇒ `_m1.json` 逐位不变 ⇒ `_feat.pt` 逐位不变。
又：M3 的结构特征与边无关（`build_struct_features` 只用节点语义谓词）。
⇒ **变体目录只需真产出一个 `_pyg.pt`**（其余全部软链），**不重跑 M1、不重跑 M3**。

| 步骤 | 产物 | 是否可复用正典 |
| --- | --- | --- |
| M2（加 `--callback-rev`） | `_hetero.json` | ❌ 重算（但只多一个边键） |
| M1 | `_m1.json` | ✅ **软链**（REV 不在它读的键里） |
| PyG | `_pyg.pt` | ❌ 重算（edge_type 域 5→6） |
| `_feat.pt` / `_cb.pt` / 划分 | — | ✅ **全部软链** |

**代码改动（4 处，均最小）**：

1. `build_cfg_centered_hetero_graph.py`
   - `--callback-rev`（`action="store_true"`，**默认关** ⇒ 正典逐字节不变）。
   - `build_callback_risk_edges(...)` 增参 `callback_rev: bool`，返回**已建边集的精确反向**
     `{(entry, ext) for (ext, entry) in callback_edges}`。**语义上必须是同一批配对的镜像**，
     不要对反向边另跑一套过滤规则（那会引入第二个变量，且无可辩护的理由）。
   - 写 JSON：`edges["CALLBACK_RISK_REV"]`；`meta` 增 `callback_rev_edge_count` 与 `callback_rev` 布尔。
2. `convert_hetero_json_to_pyg.py`
   - `RELATION_IDS` 增 `"CALLBACK_RISK_REV": 5`。
   - 🔴 **`num_relations` 必须按"实际出现的键"算，不能按常量表的最大编号算**：
     `num_relations = 1 + max(RELATION_IDS[k] for k in edges if k in RELATION_IDS)`。
     否则**正典语料**（无 REV 键）也会被写成 6，模型侧 `num_relations=6` 而数据只有 5 类——
     不报错、但 RGCN 多出一组永远收不到消息的基。写成 payload 的 `num_relations` 字段
     （正典 `_pyg.pt` 的结构**不因这次改动而变**，因为都不含该键——**注意**：新增该键会让
     正典下次重建时多一个字段，故只在**新产物**里生效，旧文件靠 `.get(..., 5)` 兜底）。
3. `dataset.py`
   - `RELATION_NAMES` **保持 5 不动**——`audit_data_funnel.py:382` 有
     `assert len(dataset.RELATION_NAMES) == 5`，它是**正典语料**的审计，不能为一个消融放宽。
   - `load_graph` 把 `num_relations` 透传进 `sample_meta`（`payload.get("num_relations", 5)`）；
     显示用的**扩展名表**（仅 `type_dist` 打印用，不影响行为）另立常量。
   - `DROPPABLE_EDGES` **不扩**（白名单只用于校验"请求删的编号"，与观测到的编号无关；
     扩了等于给正典开一个无用的删边口子）。
4. `train.py` / `evaluate.py`
   - `build_fuser_model`：`num_relations = int(meta.get("num_relations", NUM_RELATIONS))`；
     `_load_split_samples` 增一条**跨图一致性断言**（现只断言 `D_struct`/`struct_layout`，
     多一个 `num_relations` 断言，否则混语料会静默按第一张图建模型）。
   - `derived["num_relations"]`；`evaluate.py` 从 `derived` 回读（**不是**从 `args`）。
   - `num_bases` 默认 5 ≤ 6，**合法**；参数量只多 `num_bases=5` 个（RGCN 的 `comp` 是
     `[num_relations, num_bases]`）⇒ 本项**几乎不是容量类消融**，参数量仍须随附。

**训练**：照 §6.1 的命令模板，`--graph-dir products/alldata/graph_variants/callback_rev`。

**成本**：M2 数分钟 + PyG 数秒 + 训练 3 × ≈30 s。**磁盘 ≈ 10 MB**（只有 `_pyg.pt` 是真的）。

**验收（本项特有）**：
- **`_feat.pt` 与正典逐位相同**（这条是"唯一变量"的机器证明，比断言 CLI 差异更强）；
- 变体 `edge_type` 值域 `[0,6)`，`CALLBACK_RISK_REV` 边数 == `CALLBACK_RISK` 边数，且配对集恰为镜像；
- `train.py --drop-edges 5` 应**报错**（白名单未扩，属预期行为，写进验收以免被当成 bug）。

---

### 6.4 第 17 项：微调 CodeBERT vs 冻结

**缺什么**：M3 只产**冻结**嵌入缓存 `_cb.pt`；训练期没有任何微调路径。

**为什么必须走"两阶段"而不是"端到端"**（这是本项最重要的设计选择）：

本仓的架构事实是——**CodeBERT 只活在 M3 里，`_cb.pt` 是它进入 M5 的唯一载体**。
若改成"训练时把 CodeBERT 接进 `NodeFuser` 端到端反传"，代价是：每 epoch 要对
**95,918 个节点窗口 + 23,919 条函数序列**跑一次 BERT 前向+反向——
仅 M3 的**纯前向**（GPU，7.2 ms/节点）就约 12 分钟量级，反向训练要在此之上再乘数倍，
而早停发生在 14–23 个 epoch（§0.1 第 2 条）⇒ **不可承受**；同时会打破
「M3 产出可离线复算的缓存」这一可复现性契约。故采用：

> **阶段 1** 用合约级标签微调 CodeBERT（只喂 **train 划分**的合约文本）；
> **阶段 2** 用微调后的编码器**重跑一次 M3** 产出变体 `_cb.pt`；
> **阶段 3** 用变体 `_cb.pt` 照常训练 GNN（M5 逐行不变）。

**它回答什么、不回答什么（必须披露）**：它回答「**微调后的编码器作为特征提取器**是否更好」，
**不**回答「端到端联合微调是否更好」（后者的优化面与显存占用都不同）。
大纲 4.3.2 给的三条冻结理由（省显存、短序列梯度不稳、可离线缓存可复现）中，
本设计**只解除了第 1 条的动机**（因为不是联合训练），第 2、3 条仍成立——
故本项作为**可选消融**的性质不变。

**阶段 1：`scripts/finetune_codebert.py`（新增）**

| 项 | 设计 |
| --- | --- |
| 输入 | `--split-dir products/alldata/splits --split-seed S --graph-dir products/alldata/graphs --out-dir runs/codebert_ft/seed{S}` |
| 文本口径 | **必须复用 M3 的文本构造**（`m3_build_features.build_node_window` 与函数源码 `src_lines[fs-1:fe]`，`512`/`128` 截断）——直接 `import` 该模块，**不另写一份**。两份文本口径必然漂移（本仓已有 §29.4 的同类教训） |
| 标签 | 合约级 7 维多标签；函数级 `[CLS]` 在**合约内 mean-pool** → `Linear(768, 7)`；损失 = `masked_weighted_bce` 同口径（复用 `train.class_stats` 的 `pos_weight` 计算，含 20 倍截断） |
| 数据 | **只用 train 划分**（`split_seed{S}.json::train`）。**硬断言** `train ∩ (val ∪ test) = ∅` |
| 选择判据 | **val macro-F1**（大纲第 452 行点名此指标）；`ReduceLROnPlateau` + 早停 |
| 产物 | `runs/codebert_ft/seed{S}/encoder/`（HF `save_pretrained`，供 `--codebert <dir>` 直接吃）+ `config.json`（含 train/val 合约清单与 sha256、超参、逐 epoch 日志） |
| 成本 | **实测基数（2026-09-18）**：正典 590 图、节点合计 **95,918**、`functions` 条目合计 **23,919**（均值 40.5/图）；`split_seed0` train/val/test = **362/45/46** ⇒ 微调每 epoch 约 **14.7k 条 512-token 序列**（362 × 40.5）。估 5–12 min/epoch × 3–5 epoch。**实测已回填**（① **848.5 s/种子**、② **3,797.3 s/种子**——旧载「② 4,280 s/种子」与本节末 ③ 表的 3,801.2/3,841.2/3,749.5 均值不符，已按 `experiments/canonical_ft_numbers.md` §D 更正）——见本节末「❝实现更正❞」的第 ③ 条 |

**阶段 2：重跑 M3 产出变体 `_cb.pt`**

```bash
V=products/alldata/graphs_ft/ss$S   # ⚠ 原名 graph_variants/cb_ft_ss$S，§37.3 已改名；旧名只留兼容软链
mkdir -p "$V"
# 结构类产物全部软链（M3 只读它们；_hetero.json 供节点/函数表、_m1.json 供 s_v、ir_cat.json 供冻结字典）
for f in products/alldata/graphs/*_hetero.json products/alldata/graphs/*_m1.json; do ln -sf "$PWD/$f" "$V/"; done
python scripts/m3_build_features.py --in-dir "$V" --out-dir "$V" --m1-dir "$V" \
    --categories products/alldata/graphs/ir_cat.json \
    --codebert runs/codebert_ft/seed$S/encoder --force
```

- ⚠ `--force` 只强制重写 `_cb.pt`/`_feat.pt`；**`--categories` 给了冻结文件时不会回写 `ir_cat.json`**
  （`m3_build_features.py:1002-1012` 已核实：`load_categories_file` 命中即走该分支，不调 `write_categories`）。
  **绝不要把正典 `ir_cat.json` 软链进 `$V`**——若代码路径万一回写，会顺着软链改掉正典（本设计不依赖该假设，
  但这条要写进注释）。
- ✅ **免费的单变量证明**：变体重算出的 `_feat.pt` 必须与正典**逐位相同**
  （同 `_hetero` + 同 `_m1` + 同 `ir_cat` ⇒ 结构/类型/`s_v` 三通道不变）——**断言它**，
  等于机器证明了本项的唯一变量就是 `_cb.pt`。
- ⚠ **必须走 §6.0 的 `encode()` 紧凑化修复**，否则每个种子落 14.6 GB。

**阶段 3：训练 GNN**

```bash
python scripts/train.py --seed $S --split-seed $S --graph-dir "$V" \
    --split-dir products/alldata/splits --out-dir runs/codebert_ft/arm_ss$S
python scripts/evaluate.py --seed $S --runs-dir runs/codebert_ft/arm_ss$S --graph-dir "$V" \
    --split-dir products/alldata/splits
```

**为什么必须"每个划分种子训练一个编码器"**：编码器若见过某合约的源码，该合约的 `_cb` 特征对这个
划分就是污染的（哪怕只用于特征提取）。用同一编码器跑三个划分种子 ⇒ 其中两个种子的 val/test
合约进过编码器的训练集 ⇒ **不可比的乐观偏差**。故 **3 个划分种子 = 3 次微调 = 3 套变体 `_cb.pt`**。

**成本**：阶段 1 约 3 × 20–40 min（14.7k 序列/epoch）；阶段 2 约 3 × 12–15 min
（95,918 节点 + 23,919 函数，GPU；参照增强集 463k 节点实测 49 min 外推）；
阶段 3 约 3 × 30 s。**合计 ≈ 2–3 小时 GPU**（本批四项中最贵者）。
~~**资源与范围（2026-09-18 裁定）**：**只做 ① 主库**（② 已在 0.93–0.98 天花板、无可观察空间，见 §6.6）。~~
> 🔴 **该裁定的范围部分已被推翻**（2026-09-19 起 ② 全项照跑）；其数字依据「0.93–0.98」为**冻结编码器**口径（新正典 ② 为 0.9901 / mAP 0.9975，天花板更紧）。见 `decisions.md` §39、§0.5。
**磁盘 ≈ 3 × (0.38 + 0.06) GB ≈ 1.3 GB**（§6.0 紧凑化后；不修则 44 GB，不可行）。

**验收（本项特有）**：
- 编码器训练集与 val/test 的合约集**交集为空**（测试钉死）；
- 变体 `_feat.pt` 与正典逐位相同（见上）；
- 变体 `_cb.pt` 与正典**必然不同**（否则编码器没生效——这是个必须显式断言的"反向验收"）；
- 阶段 1 自身报告的**val macro-F1** 一并入档（大纲点名的指标，与下游 GNN 指标并列呈现）。

> ### ❝实现更正（2026-09-18）❞
>
> **① 范围：本节原写"只做 ① 主库"，已按用户裁定改为「两组都做」。** 原理由（② 已在 0.93–0.98
> 天花板、无可观察空间）仍然成立，但**裁定权在用户**：② 上做同类干预，价值不在"能否提升"，
> 而在**「干预在高分语料上是否同样中性」**——这正好与 §6.6 的边界问题互补。故 ② 全项照跑，
> 结果与 ① **各自成表、不跨组比较**（§23）。
>
> **② 实际路径**（与本节草稿不同，以本节为准的是**代码**，草稿仅存设计意图）：
>
> | 项 | 草稿 | 实现 |
> | --- | --- | --- |
> | 编码器输出 | `runs/codebert_ft/seed{S}/` | **`runs/codebert_ft/<语料>/ss{S}/encoder/`**（`--out-root` 省略时由 `--graph-dir` 派生；语料 = `products/<语料>/graphs` 的父目录名） |
> | GNN 产物 | `runs/codebert_ft/arm_ss{S}` | **`runs/ablation{,_aug}/cb_ft/seed{S}/`**（统一并入消融根，由 `run_ablation.py` 驱动） |
> | 变体目录 | 手工 `ln -sf` + `m3 --force` | **`scripts/build_graph_variant.py --variant cb_ft`**（含 `_feat.pt` 逐位断言与 `_cb.pt` 反向抽样） |
> | 驱动 | 手敲三阶段 | **`bash scripts/run_remaining_ablations.sh {main,aug}`**（可重入） |
>
> 🔴 **路径为什么必须带语料维度**（本次实测掐掉的静默错误，`decisions.md` §35.2）：
> 草稿的 `runs/codebert_ft/seed{S}` 与 `.../arm_ss{S}` 都**没有语料维度**，而队列先 `main` 后 `aug`。
> 于是 ② 那一步会看到 ① 留下的编码器而**跳过微调**，再拿它去重编码 ②——`_feat.pt` 逐位断言过、
> `_cb.pt` 反向抽样也过（确实"变了"，因为是另一个编码器），**全程不报任何错**，
> 只是这一项答的不是它要问的问题。现由 `encoder/corpus.json` 边车 + `build_cb_ft` 的硬校验兜底。
>
> **③ 成本实测（替代本节的估算，2026-09-18 跑完后回填）**
>
> | 语料 | 划分种子 | 序列数 | s/epoch | epoch 数 | wall | best_epoch | best_val_macro_f1 |
> |---|---|---|---|---|---|---|---|
> | ① | ss0 | 8,540 | 187 | 5 | 934 s | 3 | 0.5258 |
> | ① | ss1 | 8,665 | 186 | 5 | 931 s | 4 | 0.6067 |
> | ① | ss2 | 8,542 | **136** ⚠ | 5 | **681 s** | 5 | 0.4365 |
> | ② | ss0 | 49,243 | 950 ⚠ | 4（早停） | 3,801 s | 2 | 0.9854 |
> | ② | ss1 | 49,430 | 768 | 5 | 3,841 s | 4 | 0.9938 |
> | ② | ss2 | 49,546 | **750** | 5 | 3,750 s | 4 | 0.9911 |
>
> **① 均值 848.5 s/种子 ≈ 14 min**；本节原估 20–40 min/种子，**偏高约 1.5–2.5×**。
> ⚠ **① ss2 的 136 s/epoch 比 ss0/ss1 低 27%**，而三者跑的都是 5 epoch、序列数几乎相同
> （8540/8665/8542）⇒ **差异来自 GPU 争用、不是算法**。故 848.5 s **偏乐观**，单种子应按 ~930 s 计。
> ⚠ **② ss0 的 950 s/epoch 同样是争用**：其逐 epoch 为 **1070/1069/850/813 s**，
> 前两个 epoch 慢 26%。**ss2 是唯一全程无争用的读数**（750/751/748/752/748 s，五个 epoch 极稳）
> ⇒ **② 的干净单 epoch 成本应按 ~750 s 计**，`config.json::timing` 记的是各 run 的实际 wall
> （3,801 / 3,841 / 3,750 s，均值 **3,797 s ≈ 63 min/种子**）。
> ⚠ **② 是 ① 的 ~4 倍**（750 vs 187 s/epoch；序列数比 49,243/8,540 = **5.8×**）——
> 单 epoch 成本比低于序列数比，因为 ② 的图更大、批内并行更充分。
> 本行原估"约为 ① 的 3–4 倍"，**按干净读数落在区间内、按 config 值（950）偏高**。
> 🔴 **② 的编码器自己就是 0.9854 的七类分类器**（① 只有 0.44–0.61）——
> 同一配方、两组语料，编码器质量差一倍以上。**这决定了 `cb_ft` 的说服力只能来自 ①**
> （② 已接近饱和，正典 mAP **0.9975**——旧载 0.9804，为冻结编码器口径，已作废）。详见 `ablation_results.md` §9.5、`decisions.md` §34.5。
>
> 🔴 待复核（2026-09-20 口径变更）：上句结论建立在冻结编码器（② mAP = 0.9804）之上，新正典为 0.9975。见 decisions.md §39。

---

### 6.5 🔴 顺带修掉的缺口：M2 没有输出目录守卫

已核实：`build_cfg_centered_hetero_graph.py` 中**没有任何覆盖检查**
（无 `run_guard`、无 `--overwrite`、无 `ALLOW_WIPE`）。而它的默认 `--out-dir` 是
`products/alldata/graphs` —— 即**正典语料**。

后果：`python scripts/build_cfg_centered_hetero_graph.py --callback-limit 0`（不传 `--out-dir`）
会**逐个改写 590 个正典 `_hetero.json`**，而下游 `_m1.json` / `_pyg.pt` / `_feat.pt`
**全部不同步**——正典语料从此处于"JSON 与特征互不对应"的状态，**且不报错**。
这与 §28（`.ravel()`）、§29.4（`diagnose.py` 标签源）、§31.3（`run_guard` 漏新键）是同一类失效。

**处置（✅ 已实施，2026-09-18；以下为当时的建议原文）**：给 M2 加**与其它三处同构**的守卫——
out-dir 非空且已存在 `*_hetero.json` 时，若无 `--overwrite` 则报错退出，
提示改用 `--out-dir products/alldata/graph_variants/<name>`。
第 5 项与第 12 项**都要重跑 M2**，是本缺口最可能被踩中的时刻。

### 6.6 裁定结果（2026-09-18）

| # | 事项 | 裁定 | 落地 |
| --- | --- | --- | --- |
| 1 | 正典 590 个 `_cb.pt` 是否紧凑化 | ✅ **已执行**（15.586 GB → 0.403 GB，×39）——三重值中性验证通过，**全部已报告结果继续有效、无需重训** | `decisions.md` §33、`scripts/recompact_cb_cache.py`、`tests/test_m3_cb_cache.py` |
| 2 | 第 17 项（微调 CodeBERT）的语料范围 | ✅ **只做 ① 主库**——② 增强集已在 0.93–0.98 且 mAP 0.9804，**没有可观察空间**（与 §31.8 对二分类臂 ② 的判定同理） | 本计划 §6.4；成本表按 ① 计 |
| 3 | M2 守卫（§6.5） | ✅ **本批一并加**（缺口已证实存在，且 §6.1/§6.3 正是触发窗口） | ✅ **已实施**（2026-09-18）：`build_cfg_centered_hetero_graph.py` 输出目录守卫 + `--overwrite`，`tests/test_run_guard.py` 覆盖 |

> ⚠ 第 2 项的**代价已确认为零**：① 的 `_cb.pt` 紧凑化后三种子变体合计约 1.1 GB，
> ② 若不排除也只是再增约 0.6 GB——排除它**不是因为磁盘**，而是因为**没有可观察空间**，
> 硬做会得到"两者无差异"的结论而无法区分"微调无效"与"天花板效应"。

> 🔴 **2026-09-20 口径刷新（本表两处失真）**：
> - 第 2 项里的 **「0.93–0.98 且 mAP 0.9804」是冻结编码器口径，已作废**；§37 新正典下 ② 为
>   micro 0.9901、macro 0.9918、**mAP 0.9975**（瓶颈空间更小，"饱和"这一判断只会更强）。
> - 第 2 项的**裁定范围亦已被推翻**：2026-09-19 起 ② 全项照跑（见 §6.4 末「❝实现更正❞」①），
>   两项均以该处为准。
>
> 🔴 待复核（2026-09-20 口径变更）：上表「没有可观察空间」的结论建立在冻结编码器（② mAP = 0.9804）之上，新正典为 0.9975。见 decisions.md §39。

---

### 6.7 四项合计：成本与产物

| 项 | 数据侧 | 训练 run | 磁盘 | 依赖 §6.0 |
| --- | --- | --- | --- | --- |
| §6.2 RGCN 层数 | 无 | 6 | ≈90 MB | 否 |
| §6.3 CALLBACK_RISK_REV | 重建 `_pyg.pt` | 3 | ≈10 MB | 否 |
| §6.1 CALLBACK_RISK 上限 | 重建 M2+M1+PyG+M3 | 3 | ≈230 MB | 否（`_cb.pt` 软链） |
| §6.4 微调 CodeBERT | 3 次微调 + 3 次 M3 重编码 | 9 | ≈1.3 GB | ✅ **已完成** |
| **合计** | | **21 run** | **≈1.7 GB** | |

⚠ 上表是**设计估算**；开跑前仍须 `df -h /mnt/c`（**AGENTS 硬规则：C 盘可用 ≥8 GB**，不是 30 GB——本条 2026-09-20 更正）。
⚠ 四个变体目录**都不得**写入 `products/alldata/graphs/`、`runs/seed*/`、`products/alldata/splits/`。


## 7. 每项验收清单

对每个消融项 `X`：

- [ ] 命令只改了一个开关（与正典 `config.json::args` 逐项 diff 应只有 1 处不同）——可用 `runs/ablation/X/seed0/config.json` 与 `runs/seed0/config.json` 对比。
- [ ] 3 种子都跑完；`runs/ablation/X/summary.json` 输出 mean±std。
- [ ] 逐类 F1 与 support 同表报告；support ≤2 的类仅描述性呈现（`decisions.md` §13）。
- [ ] 阈值只在验证集选；固定 0.5 与验证集阈值两套结果都记。
- [ ] 与正典对照时，**明确方差**（种子间波动可能大于消融效应；参考正典 std：micro-F1@0.5 **±0.0389**，mAP **±0.0056**——**2026-09-20 按 §37 新正典（微调 CodeBERT）刷新**；旧载 `±0.0309 / ±0.0119` 为冻结编码器口径，已作废）。
      ⚠ 该 std 偏大 ⇒ **单臂 3 种子不足以判定 ±0.05 量级的效应**，判定须用**同配对**设计且 ≥9 点（教训见 `decisions.md` §26.7）。
- [ ] 记 `timing`（跨工具对比口径）。

## 8. 机时与空间预估

| 项 | 机时（GPU） | 空间 |
| --- | --- | --- |
| 12 项配置 × 3 种子（36 run） | **≈ 20 分钟**（实测单 run 29.5 s） | 每项 ≈ 15 MB（`best.pt` 4.77 MB × 3）+ JSON；**合计约 180 MB**（驱动会在每个 run 后剪除 `last.pt`，否则翻倍） |
| 第 5 项（M2 变体） | M2 数分钟 + M1/PyG/M3 ≈ 1 分钟 + 训练 ≈ 1 分钟 | 变体图 ≈ 0.15 GB（`_cb.pt` 软链，不另占 14.6 GB）+ 划分 + 权重 |
| 3 个开发项 | 取决于实现量 | 同上 |

⚠ **磁盘是约束，不是非约束**：WSL 卷内 `df` 显示 912 GB 可用，**但那只反映 ext4 卷、不代表宿主**——
本仓库在 WSL 的 ext4 上，写入会撑大 `ext4.vhdx` 并直接吃掉 **C 盘**。
**C 盘硬规则：可用必须 ≥ 8 GB**（见 `AGENTS.md` 磁盘空间规则；本条 2026-09-20 由误写的 30 GB 更正）。
2026-09-16 曾实测仅 3.3 GB（远低于阈值）→ 已回收；**2026-09-20 实测 32 GB 可用**。
⚠ 「37 GB」是 `ext4.vhdx` 未转稀疏时的显示值，勿据此判断真实余量。
故**开跑前先 `df -h /mnt/c` 看 `Avail`**；上表 12 项合计约 180 MB 权重虽不大，但**须先回收再跑**。
