# project_codex SystemVerilog 代码说明

## 项目总体说明

本仓库的主要 RTL 位于 `rtl/`，围绕一个双时钟域图像几何处理 datapath 展开：AXI-Lite 在 `image_geo_top.sv` 中配置帧参数和控制寄存器，core 域执行几何处理和 cache 调度，DDR 读写路径通过 AXI4 访问外部存储。`axi/rtl/taxi_*.sv` 是通用 AXI/AXI-Lite 基础库，本轮文档只作为接口依赖列入索引，不逐模块展开。

代码中可确认的主处理路径以 `image_geo_top` 为顶层：AXI-Lite 寄存器 -> `frame_config_cdc` -> core 域控制/几何初始化 -> `src_tile_cache` 与 `ddr_read_engine` 取源图 -> `rotate_core_bilinear` 采样和插值 -> `row_out_buffer` -> `ddr_write_engine` 写回 DDR。缩放模块 `scale_core_nearest`、`scale_core_bilinear`、`src_line_buffer`、`src_row_cache` 仍在仓库中保留，当前是否接入最新顶层路径需按实例关系确认。

## 顶层数据流

```text
AXI-Lite 控制寄存器
  -> frame_config_cdc
  -> scaler_ctrl / rotate_geom_init_unit / rotate_core_bilinear
  -> src_tile_cache --miss/read_start--> ddr_read_engine -> AXI4 read DDR
  -> src_tile_cache --sample_rsp--> rotate_core_bilinear
  -> row_out_buffer
  -> ddr_write_engine -> AXI4 write DDR
  -> result/error/status/irq 回到 AXI-Lite 域
```

`image_geo_top.sv` 中可以追溯到 `frame_config_cdc`、`cache_stats_cdc`、`scaler_ctrl`、`src_tile_cache`、`ddr_read_engine`、`rotate_core_bilinear`、`row_out_buffer`、`ddr_write_engine` 的实例化。DDR AXI 信号通过 `taxi_axi_if` 接口在顶层内部汇聚，再展开为顶层端口。

## 时钟域划分

- `axi_clk` 域：AXI-Lite 寄存器、AXI4 DDR 读写通道、DDR burst reader/writer 内部状态机。
- `core_clk` 域：图像几何核心、cache、行缓冲、任务调度、统计生成。
- CDC 路径：`frame_config_cdc` 传配置，`task_cdc`/`task_cdc_2d` 传 DDR 任务，`result_cdc` 回传完成/错误，`cache_stats_cdc` 传统计快照，`async_word_fifo` 承载跨域数据流。
- reset：`reset_sync.sv` 对异步复位做目标域同步释放；`image_geo_top.sv` 中分别生成 `axi_sys_rst` 和 `core_sys_rst`。

## 主要模块分层

- 顶层/控制：`image_geo_top`、`scaler_ctrl`、`axi_ddr_rw32`。
- DDR/AXI：`axi_burst_reader`、`axi_burst_writer`、`ddr_read_engine`、`ddr_write_engine`、`ddr_axi_pkg`。
- CDC/reset/FIFO：`reset_sync`、`async_word_fifo`、`task_cdc`、`task_cdc_2d`、`result_cdc`、`frame_config_cdc`、`cache_stats_cdc`。
- buffer/cache：`src_tile_cache`、`src_row_cache`、`src_line_buffer`、`row_out_buffer`。
- 图像核心：`rotate_core_bilinear`、`rotate_geom_init_unit`、`row_advance_unit`、`scale_core_nearest`、`scale_core_bilinear`、`pixel_unpacker`、`pixel_packer`。
- 验证：`rtl/sim/tb_*.sv`。

## 一次任务流程

1. 软件通过 `image_geo_top.sv` 的 AXI-Lite 寄存器写入源/目标基地址、stride、尺寸、旋转 Q16 参数、cache/scheduler 控制位，并写控制寄存器启动。
2. AXI-Lite 域把帧配置打包，经 `frame_config_cdc` 送入 core 域，避免配置 bus 直接跨域。
3. core 域控制逻辑启动几何初始化和处理核心；旋转路径中 `rotate_geom_init_unit` 生成步进和边界参数，`rotate_core_bilinear` 逐目标像素发出四邻域采样请求。
4. `src_tile_cache` 判断采样是否命中。命中时直接返回 `sample_p00/p01/p10/p11`；miss 时组织 sector/tile fill，通过 `read_start/read_addr/read_byte_count/read_row_count` 请求 `ddr_read_engine`。
5. `ddr_read_engine` 使用 `task_cdc_2d` 把读任务送到 AXI 域，`axi_burst_reader` 按 burst 长度、outstanding 限制和 4KB 边界发 AR，并经 `async_word_fifo` 和 `pixel_unpacker` 回到 core 域像素流。
6. `rotate_core_bilinear` 得到采样响应后做 Q16 双线性插值，输出像素到 `row_out_buffer`。
7. `row_out_buffer` 将行数据整理为写回流，`ddr_write_engine` 用 `pixel_packer` 打包，经 `task_cdc` 和 `async_word_fifo` 进入 AXI 域，由 `axi_burst_writer` 发 AW/W/B 写回 DDR。
8. 完成、错误和统计通过 `result_cdc`、`cache_stats_cdc` 回到 AXI-Lite 可读寄存器；顶层状态/中断由 `image_geo_top` 输出。具体中断清除语义以 `image_geo_top.sv` 控制寄存器逻辑为准。

## 待清理项

- `image_geo_top.sv` 等文件中存在明显中文注释乱码，影响维护和答辩材料复用；本次仅在文档中记录，不修改 RTL。
- 部分模块命名保留历史缩放路径和当前旋转/cache 路径并存，例如 `scaler_ctrl` 与 `rotate_core_bilinear`，顶层实际使用关系需要持续保持索引同步。
- `axi_ddr_rw32.sv` 位于仓库根目录，工程定位和是否仍作为正式顶层待确认。
- `scale_core_*`、`src_line_buffer`、`src_row_cache` 与最新 `image_geo_top` 主路径关系待确认。
- taxi AXI 基础库建议记录来源/版本/license，避免后续把第三方通用 IP 当作项目自研模块描述。
