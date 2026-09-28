#!/usr/bin/env bash
# 五个传统工具在「含 buggy_* 的主库（池 497）」上的补跑 —— v2（2026-09-27 21:0x）。
#
# v1 死于 20:23 的 WSL 关机（不是 OOM：`journalctl -b -1` 末尾是完整的 systemd poweroff 序列，
# 今日 syslog 无任何 oom 行）。v2 的三条修补：
#   ① **内存上限覆盖六个工具**（v1 只给 manticore 加了 cgroup）——全部走
#      `systemd-run --user --scope -p MemoryMax=4.5G -p KillMode=process -p OOMPolicy=continue`。
#   ② **每个工具显式传 `--tool-timeout`**，与 canon37 产物里记录的预算**逐一对齐**
#      （🔴 v1 漏传 ⇒ securify 用了适配器默认 180 s，而 canon37 那轮是 120 s ⇒ 不同尺。
#       适配器默认与产物记录对不上的有三个：securify 180≠120、oyente 180≠120、manticore 300≠180）。
#   ③ **可续跑 + 自愈 + 脱离会话**：每合约增量落盘；`_p8_supervisor.sh` 反复重入直到 sentinel。
#
# 🔴 为什么只跑 92 个而不是 236 个：工具的**逐合约输出与划分无关**（模块 docstring 第 11 行明写
#    「换划分只需重跑 --eval-only，不必重跑工具」）。canon37 已跑过 214 个，buggy 并集 236
#    ⇒ 只补差集 92 个，其余 144 个逐位复用。
#
# 🔴 绝不改 canon37 产物：先 `cp` 成 `<工具>_alldata_buggy.json`（不存在时才拷 ⇒ 可续跑），
#    再往副本里并集补跑。命名对齐 `collect_baseline_tables.trad_root(tool,'buggy')`。
#
# 🔴 符号执行类**不得并行**：本脚本严格串行。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
LOGDIR=products/alldata/raw/logs/baseline_buggy
LOG=$LOGDIR/tools_alldata_buggy.log
RC=runs/_p8_tools_buggy.rc
DONE=runs/_tools_work/_p8_done
SPLIT=products/alldata/splits/withbuggy_snapshot
GDIR=products/alldata/graphs
TAG=alldata_buggy
MEMCAP=4.5G
mkdir -p "$LOGDIR" runs/_tools_work
rm -f "$RC"

log() { echo "=== [$(date +%H:%M:%S)] $* ===" >> "$LOG"; }
cspace() { df -m /mnt/c | awk 'NR==2{printf "%d", $4/1024}'; }
guard() {
  local f; f=$(cspace)
  if [ "$f" -lt 8 ]; then log "🔴 C盘只剩 ${f}G（< 8G 硬阈值）→ 停止"; echo 4 > "$RC"; exit 4; fi
}
mem() { awk '/MemAvailable/{printf "%.1f", $2/1048576}' /proc/meminfo; }
kills() { grep -hc "constraint=CONSTRAINT_MEMCG" /var/log/syslog 2>/dev/null || echo 0; }

# 统一的调用壳：**每个工具都在 cgroup 上限下跑**（v1 只有 manticore 有）
run_capped() {   # $@ = baseline_static_tools.py 的参数
  systemd-run --user --scope -p MemoryMax=$MEMCAP \
      -p KillMode=process -p OOMPolicy=continue --quiet \
      python scripts/baseline_static_tools.py "$@" >> "$LOG" 2>&1
}

log "v2 启动：C盘可用 $(cspace)G，MemAvailable $(mem)GB，内存上限 $MEMCAP（六工具统一）"

# ---------------------------------------------------------------- 0) 差集列表
python - > runs/_tools_work/_buggy_need.txt <<'PY'
import json
def union(sd):
    u = set()
    for s in (0, 1, 2):
        j = json.load(open(f"{sd}/split_seed{s}.json"))
        u |= set(j["val"]) | set(j["test"])
    return u
need = sorted(union("products/alldata/splits/withbuggy_snapshot")
              - union("products/alldata/splits"))
print("\n".join(need))
PY
mapfile -t NEED < runs/_tools_work/_buggy_need.txt
N=${#NEED[@]}
log "需补跑 $N 个合约（buggy 并集 236 − canon37 并集 214）"

seed_copy() {   # $1=tool
  local j="eval_results/baseline/$1_alldata.json"
  local b="eval_results/baseline/$1_alldata_buggy.json"
  if [ ! -f "$b" ]; then cp "$j" "$b"; log "$1 已从 canon37 复制副本：$b"; fi
}

# ---------------------------------------------------------------- 1) 三个快工具
# 🔴 预算显式传，逐一对齐 canon37 产物（见文件头 ②）
declare -A BUDGET=( [smartcheck]=120 [securify]=120 [oyente]=120 [mythril]=180 [manticore]=180 )

for T in smartcheck securify oyente; do
  guard; seed_copy "$T"
  k0=$(kills)
  log "$T 开始（预算 ${BUDGET[$T]}s，--only $N 个）"
  run_capped --tool "$T" \
      --out "eval_results/baseline/${T}_alldata_buggy.json" \
      --graph-dir "$GDIR" --split-dir "$SPLIT" --tag "$TAG" \
      --tool-timeout "${BUDGET[$T]}" --only "${NEED[@]}"
  rc=$?
  k1=$(kills)
  log "$T 结束 rc=$rc（C盘 $(cspace)G，本工具 cgroup-OOM 击杀 $((k1 - k0))）"

  # ---- 闸门：放在**第一个工具之后**（v1 放在三个之后，白白多跑 2 分钟）
  if [ "$T" = "smartcheck" ]; then
    if ! python - <<'PY' >> "$LOG" 2>&1
import json, sys
e = json.load(open("eval_results/baseline/smartcheck_alldata_buggy/seed0_eval.json"))["test"]
n = len(json.load(open("eval_results/baseline/smartcheck_alldata_buggy.json"))["contracts"])
print(f"[gate] smartcheck seed0 test: n_analyzed={e['n_analyzed']}/{e['n_in_split']} "
      f"micro={e.get('micro_f1')} | 原始产物 {n} 条")
sys.exit(0 if (e["n_analyzed"] > 0 and n > 214) else 1)
PY
    then log "🔴 闸门失败（覆盖率 0 或产物未扩容）→ 停止"; echo 3 > "$RC"; exit 3; fi
    log "闸门通过：smartcheck 覆盖 > 0 且原始产物已扩容"
  fi
done

# ---------------------------------------------------------------- 2) Mythril
guard; seed_copy mythril
k0=$(kills)
log "mythril 开始（预算 ${BUDGET[mythril]}s，单路 + cgroup，flush-every 2）"
run_capped --tool mythril \
    --out eval_results/baseline/mythril_alldata_buggy.json \
    --graph-dir "$GDIR" --split-dir "$SPLIT" --tag "$TAG" \
    --tool-timeout "${BUDGET[mythril]}" --flush-every 2 --only "${NEED[@]}"
rc=$?; k1=$(kills)
log "mythril 结束 rc=$rc（C盘 $(cspace)G，本工具 cgroup-OOM 击杀 $((k1 - k0))）"

# ---------------------------------------------------------------- 3) Manticore（自愈）
guard; seed_copy manticore
k0=$(kills)
attempt=0
while :; do
  attempt=$((attempt + 1))
  log "manticore 第 $attempt 次启动（MemAvailable=$(mem)GB，累计击杀=$(kills)）"
  run_capped --tool manticore \
      --out eval_results/baseline/manticore_alldata_buggy.json \
      --graph-dir "$GDIR" --split-dir "$SPLIT" --tag "$TAG" \
      --tool-timeout "${BUDGET[manticore]}" --flush-every 1 --only "${NEED[@]}"
  rc=$?
  ok=$(python - <<'PY'
import json
todo = set(open('runs/_tools_work/_buggy_need.txt').read().split())
cs = json.load(open('eval_results/baseline/manticore_alldata_buggy.json'))['contracts']
print(sum(1 for b in todo if cs.get(b, {}).get('status') == 'ok'))
PY
)
  log "manticore 第 $attempt 次退出 rc=$rc，已 ok $ok/$N（MemAvailable=$(mem)GB，击杀=$(kills)）"
  # 判据 = **rc==0**（整份列表走完）。稳定失败的合约永远不会变 ok，拿"全部 ok"当判据会空转到上限。
  [ "$rc" -eq 0 ] && break
  if [ "$attempt" -ge 40 ]; then log "🔴 重启 40 次仍非正常退出（ok $ok/$N）"; echo 3 > "$RC"; exit 3; fi
  guard
done
k1=$(kills)
log "manticore 全部退出（本工具 cgroup-OOM 击杀合计 $((k1 - k0))）"

# ---------------------------------------------------------------- 4) 跑动环境自述边车（两个符号执行类）
# AGENTS.md 硬规则：上限顶到时求解器被杀而合约**仍记 ok**（不报错的降级）⇒ 只能靠自述披露。
for T in mythril manticore; do
  MEMCAP="$MEMCAP" TOOL="$T" python - >> "$LOG" 2>&1 <<'PY'
import json, os, subprocess, datetime
from pathlib import Path
t = os.environ["TOOL"]
kills = subprocess.run(["grep", "-hc", "constraint=CONSTRAINT_MEMCG", "/var/log/syslog"],
                       capture_output=True, text=True).stdout.strip() or "0"
out = Path(f"eval_results/baseline/{t}_alldata_buggy/run_env.json")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({
    "tool": t,
    "pool": "含 buggy_* 的主库（池 497）",
    "run_set": "三种子 val∪test ∪ (buggy 并集 − canon37 并集)，原始产物 306 条，本轮新跑 92 条",
    "mem_cap": os.environ.get("MEMCAP", "?"),
    "cgroup_oom_kills_syslog_total": int(kills),
    "note_kills": "全机 syslog 累计，不是本工具单独的次数；本轮的逐工具增量见 tools_alldata_buggy.log。",
    "tool_timeout_s": 180,
    "flush_every": 2 if t == "mythril" else 1,
    "why": ("本机 WSL 总内存 7.8 GB（VSCode 服务进程 ≈2.3 GB）⇒ 六个工具统一加 cgroup 4.5 GB 上限；"
            "上限顶到时求解器被杀而合约仍记 ok，该降级在产物里看不出来，只能靠本文件披露。"
            "🔴 2026-09-27 20:23 那次中断**不是 OOM**：journalctl -b -1 末尾是完整 systemd poweroff 序列，"
            "今日 syslog 无任何 oom 行 ⇒ 是 WSL 整体关机带走了作业。"),
    "written_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
}, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"[sidecar] 已写 {out}")
PY
done

# ---------------------------------------------------------------- 5) 收尾自检
python - >> "$LOG" 2>&1 <<'PY'
import json
from pathlib import Path
print("\n=== 收尾自检（池 497 · tag=alldata_buggy）===")
for t in ("slither", "mythril", "manticore", "smartcheck", "securify", "oyente"):
    d = Path(f"eval_results/baseline/{t}_buggy" if t == "slither" else f"eval_results/baseline/{t}_alldata_buggy")
    if not d.exists():
        print(f"  🔴 {t}: 无产物目录 {d}"); continue
    row = []
    for s in (0, 1, 2):
        f = d / f"seed{s}_eval.json"
        if not f.exists():
            row.append("缺"); continue
        e = json.load(open(f))["test"]
        row.append(f"{e['n_analyzed']}/{e['n_in_split']} micro={e.get('micro_f1')}")
    print(f"  {t}: " + " | ".join(row))
PY

log "全部完成（sentinel 已写）"
touch "$DONE"
echo 0 > "$RC"
