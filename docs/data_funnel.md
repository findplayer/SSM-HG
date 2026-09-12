# 数据口径追溯（由 `scripts/audit_data_funnel.py` 生成，勿手改）

> 生成时间（UTC）：2026-09-12T11:41:48+00:00；运行方式：`python scripts/audit_data_funnel.py`
> 论文里出现的每个样本/标签数字都应能在下表中找到出处；下表未列出的数字不得写进论文。

## 0. 一句话口径

- 上游 `MVD-HG-dataset`（只读参考）：7 个类别文件夹共 **846** 条 `.sol` 记录（跨类别重复收录），去重后唯一（目录,文件）**591** 个。
- 主库 `alldata(readonly)`：**591** 个 `.sol`；标签文件 **2002** 条（合约定义级），其中正样本 257 条、多标签 123 条。
- 图与划分：**581** 图 → 剔除 86 个 `buggy_*` → 池 **495** → 两级去重（sha1 丢 46、地址丢 1）→ **448** → 358/45/45；池内正样本 125、全零 323、多标签 **1**。

## 1. `846 → 591` 的 255 个去向（逐条拆解）

- 846 = 七个 `<类>_contract/sol_source` 目录里 `.sol` 记录的**合计**；
- 591 = 唯一（项目目录, 文件名）对，即主库实际保留的源码文件数；
- **差额 255 = 「同一 (项目目录, 文件名) 被多个类别文件夹重复收录」的重复计数之和**：

| 同一文件被 k 个类别文件夹收录 | 文件数 | 贡献的重复计数 (k-1)×文件数 |
| --- | --- | --- |
| k=1 | 456 | 0 |
| k=2 | 55 | 55 |
| k=3 | 40 | 80 |
| k=4 | 40 | 120 |
| **合计** | **591** | **255** |

- 校验：255 == 846 - 591 = 255，**无其它去向**（不是文件丢失，类别信息已合并进多热标签）。
- 另注：跨类别副本内容不一致的同名文件组 **85** 组，全部位于 `buggy_*` 项目；非 buggy 副本内容完全一致。

## 2. 逐级数字与出处

| 阶段 | 口径 | 数值 | 出处（产物/命令） | 备注 |
| --- | --- | --- | --- | --- |
| 上游 MVD-HG-dataset | 类别文件夹 .sol 记录数（含跨类别重复） | 846 | MVD-HG-dataset/*_contract/sol_source/**/*.sol<br>`find MVD-HG-dataset/*_contract/sol_source -name "*.sol" | wc -l` | 逐类：{'access_control_contract': 114, 'arithmetic_contract': 120, 'dos_contract': 92, 'front_running_contract': 88, 'reentrancy_contract': 142, 'time_manipulation_contract': 100, 'uncheck_contract': 190}；注：上游仓库不作数据集用（只读参考） |
| 上游 MVD-HG-dataset | 唯一（项目目录, 文件名）对 | 591 | MVD-HG-dataset/*_contract/sol_source/*/*.sol | 846 去掉跨类别重复收录后的文件数 |
| 上游 MVD-HG-dataset | 差额：跨类别重复收录次数 | 255 | 同上一行 | 846 - 591 = 255；这是**计数重复**，不是文件丢失 |
| 上游 MVD-HG-dataset | 唯一项目目录数 / 唯一地址数 | `{"dirs": 591, "addresses": 499, "dual_prefix_dirs": 92}` | MVD-HG-dataset/*_contract/sol_source/<项目目录> | 目录名前缀分布：{'asd': 404, 'nasd': 442}；差额 = 同一地址同时存在 asd_/nasd_ 两份目录 |
| 上游 MVD-HG-dataset | 唯一源码内容 sha1 数 | 743 | 对 846 份副本逐一 sha1 | 内容不一致的同名副本组数 85（全部位于 buggy_* 项目：85）；非 buggy 副本内容完全一致 |
| 上游 MVD-HG-dataset | 同一文件被 k 个类别文件夹收录的分布 | `{"1": 456, "2": 55, "3": 40, "4": 40}` | MVD-HG-dataset/*_contract/sol_source | Σ(k-1)×count = 255，即差额 255 的全部构成（无其它去向） |
| 主库 alldata | 源码文件数 | 591 | alldata(readonly)/alldata_sol_source/*/*.sol<br>`find "alldata(readonly)/alldata_sol_source" -name "*.sol" | wc -l` | = 上游唯一（项目目录, 文件名）对；目录数 591（含 asd_/nasd_ 双前缀副本） |
| 主库 alldata | 标签条目数（合约定义级） | 2002 | alldata(readonly)/contract_labels.json | 一个 .sol 内的多个合约定义各占一条（这正是 2002 的来源） |
| 主库 alldata | 标签条目中正样本条数（≥1 类） | 257 | alldata(readonly)/contract_labels.json |  |
| 主库 alldata | 标签条目中多标签条数（≥2 类） | 123 | alldata(readonly)/contract_labels.json | 大纲 5.1 写的 681 与本数字不符，论文以大数字为准（口径须改写） |
| 主库 alldata | 逐类正样本条目数 | `{"access_control": 123, "arithmetic": 138, "dos": 112, "front_running": 110, "reentrancy": 137, "time_manipulation": 128, "uncheck": 179}` | alldata(readonly)/contract_labels.json | 与 MVD-HG-dataset/<类>_contract/contract_labels.json 逐类 diff=0（脚本内校验） |
| 主库 alldata | 主标签文件 vs 七类单类文件 差异条目数 | 0 | alldata(readonly)/contract_labels.json ↔ MVD-HG-dataset/*_contract/contract_labels.json | 0 = 主标签文件是七类单类文件的并集，自洽 |
| 主库→图 | 源码文件数（上一阶段） | 591 | products/alldata/raw/filter_report.txt<br>`bash scripts/generate_all_ast_cfg_dfg.sh` |  |
| 主库→图 | 过滤：assembly>50 行 | 1 | products/alldata/raw/filter_report.txt |  |
| 主库→图 | 过滤：delegatecall 动态绑定 | 9 | products/alldata/raw/filter_report.txt |  |
| 主库→图 | 解析失败（AST/CFG/DFG/cfgdetail） | `{"ast_failed": 0, "cfg_failed": 0, "dfg_failed": 0, "cfgdetail_failed": 0}` | products/alldata/raw/filter_report.txt | 591 - 1(assembly) - 9(delegatecall) = 581 = 已生成图数，无解析失败 |
| 图 | 已生成异构图数 | 581 | products/alldata/graphs/*_pyg.pt（经 scripts/dataset.py::build_index）<br>`python scripts/dataset.py --check <base>` |  |
| 图→划分 | 标签匹配失败（未进入划分）图数 | 0 | products/alldata/splits/unmatched_contracts.txt<br>`python scripts/make_splits.py` |  |
| 图→划分 | 剔除 buggy_* 注入噪声项目图数 | 86 | products/alldata/splits/split_report.json | 581 - 86 = 495；该剔除为实验室决策（大纲 5.1 未列），须在论文说明 |
| 图→划分 | 池去重 level-1：源码内容 sha1 相同（同一份源码的副本） | `{"dropped": 46, "groups": 46}` | products/alldata/splits/split_report.json::dedup<br>`python scripts/make_splits.py` | 495 - 46 = 449 |
| 图→划分 | 池去重 level-2：项目标识/地址相同（同合约的另一份源码，字节可能不同） | `{"dropped": 1, "groups": 1}` | products/alldata/splits/split_report.json::dedup | 449 - 1 = 448；该组即全库唯一多标签样本（0x627fa62c…：1847 vs 1842 字节），sha1 抓不到，seed0 下曾被拆到 train/val——去重的实质收益在此 |
| 图→划分 | 划分池样本数 | 448 | products/alldata/splits/split_seed{0,1,2}.json | 样本单位 = 源文件（唯一标识 = 源码哈希 → 项目标识），非合约定义级 |
| 图→划分 | seed0 划分规模 | `{"train": 358, "val": 45, "test": 45}` | products/alldata/splits/split_seed0.json<br>`python scripts/make_splits.py` | 覆盖校正替换 18 个（下限修正 1）；C1+C2 7/7 类达标 |
| 图→划分 | seed1 划分规模 | `{"train": 358, "val": 45, "test": 45}` | products/alldata/splits/split_seed1.json<br>`python scripts/make_splits.py` | 覆盖校正替换 16 个（下限修正 0）；C1+C2 7/7 类达标 |
| 图→划分 | seed2 划分规模 | `{"train": 358, "val": 45, "test": 45}` | products/alldata/splits/split_seed2.json<br>`python scripts/make_splits.py` | 覆盖校正替换 12 个（下限修正 0）；C1+C2 7/7 类达标 |
| 池内标签 | 全量图（581）标签分布 | `{"n": 581, "pos": 212, "zero": 369, "multi": 88, "per_class_pos": {"access_control": 91, "arithmetic": 101, "dos": 82, "front_running": 80, "reentrancy": 108, "time_manipulation": 91, "uncheck": 137}}` | products/alldata/graphs/*_pyg.pt + alldata(readonly)/contract_labels.json |  |
| 池内标签 | 划分池（448）标签分布 | `{"n": 448, "pos": 125, "zero": 323, "multi": 1, "per_class_pos": {"access_control": 15, "arithmetic": 15, "dos": 6, "front_running": 4, "reentrancy": 31, "time_manipulation": 5, "uncheck": 50}}` | 同上 | 逐类支撑决定宏平均是否可用（见 decisions §13） |
| 图→划分 | 去重不变量（同 sha1 / 同地址不得跨划分，逐种子） | `{"0": {"content_ok": true, "address_ok": true, "content_cross": 0, "address_cross": 0}, "1": {"content_ok": true, "address_ok": true, "content_cross": 0, "address_cross": 0}, "2": {"content_ok": true, "address_ok": true, "content_cross": 0, "address_cross": 0}}` | products/alldata/splits/split_report.json::rule_check<br>`python scripts/make_splits.py` | 全 0 = 大纲 5.1「同一合约及其所有重复记录不跨划分」已构造性保证 |
| DIVE 外部测试 | 标签条目数 / 多标签条数 / 全零条数 | `{"n": 21696, "multi": 14789, "zero": 2686}` | DIVE/contract_labels.json | 多标签占比 68.2% → 外部测试可支撑「多类共存」的实证 |
| DIVE 外部测试 | 逐类正样本数与占比 | `{"access_control": "16134 (74.36%)", "arithmetic": "9183 (42.33%)", "dos": "3548 (16.35%)", "front_running": "530 (2.44%)", "reentrancy": "10936 (50.41%)", "time_manipulation": "6065 (27.95%)", "uncheck": "5712 (26.33%)"}` | DIVE/contract_labels.json | front_running 占比最低，决定抽样规模下限 |
| DIVE 外部测试 | 均匀抽样下的逐类期望（500/900） | `{"500": {"per_class_expected": {"access_control": 371.8, "arithmetic": 211.6, "dos": 81.8, "front_running": 12.2, "reentrancy": 252.0, "time_manipulation": 139.8, "uncheck": 131.6}, "multi_label_expected": 340.8}, "900": {"per_class_expected": {"access_control": 669.3, "arithmetic": 380.9, "dos": 147.2, "front_running": 22.0, "reentrancy": 453.7, "time_manipulation": 251.6, "uncheck": 236.9}, "multi_label_expected": 613.5}, "front_running_p_ge20": {"500": 0.022, "900": 0.7, "1100": 0.936}}` | DIVE/contract_labels.json | 大纲 5.1(6)「≥500 且每类 ≥20」在 500 规模下对 front_running 不可达（期望 12.2）；n=900 期望 22.0、P(fr≥20)=0.70，三条件自洽 → 2026-09-12 P1 定稿 n=900 |
| 图结构 | 异构图数 / 节点数 / 边数合计 | `{"graphs": 581, "nodes": 93551, "edges": 226511}` | products/alldata/graphs/*_hetero.json<br>`python scripts/build_cfg_centered_hetero_graph.py` |  |
| 图结构 | 逐边类型：边数 / 含该边的图数 / 平均每图 / 边数占比 | `{"CFG_FLOW": {"edges": 71296, "graphs_with_edge": 581, "edges_per_graph": 122.71, "share": 0.3148}, "AST_PARENT": {"edges": 1957, "graphs_with_edge": 481, "edges_per_graph": 3.37, "share": 0.0086}, "AST_PARENT_SAME": {"edges": 6035, "graphs_with_edge": 563, "edges_per_graph": 10.39, "share": 0.0266}, "DFG_DEP": {"edges": 146712, "graphs_with_edge": 569, "edges_per_graph": 252.52, "share": 0.6477}, "CALLBACK_RISK": {"edges": 511, "graphs_with_edge": 86, "edges_per_graph": 0.88, "share": 0.0023}}` | products/alldata/graphs/*_hetero.json | AST_PARENT 仅 1957 条（481/581 图有），边集主体是 DFG_DEP 与 CFG_FLOW |
| 图结构 | AST 专项：AST_PARENT / AST_PARENT_SAME / 端点未映射到 CFGNode 的 AST 父子关系 | `{"AST_PARENT": 1957, "AST_PARENT_SAME": 6035, "ast_unmapped": 273811}` | products/alldata/graphs/*_hetero.json（meta.ast_*_edge_count） | 保留为语义边的 AST 父子关系仅 AST_PARENT+SAME=7992 条（占全部边 3.53%），其余 273811 条端点未映射到 CFGNode；→ “语法从属”边几乎不承载信息，论文需给出本稀疏性统计，并据此调整“四类边”的贡献表述 |
| 图结构 | 关系编号映射：实现 5 物理关系 → 论文 4 语义边（可选 6 关系） | `{"0": {"physical": "CFG_FLOW", "paper_semantic": "CFG_FLOW（含 seq/true/false 子类）"}, "1": {"physical": "AST_PARENT", "paper_semantic": "AST_PARENT"}, "2": {"physical": "AST_PARENT_SAME", "paper_semantic": "AST_PARENT（实现细节：多个 AST 节点落在同一 CFGNode）"}, "3": {"physical": "DFG_DEP", "paper_semantic": "DFG_DEP"}, "4": {"physical": "CALLBACK_RISK", "paper_semantic": "CALLBACK_RISK"}}` | scripts/dataset.py::RELATION_NAMES / scripts/convert_hetero_json_to_pyg.py | 论文默认 4 语义边（AST_PARENT_SAME 并入 AST_PARENT 叙述）；若把 CFG_FLOW 三子类当独立关系则为 6（需新增 kind→edge_type 映射，当前未实现）；边消融口径：去 AST_PARENT = 同时删 relation 1 与 2（dataset.py::DROP_AST，加载时过白名单校验）；DROPPABLE_EDGES = 全部 5 个物理关系，load_graph 强制校验，不做物理合并（num_bases=5 不变） |
| 口径绑定 | 划分产物指纹 sha256（支撑数字绑定的版本） | `{"split_seed0.json": "3de35729c8fbdbdf093fee070ba414879c2d41c9ceb0df952d72f17a0a47383b", "split_seed1.json": "060fb038bc22efb3a9a4e262e85d2878e82d99d0c565943c6dc939f9c0133203", "split_seed2.json": "d9a14613e7c0b8d69f49cd14473947b09e37d8e5d5a98943f145fb78f7c43e3d"}` | products/alldata/splits/split_seed{0,1,2}.json<br>`python scripts/make_splits.py` | 本报告与 decisions 中所有 val/test 支撑数字均对应此指纹（**两级去重后的现行 splits**）；任何划分产物变更（含去重口径、覆盖约束、种子）都会改变指纹 → 必须重跑本脚本并刷新 decisions/手册的支撑数字 |
| DIVE 外部测试 | 抽样结果（固定协议） | `{"seed": 0, "n": 900, "attempt": 1, "per_class": {"access_control": 682, "arithmetic": 378, "dos": 136, "front_running": 30, "reentrancy": 468, "time_manipulation": 234, "uncheck": 246}, "multi_label": 614, "all_zero": 105, "gate": "closed: n=900, front_running=30 (≥20)"}` | products/dive/splits/sample_report.json<br>`python scripts/sample_dive_subset.py` | 抽样是一次确定事件：实测支撑即结果（front_running≥20 → 闭案）；后备路径（n→1100 重抽一次，再不足则记 report-only）与“禁止换 seed 重抽”见 decisions §13 |

## 3. DIVE 外部测试抽样门槛

- DIVE 标签 21696 条，多标签 14789 条（68.2%）。
- n=500 均匀抽样：多标签期望 340.8；逐类期望 {'access_control': 371.8, 'arithmetic': 211.6, 'dos': 81.8, 'front_running': 12.2, 'reentrancy': 252.0, 'time_manipulation': 139.8, 'uncheck': 131.6}
- n=900 均匀抽样：多标签期望 613.5；逐类期望 {'access_control': 669.3, 'arithmetic': 380.9, 'dos': 147.2, 'front_running': 22.0, 'reentrancy': 453.7, 'time_manipulation': 251.6, 'uncheck': 236.9}
- front_running 达到 ≥20 的超几何概率（抽样前口径）：{'500': 0.022, '900': 0.7, '1100': 0.936}
- 结论：多标签计数在 DIVE 上不是退化项（占比高），外部测试的多标签证据成立；均匀抽样在 500 规模下对 front_running 不可达（期望 12.2），**抽样规模已定稿 n=900**（2026-09-12 P1；固定 seed，一次确定事件；实测结果见下表），后备路径见 decisions §13。

## 4. 图结构口径（AST 稀疏性 / 关系数映射）

- 581 图 / 93551 节点 / 226511 边。

| 边类型（物理关系） | 边数 | 含该边的图数 | 平均每图 | 边数占比 |
| --- | --- | --- | --- | --- |
| CFG_FLOW | 71296 | 581 | 122.71 | 31.48% |
| AST_PARENT | 1957 | 481 | 3.37 | 0.86% |
| AST_PARENT_SAME | 6035 | 563 | 10.39 | 2.66% |
| DFG_DEP | 146712 | 569 | 252.52 | 64.77% |
| CALLBACK_RISK | 511 | 86 | 0.88 | 0.23% |

- AST 专项：AST_PARENT 1957 / AST_PARENT_SAME 6035 / 映射不到 CFGNode 的 AST 父子关系 273811；→ 语法从属边几乎不承载信息，论文须给出本表并据此调整“四类边”的贡献表述。

| 编号 | 物理关系（实现） | 论文语义 |
| --- | --- | --- |
| 0 | CFG_FLOW | CFG_FLOW（含 seq/true/false 子类） |
| 1 | AST_PARENT | AST_PARENT |
| 2 | AST_PARENT_SAME | AST_PARENT（实现细节：多个 AST 节点落在同一 CFGNode） |
| 3 | DFG_DEP | DFG_DEP |
| 4 | CALLBACK_RISK | CALLBACK_RISK |

- 论文默认 **4 语义边**（AST_PARENT_SAME 并入 AST_PARENT 叙述）；实现为 **5 个物理关系**（`num_bases=5`）；若把 CFG_FLOW 三子类当独立关系则为 **6**（需补 `kind→edge_type` 映射，当前未实现）。
- 边消融口径：**去 AST_PARENT = 同时删 relation 1 与 2**（`dataset.py::DROP_AST`）；`DROPPABLE_EDGES` 为**全部 5 个物理关系**的白名单，`load_graph` 在加载时强制校验（越界编号直接报错）；不做物理合并（5 个物理关系、`num_bases=5` 不变）。

## 5. 口径绑定指纹与刷新义务（防文档/产物漂移）

- **注释必须与被解释的指标同口径**（decisions §13 第 8 条）：
  - macro-F1 的*低支撑构成*注释 → 用**计算它的那个划分**（seed0 test：‘5 个类 support ≤2’）；
  - 数据固有稀疏的*天花板*叙述 → 用**池级**（‘池内 3 个类正样本 ≤6’）；
  - 两个口径都保留、各有用途，**禁止互相借用**。

- 划分产物指纹（本节所有 val/test 支撑数字绑定于此；均为**两级去重后的现行 splits**）：

| 产物 | sha256 |
| --- | --- |
| split_seed0.json | `3de35729c8fbdbdf093fee070ba414879c2d41c9ceb0df952d72f17a0a47383b` |
| split_seed1.json | `060fb038bc22efb3a9a4e262e85d2878e82d99d0c565943c6dc939f9c0133203` |
| split_seed2.json | `d9a14613e7c0b8d69f49cd14473947b09e37d8e5d5a98943f145fb78f7c43e3d` |

- **刷新义务（已履行 2026-09-12）**：T-A 两级池去重重跑后，本报告（重跑本脚本）、`experiments/decisions.md`（§12 历史标注 + §14 现行口径）、`论文开发手册.md` §10.2/§10.5 的池规模、划分规模与逐类支撑数字已同步刷新；今后任何划分产物变更必须重复这一链条，未刷新即视为口径漂移（验收不通过）。

## 6. 论文口径写法（按本表）

- 训练/验证/内部测试：**448 个源文件级样本**（非 2002 个合约定义），并说明 2002 的来由与差额；
- 正/负样本：池内正样本 125、全零 323；多标签 **1** → 多标签证据改由 DIVE 承担；
- 去重口径：两级（源码内容 sha1 → 项目标识/地址），保两级的跨划分不变量均为 0；
- 逐类支撑必须随指标一起报告（见 `experiments/decisions.md` §13）。

