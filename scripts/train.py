#!/usr/bin/env python3
"""M5 训练闭环（手册 10.3/10.4/12.6；大纲改II 4.5.1；`docs/M5_dev_plan.md` §5）。

契约（只 import `model`/`dataset`/`metrics`/stdlib；**不引入 PyG DataLoader**）：
  - 数据 = `dataset.load_graph` 的 `GraphSample` 列表（通道字典 + 边 + 标签），一次性进内存；
  - 批图 = **自实现 collate**：通道沿节点维 cat + `edge_index` 加节点偏移 + `edge_type` cat +
    batch 向量 + labels stack；DropEdge 先逐图 mask 再 batch（`model.apply_edge_mask`），随机流 =
    `(train_seed, epoch)` 构造的 `torch.Generator`（顺序 = DropEdge → prior → struct，逐图独立）；
  - **双模块** `fuser`(NodeFuser) + `model`(SSMHG)：`SSMHG(in_dim=fuser.in_dim)` 从融合层回读维度，
    不硬编码 1631/128；checkpoint 必须同时存两者 `state_dict`；
  - 损失 = masked 加权分类损失（`--loss bce`（主实验默认）/`focal`/`asl` 只改调制因子，加权结构与
    class_mask 不变；`pos_weight` 截断默认 20、`--pos-weight-cap 0` 放开；零正类用 `class_mask` 显式跳过）
    + `lambda_var·L_var`；
    `L_var` 按图 population std（不 detach），单节点 std=0、空图报错；
  - 优化 AdamW + `clip_grad_norm_(1.0)` + `ReduceLROnPlateau(mode="max")` 监控 **val micro-F1**；
    早停 = 连续 `--early-stop-patience` epoch 不提升；
  - 训练期先验/结构 dropout：`sample_dropout_masks` 逐图采样，随 batch 传入 `NodeFuser`；验证不传掩码；
  - 日志 JSONL（每 epoch 一行）：epoch/loss_total/loss_cls/loss_var/**score_mean/score_std**（训练期
    a_v 统计，见 10.4 骨架）/val_macro_f1/val_micro_f1/lr/epoch_seconds/samples_processed（累计节点）/
    graphs_processed（累计图）/gpu_mem_allocated（CPU 为 null）；
  - 种子语义（`experiments/decisions.md` §16）：`--seed`=训练种子（SSMHG 初始化/先验+结构 dropout/
    训练集打乱/DropEdge 随机流）、`--split-seed`（默认=`--seed`）读 `split_seed{split_seed}.json`。

产物（`runs/seed{seed}/`）：`config.json`（全量参数+派生量+环境/计时）、`log.txt`（epoch JSONL）、
`best.pt`/`last.pt`（fuser+model+optimizer+config+seed）、`val_best_probs.pt`（best epoch 的 val
probs/labels/threshold，供 evaluate 复用免重复推理）、`thresholds.json`（best epoch 全候选扫描）。
`results.json`（内部测试双报告）由 `evaluate.py` 写，本文件不写。

smoke：`python scripts/train.py --seed 0 --limit-graphs 1 --epochs 2` 完成前向/反向/checkpoint/日志。
"""

from __future__ import annotations

import argparse
import json
import platform
import random
import time
from pathlib import Path

import hashlib

import torch
import torch.nn.functional as F

import metrics
import run_guard
from dataset import (DEFAULT_GRAPH_DIR, Ablation, build_index, collate,
                     load_graph, resolve_label_file, resolve_label_key_mode)
from model import (AblationConfig, NodeFuser, SSMHG, parameter_report,
                   sample_dropout_masks)

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
DEFAULT_SPLIT_DIR = f"{BASE}/products/alldata/splits"
DEFAULT_OUT_DIR = f"{BASE}/runs"
NUM_CLASSES = 7
NUM_RELATIONS = 5
STD_EPS = 1e-8          # 开方内 eps：防 std=0（单节点图）时 sqrt 反向梯度 NaN；前向值 ≈0 不变语义


# --------------------------------------------------------------------------- 纯函数（可单测）
def class_stats(labels: torch.Tensor, pos_weight_cap: float = 20.0):
    """训练集类别统计 → (pos_weight[7], class_mask[7], active_count, train_pos, train_neg)。

    pos_weight_c = min(neg_c/pos_c, pos_weight_cap)（pos_c>0；pos_weight_cap<=0 时不截断）；
    pos_c==0 → pos_weight=0 且 class_mask=0（从逐元素 BCE 的分子分母显式排除，
    **不传 pos_weight=0 给 BCE**，decisions §2）。默认 cap=20（主实验）；`--pos-weight-cap 0`
    放开截断（消融欠置信根因，稀有类真实负正比 88–178 全量生效）。
    """
    train_pos = labels.sum(0)
    n = float(labels.shape[0])
    train_neg = n - train_pos
    ratio = train_neg / train_pos.clamp(min=1.0)
    if pos_weight_cap > 0:
        ratio = torch.clamp(ratio, max=pos_weight_cap)
    pos_weight = torch.where(
        train_pos > 0,
        ratio,
        torch.zeros_like(train_pos))
    class_mask = (train_pos > 0).float()
    active_count = int(class_mask.sum())
    return pos_weight, class_mask, active_count, train_pos, train_neg


def masked_weighted_bce(z: torch.Tensor, labels: torch.Tensor,
                        pos_weight: torch.Tensor, class_mask: torch.Tensor,
                        loss: str = "bce", focal_gamma: float = 2.0,
                        asl_gamma_pos: float = 1.0, asl_gamma_neg: float = 4.0,
                        asl_clip: float = 0.05) -> torch.Tensor:
    """逐元素 masked 加权损失（分母恒为 B × active_class_count）。

    `loss="bce"`（主实验默认，decisions §2）= 加权 BCE，无平滑项；
    `loss="focal"` = 在加权 BCE 上乘调制因子 `(1-p_t)^gamma`（gamma=focal_gamma）；
    `loss="asl"` = 非对称损失（Ben-Baruch et al. 2020）：正项 `(1-p)^g_pos·BCE`、负项
      `(p_m)^g_neg·BCE`，`p_m = max(p - clip, 0)`（clip 为负样本概率裕度）。

    **三条损失共用同一加权结构**（正样本 × `pos_weight`、负样本 ×1）与同一 class_mask，因此
    三者之间**唯一的差异就是调制因子**——这是把「损失形状」与「类别加权」两个变量隔离开的必要条件。
    分母不变（B × active_class_count）：不采用 ASL 原文的「按正样本数归一」，否则总损失尺度随损失
    形状变化，会与 lr/早停混在一起无法归因。代价是 focal/ASL 的梯度幅度小于 BCE，属预期。
    概率项用 `logsigmoid`/`softplus` 表达以避免 `log(0)`（`p` 恰为 0/1 时不产生 NaN/Inf）。
    """
    active_count = int(class_mask.sum())
    if active_count <= 0:
        raise ValueError("所有类别正样本均为 0，无法训练（应报错而非静默）")
    weight = labels * pos_weight + (1.0 - labels)                            # 正样本×pos_weight、负样本×1
    if loss == "bce":
        bce = F.binary_cross_entropy_with_logits(z, labels, reduction="none")   # [B,7]
    else:
        # 数值稳定：-log sigmoid(z) = softplus(-z)；-log(1-sigmoid(z)) = softplus(z)
        neg_log_p = F.softplus(-z)      # = -log p
        neg_log_1mp = F.softplus(z)     # = -log(1-p)
        bce = labels * neg_log_p + (1.0 - labels) * neg_log_1mp
        if loss == "focal":
            p = torch.sigmoid(z)
            p_t = labels * p + (1.0 - labels) * (1.0 - p)   # 预测该标签「真值那一侧」的概率
            bce = bce * (1.0 - p_t).pow(focal_gamma)
        elif loss == "asl":
            p = torch.sigmoid(z)
            p_m = torch.clamp(p - asl_clip, min=0.0)        # 负样本概率裕度
            mod = labels * (1.0 - p).pow(asl_gamma_pos) + \
                (1.0 - labels) * p_m.pow(asl_gamma_neg)
            bce = bce * mod
        else:
            raise ValueError(f"未知 loss='{loss}'（应为 bce/focal/asl）")
    masked = bce * weight * class_mask
    return masked.sum() / (labels.shape[0] * active_count)


def per_graph_population_std(a: torch.Tensor, batch: torch.Tensor, n_graphs: int) -> torch.Tensor:
    """按图 population std（unbiased=False，等价 torch.std；**不 detach**，decisions §3）。

    a:[N]、batch:[N] long → [n_graphs]。用 sum/sum-of-squares/count 分组；n==1 → std=0（精确），
    n==0 → 报错。var 做非负 clamp 再开方，防浮点负零。
    """
    if n_graphs <= 0 or int(a.numel()) == 0:
        raise ValueError("per_graph_population_std：空输入（无图或无节点）")
    cnt = torch.zeros(n_graphs, dtype=a.dtype, device=a.device)
    cnt.index_add_(0, batch, torch.ones_like(a))
    if bool((cnt <= 0).any()):
        raise ValueError("per_graph_population_std：存在节点数为 0 的空图")
    s = torch.zeros(n_graphs, dtype=a.dtype, device=a.device)
    s.index_add_(0, batch, a)
    ss = torch.zeros(n_graphs, dtype=a.dtype, device=a.device)
    ss.index_add_(0, batch, a * a)
    mean = s / cnt
    var = torch.clamp(ss / cnt - mean * mean, min=0.0)
    return torch.sqrt(var + STD_EPS)


def build_fuser_model(meta: dict, ablation: AblationConfig, cfg: argparse.Namespace):
    """从图 meta 读取维度 → (fuser, model)。`SSMHG(in_dim=fuser.in_dim)` 回读，不硬编码。

    顺序：先建 fuser（内部 fork_rng、不动全局 RNG），再 `torch.manual_seed(seed)` 建 SSMHG
    （训练种子只控制 SSMHG 初始化 + 训练期随机流；fuser 初始化由固定 FUSER_INIT_SEED 决定）。
    """
    d_struct = int(meta["D_struct"])
    struct_layout = dict(meta["struct_layout"])
    fuser = NodeFuser(d_struct, struct_layout, ablate=ablation,
                      prior_dropout=cfg.prior_dropout, struct_dropout=cfg.struct_dropout)
    torch.manual_seed(cfg.seed)
    # SSMHG 接收 fuser 的**输出** h_v^(0) ∈ R^128 → in_dim = fuser.hidden（而非融合输入 fuser.in_dim=1631）。
    model = SSMHG(in_dim=fuser.hidden, hid=cfg.hid, num_relations=NUM_RELATIONS,
                  num_bases=cfg.num_bases, num_classes=NUM_CLASSES, dropout=cfg.model_dropout,
                  conv_type=cfg.conv, use_meanpool=cfg.meanpool)
    return fuser, model


def _to_list(t: torch.Tensor) -> list:
    return [round(float(v), 6) for v in t.detach().cpu().tolist()]


def _int_list(t: torch.Tensor) -> list:
    return [int(v) for v in t.detach().cpu().tolist()]


def parse_args() -> argparse.Namespace:
    """CLI（对齐 `docs/M5_dev_plan.md` §5.6；消融开关透传到 dataset/model）。"""
    p = argparse.ArgumentParser(description="M5 train: graph-level 7-way multi-label classification.")
    p.add_argument("--seed", type=int, default=0, help="训练种子（SSMHG 初始化/dropout/打乱/DropEdge）。")
    p.add_argument("--split-seed", type=int, default=None,
                   help="读 split_seed{split-seed}.json；默认 = --seed（decisions §16）。")
    p.add_argument("--epochs", type=int, default=200)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--weight-decay", type=float, default=1e-4)
    p.add_argument("--lambda-var", type=float, default=1e-3, help="L_var 系数（消融 --lambda-var 0）。")
    p.add_argument("--tau-var", type=float, default=0.1)
    p.add_argument("--pos-weight-cap", type=float, default=20.0,
                   help="pos_weight 截断上限（decisions §2）；0 或负数 = 不截断（放开，稀有类真实负正比全量生效）。")
    p.add_argument("--loss", choices=["bce", "focal", "asl"], default="bce",
                   help="分类损失形状（默认 bce=主实验口径）；focal/asl 仅改调制因子，加权结构不变。")
    p.add_argument("--focal-gamma", type=float, default=2.0, help="focal 调制指数（--loss focal）。")
    p.add_argument("--asl-gamma-pos", type=float, default=1.0, help="ASL 正样本指数（--loss asl）。")
    p.add_argument("--asl-gamma-neg", type=float, default=4.0, help="ASL 负样本指数（--loss asl）。")
    p.add_argument("--asl-clip", type=float, default=0.05, help="ASL 负样本概率裕度 m（--loss asl）。")
    p.add_argument("--prior-dropout", type=float, default=0.2, help="消融 --prior-dropout 0。")
    p.add_argument("--struct-dropout", type=float, default=0.2)
    p.add_argument("--model-dropout", type=float, default=0.3)
    p.add_argument("--scheduler-patience", type=int, default=3)
    p.add_argument("--early-stop-patience", type=int, default=5)
    p.add_argument("--drop-edge-prob", type=float, default=0.0, help="DropEdge（默认关，先单图 mask 再 batch）。")
    p.add_argument("--limit-graphs", type=int, default=0,
                   help="小样：只取前 N 个 train/val 图（smoke）。0=全量。")
    p.add_argument("--drop-edges", default="", help="边级消融：逗号分隔物理关系编号（白名单外报错）。")
    p.add_argument("--drop-ast", action="store_true", help="边级消融：删 relation 1+2（AST_PARENT+AST_PARENT_SAME）。")
    p.add_argument("--conv", choices=["rgcn", "gcn"], default="rgcn")
    p.add_argument("--meanpool", action="store_true")
    p.add_argument("--num-bases", type=int, default=5)
    p.add_argument("--hid", type=int, default=128)
    p.add_argument("--ablate-sv", action="store_true", help="特征消融：s_v 通道恒零（AblationConfig）。")
    p.add_argument("--cb-channels", default="cb_func,cb_node",
                   help="特征消融：参与拼接的 CodeBERT 通道子集（逗号分隔，如 cb_node=去函数级）。")
    p.add_argument("--feat-groups", choices=["all", "base", "base+sem"], default="all")
    p.add_argument("--deterministic", action="store_true", help="完整确定性开关（非主实验默认）。")
    p.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR)
    p.add_argument("--split-dir", default=DEFAULT_SPLIT_DIR)
    p.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    p.add_argument("--label-file", default=None,
                   help="标签文件路径（省略则走 SSMHG_LABEL_FILE 环境变量，再默认主库 "
                        "contract_labels.json）。跑第二语料时**必须**与新语料的划分一致。")
    p.add_argument("--label-key-mode", choices=["project", "stem"], default=None,
                   help="标签键模式（省略则走 SSMHG_LABEL_KEY_MODE，再默认 project）。"
                        "扁平/词干命名语料（augmentation）必须传 stem，否则键对不上。")
    p.add_argument("--verify-channel-hash", action="store_true", help="额外校验 cb 两通道哈希。")
    p.add_argument("--overwrite", action="store_true",
                   help="允许覆盖已存在的 <out-dir>/seed{N}/。**默认拒绝**：若该目录已有 "
                        "config.json 且本次参数与产出它的那次不同，直接报错退出（防止换数据集或"
                        "做消融时无声销毁 runs/seed{0,1,2}/ 的正典结果）。")
    return p.parse_args()


def _load_split_samples(split_path: str, graph_dir: str, ab: Ablation, index: dict,
                        verify: str, limit: int):
    """读 split json → 按序 load_graph（train/val 各限前 `limit` 个）。返回 (train, val, meta)。

    先做「划分内 base 是否都在标签索引里」的硬校验：标签文件/键模式错配时，
    下游 `index[b]` 只会抛裸 `KeyError`（看不出根因），这里提前给出可诊断的报错。
    """
    with open(split_path, encoding="utf-8") as fh:
        split = json.load(fh)
    missing = [b for b in split["train"] + split["val"] if b not in index]
    if missing:
        raise SystemExit(
            f"[train] 划分内有 {len(missing)}/{len(split['train']) + len(split['val'])} 个合约"
            f"不在标签索引中（标签文件或 --label-key-mode 与划分不一致？）例：{missing[:5]}")
    if not limit:
        missing_test = [b for b in split.get("test", []) if b not in index]
        if missing_test:
            raise SystemExit(f"[train] test 划分内有 {len(missing_test)} 个合约不在标签索引中；"
                             f"例：{missing_test[:5]}")
    # --limit-graphs 为 smoke 专用：取前 N 个**含正样本**的 train 图（保证 masked BCE 的
    # active_count>0，否则前若干图多为全零样本会触发「全零正类报错」）；val 直接取前 N 个。
    if limit:
        train_bases = [b for b in split["train"] if any(index[b])][:limit]
        val_bases = split["val"][:limit]
    else:
        train_bases = split["train"]
        val_bases = split["val"]
    train = [load_graph(b, graph_dir=graph_dir, ab=ab, index=index, verify_channels=verify)
             for b in train_bases]
    val = [load_graph(b, graph_dir=graph_dir, ab=ab, index=index, verify_channels=verify)
           for b in val_bases]
    meta = train[0].meta
    for s in train + val:
        assert int(s.meta["D_struct"]) == int(meta["D_struct"]) and \
            s.meta["struct_layout"] == meta["struct_layout"], \
            "train/val 图之间的 D_struct/struct_layout 不一致（数据契约破坏）"
    return train, val, meta


def run_dir_conflict(run_dir: Path, args: argparse.Namespace, split_seed: int) -> str | None:
    """既有 `runs/seed{N}/` 是否与本次调用属于**同一次实验**；不同则返回差异描述。

    判定依据 = 已保存的 `config.json`（`args` + `split_seed`）。任一**双方都记录过**的键不同，
    就说明本次要跑的不是产出该目录的那次实验；直接覆盖会**无声销毁**已报告的结果
    （`runs/seed{0,1,2}/` 是论文正典，消融/换数据集必须另开 `--out-dir`）。

    比较逻辑（含路径归一化）复用 `run_guard`：命令行常传相对路径而 config 记的是绝对路径，
    不归一化会把"同一个目录"误判成冲突（2026-09-16 实测踩到）。
    返回 None = 无冲突（目录不存在或逐项相同）。
    """
    prev = run_dir / "config.json"
    if not prev.exists():
        return None
    old = run_guard.read_record(prev)
    if isinstance(old, str):                      # 坏文件 → 宁可疑，不可无声覆盖
        return old
    diffs = run_guard.diff_args(old.get("args"), vars(args))
    if old.get("split_seed") != split_seed:
        diffs.insert(0, f"split_seed: {old.get('split_seed')!r} → {split_seed!r}")
    return "；".join(diffs) if diffs else None


def main() -> None:
    args = parse_args()
    split_seed = args.split_seed if args.split_seed is not None else args.seed
    if args.deterministic:
        torch.set_num_threads(1)
        torch.manual_seed(args.seed)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    run_dir = Path(args.out_dir) / f"seed{args.seed}"
    conflict = run_dir_conflict(run_dir, args, split_seed)
    if conflict and not args.overwrite:
        raise SystemExit(run_guard.guard_message(
            str(run_dir), [conflict],
            "换数据集/做消融请改用 `--out-dir <新臂名>`（runs/seed{0,1,2}/ 是论文正典）；"
            "确实要覆盖时加 `--overwrite`。"))
    if conflict:
        print(run_guard.warn_message(str(run_dir), [conflict]), flush=True)
    run_dir.mkdir(parents=True, exist_ok=True)
    t_run_start = time.perf_counter()

    # ---- 数据加载（计时）----
    t0 = time.perf_counter()
    index, unmatched = build_index(Path(args.graph_dir),
                                   label_file=args.label_file,
                                   key_mode=args.label_key_mode)
    ab = Ablation(drop_edges={int(t) for t in args.drop_edges.split(",") if t.strip()},
                  drop_ast=args.drop_ast)
    verify = "all" if args.verify_channel_hash else "cheap"
    train_samples, val_samples, meta = _load_split_samples(
        f"{args.split_dir}/split_seed{split_seed}.json", args.graph_dir, ab, index,
        verify, args.limit_graphs)
    data_load_seconds = time.perf_counter() - t0

    # ---- 模型组装（维度从 meta 回读）----
    ablation = AblationConfig(ablate_sv=args.ablate_sv, feat_groups=args.feat_groups,
                              cb_channels=tuple(args.cb_channels.split(",")))
    fuser, model = build_fuser_model(meta, ablation, args)
    fuser.to(device)
    model.to(device)

    # ---- 类别统计（只用训练集）----
    train_labels = torch.stack([s.label for s in train_samples])
    pos_weight, class_mask, active_count, train_pos, train_neg = class_stats(
        train_labels, pos_weight_cap=args.pos_weight_cap)
    active_classes = [i for i in range(NUM_CLASSES) if int(class_mask[i]) == 1]
    skipped_classes = [i for i in range(NUM_CLASSES) if int(class_mask[i]) == 0]

    params = list(fuser.parameters()) + list(model.parameters())
    opt = torch.optim.AdamW(params, lr=args.lr, weight_decay=args.weight_decay)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        opt, mode="max", factor=0.5, patience=args.scheduler_patience)

    # ---- config（全量参数 + 派生量 + 环境；计时在结束追加）----
    label_path = resolve_label_file(args.label_file)
    label_source = {
        "file": str(label_path),
        "sha256": hashlib.sha256(label_path.read_bytes()).hexdigest()
        if label_path.exists() else None,
        "key_mode": resolve_label_key_mode(args.label_key_mode),
        "n_index": len(index),
        "n_unmatched": len(unmatched),
    }
    config = {
        "args": vars(args),
        "split_seed": split_seed,
        "label_source": label_source,
        "derived": {
            "D_struct": int(meta["D_struct"]),
            "struct_layout": meta["struct_layout"],
            "fuser_in_dim": fuser.in_dim,          # 融合 Linear 输入维（主配置 1631；--cb-channels 消融会变）
            "fuser_hidden": fuser.hidden,          # fuser 输出维 = SSMHG 输入维（恒 128）
            "num_relations": NUM_RELATIONS,
            "num_classes": NUM_CLASSES,
            "pos_weight": _to_list(pos_weight),
            "class_mask": _to_list(class_mask),
            "active_classes": active_classes,
            "skipped_classes": skipped_classes,
            "train_pos": _int_list(train_pos),
            "train_neg": _int_list(train_neg),
            "train_graphs": len(train_samples),
            "val_graphs": len(val_samples),
            "parameter_report": parameter_report(fuser=fuser, rgcn=model),
        },
        "environment": {
            "device": device,
            "torch_version": torch.__version__,
            "python_version": platform.python_version(),
            "torch_num_threads": torch.get_num_threads(),
        },
    }

    # ---- 训练设备：损失权重随 batch 上 device（模型在组装后已 .to(device)）----
    pos_weight = pos_weight.to(device)
    class_mask = class_mask.to(device)

    # ---- 训练循环 ----
    best_micro_f1 = float("-inf")
    best_val_probs = None
    bad_epochs = 0
    train_seconds = 0.0
    validation_seconds = 0.0
    train_graphs_total = 0
    cum_nodes = 0
    log_lines: list[str] = []

    for epoch in range(args.epochs):
        t_epoch = time.perf_counter()

        # -------- 训练 --------
        model.train()
        fuser.train()
        order = list(range(len(train_samples)))
        random.Random(args.seed * 100000 + epoch).shuffle(order)
        gen = torch.Generator().manual_seed(args.seed * 100000 + epoch)
        tot = {"loss_total": 0.0, "loss_cls": 0.0, "loss_var": 0.0,
               "score_mean": 0.0, "score_std": 0.0}
        n_batches = 0
        t_train = time.perf_counter()
        for i in range(0, len(order), args.batch_size):
            samples = [train_samples[j] for j in order[i:i + args.batch_size]]
            B = len(samples)
            channels, ei, et, batch, labels = collate(
                samples, drop_edge_prob=args.drop_edge_prob, generator=gen,
                training=True, device=device)
            prior_mask, struct_mask = sample_dropout_masks(
                B, prior_p=args.prior_dropout, struct_p=args.struct_dropout, generator=gen)
            prior_mask = prior_mask.to(device)
            struct_mask = struct_mask.to(device)
            x = fuser(channels, prior_mask=prior_mask, struct_mask=struct_mask, batch=batch)
            z, a, _ = model(x, ei, et, batch=batch)
            loss_cls = masked_weighted_bce(
                z, labels, pos_weight, class_mask, loss=args.loss,
                focal_gamma=args.focal_gamma, asl_gamma_pos=args.asl_gamma_pos,
                asl_gamma_neg=args.asl_gamma_neg, asl_clip=args.asl_clip)
            std = per_graph_population_std(a, batch, B)
            loss_var = torch.relu(args.tau_var - std).mean()
            loss = loss_cls + args.lambda_var * loss_var
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(params, 1.0)
            opt.step()
            tot["loss_total"] += float(loss.item())
            tot["loss_cls"] += float(loss_cls.item())
            tot["loss_var"] += float(loss_var.item())
            tot["score_mean"] += float(a.detach().mean())
            tot["score_std"] += float(std.detach().mean())
            n_batches += 1
            train_graphs_total += B
            cum_nodes += int(a.numel())
        train_seconds += time.perf_counter() - t_train

        # -------- 验证（不采样掩码、不丢边）-----
        t_val = time.perf_counter()
        model.eval()
        fuser.eval()
        val_probs_list, val_labels_list = [], []
        with torch.no_grad():
            for i in range(0, len(val_samples), args.batch_size):
                chunk = val_samples[i:i + args.batch_size]
                B = len(chunk)
                channels, ei, et, batch, labels = collate(chunk, training=False, device=device)
                x = fuser(channels, batch=batch)
                z, a, _ = model(x, ei, et, batch=batch)
                val_probs_list.append(torch.sigmoid(z))
                val_labels_list.append(labels)
        val_probs = torch.cat(val_probs_list, dim=0)
        val_labels = torch.cat(val_labels_list, dim=0)
        validation_seconds += time.perf_counter() - t_val

        thr = metrics.search_global_threshold(val_probs, val_labels)
        val_micro_f1 = float(thr["best_micro_f1"])
        val_macro_f1 = float(thr["best_macro_f1"])

        scheduler.step(val_micro_f1)
        epoch_seconds = time.perf_counter() - t_epoch

        # -------- checkpoint / 早停 --------
        improved = val_micro_f1 > best_micro_f1
        if improved:
            best_micro_f1 = val_micro_f1
            bad_epochs = 0
            best_val_probs = {"probs": val_probs, "labels": val_labels,
                              "sample_ids": [s.name for s in val_samples],
                              "threshold": thr["best_threshold"]}
            torch.save({
                "model_state_dict": model.state_dict(),
                "fuser_state_dict": fuser.state_dict(),
                "optimizer_state_dict": opt.state_dict(),
                "epoch": epoch, "best_micro_f1": best_micro_f1,
                "config": config, "seed": args.seed,
            }, run_dir / "best.pt")
            torch.save(best_val_probs, run_dir / "val_best_probs.pt")
            (run_dir / "thresholds.json").write_text(
                json.dumps(thr, ensure_ascii=False, indent=2), encoding="utf-8")
        else:
            bad_epochs += 1
        torch.save({
            "model_state_dict": model.state_dict(),
            "fuser_state_dict": fuser.state_dict(),
            "optimizer_state_dict": opt.state_dict(),
            "epoch": epoch, "best_micro_f1": best_micro_f1,
            "config": config, "seed": args.seed,
        }, run_dir / "last.pt")

        # -------- 日志（JSONL + 终端一行）-----
        n = max(n_batches, 1)
        row = {
            "epoch": epoch,
            "loss_total": tot["loss_total"] / n,
            "loss_cls": tot["loss_cls"] / n,
            "loss_var": tot["loss_var"] / n,
            "score_mean": tot["score_mean"] / n,
            "score_std": tot["score_std"] / n,
            "val_macro_f1": val_macro_f1,
            "val_micro_f1": val_micro_f1,
            "lr": float(opt.param_groups[0]["lr"]),
            "epoch_seconds": round(epoch_seconds, 4),
            "samples_processed": cum_nodes,
            "graphs_processed": train_graphs_total,
            "gpu_mem_allocated": int(torch.cuda.memory_allocated()) if device == "cuda" else None,
        }
        log_lines.append(json.dumps(row, ensure_ascii=False))
        print(f"epoch {epoch:3d} loss {row['loss_total']:.4f} clss {row['loss_cls']:.4f} "
              f"var {row['loss_var']:.4f} sc_mean {row['score_mean']:.4f} sc_std {row['score_std']:.4f} "
              f"val_micro {val_micro_f1:.4f} val_macro {val_macro_f1:.4f} "
              f"lr {row['lr']:.2e} {epoch_seconds:.1f}s", flush=True)
        if bad_epochs >= args.early_stop_patience:
            print(f"early stop at epoch {epoch}（连续 {bad_epochs} epoch val micro-F1 不提升）")
            break

    # ---- 收尾：计时 + config.json + log.txt ----
    run_wall_seconds = time.perf_counter() - t_run_start
    epoch_seconds_mean = (train_seconds + validation_seconds) / max(epoch + 1, 1)
    config["timing"] = {
        "run_wall_seconds": round(run_wall_seconds, 4),
        "data_load_seconds": round(data_load_seconds, 4),
        "train_seconds": round(train_seconds, 4),
        "validation_seconds": round(validation_seconds, 4),
        "epoch_seconds_mean": round(epoch_seconds_mean, 4),
        "graphs_per_second": round(train_graphs_total / train_seconds, 4) if train_seconds > 0 else 0.0,
        "train_graphs": train_graphs_total,
        "epochs_completed": epoch + 1,
    }
    (run_dir / "config.json").write_text(
        json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    (run_dir / "log.txt").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    print(f"done seed{args.seed} (split_seed{split_seed}): best val micro-F1={best_micro_f1:.4f} "
          f"@ epoch; wall={run_wall_seconds:.1f}s train={train_seconds:.1f}s "
          f"graphs/s={config['timing']['graphs_per_second']:.2f} → {run_dir}")


if __name__ == "__main__":
    main()
