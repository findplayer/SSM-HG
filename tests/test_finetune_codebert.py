"""微调脚本（§6.4）的回归锁。

**三条最要命的性质**，全部是"错了也不报错"那一类：
  1. **文本口径与 M3 同源**——若微调用的函数文本与 M3 编码的函数文本哪怕差一个字符，
     变体 `_cb.pt` 与正典的差异就同时包含"编码器变了"和"文本口径变了"两个变量，
     本项立刻不再是单变量消融。本仓已有 §29.4 的同类教训。
  2. **合约内 mean-pool 的归一化**——分母错（用批内序列数而不是该合约自己的函数数）
     只会让梯度尺度不对，不报错，训练照样"能跑"。
  3. **`_feat.pt` 的形参一致性**（见 `tests/test_m3_cb_cache.py` / `build_graph_variant.py` 的断言）。
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest
import torch
import torch.nn as nn

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

import finetune_codebert as ft      # noqa: E402
import m3_build_features as m3      # noqa: E402


def _fake_graph(tmp_path: Path) -> Path:
    """造一张最小 `_hetero.json`：两个函数、各 3 行源码。"""
    src = tmp_path / "c.sol"
    src.write_text("line1\nline2\nline3\nline4\nline5\nline6\n", encoding="utf-8")
    graph = {
        "meta": {"source_path": str(src)},
        "functions": [
            {"contract": "C", "function": "a", "start_line": 1, "end_line": 3},
            {"contract": "C", "function": "b", "start_line": 4, "end_line": 6},
        ],
        "nodes": [],
        "edges": {},
    }
    (tmp_path / "g_hetero.json").write_text(json.dumps(graph), encoding="utf-8")
    (tmp_path / "g_m1.json").write_text(json.dumps({"node_scores": {}}), encoding="utf-8")
    return tmp_path


def test_finetune_text_is_byte_identical_to_m3_text(tmp_path):
    """微调的函数文本必须与 M3 的**逐字节相同**（同源，不另写一份）。"""
    d = _fake_graph(tmp_path)
    got = ft.contract_texts(d, ["g"])["g"]
    data = m3.load_graph(d / "g_hetero.json", d / "g_m1.json")
    src = data["src_lines"]
    want = ["\n".join(src[f["start_line"] - 1:f["end_line"]])
            for f in sorted(data["fn_table"].values(), key=lambda f: (f["contract"], f["function"]))]
    assert got == want == ["line1\nline2\nline3", "line4\nline5\nline6"]


class _StubEncoder(nn.Module):
    """把每条序列映射成"由它**首个 token 的值**决定的常数向量"。便于手算 mean-pool。

    ⚠ 不能按"批内第 i 条 → 常数 i"来造：micro-batch 是分块的，计数器会**每块归零**，
    于是同一合约的均值依赖于分块方式——那样的桩测不出"分母用错"这类缺陷。
    改用输入内容编码，分块与否都不变。

    ⚠ 必须实现 `forward(input_ids, attention_mask)`（而不是名为 `encode` 的方法）：
    `CodeBertContract.encode` 以**关键字参数**调用 `self.encoder(...)`，走 `nn.Module.__call__`。
    """

    def __init__(self, dim: int = 4):
        super().__init__()
        self.dim = dim
        self.p = nn.Parameter(torch.zeros(1))

    def forward(self, input_ids, attention_mask):        # noqa: ARG002 — 桩只需首 token
        # `CodeBertContract.encode` 读 `.last_hidden_state[:, 0, :]`，故给出同构 [B, 1, dim]
        vals = input_ids[:, 0].float()
        hidden = vals[:, None, None].expand(-1, 1, self.dim).contiguous()
        return _Out(hidden)


class _Out:
    def __init__(self, t):
        self.last_hidden_state = t


def _stub_model():
    m = ft.CodeBertContract.__new__(ft.CodeBertContract)     # 跳过 __init__（不加载真 BERT）
    nn.Module.__init__(m)
    m.encoder = _StubEncoder()
    return m


def test_pooled_contracts_normalizes_per_contract_not_per_batch():
    """分母必须是**该合约自己的函数数**。若误用批内总数，下面的手算值会对不上。"""
    model = _stub_model()
    seqs_of = {"A": [torch.tensor([0]), torch.tensor([1])], "B": [torch.tensor([2])]}
    out = ft.pooled_contracts(model, seqs_of, ["A", "B"], seq_batch=8,
                              device="cpu", pad_id=0)
    # 序列顺序：A 的两条（第 0、1 条）→ 常数 0,1；B 的一条（第 2 条）→ 常数 2
    assert torch.allclose(out[0], torch.full((4,), 0.5)), out[0]
    assert torch.allclose(out[1], torch.full((4,), 2.0)), out[1]


def test_pooled_contracts_handles_uneven_micro_batches():
    """`seq_batch` 不整除总序列数时，最后一个 micro-batch 不能被丢掉。"""
    model = _stub_model()
    seqs_of = {"A": [torch.tensor([float(i)]) for i in range(5)]}
    out = ft.pooled_contracts(model, seqs_of, ["A"], seq_batch=2, device="cpu", pad_id=0)
    assert torch.allclose(out[0], torch.full((4,), 2.0)), out[0]   # (0+1+2+3+4)/5


def test_pad_batch_masks_the_padding():
    ids, mask = ft.pad_batch([torch.tensor([1, 2, 3]), torch.tensor([4])], "cpu", pad_id=9)
    assert ids.tolist() == [[1, 2, 3], [4, 9, 9]]
    assert mask.tolist() == [[1, 1, 1], [1, 0, 0]], "padding 位必须 mask 掉，否则 [CLS] 会被污染"


def test_tokenize_skips_empty_texts():
    """空文本与 M3 的 `zeros(768)` 语义一致：**不参与** mean-pool（否则分母被虚假增大）。"""
    class _Tok:
        pad_token_id = 0

        def __call__(self, text, **_kw):
            return {"input_ids": torch.tensor([[1] * max(1, len(text))])}

    out = ft.tokenize_all({"g": ["abc", "", "de"]}, _Tok(), 512)
    assert len(out["g"]) == 2, "空文本应被跳过"


# ---------------------------------------------------------------- 语料隔离（2026-09-18）
# 第 4 条"错了也不报错"的性质：**编码器的语料归属**。
# 原先 ①②两个语料共用 `runs/codebert_ft/ss{S}/encoder`，队列先跑 ① 再跑 ②，
# ② 那一步会看到 ① 的编码器而跳过微调，再拿它去重编码 ②。产物齐全、`_feat.pt` 断言过、
# `_cb.pt` 确实与原版不同（反向抽样也过）——**没有任何一处会失败**，
# 但这一项消融答的不是它要问的问题。故：路径带语料维度 + 边车硬校验。

def test_corpus_tag_splits_the_two_corpora():
    """两个语料必须派生出**不同**的 tag——这是隔离成立的前提。"""
    a = ft.corpus_tag("products/alldata/graphs")
    b = ft.corpus_tag("products/augmentation/graphs")
    assert a == "alldata" and b == "augmentation" and a != b


def test_corpus_tag_accepts_absolute_paths():
    """`--graph-dir` 传绝对路径时也必须得到同一个 tag（否则"同一语料两个路径"又混一起）。"""
    assert ft.corpus_tag(REPO / "products" / "alldata" / "graphs") == "alldata"
    assert ft.corpus_tag(REPO / "products" / "augmentation" / "graphs") == "augmentation"


def test_default_encoder_dirs_do_not_collide():
    """🔴 回归锁：两条语料的**默认编码器目录必须不同**。

    只要它们相同，"后跑的语料静默复用先跑的编码器"这个 bug 就会原样复活——
    而且从最终指标上完全看不出来。
    """
    import build_graph_variant as bgv
    main = bgv.default_encoder_dir(REPO / "products" / "alldata" / "graphs", 0)
    aug = bgv.default_encoder_dir(REPO / "products" / "augmentation" / "graphs", 0)
    assert main != aug
    assert main.parent.parent.name == "alldata"
    assert aug.parent.parent.name == "augmentation"
    # 与 finetune 侧的默认输出根**必须落在同一处**，否则一处写、另一处读，还是找不到
    assert str(main).startswith(str(ft.default_out_root(REPO / "products" / "alldata" / "graphs")))
    assert str(aug).startswith(str(ft.default_out_root(REPO / "products" / "augmentation" / "graphs")))


def test_build_cb_ft_refuses_missing_corpus_sidecar(tmp_path, monkeypatch):
    """缺边车 ⇒ 硬失败（不得"先跑起来再说"）。"""
    import build_graph_variant as bgv
    enc = tmp_path / "encoder"
    enc.mkdir()
    (enc / "config.json").write_text("{}", encoding="utf-8")     # HF 文件在、边车不在
    graphs = tmp_path / "graphs"
    graphs.mkdir()
    with pytest.raises(SystemExit) as e:
        bgv.build_cb_ft({"graphs": str(graphs)}, tmp_path / "v", enc, 0, force=False)
    assert "corpus.json" in str(e.value)


def test_build_cb_ft_refuses_cross_corpus_encoder(tmp_path):
    """🔴 核心回归锁：①的编码器 + ②的图 ⇒ 必须**报错退出**，而不是默默跑完。"""
    import build_graph_variant as bgv
    graphs = tmp_path / "products" / "augmentation" / "graphs"
    graphs.mkdir(parents=True)
    enc = tmp_path / "codebert_ft" / "alldata" / "ss0" / "encoder"
    enc.mkdir(parents=True)
    (enc / "config.json").write_text("{}", encoding="utf-8")
    (enc / "corpus.json").write_text(json.dumps({"corpus": "alldata"}), encoding="utf-8")
    with pytest.raises(SystemExit) as e:
        bgv.build_cb_ft({"graphs": str(graphs)}, tmp_path / "v", enc, 0, force=False)
    msg = str(e.value)
    assert "alldata" in msg and "augmentation" in msg
    assert "不匹配" in msg


def test_queue_script_uses_corpus_scoped_encoder_path():
    """队列脚本的跳过判据必须指向语料专属路径——否则它仍会跳过 ② 的微调。"""
    src = (REPO / "scripts" / "run_remaining_ablations.sh").read_text(encoding="utf-8")
    assert 'FT_ROOT="runs/codebert_ft/$DS"' in src
    assert '"$FT_ROOT/ss${S}/encoder/corpus.json"' in src
    # 旧的共用路径不得再出现在跳过判据里
    assert 'runs/codebert_ft/ss${S}/encoder/config.json' not in src


# ---------------------------------------------------------------- HF 离线回退（2026-09-21）


def test_hf_offline_fallback_retries_with_env(monkeypatch):
    """联网失败必须**自动回退到本地缓存**再试一次，且回退时把离线开关设进环境。

    为什么值得单测：这是 2026-09-21 实测事故的根因——本机 HF 缓存**完整**，
    但 `transformers` 默认联网重校验，一次 SSL 抖动就让**整次 40 分钟微调前功尽弃**
    （ss1 就是这么失败的，日志末尾是 `huggingface_hub` 的 SSLError）。
    回退逻辑写错的形态很隐蔽：比如"重试但没设环境变量"，那第二次仍走联网、仍然失败，
    而外层看到的是同一个异常——**与没写回退长得一模一样**。
    """
    import requests
    for k in ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE"):
        monkeypatch.delenv(k, raising=False)
    calls = []

    def loader():
        calls.append(dict(os.environ))
        if len(calls) == 1:
            raise requests.exceptions.SSLError("EOF occurred in violation of protocol")
        return "ok"

    assert ft.load_hf_offline_fallback(loader, "microsoft/codebert-base", "model") == "ok"
    assert len(calls) == 2, "联网失败后必须再试一次"
    assert "HF_HUB_OFFLINE" not in calls[0], "首试应当允许联网（缓存不全时需要下载）"
    assert calls[1].get("HF_HUB_OFFLINE") == "1", "回退那次必须带离线开关"
    assert calls[1].get("TRANSFORMERS_OFFLINE") == "1"


def test_hf_offline_fallback_passes_through_on_success(monkeypatch):
    """成功时不得多试一次、也不得改环境（默认行为逐字不变）。"""
    monkeypatch.delenv("HF_HUB_OFFLINE", raising=False)
    calls = []
    assert ft.load_hf_offline_fallback(lambda: calls.append(1) or "ok", "x", "model") == "ok"
    assert len(calls) == 1
    assert "HF_HUB_OFFLINE" not in os.environ
