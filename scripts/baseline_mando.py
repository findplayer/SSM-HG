#!/usr/bin/env python3
"""MANDO-LLM 基线（5.3）**训练 + 评估**：异构节点类型 + `HGTConv` → 7 维 logits。

🔴 **与 dgl 原版的对应关系**（逐项）：`HGTLayer` ⟷ PyG `HGTConv`、`edge_softmax(norm_by='dst')`
⟷ 按目标结点 softmax、`multi_update_all(cross_reducer='mean')` ⟷ mean 聚合。规模照它的
默认值与实测 checkpoint：2 层 / hidden 128 / heads 8。唯一改动 = `out_size 2→7`
（CE → BCEWithLogits），符合大纲 5.3 [411]。

**节点类型取 9 类语义角色**（`dataset.ROLE_NAMES`）：MANDO-LLM 的「异构图 transformer」
核心就是**每种节点类型独立的 K/Q/V**；只用 1 类会把它退化成「带 N 组关系参数的 RGCN
+ 逐关系 softmax」，丢掉该算子的本质。它的原图节点类型来自 slither 的 CFG 节点种类，
本仓最近似的现成类比物就是 `_feat.pt::type_id` 的 9 类角色。

**图 = 我方 CFG 中心异构图**（`products/<语料>/graphs_ft/ss{S}`）——这一点必须随结果披露：
原版吃的是它自己的 slither 图，形态不同。

输入走 `dataset.load_graph`（与本文方法**逐字相同的通道字典**），主臂 `--node-feature fuser`
经 `model.NodeFuser` 融合 ⇒ 与本文方法**唯一变量 = 图算子**（RGCN → HGT）。

产物 = `eval_results/baseline/mando/seed{S}/…`，形制与 `runs/seed{S}/` 一致。

用法（仓库根目录）：
    python scripts/baseline_mando.py --meta-only                       # 冻结 metadata + 冒烟
    python scripts/baseline_mando.py --seed 0 --limit-graphs 8 --epochs 2   # 冒烟
    python scripts/baseline_mando.py --seed 0                          # 单种子全量
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import torch
import torch.nn as nn

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402
import baseline_models as BM                                             # noqa: E402
import dataset as D                                                      # noqa: E402

NAME = "mando"
RECONSTRUCTION_NOTES = [
    "🔴 图算子用 PyG 2.7 的 `HGTConv` 替代 dgl 的 `HGTLayer`（base 环境无 dgl、不新建 conda 环境）。"
    "逐项对应：relation_att/relation_msg/relation_pri ⟷ k_rel/v_rel/p_rel、"
    "edge_softmax(norm_by='dst') ⟷ 按目标结点 softmax、cross_reducer='mean' ⟷ mean 聚合、"
    "skip(α=sigmoid(skip)) + a_linear + LayerNorm ⟷ PyG 的 skip/out_lin。"
    "**参数化方式不是逐位等价**（PyG 用 bases/attention 分解），故不得声称复现了作者原结果。",
    "🔴 图 = **我方 CFG 中心异构图**（`graphs_ft/ss{S}`），不是原版的 slither 图；"
    "节点类型取 `_feat.pt::type_id` 的 9 类语义角色（原版用 slither CFG 节点种类）。",
    "节点输入主臂 = `model.NodeFuser` 融合后的 h_v^(0)（与本文方法**逐字相同**的通道字典）"
    "⇒ 与本文方法的唯一变量 = 图算子。对照臂 `role_onehot` / `cb_node_raw` 见 `--node-feature`。",
    "fuser 与 HGT **联合训练**（端到端），不是冻结特征。",
    "🔴 **metadata 跨 seed 冻结**（`hgt_metadata.json`，带 pool_sha256）：三 seed 必须共用同一份"
    "`(node_types, edge_types)`，否则各 seed 参数量不同、不是同一个模型。"
    "它只由 `type_id` 与 `edge_type` 扫出，不碰标签 ⇒ 不构成泄漏。",
    "输出头 2→7（原版是 7 个独立二分类 / CE）、改 BCEWithLogitsLoss（大纲 5.3 [411]）。",
    "训练期先验/结构 dropout 沿用本方 `sample_dropout_masks`（p=0.2），随 batch 传入 `NodeFuser`；"
    "验证/推理不传掩码。",
]


# --------------------------------------------------------------------------- metadata
def pool_fingerprint(pool: list[str], graph_dir: str) -> str:
    """**旧口径**指纹：把 `graph_dir` 的**路径**也哈希进去。保留只为兼容库里的老 metadata。"""
    h = hashlib.sha256()
    h.update(str(Path(graph_dir).resolve()).encode())
    for b in sorted(pool):
        h.update(b.encode())
    return h.hexdigest()


def structure_fingerprint(pool: list[str]) -> str:
    """**新口径**指纹：只按**池**算，不含路径。

    它才是 `hgt_metadata.json` 真正依赖的东西——该文件是
    `(node_types, edge_types)` 的并集，而这两者只来自 `_pyg.pt::edge_type/edge_index`
    与 `_feat.pt::type_id`（**结构通道**），与 `graph_dir` 叫什么名字无关。

    🔴 **为什么必须去掉路径**（2026-09-23 实测踩到）：`graphs_ft/ss{S}` 与
    `graphs_ft_buggy/cb_ft_ss{S}` 的三种子变体**结构逐字节相同**（`_hetero.json` 同哈希、
    `_pyg.pt` 逐位相同、`_feat.pt::type_id` 逐位相同、全池词表同为 9×187），
    只有 CodeBERT 通道 `_cb.pt` 不同。任务 2 的新正典要求 `cb_ft_ss{S}` 与 `--split-seed S`
    **配对**（`AGENTS.md` 语义锁死项），于是一份形态上完全正确的 metadata 会被
    path-based 的旧指纹判成「不同语料」而**硬失败**（实测：MANDO 的 seed1/seed2 在 2–3 s 内 rc=1）。
    旧口径之所以没暴露这个错，是因为 canon37 段三种子**都用 `ss0`**（`decisions.md` §52.3）。

    ⚠ **保护没有丢**：池换了（453 ↔ 497）指纹就变，故「漏传 `--feature-suffix` 就会拿另一个池的
    metadata」这条仍然被挡住。**路径**本身从来不是保护对象。
    """
    h = hashlib.sha256(b"ssmhg-hgt-structure-v1\x00")
    for b in sorted(pool):
        h.update(b.encode())
        h.update(b"\x00")
    return h.hexdigest()


def scan_metadata(pool: list[str], graph_dir: str, *, force: bool = False,
                  suffix: str = "") -> dict:
    """扫全池 → `(node_types, edge_types)` 并集，冻结进 `hgt_metadata.json`。

    只用 `type_id` 与 `edge_type`（**不碰标签**）⇒ 结构词表，不构成泄漏。

    `suffix` = 正典后缀（同 `feature_root`）。497 池实测比 453 池**多一种边类型**
    （`('OTHER','AST_PARENT','CONDITION')`，9×187 vs 9×186），故两个正典的 metadata
    **不是同一份**。若漏传后缀，指纹会不匹配并提示「加 `--force-meta` 重建」——
    **照做就会用 497 的结构覆盖 453 那份**，而文件"看起来还对"，canon MANDO 从此静默不可复现。
    故后缀与池必须同进同出。
    """
    path = B.feature_root(NAME, suffix) / "hgt_metadata.json"
    fp = pool_fingerprint(pool, graph_dir)
    sfp = structure_fingerprint(pool)
    if path.exists() and not force:
        d = json.loads(path.read_text(encoding="utf-8"))
        # 🔴 **两个指纹匹配其一即放行**（见 `structure_fingerprint` 的 docstring）：
        # 库里的老 metadata 只有 `pool_sha256`（含路径）⇒ 按老口径仍能匹配；
        # 新写的两者都有 ⇒ **同结构、不同编码器变体**（`ss{S}` vs `cb_ft_ss{S}`、跨 ss 变体）
        # 可以合法复用一份词表，而**换池**依然会被拒。
        ok = (d.get("pool_sha256") == fp) or (d.get("structure_sha256") == sfp)
        if not ok:
            raise SystemExit(
                f"[mando] {path} 的词表指纹与当前池不符（不同语料）："
                f"pool_sha256 {str(d.get('pool_sha256'))[:12]} != {fp[:12]}；"
                f"structure_sha256 {str(d.get('structure_sha256'))[:12]} != {sfp[:12]}；"
                f"确认无误后加 --force-meta 重建")
        # 🔴 JSON 会把 tuple 还原成 list，而 `HGTConv` 用 edge type 做 dict 的键 ⇒
        # **unhashable type: 'list'**。落盘用 list（JSON 只认 list），**读回必须转回 tuple**。
        d["edge_types"] = [tuple(e) for e in d["edge_types"]]
        return d

    roles = list(D.ROLE_NAMES)
    ets: set[tuple[str, str, str]] = set()
    n_seen = 0
    for b in pool:
        pp = Path(graph_dir) / f"{b}_pyg.pt"
        fpth = Path(graph_dir) / f"{b}_feat.pt"
        if not (pp.exists() and fpth.exists()):
            continue
        payload = torch.load(pp, map_location="cpu")
        tid = torch.load(fpth, map_location="cpu")["type_id"]
        ei, et = payload["edge_index"], payload["edge_type"]
        src, dst = tid[ei[0]].tolist(), tid[ei[1]].tolist()
        for s, d_, r in zip(src, dst, et.tolist()):
            ets.add((roles[s], D.RELATION_NAMES_EXT.get(r, str(r)), roles[d_]))
        n_seen += 1
    meta = {"node_types": roles, "edge_types": [list(e) for e in sorted(ets)],
            "pool_sha256": fp, "structure_sha256": sfp, "n_graphs_scanned": n_seen,
            "note": "结构词表（type_id × edge_type 并集），不含标签。"
                    "structure_sha256 只按池算（不含路径）⇒ 同结构的不同编码器变体可复用；"
                    "pool_sha256 是含路径的旧口径，保留供老文件匹配"}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[mando] metadata 已冻结：{len(roles)} 种节点类型 × {len(ets)} 种边类型"
          f"（扫了 {n_seen} 图）→ {path}", flush=True)
    meta["edge_types"] = [tuple(e) for e in sorted(ets)]     # 内存里必须是 tuple（见上）
    return meta


# --------------------------------------------------------------------------- 批 → 异构图
def to_hetero(x_all, type_id, edge_index, edge_type, metadata):
    """全局批图 → `(x_dict, edge_index_dict)`。

    🔴 **下标是「类型内」的**（异构图语义）：每个节点类型各自从 0 开始连续编号，
    所以 `local[global_idx]` 给出该节点在**本类型内**的位置。
    `x_dict[nt]` 按全局序取（= 图0 的该类型节点、图1 的该类型节点…），
    与 `MandoHGT.forward` 的 `batch_index` 顺序契约一致。
    """
    node_types, edge_types = metadata["node_types"], metadata["edge_types"]
    T = len(node_types)
    idx_by_type = {nt: (type_id == i).nonzero(as_tuple=False).reshape(-1)
                   for i, nt in enumerate(node_types)}
    local = torch.empty(type_id.numel(), dtype=torch.long, device=type_id.device)
    for nt in node_types:
        idx = idx_by_type[nt]
        local[idx] = torch.arange(idx.numel(), dtype=torch.long, device=type_id.device)
    x_dict = {nt: x_all[idx_by_type[nt]] for nt in node_types}

    rel_ids = sorted({int(r) for r in edge_type.tolist()}) or [0]
    R = max(rel_ids) + 1
    src_role = type_id[edge_index[0]]
    dst_role = type_id[edge_index[1]]
    bid = (src_role * R + edge_type) * T + dst_role                       # [E] 桶号
    order = torch.argsort(bid)
    bs = bid[order]
    uniq, counts = torch.unique_consecutive(bs, return_counts=True)
    src_l = local[edge_index[0]][order]
    dst_l = local[edge_index[1]][order]
    starts = torch.cat([counts.new_zeros(1), counts.cumsum(0)[:-1]])
    bucket = {}
    for u, c, st in zip(uniq.tolist(), counts.tolist(), starts.tolist()):
        # u = (s * R + r) * T + d ⇒ 反解顺序必须是「先 //(R*T) 得 s、再 %T 得 d」。
        # 🔴 曾把 s/d 写反，于是 `edge_index_dict` 的键把源与目标类型对调，
        # 行下标落进**别的类型**的节点数范围 ⇒ PyG 报
        # 「indices larger than 384 (got 421)」，GPU 上则是一句 device-side assert。
        s_role, rel, d_role = u // (R * T), (u // T) % R, u % T
        key = (node_types[s_role], D.RELATION_NAMES_EXT.get(rel, str(rel)), node_types[d_role])
        bucket[key] = torch.stack([src_l[st:st + c], dst_l[st:st + c]])
    empty = torch.empty((2, 0), dtype=torch.long, device=type_id.device)
    edge_index_dict = {k: bucket.get(k, empty) for k in edge_types}
    return x_dict, edge_index_dict


class MandoModel(nn.Module):
    """`NodeFuser`（可选）→ 异构切分 → `MandoHGT` → `[B,7]` logits。"""

    def __init__(self, metadata, *, mode: str, d_struct: int = 0,
                 struct_layout: dict | None = None, hidden: int = 128,
                 num_layers: int = 2, heads: int = 8, dropout: float = 0.3,
                 prior_dropout: float = 0.2, struct_dropout: float = 0.2):
        super().__init__()
        from model import NodeFuser
        self.metadata = metadata
        self.mode = mode
        self.prior_dropout, self.struct_dropout = prior_dropout, struct_dropout
        if mode == "fuser":
            self.fuser = NodeFuser(d_struct, struct_layout,
                                   prior_dropout=prior_dropout, struct_dropout=struct_dropout)
            in_dim = self.fuser.hidden
        elif mode == "role_onehot":
            self.fuser = None
            in_dim = len(metadata["node_types"])
        elif mode == "cb_node_raw":
            self.fuser = None
            in_dim = D.CB_DIM
        else:
            raise SystemExit(f"[mando] 未知 --node-feature {mode}")
        self.in_dim = in_dim
        self.hgt = BM.MandoHGT(metadata=(metadata["node_types"], metadata["edge_types"]),
                               in_dim=in_dim, hidden=hidden, num_layers=num_layers,
                               heads=heads, num_classes=7, dropout=dropout)

    def forward(self, batch):
        ch, batch_idx = batch["channels"], batch["batch"]
        if self.mode == "fuser":
            pm = sm = None
            if self.training:
                from model import sample_dropout_masks
                pm, sm = sample_dropout_masks(int(batch_idx.max()) + 1,
                                              prior_p=self.prior_dropout,
                                              struct_p=self.struct_dropout)
                pm, sm = pm.to(batch_idx.device), sm.to(batch_idx.device)
            x_all = self.fuser(ch, prior_mask=pm, struct_mask=sm, batch=batch_idx)
        elif self.mode == "role_onehot":
            x_all = torch.nn.functional.one_hot(
                ch["type_id"], len(self.metadata["node_types"])).to(torch.float32)
        else:
            x_all = ch["cb_node"]
        x_dict, ei_dict = to_hetero(x_all, ch["type_id"], batch["edge_index"],
                                    batch["edge_type"], self.metadata)
        return self.hgt(x_dict, ei_dict, batch_index=batch_idx)


# --------------------------------------------------------------------------- 数据
class GraphDataset(torch.utils.data.Dataset):
    """预加载 `dataset.load_graph`（453 图全池约 291 MB，可常驻内存）。"""

    def __init__(self, bases: list[str], graph_dir: str, index: dict):
        self.items = []
        for b in bases:
            self.items.append(D.load_graph(b, graph_dir=graph_dir, index=index))

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        return self.items[i]


def collate_mando(samples, device=None):
    channels, ei, et, batch, labels = D.collate(samples, training=False, head="multi")
    out = {"channels": channels, "edge_index": ei, "edge_type": et,
           "batch": batch, "labels": labels, "names": [s.name for s in samples]}
    return B.to_device(out, device) if device else out


def _forward(model, batch):
    return model(batch)


# --------------------------------------------------------------------------- 主流程
def parse_args():
    p = B.base_parser("MANDO-LLM 基线（7 维多标签）训练与评估。", NAME)
    p.add_argument("--node-feature", choices=["fuser", "role_onehot", "cb_node_raw"],
                   default="fuser", help="节点输入。主臂 fuser（与本文方法同输入），另两个为对照臂。")
    p.add_argument("--heads", type=int, default=8)
    p.add_argument("--hgt-layers", type=int, default=2)
    p.add_argument("--hgt-hidden", type=int, default=128)
    p.add_argument("--prior-dropout", type=float, default=0.2)
    p.add_argument("--struct-dropout", type=float, default=0.2)
    p.add_argument("--meta-only", action="store_true", help="只冻结 metadata + 3 图 forward 冒烟。")
    p.add_argument("--force-meta", action="store_true", help="无视 pool_sha256 重建 metadata。")
    return p.parse_args()


def main() -> int:
    args = parse_args()
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
    pool = [b for b in split["train"] + split["val"] + split["test"] if b in index]
    meta = scan_metadata(pool, args.graph_dir, force=args.force_meta,
                         suffix=args.feature_suffix)

    if args.meta_only:
        probe = [b for b in pool if (Path(args.graph_dir) / f"{b}_feat.pt").exists()][:3]
        ds = GraphDataset(probe, args.graph_dir, index)
        batch = collate_mando(list(ds), device)
        ref = D.load_graph(probe[0], graph_dir=args.graph_dir, index=index)
        model = MandoModel(meta, mode=args.node_feature, d_struct=int(ref.meta["D_struct"]),
                           struct_layout=dict(ref.meta["struct_layout"]),
                           hidden=args.hgt_hidden, num_layers=args.hgt_layers,
                           heads=args.heads, dropout=args.model_dropout,
                           prior_dropout=args.prior_dropout, struct_dropout=args.struct_dropout)
        model = model.to(device)
        n_par = sum(p_.numel() for p_ in model.parameters())
        out = model(batch)
        out.sum().backward()
        n_grad = sum(1 for p_ in model.parameters() if p_.grad is not None and p_.grad.abs().sum() > 0)
        print(f"[mando] metadata：{len(meta['node_types'])} 种节点类型 × "
              f"{len(meta['edge_types'])} 种边类型；node-feature={args.node_feature}")
        print(f"[mando] 参数量 {n_par/1e6:.3f} M；3 图 forward+backward 通过，"
              f"有非零梯度的参数张量 {n_grad}/{sum(1 for _ in model.parameters())}")
        print(f"[mando] logits {tuple(out.shape)}")
        return 0

    out_dir = Path(args.out_dir) / f"seed{args.seed}"
    B.guard_dir(out_dir, args, split_seed, overwrite=args.overwrite)

    def limited(arm):
        bs = split[arm]
        return bs[:args.limit_graphs] if args.limit_graphs else bs

    ds = {arm: GraphDataset(limited(arm), args.graph_dir, index)
          for arm in ("train", "val", "test")}
    labels_map = {b: index[b] for b in split["train"] + split["val"] + split["test"]}
    train_labels = torch.stack([torch.as_tensor(index[b], dtype=torch.float32)
                                for b in limited("train")], 0)
    pos_weight, class_mask, active, train_pos, _ = B.class_stats_of(train_labels,
                                                                    args.pos_weight_cap)

    ref = ds["train"][0]
    torch.manual_seed(args.seed)
    model = MandoModel(meta, mode=args.node_feature, d_struct=int(ref.meta["D_struct"]),
                       struct_layout=dict(ref.meta["struct_layout"]),
                       hidden=args.hgt_hidden, num_layers=args.hgt_layers, heads=args.heads,
                       dropout=args.model_dropout, prior_dropout=args.prior_dropout,
                       struct_dropout=args.struct_dropout)
    n_par = sum(p_.numel() for p_ in model.parameters())
    print(f"[mando] train {len(ds['train'])} / val {len(ds['val'])} / test {len(ds['test'])}"
          f"；metadata {len(meta['node_types'])}×{len(meta['edge_types'])}；"
          f"node-feature={args.node_feature}；in_dim={model.in_dim}；参数量 {n_par/1e6:.3f} M；"
          f"active classes {active}/7", flush=True)

    cf = B.TrainCfg(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr,
                    weight_decay=args.weight_decay,
                    scheduler_patience=args.scheduler_patience,
                    early_stop_patience=args.early_stop_patience,
                    pos_weight_cap=args.pos_weight_cap, seed=args.seed, device=device,
                    limit_batches=args.limit_batches, accum_steps=args.accum_steps)
    gen = torch.Generator().manual_seed(args.seed * 100000 + 1)
    # micro-batch = batch_size // accum_steps ⇒ 显存按 micro 算，**等效 batch 不变**
    micro = max(1, args.batch_size // max(1, args.accum_steps))
    tr = B.torch_loader(ds["train"], lambda b: collate_mando(b, device),
                        micro, True, generator=gen)
    va = B.torch_loader(ds["val"], lambda b: collate_mando(b, device), args.batch_size, False)
    te = B.torch_loader(ds["test"], lambda b: collate_mando(b, device), args.batch_size, False)

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
              "derived": {"in_dim": model.in_dim, "n_params": n_par,
                          "n_node_types": len(meta["node_types"]),
                          "n_edge_types": len(meta["edge_types"]),
                          "pool_sha256": meta["pool_sha256"], "active_classes": active,
                          "train_pos": [int(v) for v in train_pos],
                          "pos_weight": [round(float(v), 4) for v in pos_weight]}}
    B.write_bundle(bundle, out_dir, thr_scan=thr, results=results, config=config)
    (out_dir / "log.txt").write_text(
        "\n".join(json.dumps(h, ensure_ascii=False) for h in out.history), encoding="utf-8")
    torch.save({"model_state_dict": model.state_dict()}, out_dir / "best.pt")
    print(f"[mando] seed{args.seed} 完成：val_thr={thr['best_threshold']} "
          f"test micro@0.5={results['test']['fixed_0.5']['micro_f1']:.4f} "
          f"@thr={results['test']['val_threshold']['micro_f1']:.4f} "
          f"（best epoch {out.best_epoch}，{out.seconds:.0f}s）→ {out_dir}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
