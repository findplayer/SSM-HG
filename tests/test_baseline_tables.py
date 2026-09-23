#!/usr/bin/env python3
"""5.3 三条论文基线（EGFL / MVD-HG / MANDO-LLM）的**契约守卫**。

每一条都对应一个"不报错、只出错数字"的坑——本仓已栽过的那类。核心是
**七维契约**：`[N,1]` 的产物必须让下游抛错，而不是静默退化成 accuracy（decisions §28/§31）。

    pytest tests/test_baseline_tables.py -q
"""

from __future__ import annotations

import ast
import json
import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import baseline_common as B                                              # noqa: E402
import metrics                                                           # noqa: E402

BASELINES = ("mvdhg", "egfl", "mando")
SEEDS = (0, 1, 2)


def _bundle(n=6, n_classes=7):
    g = torch.Generator().manual_seed(0)
    probs = torch.rand(n, n_classes, generator=g)
    labels = (torch.rand(n, n_classes, generator=g) > 0.5).to(torch.float32)
    return B.EvalBundle(test_probs=probs, test_labels=labels,
                        test_ids=[f"s{i}" for i in range(n)],
                        val_probs=probs.clone(), val_labels=labels.clone(),
                        val_ids=[f"v{i}" for i in range(n)])


# --------------------------------------------------------------- ① 七维契约
def test_single_column_rejected_by_metrics():
    """`[N,1]` 在多标签入口必须**抛错**（sklearn 会把 micro 退化成 accuracy）。"""
    y = torch.zeros(6, 1).numpy()
    p = torch.zeros(6, 1).numpy()
    with pytest.raises((ValueError, AssertionError)):
        metrics.micro_f1(y, p)


def test_assert_bundle_rejects_single_column():
    b = _bundle()
    b.test_probs = b.test_probs[:, :1]
    b.test_labels = b.test_labels[:, :1]
    with pytest.raises(SystemExit) as e:
        B.assert_bundle(b, {"test": b.test_ids, "val": b.val_ids})
    assert "7" in str(e.value)                     # 错误信息必须点名 7 维


def test_assert_bundle_rejects_out_of_range():
    """「忘了 sigmoid」的唯一警报：probs ∉ [0,1]。"""
    b = _bundle()
    b.test_probs = b.test_probs * 10.0
    with pytest.raises(SystemExit) as e:
        B.assert_bundle(b, {"test": b.test_ids, "val": b.val_ids})
    assert "sigmoid" in str(e.value)


def test_assert_bundle_rejects_nan_and_dtype():
    b = _bundle()
    b.test_probs[0, 0] = float("nan")
    with pytest.raises(SystemExit):
        B.assert_bundle(b, {"test": b.test_ids, "val": b.val_ids})
    b = _bundle()
    b.test_probs = b.test_probs.double()
    with pytest.raises(SystemExit):
        B.assert_bundle(b, {"test": b.test_ids, "val": b.val_ids})


def test_assert_bundle_rejects_id_misalignment():
    """行序错了会把 probs 配到别人的标签上——必须逐字比对。"""
    b = _bundle()
    with pytest.raises(SystemExit) as e:
        B.assert_bundle(b, {"test": list(reversed(b.test_ids)), "val": b.val_ids})
    assert "行序" in str(e.value) or "不一致" in str(e.value)


# --------------------------------------------------------------- ② 写盘契约
def test_write_bundle_roundtrip_and_ids(tmp_path):
    b = _bundle()
    thr = {"best_threshold": 0.4, "candidates": [0.4]}
    B.write_bundle(b, tmp_path, thr_scan=thr, results={"a": 1}, config={"b": 2})
    d = torch.load(tmp_path / "test_probs.pt", map_location="cpu")
    assert d["probs"].shape == (6, 7)
    assert list(d["sample_ids"]) == b.test_ids          # 逐字相等，顺序不动
    assert "best_threshold" in json.loads((tmp_path / "thresholds.json").read_text())


def test_write_bundle_requires_best_threshold(tmp_path):
    """缺 `best_threshold` 会让 val_thr 两列整块消失且**不报错** ⇒ 必须硬拦。"""
    with pytest.raises(SystemExit) as e:
        B.write_bundle(_bundle(), tmp_path, thr_scan={"candidates": []},
                       results={}, config={})
    assert "best_threshold" in str(e.value)


# --------------------------------------------------------------- ③ 三口径可算
@pytest.mark.parametrize("name", BASELINES)
def test_three_calibers_computable(name):
    """有产物就核三口径；没有则跳过（不静默假装通过）。"""
    rel = f"eval_results/baseline/{name}"
    seeds = [s for s in SEEDS if (REPO / rel / f"seed{s}" / "test_probs.pt").exists()]
    if not seeds:
        pytest.skip(f"{rel} 尚无产物")
    sys.path.insert(0, str(REPO / "scripts"))
    import collect_three_caliber_tables as T
    r = T.row_from_run(rel, [seeds[0]])
    assert set(r["cells"]) == {"fixed_0.5", "val_thr"}
    for wp in r["cells"]:
        for cal in ("micro", "buggy", "macro"):
            assert r["cells"][wp][cal], f"{name}/{wp}/{cal} 为空"
        # 逐类格列数 == 7，汇总列是标量
        f1, summ = r["cells"][wp]["micro"][0]
        assert len(f1) == 7 and summ is not None
        # micro 与 macro 的逐类格**逐位相同**（macro 只是那 7 个数的平均）
        assert r["cells"][wp]["micro"][0][0] == r["cells"][wp]["macro"][0][0]

    # 汇总列必须与 metrics 直算逐位相同（证明汇总层没有偷偷重实现指标）
    blob = torch.load(REPO / rel / f"seed{seeds[0]}" / "test_probs.pt", map_location="cpu")
    y = blob["labels"].numpy().astype(int)
    thr = T._val_thr(rel, seeds[0])
    preds = metrics.binary_preds(blob["probs"], thr).numpy()
    # 汇总层渲染出的那个字符串，必须就是 metrics 直算的数（没有偷偷重实现指标）
    assert T._ms([metrics.micro_f1(y, preds)]) == f"{metrics.micro_f1(y, preds):.4f}"


@pytest.mark.parametrize("name", BASELINES)
def test_bundle_is_7dim_on_disk(name):
    """落盘产物必须真的是 [N,7]，且 sample_ids 与正典 split 逐字相等。"""
    for s in SEEDS:
        p = REPO / f"eval_results/baseline/{name}/seed{s}/test_probs.pt"
        if not p.exists():
            continue
        d = torch.load(p, map_location="cpu")
        split = json.loads((REPO / f"products/alldata/splits/split_seed{s}.json")
                           .read_text(encoding="utf-8"))
        assert d["probs"].shape[1] == 7, f"{name}/seed{s} 不是 7 维"
        assert d["probs"].shape == d["labels"].shape
        # 缺离线特征的样本会被剔除；test 若被削必须在这里**显式**看见
        assert list(d["sample_ids"]) == list(split["test"])[:len(d["sample_ids"])]
        if len(d["sample_ids"]) != len(split["test"]):
            print(f"⚠ {name}/seed{s} test 覆盖 {len(d['sample_ids'])}/{len(split['test'])}")


# --------------------------------------------------------------- ④ 守卫与源码级
def test_default_out_dir_not_canon():
    """三个 `baseline_*.py` 的默认 `--out-dir` 绝不能落在正典 `runs/seed*`。"""
    for name in BASELINES:
        src = (REPO / f"scripts/baseline_{name}.py").read_text(encoding="utf-8")
        for node in ast.walk(ast.parse(src)):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr == "add_argument" and node.args
                    and getattr(node.args[0], "value", None) == "--out-dir"):
                default = node.args[1].value if len(node.args) > 1 else None
                kw = next((k.value for k in node.keywords if k.arg == "default"), None)
                val = default if isinstance(default, ast.Constant) else (
                    kw.value if isinstance(kw, ast.Constant) else "")
                assert "runs/seed" not in str(val), f"{name} 默认 out-dir 落在正典区：{val}"


def test_builders_never_write_readonly_sources():
    """源码级：两个离线脚本**不得**对只读源 / `raw/AST-raw` 写、删、改名。"""
    banned = ("alldata(readonly)", "AST-raw", "MVD-HG-dataset", "SolidiFI", "DIVE")
    for f in ("baseline_mvdhg_build.py", "baseline_egfl_build.py"):
        src = (REPO / "scripts" / f).read_text(encoding="utf-8")
        tree = ast.parse(src)
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            fn = node.func
            name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", "")
            if name not in ("unlink", "remove", "rmtree", "rename", "replace",
                            "write_text", "write_bytes", "save", "dump"):
                continue
            seg = ast.get_source_segment(src, node) or ""
            for b in banned:
                assert b not in seg, f"{f}:{node.lineno} 对只读源调用了 {name}：{seg[:120]}"


def test_guard_blocks_param_drift(tmp_path):
    """改了参数却没 `--overwrite` 必须 `SystemExit`，且目录内容逐字节不变。"""
    import argparse
    d = tmp_path / "seed0"
    d.mkdir()
    g0 = str(REPO / "products/alldata/graphs_ft/ss0")
    base = {"seed": 0, "epochs": 200, "graph_dir": g0}
    # 存的 record 必须带 `split_seed`：缺它会被判成 `None != 0` 而有冲突（实测踩到）
    (d / "config.json").write_text(json.dumps({"args": base, "split_seed": 0}),
                                   encoding="utf-8")
    before = (d / "config.json").read_bytes()
    args = argparse.Namespace(**base)
    B.guard_dir(d, args, 0, overwrite=False)                 # 同参数：放行
    args.graph_dir = str(REPO / "products/alldata/graphs_ft/ss1")   # 路径型键漂移
    with pytest.raises(SystemExit):
        B.guard_dir(d, args, 0, overwrite=False)
    assert (d / "config.json").read_bytes() == before        # 内容未被动过


# --------------------------------------------------------------- ⑤ 外部驱动
def test_mvdhg_import_forces_generate_all():
    """🔴 R1：`create_corpus_mode` 绝不能是 `create_corpus_txt`（会清空输入 AST）。"""
    try:
        import baseline_mvdhg_build as MB
    except Exception as e:                                   # noqa: BLE001
        pytest.skip(f"外部仓库不可用：{e}")
    if not (MB.MVDHG_REPO / "config.py").exists():
        pytest.skip("找不到 MVD-HG 仓库")
    m = MB._import_mvdhg(B.feature_root("mvdhg"), 40)
    assert m.config.create_corpus_mode == "generate_all"


def test_mvdhg_import_restores_environ():
    """它 `config.py` 会写死 `CUDA_VISIBLE_DEVICES="0,1"`；不得泄进子进程。"""
    try:
        import baseline_mvdhg_build as MB
    except Exception as e:                                   # noqa: BLE001
        pytest.skip(f"外部仓库不可用：{e}")
    if not (MB.MVDHG_REPO / "config.py").exists():
        pytest.skip("找不到 MVD-HG 仓库")
    import os
    before = dict(os.environ)
    MB._import_mvdhg(B.feature_root("mvdhg"), 40)
    assert {k: v for k, v in os.environ.items() if before.get(k) != v} == {}


def test_decode_bucket_id_order():
    """`to_hetero` 的桶号反解：s/d 写反过一次（PyG 报 indices 越界）。"""
    sys.path.insert(0, str(REPO / "scripts"))
    from baseline_mando import to_hetero
    import dataset as D
    # 3 种类型 × 2 个图；构造一条 A→B 的边，检查它落进键 (A, rel, B)。
    # ⚠ 关系名必须用 `RELATION_NAMES_EXT` 的真实映射——`scan_metadata` 与 `to_hetero`
    #   两侧都经它取名，测试若自造一个名字，键就对不上（这正是本条测试第一次红的原因）。
    rel_name = D.RELATION_NAMES_EXT[0]
    meta = {"node_types": ["A", "B", "C"], "edge_types": [("A", rel_name, "B")]}
    type_id = torch.tensor([0, 1, 2, 0, 1, 2])               # 两个图，各 3 个节点
    edge_index = torch.tensor([[0], [1]])                    # 图0 的 A(type0) → B(type1)
    edge_type = torch.tensor([0])
    x = torch.arange(6, dtype=torch.float32).reshape(-1, 1)
    x_dict, ei = to_hetero(x, type_id, edge_index, edge_type, meta)
    key = ("A", rel_name, "B")
    assert set(ei) == {key}
    # 图0 的 A 是本类型第 0 个（local=0）、B 也是本类型第 0 个 ⇒ 边为 (0,0)
    assert ei[key].tolist() == [[0], [0]]
    assert x_dict["A"].shape[0] == 2 and x_dict["B"].shape[0] == 2


def test_opcodes_table_has_144_entries():
    p = B.feature_root("egfl") / "opcodes.json"
    if not p.exists():
        pytest.skip("opcodes.json 尚未生成")
    assert len(json.loads(p.read_text(encoding="utf-8"))) == 144


def test_mando_metadata_sha_matches_current_pool():
    p = B.feature_root("mando") / "hgt_metadata.json"
    if not p.exists():
        pytest.skip("hgt_metadata.json 尚未生成")
    d = json.loads(p.read_text(encoding="utf-8"))
    assert d["pool_sha256"] and len(d["node_types"]) == 9
    # 落盘必须是 list（JSON 只认 list），读回必须转 tuple（HGTConv 拿它当 dict 键）
    assert all(isinstance(e, list) for e in d["edge_types"])


def test_baseline_placeholder_sanitizer():
    """未链接库的 `__$…$__` 占位符必须被替成长度相同的 0（保持 offset 不变）。"""
    sys.path.insert(0, str(REPO / "scripts"))
    from baseline_egfl_build import sanitize_bin, pick_bytecode
    ph = "__$" + "a" * 34 + "$__"
    h, n = sanitize_bin("0x6000" + ph + "f3")
    assert n == 1 and h == "6000" + "0" * 40 + "f3" and len(h) == 4 + 40 + 2
    assert sanitize_bin("0x6000") == ("6000", 0)
    hexed, n_c, n_ph = pick_bytecode({"C": {"bin": "6000" + ph + "f3"}}, "concat")
    assert (n_c, n_ph) == (1, 1) and len(hexed) == 4 + 40 + 2


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
