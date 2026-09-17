"""`diagnose.py` 标签来源解析单测（纯函数、零数据依赖）。

**为什么单测这一条**：`diagnose.py` 原以 `build_index(graph_dir)` 取标签、不接受
`--label-file`/`--label-key-mode`（2026-09-17 修复），即硬编码主库标签源。对第二语料
（augmentation）跑时它会拿主库标签匹配该语料的图 base —— **全部对不上却不报错**，
产出看似正常、实则错位的逐类诊断。这类"不报错的错"是本仓最难发现的失效模式，
故把优先级规则钉成测试。

优先级（与 `evaluate.py::eval_seed` 完全一致）：**CLI → 环境变量 → checkpoint 的 label_source**。

运行：`pytest tests/test_diagnose.py -q`
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import diagnose  # noqa: E402
from dataset import ENV_LABEL_FILE, ENV_LABEL_KEY_MODE  # noqa: E402


class _Args:
    """最小 argparse 替身（只需两个属性）。"""

    def __init__(self, label_file=None, label_key_mode=None):
        self.label_file = label_file
        self.label_key_mode = label_key_mode


@pytest.fixture(autouse=True)
def _clear_env(monkeypatch):
    """隔离宿主环境：SSMHG_LABEL_* 若在外部被设过，会让测试结果依赖运行环境。"""
    monkeypatch.delenv(ENV_LABEL_FILE, raising=False)
    monkeypatch.delenv(ENV_LABEL_KEY_MODE, raising=False)


def test_cli_wins_over_env_and_checkpoint(monkeypatch):
    monkeypatch.setenv(ENV_LABEL_FILE, "/env/labels.json")
    monkeypatch.setenv(ENV_LABEL_KEY_MODE, "project")
    cfg = {"label_source": {"file": "/ckpt/labels.json", "key_mode": "project"}}
    got = diagnose.resolve_label_source(_Args("/cli/labels.json", "stem"), cfg)
    assert got == ("/cli/labels.json", "stem")


def test_env_wins_over_checkpoint(monkeypatch):
    monkeypatch.setenv(ENV_LABEL_FILE, "/env/labels.json")
    monkeypatch.setenv(ENV_LABEL_KEY_MODE, "stem")
    cfg = {"label_source": {"file": "/ckpt/labels.json", "key_mode": "project"}}
    assert diagnose.resolve_label_source(_Args(), cfg) == ("/env/labels.json", "stem")


def test_checkpoint_is_fallback():
    """跨语料的关键路径：命令行什么都不传时，必须靠 checkpoint 记录把语料认回来。"""
    cfg = {"label_source": {"file": "/ckpt/aug_labels.json", "key_mode": "stem"}}
    assert diagnose.resolve_label_source(_Args(), cfg) == ("/ckpt/aug_labels.json", "stem")


def test_nothing_specified_returns_none():
    """三者皆无 → 返回 (None, None)，交给 build_index 默认值 + 后续硬校验兜底。

    ⚠ 刻意**不在此处回退到主库默认路径**：静默回退正是原缺陷的形态。
    """
    assert diagnose.resolve_label_source(_Args(), {}) == (None, None)
    assert diagnose.resolve_label_source(_Args(), {"label_source": None}) == (None, None)


def test_partial_spec_does_not_cross_contaminate(monkeypatch):
    """只传了 key_mode 时，file 仍应从下一优先级取（两个字段独立解析）。"""
    monkeypatch.setenv(ENV_LABEL_FILE, "/env/labels.json")
    cfg = {"label_source": {"file": "/ckpt/labels.json", "key_mode": "project"}}
    assert diagnose.resolve_label_source(_Args(label_key_mode="stem"), cfg) == \
        ("/env/labels.json", "stem")
