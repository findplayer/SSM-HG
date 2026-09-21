#!/usr/bin/env python3
"""阶段 1：用**合约级标签**微调 CodeBERT（大纲 5.4.2 第 17 项；`ablation_plan.md` §6.4）。

**为什么是"两阶段"而不是端到端**：本仓的架构事实是——**CodeBERT 只活在 M3 里**，
`_cb.pt` 是它进入 M5 的唯一载体。若改成训练期把编码器接进 `NodeFuser` 端到端反传，
每个 epoch 要对约 12 万条序列跑一次 BERT 前向**加反向**（仅纯前向就 20+ 分钟量级），
而早停发生在 14–23 个 epoch ⇒ 不可承受；同时会打破「M3 产出可离线复算的缓存」这一
可复现性契约。故：**本脚本只训编码器 → 存盘 → 由 `build_graph_variant.py` 重跑 M3 取特征**。

它回答「**微调后的编码器作为特征提取器**是否更好」，**不**回答「端到端联合微调是否更好」——
后者的优化面与显存占用都不同（大纲 4.3.2 的三条冻结理由中，本设计只解除了第 1 条的动机）。

🔴 **每个划分种子必须单独微调一个编码器**：编码器若见过某合约的源码，该合约的 `_cb` 特征
对这个划分就是污染的（哪怕只用于特征提取）。同一编码器跑三个划分种子 ⇒ 其中两个种子的
val/test 合约进过编码器的训练集 ⇒ **不可比的乐观偏差**。故 **3 个划分种子 = 3 次微调**。

文本口径**必须复用 M3 的实现**（`m3_build_features.build_node_window` 与函数源码切片、
512/128 截断）——直接 `import`，**不另写一份**。两份文本口径必然漂移，本仓已有 §29.4 的同类教训。

用法（从仓库根目录运行）：
  python scripts/finetune_codebert.py --split-seed 0 --limit-contracts 20 --epochs 1   # 冒烟
  python scripts/finetune_codebert.py --split-seed 0                                   # 全量

产物：`runs/codebert_ft/ss{S}/encoder/`（HF 格式，可直接喂 `m3_build_features.py --codebert`）
      + `runs/codebert_ft/ss{S}/config.json`（超参、逐 epoch 日志、划分完整性证据）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import torch
import torch.nn as nn

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import m3_build_features as m3                                          # noqa: E402
import metrics                                                          # noqa: E402
from dataset import build_index, resolve_label_file, resolve_label_key_mode   # noqa: E402
from train import class_stats, masked_weighted_bce                      # noqa: E402

BASE = str(REPO)
DEFAULT_GRAPH_DIR = f"{BASE}/products/alldata/graphs"
DEFAULT_SPLIT_DIR = f"{BASE}/products/alldata/splits"
NUM_CLASSES = 7


def load_hf_offline_fallback(loader, name: str, what: str):
    """HF 加载：联网失败时**自动回退到本地缓存**（`HF_HUB_OFFLINE=1`）再试一次。

    🔴 **为什么必须有**：本机 HF 缓存是**完整的**，但 `transformers` 默认仍会联网
    **重校验**。2026-09-21 实测：ss1 的微调跑到一半前（加载 tokenizer 时）抛
    `requests.exceptions.SSLError ... EOF occurred in violation of protocol`，
    **整次 40 分钟的微调前功尽弃**——失败原因与代码、数据、超参都无关，纯网络抖动。
    缓存齐备时联网毫无必要：离线加载既快又不受网络影响。

    回退前会先把离线开关设进 `os.environ`，因为 HF 的离线判定发生在**库内部**
    （模块级读环境变量），改完之后重新构造调用即可生效（`transformers` 每次
    `from_pretrained` 都会重新读）。
    """
    try:
        return loader()
    except Exception as exc:                                   # noqa: BLE001 —— 网络异常族太多
        print(f"[ft] ⚠ 联网加载 {what}（{name}）失败：{type(exc).__name__}: {str(exc)[:200]}\n"
              f"[ft]   → 回退到本地缓存（HF_HUB_OFFLINE=1）重试", flush=True)
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        return loader()


def corpus_tag(graph_dir) -> str:
    """`products/<语料>/graphs` → `<语料>`。**编码器按语料隔离的依据**。

    ⚠ 原先把所有语料的编码器都写到 `runs/codebert_ft/ss{S}/encoder`（无语料维度），
    而 ①②两组的划分、标签口径、文本来源全都不同。队列先跑 ① 再跑 ② 时，② 那一步会
    看到 ① 留下的编码器而**跳过微调**，接着拿 ① 的编码器去重编码 ②——产物齐全、
    各项验收断言全过、**不报任何错**，但这项消融答的不是它要问的问题（与 §28 同类）。
    故默认输出根带语料维度，并在 `encoder/` 内写 `corpus.json` 边车供下游硬校验。
    """
    return Path(graph_dir).resolve().parent.name


def default_out_root(graph_dir) -> Path:
    return REPO / "runs" / "codebert_ft" / corpus_tag(graph_dir)


# --------------------------------------------------------------------------- 数据侧（纯函数）
def contract_texts(graph_dir: Path, names: list[str]) -> dict[str, list[str]]:
    """`{base: [函数源码文本, …]}`——**文本口径与 M3 完全同源**（复用 `m3.load_graph`）。

    M3 的函数级通道取 `"\\n".join(src_lines[fs-1:fe])`（该函数起止行），本函数逐字相同；
    截断发生在 tokenizer 侧（`max_len`），也与 M3 的 512 一致。
    """
    out: dict[str, list[str]] = {}
    for base in names:
        data = m3.load_graph(graph_dir / f"{base}_hetero.json", graph_dir / f"{base}_m1.json")
        src = data["src_lines"]
        texts = []
        for (_contract, _function), fn in sorted(data["fn_table"].items()):
            fs, fe = fn.get("start_line"), fn.get("end_line")
            texts.append("" if fs is None or fe is None
                         else "\n".join(src[int(fs) - 1:int(fe)]))
        out[base] = texts
    return out


def tokenize_all(texts: dict[str, list[str]], tok, max_len: int) -> dict[str, list[torch.Tensor]]:
    """预算 token（每序列 1-D，不 padding）——padding 留到组批时按批内最长做。"""
    out: dict[str, list[torch.Tensor]] = {}
    for base, seqs in texts.items():
        ids = []
        for text in seqs:
            if not text:
                continue                                  # 空文本与 M3 的 zeros 语义一致：不参与
            enc = tok(text, truncation=True, max_length=max_len, return_tensors="pt")
            ids.append(enc["input_ids"][0])
        out[base] = ids
    return out


class CodeBertContract(nn.Module):
    """函数级 `[CLS]` → **合约内 mean-pool** → `Linear(768, 7)`（合约级多标签）。

    ⚠ 这里的 head 在阶段 2 会被**丢弃**（只存 encoder）：它存在的唯一理由是给编码器
    提供合约级梯度。故下游 `_cb.pt` 用的是 `encoder` 的输出，不是本模型的输出。
    """

    def __init__(self, name: str, num_classes: int = NUM_CLASSES):
        super().__init__()
        from transformers import AutoModel
        self.encoder = load_hf_offline_fallback(lambda: AutoModel.from_pretrained(name),
                                                name, "model")
        hidden = int(self.encoder.config.hidden_size)
        self.head = nn.Linear(hidden, num_classes)

    def encode(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        return self.encoder(input_ids=input_ids,
                            attention_mask=attention_mask).last_hidden_state[:, 0, :]


def pad_batch(seqs: list[torch.Tensor], device: str, pad_id: int):
    """等长补齐 + attention_mask（右 padding）。"""
    width = max(int(s.numel()) for s in seqs)
    ids = torch.full((len(seqs), width), pad_id, dtype=torch.long, device=device)
    mask = torch.zeros((len(seqs), width), dtype=torch.long, device=device)
    for i, s in enumerate(seqs):
        n = int(s.numel())
        ids[i, :n] = s.to(device)
        mask[i, :n] = 1
    return ids, mask


def pooled_contracts(model: CodeBertContract, seqs_of: dict, batch_names: list[str],
                     seq_batch: int, device: str, pad_id: int) -> torch.Tensor:
    """一个 step 的合约表示 [C, 768]：批内全部序列编码后按合约求均值。

    ⚠ 所有 micro-batch 的图**同时存活到 backward**（损失是 cls 的线性函数之外的复合，
    不能分块 backward）。故 `--seq-batch` / `--contracts-per-batch` 共同决定显存峰值，
    调小它们即可在 8 GB 卡上跑（实测见 config.json::timing）。
    """
    seqs, owner = [], []
    for ci, name in enumerate(batch_names):
        for s in seqs_of[name]:
            seqs.append(s)
            owner.append(ci)
    chunks = []
    for lo in range(0, len(seqs), seq_batch):
        ids, mask = pad_batch(seqs[lo:lo + seq_batch], device, pad_id)
        chunks.append(model.encode(ids, mask))
    cls = torch.cat(chunks, 0)                                        # [S, 768]
    owner_t = torch.tensor(owner, dtype=torch.long, device=device)
    pooled = torch.zeros(len(batch_names), cls.shape[1], dtype=cls.dtype, device=device)
    pooled.index_add_(0, owner_t, cls)
    counts = torch.zeros(len(batch_names), dtype=cls.dtype, device=device)
    counts.index_add_(0, owner_t, torch.ones_like(owner_t, dtype=cls.dtype))
    return pooled / counts.clamp(min=1.0).unsqueeze(1)


@torch.no_grad()
def score(model: CodeBertContract, seqs_of: dict, names: list[str], label_of: dict,
          seq_batch: int, device: str, pad_id: int) -> tuple:
    """验证集打分 → (macro-F1, probs[N,7], labels[N,7])。编码器置 eval（关闭 dropout）。

    `names` 必须是**已过滤掉无函数序列的合约**（调用方用 `[n for n in … if seqs_of[n]]`），
    否则 `probs` 与 `labels` 会错位——这类错位不报错，只会静默给出一个偏低的 F1。
    """
    model.eval()
    probs = []
    for lo in range(0, len(names), 8):
        batch = names[lo:lo + 8]
        pooled = pooled_contracts(model, seqs_of, batch, seq_batch, device, pad_id)
        probs.append(torch.sigmoid(model.head(pooled)).cpu())
    if not probs:
        return 0.0, torch.zeros(0, NUM_CLASSES), torch.zeros(0, NUM_CLASSES)
    probs = torch.cat(probs, 0)
    y = torch.stack([label_of[n] for n in names])
    return metrics.macro_f1(y.numpy(), (probs >= 0.5).float().numpy()), probs, y


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--split-seed", type=int, default=0)
    p.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR)
    p.add_argument("--split-dir", default=DEFAULT_SPLIT_DIR)
    p.add_argument("--label-file", default=None)
    p.add_argument("--label-key-mode", choices=["project", "stem"], default=None)
    p.add_argument("--out-root", default=None,
                   help="编码器输出根；默认按 `--graph-dir` 的语料派生 "
                        "`runs/codebert_ft/<语料>/`（**不得跨语料复用**，见 corpus_tag 的说明）。")
    p.add_argument("--codebert", default=m3.CODEBERT, help="起始权重（HF id 或本地目录）。")
    p.add_argument("--epochs", type=int, default=5)
    p.add_argument("--lr", type=float, default=2e-5, help="编码器学习率（微调典型量级）。")
    p.add_argument("--head-lr", type=float, default=1e-3, help="分类头学习率（从零训练，故更大）。")
    p.add_argument("--weight-decay", type=float, default=0.01)
    p.add_argument("--seq-batch", type=int, default=6, help="编码 micro-batch（显存主开关）。")
    p.add_argument("--no-grad-checkpoint", dest="grad_checkpoint", action="store_false",
                   help="关闭梯度检查点（显存换速度；8 GB 卡上默认开启）。")
    p.add_argument("--contracts-per-batch", type=int, default=2,
                   help="一个优化步含几个合约（显存主开关之二）。")
    p.add_argument("--max-funcs-per-contract", type=int, default=48,
                   help="单合约最多取几个函数（全库均值 40.5，截断只影响极少数超大合约）。")
    p.add_argument("--pos-weight-cap", type=float, default=20.0, help="与 train.py 同口径。")
    p.add_argument("--patience", type=int, default=2, help="val macro-F1 早停耐心（epoch 数）。")
    p.add_argument("--limit-contracts", type=int, default=0, help="冒烟用；0=全部。")
    p.add_argument("--seed", type=int, default=0, help="只控 head 初始化与打乱（编码器有预训练权重）。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    device = "cuda" if torch.cuda.is_available() else "cpu"
    corpus = corpus_tag(args.graph_dir)
    out_root = Path(args.out_root) if args.out_root else default_out_root(args.graph_dir)
    out_dir = out_root / f"ss{args.split_seed}"
    encoder_dir = out_dir / "encoder"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"[ft] 语料={corpus}  输出={out_dir}", flush=True)

    # ---- 划分与标签（三条硬校验：划分完整性、标签齐全、**无泄漏**）----
    split = json.loads((Path(args.split_dir) / f"split_seed{args.split_seed}.json")
                       .read_text(encoding="utf-8"))
    index, unmatched = build_index(Path(args.graph_dir), label_file=args.label_file,
                                   key_mode=args.label_key_mode)
    train_names = [b for b in split["train"] if b in index]
    val_names = [b for b in split["val"] if b in index]
    test_names = [b for b in split.get("test", []) if b in index]
    if not args.limit_contracts:
        leak = set(train_names) & (set(val_names) | set(test_names))
        assert not leak, f"🔴 训练集与 val/test 有交集（{len(leak)} 个）：{sorted(leak)[:5]}"
    else:
        # 冒烟路径专用：**必须取含正样本的合约**。主库 453 个池里有 326 个全零标签，
        # 前 N 个多半全零 → `class_stats` 会以"所有类别正样本均为 0"报错退出。
        # `train.py --limit-graphs` 用同一策略（limit 分支筛 `any(index[b])`）；
        # **全量路径不筛**——全零合约是真实训练数据的一部分，筛掉就是改了实验。
        train_names = [b for b in train_names if any(index[b])][:args.limit_contracts]
        val_names = val_names[:max(4, args.limit_contracts // 2)]
    n_train = len(train_names)
    label_of = {b: torch.tensor(index[b], dtype=torch.float32)
                for b in train_names + val_names}
    train_labels = torch.stack([label_of[b] for b in train_names])
    print(f"[ft] split_seed{args.split_seed}  train={n_train} val={len(val_names)} "
          f"test={len(test_names)}（已断言 train ∩ val∪test = ∅）", flush=True)

    # ---- 文本（复用 M3 口径）与分词 ----
    from transformers import AutoTokenizer
    tok = load_hf_offline_fallback(lambda: AutoTokenizer.from_pretrained(args.codebert),
                                   args.codebert, "tokenizer")
    texts = contract_texts(Path(args.graph_dir), train_names + val_names)
    trunc = args.max_funcs_per_contract
    seqs_of = {b: v[:trunc] for b, v in tokenize_all(texts, tok, 512).items()}
    val_names = [b for b in val_names if seqs_of.get(b)]      # 无函数序列的合约不参与打分
    n_seq = sum(len(seqs_of[b]) for b in train_names if b in seqs_of)
    print(f"[ft] 训练序列 {n_seq} 条（合约均 {n_seq / max(n_train, 1):.1f} 个函数）", flush=True)

    # ---- 模型 / 优化器 / 损失权重（**与 train.py 同口径**）----
    torch.manual_seed(args.seed)
    model = CodeBertContract(args.codebert)
    # 梯度检查点：一个 step 内**所有 micro-batch 的图都要活到 backward**（见
    # `pooled_contracts` 的说明），8 GB 卡上不检查点会直接 OOM（已实测）。
    # 代价约 20–30% 速度，换来激活显存降一个量级——本项是"能跑完"与"跑不完"的区别。
    if args.grad_checkpoint:
        model.encoder.gradient_checkpointing_enable()
        model.encoder.config.use_cache = False
    model = model.to(device)
    pos_weight, class_mask, _, _, _ = class_stats(train_labels, pos_weight_cap=args.pos_weight_cap)
    pos_weight, class_mask = pos_weight.to(device), class_mask.to(device)
    opt = torch.optim.AdamW([
        {"params": model.encoder.parameters(), "lr": args.lr},
        {"params": model.head.parameters(), "lr": args.head_lr},
    ], weight_decay=args.weight_decay)
    sched = torch.optim.lr_scheduler.ReduceLROnPlateau(opt, mode="max", factor=0.5, patience=1)
    pad_id = tok.pad_token_id if tok.pad_token_id is not None else 0

    # ---- 训练循环（判据 = **val macro-F1**，大纲第 452 行点名此指标）----
    log, best_f1, best_epoch, bad = [], -1.0, -1, 0
    t_start = time.perf_counter()
    for epoch in range(1, args.epochs + 1):
        model.train()
        order = torch.randperm(n_train, generator=torch.Generator().manual_seed(
            args.seed * 1000 + epoch)).tolist()
        bs = args.contracts_per_batch
        losses = []
        for lo in range(0, n_train, bs):
            batch = [train_names[i] for i in order[lo:lo + bs]]
            batch = [b for b in batch if seqs_of[b]]
            if not batch:
                continue
            pooled = pooled_contracts(model, seqs_of, batch, args.seq_batch, device, pad_id)
            z = model.head(pooled)
            y = torch.stack([label_of[b] for b in batch]).to(device)
            loss = masked_weighted_bce(z, y, pos_weight, class_mask)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            losses.append(float(loss))
        f1, _, _ = score(model, seqs_of, val_names, label_of, args.seq_batch, device, pad_id)
        sched.step(f1)
        log.append({"epoch": epoch, "train_loss": round(sum(losses) / max(len(losses), 1), 6),
                    "val_macro_f1": round(float(f1), 6),
                    "lr": opt.param_groups[0]["lr"],
                    "seconds": round(time.perf_counter() - t_start, 1)})
        print(f"[ft] epoch {epoch}: loss={log[-1]['train_loss']:.4f} "
              f"val_macro_f1={f1:.4f} lr={log[-1]['lr']:.2e} "
              f"({log[-1]['seconds']}s)", flush=True)
        if f1 > best_f1:
            best_f1, best_epoch, bad = float(f1), epoch, 0
            model.encoder.save_pretrained(encoder_dir)
            tok.save_pretrained(encoder_dir)
        else:
            bad += 1
            if bad >= args.patience:
                print(f"[ft] val macro-F1 连续 {bad} 个 epoch 未提升，早停于 epoch {epoch}", flush=True)
                break

    # 🔴 `encoder/` 的**语料边车**：让编码器自描述"我是用哪个语料微调的"。
    # 下游 `build_graph_variant.build_cb_ft` 靠它做硬校验——跨语料套用不会报错，
    # 只会静默产出一个错误的消融，所以归属必须写在产物里、由下游断言，而不是靠约定。
    (encoder_dir / "corpus.json").write_text(json.dumps({
        "corpus": corpus, "graph_dir": str(Path(args.graph_dir).resolve()),
        "split_dir": str(Path(args.split_dir).resolve()),
        "label_file": args.label_file, "label_key_mode": args.label_key_mode,
        "split_seed": args.split_seed,
        "note": "本文件只作语料归属标识；HF `from_pretrained` 会忽略它。",
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    (out_dir / "config.json").write_text(json.dumps({
        "args": vars(args), "device": device, "torch_version": torch.__version__,
        "split_seed": args.split_seed, "corpus": corpus,
        "split_counts": {"train": len(train_names), "val": len(val_names),
                         "test": len(test_names)},
        "leak_check": "train ∩ (val ∪ test) = ∅（未用 --limit-contracts 时强制断言）",
        "text_spec": "函数源码 src_lines[fs-1:fe]，512 token 截断；与 m3_build_features 同源",
        "selection_metric": "val macro-F1（大纲第 452 行）",
        "best_epoch": best_epoch, "best_val_macro_f1": round(best_f1, 6),
        "n_train_sequences": n_seq,
        "pos_weight": [round(float(v), 6) for v in pos_weight.cpu()],
        "class_mask": [int(v) for v in class_mask.cpu()],
        "epochs_log": log,
        "timing": {"wall_seconds": round(time.perf_counter() - t_start, 1)},
        "encoder_dir": str(encoder_dir),
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[ft] 完成：best epoch {best_epoch} val_macro_f1={best_f1:.4f} → {encoder_dir}", flush=True)


if __name__ == "__main__":
    main()
