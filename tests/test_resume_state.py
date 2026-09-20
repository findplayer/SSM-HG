#!/usr/bin/env python3
"""消融驱动的**三态续跑判据**回归锁（2026-09-18）。

**为什么值得单独锁**：`run_ablation.py` / `run_study.py` 是"可重入队列"——中途被打断
（本机 WSL 会整机重启，2026-09-15 实测腰斩过 M3；2026-09-18 `wsl --shutdown` 腰斩过
`runs/ablation_aug/layers3/seed2`）后重跑，靠的就是"每步开工前先看产物在不在"。
**判据写错不会报错，只会静默少算。**

原判据是 `best.pt 已存在 → 跳过`，而 `best.pt` 是**训练中途**落盘的（每 epoch 刷新），
`config.json` 才是 `train.py` 训练全部结束后才写的（`train.py:624`）。于是被打断的 run
留下 `best.pt` 却无 `config.json`/`results.json`，会被当成"已完成"跳过 ⇒ `results.json`
永远补不上 ⇒ `--summarize` 只聚合到剩下的种子 ⇒ **n=2 的均值挂在"3 种子消融"名下**。
`summary.json` 的 `n` 字段虽会显形，但极易漏看——故把判据钉死成测试。

运行：`pytest tests/test_resume_state.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import run_ablation  # noqa: E402


def _touch(d: Path, *names: str) -> None:
    d.mkdir(parents=True, exist_ok=True)
    for n in names:
        (d / n).write_bytes(b"")


def test_missing_dir_is_train():
    """目录不存在 ⇒ 全跑（第一个 run 的常态）。"""
    assert run_ablation.resume_state(REPO / "runs" / "_nonexistent_probe") == "train"


def test_best_pt_alone_is_still_train():
    """🔴 回归锁：只有 `best.pt`（+ `last.pt`）**不算完成**——正是被打断的现场。

    `runs/ablation_aug/layers3/seed2` 实测就是这个形状：best/last/thresholds/val_best_probs
    四件在，config.json 与 results.json 都不在。
    """
    d = REPO / "runs" / "_probe_best_only"
    _touch(d, "best.pt", "last.pt", "thresholds.json", "val_best_probs.pt")
    try:
        assert run_ablation.resume_state(d) == "train", \
            "只有 best.pt 时判成已完成 = 静默漏跑，n 会少算"
    finally:
        for f in d.iterdir():
            f.unlink()
        d.rmdir()


def test_config_without_results_is_eval():
    """训练完成、evaluate 未完成 ⇒ 只补 evaluate（不重训，省一次 GPU）。"""
    d = REPO / "runs" / "_probe_eval_only"
    _touch(d, "best.pt", "config.json", "log.txt")
    try:
        assert run_ablation.resume_state(d) == "eval"
    finally:
        for f in d.iterdir():
            f.unlink()
        d.rmdir()


def test_results_is_done():
    """`results.json` 是最后一步的产物 ⇒ 完成。"""
    d = REPO / "runs" / "_probe_done"
    _touch(d, "best.pt", "config.json", "results.json")
    try:
        assert run_ablation.resume_state(d) == "done"
    finally:
        for f in d.iterdir():
            f.unlink()
        d.rmdir()


def test_predicate_is_not_best_pt():
    """把"判据必须是最后一步产物"写成对源码的断言——防止有人改回 best.pt。

    比行为测试更直接：`best.pt` 一旦重新出现在跳过分支里，这里就红。
    """
    src = (REPO / "scripts" / "run_ablation.py").read_text(encoding="utf-8")
    # 跳过分支所在的那几行里不得再出现 best.pt（resume_state 的文档串里提到它是允许的）
    body = src.split("def resume_state", 1)[1].split("def verify_single_variable", 1)[0]
    assert 'run_dir / "results.json"' in body
    assert 'run_dir / "best.pt"' not in body


def test_run_study_shares_the_predicate():
    """`run_study.py` 必须复用同一处实现，不得自己再写一份判据。"""
    src = (REPO / "scripts" / "run_study.py").read_text(encoding="utf-8")
    assert "run_ablation.resume_state(" in src, \
        "run_study.py 应复用 run_ablation.resume_state，避免两份判据漂移"
