# tb_ddr_read_engine

- DUT: `ddr_read_engine`
- Testbench: `tb_ddr_read_engine.sv`

`ddr_read_engine` 负责从 AXI DDR 读通道取回字数据，再在核心时钟域拆成像素流。
任务控制端口与写侧统一为：

- `task_start/task_addr/task_byte_count`
- `task_busy/task_done/task_error`

像素流在内部 `pixel_unpacker` 已统一为 `pixel_data/pixel_valid/pixel_ready` 语义；
模块对外仍保持读方向接口：

- `out_data/out_valid/out_ready`

当前覆盖场景：
- `aligned_whole_word`
- `unaligned_partial`
- `multi_burst`
- `split_4kb_boundary`
- `backpressure`
- `rresp_error`
- `rlast_error`

最近一次预期仿真结果：

- 正常场景应逐字节比对通过
- 错误场景应拉起 `task_error`，且不得拉起 `task_done`
