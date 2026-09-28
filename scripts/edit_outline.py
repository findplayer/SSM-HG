#!/usr/bin/env python3
"""`研究点一细化大纲改II.docx` 的**可审计改写器**：把「补全实现细节」的编辑写成声明式清单，
默认 **dry-run 只打印 diff**，`--apply` 才落盘，落盘前先在 `runs/_snap/` 存一份带时间戳的备份。

🔴 **为什么不手改**：大纲 220 段 / 18 表，本次要动几十处（改数值 + 插新段）。
手改无法复核、无法回滚、也无法证明「只改了该改的」。

🔴 **格式保真的两条硬技术**（本脚本的全部价值所在）：
  1. **run 级子串替换**（`replace_in_para`）：段落里的文字被 Word 按中英边界切成了几十个
     run（实测最多 73 个），**但它们的格式逐位相同**（`bold/size/name` 全 None，
     `Times New Roman`）——即 run 边界不是格式边界。故本脚本**只动被替换区间覆盖的那几个
     run 的 `text`**，其余 run 一个字都不碰，字号/字体/加粗/语言属性全部原样保留。
     实测全库仅 14/500 段格式不统一，且差异几乎只是中英字体名（`Times New Roman`/`宋体`），
     用本法则连这 14 段也不必特殊处理。
  2. **样式克隆插入**（`insert_after`）：新段不是凭空造一个，而是 `deepcopy` 一个**参照段的
     `<w:p>` XML** 再清空文字 ⇒ 段落样式、run 属性、编号、缩进全部继承。凭空造段在
     Word 里会变成「无格式段落」，肉眼可见。

用法（仓库根目录）：
    python scripts/edit_outline.py                  # dry-run：逐条打印 diff，不落盘
    python scripts/edit_outline.py --apply          # 落盘（先备份到 runs/_snap/）
    python scripts/edit_outline.py --list           # 只列将要动的段落地址与前后文本
    python scripts/edit_outline.py --verify         # 落盘后复核：逐条确认新文本已在文档里
"""
from __future__ import annotations

import argparse
import copy
import difflib
import shutil
import sys
from datetime import datetime
from pathlib import Path

import docx
from docx.table import Table
from docx.text.paragraph import Paragraph

REPO = Path(__file__).resolve().parents[1]
OUTLINE = REPO / "研究点一细化大纲改II.docx"
SNAP = REPO / "runs" / "_snap"


# ----------------------------------------------------------------- 段落寻址
def walk(doc) -> list[tuple[str, Paragraph]]:
    """按文档流顺序返回 `[(地址, 段落)]`。

    地址形如 `body:72` / `T4:r1:c1:p0`——**表格内段落也算**（表格才是大纲里信息最密的地方，
    只走 `doc.paragraphs` 会把它们全漏掉，这是 python-docx 最常见的坑）。
    """
    out: list[tuple[str, Paragraph]] = []
    for i, p in enumerate(doc.paragraphs):
        out.append((f"body:{i}", p))
    for ti, t in enumerate(doc.tables):
        for ri, row in enumerate(t.rows):
            for ci, cell in enumerate(row.cells):
                for pi, p in enumerate(cell.paragraphs):
                    out.append((f"T{ti}:r{ri}:c{ci}:p{pi}", p))
    return out


def index(doc) -> dict[str, Paragraph]:
    return {addr: p for addr, p in walk(doc)}


def find_table(doc, needle: str) -> Table:
    """按**单元格文本**定位表——抗表号位移。

    🔴 为什么要这个：本脚本会往文档里插表，**插在中间会把后面所有表的 `tables[i]` 下标顶掉**
    （实测：§4.7 插 8 张表后 `T13` 变成 `T21`）。凡「表号」在多次编辑之间传递，
    第二次就会改错对象——而且**不报错**。故凡涉表的编辑一律改用内容定位。
    """
    hits = [t for t in doc.tables
            if any(needle in c.text for r in t.rows for c in r.cells)]
    if len(hits) != 1:
        raise SystemExit(f"🔴 用 {needle!r} 命中 {len(hits)} 张表（要求恰 1 张）")
    return hits[0]


def resolve_anchor(doc, idx: dict, spec: str) -> Paragraph:
    """锚点解析：**先用原地址，找不到再按段落文字前缀定位**。

    🔴 为什么要有「按文字定位」这条退路：本脚本自己会插段，插完**锚点的 `body:N` 就位移了**
    （实测在 `body:168` 插 16 段后，`T13:r1:c2:p1` 这个单元格地址再也解析不出来，
    重跑直接以「地址不存在」失败）。凡锚点地址可能因本脚本自身的改动而失效的，
    就改用文字前缀——它对位移免疫。
    """
    if spec in idx:
        return idx[spec]
    hits = [q for q in all_paragraphs(doc) if text_of(q).startswith(spec)]
    if len(hits) != 1:
        raise SystemExit(f"🔴 锚点 {spec!r}：既不是地址，按文字前缀也命中 {len(hits)} 段（要求恰 1）")
    return hits[0]


def all_paragraphs(doc) -> list[Paragraph]:
    """正文段 + 全部表格单元格段（用于 --verify 的全域搜索）。"""
    out = list(doc.paragraphs)
    for t in doc.tables:
        for row in t.rows:
            for cell in row.cells:
                out.extend(cell.paragraphs)
    return out


def text_of(p: Paragraph) -> str:
    return "".join(r.text for r in p.runs)


# ----------------------------------------------------------------- 编辑原语
def replace_in_para(p: Paragraph, old: str, new: str) -> bool:
    """在段落**跨 run** 地替换 `old` → `new`，**只改被覆盖的 run**，格式零损伤。

    返回是否命中。`old` 必须**唯一**（出现 0 次或 ≥2 次都算失败并返回 False），
    否则会改错地方——这条比"能不能改"更重要。
    """
    runs = list(p.runs)
    full = "".join(r.text for r in runs)
    n = full.count(old)
    if n != 1:
        return False
    i = full.index(old)
    j = i + len(old)
    pos = 0
    for r in runs:
        rs, re_ = pos, pos + len(r.text)
        pos = re_
        if re_ <= i or rs >= j:          # 与替换区间不相交 ⇒ 一字不动
            continue
        head = r.text[: max(0, i - rs)]
        tail = r.text[max(0, j - rs):]
        r.text = (head + new + tail) if rs <= i < re_ else (head + tail)
    return True


def insert_before(anchor: Paragraph, lines: list[str], clone_from: Paragraph) -> list[Paragraph]:
    """在 `anchor` **之前**插入若干新段（格式克隆自 `clone_from`）。

    ⚠ 与 `insert_after` 的分工：**「插在表格之后」只能用 `insert_before`**——
    python-docx 的段落对象拿不到「表格后面」这个位置，得改成「插在表格后面那个段落的**前面**」。
    本仓大纲里 §4.6 结束于一张表（T12），要在它之后加 §4.7 就必须用这个方向。
    """
    made: list[Paragraph] = []
    cur = anchor
    for line in lines:
        new_p = copy.deepcopy(clone_from._p)
        cur._p.addprevious(new_p)
        para = Paragraph(new_p, anchor._parent)
        runs = list(para.runs)
        if not runs:
            para.add_run("")
            runs = list(para.runs)
        runs[0].text = line
        for r in runs[1:]:
            r.text = ""
        made.append(para)
        # 逐行插在「上一行之前」会倒序，故每行都插在 anchor 之前（保持先后）
    return made


def insert_table_before(anchor: Paragraph, rows: list[list[str]], style_ref: Table,
                        doc) -> Table:
    """在 `anchor` **之前**插入一张表，**样式与单元格字体克隆自 `style_ref`**。

    做法：先 `doc.add_table`（会追加到文末）再把它整块 `<w:tbl>` **搬**到锚点前。
    比手工拼 `<w:tbl>` XML 稳得多——表样式（边框/底纹）、列宽策略、`tblPr` 全部继承。
    单元格文字用参照表 `style_ref` 首个数据格 run 的字体名，避免新表单元格变成默认字体。
    """
    # ⚠ `Paragraph._parent` 是 `_Body`/`_Cell`（`BlockItemContainer`），它的 `add_table`
    #   要额外传 `width`；只有真 `Document.add_table(rows, cols)` 才是我们要的签名。
    #   故 `doc` 由调用方显式传入，不去猜。
    ref_run = None
    for r in style_ref.rows[0].cells[0].paragraphs[0].runs:
        ref_run = r
        break
    # 参照格常常**不显式写字体**（继承表样式），此时显式给正文默认字体，
    # 否则新格会落到 Word 的默认（可能是等线/Calibri），与全表不一致
    font_name = (ref_run.font.name if ref_run is not None else None) or "Times New Roman"
    size = ref_run.font.size if ref_run is not None else None

    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    try:
        t.style = style_ref.style
    except Exception:
        pass
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            cell = t.cell(ri, ci)
            cell.text = ""
            run = cell.paragraphs[0].add_run(val)
            if font_name:
                run.font.name = font_name
            if size:
                run.font.size = size
    anchor._p.addprevious(t._tbl)
    return t


def insert_after(anchor: Paragraph, lines: list[str], clone_from: Paragraph) -> list[Paragraph]:
    """在 `anchor` 之后插入若干新段，**样式与 run 格式克隆自 `clone_from`**。

    多行时第 1 行用 `clone_from` 的格式，其余行同样克隆（同一参照段）——
    段内不再细分格式，因为原文档的段内格式本就统一（见模块 docstring）。
    """
    made: list[Paragraph] = []
    cur = anchor
    for line in lines:
        new_p = copy.deepcopy(clone_from._p)
        cur._p.addnext(new_p)
        para = Paragraph(new_p, anchor._parent)
        runs = list(para.runs)
        if not runs:                                  # 参照段无 run ⇒ 补一个空的
            para.add_run("")
            runs = list(para.runs)
        runs[0].text = line
        for r in runs[1:]:
            r.text = ""
        made.append(para)
        cur = para
    return made


# ----------------------------------------------------------------- 编辑清单
# 内容真源在 `scripts/outline_spec.py`（引擎与内容分离：改内容不必碰引擎）。
# 每条 = ("replace", 地址, 旧文本, 新文本)
#      | ("insert"|"insert_before", 地址, [(文本, 克隆源地址), ...])
#      | ("table_before", 地址, 行数据, 参照表号)
#      | ("block_before", 地址, [("para", 文本, 克隆源)|("table", 行数据, 参照表号), ...])
# 🔴 `replace` 的 `old` 必须在该段落里**唯一**出现；引擎硬校验，命中数 ≠ 1 直接报错中止。
sys.path.insert(0, str(Path(__file__).resolve().parent))
from outline_spec import EDITS                                       # noqa: E402


def block_para_texts(kind: str, spec_block) -> list[str]:
    """插入类编辑里**全部段落**的文字（表格项跳过 —— 表没有可靠的"首段"判据）。

    `insert`/`insert_before` 的 spec 是 `[(text, clone_ref), …]`；
    `block_before` 的是 `[("para", text, clone_ref) | ("table", rows, style_ref), …]`。
    """
    if kind == "block_before":
        return [it[1] for it in (spec_block or []) if it and it[0] == "para"]
    return [it[0] for it in (spec_block or []) if it]


def insert_table_row_after(tbl: Table, ref_text: str, cells: list[str]) -> None:
    """在「首格文本含 `ref_text`」的那一行**之后**插入一行（内容 `cells`）。

    **为什么要深拷贝 `<w:tr>` 而不是 `Table.add_row()`**：本仓大纲的表格靠表样式 +
    逐格 `tcPr` 控制边框/底纹/列宽，`add_row()` 只保证格数对得上，不保证这些属性克隆。
    深拷贝参照行的 XML 则让新行的 `trPr`/`tcPr`/`gridSpan` **与参照行逐字一致**。
    单元格文字写进「该格已有的第一个 run」以保留其 `rPr`（字体/字号/加粗），
    没有 run 才新建 —— 与 `replace_in_para` 的思路一致。
    """
    ref_idx = None
    for i, row in enumerate(tbl.rows):
        if ref_text in row.cells[0].text:
            ref_idx = i
            break
    if ref_idx is None:
        raise SystemExit(f"🔴 插表行：在表里找不到首格含 {ref_text!r} 的参照行")
    ref_tr = tbl.rows[ref_idx]._tr
    ref_tr.addnext(copy.deepcopy(ref_tr))
    row = tbl.rows[ref_idx + 1]                 # 重新取，`addnext` 后才会含新行
    if len(cells) != len(row.cells):
        raise SystemExit(f"🔴 插表行：给了 {len(cells)} 格，但参照行有 {len(row.cells)} 格")
    for ci, val in enumerate(cells):
        cell = row.cells[ci]
        for extra in cell.paragraphs[1:]:        # 参照行的格可能多段，收成一段
            extra._p.getparent().remove(extra._p)
        p0 = cell.paragraphs[0]
        runs = p0.runs
        if runs:
            runs[0].text = val
            for r in runs[1:]:
                r._r.getparent().remove(r._r)
        else:
            p0.add_run(val)


def apply_edits(doc, edits, *, dry: bool, clone_pool: dict[str, Paragraph]):
    """逐条执行；任何一条失败即中止（**不允许"部分成功"**——那会留下半改状态）。"""
    idx = index(doc)
    log: list[str] = []
    for e in edits:
        kind, addr = e[0], e[1]
        # 🔴 **只有真正需要段落锚点的编辑类型才校验地址**：
        #    `replace` 现在按内容定位（`addr` 仅当日志标签），`replace_in_table` 的 `e[1]`
        #    是表定位句、根本不是地址——对它们做存在性检查会把合法编辑误判为「地址不存在」。
        #    （这条在给 `replace_in_table` 加幂等分支时实测踩到，表现为 rc=1 +「地址不存在：消息传递层数L」。）
        _USES_ADDR = ("insert", "insert_before", "table_before", "block_before")
        p = None
        if kind in _USES_ADDR:
            p = resolve_anchor(doc, idx, addr)
            # 幂等判据 = **本块的「全部」段落文字是否都已在文档里**（不是只看首段）。
            # 🔴 只看首段的旧判据有个**静默洞**（2026-09-25 实测）：
            #   改了 `outline_spec.py` 里块的**内容**而首段未动时，重跑会报「已应用」
            #   并**把改动丢掉** —— 实测 §4.7 路径表的 5 行改动就是这样没进 docx 的
            #   （docx 里 `graphs_ft_p2` 出现 0 次，而脚本说"已应用"）。
            #   现在：全在 ⇒ 跳过；**部分在 ⇒ 响亮报错**并列出缺哪些。
            block_texts = block_para_texts(kind, e[2])
            if block_texts:
                # ⚠ 判据必须是**全文相等**，不能用 `startswith(t[:40])` 之类的**前缀**匹配——
                #   前缀匹配对本仓的改动形态是瞎的（实测：`_S471_NOTE` 只把
                #   `graphs_ft` 改成 `graphs_ft_p2`，差异落在第 40 字符**之后**，
                #   于是"全部命中"、静默跳过）。比较前统一压掉空白。
                def _norm(x: str) -> str:
                    return "".join(x.split())
                doc_texts = {_norm(text_of(q)) for q in all_paragraphs(doc)}
                present = [t for t in block_texts if _norm(t) in doc_texts]
                if len(present) == len(block_texts):
                    log.append(f"### {addr}  [{kind}] ⏭ 已应用，跳过")
                    continue
                if present:
                    missing = [t for t in block_texts if t not in present]
                    raise SystemExit(
                        f"🔴 {addr} [{kind}]: 本块 {len(present)}/{len(block_texts)} 段已在文档里，"
                        f"但**内容已分叉** —— `outline_spec.py` 改过而 docx 没跟着改。\n"
                        f"    缺失 {len(missing)} 段（列前 3）：\n      "
                        + "\n      ".join(x[:70] for x in missing[:3])
                        + "\n    ⇒ **不得让它静默跳过**；请改用 `replace`/`replace_in_table` "
                          "逐处修改，或先手工移除该块再重跑。")
                # 一段都不在 ⇒ 正常插入
            elif kind != "block_before":
                probe = e[2][0][0] if e[2] else None
                if probe and any(text_of(q).startswith(probe[:40]) for q in all_paragraphs(doc)):
                    log.append(f"### {addr}  [{kind}] ⏭ 已应用，跳过")
                    continue
        if kind == "replace":
            old, new = e[2], e[3]
            # 可选第 5 元 `"superseded"`：本条的**效果已被清单里更后面的另一条 `replace` 覆盖**
            #（「append-only 编辑清单」的必然产物——同一段落改两次 = 两条编辑，前一条的输出不再是终态）。
            # 🔴 为什么必须显式标记而不是让它报错：落盘后前一条的 `old` 与 `new` **都不在**文档里
            #   （old 被它自己换掉了、new 又被后一条换掉了）⇒ 不标记就会把「正常的历史编辑」
            #   误报成「旧文本和新文本都找不到」并中止整批。`--verify` 亦跳过。
            # ⚠ 不会因此漏改：目标段落的终态文本仍被块级守卫（`block_before` 的全文相等判）盯着
            #   ⇒ 若后一条编辑丢失，守卫会立刻 `SystemExit`，不会静默通过。
            superseded = len(e) > 4 and e[4] == "superseded"
            # 🔴 **按内容定位，不用 `addr`**：本脚本会插段，插完原文地址整体位移
            #    （实测在 `body:168` 插 16 段后，`body:196` 指向了另一个段落）。
            #    用地址回查在第二次运行时会**改错段落而且不报错**。`addr` 现在只当日志标签。
            #    唯一性要求仍在：全文档必须**恰有一个**段落含 `old`。
            hits = [q for q in all_paragraphs(doc) if old in text_of(q)]
            if len(hits) == 0:
                # 幂等：本批编辑之前已施加过 ⇒ 旧文本没了、新文本在了 ⇒ 跳过而不是报错。
                #（闸门后要**追加**编码器编辑再跑一次，这条让第二批不必重放第一批。）
                if any(new in text_of(q) for q in all_paragraphs(doc)):
                    log.append(f"### {addr}  [replace] ⏭ 已应用，跳过")
                    continue
                if superseded:
                    log.append(f"### {addr}  [replace] ⏭ 已被后续编辑取代（历史编辑），跳过")
                    continue
                raise SystemExit(f"🔴 {addr}: 全文找不到旧文本，也没找到新文本\n    old={old!r}")
            if len(hits) > 1:
                raise SystemExit(f"🔴 {addr}: 旧文本命中 {len(hits)} 个段落（要求恰 1 个）\n    old={old!r}")
            p = hits[0]
            before = text_of(p)
            ok = replace_in_para(p, old, new)
            if not ok:
                raise SystemExit(f"🔴 {addr}: 替换失败")
            after = text_of(p)
            log.append(f"### {addr}  [replace]\n- {before}\n+ {after}")
        elif kind in ("insert", "insert_before"):
            # 逐行 `(文本, 克隆源地址)`——标题与正文样式不同，**必须能逐行指定参照段**
            #（否则标题会被赋予正文字号，或正文被赋予标题字号）
            items = e[2]
            fn = insert_after if kind == "insert" else insert_before
            before = text_of(p)
            log.append(f"### {addr}  [{kind} {len(items)} 段]\n  锚点原文: {before[:80]}…")
            for text, ref in items:
                ref_p = idx.get(ref)
                if ref_p is None:
                    raise SystemExit(f"🔴 克隆源地址不存在：{ref}")
                fn(p, [text], ref_p)
                log.append(f"  + [{ref}] {text[:110]}")
        elif kind == "replace_in_table":
            # ("replace_in_table", 表定位句, 旧文本, 新文本)——**抗表号位移**（见 find_table）
            needle, old, new = e[1], e[2], e[3]
            # 可选第 5 元 `"exact"`：要求**整格文本恰好等于 `old`**（压掉首尾空白）。
            # 🔴 为什么需要（2026-09-25 实测）：`old` 是**子串**匹配，而本表里
            #   `…/encoder` 同时是 `…/encoder（**原地保留，未删**）` 与 `…/encoder/（HF…）`
            #   的前缀 ⇒ 一旦表里新增了含该前缀的格，子串匹配就会改错格**且不报错**。
            #   ⚠ 本次实测正是：`table_row_after` 新插的「消融档」行含
            #   `runs/codebert_ft/alldata/ss{S}/encoder（**原地保留，未删**）`，
            #   第二次 `--apply` 会把那一格也改成新路径（干跑时发现，磁盘未受影响）。
            exact = len(e) > 4 and e[4] == "exact"
            # 🔴 **定位句本身可能就是要被替换掉的文本**（`needle == old` 那种写法）——
            #   于是「已应用」时定位句当然找不到。此时若直接让 `find_table` 抛，
            #   幂等重跑就会误报成「定位失败」（2026-09-25 实测踩到，编辑 #8 正是这种）。
            #   判据 = 「`new` 已在某张表里」⇒ 跳过；否则才是真的定位失败。
            _hits = [t for t in doc.tables
                     if any(needle in c.text for r in t.rows for c in r.cells)]
            if not _hits:
                if any(new in c.text for t in doc.tables for r in t.rows for c in r.cells):
                    log.append(f"### [table:{needle}]  [replace_in_table] "
                               f"⏭ 已应用（定位句自身已被替换），跳过")
                    continue
                raise SystemExit(f"🔴 用 {needle!r} 命中 0 张表，且未在任何表中找到新文本\n"
                                 f"    new={new!r}")
            if len(_hits) > 1:
                raise SystemExit(f"🔴 用 {needle!r} 命中 {len(_hits)} 张表（要求恰 1 张）")
            tbl = _hits[0]
            cand = [pp for row in tbl.rows for c in row.cells for pp in c.paragraphs
                    if (text_of(pp).strip() == old if exact else old in text_of(pp))]
            # ⚠ 幂等判**必须排在唯一性判之前**：已应用时 `old` 命中 0 个段，
            #   若先判 `len(cand) != 1` 就会把「已应用」误报成「找不到」。
            if len(cand) == 0:
                if any(new in text_of(pp) for row in tbl.rows for c in row.cells
                       for pp in c.paragraphs):
                    log.append(f"### [table:{needle}]  [replace_in_table] ⏭ 已应用，跳过")
                    continue
                raise SystemExit(f"🔴 表内 {needle!r} 找不到旧文本，也没找到新文本\n    old={old!r}")
            if len(cand) != 1:
                raise SystemExit(
                    f"🔴 表内 {needle!r} 命中 {len(cand)} 个含旧文本的段（要求恰 1）\n    old={old!r}")
            before = text_of(cand[0])
            if before.count(old) != 1:
                raise SystemExit(f"🔴 表内 {needle!r}: 旧文本出现 {before.count(old)} 次")
            replace_in_para(cand[0], old, new)
            log.append(f"### [table:{needle}]  [replace_in_table]\n- {before}\n+ {text_of(cand[0])}")
        elif kind == "table_row_after":
            # ("table_row_after", 表定位句, 参照行首格文本, [新行各格...])——**抗表号位移**
            needle, ref_text, cells = e[1], e[2], e[3]
            _hits = [t for t in doc.tables
                     if any(needle in c.text for r in t.rows for c in r.cells)]
            if len(_hits) != 1:
                raise SystemExit(f"🔴 插表行：用 {needle!r} 命中 {len(_hits)} 张表（要求恰 1 张）")
            tbl = _hits[0]
            # 幂等：新行的首格文本已在表里 ⇒ 已插过（重跑不得插第二遍）
            if any(cells[0] in row.cells[0].text for row in tbl.rows):
                log.append(f"### [table:{needle}]  [table_row_after] ⏭ 已应用，跳过")
                continue
            insert_table_row_after(tbl, ref_text, cells)
            log.append(f"### [table:{needle}]  [table_row_after] ＋新行：{cells[0]}")
        elif kind == "block_before":
            # 一整节：段落与表格交替，**按给定顺序**落进锚点之前。
            # 逐项 = ("para", 文本, 克隆源地址) | ("table", 行数据, 参照表号)
            log.append(f"### {addr}  [block_before {len(e[2])} 项]")
            for item in e[2]:
                if item[0] == "para":
                    _, text, ref = item
                    ref_p = idx.get(ref)
                    if ref_p is None:
                        raise SystemExit(f"🔴 克隆源地址不存在：{ref}")
                    insert_before(p, [text], ref_p)
                    log.append(f"  ¶ [{ref}] {text[:110]}")
                elif item[0] == "table":
                    _, rows, ref_tbl = item
                    if not isinstance(ref_tbl, int) or ref_tbl >= len(doc.tables):
                        raise SystemExit(f"🔴 参照表号非法：{ref_tbl}")
                    insert_table_before(p, rows, doc.tables[ref_tbl], doc)
                    log.append(f"  ▦ [{len(rows)}×{len(rows[0])}] 首行: "
                               + " | ".join(c[:22] for c in rows[0]))
                else:
                    raise SystemExit(f"🔴 block 内未知项：{item[0]}")
        elif kind == "table_before":
            rows, ref_tbl = e[2], e[3]
            if not isinstance(ref_tbl, int) or ref_tbl >= len(doc.tables):
                raise SystemExit(f"🔴 参照表号非法：{ref_tbl}")
            insert_table_before(p, rows, doc.tables[ref_tbl], doc)
            log.append(f"### {addr}  [table_before {len(rows)}行×{len(rows[0])}列]\n"
                       + "\n".join("  | " + " | ".join(c[:28] for c in r) for r in rows[:3])
                       + (f"\n  …共 {len(rows)} 行" if len(rows) > 3 else ""))
        else:
            raise SystemExit(f"🔴 未知编辑类型：{kind}")
    return log


def main() -> int:
    ap = argparse.ArgumentParser(description="大纲改写器（默认 dry-run）")
    ap.add_argument("--apply", action="store_true", help="落盘（先备份到 runs/_snap/）")
    ap.add_argument("--list", action="store_true", help="只列编辑清单")
    ap.add_argument("--verify", action="store_true", help="复核：确认所有新文本已在文档中")
    args = ap.parse_args()

    if not EDITS:
        print("编辑清单 `EDITS` 为空——尚未填写任何编辑。")
        return 0

    if args.list:
        for e in EDITS:
            kind, addr = e[0], e[1]
            extra = ""
            if kind in ("insert", "insert_before"):
                extra = f"  {len(e[2])} 段（克隆源 {e[2][0][1]}）"
            elif kind == "table_before":
                extra = f"  {len(e[2])}×{len(e[2][0])} 表（参照 T{e[3]}）"
            elif kind == "block_before":
                n_t = sum(1 for it in e[2] if it[0] == "table")
                extra = f"  {len(e[2])} 项（{len(e[2]) - n_t} 段 + {n_t} 表）"
            print(f"{kind:13s} {addr}{extra}")
        return 0

    doc = docx.Document(str(OUTLINE))

    if args.verify:
        # 🔴 **全域搜索**，不按地址回查：本脚本会插段插表，插完之后原文的 `body:N` / `T{i}`
        #    全部位移（实测 §4.7 插 8 表后 `T13` 变 `T21`）⇒ 用地址复核必然误报「未找到」。
        #    判据改为「新文本在文档里出现、且旧文本不再出现」——这两条都抗位移。
        parts = [text_of(p) for p in all_paragraphs(doc)]
        bad = 0
        for e in EDITS:
            kind = e[0]
            if kind == "replace":
                addr, old, new = e[1], e[2], e[3]
                if len(e) > 4 and e[4] == "superseded":
                    continue          # 见 `apply_edits` 的说明：输出已被后续编辑覆盖
            elif kind == "replace_in_table":
                addr, old, new = f"table:{e[1]}", e[2], e[3]
            else:                                    # insert/table/block：无需复核文本
                continue
            # ⚠ **不能在全文里搜 `old`**：`old` 常是 "0.1" 这种短串，别处（甚至别的数字里）
            #   照样命中 ⇒ 必然误报「旧文本仍在」（本脚本首版实测踩到）。
            #   正确判据 = 「含 `new` 的那个段落里，`old` 不再出现」。
            holders = [t for t in parts if new in t]
            if not holders:
                print(f"❌ {addr}: 新文本未出现")
                bad += 1
            elif any(old in t for t in holders):
                print(f"❌ {addr}: 含新文本的段落里旧文本仍在（半改状态）")
                bad += 1
        n_checked = sum(1 for e in EDITS if e[0] in ("replace", "replace_in_table"))
        print(f"[verify] {n_checked - bad}/{n_checked} 条文本编辑通过（全域搜索）")
        return 1 if bad else 0

    idx = index(doc)
    log = apply_edits(doc, EDITS, dry=not args.apply, clone_pool=idx)
    print("\n\n".join(log))

    if args.apply:
        SNAP.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        bak = SNAP / f"outline-before-{stamp}.docx"
        shutil.copy2(OUTLINE, bak)
        doc.save(str(OUTLINE))
        print(f"\n[outline] 已落盘 {OUTLINE.name}；备份 {bak.relative_to(REPO)}")
    else:
        print("\n[dry-run] 未落盘。加 --apply 生效。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
