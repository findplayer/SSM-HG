#!/usr/bin/env bash
# Manticore 续跑 v3（2026-09-26 17:2x）。
#
# 🔴 为什么推翻 v1（2 路并行）—— 两次 WSL **整体重启**（15:0x 与 17:02，`PID 1` 启动时间可证）
#    各带走一次续跑，且两次都是**零进度**。三条实测：
#      (a) **内存账**：单路 cgroup 实测 **2.71 GB**（`manticore`+`z3` 的 RSS 之和是 4.4 GB，
#          但共享页被重复计数，cgroup 才是真值）⇒ **2 路 = 5.4 GB**，加 VSCode/Claude ≈2.5 GB
#          = **7.9 GB > 本机 WSL 总内存 7.8 GB** ⇒ 必然压垮 WSL。
#      (b) **上限有效**：`systemd-run --user --scope -p MemoryMax=200M` 下实写 900 MB 的进程被
#          **Killed(137)** ⇒ 用它给本进程加硬上限，越界只杀自己、**不牵连 VSCode**。
#      (c) **落盘间隔**：驱动默认每 10 个合约写一次 ≈ **27 min**，与崩溃间隔同量级
#          ⇒ **永远走不到第一个落盘点**。⇒ `--flush-every 1`（每合约即落盘，最坏丢 1 个）。
#    🔴 上限为何是 **4.5 G**（2026-09-26 再收紧）：基线（VSCode 服务进程等）实测 ≈2.3 GB，
#       若上限取 5 G 则 7.8 − 2.3 − 5.0 = **只剩 0.5 GB**；而全局 OOM 的首选靶子是
#       `systemd --user`（`oom_score_adj=100`，16:59 那次正是它被杀 ⇒ 会**再带走 VSCode**）
#       ⇒ 收到 4.5 G，留 1 GB 余量。
#    ⇒ 取舍：**单路 + 4 GB 上限 + 崩溃自愈**，放弃 2 倍速度换「不把用户的编辑器搞崩」。
#       代价：172 个 × ~163 s ≈ **7.8 h**（v1 是 ~3.9 h）。
#
# 🔴 v2 的 supervisor 有 bug（已修）：循环条件写成「全部 status==ok」，但前 50 个里
#    **7 个 timeout + 1 个 error 永远不会变 ok** ⇒ 会空转到上限再 `rc=3`，把后面的
#    合并/评测整段跳过。**正确判据 = 驱动返回 0**：它返回 0 就说明整份 `--only` 列表都走过了，
#    剩下的都是稳定失败，再跑也不会有新结果。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
LOG=runs/_p7_manticore_finish.log
RC=runs/_p7_manticore_finish.rc
TODO_FILE=runs/_tools_work/_manticore_todo.txt
MEMCAP=4.5G
rm -f "$RC"

python - > "$TODO_FILE" <<'PY'
import json
m = json.load(open('eval_results/baseline/manticore_alldata.json'))
cs = m['contracts']
uni = set()
for seed in (0, 1, 2):
    sp = json.load(open(f'products/alldata/splits/split_seed{seed}.json'))
    uni |= set(sp['val']) | set(sp['test'])
todo = [x for x in sorted(uni) if cs.get(x, {}).get('status') != 'ok']
# 🔴 **排序有讲究**（2026-09-26 实测）：`x in cs` 为真 = **已经试过且失败**（前 50 里的 7 timeout+1 error）。
# 它们会跑满 180 s 预算、内存峰值 ~3.7 GB（新合约只要 ~2.7 GB），且**不产生任何新结果**。
# 把「新合约」排在前面 = ① 内存压力只出现在末尾；② 万一又被打断，先拿到的是**有新信息的那批**。
todo.sort(key=lambda x: (x in cs, x))
for b in todo:
    print(b)
PY
mapfile -t TODO < "$TODO_FILE"
N=${#TODO[@]}
echo "=== [$(date +%H:%M:%S)] v3 单路续跑开始：待跑 $N 个，内存上限 $MEMCAP，flush-every=1 ===" >> "$LOG"

mem() { awk '/MemAvailable/{printf "%.1f", $2/1048576}' /proc/meminfo; }
# 🔴 求解器被杀 = **搜索可能不完整**（不报错的降级）⇒ 计数并写进日志，供报告如实披露。
kills() { grep -hc "constraint=CONSTRAINT_MEMCG" /var/log/syslog 2>/dev/null || echo 0; }

attempt=0
while :; do
  attempt=$((attempt + 1))
  echo "--- [$(date +%H:%M:%S)] 第 $attempt 次启动（启动前 MemAvailable=$(mem) GB，累计 cgroup-OOM 击杀=$(kills)）---" >> "$LOG"
  # 🔴 `-p KillMode=process -p OOMPolicy=continue` **不是可选项**（2026-09-26 实测踩到活锁）：
  # systemd 默认 `KillMode=control-group` ⇒ cgroup 一 OOM，它把**整个 scope** 判失败并发 SIGTERM
  # ⇒ 驱动 `rc=143`、**在飞合约白跑**。实测两次尝试各死在 z3 被杀的同一秒（17:37:50 / 17:40:08），
  # `ok 0/169` 永远不动。加这两项后：吃内存的进程照旧被杀，**同 scope 的驱动存活**（已用
  # `sleep 300` 旁观进程实测验证）⇒ 合约跑完、循环继续。
  systemd-run --user --scope -p MemoryMax=$MEMCAP \
    -p KillMode=process -p OOMPolicy=continue --quiet \
    python scripts/baseline_static_tools.py --tool manticore \
      --graph-dir products/alldata/graphs --only "${TODO[@]}" \
      --tag alldata --tool-timeout 180 --flush-every 1 >> "$LOG" 2>&1
  rc=$?
  ok=$(python - <<'PY'
import json
todo = set(open('runs/_tools_work/_manticore_todo.txt').read().split())
cs = json.load(open('eval_results/baseline/manticore_alldata.json'))['contracts']
print(sum(1 for b in todo if cs.get(b, {}).get('status') == 'ok'))
PY
)
  echo "--- [$(date +%H:%M:%S)] 第 $attempt 次退出 rc=$rc，已 ok $ok/$N（MemAvailable=$(mem) GB，累计 cgroup-OOM 击杀=$(kills)）---" >> "$LOG"
  # 🔴 判据是 **rc==0**（整份列表走完），不是「全部 ok」——见文件头 v2 的 bug 说明。
  if [ "$rc" -eq 0 ]; then
    echo "=== [$(date +%H:%M:%S)] 驱动正常走完全部 $N 个（ok $ok/$N，其余为稳定 timeout/error）===" >> "$LOG"
    break
  fi
  if [ "$attempt" -ge 40 ]; then
    echo "🔴 已重启 40 次仍非正常退出（当前 ok $ok/$N）——停下交人判断" >> "$LOG"
    echo 3 > "$RC"; exit 3
  fi
done

python scripts/baseline_static_tools.py --tool manticore --eval-only \
    --graph-dir products/alldata/graphs --tag alldata >> "$LOG" 2>&1

# 🔴 **运行环境自述边车**（2026-09-26 用户裁定「方案 A + 如实披露」）：
# 本机 WSL 总内存只有 7.8 GB，而 manticore 默认 `--core.procs = CPU 核数 = 24` 个 z3 进程
# ⇒ 必须给进程加 cgroup 上限，**代价是上限被顶到时求解器会被内核击杀**（合约仍记 `ok`，
# 但搜索可能不完整 —— 这是**不报错的降级**，只能靠这份自述披露，不可能从产物里看出来）。
# 报告（`collect_traditional_tools.section_cost`）会读本文件并自动印出，**不手写**。
MEMCAP="$MEMCAP" python - >> "$LOG" 2>&1 <<'PY'
import json, os, subprocess, datetime
from pathlib import Path
kills = subprocess.run(["grep", "-hc", "constraint=CONSTRAINT_MEMCG", "/var/log/syslog"],
                       capture_output=True, text=True).stdout.strip() or "0"
out = Path("eval_results/baseline/manticore_alldata/run_env.json")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({
    "tool": "manticore",
    "mem_cap": os.environ.get("MEMCAP", "?"),
    "mem_cap_bytes": 5 * 1024 ** 3,
    "cgroup_oom_kills_syslog_total": int(kills),
    "note_kills": ("该计数是**全机 syslog 累计**（含 2026-09-26 我做的 2 次上限验证测试），"
                   "不是本工具单独的次数；本工具相关的击杀发生在 2026-09-26 17:32 与 17:34。"),
    "core_procs": "默认（= CPU 核数 24）—— 🔴 **不得**为省内存而中途调小：并行度直接决定"
                  "「180 s 预算内能搜到多少」，前 50 个合约已用默认值跑完，改了前后两半就不同尺。",
    "flush_every": 1,
    "machine_ram_bytes": 7 * 1024 ** 3 + 823 * 1024 ** 2,
    "why": ("本机 WSL 总内存 7.8 GB（VSCode 服务进程实测占 1.36 GB）⇒ manticore 只能用 ~5 GB。"
            "2026-09-26 16:59 因**两路并行 + 并发的 pytest** 触发全局 OOM，内核杀掉了 `systemd` 与 "
            "VSCode 的 `MainThread` ⇒ WSL 整体重启。此后改为**单路 + cgroup 上限**。"),
    "written_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"[run_env] 已写 {out}（上限 {os.environ.get('MEMCAP')}，累计 cgroup-OOM 击杀 {kills}）")
PY

python scripts/collect_traditional_tools.py >> "$LOG" 2>&1
echo "ALL DONE rc=0 $(date +%H:%M:%S)" >> "$LOG"
echo 0 > "$RC"
