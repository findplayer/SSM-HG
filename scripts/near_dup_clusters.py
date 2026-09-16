#!/usr/bin/env python3
"""近重复簇检测（跨语料防泄漏；2026-09-14）。

用途：`make_splits.py` 的现有两级去重（源码 sha1 完全相同 / 同一项目标识）只能抓
**精确重复**。语料里还有大量"改动过的孪生"——同一合约的不同副本、复制粘贴到不同地址的
同款源码（实测 Jaccard 0.98）——它们 sha1 不同、项目标识也不同，两级去重都抓不到，
却一旦分入不同划分就是实打实的泄漏（本检测在主库现行划分上实测到 seed0 test↔train
17 对、最高 Jaccard 0.98）。

方法（纯标准库、确定性、无 RNG）：
  1. 每个 `.sol` → 逐行 strip 后 sha1 的集合（跳过空行与过短行）；新语料已去注释且保留空行，
     故逐行哈希即行级 shingle，strip 吸收缩进差异，copy-paste 双胞胎仍能命中；
  2. 只保留**出现文件数 ≤ `--df-cap`** 的行（`}`、`pragma`、常见 require 等高频行会淹没信号）；
  3. 倒排表累加两两共享的稀有行数（预筛）；
  4. 候选对上再算**行集合 Jaccard**，保留 ≥ `--min-jaccard` 的对（共享行数未归一化，
     单独用它会把同族合约也算成近重复）；
  5. **全链接**凝聚成簇（不用并查集：单链接的传递闭包会把 A~B、B~C 合成 A≁C 的大簇）。

输出（`--out` JSON + `--report` txt，均为中间产物，不手改）：
  {"meta": {min_shared, min_jaccard, df_cap, min_line_len, n_bases, n_rare_lines,
            n_pairs_prefiltered, n_pairs_similar, n_clusters, n_files_in_clusters,
            coverage, max_cluster, created_utc, source_digest_sha256},
   "clusters": [["base", ...], ...]}      簇按 (大小降序, 首元素) 排序，编号 c0000…

运行（仓库根目录）：
  python scripts/near_dup_clusters.py --graph-dir products/augmentation/graphs \\
      --out products/augmentation/splits/near_dup_clusters.json \\
      --report products/augmentation/splits/near_dup_report.txt
  python scripts/near_dup_clusters.py --graph-dir ... --only <base>   # 小样干跑
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import itertools
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE / "scripts"))
import make_splits  # noqa: E402  （source_path_of / exclude_buggy：与划分走同一条口径）
from dataset import build_index as dataset_build_index  # noqa: E402

DEFAULT_MIN_SHARED = 20     # 共享稀有行数下限（实测主口径；50 作敏感性）
DEFAULT_DF_CAP = 25         # 稀有行定义：出现文件数 ≤ 该值
DEFAULT_MIN_JACCARD = 0.6   # 近重复判定：行集合 Jaccard 下限（0.5 更松、0.7 更严）
MIN_LINE_LEN = 13           # 过短行（`}`、`)`）不承载信息，直接排除


def line_hashes_of(path: Path | str) -> frozenset[str]:
    """源码 → 逐行（strip 后）sha1 集合；跳过空行与长度 < MIN_LINE_LEN 的行。"""
    text = Path(path).read_text(encoding="utf-8", errors="ignore")
    out = set()
    for raw in text.splitlines():
        line = raw.strip()
        if len(line) < MIN_LINE_LEN:
            continue
        out.add(hashlib.sha1(line.encode("utf-8")).hexdigest())
    return frozenset(out)


def rare_line_index(sigs: dict[str, frozenset[str]],
                    df_cap: int = DEFAULT_DF_CAP) -> dict[str, list[str]]:
    """行哈希 → 含该行的文件列表，只保留 `1 < 文件数 <= df_cap` 的行。"""
    inv: dict[str, list[str]] = collections.defaultdict(list)
    for base, lines in sigs.items():
        for h in lines:
            inv[h].append(base)
    return {h: fs for h, fs in inv.items() if 1 < len(fs) <= df_cap}


def pair_shared_counts(rare: dict[str, list[str]]) -> dict[tuple[str, str], int]:
    """倒排表累加两两共享的稀有行数（每行的文件列表已被 df_cap 截断）。"""
    pair: dict[tuple[str, str], int] = collections.Counter()
    for files in rare.values():
        for a, b in itertools.combinations(sorted(files), 2):
            pair[(a, b)] += 1
    return pair


def jaccard(sig_a: frozenset[str], sig_b: frozenset[str]) -> float:
    """行集合的 Jaccard 相似度（空交集即 0）。"""
    union = len(sig_a | sig_b)
    return len(sig_a & sig_b) / union if union else 0.0


def pair_similarities(sigs: dict[str, frozenset[str]], cand: dict[tuple[str, str], int],
                      min_shared: int = DEFAULT_MIN_SHARED,
                      min_jaccard: float = DEFAULT_MIN_JACCARD) -> dict[tuple[str, str], float]:
    """候选对（共享稀有行 ≥ min_shared）上再算 Jaccard，保留 ≥ min_jaccard 的对。

    先用量化的共享行数做**预筛**（省掉全 O(n²) 的集合交），再以 Jaccard 定判——
    共享稀有行数没有归一化，单独用它会把"同族合约"（共享 ERC20 核心行）也算成近重复。
    """
    out: dict[tuple[str, str], float] = {}
    for (a, b), shared in cand.items():
        if shared < min_shared:
            continue
        j = jaccard(sigs[a], sigs[b])
        if j >= min_jaccard:
            out[(a, b)] = j
    return out


def similar_pairs(bases: list[str], graph_dir: Path | str,
                  min_shared: int = DEFAULT_MIN_SHARED, df_cap: int = DEFAULT_DF_CAP,
                  min_jaccard: float = DEFAULT_MIN_JACCARD,
                  source_of=None) -> tuple[dict[tuple[str, str], float], list[str], dict]:
    """→ (相似对 {(a,b): jaccard}, 有序 base 列表, 中间量诊断)。

    从 `detect` 抽出，供**泄漏审计**复用完全相同的判据——避免"检测一套阈值、审计另一套"
    导致结论对不上。
    """
    source_of = source_of or (lambda b: make_splits.source_path_of(b, graph_dir))
    ordered = sorted(bases)
    sigs = {b: line_hashes_of(source_of(b)) for b in ordered}
    rare = rare_line_index(sigs, df_cap=df_cap)
    cand = pair_shared_counts(rare)
    sims = pair_similarities(sigs, cand, min_shared=min_shared, min_jaccard=min_jaccard)
    diag = {"n_rare_lines": len(rare),
            "n_pairs_prefiltered": sum(1 for v in cand.values() if v >= min_shared)}
    return sims, ordered, diag


def split_leakage(sims: dict[tuple[str, str], float], split: dict) -> dict:
    """统计**跨划分**的相似对（泄漏量级）。

    划分原子性只保证"簇不跨划分"，本函数给出可直接写进论文的量化：跨划分相似对
    train↔test / train↔val / val↔test 各多少对、最高与中位 Jaccard。

    返回 {"n_cross": n, "by_pair": {"train|test": n, ...}, "max_jaccard": j,
          "median_jaccard": j, "worst": [(a, b, wa, wb, j), ...]（按 Jaccard 降序前 20）}
    """
    where: dict[str, str] = {}
    for name in ("train", "val", "test"):
        for base in split.get(name, []):
            where[base] = name
    cross: list[tuple[str, str, str, str, float]] = []
    for (a, b), j in sims.items():
        wa, wb = where.get(a), where.get(b)
        if wa and wb and wa != wb:
            cross.append((a, b, wa, wb, j))
    cross.sort(key=lambda t: -t[4])
    by_pair: dict[str, int] = collections.Counter("|".join(sorted((wa, wb)))
                                                 for _a, _b, wa, wb, _j in cross)
    js = [t[4] for t in cross]
    return {
        "n_cross": len(cross),
        "by_pair": dict(by_pair),
        "max_jaccard": round(max(js), 4) if js else 0.0,
        "median_jaccard": round(statistics.median(js), 4) if js else 0.0,
        "worst": [[a, b, wa, wb, round(j, 4)] for a, b, wa, wb, j in cross[:20]],
    }


def complete_linkage_clusters(sims: dict[tuple[str, str], float], bases: list[str]) -> list[list[str]]:
    """全链接（complete-linkage）凝聚：新成员必须与簇内**所有**成员都有边才并入。

    刻意不用并查集：单链接的传递闭包会把 "A~B、B~C" 合成一个 A≁C 的大簇
    （2026-09-14 实测：单链接在主库上产出 92 个成员的簇，簇内 92% 的成员对
    Jaccard < 0.3、中位 0.11 —— 那不是近重复，是同族合约的链式串联）。
    全链接把这 92 个成员拆成最大 7 个的真实近重复簇，簇内 Jaccard 最低 0.84。
    顺序无关（按 base 升序贪心），确定性。
    """
    clusters: list[list[str]] = []
    for base in bases:
        for cluster in clusters:
            if all((min(a, base), max(a, base)) in sims for a in cluster):
                cluster.append(base)
                break
        else:
            clusters.append([base])
    multi = [sorted(c) for c in clusters if len(c) > 1]
    multi.sort(key=lambda c: (-len(c), c[0]))
    return multi


def connected_components_clusters(sims: dict[tuple[str, str], float],
                                  bases: list[str]) -> list[list[str]]:
    """相似图的**连通分量**（并查集）——用于「防泄漏」而非「报告孪生」。

    与 `complete_linkage_clusters` 的取舍：
      - 全链接给的是"紧密孪生"（簇内每对都 ≥ 阈值），但它是**贪心**的：两条 ≥ 阈值的边
        可能被分进不同簇，于是划分后仍有少量 ≥ 阈值的对跨划分
        （2026-09-15 主库实测：全链接划分剩 8/7/5 对，最高 Jaccard 0.73）。
      - 若判据严格取"≥ 阈值的对**不得**跨划分"，原子单位就必须是连通分量：按定义，
        分量之间不存在 ≥ 阈值的边 → 跨划分对**恒为 0**（可证，非近似）。
    代价：分量比全链接簇更粗（主库 Jaccard≥0.6 实测最大 15 vs 全链接 8），划分自由度略降。
    顺序无关（按 base 升序），确定性；只返回 size>1 的分量。
    """
    parent = {b: b for b in bases}

    def find(x: str) -> str:
        while parent[x] != x:
            parent[x] = parent[parent[x]]        # 路径减半
            x = parent[x]
        return x

    for a, b in sims:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    groups: dict[str, list[str]] = collections.defaultdict(list)
    for b in bases:
        groups[find(b)].append(b)
    multi = [sorted(members) for members in groups.values() if len(members) > 1]
    multi.sort(key=lambda c: (-len(c), c[0]))
    return multi


def detect(bases: list[str], graph_dir: Path | str,
           min_shared: int = DEFAULT_MIN_SHARED, df_cap: int = DEFAULT_DF_CAP,
           min_jaccard: float = DEFAULT_MIN_JACCARD,
           source_of=None, mode: str = "complete") -> tuple[list[list[str]], dict]:
    """检测近重复簇 → (clusters, stats)。

    `source_of` 默认走 `make_splits.source_path_of`（读 `_hetero.json::meta.source_path`）——
    扁平语料没有 `<项目>/<词干>.sol` 可拼，必须走 meta；注入点供单测使用。
    `mode`：`"complete"`（默认，紧密孪生，供报告）/ `"components"`（连通分量，供防泄漏划分，
    跨划分对可证为 0）。
    """
    source_of = source_of or (lambda b: make_splits.source_path_of(b, graph_dir))
    sims, ordered, diag = similar_pairs(bases, graph_dir, min_shared=min_shared, df_cap=df_cap,
                                        min_jaccard=min_jaccard, source_of=source_of)
    if mode == "components":
        clusters = connected_components_clusters(sims, ordered)
    elif mode == "complete":
        clusters = complete_linkage_clusters(sims, ordered)
    else:
        raise ValueError(f"未知 cluster mode: {mode!r}")
    covered = sum(len(c) for c in clusters)
    stats = {
        "min_shared": min_shared, "df_cap": df_cap, "min_line_len": MIN_LINE_LEN,
        "min_jaccard": min_jaccard, "cluster_mode": mode,
        "n_bases": len(ordered), "n_rare_lines": diag["n_rare_lines"],
        "n_pairs_prefiltered": diag["n_pairs_prefiltered"],
        "n_pairs_similar": len(sims), "n_clusters": len(clusters),
        "n_files_in_clusters": covered,
        "coverage": round(covered / len(ordered), 4) if ordered else 0.0,
        "max_cluster": max((len(c) for c in clusters), default=0),
    }
    return clusters, stats


def digest_of(bases: list[str], graph_dir: Path | str, source_of=None) -> str:
    """簇文件与池绑定的指纹：base 名 + 源码 sha1 的有序摘要（池变即变）。"""
    source_of = source_of or (lambda b: make_splits.source_path_of(b, graph_dir))
    h = hashlib.sha256()
    for b in sorted(bases):
        h.update(b.encode("utf-8"))
        h.update(make_splits.sha1_file(source_of(b)).encode("ascii"))
    return h.hexdigest()


def write_clusters(path: Path | str, clusters: list[list[str]], meta: dict) -> None:
    """写簇文件（JSON，簇按大小降序编号 c0000/c0001/…）。"""
    payload = {"meta": meta,
               "clusters": clusters}
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")


def load_clusters(path: Path | str) -> tuple[dict[str, str], dict]:
    """读簇文件 → ({base: cluster_key}, meta)。不在任何簇里的文件不出现在映射中。"""
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    mapping: dict[str, str] = {}
    for i, members in enumerate(payload.get("clusters", [])):
        key = f"c{i:04d}"
        for base in members:
            mapping[base] = key
    return mapping, payload.get("meta", {})


def render_report(stats: dict, clusters: list[list[str]], source: str) -> str:
    lines = ["# 近重复簇报告（`scripts/near_dup_clusters.py` 生成，勿手改）", "",
             f"> 生成时间（UTC）：{stats.get('created_utc', '—')}；图目录：`{source}`", "",
             f"- 样本 {stats['n_bases']} 个；稀有行（出现文件数 ≤ {stats['df_cap']}）"
             f" {stats['n_rare_lines']} 条；预筛候选对 {stats['n_pairs_prefiltered']} 对。",
             f"- 阈值（共享稀有行 ≥ {stats['min_shared']} 且 Jaccard ≥ {stats['min_jaccard']}）："
             f"命中 **{stats['n_pairs_similar']}** 对，"
             f"聚成 **{stats['n_clusters']}** 个簇，覆盖 **{stats['n_files_in_clusters']}** 个文件"
             f"（{stats['coverage']:.1%}），最大簇 **{stats['max_cluster']}** 个。", "",
             "| 簇 | 大小 | 成员（前 6 个） |", "| --- | --- | --- |"]
    for i, members in enumerate(clusters[:40]):
        shown = "`, `".join(members[:6])
        more = f" …（共 {len(members)}）" if len(members) > 6 else ""
        lines.append(f"| c{i:04d} | {len(members)} | `{shown}`{more} |")
    if len(clusters) > 40:
        lines.append("")
        lines.append(f"（仅列前 40 个簇，完整清单见 JSON 的 `clusters` 字段）")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Detect near-duplicate clusters for leak-safe splitting.")
    parser.add_argument("--graph-dir", default=f"{BASE}/products/alldata/graphs")
    parser.add_argument("--out", default=None, help="簇 JSON 输出路径（省略则只打印）")
    parser.add_argument("--report", default=None, help="人读报告输出路径（省略则不写）")
    parser.add_argument("--min-shared", type=int, default=DEFAULT_MIN_SHARED,
                        help=f"共享稀有行数下限（默认 {DEFAULT_MIN_SHARED}；50 为高置信档）")
    parser.add_argument("--df-cap", type=int, default=DEFAULT_DF_CAP,
                        help=f"稀有行的文档频率上限（默认 {DEFAULT_DF_CAP}）")
    parser.add_argument("--only", default=None, help="只处理该 base（小样干跑）")
    parser.add_argument("--buggy-policy", choices=list(make_splits.BUGGY_POLICIES),
                        default="project-prefix",
                        help="池口径：先按该策略剔注入噪声再检测（须与 make_splits 一致，"
                             "否则簇可能在划分时不适用）。主库用 project-prefix；新语料用 none。")
    parser.add_argument("--min-jaccard", type=float, default=DEFAULT_MIN_JACCARD,
                        help=f"行集合 Jaccard 下限（默认 {DEFAULT_MIN_JACCARD}）")
    parser.add_argument("--cluster-mode", choices=("complete", "components"), default="complete",
                        help="complete=全链接紧密孪生（默认，供报告）；"
                             "components=相似图连通分量（**划分防泄漏用**：跨划分近重复对可证为 0，"
                             "代价是原子单位更粗）。")
    parser.add_argument("--label-file", default=None,
                        help="标签文件路径（省略则走 SSMHG_LABEL_FILE，再默认主库 contract_labels.json）。"
                             "**第二语料必须显式给**，否则池会静默缩水（2026-09-15 实测：aug 语料漏传时"
                             "池从 1774 掉到 167，检测结果毫无意义）。")
    parser.add_argument("--label-key-mode", choices=["project", "stem"], default=None,
                        help="标签键模式（省略则走 SSMHG_LABEL_KEY_MODE，再默认 project）；"
                             "扁平/词干命名语料（augmentation）必须传 stem。")
    parser.add_argument("--print", dest="print_only", action="store_true")
    parser.add_argument("--audit-split", default=None,
                        help="泄漏审计：给定 split_seedN.json，报告其中**跨划分**的近重复对"
                             "（复用同一批相似对，不另设阈值）。可重复传入（如 seed0/1/2）。")
    parser.add_argument("--audit-out", default=None,
                        help="把审计结果写成 JSON（供 results.md 引用）；省略则只打印。")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    graph_dir = Path(args.graph_dir)
    index, unmatched = dataset_build_index(graph_dir, label_file=args.label_file,
                                           key_mode=args.label_key_mode)
    if unmatched:
        # 池静默缩水是本脚本最危险的失效模式：近重复检测会"正常完成"但只覆盖了子集，
        # 产出的簇文件拿去划分时，未覆盖的部分完全不受保护。故一律显式告警。
        n_graphs = len(list(graph_dir.glob("*_pyg.pt")))
        print(f"[near-dup] ⚠ 警告：{len(unmatched)}/{n_graphs} 个图未匹配到标签，已被排除在池外。"
              f"若这不是预期（如第二语料忘传 --label-file/--label-key-mode），"
              f"检测结果**不可用**。例：{unmatched[:3]}", file=sys.stderr)
    kept, _excluded = make_splits.exclude_buggy(index, policy=args.buggy_policy)
    bases = sorted(kept)
    if not bases:
        raise SystemExit(f"{graph_dir} 下没有可用样本（--buggy-policy={args.buggy_policy} 后池为空）")
    if args.only:
        if args.only not in bases:
            raise SystemExit(f"--only {args.only} 不在 {graph_dir} 的池内")
        bases = [args.only]

    clusters, stats = detect(bases, graph_dir, min_shared=args.min_shared,
                             df_cap=args.df_cap, min_jaccard=args.min_jaccard,
                             mode=args.cluster_mode)
    stats["created_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    stats["source_digest_sha256"] = digest_of(bases, graph_dir)
    print(f"[near-dup] 样本 {stats['n_bases']}；阈值 共享≥{stats['min_shared']} 且 "
          f"Jaccard≥{stats['min_jaccard']} 命中 {stats['n_pairs_similar']} 对，"
          f"{stats['n_clusters']} 簇覆盖 {stats['n_files_in_clusters']} 文件"
          f"（{stats['coverage']:.1%}），最大簇 {stats['max_cluster']}")
    for i, members in enumerate(clusters[:10]):
        print(f"  c{i:04d} ({len(members):3d})：{', '.join(members[:4])}"
              f"{' …' if len(members) > 4 else ''}")
    if args.audit_split:
        # 泄漏审计：判据与检测完全一致（同一 similar_pairs），只是换个问法——"这些相似对里
        # 有多少落到了不同划分"。此处重算一次相似对（秒级），以保住 detect 的原签名。
        sims, _ordered, _diag = similar_pairs(bases, graph_dir, min_shared=args.min_shared,
                                              df_cap=args.df_cap,
                                              min_jaccard=args.min_jaccard)
        audit: dict[str, dict] = {}
        for path_str in args.audit_split.split(","):
            path = Path(path_str.strip())
            split = json.loads(path.read_text(encoding="utf-8"))
            res = split_leakage(sims, split)
            audit[path.name] = res
            print(f"[leak] {path.name}: 跨划分近重复 {res['n_cross']} 对"
                  f"{dict(res['by_pair'])}；最高 Jaccard {res['max_jaccard']}"
                  f"、中位 {res['median_jaccard']}")
        if args.audit_out:
            out_path = Path(args.audit_out)
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(json.dumps(
                {"source": str(graph_dir), "threshold": {"min_shared": args.min_shared,
                                                         "min_jaccard": args.min_jaccard,
                                                         "df_cap": args.df_cap},
                 "audit": audit}, ensure_ascii=False, indent=1), encoding="utf-8")
            print(f"written: {out_path}")
    if args.print_only:
        return
    if args.out:
        write_clusters(args.out, clusters, stats)
        print(f"written: {Path(args.out).relative_to(BASE) if str(args.out).startswith(str(BASE)) else args.out}")
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(render_report(stats, clusters, str(graph_dir)), encoding="utf-8")
        print(f"written: {Path(args.report).relative_to(BASE) if str(args.report).startswith(str(BASE)) else args.report}")


if __name__ == "__main__":
    main()
