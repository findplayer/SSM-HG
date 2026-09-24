#!/usr/bin/env python3
"""输出目录覆盖守卫的回归测试（`scripts/run_guard.py`，2026-09-16）。

锁住四件事：
  1. **路径归一化**——命令行常传相对路径而实验自述记的是绝对路径，不归一化会把
     "同一个目录"误判成冲突（2026-09-16 实测踩到，见 `test_relative_and_absolute_same_dir_*`）；
  2. **只比较双方都存在的键**——老自述没有的新键不算冲突，否则"用新代码复跑旧实验"会被全部误拒；
  3. 坏自述文件按冲突处理（宁可疑、不可无声覆盖）；
  4. `corpus_conflict` 的判据是"**完全不相交**才拦"（断点续跑/增量/--force 全量重建都必须放行）。

运行：`pytest tests/test_run_guard.py -q`
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import run_guard  # noqa: E402
import make_splits  # noqa: E402
import train  # noqa: E402


# ------------------------------------------------------------ 归一化与差异
def test_canonical_args_resolves_paths_and_drops_volatile():
    out = run_guard.canonical_args({"graph_dir": "products/alldata/graphs",
                                    "overwrite": True, "lr": 1e-4})
    assert out["graph_dir"] == str((REPO / "products/alldata/graphs").resolve())
    assert "overwrite" not in out, "volatile 键不参与身份判定"
    assert out["lr"] == 1e-4, "非路径键原样保留"


def test_diff_args_only_compares_shared_keys():
    """老自述缺新键时不得报差异（否则新版本会拒绝复跑旧实验）。"""
    assert run_guard.diff_args({"lr": 1e-4}, {"lr": 1e-4, "brand_new": 7}) == []
    assert run_guard.diff_args({}, {"lr": 1e-4}) == []


def test_diff_args_ignores_volatile_and_normalizes_paths():
    old = {"out_dir": str(REPO / "runs"), "overwrite": False}
    new = {"out_dir": "runs", "overwrite": True}      # 同一目录、不同写法 + 翻转 overwrite
    assert run_guard.diff_args(old, new) == []


def test_diff_args_reports_real_change():
    d = run_guard.diff_args({"lr": 1e-4}, {"lr": 1e-3})
    assert len(d) == 1 and "lr" in d[0]


def test_canonical_path_none_and_bad_input():
    assert run_guard.canonical_path(None) is None
    assert run_guard.canonical_path("") is None
    assert run_guard.canonical_path("/a/b") == "/a/b"


def test_guard_message_dedupes_identical_lines():
    msg = run_guard.guard_message("/x", ["lr: 1 → 2", "lr: 1 → 2"], "提示")
    assert msg.count("lr: 1 → 2") == 1


# ------------------------------------------------------------ corpus_conflict（M3 用）
def test_corpus_conflict_disjoint_is_conflict(tmp_path):
    (tmp_path / "in").mkdir()
    (tmp_path / "out").mkdir()
    for b in ("a", "b"):
        (tmp_path / "in" / f"{b}_hetero.json").write_text("{}", encoding="utf-8")
    for b in ("dive_x", "dive_y"):
        (tmp_path / "out" / f"{b}_feat.pt").write_bytes(b"")
    assert run_guard.corpus_conflict(tmp_path / "out", tmp_path / "in") is not None


def test_corpus_conflict_overlap_is_fine(tmp_path):
    """有交集即同一语料：断点续跑、增量补图、--force 全量重建都必须放行。"""
    (tmp_path / "in").mkdir()
    (tmp_path / "out").mkdir()
    for b in ("a", "b", "c"):
        (tmp_path / "in" / f"{b}_hetero.json").write_text("{}", encoding="utf-8")
    for b in ("a", "b"):                       # 只做了一部分 → 交集非空
        (tmp_path / "out" / f"{b}_feat.pt").write_bytes(b"")
    assert run_guard.corpus_conflict(tmp_path / "out", tmp_path / "in") is None


def test_corpus_conflict_empty_dirs_are_fine(tmp_path):
    (tmp_path / "in").mkdir()
    (tmp_path / "out").mkdir()
    assert run_guard.corpus_conflict(tmp_path / "out", tmp_path / "in") is None


# ------------------------------------------------------------ train.py 集成
def _write_cfg(run_dir: Path, args: dict, split_seed: int = 0) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "config.json").write_text(
        json.dumps({"args": args, "split_seed": split_seed}, ensure_ascii=False),
        encoding="utf-8")


def test_relative_and_absolute_same_dir_is_not_a_conflict(tmp_path):
    """★ 回归：曾因"相对路径 vs 绝对路径"把同参数复跑误判成冲突。"""
    _write_cfg(tmp_path / "seed0", {"graph_dir": str(REPO / "products/alldata/graphs"),
                                    "lr": 1e-4})
    got = train.run_dir_conflict(tmp_path / "seed0",
                                 argparse.Namespace(graph_dir="products/alldata/graphs",
                                                    lr=1e-4), 0)
    assert got is None, got


def test_train_guard_detects_changed_split_dir(tmp_path):
    _write_cfg(tmp_path / "seed0", {"split_dir": "/a/splits", "lr": 1e-4})
    got = train.run_dir_conflict(tmp_path / "seed0",
                                 argparse.Namespace(split_dir="/b/splits", lr=1e-4), 0)
    assert got is not None and "split_dir" in got


def test_train_guard_missing_dir_is_none(tmp_path):
    assert train.run_dir_conflict(tmp_path / "seed0",
                                  argparse.Namespace(lr=1e-4), 0) is None


def test_train_guard_unparseable_record_is_conflict(tmp_path):
    (tmp_path / "seed0").mkdir()
    (tmp_path / "seed0" / "config.json").write_text("{ 半截", encoding="utf-8")
    assert train.run_dir_conflict(tmp_path / "seed0", argparse.Namespace(lr=1e-4), 0) is not None


# ------------------------------------------------------------ make_splits.py 集成
def _write_split_meta(out_dir: Path, graph_dir: str, **extra) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    meta = {"seed": 0, "ratio": [0.8, 0.1, 0.1], "strategy": "constrained",
            "constraints": {"min_pos_ratio": 0.30},
            "dedup": {"mode": "source-sha1+address"},
            "inputs": {"graph_dir": graph_dir}, **extra}
    (out_dir / "split_metadata_seed0.json").write_text(
        json.dumps(meta, ensure_ascii=False), encoding="utf-8")


def _ns(**over):
    """构造 split_dir_conflict 需要的最小 args（graph_dir 可被 over 覆盖）。"""
    base = dict(graph_dir=str(REPO / "products/alldata/graphs"), strategy="constrained",
                dedup="source-sha1+address", min_pos_ratio=0.30)
    base.update(over)
    return argparse.Namespace(**base)


def test_split_relative_and_absolute_same_dir_is_not_a_conflict(tmp_path):
    """★ 回归：同 make_splits 的相对/绝对路径误判。"""
    _write_split_meta(tmp_path, str(REPO / "products/alldata/graphs"))
    got = make_splits.split_dir_conflict(tmp_path, _ns(), [0.8, 0.1, 0.1])
    assert got == [], got


@pytest.mark.parametrize("field,value,frag", [
    ("graph_dir", "/other/graphs", "graph_dir"),
    ("strategy", "random", "strategy"),
    ("min_pos_ratio", 0.0, "min_pos_ratio"),
])
def test_split_guard_detects_identity_change(tmp_path, field, value, frag):
    _write_split_meta(tmp_path, str(REPO / "products/alldata/graphs"))
    args = _ns(**{field: value})
    got = make_splits.split_dir_conflict(tmp_path, args, [0.8, 0.1, 0.1])
    assert got and frag in got[0], got


def test_split_guard_detects_ratio_change(tmp_path):
    _write_split_meta(tmp_path, str(REPO / "products/alldata/graphs"))
    got = make_splits.split_dir_conflict(tmp_path, _ns(),
                                         [0.7, 0.15, 0.15])
    assert got and "ratio" in got[0], got


def test_split_guard_empty_dir_is_fine(tmp_path):
    assert make_splits.split_dir_conflict(tmp_path, _ns(),
                                          [0.8, 0.1, 0.1]) == []


def test_split_guard_unparseable_record_is_conflict(tmp_path):
    tmp_path.mkdir(exist_ok=True)
    (tmp_path / "split_metadata_seed0.json").write_text("{ 半截", encoding="utf-8")
    got = make_splits.split_dir_conflict(tmp_path, _ns(),
                                         [0.8, 0.1, 0.1])
    assert got and "无法解析" in got[0]


# ------------------------------------------------------------ shell 守卫（端到端）
def test_raw_script_refuses_and_touches_nothing():
    """`generate_all_ast_cfg_dfg.sh` 在默认（主库）路径下必须**拒绝且一个字节都不写**。

    ★ 这是 2026-09-16 事故的回归：初版守卫只检查 AST/CFG/DFG 三个目录，漏了 `LOG_DIR` 与
    `FILTER_REPORT`，且位置在日志截断**之后** —— 于是"只覆盖部分环境变量"的一次运行把主库正典
    `filter_report.txt` 写成了全 0。现在守卫覆盖全部六条路径且前移到所有清空动作之前。
    """
    import hashlib
    import os
    import subprocess

    script = REPO / "scripts" / "generate_all_ast_cfg_dfg.sh"
    watched = [REPO / "products/alldata/raw/filter_report.txt",
               REPO / "products/alldata/raw/logs/ast_error.log"]
    before = {p: (hashlib.sha1(p.read_bytes()).hexdigest() if p.exists() else None)
              for p in watched}
    env = {k: v for k, v in os.environ.items()
           if k not in ("AST_DIR", "CFG_DIR", "DFG_DIR", "LOG_DIR", "SRC_ROOT",
                        "FILTER_REPORT", "SSMHG_ALLOW_WIPE")}
    proc = subprocess.run(["bash", str(script)], capture_output=True, text=True,
                          cwd=str(REPO), env=env, timeout=300)
    assert proc.returncode == 2, f"应拒绝并返回 2，实际 {proc.returncode}"
    assert "拒绝" not in proc.stdout and "非空" in proc.stderr
    for p in watched:
        now = hashlib.sha1(p.read_bytes()).hexdigest() if p.exists() else None
        assert now == before[p], f"{p.name} 被守卫触碰了（事故回归）"



# ------------------------------------------- 身份键默认值（IDENTITY_DEFAULTS，decisions §31）
# 起因：`diff_args` 只比对**双方都有**的键。这对"用新代码复跑旧实验"是必需的，
# 但反过来会造成「用一个新参数写进旧目录」差异为 0 → 守卫放行 → **无声覆盖**。
#   `train.py --head binary --out-dir runs/prior_dropout_study/drop20_ts3_ss0` 就是这条路径。

def test_identity_default_catches_new_flag_written_into_old_dir():
    """🔴 老记录无 `head` + 新调用 `--head binary` → **必须报冲突**（否则无声覆盖配对基线）。"""
    old = {"out_dir": "runs/prior_dropout_study/drop20_ts3_ss0", "lr": 1e-4}   # 引入 head 之前
    new = {"out_dir": "runs/prior_dropout_study/drop20_ts3_ss0", "lr": 1e-4,
           "head": "binary"}
    diffs = run_guard.diff_args(old, new)
    assert any(d.startswith("head:") for d in diffs), diffs
    assert "multi" in diffs[0] and "binary" in diffs[0]


def test_identity_default_still_allows_replaying_old_experiment():
    """复跑旧实验（老记录无 `head`、新调用用默认 `multi`）**不得**被判冲突。"""
    old = {"out_dir": "runs/seed0", "lr": 1e-4}
    assert run_guard.diff_args(old, {"out_dir": "runs/seed0", "lr": 1e-4}) == []
    assert run_guard.diff_args(old, {"out_dir": "runs/seed0", "lr": 1e-4,
                                     "head": "multi"}) == []


def test_identity_default_lets_single_variable_assertion_see_the_new_key():
    """新臂相对**老基线**只覆盖一个键时，`changed` 必须恰为该键（否则消融断言会误判"未生效"）。"""
    old = {"lr": 1e-4, "out_dir": "runs/prior_dropout_study/drop20_ts3_ss0"}
    new = dict(old, head="binary")
    changed = {d.split(":", 1)[0] for d in run_guard.diff_args(old, new)}
    assert changed == {"head"}, changed


def test_identity_default_keys_are_real_cli_flags():
    """漂移守卫：登记进 `IDENTITY_DEFAULTS` 的键必须是**某个真实消费方**真有的开关。

    挡的是"拼错键名"——`diff_args` 走 `setdefault(key, default)`，一个拼错的键会
    **永远静默不生效**，而表面上"已登记"。

    🔴 **消费方是两族**：`train.py`（`head`/`layers`）与基线族
    （`baseline_common.base_parser()`，`feature_suffix`）。故键集合取**两族的并集**，
    且**必须从真 parser 现算**（写成字面量等于把守卫关掉）。
    """
    import io
    import contextlib
    import baseline_common
    with contextlib.redirect_stdout(io.StringIO()):     # --help 之类不会触发，但保持安静
        saved, sys.argv = sys.argv, ["train.py"]
        try:
            flags = set(vars(train.parse_args()))
        finally:
            sys.argv = saved
        saved, sys.argv = sys.argv, ["baseline_mvdhg.py"]
        try:
            flags |= set(vars(baseline_common.base_parser("漂移守卫", "mvdhg").parse_args([])))
        finally:
            sys.argv = saved
    unknown = set(run_guard.IDENTITY_DEFAULTS) - flags
    assert not unknown, f"IDENTITY_DEFAULTS 里有不存在的 CLI 键（拼写错误？）：{unknown}"
    # `feature_suffix` 只属于基线族：它必须**不在** train.py 里，否则上面那条并集断言会
    # 掩盖"两边同名不同义"的坑（本仓 §31.3 的教训是键要可见，不是键要同名）。
    with contextlib.redirect_stdout(io.StringIO()):
        saved, sys.argv = sys.argv, ["train.py"]
        try:
            train_flags = set(vars(train.parse_args()))
        finally:
            sys.argv = saved
    assert "feature_suffix" not in train_flags, "feature_suffix 不该出现在 train.py 里"
