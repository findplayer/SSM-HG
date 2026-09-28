开发手册log：
> - 2026-09-12 目录重构（方案 B）：数据集产物统一迁入 `products/<数据集>/`（`products/alldata/`、`products/dive/`、`products/solidifi/`）；训练/评估产物仍在 `runs/`、`eval_results/`。详见 `项目组织架构.md`。
> 当前真实状态（2026-09-05 第三轮审查修复后全量重跑，两次运行结果完全一致）：`products/alldata/raw/` 已按第 5 章从 `alldata(readonly)` 全量生成（581/591 合约：AST 581、CFG dot 24672 + cfgdetail 581、DFG 581；过滤 1 个 >50 行 assembly、9 个 delegatecall 动态绑定——**该 9 个已于 2026-09-14 恢复**（规则改为仅记账），现行 590/591，见 `experiments/decisions.md` §18；1 个合约（TownCrier）因 Slither 0.11.5 对 0.4.12+ AST 常量折叠崩溃自动回退 0.4.19 解析，`filter_report.txt` 记录 `cfg_retried_lower_version=1`；solc 版本选择已改为降序取最高满足版本，AST 版本分布 0.4.26×213 / 0.5.17×209 / 0.4.24×84 等，cfgdetail 节点行号缺失为 0）；`products/alldata/graphs/` 已生成 581 个 `_hetero.json`（93551 节点；CFG_FLOW 71296 / AST_PARENT 1957 / AST_PARENT_SAME 6035 / DFG_DEP 146679 / CALLBACK_RISK 6328（**以上为 2026-09-05 口径**；现行数字见 §7.7 表：CALLBACK_RISK **511/86**、DFG_DEP **146712**）；DFG 状态变量合同级索引 + 定义∪使用两级匹配，2026-09-05 起 token 键补充成员名回退（self.credit→credit）使 DFG_DEP 146242→146679；CALLBACK_RISK 状态写判定改写入方向正则（`-> balances` 读取不再误判，mapping 关键字分支删除），6171→5914（163→141 图）→2026-09-07 6328（172 图，见第五轮修复）；零 DFG 边图 72→12）、581 个 `_pyg.pt` 与 581 个 `_m1.json`（93551 节点中 21567 个节点命中七类规则：reentrancy 1629 / front_running 11004 / access_control 3774 / time_manipulation 832 / uncheck_return 536 / dos 199 / arithmetic 9290；命中图数 reentrancy 263 / front_running 525 / access_control 174 / time_manipulation 134 / uncheck_return 99 / dos 73 / arithmetic 468）。2026-09-06 M1 第六轮修复：uncheck_return 的 bool 消费判定按 Slither 0.11.5 签名形态 `require(bool)(var)` 修复（见 6.3 与第 12 节第 38 条），540→536 节点、103→99 图（DAO/reentrancy 4 图 4 个误报清除），总命中 21568→21567，其余六类零变动。2026-09-04 已按七类漏洞触发方式对 M1 规则做第二轮审查并修正（见 6.3：重入改 CEI 判据＋跨函数、算术放开 pre-0.8、访问控制改 tx.origin/selfdestruct/非 msg.sender 收款方、uncheck 补内联消费、dos 补无界循环/push/send 三类锚点、front_running 排除纯字面量与大小写敏感匹配），并用 `alldata(readonly)/contract_labels.json` 做图级召回审计：真实合约（非 buggy_X 注入样本）上 reentrancy/dos/time_manipulation/uncheck_return 漏检图为 0。2026-09-05 第三轮审查修复：dos 锚点①限定循环条件节点 IFLOOP（排除 STARTLOOP/ENDLOOP init/step 误判）；M1 单命中图归一化修复（全 0 保持 0、单非零值置 1，旧实现整体清零丢失唯一信号）；`_m1.json` meta.exclusive_priority 改为记录真实仲裁顺序 EXCLUSIVE_RULE_PRIORITY；batch_summary 新增 total_class_hits/class_hit_graphs；dump_cfg 行号区间展开与 receive/fallback 显式命名；构图脚本 find_source_file 多候选告警、parse_dfg 噪声行计数 dfg_non_table_lines；sh 脚本支持 ~ pragma 并新增 pragma_missing/no_version 计数；同日两处口径修复：dfg_non_table_lines 排除表边框分隔线（只计 solc 命令日志等真噪声行）、front_running 排除 address(0) 常量写入（front_running 11313→11004）；另做召回增强：dos 锚点②扩展动态数组 length 自增模式（`array.length += 1`/`++`/`= array.length + 1`，与 `.push()` 共用循环祖先+状态数组判定，dos 198→199）。2026-09-05 第四轮修复：CALLBACK_RISK 状态写判定改 SlithIR 写入方向正则（排除 `-> balances` 读取误判，CALLBACK_RISK 6171→5914）；parse_dfg 删除不可达死代码；main 简化冗余跳过条件；cfgdetail 行号回填不共享跨函数缓存（缓存键冲突隐患）；补 walk_ast/normalize_function_name/parse_cfg_filename/node_is_state_write/node_has_transfer_or_balance 五个 docstring；核对 dump_cfg `sons[0]=true` 分支约定（7.4.3）；60 个新样本批量审计（图结构/m1 结构 0 问题、标签匹配 581 图全覆盖、非 buggy 真实合约召回 100%，漏检全部集中在 buggy_* 噪声项目）；补 m1_runner 7 个函数与 priori_scoring.from_json_file 的 docstring。M1/M2 已完成代码审查、修复并通过全量结构回归；M3、M4、M5 尚未开始。2026-09-05 第五轮定向语义抽样审计（非 buggy 真漏洞图逐节点核对）：EtherBank / Reentrancy_cross_function / IntegerOverflowSingleTransaction 三图命中全部语义正确；FindThisHash（公开 constant 猜谜 + msg.sender.transfer，无 storage 读/写序列）front_running 全 0 漏检，判定为首个非 buggy 召回缺口。经查 front_running 全部语义正样本仅 4 个（EthTxOrderDependenceMinimal / OddsAndEvens / ERC20 命中，FindThisHash 漏），该"constant 猜谜竞态"形态为孤例、无同类集合；为孤例扩规则收益低且易误报，记为已知局限、不改规则（见 6.3 与第 12 节第 37 条）。据此 M1/M2 审计收尾关闭。
> 2026-09-07 M4 已完成（开发计划 v4 落地）：`scripts/model.py`（SSMHG：RGCN/GCN 两层、h2-based Readout、forward→(z,a,node_logits)、批图 batch、helpers）、`tests/test_model_smoke.py`（22 用例全绿）、`docs/M4_interface.md`；simple_dao 真实前向验收通过。要点：Readout 用第二层传播 h2（绝非输入 x）；conv_type 仅 rgcn/gcn（普通 GAT 已删除）；num_bases 默认 5；空边/孤立用 PyG 官方语义；DropEdge/先验 dropout/L_var/日志归属 M5。详见 9.5/9.6。
> 2026-09-07 M1/M2 第五轮审查修复（代码审查，行为改动仅 1 处）：M2 `RE_IR_EXT_CALL` 补 `HIGH_LEVEL_CALL`（旧版漏判：expression 不含 .call/.send/.transfer 但 ir 为 HIGH_LEVEL_CALL 的具名调用——ERC721 `transferFrom`、ERC20 `approve` 等全库 770 节点被 CALLBACK_RISK 与 M1 external_callback(+0.5) 遗漏，与 7.6/大纲 4.2.2 判据不符）。修复后全量重跑（build×2 确定性一致）：CALLBACK_RISK 5914→6328、141→172 图、ext_call_node_count 5954→6717；M1 七类 flags 命中不变（21567），node_scores 因 external_callback +0.5 变化；PyG 重转、M3 全量重算 `_feat.pt`（`_cb.pt` 复用 581/581）；simple_dao 特征 hash 不变；M4 22 用例回归通过。另 2 处小修（无行为影响）：构图脚本 `skipped_no_cfg` 提前 continue 分支补计数；priori_scoring `BFS_MAX_DEPTH` 过时注释修正（大纲无 ≤2，实际调用点均显式传 10）。详见 7.6/12-39。
> **2026-09-11 按 `研究点一细化大纲改II.docx` 复核（本版依据）：** `改II` 相对 `改I` 的设计改动如下，其中**影响既有产物/代码的改动已重新标注为未完成**（详见第 6/7/8/9/10 节与 `Todo_List.md`）：

项目组织架构log：

# 目录重构记录（2026-09-12 方案 B 统一迁移）：顶层 raw/ → products/alldata/raw/、Heterogeneous graphs/ → products/alldata/graphs/、splits/ → products/alldata/splits/（mv 同盘瞬时完成；产物文件名与内容不变，无需重跑）；新建 products/{dive,solidifi}/ 产物区（含 dive/splits、solidifi/mapping 与 .gitkeep）及 runs/、eval_results/{ablation,baseline,dive,solidifi}/；8 个脚本默认路径（6 个 Python + shell 脚本 + dataset.py 常量）、.gitignore、手册/Todo/copilot-instructions 全部同步；迁移验证：compileall + bash -n + pytest（22 passed）+ dataset.py --check simple_dao（9 节点/128 维/28 边）通过；另将 `_m1.json`/`batch_summary.json` 内嵌的旧路径经 `m1_runner --force` 全量刷新（581 文件，`node_flags`/`node_scores`/七类命中与刷新前逐位一致；`_hetero.json`/`_pyg.pt`/`_feat.pt`/`_cb.pt`/`ir_cat.json` 无内嵌路径、无需处理）。旧顶层目录名（raw/、Heterogeneous graphs/、splits/）不再存在；一切路径以本文件与手册 §3.2 为准。
# 划分口径修订（2026-09-12，大纲 5.1 第三条）：门槛由“验证/内部测试每类 ≥20 个”改为“**验证集与内部测试集中的正样本合计 ≥ 该类正样本总数的30%**”（逐划分 30% 对低频类不可行，取合计口径；docx 已改）；make_splits.py 增补 splits.csv、split_metadata_seed*.json、逐类 support 与 rule_check（三种子成员不变，sha256 校验通过）；实测三种子均未达标（seed0 5/7、seed1 6/7、seed2 6/7 类不足；随机划分下 val+test 期望占比 ≈20%，换种子不可解）→ 约束分层重划/局限记录待决策。
# 覆盖约束校正落地（2026-09-12，A2）：大纲 5.1 补半句；make_splits.py 增 --strategy（constrained 默认；random 输出隔离 random_snapshot/）与 refine_coverage（最小确定性替换：换入稀有类正样本、换出全零合约）；coverage_swaps_seed*.txt 记录替换明细；主种子 seed0（用途定位声明见 decisions §12）；pytest 25 通过。（本节数字均为**预去重**口径，已被下方 P1 记录取代。）
# ⚠ 本行以下含 2026-09-13 旧 448 池数字（micro-F1 0.9058 / mAP 0.4139 等），**已作废**，存档 `runs/prior_448pool/`；现行两组结果见本文件末尾「两组结果集并存」记录。
# 状态（2026-09-12）：M1–M4 完成（CALLBACK_RISK **511 边/86 图**（R5 修复后；原 509/85）；M1 七类 flags **21571**（原 21567）；M3 _cb.pt×581 + _feat.pt×581；M4 model.py + 22 用例 + M4_interface.md）；M5 主体已实现（2026-09-12）——dataset.py、make_splits.py、metrics.py、train.py、evaluate.py 均已完成，`pytest tests/` **64 passed**，train/evaluate/summary 全链路 smoke 通过；products/alldata/splits/ 已生成（train 358/val 45/test 45 × 3 种子；448 训练池/86 buggy 剔除/0 unmatched；逐类 pos 与 rule_check 见 split_report.json；另含 splits.csv、split_metadata_seed*.json、dedup_dropped.txt）；划分按大纲 5.1（固定种子 8:1:1 + **覆盖约束校正**：C1 合计每类 ≥30% + C2 每划分每类 ≥1；2026-09-12 落地；**两级池去重**后三种子构造达标，替换 18/16/12 个；主种子 seed0）。**3 种子主实验已完成（2026-09-13，CUDA/RTX 4070 Laptop，torch 2.0.1+cu118）**：`runs/seed{0,1,2}/` + `summary.json` 就绪——micro-F1（主指标，标签对级）固定 0.5 = **0.9058±0.0397**、验证集阈值 = **0.9492±0.0145**（阈值 0.75/0.60/0.55）；macro-F1（参考）固定 0.5 = 0.2300±0.0428；mAP = 0.4139±0.1070。训练时间（§11.4 口径）：seed0/1/2 wall 40.8/16.3/16.0 s、train_seconds 7.4/6.0/3.2 s、graphs/s 924/660/1003、早停 @epoch 18/10/8（best val micro-F1 0.9556/0.9492/0.9587）。阶段 F（消融/基线）与 G（DIVE/SolidiFI）待执行。
# 外部数据集就位（2026-09-11）：DIVE（22330 源码 + 21696 条 7 维标签 + 3 张原始 CSV）与 SolidiFI（350 注入合约 + 350 日志 + 350 条 7 维标签）均只用于阶段 5 评估，不参与训练/验证/模型选择；使用前须先建类别映射表（SolidiFI 前缀→七类已确定，手册 10.5/10.6）。
# 清理记录（2026-09-12）：删除残留 slither-env/（25 MB 空 venv，未被 git 跟踪；.gitignore 规则保留以防重建）。解析环境始终为 conda base，删除不影响任何脚本。
# 口径修正记录（2026-09-12，P0 最小改动；见 decisions §13）：新增 `scripts/audit_data_funnel.py`（每步数字带产物出处；含 `846 → 591` 差额 255 的逐条拆解）→ `docs/data_funnel.md` + `products/alldata/splits/data_funnel.json`；主指标改 micro-F1，阈值/早停目标改 val micro-F1，macro-F1 降参考（含 3 个池内 ≤6 支撑类）；逐类 F1/PR-AUC 强制标注 support，support ≤2 仅描述性；多标签叙事降级为架构性声明 + DIVE 外部证据（DIVE 68.2% 多标签）；DIVE 抽样规模定 n=1000（**已由下方 P1 记录改为 n=900**）。
# 口径收口记录（2026-09-12）：DIVE 抽样按定稿协议实跑并闭案（`scripts/sample_dive_subset.py`：seed=0/均匀无放回，实测 fr≥20，未触发 n→1100 后备；禁止换 seed 重抽）→ `products/dive/splits/{sample_seed0.json,sample_report.json}`；审计脚本新增图结构口径（AST 稀疏性 + 4 语义边/5 物理关系映射）与口径绑定指纹（`split_seed*.json` sha256）+ T-A 刷新义务；手册 §7.7 补关系数映射表、§10.4 修正为三值接口 `(z, a, node_logits)`、§10.5 补防错位原则。
# P1 落地记录（2026-09-12，见 decisions §14）：① **两级池去重**——`make_splits.py --dedup source-sha1+address`（默认）；池 **495 → 448**（level-1 源码内容 sha1 丢 46，全为全零副本；level-2 项目标识/地址丢 1，即全库唯一多标签样本 0x627fa62c…，两份源码 1847 vs 1842 字节、sha1 抓不到、曾跨 train/val），划分 **358/45/45**，三种子 C1+C2 7/7 达标且**跨划分内容/地址重复均为 0**；新增 `dedup_dropped.txt`、`split_report.json::dedup` 与逐种子去重不变量；② **DIVE 抽样改 n=900**（front_running=30 ≥20，attempt=1 闭案；n=1000 旧试验作废）；③ **关系数口径**：论文 4 语义边 / 实现 5 物理关系、`num_bases=5`，不做物理合并；④ **边级消融**：`dataset.py::DROP_AST={1,2}`，`--drop-ast` = 删 relation 1+2，`DROPPABLE_EDGES` 加载时强制白名单校验；⑤ **M3 前端化设计稿待审**：`docs/M3_frontend_design.md`（`_pyg.pt` 不动）。
# 函数级通道缺口修复记录（2026-09-12 三轮，见 decisions §15）：新增 `scripts/audit_cb_func_gap.py`（→ `products/alldata/splits/cb_func_gap{,_after}.json` + `docs/cb_func_gap{,_after}.md`；新增 `legacy_ctor` 类与基线防覆写守卫）；M2 `build_cfg_centered_hetero_graph.py` 增加**函数表补登记**（alias + modifier + **legacy_ctor**；`--only` 小样开关；`fn_meta_table` 双隔离）+ **`normalize_ast()` 兼容 solc ≥0.8 风格 AST（R5）**→ `functions` 14741→**23260**、缺口 **37.6%→2.8%→2.55%→2.52%**（2356 行/475 键/382 图，覆盖率 97.48%）；`_cb.pt` **全量 `--force` 重建**（≈55 min；与 `--cb-patch` 增量补丁全库逐位等价）；旧 `_hetero.json` 备份于 `graphs/_hetero_backup_pre_gapfix/`；残余**全部是** `slitherConstructor*`（不可编码），裁定入口 `docs/residual_gaps.md`；R5 后库级统计刷新（边 226476→**226511**、DFG 146679→**146712**、CALLBACK_RISK 509/85→**511/86**、M1 raw hits 21567→**21571**）。
# 前端化落地记录（2026-09-12，承重墙；见 docs/M3_frontend_design.md 已实施版）：M3 → 纯通道构建（`_feat.pt` = schema v2 通道字典 struct/type_id/sv + 逐通道 sha256；无 RNG；`--variant`/`--feat-groups` 退役；`_cb.pt` 命中不加载 CodeBERT，全量 581 图 41 s）；`dataset.py` → `GraphSample` 通道组合 + 契约断言（旧格式报错、哈希报具体通道名）；`model.py` → `NodeFuser`（可学习嵌入；**融合前**掩码；配置层 ablate_sv/feat_groups/cb_channels 与正则层按图 Bernoulli(0.2) 严格分层）+ `sample_dropout_masks`/`parameter_report`；旧特征归档 `graphs/legacy_feat_pre_frontend/`（583 文件）。验收：T2 冻结等价逐位相等（maxdiff 0）、T1 无泄漏单测、全库 581 图断言通过、`pytest` 39 passed；新增 `tests/test_frontend.py`（13 用例）。发现待裁定：cb 函数级通道缺行 35195/93551（37.6%，继承函数不在 functions 表；旧路径同行为）——**已三轮修复至 2.52%（2356 行）**，见上一条。
# 代理指令迁移（2026-09-12）：.github/copilot-instructions.md → 根目录 AGENTS.md（跨工具开放标准，VS Code/Copilot 直接读取）；新增根目录 CLAUDE.md（内容仅为 @AGENTS.md 导入，供 Claude Code 与 VS Code 读取）；约定内容单一维护在 AGENTS.md，两者勿重复。
# 并行第二数据集引入（2026-09-14，见 decisions §19）：新增只读数据源 `alldata_augmentation/`（MVD-HG 论文增强集；1780 个扁平 `.sol` + 9026 条 7 维标签，10 种标签模式，逐类正样本 1033/1204/948/1044/971/870/1313），只读源由 4 个增至 **5 个**；新增产物分区 `products/augmentation/{raw,graphs,splits}/`（**骨架已建、产物待生成**），产物区由三区变四区。**定位为与 `alldata(readonly)` 并行的第二个数据集**（增强/不平衡对照），暂不替换主实验口径、不改动 `products/alldata/` 既有产物与 `runs/` 主结果。`MVD-HG-dataset/` 一度被删除后**已按裁定恢复**（`git restore`，工作区与 HEAD 一致），故 `audit_data_funnel.py` 的「上游 MVD-HG-dataset → 主库 alldata」审计链保持完整、`docs/data_funnel.md` 无需改动。⚠ 谱系未闭合：`alldata_augmentation` 与 `MVD-HG-dataset/*_data_augmentation/` 的并集互不为子集（差 300/51 文件）、标签合并亦不吻合（22939 vs 9026，共有键 5 条不一致），来源待确认后方可写入论文。
# 增强集标注审计（2026-09-14，decisions §19.3–§19.3.2）：**谱系已结案**——源文件取 `MVD-HG-dataset/{类}_contract_data_augmentation/sol_source/`，同名同内容合并并改名去歧义（`buggy_N.sol` → `{类}__buggy_N.sol`），标签 = 7 类目录 `targets==1` 并集，实测 **8997/9026 = 99.7%** 严格一致；结构对齐零缺陷（1780 文件 ↔ 9026 条目，零孤儿），此前"对不上"的三条差异**全部由改名规则解释**。**但发现标注缺陷**：298 个 `{类}__buggy_N` 文件「同名不同内容」（同一编号在 7 类目录里是 7 个不同文件），被并集规则推成 `1111111`（714 条），与上游 `solidifi_labels.json` 的单类注入真值矛盾 → **全集中 59% 正样本（4386/7383）虚高**，启用前须按 §19.3.1 三方案择一处置。另有两处**上游继承**缺陷：123 个双地址拼接文件名、779 条幽灵标签条目（§19.3.2）。
# 增强集标签修正落地（2026-09-14，decisions §19.3.1，裁定方案 A）：新增 `scripts/repair_augmentation_labels.py`（窄规则：仅 `{类}__buggy_<rest>` 条目取其本类目录 `targets` 写成 one-hot，其余原样；`--dry-run` 可先看影响面，默认拒绝覆写需 `--force`）→ `products/augmentation/contract_labels_repaired.json` + `label_repair_report.json`。实测**修正 765 条、未解析 0、solidifi 交叉校验不一致 0**；独立复核：键集合不变、改动项全落在 `__buggy_` stem、**修正后多标签条目 0**、合计正样本 **2997 = 非零条目数**（= 单标签集）。逐类正样本 7383 → **2997**（access_control 421 / arithmetic 558 / dos 336 / front_running 432 / reentrancy 359 / time_manipulation 224 / uncheck 667）。**`alldata_augmentation/` 只读源未被写入**，两者并存备查；该集**正典标签自此为 `contract_labels_repaired.json`**。
# 防误提交保护（2026-09-14，用户裁定）：`alldata_augmentation/` 加入 `.gitignore`——该目录 1781 个文件属只读数据源，未跟踪状态下会被 IDE 的「提交全部」一键扫入（撞 AGENTS.md「不要把只读数据源加入提交」）。加忽略后未跟踪条目 **1832 → 51**。磁盘文件与只读约束不受影响（`git check-ignore` 判定通过、标签仍可读）。刻意**不跟从**其余 4 个只读源「历史已入库」的惯例：本目录可由 `MVD-HG-dataset/` 派生重建，无需占版本体积。已在 `.gitignore` 注释、`AGENTS.md` 数据边界段与本文件同步说明。
# 泄漏处置与两组结果集裁定（2026-09-15/16，见 decisions §21/§22/§23）：① `near_dup_clusters.py` 新增 `--cluster-mode {complete,components}`——**划分防泄漏必须用 components（相似图连通分量）**，全链接是贪心分组、只能降 90% 不能归零（主库实测 8/7/5 对 vs 连通分量 0/0/0）；新增 `--audit-split/--audit-out` 泄漏审计入口。② 主库零泄漏对照臂 `products/alldata/splits/neardup_snapshot/` + `runs/neardup/`：micro-F1@0.5 **0.8561±0.0379**（现行正典 0.8954±0.0211，**−3.9 点**），泄漏抬升集中在固定 0.5 工作点。③ C1 覆盖约束在增强集上**算术不可行**（正样本率 79.7% > 66.7% = s/r，与种子无关；需 427 个「类-样本」计数而上界 357），已 `--min-pos-ratio 0` 关 C1 保留 C2；`make_splits.py` 内置可行性预检。④ **两组结果集并存裁定**：① 主库（池 453，逐类 17/15/6/4/31/5/50，micro-F1@0.5 0.8954±0.0211、mAP 0.2980±0.0127）与 ② 增强集（池 1774，单标签，逐类 106–361，micro-F1@0.5 0.9744±0.0128、mAP 0.9804±0.0090）**各自独立完整、并列呈现**，禁止跨组比较或合并；三条例外臂 `runs/{neardup,withbuggy,augmentation_dedup}/` 不进两表。总表 `experiments/results.md` §0。⑤ `m3_build_features.py` 新增 `--device {cpu,cuda,auto}`（默认 cpu 不变；GPU 实测 6.2×）+ `cache_usable()`/`atomic_torch_save()`（防 WSL 整机重启腰斩留下的 0 字节残缺缓存）；`train.py`/`evaluate.py` 新增显式 `--label-file`/`--label-key-mode` 与划分内标签硬校验。`pytest tests/` **101 passed**。（本条结果数字为**冻结编码器**旧口径，已被下方 ⚠ 注记取代。）
# ⚠ 口径刷新（2026-09-20，decisions §37 微调 CodeBERT 升为正典）：本条 ② `neardup` 的 0.8561±0.0379 / **−3.9 点**与 ④ 的 ① micro-F1@0.5 0.8954±0.0211、mAP 0.2980±0.0127、② micro-F1@0.5 0.9744±0.0128、mAP 0.9804±0.0090 均为**冻结编码器**时期的旧值（其中 ① 一组更早，属 2026-09-16 前「丢弃 80%」口径），**已作废**；本条只保留「两组结果集并存」这一**裁定**（池 453 / 1774、划分、单标签结构**均未变**）。新正典（test，微调 CodeBERT，出处 `experiments/canonical_ft_numbers.md`）：① micro-F1@0.5 **0.7110±0.0389**、micro-F1@val_thr **0.7297±0.0675**、mAP **0.7582±0.0056**；② micro-F1@0.5 **0.9901±0.0100**、micro-F1@val_thr **0.9913±0.0076**、mAP **0.9975±0.0025**。⚠ `neardup` 臂在两份权威源（`canonical_ft_numbers.md` / `runs/error_rates.json`）中**均无新值**，待补。
# 消融准备与覆盖守卫（2026-09-16，见 decisions §25、experiments/ablation_plan.md）：① 新增 `scripts/run_guard.py`，给**四处**默认指向正典区的输出加守卫（train/make_splits/m3 用 `--overwrite`、shell 脚本用 `SSMHG_ALLOW_WIPE=1`）；实施中修掉一个真 bug——实验自述记绝对路径而命令行常传相对路径，未归一化会把同参数复跑误拒。② 新增 `tests/test_ablation_switches.py` 逐项验证消融开关**真的接到了数据/模型上**（消融的价值全在"只有一个变量在动"）。③ 新增 `experiments/ablation_plan.md`：17 项消融的命令矩阵与就绪盘点——12 项可直接跑、1 项需 M2 变体、1 项被阻断、3 项需开发；M2 变体空间可压到 0.15 GB（`_cb.pt` 占 14.6/15 GB 且与边无关，软链复用）。④ **发现阻断项**：`--prior-dropout` 实为**保留率**（默认 0.2 实际置零 80% 的图，与大纲 4.1.4 的丢弃率口径差 4 倍），且 `--prior-dropout 0` 会每张图都置零、等价于 `--ablate-sv` → 「关闭先验 Dropout」无法按意图表达；**待裁定**（三方案见 decisions §25.3），测试以 `xfail(strict=True)` 钉住。`pytest tests/` **149 passed + 2 skipped + 1 xfailed**。
# `--prior-dropout` 语义修正与全量重跑（2026-09-16，见 decisions §26）：`model.sample_dropout_masks` 原为 `rand < p`，
# 掩码是乘性系数 ⇒ `p` 实为**保留率**（默认 0.2 实际置零 80% 的图，与大纲 4.1.4 的丢弃率口径差 4 倍），且 `--prior-dropout 0`
# 会把每图都置零（等价 `--ablate-sv`，使「关闭先验 Dropout」无法表达）。已改为**丢弃率**（`rand >= p`）；**结构 dropout 共用
# 同一函数，一并修好**。四处同步（代码/参数名/文档/测试），`tests/test_frontend.py` 中一个按旧语义写的断言也已改正。
# 旧口径全部结果作废并归档 `runs/prior_dropout80/`（**不含 best/last.pt**——与现行仅差 `--prior-dropout 0.8` 一个开关，且本机
# C 盘紧张，不为作废口径保留 114 MB 二进制）；8 个臂已按原参数逐字重跑为新口径。补跑 `diagnose.py` 与 `calibrate.py`
# （二者依赖 runs/ 缓存，重跑后失效）。裁决：**维持 0.2、不返工 80%**（n=9 同配对研究：丢 20% 反而略优、丢 100% 不更好、
# mAP 随丢弃率单调下降）。补充研究 `runs/prior_dropout_study/`（权重已删，仅 2.1 MB）。
# ⚠ 磁盘：C 盘可用 12 GB **低于 20 GB 硬阈值**（见 AGENTS.md 磁盘空间规则），故本轮 114 MB 权重**暂未入库**，待回收后补。
#   ⚠ 口径刷新（2026-09-20，§37）：本条数值来自 runs/loss_study/* 与 runs/prior_dropout_study/*，
#   其 graph_dir 仍是 products/alldata/graphs（冻结编码器）⇒ 未按新正典重算；且本节列的
#   focal +0.0072 / mAP +0.0514 / −0.0825 一组属 §28 指标修复之前的口径。
#   🔴 待复核（2026-09-20 口径变更）：只能读作「在冻结工作点上未能改善」。见 decisions.md §39.6 待办 2。
# §1.8/§1.10 多种子复核（2026-09-17，见 decisions §27）：修正 dropout 语义后这两节结论方向曾翻转，用**同配对 n=9**（基线复用 `runs/prior_dropout_study/drop20_ts*_ss*`，三臂重跑于 `runs/loss_study/`，权重已删、仅 1.1 MB）复核定稿：**§1.8 旧结论成立**（放开截断不救稀有类，且 @0.5 显著变差 −0.0825）；**§1.10 对 ASL 成立、对 focal 不成立**（focal `@val_thr` +0.0072 显著、mAP +0.0514 边缘、`@0.5` 不受影响）。待裁定：主实验是否改用 focal（建议维持 bce）。⚠ 规范：噪声 ±0.05–0.07 量级时 **n=3 表面模式不可信**，判方向须同配对 ≥9 点（两天内同类教训 2 次）。
# 报告文档新增与 results.md 作废口径残留修正（2026-09-17）：按用户要求把「实验数据」与「实验结论」**分开存储**——新增 `experiments/report_data.md`（**数据卷**：全臂逐类 F1/阈值/计时/产物索引，由 `runs/**/results.json` 直接聚合，**非权威**）与 `experiments/report_conclusions.md`（**结论卷**：解读、各臂处置建议、指标优化方向、待裁定事项）；两卷均声明 `results.md`/`decisions.md` 为权威源。同期修正 `results.md` **五处**作废口径残留（§1.4 阈值括注 `0.70/0.60/0.55` → `0.60/0.70/0.60`；§1.9 三处：`0.9492/0.9471`、`0.9556/0.9492/0.9587`、`0.728/0.582/0.543` 与 `0.75/0.60/0.55`、`0.2635/0.2455` → 现行值；§6.5 计时 `12.7–23.9 s` 实为 `runs/prior_dropout80/seed*` 的实测值 → `10.4–15.1 s`）。⚠ 修正过程中发现一个**待裁定**问题：`scripts/metrics.py::micro_f1` 对输入做了 `ravel()`，使 sklearn 按二分类处理、`average="micro"` 退化为**准确率**（全判负时返回约 0.93 而非 0），波及全部上报 micro-F1 与阈值搜索/早停；**未擅自改动**，证据与方案见 `experiments/report_conclusions.md` §4 待裁定 #1。
# 指标口径修复与全量重训（2026-09-17，见 decisions §28）：`scripts/metrics.py::micro_f1` 与 `search_global_threshold` 对输入调用 `.ravel()`，把 `[N,7]` 展平成 1-D `{0,1}`，sklearn 的 `type_of_target` 遂从 `multilabel-indicator` 改判为 `binary`，而 `average="micro"` 在 binary 下**恒等于逐样本 accuracy**。实测 **24/24 个 run 的旧记录与 accuracy 逐位相等（最大绝对差 0.00e+00）**；主库 seed0 test@0.5 记录 0.7795、真值为 0.1839。**影响不止"数字算错"**：该指标还参与 LR 调度 / 早停 / `best.pt` 选点，旧正典权重实为**从未学过任何漏洞的全负模型**（seed0 的 val 指标六 epoch 冻结在 0.9302 = 负类基准率、`val_macro` 起始 0.0000；"最优" val 阈值落在全判负退化解 `max(val_prob)=0.567 < 0.60`）。修复：新增 `_as_2d()` 守卫（一维视为单列，**严禁 ravel**）、两处调用改用它、模块 docstring 改写为**数组形状契约**（"展平"是统计口径不是数组操作，正是 bug 的语义来源）；`tests/test_metrics.py` 原有 2 处断言**把 bug 抄成了期望值**（"与 sklearn 对照逐位相等"因此反而保护了 bug），已改正并新增 3 个回归锁（全判负必为 0、micro-F1 ≠ accuracy ≠ `subset_accuracy`、阈值 argmax ≠ accuracy argmax）。`pytest tests/` **157 passed + 2 skipped**。旧产物全量归档 `runs/prior_badmetric/`（含 README 说明；**权重保留未删**，它们是坏指标诊断的物证，且 `best.pt` 是 `evaluate.py` 唯一输入）。⚠ **`run_guard` 拦不住这次**——它只比对参数，而本修复不改任何 CLI 参数 → 会被判定为"同一次实验"并放行覆盖，故必须手工先归档。重训：新增 `scripts/rerun_from_config.py`，从归档 `config.json::args` **逐参数重放** 105 个 run（8 正典臂 × 3 种子 + 2 研究臂 × 81 配对），wall 2530.9 s ≈ 42 min（GPU 串行），随后评估 24 个正典 run + 8 臂 summarize + 逐类诊断 + 标定；研究臂 `best.pt` 按原惯例剪除（81 个，≈405 MB，仅留 `val_best_probs.pt` + JSON）。**主库新值**：micro@0.5 **0.4256 ± 0.0309**（旧 0.8489 为 accuracy）、micro@val_thr **0.4528 ± 0.0774**、macro@0.5 **0.2503 ± 0.0313**（近翻倍）、mAP **0.3047 ± 0.0119**（**std 由 ±0.0963 塌到 ±0.0119**——mAP 本身不受 bug 影响，故此变化纯粹来自模型选择改善）。**三处结构性变化**：(a) 旧结论「验证集阈值大幅提升主指标」（0.85→0.94）**是退化假象**，真口径下仅高 +0.027；(b) mAP 波动降 88%，是"修指标 = 修训练控制流"的直接量化证据；(c) `access_control` **不再恒零**（0.229 ± 0.206），"4 类恒零"改为 **3 类**。**结论翻转**（n=9 同配对，`scripts/paired_study_analysis.py`）：focal 的「显著更好且不付代价」**被推翻**（`@val_thr` +0.0072 t=+2.80★ → +0.0210 t=+0.84；mAP +0.0514 → **−0.0008 t=−0.05**），`decisions.md` §27.4 原本的建议 A（维持 bce）**反而是对的**；放开 `pos_weight` 截断由"仅 @0.5 显著"**加强**为两个工作点均显著（t=−7.02 / −3.31）；ASL 的 mAP 优势**不再显著**（+0.0915★ → +0.0239）而 @0.5 崩溃更明确（t=−11.29）；零泄漏臂 `neardup` **方向翻转**（+0.0062 → −0.0810，符合预期但 n=3 不足以判定）；dropout 维持 0.2 **存活**（mAP 随丢弃率单调下降）。**设计定稿 = 维持全部现有设计**（`report_conclusions.md` §7.6）。文档同步：`results.md` §0/§1.2/§1.3/§1.4/§1.5/§1.7/§1.7.1/§1.7.3/§1.8/§1.9/§1.10/§6.3/§6.4/§6.5/§6.6 全部按新值重写 + 顶部作废横幅；`report_data.md` §1.1/§1.2/§1.3/§2.1/§2.2/§3/§4.1/§4.2/§6 刷新（§2.3–§2.6 标注待刷新）；`report_conclusions.md` 头部/§0/§7 重做并新增 §7.6。**教训**：① "展平"有歧义，口径描述必须写**输入形状与分派预期**；② **测试会把 bug 固化成"正确行为"**——对照测试必须以口径定义书写，不能以实现书写；③ 报告多标签结果时主指标必须与 `subset_accuracy`/macro-F1 **同表呈现**（旧 §1.3 的 seed0 行 `micro 0.7795` 与 `subset acc 0.0000` 同行自相矛盾，是最早可得的警报）；④ **参与训练控制流的指标，修改它 = 全部结果作废**——判断一次口径修复的代价，先问"该指标有没有进控制流"。（本条「主库新值」为**冻结编码器**旧口径，已被下方 ⚠ 注记取代。）
# ⚠ 口径刷新（2026-09-20，decisions §37 微调 CodeBERT 升为正典）：本条「**主库新值**」micro@0.5 **0.4256 ± 0.0309**、micro@val_thr **0.4528 ± 0.0774**、macro@0.5 **0.2503 ± 0.0313**、mAP **0.3047 ± 0.0119** 为**冻结编码器**口径，**已作废**；本条对 §28 缺陷本身（`.ravel()` 使 `average="micro"` 退化为 accuracy、指标进训练控制流、测试把 bug 抄成期望值）的记述**不受影响**。新正典（test，微调 CodeBERT，出处 `experiments/canonical_ft_numbers.md`）：micro@0.5 **0.7110±0.0389**（逐种子 0.7273 / 0.6667 / 0.7391）、micro@val_thr **0.7297±0.0675**（0.7556 / 0.6531 / 0.7805；val 阈值 **0.75 / 0.60 / 0.80**）、macro@0.5 **0.6091±0.0751**、macro@val_thr **0.4986±0.0452**、mAP **0.7582±0.0056**；池 453 / 划分 / 训练超参 / 参数量 415226 **均未变**（本轮只换编码器）。合约级二分类 F1@val_thr **0.9419±0.0385**、误报率 **2.62%** / 漏报率 **8.02%**（出处 `runs/error_rates.json`）。逐类与消耗见 `experiments/canonical_ft_numbers.md`。
#   🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。原句（上条 2026-09-17 §28 记录内，原样保留）："(a) 旧结论「验证集阈值大幅提升主指标」（0.85→0.94）**是退化假象**，真口径下仅高 +0.027"；"(c) `access_control` **不再恒零**（0.229 ± 0.206），"4 类恒零"改为 **3 类**"。（新正典下 (a) 的差值更小（0.7110 → 0.7297）、`access_control` F1@0.5 = 0.4545±0.1273，"不再恒零"方向未变，但两处数值须按新正典改写。）

# 单头二分类臂（2026-09-17，见 decisions §31）：新增 `--head {multi,binary}`（默认 multi，正典臂逐字节不变）——
#   `binary` 时输出头 7→1、标签塌成 `any(targets)`（**塌缩只发生在 `dataset.stack_labels` 一处**，
#   build_index/划分/标签文件/通道哈希全部不动）、损失单类 BCE、早停/调度判据改用 **val 二分类 AP**
#   （§9.6.1 已证合约级 F1 被常量解刷到 0.62/0.93，动态范围不足以做判据）。**「只换输出头」是逐位成立的**：
#   同 seed 下 `SSMHG(num_classes=7)` 与 `(1)` 的 12/12 共享张量逐位相同，唯一差异是 `cls.2`（机检于
#   tests/test_binary_arm.py）。⚠ 头号约束：`[N,1]` 的 `type_of_target` 是 `binary`，`average="micro"`
#   **恒等于 accuracy**——即 §28 那个 bug 换个入口重现；故 (a) 多标签入口经 `_as_2d_multilabel()` 对单列**报错**、
#   二分类入口对多列报错；(b) 二分类指标一律由**混淆计数直接算**，完全不经 sklearn 的 `average=` 分派；
#   (c) `evaluate.compute_binary_report` 刻意不复用 `micro_f1` 键名（键名一律 `binary_*`），使误读变成 KeyError。
#   🔴 **附带修掉一个 `run_guard` 静默覆盖洞**：`diff_args` 只比对双方都有的键 → 用新键（如 `--head binary`）
#   写进旧目录时差异为 0、守卫放行、**不加 --overwrite 也会覆盖**（同 §28 那类"守卫看不见新键"）。
#   新增 `run_guard.IDENTITY_DEFAULTS`（缺失侧按默认值补齐后再比）：新键写旧目录会报冲突、复跑旧实验仍放行、
#   且 `run_ablation.verify_single_variable` 不再误判新键"未生效"。**新增身份键必须登记进该表**（有漂移守卫测试）。
#   驱动：新增 `scripts/run_study.py`（唯一支持 (train_seed, split_seed) 独立配对的运行器；import 复用
#   run_ablation 的单变量断言，另加"一对两臂语料四键逐字相同"的断言）。分析：`paired_study_analysis.py` 的
#   `val_binary_*` 族**两条臂都算**，合法性来自恒等式 `max_c p_c >= t ⇔ any_c(p_c >= t)`（已机检）。
#   `pytest tests/` 191 passed + 2 skipped。

# 阶段 F 消融首跑（2026-09-17，见 experiments/ablation_results.md）：`scripts/run_ablation.py` 跑完 **12 项 × 3 种子 = 36 run**
#   （5.4.1 的 11 项 + 5.4.2 的 `hid256` + 09-18 补的 `numbases1/3/4`、`dropedge02`），wall ≈19 min、失败 0 → `runs/ablation/<item>/seed{0,1,2}/` + `summary.json`。
#   **验收第 1 条 16/16 通过**：开跑前驱动断言 + 产出后对 36 份 config.json 再核，"去掉记账键后恰一个变量"，违规 0 处。
#   ⚠ **全文是 n=3 描述性、不作方向性结论**（本仓 §26.7/§27.5：正典 std ±0.0309，n=3 判不了 ±0.05 量级）。
#   三条可读观察：① **Δmicro 与 ΔmAP 六项反号**（"用召回换排序"，单看任一指标都会片面）；
#   ② **mAP 是唯一 std 够紧的指标**（正典 ±0.0119），12 项中 9 项的 |ΔmAP| 超阈 → 若要做同配对 ≥9 点验证，
#   **mAP 是信噪比最高的观察窗**；③ `hid256` 的 ΔmAP 最大（+0.0704）**但它同时是唯一动容量的一项**（参数 ×1.97），
#   在分离容量与结构之前**不可解读**。另记：`cb_*_only` 的两项参数量少 23.7%（融合层随通道数变小），
#   故其差异不能只归因于"少了那一路语义"。正典与消融的 wall **不可直接比**（正典含 24.76 s 冷缓存数据加载）。
#   未跑 4 项：CALLBACK_RISK 上限（需 M2 变体）、CALLBACK_RISK_REV 与 RGCN 层数、微调 CodeBERT（需开发）。
#   开发方案见 experiments/ablation_plan.md §6（四项共 21 run、≈1.7 GB）。
#   ⚠ **`num_bases` 的"取 10"实测不可行**（`model.py:332` 约束 `1<=num_bases<=num_relations`=5，
#   而合法上端 5 就是基线）→ 改取合法非默认区间的两端 1 与 4，并补 3，凑成 1/3/4 vs 默认 5 的剂量-反应。
#   ⚠ 口径刷新（2026-09-20，decisions §37 微调 CodeBERT 升为正典）：本例引用的「正典 std ±0.0309」与「正典 ±0.0119」均为**冻结编码器**口径，**已作废**；新正典（test）micro@0.5 std **±0.0389**、mAP std **±0.0056**（出处 `experiments/canonical_ft_numbers.md`）。另：本例只记 ① 的首跑；2026-09-19 §38 已完成 ①② 各 21 臂 × 3 种子 = 126 run 的全量重跑（Δ 相对**新**正典重算）。
#   🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。原句（本例内，原样保留）："⚠ **全文是 n=3 描述性、不作方向性结论**（本仓 §26.7/§27.5：正典 std ±0.0309，n=3 判不了 ±0.05 量级）"；"② **mAP 是唯一 std 够紧的指标**（正典 ±0.0119），12 项中 9 项的 |ΔmAP| 超阈 → 若要做同配对 ≥9 点验证，**mAP 是信噪比最高的观察窗**"。（新正典 mAP std ±0.0056 仍是最紧的一路、"n=3 判不了 ±0.05"亦不受影响，方向未变；但两条判断的**依据数值**须按新正典改写。）

当前进度：
- **★ 2026-09-16 裁定：两组结果集并存**（`decisions.md` §23、总表 `results.md` §0）。两组**各自独立完整、并列呈现，禁止跨组比较绝对值或合并成一个数字**：

  | | ① 主库 `alldata(readonly)` | ② 增强集 `alldata_augmentation` |
  | --- | --- | --- |
  | 池 | **453**（590 − 90 buggy − 47 去重） | **1774**（0 剔除） |
  | 逐类正样本 | 17/15/**6**/**4**/31/**5**/50 | 200/251/143/171/182/106/361 |
  | 标签结构 | 多标签 | **单标签** |
  | 跨划分近重复对 | 69/68/76（已披露） | **0/0/0** |
  | micro-F1 @0.5 | **0.7110±0.0389** | **0.9901±0.0100** |
  | micro-F1 @val_thr | **0.7297±0.0675** | **0.9913±0.0076** |
  | mAP | **0.7582±0.0056** | **0.9975±0.0025** |

  > ⚠ **本表已于 2026-09-18 按 §28（`micro_f1` 的 `.ravel()` 缺陷修复）后的重训结果更正。**
  > 旧载 `① 0.8489/0.9389/0.2804`、`② 0.9739/0.9828/0.9795` 是**坏口径产物**：
  > 旧的「micro-F1」实为 accuracy，旧 `@val_thr` 是全判负退化解（详见 `results.md` §0 的对照段与 `decisions.md` §28）。
  >
  > ⚠ **本表已于 2026-09-20 按 §37 新正典（微调 CodeBERT）再次刷新**：上表三行改为微调口径——
  > ① **0.7110±0.0389 / 0.7297±0.0675 / 0.7582±0.0056**、② **0.9901±0.0100 / 0.9913±0.0076 / 0.9975±0.0025**。
  > **旧载 ① 0.4256±0.0309 / 0.4528±0.0774 / 0.3047±0.0119、② 0.9347±0.0172 / 0.9547±0.0283 / 0.9804±0.0041
  > 为冻结编码器口径，已作废。** 权威出处 `experiments/canonical_ft_numbers.md`。
  > ⚠ 池 453 / 1774、逐类正样本、划分、训练超参、参数量 **415226** **均未变**——唯一变量是编码器（冻结 → 微调）。

  ① 回答「真实部署合约（含天然极稀缺类）上能检出什么」，宏观指标低是**数据事实**、非方法失效；② 回答「训练信号充足时的能力上限」，**不得**解读为 ① 的问题已解决。三条例外臂（`runs/neardup/`、`runs/withbuggy/`、`runs/augmentation_dedup/`）均不进两表。
  > 🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。
- **2026-09-16 消融准备完成（阶段 F **尚未开跑**；计划见 `experiments/ablation_plan.md`，决议见 `decisions.md` §25/§27）**：
  - 四处覆盖点全部加守卫（`scripts/run_guard.py` + 各自 `--overwrite`；shell 脚本用 `SSMHG_ALLOW_WIPE=1`）。
  - 消融开关接线验证 `tests/test_ablation_switches.py`：4 项边消融 + `--drop-ast` + 白名单、三项特征消融的列级掩码、
    `meanpool`、`num_bases`/`hid`、`L_var` 复合式（读既有日志验证，零新计算）。
  - **就绪盘点：17 项（5.4.1×11 + 5.4.2×6）中 12 项可直接跑**（零重跑，12 项×3 种子 ≈ 15 分钟 GPU）；
    **1 项**（CALLBACK_RISK 上限 4 vs 不限）需先造 M2 变体（空间可压到 0.15 GB：`_cb.pt` 占 14.6/15 GB
    且与边无关 → 软链复用）；**3 项需开发**（CALLBACK_RISK_REV 无反向边开关、RGCN 层数硬编码两层、微调 CodeBERT 无路径），
    已用 `@pytest.mark.skip` 显式登记不假绿。
  - ✅ **「关闭先验 Dropout」的 bug 已修正（2026-09-16，§26）**——原描述保留如下备查：。`sample_dropout_masks` 返回 `rand < prior_p`，掩码乘法作用于 s_v，
    故 **`prior_p` 是保留率**：默认 `--prior-dropout 0.2` 实际**置零 80% 的图**（大纲 4.1.4 的散文写的是丢弃率 0.2
    → **默认强度差 4 倍，且现有全部结果都带此口径**）；而 `--prior-dropout 0` 会**每张图都置零 = 等价于 `--ablate-sv`**，
    使该项跑不出它该测的东西。
    → **已按方案 A 修正**：`sample_dropout_masks` 改为丢弃率语义（`rand >= p`；与结构 dropout **共用同一函数**，一并修好），
    四处（代码/参数名/文档/测试）同步；`--prior-dropout 0` 现为「关闭」、`1` 为「全丢」、默认 `0.2` 置零约 20% 的图；
    **全部结果已重跑**，旧口径作废归档。测试已改为 6 个正常断言（原 `xfail(strict=True)` 会因修好而 XPASS 导致 pytest 失败）。
    裁决：**维持 0.2、不返工 80%**（同配对 n=9 研究显示丢 20% 反而略优、丢 100% 不更好、mAP 随丢弃率单调下降）。见 §26.6。
- **2026-09-17 §1.8/§1.10 多种子复核完成（见 `decisions.md` §27、`results.md` 表 1.8-d/1.10-b2）**：
  > 🔴 **待复核（2026-09-20 口径变更）**：本节全部数值来自 `runs/loss_study/*` 与 `runs/prior_dropout_study/*`，
  > 其 `graph_dir` **仍是 `products/alldata/graphs`（冻结编码器）**，未按 §37 重跑；且此处列的
  > focal −0.0825 / +0.0072 / +0.0514 一组更早，属 §28 指标修复**之前**的口径（§28 后已推翻）。
  > ⇒ 本节只能写成「**在冻结工作点上**未能改善」，**不得**推广为「在本文方法上无效」（`decisions.md` §39.6 待办 2）。
  修正 dropout 语义后这两节结论方向曾翻转，用**同配对 n=9** 复核后定稿（以下为当时记录，原文保留）：
  - **§1.8 旧结论成立**：放开 `pos_weight` 截断**不救稀有类**（逐类 ΔF1@val_thr 全为 0 或负），
    且 `micro@0.5` **显著变差 −0.0825（t=−3.50）**。3 种子下「access_control 0.000→0.121」是噪声，标记已撤回。
  - **§1.10 旧结论对 ASL 成立、对 focal 不成立**：focal(γ=2) `micro@val_thr` **+0.0072（t=+2.80 显著）**、
    `mAP` +0.0514（t=1.96 边缘），而 `micro@0.5` 不受影响（+0.0003）→ **唯一「显著更好且不付代价」的干预**。
    ASL 则是「概率膨胀」的两面：mAP **+0.0915（t=+3.31）** 显著更好、`@0.5` **−0.3734（t=−8.76）** 崩溃。
  - **待裁定**：主实验是否改用 focal（效应 +0.0072，但会再次作废全部结果）——**建议维持 bce**，
    把 focal 作为损失形状的改进方向写入论文讨论。见 §27.4。
  - ⚠ **规范（两天内同类第 2 次教训）**：噪声 ±0.05–0.07 量级的指标，**n=3 的表面模式不可信**；
    凡下「干预有效/无效」的结论必须**同配对 ≥9 点**，3 种子只用于报 mean±std。见 §26.7/§27.5。
- **2026-09-17 新增单头二分类实验臂 `--head binary`（`decisions.md` §31）**：回答 §30.5 明确留下的
  「二分类**模型**是否更强」（此前只证明了二分类**判据**更弱）。设计 = **唯一变量为输出空间**，
  n=9 同配对，覆盖 ①②两组语料，产物在 `runs/binary_arm/{main,aug}_{base,bin}/`。
  - 🔴 **头号坑已实测**：`[N,1]` 的 `type_of_target` 是 `binary` ⇒ `average="micro"` **恒等于 accuracy**，
    即 §28 那个让 105 个 run 作废的 bug 换个入口重现（`micro_f1([N,1], 全判负) == 0.5`，真值 0）。
    对策：多标签入口**对单列报错**、二分类入口对多列报错；二分类指标**由混淆计数直接算**，
    完全不经 sklearn 的 `average=` 分派；`evaluate` 的二分类键名一律 `binary_*`（误读变 KeyError）。
  - 🔴 **连带修掉 `run_guard` 一个静默覆盖洞**（§31.3）：`diff_args` 只比对双方都有的键 ⇒
    用新键（如 `--head binary`）写进旧目录时差异为 0、守卫放行、**不加 `--overwrite` 也会覆盖**。
    新增 `run_guard.IDENTITY_DEFAULTS`（缺失侧按默认值补齐后再比）。**新增身份键必须登记进该表。**
  - 「只换输出头」**逐位成立**：同 seed 下 `SSMHG(num_classes=7)` 与 `(1)` 的 12/12 共享张量逐位相同
    （`tests/test_binary_arm.py`）。标签塌缩只在 `dataset.stack_labels` 一处，图/划分/标签文件零改动。
  - 新增 `scripts/run_study.py`（唯一支持 (train_seed, split_seed) 独立配对的驱动，import 复用
    `run_ablation` 的单变量断言 + 同语料断言）。`pytest tests/` **193 passed + 2 skipped**
    （2026-09-17 当时；**现行 268 passed + 2 skipped**，见下方 M5 主体条）。
  - ✅ **已跑完并记录（36 run、wall 2665.5 s、0 失败；产物 `runs/binary_arm/`）**。结论
    （`decisions.md` §31.8、结论卷 §9.6.5、数据卷 §3.5）：
    **二分类模型确实略强，但只强在"排序"这一环** —— ① 主库 AP 同配对 Δ=**+0.0335（val t=+2.99 ★）**、
    test 点估计相同（+0.0334）但 t=+1.18 不显著；而**阈值化的 F1 在两个工作点、val 与 test 上全部无差异**。
    → **维持 §9.5 裁定：不改主任务为二分类**；本臂作为"输出空间消融"证据入论文。
    ⚠ ② 增强集的显著（AP t=+3.09/+4.71）建立在 `0.998 → 1.000` 的天花板空间上，**判定意义有限**。
  - 🔴 **等待长跑任务一律按 PID，禁止 `pgrep -f`**（2026-09-18 升级为通则）。
    此处原记的是**一个实例**（`pgrep -f "run_study.py --keep-going"` 会匹配等待脚本自己的命令行，
    补救写成"改用 `pgrep -f "python scripts/run_study.py"`"）——但那是**针对该实例的**，
    不是通则，故 2026-09-18 等待消融队列时**再次踩中**：等待
    `run_remaining_ablations.sh main` 的脚本末尾还要跑 `... aug`，两个字符串都在它自己命令行里，
    `pgrep -f` 匹配到自身 ⇒ 循环永不退出 ⇒ ② 那一组**永远不会开跑**，且没有任何报错。
    **通则：`while kill -0 <pid> 2>/dev/null; do sleep N; done`**，从根上消除自匹配。
    （`pgrep -af` 仅用于**人工排查**，此时能看到自身也无妨。）
  - ⚠ 二分类臂的 `micro_f1` 与
    `binary_f1` **数值恒等**（C=1），故"F1 == accuracy"这条检查会在**完美解**上误报——
    §28 的判据是"**非完美**时 F1 == accuracy"，校验应改为"由存的 TP/FP/FN 重算并逐位比对"。
- **2026-09-17/18 阶段 F 消融完成（`experiments/ablation_results.md`）**：**16 项 × 3 种子 = 48 run**，
  ≈19 min、失败 0 → `runs/ablation/<item>/`。**验收第 1 条 16/16 通过**（开跑前驱动断言 +
  产出后对 48 份 `config.json` 再核，"去掉记账键后恰一个变量"，违规 0 处）。
  - 🔴 **`num_bases` 的计划建议"取 10"实测不可行**：`model.py:332` 硬约束 `1 <= num_bases <= num_relations`(=5)，
    且**合法上端 5 就是基线**（`model.py:19`）→ 原"两端各一"的设计在合法区间内**没有上端可用**。
    改取合法非默认区间的两端 **1 与 4**（`model.py:19` 点名 4「仅作消融」）并补 3，
    凑成 **1/3/4 vs 默认 5** 的剂量-反应（比原计划信息量更大）。`drop_edge_prob` 按建议取 0.2。
    描述性读数：参数量 284,114(1) < 349,670(3) < 382,448(4) < 415,226(默认5)，而 mAP
    0.3134 → 0.3301 → 0.3417 → **0.3047**（三个非默认点单调上升、默认值反而最低）——
    ⚠ n=3 且这些臂 mAP 的 std 是正典的 2–5 倍，**是线索不是结论**。
  - 🔴 **全文是 n=3 描述性、不作方向性结论**（正典 std ±0.0309，n=3 判不了 ±0.05 量级；
    要判定某组件有效/无效须另做同配对 ≥9 点）。该声明写在文档 §0 与每张表下。
  - 四条可读观察：① **Δmicro/Δmacro 与 ΔmAP 在 16 项里有 12 项反号**（其中 11 项为"micro 降、mAP 升"的
    "用召回换排序"形态；复算口径见该文 §6，**此计数已写错两次，引用前请复算**）；
    ② **mAP 是唯一 std 够紧的指标**（正典 ±0.0119），**16 项中 12 项**的 |ΔmAP| 超阈
    （原 12 项矩阵时为 9/12；补 4 项后为 12/16）→
    若要做同配对验证，**mAP 是信噪比最高的观察窗**；③ `hid256` 的 ΔmAP 最大（+0.0704）
    **但它同时是唯一动容量的一项**（参数 ×1.97）→ 分离容量与结构之前**不可解读**。
    ④ **另一条计数**（同一程序复算）：Δmacro-F1@0.5 **16 项里 15 项下降**，唯一"上升"的 `hid256`
    只 +0.0028（std ±0.0313，实为持平）；而 ΔmAP **14/16 上升** ⇒ 与①合起来是同一个形态：
    **拿掉任何组件，排序质量（mAP）多半变好、阈值化 F1 多半变差**。
  - ⚠ `cb_*_only` 两项参数量少 23.7%（融合层随通道数变小），差异不能只归因于"少了那一路语义"。
    正典与消融的 wall **不可直接比**（正典含 24.76 s 冷缓存数据加载）。
  - 未跑 4 项：CALLBACK_RISK 上限（需 M2 变体）、CALLBACK_RISK_REV 与 RGCN 层数、微调 CodeBERT（需开发）。
    **开发方案已成文**：`experiments/ablation_plan.md` §6（四项共 21 run、≈1.7 GB；含 `_cb.pt` 膨胀 39 倍的前置发现与修复，`decisions.md` §33）。
  - 🔴 **本节是 2026-09-17/18 冻结编码器工作点的记录**——文中「正典 std ±0.0309」「正典 ±0.0119」以及
    被当作基线的 mAP `0.3047`，都是**旧正典**（2026-09-20 起 ① micro@0.5 = **0.7110±0.0389**、mAP = **0.7582±0.0056**）。
    本节各臂的 Δ 与读数**未按新正典改写**（新值见 `experiments/ablation_results.md` 与 `decisions.md` §38），
    引用前请先复算、勿与本节的正典参照混用。
- **★ 2026-09-19 待办 B1 完成：`cb_ft` 的 n=9 同配对复核 —— 效应确认（`decisions.md` §36）**。
  新增 `scripts/run_cbft_study.py`（`ts∈{0,1,2}×ss∈{0,1,2}`，两臂 frozen / cbft，**变量即 `graph_dir`**；
  三条开跑前断言：单变量 + 同语料（⚠ 语料键**不含 `graph_dir`**，与 `run_study.py` 的唯一实质差别）+
  产物层 590 图全量 sha256），18 run / wall 250.2 s / 失败 0 → `runs/cbft_study/`。
  **test 侧 8/8 指标显著**（判据 `|t|≳2.3`）：`micro@0.5` **+0.2466（t=+11.92）**、
  `micro@val_thr` +0.3094（t=+10.42）、`macro@0.5` +0.3070、`mAP` **+0.4366（t=+17.66）**、
  `Buggy@0.5` +0.1390（t=+5.38）；且 `Δmicro@0.5`/`ΔmAP`/`ΔBuggy@0.5` 的 **9 个配对全部为正**。
  val 侧（`paired_study_analysis.py` → `experiments/cbft_paired.json`）同向，t=+6.99~+12.94。
  ⇒ **原 n=3 的表面模式在 n=9 下成立** —— 「瓶颈在输入表征质量、不在图结构」由线索升为结论。
  ⚠ **边界**：(i) 编码器是在**训练标签**上监督微调，论文须写明；(ii) 只测 ①，② 未做。
  (iii) ~~仍不改正典~~ → **已改正典，见下条（§37）**。
- **★ 2026-09-19 裁定：微调 CodeBERT 升为主设计，冻结降为消融/对比（`decisions.md` §37）**。
  **正典定义变了** —— 这是本仓继 §26（dropout 语义）、§28（`.ravel()`）之后**第三次全量作废重跑**。
  - **正典 `graph_dir`**：`products/<语料>/graphs`（冻结）→ **`products/<语料>/graphs_ft/ss{S}`**（微调，**含划分种子**）。
  - **臂清单变**：删 `cb_ft`（升为正典）、加 **`cb_frozen`**（冻结）；大纲 5.4.2 该项方向反转，对比关系不变。
  - **大纲已先改**（最高权威）：`改II` 共改 **9 段 + 补 1 段**（补的是原先**完全没有**的编码器微调超参）；
    原件备份 `研究点一细化大纲改II.docx.bak-20260919-微调升正典前`。
  - 🔴 **目录改名 `graph_variants/cb_ft_ss{S}` → `graphs_ft/ss{S}`**：因为
    `run_ablation.variants_root_of()` 用「`graph_dir` 父目录 + `graph_variants`」推导变体根，
    沿用原路径会推出 `…/graph_variants/graph_variants`（**全线错位**）。
    历史 config 不改写，另留**兼容软链**保证旧记录仍可解析。
  - 🔴 **连带必修**：正典路径含划分种子 ⇒ **每个开关臂的 `graph_dir` 也必须逐种子取**
    （否则 `seed2` 拿 `ss0` 的编码器配 `split_seed2`）。`canonical_args()` 已把 `graph_dir` 模板化，
    `build_args()` 基线侧与覆盖侧一并展开，开跑前断言用同样展开的参照（否则每个开关臂都被误判"多改一个键"）。
  - 🔴 **`cb_rev`/`cb_unlimited` 的旧变体带的是冻结 `_cb.pt`** ⇒ 会造成**两个变量**。
    新建 `cb_rev_ss{S}`/`cb_unlimited_ss{S}`（`scripts/build_ft_edge_variants.py`，逐图分流：
    三通道未变者软链、被边改动者真跑 M3）。**① `cb_rev` 590/590 软链、`cb_unlimited` 570+20**。
  - 🔴 **顺带测出：`cb_unlimited` 从来不是纯边消融** —— 放开上限后**恰好 20/590 图（② 199/1774）
    的 `_feat.sv`（先验 $s_v$）随之改变**，且与边改变那批**完全重合** ⇒ 边集变化经 M1 回流到节点特征。
    与「稀释」（变量只落在 3.4%/11.2% 图上）是两个**独立**缺陷，引用时都须披露。
  - **正典 run 不重训**：由 n=9 复核产物提升（`runs/cbft_study/cbft_ts{s}_ss{s}` → `runs/seed{s}`，
    `runs/ablation_aug/cb_ft/seed{s}` → `runs/augmentation/seed{s}`），`config.json` 记 `promoted_from`。
  - **归档** `runs/prior_frozen/`（含 README）；`runs/cbft_study/` **原地保留**（它是裁定的证据）。
  - ⚠ **消融 78 run 全部重跑**（① 21×3 + ② 5×3）：正典换了，**每个臂的 Δ 都必须相对新正典重算**。
  - ⚠ **未重跑**：`loss_study`/`prior_dropout_study`/`binary_arm` 的基线仍是冻结正典 ⇒ 结论须标注工作点（已知开口）。
  🔴 **附带发现：主实验不是逐位可复现的**。冻结臂 `(s,s)` 重跑 vs 正典实测
  Δmicro@0.5 = 0.0000/0.0135/0.0223（**重跑抖动 ≈0.012，约为种子间 std 的 40%**）。
  根因非代码改动（argv 与 batch 组成逐位相同）而是 **CUDA 归约顺序非确定性**（RGCN scatter），
  loss 自 epoch 0 起差 ~1e-9，混沌放大后早停落在不同 epoch。
  **本仓目前无任何开关可关掉它**：`--deterministic` 只设线程数与种子，未设
  `cudnn.deterministic`/`use_deterministic_algorithms`。论文局限陈述应收入此条。
- **★ 2026-09-20 统计口径改为「最佳种子」（`decisions.md` §39，用户裁定）**：
  **主口径 = 每语料取正典在 micro-F1@val_thr 上最高的那个种子**（**① seed2 / ② seed1**），
  **正典与全部 21 臂、内测列与 DIVE 列共用同一个种子**；mean±std **降为附录**。
  两条口径与理由写死在 `collect_ablation_results.best_seed_of()` 的 docstring 里。
  ⚠ **代价必须披露**：实测「最佳种子比均值高 +0.0508」≈「3 次纯噪声取最大的期望 +0.85σ = **+0.057**」
  ⇒ **那 +0.05 基本全是选择膨胀、不是模型能力**；据最佳种子下「某干预有效」的结论**依然禁止**。
  产物：`eval_results/ablation/collected{,_aug}.md`（表 A′/B′）、`eval_results/dive/comparison.md`
  （表 1′.{micro@0.5,micro@val_thr,macro@0.5,mAP}）、`experiments/per_class_three_caliber_tables.md`
  （**表 1–6 最佳种子 / 表 7–12 mean±std**）。
- **★ 2026-09-20 SolidiFI 层次二完成（`decisions.md` §40）**：
  新增 `scripts/map_solidifi_injections.py` + `scripts/evaluate_node_localization.py`；
  `build_dive_external_set.py` 泛化为 `--dataset {dive,solidifi}`（两者形态一样；SolidiFI 全量 350、不含 dos）。
  🔴 **手册 §10.2 第 9 条的映射规则原文实现出来是错的（已更正）**：日志的 `loc` 是注入**块首行**、
  `length` 是块长 ⇒ 必须按**行域 `[loc, loc+length-1]` 与节点 `[line_start,line_end]` 求重叠**，
  **不能只按单点 `loc`**——单点会命中 **ENTRYPOINT**（实测三类分数 P@5 全为 0；未映射率 **32.92%**
  且带强类别偏差 access_control 0% vs reentrancy 71.3%）。改行域后未映射率 **0.04%**、偏差消失。
  **结果**（随机基线 P@k = **0.1090**，必须先减基线）：$s_v$ 两语料逐位相同（内部一致性 ✅）；
  **$a_v$ 在 ① 上 −0.068（远低于随机）**、② 上 ≈0；$g_v$ 仅 ① 的 k=5 为 +0.023。
  ⇒ 大纲要求的那句必须写：**「图传播未带来额外节点定位收益」**（此处为**负收益**）。
  逐类只有 `arithmetic` 真正有效（$g_v$ 0.416）；`access_control`/`front_running` 三类分数全为 0。
  ⚠ ① 模型在 SolidiFI 上**只有 1/350 个合约预测正确**（② 为 300/350）⇒ 大纲要求的
  「预测正确/错误分开统计」**在此退化**，须如实说明。
- **★ 2026-09-20 ① 主库改进方向诊断（`experiments/improvement_proposals.md`）**：
  6 视角诊断 + 对抗核查（12 代理、36 条建议），承重条目经本人复核并逐条标 ✅/⚠️/❌。最要紧三条：
  (i) 🔴 **① 的编码器微调在还在爬升时被 `--epochs 5` 截断** —— 主口径用的 `ss2` 是
    `best_epoch=5 == epochs=5`，val macro-F1 逐轮单调上升（…→0.376→**0.4365**）、train loss 仍在降；
    而 `cb_frozen` −0.276 / n=9 +0.2466 已证明**表征就是瓶颈** ⇒ 这个瓶颈部件**本身还欠训**；
  (ii) **同划分多种子概率集成实测 +0.019~+0.053（均 +0.033）**，零重训、高于抖动 0.012，
    且是**平均掉**方差（与"挑最好那次"性质相反）；
  (iii) 🔴 **既有消融「关闭 L_var」是构造性空操作** —— λ·L_var 只占总损失 **0.0003%–0.006%**
    （`no_lvar` 臂实测 Δ +0.0045 = 纯噪声），论文**不得**写成"L_var 无作用"，
    须改为「本实验的 λ 取值使该项不产生可测影响」。
  另：大纲 5.3 的 9 个对比方法**一个都没跑**（`eval_results/baseline/` 为空）⇒「0.78 算不算低」目前无法判定。
- **★ 2026-09-19 消融全部重跑完成 + DIVE 外部测试（`decisions.md` §38）**：
  **①②各 21 臂 ×3 种子 = 126 run，0 失败**（② 从原设计 5 臂扩到 21 臂，与 ① 逐臂对齐——
  起因是 ② 那次调用没带 `--only`，结果正合"完成所有消融"，已在 `collect_ablation_results.GROUPS`
  与 `test_collect_ablation.py` 同步；该测试的"非对称"断言随之改为"对齐"）。
  新增每臂**逐类 F1/P/R**（`collected{,_aug}.json` 的表 D/E，随 support 同列，零重算）。
  - **DIVE 外部测试**（大纲 5.1 第六条 / 5.2 层次一）：新增 `scripts/build_dive_external_set.py`
    （五步 stage→raw→M2/M1/PyG→M3→边变体，可重入）与 `scripts/evaluate_external.py`
    （`--matrix {main,aug}`；🔴 **阈值只读源语料 `thresholds.json`，绝不在 DIVE 上重搜**；
    `--selfcheck` 与 `evaluate.py` 对拍实测**逐位一致**）。抽样**不重抽**：沿用 §13 冻结的
    seed=0/n=900（实测支撑 682/378/136/**30**/468/234/246，多标签 68.2%、全零 105）；
    DIVE 实测过滤后 **891/900 图**（逐项见 `products/dive/raw/filter_report.txt`）。
    **编码器矩阵**：图结构只建**一份**，特征建**三套**（冻结 / ① 微调 / ② 微调）→
    `products/dive/graphs{,_ft,_ft_aug}/`；边变体按编码器树各一份。编码器经 `corpus.json`
    硬校验语料归属（跨语料套用不报错、只静默产出错误特征）。
    三方并列汇总 `scripts/collect_dive_comparison.py` → `eval_results/dive/comparison.{json,md}`
    （**禁止跨列比绝对值**，Δ 各减各列自己的正典）。
  - 🔴 **DIVE 结果的两条硬结论**（完整分析见 **`experiments/dive_external_results.md`**）：
    (i) **F1 近乎归零**（① 模型 micro@val_thr **0.0152**、② 模型 0.0614），根因是**类别先验错配**
    （逐类正样本率漂移 **25–43 倍**；模型概率中位数 0.097 vs DIVE 真值 0.346），**不是故障**；
    (ii) **最重要的发现——排序能力也只保住 7.4%**：随机排序器的期望 AP **恰等于该类正样本率**，
    故必须**减去随机基线**才看得见真相：同分布 **+0.693**（mAP 0.7582 / 基线 0.065）→
    跨数据集 **+0.052**（mAP 0.3979 / 基线 0.346）。**只报 F1 会以为问题全在阈值，只报 mAP 会以为问题不大，
    两者都报并减基线才看得见排序本身也大幅退化。**
    (iii) **消融排序不可外推到 DIVE**：① 模型 21 臂在 DIVE 上全挤在 ±0.013 内（正典 std 就是 0.0167）。
  - 🔴 **实测发现：`cb_unlimited` 在①②上都是零功效臂（Δ 恰为 0）**——变体确实不同
    （① 20/590 图边集改变，其中**仅 9 张在池内**；② 199/1774）、两次训练 `best.pt` 与
    epoch-0 loss 确实不同（0.960**3248** vs 0.960**2375**）、`test_probs` maxΔ 0.012–0.051，
    但**预测矩阵翻转 0/322**（差异全落在阈值带内）⇒ **不是 bug，是没有功效**（① 干预面 9/453、
    ② 已在天花板）。论文中该项须写成「**本实验未能检验该问题**」，**不得**读作
    "CALLBACK_RISK 上限不重要"。（叠加 §37.6 已记的两个独立缺陷：稀释 + 非纯边。）
- **2026-09-17 新增运维口径：误报率 / 漏报率（结论卷 §9、`decisions.md` §30）**——
  新增 `scripts/error_rates.py`（只读 `test_probs.pt`，零重训）→ `runs/error_rates.json`；
  纯函数与恒等式由 `tests/test_error_rates.py`（9 例）锁住。**多标签下「误报率」有三个互不相等的定义，必须三层同报**：
  L1 标签对级 / L2 逐类 / L3 合约级——① 主库 test @val_thr 依次为 **2.6% / 逐类 / 2.62%**（旧载 5.1% / 逐类 / 18.3%，
  为冻结编码器口径，已作废），
  ~~**L1 与 L3 差 3.6 倍且方向相反**（少报 ⇒ L1 的 FPR 低、L3 的漏报率高）~~，单报 L1 会得出相反结论。
  > 🔴 **该「3.6 倍」已作废**（2026-09-20 换正典）：新正典下 **L1 2.55% vs L3 2.62%（≈1.0 倍）**，
  > 差的是**漏报侧**（L1 22.2% vs L3 8.0%，**2.8 倍且 L1 更高**）。见 `report_conclusions.md` §9.1。
  > 🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。
  - **恒等式：L3 合约级 ≡ 二分类（"有没有漏洞"）视图**（已固化为测试；与 §2.3.1 独立算法逐位一致）。
    ① 主库合约级：误报率 **2.62%**、漏报率 **8.02%**、二分类 F1 **0.9419±0.0385**（@0.5 为 **3.95% / 6.43% / 0.9435**），
    **远好于七类 micro-F1 0.7110 给人的印象**——差额里约 **2/3 是「把有漏洞的合约报成了别的类」**
    （~~① 的 FP 有 63–65% 落在已有漏洞的合约上~~——🔴 **该比例已按新正典重算为 86–92%**（@0.5 91.7% / @val_thr 85.7%），
  方向不变、幅度更强），**这类错误在二分类里被整类免除**，不是检测能力的差距。
    > ⚠ 本行的旧载值 **18.3% / 30.6% / 0.723**（@0.5 为 0.262 / 0.147 / 0.784）为冻结编码器口径，已作废；
    > 新值出处 `runs/error_rates.json`（2026-09-20 重算，`test_probs.pt` 零重训）与 `experiments/canonical_ft_numbers.md`。
    > 🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。
  - **裁定：不改主任务为二分类**，改为「主表七类 + 并列 L3 合约级」双报（七类提供可操作性与可解释性，
    且 `any()` 一塌即得二分类，反向不成立）。
  - 🔴 ~~⚠ 阈值 0.5→val_thr 是**用漏报换误报**：① 漏报率 6.43%→8.02%（**翻倍**）~~ —— **该条已按新正典改写**：
    误报率 3.95%→**2.62%**、漏报率 6.43%→**8.02%**（仅 1.25 倍，**不是翻倍**），合约级 F1 几乎不动（0.9435→0.9419）。
    结构性问题（阈值搜索目标＝标签对级 micro-F1，而部署代价在合约级）**仍在**：21 个 arm-seed 中 20 个为正、均值错位 **+0.43**。
    > ⚠ 旧载 14.7%→30.6%、0.4256→0.4528 为冻结编码器口径，已作废。新值出处 `runs/error_rates.json` 与 `experiments/canonical_ft_numbers.md`。
    > 🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。
    **候选线索（未验证）**：阈值搜索目标是标签对级 micro-F1，而部署代价是合约级的 → **目标与代价不一致**。
  - ⚠ 三条禁令：不得 L1/L3 互换；不得跨结果集①②比较（② 干净合约仅 23 个）；不得在 n=3 上对差值下「干预有效」。
  - **裁定：合约级二分类是「报告口径」，不是「训练口径」（§9.6、`decisions.md` §30.5）**——
    作为**判据**它更弱：常量预测器（恒报任意一类）就得 **0.620 / 0.930**（真实模型 **0.9419 / 0.9967**，
    🔴 ~~可提升空间只剩 0.10 / 0.06~~ —— **已按新正典重算**：① **0.32**（0.9419−0.6199）、② **0.067**（0.9967−0.9304）。
    **引用时不得再用 0.10**（`report_conclusions.md` §0.5 A3）。裁定本身维持，其依据不依赖该差值；
    旧载真实模型 0.723 / 0.990 为冻结编码器口径，已作废），且七个恒报类得分**逐位相同**（`any()` 对类别身份完全盲）；
    106 个 run 上其 val 阈值曲线平台比 micro-F1 **宽 1.7 倍**、2.8% 的 run 整条曲线不分高下。
    → **早停 / 调度 / 阈值搜索目标一律不改**；原「换阈值目标」候选**关闭**。
    ⚠ **边界**：这只证明**判据**弱，**不**证明"训一个二分类模型"弱（损失≠判据，单头可消掉 4.0%→28.0% 的
    极端不平衡）——该问题**未测**且非零重跑项。
  - 📌 **更正**：「标注/采集成本」这一维**两边都是零**（二分类标签 = `any(targets)`，一行派生；
    `MVD-HG-dataset/{类}_contract/contract_labels.json` 本就是标量 0/1）——既不支持也不反对二分类。
- 已完成：M1–M4；`scripts/` 中 `dataset.py`、`make_splits.py` 已实现（2026-09-12：覆盖约束校正 `--strategy constrained`（默认）+ `coverage_swaps_seed*.txt`、`splits.csv`、split metadata；三种子 C1/C2 构造达标，主种子 seed0）。
- **2026-09-16 第二数据集 `alldata_augmentation` M1–M5 全链跑通（见 `experiments/results.md` §6）**。产物隔离在 `products/augmentation/`、`runs/augmentation{,_dedup}/`；**主库数字与产物零改动**。
  - 语料：池 **1774**（0 精确重复、0 buggy 剔除、0 标签未匹配；全零 362、多标签 2、**单标签**语料），逐类正样本 106–361。**M3 在 GPU 上全量重建**（`--device cuda --force`，1774 图 49 分 10 秒，`cb_reused=0/1774`）。
  - 跨语料契约逐项相等（`D_struct=30`、`struct_layout`、schema v2、role_names），不一致 0 个；节点合计 463,264。
  - **两臂均零泄漏**（连通分量簇原子 0/0/0；近重复去重按构造 0），覆盖校正替换 **0** 次：
    | 臂 | 池 | micro-F1@0.5 | micro-F1@val_thr | macro-F1@val_thr | mAP |
    | --- | --- | --- | --- | --- | --- |
    | **簇原子（正表）** | 1774 | **0.9901±0.0100** | **0.9913±0.0076** | **0.9924±0.0066** | **0.9975±0.0025** |
    | 近重复去重 | 1400 | 0.9102±0.0466 | 0.9468±0.0314 | 0.9475±0.0330 | 0.9846±0.0049 |
    > ⚠ 本表 2026-09-18 按 §28 后的重训结果更正（旧载 0.9739 / 0.9828 / 0.9507 等为坏口径值）。
    > ⚠ **2026-09-20 按 §37 新正典（微调 CodeBERT）刷新「簇原子（正表）」一行**（旧载 0.9347±0.0172 / 0.9547±0.0283 /
    > 0.9602±0.0247 / 0.9804±0.0041 为冻结编码器口径，已作废；新值出处 `experiments/canonical_ft_numbers.md`）。
    > ⚠ **「近重复去重」一行未在本轮刷新范围内**（该臂 `runs/augmentation_dedup/` 产物仍是 2026-09-17，
    > 早于 §37 裁定；`runs/error_rates.json` 也把它列入 `skipped_no_cache`）⇒ 它与上行的对比**不可跨工作点解读**，
    > 引用前先确认口径。
  - **C1 在 aug 上算术不可行**（正样本率 79.7% > 66.7% = s/r，与种子无关），已 `--min-pos-ratio 0` 关闭 C1、保留 C2；
    该语料每类 val/test support ≥8（最低 time_manipulation val 9 / test 12），C1 的目的由数据本身满足。证明与替代方案见 `decisions.md` §22。
  - 计时（`config.json::timing`，跨工具对比用，GPU）：簇原子臂 3 种子 wall 278.0 s / train 220.5 s、graphs/s 633–667。
  - **披露 5 项**（`results.md` §6.7）：去注释源使 `_cb.pt` 文本口径与主库不同；aug 的 M3 在 GPU 构建；单标签语料勿套多标签叙事；C1 关闭；该语料显著更"易"（**0.9901 vs 主库 0.7110**，§37 微调口径；旧载 0.9347 vs 0.4256 为冻结编码器口径，已作废），不能解读为主库问题已解决。
    > 🔴 待复核（2026-09-20 口径变更）：本句结论建立在冻结编码器（micro@0.5 = 0.4256）之上，新正典为 0.7110。见 decisions.md §39。
- **2026-09-15 泄漏处置（见 `experiments/decisions.md` §21）**：主库现行划分的同源泄漏已量化并给出可证零泄漏对照臂。
  - 现行划分跨划分近重复对 seed0/1/2 = **69/68/76**（最高 Jaccard **1.00**）→ §1.2 的微观指标**含泄漏**。
  - 新增 `near_dup_clusters.py --cluster-mode {complete,components}`：`complete`（默认，全链接）报"紧密孪生"；
    **`components`（连通分量）用于划分防泄漏，跨划分近重复对可证恒为 0**（主库实测 0/0/0，C1/C2 仍 7/7 达标，
    分量最大 15）。⚠ §20.2"必须全链接、不能用并查集"仅对**未加 Jaccard 归一化的初版**成立，勿误读为矛盾。
  - **零泄漏对照臂 `runs/neardup/`（划分 `products/alldata/splits/neardup_snapshot/`）**：
    micro-F1@0.5 **0.3446±0.0829**（现行 **0.4256±0.0309**，**−0.0810**）、@val_thr 0.3828（−0.0700）、mAP 0.3301（+0.0254）。
    ⚠ **方向在 §28 修复后翻转了**：坏口径下曾是 +0.0062（结论「泄漏不再是可判定效应」）。正确口径下它**更低**（符合「少泄漏 → 分数更低」的预期），
    但 n=3 且区间重叠（0.3446+0.0829 > 0.4256−0.0309），**不足以判定**，效应量待 n≥9 复核（`results.md` §1.7.3）。
    ⚠ 旧口径（丢弃 80%）下曾测得 −3.9 点，属**已作废**数字（`runs/prior_dropout80/`），不得引用。
    > ⚠ **本段尚未按 §37 新正典重跑**（`runs/neardup/` 产物仍是 2026-09-17）⇒ 括号里的「现行 **0.4256±0.0309**」
    > 是**旧正典**（2026-09-20 起为 **0.7110±0.0389**），且 `−0.0810 / −0.0700 / +0.0254` 三个 Δ 都是相对旧正典算的，
    > **未按新正典重算**，引用前须重跑或显式标注工作点。
  - 审计入口：`python scripts/near_dup_clusters.py --print --audit-split <seed0,seed1,seed2> --audit-out <out.json>`。
- **2026-09-15 M3 设备与缓存加固**：`m3_build_features.py` 新增 `--device {cpu,cuda,auto}`（**默认 cpu，主库路径逐字节不变**），
  GPU 实测 **6.2×**（44.6→7.2 ms/节点）、数值差 max|Δ|=5.6e-05；新增 `cache_usable()`（0 字节残缺文件视为未缓存）
  与 `atomic_torch_save()`（临时文件 + `os.replace`）——**因本机 WSL 整机会重启**（2026-09-15 20:31 腰斩 M3，留下 2 个 0 字节缓存）。
  `train.py`/`evaluate.py` 新增显式 `--label-file`/`--label-key-mode` + 划分内 base 标签硬校验；`train.py` 把
  `label_source`（路径+sha256+key_mode）记入 config；`evaluate.py` 按 CLI→环境变量→**checkpoint 记录**回退，保证同源。
- 已完成（2026-09-12）：M5 主体 `scripts/{metrics,train,evaluate}.py` 落地，train/evaluate/summary 全链路 smoke 通过（`pytest tests/` 现行 **268 passed + 2 skipped**）。
- **2026-09-18 `_cb.pt` 存储膨胀 39 倍已修复并紧凑化（`decisions.md` §33）**：`m3_build_features.encode()`
  原先返回 `[1, seq_len, 768]` 的**视图**（CPU 上 `.cpu()` 是 no-op ⇒ 视图保留整块 storage），
  故每条目按 `seq_len×3 KB` 落盘。**只影响 CPU 构建的缓存**——增强集（`--device cuda` 建的）本就紧凑。
  修复 = `.clone()`；存量 `products/alldata/graphs/*_cb.pt` **15.586 GB → 0.403 GB**（×39，590/590）。
  **值中性三重验证**：逐文件 `torch.equal` + 全库 `verify_channels="all"` 590/590 + `evaluate.py --seed 0` 复算逐位相同
  ⇒ **全部已报告结果继续有效、无需重训**。回归锁 `tests/test_m3_cb_cache.py`（8 例，钉死
  「每条缓存 `untyped_storage().nbytes() == numel*4`」）。
  ⚠ **C 盘可用（2026-09-20 实测 32 GB / 85%）**——该次紧凑化在 WSL 内部释放了 14 GB（`df /` 40G→26G），但 `ext4.vhdx` 非稀疏，
  需按本文件「磁盘空间」的手工步骤（`fstrim` + `wsl --manage --set-sparse`）才体现到 `/mnt/c`。

- **3 种子主实验（2026-09-20 现行口径 = §37 微调 CodeBERT 正典；CUDA/RTX 4070 Laptop）**：micro-F1（主指标，标签对级）固定 0.5 = **0.7110±0.0389**、验证集阈值 = **0.7297±0.0675**；macro-F1（参考）**0.6091±0.0751**（@val_thr **0.4986±0.0452**）；mAP = **0.7582±0.0056**。① 逐种子 micro@0.5 = 0.7273 / 0.6667 / 0.7391、@val_thr = 0.7556 / 0.6531 / 0.7805；val 阈值 = **0.75 / 0.60 / 0.80**。
  > ⚠ **本行 2026-09-20 按 §37 新正典（微调 CodeBERT）刷新。旧载 `0.4256±0.0309 / 0.4528±0.0774 / 0.2503±0.0313 / 0.2621±0.0506 / 0.3047±0.0119` 为冻结编码器口径，已作废。** 池 **453**（正 127、全零 326）、划分、训练超参、参数量 415226 均未变——唯一变量是编码器。权威出处 `experiments/canonical_ft_numbers.md`。
  > ⚠ 本行 2026-09-18 更正（当时口径）。**旧载 `0.8489 / 0.9389 / 0.1469 / 0.2804` 全部作废**——那是 `micro_f1` 的 `.ravel()` 缺陷（`decisions.md` §28）造成的：旧「micro-F1」实为 accuracy，旧 `@val_thr` 是全判负退化解。权威出处 `experiments/results.md` §1。
  > ⚠ **2026-09-16 之前的全部数字（micro 0.8954 / mAP 0.2980 等）已作废**——那是 `--prior-dropout` 实为保留率（实际丢弃 80%）的口径，与大纲 4.1.4 差 4 倍。归档 `runs/prior_dropout80/`，详见 `decisions.md` §26。
- **语料口径**：590 图 → 剔 90 buggy → 池 **453**（正 127、全零 326）。**2026-09-13 的旧数字（581 图 / 池 448 / micro-F1 0.9058±0.0397）已存档于 `runs/prior_448pool/`，两者不可跨口径混用。** 改动与对照臂见 `experiments/decisions.md` §18。
- **2026-09-14 过滤规则修订 + 对照臂**：`generate_all_ast_cfg_dfg.sh` 的 `delegatecall 动态绑定` 规则改为**仅记账、不再剔除**（原规则系统性删掉 SWC-112 访问控制样本本身；恢复 9 个文件、图 581→590、access_control 池级 15→17）；新增 `make_splits.py --include-buggy`（含 buggy 对照臂，隔离到 `withbuggy_snapshot/` + `runs/withbuggy/`）与 `--buggy-policy`；新增 `scripts/near_dup_clusters.py` 近重复簇检测（主库现行划分实测带同源泄漏：seed0 test↔train 17 对、最高 Jaccard 0.98）。阶段 F（消融/基线）与 G（DIVE/SolidiFI）待执行；`alldata_augmentation` 第二数据集的 M1–M5 全链待跑（产物区 `products/augmentation/`）。
- 2026-09-12 目录重构（方案 B）：数据集产物统一迁入 `products/<数据集>/`；脚本默认路径、.gitignore 与文档已同步；`products/{dive,solidifi}/`、`runs/`、`eval_results/{ablation,baseline,dive,solidifi}/` 已建。
- 2026-09-14 并行第二数据集：新增只读源 `alldata_augmentation/`（MVD-HG 论文增强集；1780 扁平 `.sol` + 9026 条 7 维标签），只读源 4→5；新增 `products/augmentation/{raw,graphs,splits}/` 空骨架，产物区 三→四区。**2026-09-16 该集已全链跑通并裁定与主库结果集并存**（见下方 09-16 条目与 `decisions.md` §23）。`MVD-HG-dataset/` 删除后已恢复，审计链与 `docs/data_funnel.md` 保持有效。决议见 `experiments/decisions.md` §19。
- 2026-09-20 七类逐类 F1 三口径对比表：新增 `scripts/collect_three_caliber_tables.py`（纯聚合层，只调 `metrics`，不重实现指标）→ `experiments/per_class_three_caliber_tables.md`。**6 张表 = 3 口径（micro / buggy / macro）× 2 工作点（@0.5 / @验证集阈值）**，46 行 = ① 主库正典 + ① 21 消融臂 + ② 增强集正典 + ② 21 消融臂 + DIVE（①模型/②模型），列 = 7 类 + 汇总，逐类 3 种子 mean±std。🔴 **`macro` 口径与 `micro` 口径的逐类格逐位相同**——macro-F1 就是那 7 个数的未加权平均，**差异只在汇总列**（数学恒等，不是重复计算）。为取 DIVE 的 **buggy 口径**（漏洞子集 `y.any(axis=1)`，DIVE 890 图中 103 张全零 ⇒ 子集 787 张）给 `evaluate_external.py` 增 `buggy_subset_prf`（与既有 `normal_subset_*` 对称的**纯增量**块；标量直接调 `metrics.buggy_f1`，不另写实现），并重跑 `matrix_{main,aug}.json`（446.7 s / 415.7 s）。**复现性核对：154 个逐类 @val_thr 格 + canon 全部 micro/macro/逐类 F1 + `subset_accuracy` 与 09-19 旧产物逐位相同。** 三口径定义与「buggy ≠ 合约级二分类 F1」的区别见 `decisions.md` §41。
- 2026-09-20 ⚠ **发现：DIVE 外部测试的 `mAP` 不可逐位复现（F1 可以）**。同条件重跑 canon，`mAP` 三次分别为 **0.410013975660806 / 0.410031329647214 / 0.410030999738092**（末 4–5 位漂移 ≈1.7e-5），而同一批 `micro_f1` 逐位相同、154 格逐类 F1 全对。判定为 **GPU 推理（PyG RGCN 的 scatter/atomicAdd）末位不确定**：阈值化后的 F1 对该级扰动稳健，AP 用概率全序、不稳健。⇒ **引用 DIVE 的 mAP 须声明是单次运行值**；`eval_results/dive/comparison.{json,md}` 已按新矩阵重生成（canon mAP 均值 0.397876→0.397866，显示精度下不可见，F1 未变）。详见 `decisions.md` §41.4。
- 2026-09-21 改进方案第一轮（`experiments/improvement_round1_results.md`、`decisions.md` §42）：**P0/P1/P3 完成，P2 按用户裁定挪到任务2 之后**。① **编码器 epoch 探针**（`runs/codebert_ft_probe/ss2/`，隔离）：val macro-F1 在正典 `--epochs 5` 上限处 **0.4365**，跑到 12 轮 **0.6149（+0.178，+41%）仍未收敛** ⇒ ① 的编码器**在收敛路径中段被截断**，这条直接改写任务的 epoch 预算。② **Slither 基线**（`scripts/baseline_static_tools.py` → `eval_results/baseline/`）：590 图成功 **560**、test 覆盖 **45/46**，test micro-F1 **0.4547**（0.4776/0.4348/0.4516）、macro 0.2937 ⇒ 「0.78 算不算低」**有了参照系**（本文方法高 0.26–0.28，是重跑抖动的 20 倍以上）；`front_running` 的 0 是**映射边界**（Slither 无 SWC-114 检测器），不得读作"工具在此类 F1=0"。其余 5 个传统工具为 py2/3.6 时代归档项目、本机无 docker，**标注环境不可用**。③ **多种子集成**（`scripts/ensemble_eval.py`）：独立复算与提案逐位一致，**+0.0329**（ss0/1/2 = +0.0527/+0.0274/+0.0187）；⚠ 相对**最好单模型**是 **−0.016**（集成打不过事后挑最好的那次），两者必须并列报。④ **`--deterministic` 修好**：原实现只设线程数与种子、CUDA 一个开关都没设，补齐四条后 `best.pt`（17 张量）与 val 概率**逐位相同**。⑤ **bootstrap/加权 macro**（`scripts/oof_bootstrap.py`）：micro-F1 的 95% 区间宽 **0.29–0.40** ⇒ 在 46 合约/21 正标签对上 **0.65 与 0.78 统计上不可分**；test 上 support≤2 的类有 **4 个**（arithmetic/dos/front_running/time_manipulation），剔除后 macro 由 0.4841 抬到 **0.8472**。⑥ 新增机检：`tests/test_baseline_static_tools.py`(13) + `test_oof_bootstrap.py`(5) + `test_ensemble_eval.py`(3) + `model.py` 的四算子/关系盲判据；全套 **290 passed**。⑦ 🔴 **第三次踩同一个 `.gitignore` 洞**：字面量规则匹配不到新前缀目录，`git add -A --dry-run` 实测 **42 文件 / 958.5 MB**（两份 475 MB 的 `pytorch_model.bin`）⇒ 规则改用前缀通配（`graphs_ft*` / `codebert_ft*`），修后 **34 文件 / 1.02 MB**；AGENTS.md 记明「(b) 步是唯一能兜住字面量失效的一步」。
- 2026-09-21 **任务2：`buggy_*` 补回池并重划（`decisions.md` §43，用户裁定「进池并重划 8:1:1」）**。管道 = `scripts/run_buggy_canon.py`（变体→训练→评测→diagnose→聚合，4 条硬前置）。产物**全部另开目录**、§37 正典零改动：`products/alldata/splits/withbuggy_snapshot/`（池 **497**，train/val/test = 398/50/49，**与既有快照逐字节可复现**）、`runs/codebert_ft_buggy/ss{S}/encoder/`（epoch 预算 5→16，依据 = epoch 探针）、`products/alldata/graphs_ft_buggy/cb_ft_ss{S}/`（M3 重编码；`_feat.pt` 与正典 590/590 逐位相同、`_cb.pt` 590/590 全不同）、`runs/buggy_canon/seed{S}/`。**全 test 结果（3 种子）**：micro@0.5 **0.9251±0.0552**、micro@val_thr **0.9404±0.0276**、mAP **0.9662±0.0220**；训练 wall 7.5/9.3/7.1 s、编码器微调 2497/2612/2474 s。🔴🔴 **最重要的发现：这些涨分绝大部分不是检测能力、是标签假象**——test 49 个合约里 **7 个是 `buggy_*`（占 14%）**，标签是**七类全 1**（§18.4），模型「全报有漏洞」即可拿满分。新增 **`clean_only` 诊断口径**量化：剔掉这 7 个后 micro **0.9404→0.7968**、macro **0.9351→0.4065**、mAP **0.9662→0.7307**，与 §37 旧正典（0.7297/0.4986/0.7582）**基本持平** ⇒ **「补回 buggy 提升检测能力」不成立**；第二条独立佐证 = 编码器 val macro-F1 轨迹在旧预算第 5 轮处 **0.4365 → 0.8985**（该指标同时是编码器的选 epoch/调 lr/早停判据 ⇒ 假象也污染了模型选择）。⚠ 两条口径限制：`clean_only` 的 macro 被零支撑类（`time_manipulation` support→0）人为压低、**只有 micro 的 Δ 是干净的**；新旧 test 不是同一批合约、**看方向合理看小数位不合理**。**最终口径须作者裁定**（与 §40.4 的 GCN 负面结果同性质）。产物：`experiments/per_class_three_caliber_tables_buggy.md`（12 张表）+ `experiments/buggy_canon_summary.md`。
- 目录与状态详情见 `项目组织架构.md` 末节。
- 2026-09-21 **大纲 `改II` 5.3 对比实验按原文重列：基线 = 六个传统工具 + EGFL + MVD-HG/MANDO-LLM，不含 CodeBERT 序列、也不含 GCN/GAT/SAGE**（用户指出 5.3 已改为「类似的论文」而非通用 GNN 算子）。
  权威原文（大纲段落 [400]–[411]）：`Securify、Mythril、Slither、Manticore、Smartcheck、Oyente` → 静态传统工具对比；`EGFL` → 验证异构图边类型是否必要；`MVD-HG、MANDO-LLM` → 基线；`本文方法` → 完整方法。附 [411]「所有基线均按多标签任务统一训练和评估……均输出七维 logits，并使用 `BCEWithLogitsLoss` 训练」与 [395]「5.3 全部对比方法均在两种设定下评估」（MVD-HG 内部测试 + DIVE）。
  ✅ **同日作者四条裁定并已落地**：(1) 基线名全局 **`MANDO-HGT` → `MANDO-LLM`**——本仓**代改了 `研究点一细化大纲改II.docx`**（4 处，段落 [43]/[46]/[65]/[67]；替换后 500 段落/18 表格/14 部件完好、全部 XML 可解析、zip 无损，权限位保持 755；备份 `/tmp/outline_backup.docx`，git 亦可回滚）。⚠ **遗留语义问题**：段落 [65] 行表头是「异构图GNN」、[67] 写作「MANDO-LLM 等异构图方法」，把 LLM 方法归入异构图 GNN，**分类标签须作者复核**；(2) **`SCVHunter(2024)` 不纳入 5.3**（仍留在大纲相关工作的异构图一行，那是文献综述、不是基线表）；(3) 三个论文基线（EGFL/MVD-HG/MANDO-LLM）**已由作者安装在 `/home/saumarez/projects/deep-learning`**——🔴 **该路径在本仓「只能读取 SSM-HG」硬边界之外**（本文件 §数据边界 + AGENTS.md），接入方式待确认；(4) 关系盲算子族**保留**（裁定「有 F1 结果则保留」，实测 GCN/GAT/SAGE + 4 个 `*_pm` 全部有完整 micro/macro/mAP），作 §40.4 附录证据、不入 5.3。
  **同步的六处**（此前均按旧设计写）：`论文开发手册.md` §10.6 基线表（改为按大纲逐行的表 + 本仓现状列）、同文件 §9 的 `conv_type` 说明与 §12 常见错误第 26 条、`Todo_List.md` 新增 **§12.7.1「5.3 对比实验（现行）」**并改掉 4 处旧描述（267/372/421/452 行）、`项目组织架构.md` 的 `eval_results/baseline/` 说明与 `arch_n9` 说明、`AGENTS.md` 的 n=9 产物段。**另全仓扫了一遍**把同一错误的残余也改掉：`docs/M5_dev_plan.md`（阶段 F 基线）、`experiments/report_data.md`（F 行）、`experiments/results.md` §3。
  🔴 **顺带更正两处文档缺陷**：(1) 手册原写「实现映射参考 12.8」是**跨文档悬空引用**（手册无 12.8 小节，`Todo_List.md` 才有 §12.8）——已改指；同处原写「RGCN→GCN 仅保留为 5.3 同构图外部基线」与「5.3 基线文字去掉 HGT、只列 CodeBERT、GCN、GAT」**两句都与大纲不符**，已作废并注明。
  ⏳ **须作者裁定四件事**：(a) 大纲**自相矛盾**——5.3 表写 `MANDO-LLM`，正文 [43]/[46]/[65]/[67] 四处写 `MANDO-HGT(2023)`（HGT 系 vs LLM 系，依赖与工作量差别很大）；(b) 相关工作的异构图一行列了 `SCVHunter(2024)`，但 5.3 表未列，是否纳入；(c) 三个论文基线（EGFL / MVD-HG / MANDO-*）的**复现深度**要求；(d) 已跑完的关系盲算子族（GCN/GAT/SAGE 各 n=9、含参数量匹配对照 `*_pm`，`runs/arch_n9*`）保留为附录证据还是弃用。
  基线现状：`slither_alldata` 已跑（其余 5 个传统工具未实跑，Mythril/Smartcheck 装进 conda base 有污染 torch 2.0.1 的风险）；EGFL / MVD-HG / MANDO-* **均未实现**。关系盲算子族**明确不属 5.3**，只作 `decisions.md` §40.4 的内部证据。
- 2026-09-21 **消融 n=9 同配对复核完成 + buggy 新正典消融 + 三处静默错误修复**（`decisions.md` §44/§45）。用户裁定：「**消融按新跑的来，但原来的结果不要删，且同步记录到组织架构中**；三个论文基线在别的会话做，本对话只做消融实验并记录结果」。
  **A. n=9 网格**（`runs/ablation_n9{, _aug}/`、`runs/arch_n9/`）：`ts × ss` 3×3 = **9 对**同配对，**只补非对角 6 对**——对角复用 `runs/ablation{,_aug}/`，① 的 9 对基线复用 `runs/cbft_study/`（论文正典 `runs/seed{S}` 即其对角提升而来）。**复用合法性是实测的**：`run_ablation_n9.reuse_violations` 逐 run 逐键对拍旧 `config.json`，3/3 逐位一致。**跑批结果：新跑 255 run、wall 192.3 min、失败 0**；buggy 那批 **63 run、0 失败、24.4 min**。
  🔴 **结论**：① 21 臂里**只有 2 个存活**——`cb_frozen`（Δmicro@val_thr **−0.3077**，t=−10.13，**六个指标全过 Bonferroni**，0+/9−）与 `no_prior_drop`（−0.0290，t=−2.55）。**6 个臂符号翻转**，再按重跑抖动（0.012）分档后**只有 4 个是实质翻转**（`cb_node_only`/`cb_func_only`/`hid256`/`layers1`）、2 个在抖动内（`meanpool`/`no_lvar`）。**架构基线族三个算子全不显著**（t=+0.95/+0.65/−0.28）⇒ §40.4 那个 n=3 的 GCN 读数是**噪声**。**参数量匹配对照**：`gcn_pm`/`gat_pm` 参数量对齐后仍**显著更差**；🔴 **`hid256` 的增益在对齐参数量后反转为显著为负**（−0.0548★）⇒ 那是**容量效应、不是宽度效应**（§12.4 第 3 项开口就此闭案）。`numbases3` 的 Δmacro@0.5 −0.0929（6+/3−）是唯一新线索，但参数量 0.842× ⇒ **与容量混淆，不得解读**。L_var 剂量臂（λ×10/×100/×1000）全部不显著，与"λ·L_var 只占总损失 0.0003%–0.0054%"一致。**② 增强集**：基线饱和在 **0.9869/0.9856**（mAP 0.9948），21 臂 |Δ| ≤ 0.01，**唯一可读的是 `cb_frozen` 仍显著为负**（−0.0320，t=−4.67，六个指标全过 Bonferroni）；该组机械判据会报 9 个"翻转"，加抖动判据后**只剩 `numbases3` 一个**，其余 8 个是噪声朝向。
  **B. buggy 新正典的 21 臂**（`runs/ablation_buggy/`）：填充 `experiments/per_class_three_caliber_tables_buggy.md` —— **22 行（1 正典 + 21 臂）× 12 张表，0 空行**。前置两件：给 `build_ft_edge_variants.py` **新增 `--layout buggy`**（边变体源与冻结树与 §37 共用同一份，产物 `variant.json` 与 §37 版**只差 `derived_from` 一个键**；`_cb.pt` 三方比对证明各带本语料编码器）；`run_ablation.py` 补 diagnose（见 C2，**这是该修复第一次实际受益**）。**结果：只有 `cb_frozen` 有实质效应（−0.2205），其余 20 臂 |Δ| ≤ 0.03 而正典种子间 std 已达 ±0.0552** ⇒ 该正典处于**标签假象饱和区**（`buggy_canon_summary.md` §3），**消融行只可作申报口径呈现，不得用于任何"某组件重要/不重要"的结论**。
  **C. 修掉三处「不报错的错」**（全套测试 **317 passed + 2 skipped**）：(1) 🔴 `run_ablation.canonical_args` 的逐种子模板化正则 `(.+)/ss\d+` **认不出新正典的 `cb_ft_ss{S}`**，会让 **seed1/2 静默拿到 ss0 的编码器**——正是 AGENTS.md 点名的「本仓第三次全量作废的根因」同型；改为保留前缀的正则 + 回归锁（含"展开后三种子必须不同"）。(2) 🔴 `run_ablation.py` 链条**缺 diagnose**：`test_probs.pt` 只由 `diagnose.py` 写、`evaluate.py` 不写，而三口径表/误报率**只读这个缓存** ⇒ 缺了不是报错而是**整列变 `—`**；已补，且 `resume_state(require_probs=True)` 只补那一步不重训（默认 `False` 以免 `run_study` 那条链的判据漂移）。(3) 中文 f-string 嵌 ASCII 引号（**本日第四次**）⇒ 新增 `tests/test_all_scripts_parse.py`：全仓逐文件 `ast.parse` + **自证测试**（喂已知会炸的样本必须报错）。⚠ 我前两版守卫（数引号 / 扫 token）**实测都无效或误报一片**，已否掉，不留假守卫。
  **D. 一处读法纠正（重要）**：报告的 `同号` 列里 **`Δ 恰好为 0` 不是「干预没作用」**——实测 ① 全部 **35 个 `=0` 配对（横跨 13 个臂）**两侧的 `test_probs.pt` **都逐位不同**（`no_prior_drop` 0:0 最大差 4.9e-2、322/322 元素全变）。成因是**指标性质**：mAP 只看**排序**且本仓逐类 AP 是**很粗的有理数**（support 个位数），阈值型指标只要无元素跨阈就完全相同 ⇒ **不同概率可以给出相同读数**。已改注释与报告抬头，并同步纠正 §44.5。
  **E. 两代并存（用户裁定）**：n=3 的 `runs/ablation{,_aug}/`、`experiments/ablation_results.md`、`eval_results/ablation/collected{,_aug}.{json,md}` **原地保留、不覆盖**；n=9 另开目录 + 另出报告（`experiments/ablation_n9_results.md`、`eval_results/ablation/n9_summary.json`）。**两代不打架**：n=9 的对角 3 对**就是 n=3 的同一份物理产物**。两份旧报告已加指向 n=9 的指针并注明"n=3 保留"。已同步 `项目组织架构.md`（产物形态、三个正典对照表、`.gitignore` 说明、experiments 清单、测试计数）、`AGENTS.md`、`论文开发手册.md` §12 错误 55/56、`Todo_List.md` §12.8.2/12.8.3。
  **F. 一处取舍（待作者确认）**：`runs/ablation_buggy/**/best.pt` 按本仓对 n=9 那批的**同一条裁定排除出库**（约 315 MB）；⚠ 该批**没有**"对角另有完整备份"的兜底，故 63 个 run **全部**不能从零重跑 `evaluate.py`。若要连权重一起入库，须改回 `.gitignore`。
- 2026-09-22 **5.3 三条论文基线（EGFL / MVD-HG / MANDO-LLM）接入并跑出结果**（`decisions.md` §46、计划仓库版 `docs/baseline_dev_plan.md`、交付物 `experiments/baseline_three_caliber_tables.md`）。
  **背景**：大纲 `改II` 5.3 点名三条基线，`Todo_List.md` §12.7.1 全标 ⏳ 未实现。三份只读调查的结论：三个仓库**没有一个是多标签**（EGFL `Dense(1)` / MVD-HG `Linear(8→1)` / MANDO-LLM `Linear(128→2)`），**base 环境三个都跑不起来**（要 TF1.15 / dgl / gensim 3.x），**三个都没有可用预训练权重**。大纲 [411] 已定死「均输出七维 logits + `BCEWithLogitsLoss`」⇒ 必须改造 + 从零重训。
  **用户三条裁定**：① **路线 2**（MVD-HG 驱动原仓库代码忠实复现 + EGFL/MANDO-LLM 按论文重实现）；② **不新建 conda 环境**，base 改造；③ 对比实验喂**去除 `buggy_*` 的数据集**、EGFL 走**原生字节码模态**。
  **数据口径（硬证据）**：「去除 `buggy_*`」**就是 §37 正典本身**——`withbuggy_snapshot`（池 497）删 44 个 `buggy_*` 后与 453 **集合级恒等**，逐类正样本同为 `[17,15,6,4,31,5,50]`。🔴 **不得**用「497 删 buggy 行」代替（那份在 497 上重打过乱，test 会换人）。
  **新增 8 个脚本 + 1 个测试**：`baseline_common.py`（共用层：训练/评估/产物/守卫/设备/solc 候选/覆盖率剔除）、`baseline_models.py`（三个模型纯 `nn.Module`）、`baseline_mvdhg_build.py` + `baseline_mvdhg.py`、`baseline_egfl_build.py` + `baseline_egfl.py`、`baseline_mando.py`、`run_baselines.py`（子进程驱动）、`collect_baseline_tables.py`（**零重实现**：逐类格与汇总列一律走 `collect_three_caliber_tables.render_table`，support 走 `support_block`、薄支撑警告走 `_thin_support_note`）、`tests/test_baseline_tables.py`（20 条契约守卫）。产物落 `eval_results/baseline/<name>/seed{S}/`，**形制与 `runs/seed{S}/` 逐项相同** ⇒ 汇总链可直接读。
  **实测覆盖与口径损失（必须随结果披露）**：MVD-HG **448/453（98.9%）**，5 个失败样本**全在 train**（seed2 另有 1 个在 val）⇒ **test 一个没少**（46）；EGFL **453/453（100%）**；但 EGFL **83.2% 的合约被截断到 `seq_len=512`**（池内 token 数中位数 **3118**）——它的注意力是**稠密 O(L²)**，本机 8 GB 卡实测 L=512 → 2.5 GB / 0.16 s 每步，**L=1024 就溢出到共享显存**（9.9 GB、7.75 s 每步），原论文 `SEQ_LEN=8000` 在这张卡上任何实现都跑不动。**这是硬件逼出来的口径损失，会系统性压低 EGFL。**
  **修掉 9 个「不报错、只出错数字」的坑**（详见 `docs/baseline_dev_plan.md` §5）：① 27/453 合约「编译失败」的真因是**文件中段还有第二条精确 pragma**，而候选列表被截断在前 8 个（改全量回退）；② 词向量只用 train 拟合 ⇒ 非 train 才出现的 AST 节点类型 `KeyError` 崩整轮（改零向量兜底 + 计数，实测仅 6 个节点）；③ 8/453 EGFL `ValueError: non-hexadecimal` 的真因是 solc 对**未链接库**写占位符，且 **0.4.x（`__<限定名>__`）与 ≥0.5（`__$hash$__`）是两种写法**（锚 `__…__` 骨架、按原长替 0 保持字节偏移）；④ EGFL 的截断计数器在**截断后**取长度 ⇒ 永远报「0% 被截断」（一个只会说谎的计数器）；⑤ `to_hetero` 桶号反解把源/目标类型**写反**（GPU 上表现为一句 device-side assert）；⑥ JSON 把 tuple 还原成 list ⇒ `HGTConv` 报 `unhashable type: 'list'`（读回必须转 tuple）；⑦ MVD-HG 的 `config.py` 在 import 期写死 `CUDA_VISIBLE_DEVICES="0,1"`（本机单卡）⇒ 快照+还原 `os.environ`；⑧ 🔴 **跨进程环境污染**：父进程 `import torch` 后子进程集体 rc=1 并报 `MKL_THREADING_LAYER=INTEL is incompatible with libgomp`——**报错完全指向 MKL、与真正根因无关**，同一条命令手工跑却正常（修法 `subprocess.run(..., env=dict(os.environ))`；`env=None` 连跑 5 次全 1、显式 env 连跑 5 次全 0）；⑨ `git check-ignore` 的判据是**打出的规则带不带 `!`**，不是退出码（退出码对白名单命中同样返回 0，只看退出码会把「入库」误读成「已忽略」）。
  **两处必须随结果披露的口径差**：① 🔴 **`early_stop_patience` 基线用 20、本文方法正典用 5**——正典的 5 是为 SSM-HG 调的，实测套到 MVD-HG 上会在 **loss 仍在下降**（2.20→0.64）时于第 14 轮截断、**系统性压低基线**；② **batch 配置逐行不同**：本文方法与 MANDO = 字面 32；MVD-HG 与 EGFL = `4×8` 累积（EGFL 是 OOM 所迫，MVD-HG 为口径一致）。⚠ `4×8` 与整批 32 **不逐位等价**（损失期望相同但 dropout 采样结构不同），该差异未消除。
  🔴 **MANDO 的一个反直觉发现**：它的 HGT 有 **186 种边类型 × 2 层 = 372 次 Python 级小算子调用**，**每步开销与样本数几乎无关**（batch 4 → 4.5 s/步 × 90 步 = **408 s/epoch**；batch 32 → 10.4 s/步 × 12 步 = **125 s/epoch**）⇒ **梯度累积在这里慢 3.3 倍**，必须用整批。这条与 EGFL 的结论（必须累积）方向相反，说明「统一 batch 口径」不能靠拍脑袋。
  🔴 **EGFL 的两臂对照（先报结论，防止误读）**：统一 lr 1e-4 的 `micro@val_thr` = **0.209/0.182/0.209**（均值 0.200，`best_epoch` 停在 0–2、lr 到第 20 轮已衰减到 3.13e-06 ≈ 冻结）；改用**其论文自带的 `lr=0.002`**（`EGFL/parser_set.py:13`，20 倍）后 = **0.222/0.333/0.383**（均值 **0.313**，`best_epoch` 12–15）。⇒ **lr 确是显著压制项（+0.113），但改对 lr 后 EGFL 仍在 0.31 量级** ⇒ 剩下的差距主要归因于 **`seq_len=512` 的截断**与图分支 256 维是重建件。**不得据此宣称「EGFL 方法本身弱」。**
  **`.gitignore` 三步自检全过**（本仓第四次同形态）：新增 `products/**/baseline/**`（只留 `manifest.json`/`hgt_metadata.json`/`opcodes.json` 三个自述件）与 `eval_results/baseline/**/*.pt`（只留 `test_probs.pt`/`val_best_probs.pt`，`best.pt` 排除，与 `runs/**` 同口径）。实测 `git add -A --dry-run` 共 **3341 个文件、最大单文件 0.27 MB、无 >100 MB**；`baseline` 相关 32 个文件逐文件 `check-ignore` 实测。规则一律**前缀通配**。
  **同步文档**：`AGENTS.md`（新增产物形态段 + `check-ignore` 判据更正）、`项目组织架构.md`、`论文开发手册.md` §3.2、`Todo_List.md` §12.7.1（三行状态）、`experiments/decisions.md` §46、`experiments/report_data.md` F 行、`experiments/results.md` §3、`docs/baseline_dev_plan.md`（新增）。
- 2026-09-22（补） **5.3 三基线全部跑完，交付物定稿**。最终读数（test，micro-F1@val_thr，3 种子 mean±std；最佳种子口径 = seed2）：
  | 行 | micro@0.5（3 种子） | micro@val_thr（最佳种子 seed2） | 参数量 | 训练成本 |
  | --- | --- | --- | --- | --- |
  | 本文方法（§37 正典） | **0.7110±0.0389** | 0.7391 | — | — |
  | Slither（传统工具，**分母不同**） | 0.4547±0.0216 | 0.4516 | — | 规则工具，无训练 |
  | MVD-HG | 0.4052±0.1125 | 0.3077 | 0.088 M | 4.9 s/epoch，137–213 s/种子 |
  | EGFL（其论文 lr=0.002） | 0.3068±0.0731 | 0.3830 | 2.787 M | 9.9–12.1 s/epoch，214–281 s/种子 |
  | MANDO-LLM | 0.1908±0.0529 | 0.1509 | 3.075 M | 76–81 s/epoch，1904–2915 s/种子 |
  | EGFL（统一 lr=1e-4） | 0.0697±0.1206 | 0.0000 | 2.787 M | 同上 |
  MANDO 三种子以 `batch_size=32`（字面整批，非累积）跑完，共 6879 s ≈ 1.9 h。
  🔴 **一处必须随结果披露的读法**：**本表不得读作「本文方法优于这些方法」**——三条基线各自带着已声明的、量级不同的损失（EGFL 被 8 GB 卡截断到 `seq_len=512`、池内 83.2% 合约受影响；MVD-HG 缺 5 个训练样本；MANDO 用 PyG `HGTConv` 替 dgl 且图取我方 CFG 中心异构图而非原版 slither 图），且三者的输入模态、图定义、节点特征来源**各自不同**。表头已逐行写明「**不是原作者的二进制**、**不得声称复现了作者原结果**」。
  🔴 **关于「要不要改成二分类」的裁定依据（2026-09-22 用户提问）**：**不改**。实测同一测试集上**平凡分类器**（一律报"有漏洞"）的得分 —— 七维多标签 micro-F1 **0.1224**（322 个标签格里只有 21 个正例），合约级二分类 F1 **0.6269**（46 个合约里 21 个有漏洞，**45.7%**）⇒ 换成二分类等于**白送约 +0.50**，与检测能力无关。仓库既有的同配对研究（`runs/binary_arm/`，9 对，注意它用的是**冻结编码器** `graphs` 而非正典 `graphs_ft`）读数 binary 0.7807 vs multi 0.4486；**扣掉平凡下限后的净技能反而 multi 更大（+0.326 vs +0.154）**。另：大纲 `改II` [411] 原文即禁止单标签（「传统模型也输出**七维**规则命中结果，**而不是单标签类别**」），按 AGENTS.md 权威顺序大纲为第 1 位。⇒ 结论：**主表保持七维多标签**；二分类按既有设计（`--head binary`，`decisions.md` §31）只作附录。建议的替代做法 = 给表加「平凡下限 / 净技能」列（待用户定夺）。
- 2026-09-23 **三条基线读数为何远低于各自论文的「90 多」——逐篇核对论文后结案**（`decisions.md` §48）。
  用户提问：「这三个工具指标太低，提升指标让数据好看些，或给出理由，因为它们各自论文里 F1 都到了 90 多」。
  **做法**：派三个子代理分别读三篇 PDF（`EGFL/*.pdf`、`MVD-HG/*.pdf`、`MANDO-LLM/*.pdf`），逐条抽取任务定义/指标定义/数据集规模/划分/阈值与模型选择协议；关键断言**本地复核**（如 SMOTE 那一条亲自读了 `EGFL/main_run.py:107-116`）。
  🔴 **结论一：三篇论文没有一篇是多标签**，全部是「**每类漏洞各训一个独立二分类器**」——EGFL 6 类（逐类 83.67–90.47，**平均 87.32**）、MVD-HG 7 类（合约级 **0.9056–0.9559**）、MANDO-LLM 7 类（合约级 **86.65–97.06**，指标名 `Buggy-F1`）。而大纲 [411] 强制本仓按**一个模型 7 维多标签**评测。
  🔴 **结论二：每一篇都含至少一条会抬高数字、而本仓明确禁止的做法**——EGFL：**官方代码对训练集与评测集都做 SMOTE**（`main_run.py:107-116`，论文全文无 SMOTE 字样），且 `ModelCheckpoint(monitor='val_acc')` 就在同一集合上选模型；MVD-HG：**分类阈值在训练集上搜**（`contract_classification_train.py:86`，准则 = P+R+Acc+F1 之和最大）且无验证集，数据划分还在 `while True` 里反复重采样；MANDO-LLM：合约级把 clean:buggy **人为平衡成 1:1**（论文脚注自陈「这正是 Macro-F1 与 Buggy-F1 接近的原因」）；三者都**没有独立测试集**（80/20、70/30、5/10 折 CV）。
  🔴 **结论三：支撑度量级差 10–100 倍**（`decisions.md` §48.6.3）——MVD-HG 单类数据集的正例数（88–190）**比我们整个 453 池里该类的正例数（4–50）还多**；我们 test 里 `dos`/`front_running` 各只有 **1** 个正例（单类 F1 一次翻转差 0.67）。
  ⚠ **本条已作废（2026-09-23，见下方同日条目与 `decisions.md` §51）**：88–190 **不是**「MVD-HG 单类数据集的正例数」，而是 `<类>_contract/sol_source/` 的**语料文件数（正+负）**——论文 Table 1 自述的「Contract-Origin files」逐类 **114/120/92/88/142/100/190** 即此，**论文从未把它写成正例数**。其每类正例是 **57–95（含 40–45 个 `buggy_*` 全 1 注入样本）**，**剔除注入样本后 = 17/15/6/4/31/5/50，与本仓逐类相同**。⇒「支撑度量级差 10–100 倍」**不成立**；使数字真正不可比的是**评测协议**（结论二）与**语料是否含注入噪声样本**，不是支撑度。本节其余三条结论不受影响。
  🔴 **结论四：量化「任务口径」这一项**（同测试集、同一份产物，只换怎么算分）——平凡分类器（一律报「有漏洞」）在**七维 micro** 上是 **0.1224**（322 个标签格里 21 个正例，6.5%），在**合约级二分类**上是 **0.6199**（46 个合约里 21 个有漏洞，45.7%）。**两个口径的地板相差 0.50**。
  **据此新增交付物一节（§3 合约级二分类口径）**：把每行的 `test_probs.pt` 按 `max_c p_c ≥ t ⇔ any_c p_c ≥ t`（§31 已机检）坍缩到合约级，**不重训**。结果：**本文方法 0.9419**（净技能 **+0.3219**）、MVD-HG 0.8188（+0.1989）、**EGFL 0.6199（±0.0000，三个种子都把 46/46 全判为有漏洞，退化成常量预测器）**、**MANDO-LLM 0.6178（−0.0021，打不过平凡分类器）**、EGFL(论文 lr) 0.5254（−0.0946）。
  ⇒ **「让数据好看」与「讲清楚为什么低」是同一件事**：换成各论文的原生口径（合约级二分类）后，本文方法正好落在各论文自称的区间，而两条基线在该口径下**不高于平凡分类器**。
  **EGFL 的 `seq_len` 提升路径实测关闭**：注意力模块本身是 O(L²)，实测 L=512 占 **2.45 GB**、L=1024 占 **9.77 GB**（溢出到共享显存、慢 8 倍）、L=2048 **OOM** ⇒ 8 GB 卡上做不到，不是调参问题。
  **另记**：`/tmp/.x`（子代理抽 PDF 时误落的 93 KB 临时文件）已清理；`MVD-HG-dataset/` 实际位于 `SSM-HG/` 下而非 `deep-learning/` 根（两者都在允许边界内，AGENTS.md 写法不算错）。
- 2026-09-23 **5.3 对比表新增「逐类二分类 F1（binary-F1）」口径与全口径总览**（`decisions.md` §49；交付物扩到 **16 张表**）。
  用户要求：「记录本文方法 / MVD-HG / EGFL（统一 lr）/ MANDO-LLM 在 **7 类漏洞 + 平均** 上的 binary-F1 表（8 列），解释什么是 binary-F1；并检查有哪些好看的分数（buggy/micro/macro 等）可以放，好看就也列一张表；完成后修改项目组织结构、同步没记录的文件」。
  **做成两件事、共 3 张新表**（全部零重训，读同一批 `test_probs.pt` / `val_best_probs.pt`）：
  **① 表 1 = 逐类 binary-F1 @逐类验证集阈值**（行 = 本文方法 / MVD-HG / EGFL / MANDO-LLM + EGFL 论文 lr 臂 + Slither，列 = 7 类 + 平均）。
  平均列：本文方法 **0.6363±0.0919**、MVD-HG **0.3224±0.0795**、EGFL（统一 lr）0.1138±0.0101、MANDO-LLM 0.1091±0.0366、EGFL（论文 lr）0.1369±0.0425、Slither 0.2937±0.0111。
  **② 表 2 = 方法 × 8 口径汇总列总览**（选口径用，末列标出每行的最高口径）：本文方法最高 = **合约级 binary 0.9419**，其次 buggy@val_thr 0.7455、micro@val_thr 0.7297。
  **③ §4.1 的 binary-F1 定义 + 两条恒等式**：多标签评测里的「第 c 类 F1」**本身就是**该类的二分类 F1（同一个混淆矩阵、同一个公式），两个口径**唯一的分歧在判决规则**（七类共享一个阈值 vs 每类各一个阈值 $t_c$）。⇒ **@0.5 的 binary-F1 逐位等于三口径表的逐类格、其平均列恒等于 macro-F1@0.5**（故 @0.5 版**不另列**，那是同一批数字的第二次排印）；本块**唯一新增的信息**是「阈值逐类独立」。**「平均」列 ≠ micro-F1**（前者逐类等权、后者标签对加权，实测可差 0.10 以上）。
  🔴 **零重实现 + 逐位对拍**：阈值搜索**复用 `calibrate.per_class_thresholds`**（本仓 per-class 阈值的唯一实现），逐类 F1 走 `metrics.per_class_prf`；本文方法那一行与**存量审计产物** `eval_results/calibration/summary.json::test_schemes.per_class_threshold` **逐位相同**（7 类 + 平均，容差 1e-6），不一致即**拒绝出表**（已实测通过，声明原文落在表 1 下方）。
  🔴 **口径合法性**：per-class 阈值**仅作补充分析、不进主结果**是本仓**早已写死**的裁定（`metrics.py` 契约、`论文开发手册.md` §1223、`Todo_List.md`）⇒ 本节**不是发明新指标**，是把同一口径补到三条基线上。其**过拟合已量化**（同 `gcn_baseline_and_per_class_f1.md` §3）：val 上 `dos`/`front_running`/`time_manipulation` **各只有 1 个正样本**，`dos` 阈值三种子极差 **0.55**、val→test 落差最大 **0.16**。
  **关键读法（对「能不能让数据好看」的回答）**：**换到三篇论文的原生判决规则后，排序不变、量级不变**——低读数**不是**「阈值没调好」。且 **EGFL 两行与 MANDO 行的最高口径读数（0.6199 / 0.5254 / 0.6178）都不高于该口径的平凡下限 0.6199**，即那三行**换成任何口径都打不过「一律报有漏洞」**。
  **建议正文口径**：以 **micro@val_thr 为主、合约级 binary 为辅**（后者用来回答「为什么基线数字低」），buggy 作补充列；**不要只放合约级 binary**——那会被读成避重就轻。
  **代码/测试**：`scripts/collect_baseline_tables.py` 新增 `_pc_pairs` / `_mAP_of` / `_pc_crosscheck` / `per_class_binary_block` / `overview_block`，交付物重排为 **表 1–2 总览 + 表 3–8 最佳种子 + 表 9–14 三种子**；`tests/test_baseline_tables.py` 新增 5 条守卫（**逐类阈值只从 val 取的拦截式验证**、恒等式 ①、与存量产物对拍、表 1 列数、表 2 必带平凡下限声明）。**全量 `pytest tests/ -q` → 344 passed + 2 skipped**（26 s）。
  **文档同步**：`项目组织架构.md`（`eval_results/baseline/` 说明 + `experiments/` 登记本交付物 + 测试计数 317→344）、`论文开发手册.md` §3.2、`decisions.md` §49、`log.md`（本条）。
  **另补登 4 个此前未记录在 `项目组织架构.md` 的文件**（用「逐文件 grep 反查」找出）：`improvement_round1_results.md`、`binary_main_paired.json`、`binary_aug_paired.json`、`gcn_baseline_and_per_class_f1.md`。
- 2026-09-23 **补充臂实测：7 个独立二分类器 vs 正典七维共享——「共享」是承重的，换掉会让稀有类归零**（`decisions.md` §50；交付物 `experiments/perclass_arm_results.md`）。
  用户裁定要跑上一轮提的补充臂。**先自查发现我上一轮的提议是个空操作**：`Linear(64,7)` 与 7 个 `Linear(64,1)` **参数空间恒等**，共享编码器下两者是同一个模型 ⇒ 改成跑**真正有区别的那一版**：**7 个完全独立的模型**（各自编码器 + 各自头）。
  🔴 **零模型改动**：`--head binary` 的标签塌缩只发生在 `dataset.stack_labels` 一处（`any(targets)`），故把标签文件里**除第 c 列外全部置 0** 即得该类专属二分类器 ⇒ 复用已单测的 §31 链路，不新增模型代码。驱动 `scripts/run_perclass_arm.py`；汇总 `scripts/collect_perclass_arm.py`。
  🔴 **本臂唯一的「只会说谎、不会报错」的坑已被兜住**：标签若没生效，`any(targets)` 会退回**全类并集**，7 个臂会**静默变成同一个 any 分类器**且数字看着正常。`--steps check` 逐产物断言「test 正例 = **该类** support ≠ 全类并集」，42 个产物逐条实测通过（如 `front_running/seed0` test 正例 **1** vs 全类并集 **21**）。
  **规模**：7 类 × 3 种子 × 2 个 `pos_weight` 档 = 42 run + 3 个 any 对照 = 45 run（① epoch ≈0.37 s，全程约 20 分钟）。
  **结果（逐类等权平均）**：正典共享 @逐类阈值 **0.6363±0.0919** > @0.5 **0.6091±0.0751** > 独立分类器 `cap=20`@val_thr 0.5258 > `cap=0`@val_thr 0.5045 > `cap=0`@0.5 0.4150 > `cap=20`@0.5 0.4115。
  🔴 **机制（本臂最有价值的部分）**：`dos`/`front_running`/`time_manipulation` 的独立分类器在 @0.5 下 **test 预测正例数 = 0/0/0**（概率中位数 ≈0）——**根本没报过正类**，F1 ≡ 0。根因是这三类在 **train 里只有 4/2/2 个正样本**：专属分类器的最优解就是「全判负」。而共享模型里它们的**排序能力是存在的**（oracle-F1 上限 0.722/0.651）——**那是从另外 6 个类的监督里借来的**（多任务共享 = 正则化）。
  **逐类净效应（同工作点相减，共享−独立）**：@0.5 平均 **+0.198**（`dos` +0.489、`time_manipulation` +0.489、`front_running` +0.167）；@val_thr 平均 **+0.111**（`front_running` +0.509、`time_manipulation` +0.135）。⚠ **唯一反向格必须一并报出**：最大的 `uncheck` 独立反而更好 **−0.084**（35 个训练正例，独立时不受其他 6 类梯度干扰）⇒ 正确表述是「共享在稀有类上决定性、在大类上略有让步」，不是「共享全面更好」。
  **净技能对照**：单头 any 分类器 **0.9335 / 净技能 +0.3136**，与正典七维坍缩 **0.9419 / +0.3219** **在噪声内持平** ⇒ **换单头二分类不带来任何净收益**；「换二分类数字就好看」纯粹是平凡下限从 **0.12 抬到 0.62** 的错觉。
  ⇒ **裁定：不换。** 本臂的正确用途是**防御性证据**——写进论文回答「为什么必须是多标签共享」，比任何调参都值钱。
  **入库自检**：`.gitignore` 新增 `runs/perclass_arm/**/best.pt` + `products/**/perclass_labels/**`（前缀通配，写在 `!runs/**/best.pt` 之后）。三步全过：**345 文件 / 2.1 MB**、最大 <1 MB、**`best.pt` 命中 0 个**、`test_probs.pt`/`thresholds.json` 实测入库、`runs/seed0/best.pt` 仍未被忽略（规则没漏出去）。
  **文档同步**：`AGENTS.md`（新增形态段）、`项目组织架构.md`（scripts 段两个新脚本 + runs 段 + experiments 段）、`decisions.md` §50、`log.md`。测试：`tests/test_baseline_tables.py` 新增 2 条守卫（**逐类标签塌缩的逐条断言**、产物目录不与正典相交）。
- 2026-09-23 **口径澄清：上游类别文件夹的「88–190」是记录数、不是正例数——我们的 453 池一个正例都没丢**（`decisions.md` §51；`docs/data_funnel.md` §3）。
  用户提问：「为什么 MVD-HG 单类数据集的正例数（88–190），经我们改造为多标签后变成 453 池的 4–50？该改回单标签，还是改到补回 `buggy_*` 的 497 池上跑三对比？」
  **核查结论：不是缩水，是两个不同的量在对照。**逐类拆解（脚本 `scripts/audit_data_funnel.py` 新增 `stage_class_folder_vs_labels()`，两条不变量是**硬断言**）：
  ① 文件夹 `.sol` 记录数 114/120/92/88/142/100/190（合计 846，含跨类重复）→ ② 其中非 `buggy_*` 项目键 74/75/52/48/102/55/145（合计 551）→ ③ 上游**自己的**单类标签文件判 **0** 的 57/60/46/44/71/50/95（合计 423）→ ④ 判 **1** 的 **17/15/6/4/31/5/50**（合计 128）→ ⑤ 本仓 453 池正例 **17/15/6/4/31/5/50**（合计 128）。
  🔴 **两条断言**：**②=③+④ 逐类无残差**（文件夹里每个非 buggy 键都被上游明确判过 0 或 1，无「未标注」第三态）；**④=⑤ 逐类恒等 7/7**（本仓池是上游标签的**忠实投影**；标签键走 `scripts/dataset.py` 与训练同一条代码路径）。
  两级虚高来源：①→② 是 45 个 `buggy_*` 项目被**复制进全部 7 个文件夹**（每类 40–45 条，合计 295 条记录）；②→③ 是**文件夹归属 ≠ 标签**——类别文件夹只是源码池，收进来的部署合约被上游自己判为**没有**该类漏洞（access_control 74 个非 buggy 键里 57 个判 0）。
  **两条路都不走**：① **改回单标签** —— §50 已用数据裁定**不换**（单头二分类净技能 +0.3136 vs 七维坍缩 +0.3219，噪声内持平；大纲 `改II` [411] 明文禁止），**且**单标签不改变任何正例数（453 池里 front_running 就是 4 个合约，与输出头形状无关）。② **换到 497 池** —— 多出的 44 个 `buggy_*` 里 39 个标签 `1111111`、5 个 `0100011`，是 §18.4 已量化的**度量假象**（对照臂 macro-F1 0.7043 vs 正典 0.1918）；且 `withbuggy_snapshot` 的 test 重新打乱过（§46.2 警告），换池等于本文方法全部结果重跑。§46.1/§46.2 已裁定三对比走 453 且已跑完。
  ✅ **第二轮（同日晚）：查原论文 Table 1 + 官方代码 `Astronaut-diode/MVD-HG`，未决项结案**（`decisions.md` §51.5）。
  **证据 A（论文自述）**：Table 1「Detailed statistical information about the dataset」的 **Contract-Origin files 逐类 = 114/120/92/88/142/100/190**，与我们本地 `<类>_contract/sol_source/` 的文件数**逐位相同** ⇒ 论文这张表列的就是**语料文件数（正+负）**，**论文从未把它写成"正例数"**——「每类正例 88–190」是本仓 2026-09-23 新写 §48.6 时**自己的误读**。
  **证据 B（官方代码）**：`contract_classification_dataset.py` 按项目目录→逐文件 append `Data` ⇒ **样本单位 = 一个源文件（与我们相同）**，标签取 `{project}_node.json` 的 `contract_label`；`contract_classification_train.py` 为 `split=int(len*0.7)` 的位置切分 + `random.shuffle`（**无种子**）+ 外层 `while True` 重采样直到**四类计数**（`buggy1/clear1/buggy2/clear2`）全非零；**无独立验证集**；阈值在**训练集**搜（末 epoch 的 `get_best_metric`，取 P+R+Acc+F1 之和最大）；`BCELoss`+SGD。⇒ 与 §48.6.2 既有记载一致，且**证明其语料含 `buggy_*`**（否则不会去数 `buggy1/buggy2`）。
  **证据 C（两次独立读数互印）**：类文件夹被类标签文件 **100% 覆盖**（逐类 `未覆盖 0`，标签键数 == 项目数）⇒ **文件夹 = 二分类语料，标签文件 = y**；论文 Table 1 的 **Line-Origin 列 = 57/60/46/44/71/50/95** 恰等于「该类标签判 1、**含** `buggy_*` 的项目数」。
  🔴 **修正后的对照**：MVD-HG 每类**语料** 88–190；每类**正例** **57–95**（其中 **40–45 个是 `buggy_*` 全 1 注入样本**，约占 **70–75%**）；**剔注入样本后 = 17/15/6/4/31/5/50，与本仓 453 池逐类完全相同**。其 70/30 测试集正例约 **17–28**（其中 12–14 个是送分的注入样本），本仓 **1–7**。
  ⇒ ①「支撑度量级差 10–100 倍」**彻底不成立**；② 两篇工作**同源**（同一份底层数据与标注）；③ **新增一条对论文有用的发现**：MVD-HG 正例里约七成是注入噪声样本，这与其 0.90+ 直接相关。
  **5.3 对比节的建议写法**：不写「它的正例比我们多」，改写为「两篇同源；本仓按大纲剔除注入噪声项目，MVD-HG 保留，故其每类正例 57–95 中含 40–45 个注入样本；再加其阈值在训练集搜、70/30 无验证集 ⇒ 其合约级 0.90+ 与我们的七维 micro 0.41 口径不可比」。
  **文档同步**：`scripts/audit_data_funnel.py`（新增一层，两条硬断言）；产物刷新 `products/alldata/splits/data_funnel.json`（新增 `class_folder_funnel` 段）与 `docs/data_funnel.md`（新增 §3，原 §3–§6 顺延为 §4–§7）；`decisions.md` §51 新增 + §48.6.2/§48.6.3/§48.7 口径措辞更正；`experiments/results.md`（表 1.7-a 段补强）；`experiments/baseline_three_caliber_tables.md`（同一处更正）；`论文开发手册.md` §12 新增第 57 条（「把文件夹记录数当正例数」，与第 17 条的**格式混淆**区分开）；`log.md` 本条。
- 2026-09-23（**跨至 09-24 00:48 跑完**）**三条论文基线在「含 `buggy_*` 的新正典（池 497）」上补跑完毕**（`decisions.md` §52；交付物 = `experiments/baseline_three_caliber_tables.md` 新增「三、」段，表 15–28）。
  **用户裁定**：§51.6.2 曾把「换到 497 池跑三对比」判为**不可行**，本次用户明确要求做，范围经确认 = **三条论文基线（EGFL / MVD-HG / MANDO-LLM）+ 其 lr 敏感性臂 `egfl_ownlr` + Slither 一行**，不含另外 5 个尚未接入的传统工具。**本文方法侧零重跑**（`runs/buggy_canon` 早已存在）。
  🔴 **§51.6.2 的两条理由仍然成立**，故**原样进新段表头**：① `buggy_*` 标签绝大多数是七类全 1（§18.4 的度量假象）；② test 是重划过的（46→49）⇒ 与 §37 正典**不可相减**。新段额外并列 **`clean_only` 诊断列**（复用 `dataset.is_buggy_project`，与 `collect_buggy_canon_summary.is_buggy` 同一份实现；实测 test 剔 7/8/7 ⇒ 42/41/42，与既有汇总**逐位吻合**）。
  🔴 **新发现（既存口径不对称，本次未改）**：**canon37 段的三条基线，三个划分种子用的都是 `graphs_ft/ss0`**（十二处 `config.json` 实测），而本仓语义锁死项要求 `ss{S}` 与 `--split-seed S` 配对。**它影响读数**：`_cb.pt` 的 CodeBERT 节点行**逐张量随 `ss` 变**（ss0/ss1/ss2 全不同，跨正典更不同）。本次处置 = canon37 段**原样保留**（重跑会动表 3–14 全部数字），`_buggy` 段一律用**配对的 `cb_ft_ss{S}`**（与 `runs/buggy_canon` 同款）⇒ **两段除了池还差着特征配对方式**，这是「跨段不可比」的第二条理由。**修 canon37 段需另开决议，留待用户裁定。**
  🔴 **本次修掉 5 个「只出错、不报错」的坑**（§52.4），其中第 1 个是**实测踩到**：`baseline_mvdhg_build.ensure_layout()` 漏改正典后缀 ⇒ **497 池的 44 份 AST 被编译进正典根**（88 个新文件），而 `_assert_under_feature_root` **自己也在查正典根**故一路放行。已删除那 88 个文件并复原 5 个空目录（正典根实测回到跑前状态：`AST_json` 453 目录/448 json、`sol_source` 453、`feat` 448、`manifest` 453），并新增**源码级守卫** `test_all_feature_root_calls_pass_the_suffix`（AST 扫 5 个脚本，每处 `feature_root(` 必须带后缀）。其余 5 个：MANDO 的 `hgt_metadata.json` 守卫**把目录路径当成语料**（实测 seed1/seed2 在 2–3 秒内 rc=1；三份 `cb_ft_ss{S}` 的结构**逐字节相同**、全池词表同为 9×187 ⇒ 已改为只按池算的 `structure_fingerprint`，两个指纹匹配其一即放行，**换池仍被拒**、canon 老文件行为不变）、`_hex_table()` 读错根、`--only-missing` 硬编码正典 `out_dir`（会让 `--layout buggy` **静默空跑**）、日志文件名不分正典（已实际发生过互相覆盖）、`collect_baseline_tables` 的 `slither_row`/`coverage_block`/`timing_block`/`binary_caliber_block`/`overview_block` 的**根目录与分母全写死**（会让 46 池数字静默进 497 池的表）。
  **新增守卫**：`baseline_common.LAYOUTS`（布局唯一真源）+ `check_layout()`（四条路径必须同正典，判据是**互不一致**而非"认不认识"⇒ 自定义 `--graph-dir` 照常可跑）+ `--feature-suffix` 登记进 `run_guard.IDENTITY_DEFAULTS`（否则「用新键写进旧目录」会被 `diff_args` 放行 ⇒ 无声覆盖正典，§31.3 那个洞），连带把漂移守卫放宽为「`train.py` ∪ 基线族」的**真 parser 并集**。
  **产物区**：`products/alldata/baseline/<名>_buggy/`（离线特征）+ `eval_results/baseline/<臂>_buggy/seed{S}/` + `slither_buggy/` + `raw/logs/baseline_buggy/`。`.gitignore` **无需新增规则**（`products/**/baseline/**` 与 `eval_results/baseline/**/*.pt` 都是 `**` 通配），仍按三步自检实测。
  **成本（实测）**：MVD-HG 建图 318 s（含首次编译 497 份 compact AST）、训练 wall 260/409/167 s/种子；EGFL 建图 149 s；MANDO **wall 3554/2550/2418 s**（88–93 s/epoch，best_epoch 17/8/5）——比正典段贵约 1.25 倍。**全量补跑总 wall ≈ 3.2 h**。🔴 **两段成本普遍更贵 1.2–2.0 倍，根因不是数据变大（+10%）而是 497 池的 val 让 `best_epoch` 普遍变大**（`buggy_*` 全 1 合约使 val micro-F1 持续小幅提升、`bad` 攒不满 `patience`）⇒ 早停更晚。🔴 **MANDO 的成本风险已评估**：早停 = `best_epoch + 1 + patience`（正典实测 5/26、15/36、4/25 与 `patience=20` 逐位吻合）⇒ 要跑到 200 轮需每 ≤20 轮就出现一次新高；`write_bundle` 是唯一写盘点且**原子替换** ⇒ 中途 kill 不留半截产物。
  🔴 **本次读数最值得写进论文的一条**（`decisions.md` §52.5b）：`micro@val_thr`（3 种子均值）本文方法 0.730→**0.940**、
  **MVD-HG 0.413→0.870（距本文方法从 +0.317 缩到 +0.071）**、EGFL 0.200→0.372、EGFL(论文 lr) 0.313→0.423、
  MANDO-LLM 0.193→0.317；而 **Slither（不训练、无阈值）0.455→0.402（−0.053）作干净对照**。
  ⇒ **只有 MVD-HG 的差距形状真的变了**，且与 §48.6.3/§51 查明的机制逐条吻合：**它的原生语料本来就含 `buggy_*`**
  （每类正例 70–75% 是注入样本），此前我们拿剔除 buggy 的 453 池喂它 = 用**它没见过的分布**评它。
  ⇒ 论文 5.3 应据此改写为「MVD-HG 在剔除注入样本的池上评测条件对它不利」，而非「它方法弱」。
  ⚠ 涨分**不是**检测能力提升（全 1 标签是度量假象）；Slither 的负 Δ 正说明「不是 497 池任务变简单了」。
  **文档同步**：`AGENTS.md`（数据边界段新增 2026-09-23 条目 + 五条硬约束）、`项目组织架构.md`（products/ 段补 `baseline/` 条目、eval_results/ 段、scripts 段、experiments 段）、`论文开发手册.md` §3.2、`decisions.md` §52、`Todo_List.md` §12.7.1、`log.md`（本条）。测试：`tests/test_baseline_tables.py` 新增 10 条守卫（布局两表一致、错配硬拒×3、自洽放行×2、图前缀不跨匹配、特征根隔离、**feature_root 调用必须带后缀**、产物不相交、buggy 三基线落盘契约、metadata 逐正典独立）；`tests/test_run_guard.py` 的漂移守卫放宽为并集。全量 `pytest tests/ -q` = **363 passed / 2 skipped**。
- 2026-09-24 **交付物排版裁定 + 编码器 SWA 选点 + P1 落成 + 文档滞移修复**（`decisions.md` §53）。
  **用户四项指示**：① 成本表补本文方法、表前标注来源与项目数量；② 解释性文字放表后、不打断阅读（其他文档同理）；
  ③ 修文档滞移；④ 跑探针全量 + P1 + P2（**不用管 §30.5 裁定**）。
  **① 成本表（§2）**：`timing_block()` 现先出本文方法 3 行（**0.415 M 参数 / 训练 4.6–6.6 s / 每 epoch 0.33 s /
  总 wall 6.5–9.7 s**，对照 MVD-HG 137–213 s、EGFL 214–281 s、MANDO-LLM 1905–2916 s），并新增 `_inputs_block()`：
  表前一张 3 列小表 = 行 / 图·特征来源 / **逐种子** train-val-test 数量（**从产物读**——两段池不同且基线会逐种子掉
  样本（MVD-HG 实测 357/357/358、45/45/44），写死必错）。🔴 `best_epoch` **不在 config.json 里** ⇒ 从 `log.txt`
  逐 epoch JSONL 复算，判据与 `train.py::best_monitor` 逐字相同（严格 `>`、并列取第一）。
  **② 排版**：三份**程序生成**的交付物（`baseline_three_caliber_tables.md`、`per_class_three_caliber_tables{,_buggy}.md`）
  改为**表在前、声明在后**——改的是两个生成脚本的拼装顺序（改 `.md` 会被下次运行覆盖）。🔴 **段号「§0」标题名
  与表号 1–28 一个都没动**（全仓「见本表 §0 第 N 条」「表 N」引用继续有效，而 Markdown 里的段号引用**不会被任何
  测试发现失效**）。
  > ⚠ **2026-09-24 二轮排版更正上句的一半**：`baseline_three_caliber_tables.md` 的**表号 1–28 确实一个都没动**，
  > 但 **§0 的标题名已改**——两段的 `## 0. 口径声明…` 合并为单一文末节
  > **`## 附（原「§0」）：口径声明与逐行声明（引用本表前必读）`**，下辖 附-A/附-B/附-C/附-D 四组
  > （原 §4.1/§4.2 改为 附-C-2/附-C-3）。**「§0」字样与条目编号 1)–6)/1)–7) 均保留**，
  > 故「见本表 §0 第 N 条」式引用仍可解析；另有 3 处**指向已搬走位置**的交叉引用同步改写
  > （§2 表下注 → 附-A-2、§4.1 → 附-C-2、「三、」§0 第 4 条 → 附-D 第 4 条），否则会变成死指针。
  > 同时修 `项目组织架构.md` 的同一处滞移（「§0–§二」→「§一–§二」）。`git diff` 验证三份文件的**数据行逐字节未变**。其余生成文档实测两表之间非引用散文 ≤2–6 行
  （`ablation_n9`/`perclass_arm`），无同类问题；`dive_external_results` 的 19 行是正当分析段（非声明块），不动。
  **③ 滞移修复 5 处**：`results.md` §5 SolidiFI（**「未开始」实为 2026-09-20 已完成**，§40）、§3 五工具（「未实跑」
  → 「**未接入**，环境已落地 §47」）、`report_conclusions.md` §2.2 两行 + 抬头滞移横幅、`Todo_List.md` MANDO 行
  （「训练中」→ 已跑完）+ 顶部新增「当前状态以 `log.md` 为准」指引、`dive_external_results.md` §6 第 9 条。
  **④a 探针全量**：`--epochs 16 --patience 4` 三划分种子 → `runs/codebert_ft_probe16/`（隔离）。ss0 实测
  epoch 7 时 val macro-F1 已 **0.7308**、epoch 8 **0.7430**，而**正典上限 5 轮时只有 0.4365（best 0.526@ep3）**
  ⇒ `improvement_proposals.md` §1.1 的"欠训"结论在 3 个种子上成立、且幅度被低估。
  **④b P1 落成**：新增 `scripts/collect_p1_gains.py`（**只读**既有三个 JSON，不重训）→ `experiments/p1_gains.md`：
  表 1 工作点（**逐类阈值 macro +0.1378 / micro −0.0446**）、表 2 同划分多种子集成（**Δ vs 均值 +0.0330**，
  vs 最好单模型 −0.0157）、表 3 分辨率（**micro 95% CI 宽 0.34–0.40**；按 support 加权 macro 0.4841→**0.7593**、
  剔薄类 →**0.8472**）。🔴 §0 三条使用规则：集成**不得**与 best-of-3 并列比（后者含选择膨胀）、逐类阈值是**并列**
  口径、三笔**只进报告口径不进训练控制流**。
  **④c P2 实现**：`finetune_codebert.py` 新增 `--swa-start N`（编码器选点改**后缀权重平均**）：默认关 ⇒ 行为逐字节
  不变；**只存一份 fp32 累加器**（本机可用内存仅 ~4 GB，K 份快照会 OOM）；**平均权重先在 val 上打分、只有不劣于
  best-epoch 才采用** ⇒ 在 val 上不可能变差，两个读数写入 `config.json::swa`。冒烟实测走通（`{swa_start:2,
  n_averaged:3, selection:"best_epoch"}`，正确地回退了）。守卫 `tests/test_finetune_swa.py`（3 例，含
  "默认必须为 0"——盯新增开关悄悄改默认路径）。**P2 执行**：三划分种子 `--epochs 20 --patience 4 --swa-start 16`
  → `runs/codebert_ft_p2/`，再串 M3（`build_graph_variant --variants-root products/alldata/graphs_ft_p2`）
  → GNN（`--deterministic`）→ evaluate → diagnose，全链**另开目录，正典零改动**；两条队列脚本挂在探针之后自动接力。
  **测试**：`pytest tests/ -q` → **366 passed + 2 skipped**。**入库自检（三步）**：(a) `git check-ignore -v` 逐文件
  实测 `runs/codebert_ft_probe16/.../pytorch_model.bin` 被 `runs/codebert_ft*/**` 忽略、`config.json` 被白名单纳入；
  (b) `git add -A --dry-run` 共 **25 个文件、最大 340 KB**、无 >100 MB；(c) 见下条（P2 产物落地后补）。
- 2026-09-24（续）**P2 全链跑完 + 编码器换代闸门通过**（详见 `experiments/decisions.md` §54）。
  **① 两个真 bug（都是我的脚本的错，已记进脚本注释当纪律）**：
  (a) **`--out-dir` 语义错**——`train.py` 的 `--out-dir` 是「**父目录**」，它会自己再拼 `seed{S}`；
      我传了 `runs/p2_canon/seed${S}` ⇒ 产物落到 `runs/p2_canon/seed0/seed0/`，而 evaluate 找的是
      `seed0/best.pt` ⇒ 三个种子的 evaluate/diagnose **全部崩溃**。产物一个没丢（训练本身全成功），
      把多出来的一层抹平后只补评测段即可（`runs/_p2_finish.sh`）。
  (b) **退出码捕获错**——`echo "... rc=$? ..."` 里的 `$?` **永远得 0**：同一行里 `$(date +%H:%M:%S)`
      这个命令替换先执行、把 `$?` 覆盖成了 date 的退出码。于是三个 evaluate 全崩、闸门因产物缺失返回 3，
      日志里却写着「闸门 rc=0」。⇒ 纪律：**退出码必须紧跟命令单独取 `rc=$?`**，不要塞进带命令替换的 echo。
  **② 闸门（`experiments/encoder_promotion_gate.md`）三道门全过**：G1 方向 mAP 3/3 + macro@val_thr 3/3；
  G2 幅度 mAP **+0.1369**、macro@val_thr **+0.1923**；G3 上游编码器 3/3、mean **+0.2589**。
  ⚠ 唯一负向 = `test macro@0.5` 2/3（seed0 −0.0229），非主判据、如实列出。
  **③ 🔴 本次提升的实质是 epoch 预算，不是 SWA**：`codebert_ft_p2/ss{S}/config.json::swa` 实测
  `n_averaged` = 0/0/2、三种子 `selection` **全是 best_epoch**（ss0/ss1 最佳轮为 ep10/ep11，
  早停在第 16 轮前触发 ⇒ SWA 窗口从未打开；ss2 累到 2 轮但 0.6290 < best 0.7165 被正确拒绝）。
  ⇒ `--swa-start 16` 事后证明太晚，**任何文档都不得写成「换代 = 20 轮 + SWA」**。
  **④ 成本**（用户要求记录）：编码器 20 轮档 **1825.8 / 1954.4 / 2322.7 s**（5 轮档 933.5/931.2/680.9），
  M3 重编码 631.9/578.5/574.4 s，GNN wall 8.6/6.5/8.6 s ⇒ **端到端从零合计 ≈2470/2540/2910 s/种子**。
  换代代价 = 上游涨约 2.3 倍。
  **⑤ 大纲已同步**（`scripts/edit_outline.py` + `outline_spec.py`，幂等、逐条带依据、落盘前自动备份）：
  §4.3.2 两处改三档阶梯、§4.5.1 改 20 轮/patience 4 并写明 SWA 未被选中、T16 末行改三档、
  **新增 §4.7 实现细节整节**（7 小节 + 8 表）+ 修 3 处口径滞移（`448/323`→`453/326`、
  T7 DropEdge `0.1`→`0（默认关闭）`、T13 补 590 项目级）。根因：`data_funnel.json` 步骤 25/26
  **标签写「581」「448」而数值是 590/453**，大纲沿用了错的那半。
  **⑥ ⚠ 代码层「升正典」尚未执行**：`run_ablation.variants_root_of()` 把变体根**推导**为
  `Path(graph_dir).parent / "graph_variants"` ⇒ 换到 `graphs_ft_p2/` 后该根不存在，
  `cb_rev`/`cb_unlimited` 两臂会**静默指向空目录**。完整清单与成本（≈5 h，含 303 个下游 run 重放）
  见 §54.5，**两点待用户裁定**（n=9 两代怎么处理、② 与 `_buggy` 是否同步换代）。

## 2026-09-25（续）：编码器换代**代码层落地** —— 混合换位 + n=9 全重跑 + `_buggy` 同步换代

**用户裁定（本次）**：① n=9 全部重跑、**不另开一代**（新结果更高则在各对照表的**原正典位置原地替换**
⇒ 整表换 + 逐格对照）；② `_buggy` 正典**同步换代**（16 轮 → 20 轮）；③ **② 增强集不动**；
④ 详细记录训练成本与实验结果。

### 一、方案：**混合换位**（`decisions.md` §55）

**run 目录物理换位**（新一代替换到正典路径，旧一代改名到 `runs/prior_*`）；
**编码器与图树保留各自的 `_p2` 名字**（旧树原地不动）。

```
runs/seed{S}          ← runs/p2_canon/seed{S}          （就位 ⇒ runs 侧常量**自动正确**）
runs/prior_canon37/   ← seed{S} + cbft_study + ablation + ablation_n9 + arch_n9 + perclass_arm + baseline_gcn
runs/prior_buggy16/   ← buggy_canon + ablation_buggy + baseline_arch_buggy
runs/prior_probes/    ← codebert_ft_probe 的**边车**（权重按 .gitignore 同一判据删除）
products/alldata/graphs_ft_p2/cb_ft_ss{S}/   ·  runs/codebert_ft_p2/   ← 新，名字不变
products/alldata/graphs_ft/ss{S}/            ·  runs/codebert_ft/      ← 旧，原地不动
```

**为什么这样切**（三条都是**实测**依据，不是偏好；前两条把「全物理换位」判死了）：
① 归档 run 的 `config.json` 里 `graph_dir`/`encoder_dir` 是原路径、旧树不动 ⇒ **旧产物仍可逐字重放**；
   全物理换位会让它们指向新一代且**不报错**。
② `m3_build_features.py` 的 `_cb.pt` 是**断点续跑缓存**（`cache_usable and not force`）⇒
   把新编码器放进旧路径重跑 M3 会产出「新目录名 + 旧特征」且**不报错**。
③ `check_encoder_promotion` / `collect_buggy_canon_summary` / `collect_ablation_results` 都把
   `codebert_ft/` + `graphs_ft/` 当**旧一代/消融档**引用 ⇒ 旧树不动，这些引用**逐条仍然正确**。
④ 归档用 `prior_` 前缀 ⇒ `aggregate_results.ARCHIVE_PREFIX` **自动排除**（零代码改动）；
   ⚠ 实测不可用 `runs/_archive/`：`.gitignore` 的 `runs/codebert_ft*/**` 是**路径前缀**匹配，
   归档到别处会让 **2.9 GB 的 `.bin` 漏网**（本方案从不归档编码器，故无此问题）。

### 二、代码改动（11 个脚本 + 3 个测试 + 2 份文档）

**换正典必须改的图侧常量（4 处 + 1 layout + 1 守卫）**：`baseline_common.LAYOUTS[*]["graph_dir"]`
与 `base_parser()` 默认、`collect_baseline_tables` 的同名字面量（有机检要求逐字相同）、
`run_perclass_arm.GRAPH_TMPL`、`run_arch_baselines --graph-root`、两个 `baseline_*_build` 的默认值；
`build_ft_edge_variants` 新增 **`canon_p2`** 与 **`buggy_p2`** 两个 layout 键；
`run_ablation` 新增 **`require_layout_dirs()` 硬守卫**（变体根/冻结树/`cb_rev_ss{S}` 缺一即 `SystemExit`）
—— 这正是 §54.5 记录的静默耦合，从此不可能再静默。

**🔴 顺带修掉的两个既有静默 bug**：
① `run_cbft_study` 的 `frozen` 臂靠「继承基线 `graph_dir`」定义 —— 该脚本写于「冻结=正典」时期，
   **§37 把微调升为正典后它悄悄不再冻结**，「冻结 vs 微调」实际是「微调 vs 微调」。已改为显式取
   `products/alldata/graphs`；`cbft` 臂改为**直接取正典树本身**（不再经副本树）⇒ 其对角与
   `runs/seed{S}` 的同配置性**由构造成立**；单变量证据改由 `check_artifacts()` 对**冻结树 ↔ 正典树**
   逐图断言（实测三通道全同、`_cb.pt` 两通道全异，正是要证的事）。
② `build_dive_external_set.step_features()` 调 M3 **不带 `--force`** ⇒ 会静默复用**别的编码器**留下的
   `_cb.pt`（`assert_feat_same` 只比三通道、与编码器无关 ⇒ **不报错**）。已补 `--force`，
   并新增 `ENCODER_ROOTS` **逐语料**映射（① 走 `codebert_ft_p2`，② 仍走 `codebert_ft/augmentation`）
   —— 不这样改会让 DIVE 静默拿旧 5 轮编码器重编码。
③ `run_ablation.VARIANT_ROOT` 是**死常量**且指向「边变体源」而非「臂变体根」（同名两概念），
   改名 `EDGE_SOURCE_ROOT` 并加注释；`run_cbft_study.CANON_STD_MICRO05 = 0.0309` 是**写死的旧正典 std**
   （判决阈值！），改为 `canon_std_micro05()` **现算**，取不到就明说"不判"而不用过期门槛。
④ `evaluate.py::_provenance()` 的口径戳扩到**六种形态**（`.p2` 两条 + 旧两条 + 冻结 + 兜底），
   判序**从具体到泛**（`graphs_ft_buggy_p2` ⊃ `graphs_ft_buggy` ⊃ `graphs_ft`，写错会自己认错自己）。

**测试**：更新 3 处钉死的旧字面量 + 新增 `test_deposed_trees_match_no_layout`（机检旧树不匹配任何
layout ⇒ `cb_ft5` 不会被判成正典）。**367 passed / 2 skipped**。

### 三、磁盘（用户裁定：删整个小探针目录）

`runs/codebert_ft_probe16/ss{0,1,2}/encoder/pytorch_model.bin` 3 个 + `runs/codebert_ft_probe/`
（移边车到 `runs/prior_probes/` 后）⇒ 全仓 `.bin` **16 → 12 个**。
⚠ **对该裁定的细化**：按同一空间收益（1.91 GB）执行，但**保留全部能承载结论的 JSON 边车**
（探针的 `config.json` 含 `epochs_log` 逐轮曲线），只丢可由 `finetune_codebert.py` 重建的权重
—— 与 `.gitignore` 早已采用的判据一致。**实测可用空间 31.94 GB**（会话开始时为 13 GB，
期间另有约 19 GB 被释放）⇒ 8 GB 硬规则全程无虞。

### 四、.gitignore 三步自检（实测）

新增 `runs/prior_canon37/**/best.pt` + `runs/prior_buggy16/**/best.pt`（写在 `!runs/**/best.pt` **之后**）。
(a) `check-ignore`：`prior_canon37/seed0/best.pt` 命中第 85 行 ⇒ 忽略；`test_probs.pt` **入库**；
    `runs/seed0/best.pt` **仍未被忽略**（规则没漏出去）。
(b) `git add -A --dry-run runs/ products/ eval_results/` = **3359 文件 / 0.03 GB**（均 9.4 KB）、
    最大单文件 **5.0 MB**、**`pytorch_model.bin` 命中 0**、`_snap` 命中 0、**无 >100 MB**。
(c) 本段与 `AGENTS.md` / `项目组织架构.md` 同步。

### 五、阶段 3 首跑中止：GAT 与 `--deterministic` 不兼容（已修）

**现象**：3.1/3.2/3.3 全绿（6 变体树 + 18 + 63 run），3.4 跑到第 163 个时中止：
```
[main/conv_gat/0:0] ✗ train 退出码 1
RuntimeError: scatter_reduce_cuda does not have a deterministic implementation,
              but you set 'torch.use_deterministic_algorithms(True)'
```

**根因（换代带出来的新耦合）**：`--deterministic` 是 `_p2_chain.sh` 为 **SWA 逐位对拍**给新正典加的，
而下游所有臂的参数由基线 `config.json::args` **继承** ⇒ 换代后**全部下游臂都变成了确定性训练**。
旧一代（`runs/prior_canon37/arch_n9/*`）实测 `deterministic=False`，所以从没暴露过这个问题。

**实测哪些算子支持**（`--limit-graphs 12 --epochs 2` 冒烟，不靠猜）：

| `--conv` | `--deterministic` |
|---|---|
| `rgcn`（正典） | ✅ 可用 |
| `gcn` | ✅ 可用 |
| `sage` | ✅ 可用 |
| **`gat`** | ❌ **PyTorch 无确定性 CUDA `scatter_reduce` 实现** |

⇒ **只影响 GAT 系的两个臂**（`conv_gat`、`gat_pm`，各 9 对 = 18 run）。

**修法**：`run_ablation.forced_overrides()` —— 对 `conv in {"gat"}` 的臂补 `deterministic: False`，
并在 `run_ablation_n9.override_keys_of()` / `run_arch_baselines` 的单变量断言里把该键**计入 expected**
（否则会误报「预期覆盖的键未生效」）。`rgcn/gcn/sage` 一律**保持** `--deterministic`，与基线逐字同。

⚠ **被迫的第二变量，必须随表披露**：这两个臂相对基线因此多了「确定性开关」一个变量。
不是可选的美化 —— 是 PyTorch 的限制；且它属**噪声级**而非**偏差级**差异
（确定性开关不改变期望精度，只消除归约顺序抖动），故可接受。写进架构族的口径注（该族本就有三条）。

### 六、🔴 又一次退出码教训（同类第二次，已固化纪律）

后台启动命令写成 `bash chain.sh > log 2>&1; echo "退出码=$?"; tail -20 log`，
于是**上报的退出码是末尾 `tail` 的（0）**，把 3.4 的真实失败 `rc=1` **掩盖成成功**。
本次靠目标文件数对不上（`perclass_arm` 0 个、`baseline_gcn` 0 个）才发现。

⇒ **纪律（与 `_p2_chain.sh` 的 `rc=$?` 那条同源）**：
**后台链的包装行不得以 `echo`/`tail`/`grep` 结尾**；链子自己去写
`runs/<链名>.status`（`OK` / `FAIL <原因>`）与 `runs/<链名>.rc`，外部只认这两个文件，
**不认任务框架上报的退出码**。

### 七、阶段 3 续跑的四个发现（三个是既有问题，一个是我的错）

**① 我的错：`diagnose.py` 没有 `--summarize`。** 我照 `evaluate.py --summarize` 类推，
实际 `diagnose.py` 在 `main()` 里**无条件**写 `diagnosis_summary.json`，**没有**该开关
⇒ `error: unrecognized arguments: --summarize`，3.7 中止。改用
`diagnose.py --runs-dir runs` 后一次通过（三种子齐）。
⚠ 缓存安全性顺带确认：`diagnose_seed` 命中 `seed{S}/test_probs.pt` 且**校验 `sample_ids`
与当前划分一致**才复用 ⇒ 三个缓存都在时单次 `--runs-dir runs` 对三种子都走缓存，
**「单一 `--graph-dir` 配多个不同划分种子」那个坑不会触发**。

**② 🔴 `runs/perclass_arm/cap20/cls_ANY_union/` 是孤儿产物**（本次换代才暴露）：
它在旧的 45 个 run 里存在，但**没有任何脚本能产出它** ——
`run_perclass_arm.py` 的 `classes = metrics.VULN_NAMES`（7 类，不含 union），
`git log -S "ANY_union" -- scripts/run_perclass_arm.py` **为空**（从未有过）；
`--classes ANY_union` 会被「未知类名」守卫直接拒绝。
只有 `collect_perclass_arm.py::union_rows()` 读它（**读不到就 `continue` 跳过**），
且旧的 `experiments/perclass_arm_results.md` 里**根本没有 union 行** —— 即
**这个臂的数字从未进过交付表**，而 `AGENTS.md` 的布局串却登记了它。
**真实身份**（从归档 `config.json` 读出）：`head=binary` + `label_file=None` +
`pos_weight_cap=20` ⇒ 就是 §31 的 `--head binary` 塌缩（`dataset.stack_labels` 的
`any(targets)`）那条「有没有漏洞」臂，与逐类臂**同池同划分**。
⇒ 本次**忠实重放**（唯一被替换的两个键：`graph_dir` → 新树、`deterministic` → 与现行正典一致），
使文档登记的布局不再有洞；命令行由 `run_ablation` 的三个 argv 构造器从**新正典 config** 派生，
**不手抄参数**（手抄 30 个参数正是本仓警告过的错源），并加单变量自检守住「只差 head 与 cap 两键」。

**③ ⚠ 新正典的 `config.json::args.out_dir` 仍写着构建地 `runs/p2_canon/seed0`**，
而它现在住在 `runs/seed0`（换代时是 `mv`）。**不去改它** —— 它是「这次运行是在哪里产出的」
的**不可变自述**，改了就成伪造。但由此产生一个**必须写进文档的操作性风险**：
`rerun_from_config.py` 按 `config.json::out_dir` 回填目标 ⇒
**重放 `runs/prior_canon37/` 会写到 `runs/seed{S}`（即活的现行正典）**。
已在 `runs/prior_canon37/README.md` 与 `decisions.md` §55 加醒目警告：**该归档不得用该工具直接重放**。

**④ `verify_single_variable` 的模板坑（我踩到一次）**：基线侧
`canonical_args` 返回的 `graph_dir` 是**模板** `…/cb_ft_ss{seed}`，而臂侧是**展开值**；
不把基线也展开就会被 `diff_args` 按内容判成「改了 `graph_dir`」而误报。
已在调用处展开（`base_e`）并加注释。

### 八、🔴 我造成的一次真实损伤：DIVE 的 `raw/` 被清空到一半（已加守卫）

**经过**：3.8 我传的是 `--steps all`，它展开成 `stage,raw,graphs,features,variants`。
其中 **`raw` 会带 `SSMHG_ALLOW_WIPE=1` 调 `generate_all_ast_cfg_dfg.sh`，该脚本开工即
`find -delete` 清空 DIVE 的 AST/CFG/DFG 四个目录再逐个重生成** —— 与编码器**无关**，
是数小时的无谓开销，且会扰动既有交付数字所依赖的产物。我**主动中止**了它。

**代价（实测）**：
| 区 | 主库对照 | DIVE 中止后 | 应为 |
|---|---|---|---|
| `raw/AST-raw` | 590 | **13** | ≈891 |
| `raw/DFG-raw` | 590 | **13** | ≈891 |
| `raw/CFG-raw` | 25949 | **891** | ≈40000 |

⚠ **为什么当时看不出来**：`filter_report.txt` 是脚本在**末尾**才重写的，中止后它**仍是上一轮
完整运行的旧报告**（`total_source_files=900`、`cfg_failed=1`，与 git 版本逐字节相同）
⇒ 从外面看一切正常。这是一个**静默陷阱**。

**影响面（关键）**：读 `raw/` 的**只有** `step_graphs` 一个消费者；
而 `products/dive/graphs/`（890×5 文件，**一切已报告 DIVE 数字的实际来源**）**完好未动**
⇒ **不影响任何已报告数字**。

**已做的补救**：`build_dive_external_set.assert_raw_complete()` —— 建图前拿**同一份
`graphs/` 里的图数**做参照（一合约一图一 AST 一 DFG，三者必须齐平；自校准，不写死 900/891），
不齐即 `SystemExit` 并明说"很可能是 `--steps raw` 被打断"。实测已拦住 ✅。

**待裁定**：是否花约 2.5 h（Slither × 900）补跑 `--steps raw` 把 `raw/` 恢复完整？
- 选「补」：`raw/` 恢复可审计，且**不碰** `graphs/`（保持"数字来源"与产物一致）。
- 选「不补」：不影响任何交付；代价是「从零重建 DIVE `graphs/`」这条路暂时走不通（被守卫挡住，**响亮**而非静默）。

### 九、另一处修正：`--force` 改成**按编码器是否换了**决定

3.8 我原先把 M3 调用改成**无条件** `--force`（修「复用别的编码器留下的 `_cb.pt`」那个静默 bug）。
但它会让**未换代的语料**（② 增强集）白跑 3 棵树的 M3（约 45 min）。
⇒ 改为**判据驱动**：`variant.json::encoder` 与当前编码器路径不同才 `--force`。
实测：①（alldata）三棵树 `force=True`、②（augmentation）三棵 `force=False` ✅ 正确且不浪费。

### 十、大纲同步：从「静默丢弃」到「响亮报错」（2026-09-25）

**起因**：本次换代要改大纲 §4.7 的路径表，改完 `outline_spec.py` 后跑 `edit_outline.py`，
它报「已应用，跳过」—— 而 `.docx` 里 `graphs_ft_p2` 出现 **0 次**。**改动被静默丢了。**

**根因**：插入类编辑的幂等判 **只看块的首段文本**；首段没动就整块跳过。

**三次修正（每次都是我自己的错）**：
1. 先改成 `startswith(t[:40])` 前缀匹配 —— **自己把守卫弄瞎**：`_S471_NOTE` 只把
   `graphs_ft` 改成 `graphs_ft_p2`，差异恰落在**第 40 字符之后** ⇒ 仍然"全部命中"。
2. 改为**全文相等**（压掉空白）判据 ⇒ 立刻准确报出
   「本块 14/16 段已在文档里，**内容已分叉**」并列出缺失的 2 段。
   **部分命中即 `SystemExit`** —— 不允许静默跳过。
3. 补 `table_row_after`（插表行，深拷贝参照行 `<w:tr>` 保 `trPr`/`tcPr`/`gridSpan`）——
   大纲 §4.7 表**缺「消融档」一整行**，原引擎改不了。**顺序敏感**：新编辑必须排在
   `block_before` **之前**，否则先撞上分叉守卫。

**第四处修正（干跑抓到的腐蚀隐患）**：`replace_in_table` 的 `old` 是**子串**匹配，
而 `…/encoder` 同时是新插「消融档」行里 `…/encoder（**原地保留，未删**）` 的前缀
⇒ 第二次 `--apply` 会**改错格且不报错**。已给该编辑加第 5 元 **`"exact"`**（整格精确匹配）。
⚠ 本次是**干跑**发现的，磁盘未受影响（已逐格核对消融档行完好）。

**落盘结果**（备份 `runs/_snap/outline-before-20260925-141441.docx`）：19 条编辑全部应用，
**复跑 19/19 报「已应用」= 完全幂等**。`.docx` 现在：
`graphs_ft_p2` 3 处、`cb_ft_ss` 5、`codebert_ft_p2` 4、`cb_ft5` 3、`prior_canon37` 1。
残余的 `graphs_ft/ss` 3 处与 `codebert_ft/alldata` 3 处**全部在"指消融档"的合法位置**
（新插的消融档行、表 #14 的消融档行、成本表的消融档行）—— 三档阶梯的叙事要求它们保留。

**大纲仍差**：只有一项 —— 表 #18 需补**本次换代的实测成本**（阶段 3 各步 wall + 阶段 4），
待阶段 4 跑完一次性补。**3 条新口径按用户裁定不入大纲**（留在 `AGENTS.md` / `log.md` / §55）。

### 十一、DIVE：按裁定**不重跑外部评测**

用户裁定「**DIVE 不需要完全跑完，与原数据集大致相当即可**」。
`evaluate_external.py --matrix {main,aug}` 要跑 21 臂 × ①② × 3 种子（约 2 h+），
而 DIVE 只是跨数据集泛化性的旁证 ⇒ **保留换代前的 `matrix_*.json` 与 `comparison.*`**，
在 `experiments/dive_external_results.md` 顶部加**口径披露横幅**：
**特征树是新的、评测数字是旧的，两者不同代**。
⚠ 我一度把这两条评测加进阶段 5 脚本（原脚本漏了，会把旧矩阵当新结果汇总），已按裁定撤回。

**阶段 3.8 的输入侧已全部完成**：① 特征树 3×890（`variant.json` 记 `codebert_ft_p2`）、
① 变体树 6 个、② 特征树复用未变、② 变体树 6 个。
`--force` 判据化实测有效：① force（1725 s/树）、② 复用（~200 s/树）⇒ **省约 1.5 h**。

### 十二、交付面体检（2026-09-25，阶段 4 运行期间）：四处静默错 + 两处「假程序生成」

用户问「还差哪些开发工作、哪些文档没同步」。逐项实测（不靠记忆）后查出并**当场修掉**四条：

1. 🔴 **`scripts/collect_buggy_canon_summary.py` 的 `--encoder-root` 默认值仍指 16 轮旧编码器**
   （`runs/codebert_ft_buggy`）。换代后 `runs/buggy_canon` 是用 `codebert_ft_buggy_p2` 训的
   ⇒ 阶段 5 跑它会把**16 轮档的编码器时间表/轨迹**贴在**20 轮档的 run** 旁边，**不报错**。
   已改默认为 `_p2`，并在卷首第 3 条补上「池 + 训练量是双变量、对齐 20 轮后才只剩池」的口径限制。
   （另两处默认值 `--old-encoder-root runs/codebert_ft/alldata`、`--old-runs-root runs/prior_canon37`
   **经查是对的**：本卷的 old 侧按设计就是 ① 的 5 轮正典，不是 buggy 的 16 轮。）
2. 🔴 **`runs/_p5_collect.sh` 漏了两个采集器**：`collect_p1_gains.py`（写 `p1_gains.md`，mtime 09-24）
   与 `audit_cb_unlimited_reach.py`（写 `cb_unlimited_reach.md`，mtime 09-21）——**两者都有生成脚本
   却不在阶段 5 清单里**，换代后会静默留着旧一代数字。已补入（`bash -n` 通过）。
3. 🔴 **两个「权威出处」其实是手写**（`grep -rn` 全仓无生成者，git 历史里也从无生成脚本被删）：
   - `experiments/canonical_ft_numbers.md`（`项目组织架构.md:420` 称其「全仓新口径数字的权威出处」）
     仍是 **5 轮档**：micro@0.5 **0.7110**（现行 **0.8129**）、mAP **0.7582**（现行 **0.8952**）。
   - `experiments/ablation_three_metric_table.md` 自述「程序复算、**不手抄**」——**不属实**，仍是 5 轮档 21 臂。
   ⇒ 两处各加 **🔴 作废横幅 + 逐口径新旧对照**，并写明「待阶段 5 后按新正典重写、补生成脚本」。
   这一步的意义：把「可被静默引用的错数字」变成「引用时必然撞见横幅」。
4. ⚠ **大纲的四处「没记录」**（详见对话回报，须用户裁定后才动大纲）：
   ② 增强集（池 1774）、任务 2 的池 497 线、**n=9 同配对 ≥9 点**、L_var 剂量臂。
   其中剂量臂在 `run_ablation.py:102-111` 已自述「**大纲之外的后处理**（须先同步大纲与开发手册）」——
   即**流程上已知未同步**；而 ≥9 点规则只写在 `ablation_three_metric_table.md` 与 `decisions.md`，
   **大纲 §5.2 只写「至少 3 个随机种子」**。

**排查方法留档**（下次同类体检照做）：不看 mtime 一条条猜，而是
(a) 用 `grep -oE 'experiments/[a-z_0-9]+\.md' scripts/**.py` 列出**脚本里出现过的**交付物名，
(b) 对每个文件 `grep -rn '<basename>' scripts/` 区分「真写」与「只是注释/指针」，
(c) 再比 mtime 与换代时点。**只有 (b) 能区分"程序生成"与"手写"**——本仓这两个文件正是靠 (b) 抓出来的。

5. 🔴 **`cb_ft5` 是一个"只存在于文档里"的臂名——上一轮我把它当真的写进了大纲（我的错）**。
   实测三条硬证据：
   (a) `git --no-pager log -S "cb_ft5" -- scripts/` **为空** ⇒ 脚本里从未出现过这个名字；
   (b) `ls runs/ablation` 21 个臂里**没有** `cb_ft5`（`run_ablation.ABLATIONS` 的编码器臂只有 `cb_frozen`）；
   (c) 中档（5 轮）的**真实产物是归档的旧正典** `runs/prior_canon37/seed{S}`，
       其 `config.json::graph_dir = …/graphs_ft/ss{S}`（三种子逐条实测）。
   ⇒ 全仓（`AGENTS.md` / `项目组织架构.md` / `论文开发手册.md` / `Todo_List.md` / **大纲**）
   把它写成「消融臂 `cb_ft5`」，**但这个臂不存在**。上一轮我给大纲加的「消融档（5 轮）」行与
   命名 `cb_ft5` 的那格，**沿用了这个错标签**。
   ⚠ 影响面：不是数字错（中档数字取自旧正典，是对的），而是**读者会去 `runs/ablation/cb_ft5/`
   找一个不存在的目录**，且"三档阶梯是同一张消融表里的三行"这一读法**不成立**——
   它实际是**跨代对照**（`check_encoder_promotion.py`，old=归档 / new=现行）。
   **两条出路（须用户裁定，见对话回报）**：
   (A) 零重跑改口径：全仓把「消融臂 `cb_ft5`」改写为「5 轮档（旧正典，已归档 `runs/prior_canon37/seed{S}`）」；
   (B) 造真臂：给 `ABLATIONS` 加一项 `cb_ft5 = {"graph_dir": "{ft5}"}`（3 seed × ~8 s ≈ 半分钟），
       三档阶梯即成**同一次消融内的单变量对照**（更干净、且可用 `--deterministic` 统一），
       代价 = 打破「21 臂」的硬引用（`tests/test_collect_ablation.py` 与多张表的行数、`n/21` 断言）。

### 十三、大纲按裁定补齐（用户裁定：**3/4/5 改、1/2 忽略**；(A) 改口径零重跑）

**裁定原文**：「大纲修改345,12忽略。(A) 改口径，零重跑。大纲没有需要修改的内容时提醒我。」
⇒ 大纲补 **第 3 项**（n=9 判据口径）、**第 4 项**（L_var 剂量臂）、**第 5 项**（成本表，等阶段 4）；
**第 1、2 项忽略**（② 增强集、任务 2 的池 497 线不进大纲）；`cb_ft5` 走 **(A)**。

**大纲落盘**（备份 `runs/_snap/outline-before-20260925-144829.docx`）：新增 6 条编辑，
`--verify` **21/21**、复跑 **0 条待施加**（完全幂等）。逐条：

| # | 位置 | 内容 |
|---|---|---|
| 1 | §4.7.1 路径表 | 消融档那格 → 「**旧正典（5 轮档）**的输入树；其 run 已归档于 `runs/prior_canon37/seed{S}`（**不另设名为 `cb_ft5` 的臂**）」 |
| 2 | §4.7.2 超参数表 | 同上口径（该格原写「消融臂 `cb_ft5`」） |
| 3 | §4.7.1 脚注段 | 同上，并补「5 轮 vs 20 轮是**跨代对照**，不是同一张消融表里的两行」 |
| 4 | **§5.2** | 补「**凡下「有效/无效」结论须同配对 ≥9 点**」+ 产物/报告出处 |
| 5 | §4.7.7 对照臂表 | 「21 臂」格 → 「n=3 对角（63 run）+ **n=9 同配对复核**（126 run）；判「有效/无效」以 n=9 为准」 |
| 6 | **§5.4.2 可选消融表** | **新增一整行**「L_var 剂量-反应（λ=0.01 / 0.1 / 1.0，基线 1e-3）」+ 实测结论（三档全无增益） |

🔴 **两处引擎/编辑纪律（都是本轮实测踩到的，已写进代码注释）**：
1. **新增 `"superseded"` 标记**（`edit_outline.py`）：append-only 编辑清单里，同一段落改两次 = 两条编辑，
   前一条的输出**不再是终态** ⇒ 落盘后它的 `old` 与 `new` **都不在**文档里。不标记就会被误判成
   「旧文本和新文本都找不到」并中止整批。`--verify` 亦跳过。⚠ 不会因此漏改——
   目标段落的终态仍被块级守卫（`block_before` 的全文相等判）盯着。
2. 🔴🔴 **子串型幂等失效（真实事故，已回滚）**：`replace_in_table` 的 `old = "21 臂 × 3 种子"`
   **被新文本包含** ⇒ 复跑时 `cand` 又命中、**又替换一遍**，整格文字叠成两遍。
   实测发生 → 从备份回滚 → 给该条加 **`"exact"`**（整格精确匹配）**且**改新文本使其**不含** `old`。
   ⚠ 后半条同时是 `--verify` 的要求：verify 的判据是「含新文本的段里旧文本仍在 ⇒ 半改状态」，
   新文本若包含 `old` 会被**误报**（实测 20/21）。
   ⇒ **纪律：`replace_in_table` 一律先问「新文本会不会包含旧文本」；会，就用 `"exact"` 并改掉嵌套。**

**`cb_ft5` 改口径（(A)，零重跑）**：来源查清了 —— 它是 **`decisions.md` §54.5 清单的第 4 项**
（「`run_ablation.py` 新增 `cb_ft5` 臂」，估「一行 + 3 run」），**计划过但从未执行**，
而 AGENTS.md / 论文开发手册 / 项目组织架构 / Todo_List / 大纲都据此当成既成事实写了出去。
全仓 **23 处**逐条断言命中数 == 1 后改写（`AGENTS.md` 3、`论文开发手册.md` 4、`项目组织架构.md` 2、
`Todo_List.md` 4、`baseline_common.py` 2、`check_encoder_promotion.py` 1、`evaluate.py` 2、
`ablation_plan.md` 1、`gcn_baseline_and_per_class_f1.md` 1、`M5_dev_plan.md` 1、`test_baseline_tables.py` 2）；
`decisions.md` §54.5 第 4 项划掉并附「已裁定不采纳 + 三条证据 + 为什么不造臂」。
剩余 `cb_ft5` 全在**否定句或历史 log** 里（历史条目不改写，本节点名即可）。

**开发手册同步**（AGENTS.md 改动原则：大纲之外的实验须「大纲 + 开发手册」两处同改）：
`论文开发手册.md` §消融条目补入 (1) n=9 判据口径、(2) 剂量臂的启用方式与实测结论。

**回归**：`pytest tests/ -q` → **364 passed / 3 failed / 2 skipped**，与改前逐条相同
（3 个失败仍为阶段 4/5 未完成的中间态，见第十二节），**文案改写零回归**。

### 十四、阶段 4 完成 + 阶段 5 完成 + **大纲收尾（已无待改）**

**阶段 4（任务 2 换代）✅**：`runs/p4_buggy_chain.status` = `OK 全部完成`，包装层 rc 文件 = 0
（**真值取自 `.status`/`.rc`，不取 harness 的退出码**——包装行以写文件结尾恒返回 0）。
逐种子编码器 best val macro-F1：**0.9430（ep7）/ 0.9830（ep11）/ 0.9671（ep14）**。
产物核对：`runs/buggy_canon` 3 + `ablation_buggy` 63 + `baseline_arch_buggy` 9 = **75 run**，
与归档的 `prior_buggy16`（75）**逐项同形** ✅；三棵树各 590 图 + 各 2 棵变体树；
`summary.json::provenance.encoder` = 「20 轮档；含 `buggy_*` 的池 497 划分；任务2 现行正典」✅。
**新 vs 旧（16 轮）5 个指标全部上升、无下降格**：micro@0.5 0.9378±0.0666（旧 0.9251）、
macro@0.5 0.9322（0.9204）、micro@thr 0.9413（0.9404）、macro@thr 0.9376（0.9351）、mAP 0.9702（0.9662）。
⚠ 与 ① 不同（① 有 1 个下降格）；但池 497 的涨分**大部分是 `buggy_*` 全 1 标签的假象**，
`clean_only` 口径见 `buggy_canon_summary.md`，随表披露。

**阶段 5（交付表重生成）✅ 26/26**。首跑 24/26，**3 条是我自己的脚本错**，全部修掉并复跑：
1. `calibrate ②`：我传了 `--label-file`/`--label-key-mode`，而 `calibrate.py` **没有这两个参数**（rc=2）。
   改为 `--graph-dir products/augmentation/graphs_ft`（② 未换代、叶子仍是 `ss{S}`）+ 原有三参数。
2. `audit_cb_unlimited_reach`：`CORPORA` 里 ① 的叶子写死 `ss{S}`，换代后应是 `cb_ft_ss{S}`
   ⇒ 拼出 `graphs_ft_p2/ss0/...` 不存在 ⇒ `FileNotFoundError`（**响亮的错，不是静默错**）。
   修法 = 给 `CORPORA` 加第 6 元「正典叶子模板」（①`cb_ft_ss{seed}` / ②`ss{seed}`）。
   ⚠ 首修时**只加了第 6 元却没改 5 元解包** ⇒ `ValueError: too many values to unpack`（二次踩，已修）。
   ⚠ 同时我又一次用 `cmd | tail` 取 `$?` ⇒ 拿到的是 `tail` 的 rc=0（**纪律再犯，已记**）。
3. `collect_perclass_arm`：`--out` 默认**空串** ⇒ 空串时它**只打印不落盘**，脚本报 ✅ 但
   `experiments/perclass_arm_results.md` 的 mtime 仍是 09-23 的旧代 ⇒ 补 `--out` 后重跑（17:10）。

**大纲：已无待改内容**（按裁定范围：3/4/5 已改、1/2 忽略）。本批新增 8 条编辑，
`--verify` **23/23**、复跑 **0 条待施加**。其中**两条是收尾审计时自己查出来的错**：
- 🔴 成本表脚注③把 `promoted_from` **挂错了对象**：该字段**不在** `runs/cbft_study/*` 上，
  而在**归档的旧正典** `runs/prior_canon37/seed{S}` 上（值 = `runs/cbft_study/cbft_ts{S}_ss{S}/seed{S}`）；
  现行正典 `runs/seed{S}` 该字段**为空**（三种子实测）⇒ 现正典确是从零训练。已改准确。
- 🔴 成本表「消融档」那格仍写「该档**现为消融臂**」⇒ 按 (A) 改成「已降为**旧档（5 轮）**，**不另设同名消融臂**」。
最终审计 11 项全绿（`现为消融臂` 0、`消融档那一行` 0、`16 轮档` 0、`graphs_ft/ss` 3 处全在旧档语境）。

**测试全绿**：`pytest tests/ -q` → **367 passed / 2 skipped / 0 failed**。
最后一条失败 `test_buggy_layout_output_...` 是**测试自己钉死了旧 layout**（写 `"buggy"` 而现行是
`"buggy_p2"`）⇒ 换代后必然失败、且会把**正确的新路径判成错的**，已对齐。
（另两条 calibration 失败随阶段 5 重生成自动转绿。）

**仍未做（非大纲项）**：`decisions.md` §55 逐格对照；`canonical_ft_numbers.md` 与
`ablation_three_metric_table.md` 仍是 5 轮档（横幅已就位、待按新正典重写）；
`results.md`（09-24）、`report_data.md`（09-23）、`ablation_results.md`（09-21，历史记录需加换代横幅）
三份手写文档未刷新；`.gitignore` 三步自检与提交未做。

### 十五、文档 2/3/4/5 落地（用户裁定：「执行文档2345，将错误的旧数据覆盖掉」）

🔴 **本轮最重要的发现：文档 3 的两条核心结论被换代翻掉了**（见下），且**都是我先机检过的**，
不是印象判断。

**文档 2 —— `canonical_ft_numbers.md`：「权威出处」的根因修复** ✅
- 查清它自称「程序生成/权威出处」却**全仓无生成者**⇒ 补了 **`scripts/collect_canonical_numbers.py`**，
  把「程序生成」这句话**变成真的**（换代后重跑即自愈）。
- 🔴 **每一行的定义都机检过**：拿**旧正典** `runs/prior_canon37/seed{S}` 跑出旧文件的逐格值
  （`cbin_f1_05` = 0.9756、`buggy_sub_05` = 0.7273/0.6923/0.7727）**逐位一致**才定的映射。
- 另纠正一处**命名误导**（写进文件头）：`buggy_sub_*` **不是**「`buggy_*` 合约子集」，
  而是**「有漏洞合约」子集**（`labels.any()`）上的 micro-F1——① 的池里根本没有 `buggy_*`。
- 落盘后用**独立算法**交叉核对 15 格（micro/macro/buggy_sub/cbin/mAP × 3 种子）**全部通过** ✅

**文档 3 —— `ablation_three_metric_table.md`：4 张表程序生成 + 两处结论翻转** ✅
- 补 **`scripts/collect_ablation_three_metric.py`**；公式链用**旧正典**验证过：
  复算旧表正典行 `0.7297 / 0.7455 / 0.9419 / 0.4986 / 0.7582`（**含 std**）**逐位一致** ✅
- 🔴🔴 **§1.1 结论翻转**：三口径的 Spearman ρ 从（+0.977 / **−0.032** / −0.097）变成
  （+0.997 / **+0.648** / +0.654）⇒ 旧文「三个口径给出**三种不同的排序**」**不再成立**。
  ⚠ 我先猜「是 `cb_frozen` 一个极端臂抬起来的」，**实测算掉了这个解释**
  （去掉它 ρ 只从 +0.648 变 +0.592）⇒ 是秩结构本身的实质变化，不是单点伪影。
- 🔴 **§1.2 部分翻转**：「21 臂中**唯一**在三口径上下降」**不成立**（现行正典下是 **8 个臂**）；
  但「**编码器是压倒性第一杠杆**」**更强了**（次差的 `cb_node_only` 仅 −0.0560，
  `cb_frozen` 是它的 **6.5 倍**）。另：旧文「val_thr 只对 micro 更好、对 macro 不成立」**也翻转**
  （现 `macro@val_thr` 0.6909 > `macro@0.5` 0.6804）。
- §1.3 **方向不变且更强**（非 `cb_frozen` 臂的逐种子上界 38/966 → **7/966**；零翻转臂 2 → 4）。
- ✅ §1.4 顺手抓到**旧表自身一处事实错**：`layers1` 参数量是 **316,769**（归档旧代与现行新代**都是**），
  旧表把它并进 316,922 那组 ⇒ 已拆开更正（比值仍 ×0.763，结论不受影响）。
- §1.5 ② 未换代 ⇒ **逐位未变**，原样有效。

**文档 4/5 —— 手写文档的换代处置** ✅（**部分刷新 + 明确边界**，不是假称已刷新）
- `results.md`：新增**顶部三级横幅**（三套口径分界、已刷新 / 未刷新小节的**逐节清单**）；
  **§0 总表逐格改为 20 轮档**并标出三处翻转：① `macro@val_thr` 现**高于** `macro@0.5`；
  ② 现行正典下**两个工作点都无三种子恒零类**；③ mAP std **扩大**（±0.0056 → ±0.0613）。
- `report_data.md`：顶部横幅 + **新旧六项指标对照表** + 三处翻转提示。
- `ablation_results.md`：补一条横幅纠正「旧在 n=3」的**半对**说法——它**同时**旧在**编码器代**。

**仍差（已如实标在文档里，非我在本轮宣称已完成）**：`results.md` §1.4/§1.7–§1.10/§2–§6 的逐格刷新、
`report_data.md` 正文逐格刷新——两份手写稿的每一格都要重新推导，属**单独一轮**的量。

**顺带抓到第三处「换代后路径漏改」**（前两处是 `audit_cb_unlimited_reach` 与
`calibrate ②` 的调用参数）：`evaluate_external.dive_graph_dir_of()` **只认三种形态**，
不认 `graphs_ft_p2/cb_ft_ss<S>` ⇒ **正典单臂重评直接崩**（实测 rc=1）。
已按 `AGENTS.md` 那条「逐种子模板化必须同时认 `ss{S}` 与 `cb_ft_ss{S}`」补第四种形态。

---

## 2026-09-25（续二）：DIVE 跨代**回归**的披露落地 + 两处过期数字更正

用户裁定「修改」= 执行上一轮点名的两项（AGENTS.md 自检数字、DIVE 文档横幅 + 回归落点）。

### 一、新测出的硬事实：换代把 DIVE 变差了

| 同一批 DIVE 890 图 | 旧（5 轮档） | 新（20 轮档） | Δ |
| --- | --- | --- | --- |
| micro-F1 @0.5 | 0.0282 ± 0.0310 | **0.0040 ± 0.0014** | **−0.0242** |
| micro-F1 @val_thr | 0.0152 ± 0.0167 | **0.0034 ± 0.0014** | **−0.0118** |
| mAP（阈值无关） | 0.3979 ± 0.0106 | **0.3921 ± 0.0062** | −0.0058 |
| 逐类 `uncheck`@val_thr | 0.0787 ± 0.1363 | **0.0052 ± 0.0090** | **−0.0735** |

对照：**同分布** ① 主库 test mAP 0.7582 → 0.8952（**+0.1370**）。
⇒ **源域拟合更深、跨域更差**。**根因 = 换代闸门 `check_encoder_promotion.py` 只查同分布三项，DIVE 不在门内**
（流程缺口，非执行错误）⇒ 论文必须把这笔代价如实写出，不得只报增益。

产物：`eval_results/dive/canon_main_newcanon.json`（2026-09-25，39.6 s；`--runs-dir runs` 只跑正典）。
对照旧侧：`eval_results/dive/matrix_main.json` 的 `arms.canon`（2026-09-20，旧树）。
两列**同脚本、同 890 图抽样集、同阈值纪律** ⇒ 跨代同协议对照。

### 二、连带抓到「混代 artifact」（本轮最重要的静默风险）

`eval_results/dive/comparison.{json,md}` 的**内测列**已随换代重算（09-25），
而**两列 DIVE 仍来自 09-20 的 `matrix_main/aug.json`**（旧树）⇒ **同一张表内测新代 / DIVE 旧代**。
此前只在 `dive_external_results.md` 的散文里提示，**程序产物本身不带任何标记**。
另：`products/dive/graphs_ft/ss{S}` 是**原地覆盖**重建的 ⇒ **旧代 ① DIVE 特征树已不可重建**，
旧读数只剩 `matrix_main.json` 里的数字。

**修法（改生成脚本，不手改产物）**：`scripts/collect_dive_comparison.py` 新增
`inputs_created_utc` 字段 + 顶部横幅逐份列出四个输入的生成时间。
⚠ **必须给 mtime 兜底**：`collected{, _aug}.json` **没有 `created_utc`**，
只认自述字段会把**内测侧（正是换代的那一半）**渲染成「无此字段」——等于把最该看见的一半藏起来。
实跑结果：内测 `2026-09-25T09:07:56`（mtime）vs DIVE `2026-09-20T02:15/02:24`（自述）⇒ 混代一眼可见。
表格逐格未动（diff 仅新增 10 行横幅）。

### 三、两处过期数字更正（同一类病：**自检/说明数字未随产物更新**）

1. `AGENTS.md` 三步自检 (b)：旧载「3359 个文件 / 0.03 GB / 最大 5.0 MB」**已作废**。
   实测**全仓** `git add -A --dry-run` = **6865 个文件 / 0.4747 GB（509,660,552 B；均 72.5 KB）**、
   最大单文件 **9.37 MB**、`.bin`/`.safetensors` **命中 0**、**无 >100 MB**；
   拆开 = 真新增 3409（`prior_canon37` 2734 + `prior_buggy16` 555 + `prior_probes` 6 = 3295）+ 已跟踪待更新 3456。
   旧数字是「只扫 `runs/ products/ eval_results/` 且早于 `prior_*` 落盘」时的读数。
2. `AGENTS.md` 三件套行：旧载「约 1.5 GB / 1125 个文件、单文件 ≤4.77 MB」**已作废**。
   实测入库三件套 **1773 个 / 0.451 GB**（均 0.26 MB）、**`last.pt` 入库命中 0** ✅、
   入库 `best.pt` 最大 **9.37 MB**（`runs/ablation/hid256/seed{S}/best.pt`；
   4.77 → 9.37 MB 的差**就是该臂的参数量**）。

### 四、文档落点

- `experiments/dive_external_results.md`：顶部横幅改为**四条**（①本文整代 5 轮档 ②① 正典已重评=回归
  ③comparison 是混代 artifact ④旧 ① 树不可重建）；新增 **§0.1**（回归对照表 + 同分布/跨域对照 + 闸门缺口）；
  §4.1 表下加「本表整代 5 轮档」指针；§6 新增第 **10/11** 条（跨域代价 + 混代 artifact）。
- `experiments/results.md`：总表横幅补一条**跨域代价**指针（同分布 +0.1370 vs 跨域 −0.0058），指向 §0.1。
- **未改**：§2/§4 的任何数字（整代 5 轮档，改单行会把两代混进一张表）。

### 五、验证

`python -m py_compile scripts/collect_dive_comparison.py` ✅ ｜ `edit_outline.py --verify` **23/23** ✅
｜ `pytest tests/ -q` **367 passed / 2 skipped / 0 failed** ✅ ｜ `df -h /mnt/c` **29 G** ✅（红线 8 G）。

### 六、待裁定

**是否把 21 臂 DIVE 矩阵也统一到新代**（`evaluate_external.py --matrix {main,aug}`，约 2 h+）。
- 做：四列同代，§2/§4/§0.1 可合并成一套；代价 = 2 h+ 与重跑。
- 不做：保持现状——**已如实标注混代**，但 §2/§4 整代旧值，跨列 Δ 不可比。
- 注意：**无论做不做，旧代 ① 树都回不来了**（原地覆盖），逐位复现只能靠 `matrix_main.json`。

---

## 2026-09-25（续三）：五个传统工具接入 5.3 对比实验（缺口 A）+ SolidiFI 层次二补齐 6/6

**用户指令**：「完成上述内容后执行所有传统工具的对比实验，不要跑 dive 了。」
⇒ ① DIVE 21 臂矩阵**不重跑**（裁定已落 `dive_external_results.md` §6 第 11 条，含代价）；
② 本轮的实体工作 = 把 5.3 点名的**六个传统工具**从"环境装好但只接了 Slither"补到**六个全部出数**。

### 一、做了什么

| 产物 | 说明 |
| --- | --- |
| `scripts/static_tool_adapters.py`（**新**） | 其余五工具的**调用 / 解析 / 映射表** + 能力边界 + 排除项。**评测部分不在这里** |
| `scripts/baseline_static_tools.py --tool {…}`（改） | 加 `--tool` 分派；`evaluate()` **一行未改** ⇒ 六工具**同一份指标实现**（表的内部可比性靠这条） |
| `scripts/collect_traditional_tools.py`（**新**） | → `experiments/traditional_tools_results.md`（映射/能力/覆盖/成本） |
| `scripts/collect_baseline_tables.py`（改） | 由"只出 Slither 一行"改成**出六行**；缺产物的工具**点名而不静默少行** |
| `tests/test_static_tool_adapters.py`（**新，26 例**） | **每条对应一个已踩到的坑** |
| 产物 | `eval_results/baseline/<工具>_alldata{,.json}`（逐合约原始检测项 + 七维向量 + 状态） |

范围：**三种子 val∪test 并集 = 214 个合约**（Slither 是 2026-09-21 跑的**全 590 图**，
两者范围不同 ⇒ 覆盖率一栏不可横比，已在报告第一节披露）。

### 二、🔴 五个「不报错」的解析陷阱（每个都会让整行数字变成假的）

写错这里**不崩、不抛异常**，只让某个工具的七维向量悄悄变成全零或全一，然后进论文表。

| # | 工具 | 症状 | 真因 |
| --- | --- | --- | --- |
| 1 | securify | 恒空集 | 结果用**展示名**（`Unused Return Pattern`），`--list-patterns` 给的是**类名**（`UnusedReturn`），两套毫无字面关系；真源 = `souffle_analysis/patterns/*.dl` 的 `NAME("…")` |
| 2 | manticore | 恒空集 | 命中写在 `global.findings` 的**描述文本**（`- Reachable SELFDESTRUCT -`），不是 ARGUMENT 名；我原先假设的 `.lst` 文件**根本不存在**；且 `--list-detectors` 本机**直接崩**（上游排序 bug）⇒ ARGUMENT 名只能读源码 |
| 3 | **oyente** | **恒全集（六类全亮）** | 它**把 8 个检查名全打印**、后面才跟 `True`/`False`。只匹配名字 ⇒ 每个合约六类全置 1。**比全零更危险**：micro-F1 看着还不低 |
| 4 | oyente / manticore | 恒空集 | 结果走 **stderr**（Python `logging` 默认 handler）。只解析 stdout ⇒ 什么都没读到 |
| 5 | 全部 | 候选重试**永不触发** | 报错摘要取「最后一行」，而 securify 的 traceback 最后一行是 `> stdout:`，版本线索（`ParserError`）在**倒数第二行**的 `SolcError` 文本里 |

**验证方法（唯一能证明解析器没错的方法）**：拿 **Slither 在同一批合约上报过命中的**做阳性对照 ——
实测四个工具**逐项吻合**（smartcheck `SOLIDITY_UNCHECKED_CALL`、mythril `SWC-104+107`、
oyente `Integer Underflow`+`Re-Entrancy`、manticore `Reachable SELFDESTRUCT`）；
securify 在本池无合格样本，改用**它自带的 `testContract.sol`** 对照。

顺带修掉一处**我自己引入的规则违规**：工具工作目录最初写成仓库根的 `work/`
（硬规则：中间产物只能写 `products/`、`runs/`、`eval_results/`）⇒ 迁到 `runs/_tools_work/` 并补 `.gitignore` 第 70 行。
另修一处**既有违规**：Slither 的 `--json` 原先写在 `source.parent`（= `alldata(readonly)/…`）再删掉，
`finally` 清干净了、无残留，但**瞬时也违规** ⇒ 改到工作目录。

### 三、🔴🔴 方法学发现：**覆盖率不是随机缺失**

读对比表时容易把传统工具那几行低读成"工具弱"。实测不是：

| 族 | pragma | 合约数 | 含漏洞 | 比例 |
| --- | --- | --- | --- | --- |
| **真实池** | 0.4.x | 335 | 128 | **38%** |
| **真实池** | 0.5.x | 147 | **0** | **0%** |
| `buggy_*`（合成注入） | 0.5.x | 80 | 80 | 100% |

⇒ **自然语料里「有漏洞 ⟺ 0.4.x」是完美分离（128 : 0）**；全库那 80 个 0.5.x "漏洞"**全部是合成的 `buggy_*`**
（100% 正例、**不在池 453 的划分里**）——**不分族会得出相反的结论**（我第一版就写错了，是分族才看清）。

连起来的后果：

- **Securify 只吃 pragma 0.5.x** ⇒ 可分析集在真实池里**恰好全是干净合约** ⇒ 其 test 逐类 support
  **恒为 `[0,0,0,0,0,0,0]`**（三种子）⇒ `micro_f1 = 0.0` **不是「预测全错」而是「分母里没有正样本」**
  ⇒ **该行结构性不可评估**。已做成 `degenerate_tools()` **自动检测并报 warning**（不靠人看）。
- **Oyente 钉 solc 0.4.19** ⇒ 可分析面**正好落在漏洞所在的 0.4.x** ⇒ 它是唯一有公平机会的工具。
- 论文写法：这几行**不能只写「分母不同」**（会让读者以为缺失随机），必须同时给出覆盖率与该工具的分集漏洞率。

### 四、🔴 派生取代手写：`no_detector_classes`

退化检查（看"工具预测为 1 的比例"）发现 **SmartCheck 的 40 条规则里根本没有 reentrancy 规则**，
而 `reentrancy` 是本池最大漏洞类（24 个正例）—— 说明它那一格为 0 是「**工具没这个检测项**」。
原先该字段是**手写**的，我给 SmartCheck 写了空元组（= 漏了）。
⇒ 改为**从映射表派生**（差集），并加机检 `test_no_detector_classes_are_derived`
+ `test_smartcheck_lacks_reentrancy_and_front_running` + 与 Slither **手写常量的交叉核对**。

派生结果：Slither 缺 `front_running`；Manticore 缺 `dos`/`time_manipulation`；
**SmartCheck 缺 `reentrancy`/`front_running`**；Oyente 缺 `dos`/`uncheck`；**Mythril / Securify 七类齐全**。

另有两处**跨工具一致性**收获（同一把尺的价值）：securify 的 `arbitrary-send` 与 SmartCheck 的
`SOLIDITY_GAS_LIMIT_IN_LOOPS` 原先都没进草表，是**对照 Slither 的 `arbitrary-send-eth` / `calls-loop` 才发现漏了**；
反过来 `SOLIDITY_BALANCE_EQUALITY`（SmartCheck）与 `lockdrop`（Manticore）是同一概念、都无锚点 ⇒ **两个一起排除**。

### 五、Securify 的能力边界（**两处实测更正**）

1. 不是「≥0.5.8」，而是**只能吃 pragma 0.5.x 的老合约**。按 pragma 分的**最终**成功率：
   **0.5.x 45/46（98%）**、**0.4.x 2/161（1.2%）**、**无 pragma 0/7** ⇒ 总覆盖 **47/214 = 22.0%**。
   ⚠ 中途读数（33 个成功、15.4%、"0.4.x 全数失败 110/110"）是**前 150 个合约**的，
   跑完后作废——**这类"跑到一半的百分比"一律不要写进文档**。
2. **两条失败路径都实测到**（证明"真的不行"而非"参数没调对"）：
   给 0.4.x solc ⇒ `Solc version X not supported by CFG compiler`（`ast_dict[_solc_version]` KeyError）；
   给 0.5.12 ⇒ `SyntaxError: No visibility specified` + `TypeError: Wrong argument count`。
   **pragma 改写只改 pragma 行、不升级语法**，故两条路都堵死。（`decisions.md` §47.4 第 1 条的措辞本轮被更正。）

### 六、SolidiFI 层次二补齐 **6/6 组合**（副产品，同一轮里跑完）

`evaluate_node_localization.py --corpus {main,aug} --all-seeds`，6 组合合计 ≈75 s。P@5（三种子）：

| 语料 | `s_v`（M1 先验，**不含学习**） | `a_v`（模型可疑度） | `g_v`（梯度显著性） |
| --- | --- | --- | --- |
| `main` | **0.0983 ± 0.0000** | 0.0030 ± 0.0029 | 0.0743 ± 0.0436 |
| `aug` | **0.0983 ± 0.0000** | 0.1263 ± 0.0154 | 0.0371 ± 0.0124 |

🔴 **训练得到的显著性没有超过不含学习的先验**（main 0.0743 < 0.0983、aug 0.0371 < 0.0983），
且 **没有任何信号在两语料上都赢过先验**。这正是脚本 docstring 里那条诚实声明的定量证据。
另：① 模型在 SolidiFI 上**预测正确的合约只有 1–3/350**（逐种子 3/1/1；**旧文档的单种子值「1/350」是 seed2**），
② 为 300/350（三种子恒定）⇒ §4.6 那张表**主要是在 347–349 个预测错误的合约上算的**，读的是**排序**不是分类。
落点：`dive_external_results.md` **§4.6（新）** + §0/§6 第 12–14 条、`results.md` §5（重写，单种子读数作废）。

### 七、文档同步与验证

- `decisions.md` **§56（新）**：六工具接入的范围/尺子/陷阱/边界/结果/已知未做（§55 仍保留给混合换位的逐格对照）
- `AGENTS.md`：加入口、三条读表须知、`.gitignore` 新规则说明（含三步自检实测）
- `Todo_List.md` §12.7.1：状态由「剩余工作 = 接入」改为**接入完成**
- `项目组织架构.md`：脚本区 3 条 + `eval_results/solidifi/` + experiments 列表 1 条
- 验证：`pytest tests/ -q` **393 passed / 2 skipped**；`edit_outline.py --verify` **23/23**；
  `.gitignore` 自检 (a)(b) 通过（`runs/_tools_work/` 命中 0、`runs/seed0/best.pt` 未被漏出）

### 八、已知未做（如实记）

- **`_buggy` 池（497）上五个新工具未跑**：那一段目前仍只有 Slither（`slither_buggy`）。
- **DIVE 侧的传统工具未跑**：大纲 5.3 要求"全部对比方法在两种设定下评估"，这条**未完成**。
- **DIVE 21 臂矩阵不重跑**（用户裁定）⇒ `comparison.{json,md}` 的 DIVE 列**永久停在 5 轮档**。

## 2026-09-26/27：5.3 **六工具全部跑完** —— 口径三裁定 + 内存事故与修法

**本轮目标**：把 §56（2026-09-25 接入）之后仍缺的那一步做完 —— **六个传统工具在正典池上全部跑出结果**，
主对比表由五行变**六行**。收工于 **2026-09-27 01:02**。

### 一、结果（六行齐全）

`experiments/baseline_three_caliber_tables.md` 的六行 + `experiments/traditional_tools_results.md` §四
（六工具 × 7 类 F1，含 micro/macro）。Slither 全库 590、其余五个三种子 val∪test 并集 **214**。
逐工具的 status 分布与 test 覆盖见 `decisions.md` §56.7.5。

**Manticore**（本轮唯一真正在跑的）：三类 `micro` = 0.4286 / 0.3333 / 0.4545，
逐类 F1 `access_control 0.4167±0.2205`、`arithmetic 0.6667±0.2309`、`front_running 0.0000`、
`reentrancy 0.4444±0.0962`、`uncheck 0.3333±0.2887`（`dos`/`time_manipulation` 无检测项 ⇒ `—`）。

### 二、三条口径裁定（用户 2026-09-26）

1. **没有该项检测能力的类，表里画 `—`**（不画 `0.0000`）——判据 = 从映射表**派生**的
   `no_detector_classes`。⚠ 但 `—` 有**三种成因**（能力缺失 / 整行不可评估 / 尚未评测），
   三者必须分开点名；而「**跑了但没检出来**」的真实 0 **一律保留**。
2. **新增 † 两列** = 「仅该工具有检测项的类」的 micro/macro（切列重算 + 与产物存档逐位对拍，
   不符即拒绝出数）。🔴 **分母更小 ⇒ 系统性偏高，不得横比到本文方法/三条基线**。
3. **裁定 A：0/0 的 F1 不计成 0** —— 某种子上某类 `support=0` ⇒ F1 未定义，已从该格均值
   **剔除并标 `‡`**。实测受影响格只有 Oyente 的 `time_manipulation`：`0.3333±0.5774` → `0.5000±0.7071‡`。

### 三、🔴 一次真实事故与三条硬教训（decisions §56.7.4）

**内核日志坐实**：2026-09-26 16:59 因**两路并行 + 并发的 pytest** 触发**全局 OOM**
（`constraint=CONSTRAINT_NONE, global_oom`），内核杀掉 **`systemd`（pid 669）**与
**VSCode 的 `MainThread`（pid 831）** ⇒ **VSCode 崩溃、WSL 于 17:02 整体重启**，两次续跑**零进度**。

三条教训（都已落地为机制，不是记在文档里就完）：
1. **落盘间隔必须远小于崩溃间隔** —— 原本每 10 个合约落盘 ≈27 min，与崩溃间隔同量级 ⇒
   永远走不到第一个落盘点。已加 `--flush-every`（**默认值与旧行为逐字相同**），长跑用 1。
2. **cgroup 上限会被 systemd 连带执行** —— 默认 `KillMode=control-group` 下，cgroup 一 OOM，
   systemd 把整个 scope 判失败并 SIGTERM ⇒ 驱动 `rc=143`、在飞合约白跑（**活锁**，实测三次尝试
   全死在 z3 被杀的同一秒）。修法：scope 加 **`-p KillMode=process -p OOMPolicy=continue`**
   （用 `sleep 300` 旁观进程实测验证：吃内存的进程照旧被杀、驱动存活）。
3. **上限的代价要按"受影响合约数"披露，不是击杀次数** —— 实测 45 次击杀只对应 **8 个合约**
   （3.7%），因为一个超重合约会在几十秒内被连杀 9~10 次（杀的多是 `manticore` 主进程）。

**最终配置**：单路 + cgroup **4.5 GB**（本机 WSL 总内存 7.8 GB、基线 VSCode ≈2.3 GB；
取 5 GB 则余量只剩 0.5 GB，而全局 OOM 的首选靶子是 `oom_score_adj=100` 的 `systemd --user`）。
**零新增击杀**出现在绝大多数合约上（普通合约 cgroup 只用 0.3~0.4 GB），上限只在极少数超重合约上兜底。

### 四、数据来源的一处坑

`/var/log/syslog` 于 **2026-09-27 00:00 被 logrotate 轮转**，续跑脚本收尾时只数到轮转后的 3 次
⇒ 边车 `run_env.json` 的原始计数**被截断**。已由 `syslog.1 + syslog` 合并重算并**回填**，
新增 `affected_contracts` / `affected_contracts_derivation` 两字段自述来源。
**教训：依赖 `/var/log` 的计数必须先确认轮转边界。**

### 五、文档与自检

- `decisions.md` **§56.7**（新，含 56.7.1–56.7.5）：三条口径裁定 + 四条工程结论 + 最终结果表
- `AGENTS.md`：读表须知 **三条 → 六条**（④†两列、⑤裁定A、⑥跑动环境）；`.gitignore` 三步自检
  **(a)** `run_env.json`/`seed{S}_eval.json`/`best.pt` 按既定口径**入库**、`_tools_work/*` 被忽略；
  **(b)** `git add -A --dry-run` **6914 文件 / 0.479 GB / 最大 9.37 MB / 无 >100MB**；**(c)** 文字同步
- `Todo_List.md` / `report_conclusions.md` / `report_data.md` / `results.md`：四处「其余 5 个工具未实跑」
  改为事实状态；`项目组织架构.md` 记录 `run_env.json` 边车必须入库的理由
- 报告生成器的两处修正：§四小节编号错序（`四→六→五`）、缺工具注记「未接入」→「**无产物**」
- 验证：`pytest tests/ -q` **418 passed / 2 skipped**；回归测试 **+9 条**（三种 `—` 判据、† 口径、
  裁定 A、边车披露、整行皆 `—` 时的 `KeyError` 守卫）

### 六、仍未做（如实记，同 §56.6）

- **`_buggy` 池（497）上五个新工具未跑**（那一段仍只有 Slither）
- **DIVE 侧的传统工具未跑**（大纲 5.3「两种设定」这一条仍未闭合）
- 成本口径：六工具记的是**分析成本**、方法/基线记的是**训练成本**，**两者分母不同、不可横比**；
  若要一张同口径的端到端成本表，需补 M3 重编码与 EGFL 离线特征的耗时（见本轮对话，待用户裁定）

## 2026-09-27：新增「逐类 binary-F1 @逐类验证集阈值」的**正典 + 消融**表（零重训）

### 一、为什么做

用户指令：输出主库正典（含 `buggy_*`）与**逐个消融选项**的逐类 binary-F1 @逐类验证集阈值 +
micro-F1 + macro-F1。此口径此前**只有正典一行**（`experiments/gcn_baseline_and_per_class_f1.md`、
`baseline_three_caliber_tables.md` 表 1/15 的「本文方法」行），**21 个消融臂从没有过**——
而它回答的正是「某消融在**某一类**上到底怎样」，与 `ablation_three_metric_table.md`（七类共享
一个 `val_threshold`，只有 micro/buggy/macro 汇总列）互补。

### 二、产物（三件，全部新增、零重训、零重搜之外的零成本）

| 件 | 路径 |
| --- | --- |
| 生成脚本 | `scripts/collect_per_class_binary_thr.py`（**纯聚合层**） |
| 报告（2 张表 × 22 行） | `experiments/per_class_binary_thr_ablation.md`（98 行 / 3 表） |
| 数据产物 | `eval_results/per_class_binary_thr.json`（101 KB，含逐种子阈值可复核） |

**口径零新增**（全部复用既有唯一实现，不写第二份）：
逐类阈值 ← `calibrate.per_class_thresholds`；应用 ← `calibrate.apply_per_class`；
指标 ← `metrics.per_class_prf/micro_f1/macro_f1`；消融的层名/变量名 ← `collect_ablation_three_metric.LAYERS`。
两池 = 池 453（`runs/seed{S}` + `runs/ablation/{臂}/seed{S}`）与池 497
（`runs/buggy_canon/seed{S}` + `runs/ablation_buggy/{臂}/seed{S}`）；覆盖实测 **2 × 22 行全齐**
（21 臂 × 3 种子的 `test_probs.pt` + `val_best_probs.pt` 一个不缺）。

### 三、两条硬机检（默认执行，不通过即 `exit 1` 且不落盘）

① **对拍**：池 453 正典行的 7 个逐类格 + micro + macro 与
`eval_results/calibration/summary.json::test_schemes.per_class_threshold` **逐位相同**（容差 1e-6）
⇒ 本脚本无第二套 per-class 阈值实现。② **恒等式**：每行每种子的 `metrics.macro_f1`
**逐位等于**其 7 个逐类 F1 的算术平均（`zero_division=0` 下数学恒等）⇒ 类序与 zero 处理未被改动。

### 四、🔴 首次运行踩到的坑（写进脚本注释与 docstring）

初次对拍**误报 7 处「不一致」**（如 `dos` 复算 0.4333 vs 存量 0.433333）。根因不是口径错，而是
**拿显示层舍入到 4 位的值去比存量 6 位值**（容差 1e-6）⇒ 修法 = 对拍一律走**未舍入的逐种子原始值**
（`_raw_pc` / `micro_per_seed`），显示层才降到 4 位。**教训**：
**呈现精度与比较精度必须分开**——否则守卫本身会变成假警报源，读者会开始怀疑真差异。

另一处**自我更正**：初稿把 support 行写成「test 合约数 = 逐类 support 之和」——**多标签下不成立**
（一个合约可含多类）。已改为从数据取 `n_test`，并显式写明「support 之和 ≠ test 合约数」。

### 五、⚠ 两条谱系的非对称（如实记）

池 497 **没有**对应的 `eval_results/calibration/` 校准产物（该目录只有池 453 的）
⇒ 表 2 只有机检 ② 覆盖、**无机检 ①**。这是本表在两条谱系上唯一的非对称，已写在报告正文里。

### 六、文档同步与自检

- `docs/results_tables_index.md`：§2 新增一行（96 行 / 3 表 / 需 `--write`）、§5 新增复现命令、
  §3.B 补该表与 `ablation_three_metric_table.md` 的**同族不同工作点**关系、§4 陷阱表补
  「逐类阈值是并列口径不是主口径」一行。
- `log.md`：本条（**注意本文件即 log.md**）。
- 入库自检：`git check-ignore -v` 三个新文件**均未被忽略**（=按既定口径入库，判据是打出的规则带不带 `!`）；
  `eval_results/per_class_binary_thr.json` 101 KB，**无 >100 MB**；本次**不是新目录形态**
  （`eval_results/` 下的普通文件，与既有 `per_class_f1.json` 同款）⇒ 无需新增 `.gitignore` 规则。


# 五工具补跑池 497（2026-09-28）

- 补齐 `experiments/baseline_three_caliber_tables.md`「三、」段的六工具行（此前只有 Slither）。
  只跑差集 **92 个**（工具输出与划分无关，144 个复用），六工具串行 + cgroup 4.5G，约 7 h。
- 🔴 **预算逐工具显式传**并对齐 canon37 产物：`smartcheck/securify/oyente 120`、`mythril/manticore 180`。
  适配器默认与产物记录差三个工具（securify/oyente 180、manticore 300）——v1 漏传已踩到，删副本重跑。
- 🔴 20:23 那次中断**不是 OOM**（`journalctl -b -1` 末尾是完整 poweroff 序列、当日 syslog 无 oom 行）
  ⇒ 是 WSL 整体关机；已改为 `setsid` 脱离会话 + 监护自愈。
- manticore 池 497 逐 scope 击杀 **11 次**（已回填 `run_env.json`）；Securify/Oyente 两行的
  **正样本来源**（真实 0 正例 / 真实 ≈100% 正例）见 `decisions.md` §57，**引用前必读**。
- 报告已重生成：canon37 段逐字节不变（diff 实测 0 差异）。

# 两语料逐类 F1 总表（① 主库 / ② 增强集，2026-09-28）

- 新增 `experiments/main_aug_f1_summary.md`（程序生成，`scripts/collect_main_aug_f1_summary.py`）：
  **行 = ① 主库 / ② 增强集 × 本文方法/三论文基线/六传统工具**，
  **列 = 7 类逐类 F1 + `micro-F1` + `macro-F1`**（两列汇总并排，同源于同一批逐类 F1，不产生口径混用）。
- 🔴 **为什么需要它**：现有两份表各缺一半 —— `per_class_three_caliber_tables.md` 有 ①② 的逐类
  但**没有**基线/工具，`baseline_three_caliber_tables.md` 有基线/工具但**只有 ①**。
  于是「② 上基线/工具是多少」在两份文件里都**看不出来**（沉默长得像「不在范围」）。
- 🔴 **实测结论：② 增强集上三条论文基线与六个传统工具全部未跑**（共 10 行，报告 §4 逐条点名）。
  根因：`baseline_common.LAYOUTS` 只有 `canon37`/`buggy` 两个 layout，**没有 `aug`**；
  六工具的产物根 `{tool}_alldata{suffix}` 的 suffix 也由 layout 派生。
  补跑成本与两个必须先解决的口径问题（② 的可分析集上逐类 support 是否全 0 **须实测、不可外推 ① 的结论**）
  已写进 §4，**待作者裁定**。
- 🔴 **`--check` 逐格对拍守卫**：与另两份**不同脚本**生成的表比对 **234 格**（非自证）。
  本轮它抓到两次真问题，都是**解析器**的、不是数字的：
  ① 全文件扫表导致 `baseline_three_caliber_tables.md` 的 §三之二（池 497）**静默覆盖** §二（池 453）
     ⇒ 报出 158 格假不一致；
  ② 行名 `**① 主库 · 本文方法（正典）**` 先剥 `**` 再判语料，否则两行**静默跳过对拍**
     （`checked` 少 36 格却仍报「通过」）。
  ⇒ 两条都写进了代码注释；`checked == 0` 一律判失败（虚假的安心比不检查更危险）。
- 变异测试：手动改掉 ① 本文方法 @0.5 的 `reentrancy` 一格 → 两份参照表**同时**报不一致、rc=1。
- 文档同步：`docs/results_tables_index.md` §2 新增一行、§3.A 新增一条、§4「`—` 三种成因」一行
  补注「本表的 `—` **只有 `未评测` 一种**，不可与另两表的 `—` 互相套用读法」、§5 补复现命令。

# 混淆计数审计：micro/macro 背后的 TP/FP/FN（2026-09-28）

- 新增 `experiments/confusion_counts.md`（程序生成，`scripts/audit_confusion_counts.py`）。
  回答「micro-F1 0.8129 是怎么来的」—— 此前**全仓没有一处**存混淆矩阵：
  `runs/seed{S}/results.json` 只存 P/R/F1，`<工具>_alldata/seed{S}_eval.json` 更只有 F1 与 support。
- 🔴 **计数单位 = `(合约, 类)` 标签对**（不是合约）。`micro = 2TP/(2TP+FP+FN)` 用**池化**计数；
  `macro = mean(7 个逐类 F1)` 用**逐类**计数 ⇒ **macro 无法由池化计数反推**，两列都列。
- 🔴 **实测暴露的量级差**：① 主库 seed0 的池化计数只有 **TP=17 / FP=4 / FN=4**
  （测试集 46 合约 × 7 = 322 个标签对，其中真值 1 的仅 **21** 个）。
  ⇒ micro-F1 几乎只由「这 21 个正标签对抓到几个」决定，负标签对只通过 FP 参与；
  而 macro 被 support=1 的类（`dos`/`front_running`/`time_manipulation`）单次翻转拖到 0。
  **这正是「micro 高、macro 低」的算术来源**，不是两个模型。
- 🔴 **三种子的计数不可相加**（每种子不同划分 + 不同模型）⇒ 报告**逐种子**列计数、不列合计；
  表里报的 mean±std 是**逐种子 F1 的均值**（实测 ① @0.5：0.8095/0.8293/0.8000 → 0.8129 逐位吻合），
  **不是**「计数均值再套公式」（Jensen 不等式，两者不是一回事）。
- 🔴 **自带对拍 = 敢出数的依据**：从 `test_probs.pt` / 原始检测器 JSON 重新取 `(y, p)`，
  与产物存档的 micro/macro **逐位比对**，不符即 `SystemExit`（54 条记录全过）。
  本轮该对拍**当场抓到我自己的一处错**：把 `thresholds.json` 的**验证集阈值**拿去对拍 `fixed_0.5` 档。
  ⇒ 「先对拍再用数」不是形式主义，它抓的正是「看着都合理、只是对不上」那类错。
- 文档同步：`docs/results_tables_index.md` §2 新增一行、§5 补复现命令。
