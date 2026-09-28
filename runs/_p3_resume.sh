#!/usr/bin/env bash
# 阶段 3 **续跑**：3.4 起（3.1/3.2/3.3 已完成，实测 3.1 6 树齐、3.2 18 run、3.3 63 run）。
#
# 🔴 3.4 首次为何中止（2026-09-25 实测，已修）：`conv_gat` + `--deterministic` ⇒
#    `RuntimeError: scatter_reduce_cuda does not have a deterministic implementation`。
#    现行正典带 `--deterministic`（`_p2_chain.sh` 为 SWA 对拍所加），下游臂**继承**它。
#    实测 rgcn/gcn/sage 三者可用、**只有 GAT 不行** ⇒ 已在 `run_ablation.forced_overrides`
#    给 `conv_gat`/`gat_pm` 补 `deterministic: False`（被迫的第二变量，随表披露）。
#    `resume_state` 会跳过已完成的 162 个，本次只需补 **54 个**。
#
# 🔴 退出码纪律（本次又踩一次）：**后台包装行不能以 `echo`/`tail` 结尾** ——
#    那样上报的是它们的退出码（0），会把真正的失败掩盖成成功。本脚本以链子自己的
#    `exit $rc` 结束，并另落一份 `.status` 文件供外部核对。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
LOG=runs/p3_resume.log
SPLITS_MAIN=products/alldata/splits

step() { echo "=== [$(date +%H:%M:%S)] $* ==="; }
fail() { echo "!!! [$(date +%H:%M:%S)] 中止：$*"; echo "FAIL $*" > runs/p3_resume.status; exit 1; }

echo "=== [$(date +%H:%M:%S)] P3 续跑启动（3.4 起）==="

# ---------- 3.4 消融 n=9 + 架构族 + 参数量匹配（补 54 个）----------
step "3.4 run_ablation_n9（补 conv_gat 9 + conv_sage 9 + 4 个 PM × 9 = 54 个）"
${PY} scripts/run_ablation_n9.py --group main \
    --with-dose-arms --with-arch-arms --with-pm-arms >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.4 run_ablation_n9 rc=$rc（见 $LOG）"
for A in conv_gcn conv_gat conv_sage gcn_pm gat_pm hid256_pm sage_pm; do
  N=$(find "runs/arch_n9/$A" -name results.json 2>/dev/null | wc -l)
  [ "$N" -eq 9 ] || fail "3.4 runs/arch_n9/$A 只有 $N/9 个 run"
done
step "3.4 完成：7 个架构/PM 臂各 9 个 run"

# ---------- 3.5 GCN 对照臂（逐类 F1 表的输入）----------
# 命令逐字取自 experiments/gcn_baseline_and_per_class_f1.md:197-215（该表的产出命令）。
# ⚠ 该链是手敲的（不走 run_arch_baselines.py：后者的 out_dir 会多一层 `<conv>/`）。
step "3.5 GCN 对照臂（runs/baseline_gcn，3 seed）"
for s in 0 1 2; do
  GD="products/alldata/graphs_ft_p2/cb_ft_ss${s}"
  ${PY} scripts/train.py --seed "$s" --split-seed "$s" --conv gcn \
      --graph-dir "${GD}" --out-dir runs/baseline_gcn >>"$LOG" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || fail "3.5 train gcn seed${s} rc=$rc"
  ${PY} scripts/evaluate.py --seed "$s" --runs-dir runs/baseline_gcn \
      --graph-dir "${GD}" --split-dir "${SPLITS_MAIN}" >>"$LOG" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || fail "3.5 evaluate gcn seed${s} rc=$rc"
done
${PY} scripts/evaluate.py --summarize --runs-dir runs/baseline_gcn >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.5 evaluate --summarize gcn rc=$rc"
# 🔴 diagnose 必须**逐 seed 传匹配的树**：首次跑（无 test_probs.pt 缓存）会真的加载图，
#    传错 ss 会拿 A 树的特征喂 B 树训出的模型 ⇒ **数值错但不报错**（该文档 §(4) 记的坑）。
for s in 0 1 2; do
  ${PY} scripts/diagnose.py --runs-dir runs/baseline_gcn --seed "$s" \
      --graph-dir "products/alldata/graphs_ft_p2/cb_ft_ss${s}" \
      --split-dir "${SPLITS_MAIN}" >>"$LOG" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || fail "3.5 diagnose gcn seed${s} rc=$rc"
done
${PY} scripts/diagnose.py --runs-dir runs/baseline_gcn \
    --graph-dir products/alldata/graphs_ft_p2/cb_ft_ss0 \
    --split-dir "${SPLITS_MAIN}" >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.5 diagnose gcn 聚合 rc=$rc"
step "3.5 完成"

# ---------- 3.6 逐类独立二分类器（7 类 + ANY_union，2 个 cap = 45 run）----------
step "3.6 run_perclass_arm --steps all（45 run）"
${PY} scripts/run_perclass_arm.py --steps all >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.6 run_perclass_arm rc=$rc（见 $LOG）"
step "3.6 完成"

# ---------- 3.7 runs/ 根下的跨种子聚合（换位后旧 summary 已归档，须重生成）----------
step "3.7 重生成 runs/{summary,diagnosis_summary}.json"
${PY} scripts/evaluate.py --summarize --runs-dir runs >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.7 evaluate --summarize rc=$rc"
${PY} scripts/diagnose.py --summarize --runs-dir runs \
    --graph-dir products/alldata/graphs_ft_p2/cb_ft_ss0 \
    --split-dir "${SPLITS_MAIN}" >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.7 diagnose --summarize rc=$rc"
step "3.7 完成"

# ---------- 3.8 DIVE / SolidiFI 外部集：① 用新编码器重编码 ----------
step "3.8 build_dive_external_set（重编码 ① 的 DIVE/SolidiFI 特征）"
${PY} scripts/build_dive_external_set.py --steps all >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.8 build_dive_external_set rc=$rc（见 $LOG）"
step "3.8 完成"

step "P3 续跑产物统计"
{
  for d in seed0 seed1 seed2 cbft_study ablation ablation_n9 arch_n9 perclass_arm baseline_gcn; do
    printf "  runs/%-14s %s\n" "$d" "$(find runs/$d -name results.json 2>/dev/null | wc -l)"
  done
  df -h /mnt/c | tail -1
} | tee -a "$LOG"

echo "OK 全部完成" > runs/p3_resume.status
echo "=== P3 RESUMED DONE [$(date +%H:%M:%S)] ==="
