#!/usr/bin/env bash
# 任务2 编排：等 3 个编码器齐 → 补造 ss1/ss2 的 M3 变体（ss0 已并行造好）→ 训练/评测/聚合。
# **可重入**：变体看 variant.json、训练看 run_ablation 式的产物判据；已存在的步骤跳过。
set -u
cd "$(dirname "$0")/.." || exit 1
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
mkdir -p runs/queue_logs

echo "=== [$(date +%H:%M:%S)] 等 3 个编码器 ==="
for S in 0 1 2; do
  until [ -f "runs/codebert_ft_buggy/ss$S/encoder/corpus.json" ]; do sleep 20; done
  echo "  ✓ encoder ss$S"
done

for S in 1 2; do
  V="products/alldata/graphs_ft_buggy/cb_ft_ss$S"
  if [ -f "$V/variant.json" ]; then echo "✓ variant ss$S 已存在，跳过"; continue; fi
  echo "=== [$(date +%H:%M:%S)] build variant ss$S ==="
  if python scripts/build_graph_variant.py --variant cb_ft --dataset alldata --split-seed $S \
        --encoder "runs/codebert_ft_buggy/ss$S/encoder" \
        --variants-root products/alldata/graphs_ft_buggy \
        > "runs/queue_logs/variant_buggy_ss$S.log" 2>&1; then
    echo "  ✓ variant ss$S"
  else
    echo "  ✗ variant ss$S 失败"; tail -20 "runs/queue_logs/variant_buggy_ss$S.log"; exit 1
  fi
done

echo "=== [$(date +%H:%M:%S)] 训练 + 评测 + 聚合 ==="
python scripts/run_buggy_canon.py --steps train eval summarize || exit 1
echo "=== [$(date +%H:%M:%S)] PIPELINE DONE ==="
