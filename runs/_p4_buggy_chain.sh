#!/usr/bin/env bash
# 编码器换代落地 · 阶段 4：任务 2（池 497）正典同步换代 16 轮 → 20 轮
#
# 🔴 换代的**理由与 ① 不同、更硬**：`decisions.md` §43 起该段的立论是「池 497 vs 池 453」，
#    但换代前两侧 epoch 预算是 **16 vs 5** ⇒ 实际是**双变量**（池 + 训练量），不可分离。
#    两侧都对齐到 20 轮才只剩「池」一个变量。
# ⚠ **不加 `--swa-start`**：① 实测 `n_averaged = 0/0/2`、三种子 `selection` 全为 `best_epoch`
#    ⇒ 增益来自 epoch 预算而非 SWA。为与 ① 逐字同口径，这里也不加（否则又引入新变量）。
#
# 🔴 纪律同阶段 3：单脚本串行；`rc=$?` 紧跟命令单独取。
# 旧一代已归档到 `runs/prior_buggy16/`（`buggy_canon` / `ablation_buggy` / `baseline_arch_buggy`）。
# `products/alldata/graphs_ft_buggy/` 与 `runs/codebert_ft_buggy/` **原地保留、只读**。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
LOG=runs/p4_buggy_chain.log
SPLITS=products/alldata/splits/withbuggy_snapshot

step() { echo "=== [$(date +%H:%M:%S)] $* ==="; }
fail() { echo "!!! [$(date +%H:%M:%S)] 中止：$*"; echo "FAIL $*" > runs/p4_buggy_chain.status; exit 1; }

echo "=== [$(date +%H:%M:%S)] P4 buggy 换代链启动 ==="

# ---------- 4.1 编码器重微调（20 轮，约 1.7 h）----------
# ⚠ `--graph-dir` 是**冻结树**（590 图）：编码器只借它取节点文本与标签，与划分无关。
# ⚠ `--split-dir` 必须显式传 `withbuggy_snapshot`（默认是 ① 的 `splits/`）——
#   传错会静默用错划分的标签微调，**不报错**。
step "4.1 finetune_codebert ×3（--epochs 20 --patience 4，约 1.7 h）"
for S in 0 1 2; do
  ${PY} scripts/finetune_codebert.py --split-seed "${S}" \
      --split-dir "${SPLITS}" --graph-dir products/alldata/graphs \
      --epochs 20 --patience 4 \
      --out-root runs/codebert_ft_buggy_p2 >>"$LOG" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || fail "4.1 finetune ss${S} rc=$rc（见 $LOG）"
  echo "    ss${S} 完成 $(date +%H:%M:%S)"
done
for S in 0 1 2; do
  [ -f "runs/codebert_ft_buggy_p2/ss${S}/encoder/corpus.json" ] \
    || fail "4.1 缺 ss${S}/encoder/corpus.json"
done
step "4.1 完成：三个编码器齐备"

# ---------- 4.2 M3 重编码树 ----------
# ⚠ `run_buggy_canon.py --steps variant` 用的是它自己那份四路径常量（唯一真源），
#   与手敲 `build_graph_variant` 等价；`--skip-preflight` 是因为树还没建。
step "4.2 run_buggy_canon --steps variant（M3 重编码 590 图）"
${PY} scripts/run_buggy_canon.py --steps variant --skip-preflight >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "4.2 variant rc=$rc（见 $LOG）"
for S in 0 1 2; do
  N=$(ls products/alldata/graphs_ft_buggy_p2/cb_ft_ss${S}/*_feat.pt 2>/dev/null | wc -l)
  [ "$N" -eq 590 ] || fail "4.2 cb_ft_ss${S} 图数 ${N} ≠ 590"
done
step "4.2 完成：三棵树各 590 图"

# ---------- 4.3 结构变体（buggy_p2 layout）----------
step "4.3 build_ft_edge_variants --layout buggy_p2（约 10 min）"
${PY} scripts/build_ft_edge_variants.py --dataset alldata --layout buggy_p2 >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "4.3 ftvar rc=$rc（见 $LOG）"
for S in 0 1 2; do
  for V in cb_rev cb_unlimited; do
    [ -d "products/alldata/graphs_ft_buggy_p2/graph_variants/${V}_ss${S}" ] \
      || fail "4.3 产物缺失：${V}_ss${S}"
  done
done
step "4.3 完成"

# ---------- 4.4 正典 GNN ----------
# ⚠ `diagnose` 不可省：`test_probs.pt` / `diagnosis.json` **只由 diagnose.py 写**，
#   而 `collect_three_caliber_tables.py` 读的正是 `test_probs.pt`
#   ⇒ 漏掉它不是报错，而是整列 `—`。
step "4.4 run_buggy_canon --steps train eval diagnose summarize"
${PY} scripts/run_buggy_canon.py --steps train eval diagnose summarize >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "4.4 buggy_canon rc=$rc（见 $LOG）"
for S in 0 1 2; do
  for f in config.json results.json test_probs.pt val_best_probs.pt thresholds.json diagnosis.json; do
    [ -f "runs/buggy_canon/seed${S}/${f}" ] || fail "4.4 缺 runs/buggy_canon/seed${S}/${f}"
  done
done
step "4.4 完成"

# ---------- 4.5 消融（21 臂 × 3 种子）----------
# ⚠ `--root` 必须显式传（默认是 ① 的 `runs/ablation`）。
# ⚠ `--base-config` 指向新 buggy 正典 ⇒ 变体根自动派生出 `graphs_ft_buggy_p2/graph_variants`
#   （`run_ablation.variants_root_of`），并由新增的硬守卫确认它存在。
step "4.5 run_ablation --root runs/ablation_buggy（63 run，约 25 min）"
${PY} scripts/run_ablation.py --base-config runs/buggy_canon/seed0/config.json \
    --root runs/ablation_buggy --keep-going >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "4.5 ablation_buggy rc=$rc（见 $LOG）"
step "4.5 完成"

# ---------- 4.6 架构基线族（pool 497 侧）----------
step "4.6 run_arch_baselines --graph-root graphs_ft_buggy_p2（9 run）"
${PY} scripts/run_arch_baselines.py \
    --graph-root products/alldata/graphs_ft_buggy_p2 \
    --split-dir "${SPLITS}" \
    --runs-root runs/baseline_arch_buggy >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "4.6 arch_buggy rc=$rc（见 $LOG）"
step "4.6 完成"

# ---------- 4.7 三条论文基线：**本次一律不重跑**（用户 2026-09-25 裁定）----------
# 实测依据（逐条）：MVD-HG 从 `.sol` 自建 compact AST、EGFL 走 `solc --bin` 反汇编
#   —— 两者**根本不读 `_cb.pt`**；MANDO 只读 `_pyg.pt` 与 `_feat.pt::type_id`
#   （**结构通道**，三种子逐位相同、与编码器无关）；Slither 只吃源码。
# ⇒ 换 20 轮编码器**不改变它们的任何输入**，数字逐位不变。
# MANDO 重跑本可让产物里的 `graph_dir` 从旧树改记到新树（纯 provenance 刷新，约 30 min），
#   但用户裁定**不重跑** ⇒ `eval_results/baseline/mando_buggy/seed{S}/config.json`
#   仍记着 `products/alldata/graphs_ft_buggy/cb_ft_ss{S}`（旧的 16 轮档）。
#   ⚠ **这是一处必须随表披露的口径**：该段的 MANDO 行其 `graph_dir` 指向的是**已降为旧档**
#   的树；**数字不受影响**（它只用结构通道），但读表者会看到路径与其余行不同。
#   已在 `experiments/baseline_three_caliber_tables.md` 的「三、」段口径注里写入。
step "4.7 按裁定跳过（三条论文基线均无需重跑，见脚本注释）"


# ---------- 收尾统计 ----------
step "P4 产物统计"
{
  echo "--- buggy 侧 run 数 ---"
  for d in buggy_canon ablation_buggy baseline_arch_buggy; do
    printf "  runs/%-22s %s\n" "$d" "$(find runs/$d -name results.json 2>/dev/null | wc -l)"
  done
  echo "--- 编码器 best_val_macro_f1（应显著高于旧的 16 轮档）---"
  for S in 0 1 2; do
    ${PY} -c "
import json;d=json.load(open('runs/codebert_ft_buggy_p2/ss${S}/config.json'))
print('  ss${S}: best_val_macro_f1=%.4f  epoch=%s  epochs=%s' % (
  d.get('best_val_macro_f1',-1), d.get('best_epoch'), d['args']['epochs']))"
  done
  echo "--- 磁盘 ---"
  df -h /mnt/c | tail -1
} | tee -a "$LOG"

echo "OK 全部完成" > runs/p4_buggy_chain.status
echo "=== P4 PIPELINE DONE [$(date +%H:%M:%S)] ==="
