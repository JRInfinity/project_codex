# MATLAB 图像几何与 Tile Cache 参考模型使用说明

这个目录服务两个目标：

1. 生成可写入 DDR 的 8-bit 灰度输入图，同时给出肉眼可看的 PNG 和与 BIN 完全一一对应的 TXT。
2. 在给定源图尺寸、目标图尺寸、旋转角度后，用 MATLAB 估计 tile 访问、cache 命中、预取时机，并辅助选择 `TILE_W / TILE_H / TILE_NUM`。

## 先看这个：唯一入口文件

日常使用只需要打开并修改：

```text
run_image_geo_tool.m
```

它是唯一需要你改输入参数和运行的入口脚本。其它 `.m` 文件是底层实现，不需要直接运行。

入口脚本顶部有一个配置区：

```matlab
mode = "single_case";  % "input_only", "single_case", or "sweep"

src_w = 600;
src_h = 600;
dst_w = 600;
dst_h = 600;
angle_deg = 45;        % Clockwise is positive.

pattern = "random_blocks";
seed = 1;
case_name = "";
```

只改这些值即可控制输入图尺寸、输出图尺寸、旋转角度、图案类型和随机种子。

## 三种运行模式

### 1. `mode = "input_only"`

只生成输入图和给真实系统/DDR 使用的文件，不做输出图和 tile/cache 分析。

适合用途：

- 只想得到一张灰度源图。
- 只想把 `input.bin` 放进 DDR。
- 想用 `input.png` 肉眼确认图案。
- 想用 `input.txt` 对照 bin 中每个 byte 是否正确。
- 想生成一个带尺寸和角度配置的 `case.txt` 给软件或 testbench。

输出目录：

```text
matlab/out/ddr_inputs/<case_name>/
  input.png
  input.bin
  input.txt
  input_meta.txt
  case.txt
```

### 2. `mode = "single_case"`

生成完整的单 case 参考结果。这个模式会先生成输入图，再根据 RTL Q16 逆映射公式生成输出参考图，并分析 tile/cache/prefetch。

适合用途：

- 看某一组 `src_w/src_h/dst_w/dst_h/angle_deg` 下的输出图是否符合预期。
- 对照 RTL 输出图和 MATLAB 参考输出图。
- 看每个目标像素需要访问哪些源 tile。
- 判断这个 case 下推荐的 `TILE_W / TILE_H / TILE_NUM`。
- 看推荐预取提前量 `lead_pixels` 和每个 tile 的 `prefetch_at`。

输出目录：

```text
matlab/out/cache_ref_runs/<case_name>/
  input.png
  input.bin
  input.txt
  input_meta.txt
  case.txt
  output_ref.png
  output_ref.bin
  output_ref.txt
  coeffs.txt
  tile_summary.txt
  tile_summary.csv
  prefetch_plan.csv
  tile_heatmap.png
```

如果在入口里设置：

```matlab
write_timeline = true;
```

还会额外生成：

```text
tile_timeline.csv
```

这个文件是逐目标像素的 tile 访问序列，适合小图和 RTL trace 对齐。大图不要打开，否则文件会非常大。

### 3. `mode = "sweep"`

跑多组代表性实验，给出跨 case 的 RTL 参数建议。

适合用途：

- 比较不同缩放比和旋转角度下 tile 配置的表现。
- 给 RTL 顶层参数选择提供依据。
- 观察 `32x16x8`、`32x16x12`、`32x32x8` 等候选配置的 miss、预取浪费和 BRAM 代价。

默认 sweep case 在 `run_image_geo_tool.m` 的这个位置修改：

```matlab
sweep_cases = default_sweep_cases();
```

如果要自己定制，可以在入口脚本里直接构造 `sweep_cases`。每个 case 需要字段：

```matlab
src_w, src_h, dst_w, dst_h, angle_deg, name
```

总报告输出：

```text
matlab/out/cache_ref_runs/rtl_recommendations.md
matlab/out/cache_ref_runs/rtl_recommendations.csv
```

## 文件作用详解

### `run_image_geo_tool.m`

唯一用户入口脚本。

你应该在这里完成所有常规操作：

- 选择运行模式：只生成输入、单 case 完整分析、或多 case sweep。
- 设置源图宽高：`src_w/src_h`。
- 设置目标图宽高：`dst_w/dst_h`。
- 设置旋转角度：`angle_deg`，顺时针为正。
- 设置输入图案：`pattern`。
- 设置随机种子：`seed`。
- 设置候选 tile 配置：`tile_configs`。
- 设置 DDR 性能估计参数：`ddr_latency_cycles/ddr_bytes_per_cycle/ddr_outstanding/pixel_cycles`。
- 控制是否生成巨大调试文件：`write_pixel_txt/write_timeline`。

这个文件本身不实现复杂数学，只负责把你的配置分发到下面的实现函数，并把结果放到统一的 `out/` 目录。

### `generate_gray_image.m`

底层输入图生成器。

它负责把你指定的宽高和图案类型变成一张 `uint8` 灰度图，并输出：

- `.png`：肉眼看的源图。
- `.bin`：真实系统 DDR 输入文件。
- `.txt`：与 `.bin` 完全一致的十六进制文本。
- `_meta.txt`：宽高、格式、路径、字节数等元信息。
- 可选 `.coe` 和 `_preview.png`，默认入口脚本关闭。

它支持规则图案和随机图案，包括：

- `random`
- `horizontal_gradient`
- `vertical_gradient`
- `checkerboard`
- `noisy_gradient`
- `random_blocks`
- `impulse_points`
- `rings`
- `diagonal_ramp`
- `constant`

随机图案可以用 `seed` 固定结果。这样 MATLAB 生成的 bin、RTL 输入、trace 对齐时都能复现同一张图。

### `export_image_geo_case.m`

输入 case 导出器。

它在 `generate_gray_image.m` 的基础上多生成一个 `case.txt`。这个文件记录：

- 输入 bin 文件名。
- 输出 bin 文件名。
- 源图宽高和 stride。
- 目标图宽高和 stride。
- 旋转角度。
- `sin/cos` 的 Q16 整数值。
- 像素格式和 row-major 存储说明。

如果只做 `input_only`，入口脚本会调用它，因为你通常不只需要 bin，还需要知道这个 bin 对应的尺寸和角度配置。

### `image_geo_cache_ref.m`

核心参考模型。

它是单 case 详细分析的主体，负责：

- 调用 `export_image_geo_case.m` 生成输入图和 case 文件。
- 按 RTL 风格 Q16 统一逆映射计算几何系数。
- 计算 `scale_x_q16/scale_y_q16`。
- 计算 `sin/cos Q16`。
- 计算 `step_x_x/step_y_x/step_x_y/step_y_y`。
- 计算 `row0_x/row0_y`。
- 对目标图做光栅扫描，找每个输出像素对应的源坐标。
- 对有效像素做 Q16 双线性插值，输出 `output_ref.png/bin/txt`。
- 对越界连续源坐标直接输出 0，并且不产生 tile/cache 访问。
- 按 `00, 01, 10, 11` 的 RTL 顺序统计四个双线性源像素对应的 tile。
- 对每组候选 tile 配置做 cache 仿真。
- 统计 hit/miss、unique tile、slot pressure、BRAM bits、DDR read bytes。
- 生成 oracle/lookahead 预取计划。
- 选择当前 case 推荐的 `TILE_W / TILE_H / TILE_NUM / lead_pixels`。

你通常不直接改这个文件。只有当 RTL 的几何公式、越界策略、cache 替换策略改变时，才需要同步改它。

## BIN 和 TXT 的严格格式

`input.bin` 是裸 byte 文件：

- 无文件头。
- 无压缩。
- 无行 padding。
- 每个像素 1 byte。
- 类型等价于 `uint8`。
- 灰度范围 `0..255`。
- `0` 为黑，`255` 为白。
- 存储顺序为 row-major。

地址公式：

```text
byte_offset = y * width + x
```

其中：

```text
x = 0..width-1
y = 0..height-1
```

所以文件大小必须等于：

```text
width * height bytes
```

`input.txt` 是给人看的 bin 展开形式：

```text
# format=row-major uint8 grayscale, hex byte per pixel
# width=4 height=3 byte_offset=y*width+x
00 12 34 56
78 9A BC DE
F0 11 22 33
```

去掉前两行注释后，从左到右、从上到下读取每个两位十六进制数，得到的 byte 序列与 `input.bin` 完全相同。

`output_ref.bin/output_ref.txt` 的格式也一样，只是宽高对应 `dst_w/dst_h`。

## 重点输出文件怎么读

### `input.png`

源图灰度图。它就是写入 DDR 的图像内容的可视化版本。

### `input.bin`

真实系统的输入文件。DDR 中按 1 byte/pixel、row-major 存放。

### `input.txt`

`input.bin` 的可读版本。用于人工检查某个坐标的像素值，或者和 testbench 打印的 byte 对齐。

### `output_ref.png`

MATLAB 参考输出图。用于肉眼看旋转、缩放、越界填 0 是否符合预期。

### `output_ref.bin/output_ref.txt`

参考输出的二进制和文本版本。用于和 RTL 输出逐 byte 比较。

### `coeffs.txt`

几何系数报告。重点看：

- `scale_x_q16/scale_y_q16`
- `sin_q16/cos_q16`
- `step_x_x/step_y_x/step_x_y/step_y_y`
- `row0_x/row0_y`
- 四个角的映射结果

这个文件用于确认 MATLAB 和 RTL 的几何步进常数一致。

### `tile_summary.txt`

当前 case 的 tile/cache 总结。重点看：

- 每组 tile 配置的 `unique_tiles`
- tile request 数量
- no-prefetch miss
- lookahead/oracle miss
- late prefetch
- wasted prefetch
- BRAM bits
- recommended lead pixels
- 推荐的 `TILE_W/TILE_H/TILE_NUM`

### `tile_summary.csv`

和 `tile_summary.txt` 内容类似，但适合放进 Excel、Python 或脚本继续分析。

### `prefetch_plan.csv`

每个 tile 的预取计划。重点列：

- `tile_x/tile_y`
- `first_use_pixel`
- `last_use_pixel`
- `prefetch_at`
- `fill_pixels`
- `late`
- `wasted`

推荐换 tile/预取时机：

```text
prefetch_at = max(0, first_use_pixel - lead_pixels)
lead_pixels = ceil((ddr_latency + tile_bytes / bytes_per_cycle) / pixel_cycles)
```

如果 slot pressure 高，不要过早预取，避免把当前四个双线性采样 tile 驱逐掉。

### `tile_heatmap.png`

源图 tile 访问热度图。越亮代表访问越多。它适合快速判断旋转角度和缩放比导致的访问形态。

## 推荐工作流

1. 先用 `mode = "input_only"` 生成一张输入图，确认 `input.png/input.txt/input.bin` 格式没问题。
2. 再用 `mode = "single_case"` 跑同一组尺寸和角度，看 `output_ref.png`、`coeffs.txt`、`tile_summary.txt`。
3. 当你要选 RTL 参数时，用 `mode = "sweep"` 跑多组代表性配置，看 `rtl_recommendations.md`。
4. 如果要和 RTL trace 逐像素对齐，只对小图打开 `write_timeline = true`。
5. 大图不要打开 `write_pixel_txt` 和 `write_timeline`，否则输出文件会很大。

## 当前行为约定

- 输入和输出都是 8-bit 灰度。
- DDR 输入是 1 byte/pixel。
- `.bin` 全部 row-major。
- 旋转角度顺时针为正。
- MATLAB 参考模型中，连续源坐标越界时输出像素填 0。
- 越界输出像素不产生 DDR/tile/cache 访问。
- 当前 RTL 如果仍是 clamp 行为，和 MATLAB 参考输出会存在边界差异。
