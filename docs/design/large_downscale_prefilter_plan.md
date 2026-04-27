# Large Downscale Prefilter Plan

最后更新：2026-04-27

本文档记录 `large_downscale_preprocess` 研究分支。当前结论只用于方案筛选，不是最终硬件推荐，也不修改主线 RTL。

## 1. 背景

当前 `image_geo_top` 主链路是：

```text
rotate_geom_init_unit -> rotate_core_bilinear -> src_tile_cache -> DDR read/write
```

`rotate_core_bilinear` 使用 inverse mapping + 2x2 bilinear sample：每个目标像素反推源坐标，再取 `p00/p01/p10/p11` 做双线性插值。对 `scale <= 4` 的 near / medium scale，当前解析式 cache/prefetch 主线继续优化。

当 `scale > 4`，尤其 `7200 -> 600` 这种 `scale_ratio ~= 12` 的 very large downscale，单次 2x2 bilinear 只采样少量源像素，存在明显混叠风险。

## 2. 为什么 cache 不能单独解决大比例缩小

cache/prefetch 优化的是“访问效率”：读哪些 tile、何时读、如何合并读、如何减少 miss 和 overfetch。

大比例缩小时的核心质量问题不同。以 `7200 -> 600` 为例，一个输出像素约覆盖 `12x12` 个源像素。direct bilinear 只使用 4 个源像素，无法表达该 footprint 内的高频平均值，容易出现 checkerboard、条纹、斜线等 aliasing。

因此 tile/lead/fifo/merge 参数可以改善访问局部性和吞吐，但不能单独补上低通滤波。`large_downscale_preprocess` 的目标是先降低源图高频能量并提高局部性，再复用当前主链路。

## 3. 候选方案 A：separable box / area prefilter

基本流程：

```text
src -> horizontal accumulate -> vertical accumulate -> intermediate
intermediate -> existing image_geo_top rotate/bilinear -> dst
```

建议第一轮只支持整数缩小因子：

- `2x`
- `3x`
- `4x`
- `6x`
- `12x`

资源估算维度：

- accumulator bit width：`pixel_bits + ceil(log2(factor_x * factor_y))`。
- line buffer rows：约 `factor_y` 行，最小 2 行。
- BRAM：约 `line_buffer_rows * src_w * pixel_bytes`，后续可用分块/streaming 降低峰值。
- DSP usage：box average 可主要使用加法器；除法对固定整数因子可用乘常数/移位近似或定点倒数。
- DDR passes：至少增加一次顺序读源图和一次写 intermediate。

优点：

- 简单，规则，抗混叠效果直观。
- 访问模式顺序，容易做 AXI burst。
- 可作为独立 engine，不扰动现有 rotate/cache 路径。

缺点：

- 画面会偏软。
- 非整数比例处理复杂。
- 大因子一次性 box 需要更宽 accumulator 和更多行缓存。

## 4. 候选方案 B：multi-stage downscale

示例：

```text
7200 -> 1800 -> 900 -> 600
7200 -> 1200 -> 600
7200 -> 2400 -> 1200 -> 600
```

每一级比例较小，可以复用同一个 prefilter engine。多级后每次滤波 footprint 更容易控制，也更接近硬件可实现的 streaming pass。

缺点是多次 DDR read/write，必须用软件模型确认额外 pass 的代价是否可接受。

## 5. 候选方案 C：polyphase FIR

polyphase FIR 支持非整数比例，质量通常优于 box/area，并能按目标采样位置选择相位系数。

代价：

- 需要系数表。
- DSP 和 line buffer 使用增加。
- 调试复杂度明显高于 box。

该方案暂时作为高级方案，不进入第一版 RTL。

## 6. 候选方案 D：EWA / footprint-based filtering

EWA 或 footprint-based filtering 能根据几何变换后的 footprint 做高质量滤波，质量最好，尤其适合旋转、非均匀缩放和强透视类场景。

代价是访存和硬件复杂度最高：footprint 内像素数量可变，权重计算复杂，cache 压力也更难界定。当前不建议实现，只作为论文相关工作或未来工作。

## 7. 推荐的第一版硬件方向

研究分支的第一版硬件方向建议只做：

```text
integer-factor separable box prefilter
```

支持因子：

```text
2x, 3x, 4x, 6x, 12x
```

输出：

```text
intermediate image in DDR
```

随后复用现有 `image_geo_top`：

```text
intermediate -> rotate/scale -> dst
```

这仍是研究分支初步方向，不是当前默认功能。

## 8. 与现有主链路的接口

约束：

- 不修改 `rotate_core_bilinear`。
- 不修改 `src_tile_cache`。
- 不修改 `image_geo_top` 主数据通路。
- 新增可选 prefilter mode，作为主链路之前的独立 pass。
- prefilter 输出 intermediate buffer base/stride/size。
- 当前 `image_geo_top` 继续处理 intermediate image。
- AXI burst 不跨 4KB。
- VALID/READY 语义不变。
- 错误通过 result/error/status 上报。

建议接口元数据：

| 字段 | 含义 |
| --- | --- |
| `prefilter_enable` | 是否启用预滤波 pass。 |
| `prefilter_factor_x/y` | 整数缩小因子。 |
| `src_base/stride/size` | 原始输入图。 |
| `intermediate_base/stride/size` | 预滤波输出图。 |
| `status/error` | 完成、非法因子、地址越界、AXI 错误等状态。 |

## 9. 进入 RTL 实现的门槛

必须同时满足：

- software quality golden 显示 direct bilinear 有明显 aliasing，而 prefilter 有明显改善。
- `model_large_downscale_pipeline.py` 显示额外 DDR pass 的代价可接受。
- intermediate size 合理。
- 不影响 `timing_safe_smallconfig`。
- 有独立 testbench 计划。

未满足这些门槛前，不把大比例缩小逻辑硬塞进 `rotate_core_bilinear` 或 `src_tile_cache`。
