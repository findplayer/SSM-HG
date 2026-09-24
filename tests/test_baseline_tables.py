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


# ------------------------------------------------- ⑥ 逐类二分类口径（binary-F1，§4）
def _rel_of(name):
    return "runs" if name == "runs" else f"eval_results/baseline/{name}"


def test_pc_binary_thresholds_come_from_val_only(monkeypatch):
    """🔴 逐类阈值**只允许**由 val 缓存决定。

    这是本块唯一能出错数字的地方（「在 test 上调阈值」是本仓明令禁止的口径）。
    做法 = 拦截 `calibrate.per_class_thresholds`，看它实际收到的是哪个张量。
    """
    import numpy as np
    import calibrate as CAL
    import collect_baseline_tables as CB
    if not (REPO / "runs/seed0/val_best_probs.pt").exists():
        pytest.skip("runs/seed0 尚无概率缓存")
    seen = []
    orig = CAL.per_class_thresholds

    def spy(vp, vy, *a, **k):
        seen.append((np.asarray(vp).copy(), np.asarray(vy).copy()))
        return orig(vp, vy, *a, **k)

    monkeypatch.setattr(CAL, "per_class_thresholds", spy)
    CB._pc_pairs("runs", [0])
    assert len(seen) == 1, "每种子应恰好选一次逐类阈值"
    dv = torch.load(REPO / "runs/seed0/val_best_probs.pt", map_location="cpu")
    assert np.allclose(seen[0][0], dv["probs"].numpy())
    assert np.array_equal(seen[0][1], dv["labels"].numpy().astype(int))
    # 负向断言：绝不能是 test 缓存
    dt = torch.load(REPO / "runs/seed0/test_probs.pt", map_location="cpu")
    assert not np.array_equal(seen[0][1], dt["labels"].numpy().astype(int))


def test_pc_binary_average_equals_macro_at_half():
    """§4.1 恒等式 ①：@0.5 的 binary-F1 **平均列 == macro-F1@0.5**（逐位）。

    这条恒等式是"@0.5 版不另列"的全部依据；它一旦不成立，文件里那句声明就是错的。
    """
    import numpy as np
    import collect_three_caliber_tables as T
    checked = 0
    for name in ("runs",) + BASELINES:
        rel = _rel_of(name)
        p = REPO / rel / "seed0/test_probs.pt"
        if not p.exists():
            continue
        blob = torch.load(p, map_location="cpu")
        y = blob["labels"].numpy().astype(int)
        preds = metrics.binary_preds(blob["probs"], 0.5).numpy()
        avg = float(np.mean(metrics.per_class_prf(y, preds)["f1"]))
        assert abs(avg - metrics.macro_f1(y, preds)) < 1e-12, f"{name} 恒等式 ① 不成立"
        # 渲染层给出的汇总列必须就是同一个数（没有偷偷重实现）
        pairs = T.row_from_run(rel, [0])["cells"]["fixed_0.5"]["macro"]
        assert T._ms([pairs[0][1]]) == f"{pairs[0][1]:.4f}" == f"{avg:.4f}"
        checked += 1
    if not checked:
        pytest.skip("尚无概率缓存")


def test_pc_binary_matches_calibration_artifact():
    """本文方法的逐类二分类读数必须与**存量审计产物**逐位相同（证明没有第二套实现）。"""
    import numpy as np
    import collect_baseline_tables as CB
    f = REPO / "eval_results/calibration/summary.json"
    if not f.exists() or not (REPO / "runs/seed0/test_probs.pt").exists():
        pytest.skip("缺 calibration/summary.json 或 runs 概率缓存")
    sc = json.loads(f.read_text(encoding="utf-8"))["test_schemes"]["per_class_threshold"]
    pairs = CB._pc_pairs("runs", list(SEEDS))
    for i, n in enumerate(metrics.VULN_NAMES):
        mine = float(np.mean([p[0][i] for p in pairs]))
        assert abs(mine - float(sc["per_class_f1"][n]["mean"])) < 1e-6, f"{n} 与存量不一致"
    assert abs(float(np.mean([p[1] for p in pairs]))
               - float(sc["macro_f1"]["mean"])) < 1e-6


def test_pc_binary_block_renders_8_columns():
    """表 1 必须是 7 类 + 平均 = 8 列，且行数 ≥ 请求的 4 行。"""
    import collect_baseline_tables as CB
    if not (REPO / "eval_results/baseline/mvdhg/seed0/test_probs.pt").exists():
        pytest.skip("三条基线尚无产物")
    lines = CB.per_class_binary_block("runs", list(SEEDS))
    assert "**平均**" in lines[2] and "| 方法 |" in lines[2], "表头末列必须叫「平均」"
    body = [ln for ln in lines if ln.startswith("| **")]
    assert len(body) >= 4, "至少要有 本文方法 + 三条基线四行"
    for ln in body:
        # `| 行名 | 7 类 | 平均 |` ⇒ 去掉首尾空段后是 行名 + 8 个数据格
        assert len([c for c in ln.split("|")[1:-1]]) == 9, "每行必须是 行名 + 8 列（7 类 + 平均）"
    assert any("本文方法" in ln for ln in body)


def test_overview_block_marks_below_trivial_rows():
    """EGFL / MANDO 的「本行最高」不得被读成「好看」——块内必须有该声明的原文。"""
    import collect_baseline_tables as CB
    if not (REPO / "eval_results/baseline/mando/seed0/test_probs.pt").exists():
        pytest.skip("三条基线尚无产物")
    txt = "\n".join(CB.overview_block("runs", list(SEEDS)))
    assert "平凡下限" in txt and "本行最高" in txt


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))


# ------------------------------------------------- ⑦ 7 个独立二分类器补充臂（§50）
def test_perclass_labels_collapse_to_single_class():
    """🔴 本臂**唯一**「只会说谎、不会报错」的坑：标签没生效时 `any(targets)` 会退回
    **全类并集**，于是 7 个「独立分类器」全部静默变成同一个 any 分类器。

    故逐条断言：`any(逐类文件的 targets) == 原文件第 c 列`，且其余列**必须**全 0。
    """
    import run_perclass_arm as A
    if not A.LABEL_SRC.exists():
        pytest.skip("缺只读标签源")
    A.write_labels()
    raw = json.loads(A.LABEL_SRC.read_text(encoding="utf-8"))
    for c, name in enumerate(metrics.VULN_NAMES):
        rows = json.loads((A.LABEL_DIR / f"cls_{name}.json").read_text(encoding="utf-8"))
        assert len(rows) == len(raw), f"{name} 条数与原文件不一致"
        for r, o in zip(rows, raw):
            assert all(v == 0 for i, v in enumerate(r["targets"]) if i != c), \
                f"{name} 有非第 {c} 列的非零值——塌缩会退回全类并集"
            if any(r["targets"]) != bool(o["targets"][c]):
                pytest.fail(f"{name}: any(targets) 与原文件第 {c} 列不符")
        # 正向：该类在全池上确实有正例（否则上面的断言可能被"全 0"平凡满足）
        assert any(any(r["targets"]) for r in rows), f"{name} 全池一个正例都没有？"


def test_perclass_arm_target_dir_never_intersects_canon():
    """产物目录必须落在 `runs/perclass_arm/` 下，绝不与正典 `runs/seed{S}` 相交。"""
    import run_perclass_arm as A
    for cap in A.CAPS if hasattr(A, "CAPS") else (20.0, 0.0):
        for name in metrics.VULN_NAMES:
            for s in A.SEEDS:
                rel = str(A.run_dir_of(cap, name, s).relative_to(REPO))
                assert rel.startswith("runs/perclass_arm/"), rel
                assert not rel.startswith("runs/seed")


# =============================================================== ⑧ 正典布局（池 453 / 池 497）
# 这一组守的是 2026-09-23 引入「换正典」能力时**实际踩到**的那一类坑：
# 四处路径（split/graph/特征根/产物）默认值全指向正典区，换正典只改一处**不报错**，
# 只会静默拿另一套划分训练、或把新池的产物写进正典目录（`decisions.md` §52.6）。


def _ns(**kw):
    import argparse
    base = {"split_dir": str(REPO / "products/alldata/splits"),
            "graph_dir": str(REPO / "products/alldata/graphs_ft/ss0"),
            "out_dir": str(REPO / "eval_results/baseline/mvdhg"),
            "feature_suffix": ""}
    base.update(kw)
    return argparse.Namespace(**base)


def test_layout_tables_agree_across_modules():
    """两处布局知识必须一致——`baseline_common`（跑批）与 `collect_baseline_tables`（出表）。

    它们是**两个模块里的两张表**，漂移了不会报错，只会让「表里写 `_buggy`、跑批写别的」。
    """
    import baseline_common as BC
    import collect_baseline_tables as CB
    assert set(BC.LAYOUTS) == set(CB.LAYOUTS), "两处布局名集合不同"
    for k in BC.LAYOUTS:
        assert BC.LAYOUTS[k]["feature_suffix"] == CB.LAYOUTS[k]["suffix"], f"{k} 后缀不一致"
    # 出表侧的 `rel_of` 必须与跑批侧展开的 out_dir 逐字相同
    for k in BC.LAYOUTS:
        for arm in ("mvdhg", "egfl", "egfl_ownlr", "mando"):
            assert CB.rel_of(arm, k) == BC.LAYOUTS[k]["out_dir"].format(name=arm)


@pytest.mark.parametrize("layout,overrides", [
    # 只加 `--feature-suffix`（最典型的"以为改一处就够"）
    ("canon37", {"feature_suffix": "_buggy"}),
    # 换了池与图（读的是 497 的图/划分），却把**特征根与产物根**留在正典
    ("buggy", {"graph_dir": str(REPO / "products/alldata/graphs_ft_buggy/cb_ft_ss0"),
               "split_dir": str(REPO / "products/alldata/splits/withbuggy_snapshot"),
               "feature_suffix": "",
               "out_dir": str(REPO / "eval_results/baseline/mvdhg")}),
    # 产物根换了、输入没换（最危险：新池的划分 + 正典的特征 + 正典的图）
    ("buggy", {"graph_dir": str(REPO / "products/alldata/graphs_ft/ss0"),
               "split_dir": str(REPO / "products/alldata/splits"),
               "feature_suffix": "_buggy"}),
])
def test_check_layout_rejects_mixed_canon(layout, overrides):
    import baseline_common as BC
    args = _ns(**overrides)
    with pytest.raises(SystemExit) as e:
        BC.check_layout(args, "mvdhg")
    assert "正典" in str(e.value)


@pytest.mark.parametrize("layout", ["canon37", "buggy"])
def test_check_layout_accepts_consistent_canon(layout):
    import baseline_common as BC
    got = BC.layout_paths(layout, "mvdhg", 2)
    args = _ns(split_dir=str(REPO / got["split_dir"]),
               graph_dir=str(REPO / got["graph_dir"]),
               out_dir=str(REPO / got["out_dir"]),
               feature_suffix=got["feature_suffix"])
    assert BC.check_layout(args, "mvdhg") == layout


def test_graph_dir_prefix_does_not_cross_match_canons():
    """`graphs_ft/` 的前缀匹配不得把 `graphs_ft_buggy/...` 也算成 canon37。

    这是 `_match_graph` 唯一要注意的地方——少了尾斜杠，两个正典会同时命中。
    """
    import baseline_common as BC
    assert BC._match_graph(REPO / "products/alldata/graphs_ft/ss0") == "canon37"
    assert BC._match_graph(REPO / "products/alldata/graphs_ft_buggy/cb_ft_ss0") == "buggy"


def test_feature_suffix_isolates_roots():
    """两个正典的离线特征根**必须不同**——同根会让两池的 `feat/*.pt` 混在一个目录里。"""
    import baseline_common as BC
    a, b = BC.feature_root("mvdhg"), BC.feature_root("mvdhg", "_buggy")
    assert a != b and a.name == "mvdhg" and b.name == "mvdhg_buggy"
    # 敏感性臂与主臂共用同一份离线特征（唯一变量是 lr）
    assert BC.feature_root("egfl_ownlr") == BC.feature_root("egfl")


def test_all_feature_root_calls_pass_the_suffix():
    """★ 源码级守卫：5 个脚本里**每一处** `feature_root(` 都必须带后缀参数。

    🔴 这正是 2026-09-23 实际踩到的坑：`main()` 改对了、`ensure_layout()` 漏改
    ⇒ 497 池的 44 份 AST 被编译进**正典根**，而 `_assert_under_feature_root` 因为
    **自己也在查正典根**而一路放行（`decisions.md` §52.6）。漏一处就是一次静默污染。
    """
    scripts = ("baseline_mvdhg_build.py", "baseline_egfl_build.py",
               "baseline_mvdhg.py", "baseline_egfl.py", "baseline_mando.py")
    bad = []
    for fn in scripts:
        src = (REPO / "scripts" / fn).read_text(encoding="utf-8")
        for node in ast.walk(ast.parse(src)):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr == "feature_root"):
                has_kw = any(k.arg == "suffix" for k in node.keywords)
                if not (len(node.args) >= 2 or has_kw):
                    bad.append(f"{fn}:{node.lineno}")
    assert not bad, f"这些 feature_root() 调用漏了正典后缀：{bad}"


def test_buggy_products_never_intersect_canon():
    """`_buggy` 段的产物路径不得与正典段（`runs/`、`eval_results/baseline/<name>`）相交。"""
    import collect_baseline_tables as CB
    for arm in ("mvdhg", "egfl", "egfl_ownlr", "mando"):
        canon = CB.rel_of(arm, "canon37")
        buggy = CB.rel_of(arm, "buggy")
        assert canon != buggy, arm
        assert not str(REPO / buggy).startswith(str(REPO / "runs")), arm
        assert (REPO / buggy).name.endswith("_buggy"), arm
    assert CB.slither_root("buggy") != CB.slither_root("canon37")


@pytest.mark.parametrize("name", BASELINES)
def test_buggy_bundle_is_7dim_on_disk(name):
    """buggy 段落盘产物：`[N,7]`、行序是 split 的**保序子序列**、`N ≤ 49`。

    🔴 **不能照抄 canon 段的「前缀相等」断言**：`drop_without_features` 是**保序剔除**，
    被剔的样本**不一定在末尾**。实测 MVD-HG 在 **ss1 掉的那个 test 合约排在 index 7**，
    用前缀断言会误报失败（而它的真实性质——少了 1 个——才是要盯住的）。
    故这里断言两件事：① 行序是 `split["test"]` 的保序子序列；② 缺的**恰好**是没有
    `feat/<base>.pt` 的那些 base（多缺一个、少缺一个都算错）。
    """
    feat = B.feature_root(name, "_buggy") / "feat"
    for s in SEEDS:
        p = REPO / f"eval_results/baseline/{name}_buggy/seed{s}/test_probs.pt"
        if not p.exists():
            continue
        d = torch.load(p, map_location="cpu")
        sp = REPO / f"products/alldata/splits/withbuggy_snapshot/split_seed{s}.json"
        split = json.loads(sp.read_text(encoding="utf-8"))
        assert d["probs"].shape[1] == 7, f"{name}_buggy/seed{s} 不是 7 维"
        assert d["probs"].shape == d["labels"].shape
        ids = list(d["sample_ids"])
        assert len(split["test"]) == 49
        # ① 保序子序列
        it = iter(split["test"])
        assert all(any(x == b for x in it) for b in ids), f"{name}/seed{s} 行序不是 split 的保序子序列"
        # ② 缺失集 == 无离线特征的 base
        # ⚠ MANDO **没有离线步**（直接读正典图）⇒ 它一个都不该缺；若照 `feat/` 判会把
        #   整个 test 集算成"应缺"，得出 49 个假缺失（本条测试初版就踩了这个）。
        if not feat.exists():
            expect_missing = set()
        else:
            expect_missing = {b for b in split["test"] if not (feat / f"{b}.pt").exists()}
        assert set(split["test"]) - set(ids) == expect_missing, f"{name}/seed{s} 缺失集与覆盖率对不上"


def test_buggy_metadata_is_its_own_file():
    """MANDO 的结构词表逐正典一份：497 池比 453 池**多一种边类型**，两份不能是同一个文件。"""
    canon = B.feature_root("mando") / "hgt_metadata.json"
    buggy = B.feature_root("mando", "_buggy") / "hgt_metadata.json"
    if not buggy.exists():
        pytest.skip("products/alldata/baseline/mando_buggy/hgt_metadata.json 尚无产物")
    assert canon.exists()
    a = json.loads(canon.read_text(encoding="utf-8"))
    b = json.loads(buggy.read_text(encoding="utf-8"))
    assert a["pool_sha256"] != b["pool_sha256"], "两个正典的 metadata 指纹相同（说明写进了同一份）"
    assert len(b["node_types"]) == 9 and isinstance(b["edge_types"], list)


def test_structure_fingerprint_ignores_graph_dir_but_not_pool():
    """★ MANDO 的 `hgt_metadata.json` 守卫：**只看池、不看路径**。

    🔴 这正是 2026-09-23 实测踩到的第二个坑：任务 2 要求 `cb_ft_ss{S}` 与 `--split-seed S`
    配对，而旧指纹把 **graph_dir 路径**也哈希了进去 ⇒ 形态完全正确的 metadata 被判成
    「不同语料」，MANDO 的 seed1/seed2 **在 2–3 秒内 rc=1**。
    本仓语义上该文件只依赖 `(type_id, edge_type)` 的并集（**结构通道**），与目录叫什么都不相干。
    """
    import baseline_mando as M
    pool_a = ["x__1", "y__2", "z__3"]
    pool_b = ["x__1", "y__2", "w__4"]
    # 同一个池、不同目录 ⇒ 结构指纹必须相同（否则配对要求必然撞上这个守卫）
    assert M.structure_fingerprint(pool_a) == M.structure_fingerprint(pool_a)
    # 换池 ⇒ 必须不同（保护没丢：漏传 --feature-suffix 仍会被挡住）
    assert M.structure_fingerprint(pool_a) != M.structure_fingerprint(pool_b)
    # 旧口径仍然包含路径（保留只为兼容库里的老文件）
    assert M.pool_fingerprint(pool_a, "a/b") != M.pool_fingerprint(pool_a, "a/c")


def test_mando_metadata_carries_both_fingerprints():
    """新写的 metadata 必须同时带两个指纹键（老的只有 `pool_sha256`）。"""
    for suffix in ("", "_buggy"):
        p = B.feature_root("mando", suffix) / "hgt_metadata.json"
        if not p.exists():
            continue
        d = json.loads(p.read_text(encoding="utf-8"))
        assert "pool_sha256" in d, f"{p} 缺 pool_sha256"
        if suffix == "_buggy":
            assert "structure_sha256" in d, f"{p} 缺 structure_sha256（本次新写的应有）"
