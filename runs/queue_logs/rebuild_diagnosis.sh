#!/usr/bin/env bash
# 重建 42 个消融臂的 diagnosis_summary.json（原文件 seeds 只有 [2]，n=1）。
# 零推理：test_probs.pt / val_best_probs.pt 均在，diagnose.py 走缓存。
# 每臂的 graph_dir/split_dir/label_* 一律从 seed0/config.json 读，不手抄。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
FAIL=0
for base in runs/ablation runs/ablation_aug; do
  for arm in $(ls "$base"); do
    d="$base/$arm"
    [ -f "$d/seed0/config.json" ] || { echo "SKIP $d（无 seed0/config.json）"; continue; }
    gd=$(python3 -c "import json;print(json.load(open('$d/seed0/config.json'))['args']['graph_dir'])")
    sd=$(python3 -c "import json;print(json.load(open('$d/seed0/config.json'))['args']['split_dir'])")
    extra=""
    lf=$(python3 -c "import json;print(json.load(open('$d/seed0/config.json'))['args'].get('label_file') or '')")
    lm=$(python3 -c "import json;print(json.load(open('$d/seed0/config.json'))['args'].get('label_key_mode') or '')")
    [ -n "$lf" ] && extra="$extra --label-file $lf"
    [ -n "$lm" ] && extra="$extra --label-key-mode $lm"
    python scripts/diagnose.py --runs-dir "$d" --graph-dir "$gd" --split-dir "$sd" $extra \
        > /dev/null 2>&1 || { echo "FAIL $d"; FAIL=$((FAIL+1)); }
  done
  echo "done $base"
done
echo "REBUILD_DIAGNOSIS_DONE failures=$FAIL"
