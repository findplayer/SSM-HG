#!/usr/bin/env bash
# 剩余消融项的**串行队列**（数据侧 + 训练侧），一次跑完一批，日志逐项落盘。
#
# 为什么要有它：本批步骤之间有**硬顺序**，而 GPU 只有一张（8.6 GB，实测并发会 OOM）：
#   造变体(M2→M1/PyG→M3) → 训练 → evaluate/summarize；且 `cb_ft` 必须先微调出编码器。
# 手工一条条敲既容易漏步，也会让"跑到哪了"变成口头状态；写成脚本则**可重入、可审计**。
#
# **可重入**：每一步开工前先看产物在不在——
#   变体看 `variant.json`、微调看 `encoder/config.json`、训练看 `run_ablation.py` 自带的
#   `best.pt 已存在则跳过`。故中途被打断（含 `wsl --shutdown`）后直接重跑本脚本即可，
#   已完成的步骤不会重做。
#   唯一的例外是**变体构建被中断**：那时目录里是半成品但没有 `variant.json`，
#   本脚本会带 `--overwrite` 重跑该变体（`build_graph_variant.py` 自己会先清空该目录）。
#
# 用法（从仓库根目录运行）：
#   bash scripts/run_remaining_ablations.sh main          # ① 主库
#   bash scripts/run_remaining_ablations.sh aug           # ② 增强集
#   STEPS=finetune bash scripts/run_remaining_ablations.sh main   # 只跑某一步
set -u
cd "$(dirname "$0")/.." || exit 1

GROUP="${1:-main}"
LOG_DIR=runs/queue_logs
mkdir -p "$LOG_DIR"

case "$GROUP" in
  main)
    DS=alldata; BASE=runs/seed0/config.json; ROOT=runs/ablation
    FT_ARGS=(--graph-dir products/alldata/graphs --split-dir products/alldata/splits) ;;
  aug)
    DS=augmentation; BASE=runs/augmentation/seed0/config.json; ROOT=runs/ablation_aug
    # ② 的标签口径与 ① 不同（单标签语料 + 修好的标签文件），必须逐字沿用其正典 config
    # 里的那一对参数，否则微调用的标签会与下游 GNN 的标签**不是同一套**。
    FT_ARGS=(--graph-dir products/augmentation/graphs --split-dir products/augmentation/splits
             --label-file products/augmentation/contract_labels_repaired.json
             --label-key-mode stem) ;;
  *) echo "用法: $0 {main|aug}"; exit 2 ;;
esac

# 编码器根目录**按语料隔离**（与 finetune_codebert.default_out_root 同一约定）。
FT_ROOT="runs/codebert_ft/$DS"

WANT="${STEPS:-variant_rev,train_rev,variant_unlimited,train_unlimited,finetune,variant_ft,train_ft}"
step_enabled() { case ",$WANT," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

run() {                    # run <日志名> <命令…>
  local name="$1"; shift
  echo "=== [$(date +%H:%M:%S)] $GROUP/$name ==="
  if "$@" > "$LOG_DIR/${GROUP}_${name}.log" 2>&1; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name 失败，末尾 20 行："
    tail -20 "$LOG_DIR/${GROUP}_${name}.log"
    return 1
  fi
}

build_variant() {          # build_variant <变体名> <目录名> [额外参数…]
  local v="$1" dir="$2"; shift 2
  if [ -f "products/$DS/graph_variants/$dir/variant.json" ]; then
    echo "=== $GROUP/variant_$dir：已存在，跳过 ==="
    return 0
  fi
  run "variant_$dir" python scripts/build_graph_variant.py --variant "$v" --dataset "$DS" \
      --overwrite "$@"
}

fail=0
# ---- 1) CALLBACK_RISK_REV ----
step_enabled variant_rev && { build_variant callback_rev callback_rev || fail=1; }
step_enabled train_rev && [ $fail -eq 0 ] && { run train_rev python scripts/run_ablation.py \
    --only cb_rev --keep-going --base-config "$BASE" --root "$ROOT" || fail=1; }

# ---- 2) CALLBACK_RISK 上限 ----
step_enabled variant_unlimited && [ $fail -eq 0 ] && { build_variant callback_unlimited callback_unlimited || fail=1; }
step_enabled train_unlimited && [ $fail -eq 0 ] && { run train_unlimited python scripts/run_ablation.py \
    --only cb_unlimited --keep-going --base-config "$BASE" --root "$ROOT" || fail=1; }

# ---- 3) 微调 CodeBERT（每个划分种子一个编码器）→ 重编码 → 训练 ----
if step_enabled finetune && [ $fail -eq 0 ]; then
  for S in 0 1 2; do
    # ⚠ 编码器路径**带语料维度**（runs/codebert_ft/<语料>/ss{S}）。原先是共用的
    #   `runs/codebert_ft/ss{S}`，会让后跑的语料看到先跑的编码器而跳过微调，
    #   再拿别的语料微调出来的编码器去重编码——不报错，但消融答错了问题。
    if [ -f "$FT_ROOT/ss${S}/encoder/corpus.json" ]; then
      echo "=== $GROUP/finetune ss$S：已存在，跳过 ==="
    else
      run "finetune_ss$S" python scripts/finetune_codebert.py --split-seed "$S" \
        "${FT_ARGS[@]}" || { fail=1; break; }
    fi
  done
fi
if step_enabled variant_ft && [ $fail -eq 0 ]; then
  for S in 0 1 2; do
    build_variant cb_ft "cb_ft_ss$S" --split-seed "$S" || { fail=1; break; }
  done
fi
step_enabled train_ft && [ $fail -eq 0 ] && { run train_ft python scripts/run_ablation.py \
    --only cb_ft --keep-going --base-config "$BASE" --root "$ROOT" || fail=1; }

echo "=== [$(date +%H:%M:%S)] $GROUP 队列结束，fail=$fail ==="
exit $fail
