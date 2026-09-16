#!/usr/bin/env python3
"""审计脚本防漂移回归测试（`scripts/audit_data_funnel.py` / `scripts/audit_cb_func_gap.py`）。

这两个脚本产出的数字**直接进论文口径文档**，因此它们“静默出错”的代价远高于普通脚本：
  - 边类型键对不上时 Counter 默认返回 0 → 整张表全 0 而脚本不报错；
  - 源码读不到时缺失键全部落入 `none` → 伪造“必须报出”的停止条件。

本测试锁住这些**静默失败路径**已转为显式报错/单列统计，以及分类规则的边界。

运行（仓库根目录）：`python -m pytest tests/test_audit_scripts.py -v`
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

_REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_REPO / "scripts"))

import audit_cb_func_gap as gap  # noqa: E402
import audit_data_funnel as funnel  # noqa: E402


# ------------------------------------------------------------ 边类型键（防“全 0 表”）
def _write_hetero(tmp: Path, name: str, edges: dict, nodes: int = 1,
                  ast_unmapped: int = 0) -> Path:
    p = tmp / f"{name}_hetero.json"
    p.write_text(json.dumps({
        "meta": {"ast_unmapped_edge_count": ast_unmapped},
        "functions": [], "nodes": [{}] * nodes, "edges": edges,
    }), encoding="utf-8")
    return p


def test_accumulate_accepts_named_edge_keys(tmp_path):
    """正常路径：键是物理关系名（`_hetero.json` 的实际格式）。"""
    g = _write_hetero(tmp_path, "a", {"CFG_FLOW": [[0, 1]], "DFG_DEP": [], "AST_PARENT": [[1, 2]]},
                      nodes=3, ast_unmapped=7)
    acc = funnel.accumulate_graph_structure([g])
    assert acc["totals"]["CFG_FLOW"] == 1
    assert acc["totals"]["DFG_DEP"] == 0
    assert acc["graphs_with"]["CFG_FLOW"] == 1
    assert acc["graphs_with"]["DFG_DEP"] == 0      # 空边不计入覆盖图数
    assert acc["nodes"] == 3 and acc["ast_unmapped"] == 7 and acc["n_graphs"] == 1


def test_accumulate_rejects_numbered_edge_keys(tmp_path):
    """编号键（"0"–"4"）必须报错：容忍就等于产出全 0 的论文表。"""
    g = _write_hetero(tmp_path, "b", {"0": [[0, 1]], "3": [[1, 2]]})
    with pytest.raises(ValueError, match="未知边类型键"):
        funnel.accumulate_graph_structure([g])


def test_accumulate_rejects_missing_edges_field(tmp_path):
    p = tmp_path / "c_hetero.json"
    p.write_text(json.dumps({"meta": {}, "nodes": [], "functions": []}), encoding="utf-8")
    with pytest.raises(ValueError, match="缺 edges 字段"):
        funnel.accumulate_graph_structure([p])


def test_edge_types_match_dataset_relation_names():
    """物理关系名的单一事实来源是 dataset.RELATION_NAMES，审计脚本不得自持一份。"""
    assert len(funnel.EDGE_TYPES) == 5
    assert funnel.EDGE_TYPES == tuple(funnel.dataset.RELATION_NAMES[k]
                                      for k in sorted(funnel.dataset.RELATION_NAMES))
    assert set(funnel.PAPER_SEMANTIC) == set(funnel.dataset.RELATION_NAMES)


def test_redundancy_total_handles_str_and_int_keys():
    """Σ(k-1)×count 是 846→591 差额 255 的构成；键在内存态是 int、序列化后是 str，两处共用同一函数。"""
    k_hist = {1: 456, 2: 111, 3: 11}
    assert funnel.redundancy_total(k_hist) == 0 + 111 + 22
    assert funnel.redundancy_total({str(k): v for k, v in k_hist.items()}) == 133
    assert funnel.redundancy_total({1: 591}) == 0


# ------------------------------------------------------------ 缺失键分类（防伪造停止条件）
def test_classify_source_missing_not_none():
    """源码读不到时必须单列 source_missing，绝不落入 none（none 是停止条件口径）。"""
    assert gap.classify("foo", "", []) == "source_missing"
    assert gap.classify("foo", "", ["Bar"]) == "source_missing"   # 有同名条目也一样，分类整体失效


def test_classify_alias_wins_over_source_text():
    assert gap.classify("transfer", "function transfer(address to) public {}", ["Token"]) == "alias"


def test_classify_legacy_ctor_abstract_contract():
    """abstract contract Ownable + `function Ownable()` 老式构造函数。"""
    src = "abstract contract Ownable {\n    function Ownable() public { }\n}"
    assert gap.classify("Ownable", src, []) == "legacy_ctor"
    assert gap.classify("Ownable", "contract Ownable {}", []) == "legacy_ctor"
    assert gap.classify("Ownable", "interface Ownable {}", []) == "legacy_ctor"


def test_classify_modifier_and_function():
    assert gap.classify("onlyOwner", "modifier onlyOwner() { _; }", []) == "modifier"
    assert gap.classify("onlyOwner", "modifier onlyOwner { _; }", []) == "modifier"
    assert gap.classify("pay", "function pay(uint x) public {}", []) == "function"


def test_classify_ignores_commented_out_definitions():
    """注释里的定义不得被当成真实定义（否则 function/modifier 类被高估）。"""
    line_cmt = "// function transfer(address to) public\ncontract A {}"
    block_cmt = "/*\n * function transfer(address to) public\n */\ncontract A {}"
    assert gap.classify("transfer", gap.strip_comments(line_cmt), []) == "none"
    assert gap.classify("transfer", gap.strip_comments(block_cmt), []) == "none"
    # 剥离注释不得误伤真实定义
    real = "function transfer(address to) public {}\n// function transfer(address a)"
    assert gap.classify("transfer", gap.strip_comments(real), []) == "function"


def test_strip_comments_preserves_line_structure():
    """剥离注释要保留换行数，否则 `^` 行锚定的匹配会跨行错位。"""
    src = "a\n/* x\n y\n z */\nb // tail\nc"
    out = gap.strip_comments(src)
    assert out.count("\n") == src.count("\n")
    assert "tail" not in out and "x" not in out


def test_strip_comments_ignores_comment_markers_inside_strings():
    """字符串里的 `//` / `/*` 不是注释。

    朴素正则的两个致命误判：
      - `"// not a comment"` 会把该行剩余部分当注释吞掉；
      - `"/*"` 会一路吞到下一个 `*/`（可能横跨整个文件），把真实定义删掉 →
        相关键被误判成 `none`（停止条件），伪造出必须裁定的结论。
    """
    # 字符串里的 // 不得吞掉后文
    src = 'string s = "// not a comment";\nfunction pay(uint x) public {}'
    out = gap.strip_comments(src)
    assert "function pay" in out
    assert gap.classify("pay", out, []) == "function"

    # 字符串里的 /* 不得开启块注释
    src = 'string s = "/*";\nfunction pay(uint x) public {}\nstring t = "*/";'
    out = gap.strip_comments(src)
    assert "function pay" in out
    assert gap.classify("pay", out, []) == "function"

    # 转义引号不得提前结束字符串（\ 后面的 " 仍是字符串内容）
    src = 'string s = "a\\"//b";\nfunction pay(uint x) public {}'
    out = gap.strip_comments(src)
    assert "function pay" in out

    # 单引号字符串同理
    src = "string s = '// x';\nfunction pay(uint x) public {}"
    assert gap.classify("pay", gap.strip_comments(src), []) == "function"


def test_strip_comments_still_removes_real_comments():
    """状态机不能因为防字符串而放过真注释。"""
    assert "hidden" not in gap.strip_comments("/* hidden */ code")
    assert "hidden" not in gap.strip_comments("code // hidden")
    assert gap.classify("pay", gap.strip_comments("// function pay() public\ncontract A {}"), []) == "none"
    # 块注释横跨多行时，行数必须守恒
    src = "contract A {\n/* function pay() public\n   still comment */\n}"
    out = gap.strip_comments(src)
    assert out.count("\n") == src.count("\n")
    assert gap.classify("pay", out, []) == "none"


def test_classify_falls_back_to_none():
    assert gap.classify("slitherConstructorVariables", "contract A {}", []) == "none"


def test_action_table_covers_every_class():
    """每个可能被 classify 返回的类别都必须在 ACTION 里有处置文字（否则 print/md KeyError）。

    历史 bug：`legacy_ctor` 类存在但 ACTION 漏了它，一旦真出现该类键即崩。
    """
    reachable = {"none", "source_missing"}
    samples = [
        ("transfer", "contract A {}", ["Token"]),                    # alias
        ("Ownable", "contract Ownable {}", []),                      # legacy_ctor
        ("onlyOwner", "modifier onlyOwner() { _; }", []),            # modifier
        ("pay", "function pay(uint x) public {}", []),               # function
        ("slitherConstructorVariables", "contract A {}", []),        # none
        ("foo", "", []),                                             # source_missing
    ]
    for name, src, same in samples:
        reachable.add(gap.classify(name, src, same))
    assert reachable == {"alias", "legacy_ctor", "modifier", "function", "none", "source_missing"}
    assert reachable <= set(gap.ACTION), sorted(reachable - set(gap.ACTION))


# ------------------------------------------------------------ 端到端：脚本可跑且数字自洽
def test_audit_data_funnel_print_only_runs():
    """--print 端到端跑通（含全部断言：漏斗不变量、池规模、targets 列宽、边类型键）。"""
    import subprocess
    r = subprocess.run([sys.executable, str(_REPO / "scripts/audit_data_funnel.py"), "--print"],
                       cwd=_REPO, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr[-2000:]
    assert "两级去重" in r.stdout


def test_audit_cb_func_gap_print_only_runs():
    import subprocess
    r = subprocess.run([sys.executable, str(_REPO / "scripts/audit_cb_func_gap.py"), "--print"],
                       cwd=_REPO, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr[-2000:]
    assert "缺口" in r.stdout


# ------------------------------------------------------------ 推理缓存必须与划分一致
def test_cached_test_probs_match_current_split():
    """`runs/seed*/test_probs.pt` 的 sample_ids 必须等于当前划分的 test 列表。

    2026-09-14 实际踩过：缓存只按“文件存在”复用，重训/重划后静默沿用旧划分的推理结果，
    `diagnosis.json` 的逐类 support 与诊断结论随之错位（access_control test_pos 报 2、实为 3）。
    `evaluate.py` 早有 sample_ids 校验，`diagnose.py` 已补齐同样校验；本测试防止回归。
    """
    import json

    import torch

    runs = _REPO / "runs"
    splits = _REPO / "products/alldata/splits"
    checked = 0
    for seed_dir in sorted(runs.glob("seed[0-9]")):
        cache = seed_dir / "test_probs.pt"
        split_file = splits / f"split_seed{seed_dir.name[4:]}.json"
        if not cache.exists() or not split_file.exists():
            continue
        cached = list(torch.load(cache, map_location="cpu").get("sample_ids", []))
        assert cached == json.loads(split_file.read_text(encoding="utf-8"))["test"], (
            f"{cache} 与 {split_file.name} 的 test 不一致 —— 诊断结果将基于过期缓存")
        checked += 1
    assert checked, "没有可校验的 test_probs.pt（先跑 train+evaluate+diagnose）"


# ------------------------------------------------------------ 对照臂隔离（--include-buggy）
def test_include_buggy_isolates_output_and_keeps_canon(tmp_path):
    """`--include-buggy` 只能写 <out-dir>/withbuggy_snapshot/，绝不触碰正典划分。

    含 buggy_* 的臂是**对照**：buggy_* 为七类全 1 的注入标签，其 macro-F1/mAP 会被
    支撑虚高（度量假象），绝不能让它的产物覆盖正典，也不能让正典数字被它污染。
    """
    import hashlib
    import json
    import subprocess

    splits = _REPO / "products/alldata/splits"
    canon_before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(splits.glob("*.json"))}
    assert canon_before, "正典划分不存在，先跑 make_splits.py"

    r = subprocess.run([sys.executable, str(_REPO / "scripts/make_splits.py"),
                        "--include-buggy", "--seeds", "0", "--out-dir", str(tmp_path)],
                       cwd=_REPO, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr[-2000:]

    arm = tmp_path / "withbuggy_snapshot"
    assert (arm / "split_report.json").exists(), "对照臂未隔离到 withbuggy_snapshot/"
    arm_report = json.loads((arm / "split_report.json").read_text(encoding="utf-8"))
    assert arm_report["include_buggy"] is True
    assert arm_report["buggy_excluded_graphs"] == 0

    canon_report = json.loads((splits / "split_report.json").read_text(encoding="utf-8"))
    assert canon_report.get("include_buggy", False) is False
    assert arm_report["dedup"]["pool_after_dedup"] > canon_report["dedup"]["pool_after_dedup"]

    canon_after = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in sorted(splits.glob("*.json"))}
    assert canon_after == canon_before, "对照臂改动了正典划分产物"
