#!/usr/bin/env python3
"""MVD-HG 基线（5.3）**训练 + 评估**：7 维 logits + `BCEWithLogitsLoss`。

输入 = `scripts/baseline_mvdhg_build.py` 产出的 `feat/<base>.pt`（它的原代码建出的
AST/CFG/DFG 异构图 + 300 维 word2vec 节点特征）。

产物 = `eval_results/baseline/mvdhg/seed{S}/{test_probs.pt, val_best_probs.pt,
thresholds.json, results.json, config.json, best.pt, log.txt}` —— 形制与 `runs/seed{S}/`
一致，故 `collect_three_caliber_tables.row_from_run` 能**零重实现**直接读。

用法（仓库根目录）：
    python scripts/baseline_mvdhg.py --seed 0 --limit-graphs 8 --epochs 2   # 冒烟
    python scripts/baseline_mvdhg.py --seed 0                               # 单种子全量
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402
import baseline_models as BM                                             # noqa: E402

NAME = "mvdhg"
RECONSTRUCTION_NOTES = [
    "建图由 MVD-HG 原仓库代码（read_compile / append_control_flow_information / "
    "append_data_flow_information）产出，AST 为 solc --ast-compact-json 的 compact 格式。",
    "词向量用 gensim 4.3 的 Word2Vec(vector_size=300)，语料**只用 train 划分**"
    "（原实现用 train+val 全体拟合，对我们是泄漏）；原代码的 gensim 3 `size=` 在 base 里会 TypeError。",
    "节点特征公式逐字保留：w2v[node_type] + Σ w2v[hump2sub(value/name)]；"
    "已用原实现逐字段对拍（--faithful-node-json）。",
    "DFG 有 40 s/文件上限（原仓库默认）：超时样本记 dfg_timeout，其图只含部分 DFG 边。",
    "输出头 1→7、去掉末尾 Sigmoid、改 BCEWithLogitsLoss（大纲 5.3 [411]）；"
    "原实现把标签 OR 塌成 1 维，我们保留 7 维。",
    "dropout 保持它的 config.dropout_pro=0.1（不是正典的 0.3）—— 复现优先。",
    "池化按图中实际出现的 owner_contract 分组（逐合约均值 → 跨合约平均），"
    "而不是按 contract_buggy_record 的键（后者取决于标签文件是否收录该合约名）。",
]


class FeatDataset(torch.utils.data.Dataset):
    """预加载 `feat/<base>.pt` 到内存（453 个约 0.5 GB；每 epoch 读盘不划算）。"""

    def __init__(self, bases: list[str], feat_root: Path):
        self.bases = list(bases)
        self.items = []
        for b in self.bases:
            p = feat_root / "feat" / f"{b}.pt"
            if not p.exists():
                raise SystemExit(f"[mvdhg] 缺离线特征 {p}；先跑 baseline_mvdhg_build.py")
            d = torch.load(p, map_location="cpu")
            groups: dict[str, list[int]] = {}
            for i, c in enumerate(d["owner_contract"]):
                groups.setdefault(c if c is not None else "__none__", []).append(i)
            self.items.append({"base": b, "x": d["x"], "edge_index": d["edge_index"],
                               "edge_type": d["edge_type"],
                               "groups": [torch.tensor(v, dtype=torch.long)
                                          for v in groups.values()]})

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        return self.items[i]


def collate_mvdhg(samples, labels_map, device=None):
    xs, eis, ets, groups, ys, names = [], [], [], [], [], []
    off = 0
    for s in samples:
        n = s["x"].shape[0]
        xs.append(s["x"])
        if s["edge_index"].numel():
            eis.append(s["edge_index"] + off)
            ets.append(s["edge_type"])
        groups.append([g + off for g in s["groups"]])
        ys.append(torch.as_tensor(labels_map[s["base"]], dtype=torch.float32))
        names.append(s["base"])
        off += n
    edge_index = (torch.cat(eis, 1) if eis else torch.zeros((2, 0), dtype=torch.long))
    edge_type = (torch.cat(ets) if ets else torch.zeros(0, dtype=torch.long))
    out = {"x": torch.cat(xs, 0), "edge_index": edge_index, "edge_type": edge_type,
           "groups": groups, "labels": torch.stack(ys, 0), "names": names}
    return B.to_device(out, device) if device else out


def _forward(model, batch):
    return model(batch["x"], batch["edge_index"], batch["edge_type"], batch["groups"])


def main() -> int:
    p = B.base_parser("MVD-HG 基线（7 维多标签）训练与评估。", NAME)
    args = p.parse_args()
    if args.smoke:
        args.epochs = args.epochs if args.epochs != 200 else 2
        # 🔴 **不要**在冒烟里缩 `--limit-graphs`：split 前缀全是干净合约（7 类真值全 0），
        # `class_stats` 会正确地报「所有类别正样本均为 0，无法训练」而中止。
        # 冒烟改缩 **batch 数**（数据池仍是全量，只是每 epoch 只跑前几个 batch）。
        args.limit_batches = args.limit_batches or 3
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
    ds = {arm: FeatDataset(limited(arm), feat_root) for arm in ("train", "val", "test")}
    labels_map = {b: index[b] for b in split["train"] + split["val"] + split["test"]}

    train_labels = torch.stack([torch.as_tensor(index[b], dtype=torch.float32)
                                for b in limited("train")], 0)
    pos_weight, class_mask, active, train_pos, _ = B.class_stats_of(train_labels,
                                                                   args.pos_weight_cap)
    print(f"[mvdhg] train {len(ds['train'])} / val {len(ds['val'])} / test {len(ds['test'])}"
          f"；active classes {active}/7；pos_weight {[round(float(v),2) for v in pos_weight]}",
          flush=True)

    torch.manual_seed(args.seed)
    model = BM.MVDHGRGCN(dropout=0.1)
    n_par = sum(p_.numel() for p_ in model.parameters())
    print(f"[mvdhg] 参数量 {n_par/1e6:.3f} M", flush=True)
    cf = B.TrainCfg(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr,
                    weight_decay=args.weight_decay,
                    scheduler_patience=args.scheduler_patience,
                    early_stop_patience=args.early_stop_patience,
                    pos_weight_cap=args.pos_weight_cap, seed=args.seed, device=device,
                    limit_batches=args.limit_batches, accum_steps=args.accum_steps)
    gen = torch.Generator().manual_seed(args.seed * 100000 + 1)
    # micro-batch = batch_size // accum_steps ⇒ 显存按 micro 算，**等效 batch 不变**
    micro = max(1, args.batch_size // max(1, args.accum_steps))
    tr = B.torch_loader(ds["train"], lambda b: collate_mvdhg(b, labels_map, device),
                        micro, True, generator=gen)
    va = B.torch_loader(ds["val"], lambda b: collate_mvdhg(b, labels_map, device),
                        args.batch_size, False)
    te = B.torch_loader(ds["test"], lambda b: collate_mvdhg(b, labels_map, device),
                        args.batch_size, False)

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

    results = {
        "baseline": NAME, "seed": args.seed, "split_seed": split_seed, "head": "multi",
        "select_metric": "val_micro_f1", "val_threshold": float(thr["best_threshold"]),
        "threshold_scan": thr, "mAP": None,
        "test": {wp: B.report_of(test_probs, test_labels, t)
                 for wp, t in (("fixed_0.5", 0.5), ("val_threshold", thr["best_threshold"]))},
        "best_epoch": out.best_epoch, "best_val_micro_f1": out.best_monitor,
        "n_train_graphs": len(ds["train"]), "n_val_graphs": len(ds["val"]),
        "coverage": {"n_features": len(list((feat_root / "feat").glob("*.pt"))),
                     "dropped": {k: len(v) for k, v in dropped.items()},
                     "dropped_test": dropped["test"]},
        "n_test_graphs": len(ds["test"]),
        "reconstruction_notes": RECONSTRUCTION_NOTES,
        "partial": (not full),
        "n_params": n_par,
        "timing": {"train_seconds": round(out.seconds, 2),
                   "wall_seconds": round(time.time() - t0, 2),
                   "seconds_per_epoch": round(out.seconds / max(1, len(out.history)), 2)},
        "environment": {"device": device, "torch": torch.__version__},
    }
    import metrics
    results["mAP"] = metrics.mean_average_precision(test_probs, test_labels)
    config = {"args": {k: v for k, v in vars(args).items()}, "split_seed": split_seed,
              "head": "multi", "baseline": NAME, "notes": RECONSTRUCTION_NOTES,
              "derived": {"in_dim": 300, "hidden": [64, 32, 16, 8], "num_relations": 3,
                          "num_classes": 7, "dropout": 0.1,
                          "active_classes": active,
                          "train_pos": [int(v) for v in train_pos],
                          "pos_weight": [round(float(v), 4) for v in pos_weight]}}
    B.write_bundle(bundle, out_dir, thr_scan=thr, results=results, config=config)
    (out_dir / "log.txt").write_text(
        "\n".join(json.dumps(h, ensure_ascii=False) for h in out.history), encoding="utf-8")
    torch.save({"model_state_dict": model.state_dict()}, out_dir / "best.pt")
    print(f"[mvdhg] seed{args.seed} 完成：val_thr={thr['best_threshold']} "
          f"test micro@0.5={results['test']['fixed_0.5']['micro_f1']:.4f} "
          f"@thr={results['test']['val_threshold']['micro_f1']:.4f} "
          f"（best epoch {out.best_epoch}，{out.seconds:.0f}s）→ {out_dir}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
