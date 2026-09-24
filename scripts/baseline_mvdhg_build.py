#!/usr/bin/env python3
"""MVD-HG 基线（5.3）**离线建图 + 300 维节点特征**：驱动 MVD-HG 原仓库代码。

**为什么要驱动它的代码而不是重实现**：MVD-HG 是数据集自身的方法，其建图（solc AST →
节点 → 挂 CFG/DFG 边）就是它的方法核心。用户的裁定是「忠实复现」——所以我们**调用它的
`read_compile` / `append_*` / `built_vector_dataset`**，只做三件它没做的事：
  ① 把输入目录换成我们的正典 453 个合约；
  ② 用 gensim 4.3 训练词向量（它的 `main.py:204` 是 gensim 3 的 `size=`，在 base 里会 TypeError）；
  ③ 把它的产物折叠成「一个 .sol 一个样本」的 `feat/<base>.pt`。

🔴🔴 **最高危雷区（数据销毁级）**：`read_compile` 在 `config.create_corpus_mode == "create_corpus_txt"`
时会 `os.remove` 掉传入的 AST json，再把只抄到 `======= path =======` 之后的 `w.json` 改名顶上
（`read_compile.py:33-34`）。**我们的 `products/alldata/raw/AST-raw/*.json` 没有那个分隔头**
（它是纯 solc JSON）⇒ 一旦指向它就会被**清空**。故：
  - 本脚本**只**在 `products/alldata/baseline/mvdhg/AST_json/` 下操作，`_assert_under_feature_root`
    在每次 `read_compile` 前硬断言路径前缀；
  - `_import_mvdhg` 后立刻断言 `config.create_corpus_mode == "generate_all"`；
  - `tests/test_baseline_tables.py` 另有一条源码级守卫。

三段流水线（各自可断点续跑，`manifest.json` 是唯一完成判据）：
  `graphs`  read_compile → append_method → append_cfg → append_dfg → `graphs/<base>.pkl`
            （CFG/DFG 是最贵的一步，缓存成 pkl 后**不重跑**；DFG 有 40 s/文件上限）
  `corpus`  收集 BFS 语料 → gensim `Word2Vec(vector_size=300)` → `w2v.model`
  `feat`    载入 pkl → 写四个 json（**复用它的 `create_*_json`**）→ 折叠成 `feat/<base>.pt`

用法（仓库根目录）：
    python scripts/baseline_mvdhg_build.py --limit 3 --dfg-cap 5 --faithful-node-json   # 冒烟
    python scripts/baseline_mvdhg_build.py                                             # 全量 453
"""

from __future__ import annotations

import argparse
import json
import os
import pickle
import re
import sys
import time
import traceback
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402

MVDHG_REPO = Path("/home/saumarez/projects/deep-learning/MVD-HG")
NAME = "mvdhg"

# 由 `_import_mvdhg` 填充
M = None


# --------------------------------------------------------------------------- 外部仓库接入
class _Mods:
    pass


def _import_mvdhg(data_dir: Path, dfg_cap: int) -> _Mods:
    """在 SSM-HG 进程内加载 MVD-HG 的代码。**四步顺序不可换**。

    `config.py:47` 在 **import 期**就 `parse_args()`，所以必须先伪造 `sys.argv`；
    而 `config` 是模块级单例、被所有子模块共享，argv 还原必须等**全部** import 完。
    """
    if not (MVDHG_REPO / "config.py").exists():
        raise SystemExit(f"[mvdhg] 找不到外部仓库：{MVDHG_REPO}")

    # 🔴 **它的 `config.py` 在 import 期会 `os.environ["CUDA_VISIBLE_DEVICES"] = "0,1"`**
    # （写死双卡）。本机只有 **1 块** GPU ⇒ 该变量一旦泄进子进程，torch 的 CUDA 初始化就崩，
    # 并连带触发 mkl-service 的
    # 「MKL_THREADING_LAYER=INTEL is incompatible with libgomp」——报错完全指向 MKL，
    # 与真正的根因毫无关系（实测：`run_baselines.py` 的 preflight 在本进程 import 过它之后，
    # 之后 fork 出的**每一个**训练子进程都 rc=1，而手工跑同一条命令却正常）。
    # 故这里**快照 + 还原整个 os.environ**，不让它的进程级副作用漏出去。
    saved_env = dict(os.environ)
    saved_argv = sys.argv
    sys.argv = ["mvdhg_build", "--run_mode", "contract_classification_train",
                "--train_mode", "contract_classification",
                # ★ 绝不能用 create_corpus_txt：那会让 read_compile 删改 AST 原文件
                "--create_corpus_mode", "generate_all",
                "--data_dir_name", "unused", "--attack_type_name", "multi7"]
    sys.path.insert(0, str(MVDHG_REPO))
    try:
        import config                                                    # noqa: E402
        import utils                                                     # noqa: E402
        import read_compile                                              # noqa: E402
        import append_method_message_by_dict as ammb                     # noqa: E402
        import append_control_flow_information as acfi                   # noqa: E402
        import append_data_flow_information as adfi                      # noqa: E402
        import built_vector_dataset as bvd                                # noqa: E402
    finally:
        sys.argv = saved_argv
        leaked = {k: v for k, v in os.environ.items() if saved_env.get(k) != v}
        os.environ.clear()
        os.environ.update(saved_env)          # ← 撤销它写死的 CUDA_VISIBLE_DEVICES="0,1"
        if leaked:
            print(f"[mvdhg] 已还原外部仓库改写的进程环境变量：{sorted(leaked)}", flush=True)

    # ---- 覆盖它的全局（先例：它自己的 run_generate_edges.py:44-47）----
    config.data_dir_path = str(data_dir)
    config.create_corpus_mode = "generate_all"
    config.train_mode = "contract_classification"
    config.run_mode = "contract_classification_train"
    config.create_data_flow_max_time = int(dfg_cap)
    config.device = __import__("torch").device("cpu")   # 我们不用它的训练循环，防无 GPU 崩

    if config.create_corpus_mode != "generate_all":
        raise SystemExit("[mvdhg] create_corpus_mode 不是 generate_all —— "
                         "这会让 read_compile 删改 AST 原文件，拒绝继续")

    m = _Mods()
    m.config, m.utils = config, utils
    m.read_compile = read_compile.read_compile
    m.append_method = ammb.append_method_message_by_dict
    m.append_cfg = acfi.append_control_flow_information
    m.append_dfg = adfi.append_data_flow_information
    m.bvd = bvd
    return m


def _assert_under_feature_root(p: Path, root: Path) -> None:
    """★ 每次调用 `read_compile` 前硬断言——它是唯一会**删改输入文件**的一步。

    🔴 `root` **必须由调用方传进来**（取自 `ensure_layout` 本次实际用的那个根）。
    它原先在函数体里自己调 `B.feature_root(NAME)`（= 正典根），于是换正典时
    **守卫自己指着另一个根**：497 池的 AST 明明编译进了正典根，它却一路放行
    （2026-09-23 实测踩到，见 `decisions.md` §52.6）。守卫指向的根与本次用的根
    **必须是同一个**，否则它不是守卫，只是装饰。
    """
    rp = Path(p).resolve()
    if root not in rp.parents and rp != root:
        raise SystemExit(
            f"[mvdhg] 拒绝把 {rp} 交给 read_compile —— 它只允许操作 {root} 下的副本。"
            f"（read_compile 在 create_corpus_txt 下会 os.remove 掉输入文件）")


# --------------------------------------------------------------------------- 目录布局
def proj_and_stem(base: str, graph_dir: str) -> tuple[str, str, Path]:
    """base → (proj, stem, 源码路径)。切法与 `make_splits.source_path_of` 一致。"""
    from make_splits import source_path_of
    src = source_path_of(base, graph_dir)
    proj = base.partition("__")[0]
    return proj, src.stem, src


SOLC_ARTIFACTS = Path.home() / ".solc-select" / "artifacts"


def _solc_versions() -> list[str]:
    return sorted((p.name.replace("solc-", "") for p in SOLC_ARTIFACTS.glob("solc-*")),
                  key=lambda v: tuple(int(x) for x in v.split(".")))


def compile_compact_ast(src_sol: Path, dst_json: Path, *, timeout: int = 180) -> str:
    """编译出 MVD-HG 要的 **compact AST**，并复刻 `read_compile` 的裁剪。

    🔴 **为什么不能复用 `products/alldata/raw/AST-raw/`**：那是 legacy 格式
    （`attributes`/`children`），而它的 `create_graph` 要的是 compact 格式
    （`nodeType`/`nodes`）——实测直接喂会 `KeyError: 'declarations'`。

    🔴 **为什么也不能直接喂 solc 的原始 stdout**：`solc <f> --combined-json ast --ast-compact-json`
    输出**两段**——先是 combined-json 信封，再是 `======= <绝对路径> =======` + compact AST。
    它靠**第一趟 `create_corpus_txt`** 把文件就地裁成只有第二段；我们在 `generate_all` 模式下
    跑，所以要自己裁。裁剪逻辑逐字复刻 `read_compile.py:24-37`（同一 pattern、同一 flag 循环）。

    命令逐字复刻 `compile_files.py:23`（含 `--allow-paths` 与**绝对路径**——header 里的路径
    必须与 `read_compile` 按 `AST_json→sol_source` 推出的 pattern 相同）。
    """
    import subprocess

    cand = B.solc_candidates(src_sol)        # 满足 pragma（高→低）→ 最高 0.8.x → 其余全部（低→高）
    if not cand:
        raise RuntimeError(f"没有可用的已装 solc（{SOLC_ARTIFACTS}）")

    last_err = ""
    for ver in cand:                         # 🔴 不设上限：中段第二条 pragma 只有靠全量回退才够得到
        r = subprocess.run(
            ["solc", str(src_sol), "--combined-json", "ast",
             "--allow-paths", str(src_sol), "--ast-compact-json"],
            capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "SOLC_VERSION": ver})
        if r.returncode != 0 or "=======" not in r.stdout:
            last_err = (r.stderr or r.stdout).strip().splitlines()[:1]
            continue
        # ---- 裁剪：只保留 `======= <src_sol> =======` 之后的内容 ----
        pattern = f"======= {src_sol} ======="
        keep, flag = [], False
        for line in r.stdout.splitlines(keepends=True):
            if flag:
                keep.append(line)
                continue
            if pattern in line.replace("\n", ""):
                flag = True
        stripped = "".join(keep)
        try:
            ast = json.loads(stripped)
        except json.JSONDecodeError as e:
            last_err = f"裁剪后不是合法 JSON：{e}"
            continue
        if "nodeType" not in ast:
            last_err = f"裁剪后的根节点没有 nodeType（keys={list(ast)[:6]}）"
            continue
        dst_json.parent.mkdir(parents=True, exist_ok=True)
        dst_json.write_text(stripped, encoding="utf-8")
        return ver
    raise RuntimeError(f"编译失败（试过 {len(cand)} 个候选 {cand}）：{last_err}")


def ensure_layout(bases: list[str], graph_dir: str, *, refresh: bool,
                  suffix: str = "") -> dict:
    """准备 `sol_source/<proj>/<stem>.sol` 与 `AST_json/<proj>/<stem>.json` 两棵树。

    布局**必须字面含** `sol_source` / `AST_json` / `raw` 三段——它的代码里有两个
    `str.replace("AST_json", "raw")` 和一个 `str.replace("/raw/", "/sol_source/")`，
    目录名一改就静默错位。

    🔴 `suffix` = 正典后缀（同 `feature_root`）。**必须与 `main()` 用的是同一个根**，
    否则 AST 会编译进另一个正典的目录（2026-09-23 实测：`_buggy` 池的 44 份 AST
    被写进了正典根，而守卫因为指错根而放行，见 `decisions.md` §52.6）。
    每个 entry 里带 `root`，供 `_assert_under_feature_root` 复核。
    """
    root = B.feature_root(NAME, suffix)
    layout = {}
    n_compiled, n_reused, fails = 0, 0, []
    for base in bases:
        proj, stem, src = proj_and_stem(base, graph_dir)
        dst_dir_sol = root / "sol_source" / proj
        dst_dir_ast = root / "AST_json" / proj
        dst_dir_sol.mkdir(parents=True, exist_ok=True)
        dst_dir_ast.mkdir(parents=True, exist_ok=True)
        dst_sol = dst_dir_sol / f"{stem}.sol"
        dst_ast = dst_dir_ast / f"{stem}.json"
        if refresh or not dst_sol.exists():
            dst_sol.write_bytes(src.read_bytes())
        entry = {"proj": proj, "stem": stem, "sol": dst_sol, "ast": dst_ast, "solc": None,
                 "root": root}
        if dst_ast.exists() and not refresh:
            try:
                json.loads(dst_ast.read_text(encoding="utf-8"))
                n_reused += 1
                layout[base] = entry
                continue
            except json.JSONDecodeError:
                pass                          # 半截产物 → 重编
        try:
            entry["solc"] = compile_compact_ast(dst_sol.resolve(), dst_ast)
            n_compiled += 1
        except Exception as e:                                     # noqa: BLE001
            fails.append((base, f"{type(e).__name__}: {e}"))
        layout[base] = entry
    # 它的节点特征函数读 `config.data_dir_path/contract_labels.json`
    lbl_dst = root / "contract_labels.json"
    if refresh or not lbl_dst.exists():
        lbl_src = REPO / "alldata(readonly)" / "contract_labels.json"
        lbl_dst.write_bytes(lbl_src.read_bytes())
    print(f"[mvdhg] 布局就绪：{len(layout)} 个 base（新编译 {n_compiled}、复用 {n_reused}、"
          f"失败 {len(fails)}）→ {root}", flush=True)
    for b, e in fails[:5]:
        print(f"[mvdhg]   ✗ {b}: {e}", flush=True)
    return layout


# --------------------------------------------------------------------------- 语料
def corpus_sentences_of(m, node_list) -> list[str]:
    """复刻 `built_corpus.built_corpus_bfs` 的**句子构造**（BFS over `childes`）。

    不调它的 `built_corpus_bfs`：那个函数只在 `create_corpus_txt` 下写盘、其余模式**返回 None**
    （`built_corpus.py:52-70`）。这里只借它的两个纯函数（`hump2sub` / `have_attribute`），
    保证语料口径只有一份实现。
    """
    words = []
    queue = [n for n in node_list if n.node_type == "SourceUnit"] or list(node_list[:1])
    seen = set()
    while queue:
        node = queue.pop(0)
        if id(node) in seen:
            continue
        seen.add(id(node))
        words.append(node.node_type)
        tmp = m.bvd.have_attribute(node)
        if tmp and isinstance(tmp[0], (str, int)):
            for s in m.bvd.hump2sub(str(tmp[0])):
                words.append(s)
        queue.extend(node.childes)
    return words


# --------------------------------------------------------------------------- 单文件建图
def build_graphs_one(m, base: str, lay: dict, *, dfg_cap: int) -> dict:
    """read_compile → append_* → 返回节点列表与状态。"""
    t0 = time.time()
    if not lay["ast"].exists():
        return {"status": "compile_error", "error": "compact AST 未生成（solc 编译失败）",
                "seconds": 0.0}
    _assert_under_feature_root(lay["ast"], lay["root"])
    status, err = "ok", ""
    try:
        node_list, node_dict = m.read_compile(now_dir=str(lay["ast"].parent),
                                              ast_json_file_name=lay["ast"].name)
    except Exception as e:                                        # noqa: BLE001
        return {"status": "read_error", "error": f"{type(e).__name__}: {e}",
                "seconds": round(time.time() - t0, 2)}

    try:
        m.append_method(project_node_dict=node_dict, file_name=str(lay["ast"]))
    except Exception as e:                                        # noqa: BLE001
        return {"status": "method_error", "error": f"{type(e).__name__}: {e}",
                "seconds": round(time.time() - t0, 2)}

    try:
        m.append_cfg(project_node_list=node_list, project_node_dict=node_dict,
                     file_name=str(lay["ast"]))
    except Exception as e:                                        # noqa: BLE001
        # CFG 失败不致命：它的 main.py 是直接跳过该文件；我们保留已建的部分并降级记录
        status = "cfg_degraded"
        err = f"{type(e).__name__}: {e}"

    try:
        m.append_dfg(project_node_list=node_list, project_node_dict=node_dict,
                     file_name=str(lay["ast"]))
    except m.utils.CustomError as e:
        # 40 s 上限（append_data_flow_information.py:201）——**这是预期内的降级**，
        # 不是崩溃：保留已经挂上的那部分 DFG 边。
        status = "dfg_timeout" if status == "ok" else status + "+dfg_timeout"
        err = str(e)
    except RecursionError as e:
        status = "dfg_degraded" if status == "ok" else status + "+dfg_degraded"
        err = str(e)

    return {"status": status, "error": err, "seconds": round(time.time() - t0, 2),
            "n_nodes": len(node_list), "sentences": corpus_sentences_of(m, node_list),
            "_node_list": node_list}


# --------------------------------------------------------------------------- 折叠
def collapse(base: str, lay: dict, raw_half: Path) -> dict:
    """四个 json → `feat/<base>.pt`（一个 .sol 一个样本）。

    边类型编号与它 `contract_classification_dataset.py:61-65` **逐字一致**：
    `0=AST（childes）`、`1=CFG（control_childes）`、`2=DFG（data_childes）`，
    拼接顺序 AST→CFG→DFG（`edge_index = cat((ast, cfg, dfg), dim=1)`）。
    """
    import numpy as np
    import torch

    node_json = json.loads(Path(f"{raw_half}_node.json").read_text(encoding="utf-8"))
    nfl = node_json["node_feature_list"]
    if not nfl:
        return {"status": "empty_graph", "n_nodes": 0}
    x = torch.tensor(np.asarray([r["node_feature"] for r in nfl], dtype=np.float32))
    owner_contract = [r.get("owner_contract") for r in nfl]

    def _edges(suffix: str) -> list[list[int]]:
        p = Path(f"{raw_half}_{suffix}.json")
        if not p.exists():
            return []
        rows = json.loads(p.read_text(encoding="utf-8"))
        # 它写盘时节点 id 从 1 起；入模要减 1（`get_*_edge` 同款）
        return [[r["source_node_node_id"] - 1, r["target_node_node_id"] - 1] for r in rows]

    groups = [("ast", 0), ("cfg", 1), ("dfg", 2)]
    ei, et = [], []
    for suffix, t in groups:
        rows = _edges(f"{suffix}_edge")
        if rows:
            ei.extend(rows)
            et.extend([t] * len(rows))
    edge_index = (torch.tensor(ei, dtype=torch.long).T if ei
                  else torch.zeros((2, 0), dtype=torch.long))
    edge_type = torch.tensor(et, dtype=torch.long)
    oov = node_json.get("oov_node_types") or {}
    return {"x": x, "edge_index": edge_index, "edge_type": edge_type,
            "owner_contract": owner_contract,
            "n_nodes": int(x.shape[0]), "n_ast": sum(1 for t in et if t == 0),
            "n_cfg": sum(1 for t in et if t == 1), "n_dfg": sum(1 for t in et if t == 2),
            "n_oov_nodes": int(sum(oov.values())), "oov_node_types": oov}


def write_node_feature_cached(m, node_list, raw_half: Path, id_mapping: dict,
                              w2v, label_map: dict) -> dict:
    """与 `bvd.create_node_feature_json_by_contract_classification` **逐字等价**，
    只把「每个节点重读一次 contract_labels.json」改成读一次缓存。

    🔴 原实现在**逐节点循环内** `open()+json.load()`（`built_vector_dataset.py:88-90`）：
    453 文件 × ~150 节点 × 2002 条标签 ≈ 68000 次解析 272 KB JSON ⇒ 约 18 GB 无效 I/O。
    语义（匹配串、`targets` 取值、缺标签补 0、`contract_buggy_record` 首次命中优先）逐字保留，
    并由 `--faithful-node-json` 与原实现**对拍**。
    """
    out = []
    buggy = {}
    oov: dict[str, int] = {}
    for node in node_list:
        # 🔴 **OOV 兜底（本实现新增，原实现没有）**：原实现把 w2v 拟合在**全体语料**上，
        # 我们只用 **train 划分**拟合（避免泄漏）⇒ 只在非 train 合约里出现的 AST 节点类型
        # 会缺词，`w2v[node_type]` 直接 `KeyError` 崩掉整轮建图（实测：`IdentifierPath`
        # 是 Solidity ≥0.6 才有的类型，train 里恰好没有）。
        # 兜底 = 该类型记**零向量**并计数上报（与本仓 `dataset._cb_rows` 的
        # 「缺行零向量 + 计数上报」同一口径），绝不静默：计数写进 manifest 与 feat 元数据。
        if node.node_type in w2v:
            feat = w2v[node.node_type]
        else:
            import numpy as np
            feat = np.zeros(int(w2v.vector_size), dtype=np.float32)
            oov[node.node_type] = oov.get(node.node_type, 0) + 1
        tmp = m.bvd.have_attribute(node)
        if tmp and isinstance(tmp[0], (str, int)):
            for s in m.bvd.hump2sub(str(tmp[0])):
                if s in w2v:
                    feat = feat + w2v[s]
        of = node.owner_file
        key = f"{of[of.rfind('/') + 1: of.rfind('.')]}-{node.owner_contract}{of[of.rfind('.'):]}"
        obj = {"node_id": id_mapping[node.node_id], "nodeType": node.node_type,
               "owner_file": node.owner_file, "owner_contract": node.owner_contract,
               "owner_function": node.owner_function, "owner_line": node.owner_line,
               "node_feature": feat.tolist()}
        if key in label_map:
            obj["contract_label"] = label_map[key]
            buggy.setdefault(node.owner_contract, label_map[key])
        else:
            obj["contract_label"] = 0
        out.append(obj)
    data = {"node_feature_list": out, "contract_buggy_record": buggy,
            "oov_node_types": oov, "n_oov_nodes": int(sum(oov.values()))}
    Path(f"{raw_half}_node.json").write_text(
        json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return data


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


TERMINAL = {"ok", "dfg_timeout", "dfg_degraded", "cfg_degraded", "compile_error", "pickle_error",
            "cfg_degraded+dfg_timeout", "cfg_degraded+dfg_degraded",
            "empty_graph", "read_error", "method_error"}


# --------------------------------------------------------------------------- 主流程
def parse_args():
    p = argparse.ArgumentParser(description="MVD-HG 基线离线建图（驱动原仓库代码）。")
    p.add_argument("--graph-dir", default=str(REPO / "products/alldata/graphs_ft/ss0"))
    p.add_argument("--split-dir", default=str(REPO / "products/alldata/splits"))
    p.add_argument("--feature-suffix", default="",
                   help="离线特征根后缀：`\"\"`=§37 正典（池 453），`_buggy`=新正典（池 497）。"
                        "🔴 必须与 --graph-dir/--split-dir 同时换（见 baseline_common.LAYOUTS）。")
    p.add_argument("--split-seed", type=int, default=None)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--label-file", default=None)
    p.add_argument("--label-key-mode", choices=["project", "stem"], default=None)
    p.add_argument("--dfg-cap", type=int, default=40, help="DFG 单文件时间上限（秒），它的默认 40。")
    p.add_argument("--limit", type=int, default=0, help="小样：只建前 N 个 base。")
    p.add_argument("--refresh-layout", action="store_true", help="重建时重拷 .sol/AST 副本。")
    p.add_argument("--force", action="store_true", help="忽略 manifest，全部重建。")
    p.add_argument("--faithful-node-json", action="store_true",
                   help="冒烟专用：对前 N 个文件同时跑原实现并对拍（证明缓存版语义等价）。")
    p.add_argument("--keep-raw", action="store_true",
                   help="保留 raw/*.json 与 graphs/*.pkl（默认折叠后删除，省 ~1 GB）。")
    return p.parse_args()


def main() -> int:
    global M
    args = parse_args()
    split_seed = B.resolve_split_seed(args)
    B.check_layout(args, NAME)
    root = B.feature_root(NAME, args.feature_suffix)
    (root / "graphs").mkdir(exist_ok=True)
    (root / "feat").mkdir(exist_ok=True)
    (root / "raw").mkdir(exist_ok=True)

    split = B.load_split(args.split_dir, split_seed)
    index, _ = B.load_index(args.graph_dir, args.label_file, args.label_key_mode)
    # 建图对**全池**做（train+val+test），因为离线特征与划分无关；
    # 但词向量语料**只用 train**（原实现用全体，对我们是泄漏）。
    pool = list(split["train"]) + list(split["val"]) + list(split["test"])
    pool = [b for b in pool if b in index]
    if args.limit:
        pool = pool[:args.limit]
    print(f"[mvdhg] 池 {len(pool)} 个 base（split_seed={split_seed}）", flush=True)

    layout = ensure_layout(pool, args.graph_dir, refresh=args.refresh_layout,
                           suffix=args.feature_suffix)
    M = _import_mvdhg(root, args.dfg_cap)
    print(f"[mvdhg] 外部仓库已接入：{MVDHG_REPO}", flush=True)

    # ---- 阶段 1：建图（最贵，缓存成 pkl）----
    man = {} if args.force else load_manifest(root)
    t0 = time.time()
    n_done = n_skip = 0
    corpus: list[list[str]] = []
    for i, base in enumerate(pool, 1):
        rec = man.get(base)
        gpath = root / "graphs" / f"{base}.pkl"
        if rec and rec.get("status") in TERMINAL and gpath.exists():
            n_skip += 1
            with open(gpath, "rb") as fh:
                corpus.append(pickle.load(fh)["sentences"])
            continue
        try:
            out = build_graphs_one(M, base, layout[base], dfg_cap=args.dfg_cap)
        except Exception as e:                                     # noqa: BLE001
            out = {"status": "read_error", "error": f"{type(e).__name__}: {e}",
                   "seconds": 0.0, "trace": traceback.format_exc()[-400:]}
        # 🔴 corpus 必须与 pool **逐个对齐**（后面按 zip(pool, corpus) 取 train 语料）；
        # 建图失败的文件也要占位，否则语料会整体错位到别的 base 上。
        sentences = out.pop("sentences", [])
        if "_node_list" in out:
            try:
                tmp = gpath.with_suffix(".pkl.tmp")
                with open(tmp, "wb") as fh:
                    pickle.dump({"node_list": out.pop("_node_list"), "sentences": sentences}, fh)
                tmp.replace(gpath)
            except Exception as e:                                 # noqa: BLE001
                # 不静默：该文件记成失败，其余继续（一个坏文件不该毁掉 452 个）
                out = {"status": f"pickle_error", "error": f"{type(e).__name__}: {e}"}
        corpus.append(sentences)
        out.pop("trace", None)
        assert len(corpus) == i, "语料与池的对齐被破坏"
        append_manifest(root, base, out)
        n_done += 1
        if i % 20 == 0 or i == len(pool):
            print(f"[mvdhg] graphs {i}/{len(pool)}  新建 {n_done} 跳过 {n_skip}  "
                  f"耗时 {time.time() - t0:.0f}s", flush=True)

    # ---- 阶段 2：词向量（语料**只用 train 划分**）----
    train_set = set(split["train"])
    train_corpus = [s for b, s in zip(pool, corpus) if b in train_set and s]
    if not train_corpus and not args.limit:
        raise SystemExit("[mvdhg] train 语料为空——检查 split_dir/split_seed")
    from gensim.models import Word2Vec
    w2v_path = root / "w2v.model"
    if w2v_path.exists() and not args.force and not args.limit:
        w2v = Word2Vec.load(str(w2v_path)).wv
        print(f"[mvdhg] 复用词向量 {w2v_path}", flush=True)
    else:
        print(f"[mvdhg] 训练词向量：{len(train_corpus)} 句（仅 train 划分）", flush=True)
        model = Word2Vec(sentences=train_corpus, vector_size=300, sg=1, min_count=1,
                         workers=16, seed=args.seed)
        model.save(str(w2v_path))
        w2v = model.wv

    # ---- 阶段 3：折叠成 feat/<base>.pt ----
    raw_root = root / "raw"
    n_feat = 0
    for base in pool:
        gpath = root / "graphs" / f"{base}.pkl"
        fpath = root / "feat" / f"{base}.pt"
        if fpath.exists() and not args.force:
            continue
        if not gpath.exists():
            continue
        with open(gpath, "rb") as fh:
            node_list = pickle.load(fh)["node_list"]
        lay = layout[base]
        raw_dir = raw_root / lay["proj"]
        raw_dir.mkdir(parents=True, exist_ok=True)
        raw_half = raw_dir / lay["stem"]
        node_list.sort(key=lambda o: o.node_id)
        id_mapping = {n.node_id: i + 1 for i, n in enumerate(node_list)}
        label_map = _label_map(root)
        data = write_node_feature_cached(M, node_list, raw_half, id_mapping, w2v, label_map)
        _write_edges(M, node_list, raw_half, id_mapping)
        feat = collapse(base, lay, raw_half)
        import torch
        torch.save(feat, fpath)
        n_feat += 1
        # 对拍必须在删 raw 之前（它要读回 _node.json 与原实现比对）
        if args.faithful_node_json and n_feat >= 3:
            _parity_check(M, layout[base], node_list, raw_half, w2v, data)
            args.faithful_node_json = False
        if not args.keep_raw:
            for suffix in ("node", "ast_edge", "cfg_edge", "dfg_edge"):
                Path(f"{raw_half}_{suffix}.json").unlink(missing_ok=True)
            gpath.unlink(missing_ok=True)

    # ---- 折叠 manifest ----
    man = load_manifest(root)
    (root / "manifest.json").write_text(json.dumps(man, ensure_ascii=False, indent=1),
                                        encoding="utf-8")
    n_feat_total = len(list((root / "feat").glob("*.pt")))
    print(f"[mvdhg] 完成：manifest {len(man)} 条，feat/*.pt {n_feat_total} 个，"
          f"本次新建 {n_feat}，总耗时 {time.time() - t0:.0f}s", flush=True)
    return 0


def _label_map(root: Path) -> dict:
    """`contract_name → targets`（首次命中优先，与原实现的 `break` 语义一致）。"""
    p = root / "contract_labels.json"
    out = {}
    for entry in json.loads(p.read_text(encoding="utf-8")):
        out.setdefault(entry["contract_name"], entry["targets"])
    return out


def _write_edges(m, node_list, raw_half: Path, id_mapping: dict) -> None:
    """复用它的三个边写出函数（序列化口径只有一份实现）。"""
    m.bvd.create_ast_edge_json(node_list, str(raw_half), id_mapping)
    m.bvd.create_cfg_edge_json(node_list, str(raw_half), id_mapping)
    m.bvd.create_dfg_edge_json(node_list, str(raw_half), id_mapping)


def _parity_check(m, lay: dict, node_list, raw_half: Path, w2v, ours: dict) -> None:
    """把**原实现**跑一遍，与缓存版逐字段对拍（证明语义等价，而不是「看起来一样」）。

    原实现把路径里的 `/raw/` 换成 `/sol_source/` 去找源码，所以**不能**用改名后的临时路径
    喂它——必须占用同一个 `raw_half`：先备份缓存版的结果，让原实现覆写，比完再写回缓存版。
    """
    node_json = Path(f"{raw_half}_node.json")
    node_json.unlink(missing_ok=True)
    m.bvd.create_node_feature_json_by_contract_classification(
        list(node_list), str(raw_half), {n.node_id: i + 1 for i, n in enumerate(node_list)}, w2v)
    theirs = json.loads(node_json.read_text(encoding="utf-8"))
    node_json.write_text(json.dumps(ours, ensure_ascii=False), encoding="utf-8")
    a, b = ours["node_feature_list"], theirs["node_feature_list"]
    assert len(a) == len(b), f"节点数不一致 {len(a)} vs {len(b)}"
    for i, (x, y) in enumerate(zip(a, b)):
        assert x["node_id"] == y["node_id"] and x["nodeType"] == y["nodeType"], f"第 {i} 个节点元信息不同"
        assert x["contract_label"] == y["contract_label"], f"第 {i} 个节点标签不同"
        if x["node_feature"] != y["node_feature"]:
            d = max(abs(p - q) for p, q in zip(x["node_feature"], y["node_feature"]))
            raise AssertionError(f"第 {i} 个节点特征不同（最大差 {d}）")
    assert ours["contract_buggy_record"] == theirs["contract_buggy_record"], "contract_buggy_record 不同"
    print(f"[mvdhg] ✅ 对拍通过：缓存版与原实现的 node_feature_list 逐字段相同"
          f"（{len(a)} 个节点）", flush=True)


def _run_in_big_stack(fn) -> int:
    """在**大栈线程**里跑主流程。

    🔴 必须这样：它把每个节点的整棵 AST 子树挂在 `node.attribute` 上，所以
    `pickle.dump(node_list)` 的递归深度随 AST 深度走，主线程默认 8 MB 栈会
    `RecursionError: maximum recursion depth exceeded while pickling an object`（实测踩到）。
    `threading.stack_size` 只影响**新建线程**，主线程栈由 OS 固定，改不了 ⇒ 只能换线程跑。
    """
    import threading
    sys.setrecursionlimit(300000)
    box: dict = {}

    def _target():
        try:
            box["rc"] = fn()
        except BaseException as e:                                 # noqa: BLE001
            box["exc"] = e

    threading.stack_size(512 * 1024 * 1024)
    t = threading.Thread(target=_target)
    t.start()
    t.join()
    if "exc" in box:
        raise box["exc"]
    return int(box.get("rc", 0))


if __name__ == "__main__":
    raise SystemExit(_run_in_big_stack(main))
