#!/usr/bin/env python3
"""`_cb.pt` 紧凑化：把视图条目重存为紧凑副本，**值逐位不变**，体积降约 35 倍。

**为什么需要**（`decisions.md` §33）：`m3_build_features.encode()` 原先返回
`model(**ids).last_hidden_state[:, 0, :].cpu()[0]` 的**视图**。在 **CPU** 上 `.cpu()` 是 no-op，
故该视图保留 `[1, seq_len, 768]` 的整块 storage，`torch.save` 会把它**整块**写进文件——
每条目按 `seq_len × 3 KB` 落盘而不是 3 KB。实测：max_len=128 膨胀 ×128、512 膨胀 ×512。
主库 590 个 `_cb.pt` 因此合计 **14.61 GB**（真值约 0.35 GB）。

⚠ **只影响 CPU 构建的缓存**：GPU 路径 `.cpu()` 是真拷贝，产物本就是紧凑的
（增强集缓存即如此）——这是"产物不该随运行设备变化"的教训，不是"某些库可以不管"。

**本脚本做什么**：逐图 `load → 逐条 clone → 存临时文件 → 重载并逐位比对 → os.replace`。
**先验证再替换**，任何一条对不上就放弃该文件、保留原样（绝不写坏原始缓存）。

用法（从仓库根目录运行）：
  python scripts/recompact_cb_cache.py --dry-run                  # 只报预计节省，不写
  python scripts/recompact_cb_cache.py --only <base>              # 单文件小样
  python scripts/recompact_cb_cache.py                            # 全量（默认主库目录）

产物：就地重写 `<dir>/*_cb.pt` + 打印逐文件与合计的 before/after。
**不改任何别的文件**（`_feat.pt` 里的 `cb_sha256` 不需同步——它哈希的是装载后的矩阵，
值没变则哈希没变；用 `dataset.channel_hash_mismatches(which="all")` 复核，见 `--verify`）。
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
import time
from pathlib import Path

import torch

REPO = Path(__file__).resolve().parents[1]

DEFAULT_DIR = REPO / "products" / "alldata" / "graphs"
CHANNELS = ("func", "node")


def compact_entry(t: torch.Tensor) -> torch.Tensor:
    """单条缓存向量 → 紧凑副本（值逐位相同，storage 恰为 numel）。"""
    return t.detach().clone()


def recompact_one(path: Path, dry_run: bool = False) -> dict:
    """重写单个 `_cb.pt`。返回统计；失败时 `ok=False` 且**原文件不动**。"""
    before = path.stat().st_size
    cache = torch.load(path, map_location="cpu")
    if not isinstance(cache, dict) or not all(ch in cache for ch in CHANNELS):
        return {"file": path.name, "ok": False, "reason": "结构不是 {func,node} 字典", "before": before}

    data_bytes = sum(v.numel() * 4 for ch in CHANNELS for v in cache[ch].values())
    if dry_run:
        # 估算紧凑后的文件大小：数据 + 每键的 zip 头开销（实测约 100 B/键）
        n_keys = sum(len(cache[ch]) for ch in CHANNELS)
        est = data_bytes + 120 * n_keys
        return {"file": path.name, "ok": True, "dry_run": True, "before": before,
                "after_est": est, "n_keys": n_keys}

    compact = {ch: {k: compact_entry(v) for k, v in cache[ch].items()} for ch in CHANNELS}

    # ---- 先写临时文件、重载、逐位比对，通过后才 os.replace（绝不写坏原缓存）----
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=".recompact_", suffix=".pt")
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        torch.save(compact, tmp)
        back = torch.load(tmp, map_location="cpu")
        if set(back["func"]) != set(compact["func"]) or set(back["node"]) != set(compact["node"]):
            return {"file": path.name, "ok": False, "reason": "重载后键集合不一致", "before": before}
        for ch in CHANNELS:
            for k, v in compact[ch].items():
                if not torch.equal(back[ch][k], v):
                    return {"file": path.name, "ok": False,
                            "reason": f"重载后 {ch}[{k}] 与紧凑副本不逐位相同", "before": before}
    except Exception as exc:                                     # noqa: BLE001 — 失败一律保留原件
        tmp.unlink(missing_ok=True)
        return {"file": path.name, "ok": False, "reason": f"{type(exc).__name__}: {exc}",
                "before": before}

    os.replace(tmp, path)                                        # 原子替换（同目录同文件系统）
    return {"file": path.name, "ok": True, "before": before, "after": path.stat().st_size,
            "data_bytes": data_bytes}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dir", default=str(DEFAULT_DIR),
                   help="含 *_cb.pt 的目录（默认主库 graphs）。**只处理该目录下的 _cb.pt**。")
    p.add_argument("--only", default=None, help="只处理该 base（小样验证用）。")
    p.add_argument("--dry-run", action="store_true", help="只报预计节省，不写任何文件。")
    p.add_argument("--limit", type=int, default=0, help="只处理前 N 个（0=全部）。")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.dir)
    files = sorted(root.glob("*_cb.pt"))
    if args.only:
        files = [f for f in files if f.name == f"{args.only}_cb.pt"]
    if args.limit:
        files = files[:args.limit]
    if not files:
        raise SystemExit(f"[recompact] {root} 下没有匹配的 *_cb.pt")

    total_before = sum(f.stat().st_size for f in files)
    print(f"[recompact] {root}: {len(files)} 个文件，当前合计 {total_before/1e9:.2f} GB"
          f"{'（dry-run，不写）' if args.dry_run else ''}\n", flush=True)

    t0 = time.perf_counter()
    rows, failed = [], []
    for i, f in enumerate(files, 1):
        r = recompact_one(f, dry_run=args.dry_run)
        rows.append(r)
        if not r["ok"]:
            failed.append(r)
            print(f"  ✗ {r['file']}: {r['reason']}", flush=True)
        elif i % 50 == 0 or args.only or args.dry_run and i <= 3:
            done = sum(x.get("after", x.get("after_est", 0)) for x in rows if x["ok"])
            print(f"  … {i}/{len(files)}  已处理 {done/1e9:.3f} GB", flush=True)

    ok = [r for r in rows if r["ok"]]
    after = sum(r.get("after", r.get("after_est", 0)) for r in ok)
    print(f"\n[recompact] 成功 {len(ok)}/{len(files)}；用时 {time.perf_counter()-t0:.1f}s")
    print(f"[recompact] {total_before/1e9:.3f} GB → {after/1e9:.3f} GB "
          f"（×{total_before/max(after,1):.0f} 缩小，释放 {(total_before-after)/1e9:.2f} GB）")
    if failed:
        print(f"[recompact] ⚠ {len(failed)} 个文件未处理（原样保留）："
              f"{[r['file'] for r in failed][:5]}")
        sys.exit(1)


if __name__ == "__main__":
    main()
