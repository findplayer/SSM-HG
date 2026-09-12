#!/usr/bin/env python3
"""DIVE 外部测试子集抽样（阶段 5；协议定稿见 `experiments/decisions.md` §13 与手册 10.2 第 6 条）。

协议（2026-09-12 定稿，不得漂移）
--------------------------------
- **抽样单位**：唯一合约 = `DIVE/contract_labels.json` 的条目（21696 条，已剔除 Bad Randomness=1）；
- **抽样方式**：**均匀随机、无放回**（不做按类配额；均匀在期望意义上保持标签联合分布）；
- **固定 seed**：`SEED = 0` → 抽样是**一次确定事件**：抽出后以**实测支撑为准**，"概率"只在抽样前有意义；
- **规模**：主抽 **n = 900**（2026-09-12 P1 定稿：900×2.44% ≈ 22 ≥ 20，与大纲 5.1(6)「不少于 500 个」
  及「每类 ≥20」三条件自洽；成本理由见手册 10.2 第 6 条）；若实测 `front_running` 支撑 < 20，
  则 **n 单调升至 1100 重抽一次**（attempt=2）；仍 <20 时记 `front_running_gate = "report-only"`：
  如实报数、不隐藏、不改口径；
- **禁止**：换 seed 重抽、反复重抽挑到达标样本（选择偏倚）；调整 n 是公开协议参数，允许但必须披露停止规则。

输出（`products/dive/splits/`）
------------------------------
- `sample_seed{SEED}.json`：n / seed / attempt / ids / 逐类 support / 多标签与全零计数 / 停止规则 / 输入摘要 / sha256
- `sample_report.json`：人类可读摘要（含 gate 判定结论）

运行（仓库根目录）：
  python scripts/sample_dive_subset.py            # 按协议抽样并写产物
  python scripts/sample_dive_subset.py --print     # 只看结果，不写文件
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import random
from datetime import datetime, timezone
from pathlib import Path

BASE = Path("/home/saumarez/projects/deep-learning/SSM-HG")
LABEL_FILE = BASE / "DIVE/contract_labels.json"
SRC_DIR = BASE / "DIVE/Source codes"
OUT_DIR = BASE / "products/dive/splits"

CLASSES = ["access_control", "arithmetic", "dos", "front_running",
           "reentrancy", "time_manipulation", "uncheck"]
SEED = 0                 # 固定；换 seed = 选择偏倚，禁止
N_MAIN = 900             # 主抽规模（2026-09-12 P1 定稿：900×2.44% ≈ 22 ≥ 20）
N_BACKSTOP = 1100        # 后备：n 单调升至 1100，重抽一次
FR_GATE = 20             # front_running 达标门槛（报告义务的下限）


def contract_id(name: str) -> int:
    """`contract_name`（形如 `8263.sol`）→ 整数 id（用于稳定排序）。"""
    return int(Path(name).stem)


def draw(ids: list[int], n: int, rng: random.Random) -> list[int]:
    """均匀无放回抽样；返回按 id 升序的稳定列表（便于比对与复现）。"""
    return sorted(rng.sample(ids, n))


def supports(ids: list[int], labels: dict[int, list[int]]) -> dict:
    """逐类支撑 + 多标签/全零计数 + 各类正样本率（含与全集先验对比）。"""
    per = collections.Counter()
    multi = zero = 0
    for i in ids:
        t = labels[i]
        s = sum(t)
        multi += 1 if s >= 2 else 0
        zero += 1 if s == 0 else 0
        for k, v in enumerate(t):
            per[CLASSES[k]] += v
    return {"n": len(ids), "per_class": {c: per[c] for c in CLASSES},
            "multi_label": multi, "all_zero": zero,
            "multi_label_ratio": round(multi / len(ids), 4)}


def main() -> None:
    parser = argparse.ArgumentParser(description="Sample the DIVE external test subset (fixed protocol).")
    parser.add_argument("--print", dest="print_only", action="store_true", help="只打印结果，不写文件")
    args = parser.parse_args()

    entries = json.loads(LABEL_FILE.read_text(encoding="utf-8"))
    labels: dict[int, list[int]] = {}
    for e in entries:
        labels[contract_id(e["contract_name"])] = [int(v) for v in e["targets"][:7]]
    ids = sorted(labels)
    missing_src = [i for i in ids if not (SRC_DIR / f"{i}.sol").exists()]

    rng = random.Random(SEED)
    attempts: list[dict] = []
    gate = ""
    chosen: list[int] = []
    for attempt, n in ((1, N_MAIN), (2, N_BACKSTOP)):
        picked = draw(ids, n, rng)          # 同一 rng 续抽：n 单调升，非换 seed
        stats = supports(picked, labels)
        fr = stats["per_class"]["front_running"]
        attempts.append({"attempt": attempt, "n": n, **stats,
                         "front_running_gate_ok": fr >= FR_GATE})
        chosen = picked
        if fr >= FR_GATE:
            gate = f"closed: n={n}, front_running={fr} (≥{FR_GATE})"
            break
        gate = f"backstop next: n={n}, front_running={fr} (<{FR_GATE})"
    else:
        gate = (f"report-only: n={N_BACKSTOP} 仍 front_running<{FR_GATE}"
                f"（如实报数；禁止换 seed 重抽挑数据）")

    payload = {
        "dataset": "DIVE",
        "protocol": {
            "unit": "unique contract (DIVE/contract_labels.json entry)",
            "mode": "uniform random, without replacement (no per-class quota)",
            "seed": SEED,
            "n_main": N_MAIN, "n_backstop": N_BACKSTOP,
            "front_running_gate": FR_GATE,
            "stopping_rule": ("主抽 n=900；front_running<20 时 n 单调升至 1100 重抽一次；"
                              "仍不足则记 report-only（如实报数）；禁止换 seed 重抽"),
            "authority": "experiments/decisions.md §13 第 5/10 条 + 论文开发手册.md 10.2 第 6 条",
        },
        "inputs": {
            "label_file": str(LABEL_FILE.relative_to(BASE)),
            "label_count": len(entries),
            "label_file_sha256": hashlib.sha256(LABEL_FILE.read_bytes()).hexdigest(),
            "source_files_present": len(ids) - len(missing_src),
            "missing_source_ids": missing_src[:20],
            "missing_source_count": len(missing_src),
        },
        "attempts": attempts,
        "selected": {"ids": chosen, "n": len(chosen)},
        "gate": gate,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    payload["output_sha256"] = hashlib.sha256(
        json.dumps(payload["selected"], ensure_ascii=False).encode()).hexdigest()

    last = attempts[-1]
    print(f"DIVE 抽样：seed={SEED} attempt={last['attempt']} n={last['n']}")
    print(f"  逐类支撑: {last['per_class']}")
    print(f"  多标签 {last['multi_label']}（{last['multi_label_ratio']:.1%}）、全零 {last['all_zero']}")
    print(f"  gate: {gate}")
    if missing_src:
        print(f"  [warn] 标签缺源码的 id 数：{len(missing_src)}")

    if args.print_only:
        return
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"sample_seed{SEED}.json"
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    report = {k: payload[k] for k in ("dataset", "protocol", "inputs", "attempts", "gate",
                                      "output_sha256", "created_utc")}
    report["selected_n"] = len(chosen)
    (OUT_DIR / "sample_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"written: {out.relative_to(BASE)}")
    print(f"written: {(OUT_DIR / 'sample_report.json').relative_to(BASE)}")


if __name__ == "__main__":
    main()
