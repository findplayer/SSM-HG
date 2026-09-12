# 执行计划：B1 补齐函数级 CodeBERT 通道缺口（2026-09-12）

> 背景：`_hetero.json::functions` 登记不全 → 节点查不到自己的「所属函数」→ 函数级通道取零向量。
> 实测：**func 缺 35195 / 93551 节点 = 37.6%**，**495/581 图**至少一行缺失；node 通道 **0 缺失**。
> 非回归：旧的 `assemble_feat` 用同一句 `.get(..., zeros)`，行为相同，只是此前不可观测。
> 目标：兑现大纲 4.3.2(1)「以当前 CFGNode **所属函数**为单位，提取该函数的完整源码」。
> 时机：M5（train/evaluate）尚未实现 → **本次修复不使任何实验结论作废**（M5 之后再修即成倍返工）。

## 0. 口径裁定（先定，后动代码）

| 议题 | 选项 | 推荐 | 理由 |
| --- | --- | --- | --- |
| 修饰符（`modifier onlyOwner`）体内节点 | A 并入（按 modifier 完整源码编码）／B 排除（保持零向量） | **A** | Slither 的 `node.function` 对修饰符体返回该 modifier 对象；大纲说「所属函数」，修饰符体就是节点所在作用域；排除等于人为保留新缺口 |
| 构造函数 / fallback / receive | 维持现状 | — | 实测已在 `functions` 表内（`*::constructor`、`*::fallback`） |
| 仅收「同文件内定义」还是也含 import 展开 | 先统计，再定 | 待 S0 结果 | 需知道「源码内无定义」的比例；若 >0 且无法编码，需单独裁定 |

**停止条件**：若 S1 发现漏收是**方法学有意为之**（例如「只编码大纲指定的函数子集」），立即停止并回退到 A 方案报你裁定。

## 1. 步骤（每步有验收，不通过不进下一步）

### S0 缺口清单（可审计产物）✅ 已完成
- 脚本 `scripts/audit_cb_func_gap.py`（新增）→ `products/alldata/splits/cb_func_gap.json` + `docs/cb_func_gap.md`。
- **实测**：缺口 **35195 行（37.6% 节点）/ 495 图 / 5679 去重键**；分类：

| 类别 | 键 | 节点行 | 含义 | 处置 |
| --- | --- | --- | --- | --- |
| `alias` | 4351 | 27290 (77.6%) | 继承函数在 Slither 归到派生合约，AST 表按定义处记 | 补登记（同名 span） |
| `modifier` | 778 | 5283 (15.0%) | `modifier X` 体节点；AST walk 只收 `FunctionDefinition` | 补收集（ModifierDefinition） |
| `function` | 73 | 260 (0.7%) | 同名定义存在但表里无同名条目 | 人工核查（补登记后仍 unmatched 则报） |
| `none` | 477 | 2362 (6.7%) | **全部是 `slitherConstructorVariable/Constant`**（Slither 合成作用域，源码中无函数体） | **不可编码**：保留零向量 + 文档声明（非缺陷） |

> 事后归因（S8/S9）：`function` 类 73 键 = **69 键（240 行）老式继承构造函数（S8 已修）** + **4 键（20 行）三图 AST 格式未解析（S9 已修）**；
> `none` 类 2362 行含 S9 三图的 **6 行**（严格说属解析缺口，已由 S9 修复）——S9 后残余 **2356 行全为 `slitherConstructor*`**。

- **停止条件裁定**：`none` 类经核查不是「源码内也找不到定义」的解析缺陷，而是 Slither 合成作用域
  （部署期状态变量初始化），**可解释、不可编码** → 停止条件**解除**，继续 B1。

### S1 定位 M2 收集口径 ✅ 已完成
- 节点键来自 **Slither cfgdetail**（`f["contract"]`, `normalize_function_name(f["function"], ...)`）；
  函数表来自 **AST walk**（`walk_ast` 里 `if node_type == "FunctionDefinition"`，**不收 `ModifierDefinition`**）。
- 两个成因：① 继承函数归属合约不同（`InvictusWhitelist._transferOwnership` vs `Ownable._transferOwnership`）；
  ② modifier 体节点在表里完全不存在。

### S2 小样验证 + 重编码耗时实测 ✅ 已完成
- 单图 `--force` 重建 `_cb.pt`（156 节点 + 24 函数）：**7.9 s** → 全量 581 图外推 ≈ **70 min**（>1 h）。
- **结论：不做全量强制重建**，改用下面的增量补丁（只编码新增函数键）。

### S3 改 M2（最小改动）✅ 已完成（小样验收通过）
- 在 `functions_out` 生成前增加**函数表补登记**（仅当有 cfgdetail）：
  同名条目→补 `(派生合约, 函数名)`（alias）；否则用 AST 里的 `ModifierDefinition` 的 src span 补 `kind=modifier`；
  仍无→计入 `meta.functions_unmatched*`（不静默）。
- **小样实测**（`asd_0x0000000f…`）：`functions` 24 → **53**（alias 26 + modifier 3，unmatched 0）；
  **`nodes`/`edges` 逐字段不变**（✓）；**该图缺口 80 行 → 0**。
- 过程中发现：补登记会顺带填 `function_visibility`/`function_mutability`，本次用**补登记前快照**隔离
  （`fn_meta_table`），保证只有函数表变化。该发现另记（可选后续议题：是否也补全这两个节点元信息）。
- 另：新增 `--only <base>` 便于小样回归。

### S4 全量重跑 M2
- `build`（581 图）→ 复核五类边数与节点数与旧值一致（71296/1957/6035/146679/509；93551 节点）→ `convert_pyg`。
- **验收**：`_pyg.pt` 与 `_m1.json` 未变（哈希对比抽样）；`functions` 表覆盖提升。
- 备份：重跑前把 `_hetero.json` 复制到 `products/alldata/graphs/_hetero_backup_pre_gapfix/`。

### S4 全量重跑 M2 ✅ 已完成（58 s）
- 备份：`products/alldata/graphs/_hetero_backup_pre_gapfix/`（581 个，59 MB）。
- 全量 build（581 图，**58 s**）→ 全库对比备份：**`functions` 14741 → 23139（+8398 = alias 7705 + modifier 693）；
  `nodes` 不一致 0 图、`edges` 不一致 0 图、`meta` 旧键不一致 0 图**。
- **两次隔离修复（重要）**：补登记会顺带把 `function_visibility`/`function_mutability` 填上，而
  ① 节点元信息字段、② `build_callback_risk_edges()` 的 CALLBACK_RISK 边判定 都读它 → 首轮重跑出现
  **18 图 edges 变化**（会动 CALLBACK_RISK 509 边/85 图这个已冻结口径）。
  已统一改为读**补登记前的快照** `fn_meta_table`：只有 `functions` 表变，nodes/edges/CALLBACK_RISK 全冻结。
- 缺口：**35195 → 2622 行**（-92.5%）；残留 = `none`（Slither 合成作用域 2362）+ `function` 类（260，待下轮查）。
- `_pyg.pt` **无需重转**：`convert_hetero_json_to_pyg.py` 不读 `functions`，且 nodes/edges/meta 旧键逐字段未变
  （构造性结论）。

### S5 重建 `_cb.pt` + M3 全量 ✅ 已执行（两种路径都做了，最终口径 = 全量重建）
- **路径 A（增量补丁，先跑）**：`--cb-patch`（保留已有向量，只补缺失键）→ **7m25s**，`func +8398`、
  `node +0`、重写 397/581 图；随后全量 M3 写回 581 个 `_feat.pt`。
- **路径 B（全量强制重建，最终采用）**：用户裁定改用 `--force` 全量重建（消除“补丁 vs 重建”的一切疑问）。
  运行中，日志 `/tmp/m3_full_rebuild.log`；预估 ≈76 min（单图实测 7.9 s × 581）。
- **全库逐位等价比对（重建后执行）**：补丁版 581 图的三项指纹已存 `/tmp/feat_hashes_postpatch.json`
  （`combined_sha256` / `cb_func` / `cb_node`）；重建完成后逐图对比，**应全部相等**（证明两条路径等价、
  CodeBERT CPU 前向逐位可复现）；不等则逐通道定位。「补丁模式」保留为工具（以后再有同类缺口可省 10× 时间），
  但本次正典产物来自全量重建。
- 注意：重建期间**不读产物做校验**（项目铁律：脚本逐个重写，中途读取会得到“缺失/归零”假象）。
- 新增 `--cb-patch` 模式（M3）：保留现有 `_cb.pt` 的 `func`/`node` 向量不变，**只对新增的
  函数键**（补登记后新增的约 5202 个）按同一文本口径（函数源码、512 token）补编码并合并写回；
  预估 ≈ **3–4 min**（对比全量强制重建 ≈ 70 min）。
- **等价性校验（必做）**：抽样 3 图——「补丁版 `_cb.pt`」与「`--force` 全量重建」的**所有向量逐位一致**；
  不一致则改用全量重建。
- 之后全量 M3（41 s）→ `_feat.pt` 刷新。
- **验收**：`func` 缺行全库 = 0；`dataset.py --check --verify-channel-hash` 通过。

### S6 验收与回归
- 全库 581 图 `load_graph` 断言通过（T4）；
- **T2 口径调整（必须）**：归档 legacy 与新 `_feat.pt` 在「本次修复影响到的图」上不再可比 → 改为
  ① 在**未受影响**图上仍逐位比对；② 修复后产物另归档 `legacy_feat_pre_gapfix/`（可选）；
- `pytest tests/` 全绿（含 T1/T5；T2 按上条调整）；
- **数据口径变更声明**：本次改变了 `_feat.pt` 数值，必须在 `decisions` 记一条并在手册说明「M5 之前的最后一次特征口径变更」。

### S7 文档同步
- 手册 §7.x（functions 收集口径）、§8.x（通道覆盖率）、§12（错误清单新增一条「函数级通道缺口」）；
- `docs/data_funnel.md`（审计脚本新增缺口章节，重跑生成）；`experiments/decisions.md` 新增 §15；
- `Todo_List.md`、`项目组织架构.md`、`docs/M3_frontend_design.md`（§5 结果）。

### S8 **第二轮：R2（老式继承构造函数）闭合 ✅ 已完成（2026-09-12）**
- 触发：`docs/residual_gaps.md` §R2 的只读 4 步排查（不改代码）→ 定论键形态：
  `(派生合约, 基合约名)` vs 表内 `(基合约, "constructor")`。
- **上一轮“空转”的根因（小样复现）**：旧写法 `dict(entry, contract=key[0])` **只改了 `contract`、未改 `function`**
  → 条目落在 `(派生合约, "constructor")` 错键上（既救不了请求键，又与既有条目重键）。小样：旧写法 +2 键（应为 +7）。
- 修正：`fn_table[key] = dict(fn_table[(N, "constructor")], contract=key[0], function=name)`；命中计数 `meta.functions_reconciled_legacy_ctor`。
- **验收**：`functions` 23139 → 23241；缺口 2622 → **2382 行**/382 图；nodes/edges/meta 旧键 581 图**零差异**；
  `--cb-patch` +102 func / 53 图 / **1 m 08 s**；全库断言 + `pytest` 39 passed；**`functions` 键唯一性全库检查通过**。
- **将“第二类残留”拆开**：残留 `function` 类 73 键中 69 键（240 行）属本轮修复；剩下 **4 键/20 行**属 R5（三图 AST 格式）。
- **残留 class 归因修正**：`audit_cb_func_gap.py::classify` 新增 `legacy_ctor` 类（名字是本文件声明的合约名）；
  无 `--tag` 重跑需 `--force`，防止覆写历史基线（旧基线由旧版 classify 生成，该类键当时归入 `function`）。
- 详见 `experiments/decisions.md` §15.6；连带效应（240 行结构通道可见性 4 列 0→one-hot）已在 §15.6 声明。

### S9 **第三轮：R5（三图 solc 0.8 风格 AST）兼容 ✅ 已完成（2026-09-12，用户裁定 A）**
- 修法：新增 `normalize_ast()`（`load_ast` 读入时归一化新式节点：属性收入 `attributes`、子节点取 `nodes`、类型写 `name`）；
  **老式节点原样返回同一对象** → 578 图解析路径零变化。另修 `walk_ast` 分支顺序（新式 `name=""`+`kind="constructor"` 曾被误判为 `fallback`）。
- 单测 `tests/test_ast_normalize.py`（4 用例）：老式恒等返回、新式归一后表完整、构造函数不落 fallback、`load_ast` 端到端。
- **验收**：**仅 3 图**变化（578 图逐图指纹零差异）；`functions` 0→5/7/7、`state_vars` 空→2/2/3、DFG_DEP **+33**、CALLBACK_RISK 0→2（一图）、**26 节点**可见性/可变性填实；库级刷新（边 226476→**226511**、M1 raw hits 21567→**21571**）；
  缺口 2382 → **2356 行（2.52%）**（全为 `slitherConstructor*`），覆盖率 **97.48%**；`pytest` **43 passed**。

## 2. 执行结果（2026-09-12 完成）

| 步骤 | 结果 |
| --- | --- |
| S0 缺口清单 | 35195 行 / 37.6% / 495 图 / 5679 键（alias 4351·27290、modifier 778·5283、function 73·260、none 477·2362） |
| S1 成因 | Slither 归属合约 vs AST 定义处；`walk_ast` 不收 `ModifierDefinition` |
| S2 耗时实测 | 单图 `--force` 7.9 s → 全量外推 ≈70 min（实测全量约 55 min） |
| S3 M2 补登记 | 小样：24 → 53 条；nodes/edges 逐字段不变 |
| S4 全量 M2 | 58 s；`functions` 14741 → 23139；**两轮**才干净（首轮 18 图 edges 变化 → `fn_meta_table` 隔离） |
| S5 重建 `_cb.pt` | 先增量补丁（7m25s）+ 后全量 `--force`（≈55 min）；**两者全库逐位等价** |
| S6 验收 | 缺口 2622 行（2.8%）；全库断言含 cb 双通道哈希通过；`pytest` 39 passed |
| 回退 | 空转的「老式构造函数」规则已回退，回退经全库指纹逐位验证一致 |
| **S8 第二轮（R2 闭合）** | 缺口 2622 → **2382 行（2.55%）**/382 图；`functions` 23139 → 23241；**根因＝旧写法未同步改写 `function` 字段**（已复现）；`--cb-patch` 1 m 08 s；`pytest` 39 passed |
| 连带效应 | **口径更正**：M3 可见性特征有 `fn_table` 回退（`m3_build_features.py:617`）→ 补登记**同时**让 27290 节点（alias 类）的**结构通道可见性 4 列**从全 0 变为真实值（修正性变化，已声明）；S8 再让 240 节点同样变化 |
| **S9 第三轮（R5 闭合）** | 缺口 2382 → **2356 行（2.52%）**/382 图（全为 `slitherConstructor*`）；**仅 3 图**变化；库级刷新（边 226511、DFG 146712、CALLBACK_RISK 511/86、M1 21571）；`pytest` **43 passed** |
| 待办入口 | `docs/residual_gaps.md`（R1/R3/R4 保持现状；R2/R5 均已闭合；附：AST 映射丢弃率 97.2% 为披露项） |

## 3. 回滚与失败判据

- **回滚**：`_hetero.json` 与 `_cb.pt` 均有就地重写风险 → 重跑前备份 `_hetero.json` 全量；`_cb.pt`
  至少备份 1 张（用于对照），其余靠 `--force` 重建。
- **失败判据（任一成立即停下报裁）**：
  1. S0 出现大量「源码内也找不到定义」的缺失键；
  2. S1 发现漏收属方法学有意；
  3. S2 重编码耗时外推 > 3 h（实测 ≈ 70 min → 未触发，但仍改用增量补丁以省时）；
  4. S3 发现补收会牵动 nodes/edges（`_pyg.pt` 变化）→ 升级为 M2 语义变更，须重新裁定。
