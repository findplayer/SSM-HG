#!/usr/bin/env bash
# 任务2：按含 buggy 的新划分，逐划分种子重微调编码器（串行，GPU 只有一张）。
# epoch 预算取 P0 探针结论：正典 --epochs 5 时 val macro-F1 仍在单调上升，
# 跑到 12 轮 +0.178 仍未收敛 ⇒ 本臂用 --epochs 16 --patience 4。
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p runs/queue_logs
for S in 0 1 2; do
  echo "=== [$(date +%H:%M:%S)] finetune ss$S ==="
  if python scripts/finetune_codebert.py \
        --split-seed "$S" \
        --split-dir products/alldata/splits/withbuggy_snapshot \
        --graph-dir products/alldata/graphs \
        --epochs 16 --patience 4 \
        --out-root runs/codebert_ft_buggy \
        > "runs/queue_logs/ft_buggy_ss$S.log" 2>&1; then
    echo "  ✓ ss$S"
  else
    echo "  ✗ ss$S 失败，末尾 15 行："; tail -15 "runs/queue_logs/ft_buggy_ss$S.log"
  fi
done
echo "=== [$(date +%H:%M:%S)] 全部完成 ==="
