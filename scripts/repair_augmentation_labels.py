#!/usr/bin/env python3
"""修正 `alldata_augmentation` 中标错的一批标签（2026-09-14，decisions §19.3.1）。

背景
----
`alldata_augmentation/contract_labels.json` 的生成规则是「7 个类目录中该键
`targets==1` 的并集」（审计见 decisions §19.3，实测 8997/9026 严格一致）。
该规则对**同名同内容**的文件正确，但 `{类}__buggy_N` 这批文件是**同名不同内容**：

  - 同一编号 N 在 7 个 `{类}_contract_data_augmentation/sol_source/` 里是 **7 个不同文件**
    （50 个编号上跨类内容一致者 0 个）；
  - 上游对 `buggy_N-<合约名>` 这个**键名**在**全部 7 个目录**都标 `targets=1`；
  - 于是并集规则把它们推成 `1111111`（714 条），而真值是**单类**——由
    `solidifi_labels.json` 记录（各类目录只含本类注入）。

结果：全集正样本 7383 中有 4386（59%）为虚高。本脚本按真值重算这批条目。

修正规则（**窄规则**，仅动 `__buggy_` 这一类）
--------------------------------------------
对标签键 `K = "<stem>-<合约名>.sol"`：

  - 若 `stem` 形如 `{类}__buggy_<rest>`（`{类}` 为七类之一）：
    取 `<MVD_ROOT>/{类}_contract_data_augmentation/contract_labels.json` 中键
    `buggy_<rest>-<合约名>.sol` 的 `targets`（0/1），写成**该类下标上的 one-hot**；
  - 其余键：**原样保留**（并集规则已审计正确）。

为什么不做更广的推广：`reentrancy__0x627fa62c…` / `uncheck__0x627fa62c…` 这 6 条虽是
`{类}__REST` 形式，但其两份副本是同一合约的两个版本，上游标签互补
（Token 在 uncheck、TokenBank 在 reentrancy），**并集才是真值**（与 `alldata(readonly)`
逐位一致）。判别标准是「同名**不同**内容」而非「有无类前缀」，而实测中同名不同内容
**只发生在 `buggy_*` 上**（非 buggy 的同名文件跨目录内容 100% 一致）。

只读约束
--------
**不写入 `alldata_augmentation/`**（只读数据源）。修正结果写到 `products/augmentation/`，
原文件保持不动，两者并存备查。

输出
----
  - `products/augmentation/contract_labels_repaired.json`（与输入同 schema/同格式，可直接替换消费）
  - `products/augmentation/label_repair_report.json`（机器可读：改动明细 + 逐类前后计数 + 校验）

运行（仓库根目录）：
    python scripts/repair_augmentation_labels.py --dry-run   # 只看影响面，不写文件
    python scripts/repair_augmentation_labels.py             # 写出修正文件与报告
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]  # 仓库根；从任意 cwd 运行都成立

# 类别顺序锁死（reentrancy 下标 4）——与全项目一致，勿改
CLASSES = ["access_control", "arithmetic", "dos", "front_running",
           "reentrancy", "time_manipulation", "uncheck"]
IDX = {c: i for i, c in enumerate(CLASSES)}

BUGGY_MARK = "__buggy_"

# SolidiFI 的规范类名与本项目锁死的类名在 2 个类上不同名；交叉校验时按此归一，
# 否则 dos/uncheck 会被误报为「不一致」（2026-09-14 实测：332 条全是这个原因）。
SOLIDIFI_ALIAS = {
    "dos": "denial_of_service",
    "uncheck": "unchecked_low_level_calls",
}


def load_json(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def load_upstream_labels(mvd_root: Path) -> dict[str, dict[str, int]]:
    """{类: {上游键 -> targets(0/1)}}；缺目录直接报错，不静默跳过。"""
    out: dict[str, dict[str, int]] = {}
    for cls in CLASSES:
        path = mvd_root / f"{cls}_contract_data_augmentation" / "contract_labels.json"
        if not path.exists():
            sys.exit(f"[错误] 上游标签文件不存在：{path}\n"
                     f"       本脚本依赖 MVD-HG-dataset，请确认该只读数据源已就位。")
        out[cls] = {e["contract_name"]: e["targets"] for e in load_json(path)}
    return out


def load_solidifi_truth(mvd_root: Path) -> dict[tuple[str, str], list[str]]:
    """{(类, 上游文件名) -> 注入类别列表}；用于交叉校验，缺文件则该类为空。"""
    truth: dict[tuple[str, str], list[str]] = {}
    for cls in CLASSES:
        path = mvd_root / f"{cls}_contract_data_augmentation" / "solidifi_labels.json"
        if not path.exists():
            continue
        for name, per_class in load_json(path).items():
            truth[(cls, name)] = sorted(per_class.keys())
    return truth


def split_key(key: str) -> tuple[str, str]:
    """标签键 -> (stem, 合约名+'.sol')。项目名/地址本身不含 `-`，从右切一次即安全。"""
    stem, _, name = key.rpartition("-")
    return stem, name


def repair_one(stem: str, name: str, targets: list[int],
               upstream: dict[str, dict[str, int]]) -> tuple[list[int] | None, str]:
    """返回 (新 targets 或 None=保持不变, 状态标记)。"""
    if BUGGY_MARK not in stem:
        return None, "kept_not_buggy"
    cls, _, rest = stem.partition(BUGGY_MARK)
    if cls not in IDX:
        return None, "kept_unknown_class_prefix"
    up_key = f"buggy_{rest}-{name}"
    val = upstream[cls].get(up_key)
    if val is None:
        return None, "kept_upstream_key_missing"
    new = [0] * 7
    new[IDX[cls]] = int(val)
    return (None if new == list(targets) else new), "repaired"


def main() -> None:
    ap = argparse.ArgumentParser(
        description="按 solidifi_labels 真值修正 alldata_augmentation 中 {类}__buggy_N 的标签")
    ap.add_argument("--aug-dir", default=str(BASE / "alldata_augmentation"),
                    help="增强集目录（只读，脚本不会写入）")
    ap.add_argument("--mvd-root", default=str(BASE / "MVD-HG-dataset"),
                    help="MVD-HG-dataset 只读源根目录")
    ap.add_argument("--out", default=str(BASE / "products/augmentation/contract_labels_repaired.json"))
    ap.add_argument("--report", default=str(BASE / "products/augmentation/label_repair_report.json"))
    ap.add_argument("--dry-run", action="store_true", help="只统计与校验，不写任何文件")
    ap.add_argument("--force", action="store_true", help="允许覆写已存在的输出文件")
    args = ap.parse_args()

    aug_dir = Path(args.aug_dir)
    mvd_root = Path(args.mvd_root)
    src = aug_dir / "contract_labels.json"
    if not src.exists():
        sys.exit(f"[错误] 找不到增强集标签文件：{src}")

    entries = load_json(src)
    upstream = load_upstream_labels(mvd_root)
    truth = load_solidifi_truth(mvd_root)

    before = collections.Counter()
    after = collections.Counter()
    status = collections.Counter()
    changes: list[dict] = []
    unrepaired: list[dict] = []
    solidifi_bad: list[dict] = []
    solidifi_checked = 0

    out_entries: list[dict] = []
    for e in entries:
        key, targets = e["contract_name"], list(e["targets"])
        stem, name = split_key(key)
        for i, v in enumerate(targets):
            if v:
                before[CLASSES[i]] += 1

        new, st = repair_one(stem, name, targets, upstream)
        status[st] += 1
        if new is None:
            final = targets
            if st.startswith("kept_") and st != "kept_not_buggy":
                unrepaired.append({"contract_name": key, "status": st, "targets": targets})
        else:
            final = new
            changes.append({"contract_name": key,
                            "before": targets, "after": new,
                            "class": stem.partition(BUGGY_MARK)[0]})

        # 交叉校验：该类目录的 solidifi 真值是否确为本类单类（按别名归一后比较）
        if BUGGY_MARK in stem:
            cls, _, rest = stem.partition(BUGGY_MARK)
            t = truth.get((cls, f"buggy_{rest}.sol"))
            if t is not None:
                solidifi_checked += 1
                if t != [SOLIDIFI_ALIAS.get(cls, cls)]:
                    solidifi_bad.append({"contract_name": key, "solidifi": t,
                                         "dir_class": cls,
                                         "expected": SOLIDIFI_ALIAS.get(cls, cls)})

        out_entries.append({"contract_name": key, "targets": final})
        for i, v in enumerate(final):
            if v:
                after[CLASSES[i]] += 1

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": str(src.relative_to(BASE)),
        "mvd_root": str(mvd_root.relative_to(BASE)),
        "total_entries": len(entries),
        "status": dict(status),
        "repaired_count": len(changes),
        "unrepaired_count": len(unrepaired),
        "solidifi_cross_check": {
            "checked": solidifi_checked,
            "mismatch": len(solidifi_bad),
            "note": "按 SOLIDIFI_ALIAS 归一后比较；mismatch=0 表示被修正文件所在类目录的 "
                    "solidifi 真值恰为本类单类。checked 少于修正数为正常：函数级文件"
                    "（buggy_N0x<地址>_<合约>_<函数>.sol）在 solidifi_labels 中无对应键。",
        },
        "per_class": {c: {"before": before[c], "after": after[c],
                          "inflated": before[c] - after[c]} for c in CLASSES},
        "total_positive": {"before": sum(before.values()), "after": sum(after.values()),
                           "inflated": sum(before.values()) - sum(after.values())},
        "changes": changes,
        "unrepaired": unrepaired,
        "solidifi_mismatch": solidifi_bad[:50],
    }

    # ---- 打印摘要 ----
    print(f"源文件：{src}（只读，未改动）")
    print(f"条目总数：{len(entries)}    需修正：{len(changes)}    未修正(异常)：{len(unrepaired)}")
    print(f"solidifi 交叉校验不一致：{len(solidifi_bad)}")
    print(f"\n{'类别':<20}{'现行':>7}{'修正后':>8}{'虚高':>7}{'占比':>8}")
    for c in CLASSES:
        b, a = before[c], after[c]
        pct = f"{100 * (b - a) / b:.0f}%" if b else "-"
        print(f"{c:<20}{b:>7}{a:>8}{b - a:>7}{pct:>8}")
    tb, ta = sum(before.values()), sum(after.values())
    print(f"{'合计正样本':<20}{tb:>7}{ta:>8}{tb - ta:>7}{100 * (tb - ta) / tb:>7.0f}%")
    print(f"\n非零条目数：{sum(1 for e in entries if any(e['targets']))}"
          f"（修正后应与之相等 ⇒ 每条非零标签恰一类 = 单标签集）")

    if args.dry_run:
        print("\n[--dry-run] 未写出任何文件。")
        return

    out_path, rep_path = Path(args.out), Path(args.report)
    for p in (out_path, rep_path):
        if p.exists() and not args.force:
            sys.exit(f"[错误] {p} 已存在；如需覆写请加 --force（避免误覆盖历史快照）。")
    for p in (out_path, rep_path):
        p.parent.mkdir(parents=True, exist_ok=True)

    # 格式与输入逐字对齐：4 空格缩进 + targets 单行内联
    lines = ["["]
    for i, e in enumerate(out_entries):
        comma = "," if i < len(out_entries) - 1 else ""
        lines.append("    {")
        lines.append(f'        "contract_name": {json.dumps(e["contract_name"], ensure_ascii=False)},')
        lines.append(f'        "targets": {json.dumps(e["targets"])}')
        lines.append(f"    }}{comma}")
    lines.append("]")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    rep_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"\n已写出：\n  {out_path.relative_to(BASE)}\n  {rep_path.relative_to(BASE)}")
    print("`alldata_augmentation/` 未被写入（只读源）。")


if __name__ == "__main__":
    main()
