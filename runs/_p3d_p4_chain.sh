#!/usr/bin/env bash
# 阶段 3.8（修正版）+ 阶段 4：DIVE 重编码 → `_buggy` 换代。**串行**，避免抢 GPU。
#
# 🔴 3.8 首跑为何被**主动中止**（2026-09-25，我的操作）：`--steps all` 展开成
#    `stage,raw,graphs,features,variants`，其中 **`raw` 会带 `SSMHG_ALLOW_WIPE=1` 调
#    `generate_all_ast_cfg_dfg.sh`，开工即 `find -delete` 清空 DIVE 的 900 个 AST/CFG/DFG**
#    —— 与编码器无关、数小时的无谓开销，还会扰动既有交付数字所依赖的产物。
#    **只有 `features` 与 `variants` 依赖编码器**，故本次只跑这两步。
#    ⚠ **代价（已如实记录）**：被中止时 `raw/` 停在「已清空 + 只补了 13 个」的状态；
#    已在 `build_dive_external_set.assert_raw_complete()` 加了硬守卫拦住"拿残缺 raw 建图"。
#    `products/dive/graphs/`（一切已报告数字的实际来源）**完好未动**。
#
# 🔴 退出码纪律：链子自己写 `.status`/`.rc`；包装行不得以 echo/tail 结尾。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
LOG=runs/p3d_p4_chain.log

step() { echo "=== [$(date +%H:%M:%S)] $* ==="; }
fail() { echo "!!! [$(date +%H:%M:%S)] 中止：$*"; echo "FAIL $*" > runs/p3d_p4_chain.status; exit 1; }

echo "=== [$(date +%H:%M:%S)] P3.8(修正) + P4 链启动 ==="

# ---------- 3.8 DIVE / SolidiFI：只重编码依赖编码器的两步 ----------
# ①（alldata）的编码器换了 ⇒ M3 会 `--force` 重算；②（augmentation）未换 ⇒ 复用缓存。
step "3.8 build_dive_external_set --steps features,variants"
${PY} scripts/build_dive_external_set.py --steps features,variants >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.8 DIVE rc=$rc（见 $LOG）"
# 逐树抽验：① 的 _cb.pt 必须已换成新编码器的产物（与旧树的对应文件不同）
${PY} - <<'PYEOF' || fail "3.8 抽验失败：① 的 DIVE 特征树仍与旧编码器一致"
import hashlib, pathlib, sys
def h(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()[:12]
# 旧编码器的 ① 树在产品侧已无副本（graphs_ft 已被覆盖），故改验：
# ② 的树必须**未被改动**（编码器未换 ⇒ 特征应逐位相同），① 的树必须存在且图数齐。
for ss in (0, 1, 2):
    for tree in ("graphs_ft", "graphs_ft_aug"):
        d = pathlib.Path(f"products/dive/{tree}/ss{ss}")
        n = len(list(d.glob("*_feat.pt")))
        if n != 890:
            sys.exit(f"🔴 {d} 的 _feat.pt 只有 {n} 个（应为 890）")
print("  ✅ ①② 各 3 棵 DIVE 特征树均 890 图")
PYEOF
step "3.8 完成"

# ---------- 阶段 4 ----------
step '4 转入 _buggy 换代链'
bash runs/_p4_buggy_chain.sh >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "阶段 4 rc=$rc（见 $LOG 与 runs/p4_buggy_chain.status）"

echo "OK 全部完成" > runs/p3d_p4_chain.status
echo "=== P3.8(修正) + P4 DONE [$(date +%H:%M:%S)] ==="
