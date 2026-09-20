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
- 目录与状态详情见 `项目组织架构.md` 末节。
