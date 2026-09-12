# 残留缺口清单（M5 之前逐项推进，按本清单裁定）

> 来源：`experiments/decisions.md` §15（§15.6 = R2 闭合，§15.7 = R5 闭合，§15.8 = AST 映射披露）。
> 数据：`products/alldata/splits/cb_func_gap.json`（修复前基线）与 `cb_func_gap_after.json`（现行快照），
> 生成脚本 `scripts/audit_cb_func_gap.py`（无 `--tag` 重跑需 `--force`，防止覆写历史基线）。
> **本文件是待办与裁定入口，本身不改任何产物。**
> 现状（2026-09-12 第三轮后，**三处缺口均已闭合，详见下表**）：函数级通道缺口
> **35195 行（37.6%）→ 2356 行（2.52%）**，涉及图 495 → **382**；覆盖率 **97.48%**；
> 残余 **全部是 `slitherConstructor*`**（Slither 合成作用域，不可编码）。

| 项 | 状态 |
| --- | --- |
| R1 `slitherConstructor*`（Slither 合成作用域） | **保持现状 + 披露**（不可编码，无可行修法） |
| R2 老式继承构造函数（69 键/240 行） | **已闭合**（第二轮，§15.6） |
| R3 节点可见性/可变性元信息 | **已被三轮修复连带解决**（取数路径说明即可） |
| R4 `--cb-patch` 不删多余键 | 工具增强，无口径影响 |
| R5 三图 AST 格式未解析（31 节点） | **已闭合**（第三轮，§15.7，用户裁定 A） |
| 附：AST 映射丢弃率 97.2% / 18 图无 AST 边 | **披露项**（§15.8，不改实现） |

## 口径更正（2026-09-12，重要；两轮修复各一次）

先前记录「补登记只动函数级通道」**不完整**，实测应更正为：

- M3 的可见性特征在 `m3_build_features.py:617` 有**表回退**：
  `visibility = node.get("function_visibility") or (fn.get("visibility") if fn else None)`；
- 因此**第一轮**（alias/modifier 补登记）**同时改变了结构通道的可见性 4 列**：
  **27290 个节点（alias 类）从全 0 变为真实可见性**；修饰符类 5283 个节点仍为全 0——**语义正确**
  （Solidity 修饰符本就无 visibility）；**第二轮**（老式继承构造函数别名，§15.6）再让
  **240 个节点**（53 图）的可见性 4 列从全 0 变为 one-hot（`public` 239 / `internal` 1）；
  **第三轮**（R5，§15.7）再让 3 图的 **26 个节点**同样填实；
- 累计：**27556 个节点**（27290 + 240 + 26）经 M3 取数回退获得真实可见性；仍为全 0 的 **7639 个**
  = 修饰符体 5283（语义正确）+ `slitherConstructor*` 2356（无源码可编码）；
- `function_visibility`/`function_mutability` **节点字段本身从未被改写**（`fn_meta_table` 已隔离）——
  唯一的例外是 R5 的 3 图（原本就是 `None`，归一化后由 AST 表正常填实），变化仍只经由取数链发生；
- 结论：三轮连带效应都是**修正性的**（只增不改、可解释），但必须在论文/decisions 中声明为**结构通道变化**。

## R1 `slitherConstructor*` 类：Slither 合成作用域（**保持现状 + 披露**）

- **现象/证据**：这类缺失键全部是 `slitherConstructorVariable` / `slitherConstructorConstant`；抽查 8 键在源文件中
  既无 `function X(` 也无 `modifier X`（且所在文件无 `import`）→ 是 Slither 为部署期状态变量初始化造的**合成作用域**。
- **残量（第三轮后）**：**2356 行 / 475 键 / 382 图**（占节点 **2.52%**）——即三轮修复后剩下的**全部**缺口。
- **影响面**：这些节点的函数级通道恒为零向量；**无法通过补登记消除**（源码里没有对应函数体）。
- **候选处置**：A 保留零向量 + 论文披露（**推荐**）；B 用节点窗口向量兜底（**不推荐**：人为制造两个 CodeBERT 通道的
  相关性，污染 `no-cb-func` / `no-cb-node` 消融结论）。
- **成本**：A = 0；B = 一次全量重建。
- **建议**：A；论文「特征构建」处报告「函数级通道覆盖率 **97.48%**，残余 2.52% 全为 Slither 合成作用域（不可编码）」。

## R2 老式继承构造函数（69 键 / 240 行）——**已闭合（2026-09-12，第二轮）**

- **定论（实测三例）**：0.4.x `function Ownable() public {}` 被派生合约继承时，**Slither 用基合约名当函数名**
  → 节点键 = `(派生合约, 基合约名)`；`walk_ast` 见 `raw_name == 所在合约名` → 表内键 = `(基合约, "constructor")`，
  两者不同名 → 规则①（同名 alias）抓不到。证据：`MintableToken.Ownable` 节点行 378–380 正是
  `contract Ownable`（370 行）内的 `function Ownable() {`（378 行）；`MyAdvancedToken.token` → `contract token` 的
  `function token(...)`；`SaleClockAuction.ClockAuction` → `contract ClockAuction` 的 `function ClockAuction(...)`。
- **上一轮“空转”的根因（已复现）**：旧写法只改 `contract` 未改 `function` 字段 → 条目落在 `(派生合约, "constructor")`
  这个**错的键**上（既救不了请求键，又与既有条目重键）。小样复现：旧写法只 +2 键（应为 +7）；补 `function=name` 后 +7 键。
- **现行规则**：请求名 N 是本文件**声明的合约名** 且 `(N,"constructor")` 在表且 `kind=="constructor"` → 别名（span 取基合约构造）。
- **结果**：`functions` 23139 → 23241；缺口 2622 → **2382 行**；图 404 → 382；nodes/edges/meta 旧键 581 图零差异；
  `_cb.pt` 走 `--cb-patch`（+102 func / 53 图 / 1 m 08 s）；全库断言 + `pytest` 39 passed。
- 明细见 `experiments/decisions.md` §15.6。

## R3 可见性/可变性元信息缺口（**已被三轮修复连带解决**）

- **实测**：93551 节点中 35195（37.6%）的 `function_visibility` / `function_mutability` 字段**仍为 None**（节点字段层面），
  但其中 **27556**（27290 alias + 240 老式构造函数 + 26 R5 三图）已在 M3 侧经 `fn_table` 回退获得真实可见性；
  剩余 **7639** = 5283（修饰符体，语义正确）+ 2356（`slitherConstructor*`，无源码）仍为全 0。
- **影响面**：`--feat-groups base` 的前 4 列（可见性 one-hot）在「修饰符体 + 残留」节点上为 0——**这是可解释的**，不再是缺陷。
- **候选处置**：A 保持现状 + 在论文/手册说明（**推荐**）；B 再去改节点字段 `function_visibility`
  （**不建议**：会把同一语义值复制到两处，增加漂移面；且节点字段属 M2 输出，改动会再次触发 `_pyg.pt` 一致性论证）。
- **成本**：A = 0。
- **建议**：A；在手册 §8.5（结构特征）与 decisions §15 写明取数路径（节点字段 → `fn_table` 回退）。

## R4（旁支）`_cb.pt` 可能残留历史键

- **现状**：2026-09-12 首轮已手工清理 47 条孤儿键（空转规则产物）；`--cb-patch` **不删除**多余键，`--force` 重建天然干净。
  第二轮 `--cb-patch` 已加“输出无重复键”的全库校验（见 §15.6 验收表）。
- **建议**：若再出现「表变了但 cb 未重建」，要么 `--force`，要么给 `--cb-patch` 加一个「同时删除不在表内的键」开关
  （当前无此开关）。属工具增强，无口径影响。

## R5 三图 AST 格式未解析（31 节点）——**已闭合（2026-09-12，第三轮，裁定 A）**

- **问题**：581 图中 **3 图**（`asd_0x603fc324…`、`nasd_0x603fc324…`、`nasd_0x980358…`，节点 9/13/9，共 **31 节点**）
  的 `AST-raw/*.json` 是 **solc 0.8 风格**（子节点键为 `nodes`、属性在节点顶层），而 `walk_ast` 只读
  `children` / `attributes` → **functions 表为空**（31 行函数级通道全零），`state_vars` 为空（连带 DFG 状态变量
  判定与 CALLBACK_RISK 判定失真）。
- **修法**：新增 `normalize_ast()` 在 `load_ast()` 读入时归一化新式节点；**老式节点原样返回同一对象**
  → 既有 578 图解析路径不经新分支。另修 `walk_ast` 分支顺序（新式显式构造函数 `name=""` + `kind="constructor"`
  曾被误判为 `fallback`）。单测 `tests/test_ast_normalize.py`（4 用例）固定这两条保证。
- **验收（全库 581 图逐图指纹）**：**仅 3 图**变化（其余 578 图 nodes/edges/meta/functions 零差异）；
  3 图变化内容＝`functions` 0→5/7/7、`state_vars` 空→2/2/3、DFG_DEP +33（8→23 / 1→10 / 1→10）、
  CALLBACK_RISK 0→2（一图）、**26 个节点**的可见性/可变性字段由 None 填实；
  `AST_PARENT`/`AST_PARENT_SAME` 仍为 0（AST 父子边全落不到 CFGNode 对，与另 15 图同因，见附注）。
- **库级口径变化**：边总数 226476 → **226511**；DFG_DEP → **146712**/569；CALLBACK_RISK → **511/86**；节点数 93551 不变；
  M1 `total_raw_hits` 21567 → **21571**；缺口 2382 → **2356 行**；`functions` 23241 → **23260**。
- **下游重跑**：M1 全量（仅 3 图变）→ PyG（仅 3 图变，3.5 s）→ M3 `--cb-patch`（func +19 / 重写 3 图）→
  全库断言通过；`pytest` **43 passed**（新增 4 用例）。刷新 `docs/data_funnel.md`（自动含新结构统计）。
- **影响面**：3 图**均不在池 448 / 划分内** → **不影响 M5 训练/评估**。明细见 `experiments/decisions.md` §15.7。
- **流程教训（必须遵守）**：① M1 全量刷新要用**相对参数** `--in-dir products/alldata/graphs --out-dir products/alldata/graphs`，
  否则 `meta.graph_path` 由相对变绝对、全库 581 个 `_m1.json` 字节全变（数值不变）；② 局部 `--pattern` 运行会**覆写**
  库级 `batch_summary.json`，之后必须补一次全量；③ `_feat.pt` 含 `meta.created_utc`，每次 M3 运行都改写全部 581 个
  文件字节——“只有少数图变”必须看 `meta.channel_sha256`/`combined_sha256` 或 `_hetero.json` 指纹，不看文件 sha256。

## 附注：AST 关系的映射丢弃率（披露项，见 decisions §15.8）

- AST 父子边 281803 条中只有 **7992 条**（AST_PARENT 1957 + AST_PARENT_SAME 6035 = 全部边的 3.53%）能映射成
  CFG 节点对，**273811 条（97.2%）因端点未映射到 CFGNode 被丢弃**；**18 图**（含 R5 三图）AST 边为 0（其中 11 图在池内）。
- **处置：不改实现**（改映射规则会再次改变库级统计与 `_pyg.pt`，收益不明），但论文数据描述/局限处**如实披露**，
  并据此调整「四类边」的贡献叙述；数字由 `scripts/audit_data_funnel.py` 自动生成（`docs/data_funnel.md` §4）。

## 执行顺序建议

1. **R1 / R3 / R4 + 附注**：保持现状，按上表写入论文局限（R3 说明并入「结构特征取数路径」）；
2. 之后进入正式主实验 **M5**（`metrics.py` → `train.py` → `evaluate.py`）；
3. 若 M5 之后仍需改特征数值，必须重跑全链并刷新 `decisions` §15 与 `docs/data_funnel.md`。

## 数据出处（可复核）

| 用途 | 文件 / 命令 |
| --- | --- |
| 修复前 / 现行缺口清单 | `products/alldata/splits/cb_func_gap.json`、`cb_func_gap_after.json`；`python scripts/audit_cb_func_gap.py --tag _after --force` |
| 第一轮前 `_hetero.json` 备份 | `products/alldata/graphs/_hetero_backup_pre_gapfix/`（581 个） |
| 第二 / 第三轮前逐图指纹 | 固化脚本 `python scripts/audit_graph_fingerprint.py --out <路径>` / `--compare <基线>`；基线留档 `/tmp/hetero_pre_ruleA.json`（R2 前）、`/tmp/hetero_post_ruleA.json`（R5 前） |
| 修复前「MLP 后 128 维」特征归档 | `products/alldata/graphs/legacy_feat_pre_frontend/`（583 个，T2 用） |
| 可见性取数路径 | `scripts/m3_build_features.py:617` |
| 补登记实现（①alias ②modifier ③legacy_ctor）与双重隔离 | `scripts/build_cfg_centered_hetero_graph.py`（`fn_meta_table`、`build_callback_risk_edges` 调用点） |
| 两种 AST 风格归一化 | 同文件的 `normalize_ast()` / `load_ast()`；单测 `tests/test_ast_normalize.py`（4 用例） |
| 等价性证据 | 全量 `--force` 重建 vs `--cb-patch`：581 图 `combined_sha256`/`cb_func`/`cb_node` 逐位相等（第一轮，仍适用） |
| 库级结构统计（自动刷新） | `python scripts/audit_data_funnel.py` → `docs/data_funnel.md` §4 + `products/alldata/splits/data_funnel.json` |
| R5 只读探针（已实施，留档） | `/tmp/probe_classB.py`（新式 AST 归一化后的 3 图结构规模，未写任何产物） |


