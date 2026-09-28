#!/usr/bin/env bash
# P2 收尾：**只补跑评测段**（evaluate → diagnose → summarize → 闸门）。
#
# 🔴 为什么要单独一个脚本（2026-09-24 记）：
#   `runs/_p2_chain.sh` 跑完了训练，但 `evaluate.py` 全部崩溃。根因是**我的脚本拼错了产出目录**：
#   `train.py` 的 `--out-dir` 语义是「**父目录**」，它自己会再拼一层 `seed{S}`。
#   我传了 `--out-dir runs/p2_canon/seed${S}` ⇒ 产物落到 `runs/p2_canon/seed{S}/seed{S}/`，
#   而 `evaluate.py` 找的是 `runs/p2_canon/seed{S}/best.pt` ⇒ FileNotFoundError。
#   处置：把多出来的一层抹平（产物**一个都没丢**，训练本身完全成功），再只补评测段。
#   ⚠ 抹平后 `config.json::args.out_dir`（记的是传参值 `runs/p2_canon/seed{S}`）
#     与实际位置**恰好一致**了，provenance 自洽。
#
# 🔴 第二个 bug（同一个脚本里）：`echo "... rc=$? ..."` 里的 `$?` **永远得 0**——
#   同一行里 `$(date +%H:%M:%S)` 这个命令替换先执行，把 `$?` 覆盖成了 date 的退出码。
#   于是上一轮三个 evaluate 全崩、闸门因产物缺失返回 3，日志里却写着「闸门 rc=0」。
#   ⇒ 纪律：**退出码必须紧跟在命令之后单独取** `rc=$?`，再 echo；不要塞进带命令替换的 echo 里。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
echo "=== [$(date +%H:%M:%S)] P2 收尾启动（仅评测段）==="

for S in 0 1 2; do
  GD="products/alldata/graphs_ft_p2/cb_ft_ss${S}"
  echo "=== [$(date +%H:%M:%S)] ss${S} evaluate ==="
  ${PY} scripts/evaluate.py --seed "${S}" --runs-dir runs/p2_canon \
      --graph-dir "${GD}" --split-dir products/alldata/splits
  rc=$?
  echo "    ss${S} evaluate rc=${rc}"
  if [ "${rc}" -ne 0 ]; then echo "!!! evaluate 失败，中止"; exit 5; fi

  echo "=== [$(date +%H:%M:%S)] ss${S} diagnose ==="
  ${PY} scripts/diagnose.py --seed "${S}" --runs-dir runs/p2_canon \
      --graph-dir "${GD}" --split-dir products/alldata/splits
  rc=$?
  echo "    ss${S} diagnose rc=${rc}"
  if [ "${rc}" -ne 0 ]; then echo "!!! diagnose 失败，中止"; exit 6; fi
done

echo "=== [$(date +%H:%M:%S)] summarize ==="
${PY} scripts/evaluate.py --summarize --runs-dir runs/p2_canon
rc=$?
echo "    summarize rc=${rc}"

echo "=== [$(date +%H:%M:%S)] 闸门 ==="
${PY} scripts/check_encoder_promotion.py --out experiments/encoder_promotion_gate.md
gate_rc=$?
echo "    闸门 rc=${gate_rc}（0=三门前过 / 1=有门未过 / 3=产物未齐）"

echo "=== P2 FINISH DONE [$(date +%H:%M:%S)] gate_rc=${gate_rc} ==="
