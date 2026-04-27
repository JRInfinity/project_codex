# ddr_read_engine

> 依据文件：``rtl/axi/ddr_read_engine.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- 连接 core 域 cache fill 请求与 axi 域 ``axi_burst_reader``。
- 同时承担任务 CDC、AXI word FIFO CDC、像素解包和结果回传。

## 2. 文件路径
- ``rtl/axi/ddr_read_engine.sv``

## 3. 主要功能
- 接收 ``task_start``、首地址、``row_stride``、``byte_count``、``row_count``。
- 使用 ``task_cdc_2d`` 传递二维任务，按行调用 burst reader。
- 通过 ``pixel_unpacker`` 输出 8 bit 像素给 cache fill。

## 4. 参数说明
- ``DATA_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``ADDR_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``BURST_MAX_LEN``：默认 ``256``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``AXI_ID_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``FIFO_DEPTH_WORDS``：默认 ``64``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_OUTSTANDING_BURSTS``：默认 ``4``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_OUTSTANDING_BEATS``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`axi_clk`（input）。
- 时钟/复位：`core_clk`（input）。
- 时钟/复位：`axi_rst`（input）。
- 时钟/复位：`core_rst`（input）。
- 握手/状态：`task_start`（input）。
- 数据/控制：`task_addr`（input）。
- 数据/控制：`task_row_stride`（input）。
- 数据/控制：`task_byte_count`（input）。
- 数据/控制：`task_row_count`（input）。
- 握手/状态：`task_start_ready`（output）。
- 握手/状态：`task_busy`（output）。
- 握手/状态：`task_done`（output）。
- 状态/错误/统计：`task_error`（output）。
- 数据/控制：`out_data`（output）。
- 握手/状态：`out_valid`（output）。
- 握手/状态：`out_row_last`（output）。
- 握手/状态：`out_ready`（input）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- core 侧只有任务未活动、CDC ready 且 byte/row 非零时接受任务。
- axi 侧状态机按行 issue/wait/next，读完后返回 result。
- ``task_active_reg``、``unpacker_done_level``、``unpacker_error_level`` 共同决定 busy/error。
- 状态机 ``row_state_t``：R_IDLE、R_ISSUE、R_WAIT、R_DONE、R_ERROR。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/axi/ddr_read_engine.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``reader_task_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] reader_task_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，row_base_addr_reg + ((row_index_reg + 1'b1) * row_stride_reg)，task_addr_axi | if (axi_rst) begin；赋值为 '0<br>if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；赋值为 row_base_addr_reg + ((row_index_reg + 1'b1) * row_stride_reg)<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_addr_axi |
| ``reader_task_byte_count_reg`` | ``logic [31:0]``；声明：``logic [31:0] reader_task_byte_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_byte_count_reg，task_row_byte_count_axi | if (axi_rst) begin；赋值为 '0<br>if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；赋值为 row_byte_count_reg<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_row_byte_count_axi |
| ``reader_task_valid_reg`` | ``logic 1 bit/enum``；声明：``logic reader_task_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (axi_rst) begin；赋值为 1'b0<br>if (axi_rst) begin；if (result_pending_reg && result_ready_axi) begin；if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；if (reader_task_valid_reg && reader_task_ready) begin；赋值为 1'b0<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 1'b1<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 1'b1 |
| ``result_done_reg`` | ``logic 1 bit/enum``；声明：``logic result_done_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (axi_rst) begin；赋值为 1'b0<br>if (axi_rst) begin；if (result_pending_reg && result_ready_axi) begin；赋值为 1'b0<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 1'b0<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 1'b1 |
| ``result_error_reg`` | ``logic 1 bit/enum``；声明：``logic result_error_reg;`` | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (axi_rst) begin；赋值为 1'b0<br>if (axi_rst) begin；if (result_pending_reg && result_ready_axi) begin；赋值为 1'b0<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 1'b1<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 1'b0 |
| ``result_pending_reg`` | ``logic 1 bit/enum``；声明：``logic result_pending_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (axi_rst) begin；赋值为 1'b0<br>if (axi_rst) begin；if (result_pending_reg && result_ready_axi) begin；赋值为 1'b0<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 1'b1 |
| ``row_base_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] row_base_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，task_addr_axi | if (axi_rst) begin；赋值为 '0<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_addr_axi |
| ``row_byte_count_reg`` | ``logic [31:0]``；声明：``logic [31:0] row_byte_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，task_row_byte_count_axi | if (axi_rst) begin；赋值为 '0<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_row_byte_count_axi |
| ``row_count_reg`` | ``logic [15:0]``；声明：``logic [15:0] row_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，task_row_count_axi | if (axi_rst) begin；赋值为 '0<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_row_count_axi |
| ``row_index_reg`` | ``logic [15:0]``；声明：``logic [15:0] row_index_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_index_reg + 1'b1 | if (axi_rst) begin；赋值为 '0<br>if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；赋值为 row_index_reg + 1'b1<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 '0 |
| ``row_more_after_current_reg`` | ``logic 1 bit/enum``；声明：``logic row_more_after_current_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，(row_rows_remaining_reg > 16'd2)，(task_row_count_axi > 16'd1) | if (axi_rst) begin；赋值为 1'b0<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 (row_rows_remaining_reg > 16'd2)<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 (task_row_count_axi > 16'd1) |
| ``row_rows_remaining_reg`` | ``logic [15:0]``；声明：``logic [15:0] row_rows_remaining_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_rows_remaining_reg - 1'b1，task_row_count_axi | if (axi_rst) begin；赋值为 '0<br>if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；赋值为 row_rows_remaining_reg - 1'b1<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_row_count_axi |
| ``row_state_reg`` | ``row_state_t 1 bit/enum``；声明：``row_state_t row_state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``row_state_t``：``R_IDLE``=0，``R_ISSUE``=1，``R_WAIT``=2，``R_DONE``=3，``R_ERROR``=4 | if (axi_rst) begin；赋值为 R_IDLE<br>if (axi_rst) begin；if (result_pending_reg && result_ready_axi) begin；if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；赋值为 R_IDLE<br>if (axi_rst) begin；if (result_pending_reg && result_ready_axi) begin；if ((row_state_reg == R_DONE) \|\| (row_state_reg == R_ERROR)) begin；if (reader_task_valid_reg && reader_task_ready) begin；赋值为 R_WAIT<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 R_ERROR<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 R_DONE<br>if (reader_task_valid_reg && reader_task_ready) begin；if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；赋值为 R_ISSUE |
| ``row_stride_reg`` | ``logic [31:0]``；声明：``logic [31:0] row_stride_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，task_row_stride_axi | if (axi_rst) begin；赋值为 '0<br>if (reader_result_valid) begin；if (!reader_result_error && reader_result_done) begin；if (reader_result_error \|\| !reader_result_done) begin；if ((row_state_reg == R_IDLE) && task_valid_axi && task_ready_axi) begin；赋值为 task_row_stride_axi |
| ``task_active_reg`` | ``logic 1 bit/enum``；声明：``logic task_active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (core_rst) begin；赋值为 1'b0<br>if (core_rst) begin；if (task_start_accept) begin；赋值为 1'b1<br>if (core_rst) begin；if (task_start_accept) begin；赋值为 1'b0 |
| ``task_error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (core_rst) begin；赋值为 1'b0<br>if (core_rst) begin；if (task_start_accept) begin；赋值为 1'b0<br>if (core_rst) begin；if (task_start_accept) begin；if (result_error_evt_core \|\| unpacker_error_flag) begin；赋值为 1'b1 |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``row_state_t``，编码位宽：``[2:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``R_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 源码中未提取到直接 next-state 赋值；可能在顺序分支或组合默认路径中保持/跳转，待人工确认。 |
| ``R_ISSUE`` | 1 | 发起请求或地址通道阶段。 | 源码中未提取到直接 next-state 赋值；可能在顺序分支或组合默认路径中保持/跳转，待人工确认。 |
| ``R_WAIT`` | 2 | 等待下游响应或返回数据。 | 源码中未提取到直接 next-state 赋值；可能在顺序分支或组合默认路径中保持/跳转，待人工确认。 |
| ``R_DONE`` | 3 | 输出、排空或完成阶段。 | 源码中未提取到直接 next-state 赋值；可能在顺序分支或组合默认路径中保持/跳转，待人工确认。 |
| ``R_ERROR`` | 4 | 错误处理或错误结果上报阶段。 | 源码中未提取到直接 next-state 赋值；可能在顺序分支或组合默认路径中保持/跳转，待人工确认。 |

<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为 ``src_tile_cache`` 的 miss/fill 读请求。
- 下游为 ``axi_burst_reader`` 与 AXI 读通道。
- 输出像素回到 ``src_tile_cache``。

## 9. 握手协议说明
- core 侧 start/ready 接收任务；axi 侧 task_valid/task_ready 喂给 reader。
- AXI word 通过 ``async_word_fifo`` 从 axi 域到 core 域。
- result 通过 ``result_cdc`` 返回 core 域。

## 10. 错误处理与边界条件
- ``task_byte_count == 0`` 或 ``task_row_count == 0`` 不接受。
- reader 错误与 unpacker 错误合并为 ``task_error``。

## 11. 综合/时序/CDC注意事项
- FIFO 深度要与 reader outstanding 匹配。
- ``PIXEL_W`` 当前按 8 bit 检查，扩展像素格式需要同步 pack/unpack。
- 三处 CDC 边界不得旁路。

## 12. 维护建议
- 调整读吞吐时同时评估 outstanding、FIFO 深度和 cache fill 消费能力。
- 建议未来增加可读错误原因码。

## 13. 待确认问题
- 待确认：``row_stride < byte_count`` 时由软件还是硬件约束。
