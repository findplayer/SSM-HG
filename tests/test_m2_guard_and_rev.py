"""M2 输出目录守卫（§6.5）与反向关系 CALLBACK_RISK_REV（§6.3）的回归锁。

**为什么这两件事要一起钉**：它们是同一批消融里**唯一会重写 `products/alldata/graphs`
以外目录的代码路径**，且失败方式都是"不报错的错"——
  - 没有守卫时，默认 `--out-dir` 会逐个改写正典 `_hetero.json`，而下游 `_m1/_pyg/_feat`
    **全部不同步**（§6.5）；
  - `num_relations` 若按常量表的最大编号算（恒 6），正典语料也会被写成 6 ⇒ RGCN 多出一组
    **永远收不到消息的基**：不报错，只是静默改变参数量与初始化（§6.3）。
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest
import torch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import convert_hetero_json_to_pyg as pyg      # noqa: E402
import dataset                                # noqa: E402
import run_guard                              # noqa: E402


# --------------------------------------------------------------------- §6.5 守卫
def test_nonempty_out_dir_detects_existing_products(tmp_path):
    assert run_guard.nonempty_out_dir(tmp_path) is None
    (tmp_path / "a_hetero.json").write_text("{}", encoding="utf-8")
    msg = run_guard.nonempty_out_dir(tmp_path)
    assert msg and "1 个" in msg


def test_m2_refuses_to_write_into_a_nonempty_out_dir(tmp_path):
    """端到端：目标目录已有 `_hetero.json` 且未给 `--overwrite` → 必须非零退出且**不改文件**。"""
    (tmp_path / "x_hetero.json").write_text('{"sentinel": 1}', encoding="utf-8")
    proc = subprocess.run(
        [sys.executable, "scripts/build_cfg_centered_hetero_graph.py",
         "--out-dir", str(tmp_path), "--only", "whatever"],
        cwd=REPO, capture_output=True, text=True)
    assert proc.returncode != 0, proc.stdout
    assert "拒绝覆盖" in (proc.stdout + proc.stderr)
    assert json.loads((tmp_path / "x_hetero.json").read_text()) == {"sentinel": 1}, "守卫不得改动原文件"


def test_m2_canonical_outdir_is_the_default_and_is_guarded():
    """默认 `--out-dir` 就是正典语料——这正是必须加守卫的理由，写进测试以防被改掉后失去保护。

    ⚠ 不能靠 `--help` 断言：argparse 只在 help 文案里显式写了 `%(default)s` 才打印默认值。
    直接查源码里的默认表达式，语义同样明确且不会因文案调整而误报。
    """
    src = (REPO / "scripts" / "build_cfg_centered_hetero_graph.py").read_text(encoding="utf-8")
    assert 'default=f"{base}/products/alldata/graphs"' in src


# --------------------------------------------------------------------- §6.3 反向关系
def test_reverse_edges_is_the_exact_mirror():
    edges = {(1, 2), (3, 4), (5, 6)}
    rev = pyg_reverse(edges)
    assert rev == {(2, 1), (4, 3), (6, 5)}
    assert len(rev) == len(edges), "镜像必须一一对应（不另跑一套过滤规则）"


def pyg_reverse(edges):
    sys.path.insert(0, str(REPO / "scripts"))
    import importlib
    m2 = importlib.import_module("build_cfg_centered_hetero_graph")
    return m2.reverse_callback_edges(edges)


def test_num_relations_follows_keys_actually_present():
    canon = {"CFG_FLOW": [], "AST_PARENT": [], "AST_PARENT_SAME": [], "DFG_DEP": [],
             "CALLBACK_RISK": []}
    assert pyg.num_relations_of(canon) == 5
    # 🔴 关键：**键存在即为 6**，哪怕该图的 REV 边为空——否则同一语料里 num_relations
    # 会在 5/6 之间摇摆，训练侧的一致性断言会直接拒绝（这是有意的，不是过严）。
    assert pyg.num_relations_of({**canon, "CALLBACK_RISK_REV": []}) == 6
    assert pyg.num_relations_of({**canon, "CALLBACK_RISK_REV": [{"source": 1, "target": 2}]}) == 6
    # 只有 CFG_FLOW 的退化语料：按实际关系数给 1，而不是常量 5
    assert pyg.num_relations_of({"CFG_FLOW": []}) == 1


def test_convert_one_writes_num_relations_and_rev_edges(tmp_path):
    graph = {
        "nodes": [{"id": 1}, {"id": 2}],
        "edges": {"CALLBACK_RISK": [{"source": 1, "target": 2}],
                  "CALLBACK_RISK_REV": [{"source": 2, "target": 1}]},
    }
    src = tmp_path / "g_hetero.json"
    src.write_text(json.dumps(graph), encoding="utf-8")
    pyg.convert_one(src, tmp_path)
    payload = torch.load(tmp_path / "g_pyg.pt", map_location="cpu")
    assert payload["num_relations"] == 6
    assert sorted(payload["edge_type"].tolist()) == [4, 5]


def test_dataset_relation_names_stays_five():
    """`audit_data_funnel.py:382` 的 `assert len(RELATION_NAMES) == 5` 审计的是**正典语料**，
    不能为一个消融放宽——REV 走的是另立的**显示用**扩展表。"""
    assert len(dataset.RELATION_NAMES) == 5
    assert dataset.RELATION_NAMES_EXT[5] == "CALLBACK_RISK_REV"
    assert 5 not in dataset.DROPPABLE_EDGES, "REV 是'加一类边'的消融，不该开删边口子"


def test_drop_edges_rejects_rev_id():
    """`--drop-edges 5` 应报错（白名单未扩）——写进验收以免被当成 bug。"""
    for good in ([4], [0, 3]):
        assert dataset.resolve_drop_edges([str(e) for e in good]) == set(good)
    with pytest.raises(ValueError, match="白名单"):
        dataset.resolve_drop_edges(["5"])


# --------------------------------------------------------------------- 身份键登记
def test_layers_registered_in_identity_defaults():
    """`--layers` 是身份键：不登记就会让「新键写进旧目录」被守卫放行并无声覆盖（§31.3）。"""
    assert run_guard.IDENTITY_DEFAULTS.get("layers") == 2


def test_layers_key_detected_as_conflict_on_old_dir():
    """老目录（无 `layers` 键）vs 新调用 `--layers 3`：差异必须**可见**。"""
    old = {"hid": 128, "num_bases": 5}
    new = {"hid": 128, "num_bases": 5, "layers": 3}
    diffs = run_guard.diff_args(old, new)
    assert any(d.startswith("layers:") for d in diffs), diffs


# ------------------------------------------------ 冻结 IR 字典（2026-09-18，decisions §35.4）
def test_variant_builders_use_the_frozen_ir_anchor():
    """🔴 三个变体构建必须传**冻结锚点**，不得传 `<语料>/graphs/ir_cat.json`。

    ② 的 `products/augmentation/graphs/` 里**没有** `ir_cat.json`（实测），传路会命中
    `m3_build_features.py` 的"`--categories` 不存在 → WARNING + 回退全库扫描"分支：
    不报错、只多一行 WARNING，然后在变体目录里落一个重扫出来的字典。
    实测两者数值等价（② 重扫得到的 `ir_categories`/`call_modes` 与锚点逐项相同，
    节点数 463264 亦相符），但"恰好等价"不能当作依赖——故显式传锚点。
    """
    import build_graph_variant as bgv
    src = (REPO / "scripts" / "build_graph_variant.py").read_text(encoding="utf-8")
    assert src.count('"--categories", str(frozen_categories())') == 3, \
        "三处 M3 调用（cb_rev / cb_unlimited / cb_ft）都必须传冻结锚点"
    assert 'str(graphs / "ir_cat.json")' not in src
    assert bgv.FROZEN_IR_CAT == REPO / "products" / "alldata" / "graphs" / "ir_cat.json"


def test_frozen_categories_raises_when_anchor_is_missing(monkeypatch, tmp_path):
    """锚点缺失必须**硬失败**——否则 m3 会静默重扫，语义锚点悄悄漂移。"""
    import build_graph_variant as bgv
    monkeypatch.setattr(bgv, "FROZEN_IR_CAT", tmp_path / "nope.json")
    with pytest.raises(SystemExit) as e:
        bgv.frozen_categories()
    assert "冻结 IR 字典" in str(e.value)


def test_frozen_anchor_is_the_one_the_corpora_actually_used():
    """锚点必须真的存在，且含 IR 类别表（防有人把它清成空壳）。"""
    import build_graph_variant as bgv
    assert bgv.FROZEN_IR_CAT.exists()
    payload = json.loads(bgv.FROZEN_IR_CAT.read_text(encoding="utf-8"))
    assert payload["ir_categories"], "ir_categories 为空 = 锚点已坏"
    assert payload["call_modes"]


def test_rev_edge_stats_counts_exact_mirrors(tmp_path):
    """`rev_edge_stats` 必须逐图比对正/反向边数——**只断言 `_feat.pt` 相同是不够的**：
    一条 REV 边都没建出来时，`_feat.pt` 同样"逐位相同"（M1 看不见 REV），
    本项会退化成一次重复实验却通过所有通道断言。"""
    import build_graph_variant as bgv
    for name, fwd, rev in [("a", 3, 3), ("b", 5, 4), ("c", 0, 0)]:
        (tmp_path / f"{name}_hetero.json").write_text(json.dumps(
            {"meta": {"callback_risk_edge_count": fwd, "callback_rev_edge_count": rev}}),
            encoding="utf-8")
    out = bgv.rev_edge_stats(tmp_path, ["a", "b", "c"])
    assert out == {"callback_edges_fwd": 8, "callback_edges_rev": 7,
                   "graphs_with_exact_mirror": 2, "graphs_total": 3}


def test_rev_edge_stats_detects_empty_rev(tmp_path):
    """反向边全为 0 = 开关是空操作，统计必须看得出来。"""
    import build_graph_variant as bgv
    (tmp_path / "a_hetero.json").write_text(json.dumps(
        {"meta": {"callback_risk_edge_count": 7, "callback_rev_edge_count": 0}}), encoding="utf-8")
    out = bgv.rev_edge_stats(tmp_path, ["a"])
    assert out["callback_edges_rev"] == 0
    assert out["graphs_with_exact_mirror"] == 0


def _write_feat(path: Path, val: float) -> None:
    import torch as _t
    _t.save({"struct": _t.full((3, 4), val), "type_id": _t.zeros(3, dtype=_t.long),
             "sv": _t.full((3, 1), val)}, path)


def test_assert_feat_identical_returns_counts(tmp_path):
    """返回值必须带 same/diff/total——`variant.json` 的审计数字靠它。

    原先只打印不返回，`callback_rev` 的记录里就只剩一句「已断言」、一个数字都没有，
    事后不得不从产物反推补写。函数签名把这件事钉死。
    """
    import build_graph_variant as bgv
    v, c = tmp_path / "v", tmp_path / "c"
    v.mkdir(); c.mkdir()
    for n in ("a", "b"):
        _write_feat(c / f"{n}_feat.pt", 1.0)
        _write_feat(v / f"{n}_feat.pt", 1.0)
    out = bgv.assert_feat_identical(v, c, expect_same=True, graph_names=["a", "b"], label="t")
    assert out == {"same": 2, "diff": 0, "total": 2}


def test_assert_feat_identical_counts_partial_diffs(tmp_path):
    import build_graph_variant as bgv
    v, c = tmp_path / "v", tmp_path / "c"
    v.mkdir(); c.mkdir()
    for n, val in (("a", 1.0), ("b", 2.0)):
        _write_feat(c / f"{n}_feat.pt", 1.0)
        _write_feat(v / f"{n}_feat.pt", val)
    out = bgv.assert_feat_identical(v, c, expect_same=False, graph_names=["a", "b"], label="t")
    assert out["diff"] == 1 and out["same"] == 1 and out["total"] == 2


def test_cb_ft_reverse_check_is_exhaustive_not_sampled():
    """🔴 `cb_ft` 的 `_cb.pt` 反向核验必须**全量**，不得抽样。

    它是"微调编码器确实生效"的**唯一**证据（`_feat.pt` 逐位相同只证明结构没被动，
    对编码器只字未提）。原先只查 `names[:40]`，而同一函数里 `assert_feat_identical`
    是全量的——两侧证据强度不对称，且拿 40/40 外推"全库都换了编码器"。
    """
    src = (REPO / "scripts" / "build_graph_variant.py").read_text(encoding="utf-8")
    body = src.split('"反向验收"', 1)[1].split("write_variant_json", 1)[0]
    # ⚠ 必须先剥掉注释行再判：改动的**说明**里必然提到旧写法 `names[:40]`，
    #   裸 grep 会把"解释这次修复"的注释当成"又改回抽样了"（本测试第一版就这么误报了）。
    code = "\n".join(ln for ln in body.splitlines() if not ln.strip().startswith("#"))
    assert "names[:40]" not in code, "反向核验又变回抽样了"
    assert "for name in names:" in code
    assert "changed != len(names)" in code
