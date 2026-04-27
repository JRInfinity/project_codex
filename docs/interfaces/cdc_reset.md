# CDC 与 Reset 说明

## 时钟域
- `axil_clk`：AXI-Lite 寄存器、status、irq 和软件可读统计。
- `axi_clk`：DDR AXI 读写地址、数据和响应。
- `core_clk`：cache、算法 core、row buffer、任务控制。

## Reset
- `reset_sync` 采用 `ASYNC_REG` 多级寄存器链，异步置位、同步释放。
- 新增时钟域时应先实例化 reset 同步，不应直接把异步 reset release 用作普通逻辑。

## 单 bit 同步
- reset release 属于单 bit 同步场景。
- done/error 事件虽然位宽小，但不是普通单 bit 电平跨域，而是通过 `result_cdc` 事件 FIFO 传递，避免脉冲丢失。

## Payload FIFO 跨域
- `task_cdc`：单段地址+byte_count 任务。
- `task_cdc_2d`：addr、row_stride、byte_count、row_count 二维读任务。
- `frame_config_cdc`：宽帧配置 payload，目标域带 skid register。
- `async_word_fifo`：AXI word、packed word 和通用 payload 的异步 FIFO 基础件。

## 统计快照跨域
- `cache_stats_cdc` 将宽统计 payload 拆成 32 bit word 加 end marker，在 AXI-Lite 域重组成一致快照。
- 统计 payload 在未 ready 时必须保持稳定，不能逐字段直接跨域采样。

## 当前防护方式
- 所有已识别的 AXI/core/control 域 payload 都通过 CDC/FIFO 模块。
- FIFO full/empty、payload stable、end marker、overflow 等风险在相应模块有仿真检查或 ready 反压。

## CDC 风险
- 顶层新增状态寄存器读回时，不能直接读 core 域组合信号。
- cache 统计字段扩展时必须同步 `PAYLOAD_W` 和寄存器映射。
- AXI outstanding 增大时要重新评估 FIFO 深度和跨域 backpressure。
