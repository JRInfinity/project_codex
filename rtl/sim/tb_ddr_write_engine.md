# tb_ddr_write_engine

- DUT: `ddr_write_engine`
- Testbench: `tb_ddr_write_engine.sv`

这个 testbench 覆盖写 DDR 的对偶路径，重点验证三件事：

- 地址对齐后 `AW` burst 是否正确拆分，且不跨 `4KB`
- 输入字节流是否被正确打包成 `WDATA/WSTRB/WLAST`
- `BRESP` 异常时模块是否进入错误路径而不是误报完成

当前写路径内部已经拆成两层：

- `pixel_packer`：把 8bit 输入流按起始地址偏移打包成 `DATA_W` word
- `axi_burst_writer`：把整次任务拆成多个 `AW/W/B` burst 并顺序送出

任务控制端口与读侧统一为：

- `task_start/task_addr/task_byte_count`
- `task_busy/task_done/task_error`

像素流在内部 `pixel_packer` 已统一为 `pixel_data/pixel_valid/pixel_ready` 语义；
模块对外仍保持写方向接口：

- `in_data/in_valid/in_ready`

当前覆盖场景：
- `aligned_whole_word`
- `unaligned_partial`
- `multi_burst`
- `split_4kb_boundary`
- `input_backpressure`
- `bresp_error`

最近一次预期仿真结果：

- 所有成功场景应完成写入并逐字节比对通过
- `bresp_error` 应拉起 `task_error`，且不得拉起 `task_done`
