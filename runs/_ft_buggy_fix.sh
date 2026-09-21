#!/usr/bin/env bash
# 补救队列：只跑**缺的**划分种子，且**强制离线**。
#
# 为什么需要它：`finetune_codebert.py` 通过 `transformers` 从 huggingface.co 取
# `microsoft/codebert-base`。本机 HF 缓存**已完整**（snapshots 下 config/tokenizer/vocab/
# merges/pytorch_model.bin 齐全，实测 `HF_HUB_OFFLINE=1` 可正常加载），但 transformers
# 默认仍会**联网重校验**，网络一抖就抛 SSLError 并让整次 40 分钟微调前功尽弃
# （2026-09-21 实测：ss1 就是这么失败的，日志末尾是 huggingface_hub 的 SSLError）。
# ⇒ 缓存齐备时应当**禁止联网**：既快又不受网络影响。
#
# **可重入**：已存在 `encoder/config.json` 的种子直接跳过。
set -u
cd "$(dirname "$0")/.." || exit 1
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
mkdir -p runs/queue_logs
for S in 0 1 2; do
  if [ -f "runs/codebert_ft_buggy/ss$S/encoder/corpus.json" ]; then
    echo "✓ ss$S 已存在，跳过"; continue
  fi
  echo "=== [$(date +%H:%M:%S)] 补救 finetune ss$S（离线）==="
  if python scripts/finetune_codebert.py \
        --split-seed "$S" \
        --split-dir products/alldata/splits/withbuggy_snapshot \
        --graph-dir products/alldata/graphs \
        --epochs 16 --patience 4 \
        --out-root runs/codebert_ft_buggy \
        > "runs/queue_logs/ft_buggy_ss$S.log" 2>&1; then
    echo "  ✓ ss$S"
  else
    echo "  ✗ ss$S 失败，末尾 12 行："; tail -12 "runs/queue_logs/ft_buggy_ss$S.log"
  fi
done
echo "=== [$(date +%H:%M:%S)] 补救队列结束 ==="
