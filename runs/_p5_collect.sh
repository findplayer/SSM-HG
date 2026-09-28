#!/usr/bin/env bash
# 编码器换代落地 · 阶段 5：重生成全部交付表（**整表换**：正典位置的数字一律取自新正典）
#
# 🔴 设计取舍：**逐命令记 rc、失败不中断**，最后打一张成败清单。
#    理由：交付表有 20+ 条命令，任一条的默认值/参数若有出入，`set -e` 会在第一条就停，
#    我拿不到"还有哪些能跑"的信息。改为跑完全部再汇总 —— 失败项单独排查，比逐条试错快。
#
# ⚠ 前置（缺了会让 calibrate 走"重推理"分支，那时 `--graph-dir` 才起作用、
#    而它只接受**一个** graph_dir 配三个种子 ⇒ 静默用错树）：
#    三个种子都必须有 `test_probs.pt`。本脚本开工前硬检查。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
LOG=runs/p5_collect.log
declare -a OK=() BAD=()

run() {   # run <标签> <命令...>
  local label="$1"; shift
  echo "=== [$(date +%H:%M:%S)] $label ===" | tee -a "$LOG"
  "$@" >>"$LOG" 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then OK+=("$label"); echo "    ✅ $label" | tee -a "$LOG"
  else BAD+=("$label (rc=$rc)"); echo "    ❌ $label rc=$rc" | tee -a "$LOG"; fi
}

echo "=== [$(date +%H:%M:%S)] P5 汇总链启动 ===" | tee -a "$LOG"

# ---------- 前置硬检查 ----------
for S in 0 1 2; do
  [ -f "runs/seed${S}/test_probs.pt" ] || { echo "!!! 缺 runs/seed${S}/test_probs.pt ⇒ calibrate 会走重推理分支（用错树）" | tee -a "$LOG"; exit 1; }
  # 🔴 任务 2 侧同理：本条是 2026-09-25 阶段 4 换代后补的。缺它三口径/buggy 段的
  #    `test_probs.pt` 列会**整块变 `—` 而不报错**（本仓已栽过：`test_probs.pt` 只由 `diagnose.py` 写）。
  [ -f "runs/buggy_canon/seed${S}/test_probs.pt" ] || { echo "!!! 缺 runs/buggy_canon/seed${S}/test_probs.pt ⇒ buggy 段会整列变 —" | tee -a "$LOG"; exit 1; }
done
echo "=== 前置通过：三种子 + 任务2 三种子 test_probs.pt 齐备 ===" | tee -a "$LOG"

# ---------- 校准（①② 两语料）----------
run "calibrate ①" ${PY} scripts/calibrate.py --runs-dir runs --out-dir eval_results/calibration
run "calibrate ②" ${PY} scripts/calibrate.py --runs-dir runs/augmentation \
    --graph-dir products/augmentation/graphs_ft \
    --split-dir products/augmentation/splits \
    --out-dir eval_results/calibration_aug
# `--check` 会把本脚本的逐类二分类口径与 calibrate 的产物逐位对拍，不一致即拒落盘（互为守卫）
run "collect_per_class_f1 --check" ${PY} scripts/collect_per_class_f1.py --check

# ---------- 误报/漏报率 ----------
run "error_rates ①" ${PY} scripts/error_rates.py --runs-dir runs --out runs/error_rates.json
run "error_rates 消融" ${PY} scripts/error_rates.py --runs-dir runs/ablation --out runs/error_rates_ablation.json
run "error_rates 消融②" ${PY} scripts/error_rates.py --runs-dir runs/ablation_aug --out runs/error_rates_ablation_aug.json

# ---------- 消融汇总（n=3 两语料 / n=9 ①）----------
run "collect_ablation_results main" ${PY} scripts/collect_ablation_results.py --group main
run "collect_ablation_results aug"  ${PY} scripts/collect_ablation_results.py --group aug
run "collect_ablation_n9 ①（含剂量/架构/PM 臂）" ${PY} scripts/collect_ablation_n9.py --group main \
    --with-dose-arms --with-arch-arms --with-pm-arms
run "collect_ablation_n9 ②" ${PY} scripts/collect_ablation_n9.py --group aug
# ⚠ **必须显式传 `--out`**：`collect_perclass_arm.py` 的 `--out` 默认是**空串**，
#   空串时它**只把 markdown 打到 stdout、一个字都不落盘**（2026-09-25 实测：
#   首跑漏传 ⇒ 脚本报 ✅ 但 `experiments/perclass_arm_results.md` 的 mtime 仍是 09-23 的旧代）。
run "collect_perclass_arm" ${PY} scripts/collect_perclass_arm.py \
    --out experiments/perclass_arm_results.md

# ---------- 三口径 + 基线 + buggy 正典 ----------
run "collect_three_caliber_tables ①" ${PY} scripts/collect_three_caliber_tables.py \
    --out experiments/per_class_three_caliber_tables.md
run "collect_three_caliber_tables buggy" ${PY} scripts/collect_three_caliber_tables.py \
    --canon-only-runs runs/buggy_canon --ablation-root runs/ablation_buggy \
    --out experiments/per_class_three_caliber_tables_buggy.md
run "collect_baseline_tables（含 buggy 段）" ${PY} scripts/collect_baseline_tables.py --with-buggy \
    --out experiments/baseline_three_caliber_tables.md
run "collect_buggy_canon_summary" ${PY} scripts/collect_buggy_canon_summary.py \
    --out experiments/buggy_canon_summary.md

# ---------- 闸门表（**换位后 old=归档、new=现行正典**，可随时复核）----------
run "check_encoder_promotion" ${PY} scripts/check_encoder_promotion.py \
    --out experiments/encoder_promotion_gate.md

# ---------- 总表 / bootstrap / 集成 ----------
run "aggregate_results overview" ${PY} scripts/aggregate_results.py --section overview
run "aggregate_results perclass" ${PY} scripts/aggregate_results.py --section perclass
# 🔴 下面两条是 2026-09-25 补入的：它们**有生成脚本但原先不在本清单里** ⇒ 换代后会静默留着
#   旧一代数字（`p1_gains.md` mtime 09-24、`cb_unlimited_reach.md` mtime 09-21，都在换代前）。
run "collect_p1_gains（P1 三笔头寸）" ${PY} scripts/collect_p1_gains.py \
    --out experiments/p1_gains.md
run "audit_cb_unlimited_reach（cb_unlimited 触达审计，主库）" ${PY} scripts/audit_cb_unlimited_reach.py \
    --group main --out experiments/cb_unlimited_reach.md
run "oof_bootstrap ①" ${PY} scripts/oof_bootstrap.py --runs-dir runs --out eval_results/bootstrap/main.json
# ⚠ **只能集成 `cbft_study` 这一组**：本脚本的路径模板是 `<prefix>_ts{T}_ss{S}/seed{T}`，
#   对不上主实验正典的扁平布局 `runs/seed{T}/`（实测会静默 skip）。而 `cbft` 臂**就是**正典
#   （2026-09-25 起取正典树本身），故这一组即"主实验三种子集成"。
run "ensemble_eval cbft_study" ${PY} scripts/ensemble_eval.py --group runs/cbft_study --prefix cbft \
    --out eval_results/ensemble/cbft_study_cbft.json

# ---------- DIVE/SolidiFI：**本次不重跑外部评测**（用户 2026-09-25 裁定）----------
# 🔴 裁定原文：「DIVE 不需要完全跑完，与原数据集大致相当即可」。
#   背景：`evaluate_external.py --matrix {main,aug}` 要跑 **21 臂 × ①② × 3 种子**
#   （约 2 h+），而 DIVE 的角色是**跨数据集泛化性的旁证**，不是主结果。
#   ⇒ **保留换代前算出的 `eval_results/dive/matrix_{main,aug}.json` 与 `comparison.*`**，
#     并在 `experiments/dive_external_results.md` 顶部加横幅披露其口径为**换代前的 ① 编码器**。
#   ⚠ 由此产生的一处**已知不一致**（须随文披露）：① 的 DIVE 特征树已在阶段 3.8
#     换成新编码器，而 DIVE 的**评测数字**仍是旧的 ⇒ 两者不同代。
#     下面这条 `collect_dive_comparison` 只是从**既有矩阵**复算汇总，不重跑推理，
#     故不会引入新的不一致（输出与换代前一致）。
run "collect_dive_comparison（从既有矩阵复算，不重跑推理）" ${PY} scripts/collect_dive_comparison.py
run "collect_dive_comparison" ${PY} scripts/collect_dive_comparison.py

# ---------- 成败清单 ----------
echo "" | tee -a "$LOG"
echo "================ P5 汇总结果 ================" | tee -a "$LOG"
echo "成功 ${#OK[@]} 条：" | tee -a "$LOG"
for x in "${OK[@]:-}"; do [ -n "$x" ] && echo "  ✅ $x" | tee -a "$LOG"; done
echo "失败 ${#BAD[@]} 条：" | tee -a "$LOG"
for x in "${BAD[@]:-}"; do [ -n "$x" ] && echo "  ❌ $x" | tee -a "$LOG"; done
echo "=== P5 DONE [$(date +%H:%M:%S)] ===" | tee -a "$LOG"
[ "${#BAD[@]}" -eq 0 ]
