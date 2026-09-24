#!/usr/bin/env python3
"""补充臂：**7 个独立二分类器**（每类一个模型）vs 正典的七维多标签共享模型。

**目的不是提高数字**，而是回答一个审稿人必问的问题：**多标签共享是否压制了稀有类？**
（① 主库 train 逐类正例 = 11/10/4/**2**/21/**2**/35，`front_running` 与 `time_manipulation`
各只有 **2** 个正样本——本臂就是去看这 2 个正样本在「独占一个编码器」时会不会学得更好。）

🔴 **零模型改动**：`--head binary` 的标签塌缩**只发生在 `dataset.stack_labels` 一处**，规则是
`any(targets)`。故只要把标签文件里**除第 c 列以外全部置 0**，就有 `any(targets) == y_c`
⇒ 该次训练就是「这个合约有没有第 c 类漏洞」的**独立二分类器**。
⇒ 复用已单测的 `--head binary` 链路（`decisions.md` §31），**不新增任何模型/训练代码**。

🔴 **本臂最大的坑（必须靠断言兜住）**：若标签文件没生效，`any(targets)` 会退回
**全类并集**（有任意一类漏洞），于是 7 个「独立分类器」会**全部变成同一个 any 分类器**，
而且**不报错**——数字看起来还算正常。故 `--steps check` 会逐产物断言
「test 正例数 == 该类的 test support」，并**拒绝**任何等于全类并集的结果。

产物（**另开目录，绝不碰 `runs/seed{S}`**）：
    products/alldata/perclass_labels/cls_<类名>.json      # 逐类标签文件（可重建，不入库）
    runs/perclass_arm/cap<上限>/cls_<类名>/seed<S>/       # 每类一个 run，形制同 runs/seed{S}/

用法（仓库根目录）：
    python scripts/run_perclass_arm.py --steps labels check            # 只造标签 + 自检
    python scripts/run_perclass_arm.py --classes front_running --seeds 0 --steps all --smoke
    python scripts/run_perclass_arm.py --steps all                     # 全量 7 类 × 3 种子 × 2 cap 档
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import metrics                                                          # noqa: E402

NAMES = list(metrics.VULN_NAMES)
SEEDS = (0, 1, 2)
LABEL_SRC = REPO / "alldata(readonly)/contract_labels.json"
LABEL_DIR = REPO / "products/alldata/perclass_labels"
OUT_ROOT = "runs/perclass_arm"
# ⚠ 两条 ① 主库口径**逐字来自正典**，只改 `--head` 与 `--label-file`：
GRAPH_TMPL = "products/alldata/graphs_ft/ss{S}"
SPLIT_DIR = "products/alldata/splits"


# ------------------------------------------------------------------ 标签层
def class_support(seed: int) -> list[int]:
    """① 该种子的 test 逐类正例数（**用于第 3 步的硬断言**；从正典图与标签算，不手写）。"""
    import baseline_common as B
    idx, _ = B.load_index(REPO / GRAPH_TMPL.format(S=seed))
    split = json.loads((REPO / SPLIT_DIR / f"split_seed{seed}.json").read_text(encoding="utf-8"))
    sup = [0] * 7
    for base in split["test"]:
        lab = idx.get(base)
        if lab is None:
            raise SystemExit(f"🔴 正典图里找不到 {base} 的标签")
        for i, v in enumerate(lab):
            if v:
                sup[i] += 1
    return sup


def train_support(seed: int) -> list[int]:
    """① 该种子的 **train** 逐类正例数（本臂的立论依据，打印出来给人看）。"""
    import baseline_common as B
    idx, _ = B.load_index(REPO / GRAPH_TMPL.format(S=seed))
    split = json.loads((REPO / SPLIT_DIR / f"split_seed{seed}.json").read_text(encoding="utf-8"))
    sup = [0] * 7
    for base in split["train"]:
        for i, v in enumerate(idx[base]):
            if v:
                sup[i] += 1
    return sup


def write_labels() -> list[Path]:
    """`contract_labels.json` → 逐类标签文件（**除第 c 列外全部置 0**）。

    ⚠ 保留原 `contract_name` 不动 ⇒ 仍走 `--label-key-mode project`（主库默认），
    键的切法与正典**逐字相同**（`build_proj_labels` 同一个函数）。
    """
    LABEL_DIR.mkdir(parents=True, exist_ok=True)
    raw = json.loads(LABEL_SRC.read_text(encoding="utf-8"))
    out = []
    for c, name in enumerate(NAMES):
        rows = [{"contract_name": e["contract_name"],
                 "targets": [int(v) if i == c else 0 for i, v in enumerate(e["targets"])]}
                for e in raw]
        p = LABEL_DIR / f"cls_{name}.json"
        p.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        n_pos = sum(1 for r in rows if r["targets"][c])
        out.append(p)
        print(f"[labels] {p.name}: {len(rows)} 条，第 {c} 列正例 {n_pos} 个（其余列已置 0）",
              flush=True)
    return out


# ------------------------------------------------------------------ 跑批层
def run_dir_of(cap: float, cls: str, seed: int) -> Path:
    return REPO / OUT_ROOT / f"cap{cap:g}" / f"cls_{cls}" / f"seed{seed}"


def build_cmd(step: str, cap: float, cls: str, seed: int, smoke: bool) -> list[str]:
    rd = f"{OUT_ROOT}/cap{cap:g}/cls_{cls}"
    label = f"{LABEL_DIR.relative_to(REPO)}/cls_{cls}.json"
    common = ["--graph-dir", GRAPH_TMPL.format(S=seed),
              "--split-dir", SPLIT_DIR,
              "--label-file", label, "--label-key-mode", "project"]
    if step in ("train", "all"):
        return ["python", "scripts/train.py", "--seed", str(seed), "--split-seed", str(seed),
                "--head", "binary", "--pos-weight-cap", str(cap),
                "--out-dir", rd, *common] + (["--limit-graphs", "24", "--epochs", "2"] if smoke else [])
    if step in ("eval", "all"):
        return ["python", "scripts/evaluate.py", "--runs-dir", rd, "--seed", str(seed), *common]
    if step in ("diagnose", "all"):
        return ["python", "scripts/diagnose.py", "--runs-dir", rd, "--seed", str(seed), *common]
    raise SystemExit(f"未知 step {step}")


def run(cmd: list[str], log: Path | None = None) -> int:
    log = log or (REPO / OUT_ROOT / "_driver.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    # 🔴 子进程必须显式继承 os.environ：默认继承会被父进程（已 import torch）的 KMP 变量毒死。
    #    本仓在 5.3 基线驱动上实测过（env=None 5/5 失败，显式 env 5/5 成功）。
    with log.open("a", encoding="utf-8") as fh:
        fh.write(f"\n$ {' '.join(cmd)}\n")
        r = subprocess.run(cmd, cwd=str(REPO), stdout=fh, stderr=subprocess.STDOUT,
                           env=dict(os.environ))
    return r.returncode


# ------------------------------------------------------------------ 校验层
def check(cap: float, classes, seeds) -> int:
    """🔴 本臂唯一的「只会说谎、不会报错」的坑就在这里。

    断言每个产物：① 头宽 = 1（真的走了 binary 臂）；② test 正例数 == **该类的** support
    （证明标签文件生效）；③ 正例数 **不等于全类并集**（否则 7 个臂会静默退化成同一个 any 分类器）。
    """
    bad = 0
    import torch
    for seed in seeds:
        sup = class_support(seed)
        union = sum(1 for b in json.loads(
            (REPO / SPLIT_DIR / f"split_seed{seed}.json").read_text(encoding="utf-8"))["test"]
            if any(_labels_of(b, seed)))
        for cls in classes:
            c = NAMES.index(cls)
            p = run_dir_of(cap, cls, seed) / "test_probs.pt"
            if not p.exists():
                print(f"  [skip] cap{cap:g}/{cls}/seed{seed}：无 test_probs.pt")
                continue
            d = torch.load(p, map_location="cpu")
            n1, npos = int(d["labels"].numel()), int(d["labels"].sum())
            ok = (d["probs"].shape[1] == 1 and d["labels"].shape[1] == 1
                  and npos == sup[c] and npos != union)
            bad += 0 if ok else 1
            flag = "✅" if ok else "🔴"
            print(f"  {flag} cap{cap:g}/{cls}/seed{seed}: 头宽 {d['probs'].shape[1]}，"
                  f"test 正例 {npos}（该类 support {sup[c]}，全类并集 {union}）")
    if bad:
        raise SystemExit(f"🔴 {bad} 个产物不合格——**不得**用它们出表（标签很可能没生效）")
    print("✅ 全部产物通过：标签塌缩确实是逐类的，不是 any 并集")
    return 0


def _labels_of(base: str, seed: int) -> list[int]:
    import baseline_common as B
    if not hasattr(_labels_of, "_idx"):
        _labels_of._idx = {}
    if seed not in _labels_of._idx:
        _labels_of._idx[seed] = B.load_index(REPO / GRAPH_TMPL.format(S=seed))[0]
    return _labels_of._idx[seed][base]


# ------------------------------------------------------------------ 主流程
def main() -> int:
    ap = argparse.ArgumentParser(description="7 个独立二分类器补充臂（vs 正典七维共享）")
    ap.add_argument("--classes", default="all", help="逗号分隔的类名，或 all")
    ap.add_argument("--seeds", type=int, nargs="+", default=list(SEEDS))
    ap.add_argument("--caps", type=float, nargs="+", default=[20.0, 0.0],
                    help="pos_weight 上限档（20 = 与正典同正则；0 = 不截断、每类自带完整平衡）")
    ap.add_argument("--steps", default="all",
                    help="逗号分隔：labels / train / eval / diagnose / check / all")
    ap.add_argument("--smoke", action="store_true", help="每类只跑 24 图 2 轮，验链路")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    classes = NAMES if args.classes == "all" else [c.strip() for c in args.classes.split(",")]
    for c in classes:
        if c not in NAMES:
            raise SystemExit(f"🔴 未知类名 {c}；可选 {NAMES}")
    steps = set()
    for s in ("labels", "train", "eval", "diagnose", "check"):
        if args.steps == "all" or s in args.steps.split(","):
            steps.add(s)

    # 守卫：产物目录**必须**在 runs/perclass_arm 下，绝不碰正典 runs/seed{S}
    assert OUT_ROOT.startswith("runs/") and "perclass_arm" in OUT_ROOT
    for cap in args.caps:
        for cls in classes:
            for sd in args.seeds:
                rd = str(run_dir_of(cap, cls, sd).relative_to(REPO))
                assert not rd.startswith("runs/seed"), f"🔴 目标目录与正典相交：{rd}"

    if "labels" in steps:
        print(f"[support] ① train 逐类正例（seed0）= {train_support(0)}  ← 本臂的立论依据")
        print(f"[support] ① test  逐类正例（seed0）= {class_support(0)}")
        write_labels()

    grid = [(cap, cls, sd) for cap in args.caps for cls in classes for sd in args.seeds]
    print(f"[plan] {len(grid)} 个 run（cap × 类 × 种子）；steps={sorted(steps)}")
    if args.dry_run:
        for cap, cls, sd in grid:
            for st in ("train", "eval", "diagnose"):
                if st in steps:
                    print("  " + " ".join(build_cmd(st, cap, cls, sd, args.smoke)))
        return 0

    failed = []
    for i, (cap, cls, sd) in enumerate(grid, 1):
        for st in ("train", "eval", "diagnose"):
            if st not in steps:
                continue
            cmd = build_cmd(st, cap, cls, sd, args.smoke)
            rc = run(cmd)
            if rc != 0:
                failed.append((cap, cls, sd, st, rc))
                print(f"🔴 [{i}/{len(grid)}] cap{cap:g}/{cls}/seed{sd} {st} rc={rc}", flush=True)
                break
        else:
            print(f"[{i}/{len(grid)}] cap{cap:g}/{cls}/seed{sd} ✅", flush=True)

    if "check" in steps:
        for cap in args.caps:
            check(cap, classes, args.seeds)
    if failed:
        print(f"🔴 {len(failed)} 个子步骤失败：{failed}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
