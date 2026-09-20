#!/usr/bin/env bash
# GCN 基线的诊断/概率缓存：逐 seed 传**匹配的**编码器树，再聚合（缓存命中后 graph_dir 不再影响数值）。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
for s in 0 1 2; do
  python scripts/diagnose.py --runs-dir runs/baseline_gcn --seed $s \
      --graph-dir products/alldata/graphs_ft/ss$s --split-dir products/alldata/splits >/dev/null 2>&1 \
    || echo "FAIL main s$s"
done
python scripts/diagnose.py --runs-dir runs/baseline_gcn \
    --graph-dir products/alldata/graphs_ft/ss0 --split-dir products/alldata/splits >/dev/null 2>&1 || echo "FAIL main agg"

for s in 0 1 2; do
  python scripts/diagnose.py --runs-dir runs/baseline_gcn_aug --seed $s \
      --graph-dir products/augmentation/graphs_ft/ss$s --split-dir products/augmentation/splits \
      --label-file products/augmentation/contract_labels_repaired.json --label-key-mode stem >/dev/null 2>&1 \
    || echo "FAIL aug s$s"
done
python scripts/diagnose.py --runs-dir runs/baseline_gcn_aug \
    --graph-dir products/augmentation/graphs_ft/ss0 --split-dir products/augmentation/splits \
    --label-file products/augmentation/contract_labels_repaired.json --label-key-mode stem >/dev/null 2>&1 || echo "FAIL aug agg"
echo "GCN_DIAGNOSE_DONE"
