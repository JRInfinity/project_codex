# SystemVerilog 模块索引

> taxi AXI 基础库只做索引和接口引用，不生成 ``docs/modules/taxi_*.md``。分类和功能说明来自源码路径、模块名、实例化关系和本文档人工审阅。

| 文件路径 | 模块名 | 文档层级 | 类别 | 功能一句话 | 时钟域 | FSM | AXI/CDC/FIFO |
|---|---|---|---|---|---|---|---|
| ``axi/rtl/taxi_axi_adapter.sv`` | ``taxi_axi_adapter`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_adapter_rd.sv`` | ``taxi_axi_adapter_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_adapter_wr.sv`` | ``taxi_axi_adapter_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_axil_adapter.sv`` | ``taxi_axi_axil_adapter`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_axil_adapter_rd.sv`` | ``taxi_axi_axil_adapter_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_axil_adapter_wr.sv`` | ``taxi_axi_axil_adapter_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar.sv`` | ``taxi_axi_crossbar`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar_1s.sv`` | ``taxi_axi_crossbar_1s`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar_1s_rd.sv`` | ``taxi_axi_crossbar_1s_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar_1s_wr.sv`` | ``taxi_axi_crossbar_1s_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar_addr.sv`` | ``taxi_axi_crossbar_addr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar_rd.sv`` | ``taxi_axi_crossbar_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_crossbar_wr.sv`` | ``taxi_axi_crossbar_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_dp_ram.sv`` | ``taxi_axi_dp_ram`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_fifo.sv`` | ``taxi_axi_fifo`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI/FIFO |
| ``axi/rtl/taxi_axi_fifo_rd.sv`` | ``taxi_axi_fifo_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI/FIFO |
| ``axi/rtl/taxi_axi_fifo_wr.sv`` | ``taxi_axi_fifo_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI/FIFO |
| ``axi/rtl/taxi_axi_interconnect.sv`` | ``taxi_axi_interconnect`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_interconnect_1s.sv`` | ``taxi_axi_interconnect_1s`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_interconnect_1s_rd.sv`` | ``taxi_axi_interconnect_1s_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_interconnect_1s_wr.sv`` | ``taxi_axi_interconnect_1s_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_interconnect_rd.sv`` | ``taxi_axi_interconnect_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_interconnect_wr.sv`` | ``taxi_axi_interconnect_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_ram.sv`` | ``taxi_axi_ram`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_ram_if_rd.sv`` | ``taxi_axi_ram_if_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_ram_if_rdwr.sv`` | ``taxi_axi_ram_if_rdwr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_ram_if_wr.sv`` | ``taxi_axi_ram_if_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axi_register.sv`` | ``taxi_axi_register`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_register_rd.sv`` | ``taxi_axi_register_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_register_wr.sv`` | ``taxi_axi_register_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_tie.sv`` | ``taxi_axi_tie`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_tie_rd.sv`` | ``taxi_axi_tie_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axi_tie_wr.sv`` | ``taxi_axi_tie_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_adapter.sv`` | ``taxi_axil_adapter`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_adapter_rd.sv`` | ``taxi_axil_adapter_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_adapter_wr.sv`` | ``taxi_axil_adapter_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_apb_adapter.sv`` | ``taxi_axil_apb_adapter`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_axi_adapter.sv`` | ``taxi_axil_axi_adapter`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_axi_adapter_rd.sv`` | ``taxi_axil_axi_adapter_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_axi_adapter_wr.sv`` | ``taxi_axil_axi_adapter_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_crossbar.sv`` | ``taxi_axil_crossbar`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_crossbar_1s.sv`` | ``taxi_axil_crossbar_1s`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_crossbar_1s_rd.sv`` | ``taxi_axil_crossbar_1s_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_crossbar_1s_wr.sv`` | ``taxi_axil_crossbar_1s_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_crossbar_addr.sv`` | ``taxi_axil_crossbar_addr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_crossbar_rd.sv`` | ``taxi_axil_crossbar_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI/FIFO |
| ``axi/rtl/taxi_axil_crossbar_wr.sv`` | ``taxi_axil_crossbar_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI/FIFO |
| ``axi/rtl/taxi_axil_dp_ram.sv`` | ``taxi_axil_dp_ram`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_interconnect.sv`` | ``taxi_axil_interconnect`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_interconnect_1s.sv`` | ``taxi_axil_interconnect_1s`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_interconnect_1s_rd.sv`` | ``taxi_axil_interconnect_1s_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_interconnect_1s_wr.sv`` | ``taxi_axil_interconnect_1s_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_interconnect_rd.sv`` | ``taxi_axil_interconnect_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_interconnect_wr.sv`` | ``taxi_axil_interconnect_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 是 | AXI |
| ``axi/rtl/taxi_axil_ram.sv`` | ``taxi_axil_ram`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_register.sv`` | ``taxi_axil_register`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_register_rd.sv`` | ``taxi_axil_register_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_register_wr.sv`` | ``taxi_axil_register_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 单时钟 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_tie.sv`` | ``taxi_axil_tie`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_tie_rd.sv`` | ``taxi_axil_tie_rd`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``axi/rtl/taxi_axil_tie_wr.sv`` | ``taxi_axil_tie_wr`` | taxi 仅索引 | axi / ddr 读写路径 | 第三方/基础 AXI 组件，仅作为接口依赖引用。 | 无/待确认 | 否/未显式 | AXI |
| ``rtl/axi/axi_burst_reader.sv`` | ``axi_burst_reader`` | 重点详细 | axi / ddr 读写路径 | AXI 读 burst 生成器，按 4KB 和 outstanding 约束拆分读任务。 | axil/axi/core 多时钟 | 是 | AXI/FIFO |
| ``rtl/axi/axi_burst_writer.sv`` | ``axi_burst_writer`` | 重点详细 | axi / ddr 读写路径 | AXI 写 burst 生成器，负责 AW/W/B 通道和 WSTRB。 | 单时钟 | 是 | AXI |
| ``rtl/axi/cache_stats_cdc.sv`` | ``cache_stats_cdc`` | 普通详细 | cdc / reset / fifo | 统计快照 CDC，把宽 payload 拆成 32 bit word 和 end marker 传输。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/axi/ddr_axi_pkg.sv`` | ``ddr_axi_pkg`` | 普通详细 | package / interface | AXI DDR 公共 package，提供 burst、4KB、word count 和 WSTRB 计算函数。 | 无/待确认 | 否/未显式 | AXI/FIFO |
| ``rtl/axi/ddr_read_engine.sv`` | ``ddr_read_engine`` | 重点详细 | axi / ddr 读写路径 | 二维 DDR 读 engine，跨域调用 burst reader 并输出像素流。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/axi/ddr_write_engine.sv`` | ``ddr_write_engine`` | 重点详细 | axi / ddr 读写路径 | DDR 写 engine，跨域打包像素并调用 burst writer。 | axil/axi/core 多时钟 | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/axi/frame_config_cdc.sv`` | ``frame_config_cdc`` | 普通详细 | cdc / reset / fifo | AXI-Lite 到 core 域的宽配置 CDC，带目标域 skid register。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/axi/reset_sync.sv`` | ``reset_sync`` | 普通详细 | cdc / reset / fifo | 基础复位同步器，``STAGES`` 至少 2，``ASYNC_REG`` 寄存器链实现异步置位、同步释放。 | 单时钟 | 否/未显式 | AXI/CDC |
| ``rtl/axi/result_cdc.sv`` | ``result_cdc`` | 普通详细 | cdc / reset / fifo | done/error 结果事件 CDC，避免完成脉冲跨域丢失。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/axi/task_cdc.sv`` | ``task_cdc`` | 普通详细 | cdc / reset / fifo | 单段任务 CDC，打包地址和 byte_count，限制单任务 in-flight。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/axi/task_cdc_2d.sv`` | ``task_cdc_2d`` | 普通详细 | cdc / reset / fifo | 二维任务 CDC，传递 addr、row_stride、byte_count、row_count。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/buffer/async_word_fifo.sv`` | ``async_word_fifo`` | 普通详细 | cdc / reset / fifo | 通用异步 word FIFO，优先使用 Xilinx ``xpm_fifo_async``，为任务、结果、统计和 AXI word 提供 CDC。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/buffer/row_out_buffer.sv`` | ``row_out_buffer`` | 重点详细 | buffer / line buffer / row buffer | 目标行输出缓冲，吸收算法输出与 DDR 写回之间的反压。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/buffer/src_line_buffer.sv`` | ``src_line_buffer`` | 普通详细 | buffer / line buffer / row buffer | 简单源行缓冲，服务早期/辅助缩放路径。 | 单时钟 | 是 | AXI |
| ``rtl/buffer/src_row_cache.sv`` | ``src_row_cache`` | 普通详细 | buffer / line buffer / row buffer | 多行源行缓存，维护相邻源行命中和 fill。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/buffer/src_tile_cache.sv`` | ``src_tile_cache`` | 重点详细 | cache / prefetch / scheduler | 主读侧 tile cache，负责 sample 命中、miss fill、prefetch、merge 和统计。 | 单时钟 | 是 | AXI/FIFO |
| ``rtl/core/pixel_packer.sv`` | ``pixel_packer`` | 普通详细 | core 图像算法核心 | 8 bit 像素流到 AXI word/WSTRB 转换，服务 DDR 写回。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/core/pixel_unpacker.sv`` | ``pixel_unpacker`` | 普通详细 | core 图像算法核心 | AXI word 到 8 bit 像素流转换，服务 DDR 读返回。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/core/rotate_core_bilinear.sv`` | ``rotate_core_bilinear`` | 重点详细 | core 图像算法核心 | 旋转双线性核心，计算源坐标、请求四邻域样本并输出目标像素。 | 单时钟 | 是 | AXI |
| ``rtl/core/rotate_geom_init_unit.sv`` | ``rotate_geom_init_unit`` | 普通详细 | core 图像算法核心 | 旋转几何初始化单元，为 rotate core 计算起始坐标和步进。 | 单时钟 | 是 | AXI |
| ``rtl/core/row_advance_unit.sv`` | ``row_advance_unit`` | 普通详细 | core 图像算法核心 | 行基坐标推进辅助单元，用多拍分段降低宽坐标加法时序压力。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/core/scale_core_bilinear.sv`` | ``scale_core_bilinear`` | 普通详细 | core 图像算法核心 | 双线性缩放核心，保留/辅助算法路径。 | 单时钟 | 是 | AXI |
| ``rtl/core/scale_core_nearest.sv`` | ``scale_core_nearest`` | 普通详细 | core 图像算法核心 | 最近邻缩放核心，保留/辅助算法路径。 | 单时钟 | 是 | AXI |
| ``rtl/ctrl/scaler_ctrl.sv`` | ``scaler_ctrl`` | 重点详细 | top 顶层与寄存器控制 | core 域任务控制器，承接配置并编排算法与写回。 | 单时钟 | 是 | AXI |
| ``rtl/sim/tb_async_word_fifo_xpm.sv`` | ``tb_async_word_fifo_xpm`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 双时钟 CDC | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/sim/tb_cache_stats_cdc_back_to_back.sv`` | ``tb_cache_stats_cdc_back_to_back`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 无/待确认 | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/sim/tb_ddr_read_engine.sv`` | ``tb_ddr_read_engine`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_ddr_write_engine.sv`` | ``tb_ddr_write_engine`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_image_geo_top.sv`` | ``tb_image_geo_top`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_scale_stress.sv`` | ``tb_image_geo_top_perf_scale_stress`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_1000_600_downscale_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_1000_600_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_case_base`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_downscale_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_downscale_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_off_quickdiag`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_on_quickdiag`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_on_trace2uniq`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate15_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate30_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate30_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate60_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate60_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate75_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_mid_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate15_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate75_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_small_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_case.sv`` | ``tb_image_geo_top_perf_single_small_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 是 | AXI/CDC/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_1000_600_downscale_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_1000_600_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate0_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate0_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate15_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate75_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate90_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal128_rotate90_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal256_rotate0_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal256_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal256_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal256_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_cal256_rotate90_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_downscale_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_downscale_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_off_quickdiag`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_on_quickdiag`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_large_rotate45_on_trace2uniq`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_light_base`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate15_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate30_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate30_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate60_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate60_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate75_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_mid_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate0_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate15_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate75_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy_rotate90_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy512_rotate0_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy512_rotate15_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy512_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy512_rotate75_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_proxy512_rotate90_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_small_rotate45_off`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_single_light.sv`` | ``tb_image_geo_top_perf_single_small_rotate45_on`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_image_geo_top_perf_sweep.sv`` | ``tb_image_geo_top_perf_sweep`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_image_geo_top_prefetch_stress.sv`` | ``tb_image_geo_top_prefetch_stress`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_image_geo_top_trace_rotate45.sv`` | ``tb_image_geo_top_trace_rotate45`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_image_geo_top_trace_rotate45_downscale.sv`` | ``tb_image_geo_top_trace_rotate45_downscale`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_pixel_unpacker.sv`` | ``tb_pixel_unpacker`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | axil/axi/core 多时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_result_cdc.sv`` | ``tb_result_cdc`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 无/待确认 | 否/未显式 | CDC |
| ``rtl/sim/tb_rotate_core_bilinear_trace.sv`` | ``tb_rotate_core_bilinear_trace`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_rotate_geom_init_unit.sv`` | ``tb_rotate_geom_init_unit`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_scale_core_nearest.sv`` | ``tb_scale_core_nearest`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_scaler_ctrl.sv`` | ``tb_scaler_ctrl`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_src_line_buffer.sv`` | ``tb_src_line_buffer`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI |
| ``rtl/sim/tb_src_tile_cache.sv`` | ``tb_src_tile_cache`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_src_tile_cache_analytic_trace.sv`` | ``tb_src_tile_cache_analytic_trace`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_src_tile_cache_merge_reservation.sv`` | ``tb_src_tile_cache_merge_reservation`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_src_tile_cache_prefetch.sv`` | ``tb_src_tile_cache_prefetch`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 单时钟 | 否/未显式 | AXI/FIFO |
| ``rtl/sim/tb_task_cdc.sv`` | ``tb_task_cdc`` | testbench 验证说明 | testbench | 仿真验证 wrapper/testbench。 | 无/待确认 | 否/未显式 | AXI/CDC |
| ``rtl/top/image_geo_top.sv`` | ``image_geo_top`` | 重点详细 | top 顶层与寄存器控制 | 系统顶层，提供 AXI-Lite 控制寄存器并串接 DDR/cache/rotate/writeback 主链路。 | axil/axi/core 多时钟 | 否/未显式 | AXI/CDC/FIFO |
