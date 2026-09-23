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


# ---------------------------------------------------------------- diagnose 那一步（2026-09-21 修）
def test_missing_test_probs_is_diagnose_not_done():
    """🔴 回归锁：`results.json` 在而 `test_probs.pt` 不在 ⇒ **只补 diagnose**，不得判 `done`。

    洞的形状（2026-09-21 发现）：`test_probs.pt` 由 `diagnose.py` 写（`scripts/diagnose.py:210`），
    **`evaluate.py` 不写**；而 `run_ablation.py` 原先是 train→evaluate 两步链。
    于是它跑出的 run 有 `results.json` 却**没有** `test_probs.pt`，下游
    `collect_three_caliber_tables.py` / `error_rates.py` 只读这个缓存 ⇒ **整列变 `—`、不报错**。
    判据只看 `results.json` 就会把它当"已完成"永久跳过 ⇒ 缓存**永远补不上**。
    """
    d = REPO / "runs" / "_probe_no_probs"
    _touch(d, "best.pt", "config.json", "results.json", "thresholds.json", "val_best_probs.pt")
    try:
        assert run_ablation.resume_state(d, require_probs=True) == "diagnose", \
            "缺 test_probs.pt 时判成 done = 三口径表整列变 —，且不报错"
        # 默认参数**必须保持旧行为**（run_study 也调它，改默认值会让那条链的判据漂移）
        assert run_ablation.resume_state(d) == "done", \
            "默认参数的行为不得改变"
    finally:
        for f in d.iterdir():
            f.unlink()
        d.rmdir()


def test_test_probs_present_is_done_with_require_probs():
    """补上 `test_probs.pt` 之后必须回到 `done`（否则每轮都要重跑一遍 diagnose）。"""
    d = REPO / "runs" / "_probe_with_probs"
    _touch(d, "config.json", "results.json", "test_probs.pt")
    try:
        assert run_ablation.resume_state(d, require_probs=True) == "done"
    finally:
        for f in d.iterdir():
            f.unlink()
        d.rmdir()


def test_ablation_chain_includes_diagnose():
    """把"链条必须含 diagnose"写成对源码的断言——防止有人把这一步删回去。

    行为测试难以覆盖（要真跑一次 train），而这一步**删掉不会报错**，
    正是本仓反复记录的那类失效模式，故用源码断言直接钉住。
    """
    src = (REPO / "scripts" / "run_ablation.py").read_text(encoding="utf-8")
    assert "argv_for_diagnose(a)" in src, "run_ablation 主循环必须真的调 diagnose"
    assert 'require_probs=True' in src, "主循环必须用 require_probs=True 判据"


def test_diagnose_argv_has_one_implementation():
    """`run_study.argv_for_diagnose` 必须**委托**给 `run_ablation`，不得各写一份。

    两份实现的危险不是"跑不起来"，而是**其中一个后来被改**（如补一个 `--label-key-mode`）
    而另一个没跟上 ⇒ 两条链产出的 `test_probs.pt` 口径不同，且都不报错。
    """
    import run_study
    a = {"out_dir": "runs/x", "seed": 1, "graph_dir": "products/alldata/graphs_ft/ss1",
         "split_dir": "products/alldata/splits"}
    assert run_study.argv_for_diagnose(a) == run_ablation.argv_for_diagnose(a)
    src = (REPO / "scripts" / "run_study.py").read_text(encoding="utf-8")
    body = src.split("def argv_for_diagnose", 1)[1].split("\ndef ", 1)[0]
    assert "run_ablation.argv_for_diagnose(args)" in body, \
        "run_study 的 argv_for_diagnose 应当是委托，而不是又一份实现"
    # 带 label 键时的形状（② 增强集走这条分支）
    b = dict(a, label_file="products/augmentation/contract_labels_repaired.json",
             label_key_mode="repaired")
    assert run_study.argv_for_diagnose(b) == run_ablation.argv_for_diagnose(b)
    assert "--label-file" in run_ablation.argv_for_diagnose(b)
