# 5.3 三条论文基线（EGFL / MVD-HG / MANDO-LLM）接入 · 开发计划（仓库版）

> 计划批准于 2026-09-22（用户裁定）；本文件是仓库内的落地版，随实现同步。
> 交付物 = `experiments/baseline_three_caliber_tables.md`。

## 0. 为什么做

大纲 `改II` 5.3 的对比表点名三个论文基线 **EGFL、MVD-HG、MANDO-LLM**，
`Todo_List.md` §12.7.1 把它们全标为 **⏳ 未实现**。

大纲 [411] 原文定死了口径：

> **所有基线均按多标签任务统一训练和评估。……EGFL、MVD-HG、MANDO-LLM 等模型均输出七维 logits，
> 并使用 `BCEWithLogitsLoss` 训练。**

三份只读调查的结论：三个仓库**没有一个是多标签**（EGFL `Dense(1)`+BCE /
MVD-HG `Linear(8→1)`+`BCELoss` / MANDO-LLM `Linear(128→2)`+CE），
**现机 base 环境三个都跑不起来**（EGFL 要 TF1.15、MANDO-LLM 要 dgl、MVD-HG 要 gensim 3.x），
**三个都没有可用预训练权重** ⇒ 必须按大纲 [411] 改造 + 从零重训。

**用户裁定（三条）**：
1. **路线 2** —— MVD-HG **忠实复现**（驱动其原仓库代码建图）+ EGFL/MANDO-LLM **按论文重实现**；
   以「已跑通」为优先级。
2. **不新建 conda 环境**，在 **base** 上改造。
3. **对比实验喂「去除 `buggy_*` 的数据集」** = §37 正典本身；EGFL 走**原生字节码模态**。

## 1. 数据口径（已被硬证据锁定）

| 项 | 值 |
|---|---|
| 正典 | `products/alldata/graphs_ft/ss{S}` + `products/alldata/splits/split_seed{S}.json` |
| 池 | **453**（train 362 / val 45 / test 46） |
| 「去除 `buggy_*`」 | 497（`withbuggy_snapshot`）删 44 个 `buggy_*` 后与 453 **集合级恒等**（双向差集 0），逐类正样本同为 `[17,15,6,4,31,5,50]` |

🔴 **不得**用「`withbuggy_snapshot` 删掉 buggy 行」代替——那份在池 497 上**重新打乱**过，
test 会变成另一批合约，与正典 test 46 不可比。

**统一超参**（与 `train.parse_args()` 逐键相同）：
`epochs=200, batch_size=32, lr=1e-4, weight_decay=1e-4, scheduler_patience=3,
pos_weight_cap=20.0, dropout=0.3`；早停判据 = val micro-F1；阈值只在 val 搜（0.20–0.80 步长 0.05）。

⚠ **一处有意偏离**：`early_stop_patience` 三基线用 **20**（不是正典的 5）。
理由：正典的 5 是为 SSM-HG 调的，实测套到 MVD-HG 上会在 **loss 仍在下降**
（2.20→0.64，val micro 仍在爬）时于第 14 轮截断，**系统性压低基线**。
该偏离写在每个 run 的 `results.json::reconstruction_notes` 里，并在交付物抬头上声明。

## 2. 模块划分

```
scripts/
  baseline_common.py          ★ 共用层（训练/评估/产物/守卫/设备/solc 候选）
  baseline_models.py          ★ 三个模型定义（纯 nn.Module，可单测）
  baseline_mvdhg_build.py     MVD-HG 离线：驱动外部仓库建图 + 300 维 word2vec 特征
  baseline_mvdhg.py           MVD-HG 训练/评估
  baseline_egfl_build.py      EGFL 离线：solc --bin → 反汇编 → 基本块 CFG → 序列 + 图向量
  baseline_egfl.py            EGFL 训练/评估
  baseline_mando.py           MANDO-LLM 训练/评估（无离线步，复用正典图）
  run_baselines.py            ★ 跑批驱动（子进程 + preflight + 断点续跑）
  collect_baseline_tables.py  ★ 汇总（import 复用 collect_three_caliber_tables）
tests/test_baseline_tables.py  契约守卫（20 条）
products/alldata/baseline/<name>/          # 离线特征（大，不入库）
eval_results/baseline/<name>/seed{S}/      # 模型产物（形制同 runs/seed{S}/）
experiments/baseline_three_caliber_tables.md
```

**产物落 `eval_results/baseline/<name>/seed{S}/` 的理由**：
`collect_three_caliber_tables.row_from_run(run_rel, seeds)` 内部就是
`REPO/<run_rel>/seed{S}/test_probs.pt` 与 `thresholds.json` ⇒ 把 `run_rel` 设成
`eval_results/baseline/<name>` 即可**零重实现**复用整条汇总链。

## 3. 三条基线的实现与偏离

### A. MVD-HG —— 忠实复现（驱动其原代码）
建图**由它自己的代码产出**（`read_compile` → `append_method_message_by_dict` →
`append_control_flow_information` → `append_data_flow_information`），
四关系（AST/CFG/DFG）驱动 4 层 RGCN（300→64→32→16→8）。
偏离：DFG 有它的 40 s/文件上限；词向量只用 train 划分拟合（原实现用全体）；
dropout 保持它的 0.1；输出头 1→7。
**覆盖率 448/453（98.9%）**——5 个合约在任何已装 solc（试过全部 101 个候选）下都编不出
compact AST，**全部落在 train**，test 一个没少。

### B. EGFL —— 按论文重实现（原生字节码模态）
`solc --combined-json bin,bin-runtime` → 反汇编（复用 MANDO-LLM 的 144 条 opcode 表）→
基本块 CFG → BFS 展平。序列分支 = `Embedding → Conv1d → ConformerBlock`，
图分支 = 256 维 CFG 向量。
🔴 **图分支的 256 维是重建件**：原 `cfg_graph` 是**作者未开源的预处理产物**
（`Weights_CFG_SimOp/` 为 0 字节目录，全仓无脚本产出），论文只写「BFS 展平成 linear node feature
matrix」，切法不可考 ⇒ 本实现按「块内 opcode 词向量取平均 → BFS 前 k 块 concat」重建。
**不得声称复现了作者原结果。**
覆盖率 453/453（100%）。

### C. MANDO-LLM —— 按论文重实现（PyG `HGTConv` 替 dgl）
2 层 HGT / hidden 128 / heads 8；合约向量 = 全图节点隐层均值。
**节点类型取 9 类语义角色**（`_feat.pt::type_id`）——只用 1 类会把「异构图 transformer」
退化成「带 N 组关系参数的 RGCN」，丢掉算子本质。
图 = **我方 CFG 中心异构图**（不是原版的 slither 图）；节点输入主臂经 `model.NodeFuser`
⇒ 与本文方法**唯一变量 = 图算子**。
`hgt_metadata.json`（9 种节点类型 × 186 种边类型）**跨 seed 冻结**，带 `pool_sha256` 校验。

## 4. 跑批与汇总

- `run_baselines.py`：preflight 四条硬前置 → build（与 seed 无关）→ train（逐 seed）。
  链条**不含 `diagnose.py`**（三基线自己写 `test_probs.pt`，不走 SSMHG 专属链路）。
- `collect_baseline_tables.py`：行 = 本文方法 + 三基线 + Slither；逐类格与汇总列一律经
  `T.render_table`，support 走 `T.support_block`，薄支撑警告走 `T._thin_support_note`。

## 5. 实测到的坑（都已修，写在这里防复发）

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 27/453 MVD-HG 合约"编译失败" | 文件**中段还有第二条精确 pragma**（如 `pragma solidity 0.5.2;`），只有 0.5.2 恰好能编；而候选列表被截断在前 8 个 | `solc_candidates()` 全量回退（不设上限），覆盖 27→5 |
| 2 | `KeyError: 'IdentifierPath'` 整轮崩 | 词向量只拟合在 **train** 划分上，非 train 才出现的 AST 节点类型缺词 | 零向量兜底 + 计数上报（实测仅 6 个节点受影响） |
| 3 | 8/453 EGFL 合约 `ValueError: non-hexadecimal` | solc 对**未链接库**写占位符；0.4.x 是 `__<限定名>__`、0.5+ 是 `__$hash$__`，两种都 40 字符 | `sanitize_bin()` 锚定 `__…__` 骨架、按原长替 0（**保持字节偏移**）⇒ 8→0 |
| 4 | 子进程集体 rc=1，报 `MKL_THREADING_LAYER=INTEL is incompatible with libgomp` | 父进程 import torch 后，`env=None` 继承的环境让子进程 OpenMP 初始化崩（**报错完全指向 MKL，与根因无关**） | `subprocess.run(..., env=dict(os.environ))`（实测：`env=None` 连跑 5 次全 1，显式 env 连跑 5 次全 0） |
| 5 | 冒烟 `--limit-graphs 8` 直接报"所有类别正样本均为 0" | split 前缀全是干净合约（7 类真值全 0） | 冒烟改缩 **batch 数**，数据池保持全量 |
| 6 | MVD-HG 的 `config.py` 写死 `CUDA_VISIBLE_DEVICES="0,1"` | 本机只有 1 块 GPU；该副作用会泄进后续所有子进程 | `_import_mvdhg()` 快照 + 还原整个 `os.environ` |
| 7 | PyG 报 `indices larger than 384 (got 421)`；GPU 上是一句 device-side assert | `to_hetero` 的桶号反解把 s/d **写反**，边键的源/目标类型对调 | 反解顺序改为先 `//(R*T)` 得 s、再 `%T` 得 d（有单测锁死） |
| 8 | `hgt_metadata.json` 读回后 `unhashable type: 'list'` | JSON 把 tuple 还原成 list，而 `HGTConv` 拿 edge type 当 dict 键 | 落盘用 list、**读回转 tuple** |
| 9 | `check-ignore` 把「入库」误读成「已忽略」 | 退出码对白名单命中同样返回 0 | 判据改为「打出的规则带不带 `!`」 |

## 6. 范围外（预留接口）

- **DIVE 外部测试**（大纲 [395] 要求两设定）：三基线脚本的
  `--graph-dir/--split-dir/--label-file/--label-key-mode` 已做成语料无关，指向 DIVE 即可产同样的
  `test_probs.pt`；但 MVD-HG/EGFL 的离线特征要按 DIVE 源码目录再 build 一遍。建议第二阶段。
- 六个传统工具中除 Slither 外的 5 个（Mythril 等装进 base 有污染 torch 2.0.1 的风险，须先裁定装法）。
