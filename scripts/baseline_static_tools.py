#!/usr/bin/env python3
"""传统静态分析工具基线（大纲 `改II` 5.3「传统工具对比」行）。

**为什么需要它**：`eval_results/baseline/` 一直是空的（只有一个 0 字节 `.gitkeep`），
而 5.3 点名 6 个传统工具。没有参照系时「micro-F1 0.73 算不算低」**无法判定**——
这是对比实验表里最刚性、也最便宜的一项。

**本脚本做什么**：把工具在**源码**上的原始输出（Slither 的检测器命中）映射成
**七维规则命中向量**（大纲 5.3 原文：「传统模型也输出七维规则命中结果，而不是单标签类别」），
再按给定划分在 test 上算 micro/macro/逐类 P-R-F1。**工具本身不训练**，
故产物与划分无关——**换划分只需重跑 `--eval-only`，不必重跑工具**。

🔴 **两条必须随结果一起报的口径**（否则是误导）：
  1. **覆盖率**：Slither 需要**能编译**源码。编译失败的合约在本脚本里记为 `error`，
     **不计入分母也不计为全零预测**（记成全零等于把「工具跑不了」算成「工具说没漏洞」，
     那是系统性压低 FP、抬高 F1 的偏差）。分母 = 成功分析的合约数，逐类 support 同步缩小。
  2. **映射是人为规定的**：Slither 输出的是检测器名，本仓的七类标签是 MVD-HG 的类目，
     二者**没有官方对照表**。`DETECTOR_TO_CLASS` 是本脚本定义的映射，
     每条都标注 SWC 编号作为依据；`front_running` **无对应检测器**（见下），
     故其 F1 恒为 0——**这是映射的边界，不是模型的发现**。

**`front_running` 的诚实处理**：Slither 0.11.5 的 100 个检测器里没有任何一个覆盖
SWC-114（Transaction Order Dependence）。故本工具在该类上只能恒输出 0。
论文里该格必须写成「该工具不提供此检测项」，**不得**写成「该工具在此类上 F1=0」。

用法（从仓库根目录运行）：
  python scripts/baseline_static_tools.py --limit 5                 # 冒烟（5 个合约）
  python scripts/baseline_static_tools.py                           # 全量（590 图，≈2.5 h CPU）
  python scripts/baseline_static_tools.py --eval-only               # 只出指标（秒级，换划分后重跑）

产物：`eval_results/baseline/slither_<语料>.json`（逐合约原始检测器 + 七维向量 + 覆盖状态）
      `eval_results/baseline/slither_<语料>/<split>_eval.json`（逐划分指标）
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import dataset                                                    # noqa: E402
import metrics                                                    # noqa: E402  只调既有实现，不重写指标
from make_splits import source_path_of                            # noqa: E402  源码定位只有一份实现

CLASS_NAMES = metrics.VULN_NAMES                                  # 顺序锁死，不得重排

OUT_ROOT = REPO / "eval_results" / "baseline"
SOLC_ARTIFACTS = Path.home() / ".solc-select" / "artifacts"

# --------------------------------------------------------------------------- 检测器 → 七类映射
# 每条都给出 SWC 编号作为**可核对的依据**；无 SWC 依据的一律不纳入（宁可漏，不可编）。
DETECTOR_TO_CLASS: dict[str, str] = {
    # ---- reentrancy（SWC-107 Reentrancy）----
    "reentrancy-eth":             "reentrancy",
    "reentrancy-no-eth":          "reentrancy",
    "reentrancy-benign":          "reentrancy",
    "reentrancy-events":          "reentrancy",
    "reentrancy-unlimited-gas":   "reentrancy",
    "reentrancy-balance":         "reentrancy",
    # ---- access_control（SWC-105/106/112/115/124）----
    "suicidal":                   "access_control",   # SWC-106 Unprotected SELFDESTRUCT
    "unprotected-upgrade":        "access_control",   # SWC-105 类：无保护的升级入口
    "arbitrary-send-eth":         "access_control",   # SWC-105 Unprotected Ether Withdrawal
    "arbitrary-send-erc20":       "access_control",   # SWC-105 同上（ERC20 版）
    "arbitrary-send-erc20-permit": "access_control",  # SWC-105 同上（permit 版）
    "controlled-delegatecall":    "access_control",   # SWC-112 Delegatecall to Untrusted Callee
    "tx-origin":                  "access_control",   # SWC-115 Authorization through tx.origin
    "controlled-array-length":    "access_control",   # SWC-124 Write to Arbitrary Storage Location
    # ---- arithmetic ----
    "divide-before-multiply":     "arithmetic",
    "incorrect-exp":              "arithmetic",
    "tautology":                  "arithmetic",
    "tautological-compare":       "arithmetic",
    # ---- dos（SWC-113 DoS with Failed Call）----
    "calls-loop":                 "dos",
    "msg-value-loop":             "dos",
    "delegatecall-loop":          "dos",
    # ---- uncheck（SWC-104 Unchecked Call Return Value）----
    "unchecked-transfer":         "uncheck",
    "unchecked-lowlevel":         "uncheck",
    "unchecked-send":             "uncheck",
    "unused-return":              "uncheck",
    # ---- time_manipulation（SWC-116 / SWC-120）----
    "timestamp":                  "time_manipulation",  # SWC-116 Block values as a proxy for time
    "weak-prng":                  "time_manipulation",  # SWC-120 Weak Sources of Randomness
}

# **严格子集**：只保留 SWC 与类目一一对应、无争议的检测器（敏感性分析用）。
# 被排除的 4 个及理由：`tautology`/`tautological-compare`（语义更接近"逻辑冗余"而非算术）、
# `weak-prng`（严格说属"随机性"，MVD-HG 七类里没有该类，折进 time_manipulation 是**本仓的折法**）、
# `delegatecall-loop`（SWC-113 归属尚有争议）。
STRICT_EXCLUDED = frozenset({"tautology", "tautological-compare", "weak-prng", "delegatecall-loop"})

# Slither 无对应检测器的类（必须随结果一起披露）
NO_DETECTOR_CLASSES = ("front_running",)


def class_index(name: str) -> int:
    return CLASS_NAMES.index(name)


def detectors_to_vector(checks: list[str], *, strict: bool = False) -> list[int]:
    """检测器名列表 → 七维 0/1 向量（`strict=True` 时用严格子集）。"""
    vec = [0] * len(CLASS_NAMES)
    for check in checks:
        if strict and check in STRICT_EXCLUDED:
            continue
        cls = DETECTOR_TO_CLASS.get(check)
        if cls is not None:
            vec[class_index(cls)] = 1
    return vec


# --------------------------------------------------------------------------- solc 选择


def installed_solc_versions() -> list[tuple[tuple[int, int, int], Path]]:
    """扫本机 solc-select 已装版本 → [(版本元组, solc 可执行文件路径)]，升序。"""
    out: list[tuple[tuple[int, int, int], Path]] = []
    if not SOLC_ARTIFACTS.exists():
        return out
    for d in sorted(SOLC_ARTIFACTS.glob("solc-*")):
        m = re.fullmatch(r"solc-(\d+)\.(\d+)\.(\d+)", d.name)
        if not m:
            continue
        exe = d / d.name
        if exe.exists():
            out.append((tuple(int(x) for x in m.groups()), exe))  # type: ignore[arg-type]
    out.sort(key=lambda t: t[0])
    return out


def version_ok(ver: tuple[int, int, int], op: str, want: tuple[int, int, int]) -> bool:
    """`^` / `>=` / `>` / `<=` / `<` / `=` 的语义判定。

    🔴 **`^` 不是"同主版本"**：Solidity 的语义是 `^a.b.c = >=a.b.c <(a+1).0.0`，
    而 `a==0` 时退化为 `<0.(b+1).0`（即**锁次版本**）。
    实测教训：只比大版本时 `^0.5.6` 会被判成"0.8.35 满足"，于是拿 0.8 去编译 0.5 的源码，
    报一堆 pragma 错——**看起来像"工具跑不了"，其实是选错版本**。
    """
    if op == "^":
        if ver < want or ver[0] != want[0]:
            return False
        return True if want[0] != 0 else ver[1] == want[1]
    if op in (">=", "=>"):
        return ver >= want
    if op == ">":
        return ver > want
    if op in ("<=", "=<"):
        return ver <= want
    if op == "<":
        return ver < want
    return ver == want


def parse_pragma(source: Path) -> list[tuple[str, tuple[int, int, int]]]:
    """源码 → [(操作符, 版本)]；支持 `^0.5.7`、`>=0.4.22 <0.6.0`、`0.4.24` 等。"""
    try:
        text = source.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    out: list[tuple[str, tuple[int, int, int]]] = []
    for line in text.splitlines():
        if "pragma solidity" not in line:
            continue
        body = line.split("pragma solidity", 1)[1].split(";", 1)[0]
        for op, maj, minor, patch in re.findall(r"(\^|>=|=>|<=|=<|>|<)?\s*(\d+)\.(\d+)\.(\d+)", body):
            out.append((op or "=", (int(maj), int(minor), int(patch))))
        break
    return out


def pick_solc_candidates(source: Path, versions: list[tuple[tuple[int, int, int], Path]]
                         ) -> list[tuple[Path, str]]:
    """按源码 pragma 给出**候选 solc 序列**（首个最可能成功，失败则依次回退）。

    🔴 **为什么是列表而不是单值**：实测 590 图里 47 个首次编译失败，其中大部分
    **不是"这工具跑不了"、而是"第一次挑的版本不对"**——例如无 pragma 的合约按大纲 4.1.1
    先试最高 0.8.x，而它是 0.4 时代的老代码（`constant` / 无名 fallback 在 0.8 已移除），
    必然失败；此时回退到 0.4.x 就能编过。**单值方案会把这类样本记成"工具不支持"，
    系统性压低覆盖率——而覆盖率正好是要报告的口径之一。**

    顺序： 满足 pragma 的已装版本（从高到低） → 无 pragma 时最高 0.8.x → 其余已装版本（低到高）。
    """
    if not versions:
        return []
    spec = parse_pragma(source)
    out: list[tuple[Path, str]] = []
    seen: set[Path] = set()

    def add(exe: Path, tag: str) -> None:
        if exe not in seen:
            seen.add(exe)
            out.append((exe, tag))

    if spec:
        for ver, exe in reversed(versions):
            if all(version_ok(ver, op, want) for op, want in spec):
                add(exe, ".".join(str(x) for x in ver))
    eights = [v for v in versions if v[0][0] == 0 and v[0][1] == 8]
    if eights:
        add(eights[-1][1], "fallback-0.8")
    for ver, exe in versions:                      # 兜底：低版本优先（老代码更常见）
        add(exe, "fallback-" + ".".join(str(x) for x in ver))
    return out


# --------------------------------------------------------------------------- 单合约分析


def run_slither(source: Path, solc: Path, timeout: int) -> dict:
    """在**源码所在目录**里跑 slither（相对 import 靠 cwd 解析），返回解析结果。

    `--exclude-informational / --exclude-optimization` 只滤掉这两档 Impact；
    Low/Medium/High 全保留——本仓的映射表只用得上其中的一部分，
    原始检测器**全量落盘**，使得将来改映射**不必重跑工具**。
    """
    out_json = source.parent / f".slither_{source.stem}.json"
    cmd = ["slither", source.name, "--solc", str(solc),
           "--exclude-informational", "--exclude-optimization",
           "--json", str(out_json), "--no-fail-pedantic"]
    t0 = time.time()
    try:
        proc = subprocess.run(cmd, cwd=str(source.parent), capture_output=True,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "elapsed": round(time.time() - t0, 1),
                "error": f"超时 {timeout}s"}
    elapsed = round(time.time() - t0, 1)
    if not out_json.exists():
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()
        return {"status": "error", "elapsed": elapsed,
                "error": " | ".join(tail[-3:])[:400] or f"exit={proc.returncode}"}
    try:
        data = json.loads(out_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"status": "error", "elapsed": elapsed, "error": f"JSON 解析失败: {exc}"}
    finally:
        out_json.unlink(missing_ok=True)

    if not data.get("success", False):
        err = str(data.get("error") or "")[:400]
        return {"status": "error", "elapsed": elapsed, "error": err or "slither success=false"}
    checks = [d.get("check") for d in (data.get("results") or {}).get("detectors") or []]
    checks = [c for c in checks if c]
    return {"status": "ok", "elapsed": elapsed, "checks": sorted(set(checks))}


# --------------------------------------------------------------------------- 数据集侧


def corpus_tag(graph_dir: Path) -> str:
    return Path(graph_dir).resolve().parent.name


def bases_of(graph_dir: Path) -> list[str]:
    """图目录里全部 base（升序）——**排序确定**，保证产物 diff 可读。"""
    return sorted(p.name[: -len("_hetero.json")] for p in graph_dir.glob("*_hetero.json"))


def analyze(graph_dir: Path, out_path: Path, limit: int | None, timeout: int,
            only: list[str] | None) -> dict:
    """逐合约跑 slither，**增量落盘**（每 25 个写一次；长跑被腰斩也能续）。"""
    versions = installed_solc_versions()
    if not versions:
        raise SystemExit("🔴 本机没有任何 solc-select 已装版本，无法运行 slither")
    bases = only or bases_of(graph_dir)
    if limit:
        bases = bases[:limit]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    prev: dict = {}
    if out_path.exists():
        prev = json.loads(out_path.read_text(encoding="utf-8")).get("contracts", {})
    done = 0
    results: dict[str, dict] = dict(prev)
    t0 = time.time()
    for i, base in enumerate(bases):
        if base in results and results[base].get("status") == "ok":
            continue
        try:
            src = source_path_of(base, graph_dir)
        except FileNotFoundError as exc:
            results[base] = {"status": "no-source", "error": str(exc)[:300]}
            continue
        # 候选上限：本机装了 101 个 solc，全试一遍对**真正编不过**的合约是 40 s 白工。
        # 8 个已覆盖实测全部可救回的样本（pragma 命中 + 0.8 回退 + 低版本兜底）。
        cands = pick_solc_candidates(src, versions)[:8]
        if not cands:
            results[base] = {"status": "no-solc", "error": "no-solc-installed"}
            continue
        res: dict = {}
        tried: list[str] = []
        for solc, tag in cands:                   # 逐个候选重试，第一个编过的即采用
            res = run_slither(src, solc, timeout)
            tried.append(f"{tag}:{res['status']}")
            if res["status"] == "ok":
                res["solc"] = tag
                break
        res["tried"] = tried
        res["source"] = str(src.relative_to(REPO))
        if res["status"] == "ok":
            res["classes"] = detectors_to_vector(res["checks"])
            res["classes_strict"] = detectors_to_vector(res["checks"], strict=True)
        results[base] = res
        done += 1
        if done % 25 == 0 or i == len(bases) - 1:
            write_run(out_path, graph_dir, results)
            ok = sum(1 for r in results.values() if r.get("status") == "ok")
            print(f"  [{i + 1}/{len(bases)}] ok={ok} "
                  f"({(time.time() - t0) / max(done, 1):.1f} s/合约)", flush=True)
    write_run(out_path, graph_dir, results)
    return results


def write_run(out_path: Path, graph_dir: Path, results: dict) -> None:
    status = Counter(r.get("status") for r in results.values())
    payload = {
        "tool": "slither", "graph_dir": str(graph_dir), "n_contracts": len(results),
        "status_counts": dict(status),
        "detector_to_class": DETECTOR_TO_CLASS,
        "strict_excluded": sorted(STRICT_EXCLUDED),
        "no_detector_classes": list(NO_DETECTOR_CLASSES),
        "warning": ("classes 为七维规则命中向量；front_running 无对应检测器、恒为 0；"
                    "status!=ok 的合约未分析，不得记作全零预测"),
        "contracts": results,
    }
    tmp = out_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(out_path)


# --------------------------------------------------------------------------- 评测


def evaluate(run_path: Path, splits: list[Path], graph_dir: Path, label_file: Path | None,
             key_mode: str | None, out_dir: Path) -> list[dict]:
    """在给定划分的 test（及 val）上算指标。**工具不训练**，故不涉及阈值/早停。

    🔴 分母只有**成功分析**的合约：覆盖率与 support 一起报，缺一即误导（见模块 docstring）。
    """
    payload = json.loads(run_path.read_text(encoding="utf-8"))
    contracts = payload["contracts"]
    index, _ = dataset.build_index(graph_dir, label_file, key_mode)
    out = []
    for sp_path in splits:
        split = json.loads(sp_path.read_text(encoding="utf-8"))
        row: dict = {"split_file": str(sp_path), "seed": split.get("seed")}
        for arm in ("test", "val"):
            rows = [(b, index[b]) for b in split.get(arm, [])
                    if b in index and contracts.get(b, {}).get("status") == "ok"]
            n_all = len(split.get(arm, []))
            arm_out: dict = {"n_in_split": n_all, "n_analyzed": len(rows),
                             "coverage": round(len(rows) / n_all, 4) if n_all else None}
            if rows:
                y = [lab for _, lab in rows]
                for key, field in (("", "classes"), ("strict_", "classes_strict")):
                    p = [contracts[b][field] for b, _ in rows]
                    arm_out[f"{key}micro_f1"] = round(metrics.micro_f1(y, p), 6)
                    arm_out[f"{key}macro_f1"] = round(metrics.macro_f1(y, p), 6)
                    prf = metrics.per_class_prf(y, p)
                    arm_out[f"{key}per_class_f1"] = [round(v, 6) for v in prf["f1"]]
                    arm_out[f"{key}per_class_support"] = prf["support"]
                arm_out["names"] = list(metrics.VULN_NAMES)
            row[arm] = arm_out
        out.append(row)
    out_dir.mkdir(parents=True, exist_ok=True)
    for row in out:
        p = out_dir / f"seed{row['seed']}_eval.json"
        p.write_text(json.dumps(row, ensure_ascii=False, indent=1), encoding="utf-8")
    return out


# --------------------------------------------------------------------------- CLI


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--graph-dir", default="products/alldata/graphs")
    ap.add_argument("--out", default=None, help="原始检测器 JSON（默认 eval_results/baseline/slither_<语料>.json）")
    ap.add_argument("--limit", type=int, default=None, help="只跑前 N 个（冒烟）")
    ap.add_argument("--only", nargs="*", default=None, help="只跑指定 base")
    ap.add_argument("--timeout", type=int, default=300, help="单合约 slither 超时（秒）")
    ap.add_argument("--eval-only", action="store_true", help="跳过工具运行，只出指标")
    ap.add_argument("--split-dir", default="products/alldata/splits")
    ap.add_argument("--split-seeds", type=int, nargs="*", default=[0, 1, 2])
    ap.add_argument("--label-file", default=None)
    ap.add_argument("--label-key-mode", default=None, choices=[None, "project", "stem"])
    args = ap.parse_args()

    graph_dir = REPO / args.graph_dir
    tag = corpus_tag(graph_dir)
    run_path = Path(args.out) if args.out else OUT_ROOT / f"slither_{tag}.json"

    if not args.eval_only:
        print(f"[slither] 语料={tag}  图目录={graph_dir}")
        results = analyze(graph_dir, run_path, args.limit, args.timeout, args.only)
        st = Counter(r.get("status") for r in results.values())
        print(f"[slither] 完成：{dict(st)} → {run_path}")

    if not run_path.exists():
        raise SystemExit(f"🔴 原始产物不存在：{run_path}（先不加 --eval-only 跑一遍）")
    splits = [Path(args.split_dir) / f"split_seed{s}.json" for s in args.split_seeds]
    splits = [s for s in splits if s.exists()]
    rows = evaluate(run_path, splits, graph_dir, args.label_file, args.label_key_mode,
                    OUT_ROOT / f"slither_{tag}")
    for row in rows:
        t = row["test"]
        print(f"[eval] seed{row['seed']} test: 覆盖 {t['n_analyzed']}/{t['n_in_split']}，"
              f"micro-F1={t.get('micro_f1')}（严格映射 {t.get('strict_micro_f1')}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
