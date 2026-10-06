# 5.3 六个传统工具的对比实验（程序生成，勿手改）

> 生成脚本：`scripts/collect_traditional_tools.py`；驱动：`scripts/baseline_static_tools.py --tool <名>`；
> 五工具的调用/解析/映射在 `scripts/static_tool_adapters.py`。
> **主对比表**在 `experiments/baseline_three_caliber_tables.md`（同一份生成器 `collect_baseline_tables.py`）。
> 本文只放**读那六行数字的前提**：映射、能力边界、覆盖率、成本。

## 一、范围与口径（**读任何数字之前先读这一节**）

| 项 | 值 |
| --- | --- |
| 语料 | **对照口径**池 **453**（`products/alldata/graphs`，含 `buggy_*` 共 590 图） |
| 划分 | `products/alldata/splits/split_seed{0,1,2}.json`（8:1:1 覆盖约束校正） |
| 评测工作点 | **只有一个**：固定 0.5。传统工具是确定性规则，**没有阈值可搜**，故不存在 `@val_thr` 那一列 |
| 指标 | `micro_f1` / `macro_f1` / `逐类 F1`，全部调 `scripts/metrics.py`（三个基线同一份实现） |
| Slither 的跑动范围 | 全量 590 图（`products/alldata/graphs`） |
| 其余五工具的跑动范围 | 三种子 val∪test 并集 214 个合约 |

🔴 **两条必须随数字一起读的口径**：

1. **分母只有「成功分析」的合约**：编译失败／超时／不支持的合约记 `error`/`timeout`，
   **不计入分母、也不记成全零预测**。记成全零等于把「工具跑不了」算成「工具说没漏洞」，
   那是系统性压低 FP、抬高 F1 的偏差。每行的实际分母见第三节。
2. **映射是人为规定的**：工具输出的是各自的检测项名，本仓的七类是 MVD-HG 的类目，
   二者**没有官方对照表**。映射尺子见第二节，每条都给出 SWC 编号作为可核对的依据。

> ⚠ **禁止跨行比较「某一类为 0」**：那可能是**该工具不提供此检测项**（映射/能力的边界），
> 而不是「该工具在此类上 F1=0」。第二节的「未纳入」清单与第三节的「不提供的类」是判据。

## 二、检测项 → 七类映射（**同一把尺**）

尺子（六个工具一致）：**一个检测项进入七类，当且仅当它有唯一且明确的 SWC 锚点，且该 SWC 落在七类语义内**。无锚点者一律不纳入——宁可漏，不可编。

### 2.1 Slither（纳入 27 项）

| 检测项（工具原生写法） | → 类 |
| --- | --- |
| `suicidal` | access_control |
| `unprotected-upgrade` | access_control |
| `arbitrary-send-eth` | access_control |
| `arbitrary-send-erc20` | access_control |
| `arbitrary-send-erc20-permit` | access_control |
| `controlled-delegatecall` | access_control |
| `tx-origin` | access_control |
| `controlled-array-length` | access_control |
| `divide-before-multiply` | arithmetic |
| `incorrect-exp` | arithmetic |
| `tautology` | arithmetic |
| `tautological-compare` | arithmetic |
| `calls-loop` | dos |
| `msg-value-loop` | dos |
| `delegatecall-loop` | dos |
| `reentrancy-eth` | reentrancy |
| `reentrancy-no-eth` | reentrancy |
| `reentrancy-benign` | reentrancy |
| `reentrancy-events` | reentrancy |
| `reentrancy-unlimited-gas` | reentrancy |
| `reentrancy-balance` | reentrancy |
| `timestamp` | time_manipulation |
| `weak-prng` | time_manipulation |
| `unchecked-transfer` | uncheck |
| `unchecked-lowlevel` | uncheck |
| `unchecked-send` | uncheck |
| `unused-return` | uncheck |

### 2.2 Mythril（纳入 12 项）

| 检测项（工具原生写法） | → 类 |
| --- | --- |
| `106` | access_control |
| `105` | access_control |
| `112` | access_control |
| `115` | access_control |
| `124` | access_control |
| `101` | arithmetic |
| `113` | dos |
| `114` | front_running |
| `107` | reentrancy |
| `116` | time_manipulation |
| `120` | time_manipulation |
| `104` | uncheck |

**未纳入但可能被观察到（1 条）**：

- `SWC-100/108/109/110/111/117/118/119/121/122/123/125/126/127/128/129/130/131/132` —— 落在七类语义之外的 SWC，无对应类目

### 2.3 Manticore（纳入 22 项）

| 检测项（工具原生写法） | → 类 |
| --- | --- |
| `Reachable SELFDESTRUCT` | access_control |
| `Reachable selfdestruct instructions` | access_control |
| `Reachable external call or ether leak to sender or arbitrary address` | access_control |
| `Reachable ether leak to user controlled address via argument` | access_control |
| `Reachable external call to user controlled address via argument` | access_control |
| `Reachable ether leak to sender via argument` | access_control |
| `Reachable external call to sender via argument` | access_control |
| `Reachable ether leak to sender` | access_control |
| `Reachable external call to sender` | access_control |
| `Delegatecall to user controlled address` | access_control |
| `Delegatecall to user controlled function` | access_control |
| `Signed integer overflow at` | arithmetic |
| `Unsigned integer overflow at` | arithmetic |
| `Integer underflow at` | arithmetic |
| `Potential race condition (transaction order dependency)` | front_running |
| `Possible transaction race conditions` | front_running |
| `Potential reentrancy vulnerability` | reentrancy |
| `Reentrancy bug (different method)` | reentrancy |
| `Reentrancy multi-million ether bug` | reentrancy |
| `Reentrancy bug` | reentrancy |
| `Returned value at` | uncheck |
| `Unused internal transaction return values` | uncheck |

**未纳入但可能被观察到（5 条）**：

- `Potentially reading uninitialized storage` —— SWC-109，七类无此语义
- `Potentially reading uninitialized memory` —— SWC-109 同上
- `INVALID instruction` —— 执行到 INVALID 指令，无 SWC 锚点
- `Manipulable balance used in a strict comparison` —— 无 SWC 锚点（与 SmartCheck `SOLIDITY_BALANCE_EQUALITY` 同概念，一起排除）
- `instruction used` —— env-instr：环境指令可操纵，无 SWC 锚点

### 2.4 Smartcheck（纳入 11 项）

| 检测项（工具原生写法） | → 类 |
| --- | --- |
| `SOLIDITY_TX_ORIGIN` | access_control |
| `SOLIDITY_ARRAY_LENGTH_MANIPULATION` | access_control |
| `SOLIDITY_DIV_MUL` | arithmetic |
| `SOLIDITY_SAFEMATH` | arithmetic |
| `SOLIDITY_DOS_WITH_THROW` | dos |
| `SOLIDITY_TRANSFER_IN_LOOP` | dos |
| `SOLIDITY_GAS_LIMIT_IN_LOOPS` | dos |
| `SOLIDITY_EXACT_TIME` | time_manipulation |
| `SOLIDITY_INCORRECT_BLOCKHASH` | time_manipulation |
| `SOLIDITY_UNCHECKED_CALL` | uncheck |
| `SOLIDITY_SEND` | uncheck |

**未纳入但可能被观察到（5 条）**：

- `SOLIDITY_BALANCE_EQUALITY` —— `.balance ==` 无 SWC 锚点（与 manticore `lockdrop` 同概念，一起排除）
- `SOLIDITY_LOCKED_MONEY` —— 锁定资金，无 SWC 锚点（Slither 的 `locked-ether` / Securify 的 `LockedEther` 同样未纳入 ⇒ 三个工具一致）
- `SOLIDITY_OVERPOWERED_ROLE` —— 角色权限过大，无 SWC 锚点
- `SOLIDITY_VISIBILITY` —— 默认可见性（SWC-100）——⚠ **本项是边界情形**：SWC-100 真实存在，但 7 类 `access_control` 的原生语义是「授权/权限控制」而非「可见性声明」，且 Slither/Securify 均无对应项 ⇒ 为跨工具一致而不纳入
- `其余 27 条` —— 风格/兼容性/ERC 接口/气体优化类规则，无 SWC 锚点或落在七类之外

### 2.5 Securify（纳入 20 项）

| 检测项（工具原生写法） | → 类 |
| --- | --- |
| `Unrestricted call to selfdestruct` | access_control |
| `Unrestricted Ether Flow` | access_control |
| `Arbitrary Send` | access_control |
| `Unrestricted write to storage` | access_control |
| `Delegatecall or callcode to unrestricted address` | access_control |
| `Possibly unsafe usage of tx-origin` | access_control |
| `Multiplication after division` | arithmetic |
| `External call in loop` | dos |
| `Dos gas limit pattern` | dos |
| `Transaction Order Affects Ether Receiver` | front_running |
| `Transaction Order Affects Execution of Ether Transfer` | front_running |
| `Transaction Order Affects Ether Amount` | front_running |
| `Gas-dependent Reentrancy` | reentrancy |
| `Reentrancy with constant gas` | reentrancy |
| `Benign Reentrancy` | reentrancy |
| `No-Ether-Involved Reentrancy` | reentrancy |
| `Usage of block timestamp` | time_manipulation |
| `Unused Return Pattern` | uncheck |
| `Unhandled Exception` | uncheck |
| `Low Level Calls` | uncheck |

**未纳入但可能被观察到（10 条）**：

- `Locked Ether` —— 锁定资金，无 SWC 锚点（与 Slither `locked-ether`、SmartCheck `SOLIDITY_LOCKED_MONEY` 一致排除）
- `Repeated Call to Untrusted Contract` —— 「重复调用可能返回不同值」无单一 SWC 锚点
- `Missing Input Validation` —— 无 SWC 锚点（Slither 的 `missing-zero-check` 亦未纳入）
- `Dangerous Strict Equalities` —— 严格相等比较，无 SWC 锚点（Slither `incorrect-equality` 亦未纳入）
- `Constable State Variables` —— 可声明为 constant，纯风格问题
- `External Calls of Functions` —— 「可标为 external」，纯风格问题
- `Uninitialized State Variable` —— SWC-109 未初始化存储，七类无此语义
- `Unused State Variable` —— 无 SWC 锚点
- `State Variable Shadowing` —— 无 SWC 锚点
- `Taint Analysis for PASS Project` —— 特定项目的污点分析，非本文语料

### 2.6 Oyente（纳入 6 项）

| 检测项（工具原生写法） | → 类 |
| --- | --- |
| `Parity Multisig Bug 2` | access_control |
| `Integer Overflow` | arithmetic |
| `Integer Underflow` | arithmetic |
| `Transaction-Ordering Dependence (TOD)` | front_running |
| `Re-Entrancy Vulnerability` | reentrancy |
| `Timestamp Dependency` | time_manipulation |

**未纳入但可能被观察到（1 条）**：

- `Callstack Depth Attack Vulnerability` —— 调用深度攻击，**EIP-150 后已不可行**，且无 SWC 锚点

## 三、能力边界与覆盖率（§47.4 要求随表披露）

| 工具 | solc 口径 | 覆盖率（三种子 test，`n_analyzed/n_in_split`） | 状态分布（全部跑动的合约） |
| --- | --- | --- | --- |
| **Slither** | 按源码 pragma 选 solc，候选序列逐个重试（上限 8） | 45/46、45/46、45/46 | ok 560、error 30 |
| **Mythril** | `--solv` 由 pragma 决定（py-solc-x 从本机 `~/.solcx` 取，**离线**）；候选上限 3 | 40/46、38/46、39/46 | ok 184、timeout 21、error 9 |
| **Manticore** | `--solc` 由 pragma 决定；**逐合约**跑（多合约文件必须 `--contract`），候选上限 3 | 38/46、39/46、35/46 | ok 177、timeout 31、error 6 |
| **Smartcheck** | **不用 solc**（JVM 自己解析源码）⇒ 无 pragma 版本限制 | 46/46、46/46、46/46 | ok 214 |
| **Securify** | `SOLC_BINARY` 指它支持的版本；**会自动改写 pragma 但只改 pragma 行、不升级语法** | 8/46、11/46、7/46 | error 167、ok 47 |
| **Oyente** | solc **钉死 0.4.19**（env 内 shim），不吃候选 ⇒ 0.5+/0.8 源码编译失败 | 10/46、14/46、12/46 | error 169、ok 45 |

**能力边界（逐工具，进论文行注）**：

- **Mythril**：
  - 符号执行工具，逐合约**按时间预算**跑；超时记 `timeout`，与 Slither 的 `error` 同口径（不计入分母、不记全零）。
  - solc 由 py-solc-x 按 `--solv` 选择；本机已把 solc-select 的 101 个版本软链进 `~/.solcx`（`solc-bin.ethereum.org` 直连被 SSL 拦，**离线**是硬前提）。
- **Manticore**：
  - 🔴 **必须 `--thorough-mode`**：非该模式下 CLI 强制 `exclude_all=True`，一个检测器都不跑（且会撞 finalize() 的判空缺失 bug）。
  - 🔴 **多合约文件必须显式 `--contract`**：实测单文件最多含 19 个 contract/library/interface，本适配层**逐个合约跑并取并集**（Slither 是按文件整体分析，两者口径在此不同，须披露）。
  - 符号执行，逐合约按时间预算；超时记 `timeout`。
- **Smartcheck**：
  - 🔴 **走 JVM 自己解析源码，不调用 solc** ⇒ **无 pragma 版本限制**（本轮覆盖面最广的工具）。
  - `--help` 不是合法参数（会抛 IllegalArgumentException）；用法是 `smartcheck -p <路径>`。
  - 规则表 = 包内 `solidity-rules.xml` 的 40 条 `RuleId`（映射只取其中 11 条，见 `excluded`）。
- **Securify**：
  - 🔴 **实测边界（2026-09-25，本池 214 个合约逐条验过；最终跑数）**：**47 个成功里 45 个是 0.5.x、2 个是 0.4.x**（后者语法恰好 0.5 兼容）。按 pragma 分：**0.5.x 成功 45/46（98%）**、**0.4.x 成功 2/161（1.2%）**、**无 pragma 成功 0/7** ⇒ 总覆盖 **47/214 = 22.0%**。⚠ 措辞取「只能吃 0.5.x 的老合约」而非「只吃 ≥0.5.8」——实测成功的 0.5.x 里含 `^0.5.0`/`^0.5.4` 这类 <0.5.8 的。
  - 🔴 **两条失败路径都实测到了**（这是「真的不行」而非「参数没调对」的证据）：① 给 pragma 匹配的 0.4.x solc ⇒ `Solc version X not supported by CFG compiler`（`ast_dict[_solc_version]` KeyError —— 它的 CFG 语法表里没有 0.4）；② 给 0.5.12 ⇒ `SyntaxError: No visibility specified` + `TypeError: Wrong argument count for function call: 0 arguments given but expected 1`（0.4 语法在 0.5.0+ 非法）。**pragma 改写只改 pragma 行、不升级语法**，故两条路都堵死。
  - ⚠ **`--ignore-pragma` 不要传**：默认的 pragma 改写正是它能吃 0.5.x 老合约的原因（改写后按它支持的 solc 编译，0.5.x 语法恰好兼容）。
  - 需 `SOUFFLE_BINARY=souffle162` 与 `libfunctors` 的 `LD_LIBRARY_PATH`（见 `install_traditional_tools.sh`；souffle 2.5 会被 2019 年的 `.dl` 拒收）。
  - ⚠ 它**会改写源码副本**（pragma 替换）⇒ 必须在 `work/` 的副本上跑，绝不能碰只读源。
- **Oyente**：
  - 🔴 **solc 钉死 0.4.19**（源码内 tested 版本，env 内的 `solc` shim 保证）⇒ **0.5.x/0.8.x 的合约一律编译失败**；本轮池里 214 个合约有 161 个是 0.4.x，故 Oyente 的可分析面**结构性偏向老合约**，这个偏差必须写进行注。
  - 必须在 `~/tools/oyente/oyente` 目录内跑（源码用顶层 import）；`-s` **必须是绝对路径**（相对路径在 cd 后会解析失败）；`eval` 二进制由 `PATH` 提供。
  - ⚠ 启动时硬检查 `z3.z3util`，故 z3 钉 4.8.17。

**该工具不提供检测项、恒为 0 的类**（不得读成「在此类上 F1=0」）：

- **Slither**：`front_running`
- **Mythril**：**（无——七类都有对应检测项）**
- **Manticore**：`dos`、`time_manipulation`
- **Smartcheck**：`front_running`、`reentrancy`
- **Securify**：**（无——七类都有对应检测项）**
- **Oyente**：`dos`、`uncheck`

> ⚠ **上表与「能分析几个合约」是两件事**：`Securify` 七类都有检测项，但它的**可分析合约只有 15%（pragma 0.5.x）** ⇒ 它的行是「检测项齐全、但只在少数合约上跑得出来」；`Smartcheck` 反之（**全部 214 个合约都能分析**，但**没有 reentrancy 规则**）。前者影响**分母**，后者影响**某一类恒为 0** —— 读表时必须分开看。

> ⚠ **`front_running` 是重灾区**：Slither 0.11.5 的 100 个检测器里没有任何一个覆盖 SWC-114（Transaction Order Dependence）。凡该工具不提供此检测项，其 F1 恒为 0，论文里必须写成「**该工具不提供此检测项**」，不得写成「该工具在此类上 F1=0」。

## 四、逐类 F1（固定 0.5，三种子 mean ± std）

| 工具 | `access_control` | `arithmetic` | `dos` | `front_running` | `reentrancy` | `time_manipulation` | `uncheck` | micro | macro | micro† | macro† |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Slither** | 0.2322 ± 0.0710 | 0.0000 ± 0.0000 | 0.0000 ± 0.0000 | — | 0.7512 ± 0.0713 | 0.2551 ± 0.0759 | 0.8176 ± 0.0509 | 0.4547 ± 0.0216 | 0.2937 ± 0.0111 | 0.4617 ± 0.0220 | 0.3427 ± 0.0129 |
| **Mythril** | 0.4074 ± 0.1604 | 0.3286 ± 0.0939 | 0.0000 ± 0.0000 | 0.0833 ± 0.1443 | 0.4910 ± 0.0307 | 0.2286 ± 0.2060 | 0.8806 ± 0.0502 | 0.4058 ± 0.0602 | 0.3456 ± 0.0651 | 0.4058 ± 0.0602 | 0.3456 ± 0.0651 |
| **Manticore** | 0.4167 ± 0.2205 | 0.6667 ± 0.2309 | — | 0.0000 ± 0.0000 | 0.4444 ± 0.0962 | — | 0.3333 ± 0.2887 | 0.4055 ± 0.0638 | 0.2659 ± 0.0574 | 0.4417 ± 0.0703 | 0.3722 ± 0.0803 |
| **Smartcheck** | 0.3000 ± 0.2646 | 0.0000 ± 0.0000 | 0.0000 ± 0.0000 | — | — | 0.2222 ± 0.3849 | 0.9167 ± 0.0722 | 0.3287 ± 0.0228 | 0.2056 ± 0.0945 | 0.3780 ± 0.0222 | 0.2878 ± 0.1322 |
| **Securify** | — | — | — | — | — | — | — | — | — | — | — |
| **Oyente** | 0.0000 ± 0.0000 | 0.1698 ± 0.0287 | — | 0.4889 ± 0.1540 | 0.9259 ± 0.0641 | 0.5000 ± 0.7071‡ | — | 0.3853 ± 0.0601 | 0.2740 ± 0.0835 | 0.4495 ± 0.0574 | 0.3836 ± 0.1169 |

> 🔴 **上表的 `—` 有两种判据，读法不同**（两种都**不写 0.0000**，因为那样会被读成成绩）：
> ① **`—`（能力缺失）**= 该工具**不提供**此检测项 ⇒ 见下面这张交叉表的 `✗`；
> ② **`—`（整行）**= 该划分里**逐类 support 全为 0** ⇒ 该行**不可评估**（见下方 warning）。
> 二者与「工具跑了但没检出」**都不是一回事**——后者才是真正带信息量的 0（如 Slither 的 `arithmetic`/`dos`：有检测项、support>0、确实一个没报对）。
> ⚠ **`micro` / `macro`（不带 †）不因 `—` 而改变**：它们仍按**七类全量**聚合（即把该工具结构性检测不到的那些类计入漏检）——这是一把尺下「该工具作为七类检测器」的真实读数，**与本文方法、三条基线可比**。
> 
> 🔴 **带 † 的两列 = 「仅该工具有检测项的类」上的 micro / macro**（用户 2026-09-26 要求）：把上表画 `—` 的类**从分母里去掉**再算，回答「它在自己声称能做的范围内有多好」。**两列口径不可互相替代**：
> - 不带 † 的是**对比用**读数（工具与模型在同一张表里必须同口径）；
> - 带 † 的**只描述工具自身的覆盖范围**，它**系统性偏高**（分母小了），**不得**拿去和本文方法、三条基线的 micro/macro 横比——那是拿 5 类的分母比 7 类的分母。
> ⚠ 覆盖 7/7 类的工具（Mythril、Securify）两列**必然逐位相同**；Securify 两列都是 `—`（整行不可评估，见下）。算法：从标签与原始预测切列重算（`covered_metrics()`），切列前的重算值与产物存档逐位对拍不符即**拒绝出数**。

**交叉表：`✗` = 该工具**不提供**此检测项（**表中该格已画 `—`**）；`·` = 有检测项**：

| 工具 | `access_control` | `arithmetic` | `dos` | `front_running` | `reentrancy` | `time_manipulation` | `uncheck` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Slither** | · | · | · | ✗ | · | · | · |
| **Mythril** | · | · | · | · | · | · | · |
| **Manticore** | · | · | ✗ | · | · | ✗ | · |
| **Smartcheck** | · | · | · | ✗ | ✗ | · | · |
| **Securify** | · | · | · | · | · | · | · |
| **Oyente** | · | · | ✗ | · | · | · | ✗ |


> ‡ **该格不是 3 种子均值**：列出的种子在该类上 **support=0**（F1 是 0/0 未定义，`zero_division=0` 会记成 0.0）⇒ 按用户 2026-09-26 裁定 **剔除**，不当成「预测失败」计入。受影响：**Oyente** 的 `time_manipulation`（缺 seed0）。其余各格均为 3 种子。⚠ `micro`/`macro` 两列**仍按全量口径**（含零支撑类）——那是全仓统一实现（`metrics.macro_f1`，本文方法与三条基线同理），改它会动到所有已报告数字。


> 🔴🔴 **warning：下列工具在 test 划分里「逐类 support 全为 0」⇒ 该行不可评估**
>
> - **Securify**：三种子 test 的正样本合计 = 0、0、0 ⇒ **第四节该行已全部画 `—`**（**不是**它跑了得到 0，而是**分母里没有正样本**）——底层 `micro_f1` 落在产物里是 `0.0`，那是 `zero_division=0` 的占位，**不可引用**。
>
> ⚠ 论文里这一格**不能写 F1=0**，必须写「**该工具在本语料上可分析的合约集与 test 的漏洞合约集不相交，故在 test 上不可评估**」，并给出覆盖率与 pragma 分布作依据。


支持度（三种子 test 的逐类正样本数，**各行分母可能不同**）：

| 工具 | `access_control` | `arithmetic` | `dos` | `front_running` | `reentrancy` | `time_manipulation` | `uncheck` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Slither** | 3 | 2 | 1 | 1 | 5 | 2 | 7 |
| **Mythril** | 3 | 2 | 1 | 1 | 5 | 2 | 7 |
| **Manticore** | 3 | 2 | 0 | 1 | 3 | 2 | 3 |
| **Smartcheck** | 3 | 2 | 1 | 1 | 5 | 2 | 7 |
| **Securify** | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **Oyente** | 1 | 1 | 1 | 1 | 4 | 0 | 2 |
## 五、🔴 覆盖率**不是**随机缺失（读对比表前必读）

每个工具把**它自己跑动的合约集**（Slither = 590 全库；其余五个 = 214 并集）切成「能分析 / 不能分析」两集，两集的**漏洞比例**：

| 工具 | 能分析：合约数 / 含漏洞 | 不能分析：合约数 / 含漏洞 | 该工具的 pragma 面 |
| --- | --- | --- | --- |
| **Slither** | 560 / **198**（35%） | 30 / 20（67%） | 0.4.x 339、0.5.x 208、无pragma 13 |
| **Mythril** | 184 / **85**（46%） | 30 / 3（10%） | 0.4.x 147、0.5.x 37 |
| **Manticore** | 177 / **57**（32%） | 37 / 31（84%） | 0.4.x 128、0.5.x 45、无pragma 4 |
| **Smartcheck** | 214 / **88**（41%） | 0 / 0（0%） | 0.4.x 161、0.5.x 46、无pragma 7 |
| **Securify** | 47 / **0**（0%） | 167 / 88（53%） | 0.5.x 45、0.4.x 2 |
| **Oyente** | 45 / **44**（98%） | 169 / 44（26%） | 0.4.x 44、无pragma 1 |

**核心事实（全库 590 图，现算；🔴 必须分族看）**：

| 族 | pragma 主版本 | 合约数 | 其中含漏洞 | 比例 |
| --- | --- | --- | --- | --- |
| **真实池** | 0.4.x | 335 | 128 | 38% |
| **真实池** | 0.5.x | 147 | 0 | 0% |
| **真实池** | 无pragma | 18 | 0 | 0% |
| `buggy_*`（合成注入） | 0.4.x | 10 | 10 | 100% |
| `buggy_*`（合成注入） | 0.5.x | 80 | 80 | 100% |

🔴 **上表两族必须分开读，合起来会得出相反的结论**：
· **真实池**：0.4.x 有 38% 含漏洞，**0.5.x 与无 pragma 的合约一个漏洞都没有** —— 自然语料里「有漏洞 ⟺ 0.4.x」是**完美分离**（128 vs 0）；
· **`buggy_*`**：**100% 正例的合成注入族**（0.5.x 那 80 个 0.5 漏洞全在这里），而它**不在池 453 的划分里**（`dataset.exclude_buggy`）⇒ 与 5.3 的对比表无关。

⇒ 对本报告涉及的工具，结论是：**Securify（只吃 0.5.x）的可分析集在真实池里恰好全是干净合约 ⇒ 它的行在 test 上结构性不可评估；Oyente（钉 0.4.19）的可分析面正好落在漏洞所在的 0.4.x ⇒ 它是唯一有公平机会的**。
凡引用这几行，必须同时给出覆盖率与本节的分集漏洞率；**不能只写「分母不同」**（那会让读者以为缺失是随机的）。

## 六、成本（单合约耗时分布，供复现估时）

| 工具 | 单合约预算 (s) | 合约数 | 实测耗时 p50 / p90 / max (s) | 合计 wall |
| --- | --- | --- | --- | --- |
| **Slither** | —（Slither 无墙钟预算） | 590 | 0.3 / 0.5 / 3.5 | 0.06 h |
| **Mythril** | 180 | 214 | 67.7 / 171.9 / 201.6 | 4.30 h |
| **Manticore** | 180 | 214 | 186.3 / 228.5 / 235.2 | 9.26 h |
| **Smartcheck** | 120 | 214 | 1.1 / 1.4 / 4.9 | 0.07 h |
| **Securify** | 120 | 214 | 0.2 / 1.5 / 17.1 | 0.04 h |
| **Oyente** | 120 | 214 | 0.2 / 1.3 / 61.3 | 0.10 h |

> 符号执行类（Mythril / Manticore）的成本由**单合约预算**封顶，超时记 `timeout`（与 Slither 的 `error` 同口径：不计入分母）。故它们的召回**受预算限制**，这个限制必须随结果披露。

> ⚠ **Manticore** 跑动时因本机内存（WSL 总内存 7.8 GB，工具默认起 24 个 z3 进程）加了 cgroup 内存上限 4.5G：**8 个合约（8/214 ≈ 3.7%）撞到上限、分析被内核中断**（在产物里表现为 `error`/`timeout`，不计入分母），其余合约不受影响。详见 `run_env.json` 与 `decisions.md` §56.7.4。

