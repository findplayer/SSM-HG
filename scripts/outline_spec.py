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
_S47_LEAD = ("本节记录截至 2026-09-30 的实际实现，与 §4.1 至 §4.6 的设计描述互补。"
             "设计与实现不一致时，以本节为准。本节的每条数值都可以在仓库产物中逐条复核，"
             "出处随文标注。")

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
     "runs/codebert_ft_buggy_p2/ss{S}/encoder",
     "products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S}/（_hetero/_m1/_pyg 软链自 graphs/，只重算 _cb.pt）"],
    ["M4/M5 训练与评测", "scripts/train.py → evaluate.py → diagnose.py",
     "products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S} + "
     "products/alldata/splits/withbuggy_snapshot/split_seed{S}.json",
     "runs/buggy_canon/seed{S}/（best.pt、results.json、thresholds.json、test_probs.pt、config.json）"],
    ["编码器微调", "scripts/finetune_codebert.py",
     "alldata(readonly)/ 源码 + 训练划分标签（products/alldata/splits/withbuggy_snapshot/）",
     "runs/codebert_ft_buggy_p2/ss{S}/encoder/（HF 格式目录）"],
    ["消融档（5 轮）编码器与特征树", "同上两条，但 `--epochs 5 --patience 2`",
     "runs/codebert_ft/alldata/ss{S}/encoder（原地保留，未删）",
     "products/alldata/graphs_ft/ss{S}：编码器阶梯的短预算（5 轮）对照档；"
     "其 GNN run 归档于 runs/prior_canon37/seed{S}"],
]
_S471_NOTE_V2 = ("⚠ **正典输入的唯一真源** = `products/alldata/graphs_ft_p2/cb_ft_ss{S}`"
                 "（2026-09-25 编码器换代后的 20 轮档），"
                 "`cb_ft_ss{S}` **必须**与 `--split-seed S` 配对。"
                 "上一代 `products/alldata/graphs_ft/ss{S}`（§37，5 轮档）**原地保留**，"
                 "现为消融臂 `cb_ft5` 的输入；`products/alldata/graphs/` 是"
                 "**冻结编码器**树，现仅作 `cb_frozen` 消融臂输入。"
                 "三者构成编码器能力的**三档阶梯**（冻结 / 5 轮 / 20 轮），**只有最后一档是正典**。")
_S471_NOTE = ("本文主实验的图输入为 products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S}，"
              "它是含 buggy_* 的训练池所对应的微调 CodeBERT 重编码特征树，"
              "其中 S 为划分种子，必须与 --split-seed S 配对使用。"
              "该树的结构、先验与图结构通道软链自 products/alldata/graphs/，"
              "只有 CodeBERT 的两个通道被重新计算。作为编码器能力的对照，"
              "另外两档输入树同时保留：products/alldata/graphs/ 是冻结编码器树，"
              "仅用于 cb_frozen 消融臂；products/alldata/graphs_ft/ss{S} 是短预算（5 轮）微调树，"
              "仅用于编码器阶梯的对照档。三档构成编码器能力的阶梯，"
              "只有 20 轮收敛档是主实验所使用的输入。冻结、短预算与收敛三档之间的配对比较"
              "属于跨代对照，其结论记录在 experiments/encoder_promotion_gate.md 中，"
              "不作为同一张消融表内的两行并列。")

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
    ["M5", "pos_weight", "按训练集负/正比设置，上限截断 20；本池实测 access_control 10.3714、arithmetic 8.7073、dos 13.2143、front_running 13.7407、reentrancy 7.1224、time_manipulation 11.4375、uncheck 5.1231，七类均未触及截断上限",
     "config.json::derived.pos_weight"],
    ["M5", "DropEdge", "默认关闭（0.0）；仅消融臂 dropedge02 取 0.2",
     "config.json::args.drop_edge_prob"],
    ["M5", "阈值搜索", "0.20–0.80 步长 0.05，目标验证集 micro-F1，并列取较小阈值；仅用验证集",
     "evaluate.py:9, results.json::threshold_scan"],
    # ---- 编码器（2026-09-24 换代后：20 轮预算为新正典，5 轮下沉为消融档）----
    ["编码器微调（新正典）", "编码器微调（主实验）",
     "20 / 4；早停判据 = 验证集 macro-F1（该头在阶段 2 被丢弃）",
     "runs/codebert_ft_buggy_p2/ss{S}/config.json::args"],
    ["编码器微调（新正典）", "编码器微调（主实验）",
     "2e-5 / 1e-3 / 0.01 / 6", "同上"],
    ["编码器微调（新正典）", "编码器微调（主实验）",
     "对第 16 轮起的权值等权平均，再与最佳单轮 checkpoint 在验证集上比较、取优者。"
     "实测三个划分种子均未选中 SWA：平均窗口开启计数为 0/0/0，最佳轮分别在第 7、11、14 轮，"
     "早停均在第 16 轮之前触发，窗口从未打开。因此本次换代的实际增益来自 epoch 预算，不是 SWA。",
     "同上 ::swa"],
    ["编码器微调（消融档）", "编码器微调（短预算对照档）",
     "epoch 5 / patience 2，仅作编码器阶梯的对照档。该档未在本文主池上运行，"
     "其数值取自编码器阶梯对照实验；该档的输入树 products/alldata/graphs_ft/ss{S} 原地保留，"
     "与冻结档（cb_frozen 臂）、收敛档（20 轮，本文主实验）构成三档阶梯，不另设同名消融臂。",
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
_S473_NOTE = ("IR 指令类别使用冻结字典，共 6 类，跨语料（含 DIVE 与 SolidiFI）统一取自 "
              "products/alldata/graphs/ir_cat.json，版本为 m3-categories-v1。"
              "跨数据集评测必须显式传入 --categories 指向该文件，否则列宽与类别语义会发生漂移。"
              "表中结构特征各段位数之和为 4+14+5+1+6=30，与 config.json 的 derived.D_struct 一致；"
              "模型总参数量为 415226，其中融合层 209472、RGCN 205754。")

_S474_FUNNEL = [
    ["步骤", "合约数", "说明", "出处"],
    ["只读源文件", "591", "alldata(readonly)/alldata_sol_source/ 下的扁平 .sol 数", "raw/filter_report.txt"],
    ["标签索引（项目级）", "590", "按源码 sha1 → 项目标识/地址归并；n_unmatched=0", "config.json::label_source"],
    ["去重 level-1（源码 sha1）", "−48", "同一份源码的副本，保留相对源码路径字典序首个", "split_report.json::dedup"],
    ["去重 level-2（项目标识/地址）", "−45", "同合约的另一份源码，字节可能不同", "split_report.json::dedup"],
    ["训练池", "497", "train/val/test = 398/50/49（三种子规模相同）；含 buggy_*，不做注入噪声剔除",
     "withbuggy_snapshot/split_seed{0,1,2}.json"],
]
_S474_NOTE = ("上表给出数据漏斗的实测取值。MVD-HG 的只读源是 alldata(readonly)/alldata_sol_source/ "
              "下的 591 个扁平 .sol 文件；Slither 解析后得到 590 张异构图，"
              "590 张图合计 95918 个节点、229898 条边。按唯一标识做两级去重后，"
              "得到由 497 个合约构成的训练池：第一级按源码内容 sha1 判重并丢弃 48 个副本，"
              "第二级按项目标识或地址判重并丢弃 45 个同合约的另一份源码（两份文件字节可能不同），"
              "合计丢弃 93 个。三种子均按 8:1:1 划分为 train/val/test = 398/50/49。"
              "训练池保留全部 buggy_* 合约，不做事先的注入噪声剔除。"
              "池的标签构成为：全零（正常）合约 326 个，非全零合约 171 个，其中多标签合约 45 个。"
              "需要如实披露的是，这 45 个多标签合约主要来自 buggy_* 注入族："
              "上游按「每类各放一份」把同一份源码复制进多个类别文件夹，文件夹归属被推成了标签，"
              "因此七类全 1 的合约并不是真实的多标签标注，而是注入假象。这一事实有两个后果。"
              "第一，把 buggy_* 补回池中会系统性抬高 macro-F1 与 mAP，而不代表实际检测能力的提升。"
              "第二，本文的「七维多标签」任务在正样本侧仍然接近单标签，"
              "真正的多标签能力主要由 DIVE 外部测试集体现。为把这一效应量化，"
              "本文在报告该池结果时并列一个 clean_only 诊断列，"
              "即把测试划分中的 buggy_* 合约剔除后再计算一遍，两列之差即为标签假象的贡献量。")

_S474B_HDR = ["划分种子", "train 逐类正样本", "val 逐类正样本", "test 逐类正样本", "覆盖约束 C1/C2"]
_S474B = [
    ["ss0", "35/41/28/27/49/32/65", "12/9/10/10/12/10/15", "9/9/7/6/9/7/14", "全部达标"],
    ["ss1", "38/41/30/29/47/31/65", "10/9/8/7/12/10/15", "8/9/7/7/11/8/14", "全部达标"],
    ["ss2", "37/40/30/28/45/34/65", "11/10/8/9/13/8/15", "8/9/7/6/12/7/14", "全部达标"],
]
_S474B_NOTE = ("列序固定为 access_control / arithmetic / dos / front_running / reentrancy / "
               "time_manipulation / uncheck。池内逐类正样本总数为 56/59/45/43/70/49/94，"
               "逐类负样本数为 441/438/452/454/427/448/403，"
               "对应正负样本比 7.88/7.42/10.04/10.56/6.10/9.14/4.29，三种子相同。"
               "覆盖约束 C1（验证与测试合计的每类正样本不少于该类池内正样本总数的 30%）"
               "与 C2（验证、测试各自每类至少包含一个正样本）在三个划分种子上均由覆盖约束校正"
               "在构造上满足。池内 front_running 与 time_manipulation 的测试侧支撑为 6 至 8，"
               "是七类中最低的两个，单类 F1 仍对单次翻转较敏感，这两个类别仅作描述性呈现、"
               "不进入方法间比较结论；其余各类的支撑均不低于 9，可以进入常规比较。")

_S475_HDR = ["阶段", "seed0", "seed1", "seed2", "口径", "出处"]
_S475 = [
    ["M1+M2 建图（591 源文件 → 590 图）", "未记录", "未记录", "未记录",
     "主构建无计时记录；变体重建 590 图约 68–78 s 可作下界参考",
     "（主构建脚本内无计时代码）"],
    ["M3 重编码（微调编码器，590 图 / 95918 节点）", "597.6 s", "577.8 s", "585.8 s",
     "重编码净耗时（GPU）", "runs/p4_buggy_chain.log（4.2 节）"],
    ["CodeBERT 微调（主实验，20 轮预算）", "1741.3 s", "2209.1 s", "2705.0 s",
     "wall（GPU，早停于 ep7/ep11/ep14）", "runs/codebert_ft_buggy_p2/ss{S}/config.json::timing.wall_seconds"],
    ["CodeBERT 微调（短预算对照档，5 轮）", "933.5 s", "931.2 s", "680.9 s",
     "该档未在主池上运行，数值取自编码器阶梯对照实验，仅作成本量级参考",
     "runs/codebert_ft/alldata/ss{S}/config.json::timing"],
    ["GNN 训练循环", "7.7 s", "9.0 s", "7.6 s", "train_seconds", "runs/buggy_canon/seed{S}/config.json::timing"],
    ["GNN 端到端 wall", "11.7 s", "13.2 s", "12.6 s", "含验证推理与阈值搜索", "同上"],
    ["GNN 实际训练轮数", "15", "25", "16", "epochs_completed", "同上"],
    ["端到端合计（单种子，从零）", "≈2351 s", "≈2800 s", "≈3303 s",
     "= M3 重编码 + 编码器微调（20 轮档） + GNN wall（M1/M2 未计）", "上表逐行相加"],
]
# 🔴 2026-10-01 池口径切换后：`_S475_NOTE`（终态）已随 docx 改写为**池 497 / 主实验
#    `runs/buggy_canon/seed{S}`** 口径（成本表 GNN 段与编码器微调段均取自主实验产物）。
#    `_S475_NOTE_V2` 是上一代（`runs/seed{S}` 正典）的文本，仅作历史编辑的 `old`/`new` 保留。
_S475_NOTE_V2 = '🔴 **成本结构是本研究点最该被如实记录的一条**：编码器微调 + M3 重编码这两段**一次性上游成本合计约 2500–2900 s**，是 GNN 训练段（~8 s）的 **约 300 倍**。故「本文方法训练很快」**只对 GNN 段成立**；论文若要报端到端成本，必须把上游两段计入（本表末行已给出合计）。⚠ **三点必须随表披露**：① 编码器从 5 轮档换到 20 轮档，**上游成本随之由 ~850 s 涨到 ~2000 s**（约 2.3 倍）——这是换取代价，须与 §4.7.5 之后的增益一并报告；② M1/M2 的**主构建**（`generate_all_ast_cfg_dfg.sh`，591 源文件）在本仓**没有任何机器可读的计时记录**（脚本内无计时代码、日志目录无该步日志），表中所给仅为**变体重建** 590 图的近似下界，不得当作主构建耗时引用；③ 本表 GNN 段用的是**现行正典** `runs/seed{S}`（从零训练、`--deterministic`）—— 该产物原先落在 `runs/p2_canon/seed{S}`，2026-09-25 换代时**就位到正典路径**，`config.json` 与产物**逐字节未动**；而**消融档那一行**的计时出自**旧正典**，其产物是**由 `runs/cbft_study/cbft_ts{S}_ss{S}/seed{S}` 提升而来**（见其 `promoted_from` 字段），**不代表从零跑一遍的耗时**；旧正典的 run 现归档于 `runs/prior_canon37/seed{S}/`。另：5.3 对比表中三条基线的表内成本同样只含其模型训练段、离线特征工程另计，两侧口径一致（均为「模型训练」）。'
_S475_NOTE = ("成本结构是本研究点最需要如实记录的一条。在本文主实验的输入档下，"
              "编码器微调与 M3 重编码这两段一次性上游成本合计约 2300 至 3300 秒，"
              "而 GNN 训练段本身的端到端墙钟只有约 12 秒，两者相差约 200 倍。"
              "因此「本文方法训练很快」只对 GNN 段成立；论文若要报告端到端成本，"
              "必须把上游两段一并计入，表中末行已给出合计。随表需要披露三点。"
              "第一，编码器从短预算档换到 20 轮收敛档之后，上游成本由约 850 秒上升到约 2000 秒，"
              "约 2.3 倍，这是换取代价，须与该档带来的增益一并报告。"
              "第二，M1 与 M2 的主构建步骤（generate_all_ast_cfg_dfg.sh，591 个源文件）"
              "在本仓库没有任何机器可读的计时记录，脚本内没有计时代码、日志目录也没有该步日志，"
              "表中所给仅为变体重建 590 张图的近似下界，不得当作主构建耗时引用。"
              "第三，GNN 段取自主实验产物 runs/buggy_canon/seed{S}，三个种子均为从零训练，"
              "config.json 的 promoted_from 为空。三条论文基线的表内成本同样只包含各自的模型训练段，"
              "离线特征工程另计，两侧口径一致。")
_S475B_HDR = ["阶段", "步骤", "实测 wall（串行）", "说明"]
_S475B = [
    ["① 主库（阶段 3）", "3.1 结构变体树 `canon_p2`（6 棵）", "3 min 49 s",
     "边变体只重建 `_pyg.pt`/`_hetero.json`、复用 `_cb.pt`，因此远快于原先估算的 1.1 h"],
    ["", "3.2 `run_cbft_study`（18 run）", "7 min 10 s", "n=9 配对基线"],
    ["", "3.3 `run_ablation`（63 run，n=3）", "23 min 40 s", "21 臂 × 3 种子"],
    ["", "3.4 `run_ablation_n9`（216 run：153 + 63）", "1 h 15 min 13 s",
     "= 首跑 58 min + 补跑 17 min 13 s；首跑不是白跑（见注②）"],
    ["", "3.5 GCN 对照臂（3 run）", "50 s", "逐类 F1 表的输入"],
    ["", "3.6 逐类独立二分类臂（45 run）", "9 min 14 s", "7 类 × 2 配置 × 3 种子"],
    ["", "3.7 跨种子聚合 + 3.9 `ANY_union` 重放（3 run）", "5 s + 44 s", ""],
    ["", "3.8 DIVE/SolidiFI 输入侧重编码", "2 h 18 min 33 s",
     "① 3 棵树 + 12 棵变体树；本阶段最长一项（见注③）"],
    ["", "① 小计", "4 h 29 min 47 s", "09:35:15 → 14:05:02"],
    ["任务 2（阶段 4）", "4.1 编码器微调 ×3（20 轮预算）", "2 h 01 min 39 s",
     "逐种子 31 min 53 s / 40 min 25 s / 49 min 21 s（早停于 ep11/15/14）"],
    ["", "4.2 M3 重编码（590 图 × 3）", "32 min 05 s", ""],
    ["", "4.3 结构变体树 `buggy_p2`（6 棵）", "3 min 31 s", ""],
    ["", "4.4 正典 GNN（train/eval/diagnose/summarize）", "1 min 12 s", ""],
    ["", "4.5 消融（63 run，n=3）", "19 min 35 s", "池 497 侧"],
    ["", "4.6 架构族（9 run）", "2 min 03 s", ""],
    ["", "4.7 三条论文基线（MVD-HG/EGFL/MANDO）", "0（裁定不重跑）",
     "实测三者均不读 `_cb.pt`（MVD-HG/EGFL 自建 AST/反汇编；MANDO 只读结构通道；Slither 只吃源码）"],
    ["", "任务 2 小计", "3 h 00 min 05 s", "14:05:03 → 17:05:08"],
    ["合计", "本次换代总成本", "7 h 29 min 52 s", "① + 任务 2，串行；M1/M2 建图未重跑"],
]
_S475B_NOTE = ("下表与上一张成本表的计算口径不同，两者不可相加。"
               "上一张表回答的是从零训练一个模型需要多少时间，"
               "本表回答的是在已经拥有一整套主实验产物的前提下，"
               "把整条链路整体换到新的编码器档需要多少重跑时间，"
               "它既包含上游重建（编码器微调与 M3 重编码），也包含下游全部对照臂的重跑。"
               "三点须随表披露。第一，表中数值全部为单卡串行墙钟"
               "（RTX 4070 Laptop，GPU 独占），未做任何并行。"
               "第二，3.4 一项的 1 小时 15 分钟里，首跑 58 分钟产出了 162 个 run，"
               "只在 conv_gat 一步因 scatter_reduce_cuda 缺少确定性实现而中止；"
               "把 gat 排除在 --deterministic 之外后补跑 54 个 run 用了 17 分 13 秒，"
               "因此净浪费约为零计算量，代价是串行阻塞。"
               "第三，3.8 一项占 ① 侧 4 小时 30 分钟的一半以上（2 小时 18 分 33 秒），"
               "而它只重编码 DIVE 与 SolidiFI 的特征、按既定裁定不产出新的交付数字；"
               "若只统计产出交付表所必需的部分，① 侧净成本约为 2 小时 11 分钟。")

_S476 = [
    ["口径项", "设定"],
    ["主指标", "micro-F1（标签对级），两工作点并列报告：固定 0.5 与验证集阈值"],
    ["参考指标", "macro-F1（7 类未加权平均）、逐类 P/R/F1、per-class PR-AUC、mAP（阈值无关）"],
    ["阈值", "0.20–0.80 步长 0.05，目标验证集 micro-F1，并列取小；只在验证集搜，测试集不参与"],
    ["随机种子", "数据划分种子与训练种子分离，各 3 个（0/1/2）；主种子 seed0，最佳种子口径另见 5.1"],
    ["平凡下限", "七维 micro 0.1778（49 个测试合约 × 7 类 = 343 个标签格中 61 个为正）；合约级二分类 0.6553（49 个测试合约中约 32 个含至少一类漏洞）"],
    ["区间估计", "测试划分仅 49 个合约、61 个正标签对，micro-F1 的区间估计较宽，因此不得用 micro-F1 的小数位差异下方法优劣结论"],
]
_S476_NOTE = ("七维多标签口径与合约级二分类口径的平凡下限相差 0.50，两者的数字不可互相比较。"
              "诊断性补充口径（clean_only、温度缩放、逐类阈值、多种子集成）一律不进入主结果，"
              "其定义与限制见 experiments/decisions.md。")

_S477 = [
    ["对照臂族", "规模", "用途"],
    ["消融臂（必要+可选）", "21 臂：n=3 对角（63 run）与 n=9 同配对复核（126 run）；判「有效/无效」以 n=9 为准",
     "逐模块验证：边、通道、池化、L_var、先验 Dropout、特征分组、层数/宽度/基分解、DropEdge、冻结编码器"],
    ["架构基线族", "GCN / GAT / SAGE × 3 种子 + 参数量匹配对照",
     "关系感知 vs 关系盲的内部证据（不是 5.3 的对比方法）"],
    ["逐类独立二分类臂", "7 类 × 2 配置 × 3 种子", "回答「多标签共享是否压制了稀有类」"],
    ["二分类头臂", "--head binary，3 种子", "单变量消融：只换输出空间（7→1）"],
    ["论文基线（5.3 对比方法）", "MVD-HG / EGFL / MANDO-LLM × 3 种子", "三条论文基线的重实现"],
    ["传统工具（5.3 对比方法）", "Securify / Mythril / Slither / Manticore / SmartCheck / Oyente", "不训练；Slither 走主环境，其余五个各在独立 conda env"],
]


# --- §4.7.8 本池主实验结果（2026-10-01 新增：池 497 主实验交付读数，逐段抄自 docx）---
_S478 = [
    "本文主实验在该训练池上的结果如下。三个种子平均，七维多标签口径的 micro-F1 在固定阈值 0.5 下"
    "为 0.9378±0.0666，在验证集阈值下为 0.9413±0.0337；macro-F1 为 0.9322±0.0736；"
    "mAP 为 0.9702±0.0204。合约级二分类口径在验证集阈值下的 F1 为 0.9071±0.0442，"
    "扣掉全报「有漏洞」的平凡下限 0.6553 后净技能为 +0.2518；"
    "逐类二分类 F1 的平均值为 0.9259±0.0482。",

    "由于上述数字有一部分来自注入标签假象，本文同时报告 clean_only 诊断列："
    "把测试划分中的 buggy_* 合约剔除后，七维口径的 micro-F1 降为 0.8226，"
    "macro-F1 降为 0.4915，mAP 降为 0.7554。micro 的降幅约 0.12，是标签假象贡献的干净读数；"
    "macro 的降幅约 0.45，其中还混入了稀有类正样本被抽走的度量副作用"
    "（剔除后 time_manipulation 在测试划分中不再有正样本），"
    "不能读作「补回 buggy_* 使 macro-F1 提升了这么多」。",

    "三条论文基线与六个传统工具在同一划分上按相同协议评估。"
    "MVD-HG 忠实复现的七维 micro-F1@验证集阈值为 0.8699±0.0780，mAP 为 0.9113±0.0476；"
    "EGFL 按论文重实现为 0.3721±0.0291；MANDO-LLM 按论文重实现为 0.3168±0.0065。"
    "六个传统工具不训练、没有阈值可搜，只有固定 0.5 一个工作点，"
    "其 micro-F1 分别为 Slither 0.4016±0.0786、Securify 0.3951±0.0104、"
    "Mythril 0.3728±0.0683、Oyente 0.3709±0.0925、SmartCheck 0.3476±0.0278、"
    "Manticore 0.1080±0.0344；它们的分母只包含成功分析的合约，"
    "与本文方法的差异见 §5.3 的口径声明，跨行比较须谨慎。",

    "传统工具的可分析覆盖率在该池上差异很大：49 个测试合约中，Slither 可分析 46 个、"
    "SmartCheck 49 个、Mythril 41 个、Manticore 39 个，而 Securify 只有 12 个、Oyente 只有 8 个。"
    "覆盖率低的工具其分母更小，据此得到的 F1 不能与本文方法的全量分母直接比较。",

    "最后需要强调的是，本池的测试划分只有 49 个合约、61 个正标签对，"
    "micro-F1 的区间估计较宽，因此不得用小数位差异下方法优劣结论；"
    "support 不大于 2 的类别仅作描述性呈现，不进入方法间比较结论。",
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
    B.append(("para", "逐种子、逐类的正样本数如下表（列序同标签顺序）：", NRM))
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

    B.append(("para", "4.7.8  本池主实验结果（实测）", H2))
    for p in _S478:
        B.append(("para", p, NRM))
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
     "(3)报告模型在DIVE全零标签（正常合约）子集上的每类假阳性率，并结合“训练池实为 323/448 个全零（正常）合约、"
     "但其来源与 DIVE 正常合约分布不同”这一口径讨论其对结果的影响；",
     "（3）报告模型在DIVE全零标签（正常合约）子集上的每类假阳性率，"
     "并结合训练池的正常合约构成讨论其对结果的影响：本池 497 个合约中有 326 个全零（正常）合约，"
     "但其来源与 DIVE 的正常合约分布不同；"),
    ("replace", "body:213",
     "第四，MVD-HG数据集规模有限（去重后591个源文件 / 448 个训练池样本，且训练池实为 323 个全零（正常）合约、"
     "其来源与 DIVE 正常合约分布不同）；模型在DIVE正常合约子集上可能偏向预测为正；同时，"
     "MVD-HG与DIVE在标注口径与类别先验分布上存在差异，外部测试性能下降不能全部归因于模型泛化能力，"
     "跨数据集结论须注明适用边界。",
     "第四，MVD-HG数据集规模有限：只读源为 591 个源文件，经项目级归并得到 590 张异构图，"
     "两级去重后构成的训练池为 497 个合约，其中全零（正常）合约 326 个、多标签合约 45 个且主要来自注入族，"
     "其来源与 DIVE 正常合约分布不同；模型在DIVE正常合约子集上可能偏向预测为正；同时，"
     "MVD-HG与DIVE在标注口径与类别先验分布上存在差异，外部测试性能下降不能全部归因于模型泛化能力，"
     "跨数据集结论须注明适用边界。"),
    # 依据：runs/seed0/config.json::args.drop_edge_prob = 0.0（默认关闭）
    # ⚠ 必须用 `replace_in_table`：`old="0.1"` 是短串，全文另有 5 处命中，
    #    按段落定位会因「不唯一」直接报错（本脚本实测）。`needle` 取该表首列独有的文本。
    ("replace_in_table", "消息传递层数L", "0.1", "0（默认关闭；仅消融臂 dropedge02 取 0.2）"),
    # 依据：split_report.json（590 项目级索引 → 453 池）与 alldata(readonly) 实际布局
    # ⚠ 锚点用**文字前缀**而非 `T13:r1:c2:p1`：本脚本自己会往 §4.7 插表，
    #    插完 `T13` 会变成 `T21`，用地址的锚点在重跑时解析不出来。
    # ⚠ 原为 `insert`（向 §5.1 表 22 的合约级标注格追加一段）。docx 已把该格**合并为一段**并改写为
    #    池 497 口径 ⇒ 本改成 `replace`：`old` = 上一版该段原文（含 `**` 强调），`new` = docx 现文。
    ("replace", "数据按七类漏洞文件夹组织，原始记录共3482条",
     "上述 2002 为**合约名级**条目数。构建图时按项目前缀（`__` 前第一段，剥去 `asd_`/`nasd_`）"
     "归并为 **590 个唯一项目级合约**；再剔除 `buggy_*` 注入噪声（90）与源码重复（47）后，"
     "构成**训练池 453**（train/val/test = 362/45/46），其中全零（正常）合约 326 个。"
     "三份只读源现为 `alldata(readonly)/alldata_sol_source/` 下**扁平 591 个 `.sol`**"
     "（原始七类文件夹组织在导入时已摊平；上表的类别记录数 3482 = 474+514+406+398+543+444+703 "
     "为该阶段的统计）。详见 §4.7.4。",
     "七类漏洞合约级标注。数据按七类漏洞文件夹组织，原始记录共 3482 条，"
     "去重后唯一合约名数为 2002 个（等于主标签文件条目数，其中正标签条目 257 个、"
     "多标签 123 个、全零 1745 个）。各类别原始记录数为：access_control 474、arithmetic 514、"
     "dos 406、front_running 398、reentrancy 543、time_manipulation 444、uncheck 703。"
     "上述 2002 为合约名级条目数；构建图时按项目前缀（__ 前第一段，剥去 asd_/nasd_）"
     "归并为 590 个唯一项目级合约，两级去重后构成训练池 497（train/val/test = 398/50/49），"
     "其中全零（正常）合约 326 个、多标签合约 45 个。训练池保留全部 buggy_* 合约；"
     "该族合约的文件夹归属会被上游推成七类全 1 的标签，属注入假象，"
     "本文在报告结果时并列 clean_only 诊断列以量化其影响。"
     "三份只读源现为 alldata(readonly)/alldata_sol_source/ 下扁平 591 个 .sol"
     "（原始七类文件夹组织在导入时已摊平；上表类别记录数 3482 = 474+514+406+398+543+444+703 "
     "为该阶段的统计）。详见 §4.7.4。"),

    # ---- 二、编码器换代（2026-09-24 闸门通过，用户裁定：「确实上升就提升为正典，
    #          旧的作为消融实验，并同步修改大纲设计」）----
    # 依据：experiments/encoder_promotion_gate.md（G1/G2/G3 三门全过）；
    #      runs/codebert_ft_p2/ss{S}/config.json（epochs=20/patience=4/swa_start=16、swa 实测）
    ("replace", "body:72",
     "CodeBERT在本文主方案中默认参与微调：仅使用训练划分的合约级标签微调编码器，"
     "再以微调后的编码器重编码全图特征，供RGCN阶段训练使用。冻结编码器作为消融对照保留。",
     "CodeBERT在本文主方案中默认参与微调：仅使用训练划分的合约级标签微调编码器，"
     "再以微调后的编码器重编码全图特征，供RGCN阶段训练使用。编码器微调至收敛，epoch 预算 20，"
     "按验证集 macro-F1 早停（patience=4），并配置后缀权值平均（SWA，--swa-start 16）作为选点对照。"
     "冻结编码器与短预算微调（5 轮）共同作为消融对照保留，"
     "在消融实验中形成「冻结 / 短预算（5 轮）/ 收敛（20 轮）」三档阶梯。"
     "实测三个划分种子的编码器自身验证集 macro-F1：收敛档为 0.9544、0.6747、0.7165，"
     "短预算档为 0.5258、0.6067、0.4365，三档逐种子单调提升；"
     "下游 GNN 的配对比较（mAP +0.1369、macro-F1@验证集阈值 +0.1923，3/3 种子不劣）"
     "见 §4.7.5 与 experiments/encoder_promotion_gate.md。"),
    ("replace", "body:75",
     "（3）微调与编码均在离线阶段完成，微调后的嵌入同样可离线缓存，RGCN训练阶段仍只需加载缓存向量，"
     "故可复现性与冻结方案一致。需要说明的是，微调只使用训练划分的标签，属任务特定表征学习，"
     "不接触验证与测试划分的任何信息；消融实验中报告“冻结CodeBERT”与“微调CodeBERT”在验证集macro-F1上的差异。",
     "（3）微调与编码均在离线阶段完成，微调后的嵌入同样可离线缓存，RGCN训练阶段仍只需加载缓存向量，"
     "故可复现性与冻结方案一致。需要说明的是，微调只使用训练划分的标签，属任务特定表征学习，"
     "不接触验证与测试划分的任何信息。消融实验按三档阶梯报告CodeBERT处理方式的差异："
     "冻结（不执行本阶段）、短预算微调（epoch 预算 5、patience 2）与收敛微调"
     "（epoch 预算 20、patience 4，本文主方案），比较各自在验证集macro-F1上的表现及对下游GNN的影响。"),
    ("replace", "body:146",
     "编码器微调阶段单独设置超参数，与上述RGCN训练阶段相互独立：在训练划分的合约级七维标签上微调CodeBERT，"
     "训练5个epoch，编码器学习率2e-5，分类头学习率1e-3，权重衰减0.01，序列批大小6，"
     "并按验证集macro-F1早停（patience=2）。该阶段只使用训练划分的标签，验证与测试划分不参与；"
     "冻结编码器的对照设置除不执行本阶段外，其余超参数完全相同。",
     "编码器微调阶段单独设置超参数，与上述RGCN训练阶段相互独立。"
     "在训练划分的合约级七维标签上微调CodeBERT，epoch 预算为 20，"
     "按验证集 macro-F1 早停（patience=4），编码器学习率2e-5，分类头学习率1e-3，"
     "权重衰减0.01，序列批大小6。此外配置后缀权值平均（SWA）作为选点对照："
     "对第 16 轮起的权值取等权平均，再与最佳单轮 checkpoint 在验证集上比较、取优者。"
     "三个划分种子的实测结果是 SWA 一次都没有被选中，三种子的平均窗口开启计数均为 0，"
     "最佳轮分别出现在第 7、11、14 轮，早停均在第 16 轮之前触发，平均窗口从未打开。"
     "因此本次编码器换代的增益来自 epoch 预算由 5 提高到 20，而不是 SWA，"
     "SWA 在本配置下属于已实现、已运行、无增益，如实报告。该阶段只使用训练划分的标签，"
     "验证与测试划分不参与。消融对照共两档，除本阶段的执行方式外其余超参数完全相同："
     "其一为冻结编码器，不执行本阶段；其二为短预算微调，epoch 预算 5、patience 2。"),
    # ⚠ needle 必须**唯一**指向目标表：`"消融变体"` 在 T15（必要消融）与 T16（可选消融）里都有，
    #    用它会让 `find_table` 因「命中 2 张表」直接报错 ⇒ 改用只在该行出现的文本。
    ("replace_in_table", "冻结CodeBERT vs 微调CodeBERT",
     "冻结CodeBERT vs 微调CodeBERT",
     "CodeBERT 三档阶梯（冻结 / 短预算微调 5 轮 / 收敛微调 20 轮）"),
    ("replace_in_table", "冻结CodeBERT相对微调CodeBERT在验证集macro-F1上的损失",
     "冻结CodeBERT相对微调CodeBERT在验证集macro-F1上的损失",
     "各档在验证集 macro-F1 上的差异及对下游 GNN 的影响；本文主方案为收敛档。"
     "编码器侧实测三种子：收敛档 0.9544/0.6747/0.7165，短预算档 0.5258/0.6067/0.4365"),

    # ---- 四之二、2026-09-25 口径修正（用户裁定 **(A) 改口径、零重跑**）----
    # 🔴 `cb_ft5` 是一个**只存在于文档里的臂名**。三条实测证据：
    #    ① `git --no-pager log -S "cb_ft5" -- scripts/` **为空**（脚本里从未出现）；
    #    ② `runs/ablation` 的 21 个臂里**没有**它（编码器臂只有 `cb_frozen`）；
    #    ③ 中档（5 轮）的**真实产物是归档的旧正典** `runs/prior_canon37/seed{S}`
    #       （其 `config.json::args.graph_dir = …/graphs_ft/ss{S}`，三种子逐条实测）。
    #    裁定 (A) = **改口径、不造臂**（造臂会打破「21 臂」的硬引用与多张表的行数、`n/21` 断言）。
    ("replace_in_table", "scripts/m1_runner.py",
     "products/alldata/graphs_ft/ss{S}/ —— 消融臂 `cb_ft5` 的输入",
     "products/alldata/graphs_ft/ss{S}：编码器阶梯的短预算（5 轮）对照档；"
     "其 GNN run 归档于 runs/prior_canon37/seed{S}"),
    ("replace_in_table", "短预算配置",
     "作为**消融臂 `cb_ft5`** 的输入，与「冻结」（`cb_frozen`）「收敛」（20 轮，现行正典）构成三档阶梯",
     "epoch 5 / patience 2，仅作编码器阶梯的对照档。该档未在本文主池上运行，"
     "其数值取自编码器阶梯对照实验；该档的输入树 products/alldata/graphs_ft/ss{S} 原地保留，"
     "与冻结档（cb_frozen 臂）、收敛档（20 轮，本文主实验）构成三档阶梯，不另设同名消融臂。"),
    # 脚注段落 `_S471_NOTE`：`V2 → 终态`（与上面那条 `"superseded"` 成对，见其注释）
    ("replace", "_S471_NOTE", _S471_NOTE_V2, _S471_NOTE),

    # ---- 四之三、用户裁定「补齐第 3、4 项」：n=9 判据口径 + L_var 剂量臂 ----
    # 第 3 项（n=9）依据：本仓既有规矩「判「有效/无效」须同配对 ≥9 点」——
    #   原话在 `experiments/ablation_three_metric_table.md` 与 `decisions.md` §26.7/§27.5，
    #   而大纲 §5.2 此前只写「至少 3 个随机种子」⇒ **设计没记全**。
    #   产物：`runs/ablation_n9/`（153 run）、`runs/arch_n9/`（63 run）；
    #   报告：`experiments/ablation_n9_results.md`（逐配对 Δ + 配对 t）。
    ("replace", "§5.2 随机种子",
     "层次一：真实合约上的合约级多标签漏洞分类评估。该层次包含两种设定：同分布测试（MVD-HG内部测试划分）"
     "与跨数据集外部测试（DIVE外部测试集，构建方式见5.1），评估模型是否能同时识别合约是否包含七类漏洞中的每一类。"
     "5.3全部对比方法均在两种设定下评估。评估指标以micro-F1（标签对级）为主指标；macro-F1为参考指标，"
     "报告时须注明其支撑构成；每类Precision、每类Recall、每类F1与per-class PR-AUC均须与该划分的support"
     "同时给出，support≤2的类别仅作描述性呈现、不进入方法间比较结论；另报告mAP或macroPR-AUC；"
     "可选报告subset accuracy。类别阈值搜索范围默认为0.2到0.8，步长为0.05，搜索目标为验证集micro-F1。"
     "阈值选择只使用验证集，不使用测试集。为避免阈值选择过程不透明，论文中需同时报告固定阈值0.5下的结果"
     "和验证集选择阈值下的结果。所有主实验至少运行3个随机种子，并报告均值与标准差。",
     "层次一：真实合约上的合约级多标签漏洞分类评估。该层次包含两种设定：同分布测试（MVD-HG内部测试划分）"
     "与跨数据集外部测试（DIVE外部测试集，构建方式见5.1），评估模型是否能同时识别合约是否包含七类漏洞中的每一类。"
     "5.3全部对比方法均在两种设定下评估。评估指标以micro-F1（标签对级）为主指标；macro-F1为参考指标，"
     "报告时须注明其支撑构成；每类Precision、每类Recall、每类F1与per-class PR-AUC均须与该划分的support"
     "同时给出，support不大于2的类别仅作描述性呈现、不进入方法间比较结论；另报告mAP或macro PR-AUC；"
     "可选报告subset accuracy。类别阈值搜索范围默认为0.2到0.8，步长为0.05，搜索目标为验证集micro-F1。"
     "阈值选择只使用验证集，不使用测试集。为避免阈值选择过程不透明，论文中需同时报告固定阈值0.5下的结果"
     "和验证集选择阈值下的结果。所有主实验至少运行 3 个随机种子，并报告均值与标准差。"
     "凡要对某项干预下「有效」或「无效」的结论，须使用同配对不少于 9 个点：配对点由训练种子与划分种子的"
     "全交叉 3×3 构成，只沿对角取 3 个点即 n=3，仅作描述性读数、不作结论。本研究的 21 臂消融与架构基线族"
     "（GCN、GAT、SAGE 及参数量匹配对照）均已按 n=9 同配对复核，逐配对差值与配对 t 检验见 "
     "experiments/ablation_n9_results.md。n=3 与 n=9 的结果并存，n=3 的价值在于对照哪些结论在 n=9 下发生翻转。"),
    # ⚠ 本条必须带 **`"exact"`**：`old`（`21 臂 × 3 种子`）会被新文本包含 ⇒ 子串匹配在复跑时
    #   会**再替换一遍**、把整格文字叠加成两遍（2026-09-25 实测发生并已回滚）。
    #   同时**新文本里不能出现 `old` 原文**——否则 `--verify` 的「含新文本的段里旧文本仍在」判据
    #   会把已落盘的正常状态误报成「半改状态」（实测 20/21）。
    ("replace_in_table", "对照臂族",
     "21 臂 × 3 种子",
     "21 臂：n=3 对角（63 run）与 n=9 同配对复核（126 run）；判「有效/无效」以 n=9 为准",
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
     "runs/codebert_ft_buggy_p2/ss{S}/encoder/（HF 格式目录）"),
    # ⚠ 这一格必须用 **`"exact"`**：`…/encoder` 是另两格的前缀（`…/encoder/（HF…）` 与
    #   本批 `table_row_after` 新插的「消融档」行里的 `…/encoder（原地保留，未删）`）
    #   ⇒ 子串匹配会在重跑时改错格且不报错（2026-09-25 干跑时发现）。
    #   ⚠ 2026-10-01：docx 里该格（消融档的编码器树）仍指向 `runs/codebert_ft/alldata/ss{S}`（5 轮档，
    #     本就不该换成主实验树）⇒ 本条 `new` 对齐到 docx 现文；`old` 已不在 docx，命中 0 段即跳过。
    ("replace_in_table", "scripts/m1_runner.py",
     "runs/codebert_ft/alldata/ss{S}/encoder（**原地保留，未删**）",
     "runs/codebert_ft/alldata/ss{S}/encoder（原地保留，未删）", "exact"),
    ("replace_in_table", "scripts/m1_runner.py",
     "products/alldata/graphs_ft/ss{S}/（_hetero/_m1/_pyg 软链自 graphs/，只重算 _cb.pt）",
     "products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S}/（_hetero/_m1/_pyg 软链自 graphs/，只重算 _cb.pt）"),
    ("replace_in_table", "scripts/m1_runner.py",
     "products/alldata/graphs_ft/ss{S} + products/alldata/splits/split_seed{S}.json",
     "products/alldata/graphs_ft_buggy_p2/cb_ft_ss{S} + "
     "products/alldata/splits/withbuggy_snapshot/split_seed{S}.json"),
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
     "epoch 5 / patience 2，仅作编码器阶梯的对照档。该档未在本文主池上运行，"
     "其数值取自编码器阶梯对照实验；该档的输入树 products/alldata/graphs_ft/ss{S} 原地保留，"
     "与冻结档（cb_frozen 臂）、收敛档（20 轮，本文主实验）构成三档阶梯，不另设同名消融臂。"),
    # 表 #18（成本表）GNN 段的出处：2026-10-01 池切换后就位到主实验产物 `runs/buggy_canon/seed{S}`
    ("replace_in_table", "GNN 训练循环",
     "runs/p2_canon/seed{S}/config.json::timing",
     "runs/buggy_canon/seed{S}/config.json::timing"),
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
     "该档未在主池上运行，数值取自编码器阶梯对照实验，仅作成本量级参考"),

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
