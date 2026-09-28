#!/usr/bin/env bash
# 阶段 3 **收尾**：3.7（修正）+ 3.9（union 臂）+ 3.8（DIVE）。
#
# 🔴 3.7 首跑为何失败（2026-09-25 实测）：我照 `evaluate.py --summarize` 类推，给
#    `diagnose.py` 也传了 `--summarize` ⇒ `error: unrecognized arguments: --summarize`。
#    **正确形态**：`diagnose.py` 在 `main()` 里**无条件**写 `diagnosis_summary.json`，
#    **没有**该开关。`--summarize` 只属于 `evaluate.py`。
#    ⚠ 缓存安全性：`diagnose_seed` 命中 `seed{S}/test_probs.pt` 且校验 `sample_ids`
#    与当前划分一致即复用 ⇒ 三个种子的缓存都在（3.4 时写过），故单次 `--runs-dir runs`
#    对三种子都走缓存，**`--graph-dir` 逐种子不同的坑不会触发**。
#
# 🔴 3.9 是一个**孤儿臂**（2026-09-25 发现）：`runs/perclass_arm/cap20/cls_ANY_union/`
#    在旧的 45 个 run 里存在，但**没有任何脚本能产出它** ——
#    `run_perclass_arm.py` 的 `classes = metrics.VULN_NAMES`（7 类），
#    `git log -S "ANY_union" -- scripts/run_perclass_arm.py` **为空**（从未有过）。
#    只有 `collect_perclass_arm.py::union_rows()` 读它（读不到就 `continue` 跳过），
#    且旧的 `experiments/perclass_arm_results.md` 里**没有** union 行。
#    它的真实身份 = `--head binary`（`dataset.stack_labels` 的 `any(targets)` 塌缩）
#    的「有没有漏洞」臂，`label_file=None`（用默认 7 维标签）⇒ 与逐类臂同池同划分。
#    **本次按归档 config 忠实重放**（唯一被替换的两个键：`graph_dir` → 新树、
#    `deterministic` → 与 ① 现行正典一致），使文档里登记的布局不再有洞；
#    ⚠ 不新增脚本、不手抄参数：命令行由 `run_ablation` 的三个 argv 构造器从
#    **新正典 config** 派生（手抄 30 个参数正是本仓警告过的错源）。
set -u
cd /home/saumarez/projects/deep-learning/SSM-HG
PY=python
LOG=runs/p3_finish.log

step() { echo "=== [$(date +%H:%M:%S)] $* ==="; }
fail() { echo "!!! [$(date +%H:%M:%S)] 中止：$*"; echo "FAIL $*" > runs/p3_finish.status; exit 1; }

echo "=== [$(date +%H:%M:%S)] P3 收尾启动 ==="

# ---------- 3.7 runs/ 根下的跨种子聚合 ----------
step "3.7 重生成 runs/{summary,diagnosis_summary}.json"
${PY} scripts/evaluate.py --summarize --runs-dir runs >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.7 evaluate --summarize rc=$rc"
${PY} scripts/diagnose.py --runs-dir runs >>"$LOG" 2>&1      # ⚠ 无 --summarize
rc=$?
[ "$rc" -eq 0 ] || fail "3.7 diagnose rc=$rc"
[ -f runs/diagnosis_summary.json ] || fail "3.7 没写出 runs/diagnosis_summary.json"
${PY} -c "
import json
d=json.load(open('runs/diagnosis_summary.json'))
n=len(d.get('seeds',[]))
print(f'  diagnosis_summary 覆盖 {n} 个种子: {d.get(\"seeds\")}')
assert n==3, '种子数不是 3 —— 聚合不完整'
" || fail "3.7 diagnosis_summary 种子数不是 3"
step "3.7 完成"

# ---------- 3.9 全类并集 any 臂（孤儿产物，忠实重放）----------
step "3.9 重放 cap20/cls_ANY_union（--head binary，3 seed）"
${PY} - >>"$LOG" 2>&1 <<'PYEOF'
import subprocess, sys
sys.path.insert(0, "scripts")
import run_ablation as RA

base = RA.canonical_args("runs/seed0/config.json")
variants, frozen = RA.variants_root_of(base), RA.frozen_graphs_of(base)
OUT = "runs/perclass_arm/cap20/cls_ANY_union"

for S in (0, 1, 2):
    a = {k: RA.expand(v, S, variants, frozen) for k, v in base.items()}
    # 该臂相对正典的**全部**差异 = head 塌缩 + pos_weight 档位（+ 记账键）
    a.update({"head": "binary", "pos_weight_cap": 20.0,
              "seed": S, "split_seed": S, "out_dir": OUT, "overwrite": False})
    # 🔴 单变量自检：除上面两个键外不得再有差异（防止基线漂移悄悄带进第三个变量）
    # ⚠ 基线侧**也要展开** `{seed}`：`canonical_args` 返回的 `graph_dir` 是**模板**
    #   (`…/cb_ft_ss{seed}`)，而臂侧是展开值 —— 不展开会被 `diff_args` 按内容判成
    #   「改了 graph_dir」而误报（2026-09-25 实测踩到）。
    base_e = {k: RA.expand(v, S, variants, frozen) for k, v in base.items()}
    # ⚠ 只断言**真正发生变化**的键：`pos_weight_cap` 的正典默认值**本就是 20.0**
    #   ⇒ 覆盖成同值属 no-op，写进 expected 会被判「预期覆盖的键未生效」（实测踩到）。
    #   保留该 override 是为了**显式记录意图**（与归档 config 逐字一致），不是为了制造差异。
    ov = {"head": "binary", "pos_weight_cap": 20.0}
    expected = {k: v for k, v in ov.items()
                if k not in base_e or str(base_e[k]) != str(v)}
    viol = RA.verify_single_variable(base_e, a, expected)
    if viol:
        raise SystemExit(f"🔴 seed{S} 不是单变量臂：{viol}")
    # ⚠ `RA.argv_for_*` 返回的是**完整 argv**（首两项已是 `sys.executable` 与脚本绝对路径）
    #   ⇒ 直接 `subprocess.run(argv)`，**不得**再前缀一次（2026-09-25 实测踩到，
    #   报错形态是 `train.py: error: unrecognized arguments: <python> <train.py>`）。
    for step, argv in (("train", RA.argv_for_train(a)),
                       ("eval", RA.argv_for_eval(a)),
                       ("diagnose", RA.argv_for_diagnose(a))):
        r = subprocess.run(argv, capture_output=True, text=True)
        print(f"[union seed{S}/{step}] rc={r.returncode}")
        if r.returncode != 0:
            print((r.stdout or "")[-1500:] + (r.stderr or "")[-1500:])
            raise SystemExit(1)
print("[union] 3 个种子 × train/eval/diagnose 全部完成")
PYEOF
rc=$?
[ "$rc" -eq 0 ] || fail "3.9 union 臂 rc=$rc（见 $LOG）"
for S in 0 1 2; do
  for f in results.json test_probs.pt thresholds.json diagnosis.json; do
    [ -f "runs/perclass_arm/cap20/cls_ANY_union/seed${S}/${f}" ] \
      || fail "3.9 缺 cap20/cls_ANY_union/seed${S}/${f}"
  done
done
step "3.9 完成：union 臂 3 个 run 齐备"

# ---------- 3.8 DIVE / SolidiFI：① 用新编码器重编码 ----------
step "3.8 build_dive_external_set（重编码 ① 的 DIVE/SolidiFI 特征）"
${PY} scripts/build_dive_external_set.py --steps all >>"$LOG" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "3.8 build_dive_external_set rc=$rc（见 $LOG）"
step "3.8 完成"

step "P3 收尾统计"
{
  for d in seed0 seed1 seed2 cbft_study ablation ablation_n9 arch_n9 perclass_arm baseline_gcn; do
    printf "  runs/%-14s %s\n" "$d" "$(find runs/$d -name results.json 2>/dev/null | wc -l)"
  done
  df -h /mnt/c | tail -1
} | tee -a "$LOG"

echo "OK 全部完成" > runs/p3_finish.status
echo "=== P3 FINISH DONE [$(date +%H:%M:%S)] ==="
