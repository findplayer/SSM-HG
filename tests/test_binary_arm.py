#!/usr/bin/env python3
"""`--head binary` 二分类臂的回归测试（decisions §31）。

锁住三件事：

1. **「只换输出头」是逐位成立的，不是声明**——同 `torch.manual_seed` 下
   `SSMHG(num_classes=7)` 与 `(num_classes=1)` 的**全部共享张量逐位相同**（`cls` 最后创建，
   不影响初始化消耗），且同一输入下主干输出 `a`（节点可疑度）也逐位相同。
   唯一差异是 `cls.2`（7 行 vs 1 行）——这是本臂"唯一变量 = 输出空间"的机械证明。
2. **标签塌缩只发生在 `stack_labels`**，`build_index` / 划分 / 标签文件不受影响。
3. **端到端产物正确**：日志用 `val_binary_ap`、`thresholds.json` 目标是 `binary_f1`、
   `val_best_probs.pt` 是 `[N,1]`，且**多标签键不出现**（防止把 accuracy 当 micro-F1 读走，§28）。

运行：`pytest tests/test_binary_arm.py -q`
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import metrics  # noqa: E402
from model import SSMHG  # noqa: E402
from dataset import stack_labels  # noqa: E402
from train import class_stats, masked_weighted_bce  # noqa: E402


# --------------------------------------------------------------- 1) 只换输出头（逐位）
def _build(num_classes: int, seed: int = 0) -> SSMHG:
    torch.manual_seed(seed)
    return SSMHG(in_dim=128, hid=128, num_relations=5, num_bases=5,
                 num_classes=num_classes, dropout=0.3)


def test_head_width_leaves_shared_weights_bit_identical():
    """12/12 共享张量逐位相同 ⇒ 两条臂的差异**只**来自 `cls.2`。"""
    s7, s1 = _build(7).state_dict(), _build(1).state_dict()
    shared = [k for k in s7 if s7[k].shape == s1[k].shape]
    assert len(shared) == 12, f"共享张量数变了（{len(shared)}），请复核本测试前提"
    diff = [k for k in shared if not torch.equal(s7[k], s1[k])]
    assert diff == [], f"共享张量不再逐位相同：{diff}"
    assert s7["cls.2.weight"].shape[0] == 7 and s1["cls.2.weight"].shape[0] == 1


def test_backbone_output_identical_across_head_width():
    """同一输入下 `a`（节点可疑度）逐位相同、`z` 宽度 7 vs 1。"""
    m7, m1 = _build(7), _build(1)
    m7.eval(), m1.eval()
    torch.manual_seed(1)
    x = torch.randn(10, 128)
    ei = torch.tensor([[0, 1, 2], [1, 0, 3]])
    et = torch.zeros(3, dtype=torch.long)
    b = torch.zeros(10, dtype=torch.long)
    with torch.no_grad():
        z7, a7, _ = m7(x, ei, et, batch=b)
        z1, a1, _ = m1(x, ei, et, batch=b)
    assert torch.equal(a7, a1)
    assert tuple(z7.shape) == (1, 7) and tuple(z1.shape) == (1, 1)


# --------------------------------------------------------------- 2) 标签塌缩
class _S:
    """最小 GraphSample 替身（只需 `.label`）。"""

    def __init__(self, label):
        self.label = torch.tensor(label, dtype=torch.float32)


def test_stack_labels_collapses_only_for_binary():
    samples = [_S([1, 0, 0, 0, 0, 0, 0]), _S([0, 0, 0, 0, 0, 0, 0]),
               _S([0, 1, 0, 0, 0, 1, 0])]
    multi = stack_labels(samples, head="multi")
    binary = stack_labels(samples, head="binary")
    assert tuple(multi.shape) == (3, 7)
    assert tuple(binary.shape) == (3, 1)
    assert binary.reshape(-1).tolist() == [1.0, 0.0, 1.0]
    assert torch.equal(binary.reshape(-1), multi.any(dim=1).float())
    # 默认即 multi（不传 head 时行为与引入该开关前一致）
    assert torch.equal(stack_labels(samples), multi)


def test_class_stats_and_loss_work_at_c1():
    """`class_stats` / `masked_weighted_bce` 是 C 维通用的，C=1 下无需任何特殊分支。"""
    labels = torch.tensor([[1.], [1.], [0.], [0.], [0.], [0.]])      # 2 正 4 负
    pos_weight, class_mask, active, tp, tn = class_stats(labels, pos_weight_cap=20.0)
    assert tuple(pos_weight.shape) == (1,) and active == 1
    assert float(pos_weight[0]) == pytest.approx(2.0)                 # neg/pos = 4/2
    assert int(tp[0]) == 2 and int(tn[0]) == 4
    z = torch.zeros(6, 1)
    loss = masked_weighted_bce(z, labels, pos_weight, class_mask)
    assert torch.isfinite(loss) and loss.item() > 0


def test_class_stats_raises_when_single_class_has_no_positive():
    """单类无正样本必须**报错**（不静默训练一个什么也学不到的模型）。"""
    labels = torch.zeros(5, 1)
    pos_weight, class_mask, active, _, _ = class_stats(labels)
    assert active == 0
    with pytest.raises(ValueError, match="正样本均为 0"):
        masked_weighted_bce(torch.zeros(5, 1), labels, pos_weight, class_mask)


# --------------------------------------------------------------- 3) 端到端产物
def test_binary_arm_end_to_end_artifacts():
    """真图上的短跑：`--head binary` 的产物必须自洽、且**不含多标签键**。"""
    with tempfile.TemporaryDirectory(dir=REPO / "runs") as td:
        out = Path(td) / "bin"
        # 子进程继承 pytest 环境时会撞上本机 MKL/OpenMP 线程层冲突
        # （`MKL_THREADING_LAYER=INTEL` 与 libgomp 不兼容），改 GNU 层即可；
        # 与 SSM-HG 本身无关，只是让这条端到端测试可复现。
        env = {**os.environ, "MKL_THREADING_LAYER": "GNU"}
        r = subprocess.run(
            [sys.executable, str(REPO / "scripts" / "train.py"),
             "--head", "binary", "--seed", "0", "--limit-graphs", "8", "--epochs", "2",
             "--out-dir", str(out)], cwd=REPO, capture_output=True, text=True, env=env)
        assert r.returncode == 0, (r.stderr or r.stdout)[-1500:]
        run_dir = out / "seed0"

        cfg = json.loads((run_dir / "config.json").read_text(encoding="utf-8"))
        assert cfg["derived"]["head"] == "binary"
        assert cfg["derived"]["num_classes"] == 1
        assert cfg["derived"]["head_class_names"] == [metrics.BINARY_NAME]
        assert cfg["derived"]["label_aggregation"] == "any(targets)"
        assert len(cfg["derived"]["pos_weight"]) == 1

        row = json.loads((run_dir / "log.txt").read_text(encoding="utf-8").splitlines()[0])
        assert "val_binary_ap" in row and "val_binary_f1" in row
        assert row["val_micro_f1"] is None and row["val_macro_f1"] is None

        th = json.loads((run_dir / "thresholds.json").read_text(encoding="utf-8"))
        assert th["metric"] == "binary_f1"
        assert th["best_threshold"] in metrics.THRESHOLD_CANDIDATES

        vb = torch.load(run_dir / "val_best_probs.pt", map_location="cpu")
        assert tuple(vb["probs"].shape)[1] == 1
        assert tuple(vb["labels"].shape)[1] == 1
        # 缓存里的标签必须就是 any(targets)
        assert set(np.unique(vb["labels"].numpy())) <= {0.0, 1.0}
