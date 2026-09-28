#!/usr/bin/env bash
# 编码器换代落地 · 阶段 3：① 主库下游全量重跑（在新正典 graphs_ft_p2 上）
#
# 🔴 两条纪律（`_p2_chain.sh` 已各栽过一次，此处照抄）：
#   ① **串行链一律写成"一个脚本"**，绝不用 `pgrep -f` 做进程间等待 ——
#      `pgrep -f` 匹配**整条命令行**，harness shell 的命令行含本脚本全文（heredoc），
#      只要注释里出现别的脚本名就会**永久命中该 shell** ⇒ 等待循环静默空等（实测 1h37m）。
#   ② **退出码必须紧跟命令单独取** `rc=$?`，绝不塞进带 `$(date …)` 的 echo ——
#      同一行里命令替换先执行，会把 `$?` 覆盖成 date 的退出码（实测把 rc=1 记成 rc=0）。
#
# 产物一律另开目录；`runs/prior_canon37/`、`runs/prior_buggy16/`、`products/alldata/graphs_ft/`
# 与 `runs/codebert_ft/` **只读**，绝不写。
#
# ⚠ 本脚本**只产 run 与 DIVE 产物**；交付表的重生成在阶段 5，不在这里。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
LOG=runs/p3_chain.log
mkdir -p runs/queue_logs

step() { echo "=== [$(date +%H:%M:%S)] $* ==="; }
fail() { echo "!!! [$(date +%H:%M:%S)] 中止：$*"; exit 1; }

echo "=== [$(date +%H:%M:%S)] P3 全链启动 ==="

# ---------- 前置：新正典与新树必须在位 ----------
for S in 0 1 2; do
  [ -f "runs/seed${S}/config.json" ] || fail "缺 runs/seed${S}/config.json"
  [ -d "products/alldata/graphs_ft_p2/cb_ft_ss${S}" ] || fail "缺 graphs_ft_p2/cb_ft_ss${S}"
done
step "前置通过：正典 3 种子 + 新树 3 套齐备"

# ---------- 3.1 结构变体树（新根下重建 cb_rev / cb_unlimited）----------
step "3.1 build_ft_edge_variants --layout canon_p2（约 1.1 h）"
${PY} scripts/build_ft_edge_variants.py --dataset alldata --layout canon_p2 >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.1 build_ft_edge_variants rc=$rc（见 $LOG）"
for S in 0 1 2; do
  for V in cb_rev cb_unlimited; do
    [ -d "products/alldata/graphs_ft_p2/graph_variants/${V}_ss${S}" ] \
      || fail "3.1 产物缺失：graphs_ft_p2/graph_variants/${V}_ss${S}"
  done
done
step "3.1 完成：6 个变体树齐备"

# ---------- 3.2 §36 配对研究的 9 对基线（n=9 消融的基线来源）----------
step "3.2 run_cbft_study（18 run）"
${PY} scripts/run_cbft_study.py >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.2 run_cbft_study rc=$rc（见 $LOG）"
step "3.2 完成"

# ---------- 3.3 消融 n=3（21 臂 × 3 种子）----------
step "3.3 run_ablation --keep-going（63 run）"
${PY} scripts/run_ablation.py --keep-going >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.3 run_ablation rc=$rc（见 $LOG）"
step "3.3 完成"

# ---------- 3.4 消融 n=9 + 架构族 + 参数量匹配（对角复用 3.3 与 3.2 的产物）----------
# ⚠ 必须 --group main：② 增强集**未换代**（用户裁定），跑 both 会污染 ② 的目录。
step "3.4 run_ablation_n9 --group main --with-dose-arms --with-arch-arms --with-pm-arms（约 1.2 h）"
${PY} scripts/run_ablation_n9.py --group main \
    --with-dose-arms --with-arch-arms --with-pm-arms >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.4 run_ablation_n9 rc=$rc（见 $LOG；若为复用资格不成立，查 3.3 是否有臂失败）"
step "3.4 完成"

# ---------- 3.5 GCN 对照臂（逐类 F1 表的输入）----------
# 命令逐字取自 experiments/gcn_baseline_and_per_class_f1.md:197-215（该表的产出命令）。
# ⚠ 该链是手敲的（不走 run_arch_baselines.py：后者的 out_dir 会多一层 <conv>/）。
step "3.5 GCN 对照臂（runs/baseline_gcn，3 seed）"
for s in 0 1 2; do
  GD="products/alldata/graphs_ft_p2/cb_ft_ss${s}"
  ${PY} scripts/train.py --seed "$s" --split-seed "$s" --conv gcn \
      --graph-dir "${GD}" --out-dir runs/baseline_gcn >>"$LOG" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || fail "3.5 train gcn seed${s} rc=$rc"
  ${PY} scripts/evaluate.py --seed "$s" --runs-dir runs/baseline_gcn \
      --graph-dir "${GD}" --split-dir products/alldata/splits >>"$LOG" 2>&1
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
      --split-dir products/alldata/splits >>"$LOG" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || fail "3.5 diagnose gcn seed${s} rc=$rc"
done
${PY} scripts/diagnose.py --runs-dir runs/baseline_gcn \
    --graph-dir products/alldata/graphs_ft_p2/cb_ft_ss0 \
    --split-dir products/alldata/splits >>"$LOG" 2>&1   # 聚合（此时全命中缓存）
rc=$?
[ "$rc" -eq 0 ] || fail "3.5 diagnose gcn 聚合 rc=$rc"
step "3.5 完成"

# ---------- 3.6 逐类独立二分类器（7 类 + ANY_union，2 个 cap = 45 run）----------
step "3.6 run_perclass_arm --steps all（45 run，约 25 min）"
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
    --split-dir products/alldata/splits >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.7 diagnose --summarize rc=$rc"
step "3.7 完成"

# ---------- 3.8 DIVE / SolidiFI 外部集：① 用新编码器重编码 ----------
# ⚠ ② 侧（graphs_ft_aug）也会被本步走过，但其编码器未换代 ⇒ 输入逐字不变、输出幂等。
# ⚠ step_features 的 M3 已补 `--force`（否则会静默复用旧编码器的 `_cb.pt`）。
step "3.8 build_dive_external_set（重编码 ① 的 DIVE/SolidiFI 特征，约 40 min）"
${PY} scripts/build_dive_external_set.py --steps all >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.8 build_dive_external_set rc=$rc（见 $LOG）"
step "3.8 完成"

# ---------- 收尾统计 ----------
step "P3 产物统计"
{
  echo "--- 各区位 run 数（results.json 计数）---"
  for d in seed0 seed1 seed2 cbft_study ablation ablation_n9 arch_n9 perclass_arm baseline_gcn; do
    printf "  runs/%-14s %s\n" "$d" "$(find runs/$d -name results.json 2>/dev/null | wc -l)"
  done
  echo "--- 磁盘 ---"
  df -h /mnt/c | tail -1
} | tee -a "$LOG"

echo "=== P3 PIPELINE DONE [$(date +%H:%M:%S)] ==="
