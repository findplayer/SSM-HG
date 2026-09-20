"""RGCN 层数消融（大纲 5.4.1 第 13 项）的回归锁：**L=2 必须与旧版逐位一致**。

**为什么单独立一个文件**：本项改的是 `SSMHG.__init__`/`forward` 的中枢，而"默认值不变"
在这类改动里最容易被破坏且**不报错**——`nn.ModuleList` 会把键名改成 `convs.0.*`
（已有 `best.pt` 全部加载失败）、把 dropout 挪到末层会静默改变数值（指标漂移几个点也看不出）。
故用两条不变量钉死：
  1. **键名集合**：`num_layers=2` 的 `state_dict` 键与旧版完全相同；
  2. **数值**：`num_layers=2` 的前向输出与"手写的旧版两层实现"**逐位相同**（`torch.equal`）。
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import torch
import torch.nn.functional as F

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import model as M     # noqa: E402


def _graph(n: int = 11, e: int = 24, seed: int = 0):
    g = torch.Generator().manual_seed(seed)
    x = torch.randn(n, M.HID_DIM, generator=g)
    ei = torch.randint(0, n, (2, e), generator=g)
    et = torch.randint(0, 5, (e,), generator=g)
    return x, ei, et


def _old_two_layer_forward(m: M.SSMHG, x, ei, et):
    """**旧版**（本次改动前）的两层前向，逐字照抄，作为逐位比对基准。

    旧代码：`relu(conv1) → dropout → relu(conv2)`；即 dropout 只加在非末层。
    """
    if m.conv_type == "rgcn":
        h1 = F.relu(m.conv1(x, ei, et))
        h1 = F.dropout(h1, p=m.dropout, training=m.training)
        h2 = F.relu(m.conv2(h1, ei, et))
    else:
        h1 = F.relu(m.conv1(x, ei))
        h1 = F.dropout(h1, p=m.dropout, training=m.training)
        h2 = F.relu(m.conv2(h1, ei))
    return h1, h2


def test_default_num_layers_is_two():
    assert M.SSMHG().num_layers == 2


def test_state_dict_keys_unchanged_for_two_layers():
    """键名是本项的头号风险：`ModuleList` 会让全部已训练 `best.pt` 加载失败。"""
    keys = set(M.SSMHG().state_dict())
    assert {k.split(".")[0] for k in keys} == {"conv1", "conv2", "a_head", "cls"}
    assert any(k.startswith("conv1.") for k in keys)
    assert any(k.startswith("conv2.") for k in keys)
    assert not any(k.startswith("conv3.") for k in keys)


@pytest.mark.parametrize("conv_type", ["rgcn", "gcn"])
def test_two_layer_forward_is_bitwise_identical_to_old_implementation(conv_type):
    torch.manual_seed(3)
    m = M.SSMHG(conv_type=conv_type).eval()
    x, ei, et = _graph()
    with torch.no_grad():
        out = m(x, ei, et, return_intermediates=True)
        h1_ref, h2_ref = _old_two_layer_forward(m, x, ei, et)
    assert torch.equal(out["h1"], h1_ref), "h1 与旧版不逐位相同"
    assert torch.equal(out["h2"], h2_ref), "h2 与旧版不逐位相同"
    assert out["h_layers"] == [out["h1"], out["h2"]] or (
        out["h_layers"][0] is out["h1"] and out["h_layers"][1] is out["h2"])


@pytest.mark.parametrize("conv_type", ["rgcn", "gcn"])
def test_three_layers_keeps_conv1_conv2_names_and_adds_conv3(conv_type):
    m = M.SSMHG(conv_type=conv_type, num_layers=3)
    keys = set(m.state_dict())
    tops = {k.split(".")[0] for k in keys}
    assert tops == {"conv1", "conv2", "conv3", "a_head", "cls"}, tops
    x, ei, et = _graph()
    with torch.no_grad():
        out = m(x, ei, et, return_intermediates=True)
    # 末层输出 = h2 = Readout 的输入；h1 仍是**首层**输出（不是末层）
    assert len(out["h_layers"]) == 3
    assert torch.equal(out["h2"], out["h_layers"][-1])
    assert not torch.equal(out["h1"], out["h2"]), "三层时 h1 与 h2 不应相同"


def test_one_layer_has_no_conv2_and_readout_uses_the_only_layer():
    m = M.SSMHG(num_layers=1)
    assert m.conv2 is None
    tops = {k.split(".")[0] for k in m.state_dict()}
    assert tops == {"conv1", "a_head", "cls"}, tops
    x, ei, et = _graph()
    with torch.no_grad():
        out = m(x, ei, et, return_intermediates=True)
    assert len(out["h_layers"]) == 1
    assert out["h1"] is out["h2"], "单层时 h1 与 h2 应是同一个张量"
    assert torch.equal(out["h2"], F.relu(m.conv1(x, ei, et)))


def test_parameter_count_is_monotone_in_layers():
    counts = [M.parameter_report(rgcn=M.SSMHG(num_layers=l))["rgcn_params"]
              for l in (1, 2, 3)]
    assert counts[0] < counts[1] < counts[2], counts


def test_invalid_num_layers_rejected():
    for bad in (0, 4, -1):
        with pytest.raises(ValueError, match="num_layers"):
            M.SSMHG(num_layers=bad)


def test_num_relations_six_is_accepted_and_adds_one_basis_row():
    """REV 变体（`ablation_plan` §6.3）：关系 5→6，参数量只多 `num_bases` 个。"""
    m5 = M.SSMHG(num_relations=5)
    m6 = M.SSMHG(num_relations=6)
    assert m6.conv1.comp.shape == (6, 5) and m5.conv1.comp.shape == (5, 5)
    n5 = M.parameter_report(rgcn=m5)["rgcn_params"]
    n6 = M.parameter_report(rgcn=m6)["rgcn_params"]
    assert n6 - n5 == 10, f"6 类关系应只多 2×num_bases=10 个参数，实测 +{n6 - n5}"
    x, ei, et = _graph()
    et6 = torch.randint(0, 6, et.shape, generator=torch.Generator().manual_seed(1))
    with torch.no_grad():
        m6(x, ei, et6)                       # 含编号 5 的边必须能走通
    with pytest.raises(ValueError, match="edge_type"):
        with torch.no_grad():
            m5(x, ei, et6)                   # 5 类模型收到编号 5 → 必须响亮报错
