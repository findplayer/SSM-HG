#!/usr/bin/env bash
# GCN 基线（关系盲，---conv gcn）：①②各 3 种子。唯一变量 = conv（rgcn → gcn）。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
FAIL=0
for s in 0 1 2; do
  echo "=== ① seed$s train ==="
  python scripts/train.py --seed $s --split-seed $s --conv gcn \
      --graph-dir products/alldata/graphs_ft/ss$s --out-dir runs/baseline_gcn || FAIL=$((FAIL+1))
  echo "=== ① seed$s eval ==="
  python scripts/evaluate.py --seed $s --runs-dir runs/baseline_gcn \
      --graph-dir products/alldata/graphs_ft/ss$s --split-dir products/alldata/splits || FAIL=$((FAIL+1))
done
python scripts/evaluate.py --summarize --runs-dir runs/baseline_gcn || FAIL=$((FAIL+1))

for s in 0 1 2; do
  echo "=== ② seed$s train ==="
  python scripts/train.py --seed $s --split-seed $s --conv gcn \
      --graph-dir products/augmentation/graphs_ft/ss$s --split-dir products/augmentation/splits \
      --label-file products/augmentation/contract_labels_repaired.json --label-key-mode stem \
      --out-dir runs/baseline_gcn_aug || FAIL=$((FAIL+1))
  echo "=== ② seed$s eval ==="
  python scripts/evaluate.py --seed $s --runs-dir runs/baseline_gcn_aug \
      --graph-dir products/augmentation/graphs_ft/ss$s --split-dir products/augmentation/splits \
      --label-file products/augmentation/contract_labels_repaired.json --label-key-mode stem || FAIL=$((FAIL+1))
done
python scripts/evaluate.py --summarize --runs-dir runs/baseline_gcn_aug || FAIL=$((FAIL+1))
echo "GCN_BASELINE_DONE failures=$FAIL"
