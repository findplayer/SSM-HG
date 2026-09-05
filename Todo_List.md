# SSM-HG 开发 TODO（按真实代码依赖修正）

> 版本：2026-09-05（M1/M2 第五轮定向审计收尾版；Stage 0、M1、M2 完成并审计关闭；下一步进入 M3）
> 依据：论文开发手册修订版 + 当前仓库真实状态
> 先决条件：先修好 Stage 0，再动 M2；M2 是第一最小原子模块，不要跳过。

## 一、项目总原则
- 以大纲为准，旧脚本/旧手册冲突时以修订手册为准。
- 单步最小验证：每改一个模块，先跑 1 个样本，再批量。
- 先保证图数据正确，再进入 M1/M3/M4/M5。
- 真实路径必须使用：
  - AST: raw/AST-raw
  - CFG: raw/CFG-raw
  - DFG: raw/DFG-raw
  - Hetero（全部图产物 _hetero.json/_m1.json/_pyg.pt/M3 缓存）: Heterogeneous graphs
  - 源码根（只读数据源）: alldata(readonly)/alldata_sol_source
  - 主标签: alldata(readonly)/contract_labels.json
  - 生成脚本: scripts/（generate_all_ast_cfg_dfg.sh、dump_cfg.py、build_cfg_centered_hetero_graph.py、m1_runner.py、convert_hetero_json_to_pyg.py、priori_scoring.py）

## 二、Stage 0：新目录就位 + 生成 raw 原始产物
- [x] 文件已收拢到 scripts/
  - [x] 生成脚本已位于 SSM-HG/scripts/
  - [x] priori_scoring.py（由 anchor_detectors.py 改名）、convert_hetero_json_to_pyg.py、build_cfg_centered_hetero_graph.py、m1_runner.py、generate_all_ast_cfg_dfg.sh 均确认在 scripts/ 下
- [x] 修正默认脚本路径/参数（2026-09-02）
  - [x] build_cfg_centered_hetero_graph.py 默认路径改为 raw/{AST-raw,CFG-raw,DFG-raw} 与 Heterogeneous graphs（已消除末尾空格问题）
  - [x] convert_hetero_json_to_pyg.py / m1_runner.py 默认 in/out 均为 Heterogeneous graphs
  - [x] generate_all_ast_cfg_dfg.sh 的 AST_DIR/CFG_DIR/DFG_DIR 指向 raw/*，SRC_ROOT 指向 alldata(readonly)/alldata_sol_source
  - [x] 运行脚本统一用 `python scripts/xxx.py`（从 SSM-HG 根目录执行）
- [x] 从只读数据源生成 raw 原始产物（2026-09-02 完成）
  - [x] 运行 `bash scripts/generate_all_ast_cfg_dfg.sh`（先 nasd_simple_dao 单样本试跑通过，再全量）
  - [x] raw/AST-raw 生成 581 个 *.json（591 − 1 个 >50 行 assembly 过滤 − 9 个 delegatecall 动态绑定过滤）
  - [x] raw/CFG-raw 生成 24672 个 *.dot（每函数一个）+ 同名 `*__cfgdetail.json` 581 个
  - [x] raw/DFG-raw 生成 581 个 *_dfg.txt
  - [x] 单样本输出核验：文件命名与源码项目/合约名对应，AST/CFG/DFG/cfgdetail 四类产物齐全
- [x] 修正批量脚本（工具链对齐大纲）
  - [x] 修正 pragma 选择逻辑：从“优先 0.4.x”改为“优先 0.8.x + 缺失时回退 0.8.x”（select_no_pragma_version）
  - [x] 2026-09-04 修正版本选择：select_solc_version / select_no_pragma_version 改为降序取最高满足版本（修复极老 solc（≤0.4.10）无 srcmap → 22 个合约 cfgdetail 行号全空；单样本复现与验证通过）
  - [x] dump_cfg.py 输出新增 meta.nodes / meta.line_missing，行号缺失 >0 时 stderr 告警（向后兼容）
  - [x] 全量重生成 raw（2026-09-04 完成）：581 合约；cfgdetail line_missing=0（原 471 节点无行号）；AST 版本分布 0.4.26×213 / 0.5.17×209 / 0.4.24×84；TownCrier 回退 0.4.19（cfg_retried=1）；重建异构图 → m1_runner --force → convert_pyg 全部完成，前后对比通过（M1 命中基本不变）
  - [x] 增加 filter_report.txt 统计过滤项
    - [x] AST/CFG/DFG 生成失败数
    - [x] >50 行 assembly 数
    - [x] delegatecall 动态绑定数
    - [x] Slither ERROR 合约数
    - [x] 记录每类过滤数量和占比
  - [x] 新增 scripts/dump_cfg.py（Slither API 导出带 seq/true/false 分支类型的 CFG，已接入批量脚本）
  - [x] CFG 明细输出节点 unchecked 状态，供 M1 arithmetic 规则使用
  - [x] 启动时清理旧 *__cfgdetail.json，避免重跑后 AST/CFG 错配
  - [x] 单样本试跑修复 dump_cfg.py 三处 Slither 0.11.5 兼容问题（NodeType.IFLOOP、Function 无 .kind、source_mapping.lines 元素 int/tuple 混合）
- [x] 构建全量异构图到 Heterogeneous graphs/（2026-09-03 完成）
  - [x] 执行 `python scripts/build_cfg_centered_hetero_graph.py`（默认参数，--src-root 指向只读数据源）
  - [x] Heterogeneous graphs/ 生成与 raw/AST-raw 对应的 581 个 *_hetero.json（93545 节点；CFG_FLOW 71291 / AST_PARENT 1959 / AST_PARENT_SAME 6045 / DFG_DEP 30047 / CALLBACK_RISK 6335，188 图含回调边；ir 缺失仅 11；0 图缺 functions）
  - [x] 检查一份样本输出，确认 meta.cfg_node_count 与边键 CFG_FLOW / AST_PARENT / AST_PARENT_SAME / DFG_DEP / CALLBACK_RISK 齐全，seq+true+false == cfg_edge_count
  - [x] _hetero.json(581) 与 _pyg.pt(581) 已落在 Heterogeneous graphs/ 同一目录；_m1.json 待 M1 运行生成
  - [x] 说明 `raw/Callback-raw` 不作为原始产物目录；回调信息存于 `_hetero.json` 的 `CALLBACK_RISK` 边；`CFG-raw` 中允许存在合法 `digraph{}` 空函数图

## 二点五、生成脚本健壮性修改（2026-09-04 完成并验证）
- [x] generate_all_ast_cfg_dfg.sh：删除死代码 slither_error 分支，DFG 失败路径统一清理产物并计 slither_error_count
- [x] CFG 失败自动回退较低版本重试（Slither 对 0.4.12+ AST 常量折叠崩溃 NotConstant；TownCrier 实测 0.4.26 失败→回退 0.4.19 成功，AST 同步重生成）
- [x] 日志移出输出目录：AST_ERR/CFG_ERR/DFG_ERR → raw/logs/；成功路径不再把 solc/slither 告警写入 error 日志
- [x] 删除 SVG 生成（dot -Tsvg 无人消费）；启动清理补 *.svg；现有 24678 个陈旧 SVG 已清理
- [x] assembly>50 行过滤改花括号深度计数（原 awk 遇嵌套括号提前闭合）
- [x] extract_pragma_expr 过滤注释行并保留 -o（修复 CRLF 行尾使 `;$` 剥离失败 → pragma 变 `^0.4.9; ` 的 bug）
- [x] 目录硬编码绝对路径改 "$REPO_ROOT" 拼接
- [x] dot 文件名超 255 字节时哈希截断（EtherDelta/SigningLogicInterface/DaiPriceOracle 等）
- [x] 验证：TownCrier 定向重生成（单文件 runner），raw 三目录均 581 齐全，filter_report 更新（cfg_failed=0, cfg_retried_lower_version=1）
- [x] 2026-09-05 生成脚本第三轮修复
  - [x] dump_cfg.py：source_mapping.lines 的 tuple 按 (start,end) 行区间展开（多行节点 is_unchecked/行号窗口补齐）；receive/fallback 显式命名（receive→"receive"、fallback→"fallback"），不再归一成 fallback
  - [x] build_cfg_centered_hetero_graph.py：expand_token_keys 补成员名回退键（self.credit→credit，与变量纯名字键对齐；msg./block./tx. 前缀除外，this.balance→balance 属正确语义）；RE_BALANCE_MAPPING 改 \b(?:balances?|mapping)\b（补 balances 复数）；parse_dfg 返回三元组并统计非表行，meta 新增 dfg_non_table_lines（2026-09-05 口径修复：排除 +--- 表边框分隔线，只计 solc 命令日志等真噪声行）；find_source_file 同名多候选时 stderr 告警；callback_avg_edges 分母口径注释（含被过滤候选）
  - [x] generate_all_ast_cfg_dfg.sh：pragma_matches_version 支持 ~x.y.z（>=x.y.z 且 <x.(y+1).0，major=0 同 caret）；新增 pragma_missing_count/no_version_count 计数并写入 filter_report（当前源码无 ~ pragma 文件，防御性修复，raw 无需重跑）
  - [x] 重跑 build → m1_runner --force → convert_pyg 两次，结果完全一致（确定性验证通过）
- [x] 2026-09-05 生成脚本第四轮修复
  - [x] build_cfg_centered_hetero_graph.py：RE_BALANCE_MAPPING 改写入方向正则（balances[x] (...) := 与 (->balances) :=；读取 -> balances[x] 不再误判，mapping 关键字分支删除；全库 CALLBACK_RISK 6171→5914、163→141 图；etherstore 纯读取节点误判 0、状态写正确识别 2，读/写方向验证通过）；parse_dfg 删除不可达死代码（非表行分支之后的 line.startswith('+')）；main 简化冗余跳过条件（cfgdetail_invalid 尚未检测不参与首个条件）；cfgdetail 路径 find_expression_span 行号回填不共享缓存（cache=None，修复同表达式跨函数错配隐患，缓存键无函数上下文）；补 walk_ast/normalize_function_name/parse_cfg_filename/node_is_state_write/node_has_transfer_or_balance 五个 docstring
  - [x] dump_cfg.py sons[0]=true 分支约定人工核对通过（抽查多个含 if/循环的 cfgdetail，then 分支第一行对应 kind=true 后继；手册 7.4.3 补记）
- [x] 2026-09-05 60 个新样本批量审计（/tmp/audit60.py，排除已抽查样本）：图结构/m1 结构自洽 0 问题（节点数/CFG 三类计数/callback 上限/functions/ir_missing/键约定/分数范围）；标签匹配 581 图全覆盖（0 无标签）；非 buggy 真实合约召回 100%（26 条漏检全部集中在 buggy_* 噪声项目，与已定稿剔除策略一致）；发现前缀剥离顺序坑（先 nasd_ 后 asd_，已同步手册 10.2/12 新增 36/Todo 12.5）；补 m1_runner 7 个函数（parse_args/as_node_key/count_hits/build_meta/build_summary/run_one/main）与 priori_scoring.from_json_file 的 docstring
## 三、M2：第一最小原子模块（已完成）
- [x] 修正 hetero 图结构，保证后续 M1/M3/M4/M5 都能消费
- [x] 需要补齐字段（脚本已实现，待 1 个样本输出核验）
  - [x] 每个 CFGNode 补充 ir 字段（SlithIR 文本）
  - [x] 补充 functions 字段（可见性、receive/fallback、起止行等）
  - [x] 补充 meta.state_vars / function metadata
  - [x] CFG_FLOW 按三子类区分：顺序 / 真分支 / 假分支
  - [x] CALLBACK_RISK 边新增，保守先验（8 步算法 + --callback-limit 默认 4）
- [x] 修正图生成脚本
  - [x] 修改 scripts/build_cfg_centered_hetero_graph.py
  - [x] 处理 CFG dot 的 IR 段提取
  - [x] 补全函数级元信息
  - [x] 处理回调风险边构建逻辑
  - [x] 新建 scripts/dump_cfg.py 并集成 cfgdetail（缺失时回退 dot，meta 记 cfgdetail_missing）
  - [x] receive() 与 fallback() 分别命名，不再合并
  - [x] 源码定位优先按 base 还原相对路径，避免同名 .sol 配错
  - [x] 2026-09-04 DFG 重建修订：parse_dfg 保留合同级变量行（(contract,None)）；build_dfg_edges 状态变量用合同级 def/use 索引（跨函数 def→use）、局部变量按函数索引、src=dep定义(否则使用)、dst=var定义∪使用、排除自环（全库 DFG 30047→146242 边，零 DFG 边图 72→12）
  - [x] 2026-09-04 CALLBACK_RISK 状态写判定改词边界正则 \b(?:balance|mapping)\b（避免 balanceOf 读取误判；全库 CALLBACK_RISK 6335→6085 边）
  - [x] 2026-09-04 构图脚本杂项：无 CFG/无 cfgdetail 合约加 skipped_no_cfg 计数；删除 find_source_file 旧目录（reentrancy_contract/sol_source）偏好；dot 回退路径函数名前导下划线回退兼容
  - [x] 2026-09-04 全量重建 + 回归：异构图 581（93551 节点，CFG_FLOW 71296 / AST_PARENT 1957 / AST_PARENT_SAME 6035 / DFG_DEP 146242 / CALLBACK_RISK 6085）→ M1 重跑（21877 命中，与修复前基本一致）→ PyG 581 转换，前后对比与召回审计通过
  - [x] CALLBACK_RISK 入口节点类型兼容 Slither 0.11.5 枚举名 ENTRYPOINT（无下划线）
  - [x] walk_ast 兼容 0.4.x legacy AST：visibility/stateMutability/kind/stateVariable 缺失时按布尔属性与作用域回退
- [x] 验收
  - [x] 581 个样本的 hetero JSON 均输出 `ir` 字段及 `ir_missing` 统计
  - [x] 能输出 functions 列表
  - [x] 能输出 CFG_FLOW/AST_PARENT/AST_PARENT_SAME/DFG_DEP/CALLBACK_RISK
  - [x] 全量结构回归通过：节点数、CFG 三类计数、回调边同函数后继状态写入约束均一致

## 四、M1：静态规则打分
- [x] 确认 priori_scoring.py（scripts/ 下）可正常导入（m1_runner.py 导入已同步为 `from priori_scoring import ...`，import 验证通过）
- [x] 打分算法已对齐大纲 4.1.3（脚本已实现并完成全量核验）
  - [x] 命中一类 +1、external_callback +0.5、累加
  - [x] 全图 min-max 归一化（m1_runner 层完成，全 0 保持 0）
  - [x] 规则读取 expression + ir 双信息源（M2 补全后生效）
- [x] 第二轮审查：按七类漏洞触发方式逐条修订规则（2026-09-04 完成，与 MVD-HG 数据集标注逻辑核对）
  - [x] reentrancy：具备重入能力的外部调用（call.value/call{value:} 非 0、ir HIGH_LEVEL_CALL、或内部调用指向含此类调用的函数——跨函数重入）+ CEI 安全判据（“调用前已写状态且调用后无写入”才不命中）；.send/.transfer（2300 gas 无法重入）与 call.value(0) 不命中
  - [x] arithmetic：pragma<0.8 合约二元/复合/自增自减全量命中（编译器无内置检查）；0.8+ 仅 unchecked{} 内命中（detect_pre_0_8 从 meta.source_path 解析 pragma，无 pragma 按 0.8.x）
  - [x] access_control：改 tx.origin / selfdestruct / 非 msg.sender 单参数 transfer/send；msg.sender.transfer 退款与多参数 ERC20 转账不命中（原“权限关键字共现”逻辑反了）
  - [x] uncheck_return：补内联消费判定（require/assert/if(...) 直接包住调用、调用节点为 IF 节点 → 已检查）
  - [x] dos：四类锚点——非常量界循环条件（i<numbers / i<length / while(true)）、循环内状态数组 push、非 msg.sender 收款单参数 send（意外 revert/退款 DoS）、循环内外部调用
  - [x] front_running：排除纯字面量 RHS（常量写入不构成 TOD）；状态变量大小写敏感匹配（局部 acc ≠ 状态变量 Acc，成员写入 acc.balance 按基变量回退大小写不敏感）
  - [x] time_manipulation：与 block.timestamp/now 触发一致，保持不变
- [x] 第三轮审计：按 alldata(readonly)/contract_labels.json 做图级召回/精度核对（2026-09-04）
  - [x] 真实合约（非 buggy_X）上 reentrancy/dos/time_manipulation/uncheck_return 漏检图 = 0；arithmetic 漏检 6 图为无算术运算的标签噪声；access_control 召回 0.97
  - [x] front_running 召回 0.99、精度 0.15（任何合约都有状态写入，属预期）；buggy_X 七类全 1 注入标签与具体特征不对应，不作判据
- [x] 运行 m1_runner.py 生成 _m1.json（2026-09-03 完成）
  - [x] 命令: python scripts/m1_runner.py --in-dir "Heterogeneous graphs" --out-dir "Heterogeneous graphs" --force（581 个全部处理）
  - [x] 输入目录: Heterogeneous graphs（*_hetero.json）
  - [x] 输出目录: Heterogeneous graphs（与 _hetero.json 同目录，文件为 *_m1.json，不冲突；batch_summary.json 同目录）
  - [x] 2026-09-04 规则修订后全量重跑（--force 覆盖 581 个，耗时约 5s，共重跑 3 轮）
- [x] 验收规则
  - [x] node_flags 仅保留 seven-way boolean
  - [x] node_scores 为 [0,1] 标量
  - [x] 规则必须遵循大纲：不做 DFG 反向一跳传播
  - [x] external_callback 仅加 0.5 分，不作为第 8 类标签
  - [x] 全图 min-max 归一化
- [x] 检查输出
  - [x] 2026-09-05 最终全量重跑（两次一致）：93551 节点中 21568 命中；reentrancy 1629 / front_running 11004 / access_control 3774 / time_manipulation 832 / uncheck_return 540 / dos 199 / arithmetic 9290（命中图数 reentrancy 263 / front_running 525 / access_control 174 / time_manipulation 134 / uncheck_return 103 / dos 73 / arithmetic 468）
  - [x] 样本验收：`msg.sender.call.value(_am)()` 命中 reentrancy、DAO 模式（balance 先扣、credit 后清零）命中、CEI 先扣后转不命中、跨函数（bonus）命中、`block.timestamp/now` 命中 time_manipulation、`require(token.send(...))`/IF 节点内联消费后不判 uncheck_return、`tx.origin` 命中 access_control、`i < numbers`/`listAddresses.push`/非 msg.sender send 命中 dos、`.send/.transfer` 不命中 reentrancy、局部 `acc` 不误判 front_running
- [x] 第四轮修复与抽查（2026-09-05）
  - [x] minmax_normalize 单命中修复：全 0 保持 0、仅一个非零值置 1（旧实现 high==low 整体清零丢失唯一信号）
  - [x] _m1.json meta.exclusive_priority 改为记录真实仲裁顺序 EXCLUSIVE_RULE_PRIORITY（旧记录 VULN_CLASSES 顺序有误导）；meta.source_path 改名 graph_path_abs（绝对路径语义）
  - [x] batch_summary 新增 total_class_hits / class_hit_graphs（全库七类命中节点数与命中图数）
  - [x] dos 锚点①限定循环条件节点：_LOOP_CONDITION_NODE_TYPES = {IFLOOP, IF_LOOP, WHILE, FOR, DO_WHILE}（排除 STARTLOOP/ENDLOOP init/step 误判；注意图中枚举名为 IFLOOP 无下划线，初版误写 IF_LOOP 导致 dos 掉到 100，已修正回 198）
  - [x] 抽查 15 个样本（reentrancy_dao/etherstore/king_of_the_ether_throne/modifier_reentrancy/integer_overflow_1/phishable/simple_suicide/unchecked_return_value/dos_number/send_loop/list_dos/eth_tx_order_dependence_minimal/odds_and_evens/timelock/timed_crowdsale）与规则逐条对照通过（dos_number 命中 i<numbers 无界循环、send_loop 命中 x<refundAddresses.length+循环内 send 等）
  - [x] 2026-09-05 第二批新样本抽查（10 个：buggy_5/insecure_transfer/buggy_3/buggy_21/buggy_40/incorrect_constructor_name1/四个 0x 哈希合约）：命中均与源码一致（insecure_transfer 实际为算术溢出模式，uncheck_return 不命中属正常）；发现两处问题并修复：front_running 把 owner = address(0) 常量写入误报（_RE_PURE_LITERAL 补 address(0)，-309 节点）；dfg_non_table_lines 把 +--- 表边框分隔线误计为噪声（parse_dfg 排除 + 前缀，只计 solc 日志等真噪声行）
  - [x] 2026-09-05 八项修复复核：V1 minmax 单命中 25 图全对/全零图 7 个保持 0；V2 dos 无 STARTLOOP/ENDLOOP 命中（IFLOOP 98/IF 10/EXPRESSION 79/VARIABLE 11）；V3 exclusive_priority 581/581 与真实仲裁顺序一致；V4 前 60 图 3128 个多行节点区间展开正确；V5 全库 receive=0（0.4.x 无此关键字）/fallback=178；V6 batch 聚合全量重算一致；V7 dfg_non_table_lines 581/581 与文件实际一致（修复后）；V8 node_flags/scores/labels 键与节点 id 字符串一一对应 581/581
  - [x] 2026-09-05 召回增强：dos 锚点②扩展动态数组 length 自增模式（array.length += 1 / ++ / = array.length + 1），与 .push() 共用循环祖先+状态数组判定；dos_number 的 array.length += 1 独立命中（全库 dos 198→199，该图 dos 命中 2 节点）
  - [x] 2026-09-05 第五轮定向审计收尾：4 张非 buggy 真漏洞图逐节点核对（EtherBank / Reentrancy_cross_function / IntegerOverflowSingleTransaction 命中全语义正确；FindThisHash 全 0 漏检）；front_running 语义正样本仅 4 个（EthTxOrderDependenceMinimal / OddsAndEvens / ERC20 命中，FindThisHash 漏）；FindThisHash 为 constant 猜谜竞态孤例、无形态锚点、不扩规则，记为已知局限（手册 6.3 / 12-37）；M1/M2 审计收尾关闭，下一步进入 M3

## 五、M2 → PyG 适配
- [x] convert_hetero_json_to_pyg.py 位于 scripts/ 下（无需 git restore），默认 in/out 均为 Heterogeneous graphs
- [x] 生成 _pyg.pt 约定格式（脚本已按手册 7.7 对齐，待真实输出核验）
  - [x] x: torch.zeros(N,1)（M3 后替换为 128 维 h_v^(0)）
  - [x] edge_index（2×E）
  - [x] edge_type（关系编号 0=CFG_FLOW / 1=AST_PARENT / 2=AST_PARENT_SAME / 3=DFG_DEP / 4=CALLBACK_RISK）
  - [x] node_id / contract / function / expression / line_start / label(torch.zeros(7))
- [x] 验收
  - [x] 1 个样本能转成 PyG 图对象（581 个全部转换成功，torch.load 验证通过）
  - [x] edge_type 与 hetero 边类型一致（关系编号 0-4 分布与 hetero 边数一一对应）
  - [x] 节点元数据可供 M3/M4 使用；`x` 保持 M3 前的占位 N×1，后续由 M3 替换为 128 维

## 六、M3：双通道节点初始化
- [ ] 文件组织（2026-09-04 再设计）：是否需要改动 = 是
  - [ ] 只需新建 scripts/m3_build_features.py；产物 = _cb.pt + {safe}_feat.pt
  - [ ] _feat.pt 语义锁死：MLP 之后的 128 维 h_v(0)（唯一模型输入特征）；_pyg.pt 只读、绝不写回；dataset 只组合不再过 MLP
  - [ ] 独立验证入口：--only <图前缀> 跑单图（验收 8.8 不依赖 M4/M5）
  - [ ] 消融变体：--variant no-prior / no-codebert → {safe}_feat_{variant}.pt（复用 _cb.pt 缓存，秒级）
- [ ] 读取 hetero JSON + 源码 + M1 score
- [ ] 完成节点级特征构造
  - [ ] 结构特征 18 项
  - [ ] IR one-hot / 类别特征
  - [ ] M1 score 拼接
  - [ ] 函数级 CodeBERT 双通道
- [ ] 产出 h_v^(0)
- [ ] 验收
  - [ ] 1 个样本能跑通
  - [ ] 特征维度与模型输入一致（写回后 x.shape[1] == 128）
  - [ ] 没有因缺少 IR/functions 导致的空特征

## 七、M4：图编码与读出
- [ ] 文件组织（2026-09-04 再设计）：是否需要改动 = 否（scripts/model.py 按手册 9.5 照抄，不新增其它文件）；随机数据 smoke test（手册 9.5【检查】）作为 M4 独立验证入口
- [ ] 建立 RGCN 两层
- [ ] 使用四类边做消息传播
- [ ] 计算节点重要性 a_v
- [ ] 计算图级池化 h_G
- [ ] 产出 logits / probability
- [ ] 验收
  - [ ] 能从单图输出节点分数和图级输出
  - [ ] a_v 不退化到常数
  - [ ] 训练时日志记录 mask_mean / mask_std

## 八、M5：训练、验证、评估
- [ ] 文件组织（2026-09-04 再设计，标注是否需要改动）
  - [ ] dataset.py：需要新建（数据层：_pyg.pt 结构 + _feat.pt(x) + _m1(s_v) 组合、标签对齐加载断言、边级消融开关；不再过 MLP，只做组合与裁剪）
  - [ ] metrics.py：需要新建（指标层：macro/micro-F1、每类 P/R/F1、mAP/macroPR-AUC；train/evaluate/ablation 共用）
  - [ ] make_splits.py：需要新建；除 split_seed{seed}.json 外，产出 splits/split_report.json（每类正负样本/正负比/唯一合约/多标签/全 0 统计）与 splits/unmatched_contracts.txt（匹配失败记录并报告）
  - [ ] 匹配键（2026-09-05 定稿）：contract_name 的 `-` 后部分是合约名不是文件名（实据 send_loop-Refunder.sol 对应 send_loop.sol、timelock-TimeLock.sol 对应 timelock.sol），与 meta.source 直接比对会大面积失配；按项目前缀匹配（双方 lower 并去 asd_/nasd_，图前缀第一段 == 标签项目段），项目内多合约标签取并集；剥前缀顺序先 nasd_ 后 asd_（nasd_ 含 asd_ 子串，先剥 asd_ 会把 nasd_xxx 误剥成 nxxx，2026-09-05 审计发现）
  - [ ] buggy_* 噪声处置（2026-09-05 定稿）：主实验剔除 asd_buggy_*/nasd_buggy_*（每合约同款注入噪声标签，与具体特征不对应）；另做含 buggy_* 消融对比论证剔除合理性；剔除明细写入 splits/unmatched_contracts.txt 单独一节
  - [ ] train.py：需要新建（手册 10.4 骨架）；启动断言 x.shape[1]==128；只 import dataset/metrics/model；每轮落盘 runs/seedN/config.json（参数快照）
  - [ ] evaluate.py：需要新建（纯评估，不承载数据/指标实现）；主实验（默认）→ runs/seedN/results.json（固定 0.5 + 验证集搜索阈值双报告）；--task ablation/baseline → eval_results/
- [ ] 读取标签文件 alldata(readonly)/contract_labels.json
- [ ] 建模七类多标签分类
- [ ] 设定损失：
  - [ ] BCEWithLogitsLoss
  - [ ] L_var = lambda * max(0, tau - std(a_v)); tau=0.1, lambda=1e-3
- [ ] 处理类别不平衡
  - [ ] pos_weight_c = 负样本 / 正样本，截断到 20
  - [ ] 某类正样本为 0 时跳过该类
- [ ] 训练/验证
  - [ ] 早停：连续 5 个 epoch 验证 macro-F1 不提升
  - [ ] 记录 mask_mean / mask_std
  - [ ] 检查 std 低于 0.05 时排查池化退化
- [ ] 推理
  - [ ] 输出七类概率 p_G
  - [ ] 输出 TopK 可疑节点排序
  - [ ] 只作为辅助解释，不声称真实根因定位
- [ ] 评估
  - [ ] 验证集选阈值 0.2~0.8，步长 0.05
  - [ ] 记录固定阈值 0.5
  - [ ] >=3 个 seed 的均值 ± 标准差（runs/summary.json）
  - [ ] SolidiFI 只报告 a_v/s_v/g_v 三类分数

## 九、收尾与验收门槛
- [ ] 全链路在 1 个样本上跑通
- [ ] 关键中间产物齐全（均在 Heterogeneous graphs/ 下）：_hetero.json、_m1.json、_pyg.pt（只读结构）、_feat.pt（MLP 后 h_v(0)）；splits/、runs/seedN/、eval_results/ 按架构文件归档
- [ ] 图结构字段完整，后续模块可直接消费
- [ ] M1 结果与 M2 图结构一致
- [ ] 训练可启动，且 validation loss / macro-F1 可观察
- [ ] 论文中需要记录过滤统计、样本数、边类型、特征维度、损失项

## 十、下一步执行顺序（推荐）
1. M3 先对 1 个图实现双通道 CodeBERT、结构特征和 128 维 `x`
2. 验证函数级向量共享、节点窗口差异、缺失字段容错及先验 dropout
3. 批量生成 `_cb.pt` 与 `{safe}_feat.pt`（MLP 后的 128 维 h_v(0)；不写回 `_pyg.pt`；消融变体 --variant）
4. M4 实现 RGCN 两层、`a_v` 重要性读出和 `L_var`
5. M5 顺序：dataset.py + metrics.py → make_splits.py（含 split_report/unmatched）→ train.py 单种子 → evaluate.py 主实验 → 3 种子汇总 → 阶段 5 消融/基线（eval_results/）

## 十一、文档与文件组织同步（2026-09-04 再设计）
- [x] 项目组织架构.md：scripts/ 新增 dataset.py/metrics.py；_pyg.pt 只读、_feat.pt 语义锁死为 MLP 后的 h_v(0)、_feat_{variant}.pt 消融变体；runs/seedN/ 增 config.json
- [x] 论文开发手册.md：3.2 目录表、8.1/8.7（_feat.pt 语义、--only 验证入口、--variant 消融变体）、10.2（加载期一致性约束）、10.4（dataset/metrics 分层 + config.json）、12（新增 25/26）
- [x] Todo_List.md：M3/M4/M5 文件组织与验证入口更新；新增“十二、详细代码修改方案”
- [x] 大纲 docx：本次为代码文件组织调整，不涉及大纲规则/协议内容，无需改动（如后续需在大纲 5.x 补充产物目录说明再改）

## 十二、详细代码修改方案（M3/M4/M5 各文件，2026-09-04 定稿）

> 原则：_pyg.pt 只读；_feat.pt 语义锁死（MLP 后的 128 维 h_v(0)）；数据/指标/训练分层；消融三层（边=dataset 零重跑，特征=M3 变体秒级，模型=开关）；每次运行落 config.json。

### 12.1 scripts/m3_build_features.py（新建，M3）
- 函数契约：
  - `encode(text, tok, model, max_len) -> Tensor[768]`：手册 8.7 照抄（空文本返回 zeros(768)）
  - `build_node_window(lines, node, fn_start, fn_end) -> str`：手册 8.7 照抄
  - `build_struct_features(hetero, m1, src_lines) -> Tensor[N,S]`：8.5 的 18 项（缺失补 0，归一化位置补 0.5）
  - `build_type_embedding(hetero) -> Tensor[N,64]`：8.3 九角色 nn.Embedding(9,64)
  - `assemble_x(func_emb, node_emb, type_emb, struct, s_v, mlp) -> Tensor[N,128]`：拼接 `[h_cb_func; h_cb_node; type_emb; struct; s_v]` → `Linear(in,128)`；**输出即 h_v(0)，写 _feat.pt**
- 输出契约：
  - `{safe}_cb.pt = {"func": {func_key: 768}, "node": {node_id: 768}}`
  - `{safe}_feat.pt = Tensor[N,128]`（MLP 后，语义锁死）
  - `--variant no-prior`：s_v 置 0 输入、同一 MLP → `{safe}_feat_no-prior.pt`；`--variant no-codebert`：去掉 CodeBERT 两通道 → `{safe}_feat_no-codebert.pt`（复用 `_cb.pt` 缓存）
- CLI：`--only <图前缀>`（单图验证，不跑全量）、`--in-dir/--out-dir/--m1-dir` 默认 Heterogeneous graphs、`--variant`、`--force`
- 禁止：写回 `_pyg.pt`（验收：跑前后 `_pyg.pt` 的 hash 不变）

### 12.2 scripts/model.py（新建，M4）
- `SSMHG(in_dim=128, hid=128, num_relations=5, num_bases=4, num_classes=7, dropout=0.3)`：手册 9.5 照抄
- `forward(x, edge_index, edge_type) -> (z[7], a[N])`
- 消融开关（构造函数参数）：`use_meanpool=False`（meanpooling 替换重要性加权）、`conv_type="rgcn"|"gcn"|"gat"`（9.1 消融）
- 底部 `if __name__ == "__main__":`：随机数据 smoke test（x=randn(9,128)，验证输出形状 (7,)/(9,)、a∈(0,1)）——M4 独立验证入口

### 12.3 scripts/dataset.py（新建，M5 数据层）
- `build_proj_labels() -> dict[str, list[list[int]]]`：读 `alldata(readonly)/contract_labels.json`，key=项目前缀（lower；剥前缀顺序先 nasd_ 后 asd_——nasd_ 含 asd_ 子串，先剥 asd_ 会把 nasd_xxx 误剥成 nxxx）
- `build_index() -> (dict[base, label7], unmatched:list)`：扫 `Heterogeneous graphs/*_pyg.pt`，项目内多合约标签取并集；未匹配 base 收集返回（供 make_splits 写 txt）
- `load_graph(base, label, ab: Ablation) -> dict`：
  - `torch.load("{base}_pyg.pt")`；**`assert base in index`**（第一道一致性约束，缺标签直接报错）
  - `x = torch.load("{base}_feat.pt" 或 "{base}_feat_{variant}.pt")`，断言 `x.shape[1]==128`（语义锁死校验）
  - 边级消融：`ab.drop_edges ⊆ {DFG_DEP=3, CFG_FLOW=0, CALLBACK_RISK=4}` → 按 `edge_type` 过滤 `edge_index/edge_type`（零重跑）
  - 返回 `{"x", "edge_index", "edge_type", "label", "name"}`
- `@dataclass Ablation`：`drop_edges: set[int]`、`feat_variant: str|None`（对应 `_feat_{variant}.pt`）
- 单图自检入口：`python scripts/dataset.py --check <base>`（打印 N/E/type 分布/x 维度）

### 12.4 scripts/metrics.py（新建，M5 指标层）
- `macro_micro_f1(preds01, ys01) -> (float, float)`：sklearn `f1_score(average="macro"/"micro", zero_division=0)`
- `per_class_prf(preds01, ys01, names) -> dict`：`precision_recall_fscore_support` 每类 P/R/F1
- `mAP(probs, ys01) -> float`：`average_precision_score(average="macro")`
- `subset_accuracy(preds01, ys01) -> float`（可选）
- 供 train/evaluate/ablation 三处共用，不得 import dataset/model

### 12.5 scripts/make_splits.py（新建，M5）
- 从 `dataset.build_index/build_proj_labels` 导入（不重复标签逻辑）
- `random.Random(seed)` 打乱 8:1:1 → `splits/split_seed{seed}.json`（train/val/test base 列表）
- 输出 `splits/split_report.json`：每类 pos/neg、正负比、唯一合约数、多标签合约数、全 0 合约数、三划分数量（手册 10.2.4）
- 输出 `splits/unmatched_contracts.txt`：未匹配 base 列表 + 计数（手册 10.2.2 透明性报告）
- CLI：`--seeds 0,1,2`、`--split 0.8,0.1,0.1`

### 12.6 scripts/train.py（新建，M5）
- 只 import：`model`、`dataset`、`metrics`、sklearn
- CLI：`--seed 0 --epochs 80 --batch-size 32 --lr 1e-4 --weight-decay 1e-4 --drop-feat-edge 3 --feat-variant none --meanpool --conv gcn ...`（消融开关透传）
- 启动断言：每个图 `x.shape[1]==128`（M3 未跑直接报错）
- pos_weight：按训练集 `neg/pos` 截断 20、正样本 0 的类置 0（10.3）
- 损失：`l_cls + 1e-3*clamp(0.1 - a.std(), min=0)`；AdamW + `clip_grad_norm_(1.0)`；每图前向累积 batch=32 后 step
- 早停：验证 macro-F1 连续 5 epoch 不提升；日志字段按 10.3
- 产物：`runs/seed{seed}/log.txt`、`best.pt`、`config.json`（argparse+全部超参快照）

### 12.7 scripts/evaluate.py（新建，M5，纯评估）
- 只 import：`model`、`dataset`、`metrics`（不实现数据/指标逻辑）
- 主实验（默认）：加载 `runs/seed*/best.pt` → 验证集阈值搜索 0.2~0.8/步长 0.05 选 best → 测试集固定 0.5 与 best 双报告 → `runs/seedN/results.json` → 3 种子 `runs/summary.json`（均值±标准差）
- `--task ablation|baseline` → `eval_results/`（10.6；基线含 Slither 规则七维命中、CodeBERT 序列、GCN/GAT 同构图）
- 每类 P/R/F1、macro/micro-F1、mAP 用 `metrics.py`

### 12.8 消融映射（手册 10.6 → 实现位置）
| 消融变体 | 实现位置 |
| --- | --- |
| 去 M1 先验 $s_v$ | M3 `--variant no-prior` → dataset `--feat-variant no-prior` |
| 去 DFG_DEP / CFG_FLOW / CALLBACK_RISK 边 | dataset `--drop-feat-edge 3/0/4`（零重跑） |
| 去 CodeBERT（仅结构特征） | M3 `--variant no-codebert` |
| RGCN→GCN/GAT、meanpooling、num_bases | model.py 构造开关（train 透传） |
| 去外部调用回调相关特征 | M3 结构特征第 2/3/13/14/17 项置 0 的 variant |
| 仅 $s_v$ 排序 / 无 $s_v$ 输出偏置 | evaluate.py 节点排序分支 + model 开关 |
| CALLBACK_RISK 上限 4/不限制 | 唯一重跑 M2 的变体（`--callback-limit 0`） |

### 12.9 执行顺序（单步最小验证）
1. `m3_build_features.py --only nasd_simple_dao__simple_dao` 验收（8.8）→ 全量
2. `model.py` smoke test（9.5）→ `dataset.py --check` 单图自检
3. `make_splits.py` 产出三个文件 → 检查 split_report 与 unmatched
4. `train.py --seed 0` 单种子 → 日志字段齐全、无 NaN
5. `evaluate.py` 主实验 → 3 种子 summary → 阶段 5 消融/基线