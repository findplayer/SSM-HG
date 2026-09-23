#!/usr/bin/env python3
"""5.3 三条论文基线（EGFL / MVD-HG / MANDO-LLM）的**共用层**。

**存在理由**：三条基线在「图与特征」上互不相干（MVD-HG 自带 AST/CFG/DFG 异构图；
EGFL 是字节码 opcode + 基本块 CFG；MANDO-LLM 吃本仓 §37 正典图），但它们在
**「训练 / 早停 / 阈值搜索 / 产物契约 / 覆盖守卫」**上必须逐字一致——否则「某基线更弱」
就可能是被训练配置削的，而不是方法本身弱（本仓 §36.4 的教训）。

**本模块只做编排与搬运，不重实现任何指标、任何划分**：
  - 划分读 `products/alldata/splits/split_seed{S}.json`
  - 标签走 `dataset.build_index`（与正典同一个索引）
  - 指标一律调 `metrics.*`
  - 损失一律调 `train.masked_weighted_bce`（内部即 `F.binary_cross_entropy_with_logits`，
    满足大纲 5.3 [411]「七维 logits + BCEWithLogitsLoss」的实质要求）
  - 守卫复用 `train.run_dir_conflict` + `run_guard`

🔴 **产物契约（缺一条不是报错、而是整列 `—`）**：
  `eval_results/baseline/<name>/seed{S}/test_probs.pt` 必须是
  `{"probs":[N,7], "labels":[N,7], "sample_ids":[...]}`，且
  ① 第二维恰为 **7**（`[N,1]` 会让 `metrics._as_2d_multilabel` 抛 ValueError，§28）；
  ② `sample_ids` 与 `split_seed{S}.json["test"]` **逐字同序**；
  ③ `thresholds.json` 必须含 `best_threshold`。
  这三条由 `assert_bundle` 在**写盘前**硬断言（本仓栽过不止一次）。
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import dataset                                                          # noqa: E402
import metrics                                                          # noqa: E402
import run_guard                                                        # noqa: E402
import train as T                                                       # noqa: E402  只取纯函数

SEEDS = (0, 1, 2)
N_CLASSES = len(metrics.VULN_NAMES)          # 7，顺序锁死，不得重排
BASELINE_NAMES = ("mvdhg", "egfl", "mando")

# 正典超参的**唯一真源**：三个基线脚本的 argparse 默认值必须逐个等于这里的值，
# 并由 tests/test_baseline_tables.py 对照 train.parse_args() 机检（防 R5 口径漂移）。
CANON_DEFAULTS = {
    "epochs": 200, "batch_size": 32, "lr": 1e-4, "weight_decay": 1e-4,
    "scheduler_patience": 3, "early_stop_patience": 5, "pos_weight_cap": 20.0,
    "model_dropout": 0.3,
}


# ------------------------------------------------------------------ 划分与标签
def load_split(split_dir: str | Path, split_seed: int) -> dict:
    """读 `split_seed{S}.json`，并断言其 `seed` 字段与请求一致。

    🔴 断言的理由同 AGENTS.md 的语义锁死项：`ss{S}` 必须与 `--split-seed S` 配对。
    拿了 split_seed2 的划分却以为在跑 seed0，**不会报错**，只是结果无意义。
    """
    p = Path(split_dir) / f"split_seed{split_seed}.json"
    if not p.exists():
        raise SystemExit(f"[baseline] 划分文件不存在：{p}")
    split = json.loads(p.read_text(encoding="utf-8"))
    if int(split.get("seed", -1)) != int(split_seed):
        raise SystemExit(
            f"[baseline] {p} 的 seed 字段是 {split.get('seed')!r}，与 --split-seed "
            f"{split_seed} 不一致；划分与种子错配会让结果无意义（不报错）")
    for arm in ("train", "val", "test"):
        if arm not in split:
            raise SystemExit(f"[baseline] {p} 缺 `{arm}` 列表")
    return split


def load_index(graph_dir: str | Path, label_file: str | None = None,
               key_mode: str | None = None) -> tuple[dict, list[str]]:
    """→ `dataset.build_index(...)`。**三条基线共用同一个索引**，从源头保证标签逐位一致。"""
    index, unmatched = dataset.build_index(graph_dir=graph_dir, label_file=label_file,
                                           key_mode=key_mode)
    if unmatched:
        print(f"[baseline] 标签索引：{len(index)} 个 base 命中，{len(unmatched)} 个未匹配"
              f"（例：{unmatched[:3]}）", flush=True)
    return index, unmatched


def labels_of(bases: list[str], index: dict) -> torch.Tensor:
    """base 列表 → `[N,7]` float32。**缺键直接报错，不补零**——
    补零会把「标签源错配」读成「这是一批干净合约」，是系统性偏差。"""
    missing = [b for b in bases if b not in index]
    if missing:
        raise SystemExit(
            f"[baseline] {len(missing)}/{len(bases)} 个 base 不在标签索引里"
            f"（--label-file / --label-key-mode 与 --graph-dir 不一致？）例：{missing[:5]}")
    return torch.tensor([index[b] for b in bases], dtype=torch.float32)


def sample_ids_of(split: dict, arm: str) -> list[str]:
    """返回 `split[arm]` **本身**——不排序、不去重、不规范化。

    排序会改变行序，而 `test_probs.pt` 的第 i 行必须对应 `split["test"][i]`；
    顺序错了不会报错，只会把 probs 配到别人的标签上。
    """
    return list(split[arm])


# ------------------------------------------------------------------ 产物路径
def feature_root(name: str) -> Path:
    """中间产物根：`products/alldata/baseline/<name>/`（大文件，不入库）。"""
    if name not in BASELINE_NAMES:
        raise ValueError(f"未知基线名 {name!r}（应为 {BASELINE_NAMES}）")
    p = REPO / "products" / "alldata" / "baseline" / name
    p.mkdir(parents=True, exist_ok=True)
    return p


def baseline_dir(name: str, seed: int) -> Path:
    """模型产物目录：`eval_results/baseline/<name>/seed{S}/`。

    选这个路径是为了**零重实现**复用汇总层：`collect_three_caliber_tables.row_from_run`
    内部就是 `REPO/<run_rel>/seed{S}/test_probs.pt`。
    """
    p = REPO / "eval_results" / "baseline" / name / f"seed{int(seed)}"
    p.mkdir(parents=True, exist_ok=True)
    return p


# ------------------------------------------------------------------ 产物契约
@dataclass
class EvalBundle:
    """★ 七维契约的**唯一**装载体：任何要写盘的 probs/labels 都必须经此。"""
    test_probs: torch.Tensor
    test_labels: torch.Tensor
    test_ids: list[str]
    val_probs: torch.Tensor
    val_labels: torch.Tensor
    val_ids: list[str]


def assert_bundle(bundle: EvalBundle, split: dict, *, name: str = "") -> None:
    """写盘前的**硬断言**。每一条都对应本仓栽过的一个坑，不是形式主义。"""
    tag = f"[{name}] " if name else ""
    for label, probs, labels, ids, arm in (
            ("test", bundle.test_probs, bundle.test_labels, bundle.test_ids, "test"),
            ("val", bundle.val_probs, bundle.val_labels, bundle.val_ids, "val")):
        if probs.ndim != 2 or probs.shape[1] != N_CLASSES:
            raise SystemExit(
                f"{tag}{label}_probs 形状是 {tuple(probs.shape)}，必须是 [N,{N_CLASSES}]。"
                f"⚠ 单列 [N,1] 会让 metrics._as_2d_multilabel 抛 ValueError"
                f"（sklearn 会把 average='micro' 退化成 accuracy，见 decisions §28）")
        if labels.shape != probs.shape:
            raise SystemExit(f"{tag}{label} 的 probs{tuple(probs.shape)} 与 "
                             f"labels{tuple(labels.shape)} 形状不一致")
        if probs.dtype != torch.float32 or labels.dtype != torch.float32:
            raise SystemExit(f"{tag}{label} 的 dtype 必须是 float32，"
                             f"实际 {probs.dtype}/{labels.dtype}")
        if not torch.isfinite(probs).all() or not torch.isfinite(labels).all():
            raise SystemExit(f"{tag}{label} 含 NaN/Inf")
        if float(probs.min()) < 0.0 or float(probs.max()) > 1.0:
            raise SystemExit(
                f"{tag}{label}_probs 取值域 [{float(probs.min()):.4f}, {float(probs.max()):.4f}] "
                f"越出 [0,1]——**最常见的原因是忘了在 logits 上过 sigmoid**")
        if list(ids) != list(split[arm]):
            n_same = sum(1 for a, b in zip(ids, split[arm]) if a == b)
            raise SystemExit(
                f"{tag}{label}_ids 与 split[{arm!r}] 不一致（逐位相同 {n_same}/{len(split[arm])}）；"
                f"行序错了会把 probs 配到别人的标签上，且下游只会静默出错")


def write_bundle(bundle: EvalBundle, out_dir: Path, *,
                 thr_scan: dict, results: dict, config: dict) -> None:
    """写 `test_probs.pt` / `val_best_probs.pt` / `thresholds.json` / `results.json` / `config.json`。

    全部**原子落盘**（先写 `.tmp` 再 `replace`）：批量脚本被腰斩时不会留半截产物，
    而半截产物会让下游把「没跑完」读成「跑完了但结果差」。
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    def _atomic_torch(obj, path: Path) -> None:
        tmp = path.with_suffix(path.suffix + ".tmp")
        torch.save(obj, tmp)
        tmp.replace(path)

    def _atomic_json(obj, path: Path) -> None:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(path)

    if "best_threshold" not in thr_scan:
        raise SystemExit("[baseline] thr_scan 缺 `best_threshold`——"
                         "缺它三口径表的 val_thr 两列会整块消失（不报错）")
    _atomic_torch({"probs": bundle.test_probs, "labels": bundle.test_labels,
                   "sample_ids": list(bundle.test_ids)}, out_dir / "test_probs.pt")
    _atomic_torch({"probs": bundle.val_probs, "labels": bundle.val_labels,
                   "sample_ids": list(bundle.val_ids),
                   "threshold": float(thr_scan["best_threshold"])},
                  out_dir / "val_best_probs.pt")
    _atomic_json(thr_scan, out_dir / "thresholds.json")
    _atomic_json(results, out_dir / "results.json")
    _atomic_json(config, out_dir / "config.json")


def report_of(probs: torch.Tensor, labels: torch.Tensor, thr: float) -> dict:
    """一个工作点的完整读数。**每一项都只调 `scripts/metrics.py`**，不重实现。"""
    y = labels.numpy()
    p = metrics.binary_preds(probs, thr).numpy()
    prf = metrics.per_class_prf(y, p)
    return {
        "threshold": float(thr),
        "micro_f1": metrics.micro_f1(y, p),
        "macro_f1": metrics.macro_f1(y, p),
        "per_class": prf,
        "buggy_f1": metrics.buggy_f1(y, p)["f1"],
        "subset_accuracy": metrics.subset_accuracy(y, p),
    }


# ------------------------------------------------------------------ 训练循环
@dataclass
class TrainCfg:
    epochs: int = 200
    batch_size: int = 32
    lr: float = 1e-4
    weight_decay: float = 1e-4
    scheduler_patience: int = 3
    early_stop_patience: int = 5
    pos_weight_cap: float = 20.0
    seed: int = 0
    device: str = "cpu"
    grad_clip: float | None = 1.0
    limit_batches: int = 0          # smoke：每 epoch 只跑前 N 个 batch
    accum_steps: int = 1            # 梯度累积：**等效 batch = batch_size**（见 train_multilabel）


@dataclass
class TrainOut:
    best_epoch: int
    best_monitor: float
    history: list[dict] = field(default_factory=list)
    seconds: float = 0.0
    n_train: int = 0


def class_stats_of(train_labels: torch.Tensor, cap: float):
    """→ `train.class_stats`（复用）。`pos_weight` 截断与 `class_mask` 口径与正典一致。"""
    return T.class_stats(train_labels, pos_weight_cap=cap)


def train_multilabel(model: torch.nn.Module, *, train_loader, val_loader,
                     forward_fn, cfg: TrainCfg,
                     pos_weight: torch.Tensor, class_mask: torch.Tensor) -> TrainOut:
    """三条基线**唯一共享**的训练循环（口径逐条对齐 `train.py`）：

      - 损失 `train.masked_weighted_bce(loss="bce")`，分母 = B × active_class_count；
      - `ReduceLROnPlateau(mode="max", factor=0.5, patience=cfg.scheduler_patience)`；
      - 早停判据 **val micro-F1**，`patience=cfg.early_stop_patience`；
      - 阈值搜索只在 val（`metrics.search_global_threshold`，0.20~0.80 步长 0.05）。

    `forward_fn(model, batch) -> logits[B,7]` 把「批次怎么组织」外置——
    RGCN / HGT / Conformer 三种完全不同的 batch 形态因此能用同一个循环。
    batch 必须自带 `batch["labels"]`（`[B,7]` float32，已在 device 上）。
    """
    device = torch.device(cfg.device)
    model = model.to(device)
    optim = torch.optim.AdamW(model.parameters(), lr=cfg.lr, weight_decay=cfg.weight_decay)
    sched = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optim, mode="max", factor=0.5, patience=cfg.scheduler_patience)
    pw = pos_weight.to(device)
    cm = class_mask.to(device)

    best_monitor, best_epoch, best_epoch_state = -1.0, -1, None
    bad, history = 0, []
    t0 = time.time()
    n_train = 0

    for epoch in range(cfg.epochs):
        ep_t0 = time.time()
        model.train()
        total, nb = 0.0, 0
        accum = max(1, int(cfg.accum_steps))
        n_batches = len(train_loader)
        if cfg.limit_batches:
            n_batches = min(n_batches, cfg.limit_batches)
        optim.zero_grad(set_to_none=True)
        pending = 0
        for i, batch in enumerate(train_loader):
            if cfg.limit_batches and i >= cfg.limit_batches:
                break
            logits = forward_fn(model, batch)
            loss = T.masked_weighted_bce(logits, batch["labels"], pw, cm, loss="bce")
            # 🔴 **梯度累积**：EGFL 在 seq_len=8192 下 batch 32 要 ~12 GB（本机只有 8 GB）
            # ⇒ 用 micro-batch 前向、累积 `accum` 次再 step。损失除以 accum，
            # **等效 batch 仍是 `batch_size`**（`masked_weighted_bce` 按 B×active 归一，
            # 等大小 micro-batch 的均值 ≈ 整批损失），故与其它两行**同口径可比**。
            (loss / accum).backward()
            pending += 1
            if pending >= accum or (i + 1) == n_batches:
                if cfg.grad_clip:
                    torch.nn.utils.clip_grad_norm_(model.parameters(), cfg.grad_clip)
                optim.step()
                optim.zero_grad(set_to_none=True)
                pending = 0
            total += float(loss.detach())
            nb += 1
            n_train += int(logits.shape[0])
        model.eval()
        val_probs, val_labels = infer_multilabel(model, val_loader, forward_fn, device,
                                                 limit_batches=cfg.limit_batches)
        thr = metrics.search_global_threshold(val_probs, val_labels)
        monitor = float(metrics.micro_f1(val_labels.numpy(),
                                         metrics.binary_preds(val_probs, thr["best_threshold"]).numpy()))
        sched.step(monitor)
        improved = monitor > best_monitor
        if improved:
            best_monitor, best_epoch = monitor, epoch
            best_epoch_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            bad = 0
        else:
            bad += 1
        history.append({"epoch": epoch, "train_loss": (total / nb if nb else None),
                        "val_micro_f1": monitor, "val_threshold": thr["best_threshold"],
                        "lr": optim.param_groups[0]["lr"],
                        "epoch_seconds": round(time.time() - ep_t0, 3)})
        if bad >= cfg.early_stop_patience:
            break

    if best_epoch_state is not None:
        model.load_state_dict(best_epoch_state)
    return TrainOut(best_epoch=best_epoch, best_monitor=best_monitor,
                    history=history, seconds=time.time() - t0, n_train=n_train)


@torch.no_grad()
def infer_multilabel(model: torch.nn.Module, loader, forward_fn,
                     device="cpu", limit_batches: int = 0):
    """eval 模式推理 → `(probs[N,7], labels[N,7])`，probs **已过 sigmoid**。

    这里过 sigmoid 而不是在模型里：模型一律输出 logits（`BCEWithLogitsLoss` 的输入），
    「何时变概率」只在这一处决定，避免两头各 sigmoid 一次。
    """
    model.eval()
    P, L = [], []
    for i, batch in enumerate(loader):
        if limit_batches and i >= limit_batches:
            break
        logits = forward_fn(model, batch)
        P.append(torch.sigmoid(logits).detach().cpu())
        L.append(batch["labels"].detach().cpu())
    if not P:
        raise SystemExit("[baseline] 推理得到 0 个 batch（loader 为空？）")
    return torch.cat(P, 0), torch.cat(L, 0)


def search_threshold(val_probs: torch.Tensor, val_labels: torch.Tensor) -> dict:
    """只在**验证集**上搜阈值（`metrics.search_global_threshold`，候选 0.20~0.80 步长 0.05）。"""
    return metrics.search_global_threshold(val_probs, val_labels)


# ------------------------------------------------------------------ 守卫
def guard_dir(out_dir: Path, args: argparse.Namespace, split_seed: int,
              *, overwrite: bool) -> None:
    """复用 `train.run_dir_conflict`。冲突且未 `--overwrite` → 报错退出。

    **不删任何东西**（`run_guard` 只判定不删除，本函数保持同一性质）。
    """
    conflict = T.run_dir_conflict(Path(out_dir), args, split_seed)
    if conflict and not overwrite:
        raise SystemExit(run_guard.guard_message(
            str(out_dir), [conflict],
            "基线产物按 seed 分目录；换参数请改 --out-dir，或确认要覆盖时加 --overwrite"))
    if conflict:
        print(run_guard.warn_message(str(out_dir), [conflict]), flush=True)


def set_seed(seed: int, deterministic: bool = False) -> None:
    """非确定性路径只设 torch/numpy 种子；`--deterministic` 走 `train.set_deterministic`。"""
    if deterministic:
        T.set_deterministic(seed)
        return
    torch.manual_seed(seed)
    np.random.seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


# ------------------------------------------------------------------ CLI 骨架
def base_parser(desc: str, name: str) -> argparse.ArgumentParser:
    """三条基线共用的 CLI 骨架。

    🔴 **默认值必须逐个等于 `CANON_DEFAULTS` / `train.parse_args()`**——否则「基线更弱」
    可能只是被我们的训练配置削的。`tests/test_baseline_tables.py` 会对照 `train.parse_args()`
    机检这条（R5）。
    """
    p = argparse.ArgumentParser(description=desc)
    p.add_argument("--seed", type=int, default=0, help="训练种子。")
    p.add_argument("--split-seed", type=int, default=None,
                   help="读 split_seed{S}.json；默认 = --seed。")
    p.add_argument("--graph-dir", default=str(REPO / "products/alldata/graphs_ft/ss0"),
                   help="图目录（正典必须带 ss{S}，且 {S} 与 --split-seed 配对）。")
    p.add_argument("--split-dir", default=str(REPO / "products/alldata/splits"))
    p.add_argument("--label-file", default=None)
    p.add_argument("--label-key-mode", choices=["project", "stem"], default=None)
    p.add_argument("--out-dir", default=str(REPO / "eval_results" / "baseline" / name),
                   help="产物根；实际写到 <out-dir>/seed{S}/。")
    p.add_argument("--epochs", type=int, default=CANON_DEFAULTS["epochs"])
    p.add_argument("--batch-size", type=int, default=CANON_DEFAULTS["batch_size"])
    p.add_argument("--lr", type=float, default=CANON_DEFAULTS["lr"])
    p.add_argument("--weight-decay", type=float, default=CANON_DEFAULTS["weight_decay"])
    p.add_argument("--scheduler-patience", type=int, default=CANON_DEFAULTS["scheduler_patience"])
    p.add_argument("--early-stop-patience", type=int,
                   default=CANON_DEFAULTS["early_stop_patience"])
    p.add_argument("--pos-weight-cap", type=float, default=CANON_DEFAULTS["pos_weight_cap"])
    p.add_argument("--model-dropout", type=float, default=CANON_DEFAULTS["model_dropout"])
    p.add_argument("--limit-graphs", type=int, default=0, help="小样：只用前 N 个 train/val 图。")
    p.add_argument("--limit-batches", type=int, default=0, help="小样：每 epoch 只跑前 N 个 batch。")
    p.add_argument("--accum-steps", type=int, default=1,
                   help="梯度累积步数：**等效 batch = --batch-size**。EGFL 在 seq_len=8192 下"
                        "必须 >1（否则 8 GB 显存 OOM），用 --batch-size 8 --accum-steps 4 等价于 32。")
    p.add_argument("--device", default=None, help="cpu / cuda；省略则自动 cuda if available else cpu。")
    p.add_argument("--overwrite", action="store_true",
                   help="允许覆盖已存在的 <out-dir>/seed{S}/。默认拒绝（防无声销毁既有结果）。")
    p.add_argument("--deterministic", action="store_true")
    p.add_argument("--smoke", action="store_true", help="冒烟：极小 epoch 数 + 限量。")
    return p


def resolve_device(arg: str | None) -> str:
    if arg:
        return arg
    return "cuda" if torch.cuda.is_available() else "cpu"


def resolve_split_seed(args: argparse.Namespace) -> int:
    return int(args.seed if args.split_seed is None else args.split_seed)


def drop_without_features(split: dict, feat_root: Path, *, name: str = "") -> tuple[dict, dict]:
    """把该臂里**没有离线特征**的 base 剔掉，返回 `(新 split, {臂: 被剔的 base})`。

    🔴 **为什么必须显式剔而不是让它报错**：MVD-HG 有 5/453 个合约在**任何已装 solc 下都编不过**
    （试过全部 101 个候选），EGFL 同理。它们若留在池里，`FeatDataset` 会直接 `SystemExit`，
    整条基线跑不起来。剔掉之后 **test 集是否完整必须单独核对**——实测这 5 个**全在 train**
    （seed2 另有 1 个在 val），**test 一个都没少**（三个 seed 都是 46）⇒
    逐类 support 与照常、与本文方法的行**逐格可比**。报告里必须写明覆盖率。
    """
    out, dropped = {}, {}
    for arm in ("train", "val", "test"):
        keep = [b for b in split[arm] if (feat_root / "feat" / f"{b}.pt").exists()]
        out[arm] = keep
        dropped[arm] = [b for b in split[arm] if b not in set(keep)]
    rest = {k: v for k, v in split.items() if k not in ("train", "val", "test")}
    out.update(rest)
    if any(dropped.values()):
        tot = sum(len(v) for v in dropped.values())
        print(f"[{name}] ⚠ 剔除 {tot} 个缺离线特征的样本："
              f"train {len(dropped['train'])} / val {len(dropped['val'])} / "
              f"test {len(dropped['test'])}", flush=True)
        if dropped["test"]:
            print(f"[{name}] 🔴 **test 集不完整**（少 {len(dropped['test'])} 个）——"
                  f"该行与其它行的分母不同，逐格 Δ 不可直接解读！", flush=True)
    return out, dropped


def to_device(obj, device):
    """递归把 batch 里的张量搬到 `device`（支持 dict / list / tuple 嵌套）。

    🔴 **为什么必须有这一步**：本机 CUDA 可用，而 `train_multilabel` 只把**模型** `.to(device)`，
    batch 由各基线自己的 `collate` 产出（默认 CPU）。不搬就会在 GPU 上报
    「Expected all tensors to be on the same device」——**且只在 GPU 上炸**，
    CPU 冒烟完全看不出来。`labels` 也必须搬：损失用 `masked_weighted_bce`，
    而 `pos_weight` / `class_mask` 已在 device 上。
    """
    dev = torch.device(device)
    if isinstance(obj, torch.Tensor):
        return obj.to(dev)
    if isinstance(obj, dict):
        return {k: to_device(v, dev) for k, v in obj.items()}
    if isinstance(obj, list):
        return [to_device(v, dev) for v in obj]
    if isinstance(obj, tuple):
        return tuple(to_device(v, dev) for v in obj)
    return obj


def torch_loader(items, collate_fn, batch_size: int, shuffle: bool, generator=None):
    """`torch.utils.data.DataLoader` 的薄封装（统一 `collate_fn` 与打乱流）。"""
    from torch.utils.data import DataLoader
    return DataLoader(items, batch_size=batch_size, shuffle=shuffle, collate_fn=collate_fn,
                      generator=generator, num_workers=0)


SOLC_ARTIFACTS = Path.home() / ".solc-select" / "artifacts"


def solc_versions() -> list[str]:
    """已装 solc 版本（升序）。"""
    return sorted((p.name.replace("solc-", "") for p in SOLC_ARTIFACTS.glob("solc-*")),
                  key=lambda v: tuple(int(x) for x in v.split(".")))


def solc_candidates(src_sol: Path) -> list[str]:
    """按源码 pragma 给出**候选 solc 版本序列**（首个最可能成功，失败依次回退）。

    🔴 **为什么是长列表而不是前几个**：实测有合约在文件**中段还有第二条精确 pragma**
    （如 `pragma solidity 0.5.2;` 的内联依赖），首条 `^0.5.2` 会让 0.5.17 也「满足」却在
    第 444 行报版本不符 ⇒ **只有恰好 0.5.2 能编过**。若只试按首条 pragma 挑出的前 8 个
    高版本，这类合约会被误记成「编译失败」。这正是 `baseline_static_tools.pick_solc_candidates`
    注释里记的那个教训（590 图里 47 个首次失败、大多只是版本没挑对）。

    顺序照抄它：满足 pragma 的已装版本（高→低）→ 最高 0.8.x（无 pragma 时的首选）
    → **其余全部已装版本（低→高）**。
    """
    import baseline_static_tools as BST
    versions = solc_versions()
    out: list[str] = []
    seen: set[str] = set()

    def add(v: str) -> None:
        if v not in seen:
            seen.add(v)
            out.append(v)

    spec = BST.parse_pragma(src_sol)
    if spec:
        for v in reversed(versions):
            if all(BST.version_ok(tuple(int(x) for x in v.split(".")), op, want)
                   for op, want in spec):
                add(v)
    eights = [v for v in versions if v.startswith("0.8.")]
    if eights:
        add(eights[-1])
    for v in versions:
        add(v)
    return out
