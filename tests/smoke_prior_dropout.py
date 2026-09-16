"""小 smoke：验证真实训练循环里的 dropout 行为（丢弃率语义 + eval 不置零 + p=0 关闭）。

monkeypatch `train.sample_dropout_masks`（记录实际置零率）、`train.collate` 与
`NodeFuser.forward`（判断每次前向属训练批还是验证批、有没有传掩码），跑极小真实训练。
输出到 /tmp，不写仓库产物。
"""
import sys
from pathlib import Path
REPO = Path("/home/saumarez/projects/deep-learning/SSM-HG")
sys.path.insert(0, str(REPO / "scripts"))

import torch  # noqa: E402
import train  # noqa: E402
from model import NodeFuser  # noqa: E402

events, samples = [], []

_orig_sample = train.sample_dropout_masks
def rec_sample(n, *, prior_p, struct_p, generator=None):
    m, s = _orig_sample(n, prior_p=prior_p, struct_p=struct_p, generator=generator)
    samples.append((n, prior_p, struct_p, float((m == 0).float().mean()),
                    float((s == 0).float().mean())))
    return m, s
train.sample_dropout_masks = rec_sample

_orig_collate = train.collate
def rec_collate(chunk, **kw):
    events.append(("collate", bool(kw.get("training", False))))
    return _orig_collate(chunk, **kw)
train.collate = rec_collate

_orig_fwd = NodeFuser.forward
def rec_fwd(self, ch, *, prior_mask=None, struct_mask=None, batch=None):
    events.append(("fwd", prior_mask is None, struct_mask is None))
    return _orig_fwd(self, ch, prior_mask=prior_mask, struct_mask=struct_mask, batch=batch)
NodeFuser.forward = rec_fwd


def run(pd_value: str, tag: str):
    events.clear(); samples.clear()
    sys.argv = ["train.py", "--seed", "0", "--epochs", "15", "--limit-graphs", "96",
                "--graph-dir", "products/alldata/graphs", "--split-dir", "products/alldata/splits",
                "--out-dir", f"/tmp/smoke_pd_{tag}", "--prior-dropout", pd_value]
    try:
        train.main()
    except SystemExit:
        pass
    n_draws = sum(n for n, *_ in samples)
    pr = sum(n * dp for n, _, _, dp, _ in samples) / n_draws
    sr = sum(n * ds for n, _, _, _, ds in samples) / n_draws
    # 训练批是否带掩码 / 验证批是否不带
    viol = []
    for i, e in enumerate(events):
        if e[0] != "fwd":
            continue
        phase = next((events[j][1] for j in range(i - 1, -1, -1) if events[j][0] == "collate"), None)
        if phase is True and e[1]:
            viol.append("训练批未传掩码")
        if phase is False and not e[1]:
            viol.append("验证批传了掩码")
    n_tr = sum(1 for i, e in enumerate(events) if e[0] == "fwd" and e[1] is False)
    n_va = sum(1 for i, e in enumerate(events) if e[0] == "fwd" and e[1] is True)
    print(f"\n[{tag}] prior-dropout={pd_value}")
    print(f"  采样 {len(samples)} 次 / {n_draws} 个图；传入 prior_p 集合 = {sorted({p for _,p,_,_,_ in samples})}")
    print(f"  实测置零率：prior={pr:.4f}  struct={sr:.4f}")
    print(f"  前向：训练批 {n_tr}（应全带掩码）、验证批 {n_va}（应全不带掩码）；违规 {viol or '无 ✓'}")
    assert not viol, viol
    return pr, sr


print("=== 第 1 轮：默认 0.2 ===")
pr, sr = run("0.2", "p02")
# 15 epoch × 3 batch × 96 图 ≈ 4320 次抽样 → p=0.2 的二项 std ≈ 0.006
assert abs(pr - 0.2) < 0.03, f"prior 置零率 {pr} 偏离 0.2 过多"
assert abs(sr - 0.2) < 0.03, f"struct 置零率 {sr} 偏离 0.2 过多"

print("\n=== 第 2 轮：--prior-dropout 0（应「关闭」，一个图都不置零） ===")
pr0, sr0 = run("0", "p00")
assert pr0 == 0.0, f"prior 置零率应为 0，实测 {pr0}"
# 该轮只改了 --prior-dropout，--struct-dropout 仍是默认 0.2 → struct 应保持 ≈0.2
# （这恰好也证明两个开关在 CLI 上相互独立）
assert abs(sr0 - 0.2) < 0.03, f"struct 未被改动，应保持 ≈0.2，实测 {sr0}"

print("\n  ✓ 训练期置零率 ≈ 0.2（丢弃率语义）")
print("  ✓ 验证批从不传掩码 → eval 不置零")
print("  ✓ --prior-dropout 0 关闭随机正则（掩码恒 1、s_v 原值参与），与 --ablate-sv 的确定性全零不同")
