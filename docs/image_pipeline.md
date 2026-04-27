# 图像处理流水线

## 顶层文字连接图

AXI-Lite 寄存器 -> `frame_config_cdc` -> `scaler_ctrl` -> `rotate_core_bilinear` -> `src_tile_cache` -> `ddr_read_engine` -> `axi_burst_reader` -> DDR 读

`rotate_core_bilinear` -> `row_out_buffer` -> `ddr_write_engine` -> `pixel_packer` -> `axi_burst_writer` -> DDR 写

`src_tile_cache` 统计 -> `cache_stats_cdc` -> AXI-Lite 统计寄存器

## 一次任务流程
1. 软件通过 AXI-Lite 写源/目标地址、stride、尺寸、旋转正余弦、cache/scheduler 参数。
2. 写控制寄存器启动后，`frame_config_cdc` 将配置送到 core 域。
3. `scaler_ctrl` 接收配置并启动算法/写回控制。
4. `rotate_core_bilinear` 计算每个目标像素对应的源坐标并请求样本。
5. `src_tile_cache` 命中则直接返回样本；miss 或 prefetch 需要 `ddr_read_engine` 从 DDR 填充 tile/sector。
6. `rotate_core_bilinear` 完成双线性混合并输出像素。
7. `row_out_buffer` 聚合目标行，`ddr_write_engine` 写回 DDR。
8. 完成或错误通过 sticky 状态和 `irq` 返回 AXI-Lite 域。
