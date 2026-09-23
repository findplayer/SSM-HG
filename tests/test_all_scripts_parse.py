#!/usr/bin/env python3
"""全仓脚本的**语法守卫**（2026-09-21 新增）。

**为什么需要**：pytest 只在**被 import 的**模块上暴露 `SyntaxError`。`scripts/` 下多数脚本
**不被任何测试 import**（它们是命令行入口），于是语法错误可以一路走到真正要跑它的时候才炸。

**具体成因**：本项目文档一律中文，而中文引号里常夹 ASCII 引号，写成
`f"…是"这一格"的 t…"`。**这不是"f-string 嵌套引号"的版本问题**——实测 tokenize 会把它切成
两个独立的 STRING token（`f"…是"` 与 `"的 t…"`），中间夹一个**裸标识符**，于是它退化成
**隐式字符串拼接 + 语法错误**，在**任何 Python 版本**下都报错，`ast.parse` 一律能抓到。

实测频率：2026-09-21 一天内**四次**（`collect_ablation_n9.py` 三次），每次都是
「改完文档字符串没跑测试」⇒ 下次用到才炸。代价极低但反复发生，故机检。

修复方式：中文语境里的内层引号一律用 `「」`（本仓惯例），不要用 `"`。

运行：`pytest tests/test_all_scripts_parse.py -q`
"""
from __future__ import annotations

import ast
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCAN_DIRS = ("scripts", "tests")

# 合成样本：**必须被判为语法错误**。守卫自己也要有机检，否则"测试全绿"可能只是它没在看。
_SHOULD_FAIL = 'doc += [f"…是"这一格"的 t…"]\n'


def _py_files():
    for d in SCAN_DIRS:
        for p in sorted((REPO / d).glob("*.py")):
            yield p


def test_the_guard_can_actually_detect_the_pattern():
    """🔴 自证：把一个**已知会炸**的样本喂给 `ast.parse`，必须报 SyntaxError。

    没有这一条的话，`test_every_script_parses` 全绿只说明"当前仓库碰巧没这问题"，
    **不说明这个检查方式对该问题有效**（本仓反复记录的"判据写反/太松"）。
    写法一旦被误改成"搜索某个字符串"，这条会立刻红。
    """
    try:
        ast.parse(_SHOULD_FAIL)
    except SyntaxError as e:
        assert "invalid syntax" in str(e).lower() or e.lineno == 1, str(e)
        return
    raise AssertionError(
        "合成样本竟然通过了 ast.parse —— 本守卫的检查方式已失效，"
        "说明它抓不到「中文里嵌 ASCII 引号」那个真实成因")


def test_every_script_parses():
    """`scripts/` 与 `tests/` 下每个 `.py` 都必须能被 `ast.parse` 解析。"""
    bad: list[str] = []
    n = 0
    for p in _py_files():
        n += 1
        try:
            ast.parse(p.read_text(encoding="utf-8"), filename=str(p))
        except SyntaxError as e:
            bad.append(f"{p.relative_to(REPO)}:{e.lineno}: {e.msg}")
    assert n > 0, "一个 .py 都没扫到 —— 路径写错了？"
    assert not bad, ("以下脚本有语法错误（**不被 import 的脚本不会在任何测试里暴露**）：\n  "
                     + "\n  ".join(bad))
