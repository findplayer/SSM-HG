# 图变体（M2 重跑产物；仅在边拓扑类消融时需要）

**默认留空。** 主库正典图在 `../graphs/`，不要动。

用途：`build_cfg_centered_hetero_graph.py` 的部分开关会改变**边的拓扑**（而非仅特征），
无法在 `dataset.py` 层用 `--drop-edges` 过滤，必须**重跑 M2** 另建一套图：

- `callback_unlimited/` —— `--callback-limit 0`（CALLBACK_RISK 不限制，对比默认上限 4）
- `callback_rev/` —— `CALLBACK_RISK_REV` 反向边（**M2 尚无该开关，属待开发项**）

## 空间：软链复用 `_cb.pt`

`graphs/` 共 15 GB，其中 **14.6 GB 是 `_cb.pt`**（CodeBERT 缓存）。它只依赖源码文本、
与边无关，故变体可整体软链复用，只需重建 `_hetero.json` / `_m1.json` / `_pyg.pt` / `_feat.pt`
（约 0.15 GB）：

```bash
V=products/alldata/graph_variants/callback_unlimited
for f in products/alldata/graphs/*_cb.pt; do ln -sf "$PWD/$f" "$V/$(basename "$f")"; done
```

⚠ `_feat.pt` **不可**复用：M1 的 $s_v$ 含 `external_callback +0.5`（取 CALLBACK_RISK 边端点），
边变了 $s_v$ 就变。好在其重建很快——`_cb.pt` 命中时 M3 不加载 CodeBERT，全库约 41 s。

完整命令见 `experiments/ablation_plan.md` §5。
