#!/usr/bin/env python3
"""构建「**边变体 × 微调编码器**」组合变体（`decisions.md` §37；微调升为正典的配套产物）。

**为什么需要它**：正典从「冻结 CodeBERT」改为「微调 CodeBERT」后，
`cb_rev` / `cb_unlimited` 两个臂若沿用原变体，就会带着**冻结**的 `_cb.pt`
去和**微调**的基线比 —— 那是**两个变量**，结果作废。
本脚本造出「边已改、编码器已是微调版」的变体，使这两个臂回到单变量。

**逐图分流，不做全库重编码**（全库 M3 代价 ① 10 min、② 46 min / 种子，共约 5.6 h）：

| 情形 | 判据（逐图实测，非假设） | 处置 |
|---|---|---|
| 边变体的 `_feat` 三通道 == 微调基座 | 该图的节点特征**没被边改动** | `_feat.pt`/`_cb.pt` **软链**自微调基座（可证等价） |
| 否则 | 边改动**连带改了节点特征** | 只对这批图**真跑 M3**（微调编码器） |

🔴 **为什么会走到第二类**：实测 `callback_unlimited` 放开 CALLBACK_RISK 上限后，
**恰好 20/590 张图**（①；② 为 199/1774）的 `_feat.sv`（先验分数 $s_v$）随之改变——
**边集变化经 M1 回流到了节点特征**。同批图的 `_pyg.pt` 也变了，两批**完全重合**。
`callback_rev` 则 590/590 三通道不变。⇒ **`cb_unlimited` 从来就不是纯边消融**，
它的变量同时含"边"与"$s_v$"；这一点在旧设计下就已存在，**在本脚本的断言里第一次被显式测出**。

**其余断言**（全部逐图、全量，不过即 `SystemExit` 且不留产物）：
  1. 边变体的**节点集**与正典一致（否则"换 `_cb.pt`"这个动作本身就不成立）；
  2. 边变体在**冻结**编码器下的 `_cb.pt` 与正典逐位相同 —— 证明节点文本窗口未被边改动，
     故"换成微调编码器的 `_cb.pt`"是唯一变量；
  3. 对第二类图，M3 用微调编码器**真跑**出的 `_cb.pt` 必须与微调基座逐位相同
     （同一批节点文本 + 同一编码器 ⇒ 必须同一结果；不同即说明节点文本其实变了）。

用法（从仓库根目录运行）：
  python scripts/build_ft_edge_variants.py --dataset alldata --dry-run
  python scripts/build_ft_edge_variants.py --dataset alldata
  python scripts/build_ft_edge_variants.py --dataset augmentation
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

EDGE_VARIANTS = {"cb_rev": "callback_rev", "cb_unlimited": "callback_unlimited"}
SPLIT_SEEDS = (0, 1, 2)
FROM_EDGE = ("_pyg.pt", "_m1.json", "_hetero.json")
CHANNELS = ("struct", "type_id", "sv")


def paths(ds: str) -> dict[str, Path]:
    """目录布局。

    ⚠ **冻结 IR 字典只有一份（在 ① 下）**，② 没有它 —— 故一律经
    `build_graph_variant.frozen_categories()` 取（缺文件即硬失败），
    不得按语料各取各的（那会造出两个可能漂移的来源，`AGENTS.md`「数据边界」）。
    """
    import build_graph_variant as bgv
    base = REPO / "products" / ds
    return {"ft": base / "graphs_ft", "edge": base / "graph_variants",
            "frozen": base / "graphs", "categories": bgv.frozen_categories()}


def link(src: Path, dst: Path) -> None:
    """建**相对**软链（相对路径才能在仓库整体搬迁后仍解析）。"""
    dst.unlink(missing_ok=True)
    dst.symlink_to(os.path.relpath(src.resolve(), dst.parent.resolve()))


def load_feat(p: Path) -> dict:
    import torch
    return torch.load(p, map_location="cpu")


def load_cb(p: Path) -> dict:
    import torch
    return torch.load(p, map_location="cpu")


def cb_equal(a: dict, b: dict) -> bool:
    import torch
    return all(torch.equal(a[ch][k], b[ch][k]) for ch in a for k in a[ch])


def partition(edge_dir: Path, ft0: Path, frozen: Path, names: list[str]) -> tuple[list[str], list[str]]:
    """逐图分流 + 断言 1/2。返回 (可软链, 须重跑 M3)。"""
    import torch
    same: list[str] = []
    must: list[str] = []
    bad: list[str] = []
    for i, n in enumerate(names):
        stem = n[: -len("_feat.pt")]
        e_feat, f_feat = load_feat(edge_dir / n), load_feat(ft0 / n)
        e_pyg = torch.load(edge_dir / f"{stem}_pyg.pt", map_location="cpu")
        c_pyg = torch.load(frozen / f"{stem}_pyg.pt", map_location="cpu")
        e_cb = load_cb(edge_dir / f"{stem}_cb.pt")
        c_cb = load_cb(frozen / f"{stem}_cb.pt")
        # 断言 1：节点集一致
        if list(e_pyg["node_id"]) != list(c_pyg["node_id"]):
            bad.append(f"{stem}: 节点集与正典不同 —— 「换 _cb.pt」这个动作不成立")
        # 断言 2：冻结编码器下的 _cb.pt 与正典逐位相同（节点文本未变）
        elif not cb_equal(e_cb, c_cb):
            bad.append(f"{stem}: 冻结编码器下 _cb.pt 与正典不同 —— 边改动了节点文本窗口")
        # 分流：三通道是否被边改动
        elif all(torch.equal(e_feat[ch], f_feat[ch]) for ch in CHANNELS):
            same.append(n)
        else:
            must.append(n)
        if (i + 1) % 500 == 0:
            print(f"     …已分流 {i + 1}/{len(names)}", flush=True)
        if len(bad) > 6:
            bad.append("（其余省略）")
            break
    if bad:
        raise SystemExit("[ftvar] 断言未通过，未写出任何变体：\n  " + "\n  ".join(bad))
    return same, must


def run_m3(stage: Path, encoder: Path, categories: Path) -> None:
    cmd = [sys.executable, "scripts/m3_build_features.py",
           "--in-dir", str(stage), "--out-dir", str(stage), "--m1-dir", str(stage),
           "--categories", str(categories), "--codebert", str(encoder), "--device", "cuda"]
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("[ftvar] M3 失败：\n" + (r.stderr or r.stdout or "")[-800:])


def build(ds: str, dry_run: bool) -> None:
    P = paths(ds)
    if not P["ft"].is_dir():
        raise SystemExit(f"[ftvar] 找不到微调基座 {P['ft']}")
    if not P["categories"].exists():
        raise SystemExit(f"[ftvar] 找不到冻结 IR 字典 {P['categories']}（跨语料列宽锚点，必须显式给出）")
    out_root = P["ft"] / "graph_variants"
    encoder_root = REPO / "runs" / "codebert_ft" / ds
    print(f"[ftvar] 语料 {ds}\n        微调基座 {P['ft']}\n        边变体源 {P['edge']}\n"
          f"        编码器   {encoder_root}/ss{{0,1,2}}/encoder\n        产出     {out_root}\n")

    for short, edge_name in EDGE_VARIANTS.items():
        edge_dir = P["edge"] / edge_name
        if not edge_dir.is_dir():
            raise SystemExit(f"[ftvar] 找不到边变体 {edge_dir}")
        names = sorted(p.name for p in edge_dir.glob("*_feat.pt"))
        print(f"[ftvar] {short} ← {edge_name}：{len(names)} 图，逐图分流中…", flush=True)
        same, must = partition(edge_dir, P["ft"] / "ss0", P["frozen"], names)
        print(f"        ✅ 断言 1/2 通过：节点集一致、冻结 _cb.pt 逐位相同")
        print(f"        分流：可软链 {len(same)} 图  |  须重跑 M3 {len(must)} 图")
        if must:
            print(f"        ⚠ 这 {len(must)} 张图的 `_feat.sv` 被边改动 —— "
                  f"本臂的变量不止「边」，还含先验分数（已记入 variant.json）")
        if dry_run:
            for s in SPLIT_SEEDS:
                print(f"        [dry-run] 将建 {out_root / f'{short}_ss{s}'}/")
            continue

        for s in SPLIT_SEEDS:
            ft_dir = P["ft"] / f"ss{s}"
            enc = encoder_root / f"ss{s}" / "encoder"
            if not ft_dir.is_dir() or not (enc / "config.json").exists():
                raise SystemExit(f"[ftvar] 缺微调基座或编码器：{ft_dir} / {enc}")
            out = out_root / f"{short}_ss{s}"
            out.mkdir(parents=True, exist_ok=True)

            # 结构侧全部取自边变体
            for n in names:
                stem = n[: -len("_feat.pt")]
                for suf in FROM_EDGE:
                    src = edge_dir / f"{stem}{suf}"
                    if src.exists():
                        link(src, out / f"{stem}{suf}")
            # 可软链的图：_feat/_cb 直接指向微调基座
            for n in same:
                stem = n[: -len("_feat.pt")]
                for suf in ("_feat.pt", "_cb.pt"):
                    link(ft_dir / f"{stem}{suf}", out / f"{stem}{suf}")
            # 须重跑的图：临时目录只放这批，跑完 M3 再把产物搬进来
            rerun_info = {"graphs": len(must), "cb_matches_ft_base": None}
            if must:
                stage = P["ft"] / "_staging" / f"{short}_ss{s}"
                if stage.exists():
                    shutil.rmtree(stage)
                stage.mkdir(parents=True)
                for n in must:
                    stem = n[: -len("_feat.pt")]
                    for suf in FROM_EDGE:
                        src = edge_dir / f"{stem}{suf}"
                        if src.exists():
                            link(src, stage / f"{stem}{suf}")
                print(f"        [M3] {short}_ss{s}：对 {len(must)} 张图用微调编码器重跑…", flush=True)
                run_m3(stage, enc, P["categories"])
                # 断言 3：重跑出的 _cb.pt 必须与微调基座逐位相同
                mism = [n for n in must
                        if not cb_equal(load_cb(stage / n.replace("_feat.pt", "_cb.pt")),
                                        load_cb(ft_dir / n.replace("_feat.pt", "_cb.pt")))]
                if mism:
                    raise SystemExit(f"[ftvar] 断言 3 未过：{len(mism)} 张图重跑出的 `_cb.pt` "
                                     f"与微调基座不同（同一编码器+同一节点文本应当相同）：{mism[:3]}")
                rerun_info["cb_matches_ft_base"] = True
                print(f"        ✅ 断言 3 通过：重跑的 _cb.pt 与微调基座逐位相同", flush=True)
                for n in must:
                    stem = n[: -len("_feat.pt")]
                    for suf in ("_feat.pt", "_cb.pt"):
                        os.replace(stage / f"{stem}{suf}", out / f"{stem}{suf}")
                shutil.rmtree(stage)

            (out / "variant.json").write_text(json.dumps({
                "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "variant": f"{short}_ft", "split_seed": s,
                "derived_from": f"products/{ds}/graphs_ft/ss{s}",
                "edges_from": f"products/{ds}/graph_variants/{edge_name}",
                "only_variable": f"相对新正典（微调 CodeBERT）只改边：{edge_name} 的边"
                                 + ("（其中 {} 图的先验 s_v 随之改变，见下）".format(len(must)) if must else ""),
                "how": {"symlinked": f"{len(same)} 图：_feat.pt/_cb.pt 软链自微调基座（三通道逐图证同）",
                        "m3_rerun": f"{len(must)} 图：结构取自边变体，M3 用微调编码器真跑",
                        "assertions": ["节点集一致", "冻结编码器下 _cb.pt 与正典逐位相同",
                                       "重跑 _cb.pt 与微调基座逐位相同"]},
                "expect": {"_feat.pt": f"三通道取自边变体；cb 指纹取自微调基座",
                           "_cb.pt": "微调编码器产物（对全部图均已验证）",
                           "_pyg.pt": f"与 {edge_name} 一致（边已改）"},
                "caveat": (f"⚠ 本臂不是纯边消融：{len(must)} 张图的先验分数 s_v 随边改动而变"
                           f"（旧设计下亦然，此处首次显式测出）") if must else None,
                "n_rerun_graphs": len(must),
            }, ensure_ascii=False, indent=1), encoding="utf-8")
            n_link = sum(1 for p in out.iterdir() if p.is_symlink())
            print(f"        ✅ {out.relative_to(REPO)}  （{n_link} 软链 / "
                  f"{len(list(out.iterdir())) - n_link - 1} 实文件）", flush=True)

    staging_root = P["ft"] / "_staging"
    if staging_root.exists() and not any(staging_root.iterdir()):
        staging_root.rmdir()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dataset", required=True, choices=["alldata", "augmentation"])
    ap.add_argument("--dry-run", action="store_true", help="只断言 + 分流 + 打印将要建的目录。")
    args = ap.parse_args()
    build(args.dataset, args.dry_run)


if __name__ == "__main__":
    main()
