# 七类逐类 F1：三口径 × 两工作点对比

> 程序生成（`scripts/collect_three_caliber_tables.py`）：**只搬运产物、只调 `metrics`**，不手抄、不重实现指标。

> 🔴 **表 1–6 = 最佳种子口径**（用户 2026-09-20 裁定，`decisions.md` §39；取 **seed1**，判据 = 该正典在 micro-F1@val_thr 上最高），**表 7–12 = 3 种子 mean±std 附录**（ddof=1）。

> ⚠ 最佳种子口径下**没有 ±**（单种子无方差），且本仓实测重跑抖动 ≈0.012（约为种子间 std 的 40%，`decisions.md` §36.4）⇒ **不得**据它下「某干预有效」的结论；那种结论仍须同配对 ≥9 点。

> **三个口径的区别**：`micro` / `macro` 的逐类格是**全测试集**逐类 F1，`buggy` 的逐类格是**仅 `y.any(axis=1)` 的合约**上的逐类 F1。

> 🔴 **`macro` 表与 `micro` 表的逐类格逐位相同**——macro-F1 就是那 7 个数的未加权平均，**差异只在汇总列**（这是恒等，不是重复计算）。

> ✅ **全部 7 类在全部种子上 support ≥ 6** —— 无 support ≤ 2 的薄支撑类，逐类 F1 可进入方法间比较（仍受重跑抖动 0.012 约束）。

> 🔴 **本表的正典 = `runs/buggy_canon`**（含 `buggy_*` 的新池 497 / 新划分），**与 `per_class_three_caliber_tables.md` 不是同一个 test 集** ⇒ 两边的数字**不可直接相减**。

> 🔴🔴 **本表的逐类格与汇总列都含「标签假象」，引用前必须读 `experiments/buggy_canon_summary.md`**：`buggy_*` 合约的标签绝大多数是**七类全 1**（上游按「每类各放一份」复制，`decisions.md` §18.4），模型「全报有漏洞」即可在它们身上拿满分。实测（3 种子）：把 test 里那 **7 个** `buggy_*` 剔掉后，**micro 掉 0.10–0.16、macro 掉 0.33–0.61**（`buggy_canon_summary.md` §3）。
> ⇒ **本表可用于「申报口径下的完整读数」，但不得据此声称「补回 buggy 提升了检测能力」。**

## 0. 逐类 support（先读）

| 语料 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ① 主库 | 9/8/8 | 9/9/9 | 7/7/7 | 6/7/6 | 9/11/12 | 7/8/7 | 14/14/14 |

> 上表为 test 集**逐类正样本数**，按种子 0/1/2 排列（`a/b/c`）。两个工作点的 support **逐位相同**（同一测试集，只是阈值不同），故只列一张。

> ⚠ **漏洞子集（buggy 口径）的逐类 support 与上表逐位相同**——干净合约七类真值全 0，切片不会增减任何一类的正样本数。故「buggy 表」的 support 直接读本表，不另列。

---

---

# 一、主口径：最佳种子（① seed1 / ② seed1）

## 表 1 —— micro-F1 口径（全测试集逐类 F1） @0.5

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.9412 | 0.9412 | 1.0000 | 0.9333 | 0.9524 | 1.0000 | 0.9655 | **0.9612** |

## 表 2 —— buggy-F1 口径（仅有漏洞合约子集逐类 F1） @0.5

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 1.0000 | 0.9412 | 1.0000 | 0.9333 | 0.9524 | 1.0000 | 1.0000 | **0.9764** |

## 表 3 —— macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均） @0.5

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.9412 | 0.9412 | 1.0000 | 0.9333 | 0.9524 | 1.0000 | 0.9655 | **0.9619** |

## 表 4 —— micro-F1 口径（全测试集逐类 F1） @验证集阈值

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.9412 | 0.9412 | 1.0000 | 0.9333 | 0.9524 | 1.0000 | 0.9655 | **0.9612** |

## 表 5 —— buggy-F1 口径（仅有漏洞合约子集逐类 F1） @验证集阈值

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 1.0000 | 0.9412 | 1.0000 | 0.9333 | 0.9524 | 1.0000 | 1.0000 | **0.9764** |

## 表 6 —— macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均） @验证集阈值

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.9412 | 0.9412 | 1.0000 | 0.9333 | 0.9524 | 1.0000 | 0.9655 | **0.9619** |

---

# 二、附录：3 种子 mean±std（保留——单种子无方差，见抬头）

## 表 7 —— micro-F1 口径（全测试集逐类 F1） @0.5

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.8510±0.1043 | 0.9082±0.0572 | 0.9333±0.1155 | 0.8569±0.1236 | 0.9508±0.0500 | 0.9778±0.0385 | 0.9647±0.0357 | **0.9251±0.0552** |

## 表 8 —— buggy-F1 口径（仅有漏洞合约子集逐类 F1） @0.5

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.8706±0.1316 | 0.9237±0.0302 | 0.9333±0.1155 | 0.8569±0.1236 | 0.9508±0.0500 | 0.9778±0.0385 | 0.9762±0.0412 | **0.9323±0.0568** |

## 表 9 —— macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均） @0.5

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.8510±0.1043 | 0.9082±0.0572 | 0.9333±0.1155 | 0.8569±0.1236 | 0.9508±0.0500 | 0.9778±0.0385 | 0.9647±0.0357 | **0.9204±0.0640** |

## 表 10 —— micro-F1 口径（全测试集逐类 F1） @验证集阈值

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.8304±0.0991 | 0.9237±0.0302 | 0.9267±0.0715 | 0.9222±0.0839 | 0.9666±0.0290 | 1.0000±0.0000 | 0.9762±0.0207 | **0.9404±0.0276** |

## 表 11 —— buggy-F1 口径（仅有漏洞合约子集逐类 F1） @验证集阈值

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.8500±0.1323 | 0.9412±0.0000 | 0.9267±0.0715 | 0.9222±0.0839 | 0.9666±0.0290 | 1.0000±0.0000 | 0.9877±0.0214 | **0.9480±0.0300** |

## 表 12 —— macro-F1 口径（逐类格同 micro，汇总列 = 7 类未加权平均） @验证集阈值

| 行 | access_control | arithmetic | dos | front_running | reentrancy | time_manipulation | uncheck | **汇总** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **① 主库 · 正典（runs/buggy_canon）** | 0.8304±0.0991 | 0.9237±0.0302 | 0.9267±0.0715 | 0.9222±0.0839 | 0.9666±0.0290 | 1.0000±0.0000 | 0.9762±0.0207 | **0.9351±0.0341** |

