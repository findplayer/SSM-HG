# 消融实验执行计划（阶段 F；2026-09-16 准备完成 → **2026-09-17 按重训后口径更新，尚未开跑**）

> 依据：大纲 `改II` 5.4.1 必要消融（11 项）+ 5.4.2 可选消融（6 项），共 **17 项**。
> 本文只做**准备与配方**：每项的确切命令、输出目录、前置条件、就绪状态、验收项。
> 决议与缺口记于 `experiments/decisions.md` §25；开关接线由 `tests/test_ablation_switches.py` 机器验证。
>
> 🔴 **2026-09-17 更新要点**（因 `metrics.micro_f1` 修复 + 全量重训，`decisions.md` §28）：
> 1. **基线换了**：正典 `runs/seed{0,1,2}/` 已用修正后的 micro-F1 重训，**它就是"全开关默认"的对照组**，仍无需重跑。
> 2. **工期上调**：早停不再在 6 epoch 内触发，单种子 wall 由 10–15 s 升至 **≈30 s**，12 项 × 3 种子 ≈ **20 分钟**（原估 15 分钟）。
> 3. **正典 std 收窄**：micro-F1@0.5 的种子间 std 由 ±0.0699 → **±0.0309**。判定纪律**不变**（仍须同配对 ≥9 点，§26.7/§27.5）。
> 4. **新增驱动脚本** `scripts/run_ablation.py`：把 §2 的模板固化为矩阵，并在开跑前**断言每项只改了一个开关**（见 §0.1）。
> 5. **补齐了 5.4.2 的 6 项**——此前计划只列了 5.4.1 的 11 项，5.4.2 散落在 `Todo_List.md`。见 §3.1。

## 0. 就绪总览（2026-09-17 复核）

| 状态 | 项数 | 说明 |
| --- | --- | --- |
| ✅ **可直接跑** | **12 项配置** | 见 §3 与 §3.1 的矩阵；`scripts/run_ablation.py` 已就绪，冒烟通过 |
| ⏸ **开关在、取值待定** | **2** | `num_bases`、`drop_edge_prob`（5.4.2）——**取值需裁定**，故未预置，见 §3.1 |
| ⚠️ **需先造 M2 变体** | **1** | CALLBACK_RISK 上限 4 vs 不限制（开关已存在，需另建一套图） |
| ✅ **已解除阻断** | **1** | 「关闭先验 Dropout」——`--prior-dropout` 已于 2026-09-16 修正为**丢弃率**语义，`--prior-dropout 0` 现为「关闭」 |
| ❌ **需开发** | **3** | CALLBACK_RISK_REV（M2 无反向边开关）、RGCN 层数 L（`SSMHG` 硬编码两层）、微调 CodeBERT（无微调路径） |

**结论：17 项中 12 项配置已可直接开跑（约 20 分钟 GPU、约 180 MB），2 项待定取值，1 项需造 M2 变体，3 项需开发。**

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

主实验口径不变：池 453、划分 `products/alldata/splits/`、语料 `products/alldata/graphs/`、
超参取 `runs/seed0/config.json::args` 的默认值。**每条命令只改一个开关**，其余全部保持默认。

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
| 14 | **`num_bases` 不同取值** | `--num-bases`（默认 5 = 关系数） | ⏸ **取值待定** |
| 15 | **隐藏维度 128/256** | `--hid`（默认 128） | ✅ `hid256` 已入矩阵 |
| 16 | **DropEdge** | `--drop-edge-prob`（默认 0.0 = 关） | ⏸ **取值待定** |
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
python scripts/make_splits.py --graph-dir "$V" --out-dir "$V/splits"   # 划分随图重建
```

**实测依据（本项确实不是空操作）**：全库 CALLBACK_RISK 源节点出边数分布 `{1:47, 2:62, 3:21, 4:70}`，
最大值恰为 4 且在 4 处堆积；对 `asd_0x0e5632fe…` 单图实测 `--callback-limit 0` 得 **25** 条边
（每节点 5 条）vs 默认 **20** 条（每节点 4 条）→ 截断**确实发生**。但影响面有限（全库仅 ~70 个节点被截断），
**预期该项指标变化很小**——这是先验判断，须以实测为准。

`CALLBACK_RISK_REV`（5.4.2）需要 M2 **新增反向边开关**（当前无此开关），属开发项，见 §6。

## 6. 需开发的 3 项（不在本次准备范围内）

| 项 | 缺什么 | 落点 |
| --- | --- | --- |
| RGCN 层数 L=1/2/3 | `SSMHG` 硬编码 `conv1`/`conv2`；需 `num_layers` 参数 + 前向循环 + `--layers` 开关 | `scripts/model.py`、`scripts/train.py` |
| CALLBACK_RISK_REV | M2 无建反向边开关；需 `--callback-rev` 并另建图变体 | `scripts/build_cfg_centered_hetero_graph.py` |
| 微调 CodeBERT | M3 只产出**冻结**嵌入缓存，训练期无微调路径；需在 M5 接入可训练编码器（大纲 4.3.2 给了三条冻结理由，故本项是"可选消融"） | `scripts/model.py` + `scripts/train.py` |

这 3 项已用 `@pytest.mark.skip` 在 `tests/test_ablation_switches.py` 显式登记，**不会在 CI 里假绿**。

## 7. 每项验收清单

对每个消融项 `X`：

- [ ] 命令只改了一个开关（与正典 `config.json::args` 逐项 diff 应只有 1 处不同）——可用 `runs/ablation/X/seed0/config.json` 与 `runs/seed0/config.json` 对比。
- [ ] 3 种子都跑完；`runs/ablation/X/summary.json` 输出 mean±std。
- [ ] 逐类 F1 与 support 同表报告；support ≤2 的类仅描述性呈现（`decisions.md` §13）。
- [ ] 阈值只在验证集选；固定 0.5 与验证集阈值两套结果都记。
- [ ] 与正典对照时，**明确方差**（种子间波动可能大于消融效应；参考正典 std：micro-F1@0.5 **±0.0309**，mAP **±0.0119**——均为 2026-09-17 重训后口径）。
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
**C 盘硬规则：可用必须 ≥ 30 GB**（见 `AGENTS.md` 磁盘空间规则）。
2026-09-16 曾实测仅 12 GB（低于阈值）→ 已回收；**2026-09-17 复查 C 盘 37 GB 可用**，可开跑。
故**开跑前先 `df -h /mnt/c` 看 `Avail`**；上表 12 项合计约 180 MB 权重虽不大，但**须先回收再跑**。
