# AXI DDR 读写接口说明

## 读路径
- 主路径：`src_tile_cache` 发现 miss 或 prefetch 机会后发出 `read_start/read_addr/read_row_stride/read_byte_count/read_row_count`，`ddr_read_engine` 通过 `task_cdc_2d` 把二维读任务送到 `axi_clk` 域，逐行调用 `axi_burst_reader`。
- `axi_burst_reader` 按 `BURST_MAX_LEN`、4KB 边界、`MAX_OUTSTANDING_BURSTS` 和 `MAX_OUTSTANDING_BEATS` 拆分 `AR` burst。
- `R` 通道数据先以 AXI word 形式进入异步 FIFO，再由 `pixel_unpacker` 转为 8 bit 像素回填 `src_tile_cache`。

## 写路径
- 主路径：`rotate_core_bilinear` 输出像素进入 `row_out_buffer`，行缓冲按目标行顺序向 `ddr_write_engine` 提供像素。
- `ddr_write_engine` 使用 `pixel_packer` 生成 `word_data/word_strb/word_last`，通过异步 FIFO 送到 `axi_clk` 域。
- `axi_burst_writer` 规划 `AW` burst，发送 `W` 数据并等待 `B` 响应。

## Burst 拆分与 4KB 边界
- 读写 burst 规划公共计算来自 `rtl/axi/ddr_axi_pkg.sv`。
- 单个 burst 不应跨越 AXI 4KB 边界；reader/writer 源码均包含相关仿真断言。
- `ARLEN/AWLEN` 最大编码为 255，对应最多 256 beat；`BURST_MAX_LEN` 源码限制为 1 到 256。

## 地址对齐与 WSTRB
- `DATA_W` 必须按 byte 对齐。
- 写路径最后一个不满 word 的有效字节由 `pixel_packer` 和 `axi_burst_writer` 的 `WSTRB` 共同保证。
- 未对齐起始地址策略在 package 中有计算函数支撑，但系统是否允许未对齐访问仍列为待确认。

## 完成与错误上报
- 读路径错误来源包括 `RRESP` 非 OKAY、`RLAST` 与预期不一致、后级 FIFO/backpressure 不匹配、`pixel_unpacker` 长度错误。
- 写路径错误来源包括 `BRESP` 非 OKAY、输入像素数量与任务长度不匹配、WSTRB/last 边界错误。
- `ddr_read_engine` 和 `ddr_write_engine` 均通过 `result_cdc` 将 AXI 域结果送回 core 域，再由顶层 sticky 状态和 `irq` 上报。

## taxi 引用
- `axi/rtl/taxi_*.sv` 属于 AXI 基础库，只在索引和接口层引用，不生成逐模块详细页。
