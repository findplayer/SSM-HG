"""`_cb.pt` 紧凑性回归锁（`decisions.md` §33）。

**为什么需要**：`encode()` 若返回 `[1, seq_len, 768]` 的**视图**，`torch.save` 会把整块 storage
写进文件——CPU 上每条目按 `seq_len × 3 KB` 落盘而不是 3 KB（实测 ×128 / ×512）。
主库 590 个 `_cb.pt` 曾因此达 **14.61 GB**（真值 0.38 GB）。

这类缺陷**不报错、不改变任何数值**，只吃磁盘——正是本仓反复中招的那一类
（§28 的 `.ravel()`、§29.4 的标签源、§31.3 的守卫漏新键）。故用不变量钉死：
**每条缓存向量的 `untyped_storage().nbytes()` 必须恰等于 `numel()*4`**。
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import torch
import torch.nn as nn

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import m3_build_features as m3          # noqa: E402
import recompact_cb_cache as rc         # noqa: E402

CB_DIM = m3.CB_DIM


class _Out:
    def __init__(self, t):
        self.last_hidden_state = t


class _StubModel(nn.Module):
    """桩：`last_hidden_state` 形状 [1, seq, 768]，与真 CodeBERT 同构。

    ⚠ **必须是确定性的**（固定 buffer，非每次 `randn`）——否则"值没变"这类断言
    会因为两次前向本来就不同而失去意义。
    """

    def __init__(self, seq: int):
        super().__init__()
        self.p = nn.Parameter(torch.zeros(1))
        self.seq = seq
        self.register_buffer("_fixed", torch.randn(1, seq, CB_DIM,
                                                  generator=torch.Generator().manual_seed(7)))

    def forward(self, **_kw):
        return _Out(self._fixed)


def _stub_tok(text, truncation=True, max_length=512, return_tensors="pt"):   # noqa: ARG001
    n = max(1, min(len(text), max_length))
    return {"input_ids": torch.zeros(1, n, dtype=torch.long)}


@pytest.mark.parametrize("max_len", [128, 512])
def test_encode_returns_compact_tensor_not_a_view(max_len):
    """`encode()` 的返回值不得携带超长 storage（否则 `_cb.pt` 膨胀 max_len 倍）。"""
    t = m3.encode("x" * max_len, _stub_tok, _StubModel(max_len), max_len)
    assert tuple(t.shape) == (CB_DIM,)
    assert t.untyped_storage().nbytes() == t.numel() * 4, (
        f"encode 返回的是视图：storage={t.untyped_storage().nbytes()//4} 元素、"
        f"numel={t.numel()}——`_cb.pt` 会膨胀 {max_len} 倍（decisions §33）")


def test_encode_empty_text_is_already_compact():
    t = m3.encode("", _stub_tok, _StubModel(8), 128)
    assert t.untyped_storage().nbytes() == t.numel() * 4


def test_encode_value_matches_the_cls_slice():
    """紧凑化不得改变数值：返回的仍是 `[CLS]`（索引 0）那一行。"""
    torch.manual_seed(0)
    model = _StubModel(37)
    t = m3.encode("y" * 37, _stub_tok, model, 128)
    with torch.no_grad():
        ref = model(**{"input_ids": torch.zeros(1, 37, dtype=torch.long)}).last_hidden_state
    assert torch.equal(t, ref[0, 0, :])


def _write_bloated(path: Path, seq: int = 64) -> dict:
    """造一个"膨胀"缓存：条目是 [1, seq, 768] 的视图，值可复现。"""
    g = torch.Generator().manual_seed(1)
    base = torch.randn(1, seq, CB_DIM, generator=g)
    cache = {"func": {"c::f": base[0][0]}, "node": {str(i): base[0][i + 1] for i in range(3)}}
    torch.save(cache, path)
    return cache


def test_recompact_preserves_values_bitwise(tmp_path):
    path = tmp_path / "g_cb.pt"
    orig = _write_bloated(path)
    before = path.stat().st_size

    r = rc.recompact_one(path)
    assert r["ok"], r
    assert path.stat().st_size < before

    back = torch.load(path, map_location="cpu")
    assert set(back["func"]) == set(orig["func"]) and set(back["node"]) == set(orig["node"])
    for ch in ("func", "node"):
        for k, v in orig[ch].items():
            assert torch.equal(back[ch][k], v), f"{ch}[{k}] 值变了"
            assert back[ch][k].untyped_storage().nbytes() == v.numel() * 4


def test_recompact_is_idempotent(tmp_path):
    path = tmp_path / "g_cb.pt"
    _write_bloated(path)
    assert rc.recompact_one(path)["ok"]
    size1 = path.stat().st_size
    assert rc.recompact_one(path)["ok"]
    assert path.stat().st_size == size1, "已紧凑的缓存再跑一次不应改变体积"


def test_recompact_rejects_non_cb_structure(tmp_path):
    path = tmp_path / "bad_cb.pt"
    torch.save({"something": "else"}, path)
    r = rc.recompact_one(path)
    assert not r["ok"] and "结构" in r["reason"]
    assert torch.load(path, map_location="cpu") == {"something": "else"}, "拒绝时不得改动原文件"


def test_recompact_dry_run_does_not_write(tmp_path):
    path = tmp_path / "g_cb.pt"
    _write_bloated(path)
    before = path.stat().st_size
    r = rc.recompact_one(path, dry_run=True)
    assert r["ok"] and r["dry_run"]
    assert path.stat().st_size == before
