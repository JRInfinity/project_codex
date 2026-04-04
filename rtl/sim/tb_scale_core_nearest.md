# tb_scale_core_nearest

## 对应模块

- DUT: `scale_core_nearest`
- Testbench: `tb_scale_core_nearest.sv`
- Version: `v1`

## 模块做什么

`scale_core_nearest` 是最邻近插值缩放核。输入一组源图像尺寸和目标图像尺寸后，模块逐像素发出：

- 行请求 `line_req_valid/line_req_y`
- 像素请求 `pixel_req_valid/pixel_req_line_sel/pixel_req_x`
- 输出像素 `pix_data/pix_valid`

同时给出：

- 运行状态 `busy`
- 正常结束 `done`
- 非法参数错误 `error`
- 行结束脉冲 `row_done`

## 这个 testbench 测了什么

### 1. `identity_4x4`

- 输入尺寸 `4x4`
- 输出尺寸 `4x4`
- 不加行侧阻塞
- 不加输出回压

目的：

- 先验证最基础的一一映射
- 排除缩放比例计算对结果的影响
- 快速确认输出像素数、`row_done` 数量、`done` 行为正确

### 2. `downscale_6x5_to_3x2`

- 输入尺寸 `6x5`
- 输出尺寸 `3x2`
- 无阻塞

目的：

- 验证缩小场景下的最近邻取样坐标
- 检查 `x/y` 舍入与边界截断逻辑

### 3. `upscale_3x3_to_5x5`

- 输入尺寸 `3x3`
- 输出尺寸 `5x5`
- 打开行请求阻塞
- 打开输出回压

目的：

- 验证放大场景下重复采样是否正确
- 验证 `line_req_ready` 抖动时状态机能否继续前进
- 验证 `pix_ready` 拉低时 `pix_valid` / 数据保持是否正确

### 4. `mixed_7x4_to_5x3`

- 输入尺寸 `7x4`
- 输出尺寸 `5x3`
- 打开行请求阻塞
- 关闭输出回压

目的：

- 覆盖非整数比例、宽高同时变化的混合场景
- 避免只验证“整倍数缩放”这种过于理想的路径

### 5. `invalid_zero_src_w`

- `src_w = 0`

目的：

- 验证非法配置输入是否进入错误路径
- 检查 `error` 置位、`done` 不置位、`busy` 最终回落
- 检查错误情况下没有多余像素输出、没有多余行请求

## 检查方式

testbench 不是只看“跑没跑完”，而是做了逐项校验：

- 用 `calc_nearest_index()` 计算每个目标像素期望命中的源坐标
- 在 `pixel_req_valid` 当拍检查 `pixel_req_x` 和 `pixel_req_line_sel`
- 在像素输出端逐像素比对 `observed` 和期望源图像值
- 检查输出总像素数是否等于 `dst_w * dst_h`
- 检查 `row_done` 次数是否等于 `dst_h`
- 检查非法输入时无输出活动

## 最近一次仿真结果

时间：`2026-04-02`

结果：通过

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" scale_core_nearest -GtkWave -Clean
```

关键结果：

- 5 个样例全部通过
- 已导出 GTKWave 可查看的波形文件

相关输出：

- 日志：`C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\xsim.log`
- VCD：`C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\tb_scale_core_nearest.vcd`
- WDB：`C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\tb_scale_core_nearest.wdb`

## 后续维护要求

- 如果新增或删除测试样例，更新“这个 testbench 测了什么”
- 如果修改检查逻辑，更新“检查方式”
- 每次重新跑仿真后，更新“最近一次仿真结果”
