#!/usr/bin/env python3
"""EGFL 基线（5.3）**离线特征**：字节码 → 反汇编 → 基本块 CFG → opcode 序列 + 图向量。

**为什么走字节码**：EGFL 论文标题即「字节码级别」，其输入是 EVM opcode 序列
（`cfg_bfs_act`）+ 一个 CFG 衍生的定长向量。硬套源码异构图会让它名不副实
（用户 2026-09-22 裁定：走原生字节码模态）。

🔴 **必须随结果披露的重建声明**：它图分支吃的是一个**作者未开源的 256 维 `cfg_graph` 向量**
（`Weights_CFG_SimOp/` 是 0 字节目录，全仓库无任何脚本产出它；`main_run.py:49` 只是把它读进来）。
本脚本按论文描述重建：**块内 opcode 词向量取平均 → BFS 展平 → 定长 256 维**。
论文只写了「BFS 展平成 linear node feature matrix」，256 维怎么切**不可考** ⇒
提供 `(node_dim, k)` 三种切法做敏感性，默认 `(128, 2)`。

两段流水线（`manifest.json` 是唯一完成判据）：
  `seq`   solc --bin → 反汇编 → 基本块/CFG/BFS → `seq/<base>.pkl`（tokens + 块结构）
  `feat`  在 **train 划分**的 token 上训 word2vec → 块向量 → BFS 展平 256 维 → `feat/<base>.pt`

用法（仓库根目录）：
    python scripts/baseline_egfl_build.py --limit 5                 # 冒烟
    python scripts/baseline_egfl_build.py --report-seq-len          # 先看序列长度分布
    python scripts/baseline_egfl_build.py                           # 全量 453
"""

from __future__ import annotations

import argparse
import ast as pyast
import json
import os
import pickle
import re
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402

NAME = "egfl"
MANDO_OPCODES = Path("/home/saumarez/projects/deep-learning/MANDO-LLM/sco_models/opcodes.py")
SOLC_ARTIFACTS = Path.home() / ".solc-select" / "artifacts"

PUSH1, PUSH32 = 0x60, 0x7F
# EVM 终止/跳转指令（十六进制）
TERMINALS = {0x00, 0x56, 0x57, 0xF3, 0xFD, 0xFE, 0xFF}     # STOP JUMP JUMPI RETURN REVERT INVALID SELFDESTRUCT
UNCOND_TERMINALS = {0x00, 0x56, 0xF3, 0xFD, 0xFE, 0xFF}    # 除 JUMPI 外：都不 fall-through
JUMPDEST = 0x5B


# --------------------------------------------------------------------------- opcode 表
def opcode_table(dst: Path) -> dict:
    """从 MANDO-LLM 的 `sco_models/opcodes.py` 抽出 `int2op`（144 条），缓存成 json。

    ⚠ **不 import 它的模块**：`sco_models/__init__.py` 会拖进 dgl，而 base 里没有 dgl。
    改为把那一份源码在空命名空间里求值（理由见下）。
    """
    if dst.exists():
        return json.loads(dst.read_text(encoding="utf-8"))
    if not MANDO_OPCODES.exists():
        raise SystemExit(f"[egfl] 找不到 opcode 表：{MANDO_OPCODES}")
    # ⚠ 不能用 ast.literal_eval：那份 dict 用了解包推导式
    # （`**{f"{i:02x}": f"PUSH{i-0x5f}" for i in range(0x60,0x80)}` 生成 PUSH/DUP/SWAP/LOG）
    # ⇒ 只在**空命名空间**里 exec 整份源码。该文件无任何 import，是纯字面量，
    #    所以这既不引入依赖、也不执行外部代码。
    src = MANDO_OPCODES.read_text(encoding="utf-8")
    if "import" in src.split("int2op")[0]:
        raise SystemExit("[egfl] opcodes.py 头部出现了 import —— 拒绝 exec（改用别的方式取表）")
    ns: dict = {}
    exec(compile(src, str(MANDO_OPCODES), "exec"), ns)          # noqa: S102
    table = ns.get("int2op")
    if not table:
        raise SystemExit("[egfl] 在 opcodes.py 里找不到 int2op")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(table, ensure_ascii=False, indent=0), encoding="utf-8")
    return table


def _hex_table() -> dict:
    return json.loads((B.feature_root(NAME) / "opcodes.json").read_text(encoding="utf-8"))


# --------------------------------------------------------------------------- 编译
def _solc_versions() -> list[str]:
    return sorted((p.name.replace("solc-", "") for p in SOLC_ARTIFACTS.glob("solc-*")),
                  key=lambda v: tuple(int(x) for x in v.split(".")))


def solc_bytecode(src_sol: Path, *, timeout: int = 180) -> tuple[dict, str]:
    """`solc --combined-json bin,bin-runtime` → ({contract: {bin, bin-runtime}}, solc 版本)。

    用 **creation bytecode**（不是 runtime）：EGFL 的样例序列以
    `PUSH1 0x80 PUSH1 0x40 MSTORE CALLVALUE ...` 开头，那是构造期代码的自拷贝序言。
    """
    import baseline_common as B
    cand = B.solc_candidates(src_sol)        # 满足 pragma（高→低）→ 最高 0.8.x → 其余全部（低→高）
    if not cand:
        raise RuntimeError(f"没有可用的已装 solc（{SOLC_ARTIFACTS}）")
    last = ""
    for ver in cand:                         # 🔴 不设上限（理由同 baseline_common.solc_candidates）
        r = subprocess.run(["solc", str(src_sol), "--combined-json", "bin,bin-runtime"],
                           capture_output=True, text=True, timeout=timeout,
                           env={**os.environ, "SOLC_VERSION": ver})
        if r.returncode != 0 or not r.stdout.strip():
            last = (r.stderr or r.stdout).strip().splitlines()[:1]
            continue
        try:
            payload = json.loads(r.stdout)
        except json.JSONDecodeError as e:
            last = f"输出不是合法 JSON：{e}"
            continue
        contracts = {k.split(":")[-1]: v for k, v in payload.get("contracts", {}).items()}
        return contracts, ver
    raise RuntimeError(f"编译失败（试过 {len(cand)} 个候选 {cand}）：{last}")


# solc 的「未链接库」占位符**有两种写法**（必须都认，实测栽在第②种）：
#   ① solc ≥0.5：`__$<34位hex>$__`
#   ② solc 0.4.x：`__<fully/qualified/File.sol:ContractName>__`，中间不足 36 字符用 `_` 右填
# 两者长度都恰好 **40 字符** = 20 字节（一个地址），但 ② 的内含 `/` `.` `:` `_` 与字母，
# 按 ① 的正则去匹配会**一个都匹配不到**，于是照样 `fromhex` 崩。
# 故改为「**任何非 hex 的连续片段一律按原长替 0**」——不依赖任何一种具体写法。
PLACEHOLDER_LEN = 40
# 骨架一律是 `__` + 36 字符 + `__`（共 40 = 一个 20 字节地址），中间两种写法：
#   ① solc ≥0.5 → `$<34位hex>$`   ② solc 0.4.x → 限定名右填 `_` 到 36 字符
# ⚠ **不能按「非 hex 字符」去找**：0.4 的限定名里含 `/home/saumarez/...`，其中
#   `e`/`a`/`d`/`c`/`b`/`f` 本身就是 hex 字符，会把占位符切碎、数不准（实测踩到）。
#   锚在 `__` 上则绝不会误伤——纯 hex 字节码里不可能出现连续两个下划线。
_PLACEHOLDER_RE = re.compile(
    r"__(?:\$[0-9a-fA-F]{34}\$|[A-Za-z0-9_$./:\-]{36})__")
_NON_HEX_RE = re.compile(r"[^0-9a-fA-F]")


def sanitize_bin(b: str) -> tuple[str, int]:
    """solc 的 `bin` → 纯 hex。返回 `(hex, 被替换的占位符个数)`。

    🔴 **必须处理未链接库的占位符**：合约引用未部署的库时，solc 在字节码里留 40 字符的占位符
    （两种写法见上面的 `_NON_HEX_RE` 注释）。它不是合法 hex，直接 `bytes.fromhex()` 会
    `ValueError: non-hexadecimal number found` —— 实测这让 **8/453** 个合约被误记成
    「编译失败」，其中 1 个还在 seed1 的 test 里（会让那一行的分母与其它行不同）。

    替成**等长的 `0`** 而不是删掉：保持**字节偏移不变**（CFG 的 jump 目标按 offset 算）。
    """
    b = (b or "").strip()
    if b.startswith("0x"):
        b = b[2:]
    if not _NON_HEX_RE.search(b):
        return b, 0
    b, n = _PLACEHOLDER_RE.subn("0" * PLACEHOLDER_LEN, b)
    # 兜底：仍残留非 hex（形态不在已知两种之内）→ 逐字符替 0，**保持偏移不变**，且不静默
    left = _NON_HEX_RE.findall(b)
    if left:
        print(f"[egfl] ⚠ 出现未知形态的占位符残留 {len(left)} 个字符（按 0 处理）", flush=True)
        b = _NON_HEX_RE.sub("0", b)
    return b, n


def pick_bytecode(contracts: dict, mode: str = "concat") -> tuple[str, int, int]:
    """多合约 → 一条字节码流。返回 `(hex, 参与拼接的合约数, 占位符替换数)`。

    `concat` 按 solc 返回顺序拼接所有**非空** creation bin（空 bin 出现在 interface /
    抽象合约上，常见且不是错误）；`largest` 只取最长的那一个。
    一个 `.sol` 一个样本，故多合约必须合成一条流（与 MVD-HG 的「一文件一样本」口径一致）。
    """
    bins = [(name, c.get("bin") or "") for name, c in contracts.items()]
    bins = [(n, b) for n, b in bins if b]
    if not bins:
        return "", 0, 0
    if mode == "largest":
        n, b = max(bins, key=lambda kv: len(kv[1]))
        bins = [(n, b)]
    parts, n_ph = [], 0
    for _, b in bins:
        h, k = sanitize_bin(b)
        parts.append(h)
        n_ph += k
    return "".join(parts), len(bins), n_ph


# --------------------------------------------------------------------------- 反汇编
def disassemble(code_hex: str, int2op: dict) -> list[tuple[int, str, int | None]]:
    """线性反汇编 → `[(offset, opname, immediate)]`。

    PUSH1..PUSH32 吃掉 n 个立即数字节（不足时截断，与 EVM 的隐式补零不同——
    这时把该指令记为 `INVALID` 并终止，避免把数据当代码继续解出垃圾）。
    未定义字节记 `INVALID`（与 EVM 语义一致）。
    """
    code = bytes.fromhex(code_hex)
    out: list[tuple[int, str, int | None]] = []
    i = 0
    while i < len(code):
        op = code[i]
        name = int2op.get(f"{op:02x}", "INVALID")
        if PUSH1 <= op <= PUSH32:
            n = op - PUSH1 + 1
            if i + 1 + n > len(code):
                out.append((i, "INVALID", None))
                break
            imm = int.from_bytes(code[i + 1:i + 1 + n], "big")
            out.append((i, name, imm))
            i += 1 + n
        else:
            out.append((i, name, None))
            i += 1
    return out


def basic_blocks(insns: list[tuple[int, str, int | None]]):
    """切基本块 + 建 CFG。返回 (blocks, edges, bbinfo)。

    切点：offset 0；任何 `JUMPDEST`；任何终止指令的**下一条**。
    边：
      - fall-through（非无条件终止 → 下一块）；
      - `JUMPI` → fall-through + 动态分支边（`unresolved`，目标运行时才知道）；
      - `JUMP` → 做一次**单步常量传播**：紧邻前一条是 `PUSHn <dest>` 且 dest 落在某个
        JUMPDEST 上 → 精确边；否则记 `unresolved`。
    """
    if not insns:
        return [], [], {"n_blocks": 0, "n_edges": 0, "unresolved": 0, "entry_offset": None}

    offsets = [o for o, _, _ in insns]
    idx_of = {o: i for i, o in enumerate(offsets)}
    is_jumpdest = {o for o, n, _ in insns if n == "JUMPDEST"}
    starts = {offsets[0]} | is_jumpdest
    for k, (o, n, _) in enumerate(insns[:-1]):
        if _opcode_of(n) in TERMINALS:
            starts.add(insns[k + 1][0])
    starts = sorted(starts)

    blocks, cur = [], []
    start_set = set(starts)
    for ins in insns:
        if ins[0] in start_set and cur:
            blocks.append(cur)
            cur = []
        cur.append(ins)
    if cur:
        blocks.append(cur)
    off2blk = {b[0][0]: bi for bi, b in enumerate(blocks)}

    edges: list[tuple[int, int]] = []
    unresolved = 0
    for bi, blk in enumerate(blocks):
        last_off, last_name, _ = blk[-1]
        op = _opcode_of(last_name)
        nxt = None
        if bi + 1 < len(blocks):
            nxt = bi + 1
        if op not in UNCOND_TERMINALS and nxt is not None:
            edges.append((bi, nxt))                       # fall-through
        if op == 0x57:                                    # JUMPI
            unresolved += 1                               # 动态目标
        elif op == 0x56:                                  # JUMP
            target = None
            for j in range(len(insns) - 1, -1, -1):       # 找本块内紧邻前一条 PUSHn
                if insns[j][0] == last_off:
                    if j > 0 and insns[j - 1][2] is not None:
                        target = insns[j - 1][2]
                    break
            if target is not None and target in off2blk:
                edges.append((bi, off2blk[target]))
            else:
                unresolved += 1
    bbinfo = {"n_blocks": len(blocks), "n_edges": len(edges), "unresolved": unresolved,
              "entry_offset": offsets[0]}
    return blocks, edges, bbinfo


_OPNAME2HEX: dict[str, int] = {}


def _opcode_of(name: str) -> int:
    if not _OPNAME2HEX:
        for k, v in _hex_table().items():
            _OPNAME2HEX.setdefault(v, int(k, 16))
    return _OPNAME2HEX.get(name, -1)


def bfs_block_order(blocks, edges, entry: int = 0) -> list[int]:
    """从入口块 BFS 的块序（重访不重复入队）。原实现的序列字段就叫 `cfg_bfs_act`。"""
    adj: dict[int, list[int]] = {}
    for a, b in edges:
        adj.setdefault(a, []).append(b)
    order, seen, queue = [], {entry}, [entry]
    while queue:
        cur = queue.pop(0)
        if cur >= len(blocks):
            continue
        order.append(cur)
        for nb in adj.get(cur, []):
            if nb not in seen:
                seen.add(nb)
                queue.append(nb)
    for bi in range(len(blocks)):                          # 不可达块补在后面（不丢数据）
        if bi not in seen:
            order.append(bi)
    return order


def opcode_tokens(insns, keep_immediates: bool = True) -> list[str]:
    """opcode 序列。`keep_immediates=True` 时立即数单独成 token（EGFL 的 `cfg_bfs_act` 即如此）。"""
    if not keep_immediates:
        return [n for _, n, _ in insns]
    out = []
    for _, n, imm in insns:
        out.append(n)
        if imm is not None:
            out.append(hex(imm))
    return out


# --------------------------------------------------------------------------- 词向量与图向量
def block_vectors(blocks, w2v, node_dim: int):
    """每块 = 块内 token 的 word2vec 平均（论文：「节点内 opcode 用 word2vec 取平均」）。"""
    import numpy as np
    vecs = np.zeros((len(blocks), node_dim), dtype=np.float32)
    for bi, blk in enumerate(blocks):
        acc, n = np.zeros(node_dim, dtype=np.float32), 0
        for _, name, imm in blk:
            for tok in ([name, hex(imm)] if imm is not None else [name]):
                if tok in w2v:
                    acc += w2v[tok]
                    n += 1
        if n:
            vecs[bi] = acc / n
    return vecs


def flatten_bfs(vecs, order: list[int], *, k: int, out_dim: int):
    """BFS 前 k 块向量 concat → 定长 `out_dim`（不足补零，超出截断）。

    🔴 **这是重建件**：原 `cfg_graph` 是作者未开源的预处理产物，256 维怎么切不可考。
    默认 `(node_dim=128, k=2)` 恰得 256；另做 `(256,1)` / `(64,4)` 敏感性。
    """
    import numpy as np
    parts = [vecs[b] for b in order[:k] if b < len(vecs)]
    flat = np.concatenate(parts) if parts else np.zeros(0, dtype=np.float32)
    out = np.zeros(out_dim, dtype=np.float32)
    m = min(out_dim, flat.shape[0])
    out[:m] = flat[:m]
    return out


# --------------------------------------------------------------------------- manifest
def load_manifest(root: Path) -> dict:
    man = {}
    p = root / "manifest.json"
    if p.exists():
        man = json.loads(p.read_text(encoding="utf-8"))
    jl = root / "manifest.jsonl"
    if jl.exists():
        for line in jl.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rec = json.loads(line)
                man[rec.pop("base")] = rec
    return man


def append_manifest(root: Path, base: str, rec: dict) -> None:
    with open(root / "manifest.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"base": base, **rec}, ensure_ascii=False) + "\n")


# --------------------------------------------------------------------------- 主流程
def parse_args():
    p = argparse.ArgumentParser(description="EGFL 基线离线特征（字节码 → opcode + CFG）。")
    p.add_argument("--graph-dir", default=str(REPO / "products/alldata/graphs_ft/ss0"))
    p.add_argument("--split-dir", default=str(REPO / "products/alldata/splits"))
    p.add_argument("--split-seed", type=int, default=None)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--label-file", default=None)
    p.add_argument("--label-key-mode", choices=["project", "stem"], default=None)
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--force", action="store_true")
    p.add_argument("--node-dim", type=int, default=128, help="每块的词向量维度。")
    p.add_argument("--bfs-k", type=int, default=2, help="BFS 取前 k 个块向量（node_dim*k 应 = 256）。")
    p.add_argument("--bytecode-mode", choices=["concat", "largest"], default="concat")
    p.add_argument("--report-seq-len", action="store_true",
                   help="只统计 opcode 序列长度分位数（定 --seq-len 用），不写产物。")
    return p.parse_args()


def _seq_of(contracts, mode, int2op):
    code_hex, n_contracts, n_placeholder = pick_bytecode(contracts, mode)
    if not code_hex:
        return None
    insns = disassemble(code_hex, int2op)
    blocks, edges, bbinfo = basic_blocks(insns)
    order = bfs_block_order(blocks, edges, 0)
    tokens = opcode_tokens(insns, keep_immediates=True)
    return {"tokens": tokens, "blocks": [[(o, n, im) for o, n, im in b] for b in blocks],
            "bfs_order": order, "bbinfo": bbinfo,
            "n_contracts": n_contracts, "code_bytes": len(code_hex) // 2,
            "n_placeholder": n_placeholder}


def main() -> int:
    args = parse_args()
    split_seed = B.resolve_split_seed(args)
    root = B.feature_root(NAME)
    (root / "seq").mkdir(exist_ok=True)
    (root / "feat").mkdir(exist_ok=True)
    opcode_table(root / "opcodes.json")
    int2op = _hex_table()

    split = B.load_split(args.split_dir, split_seed)
    index, _ = B.load_index(args.graph_dir, args.label_file, args.label_key_mode)
    pool = [b for b in split["train"] + split["val"] + split["test"] if b in index]
    if args.limit:
        pool = pool[:args.limit]
    print(f"[egfl] 池 {len(pool)} 个 base（split_seed={split_seed}）", flush=True)

    from make_splits import source_path_of

    # ---- 阶段 1：编译 + 反汇编 + 建块 ----
    man = {} if args.force else load_manifest(root)
    t0 = time.time()
    lens: list[int] = []
    n_new = n_skip = 0
    for i, base in enumerate(pool, 1):
        spath = root / "seq" / f"{base}.pkl"
        rec = man.get(base)
        if not args.force and rec and spath.exists():
            n_skip += 1
            with open(spath, "rb") as fh:
                lens.append(len(pickle.load(fh)["tokens"]))
            continue
        src = source_path_of(base, args.graph_dir)
        try:
            contracts, ver = solc_bytecode(src.resolve())
            seq = _seq_of(contracts, args.bytecode_mode, int2op)
            if seq is None:
                rec = {"status": "empty_bytecode", "error": "所有合约的 creation bin 都为空"}
            else:
                rec = {"status": "ok", "solc": ver, "n_contracts": seq["n_contracts"],
                       "code_bytes": seq["code_bytes"], "n_tokens": len(seq["tokens"]),
                       "n_placeholder": seq["n_placeholder"], **seq["bbinfo"]}
                with open(spath, "wb") as fh:
                    pickle.dump(seq, fh)
                lens.append(len(seq["tokens"]))
        except Exception as e:                                     # noqa: BLE001
            rec = {"status": "compile_error", "error": f"{type(e).__name__}: {e}"}
        append_manifest(root, base, rec)
        n_new += 1
        if i % 25 == 0 or i == len(pool):
            print(f"[egfl] seq {i}/{len(pool)}  新建 {n_new} 跳过 {n_skip}  "
                  f"耗时 {time.time() - t0:.0f}s", flush=True)

    if args.report_seq_len:
        import numpy as np
        a = np.asarray(lens)
        print(f"[egfl] opcode token 数：n={a.size} min={a.min()} "
              f"p50={np.percentile(a,50):.0f} p90={np.percentile(a,90):.0f} "
              f"p95={np.percentile(a,95):.0f} p99={np.percentile(a,99):.0f} max={a.max()}", flush=True)
        return 0

    # ---- 阶段 2：词向量（**只用 train 划分的 token**，原实现用 train+val 算泄漏）----
    train_set = set(split["train"])
    train_seqs = []
    for base in pool:
        if base in train_set:
            sp = root / "seq" / f"{base}.pkl"
            if sp.exists():
                with open(sp, "rb") as fh:
                    train_seqs.append(pickle.load(fh)["tokens"])
    if not train_seqs:
        raise SystemExit("[egfl] train 语料为空——检查 split_dir/split_seed")
    from gensim.models import Word2Vec
    w2v_path = root / "w2v.model"
    if w2v_path.exists() and not args.force and not args.limit:
        w2v = Word2Vec.load(str(w2v_path)).wv
        print(f"[egfl] 复用词向量 {w2v_path}", flush=True)
    else:
        print(f"[egfl] 训练词向量：{len(train_seqs)} 条序列（仅 train 划分）", flush=True)
        m = Word2Vec(sentences=train_seqs, vector_size=args.node_dim, sg=1,
                     min_count=1, workers=16, seed=args.seed)
        m.save(str(w2v_path))
        w2v = m.wv

    # ---- 阶段 3：图向量 + 序列落盘 ----
    import numpy as np
    import torch
    out_dim = 256
    n_feat = 0
    for base in pool:
        sp = root / "seq" / f"{base}.pkl"
        fpath = root / "feat" / f"{base}.pt"
        if fpath.exists() and not args.force:
            continue
        if not sp.exists():
            continue
        with open(sp, "rb") as fh:
            seq = pickle.load(fh)
        vecs = block_vectors(seq["blocks"], w2v, args.node_dim)
        gvec = flatten_bfs(vecs, seq["bfs_order"], k=args.bfs_k, out_dim=out_dim)
        torch.save({"tokens": seq["tokens"], "gvec": torch.from_numpy(np.asarray(gvec)),
                    "n_blocks": seq["bbinfo"]["n_blocks"], "n_edges": seq["bbinfo"]["n_edges"],
                    "unresolved": seq["bbinfo"]["unresolved"],
                    "n_placeholder": seq.get("n_placeholder", 0)}, fpath)
        n_feat += 1

    man = load_manifest(root)
    (root / "manifest.json").write_text(json.dumps(man, ensure_ascii=False, indent=1),
                                        encoding="utf-8")
    n_total = len(list((root / "feat").glob("*.pt")))
    print(f"[egfl] 完成：manifest {len(man)} 条，feat/*.pt {n_total} 个，本次新建 {n_feat}，"
          f"总耗时 {time.time() - t0:.0f}s", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
