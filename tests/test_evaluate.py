"""M5 评估单测（手册 12.7；纯逻辑，零真实数据依赖）。

覆盖：
  - rebuild_models：从 config + checkpoint 逐键重建 fuser/model（state_dict 逐位一致）、置 eval；
    `SSMHG(in_dim=fuser.hidden)`（=128，fuser 输出维），`--cb-channels` 消融改变 `fuser.in_dim`
    （融合输入维）但 **fuser.hidden 恒 128**；
  - compute_report：micro/macro-F1、逐类 support、subset accuracy 正确；阈值只做二元化、不进搜索。
  - 阈值搜索只读 val 的口径由 `metrics.search_global_threshold`（已单测）保证；本文件不重复。

运行：pytest tests/test_evaluate.py -q
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from evaluate import compute_report, rebuild_models  # noqa: E402
from model import AblationConfig  # noqa: E402
from train import build_fuser_model  # noqa: E402

LAYOUT = {"visibility": 4, "bool": 14, "call_mode": 5, "position": 1, "ir": 6}


def _config(ablation_args=None) -> dict:
    args = {"ablate_sv": False, "feat_groups": "all", "cb_channels": "cb_func,cb_node",
            "prior_dropout": 0.2, "struct_dropout": 0.2, "hid": 128, "num_bases": 5,
            "model_dropout": 0.3, "conv": "rgcn", "meanpool": False}
    if ablation_args:
        args.update(ablation_args)
    return {"derived": {"D_struct": 30, "struct_layout": LAYOUT}, "args": args}


def test_rebuild_models_state_dict_roundtrip_and_eval_mode():
    cfg = argparse.Namespace(seed=0, prior_dropout=0.2, struct_dropout=0.2,
                             model_dropout=0.3, hid=128, num_bases=5,
                             conv="rgcn", meanpool=False)
    fuser, model = build_fuser_model({"D_struct": 30, "struct_layout": LAYOUT},
                                     AblationConfig(), cfg)
    ck = {"fuser_state_dict": fuser.state_dict(), "model_state_dict": model.state_dict()}
    f2, m2 = rebuild_models(_config(), ck)
    # state_dict 逐键逐位一致
    for k in fuser.state_dict():
        assert torch.equal(fuser.state_dict()[k], f2.state_dict()[k]), f"fuser.{k} 不一致"
    for k in model.state_dict():
        assert torch.equal(model.state_dict()[k], m2.state_dict()[k]), f"model.{k} 不一致"
    assert not f2.training and not m2.training, "重建后必须置 eval"
    assert m2.in_dim == 128 and f2.hidden == 128


def test_rebuild_models_cb_channels_ablation_keeps_hidden_128():
    # --cb-channels cb_node（去函数级 CodeBERT）：融合输入维 1631→863，但输出/SSMHG 输入仍 128
    cfg = argparse.Namespace(seed=0, prior_dropout=0.2, struct_dropout=0.2,
                             model_dropout=0.3, hid=128, num_bases=5,
                             conv="rgcn", meanpool=False)
    ablate = AblationConfig(cb_channels=("cb_node",))
    fuser, model = build_fuser_model({"D_struct": 30, "struct_layout": LAYOUT}, ablate, cfg)
    assert fuser.in_dim == 768 + 64 + 30 + 1 and fuser.hidden == 128
    ck = {"fuser_state_dict": fuser.state_dict(), "model_state_dict": model.state_dict()}
    f2, m2 = rebuild_models(_config({"cb_channels": "cb_node"}), ck)
    assert f2.in_dim == 768 + 64 + 30 + 1 and m2.in_dim == 128
    # 前向：单通道 cb 的输入仍能产出 (N,128)
    g = torch.Generator().manual_seed(0)
    ch = {
        "cb_func": torch.randn(5, 768, generator=g),
        "cb_node": torch.randn(5, 768, generator=g),
        "type_id": torch.randint(0, 9, (5,), generator=g),
        "struct": torch.randn(5, 30, generator=g),
        "sv": torch.rand(5, 1, generator=g),
    }
    assert tuple(f2(ch).shape) == (5, 128)


def test_compute_report_dual_threshold_correctness():
    probs = torch.tensor([[0.9, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1],
                          [0.1, 0.9, 0.1, 0.1, 0.1, 0.1, 0.1],
                          [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]])
    labels = torch.tensor([[1, 0, 0, 0, 0, 0, 0],
                           [0, 1, 0, 0, 0, 0, 0],
                           [0, 0, 0, 0, 0, 0, 0]], dtype=torch.float32)
    rep = compute_report(probs, labels, 0.5)
    assert rep["threshold"] == 0.5
    assert rep["micro_f1"] == pytest.approx(1.0)
    # macro-F1 对全部 7 类平均：仅 2 类有正样本（F1=1），其余 5 类 support=0 → F1=0 → 2/7
    assert rep["macro_f1"] == pytest.approx(2.0 / 7.0)
    assert rep["per_class"]["support"][0] == 1 and rep["per_class"]["support"][1] == 1
    assert rep["per_class"]["support"][2] == 0 and rep["per_class"]["f1"][2] == 0.0
    assert rep["subset_accuracy"] == pytest.approx(1.0)
    # 不同阈值只改变二元化：0.8 会把 0.1 全部判负
    rep2 = compute_report(probs, labels, 0.8)
    assert rep2["threshold"] == 0.8 and rep2["micro_f1"] == pytest.approx(1.0)
