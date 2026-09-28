"""`--swa-start`（编码器选点改后缀权重平均）的两条守卫。

**为什么值得单测**：这一项是"**在 val 上不可能变差**"的择优逻辑——若 `n` 算错、
或平均不是后缀平均（把早停轮也average进去、或重复计入），读数会**看着正常**地偏移。
与 `improvement_proposals.md` §1.2 的动机（在 45 个 val 合约上挑"最好的那一轮"是又一次最大值选择）配套。
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import finetune_codebert as F                                              # noqa: E402


def test_swa_suffix_average_is_exact_mean():
    """后缀平均 = 逐个 key 的算术平均；且**原地**（不新开张量）。"""
    acc = {"a": torch.tensor([1.0, 3.0]), "b": torch.tensor([[2.0], [4.0]])}
    ids = [id(acc["a"]), id(acc["b"])]
    out = F.swa_suffix_average(acc, 2)
    assert out is acc, "必须原地返回（内存约束）"
    assert [id(out["a"]), id(out["b"])] == ids, "不得替换张量对象"
    assert torch.equal(out["a"], torch.tensor([0.5, 1.5]))
    assert torch.equal(out["b"], torch.tensor([[1.0], [2.0]]))


def test_swa_suffix_average_rejects_zero_count():
    """n=0 会让权重全变 0（静默产出一个空编码器）⇒ 必须硬报错。"""
    with pytest.raises(ValueError):
        F.swa_suffix_average({"a": torch.ones(2)}, 0)


def test_swa_start_defaults_to_off(monkeypatch):
    """🔴 **默认关**：`--swa-start 0` ⇒ 引入该参数前后本脚本行为逐字节相同。

    这条盯的是"新增开关悄悄改了默认路径"——本仓同类事故见 `decisions.md` §31.3。
    """
    monkeypatch.setattr(sys, "argv", ["finetune_codebert.py"])
    assert F.parse_args().swa_start == 0
