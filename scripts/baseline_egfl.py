#!/usr/bin/env python3
"""EGFL 基线（5.3）**训练 + 评估**：opcode 序列 + CFG 图向量 → 7 维 logits。

输入 = `scripts/baseline_egfl_build.py` 产出的 `feat/<base>.pt`
（`tokens` = 反汇编后的 opcode 记号流，`gvec` = BFS 展平的 256 维 CFG 图向量）。

产物 = `eval_results/baseline/egfl/seed{S}/{test_probs.pt, val_best_probs.pt,
thresholds.json, results.json, config.json, best.pt, log.txt}` —— 形制与 `runs/seed{S}/`
一致，故 `collect_three_caliber_tables.row_from_run` 能**零重实现**直接读。

用法（仓库根目录）：
    python scripts/baseline_egfl.py --seed 0 --limit-graphs 8 --epochs 2 --seq-len 512   # 冒烟
    python scripts/baseline_egfl.py --seed 0 --seq-len 8192                              # 单种子全量
"""

from __future__ import annotations

import json
import sys
import time
from collections import Counter
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402
import baseline_models as BM                                             # noqa: E402

NAME = "egfl"
SEQ_LEN_DEFAULT = 512
VOCAB_SIZE = 1000                     # 论文原设（`Embedding(1000, 256)`）

RECONSTRUCTION_NOTES = [
    "输入模态 = **原生字节码**（用户 2026-09-22 裁定）：solc --bin 的 creation bytecode → "
    "反汇编 → 基本块 CFG → BFS 展平。不走源码异构图。",
    "🔴 **图分支的 256 维是重建件**：原 `cfg_graph` 是作者未开源的预处理产物"
    "（`Weights_CFG_SimOp/` 是 0 字节目录，全仓无脚本产出它，`main_run.py:49` 只负责读入）。"
    "本实现对「块内 opcode 词向量取平均 → BFS 前 k 块 concat」重建，默认 (node_dim=128, k=2)。"
    "论文只写「BFS 展平成 linear node feature matrix」，切法不可考 ⇒ **不得声称复现了作者原结果**。",
    "词表与词向量**只用 train 划分的 362 个合约**拟合（原实现用 train+val，对我们是泄漏）。",
    "opcode 词表**截断到 1000**（论文原设）。EVM 共 144 条 opcode，PUSH 立即数按 "
    "`PUSH1 0x2a` 形态整体成一个记号，故实际词表可能略超 1000，超出部分归 UNK(1)。",
    "🔴 **序列截断到 `--seq-len=512`，本库多数合约因此被截断**（池内 opcode token 数 "
    "p50≈3304）。**为什么只能是 512**：它的 Attention 是**稠密 O(L²)** 的（无 mask、无稀疏），"
    "本机 8 GB 卡实测 —— L=512 时 2.5 GB / 0.16 s 每步；**L=1024 就已溢出到共享显存**"
    "（9.9 GB 峰值、7.75 s 每步，慢 48 倍）。原论文的 `SEQ_LEN=8000` 在 8 GB 卡上"
    "**任何实现都跑不动**（单是 `dots` 就 2 GB/批）。这是**硬件逼出来的口径损失**，"
    "不是调参选择；交付物抬头必须引用本段。本实现另把注意力改成**分块在线 softmax**"
    "（数学等价）并把相对位置表按显存预算自适应收缩，见 `baseline_models._RelPosAttention`。",
    "`ConformerConvModule` 的 depthwise conv 在原代码里**被注释掉了**，本实现照抄该形态"
    "（LN → 1×1 Conv → GLU → BN → Swish → 1×1 Conv → Dropout），没有替它「修好」。",
    "`Attention` 的 mask 分支原代码写死 `tf.ones(...)`（永远全 1）⇒ 等价于无 mask，本实现直接省略。",
    "输出头 1→7、去掉末尾 Sigmoid、改 BCEWithLogitsLoss（大纲 5.3 [411]）；原实现是二分类。",
    "`Basic_blocks` 原代码有 `if f\"{n}\" and _opcode_of(n) in TERMINALS:`（字符串恒真）——"
    "语义上不影响结果，本实现写成 `if _opcode_of(n) in TERMINALS:`。",
    "⚠ **学习率口径（读本行前必看）**：本行用**正典统一的 `lr=1e-4`**，而 EGFL 论文自己的默认是 "
    "`lr=0.002`（`EGFL/parser_set.py:13`，**20 倍**）。实测后果是**双重压制**："
    "① 起点就低 20 倍；② `ReduceLROnPlateau(patience=3, factor=0.5)` 在 val 不涨时每 3 轮减半，"
    "实测 **第 20 轮 lr 已跌到 3.13e-06**（≈ 冻结），训练 loss 从 0.99 只降到 0.83 就再不动了，"
    "`best_epoch` 停在 **0–2**、`micro@0.5` 两个种子为 **0.0000**（模型几乎不报正类）。"
    "⇒ **本行读数主要反映「超参没调对」，不是 EGFL 方法的能力**。两种口径并列在交付物里"
    "（本目录 = 统一 1e-4；`eval_results/baseline/egfl_ownlr/` = 其论文 2e-3），"
    "读者可自行判断——这正是计划 R5 点名的风险，只报一行会让两种解释无法区分。",
]


def build_vocab(seqs: list[list[str]], vocab_size: int) -> dict[str, int]:
    """train 划分的 opcode 记号 → id（**0 固定为 pad，1 固定为 UNK**）。

    按频次降序取前 `vocab_size - 2` 个；其余（含全部低频 PUSH 立即数组合）归 UNK。
    """
    c = Counter()
    for toks in seqs:
        c.update(toks)
    vocab = {"<pad>": 0, "<unk>": 1}
    for tok, _ in c.most_common(max(0, vocab_size - 2)):
        vocab[tok] = len(vocab)
    return vocab


class FeatDataset(torch.utils.data.Dataset):
    """预加载 `feat/<base>.pt`（453 个约几十 MB；每 epoch 读盘不划算）。"""

    def __init__(self, bases: list[str], feat_root: Path, vocab: dict[str, int],
                 seq_len: int):
        self.items = []
        unk = vocab["<unk>"]
        for b in bases:
            p = feat_root / "feat" / f"{b}.pt"
            if not p.exists():
                raise SystemExit(f"[egfl] 缺离线特征 {p}；先跑 baseline_egfl_build.py")
            d = torch.load(p, map_location="cpu")
            # 🔴 `n_tok` 必须在**截断前**取：先在截断后取，统计出来永远是
            # 「0% 被截断」——一个只会说谎、不会报错的计数器（首版实测踩到）。
            full = [vocab.get(t, unk) for t in d["tokens"]]
            n_tok = len(full)
            ids = full[:seq_len]
            n_pad = seq_len - len(ids)
            self.items.append({
                "base": b,
                "tokens": torch.tensor(ids + [0] * n_pad, dtype=torch.long),
                "n_tok": n_tok,
                "gvec": d["gvec"].to(torch.float32).reshape(-1),
            })

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        return self.items[i]


def collate_egfl(samples, labels_map, device=None):
    out = {
        "tokens": torch.stack([s["tokens"] for s in samples], 0),
        "gvec": torch.stack([s["gvec"] for s in samples], 0),
        "labels": torch.stack([torch.as_tensor(labels_map[s["base"]], dtype=torch.float32)
                               for s in samples], 0),
        "names": [s["base"] for s in samples],
        "n_tok": torch.tensor([s["n_tok"] for s in samples], dtype=torch.long),
    }
    return B.to_device(out, device) if device else out


def _forward(model, batch):
    return model(batch["tokens"], batch["gvec"])


def main() -> int:
    p = B.base_parser("EGFL 基线（7 维多标签）训练与评估。", NAME)
    p.add_argument("--seq-len", type=int, default=SEQ_LEN_DEFAULT,
                   help="opcode 序列截断/补齐长度（默认 8192 = 实测 p90）。")
    args = p.parse_args()
    if args.smoke:
        args.epochs = args.epochs if args.epochs != 200 else 2
        # 🔴 **不要**在冒烟里缩 `--limit-graphs`：split 前缀全是干净合约（7 类真值全 0），
        # `class_stats` 会正确地报「所有类别正样本均为 0，无法训练」而中止。
        # 冒烟改缩 **batch 数**（数据池仍是全量，只是每 epoch 只跑前几个 batch）。
        args.limit_batches = args.limit_batches or 3
        args.seq_len = min(args.seq_len, 512)
    split_seed = B.resolve_split_seed(args)
    device = B.resolve_device(args.device)
    B.set_seed(args.seed, args.deterministic)
    B.check_layout(args, NAME)

    split = B.load_split(args.split_dir, split_seed)
    index, _ = B.load_index(args.graph_dir, args.label_file, args.label_key_mode)
    out_dir = Path(args.out_dir) / f"seed{args.seed}"
    B.guard_dir(out_dir, args, split_seed, overwrite=args.overwrite)

    feat_root = B.feature_root(NAME, args.feature_suffix)
    split, dropped = B.drop_without_features(split, feat_root, name=NAME)

    def limited(arm):
        bs = split[arm]
        return bs[:args.limit_graphs] if args.limit_graphs else bs

    # ---- 词表：**只用 train 划分**拟合（原实现用 train+val，对我们是泄漏）----
    train_tokens = []
    for b in limited("train"):
        fp = feat_root / "feat" / f"{b}.pt"
        if fp.exists():
            train_tokens.append(torch.load(fp, map_location="cpu")["tokens"])
    if not train_tokens:
        raise SystemExit(f"[egfl] train 语料为空；先跑 baseline_egfl_build.py（{feat_root}）")
    vocab = build_vocab(train_tokens, VOCAB_SIZE)
    print(f"[egfl] 词表 {len(vocab)} 条（train {len(train_tokens)} 个合约，"
          f"上限 {VOCAB_SIZE}）；seq_len={args.seq_len}", flush=True)

    ds = {arm: FeatDataset(limited(arm), feat_root, vocab, args.seq_len)
          for arm in ("train", "val", "test")}
    labels_map = {b: index[b] for b in split["train"] + split["val"] + split["test"]}

    train_labels = torch.stack([torch.as_tensor(index[b], dtype=torch.float32)
                                for b in limited("train")], 0)
    pos_weight, class_mask, active, train_pos, _ = B.class_stats_of(train_labels,
                                                                    args.pos_weight_cap)
    print(f"[egfl] train {len(ds['train'])} / val {len(ds['val'])} / test {len(ds['test'])}"
          f"；active classes {active}/7；pos_weight {[round(float(v),2) for v in pos_weight]}",
          flush=True)

    # 🔴 **截断代价必须量化上报**：EGFL 的注意力是 O(L²)，本机 8 GB 卡实测
    # L=1024 就溢出到共享显存（9.9 GB 峰值、7.75 s/步），L=512 才是可靠工作点
    # （2.5 GB、0.16 s/步）。而本库 opcode 序列 p50 就有 3304 ⇒ **多数合约被截断**。
    # 这是硬件逼出来的口径损失，不写清楚就等于隐瞒（交付物抬头必须引用本段）。
    n_tok = [int(s["n_tok"]) for s in ds["train"] + ds["val"] + ds["test"]]
    n_trunc = sum(1 for v in n_tok if v > args.seq_len)
    trunc_frac = n_trunc / max(1, len(n_tok))
    print(f"[egfl] ⚠ 序列截断：{n_trunc}/{len(n_tok)} = {trunc_frac:.1%} 的合约 token 数 > "
          f"seq_len={args.seq_len}（池内 token 数中位数 {sorted(n_tok)[len(n_tok)//2]}）",
          flush=True)

    torch.manual_seed(args.seed)
    model = BM.EGFLNet(vocab_size=len(vocab), num_classes=7, dropout=0.5)
    n_par = sum(p_.numel() for p_ in model.parameters())
    print(f"[egfl] 参数量 {n_par/1e6:.3f} M", flush=True)

    cf = B.TrainCfg(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr,
                    weight_decay=args.weight_decay,
                    scheduler_patience=args.scheduler_patience,
                    early_stop_patience=args.early_stop_patience,
                    pos_weight_cap=args.pos_weight_cap, seed=args.seed, device=device,
                    limit_batches=args.limit_batches, accum_steps=args.accum_steps)
    gen = torch.Generator().manual_seed(args.seed * 100000 + 1)
    # micro-batch = batch_size // accum_steps ⇒ 显存按 micro 算，**等效 batch 不变**
    micro = max(1, args.batch_size // max(1, args.accum_steps))
    tr = B.torch_loader(ds["train"], lambda b: collate_egfl(b, labels_map, device),
                        micro, True, generator=gen)
    va = B.torch_loader(ds["val"], lambda b: collate_egfl(b, labels_map, device),
                        args.batch_size, False)
    te = B.torch_loader(ds["test"], lambda b: collate_egfl(b, labels_map, device),
                        args.batch_size, False)   # 推理不反传，可用整批

    t0 = time.time()
    out = B.train_multilabel(model, train_loader=tr, val_loader=va, forward_fn=_forward,
                             cfg=cf, pos_weight=pos_weight, class_mask=class_mask)
    val_probs, val_labels = B.infer_multilabel(model, va, _forward, device,
                                               limit_batches=args.limit_batches)
    thr = B.search_threshold(val_probs, val_labels)
    test_probs, test_labels = B.infer_multilabel(model, te, _forward, device,
                                                 limit_batches=args.limit_batches)

    bundle = B.EvalBundle(test_probs=test_probs, test_labels=test_labels,
                          test_ids=B.sample_ids_of(split, "test")[:len(test_probs)],
                          val_probs=val_probs, val_labels=val_labels,
                          val_ids=B.sample_ids_of(split, "val")[:len(val_probs)])
    full = not args.limit_graphs and not args.limit_batches
    if full:
        B.assert_bundle(bundle, split, name=NAME)

    import metrics
    results = {
        "baseline": NAME, "seed": args.seed, "split_seed": split_seed, "head": "multi",
        "select_metric": "val_micro_f1", "val_threshold": float(thr["best_threshold"]),
        "threshold_scan": thr,
        "mAP": metrics.mean_average_precision(test_probs, test_labels),
        "test": {wp: B.report_of(test_probs, test_labels, t)
                 for wp, t in (("fixed_0.5", 0.5), ("val_threshold", thr["best_threshold"]))},
        "best_epoch": out.best_epoch, "best_val_micro_f1": out.best_monitor,
        "n_train_graphs": len(ds["train"]), "n_val_graphs": len(ds["val"]),
        "coverage": {"n_features": len(list((feat_root / "feat").glob("*.pt"))),
                     "dropped": {k: len(v) for k, v in dropped.items()},
                     "dropped_test": dropped["test"]},
        "n_test_graphs": len(ds["test"]), "n_params": n_par,
        "reconstruction_notes": RECONSTRUCTION_NOTES,
        "partial": (not full),
        "timing": {"train_seconds": round(out.seconds, 2),
                   "wall_seconds": round(time.time() - t0, 2),
                   "seconds_per_epoch": round(out.seconds / max(1, len(out.history)), 2)},
        "environment": {"device": device, "torch": torch.__version__},
    }
    config = {"args": dict(vars(args)), "split_seed": split_seed, "head": "multi",
              "baseline": NAME, "notes": RECONSTRUCTION_NOTES,
              "derived": {"vocab_size": len(vocab), "seq_len": args.seq_len,
                          "truncated_graphs": n_trunc, "truncated_frac": round(trunc_frac, 4),
                          "token_len_median": sorted(n_tok)[len(n_tok)//2],
                          "n_params": n_par, "active_classes": active,
                          "train_pos": [int(v) for v in train_pos],
                          "pos_weight": [round(float(v), 4) for v in pos_weight]}}
    B.write_bundle(bundle, out_dir, thr_scan=thr, results=results, config=config)
    (out_dir / "log.txt").write_text(
        "\n".join(json.dumps(h, ensure_ascii=False) for h in out.history), encoding="utf-8")
    torch.save({"model_state_dict": model.state_dict()}, out_dir / "best.pt")
    print(f"[egfl] seed{args.seed} 完成：val_thr={thr['best_threshold']} "
          f"test micro@0.5={results['test']['fixed_0.5']['micro_f1']:.4f} "
          f"@thr={results['test']['val_threshold']['micro_f1']:.4f} "
          f"（best epoch {out.best_epoch}，{out.seconds:.0f}s）→ {out_dir}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
