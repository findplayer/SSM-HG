# SSM-HG 开发 TODO（按真实代码依赖修正）

> 版本：2026-09-11（按 `研究点一细化大纲改II.docx` 复核：术语改“节点可疑度”、日志改名 `score_mean/score_std`、外部测试集改 **DIVE**、划分改固定种子 8:1:1（门槛 2026-09-12 修订：验证+内部测试合计每类正样本 ≥ 该类正样本总数的30%，原“≥20”）、CALLBACK_RISK 4.2.2 重写、结构特征 18 项+四组分组消融、消融拆 5.4.1/5.4.2、新增推理输出 4.5.4）
> 依据：论文开发手册修订版（2026-09-11 按 `改II` 复核）+ 当前仓库真实状态
> **本轮改动状态**：**M1~M3 已按 `改II` 落地并全链重跑通过**（见三/四/六节：CALLBACK_RISK 6328→509 边、172→85 图（**2026-09-12 R5 后 511 边/86 图**）；M1 七类 flags 21567（**R5 后 21571**）；M3 18 项+分组/单通道消融开关就绪；build×2 确定性一致、M4 22 用例全绿）；**M1–M4 抽查审计（2026-09-12）已执行**（581 图 M1 复算 0 差异、M2 回调边不变量 0 违规、13 合约语义抽样全部符合、M4 22 用例+真实前向通过；发现并修复 2 处文档口径问题，零行为改动，见四/六节）；**仍未完成**：M5 数据集（DIVE）/划分协议/日志字段/消融清单/推理输出（见八/十二节）。
> **2026-09-12 M5 主体实现（阶段 A→D 完成）**：`scripts/{metrics,train,evaluate}.py` 已实现并验收——主指标 **micro-F1**、masked weighted BCE（pos_weight 截断 20 + 零正类 class_mask）+ 按图 population `L_var`（开方内 eps 防 std=0 反向 NaN）+ AdamW/ReduceLROnPlateau(val micro-F1)/早停、自实现批图 collate（`dataset.collate`，不用 PyG DataLoader）、双模块 checkpoint（fuser+model）、种子语义（`--seed`/`--split-seed`）、阈值双报告（固定 0.5 + val 阈值，`--summarize` 均值±std）；新增 `tests/{test_metrics,test_train_utils,test_evaluate}.py` 21 用例，`pytest tests/` **64 passed**；`train.py --limit-graphs 12 --epochs 3` → `evaluate.py --seed 0` → `--summarize` 全链路 smoke 通过（含 checkpoint 双模块 round-trip）。实现期修正：`SSMHG(in_dim=fuser.hidden)`（fuser 输出 128，非融合输入 1631，已同步 decisions §16/§11.6/Todo 12.6）；`--limit-graphs` 取前 N 个含正样本图（保证 smoke 损失可定义）。**3 种子主实验已完成（2026-09-13，CUDA/RTX 4070 Laptop）**，结果与训练时间/吞吐见下方 2026-09-13 记录；阶段 F（消融/基线）与 G（DIVE/SolidiFI）待执行。
> **2026-09-13 M5 阶段 E 主实验完成（CUDA/RTX 4070 Laptop，torch 2.0.1+cu118）**：`train.py --seed {0,1,2} --epochs 200 --batch-size 32` → `evaluate.py --seed {0,1,2}` → `--summarize` 全跑通，`runs/seed{0,1,2}/` + `summary.json` 就绪。主指标 micro-F1（标签对级）：固定 0.5 = **0.9058±0.0397**（0.8603/0.9238/0.9333）、验证集阈值 = **0.9492±0.0145**（阈值 0.75/0.60/0.55）；macro-F1（参考）固定 0.5 = 0.2300±0.0428；mAP = 0.4139±0.1070。训练时间/吞吐（§11.4 口径，`runs/seed*/config.json::timing`）：seed0/1/2 wall 40.8/16.3/16.0 s、train_seconds 7.4/6.0/3.2 s、graphs/s 924/660/1003、早停@epoch 18/10/8（best val micro-F1 0.9556/0.9492/0.9587）。完整结果（逐种子/逐类/计时/产物）见 `experiments/results.md` §1；七类逐类 F1/macro-F1 见 §1.4、逐类诊断与改进线索见 §1.7（`scripts/diagnose.py` 生成）。阶段 F（消融/基线）与 G（DIVE/SolidiFI）待执行。
> 先决条件：先修好 Stage 0，再动 M2；M2 是第一最小原子模块，不要跳过。
> **2026-09-12 目录重构（方案 B）**：产物统一迁入 `products/<数据集>/`——顶层 `raw/`→`products/alldata/raw/`、`Heterogeneous graphs/`→`products/alldata/graphs/`、`splits/`→`products/alldata/splits/`；新增 `products/dive/{raw,graphs,splits}`、`products/solidifi/{raw,graphs,mapping}` 与 `runs/`、`eval_results/{ablation,baseline,dive,solidifi}/`；脚本默认路径、.gitignore、手册/架构/copilot-instructions 已同步，迁移后 compileall + bash -n + pytest（22 passed）+ `dataset.py --check` 全绿；`_m1.json`/`batch_summary.json` 内嵌旧路径已全量刷新（581 文件，数值零差异）。
> **2026-09-12 划分门槛修订（大纲 5.1 第三条）**：“≥20 个”改为“**验证集与内部测试集中的正样本合计 ≥ 该类正样本总数的30%**”；`make_splits.py` 增补 `splits.csv`（1485 行）、`split_metadata_seed{0,1,2}.json`、逐类 support 与 `rule_check` 门槛审核（三种子划分成员不变，sha256 校验通过；仅新增字段与新文件）；实测三种子均未达标（每种子 5–6/7 类不足；随机划分下 val+test 期望占比 ≈20% < 30%，换种子不可解）→ 约束分层重划/局限记录待决策。
> **2026-09-12 A2 落地（覆盖约束校正）**：大纲 5.1 补半句（覆盖约束校正）；`make_splits.py` 增 `--strategy {constrained(默认),random}`（random 输出隔离到 `random_snapshot/`）、`refine_coverage` 最小确定性替换与 `coverage_swaps_seed*.txt` 替换清单；三种子 C1/C2 构造达标（预去重 495 池口径：替换 18/19/17 个，eval 合计 44/42/43；**去重后 448 池现行口径：替换 18/16/12 个，见 decisions §14**）；主种子 seed0（用途定位声明见 decisions §12）；`pytest` 25 通过。

## 一、项目总原则
- 以大纲为准，旧脚本/旧手册冲突时以修订手册为准。
- 单步最小验证：每改一个模块，先跑 1 个样本，再批量。
- 先保证图数据正确，再进入 M1/M3/M4/M5。
- 真实路径必须使用：
  - AST: products/alldata/raw/AST-raw
  - CFG: products/alldata/raw/CFG-raw
  - DFG: products/alldata/raw/DFG-raw
  - Hetero（全部**结构**图产物 _hetero.json/_m1.json/_pyg.pt）: products/alldata/graphs
  - M3 特征正典（§37 微调 CodeBERT，**含划分种子**）: products/alldata/graphs_ft/ss{S}（**逐划分种子取：seed{S} 配 ss{S}**）
    - `products/alldata/graphs` 下的 M3 特征是**冻结编码器**那套（现已降为消融臂 `cb_frozen`），仅该臂使用
  - 源码根（只读数据源）: alldata(readonly)/alldata_sol_source
  - 主标签: alldata(readonly)/contract_labels.json
  - 外部测试集（只读，改II 新增）: DIVE/（Source codes 22330 .sol、contract_labels.json 21696 条七维、DIVE_Labels.csv 含第 8 类 Bad Randomness）——仅阶段 5 泛化评估
  - 节点覆盖评估集（只读，改II 指定）: SolidiFI/（buggy_contracts 350、buggy_logs 350、contract_labels.json 350 条七维）——仅阶段 5 层次二
  - 生成脚本: scripts/（generate_all_ast_cfg_dfg.sh、dump_cfg.py、build_cfg_centered_hetero_graph.py、m1_runner.py、convert_hetero_json_to_pyg.py、priori_scoring.py；M3–M5：m3_build_features.py、model.py、dataset.py、metrics.py、make_splits.py、train.py、evaluate.py）

## 二、Stage 0：新目录就位 + 生成 raw 原始产物
- [x] 文件已收拢到 scripts/
  - [x] 生成脚本已位于 SSM-HG/scripts/
  - [x] priori_scoring.py（由 anchor_detectors.py 改名）、convert_hetero_json_to_pyg.py、build_cfg_centered_hetero_graph.py、m1_runner.py、generate_all_ast_cfg_dfg.sh 均确认在 scripts/ 下
- [x] 修正默认脚本路径/参数（2026-09-02）
  - [x] build_cfg_centered_hetero_graph.py 默认路径改为 products/alldata/raw/{AST-raw,CFG-raw,DFG-raw} 与 products/alldata/graphs（已消除末尾空格问题）
  - [x] convert_hetero_json_to_pyg.py / m1_runner.py 默认 in/out 均为 products/alldata/graphs
  - [x] generate_all_ast_cfg_dfg.sh 的 AST_DIR/CFG_DIR/DFG_DIR 指向 products/alldata/raw/*，SRC_ROOT 指向 alldata(readonly)/alldata_sol_source
  - [x] 运行脚本统一用 `python scripts/xxx.py`（从 SSM-HG 根目录执行）
- [x] 从只读数据源生成 raw 原始产物（2026-09-02 完成）
  - [x] 运行 `bash scripts/generate_all_ast_cfg_dfg.sh`（先 nasd_simple_dao 单样本试跑通过，再全量）
  - [x] products/alldata/raw/AST-raw 生成 581 个 *.json（591 − 1 个 >50 行 assembly 过滤 − 9 个 delegatecall 动态绑定过滤）
  - [x] products/alldata/raw/CFG-raw 生成 24672 个 *.dot（每函数一个）+ 同名 `*__cfgdetail.json` 581 个
  - [x] products/alldata/raw/DFG-raw 生成 581 个 *_dfg.txt
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
- [x] 构建全量异构图到 products/alldata/graphs/（2026-09-03 完成）
  - [x] 执行 `python scripts/build_cfg_centered_hetero_graph.py`（默认参数，--src-root 指向只读数据源）
  - [x] products/alldata/graphs/ 生成与 products/alldata/raw/AST-raw 对应的 581 个 *_hetero.json（93545 节点；CFG_FLOW 71291 / AST_PARENT 1959 / AST_PARENT_SAME 6045 / DFG_DEP 30047 / CALLBACK_RISK 6335，188 图含回调边；ir 缺失仅 11；0 图缺 functions）
  - [x] 检查一份样本输出，确认 meta.cfg_node_count 与边键 CFG_FLOW / AST_PARENT / AST_PARENT_SAME / DFG_DEP / CALLBACK_RISK 齐全，seq+true+false == cfg_edge_count
  - [x] _hetero.json(581) 与 _pyg.pt(581) 已落在 products/alldata/graphs/ 同一目录；_m1.json 待 M1 运行生成
  - [x] 说明 `products/alldata/raw/Callback-raw` 不作为原始产物目录；回调信息存于 `_hetero.json` 的 `CALLBACK_RISK` 边；`CFG-raw` 中允许存在合法 `digraph{}` 空函数图

## 二点五、生成脚本健壮性修改（2026-09-04 完成并验证）
- [x] generate_all_ast_cfg_dfg.sh：删除死代码 slither_error 分支，DFG 失败路径统一清理产物并计 slither_error_count
- [x] CFG 失败自动回退较低版本重试（Slither 对 0.4.12+ AST 常量折叠崩溃 NotConstant；TownCrier 实测 0.4.26 失败→回退 0.4.19 成功，AST 同步重生成）
- [x] 日志移出输出目录：AST_ERR/CFG_ERR/DFG_ERR → products/alldata/raw/logs/；成功路径不再把 solc/slither 告警写入 error 日志
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
- [x] 2026-09-07 M1/M2 第五轮审查修复（代码审查，行为改动仅 1 处）
  - [x] M2 build 脚本 `RE_IR_EXT_CALL` 补 `HIGH_LEVEL_CALL`（旧版漏判：expression 不含 .call/.send/.transfer 但 ir 为 HIGH_LEVEL_CALL 的具名调用——ERC721 transferFrom、ERC20 approve 等全库 770 节点被 CALLBACK_RISK 与 M1 external_callback(+0.5) 遗漏，与手册 7.6/大纲 4.2.2 判据不符）
  - [x] 另 2 处小修（无行为影响）：构图脚本 `skipped_no_cfg` 提前 continue 分支补计数（与记录口径一致）；priori_scoring `BFS_MAX_DEPTH` 过时注释修正（大纲无 ≤2，实际调用点均显式传 10）
  - [x] 全量重跑并下游同步：build×2 确定性一致（hash 对比 PASS）→ CALLBACK_RISK 5914→6328、141→172 图、ext_call_node_count 5954→6717；M1 `--force`（七类 flags 命中不变 21567，node_scores 因 external_callback +0.5 变化；样例 ERC721 transferFrom 节点现成为回调源、s_v 含 +0.5）→ PyG 重转（其余边类计数不变）→ M3 全量 `_feat.pt`（`_cb.pt` 复用 581/581，离线模式）；simple_dao 特征 hash 5433b653 不变；M4 22 用例回归通过
- [x] 2026-09-05 生成脚本第四轮修复
  - [x] build_cfg_centered_hetero_graph.py：RE_BALANCE_MAPPING 改写入方向正则（balances[x] (...) := 与 (->balances) :=；读取 -> balances[x] 不再误判，mapping 关键字分支删除；全库 CALLBACK_RISK 6171→5914、163→141 图；etherstore 纯读取节点误判 0、状态写正确识别 2，读/写方向验证通过）；parse_dfg 删除不可达死代码（非表行分支之后的 line.startswith('+')）；main 简化冗余跳过条件（cfgdetail_invalid 尚未检测不参与首个条件）；cfgdetail 路径 find_expression_span 行号回填不共享缓存（cache=None，修复同表达式跨函数错配隐患，缓存键无函数上下文）；补 walk_ast/normalize_function_name/parse_cfg_filename/node_is_state_write/node_has_transfer_or_balance 五个 docstring
  - [x] dump_cfg.py sons[0]=true 分支约定人工核对通过（抽查多个含 if/循环的 cfgdetail，then 分支第一行对应 kind=true 后继；手册 7.4.3 补记）
- [x] 2026-09-05 60 个新样本批量审计（/tmp/audit60.py，排除已抽查样本）：图结构/m1 结构自洽 0 问题（节点数/CFG 三类计数/callback 上限/functions/ir_missing/键约定/分数范围）；标签匹配 581 图全覆盖（0 无标签）；非 buggy 真实合约召回 100%（26 条漏检全部集中在 buggy_* 噪声项目，与已定稿剔除策略一致）；发现前缀剥离顺序坑（先 nasd_ 后 asd_，已同步手册 10.2/12 新增 36/Todo 12.5）；补 m1_runner 7 个函数（parse_args/as_node_key/count_hits/build_meta/build_summary/run_one/main）与 priori_scoring.from_json_file 的 docstring
## 三、M2：第一最小原子模块（节点/边/functions/PyG 已完成；**CALLBACK_RISK 按大纲改II 重开**）
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
- [x] **2026-09-11 按大纲改II 4.2.2 重做（已完成）——CALLBACK_RISK 收窄并全链重跑**
  - [x] 外部调用节点收窄：仅 `call`/低级调用 + HIGH_LEVEL_CALL（ERC20 `token.transfer` 等具名调用保留）；**仅转发 2300-gas 的 `send`/`transfer` 不再作为 CALLBACK_RISK 源节点**
    - [x] 改 `build_cfg_centered_hetero_graph.py`：`RE_EXT_CALL_TEXT` 去掉 `\.send(`/`\.transfer(`；`RE_IR_EXT_CALL` 去掉 `SEND|TRANSFER`（保留 `LOW_LEVEL_CALL`/`HIGH_LEVEL_CALL`）；新增 `RE_VALUE_TRANSFER_TEXT`（`.transfer(`/`.send(`）供状态写入/入口含转账判定
  - [x] 高置信外部调用节点定义落地：4 条全满足（被规则 1 识别、非 view/pure、调用后同函数状态写入、**实际建立 ≥1 条边**）；仅被识别但未建边的节点**不计入** `external_callback` +0.5（M1 只取 CALLBACK_RISK 边端点集合）
  - [x] 主实验**默认保留** CALLBACK_RISK 边（删除“收益有限即降级为节点特征”分支）；上限 4 / 不限制的选择只用验证集、不使用 DIVE
  - [x] meta 统计按收窄口径重算：`ext_call_node_count` **6717→1465**、`callback_max_edges=4`、`callback_truncated_candidates=652`、`callback_avg_edges` 以收窄口径为分母
  - [x] 下游全链重跑：`build`（×2 hash 一致：`6ac9c5b7…`）→ `m1_runner --force` → `convert_pyg`（581 图，edge_type 4 = 509）→ M3 `_feat.pt`（`_cb.pt` 复用 581/581，约 57s）→ M4 22 用例回归 PASS
  - [x] 与手册 7.1/7.6/7.8 同步（已改）
  - [x] **结果对比**：CALLBACK_RISK **6328→509 边**、**172→85 图**（**2026-09-12 R5 后为 511 边/86 图**）；降幅主因是修掉旧 `\bTRANSFER\b` 正则把 `Emit Transfer(...)`（ERC20 事件）与内建 2300-gas `addr.transfer/send`（IR `Transfer dest:`/`SEND dest:`）误当外部调用（`改II` 4.2.2 已排除）

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
  - [x] 命令: python scripts/m1_runner.py --in-dir "products/alldata/graphs" --out-dir "products/alldata/graphs" --force（581 个全部处理）
  - [x] 输入目录: products/alldata/graphs（*_hetero.json）
  - [x] 输出目录: products/alldata/graphs（与 _hetero.json 同目录，文件为 *_m1.json，不冲突；batch_summary.json 同目录）
  - [x] 2026-09-04 规则修订后全量重跑（--force 覆盖 581 个，耗时约 5s，共重跑 3 轮）
- [x] 验收规则
  - [x] node_flags 仅保留 seven-way boolean
  - [x] node_scores 为 [0,1] 标量
  - [x] 规则必须遵循大纲：不做 DFG 反向一跳传播
  - [x] external_callback 仅加 0.5 分，不作为第 8 类标签
  - [x] 全图 min-max 归一化
- [x] 检查输出
  - [x] 2026-09-05 最终全量重跑（两次一致）：93551 节点中 21568 命中；reentrancy 1629 / front_running 11004 / access_control 3774 / time_manipulation 832 / uncheck_return 540 / dos 199 / arithmetic 9290（命中图数 reentrancy 263 / front_running 525 / access_control 174 / time_manipulation 134 / uncheck_return 103 / dos 73 / arithmetic 468）
  - [x] 2026-09-06 第六轮修复后最终全量重跑：93551 节点中 21567 命中；reentrancy 1629 / front_running 11004 / access_control 3774 / time_manipulation 832 / uncheck_return 536 / dos 199 / arithmetic 9290（命中图数 reentrancy 263 / front_running 525 / access_control 174 / time_manipulation 134 / uncheck_return 99 / dos 73 / arithmetic 468）
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
  - [x] 2026-09-06 第六轮修复（M1/M2 审计重开）：`_build_bool_consumed_set` 消费变量提取不跳 Slither 0.11.5 签名括号（`require(bool)(ok)`/`require(bool,string)(ok, "m")` 被误抓签名类型名 `bool` → `bool_consumed_nodes` 全库恒空、手册 6.3 判据③失效）；DAO/reentrancy 4 图 4 个 `bool ok/success = ...call...; require(ok)` 调用点被误报为 uncheck_return，修复后 uncheck_return 540→536 节点、103→99 图、总命中 21568→21567（其余六类零变动）；重跑 `m1_runner --force`（581）→ M3 `_feat.pt` 全量（`_cb.pt` 复用、仅 4 图特征变化、确定性验收通过）；手册 6.3/6.6/12-38/头部统计与 Todo 同步
- [x] **2026-09-11 按大纲改II 复核（已完成，已随 M2 重跑）**
  - [x] `external_callback` +0.5 只给“高置信外部调用节点 + 其实际连接的入口节点”：4 条全满足（被规则 1 识别、非 view/pure、调用后同函数状态写入、**实际建边**）；仅被识别但未建边不加分（`_build_callback_nodes_from_edges` 只取 CALLBACK_RISK 边端点）
  - [x] 修 M2 后重跑 `m1_runner --force`（581 图）：`total_raw_hits` **21567 不变**、七类 flags 命中不变，仅 `node_scores` 的 +0.5 位置变化（6717→1465 个源/入口）
  - [x] 验收：`addr.send/transfer`（2300 gas）不在 CALLBACK_RISK 源集合、`external_callback` 不加 0.5；ERC20 `token.transfer`（HIGH_LEVEL_CALL）仍参与
- [x] **2026-09-12 抽查审计（M1–M4 四准则：与大纲/手册一致性、逻辑、学术可行性、案例可运行）**
  - [x] 全库 581 图按 `m1_runner.run_one` 逐节点复算：`node_flags`/`node_scores` 与落盘 `_m1.json` **逐位一致 0 差异**（含 `pre_0_8` pragma 依赖路径；注：用 `from_any_json` 复算会漏 pragma 导致 927 处假差异，已确认是审计脚本自身问题）
  - [x] 13 合约抽样逐条对照 6.3：simple_dao call 点（reentrancy+uncheck_return）+ 其后状态写节点（reentrancy）均命中；reentrancy_bonus CEI 正确调用点不命中/跨函数命中；`.send(`/`.transfer(` 不命中 reentrancy；`tx.origin`/`selfdestruct(`/非 msg.sender 单参 transfer 命中 access_control、`msg.sender.transfer` 退款不命中；`require(bool)(callee.call())` 不命中 uncheck_return；pre-0.8 算术全量命中；`now` 命中 time_manipulation；`i < numbers`/`array.length += 1` 命中 dos
  - [x] 发现 1（front_running 口径未文档化，已修）：实现前置条件“节点归一化类型须为 ASSIGNMENT/STATE_WRITE”原仅在代码；全库被剔除的 718 节点 = 713 构造期初始化（`slitherConstructorVariables/ConstantVariables`，OTHER_ENTRYPOINT）+ 5 局部名遮蔽（`uint256 secret = uint256(hash)`、`address owner = childOwner[..]`），均非运行期竞态写入、**无真实漏检**；已写入手册 6.3 行内并加 6.3 抽查审计块
  - [x] 发现 2（M3 EXT_CALL 口径交叉引用过时，已修）：`node_has_ext_call`（8.3 角色 / 8.5 #2）是**节点语义宽口径**（含内建 `\.send(`/`\.transfer(` 与 ir `SEND dest:`/`Transfer dest:`），与 7.6 收窄后的 CALLBACK_RISK 源集合本就不同；代码 docstring 已改写，手册 8.3/8.5 #2 行、7.6 提示块已同步，大纲 4.3.3 #12（外呼方式含 send/transfer）已隐含支持→大纲无需改
  - [x] 权重/口径零行为改动验证：simple_dao `_feat.pt` 审计后重跑 sha1 与审计前一致（`e55bd664…`）

## 五、M2 → PyG 适配
- [x] convert_hetero_json_to_pyg.py 位于 scripts/ 下（无需 git restore），默认 in/out 均为 products/alldata/graphs
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
- [x] 文件组织（2026-09-04 再设计）：是否需要改动 = 是
  - [x] 只需新建 scripts/m3_build_features.py；产物 = _cb.pt + {safe}_feat.pt
  - [x] _feat.pt 语义锁死：MLP 之后的 128 维 h_v(0)（唯一模型输入特征）；_pyg.pt 只读、绝不写回；dataset 只组合不再过 MLP
  - [x] 独立验证入口：--only <图前缀> 跑单图（验收 8.8 不依赖 M4/M5）
  - [x] 消融变体：--variant no-prior / no-codebert → {safe}_feat_{variant}.pt（复用 _cb.pt 缓存，秒级）
- [x] 读取 hetero JSON + 源码 + M1 score
- [x] 完成节点级特征构造
  - [x] 结构特征 18 项
  - [x] IR one-hot / 类别特征
  - [x] M1 score 拼接
  - [x] 函数级 CodeBERT 双通道
- [x] 产出 h_v^(0)
- [x] 验收
  - [x] 1 个样本能跑通
  - [x] 特征维度与模型输入一致（写回后 x.shape[1] == 128）
  - [x] 没有因缺少 IR/functions 导致的空特征

### M3 开发进度（2026-09-05，已完成）
- [x] A1~A3 完成并验收：CLI/数据加载行序契约（simple_dao 9 节点 s_v 与 _m1.json 逐位一致）；`products/alldata/graphs/ir_cat.json` 全库扫描（93551 节点；IR 6 类：ASSIGNMENT 25087/SOLIDITY_CALL 13990/CONDITION 3377/HIGH_LEVEL_CALL 881/LOW_LEVEL_CALL 76/OTHER 50140；外呼 5 类）
- [x] A4~A9 完成：`scripts/m3_build_features.py`（build_node_window 手册 8.7 原样、CodeBERT 双通道→_cb.pt、9 角色类型嵌入、18+1 结构特征 s_v 独立列 MLP in=1645、assemble+MLP→_feat.pt、变体 no-prior/no-codebert；`--codebert <本地权重目录>` 离线支持；docstring 100%、py_compile OK）。网络恢复后单图全链路验收通过：`--only nasd_simple_dao__simple_dao` feat=(9,128)、窗口与源码一致、role 分布 ENTRY3/CONDITION1/EXT_CALL1/STATE_WRITE2/RETURN1/OTHER1、重跑确定性 hash 一致、no-prior/no-codebert 与主版不同、_pyg.pt 未改动
- [x] A10 8.8 断言全绿（shape/有限值/确定性/变体差异/行数=pyg node_id/只读红线）
- [x] A11 全量 581 完成：93551 节点 → `_cb.pt`×581 + `_feat.pt`×581（抽查 12 图全对齐且有限）；变体单图已验，全量按需 `--variant` 生成
- [x] A12 文档收尾（2026-09-05）：Todo/手册 8.7/架构/记忆同步
- [x] 2026-09-05 复核修复（全库扫描驱动）：INT_CALL 补 ir INTERNAL_CALL（super/成员内部调用 24 节点不再落 OTHER）；循环体判定对齐 M1 dos（10 跳/祖先/不含自身，146 个循环头节点修正）；call_mode/call_return 修复 `callbackAddr` 子串误判（2 例）；node_has_ext_call 补 SEND/Transfer IR 指令；全量 581 `_feat.pt` 重跑，确定性/形状验收通过
- [x] 2026-09-06 二次复核：#14 消费窗口 3 跳论证保留（3→10 仅 5 例翻转且均为无关条件误报形态，代码注释说明）；全库核查 14741 函数行号齐全、0 个 line_start=0 节点、0 个 `call{`（0.7 语法）节点；手册 8.5 #5/#7 口径补注、8.7 二次复核注记
- [x] 2026-09-06 8.8 验收全量执行通过（/tmp/m3_88_accept.py）：①窗口文本全库参照比对 mismatch=0；②581 `_feat.pt` shape(N,128)/有限值；③func 共享逐位一致 + simple_dao withdraw 节点向量互异；④合成缺失字段容错（位置回退 0.5、行宽=4+14+5+1+类别数、assemble (N,128)）；⑤先验 dropout 模式测试（eval 原值、训练期整图置零率 ≈0.2、M3 无实际 dropout 调用）；⑥结构特征 30 列全覆盖/无 NaN/s_v∈[0,1]；手册 8.8 全部勾选 + 8.7 执行注记
- [x] 2026-09-07 M3/M4 第六轮审查（M4 代码无问题——detach 无实调用、无 s_v/prior/m1 引用、num_bases=5、22 用例回归 PASS）：M3 `classify_call_mode` 补内建转账指令兑底分支（ir `Transfer dest:`→transfer、`SEND dest:`→send，与 `node_has_ext_call` 兑底口径一致；当前全库 expression 均存在、防御性 0 影响——全量 581 `_feat.pt` 联合 sha1 修复前后一致 ZERO-DIFF CONFIRMED）；手册 8.4.2/8.7 多行窗口措辞修正（实际 s-1..e+1，与 8.8 验收一致）、8.6 结构特征 dropout 标注“未落地/M5 可选开关”；大纲无需改（4.3/4.4 协议文本与实现一致）
- [x] （后续可选）~~全量 `--variant no-prior / no-codebert`（消融时执行，复用 `_cb.pt` 秒级）~~——已随前端化退役（2026-09-12）：特征消融在 `model.NodeFuser` 的 `AblationConfig` 内做，零重跑、无文件变体
- [x] **2026-09-11 按大纲改II 4.3.3/4.3.2 复核（代码已完成）**
  - [x] 结构特征清单确认为 **18 项**（`改I` 的第 12 项 `s_v` 已移出清单；`s_v` 仍为独立输入通道，结构列宽 30 = 可见性4+布尔14+外呼5+位置1+IR6）
  - [x] 新增**四组分组消融支持**：基础结构组（1–8）/ 漏洞语义组（9–13）/ CALLBACK_RISK 辅助组（14–16）/ 位置与指令组（17–18）；`m3_build_features.py` 加 `--feat-groups all|base|base+sem`（输出 `_feat_grp-<group>.pt`，未选中列置 0、列宽不变，复用 `_cb.pt` 秒级）
  - [x] 新增单通道消融 `--variant no-cb-func|no-cb-node`（改II 5.4.1）；simple_dao 上 4 个新变体输出互异且均 128 维
  - [x] 验收：主特征 `--feat-groups all` 重跑逐位一致（确定性通过）；全量 `_feat.pt` 已重跑（`_cb.pt` 复用 581/581，约 57s）
  - [ ] （M5 实现）结构特征 dropout 0.2 仍为可选开关（大纲 4.3.4，默认关）
  - [ ] （M5/evaluate 实现）CodeBERT 冻结三条理由写入论文（4.3.2）；“微调 vs 冻结 CodeBERT”列入 5.4.2 可选消融
- [x] **2026-09-12 抽查审计（M1–M4 四准则）**
  - [x] 全库扫描：`emit Transfer(...)` 等事件节点**不会**被误判为 EXT_CALL（10 个含 `emit` 节点仅 `Emitter(emitter).emit(x)` 命中，它是真实对外部合约的具名调用、ir=HIGH_LEVEL_CALL）；3535 个内建 `send`/`transfer` 节点按宽口径全部计入（本口径预期行为）
  - [x] 口径澄清（**仅文档/注释**）：`node_has_ext_call` 旧注释“与 7.6 正则一致”已删除（`改II` 4.2.2 收窄后不成立），改为“节点语义口径（宽于 7.6 的 CALLBACK_RISK 源集合）”；模块 docstring 加“口径澄清”段
  - [x] 结构特征行内注释编号与手册 8.5 对齐（原 #14–#17 实为 #13–#16，off-by-one 修正；`build_struct_features` 列布局 docstring 同步）
  - [x] 零行为影响验收：`--only nasd_simple_dao__simple_dao` 重跑 `_feat.pt` sha1 与审计前一致（`e55bd664…`）；role 分布不变（ENTRY3/CONDITION1/EXT_CALL1/STATE_WRITE2/RETURN1/OTHER1）；py_compile OK

## 七、M4：图编码与读出（已完成，2026-09-07）
- [x] 文件组织（2026-09-07 v4 定稿）：新增 `scripts/model.py`（SSMHG + helpers + smoke）、`tests/test_model_smoke.py`（22 用例，pytest/独立运行）、`docs/M4_interface.md`；不新增其它文件
- [x] 建立 RGCN 两层（默认 num_bases=5；GCN 消融分支忽略 edge_type）
- [x] 使用五类边（0=CFG_FLOW/1=AST_PARENT/2=AST_PARENT_SAME/3=DFG_DEP/4=CALLBACK_RISK）做消息传播
- [x] 计算节点可疑度 a_v（=sigmoid(a_head(h_v^(L)))；node_logits 一并返回，不 detach）
- [x] 计算图级池化 h_G（**基于传播后的 h2，绝非输入 x**；单图与批图均按图归一化）
- [x] 产出 logits（z 未 sigmoid；单图[7]/批图[B,7]）
- [x] 验收
  - [x] 能从单图输出节点分数与图级输出（z,a,node_logits）
  - [x] a_v 不退化到常数：由 M5 L_var 监控（score_std）；M4 提供 a.std 输出供观测
  - [x] 训练时日志记录 score_mean / score_std（大纲改II 由 mask_mean/mask_std 改名）：落点在 M5（train.py），M4 不记录
- [x] 2026-09-07 开发计划 v4 落地要点：Readout=h2-based（tests 三断言）；严格输入校验（x/edge_index/edge_type dtype·shape·值域·batch）；空边/孤立/重复边/单节点/极端 logits 用例全过（PyG 2.7.0 官方语义，无需 linear_root fallback）；forward 返回 (z,a,node_logits)；return_intermediates 字典；apply_edge_mask/safe_readout/validate_edge_types helper；批图=逐图等价；GAT 拒绝；_pyg.pt 只读 hash 未变；simple_dao 真实前向（9 节点/28 边）验收通过
- [x] **2026-09-11 按大纲改II 4.4.1 复核（文档已对齐）**：论文关系数口径为**默认 4 类边**（AST_PARENT/CFG_FLOW/DFG_DEP/CALLBACK_RISK），实现用 5 个物理关系（+AST_PARENT_SAME）；若把 CFG_FLOW 三子类当独立关系则关系数为 6——已在手册 9.1 注明 `num_relations` 与论文口径的对应（`num_bases` 默认=关系数；消融可取 4）；`model.py` 代码无需改动
- [x] **2026-09-12 抽查审计（M1–M4 四准则）：M4 无问题**——`python scripts/model.py` smoke 全通过；`pytest tests/test_model_smoke.py -q` → 22 passed；全库 581 图 `_pyg.pt.edge_type` 按类计数与 `_hetero.json` 五类边数零差异、`_feat.pt` 形状恒为 (N,128) 且有限；40 张真实图前向 `z=[7]` / `a=[N]` 均有限；`model.py` 与手册 9.1–9.5 逐项一致（in/hid=128、num_relations=5、num_bases=5、dropout=0.3、h2-based readout、a_v 不 detach）

## 八、M5：训练、验证、评估

> **2026-09-11 按大纲改II 复核（下列项为新增/改动，未完成）：**
> - **数据集**：外部测试集 SmartBugs → **DIVE**（MVD-HG 内容源自 MANDO、已含 SmartBugs，超集训练/子集测试构成污染）；主实验在 **MVD-HG 内部测试 + DIVE** 两设定评估；DIVE 只做一次性外部测试，不参与训练/验证/早停/阈值/模型选择；SolidiFI 只做层次二。
> - **划分**：唯一合约**固定种子 8:1:1**；**验证+内部测试合计每类正样本 < 该类正样本总数的30% 则换种子重划**（2026-09-12 修订，原“val/内部测试 <20”；**A2 已落地：覆盖约束校正构造达标，去重后替换 18/16/12 个**）；报告划分种子与每类样本数；**训练种子与划分种子分离**（不再要求 `iterative-stratification` 作主方案，仅留对照快照）。
> - **日志字段**：`mask_mean/mask_std` → **`score_mean/score_std`**（大纲 4.5.1）。
> - **消融**：按 5.4.1 必要消融（去 DFG_DEP/CFG_FLOW/AST_PARENT/CALLBACK_RISK、上限 4 vs 不限、去函数级 CodeBERT、去节点级 CodeBERT、meanpool、关闭 L_var、关闭先验 Dropout、结构特征分组）与 5.4.2 可选消融（CALLBACK_RISK_REV、L=1/2/3、num_bases、128/256、DropEdge、微调 CodeBERT）重排；`改I` 的“去 M1 先验 s_v / RGCN→GCN / 去回调特征 / 仅 s_v 排序 / 仅 RGCN 学重要性”不再列为必做。
> - **推理输出**：新增 4.5.4 五项输出（$p_G$、$\hat y_G$、节点可疑度列表、TopK、可选 $G_{view}$）+ 可选梯度显著性指标。
> - **层次二**：梯度显著性类别归属规则；“$a_v$ 增量覆盖节点”统计（$s_v$ 排名 50% 之后但进 $a_v$ TopK 的节点数）。
> - **5.5.1**：复用 DIVE 结果，不新增实验；5 项分析（PR-AUC、DIVE 全零子集每类 FPR、20–30 例人工检查、归因分层等）。
> - **口径（2026-09-12 P0 最小改动，见 `experiments/decisions.md` §13）**：**主指标 micro-F1**；阈值搜索与早停目标改 **val micro-F1**（协议形状不变，macro-F1 降为参考）；逐类 F1 与 per-class PR-AUC **强制标注 support**，support ≤2 的类仅描述性呈现；**多标签叙事降级为架构性声明**（池内去重后仅 1 个），实证主张只在 DIVE（68.2% 多标签）；口径数字全部取自 `docs/data_funnel.md`（`scripts/audit_data_funnel.py`）。
> - **口径收口（2026-09-12 补充；含 P1 落地）**：① **防错位原则**——macro-F1 的*低支撑构成*注释用**计算它的那个划分**（seed0 test：5 个类 support ≤2），*数据稀疏天空板*叙述用**池级**（3 个类正样本 ≤6），两口径不得互相借用；② **口径绑定指纹**——支撑数字绑定 `split_seed*.json` 的 sha256，**T-A 两级去重已重跑，刷新链条已履行**（`docs/data_funnel.md` 重跑 / decisions §13+§14 / 手册 10.2+10.5）；③ **DIVE 抽样已闭案**——seed=0、**n=900**、均匀，实测 front_running=30 ≥20（未触发后备；后备=n→1100 重抽一次，再不足则 report-only；**禁止换 seed 重抽**）；④ AST 稀疏性统计表与关系数映射表已并入 `docs/data_funnel.md` §4 与手册 §7.7；⑤ 手册 10.4 骨架接口修正为 3 值 `(z, a, node_logits)`；⑥ **P1**：池去重（495→448）、关系数口径（4 语义/5 物理）、`--drop-ast`=删 relation 1+2，详见 `experiments/decisions.md` §14。
- [x] 2026-09-07 划分已落地并验收：`scripts/dataset.py`（build_proj_labels/build_index/load_graph/Ablation/--check）与 `scripts/make_splits.py`（8:1:1、3 种子、buggy 剔除、三件套报告）已实现；`products/alldata/splits/` 已生成——train 396/val 50/test 49（每种子），495 训练池 / 86 buggy_ 剔除（asd_+nasd_ 两份 43 项目）/ 0 unmatched；3 种子互斥+全覆盖断言通过；simple_dao `--check` 通过（9 节点/28 边/label=reentrancy）
  - 更新（2026-09-12 P1 两级池去重后，**2026-09-12 当时**）：池 **448** / 划分 **358/45/45**（×3 种子）；C1+C2 7/7 达标；跨划分内容/地址重复均为 0；**现行池 453 / 划分 362/45/46**，见 `experiments/decisions.md` §18
- [x] M5 v5 审阅结论（2026-09-08，可行性判定见 `experiments/decisions.md` 第 0、9 节）
  - [x] 已确认：dataset/model 契约与 M4 输出一致；class-masked BCE 分母、按图 population `L_var`、单图 DropEdge、zero-positive 类和 split API 校验升级为硬性验收项
  - [x] **先验 dropout 前置条件升级为必做**：~~训练期 0.2 整图切换需要全量 `_feat_no-prior.pt`（现仅单图变体），train.py 前先跑 `python scripts/m3_build_features.py --variant no-prior`（复用 _cb.pt，秒级）~~——**该方案已于 2026-09-12 前端化退役**：先验 dropout 改为 `model.NodeFuser` 内按图 Bernoulli(0.2) 置零（融合前），不再需要变体文件
  - [ ] 补充项：**5.3 对比方法（2026-09-21 按大纲原文重列，旧的「CodeBERT 序列 + GCN/GAT 同构图」写法已作废）**——见下方「5.3 对比实验（现行）」小节。传统工具基线 = `_m1.json` node_flags 图级聚合（任一节点命中该类→图命中）的做法只适用于 **Slither**；其余五个工具须各自实跑（`scripts/baseline_static_tools.py` 已备好 `DETECTOR_TO_CLASS` 与 solc 版本选择）
  - [x] 风险记录：**DIVE/SolidiFI 数据已就位（2026-09-11）**；层次二与 5.5.1 需先建类别映射表（SolidiFI 前缀→七类；DIVE 已剔除 Bad Randomness，7 维可直接用）；验证集可能仅约 50 图、低正样本类（4~6 个）对 macro-F1 敏感，按手册记录训练/验证差距
- [ ] 文件组织（2026-09-08 v5：metrics/train/evaluate 与 CI smoke 仍待实现）
  - [x] dataset.py：已完成（2026-09-07；数据层：_pyg.pt 结构 + _feat.pt(x) + 标签对齐加载断言 + 边级消融开关；不过 MLP，只组合与裁剪）
  - [x] metrics.py：已实现（2026-09-12；指标层：**micro-F1（主）**/macro-F1（参考，须标注 support）、每类 P/R/F1、mAP/macroPR-AUC、subset accuracy、`search_global_threshold`（目标 val micro-F1、tie 取小、零正类跳过）；纯函数不 import dataset/model；`tests/test_metrics.py` 9 用例）
  - [x] make_splits.py（A2，2026-09-12）：`--strategy constrained`（默认）=固定种子随机基线 + **覆盖约束校正**（最小确定性替换；C1 合计 ≥30%、C2 每划分每类 ≥1）；输出 split_seed*/splits.csv/split_report（含 rule_check C1+C2、去重不变量与 coverage_fix）/coverage_swaps_seed*/split_metadata_seed*/dedup_dropped.txt/unmatched；`--strategy random` 输出隔离到 `random_snapshot/`（旧快照可逐字节复现）
  - [x] **T-A 两级池去重（2026-09-12 P1，已落地）**：`--dedup source-sha1+address`（默认）：level-1 源码内容 sha1 丢 46（内容相同的 asd_/nasd_ 副本，全为全零样本）+ level-2 项目标识/地址丢 1（**全库唯一多标签样本** 0x627fa62c…，两份源码 1847 vs 1842 字节、sha1 抓不到，曾跨 train/val）→ 池 **495 → 448**；`dedup_dropped.txt` + `split_report.json::dedup` 记录明细；`tests/test_make_splits.py` 新增两级去重用例 + 黄金值改写
  - [x] 划分门槛收口：由覆盖约束校正构造达标（三种子全部通过，去重后替换 18/16/12 个合约）；主划分种子＝seed0（用途定位声明见 `experiments/decisions.md` §12）
  - [x] 口径审计（2026-09-12）：`scripts/audit_data_funnel.py` 已建并运行 → `docs/data_funnel.md` + `products/alldata/splits/data_funnel.json`（含 `846→591` 差额 255 逐条拆解、图结构口径 §4、口径绑定指纹 §5）
  - [x] DIVE 抽样（2026-09-12，P1 定稿 n=900）：`scripts/sample_dive_subset.py` 已建并跑出定稿结果（seed=0/**n=900**/均匀，front_running=30 ≥20 闭案，未触发后备；多标签 614/900=68.2%）→ `products/dive/splits/sample_seed0.json` + `sample_report.json`；n=1000 的旧试验（fr=31）已作废
  - [x] **T-A 去重后刷新口径（已履行）**：已重跑 `audit_data_funnel.py`；已刷新 `decisions` §13/§14 与手册 §10.2/§10.5 的池规模与 val/test 支撑数字（新指纹见 §14.2）；未刷新即视为文档/产物滞移
  - [x] **M3 前端化（2026-09-12，已实施并验收）**：`m3_build_features.py` → 纯通道构建（schema v2：`struct`/`type_id`/`sv` + 逐通道 sha256；删 MLP/Embedding/`manual_seed`；`--variant`/`--feat-groups` CLI 退役；`_cb.pt` 命中时不加载 CodeBERT）；`dataset.py` → `GraphSample` 通道组合 + §4 断言（schema/形状/行序/值域/逐通道哈希报通道名；`--verify-channel-hash`）；`model.py` → `NodeFuser`（可学习嵌入 + **融合前**掩码，`ablate_sv`/`feat_groups`/`cb_channels` 确定性与 `prior_dropout`/`struct_dropout` 按图 Bernoulli(0.2) 严格分层）+ `sample_dropout_masks` + `parameter_report`；旧 `_feat.pt` 归档 `graphs/legacy_feat_pre_frontend/`。验收：T2 冻结等价**逐位相等**（maxdiff 0、5 图抽查）、T1 无泄漏单测、全库 581 图断言通过、**39 passed**。（发现待裁定：cb 函数级通道缺行 35195 ≈37.6%（继承函数不在 functions 表），旧路径同行为、非回归；**后续已两轮修复，见下条**）
    - 附带产物：`tests/test_frontend.py`（13 用例）、`docs/M3_frontend_design.md`（已实施版）
  - [x] **函数级通道缺口修复（2026-09-12 三轮，已完成）**：`scripts/audit_cb_func_gap.py` → 修复前/后清单（`cb_func_gap.json` / `cb_func_gap_after.json`）；M2 补登记（alias + modifier + **legacy_ctor**，`fn_meta_table` 双隔离）+ **`normalize_ast` 两风格 AST 兼容**（R5）→ `functions` 14741 → **23260**；缺口 **37.6% → 2.8% → 2.55% → 2.52%**（**2356 行 / 475 键 / 382 图 / 覆盖率 97.48%**）；`_cb.pt` 全量重建（≈55 min）与增量补丁（7m25s / 1m08s / R5 1m09s）全库逐位等价；R2 根因＝旧写法**未同步改写 `function` 字段**（已复现并修正）；R5 后库级结构统计刷新（边 226511、DFG 146712、CALLBACK_RISK 511/86、M1 raw hits 21571）；全库断言（含 cb 双通道哈希）+ `pytest` **43 passed**
  - [x] **残留函数级通道缺口（R1/R3/R4 保持现状，已记档）**：待办与裁定入口 **`docs/residual_gaps.md`**（**R1 合成作用域 2356 行不可编码**（保持零向量 + 披露）；**R2 老式继承构造函数已闭合**；**R3 可见性元信息已被三轮连带解决**——27556 节点经 M3 `fn_table` 回退获得真实值，属修正性结构通道变化；**R4** `--cb-patch` 不删多余键；**R5 三图 AST 格式已闭合**；**附：AST 映射丢弃率 97.2% / 18 图无 AST 边 → 披露项**）
  - [x] 匹配键（2026-09-05 定稿）：已按项目前缀并集实现（先 nasd_ 后 asd_；0 unmatched 验证）
  - [ ] buggy_* 噪声处置（2026-09-05 定稿）：主实验剔除 asd_buggy_*/nasd_buggy_*（每合约同款注入噪声标签，与具体特征不对应）；另做含 buggy_* 消融对比论证剔除合理性；剔除明细写入 products/alldata/splits/unmatched_contracts.txt 单独一节
  - [x] train.py：已实现（2026-09-12；masked BCE + 按图 `L_var`（population std、开方内 eps 防 NaN）+ DropEdge/先验 dropout + 双模块 checkpoint + JSONL 日志（含 `score_mean/score_std`）+ perf_counter 计时；`--limit-graphs` 取前 N 个含正样本图；`--seed`/`--split-seed` 分离）；`tests/test_train_utils.py` 9 用例；`--limit-graphs 12 --epochs 3` smoke 通过
  - [x] evaluate.py：已实现（2026-09-12；纯评估，只 import model/dataset/metrics）；复用 val_best_probs.pt 选阈值、内部测试固定 0.5 + val 阈值双报告、`--summarize` 汇总 mean±std；`tests/test_evaluate.py` 3 用例。**DIVE 外部测试两设定**与 `--task ablation/baseline` 属阶段 F/G（待主实验跑通后）
- [ ] 读取标签文件 alldata(readonly)/contract_labels.json
- [ ] 建模七类多标签分类
- [ ] 设定损失：
  - [ ] BCEWithLogitsLoss
  - [ ] L_var = lambda * max(0, tau - std(a_v)); tau=0.1, lambda=1e-3
- [ ] 处理类别不平衡
  - [ ] pos_weight_c = 负样本 / 正样本，截断到 20
  - [ ] 某类正样本为 0 时跳过该类
- [ ] 训练/验证
  - [ ] 早停：连续 5 个 epoch 验证 **micro-F1** 不提升（2026-09-12 主指标改 micro-F1；macro-F1 同步记录作参考）
  - [ ] 记录 score_mean / score_std（大纲改II 改名）
  - [ ] 检查 std 低于 0.05 时排查池化退化
- [ ] 推理
  - [ ] 输出七类概率 p_G
  - [ ] 输出多标签预测 yhat_G
  - [ ] 输出节点可疑度列表 {(v,a_v)}（按 a_v 降序）
  - [ ] 输出 TopK 可疑节点集合 V*
  - [ ] 可选可视化子图 G_view（CFG_FLOW/DFG_DEP 一跳扩展）
  - [ ] 可选梯度显著性 g_v 及其 P@k/R@k/IoU（仅评估）
  - [ ] 只作为辅助解释，不声称真实根因定位
- [ ] 评估
  - [ ] 两种设定：MVD-HG 内部测试（同分布，**已完成 2026-09-13**）+ DIVE 外部测试（跨数据集，阶段 G）
  - [x] **主指标 micro-F1**；macro-F1 标为参考并注明含 3 个池内 ≤6 支撑类
  - [x] **逐类 F1 与 per-class PR-AUC 均随 support 报告；support ≤2 的类仅描述性呈现、不进比较结论**
  - [x] 验证集选阈值 0.2~0.8，步长 0.05，**目标 val micro-F1**；稀有类不单独调阈
  - [ ] **口径报表**：论文数字取自 `docs/data_funnel.md`（`python scripts/audit_data_funnel.py`）；多标签主张按“架构性声明 + DIVE 外部证据”（DIVE 证据待阶段 G）
  - [x] 记录固定阈值 0.5
  - [x] >=3 个 seed 的均值 ± 标准差（runs/summary.json）
  - [ ] DIVE：各类 PR-AUC、全零标签子集每类 FPR、20~30 例 FN/FP 人工检查、归因分层（阶段 G）
  - [ ] SolidiFI 报告 a_v/s_v/g_v 三类分数（g_v 按注入类别归属）+ a_v 增量覆盖节点统计（阶段 G）

## 九、收尾与验收门槛
- [ ] 全链路在 1 个样本上跑通
- [ ] 关键中间产物齐全（**结构产物**均在 products/alldata/graphs/ 下；**M3 特征正典在 `products/alldata/graphs_ft/ss{S}`**（§37 微调，**逐划分种子取：seed{S} 配 ss{S}**））：_hetero.json、_m1.json、_pyg.pt（只读结构）、_feat.pt（schema v2 通道字典，融合在 model.NodeFuser）；products/alldata/splits/、runs/seedN/、eval_results/ 按架构文件归档；外部评估读 DIVE/、SolidiFI/（只读）
- [ ] 图结构字段完整，后续模块可直接消费
- [ ] M1 结果与 M2 图结构一致
- [ ] 训练可启动，且 validation loss / macro-F1 可观察
- [ ] 论文中需要记录过滤统计、样本数、边类型、特征维度、损失项

## 十、下一步执行顺序（推荐）

> **2026-09-11 调整（大纲改II）**：先重做 M2 CALLBACK_RISK，再向下游同步；M5 数据集/划分/消融按改II。

0. ✅ **M2 CALLBACK_RISK 重做（已完成 2026-09-11）**：收窄外部调用节点（排除 2300-gas send/transfer 与 `Emit Transfer` 事件误报）→ 高置信定义 → `build`×2（hash 一致）→ `m1_runner --force` → `convert_pyg` → M3 `_feat.pt` → M4 22 用例回归（结果：509 边/85 图，**2026-09-12 R5 后 511 边/86 图**，详见第三节）
1. M3 先对 1 个图实现双通道 CodeBERT、结构特征和 128 维 `x`
2. 验证函数级向量共享、节点窗口差异、缺失字段容错及先验 dropout
3. 批量生成 `_cb.pt` 与 `{safe}_feat.pt`（**schema v2 通道字典**；不写回 `_pyg.pt`；消融在 `model.NodeFuser` 的 `AblationConfig`——`--variant`/`--feat-groups` CLI 已随前端化退役，2026-09-12）
4. M4 实现 RGCN 两层、`a_v` 可疑度读出、h2-based Readout（**已完成 2026-09-07**：model.py + 22 用例；L_var 在 M5）
5. M5 顺序：dataset.py + metrics.py → make_splits.py（**固定种子 8:1:1 + 覆盖约束校正（C1/C2）**，含 splits.csv/split_report/coverage_swaps/metadata/unmatched）→ train.py 单种子（日志用 `score_mean/score_std`）→ evaluate.py 主实验（**MVD-HG 内部测试 + DIVE 外部测试**）→ 3 种子汇总 → 阶段 5 消融（5.4.1/5.4.2）/基线（eval_results/）

## 十一、文档与文件组织同步（2026-09-04 再设计）
- [x] 项目组织架构.md：scripts/ 新增 dataset.py/metrics.py；_pyg.pt 只读、_feat.pt 语义锁死为 schema v2 通道字典（融合在 model.NodeFuser，无变体文件，2026-09-12 前端化）；runs/seedN/ 增 config.json
- [x] 论文开发手册.md：3.2 目录表、8.1/8.7（_feat.pt 语义、--only 验证入口、--variant 消融变体）、10.2（加载期一致性约束）、10.4（dataset/metrics 分层 + config.json）、12（新增 25/26）
- [x] Todo_List.md：M3/M4/M5 文件组织与验证入口更新；新增“十二、详细代码修改方案”
- [x] 大纲 docx：本次为代码文件组织调整，不涉及大纲规则/协议内容，无需改动（如后续需在大纲 5.x 补充产物目录说明再改）
- [x] **2026-09-11 按 `研究点一细化大纲改II.docx` 同步**：手册（头部复核块、3.2/3.3 目录与数据集、4.5 日志改名+推理输出、6.3/6.6 external_callback、7.6/7.8 CALLBACK_RISK、8.4/8.5 结构特征、9.1 关系数、9.6 日志、10.2/10.3/10.5/10.6/10.7、11.x、12 表+新增错误 40–45、13）与 Todo（头部、一节路径、三/四/六/七/八/十/十二节）全部按 `改II` 更新，行为影响的项已回标为未完成。

## 十二、详细代码修改方案（M3/M4/M5 各文件，2026-09-04 定稿）

> 原则：_pyg.pt 只读；_feat.pt 语义锁死（schema v2 通道字典，融合与掩码在 model.NodeFuser）；数据/指标/训练分层；消融三层（边=dataset 零重跑，特征=NodeFuser 通道级零重跑，模型=开关）；每次运行落 config.json。

### 12.1 scripts/m3_build_features.py（新建，M3）

> **状态（2026-09-12）：本节旧设计（MLP 后 128 维 `_feat.pt` + 文件级变体）已随前端化退役**，
> 以 `docs/M3_frontend_design.md`（已实施版）与手册 §8 为准：`_feat.pt` = schema v2 通道字典
> （struct/type_id/sv + 逐通道 sha256），融合在 `model.NodeFuser`，无 `--variant`/`--feat-groups` CLI；
> 2026-09-12 新增 `--categories`（跨数据集冻结 IR 字典，DIVE/SolidiFI 必须传主库 ir_cat.json）。
> 以下旧函数契约仅存历史参考。

- 函数契约：
  - `encode(text, tok, model, max_len) -> Tensor[768]`：手册 8.7 照抄（空文本返回 zeros(768)）
  - `build_node_window(lines, node, fn_start, fn_end) -> str`：手册 8.7 照抄
  - `build_struct_features(hetero, m1, src_lines) -> Tensor[N,S]`：8.5 的 18 项（缺失补 0，归一化位置补 0.5）
  - ~~`build_type_embedding(hetero) -> Tensor[N,64]`~~（已移入 model.NodeFuser 可学习 Embedding）
  - ~~`assemble_x(...)`~~（已删除；融合 = model.NodeFuser.proj）
- 输出契约：
  - `{safe}_cb.pt = {"func": {func_key: 768}, "node": {node_id: 768}}`（现行不变）
  - ~~`{safe}_feat.pt = Tensor[N,128]`（MLP 后）~~（现行：schema v2 通道字典）
  - ~~`--variant no-prior / no-codebert / no-cb-func / no-cb-node`、`--feat-groups`~~（已退役 → `model.AblationConfig` 的 `ablate_sv` / `cb_channels` / `feat_groups`）
- CLI：`--only <图前缀>`、`--in-dir/--out-dir/--m1-dir`、`--force`、`--cb-patch`、**`--categories <冻结字典路径>`（2026-09-12 新增）**
- 禁止：写回 `_pyg.pt`（验收：跑前后 `_pyg.pt` 的 hash 不变）

### 12.2 scripts/model.py（已完成，2026-09-07 v4 定稿）
- `SSMHG(in_dim=128, hid=128, num_relations=5, num_bases=5, num_classes=7, dropout=0.3, conv_type="rgcn", use_meanpool=False)`
- `forward(x, edge_index, edge_type, batch=None, return_intermediates=False) -> (z, a, node_logits)`；批图 z=[B,7]；return_intermediates 返回 dict{z,a,node_logits,h1,h2,alpha,hg}
- Readout 使用**第二层传播结果 h2**（=h_v^(L)），禁用输入 x；alpha=a/(sum(a)+1e-6)，批图按图 scatter 归一化
- 消融开关：`use_meanpool`（仅替换 Readout）、`conv_type ∈ {rgcn,gcn,gat,sage}`（2026-09-21 扩到四个；**只有 rgcn 关系感知**，其余三个忽略 `edge_type`；`tests/test_model_smoke.py::test_non_rgcn_convs_ignore_edge_type` 机检）、`num_bases=4`（仅消融，默认 5）。⚠ 关系盲算子族**不是 5.3 的对比方法**（大纲 5.3 = 六个传统工具 + EGFL + MVD-HG/MANDO-LLM），只作 §40.4 内部证据
- helper：`validate_edge_types` / `apply_edge_mask`（同步过滤边，M5 DropEdge 用）/ `safe_readout` / `_scatter_add`（index_add 实现，免 torch_scatter）
- 底部 `if __name__ == "__main__"`：随机数据 smoke test（组合/极端图/非法输入/批图等价）——M4 独立验证入口；完整用例见 `tests/test_model_smoke.py`（22 个）
- 空边/孤立：PyG 2.7.0 官方行为（root_weight/add_self_loops）已实测可用，无自定义 fallback

### 12.3 scripts/dataset.py（已完成，2026-09-07）
- `build_proj_labels() -> dict[str, list[list[int]]]`：读 `alldata(readonly)/contract_labels.json`，key=项目前缀（lower；剥前缀顺序先 nasd_ 后 asd_——nasd_ 含 asd_ 子串，先剥 asd_ 会把 nasd_xxx 误剥成 nxxx）
- `build_index() -> (dict[base, label7], unmatched:list)`：扫 `products/alldata/graphs/*_pyg.pt`，项目内多合约标签取并集；未匹配 base 收集返回（供 make_splits 写 txt）
- `load_graph(base, label, ab: Ablation) -> dict`：
  - `torch.load("{base}_pyg.pt")`；**`assert base in index`**（第一道一致性约束，缺标签直接报错）
  - `x = torch.load("{base}_feat.pt" 或 "{base}_feat_{variant}.pt")`，断言 `x.shape[1]==128`（语义锁死校验）
  - 边级消融：`ab.resolved_drop_edges()` → 白名单校验（`DROPPABLE_EDGES` = 全部 5 个物理关系，越界编号报错）→ 按 `edge_type` 过滤 `edge_index/edge_type`（零重跑）；`drop_ast=True` ⇔ `--drop-ast` ＝ 删 relation 1+2（AST_PARENT + AST_PARENT_SAME）
  - 返回 `{"x", "edge_index", "edge_type", "label", "name"}`
- `@dataclass Ablation`：`drop_edges: set[int]`、`drop_ast: bool=False`（`--drop-ast` → 1+2）、`feat_variant: str|None`（对应 `_feat_{variant}.pt`）；`resolve_drop_edges()` 做白名单校验
- 单图自检入口：`python scripts/dataset.py --check <base>`（打印 N/E/type 分布/x 维度）

### 12.4 scripts/metrics.py（新建，M5 指标层）
- `macro_micro_f1(preds01, ys01) -> (float, float)`：sklearn `f1_score(average="macro"/"micro", zero_division=0)`
- `per_class_prf(preds01, ys01, names) -> dict`：`precision_recall_fscore_support` 每类 P/R/F1
- `mAP(probs, ys01) -> float`：`average_precision_score(average="macro")`
- `subset_accuracy(preds01, ys01) -> float`（可选）
- `search_global_threshold(probs, ys01, candidates) -> dict`：仅用于验证集，目标 validation macro-F1；并列时取较小阈值。
- 零正类：保留 `support=0`，跳过该类 AP，并返回 `ap_classes_used`。
- 供 train/evaluate/ablation 三处共用，不得 import dataset/model

### 12.5 scripts/make_splits.py（按大纲改II 5.1 重做）
- 从 `dataset.build_index/build_proj_labels` 导入（不重复标签逻辑）
- **主方案（改II，A2 已落地）**：唯一合约**固定随机种子 8:1:1** 划分为 train/val/内部测试；在随机基线之上施加**覆盖约束校正**（C1 合计 ≥30%、C2 每划分每类 ≥1；最小确定性替换：换入稀有类正样本、换出全零合约），不达标时报错换种子；输出 `split_seed{seed}.json`、逐类 support（`split_report.json` 的 `rule_check` + `coverage_fix`）、**划分种子**、`splits.csv`、`coverage_swaps_seed{seed}.txt`（替换清单）与 `split_metadata_seed{seed}.json`（均已实现，2026-09-12；random 快照隔离在 `random_snapshot/`）。旧的“多标签迭代分层（`iterative-stratification`）”仅作对照快照，不作主方案。
- 输出 `products/alldata/splits/split_report.json`：每类 pos/neg、正负比、唯一合约数、多标签合约数、全 0 合约数、三划分数量（手册 10.2.4）；外加逐种子×三划分逐类 support 与 `rule_check` 门槛审核（2026-09-12）
- 输出 `products/alldata/splits/unmatched_contracts.txt`：未匹配 base 列表 + 计数（手册 10.2.2 透明性报告）
- **新增：DIVE 外部测试集构建**（手册 10.2 第 7 条）——去 Bad Randomness=1、全零标签作为负样本保留、固定种子分层抽样 ≥500 合约（每类 ≥20 正样本），输出抽样清单与类别统计到 `products/dive/splits/`（不改 `products/alldata/splits/split_seed*.json`）
- CLI：`--strategy {constrained(默认),random}`（random 输出隔离到 `<out-dir>/random_snapshot/`）、`--seeds 0,1,2`、`--split 0.8,0.1,0.1`、`--min-pos-ratio 0.30`（大纲 5.1 门槛 C1：val+test 合计 ≥ 该类正样本数比例，2026-09-12 实现；C2=每划分每类 ≥1，常量 `MIN_POS_PER_SPLIT`）、`--dive`（构建外部测试子集；阶段 5 待实现）

### 12.6 scripts/train.py（新建，M5，v4）
- 只 import：`model`、`dataset`、`metrics`、sklearn
- CLI：`--seed 0 --epochs 200 --batch-size 32 --lr 1e-4 --weight-decay 1e-4 --scheduler-patience 3 --early-stop-patience 5 --drop-edges 3 --drop-ast --meanpool --conv gcn --ablate-sv --cb-channels cb_node --feat-groups base ...`（消融开关透传；**2026-09-12 前端化后**：`--feat-variant`/`--drop-feat-edge` 退役，特征消融走 `model.AblationConfig`，边消融走 `dataset.Ablation` 的 `--drop-edges`/`--drop-ast`）
- **种子语义（2026-09-12 裁定，见 `experiments/decisions.md` §16）**：`--seed`=训练种子、`--split-seed`（默认=`--seed`）=读 `split_seed{split_seed}.json`；主实验 seed0/1/2 = 同名划分×同名训练种子；两类种子显式分离。
- **批图（自实现 collate，不用 PyG DataLoader）**：通道沿节点维 cat + `edge_index` 加偏移 + `edge_type` cat + batch 向量；DropEdge 先逐图 mask 再 batch；`fuser`+`model` 双模块 `state_dict` 一起存 checkpoint；`SSMHG(in_dim=fuser.hidden)` 回读不硬编码（fuser 输出 128，非融合输入 1631）。
- 启动断言：每个图通道契约通过（`dataset.load_graph` 的 schema/形状/哈希断言；M3 未跑或旧格式直接报错）
- pos_weight：按训练集 `neg/pos` 截断 20；正样本为 0 的类用 class mask 从逐元素 BCE 的分子和分母中显式跳过，不传 `pos_weight=0`。
- 损失：`l_cls + 1e-3*L_var`；`L_var` 按图计算 population `a.std(unbiased=False)` 且保留梯度，单节点图 std=0；AdamW + `clip_grad_norm_(1.0)`；使用 `ReduceLROnPlateau(mode=max, factor=0.5, patience=3)`。
- 训练期先验/结构 dropout：`model.sample_dropout_masks(G, prior_p=0.2, struct_p=0.2, generator)` 采样 `(G,)` 掩码 → 随 `batch` 传入 `NodeFuser`（融合前置零）；验证/测试不传掩码。
- 早停：验证 **micro-F1** 连续 5 epoch 不提升（2026-09-12 主指标；macro-F1 同步记录作参考）；每个 epoch 日志字段按 10.3（含 **`score_mean/score_std`**），并增加 `samples_processed/graphs_processed`；GPU 可用时增加 `gpu_mem_allocated`，CPU 写 null。
- 产物：`runs/seed{seed}/log.txt`（epoch JSONL）、`best.pt`、`last.pt`、`config.json`、`results.json`、`thresholds.json`（argparse+全部超参快照）；记录 `run_wall_seconds/data_load_seconds/train_seconds/validation_seconds/epoch_seconds_mean/graphs_per_second` 和硬件环境。`graphs_per_second=train_graphs/train_seconds`，只统计 optimizer loop；run 总耗时不重复写入每个 epoch 行。

### 12.7 scripts/evaluate.py（新建，M5，纯评估）
- 只 import：`model`、`dataset`、`metrics`（不实现数据/指标逻辑）
- 主实验（默认）：加载 `runs/seed*/best.pt` → 验证集阈值搜索 0.2~0.8/步长 0.05 选 best → **MVD-HG 内部测试**固定 0.5 与 best 双报告 → `runs/seedN/results.json` → 3 种子 `runs/summary.json`（均值±标准差）
- **DIVE 外部测试（改II）**：一次性评估，不参与训练/验证/早停/阈值/模型选择；报告各类 PR-AUC、全零标签子集每类 FPR、20~30 例 FN/FP 人工检查；结果写 `eval_results/`
- `--task ablation|baseline` → `eval_results/`（10.6；**基线以上方「5.3 对比实验（现行）」小节为准**；**两种设定：MVD-HG 内部测试 + DIVE**）
- SolidiFI 层次二：$a_v/s_v/g_v$ 的 P@k/R@k/IoU（$g_v$ 按注入类别归属）+ “$a_v$ 增量覆盖节点”统计
- 每类 P/R/F1、macro/micro-F1、mAP 用 `metrics.py`
- 主阈值为验证集选择的单一全局阈值；per-class 阈值仅作补充报告；记录 support=0 和 AP 跳过类别；保存所有候选阈值及 tie 选择依据到 `runs/seedN/thresholds.json`。

### 12.7.1 5.3 对比实验（现行 · 2026-09-21 按大纲 `改II` 原文重列）

> 🔴 **本节的权威来源是大纲 `改II` 5.3 的表（段落 [400]–[411]）与层次一说明（段落 [395]）。**
> **此前 Todo 与手册写的「Slither 规则 + CodeBERT 序列 + GCN/GAT 同构图」是旧设计，已作废**——
> 大纲 5.3 表里**既没有 CodeBERT、也没有 GCN/GAT**。

大纲原文（逐字）：

| 基线 | 作用 |
| --- | --- |
| Securify、Mythril、Slither、Manticore、Smartcheck、Oyente | 静态传统工具对比 |
| EGFL | 验证异构图边类型是否必要 |
| MVD-HG、MANDO-LLM | 基线 |
| 本文方法 | 完整方法 |

> 大纲 [411]：**所有基线均按多标签任务统一训练和评估。传统模型也输出七维规则命中结果，而不是单标签类别。EGFL、MVD-HG、MANDO-LLM 等模型均输出七维 logits，并使用 `BCEWithLogitsLoss` 训练。**
> 大纲 [395]：**5.3 全部对比方法均在两种设定下评估** = 同分布（MVD-HG 内部测试）+ 跨数据集（DIVE 外部测试）。

| 基线 | 实现位置 / 现状 | 待办 |
| --- | --- | --- |
| 传统工具 ×6 | `scripts/baseline_static_tools.py`（`DETECTOR_TO_CLASS` 29 条检测器含 SWC 引用、`installed_solc_versions`/`version_ok`/`pick_solc_candidates`；**只跑通了 Slither**，产物 `eval_results/baseline/slither_alldata`） | ✅ **六环境已落地（2026-09-23，`decisions.md` §47）**：`scripts/install_traditional_tools.sh` 一键复现，五个工具各开独立 conda env、base 零污染，六个均**真实跑通**（非仅安装）。**剩余工作 = 接入**：`baseline_static_tools.py` 现只有 `run_slither`，须为其余 5 个补 `run_*` + 检测项→七类映射（如 manticore 的 `reentrancy`/`overflow`/`suicidal`/`delegatecall`/`unused-return`/`env-instr`；oyente 的 6 项；securify 的 pattern 名；smartcheck 的 SOLIDITY_* ruleId），并按 §47.4 先统计各工具**可分析合约数** |
| **EGFL** | ✅ **已实现并跑通（2026-09-22）**：`scripts/baseline_egfl_build.py` + `baseline_egfl.py`（原生字节码模态），产物 `eval_results/baseline/egfl/seed{0,1,2}/` | 🔴 两处口径损失必须随结果披露：① 图分支的 256 维是**重建件**（原 `cfg_graph` 作者未开源）；② **83.2% 的合约被截断到 seq_len=512**（8 GB 卡跑不动它的稠密 O(L²) 注意力；原论文 SEQ_LEN=8000） | 大纲列的是**具体方法**。⚠ 本仓此前的 `--conv {gcn,gat,sage}`（`runs/arch_n9*`）只**近似**了「验证边类型是否必要」这个**目的**，不是 EGFL 本身 |
| **MVD-HG** | ✅ **已实现并跑通（2026-09-22）**：`scripts/baseline_mvdhg_build.py`（**驱动原仓库代码**建图） + `baseline_mvdhg.py`，产物 `eval_results/baseline/mvdhg/seed{0,1,2}/` | 覆盖率 448/453；5 个失败样本**全在 train**、test 一个没少 ⇒ 逐类 support 与本文方法可比 |
| **MANDO-LLM** | 🟡 **代码已就绪、训练中（2026-09-22）**：`scripts/baseline_mando.py`（PyG `HGTConv` 替 dgl，无需新建 conda 环境），产物 `eval_results/baseline/mando/seed{0,1,2}/` |  ✅ 名称已裁定（2026-09-21）：以 **`MANDO-LLM`** 为准，大纲正文的 `MANDO-HGT` 须同步改（`.docx` 改动需作者授权）。基线代码已由作者安装在 `/home/saumarez/projects/deep-learning`（⚠ 在本仓读取硬边界之外，见 AGENTS.md） |
| 本文方法 | ✅ `runs/seed{0,1,2}` | 两设定评估（DIVE 见 `eval_results/dive/`） |

✅ **2026-09-22/23 状态收口**：四个基线（`slither_alldata` / `mvdhg` / `egfl`（+ 其论文 lr 臂 `egfl_ownlr`）/ `mando`）
各 3 种子**全部跑完**，逐类三口径 × 两工作点的明细见 `experiments/baseline_three_caliber_tables.md`
（`scripts/collect_baseline_tables.py` 程序生成，**16 张表**）。**2026-09-23 新增两块跨口径读数**（`decisions.md` §49）：
**表 1 = 逐类二分类 F1（binary-F1）**（三篇论文「7 个独立二分类器」的原生判决规则；平均列 本文方法 0.6363 /
MVD-HG 0.3224 / EGFL 0.1138 / MANDO-LLM 0.1091 / Slither 0.2937）、**表 2 = 方法 × 8 口径总览**。
🔴 该二分类口径**仅补充、不进主表**（`metrics.py` 契约 + 手册 §1223 的「稀有类不单独调阈」裁定）；
其 **@0.5 工作点逐位等于 macro 表的逐类格**（恒等，故不另列）。⚠ 换到该口径后**排序与量级都不变**
⇒ 基线读数低**不是**「阈值没调好」；且 EGFL 两行与 MANDO 行的最高口径读数**都不高于平凡下限 0.6199**。

✅ **2026-09-23（同日晚）第二轮：三条基线在「含 `buggy_*` 的新正典（池 497）」上补跑完毕**（`decisions.md` §52）。
§51.6.2 的「换 497 池不可行」**被用户裁定推翻**（理由仍写成表头警告，不是取消）。新增产物区一律带 `_buggy`
后缀（离线特征 `products/alldata/baseline/<名>_buggy/`、模型产物 `eval_results/baseline/<臂>_buggy/seed{S}/`、
`slither_buggy/`），驱动 = `python scripts/run_baselines.py --layout buggy`；
交付物 = `experiments/baseline_three_caliber_tables.md` 的**「三、」段（表 15–28）**，**canon37 段（表 1–14）逐字节不变**。
🔴 **读该段前必须知道的三条**：① 两段 test 集不同（46→49）**且**特征配对方式也不同
（canon37 段三种子全用 `graphs_ft/ss0`，本段用配对的 `cb_ft_ss{S}`；`_cb.pt` 逐张量随 ss 变）⇒ **跨段不可比**；
② `buggy_*` 标签绝大多数是全 1 ⇒ 该段必须并列 `clean_only`（剔 buggy）诊断列，**不得**据此声称补数据提升了检测能力；
③ **MVD-HG 在 ss1 上 test 少 1 个**（48/49）⇒ 该行分母与其余行不同，表头已显式标注。
🔴 **本次顺带修掉 5 个「只出错、不报错」的坑**（§52.4），其中第 1 个是实测踩到的：
`baseline_mvdhg_build.ensure_layout()` 漏改正典后缀 ⇒ 497 池的 44 份 AST 被写进**正典根**，
而 `_assert_under_feature_root` 因为**自己也在查正典根**而放行（已复原正典根 + 新增源码级守卫
`test_all_feature_root_calls_pass_the_suffix`）。

✅ **四条已裁定（2026-09-21 用户）**：
(a) 基线名 = **`MANDO-LLM`**（非 `MANDO-HGT`）；(b) **`SCVHunter(2024)` 不纳入**；(c) 三个论文基线（EGFL / MVD-HG / MANDO-LLM）**已安装在 `/home/saumarez/projects/deep-learning`**——⚠ **该路径超出「只能读取 SSM-HG」的硬边界，接入方式待确认**；(d) 关系盲算子族（GCN/GAT/SAGE + `*_pm`）**保留**（按「有 F1 结果则保留」，实测全部有完整 micro/macro/mAP），作 §40.4 附录证据，不入 5.3。

> ⚠ **关系盲算子族不属 5.3**：它是 `decisions.md` §40.4「关系感知 vs 关系盲」的内部证据，n=9 结果见 `experiments/ablation_n9_results.md`。报告口径三条（关系盲 / 参数量不匹配 / 必须随附 `parameter_report`）见 `scripts/run_arch_baselines.py` 的 docstring。

### 12.8 消融映射（手册 10.6 / 大纲改II 5.4 → 实现位置）

**5.4.1 必要消融（11 项）**（**2026-09-12 前端化后实现位置**）

| 消融变体 | 实现位置 |
| --- | --- |
| 去 DFG_DEP / CFG_FLOW / AST_PARENT / CALLBACK_RISK | dataset `--drop-edges 3/0/4`、`--drop-ast`（=删 relation 1+2；零重跑） |
| CALLBACK_RISK 上限 4 vs 不限制 | 唯一重跑 M2 的变体（`build --callback-limit 0` + 下游同步） |
| 去函数级 CodeBERT | model `AblationConfig(cb_channels=("cb_node",))`（通道级、零重跑） |
| 去节点级局部 CodeBERT | model `AblationConfig(cb_channels=("cb_func",))`（同上） |
| meanpooling 替换节点可疑度 $a_v$ 加权 | model.py `use_meanpool=True`（train 透传） |
| 关闭 $L_{var}$ | train.py `--lambda-var 0` |
| 关闭先验 Dropout | train.py `--prior-dropout 0`（NodeFuser 掩码不采样） |
| 节点结构特征分组消融 | model `AblationConfig(feat_groups=base\|base+sem\|all)`（报告 (a)(b)(c) 与 0.3pp） |

**5.4.2 可选消融（6 项）**

| 消融变体 | 实现位置 |
| --- | --- |
| 添加 CALLBACK_RISK_REV | 重跑 M2 加反向边（`build --callback-rev`） |
| RGCN 层数 L=1/2/3 | model.py `num_layers`（train 透传） |
| num_bases 不同取值 | model.py `num_bases`（train 透传；默认=关系数 5） |
| 隐藏维度 128/256 | model.py `hid`（train 透传） |
| DropEdge | M5 train（先单图 mask 再 batch；默认关） |
| 微调 vs 冻结 CodeBERT | M3 微调分支 / M5 微调模式；评估 val macro-F1（大纲 5.4.2 原文口径，未随主指标口径改动） |

> **`改I` 独有、`改II` 5.4 已移出必做清单的变体**（可作补充分析，不计入主消融）：去 M1 先验 $s_v$（M3 `--variant no-prior`）、RGCN→GCN（model.py `conv_type="gcn"`，**既不在 5.4 消融表、也不在 5.3 对比表**——2026-09-21 按大纲原文更正，只作 §40.4 内部证据）、去外部调用回调相关特征（结构特征 2/3/12/13/16 置 0）、仅 $s_v$ 排序 / 仅 RGCN 学重要性（evaluate 排序分支 + model 开关）。

### 12.8.1 消融实验详细执行方案（结合现有结果，2026-09-16）

**A. 统一口径与产物隔离**

- 5.4 主消融统一使用主库现行正典池 **453**、`products/alldata/splits/split_seed{0,1,2}.json` 和当前 `_feat.pt`/`_cb.pt`（§37 起：**`products/alldata/graphs_ft/ss{S}`**，**逐划分种子取，seed{S} 配 ss{S}**；训练种子与划分种子分离）；主划分固定 seed0，seed1/2 只作稳健性复核。不得把旧 `runs/prior_448pool/` 的绝对值与现行 453 池混比。
- 每个变体只改变一个因素；训练/划分种子、batch=32、lr=1e-4、weight_decay=1e-4、200 epoch 上限、val micro-F1 早停、阈值候选 0.20–0.80、固定 0.5 与 val threshold 双报告均与主实验一致。每个变体至少先跑 seed0，进入论文主消融表必须跑 seed0/1/2，并报告 mean±std。
- 主比较指标按优先级为 `micro-F1@0.5`、`micro-F1@val_thr`、mAP；macro-F1 仅参考。逐类 F1/AP 必须带 test support；support≤2 的类别只能描述，不能据此宣称变体优于另一变体。
- 消融只写入 `eval_results/ablation/<variant>/`，不覆盖 `runs/seed*/`。每个目录保存 `manifest.json`（父实验摘要、唯一变量、命令、代码/数据指纹、seed 列表）、每 seed 的 config/results/diagnosis 和汇总表。运行前后都检查 split、标签文件、`ir_cat.json`、图目录和模型默认参数。
- 主库诊断已显示稀有类的 test support 和池级正样本极低，`pos_weight`、focal/ASL、温度缩放也未稳定救活稀有类。因此 5.4 结论优先解释模块贡献、结构信息和有足够支撑的类别，不把稀有类 F1=0 直接归因于某一个模块。

**B. 5.4.1 必要消融执行矩阵（11 项）**

| 编号 | 变体与唯一变量 | 实现/命令模板 | 重跑范围 | 主要验证问题 |
| --- | --- | --- | --- | --- |
| A1 | 去 DFG_DEP | `--drop-edges 3` | M5；零重跑 M2/M3 | 数据流边是否提供额外图级判别信息 |
| A2 | 去 CFG_FLOW | `--drop-edges 0` | M5；零重跑 M2/M3 | 控制流传播是否是主要有效结构 |
| A3 | 去 AST_PARENT（论文“去 AST”） | `--drop-ast`，即删 relation 1+2 | M5；零重跑 M2/M3 | 语法父子结构是否贡献独立信息；不得只删 relation 1 |
| A4 | 去 CALLBACK_RISK | `--drop-edges 4` | M5；零重跑 M2/M3 | 回调风险边是否减少误报或提升排序质量 |
| A5 | CALLBACK_RISK 上限 4→不限 | 用 `--callback-limit 0` 重建独立图目录，再同步 M1→PyG→M3 | M2–M5；唯一必要重建 | 边截断是必要稀疏化还是损失信息 |
| A6 | 去函数级 CodeBERT | `--cb-channels cb_node` | M5；模型侧零重跑 | 函数级全局语义是否贡献检测能力 |
| A7 | 去节点级 CodeBERT | `--cb-channels cb_func` | M5；模型侧零重跑 | 局部语义窗口是否贡献检测能力 |
| A8 | meanpooling | `--meanpool` | M5；零重跑数据 | $a_v$ 加权 readout 是否优于无权平均池化 |
| A9 | 关闭 $L_{var}$ | `--lambda-var 0` | M5；零重跑数据 | 方差保持项是否防止 $a_v$ 退化；同时比较 `score_std` |
| A10 | 关闭先验 Dropout | `--prior-dropout 0` | M5；零重跑数据 | 模型是否依赖 M1 先验捷径；不与 `--ablate-sv` 混淆 |
| A11 | 结构特征分组 | 分别运行 `--feat-groups base`、`base+sem`、`all` | M5；模型侧零重跑 | 基础结构、漏洞语义、位置/指令组的增量贡献 |

seed0 的窄验证命令模板如下，确认路径和参数后再扩展 seed1/2：

```bash
python scripts/train.py --seed 0 --split-seed 0 --drop-edges 3 --out-dir eval_results/ablation/a1_drop_dfg
python scripts/evaluate.py --seed 0 --runs-dir eval_results/ablation/a1_drop_dfg --split-dir products/alldata/splits
python scripts/evaluate.py --summarize --runs-dir eval_results/ablation/a1_drop_dfg
```

实际批量执行时，每个变体必须显式传 `--split-seed {0,1,2}`，并使用不同的 `--out-dir`；禁止让消融默认写入 `runs/`。A1–A4、A6–A10 只替换对应开关；A11 的三档设置作为同一组实验分别落盘。A5 只有在不限边版本的图产物、边统计、M1/M2 审计和 M3 特征契约全部通过后才允许训练。

**C. 必要消融验收与论文记录**

- 训练前记录父实验摘要、graph/split/label/IR 字典 sha256、变体参数、训练和划分 seed；确认 config diff 只有预期字段。
- 训练中三 seed 均无 NaN/Inf；日志完整记录 `loss_total/loss_cls/loss_var/score_mean/score_std`、best epoch、训练时间、graphs/s、参数量和实际边类型计数。A8/A9 额外比较 `score_std`，验证 meanpool 或关闭 $L_{var}$ 是否伴随可疑度退化。
- 评估后固定 0.5、val threshold、mAP 三列必填，附七类 support、逐类 AP/F1、阈值扫描和 `diagnosis_summary.json`。主种子用于论文案例，三种子汇总用于结论。
- `micro-F1` 方向只有在三种子一致且绝对差至少 1 个百分点时才写作强方向证据；小于 1 个百分点或方向不一致写“与种子波动相当”。这是报告触发规则，不是统计显著性检验。
- 消融表增加“支持度/限制”列。主库 test 中 dos、front_running、time_manipulation 等 support≤2 的结果只能描述，不能用 macro-F1 的变化掩盖 micro-F1 或 mAP 的恶化。

**D. 5.4.2 可选消融执行顺序（资源允许时，6 项）**

1. **L=1/2/3**：先扩展 `SSMHG` 的 `num_layers` 和 checkpoint/config 恢复，再以 L=2 为对照跑三 seed；不能用重复调用两层模型冒充三层传播。
2. **num_bases**：关系数 5 固定时运行 `num_bases=1/2/4/5`，至少保留 4 vs 5；报告参数量、训练时间和 mAP。
3. **hidden=128/256**：只改 `--hid`，检查 readout、分类头维度和 checkpoint 可恢复性，比较容量收益与训练成本。
4. **DropEdge**：运行 `--drop-edge-prob 0.1`（默认 0 作对照），确认先逐图生成 mask 再 batch、验证/测试不丢边，并记录每 epoch 删除比例；不得与 A1–A4 的确定性关系删除混为一谈。
5. **CALLBACK_RISK_REV**：先实现并单测反向边语义和边类型编码，再在独立目录重跑 M2–M5；关系数改变时同步冻结关系映射和配置，未完成前不列为已执行。
6. **微调 CodeBERT**：当前 `_cb.pt` 是冻结输出，不能只改 CLI 参数宣称“微调”。必须实现可训练编码器、显存/时间记录和独立 checkpoint；资源不足则记录“设计保留、未执行”，不补造结果。

**E. 已完成但不替代 5.4 的相关实验**

- `runs/pw_unclamped/`：已完成 `pos_weight` 上限 20→不截断；固定 0.5 micro-F1 约 0.906→0.815，稀有类仍未恢复，主实验继续保留 cap=20。它属于损失敏感性补充，不是 5.4.1 的 11 项之一。（⚠ 旧口径；已按 §28 推翻；且这两条线的 run 仍是**冻结编码器**工作点，只能在冻结工作点上解读，见 `decisions.md` §39.6）
- `runs/loss_focal/`、`runs/loss_asl/`：已完成损失形状补充；验证阈值 micro-F1 与 BCE 差异在种子波动内，ASL 固定 0.5 不稳，BCE 仍为主方案。（⚠ 旧口径；已按 §28 推翻；且这两条线的 run 仍是**冻结编码器**工作点，只能在冻结工作点上解读，见 `decisions.md` §39.6）
- `eval_results/calibration/`：温度缩放改善校准但全局阈值下等价于阈值变化；per-class threshold 只作补充，不能进入主结果。
- `runs/neardup/`、`runs/withbuggy/`、`runs/augmentation/`、`runs/augmentation_dedup/`：分别是零泄漏、含 buggy、增强集和增强集去重对照；它们改变数据范围或划分纪律，不能放进主库 5.4 表，也不能与主库绝对指标合并。

**F. 5.4 交付与完成判定**

- [ ] 建立 `eval_results/ablation/ablation_manifest.json`：11 项必要消融、三 seed 状态、输入指纹、命令和产物路径齐全；未执行项必须写明阻塞原因。
- [ ] 建立 `eval_results/ablation/summary.json`：主实验 + A1–A11 的 `micro-F1@0.5`、`micro-F1@val_thr`、mAP、macro-F1、训练时间和参数量 mean±std；A11 三组单列。
- [ ] 生成论文表：边信息、CodeBERT 双通道、readout/L_var/先验 dropout、结构特征四块分别呈现；每行标注零重跑或 M2–M5 重跑。
- [ ] 生成解释表：A9 的 score_std、A10 的先验依赖、A5 的边数/吞吐、A1–A4 的实际保留边计数和逐类 support。
- [ ] 三种子通过 paired seed 检查；任何变体缺 seed、改 split 或写入正典 `runs/`，均不得进入论文主消融表。

### 12.8.2 消融的「两代记录」与三个正典（2026-09-21 现状）

> 🔴 **本仓现在同时存在三代消融记录，用途不同，谁都不删、谁也不覆盖谁。**
> 引用任何数字前先确认它出自哪一代、哪个正典。

| 代 | 产物 | 报告 | n | 能回答什么 |
| --- | --- | --- | --- | --- |
| **第一代** | `runs/ablation/`、`runs/ablation_aug/` | `experiments/ablation_results.md`、`eval_results/ablation/collected{,_aug}.{json,md}` | **3** | 描述性；**不得**据此判方向（§12.4 第 6 条已列此开口） |
| **第二代** | `runs/ablation_n9/`、`runs/ablation_n9_aug/`、`runs/arch_n9{,_aug}/` | `experiments/ablation_n9_results.md`、`eval_results/ablation/n9_summary.json` | **9** | 同配对判方向（`ts × ss` 3×3；判据 `\|t\| > 2.306`，另给 Bonferroni 参考） |
| **第三代（buggy 正典）** | `runs/ablation_buggy/` | `experiments/per_class_three_caliber_tables_buggy.md` | **3** | 新正典（池 497）上的逐类三口径读数 |

**第一代为什么保留**（2026-09-21 用户裁定「原来的结果不要删」）：第二代的价值有一半在于
**「和第一代比，哪些结论翻了」**——删掉 n=3 就等于删掉对照臂本身。实现上第二代
**对角 3 对直接复用第一代的物理产物**（不重跑），故两份记录之间不存在「两个版本打架」。

**复用合法性不是假设**：`run_ablation_n9.reuse_violations` 逐 run 逐键把旧 `config.json`
与现行代码重建的命令行对拍，3/3 抽查**逐位一致**（仅 `timing.infer_seconds` 不同）。
⇒ 第二代只需补**非对角 6 对**（21 臂 × 2 组 × 6 = 252 run），而非全量 396。

**三个正典不可互换**（`AGENTS.md` 语义锁死项）：

| 正典 | `graph_dir` | `split_dir` | 池 | 用在哪 |
| --- | --- | --- | --- | --- |
| §37 正典 | `products/alldata/graphs_ft/ss{S}` | `products/alldata/splits` | 453 | 主实验 `runs/seed{S}`、第二代消融 |
| 任务2 新正典 | `products/alldata/graphs_ft_buggy/cb_ft_ss{S}` | `products/alldata/splits/withbuggy_snapshot` | 497 | `runs/buggy_canon`、**第三代消融** |
| ② 增强集 | `products/augmentation/graphs_ft/ss{S}` | `products/augmentation/splits` | 1774 | `runs/augmentation`、② 的消融 |

⚠ **注意 `cb_ft_ss{S}` 这个前缀**：它是**新正典专有**的命名，`graph_dir` 的逐种子模板化
必须同时认 `ss{S}` 与 `cb_ft_ss{S}` 两种形态（2026-09-21 修掉的正则漏洞，见手册 §12 错误清单）。

**第三代要补的两件前置**（2026-09-21 已完成）：
1. `products/alldata/graphs_ft_buggy/graph_variants/{cb_rev,cb_unlimited}_ss{S}/` —— 由
   `build_ft_edge_variants.py --dataset alldata --layout buggy` 造（该 layout 为本次新增）。
   边变体源与冻结树**与 §37 正典共用同一份**（边结构与冻结 `_cb.pt` 都与池/划分/微调无关），
   只有微调基座与编码器不同 ⇒ 产物 `variant.json` 与 §37 版**只差 `derived_from` 一个键**（机检过）。
2. `run_ablation.py` 的 train→evaluate 链**补上 diagnose**（原先缺，见下）。

### 12.8.3 `test_probs.pt` 只由 `diagnose.py` 写（2026-09-21 修）

🔴 `evaluate.py` 写 `val_best_probs.pt` 与 `results.json`，**但不写 `test_probs.pt`**；
后者由 `diagnose.py` 写（`scripts/diagnose.py:210`）。而 `collect_three_caliber_tables.py` /
`error_rates.py` / `collect_ablation_results.py` **全都只读 `test_probs.pt`**。

`run_ablation.py` 原先只有 train→evaluate 两步 ⇒ 它跑出的 run **缺 `test_probs.pt`**，
下游不是报错而是**整列变 `—`**（与 `run_buggy_canon.py` docstring 里记录的同一个坑）。
已修：链条改为 train→evaluate→**diagnose**，且 `resume_state(run_dir, require_probs=True)`
会识别"有 `results.json` 但无 `test_probs.pt`"的 run 并**只补那一步**（不重训）。
`require_probs` 默认 `False`，故 `run_study` 那条链的既有判据**逐字未变**。

### 12.9 执行顺序（单步最小验证）
> M5 正式决议（按大纲改II）：主划分用**固定种子 8:1:1 + 覆盖约束校正**（C1 验证+内部测试合计每类 ≥ 该类正样本总数的30%，C2 每划分每类 ≥1；2026-09-12 修订，原“每类 val/内部测试 ≥20”；不再用迭代分层作主方案）；零正类用 class mask 跳过逐元素 BCE；主阈值为验证集选择的全局单值并保存全扫描；L_var 按图使用 population std 并保留梯度；ReduceLROnPlateau 监控 **val micro-F1**（2026-09-12 主指标口径，macro-F1 同步记录作参考）；DropEdge 先单图 mask 再 batch；至少 3 个 seed；记录可比较的训练时间和吞吐；外部泛化只用 DIVE（一次性，不参与模型选择）。

M5 硬性验收：
- [ ] 不凭 `asd_`/`nasd_` 前缀自动合并样本；support、**划分种子**与每类样本数写入 split 报告。
- [x] 划分门槛（C1 合计 ≥30% + C2 每划分每类 ≥1）已由**覆盖约束校正**构造满足（2026-09-12）：三种子达标（去重后替换 18/16/12 个合约；预去重 495 池口径 18/19/17 / eval 合计 44/42/43 见 decisions §12 历史记录；明细见 `coverage_swaps_seed*.txt`）。
- [x] 主划分种子已定：**seed0**（论文主实验固定报告；seed1/2 稳健性复核；用途定位声明见 `experiments/decisions.md` §12）。
- [x] 训练期先验 dropout 按图以 0.2 概率置零已落地于 `model.NodeFuser`（融合前、仅训练期；`sample_dropout_masks` 采样，T1 无泄漏单测把守；不再需要 `_feat_no-prior.pt`，2026-09-12 前端化）。
- [x] `best.pt`、`last.pt`、`config.json`、`log.txt`、`results.json` 均生成，epoch 日志含 `score_mean/score_std`（2026-09-12：train/evaluate 已实现，smoke 验证）。
- [x] 每 epoch 记录 `lr`、`epoch_seconds`，每次运行记录阶段耗时和硬件环境（`config.json::timing` + `environment`，2026-09-12）。
- [ ] DIVE 外部测试结果不参与任何模型选择；报告各类 PR-AUC 与全零子集每类 FPR。
- [ ] 推理输出 4.5.4 五项；SolidiFI 报 $a_v/s_v/g_v$ 与增量覆盖节点。
- [x] CI/smoke 覆盖 split 同 seed 稳定性、dataset batch/dropedge、model backward、train one-step 和 eval threshold；完整 3-seed 训练不放入 PR CI（2026-09-12：`pytest tests/` **64 passed**，含 6 类窄范围测试）。

0. **（改II 优先）M2 CALLBACK_RISK 重做** → `build`×2 → `m1_runner --force` → `convert_pyg` → M3 `_feat.pt` → M4 回归（详见第三节）
1. `m3_build_features.py --only nasd_simple_dao__simple_dao` 验收（8.8）→ 全量（已完成）
2. `model.py` smoke test（9.5）→ **已完成 2026-09-07**（model.py 自带 smoke + tests/test_model_smoke.py 22 用例）→ `dataset.py --check` 单图自检
3. `make_splits.py` 产出全套（固定种子 8:1:1 + **覆盖约束校正**：split_seed*/splits.csv/split_report/coverage_swaps/metadata/unmatched）→ 检查 split_report 的 rule_check（C1+C2）与 unmatched → 构建 DIVE 外部测试子集
4. `train.py --seed 0` 单种子 → 日志字段（含 `score_mean/score_std`）齐全、无 NaN
5. `evaluate.py` 主实验（MVD-HG 内部测试 + DIVE）→ 3 种子 summary → 阶段 5 消融（5.4.1/5.4.2）/基线