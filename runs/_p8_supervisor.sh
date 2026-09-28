#!/usr/bin/env bash
# `runs/_p8_tools_buggy.sh` 的监护进程（2026-09-27）。
#
# 为什么需要它：v1 死于 WSL 关机（20:23 那次，非 OOM），而作业一旦死掉就**没人把它拉起来**。
# 本监护的作用是「在同一个 WSL uptime 内，作业因任何原因退出就重入」，靠作业自身的
# 可续跑性（每合约增量落盘 + 跳过已 ok）把损失限制在最后几条合约。
#
# 🔴 它**不能**跨越 WSL 重启 —— WSL 一关，Linux 侧一切进程都没了。所以：
#    · 若 WSL 重启过，需要人（或用户）再执行一次本脚本；
#    · 这是刻意的：不写 cron / systemd 开机自启，因为那会越出「只在 runs/ 下留脚本」的边界。
#
# 用法（脱离会话，避免会话结束被 SIGHUP 一起带走）：
#   setsid nohup bash runs/_p8_supervisor.sh < /dev/null > /dev/null 2>&1 &
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
LOG=products/alldata/raw/logs/baseline_buggy/supervisor.log
DONE=runs/_tools_work/_p8_done
LOCK=runs/_tools_work/_p8_supervisor.lock
mkdir -p "$(dirname "$LOG")" runs/_tools_work

log() { echo "=== [$(date +%H:%M:%S)] $* ===" >> "$LOG"; }

# 单实例锁（flock；BSD 风格写法在本机不可靠，直接用 util-linux 的 flock）
exec 9>"$LOCK"
if ! flock -n 9; then log "已有监护在跑（锁 $LOCK 被占）→ 本进程退出"; exit 0; fi

log "监护启动（PID $$，脱离会话）"
for attempt in $(seq 1 200); do
  if [ -f "$DONE" ]; then log "见到 sentinel $DONE → 收工（第 $attempt 次检查）"; exit 0; fi
  f=$(df -m /mnt/c | awk 'NR==2{printf "%d", $4/1024}')
  if [ "$f" -lt 8 ]; then log "🔴 C盘只剩 ${f}G < 8G → 监护停止"; exit 4; fi
  log "第 $attempt 次重入作业（C盘 $(echo "$f")G）"
  bash runs/_p8_tools_buggy.sh
  rc=$?
  log "作业退出 rc=$rc"
  if [ -f "$DONE" ]; then log "作业正常完成 → 收工"; exit 0; fi
  if [ "$rc" -eq 3 ] || [ "$rc" -eq 4 ]; then
    log "🔴 作业以 rc=$rc 主动停止（闸门失败或磁盘不足）—— 不再自动重入，交人判断"; exit "$rc"
  fi
  sleep 20
done
log "🔴 重入 200 次仍未完成 → 停止"
exit 3
