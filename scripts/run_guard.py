#!/usr/bin/env python3
"""输出目录覆盖守卫（2026-09-16）：防止换数据集/做消融时无声销毁已报告的结果。

**为什么需要**：`train.py`、`make_splits.py`、`m3_build_features.py` 的默认输出目录
**全部指向正典产物区**（`runs/`、`products/alldata/splits/`、`products/alldata/graphs/`），
`generate_all_ast_cfg_dfg.sh` 更会在开工时 `find -delete` 清空目标目录。
默认值盲跑一次，就能把论文正典结果或 15 GB 特征删掉。

**判据**：每个输出目录里都留有"产出它的那次实验"的自述文件
（`config.json` / `split_metadata_seed*.json`）。把本次调用的参数与那份自述**逐项对比**，
只要有一项不同，就说明本次写的不是同一次实验 → 报错退出，除非显式 `--overwrite`。

**只比较两边都存在的键**：老自述文件里没有的新键（例如后续版本才加的开关）不算冲突——
否则"用新代码复跑旧实验"会被全部误拒。

**路径归一化（关键）**：自述文件里记的是**绝对路径**，而命令行常传相对路径。
直接比字符串会把"同一个目录"判成冲突（2026-09-16 实测踩到）。故对已知的路径型参数
统一 `Path(...).resolve()` 后再比；两侧都归一化，故即使某参数不是真实路径（如 HF 模型 id）
也只会得到一致的结果，不会引入新的误判。

本模块只做判定，不做任何删除/写入。各 CLI 的 `--overwrite` 语义由调用方保留。
"""

from __future__ import annotations

import json
from pathlib import Path

# 不参与「是否为同一次实验」判定的键（控制流开关，不影响实验身份）
VOLATILE_KEYS = frozenset({"overwrite"})

# 已知的路径型参数名：比较前归一化为绝对路径。跨脚本取并集，
# 出现同名非路径参数的风险极低（这些名字都是目录/文件语义）。
PATH_ARG_KEYS = frozenset({
    "graph_dir", "out_dir", "split_dir", "runs_dir", "in_dir", "m1_dir",
    "label_file", "near_dup_clusters", "categories", "src_root",
})


def canonical_args(args_map: dict) -> dict:
    """参数字典 → 去掉 volatile 键、并把已知路径型键归一化为绝对路径。"""
    out: dict = {}
    for key, value in args_map.items():
        if key in VOLATILE_KEYS:
            continue
        if key in PATH_ARG_KEYS and isinstance(value, str) and value:
            out[key] = str(Path(value).resolve())
        else:
            out[key] = value
    return out


def canonical_path(value) -> str | None:
    """单个路径值归一化（用于比较自述文件里单独记录的路径字段）。"""
    if not value:
        return None
    try:
        return str(Path(str(value)).resolve())
    except (OSError, ValueError):
        return str(value)


def diff_args(old_args: dict, new_args: dict) -> list[str]:
    """两侧参数字典的差异描述（只比双方都有的键，且已归一化）。"""
    old = canonical_args(old_args or {})
    new = canonical_args(new_args or {})
    return [f"{k}: {old[k]!r} → {new[k]!r}"
            for k in sorted(set(old) & set(new)) if old[k] != new[k]]


def read_record(path: Path) -> dict | str:
    """读"自述文件"。返回 dict；损坏时返回错误描述字符串（调用方按冲突处理）。"""
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError):
        return f"{Path(path).name} 无法解析（疑为中断残留）"


def _dedupe(items: list[str]) -> list[str]:
    """稳定去重：同一变更可能被两个来源各报一次（如 graph_dir 同时出现在 inputs 与 args 里）。"""
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def guard_message(target: str, diffs: list[str], hint: str) -> str:
    """统一的拒绝文案（各 CLI 只改 hint）。"""
    return (f"[guard] 拒绝覆盖 {target}：本次调用与产出该目录的那次不一致——\n  "
            + "\n  ".join(_dedupe(diffs))
            + f"\n  这是为了防止无声销毁已报告的结果。{hint}")


def warn_message(target: str, diffs: list[str]) -> str:
    return (f"[guard] ⚠ --overwrite 生效，即将覆盖 {target}：\n  "
            + "\n  ".join(_dedupe(diffs)))


def corpus_conflict(out_dir, in_dir, pattern: str = "*_hetero.json") -> str | None:
    """`out_dir` 是否属于**另一个语料**（`m3_build_features.py` 用）。

    暴露面：M3 的默认 `--out-dir` 是 `products/alldata/graphs`。为 DIVE/SolidiFI 跑特征时
    若忘传 `--out-dir`，就会把外部数据集的特征写进主库目录（下游 `dataset.py` 按 base 取文件，
    表现为莫名其妙的行数/标签错配，极难定位）。

    判据：out_dir 已有的 `_feat.pt` 的 base 与 in_dir 的输入图 base **完全不相交**。
    只要有交集就视为同一语料——断点续跑、增量补图、`--force` 全量重建都合法，不做子集判断。
    返回 None = 无冲突（out_dir 为空 / in_dir 为空 / 两者有交集）。
    """
    suffix_in = pattern[1:] if pattern.startswith("*") else pattern      # *_hetero.json → _hetero.json
    inputs = {p.name[: -len(suffix_in)] for p in Path(in_dir).glob(pattern)}
    existing = {p.name[: -len("_feat.pt")] for p in Path(out_dir).glob("*_feat.pt")}
    if not inputs or not existing or (inputs & existing):
        return None
    return (f"out-dir 内已有的 {len(existing)} 个 _feat.pt 与 in-dir 的 {len(inputs)} 个输入图"
            f"**没有一个同名**（out-dir 例：{sorted(existing)[:2]}；in-dir 例：{sorted(inputs)[:2]}）"
            f"——两者显然不是同一语料，写进去会污染该目录")
