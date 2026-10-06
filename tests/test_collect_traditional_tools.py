#!/usr/bin/env python3
"""`scripts/collect_traditional_tools.py` 的回归测试（2026-09-25）。

这一份报告是**论文 5.3 那六行数字的前提**，它自己写错的后果比数字错更隐蔽：
读者会按报告里的"能力边界 / 覆盖率"去解释表里的空格，报告错 ⇒ 解释错 ⇒ 结论错。
故守住三件事，每件都对应一个**已经踩到或极易踩**的坑：

  1. **能力边界以"活代码"为准，不读产物里的快照** —— 本轮实测更正过两次能力边界
     （securify 的 0.4.x 结论、SmartCheck 缺 reentrancy）。若报告读快照，
     **报告会与代码说的不一致且看不出来**。
  2. **退化行要被自动检出来** —— 某工具在 test 上逐类 support 全 0 时，它算出的
     `micro_f1 = 0.0` 与"预测全错"长得一模一样，含义却相反（分母里没有正样本）。
  3. **缺产物的工具要被点名**，不能静默少行 —— 否则"没跑"与"跑了但全错"看起来一样。

运行：`pytest tests/test_collect_traditional_tools.py -q`
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import static_tool_adapters as STA                 # noqa: E402
import collect_traditional_tools as C              # noqa: E402


# ------------------------------------------------------------------ 1. 活代码 vs 产物快照


def test_spec_of_prefers_live_code_over_stale_snapshot():
    """🔴 产物里那份 `capability` / `excluded` 是**写出时的快照**；报告必须用活代码的值。

    构造一份"快照说 securify 能吃 0.4.x"的假产物 —— 报告不能采信它。
    """
    stale = {"capability": ["**旧快照**：securify2 只吃 ≥0.5.8 且扁平"], "excluded": {"OLD": "旧理由"}}
    got = C.spec_of("securify", stale, "capability")
    assert got == STA.TOOLS["securify"].capability, "报告采信了产物里的陈旧快照"
    assert "旧快照" not in " ".join(got)
    got_exc = C.spec_of("securify", stale, "excluded")
    assert got_exc == STA.TOOLS["securify"].excluded


def test_spec_of_falls_back_to_snapshot_for_slither():
    """Slither 不在 `static_tool_adapters.TOOLS` 里（它的映射留在原脚本）⇒ 必须退回产物快照，
    否则 Slither 那一行会**整行消失**（不报错）。"""
    assert C.spec_of("slither", {"no_detector_classes": ["front_running"]}, "no_detector_classes") \
        == ["front_running"]
    assert C.spec_of("slither", {}, "capability") is None or \
        C.spec_of("slither", {}, "capability") == []


def test_no_detector_classes_comes_from_live_code():
    """派生的 `no_detector_classes` 也必须走活代码（它每改一次映射就变一次）。"""
    fake = {"no_detector_classes": []}                     # 旧的错误快照：SmartCheck 写成了空
    got = C.spec_of("smartcheck", fake, "no_detector_classes")
    assert set(got) == {"reentrancy", "front_running"}, got


# ------------------------------------------------------------------ 2. 退化行自动检测


def _stem(tool: str) -> str:
    """该工具在 497 正典下的产物主干名（`<工具>_alldata_buggy`；Slither 例外 `slither_buggy`）。

    🔴 2026-10-02：`collect_traditional_tools` 改指池 497 后，产物目录不再是 `<工具>_alldata`。
    这里**不另抄一份命名规则**，直接问 `collect_baseline_tables.trad_root()`（与脚本同源），
    使合成产物的写盘位置与脚本的读盘位置永远一致。它不依赖 `C.BASE`，故可在 monkeypatch 之前调用。
    """
    import collect_baseline_tables as CB
    return Path(CB.trad_root(tool, "buggy")).name


def _write_eval(root: Path, tool: str, seed: int, support: list[int]) -> None:
    d = root / _stem(tool)
    d.mkdir(parents=True, exist_ok=True)
    (d / f"seed{seed}_eval.json").write_text(json.dumps({
        "test": {"n_in_split": 46, "n_analyzed": 8, "per_class_support": support},
        "val": {"n_in_split": 45, "n_analyzed": 7, "per_class_support": support},
    }), encoding="utf-8")


def test_degenerate_tool_is_detected(tmp_path, monkeypatch):
    """逐类 support 全 0 ⇒ 必须被点名。这正是 Securify 的真实情形。"""
    for s in (0, 1, 2):
        _write_eval(tmp_path, "securify", s, [0] * 7)
    monkeypatch.setattr(C, "BASE", tmp_path)
    got = C.degenerate_tools({"securify": {}})
    assert "securify" in got, "分母里没有正样本的工具没有被检出"


def test_non_degenerate_tool_is_not_flagged(tmp_path, monkeypatch):
    """有正样本的工具**不得**被误报（误报会让警告贬值）。"""
    for s in (0, 1, 2):
        _write_eval(tmp_path, "slither", s, [3, 2, 1, 1, 5, 2, 7])
    monkeypatch.setattr(C, "BASE", tmp_path)
    assert C.degenerate_tools({"slither": {}}) == {}


def test_degenerate_requires_all_seeds_zero(tmp_path, monkeypatch):
    """只要**有任何一个**种子有正样本，就不算退化（单种子为零可能只是该划分的偶然）。"""
    for s, sup in ((0, [0] * 7), (1, [1, 0, 0, 0, 0, 0, 0]), (2, [0] * 7)):
        _write_eval(tmp_path, "x", s, sup)
    monkeypatch.setattr(C, "BASE", tmp_path)
    assert C.degenerate_tools({"x": {}}) == {}


def test_no_artifacts_means_not_degenerate(tmp_path, monkeypatch):
    """**没有产物** ≠ 退化。没有产物由"未接入"那句点名，不该在这里报退化（两件事不能混）。"""
    monkeypatch.setattr(C, "BASE", tmp_path)
    assert C.degenerate_tools({"mythril": {}}) == {}


# ------------------------------------------------------------------ 3. 缺产物要点名 / 数字格式


def test_missing_tools_are_named_not_silently_omitted(tmp_path, monkeypatch):
    """缺 `eval_results/baseline/<工具>_alldata.json` 的工具必须**被点名**。"""
    monkeypatch.setattr(C, "BASE", tmp_path)
    assert C.tool_names() == []
    md, payload = C.build()
    # 🔴 措辞 2026-09-26 由「尚未接入」改为「**无产物**」：六个工具的适配器**都已实现**，
    # 缺行只可能是「该池没跑」或「跑了没跑完」。断言「无产物」以免又漂回会误导的旧说法。
    assert "无产物" in md and "尚未接入" not in md
    for t in ("mythril", "manticore", "smartcheck", "securify", "oyente"):
        assert t in md, f"{t} 既没出行也没被点名"


def test_fmt_mean_and_std():
    assert C.fmt([]) == "—"
    assert C.fmt([0.5]) == "0.5000"
    out = C.fmt([0.2, 0.4, 0.6])
    assert out.startswith("0.4000 ± "), out


def test_report_declares_the_two_scopes():
    """报告必须**显式声明** Slither 与其余五工具的跑动范围不同（否则覆盖率一栏会被横比）。"""
    md, payload = C.build()
    assert payload["scope"]["slither"] != payload["scope"]["others"]
    # 🔴 2026-10-02 改指池 497 后，其余五工具的并集由 214 变为 306（Slither 仍是 590 全库）。
    #    旧期望值 214 现在只能从 `static_tool_adapters` 的能力边界文案里偶然命中
    #    （那是**池 453 时代的实测**、尚未更新）⇒ 此处改为断言**范围表**真正写出的 306。
    assert "590" in md and "306" in md


def test_report_forbids_reading_zero_as_f1_zero():
    """报告必须把「不提供此检测项」与「在此类上 F1=0」区分开（§47.4 的口径）。"""
    md, _ = C.build()
    assert "不提供此检测项" in md


# ------------------------------------------------------------------ 4. `—` 的三种判据（2026-09-26）


def _write_eval_full(root: Path, tool: str, seed: int, support: list[int],
                     f1: list[float]) -> None:
    """写一份**带逐类 F1** 的 eval —— 退化/能力缺失的渲染都要读它。

    🔴 原始产物 `<tool>_alldata.json` **也必须写**：`tool_names()` 以它判定"这个工具在不在报告里"，
    只写 eval 目录的话整行根本不出现（第一版就栽在这里）。
    """
    (root / f"{_stem(tool)}.json").write_text("{}", encoding="utf-8")
    d = root / _stem(tool)
    d.mkdir(parents=True, exist_ok=True)
    (d / f"seed{seed}_eval.json").write_text(json.dumps({
        "test": {"n_in_split": 46, "n_analyzed": 20, "per_class_support": support,
                 "per_class_f1": f1, "names": list(C.NAMES),
                 "micro_f1": 0.5, "macro_f1": 0.4},
        "val": {"n_in_split": 45, "n_analyzed": 19, "per_class_support": support},
    }), encoding="utf-8")


def _row_cells(md: str, label: str) -> list[str]:
    """取**第四节**那张表里该工具的一行（🔴 必须限定小节：第三节覆盖率表也有同名行，
    不限定就会抓到那张只有 3 格的表 —— 第一版就栽在这里）。"""
    sec = md.split("## 四、", 1)[1].split("## 五、", 1)[0]
    row = next(l for l in sec.splitlines() if l.startswith(f"| **{label}**"))
    return [c.strip() for c in row.split("|")[2:-1]]


def test_capability_missing_cells_are_dashed_not_zero(tmp_path, monkeypatch):
    """🔴 用户 2026-09-26 裁定：该工具**不提供**此检测项的类，格子里直接画 `—`。

    SmartCheck 的 40 条规则里没有 reentrancy / front_running ⇒ 下标 3、4 必须是 `—`；
    而它有检测项、确实报对的类（如 `access_control` F1=0.5）**必须保留数字**。
    """
    for s in (0, 1, 2):
        _write_eval_full(tmp_path, "smartcheck", s, [3, 2, 1, 1, 5, 2, 7],
                         [0.5, 0.0, 0.0, 0.0, 0.0, 0.6, 1.0])
    monkeypatch.setattr(C, "BASE", tmp_path)
    md, _ = C.build()
    cells = _row_cells(md, "Smartcheck")
    assert cells[3] == "—" and cells[4] == "—", f"能力缺失的格没画 —：{cells}"
    assert cells[0].startswith("0.5000"), f"有能力的格被误画成 —：{cells}"
    assert C.no_detector_idx("smartcheck", {}) == {3, 4}


def test_degenerate_row_is_dashed_but_still_warned(tmp_path, monkeypatch):
    """整行不可评估（逐类 support 全 0，Securify 的真实情形）⇒ 整行 `—` **且** warning 照旧。"""
    for s in (0, 1, 2):
        _write_eval_full(tmp_path, "securify", s, [0] * 7, [0.0] * 7)
    monkeypatch.setattr(C, "BASE", tmp_path)
    md, _ = C.build()
    assert set(_row_cells(md, "Securify")) == {"—"}, "退化行没有整行画 —（0.0000 会被读成成绩）"
    assert "逐类 support 全为 0" in md, "整行画 — 之后仍必须保留 warning（否则读者不知为何是 —）"


def test_tool_with_products_but_no_eval_is_named(tmp_path, monkeypatch):
    """🔴 第三种 `—`：**有原始产物但还没评测** —— 必须点名，否则与「不可评估」长得一样。"""
    (tmp_path / f"{_stem('manticore')}.json").write_text("{}", encoding="utf-8")
    monkeypatch.setattr(C, "BASE", tmp_path)
    md, _ = C.build()
    assert "尚未评测" in md and "Manticore" in md, "有产物无评测的工具没有被点名"
    assert set(_row_cells(md, "Manticore")) == {"—"}


def test_three_reasons_for_dash_are_spelled_out(tmp_path, monkeypatch):
    """三种 `—` 的判据必须**同时**写在报告里（能力缺失 / 整行不可评估 / 尚未评测）。

    三种情形各造一个工具：SmartCheck（有能力缺失）、Securify（退化）、Manticore（有产物无评测）。
    """
    for s in (0, 1, 2):
        _write_eval_full(tmp_path, "smartcheck", s, [3, 2, 1, 1, 5, 2, 7],
                         [0.5, 0.0, 0.0, 0.0, 0.0, 0.6, 1.0])
        _write_eval_full(tmp_path, "securify", s, [0] * 7, [0.0] * 7)
    (tmp_path / f"{_stem('manticore')}.json").write_text("{}", encoding="utf-8")   # 有产物、无评测
    monkeypatch.setattr(C, "BASE", tmp_path)
    md, _ = C.build()
    for token in ("能力缺失", "不可评估", "尚未评测"):
        assert token in md, f"报告没写清 `—` 的判据：缺 `{token}`"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))


# ------------------------------------------------------------------ 5. 「仅覆盖类」口径（†）


def _prod(tool: str) -> dict:
    p = C.trad_json(tool)
    if not p.exists():
        pytest.skip(f"{tool} 尚无产物")
    return json.loads(p.read_text(encoding="utf-8"))


# 🔴 2026-10-02：本脚本已改指**现行正典池 497**（layout `buggy`），本测试随之由池 453 改指 497。
#    原先因「池 453 产物被删、脚本尚未改指」而 `skipif` 跳过，现恢复执行。
_PROD_497 = REPO / "eval_results" / "baseline" / "mythril_alldata_buggy" / "seed0_eval.json"


@pytest.mark.skipif(not _PROD_497.exists(),
                    reason="池 497 的传统工具评测产物缺失（`<工具>_alldata_buggy/` 未生成）")
def test_covered_metrics_drops_only_the_missing_classes():
    """🔴 † 列 = **仅该工具有检测项的类**的 micro/macro。

    两条硬性质：
      ① 覆盖 **7/7** 的工具（Mythril）两列**必须逐位相同** —— 否则说明切列切错了；
      ② 覆盖 **6/7** 的 Slither，去掉的 `front_running` 在全七类口径里是 F1=0、support>0
         ⇒ 它贡献的全是 FN ⇒ 去掉后 micro **必须变高**（这就是 † 口径"系统性偏高"的来源）。

    2026-10-02 在池 497 上实测两条仍成立（Slither 三种子 cov.micro − full 分别为
    +0.0190 / +0.0162 / +0.0200）。
    """
    cov = C.covered_metrics("mythril", _prod("mythril"))
    full = {s: json.loads((C.trad_root("mythril") / f"seed{s}_eval.json")
                          .read_text(encoding="utf-8"))["test"]["micro_f1"] for s in (0, 1, 2)}
    assert cov, "Mythril 应有覆盖类读数"
    for s, v in cov.items():
        # 产物里的 `micro_f1` 是 `round(..., 6)` 存的 ⇒ 只能到 1e-6（与 `covered_metrics`
        # 内部的自检同容差）。断言 1e-9 是**测试自己的错**，不是数据不一致。
        assert abs(v["micro"] - full[s]) < 1e-6, f"7/7 覆盖的工具两列必须相同（seed{s}）"

    sl = C.covered_metrics("slither", _prod("slither"))
    sl_full = {s: json.loads((C.trad_root("slither") / f"seed{s}_eval.json")
                             .read_text(encoding="utf-8"))["test"]["micro_f1"] for s in (0, 1, 2)}
    for s, v in sl.items():
        assert v["micro"] > sl_full[s], f"去掉 front_running 后 micro 应变高（seed{s}）"


def test_covered_metrics_are_rendered_as_dedicated_columns():
    """† 两列必须真的进表；🔴 池 497 下 Securify 的行**不再是整行 `—`**。

    ⚠ **这是数据性质变化、不是代码坏了**：旧池 453 里 Securify（只吃 pragma 0.5.x）的可分析集
    恰好全是干净合约 ⇒ test 逐类 support 全 0 ⇒ 整行 `—`；池 497 并入了 `buggy_*`
    （恰是 0.5.x、100% 正例）⇒ support>0 ⇒ 该行有数。整行 `—` 的渲染逻辑本身由合成用例
    `test_degenerate_row_is_dashed_but_still_warned` 独立守住，不受本改影响。
    """
    md, _ = C.build()
    sec = md.split("## 四、", 1)[1].split("## 五、", 1)[0]
    head = next(l for l in sec.splitlines() if l.startswith("| 工具 |"))
    assert "micro†" in head and "macro†" in head, "第四节表头缺 † 两列"
    # `split("|")` = 首空段 + 行名 + 11 格 + 末空段 ⇒ 数据格 = len - 3
    assert len(head.split("|")) - 3 == len(C.NAMES) + 4, "第四节列数应为 7 类 + micro/macro + † 两列"
    cells = _row_cells(md, "Securify")
    assert set(cells) != {"—"}, "池 497 下 Securify 有正样本，不应再整行 —（数据性质已变）"
    # 未评测行（合成场景）仍必须是整行 `—`：见 test_tool_with_products_but_no_eval_is_named。


# ------------------------------------------------------------------ 6. 裁定 A：0/0 不计成 0


def test_zero_support_seed_is_dropped_not_counted_as_zero(tmp_path, monkeypatch):
    """🔴 **裁定 A（2026-09-26 用户裁定）**：某种子某类的 `support=0` ⇒ F1 是 **0/0 未定义**，
    `zero_division=0` 会把它记成 `0.0`。把它当「预测失败」计入均值，是把两件相反的事混为一谈。

    构造 Oyente 的真实情形（seed0 的 `time_manipulation` support=0）：
    剔除后 = mean(0.0, 1.0) = **0.5000 ± 0.7071**；不剔除则是 0.3333±0.5774（后者不可解读）。
    且该格**必须带 `‡`** —— `0.5000±0.7071` 与 3 种子均值长得一模一样，读者无从分辨。
    """
    import math
    for s, sup, f1 in ((0, [0] * 7, [0.0] * 7),
                       (1, [0, 0, 0, 0, 0, 1, 0], [0.0] * 7),
                       (2, [0, 0, 0, 0, 0, 1, 0], [0, 0, 0, 0, 0, 1.0, 0])):
        _write_eval_full(tmp_path, "oyente", s, sup, f1)
    monkeypatch.setattr(C, "BASE", tmp_path)
    md, _ = C.build()
    cells = _row_cells(md, "Oyente")
    assert cells[5] == "0.5000 ± 0.7071‡", f"0/0 的种子没有被剔除或没标 ‡：{cells[5]}"
    assert abs(0.7071 - round(math.sqrt(0.5), 4)) < 1e-4          # 自检：ddof=1 的两点标准差
    assert "support=0" in md and "（缺 seed0）" in md, "被剔除的格必须逐格列出来"


# ------------------------------------------------------------------ 7. 跑动环境约束要披露


def test_run_env_constraint_is_disclosed(tmp_path, monkeypatch):
    """🔴 manticore 本轮受了 **cgroup 内存上限**（本机只有 7.8 GB，而它默认起 24 个 z3 进程）。

    报告里只需**一行**（用户 2026-09-26 裁定：论文披露不堆细节）：那一行是在加了内存上限的
    条件下跑的。事实与细节留在 `run_env.json` 与 `decisions.md` §56.7。
    """
    (tmp_path / _stem("manticore")).mkdir(parents=True)
    (tmp_path / f"{_stem('manticore')}.json").write_text("{}", encoding="utf-8")
    (tmp_path / _stem("manticore") / "run_env.json").write_text(json.dumps({
        "mem_cap": "5G", "cgroup_oom_kills_syslog_total": 5,
        "note_kills": "全机累计", "core_procs": "默认 24", "flush_every": 1,
    }, ensure_ascii=False), encoding="utf-8")
    monkeypatch.setattr(C, "BASE", tmp_path)
    md, _ = C.build()
    # 🔴 收敛为**一行**（用户 2026-09-26：论文披露不要堆细节；细节留在 run_env.json 与 §56.7）
    assert "cgroup 内存上限 5G" in md and "run_env.json" in md and "§56.7" in md
