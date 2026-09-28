#!/usr/bin/env python3
"""`研究点一细化大纲改II.docx` 的**编辑清单**（与引擎 `edit_outline.py` 分离）。

🔴 **这个文件是"大纲要改成什么"的唯一真源**：所有数值都在这里，引擎只负责安全落盘。
   每条编辑都带 `依据` 注释（产物路径 / 代码行号），**不许凭常识补全**。

🔴 **地址一律相对「原始文档」**：`edit_outline.py` 在开工前建一次索引，之后所有编辑都用
   那套地址。故本文件里的 `body:N` / `T7:r6:c1:p0` 全部按**未改动的大纲**编号，
   不必（也不能）手工重算偏移。
"""

# ---------------------------------------------------------------- 克隆源（格式参照）
# 全部取锚点**之前**的段落，位置永不漂移
H1 = "body:166"    # 「4.6  五模块数据流总览」      → Heading 1
H2 = "body:167"    # 「▶ 形式化目标闭合验证」        → Heading 2
NRM = "body:165"   # 普通正文段                     → Normal
LST = "body:159"   # 「合约级七维漏洞概率pG；」      → List Paragraph

# 参照表号（原有 T0–T12 的下标不会被新表挤动——新表一律插在 T12 之后）
T2COL, T3COL, T4COL = 3, 7, 11


# ---------------------------------------------------------------- §4.7 正文
_S47_LEAD = ("本节记录截至 2026-09-24 的**实际实现**，与 §4.1–§4.6 的设计描述互补："
             "设计与实现不一致时**以本节为准**；本节每条数值都可在仓库产物中复核"
             "（出处已逐条标注）。")

_S471 = [
    ["模块", "脚本", "输入", "输出（路径模板）"],
    ["M1 先验打分", "scripts/m1_runner.py + priori_scoring.py",
     "products/alldata/graphs/*_hetero.json", "products/alldata/graphs/*_m1.json"],
    ["M2 异构图构建", "scripts/build_cfg_centered_hetero_graph.py",
     "alldata(readonly)/alldata_sol_source/*.sol",
     "products/alldata/raw/（中间件）、products/alldata/graphs/（*_pyg.pt/*_hetero.json）"],
    ["M3 特征初始化", "scripts/m3_build_features.py",
     "graphs/ + CodeBERT 编码器目录", "*_feat.pt（结构/类型/s_v 三通道）、*_cb.pt（CodeBERT 两通道）"],
    ["正典变体（微调编码器）", "scripts/build_graph_variant.py --variant cb_ft",
     "runs/codebert_ft_p2/ss{S}/encoder",
     "products/alldata/graphs_ft_p2/cb_ft_ss{S}/（_hetero/_m1/_pyg 软链自 graphs/，只重算 _cb.pt）"],
    ["M4/M5 训练与评测", "scripts/train.py → evaluate.py → diagnose.py",
     "products/alldata/graphs_ft_p2/cb_ft_ss{S} + products/alldata/splits/split_seed{S}.json",
     "runs/seed{S}/（best.pt、results.json、thresholds.json、test_probs.pt、config.json）"],
    ["编码器微调", "scripts/finetune_codebert.py",
     "alldata(readonly)/ 源码 + 训练划分标签", "runs/codebert_ft_p2/ss{S}/encoder/（HF 格式目录）"],
    ["消融档（5 轮）编码器与特征树", "同上两条，但 `--epochs 5 --patience 2`",
     "runs/codebert_ft/alldata/ss{S}/encoder（**原地保留，未删**）",
     "products/alldata/graphs_ft/ss{S}/ —— **旧正典（5 轮档）**的输入树；"
     "其 GNN run 已归档于 `runs/prior_canon37/seed{S}`（**不另设名为 `cb_ft5` 的臂**）"],
]
_S471_NOTE_V2 = ("⚠ **正典输入的唯一真源** = `products/alldata/graphs_ft_p2/cb_ft_ss{S}`"
                 "（2026-09-25 编码器换代后的 20 轮档），"
                 "`cb_ft_ss{S}` **必须**与 `--split-seed S` 配对。"
                 "上一代 `products/alldata/graphs_ft/ss{S}`（§37，5 轮档）**原地保留**，"
                 "现为消融臂 `cb_ft5` 的输入；`products/alldata/graphs/` 是"
                 "**冻结编码器**树，现仅作 `cb_frozen` 消融臂输入。"
                 "三者构成编码器能力的**三档阶梯**（冻结 / 5 轮 / 20 轮），**只有最后一档是正典**。")
_S471_NOTE = ("⚠ **正典输入的唯一真源** = `products/alldata/graphs_ft_p2/cb_ft_ss{S}`"
              "（2026-09-25 编码器换代后的 20 轮档），"
              "`cb_ft_ss{S}` **必须**与 `--split-seed S` 配对。"
              "上一代 `products/alldata/graphs_ft/ss{S}`（§37，5 轮档）**原地保留**，"
              "是**旧正典（5 轮档）**的输入树 —— 该 run 已归档于 `runs/prior_canon37/seed{S}`，"
              "**不另设名为 `cb_ft5` 的臂**（2026-09-25 实测：`git log -S \"cb_ft5\" -- scripts/` 为空，"
              "`runs/ablation` 的 21 个臂里也没有它）；"
              "`products/alldata/graphs/` 是**冻结编码器**树，现仅作 `cb_frozen` 消融臂输入。"
              "三者构成编码器能力的**三档阶梯**（冻结 / 5 轮 / 20 轮），**只有最后一档是正典**；"
              "⚠ 5 轮档与 20 轮档的配对比较是**跨代对照**"
              "（`experiments/encoder_promotion_gate.md`，旧侧取归档），"
              "**不是**同一张消融表里的两行。")

_S472_HDR = ["阶段", "超参数", "实际值", "出处"]
_S472 = [
    ["M1", "命中一类得分 / external_callback / 多类命中 / 归一化",
     "+1.0 / +0.5 / 累加 / 全图 min-max（全 0 时保持 0）",
     "priori_scoring.py::compute_anchor_score"],
    ["M1", "锚点类目", "7 类锚点（reentrancy/arithmetic/access_control/uncheck_return/dos/front_running/time_manipulation）+ external_callback 辅助项",
     "priori_scoring.py::compute_anchor_flags"],
    ["M1", "后向传播", "无 DFG 反向一跳传播、无其他后处理", "m1_runner.py:167 注释"],
    ["M2", "物理关系数", "5（0=CFG_FLOW, 1=AST_PARENT, 2=AST_PARENT_SAME, 3=DFG_DEP, 4=CALLBACK_RISK）",
     "dataset.py:75-77, model.py:13"],
    ["M2", "CALLBACK_RISK", "单向；默认上限 4 条/外部调用节点；不连 delegatecall 动态绑定",
     "build_cfg_centered_hetero_graph.py"],
    ["M3", "节点类型嵌入", "9 类（ENTRY/CONDITION/ASSIGNMENT/EXT_CALL/INT_CALL/STATE_WRITE/STATE_READ/RETURN/OTHER）→ 64 维",
     "_feat.pt::meta.role_names"],
    ["M3", "CodeBERT 双通道", "函数级 [CLS] 768 维 + 节点局部窗口 [CLS] 768 维（microsoft/codebert-base）",
     "_feat.pt::meta.codebert"],
    ["M3", "结构特征", "30 维（可见性 4 + 布尔 14 + 外呼方式 5 + 归一化位置 1 + IR one-hot 6）",
     "_feat.pt::meta.struct_layout"],
    ["M3", "先验分数 s_v", "1 维（独立于结构张量）", "_feat.pt::sv"],
    ["M3", "融合层输入维度", "1631 = 64 + 768 + 768 + 30 + 1；隐层 128", "config.json::derived.fuser_in_dim"],
    ["M4", "RGCN", "层数 L=2、隐藏维 128、num_bases=5、dropout 0.3", "config.json::args"],
    ["M4", "L_var", "λ_var=1e-3、τ=0.1", "config.json::args"],
    ["M5", "优化器", "AdamW，lr=1e-4，weight_decay=1e-4，梯度裁剪 max_norm=1.0", "config.json::args"],
    ["M5", "批大小", "32", "config.json::args.batch_size"],
    ["M5", "学习率调度", "ReduceLROnPlateau(mode=max, factor=0.5, patience=3)，监控验证集 micro-F1",
     "train.py（大纲 4.5.1 实现注）"],
    ["M5", "早停", "验证集 micro-F1 连续 5 个 epoch 不提升即停；epoch 上限 200；取 val micro-F1 最高的 checkpoint",
     "config.json::args.early_stop_patience"],
    ["M5", "先验 Dropout", "训练期 p=0.2 将当前样本全部节点的 s_v 置 0；验证/推理不置零",
     "config.json::args.prior_dropout"],
    ["M5", "结构特征 Dropout", "p=0.2（常规正则化）", "config.json::args.struct_dropout"],
    ["M5", "pos_weight", "按训练集负/正比，上限截断 20；实测 reentrancy 16.2381、uncheck 9.3429，其余 5 类均被截断到 20",
     "config.json::derived.pos_weight"],
    ["M5", "DropEdge", "默认**关闭**（0.0）；仅消融臂 dropedge02 取 0.2",
     "config.json::args.drop_edge_prob"],
    ["M5", "阈值搜索", "0.20–0.80 步长 0.05，目标验证集 micro-F1，并列取较小阈值；仅用验证集",
     "evaluate.py:9, results.json::threshold_scan"],
    # ---- 编码器（2026-09-24 换代后：20 轮预算为新正典，5 轮下沉为消融档）----
    ["编码器微调（**新正典**）", "epoch 预算 / 早停 patience",
     "20 / 4；早停判据 = 验证集 macro-F1（该头在阶段 2 被丢弃）",
     "runs/codebert_ft_p2/ss{S}/config.json::args"],
    ["编码器微调（新正典）", "学习率 / 分类头 lr / 权重衰减 / 序列批大小",
     "2e-5 / 1e-3 / 0.01 / 6", "同上"],
    ["编码器微调（新正典）", "SWA 后缀权值平均",
     "`--swa-start 16`：对第 16 轮起的权值等权平均，再与最佳单轮 checkpoint 在验证集上比较、取优者。"
     "🔴 **实测三种子均未选中 SWA**（`n_averaged` = 0/0/2；ss0/ss1 的最佳轮为 ep10/ep11、"
     "早停于第 16 轮之前，SWA 窗口从未打开；ss2 累到 2 轮但 val 0.6290 低于最佳单轮的 0.7165）"
     "⇒ **本次换代的实际增益来自 epoch 预算，不是 SWA**。",
     "同上 ::swa"],
    ["编码器微调（**消融档**）", "短预算配置（本文早期口径）",
     "epoch 5 / patience 2 —— 该档的编码器树 `products/alldata/graphs_ft/ss{S}` **原地保留**，"
     "作为**旧正典（5 轮档）**的输入，与「冻结」（`cb_frozen` 臂）「收敛」（20 轮，现行正典）"
     "构成三档阶梯；该档**不另设同名消融臂**（其 run 已归档于 `runs/prior_canon37/seed{S}`，"
     "配对比较见 §4.7.5 与 `experiments/encoder_promotion_gate.md`）",
     "runs/codebert_ft/alldata/ss{S}/config.json::args"],
]

_S473_HDR = ["位段", "列数", "内容", "消融分组"]
_S473 = [
    ["可见性 one-hot", "4", "public / external / internal / private", "基础结构组"],
    ["布尔 14 项", "14", "#2 外部调用、#3 转账、#4 写状态、#5 读状态、#6 条件节点、#7 算术、#8 block.timestamp、#9 msg.sender/tx.origin、#10 调用返回值、#11 循环体内、#13 返回值被消费、#14 后继同函数状态写、#15 入口函数 ENTRY、#16 循环内外呼",
     "#2–#8 基础结构组；#9–#11、#13 漏洞语义组；#14–#16 CALLBACK_RISK 辅助组"],
    ["外部调用方式 one-hot", "5", "call / send / transfer / low_level / other", "漏洞语义组"],
    ["归一化位置", "1", "节点起始行在所属函数行数范围内的相对位置，裁剪到 [0,1]", "位置与指令组"],
    ["SlithIR 指令类别 one-hot", "6", "ASSIGNMENT / SOLIDITY_CALL / CONDITION / HIGH_LEVEL_CALL / LOW_LEVEL_CALL / OTHER",
     "位置与指令组"],
]
_S473_NOTE = ("⚠ **IR 类别为冻结字典**：6 类，跨语料（含 DIVE/SolidiFI）统一取自 "
              "`products/alldata/graphs/ir_cat.json`（`version=m3-categories-v1`），"
              "跨数据集评测必须显式传 `--categories` 指向它，否则列宽与类别语义会漂移。"
              "⚠ 上表 4+14+5+1+6 = **30**，与 `config.json::derived.D_struct` 一致。"
              "⚠ 模型总参数量 **415226**（融合层 209472 + RGCN 205754），见 "
              "`config.json::derived.parameter_report`。")

_S474_FUNNEL = [
    ["步骤", "合约数", "说明", "出处"],
    ["只读源文件", "591", "alldata(readonly)/alldata_sol_source/ 下的扁平 .sol 数", "raw/filter_report.txt"],
    ["标签索引（项目级）", "590", "按源码 sha1 → 项目标识/地址归并；n_unmatched=0", "config.json::label_source"],
    ["剔除 buggy_* 噪声项目", "−90 → 500", "buggy_* 家族标签为注入噪声（见下注）", "split_report.json::buggy_excluded_graphs"],
    ["去重", "−47 → 453", "先剔 buggy_* 再去重；46 个按源码 sha1、1 个按地址", "split_report.json::dedup"],
    ["训练池", "453", "train/val/test = 362/45/46（三种子规模相同）", "split_seed{0,1,2}.json"],
]
_S474_NOTE = ("🔴 **池内正样本侧几乎全是单标签**（实测）：池 453 个合约中**全零（正常）326 个、"
              "单标签 126 个、多标签仅 1 个**（该合约真值为 reentrancy + uncheck）。"
              "原始「多标签」现象集中在被剔除的 90 个 `buggy_*` 合约上——它们只有两种标签模式："
              "**80 个七类全 1**、**10 个为 arithmetic+time_manipulation+uncheck**，"
              "均为「每类各放一份」的注入假象（`decisions.md` §18.4），"
              "**不是真实的多标签标注**。⇒ 本库上的「七维多标签」任务，"
              "在**正样本侧实质接近单标签**；多标签能力主要由 DIVE 外部测试集与增强集体现。"
              "此事实须在论文中如实披露。"
              "⚠ **本表数字与仓库既有的一份自述文件不一致、以本表为准**："
              "`products/alldata/raw/data_funnel.json` 的步骤 25/26 把标签写成"
              "「全量图（581）」「划分池（448）」，而同一记录的数值字段是 590 与 453"
              "（标签与数值自相矛盾）。本文档此前的「591 源文件 / 448 池样本 / 323 个全零」"
              "即沿用了那两处错误标签，本次按 **split 产物实测值**改正为 453 / 326。")

_S474B_HDR = ["划分种子", "train 逐类正样本", "val 逐类正样本", "test 逐类正样本", "覆盖约束 C1/C2"]
_S474B = [
    ["ss0", "11/10/4/2/21/2/35", "3/3/1/1/5/1/8", "3/2/1/1/5/2/7", "全部达标"],
    ["ss1", "11/10/4/2/19/3/35", "3/3/1/1/6/1/8", "3/2/1/1/6/1/7", "全部达标"],
    ["ss2", "11/10/4/2/21/3/35", "3/2/1/1/5/1/8", "3/3/1/1/5/1/7", "全部达标"],
]
_S474B_NOTE = ("列序固定为 access_control / arithmetic / dos / front_running / reentrancy / "
               "time_manipulation / uncheck。池内逐类正样本总数为 17/15/6/4/31/5/50（三种子相同）。"
               "覆盖约束 C1 = 验证+测试合计每类正样本 ≥ 该类池内总数的 30%，C2 = 验证、测试"
               "各自每类 ≥ 1，均为**校正后达标**（`split_report.json::rule_check`）。"
               "⚠ 池内 `front_running` 仅 4 个正样本、`time_manipulation` 5 个 ⇒ "
               "test 侧逐类 support 低至 1，单类 F1 一次翻转即跳 ±0.67，"
               "这些类仅作描述性呈现、不进入方法间比较结论。")

_S475_HDR = ["阶段", "seed0", "seed1", "seed2", "口径", "出处"]
_S475 = [
    ["M1+M2 建图（591 源文件 → 590 图）", "未记录", "未记录", "未记录",
     "主构建**无计时记录**；变体重建 590 图约 68–78 s 可作下界参考",
     "（主构建脚本内无计时代码）"],
    ["M3 重编码（微调编码器，590 图 / 95918 节点）", "631.9 s", "578.5 s", "574.4 s",
     "重编码净耗时（GPU）", "runs/queue_logs/main_variant_cb_ft_ss{S}.log:2"],
    ["CodeBERT 微调（**新正典**，20 轮预算）", "1825.8 s", "1954.4 s", "2322.7 s",
     "wall（GPU，早停触发于 ep13/15/18）", "runs/codebert_ft_p2/ss{S}/config.json::timing.wall_seconds"],
    ["CodeBERT 微调（**消融档**，5 轮）", "933.5 s", "931.2 s", "680.9 s",
     "wall（GPU）——该档**已降为旧档（5 轮）**，不再进主方案（**不另设同名消融臂**）", "runs/codebert_ft/alldata/ss{S}/config.json::timing"],
    ["GNN 训练循环", "6.4 s", "4.6 s", "6.3 s", "train_seconds", "runs/seed{S}/config.json::timing"],
    ["GNN 端到端 wall", "8.6 s", "6.5 s", "8.6 s", "含验证推理与阈值搜索", "同上"],
    ["GNN 实际训练轮数", "13", "15", "18", "epochs_completed（早停触发）", "同上"],
    ["端到端合计（单种子，从零）", "≈2470 s", "≈2540 s", "≈2910 s",
     "= M3 重编码 + 编码器微调（20 轮档） + GNN wall（M1/M2 未计）", "上表逐行相加"],
]
_S475_NOTE_V2 = '🔴 **成本结构是本研究点最该被如实记录的一条**：编码器微调 + M3 重编码这两段**一次性上游成本合计约 2500–2900 s**，是 GNN 训练段（~8 s）的 **约 300 倍**。故「本文方法训练很快」**只对 GNN 段成立**；论文若要报端到端成本，必须把上游两段计入（本表末行已给出合计）。⚠ **三点必须随表披露**：① 编码器从 5 轮档换到 20 轮档，**上游成本随之由 ~850 s 涨到 ~2000 s**（约 2.3 倍）——这是换取代价，须与 §4.7.5 之后的增益一并报告；② M1/M2 的**主构建**（`generate_all_ast_cfg_dfg.sh`，591 源文件）在本仓**没有任何机器可读的计时记录**（脚本内无计时代码、日志目录无该步日志），表中所给仅为**变体重建** 590 图的近似下界，不得当作主构建耗时引用；③ 本表 GNN 段用的是**现行正典** `runs/seed{S}`（从零训练、`--deterministic`）—— 该产物原先落在 `runs/p2_canon/seed{S}`，2026-09-25 换代时**就位到正典路径**，`config.json` 与产物**逐字节未动**；而**消融档那一行**的计时出自**旧正典**，其产物是**由 `runs/cbft_study/cbft_ts{S}_ss{S}/seed{S}` 提升而来**（见其 `promoted_from` 字段），**不代表从零跑一遍的耗时**；旧正典的 run 现归档于 `runs/prior_canon37/seed{S}/`。另：5.3 对比表中三条基线的表内成本同样只含其模型训练段、离线特征工程另计，两侧口径一致（均为「模型训练」）。'
_S475_NOTE = '🔴 **成本结构是本研究点最该被如实记录的一条**：编码器微调 + M3 重编码这两段**一次性上游成本合计约 2500–2900 s**，是 GNN 训练段（~8 s）的 **约 300 倍**。故「本文方法训练很快」**只对 GNN 段成立**；论文若要报端到端成本，必须把上游两段计入（本表末行已给出合计）。⚠ **三点必须随表披露**：① 编码器从 5 轮档换到 20 轮档，**上游成本随之由 ~850 s 涨到 ~2000 s**（约 2.3 倍）——这是换取代价，须与 §4.7.5 之后的增益一并报告；② M1/M2 的**主构建**（`generate_all_ast_cfg_dfg.sh`，591 源文件）在本仓**没有任何机器可读的计时记录**（脚本内无计时代码、日志目录无该步日志），表中所给仅为**变体重建** 590 图的近似下界，不得当作主构建耗时引用；③ 本表 GNN 段用的是**现行正典** `runs/seed{S}`：它**从零训练**（`config.json::promoted_from` 为空，三种子实测），该产物原先落在 `runs/p2_canon/seed{S}`，2026-09-25 换代时**就位到正典路径**、`config.json` 与产物**逐字节未动**。⚠ **5 轮档（旧正典）的 GNN 端到端耗时本表给不出、也不得引用**：旧正典的 run 现归档于 `runs/prior_canon37/seed{S}/`，其 `config.json::promoted_from` = `runs/cbft_study/cbft_ts{S}_ss{S}/seed{S}`（三种子实测）⇒ 它是**当年由配对研究里那一份提升而来**，其 `timing` **不代表从零跑一遍的耗时**。故本表的 GNN 段**只为现行正典给出**。另：5.3 对比表中三条基线的表内成本同样只含其模型训练段、离线特征工程另计，两侧口径一致（均为「模型训练」）。'
_S475B_HDR = ["阶段", "步骤", "实测 wall（串行）", "说明"]
_S475B = [
    ["① 主库（阶段 3）", "3.1 结构变体树 `canon_p2`（6 棵）", "3 min 49 s",
     "边变体只重建 `_pyg.pt`/`_hetero.json`、**复用 `_cb.pt`** ⇒ 远快于原先估算的 1.1 h"],
    ["", "3.2 `run_cbft_study`（18 run）", "7 min 10 s", "n=9 配对基线"],
    ["", "3.3 `run_ablation`（63 run，n=3）", "23 min 40 s", "21 臂 × 3 种子"],
    ["", "3.4 `run_ablation_n9`（216 run：153 + 63）", "1 h 15 min 13 s",
     "= 首跑 58 min + 补跑 17 min 13 s；**首跑不是白跑**（见注②）"],
    ["", "3.5 GCN 对照臂（3 run）", "50 s", "逐类 F1 表的输入"],
    ["", "3.6 逐类独立二分类臂（45 run）", "9 min 14 s", "7 类 × 2 配置 × 3 种子"],
    ["", "3.7 跨种子聚合 + 3.9 `ANY_union` 重放（3 run）", "5 s + 44 s", ""],
    ["", "3.8 DIVE/SolidiFI 输入侧重编码", "2 h 18 min 33 s",
     "① 3 棵树 + 12 棵变体树；**本阶段最长一项**（见注③）"],
    ["", "**① 小计**", "**4 h 29 min 47 s**", "09:35:15 → 14:05:02"],
    ["任务 2（阶段 4）", "4.1 编码器微调 ×3（20 轮预算）", "2 h 01 min 39 s",
     "逐种子 31 min 53 s / 40 min 25 s / 49 min 21 s（早停于 ep11/15/14）"],
    ["", "4.2 M3 重编码（590 图 × 3）", "32 min 05 s", ""],
    ["", "4.3 结构变体树 `buggy_p2`（6 棵）", "3 min 31 s", ""],
    ["", "4.4 正典 GNN（train/eval/diagnose/summarize）", "1 min 12 s", ""],
    ["", "4.5 消融（63 run，n=3）", "19 min 35 s", "池 497 侧"],
    ["", "4.6 架构族（9 run）", "2 min 03 s", ""],
    ["", "4.7 三条论文基线（MVD-HG/EGFL/MANDO）", "**0**（裁定不重跑）",
     "实测三者均**不读 `_cb.pt`**（MVD-HG/EGFL 自建 AST/反汇编；MANDO 只读结构通道；Slither 只吃源码）"],
    ["", "**任务 2 小计**", "**3 h 00 min 05 s**", "14:05:03 → 17:05:08"],
    ["**合计**", "**本次换代总成本**", "**7 h 29 min 52 s**", "① + 任务 2，串行；M1/M2 建图未重跑"],
]
_S475B_NOTE = ("🔴 **本表与 §4.7.5 正表口径不同、不可相加**：正表是「从零训一个模型」的单次成本，"
               "本表是「已有一整套正典，把整条链整体换到新编码器档」的**重跑成本**——"
               "它包含上游重建（编码器微调 + M3 重编码）**以及**下游全部对照臂的重跑。"
               "⚠ **三点必须随表披露**："
               "① 全部为**串行墙钟**（单卡 RTX 4070 Laptop，GPU 独占），未做任何并行；"
               "② **3.4 的 1 h 15 min 里，首跑 58 min 产出了 162 个 run**"
               "（`ablation_n9` 153 + `conv_gcn` 9），只在 `conv_gat` 一步因 "
               "`scatter_reduce_cuda does not have a deterministic implementation` 而中止；"
               "修复（把 `gat` 排除在 `--deterministic` 之外）后补跑 54 个用 17 min 13 s"
               "⇒ **净浪费≈0 计算量**，代价是**串行阻塞**（3.5–3.9 必须等它跑完）；"
               "③ **3.8 一项就占 ① 侧 4 h 30 min 的一半以上**（2 h 18 min 33 s），"
               "而它只重编码 DIVE/SolidiFI 的特征、按裁定**不产新的交付数字**"
               "（外部评测保留换代前矩阵，见 §5.5.1 的口径披露）"
               "⇒ 若只算「产出交付表所必需」的部分，① 侧净成本约 **2 h 11 min**。")

_S476 = [
    ["口径项", "设定"],
    ["主指标", "micro-F1（标签对级），两工作点并列报告：固定 0.5 与验证集阈值"],
    ["参考指标", "macro-F1（7 类未加权平均）、逐类 P/R/F1、per-class PR-AUC、mAP（阈值无关）"],
    ["阈值", "0.20–0.80 步长 0.05，目标验证集 micro-F1，并列取小；只在验证集搜，测试集不参与"],
    ["随机种子", "数据划分种子与训练种子分离，各 3 个（0/1/2）；主种子 seed0，最佳种子口径另见 5.1"],
    ["平凡下限", "七维 micro 0.1224（322 个标签格中 6.5% 为正）；合约级二分类 0.6199（46 个测试合约中 45.7% 有漏洞）"],
    ["区间估计", "micro-F1 的 bootstrap 95% CI 宽达 0.34–0.40（46 个测试合约 / 21 个正标签对）⇒ **不得**用 micro-F1 的小数位差异下方法优劣结论"],
]
_S476_NOTE = ("⚠ 两个口径的平凡下限相差 0.50，**七维与合约级二分类的数字不可互比**；"
              "诊断补充口径（`clean_only`、温度缩放、per-class 阈值、多种子集成）"
              "一律**不进主结果**，见 `experiments/decisions.md`。")

_S477 = [
    ["对照臂族", "规模", "用途"],
    ["消融臂（必要+可选）", "**21 臂**：n=3 对角（63 run）+ **n=9 同配对复核**（126 run）；判「有效/无效」以 n=9 为准",
     "逐模块验证：边、通道、池化、L_var、先验 Dropout、特征分组、层数/宽度/基分解、DropEdge、冻结编码器。"
     "**判「有效/无效」以 n=9 为准**（n=3 只作描述性读数）"],
    ["架构基线族", "GCN / GAT / SAGE × 3 种子 + 参数量匹配对照；另有 **n=9 同配对复核**"
     "（7 臂 × 9 点，含 `hid256_pm`）", "关系感知 vs 关系盲的内部证据（**不是** 5.3 的对比方法）"],
    ["逐类独立二分类臂", "7 类 × 2 配置 × 3 种子", "回答「多标签共享是否压制了稀有类」"],
    ["二分类头臂", "--head binary，3 种子", "单变量消融：只换输出空间（7→1）"],
    ["论文基线（5.3 对比方法）", "MVD-HG / EGFL / MANDO-LLM × 3 种子", "三条论文基线的重实现"],
    ["传统工具（5.3 对比方法）", "Securify / Mythril / Slither / Manticore / SmartCheck / Oyente", "不训练；Slither 走主环境，其余五个各在独立 conda env"],
]


def block_47() -> list[tuple]:
    """§4.7 整节（插在 `body:168`「5  实验设计」之前，即 §4.6 之后）。"""
    B: list[tuple] = []
    B.append(("para", "4.7  实现细节与产物清单（实际落地口径）", H1))
    B.append(("para", _S47_LEAD, NRM))

    B.append(("para", "4.7.1  代码与产物路径总表", H2))
    B.append(("table", _S471, T4COL))
    B.append(("para", _S471_NOTE, NRM))

    B.append(("para", "4.7.2  实际超参数（逐项可复核）", H2))
    B.append(("table", [_S472_HDR] + _S472, T4COL))

    B.append(("para", "4.7.3  结构特征 30 位的逐位构成", H2))
    B.append(("table", [_S473_HDR] + _S473, T4COL))
    B.append(("para", _S473_NOTE, NRM))

    B.append(("para", "4.7.4  数据漏斗与划分（实测）", H2))
    B.append(("table", _S474_FUNNEL, T4COL))
    B.append(("para", _S474_NOTE, NRM))
    B.append(("para", "逐种子的逐类正样本数（列序同标签顺序）：", NRM))
    B.append(("table", [_S474B_HDR] + _S474B, T4COL))
    B.append(("para", _S474B_NOTE, NRM))

    B.append(("para", "4.7.5  训练成本（逐种子实测）", H2))
    B.append(("table", [_S475_HDR] + _S475, T4COL))
    B.append(("para", _S475_NOTE, NRM))

    B.append(("para", "4.7.6  评测口径", H2))
    B.append(("table", _S476, T3COL))
    B.append(("para", _S476_NOTE, NRM))

    B.append(("para", "4.7.7  对照臂与对比方法清单", H2))
    B.append(("table", _S477, T4COL))
    return B


# ---------------------------------------------------------------- 编辑清单
# ---------------------------------------------------------------- 换代前的 docx 原文
# 🔴 下面两段是 **2026-09-25 编码器换代之前** `.docx` 里的段落原文，**逐字保留**。
#    用途只有一个：作为上面两条整段 `replace` 编辑的 `old`。有了它，这批编辑是**幂等**的
#    ——落盘后 `old` 不再存在、`new`（= `_S471_NOTE` / `_S475_NOTE`）在场，重跑自动跳过。
#    ⚠ **不要**把它们同步成新文本：那就等于把 `old` 抹掉，编辑会失去可重放性。
_DOCX_S471_NOTE_OLD = '⚠ **正典输入的唯一真源** = `products/alldata/graphs_ft/ss{S}`，`ss{S}` **必须**与 `--split-seed S` 配对。`products/alldata/graphs/` 是**冻结编码器**树，现仅作 `cb_frozen` 消融臂输入，不得再写作正典。'
_DOCX_S475_NOTE_OLD = '🔴 **成本结构是本研究点最该被如实记录的一条**：编码器微调 + M3 重编码这两段**一次性上游成本合计约 2500–2900 s**，是 GNN 训练段（~8 s）的 **约 300 倍**。故「本文方法训练很快」**只对 GNN 段成立**；论文若要报端到端成本，必须把上游两段计入（本表末行已给出合计）。⚠ **三点必须随表披露**：① 编码器从 5 轮档换到 20 轮档，**上游成本随之由 ~850 s 涨到 ~2000 s**（约 2.3 倍）——这是换取代价，须与 §4.7.5 之后的增益一并报告；② M1/M2 的**主构建**（`generate_all_ast_cfg_dfg.sh`，591 源文件）在本仓**没有任何机器可读的计时记录**（脚本内无计时代码、日志目录无该步日志），表中所给仅为**变体重建** 590 图的近似下界，不得当作主构建耗时引用；③ 本表 GNN 段用的是**新正典** `runs/p2_canon/seed{S}`（从零训练、`--deterministic`）；而**消融档那一行**的计时出自旧正典 `runs/seed{S}`，该产物是**由 `runs/cbft_study/cbft_ts{S}_ss{S}/seed{S}` 提升而来**（见其 `promoted_from` 字段），**不代表从零跑一遍的耗时**。另：5.3 对比表中三条基线的表内成本同样只含其模型训练段、离线特征工程另计，两侧口径一致（均为「模型训练」）。'

EDITS: list[tuple] = [
    # ---- 一、已核实的口径滞移修正（非编码器相关）----
    # 依据：products/alldata/splits/split_report.json（unique_contracts=453、all_zero_contracts=326）
    ("replace", "body:196",
     "训练池实为 323/448 个全零（正常）合约",
     "训练池实为 326/453 个全零（正常）合约"),
    ("replace", "body:213",
     "去重后591个源文件 / 448 个训练池样本，且训练池实为 323 个全零（正常）合约",
     "去重后591个源文件经项目级归并（590）并剔除 buggy_* 噪声（90）与重复（47）后得到 453 个训练池样本，"
     "其中全零（正常）合约 326 个、真正多标签合约仅 1 个"),
    # 依据：runs/seed0/config.json::args.drop_edge_prob = 0.0（默认关闭）
    # ⚠ 必须用 `replace_in_table`：`old="0.1"` 是短串，全文另有 5 处命中，
    #    按段落定位会因「不唯一」直接报错（本脚本实测）。`needle` 取该表首列独有的文本。
    ("replace_in_table", "消息传递层数L", "0.1", "0（默认关闭；仅消融臂 dropedge02 取 0.2）"),
    # 依据：split_report.json（590 项目级索引 → 453 池）与 alldata(readonly) 实际布局
    # ⚠ 锚点用**文字前缀**而非 `T13:r1:c2:p1`：本脚本自己会往 §4.7 插表，
    #    插完 `T13` 会变成 `T21`，用地址的锚点在重跑时解析不出来。
    ("insert", "数据按七类漏洞文件夹组织，原始记录共3482条", [
        ("上述 2002 为**合约名级**条目数。构建图时按项目前缀（`__` 前第一段，剥去 `asd_`/`nasd_`）"
         "归并为 **590 个唯一项目级合约**；再剔除 `buggy_*` 注入噪声（90）与源码重复（47）后，"
         "构成**训练池 453**（train/val/test = 362/45/46），其中全零（正常）合约 326 个。"
         "三份只读源现为 `alldata(readonly)/alldata_sol_source/` 下**扁平 591 个 `.sol`**"
         "（原始七类文件夹组织在导入时已摊平；上表的类别记录数 3482 = 474+514+406+398+543+444+703 "
         "为该阶段的统计）。详见 §4.7.4。", NRM),
    ]),

    # ---- 二、编码器换代（2026-09-24 闸门通过，用户裁定：「确实上升就提升为正典，
    #          旧的作为消融实验，并同步修改大纲设计」）----
    # 依据：experiments/encoder_promotion_gate.md（G1/G2/G3 三门全过）；
    #      runs/codebert_ft_p2/ss{S}/config.json（epochs=20/patience=4/swa_start=16、swa 实测）
    ("replace", "body:72",
     "冻结编码器作为消融对照保留。",
     "编码器**微调至收敛**：epoch 预算 20、按验证集 macro-F1 早停（patience=4），"
     "并配置后缀权值平均（SWA，`--swa-start 16`）作为选点对照。"
     "**冻结编码器**与**短预算微调（5 轮）**共同作为消融对照保留，"
     "消融实验中形成「冻结 / 短预算（5 轮）/ 收敛（20 轮）」**三档阶梯**。"
     "实测（3 个划分种子，编码器自身验证集 macro-F1）：收敛档 0.9544 / 0.6747 / 0.7165，"
     "短预算档 0.5258 / 0.6067 / 0.4365，三档**逐种子单调提升**；"
     "下游 GNN 的配对比较（mAP +0.1369、macro-F1@验证集阈值 +0.1923，3/3 种子不劣）"
     "见 §4.7.5 与 `experiments/encoder_promotion_gate.md`。"),
    ("replace", "body:75",
     "消融实验中报告“冻结CodeBERT”与“微调CodeBERT”在验证集macro-F1上的差异。",
     "消融实验按**三档阶梯**报告 CodeBERT 处理方式的差异：**冻结**（不执行本阶段）/ "
     "**短预算微调（epoch 预算 5、patience 2）** / **收敛微调（epoch 预算 20、patience 4，本文主方案）**，"
     "比较各自在验证集 macro-F1 上的表现及对下游 GNN 的影响。"),
    ("replace", "body:146",
     "训练5个epoch，编码器学习率2e-5，分类头学习率1e-3，权重衰减0.01，序列批大小6，"
     "并按验证集macro-F1早停（patience=2）。该阶段只使用训练划分的标签，验证与测试划分不参与；"
     "冻结编码器的对照设置除不执行本阶段外，其余超参数完全相同。",
     "**epoch 预算 20、按验证集 macro-F1 早停（patience=4）**，编码器学习率2e-5，"
     "分类头学习率1e-3，权重衰减0.01，序列批大小6。此外配置**后缀权值平均（SWA）**作为选点对照："
     "对第 16 轮起的权值取等权平均，与最佳单轮 checkpoint 在验证集上比较、取优者。"
     "🔴 **实测（3 个划分种子）SWA 一次都没被选中**：ss0/ss1 的最佳轮分别是第 10/11 轮，"
     "早停在第 16 轮之前触发 ⇒ 平均窗口从未打开（`n_averaged`=0）；"
     "ss2 累到 2 轮，但其验证集 macro-F1（0.6290）低于最佳单轮的 0.7165，故仍取最佳单轮。"
     "⇒ **本次编码器换代的增益来自 epoch 预算（5 → 20），不是 SWA**；"
     "SWA 在本配置下属「已实现、已运行、无增益」，如实报告。"
     "该阶段只使用训练划分的标签，验证与测试划分不参与。"
     "**消融对照共两档，除本阶段的执行方式外其余超参数完全相同**："
     "① 冻结编码器（不执行本阶段）；② 短预算微调（epoch 预算 5、patience 2，本文早期的编码器配置）。"),
    # ⚠ needle 必须**唯一**指向目标表：`"消融变体"` 在 T15（必要消融）与 T16（可选消融）里都有，
    #    用它会让 `find_table` 因「命中 2 张表」直接报错 ⇒ 改用只在该行出现的文本。
    ("replace_in_table", "冻结CodeBERT vs 微调CodeBERT",
     "冻结CodeBERT vs 微调CodeBERT",
     "CodeBERT 三档阶梯（冻结 / 短预算微调 5 轮 / 收敛微调 20 轮）"),
    ("replace_in_table", "冻结CodeBERT相对微调CodeBERT在验证集macro-F1上的损失",
     "冻结CodeBERT相对微调CodeBERT在验证集macro-F1上的损失",
     "各档在验证集 macro-F1 上的差异及对下游 GNN 的影响；本文主方案 = 收敛档。"
     "编码器侧实测三种子：收敛档 0.9544/0.6747/0.7165 vs 短预算档 0.5258/0.6067/0.4365"),

    # ---- 四之二、2026-09-25 口径修正（用户裁定 **(A) 改口径、零重跑**）----
    # 🔴 `cb_ft5` 是一个**只存在于文档里的臂名**。三条实测证据：
    #    ① `git --no-pager log -S "cb_ft5" -- scripts/` **为空**（脚本里从未出现）；
    #    ② `runs/ablation` 的 21 个臂里**没有**它（编码器臂只有 `cb_frozen`）；
    #    ③ 中档（5 轮）的**真实产物是归档的旧正典** `runs/prior_canon37/seed{S}`
    #       （其 `config.json::args.graph_dir = …/graphs_ft/ss{S}`，三种子逐条实测）。
    #    裁定 (A) = **改口径、不造臂**（造臂会打破「21 臂」的硬引用与多张表的行数、`n/21` 断言）。
    ("replace_in_table", "scripts/m1_runner.py",
     "products/alldata/graphs_ft/ss{S}/ —— 消融臂 `cb_ft5` 的输入",
     "products/alldata/graphs_ft/ss{S}/ —— **旧正典（5 轮档）**的输入树；"
     "其 GNN run 已归档于 `runs/prior_canon37/seed{S}`（**不另设名为 `cb_ft5` 的臂**）"),
    ("replace_in_table", "短预算配置",
     "作为**消融臂 `cb_ft5`** 的输入，与「冻结」（`cb_frozen`）「收敛」（20 轮，现行正典）构成三档阶梯",
     "作为**旧正典（5 轮档）**的输入，与「冻结」（`cb_frozen` 臂）「收敛」（20 轮，现行正典）"
     "构成三档阶梯；该档**不另设同名消融臂**（其 run 已归档于 `runs/prior_canon37/seed{S}`，"
     "配对比较见 §4.7.5 与 `experiments/encoder_promotion_gate.md`）"),
    # 脚注段落 `_S471_NOTE`：`V2 → 终态`（与上面那条 `"superseded"` 成对，见其注释）
    ("replace", "_S471_NOTE", _S471_NOTE_V2, _S471_NOTE),

    # ---- 四之三、用户裁定「补齐第 3、4 项」：n=9 判据口径 + L_var 剂量臂 ----
    # 第 3 项（n=9）依据：本仓既有规矩「判「有效/无效」须同配对 ≥9 点」——
    #   原话在 `experiments/ablation_three_metric_table.md` 与 `decisions.md` §26.7/§27.5，
    #   而大纲 §5.2 此前只写「至少 3 个随机种子」⇒ **设计没记全**。
    #   产物：`runs/ablation_n9/`（153 run）、`runs/arch_n9/`（63 run）；
    #   报告：`experiments/ablation_n9_results.md`（逐配对 Δ + 配对 t）。
    ("replace", "§5.2 随机种子",
     "所有主实验至少运行3个随机种子，并报告均值与标准差。",
     "**所有主实验至少运行 3 个随机种子，并报告均值与标准差**（主实验的最低要求）。"
     "⚠ **凡要对干预下「有效/无效」结论，须用同配对 ≥9 点**：配对点 = (训练种子 × 划分种子) 的全交叉 3×3；"
     "只沿对角取 3 点即 n=3，**仅作描述性读数、不作结论**。"
     "本研究的 21 臂消融与架构基线族（GCN/GAT/SAGE 及参数量匹配对照）均已按 **n=9** 同配对复核，"
     "逐配对 Δ 与配对 t 见 `experiments/ablation_n9_results.md`；n=3 与 n=9 **并存**，"
     "n=3 的价值在于对照「哪些结论在 n=9 下翻转」。"),
    # ⚠ 本条必须带 **`"exact"`**：`old`（`21 臂 × 3 种子`）会被新文本包含 ⇒ 子串匹配在复跑时
    #   会**再替换一遍**、把整格文字叠加成两遍（2026-09-25 实测发生并已回滚）。
    #   同时**新文本里不能出现 `old` 原文**——否则 `--verify` 的「含新文本的段里旧文本仍在」判据
    #   会把已落盘的正常状态误报成「半改状态」（实测 20/21）。
    ("replace_in_table", "对照臂族",
     "21 臂 × 3 种子",
     "**21 臂**：n=3 对角（63 run）+ **n=9 同配对复核**（126 run）；判「有效/无效」以 n=9 为准",
     "exact"),
    # 第 4 项（剂量臂）依据：`run_ablation.py::DOSE_ARMS`（3 档 λ）+ `--with-dose-arms`；
    #   读数取自 `experiments/ablation_n9_results.md`（逐格 Δ 表与判据表，均 n=9）。
    #   ⚠ 该臂在 `run_ablation.py:102-111` 自述为「**大纲之外的后处理**」⇒ 本次按裁定补进大纲，
    #     并同步 `论文开发手册.md`（AGENTS.md 改动原则要求两处同步）。
    # §5.4.2 可选消融表**缺一整行**（该表末行 = 「CodeBERT 三档阶梯」，插在其后）
    ("table_row_after", "num_bases不同取值", "CodeBERT 三档阶梯",
     ["L_var 剂量-反应（λ=0.01 / 0.1 / 1.0，基线 1e-3）",
      "方差正则强度的影响。**实测 n=9 三个剂量全无增益**（主判据 Δ 均 < 0；同号计数 "
      "0+/2−/7=0、1+/5−/3=0、2+/5−/2=0，皆未过判据）⇒ 本实验的 λ 尺度下该项不产生可测影响"
      "（λ·L_var 仅占总损失 0.0003%–0.0054%）；**不得**据此写成「L_var 无作用」"]),

    # ---- 四、2026-09-25 编码器换代（混合换位）后的路径同步 ----
    # 依据：runs/seed{S}/config.json::args.graph_dir = products/alldata/graphs_ft_p2/cb_ft_ss{S}
    #      （实测三种子配对）；products/alldata/graphs_ft_p2/ 下三套树各 590 图；
    #      runs/codebert_ft_p2/ss{S}/encoder/corpus.json 存在。
    # ⚠ **顺序敏感**：`runs/codebert_ft/alldata/ss{S}/encoder` 是另一格
    #    `…/encoder/（HF 格式目录）` 的**前缀** ⇒ 必须先替换长的那个，
    #    否则第一格替换时会有 2 个候选段、被唯一性判拒绝（本脚本实测过同族错）。
    ("replace_in_table", "scripts/m1_runner.py",
     "runs/codebert_ft/alldata/ss{S}/encoder/（HF 格式目录）",
     "runs/codebert_ft_p2/ss{S}/encoder/（HF 格式目录）"),
    # ⚠ 这一格必须用 **`"exact"`**：`…/encoder` 是另两格的前缀（`…/encoder/（HF…）` 与
    #   本批 `table_row_after` 新插的「消融档」行里的 `…/encoder（**原地保留，未删**）`）
    #    ⇒ 子串匹配会在重跑时改错格且不报错（2026-09-25 干跑时发现）。
    ("replace_in_table", "scripts/m1_runner.py",
     "runs/codebert_ft/alldata/ss{S}/encoder",
     "runs/codebert_ft_p2/ss{S}/encoder", "exact"),
    ("replace_in_table", "scripts/m1_runner.py",
     "products/alldata/graphs_ft/ss{S}/（_hetero/_m1/_pyg 软链自 graphs/，只重算 _cb.pt）",
     "products/alldata/graphs_ft_p2/cb_ft_ss{S}/（_hetero/_m1/_pyg 软链自 graphs/，只重算 _cb.pt）"),
    ("replace_in_table", "scripts/m1_runner.py",
     "products/alldata/graphs_ft/ss{S} + products/alldata/splits/split_seed{S}.json",
     "products/alldata/graphs_ft_p2/cb_ft_ss{S} + products/alldata/splits/split_seed{S}.json"),
    # 该表**缺一整行**「消融档」⇒ 用新增的 `table_row_after`（参照行 = 「编码器微调」那行）
    # ⚠ `cells[0]` **一个字都不要改**：`table_row_after` 的幂等判据就是「新行首格文本已在表里」，
    #   改它会让重跑**再插一行**（表格不像段落那样有全文相等守卫兜底）。要改行内文字，
    #   一律另加 `replace_in_table` 就地改（见下方「四之二」批）。
    ("table_row_after", "scripts/m1_runner.py", "编码器微调",
     ["消融档（5 轮）编码器与特征树", "同上两条，但 `--epochs 5 --patience 2`",
      "runs/codebert_ft/alldata/ss{S}/encoder（**原地保留，未删**）",
      "products/alldata/graphs_ft/ss{S}/ —— **旧正典（5 轮档）**的输入树；"
      "其 GNN run 已归档于 `runs/prior_canon37/seed{S}`（**不另设名为 `cb_ft5` 的臂**）"]),
    # 表 #14 的「消融档」行：点名该档的**真实身份**（旧正典，非独立臂）
    # ⚠ `new` 已是**终态文本**：`"四之二"` 批里那条 `cb_ft5` → 终态的 `replace_in_table`
    #    落盘后，本条的 `old` 与 `new` 就都不在文档里了（表格分支的兜底是「new 已在表里 ⇒ 跳过」，
    #    终态一致时两边都命中不到 ⇒ 必须先把它对齐到终态，否则重跑会 `SystemExit`）。
    ("replace_in_table", "短预算配置",
     "作为「短预算微调」消融臂的输入，与「冻结」「收敛」构成三档阶梯",
     "作为**旧正典（5 轮档）**的输入，与「冻结」（`cb_frozen` 臂）「收敛」（20 轮，现行正典）"
     "构成三档阶梯；该档**不另设同名消融臂**（其 run 已归档于 `runs/prior_canon37/seed{S}`，"
     "配对比较见 §4.7.5 与 `experiments/encoder_promotion_gate.md`）"),
    # 表 #18（成本表）GNN 段的出处：换位后就位到 `runs/seed{S}`（原为 `runs/p2_canon/seed{S}`）
    ("replace_in_table", "GNN 训练循环",
     "runs/p2_canon/seed{S}/config.json::timing",
     "runs/seed{S}/config.json::timing"),
    # 两个脚注段落与 spec 分叉（整段替换）。`old` = **换代前 docx 的原文**（见下方常量），
    # 保留它是为了让本批编辑**幂等**：落盘后 `old` 消失、`new` 在场 ⇒ 重跑即跳过。
    # ⚠ `_S471_NOTE` 这条的 `new` 是 `_S471_NOTE_V2`（**非终态**）——它的输出已被「四之二」批里
    #    `_S471_NOTE_V2 → _S471_NOTE`（终态）那条覆盖 ⇒ 标 `"superseded"`，否则落盘后两边都找不到。
    ("replace", "_S471_NOTE", _DOCX_S471_NOTE_OLD, _S471_NOTE_V2, "superseded"),
    ("replace", "_S475_NOTE", _DOCX_S475_NOTE_OLD, _S475_NOTE_V2, "superseded"),
    # ---- 四之五、成本表脚注 ③ 的措辞纠正（2026-09-25 复核时发现）----
    # 🔴 原措辞把 `promoted_from` 挂错了对象：实测该字段**不在** `runs/cbft_study/*` 上，
    #    而在**归档的旧正典** `runs/prior_canon37/seed{S}/config.json` 上，其值 =
    #    `runs/cbft_study/cbft_ts{S}_ss{S}/seed{S}`；而现行正典 `runs/seed{S}` 的该字段为**空**
    #    （三种子实测）⇒ 现行正典确是**从零训练**、旧正典才是"提升而来"。
    #    原文还写「消融档那一行…」——但成本表**没有** 5 轮档的 GNN 行，指代落空。
    ("replace", "_S475_NOTE", _S475_NOTE_V2, _S475_NOTE),
    # ⚠ 同一批里还要改**成本表那一格**：它写「该档**现为消融臂**」——按 (A) 改口径后，
    #   5 轮档是**旧档**、不另设同名臂。`new` 里不含 `old`（`--verify` 的要求）。
    ("replace_in_table", "GNN 训练循环",
     "wall（GPU）——该档现为消融臂，不再进主方案",
     "wall（GPU）——该档**已降为旧档（5 轮）**，不再进主方案（**不另设同名消融臂**）"),

    # ---- 四之四、成本表续：**本次编码器换代的整体重跑成本**（用户裁定第 5 项）----
    # 依据：`runs/p3_stdout.log`、`runs/p3_resume_stdout.log`、`runs/p3_finish_stdout.log`、
    #      `runs/p3d_p4_chain.log` 里 `step()` 的逐条时间戳（引擎不产数字，本表逐格抄自这些日志）。
    # 锚点 = §4.7.6 的标题段落 ⇒ 新段落与新表落在 §4.7.5 末尾（**不改 §4.7.6/§4.7.7 的编号**）。
    ("block_before", "4.7.6  评测口径", [
        ("para", "本次编码器换代的整体重跑成本（实测 wall，串行，单卡）：", NRM),
        ("table", [_S475B_HDR] + _S475B, T4COL),
        ("para", _S475B_NOTE, NRM),
    ]),

    # ---- 三、新增 §4.7 实现细节整节 ----
    # 锚点 = 「5  实验设计」；§4.6 结束于表 T12，故必须用 block_before（插在锚点之前）
    ("block_before", "body:168", block_47()),


]
