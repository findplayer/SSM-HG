#!/usr/bin/env python3
"""M5 数据层（手册 10.2/12.3；2026-09-12 前端化后）：_pyg.pt 结构 + 通道字典组合、标签对齐、边级消融。

契约（语义锁死；设计稿 `docs/M3_frontend_design.md` §2/§3.1/§4）：
  - `_pyg.pt` 只读（纯结构：edge_index/edge_type/元数据；其 `x` 为 N×1 占位、不回写）；
  - 模型输入 = **通道字典**，固定序 `CHANNEL_ORDER = (cb_func, cb_node, type_id, struct, sv)`：
      * `_feat.pt`（schema v2，M3 产出）提供 `struct` / `type_id` / `sv` 三通道 + `meta`
        （含逐通道 sha256 与 `combined_sha256`）；
      * `_cb.pt`（中间缓存）提供 `cb_func` / `cb_node` 两通道，在本层按节点行序对齐；
  - **本层只组合**：不做融合（无 MLP）、**不做任何掩码/置零**（确定性消融与训练期 dropout
    全在 `model.NodeFuser` 内，共用同一掩码原语）；
  - 逐通道哈希校验：三个便宜通道（struct/type_id/sv）默认每次加载校验；cb 两通道只在
    `verify_channels="all"`（CLI `--verify-channel-hash`）时重算（≈0.6 GB / 全库）；
    **失败时报具体通道名**；
  - 标签按**项目前缀**匹配（lower；剥前缀顺序先 nasd_ 后 asd_——nasd_ 含 asd_ 子串，
    先剥 asd_ 会把 nasd_xxx 误剥成 nxxx），项目内多合约 targets 取并集；
  - `load_graph` 断言 base 存在标签（第一道一致性防线，split 内缺标签直接报错）；
  - 边级消融：`drop_edges` 为**物理关系编号集合**，加载时校验白名单 `DROPPABLE_EDGES`
    （非白名单编号直接报错）；`--drop-ast` 等价于删 relation 1+2（AST_PARENT + AST_PARENT_SAME，
    手册 7.7 关系口径），由 `Ablation.resolved_drop_edges()` 统一解析；按 edge_type 过滤（零重跑）。

CLI：`python scripts/dataset.py --check <base>`（单图自检：N/E/type 分布/通道形状与哈希/标签）
     `python scripts/dataset.py --check <base> --drop-ast`（额外演示消融删边后的类型分布）
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import torch

BASE = "/home/saumarez/projects/deep-learning/SSM-HG"
LABEL_FILE = f"{BASE}/alldata(readonly)/contract_labels.json"
DEFAULT_GRAPH_DIR = f"{BASE}/products/alldata/graphs"

# ---- 语料化标签层（2026-09-14；默认路径与行为逐字节不变）----
# 主库口径：图 base 形如 `<项目>__<合约>`，标签 key = 项目前缀（剥 asd_/nasd_）。
# 新语料口径：图 base 就是 `.sol` 词干，标签 key = 该词干本身（词干内可含 `__`，不可再切）。
ENV_LABEL_FILE = "SSMHG_LABEL_FILE"        # 覆盖标签文件路径
ENV_LABEL_KEY_MODE = "SSMHG_LABEL_KEY_MODE"  # 覆盖键模式：project | stem
LABEL_KEY_MODES = ("project", "stem")

# ---- 通道契约（设计稿 §2；M3 产出侧 `import dataset` 复用这几个定义，避免口径分叉）----
SCHEMA_VERSION = 2                 # `_feat.pt` schema（R8）；版本不符直接报错，不做兼容分支
CHANNEL_ORDER = ("cb_func", "cb_node", "type_id", "struct", "sv")   # 固定拼接序（锁死）
CB_DIM = 768                       # codebert-base [CLS] 维度
ROLE_NAMES = ["ENTRY", "CONDITION", "ASSIGNMENT", "EXT_CALL", "INT_CALL",
              "STATE_WRITE", "STATE_READ", "RETURN", "OTHER"]        # type_id 索引语义（锁死）
LEGACY_FEAT_DIR = "legacy_feat_pre_frontend"   # 旧格式（MLP 后 128 维）归档目录（R5/Q4）


def channel_sha256(tensor: "torch.Tensor") -> str:
    """通道级**字节级** sha256（R7）：dtype + shape + `tobytes()` 原始字节。

    用字节而非数值判据：任何浮点漂移（含跳 torch 版本）都会改变哈希，从而被本层断言抓到。
    注意：numpy() 需要连续张量；`view(torch.uint8)` 仅用于不支持 numpy 的场景。
    """
    payload = tensor.detach().cpu().contiguous()
    header = f"{payload.dtype}|{tuple(payload.shape)}|".encode("utf-8")
    return hashlib.sha256(header + payload.numpy().tobytes()).hexdigest()


def combined_sha256(channel_hashes: dict[str, str]) -> str:
    """固定通道序（`CHANNEL_ORDER`）拼接后的总体哈希，供 run 配置一行比对。"""
    payload = "|".join(f"{k}:{channel_hashes.get(k, 'absent')}" for k in CHANNEL_ORDER)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

# 关系编号固定（手册 7.7）：0=CFG_FLOW, 1=AST_PARENT, 2=AST_PARENT_SAME,
# 3=DFG_DEP, 4=CALLBACK_RISK
RELATION_NAMES = {0: "CFG_FLOW", 1: "AST_PARENT", 2: "AST_PARENT_SAME",
                  3: "DFG_DEP", 4: "CALLBACK_RISK"}
# 🔴 `RELATION_NAMES` 必须**恒为 5 项**：`audit_data_funnel.py:382` 有一条
# `assert len(dataset.RELATION_NAMES) == 5`，它审计的是**正典语料**——不能为一个消融放宽。
# 故 `CALLBACK_RISK_REV`（编号 5，仅 `--callback-rev` 变体存在）另立**显示用**扩展表，
# 只服务于 `type_dist` 的可读输出，**不参与白名单/校验/建模型**（那三处都按图产物回读）。
RELATION_NAMES_EXT = {**RELATION_NAMES, 5: "CALLBACK_RISK_REV"}
# 边级消融白名单：允许被删的物理关系编号（白名单外编号在加载时报错，不静默忽略）
# ⚠ **不扩到 5**：扩了等于给正典开一个无用的删边口子；REV 是"加一类边"的消融，
# 不是"删一类边"的消融，`--drop-edges 5` 报错是**预期行为**（见 ablation_plan §6.3 验收）。
DROPPABLE_EDGES = frozenset(RELATION_NAMES)
# `--drop-ast`：删 AST_PARENT(1) + AST_PARENT_SAME(2)（论文叙述为“去 AST 语义边”）
DROP_AST = frozenset({1, 2})


def resolve_drop_edges(drop_edges=(), drop_ast: bool = False) -> set[int]:
    """消融开关 → 物理关系编号集合（加载时白名单校验，未知编号直接报错）。

    `drop_ast=True` 等价于 `drop_edges |= {1, 2}`；不做物理合并（5 个物理关系、num_bases=5 不变，
    论文仍叙述 4 语义边 —— 见 experiments/decisions.md 关系映射表）。
    """
    edges = {int(e) for e in drop_edges}
    if drop_ast:
        edges |= DROP_AST
    unknown = edges - DROPPABLE_EDGES
    if unknown:
        raise ValueError(
            f"drop_edges 含白名单外编号 {sorted(unknown)}；"
            f"允许删除 {sorted(DROPPABLE_EDGES)}（{RELATION_NAMES}）")
    return edges


def strip_project_prefix(name: str) -> str:
    """项目名规范化：lower 并剥 asd_/nasd_ 前缀（先 nasd_ 后 asd_）。"""
    name = (name or "").lower()
    for prefix in ("nasd_", "asd_"):
        if name.startswith(prefix):
            name = name[len(prefix):]
    return name


def project_of_base(base: str) -> str:
    """图前缀 base（`<项目>__<合约>`）→ 规范化项目名（`__` 前第一段）。"""
    return strip_project_prefix(base.split("__", 1)[0])


def is_buggy_project(proj: str) -> bool:
    """是否 buggy_* 噪声项目（标签为每合约同款注入噪声，主实验剔除，见手册 10.2.6）。"""
    return proj.startswith("buggy_")


def resolve_label_file(explicit: Path | str | None = None) -> Path:
    """标签文件解析：显式参数 > 环境变量 `SSMHG_LABEL_FILE` > 主库 `LABEL_FILE`（默认不变）。"""
    if explicit is not None:
        return Path(explicit)
    env = os.environ.get(ENV_LABEL_FILE)
    return Path(env) if env else Path(LABEL_FILE)


def resolve_label_key_mode(explicit: str | None = None) -> str:
    """键模式解析：显式参数 > 环境变量 `SSMHG_LABEL_KEY_MODE` > `"project"`（默认不变）。"""
    mode = explicit if explicit is not None else os.environ.get(ENV_LABEL_KEY_MODE, "project")
    if mode not in LABEL_KEY_MODES:
        raise ValueError(f"未知 label key mode {mode!r}；允许 {LABEL_KEY_MODES}")
    return mode


def stem_key_of(contract_name: str) -> str:
    """标签 `contract_name` → **源文件的 `.sol` 词干**（= 图 base = 标签键）。

    `stem` 键模式的**唯一职责**就是"从标签名还原出源文件名"。两个语料的标签命名不同，
    但都归结到同一件事：**取首个 `-` 之前，再剥掉 `.sol` 后缀**。

    | 语料 | 源文件 | 标签 `contract_name` | 取 `-` 前 | 再剥 `.sol` |
    | --- | --- | --- | --- | --- |
    | ② 增强集 | `0x000c…f53.sol` | `0x000c…f53-C10Token.sol` | `0x000c…f53` | `0x000c…f53` ✓ |
    | DIVE | `8263.sol` | `8263.sol` | `8263.sol` | `8263` ✓ |

    🔴 **2026-09-19 修**：原实现只做 `split("-", 1)[0]`，对 ② 恰好正确（9026/9026 的标签名
    都带 `-`），但对 DIVE **全错**——`8263.sol` 无 `-` ⇒ 键算成 `"8263.sol"`，与图 base
    `8263` 一个都匹配不上（实测 890 张图 **0 命中**）。手册 §10.2 第 9 条早就写明
    「DIVE `contract_name` 形如 `8263.sol`」且 stem 模式取的就是 `.sol` 词干——
    即**原实现没有兑现它自己的文档**。补上剥后缀这一步即可，两语料自此同一条规则。
    已实测该改动对 ② 的 9026 条**逐条键不变**（0 条不同），故 ② 全部既有结果零影响。

    与 `project` 模式的两点差别（都是刻意的）：**不做 lower**、**不剥 asd_/nasd_ 前缀**——
    两侧来自同一批文件名，精确匹配即可；若出现大小写漂移，应当在 `unmatched` 里显式暴露，
    而不是被规范化悄悄掩盖。
    """
    head = str(contract_name).split("-", 1)[0]
    return Path(head).stem if head.endswith(".sol") else head


def build_proj_labels(label_file: Path | str | None = None,
                      key_mode: str | None = None) -> dict[str, list[list[int]]]:
    """读标签文件 → {键: [targets, ...]}（同键多条目保留，供取并集）。

    `project` 模式（默认，主库）：标签 `contract_name` 的 `-` 前部分是项目名
    （`send_loop-Refunder.sol` → `send_loop`），后部分是合约名而非文件名，
    不能与 meta.source 直接比对（手册 10.2.2）；无 `-` 的条目整体跳过。
    `stem` 模式（跨语料）：键 = `.sol` 词干（见 `stem_key_of`），不要求 `-`。
    """
    mode = resolve_label_key_mode(key_mode)
    with open(resolve_label_file(label_file), "r", encoding="utf-8") as handle:
        entries = json.load(handle)
    labels: dict[str, list[list[int]]] = defaultdict(list)
    for entry in entries:
        contract_name = entry.get("contract_name") or ""
        if mode == "stem":
            key = stem_key_of(contract_name)
        else:
            if "-" not in contract_name:
                continue
            key = strip_project_prefix(contract_name.split("-", 1)[0])
        labels[key].append([int(v) for v in entry.get("targets", [])])
    return dict(labels)


def build_index(graph_dir: Path | str = DEFAULT_GRAPH_DIR,
                label_file: Path | str | None = None,
                key_mode: str | None = None) -> tuple[dict[str, list[int]], list[str]]:
    """扫 `*_pyg.pt` → {base: 7 维标签（同键多合约 targets 并集）}。

    `key_mode="project"`（默认，主库）：标签键 = 图 base 的项目前缀；
    `key_mode="stem"`（跨语料）：标签键 = 图 base 本身。
    未知键模式报错而非回退默认（静默回退会把两份语料的标签对错）。

    返回 (index, unmatched)：未匹配到标签的 base 收集返回（供 make_splits 写
    unmatched_contracts.txt 透明性报告，不静默丢弃）。
    """
    mode = resolve_label_key_mode(key_mode)
    proj_labels = build_proj_labels(label_file=label_file, key_mode=mode)
    index: dict[str, list[int]] = {}
    unmatched: list[str] = []
    for path in sorted(Path(graph_dir).glob("*_pyg.pt")):
        base = path.name.replace("_pyg.pt", "")
        targets_list = proj_labels.get(base if mode == "stem" else project_of_base(base))
        if not targets_list:
            unmatched.append(base)
            continue
        label = [0] * 7
        for targets in targets_list:
            for i, value in enumerate(targets[:7]):
                if value:
                    label[i] = 1
        index[base] = label
    return index, unmatched


@dataclass
class Ablation:
    """**边级**消融配置（手册 12.3）。

    drop_edges：要删的**物理**关系编号（加载时按 `DROPPABLE_EDGES` 校验白名单）；
    drop_ast=True：等价于 drop_edges |= {1, 2}（`--drop-ast`，删 AST_PARENT + AST_PARENT_SAME）。
    ★ **特征级**消融已前移到模型侧（`model.AblationConfig`，通道级、零重跑），本类不再持有。
    """
    drop_edges: set[int] = field(default_factory=set)
    drop_ast: bool = False

    def resolved_drop_edges(self) -> set[int]:
        """展开消融开关并做白名单校验 → 实际要过滤的 edge_type 集合。"""
        return resolve_drop_edges(self.drop_edges, self.drop_ast)


@dataclass
class GraphSample:
    """单图训练输入：通道字典（固定序 `CHANNEL_ORDER`）+ 边 + 标签 + 元数据。"""
    channels: dict[str, torch.Tensor]
    edge_index: torch.Tensor
    edge_type: torch.Tensor
    label: torch.Tensor
    name: str
    node_id: list
    meta: dict[str, Any]


def _cb_rows(payload: dict[str, Any], cb: dict[str, Any]) -> tuple[torch.Tensor, torch.Tensor, int]:
    """按节点行序对齐 `_cb.pt` → (cb_func, cb_node, missing)（缺行用零向量并计数上报）。"""
    zeros = torch.zeros(CB_DIM)
    missing = 0
    func_rows: list[torch.Tensor] = []
    node_rows: list[torch.Tensor] = []
    for contract, function in zip(payload["contract"], payload["function"]):
        vec = cb["func"].get(f"{contract}::{function}")
        if vec is None:
            missing += 1
            vec = zeros
        func_rows.append(vec)
    for node_id in payload["node_id"]:
        vec = cb["node"].get(str(node_id))
        if vec is None:
            missing += 1
            vec = zeros
        node_rows.append(vec)
    return torch.stack(func_rows), torch.stack(node_rows), missing


def channel_hash_mismatches(feat: dict[str, Any], channels: dict[str, torch.Tensor],
                            which: str = "cheap") -> list[str]:
    """逐通道哈希校验（R7）：返回不匹配的**具体通道名**（空 = 全部一致）。

    which="cheap" 只校验 struct/type_id/sv（默认，每次加载都做）；"all" 额外校验
    cb_func/cb_node（≈0.6 GB/全库，仅 CLI `--verify-channel-hash` 时用）。
    """
    meta = feat.get("meta", {})
    recorded = {**meta.get("channel_sha256", {}), **meta.get("cb_sha256", {})}
    names = ["struct", "type_id", "sv"] + (["cb_func", "cb_node"] if which == "all" else [])
    bad: list[str] = []
    for name in names:
        expect = recorded.get(name)
        actual = channel_sha256(channels[name])
        if expect != actual:
            bad.append(f"{name} (expected {expect}, got {actual})")
    return bad


def load_graph(base: str, graph_dir: str = DEFAULT_GRAPH_DIR,
               ab: Ablation | None = None,
               index: dict[str, list[int]] | None = None,
               verify_channels: str = "cheap") -> GraphSample:
    """加载单图训练输入：_pyg.pt（结构）+ 通道字典（`_feat.pt` + `_cb.pt`）+ 标签 + 边级消融。

    断言逐条对应设计稿 §4，失败信息带具体通道/形状，便于定位到单一契约。
    """
    ab = ab or Ablation()
    drop_edges = ab.resolved_drop_edges()          # 边级白名单校验（越界编号直接报错）
    if index is not None:
        assert base in index, f"{base}: label missing (第一道一致性防线：split 内缺标签直接报错)"

    payload = torch.load(f"{graph_dir}/{base}_pyg.pt", map_location="cpu")
    n = len(payload["node_id"])

    # ---- ① `_feat.pt` 通道字典（schema v2；旧格式直接报错并指向归档目录）----
    feat = torch.load(f"{graph_dir}/{base}_feat.pt", map_location="cpu")
    assert isinstance(feat, dict), (
        f"{base}: _feat.pt 是旧格式（融合后张量）；已归档至 {LEGACY_FEAT_DIR}/，"
        f"请重跑 `python scripts/m3_build_features.py`")
    assert int(feat.get("schema_version", -1)) == SCHEMA_VERSION, (
        f"{base}: _feat.pt schema={feat.get('schema_version')} != {SCHEMA_VERSION}（不兼容，不静默降级）")
    for key in ("struct", "type_id", "sv", "meta"):
        assert key in feat, f"{base}: _feat.pt 缺通道/元数据 '{key}'"
    meta = feat["meta"]
    struct, type_id, sv = feat["struct"], feat["type_id"], feat["sv"]
    assert struct.dim() == 2 and struct.shape[0] == n, \
        f"{base}: struct shape {tuple(struct.shape)} 与 N={n} 不符"
    assert int(meta["D_struct"]) == int(struct.shape[1]), \
        f"{base}: D_struct={meta['D_struct']} 与 struct 列数 {struct.shape[1]} 不符"
    assert type_id.dtype == torch.int64 and tuple(type_id.shape) == (n,), \
        f"{base}: type_id 必须 (N,) int64，got {tuple(type_id.shape)}/{type_id.dtype}"
    assert list(meta.get("role_names", [])) == ROLE_NAMES, \
        f"{base}: role_names 与契约不一致（type_id 语义漂移）"
    assert int(type_id.min()) >= 0 and int(type_id.max()) < len(ROLE_NAMES), \
        f"{base}: type_id 越界 [0,{len(ROLE_NAMES)})"
    assert tuple(sv.shape) == (n, 1), f"{base}: sv 必须 (N,1)，got {tuple(sv.shape)}"
    sv_min, sv_max = float(sv.min()), float(sv.max())
    assert 0.0 <= sv_min and sv_max <= 1.0, \
        f"{base}: sv 越界 [{sv_min}, {sv_max}]（归一化应在 M1 完成，模型侧不做统计，R9）"

    # ---- ② `_cb.pt` 行对齐（缺行零向量 + 计数上报）----
    cb = torch.load(f"{graph_dir}/{base}_cb.pt", map_location="cpu")
    cb_func, cb_node, missing = _cb_rows(payload, cb)
    assert tuple(cb_func.shape) == (n, CB_DIM) and tuple(cb_node.shape) == (n, CB_DIM), \
        f"{base}: cb 通道形状异常 {tuple(cb_func.shape)}/{tuple(cb_node.shape)}"

    channels = {"cb_func": cb_func, "cb_node": cb_node,
                "type_id": type_id, "struct": struct, "sv": sv}
    assert tuple(channels) == CHANNEL_ORDER, f"{base}: 通道序必须为 {CHANNEL_ORDER}"

    # ---- ③ 逐通道哈希（默认只校验三个便宜通道；cb 两通道需 "all"）----
    if verify_channels != "none":
        bad = channel_hash_mismatches(feat, channels, which=verify_channels)
        assert not bad, f"{base}: 通道哈希不匹配 → {bad}"

    edge_index, edge_type = payload["edge_index"], payload["edge_type"]
    if drop_edges:
        drop = torch.tensor(sorted(drop_edges), dtype=torch.long)
        keep = ~torch.isin(edge_type, drop)
        edge_index, edge_type = edge_index[:, keep], edge_type[keep]

    label = torch.tensor(index[base] if index is not None else [0] * 7,
                         dtype=torch.float32)
    sample_meta = dict(meta)
    # 关系数由图产物自带（`convert_hetero_json_to_pyg.py` 按**实际出现的边键**写入）。
    # 正典 `_pyg.pt` 早于该字段 → `.get` 兜底 5，两条路径都对。
    sample_meta.update({"n_nodes": n, "cb_missing_rows": missing,
                        "n_edges": int(edge_index.shape[1]),
                        "num_relations": int(payload.get("num_relations", 5))})
    return GraphSample(channels=channels, edge_index=edge_index, edge_type=edge_type,
                       label=label, name=base, node_id=payload["node_id"], meta=sample_meta)


def stack_labels(samples, head: str = "multi"):
    """`list[GraphSample]` → 标签张量：`multi` 为 `[B,7]`，`binary` 为 `[B,1]` 的 `any(targets)`。

    **7→1 的塌缩只在这里发生**（`collate` 与 `train.class_stats` 共用本函数）。
    `build_index` / 标签文件 / 划分 / 通道哈希全部保持 7 维不动——这是「二分类臂只换输出头」
    能成立的前提：不碰任何已入库的中间产物（decisions §31）。
    """
    labels = torch.stack([s.label for s in samples])
    if head == "binary":
        labels = labels.any(dim=1, keepdim=True).to(labels.dtype)
    return labels


def collate(samples, drop_edge_prob: float = 0.0, generator: "torch.Generator | None" = None,
            training: bool = True, device: "str | torch.device | None" = None,
            head: str = "multi"):
    """list[GraphSample] → (channels, edge_index, edge_type, batch, labels)。

    自实现批图（**不引入 PyG DataLoader**；decisions §16.2）：
    - DropEdge（training 且 prob>0）：先对每个单图生成 keep mask 再过滤（等价 `model.apply_edge_mask`，
      本层内联以避免 dataset→model 依赖），**绝不跨图**；
    - 通道沿节点维 cat；`edge_index` 加节点偏移、`edge_type` cat；`batch`=[ΣN]（PyG 语义）；
      `labels`=stack [B,7]。train/evaluate 共用。
    - `device`（可选）：非 None 时把全部张量 `.to(device)` 后返回（GPU 训练/推理用；默认 None=留在
      CPU，保持纯函数语义与既有单测不变）。
    - `head`（`--head binary` 臂，decisions §31）：`"binary"` 时把 `[B,7]` 标签塌成 `[B,1]` 的
      `any(targets)`。**塌缩只发生在这里**——`build_index` / 标签文件 / 划分 / 通道哈希全部保持
      7 维不动，这是「二分类臂只换输出头」能成立的前提。
    """
    b = len(samples)
    labels = stack_labels(samples, head=head)                            # [B,7] 或 [B,1]
    channel_parts = {k: [] for k in CHANNEL_ORDER}
    edge_parts, type_parts, node_counts = [], [], []
    offset = 0
    for s in samples:
        ei, et = s.edge_index, s.edge_type
        if training and drop_edge_prob > 0.0:
            keep = torch.rand(int(ei.shape[1]), generator=generator) > drop_edge_prob
            idx = keep.nonzero(as_tuple=False).squeeze(1)
            ei, et = ei[:, idx], et[idx]
        n = int(s.channels["sv"].shape[0])
        edge_parts.append(ei + offset)
        type_parts.append(et)
        node_counts.append(n)
        for k in CHANNEL_ORDER:
            channel_parts[k].append(s.channels[k])
        offset += n
    channels = {k: torch.cat(channel_parts[k], dim=0) for k in CHANNEL_ORDER}
    edge_index = torch.cat(edge_parts, dim=1) if edge_parts else torch.empty((2, 0), dtype=torch.long)
    edge_type = torch.cat(type_parts, dim=0) if type_parts else torch.empty(0, dtype=torch.long)
    batch = torch.repeat_interleave(torch.arange(b),
                                    torch.tensor(node_counts, dtype=torch.long))
    if device is not None:
        channels = {k: v.to(device) for k, v in channels.items()}
        edge_index = edge_index.to(device)
        edge_type = edge_type.to(device)
        batch = batch.to(device)
        labels = labels.to(device)
    return channels, edge_index, edge_type, batch, labels


def parse_args() -> argparse.Namespace:
    """CLI：--check <base> 单图自检；--drop-ast / --drop-edges 演示边级消融；--verify-channel-hash。"""
    parser = argparse.ArgumentParser(description="M5 dataset layer (channel composition + checks).")
    parser.add_argument("--check", default=None,
                        help="Base prefix of a single graph to inspect (e.g. nasd_simple_dao__simple_dao).")
    parser.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR,
                        help="Directory containing *_pyg.pt / *_feat.pt / *_cb.pt.")
    parser.add_argument("--drop-ast", action="store_true",
                        help="边级消融：删 relation 1+2（AST_PARENT + AST_PARENT_SAME）。")
    parser.add_argument("--drop-edges", default="",
                        help="边级消融：逗号分隔的物理关系编号（白名单外编号报错），如 0,3 。")
    parser.add_argument("--verify-channel-hash", action="store_true",
                        help="额外校验 cb_func/cb_node 两通道哈希（默认只校验 struct/type_id/sv）。")
    return parser.parse_args()


def main() -> None:
    """单图自检：`python scripts/dataset.py --check <base> [--drop-ast|--drop-edges 0,3] [--verify-channel-hash]`。"""
    args = parse_args()
    if not args.check:
        print("usage: python scripts/dataset.py --check <base> [--drop-ast|--drop-edges 0,3]")
        return
    explicit = {int(t) for t in args.drop_edges.split(",") if t.strip()}
    ab = Ablation(drop_edges=explicit, drop_ast=args.drop_ast)
    drop_edges = ab.resolved_drop_edges()
    index, _ = build_index(args.graph_dir)
    sample = load_graph(args.check, graph_dir=args.graph_dir, ab=ab, index=index,
                        verify_channels="all" if args.verify_channel_hash else "cheap")
    type_dist: dict[int, int] = {}
    for t in sample.edge_type.tolist():
        type_dist[t] = type_dist.get(t, 0) + 1
    if drop_edges:
        print(f"ablation  : drop_edges={sorted(drop_edges)} "
              f"({[RELATION_NAMES[e] for e in sorted(drop_edges)]})，"
              f"drop_ast={args.drop_ast}")
    print(f"name      : {sample.name}")
    print(f"nodes     : {sample.meta['n_nodes']}  edges : {sample.meta['n_edges']}")
    print("channels  : " + ", ".join(f"{k}={tuple(v.shape)}" for k, v in sample.channels.items()))
    print(f"cb missing: {sample.meta['cb_missing_rows']}  "
          f"combined sha: {str(sample.meta.get('combined_sha256'))[:16]}…")
    print(f"edge_types: { {RELATION_NAMES_EXT.get(k, k): v for k, v in sorted(type_dist.items())} }")
    print(f"label     : {sample.label.tolist()}")


if __name__ == "__main__":
    main()
