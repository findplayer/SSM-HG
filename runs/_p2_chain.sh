#!/usr/bin/env bash
# P2 全链**单脚本串行**：编码器重微调 ×3 → M3 重编码（新树）→ GNN 重训（--deterministic）
#                 → evaluate → diagnose → summarize → 闸门。
#
# 🔴🔴 **本脚本有两个已实测的 bug，重跑前必读（详细复盘见 decisions.md §54 / log.md 同日条目）**：
#   ① **`--out-dir` 语义错**：`train.py` 的 `--out-dir` 是「**父目录**」，它会自己再拼一层 `seed{S}`。
#      本脚本传的是 `--out-dir runs/p2_canon/seed${S}` ⇒ 产物落到 `runs/p2_canon/seed0/seed0/`，
#      而 `evaluate.py` 找 `runs/p2_canon/seed0/best.pt` ⇒ **三个种子的 evaluate/diagnose 全部崩溃**
#      （训练本身全成功、产物一个没丢，抹平那一层后补评测即可，见 `runs/_p2_finish.sh`）。
#      **正确写法** = `--out-dir runs/p2_canon`（父目录），产物自动落 `runs/p2_canon/seed{S}/`。
#   ② **退出码捕获错**：`echo "... rc=$? ..."` 里的 `$?` **永远得 0**——同一行里
#      `$(date +%H:%M:%S)` 这个命令替换**先执行**，把 `$?` 覆盖成了 date 的退出码。
#      后果：三个 evaluate 全崩、闸门因产物缺失返回 3，日志里却写着「闸门 rc=0」。
#      ⇒ 纪律：**退出码必须紧跟命令单独取** `rc=$?`，绝不塞进带命令替换的 echo 里。
#
# 🔴 为什么是一个脚本而不是三条用 `pgrep` 串起来的队列（2026-09-24 踩到）：
#    `pgrep -f <模式>` 匹配**整条命令行**。用 `nohup bash x.sh &` 从 harness shell 启动时，
#    **那个 shell 的命令行里含脚本全文**（heredoc），只要脚本注释里出现别的脚本名，
#    `pgrep -f` 就会**永久命中该 shell** ⇒ 等待循环永不退出、静默空等（本次实测空等 1h37m）。
#    ⇒ 纪律：串行链一律写成**一个脚本**，不要用 `pgrep` 做进程间等待。
#
# 产物一律另开目录：**runs/codebert_ft/、products/alldata/graphs_ft/、runs/seed{0,1,2}/ 零改动**。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
echo "=== [$(date +%H:%M:%S)] P2 全链启动 ==="

# ---------- 阶段 1：编码器重微调（20 轮 + SWA 选点）----------
for S in 0 1 2; do
  echo "=== [$(date +%H:%M:%S)] P2 encoder ss${S} start ==="
  ${PY} scripts/finetune_codebert.py --split-seed "${S}" \
      --out-root runs/codebert_ft_p2 --epochs 20 --patience 4 --swa-start 16
  echo "=== [$(date +%H:%M:%S)] P2 encoder ss${S} rc=$? ==="
done
echo "=== [$(date +%H:%M:%S)] P2 ENCODERS STAGE END ==="

# 硬前置：三个编码器必须都在，否则 M3 会以难懂的方式失败
for S in 0 1 2; do
  if [ ! -f "runs/codebert_ft_p2/ss${S}/encoder/config.json" ]; then
    echo "!!! 缺 runs/codebert_ft_p2/ss${S}/encoder/config.json ⇒ 中止，不进 M3"
    exit 4
  fi
done
echo "=== [$(date +%H:%M:%S)] 三个编码器齐备 ==="

# ---------- 阶段 2/3：M3 重编码 → GNN 重训 → 评测 ----------
for S in 0 1 2; do
  GD="products/alldata/graphs_ft_p2/cb_ft_ss${S}"
  echo "=== [$(date +%H:%M:%S)] ss${S} M3 重编码 -> ${GD} ==="
  ${PY} scripts/build_graph_variant.py --variant cb_ft --dataset alldata --split-seed "${S}" \
      --encoder "runs/codebert_ft_p2/ss${S}/encoder" \
      --variants-root products/alldata/graphs_ft_p2
  echo "=== [$(date +%H:%M:%S)] ss${S} M3 rc=$? ==="
  echo "=== [$(date +%H:%M:%S)] ss${S} GNN 重训（--deterministic）==="
  ${PY} scripts/train.py --seed "${S}" --split-seed "${S}" \
      --graph-dir "${GD}" --split-dir products/alldata/splits \
      --out-dir "runs/p2_canon/seed${S}" --deterministic
  echo "=== [$(date +%H:%M:%S)] ss${S} evaluate + diagnose ==="
  ${PY} scripts/evaluate.py --seed "${S}" --runs-dir runs/p2_canon \
      --graph-dir "${GD}" --split-dir products/alldata/splits
  ${PY} scripts/diagnose.py --seed "${S}" --runs-dir runs/p2_canon \
      --graph-dir "${GD}" --split-dir products/alldata/splits
  echo "=== [$(date +%H:%M:%S)] ss${S} STAGE rc=$? ==="
done

${PY} scripts/evaluate.py --summarize --runs-dir runs/p2_canon
echo "=== [$(date +%H:%M:%S)] 闸门 ==="
${PY} scripts/check_encoder_promotion.py --out experiments/encoder_promotion_gate.md
echo "=== [$(date +%H:%M:%S)] 闸门 rc=$?（0=三门前过 / 1=有门未过）==="
echo "=== P2 PIPELINE DONE [$(date +%H:%M:%S)] ==="
