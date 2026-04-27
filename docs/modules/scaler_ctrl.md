# scaler_ctrl

> 依据文件：``rtl/ctrl/scaler_ctrl.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- 位于 ``frame_config_cdc`` 下游和各处理子模块上游。
- 把软件寄存器配置转成硬件内部 start/done/error 流程。

## 2. 文件路径
- ``rtl/ctrl/scaler_ctrl.sv``

## 3. 主要功能
- 接收帧配置、尺寸、旋转参数和 cache/scheduler 控制。
- 产生算法 start、写任务和任务状态。
- 汇总下游 done/error。

## 4. 参数说明
- ``ADDR_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_W``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_H``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_W``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_H``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``LINE_NUM``：默认 ``2``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`sys_rst`（input）。
- 握手/状态：`start`（input）。
- 数据/控制：`src_base_addr`（input）。
- 数据/控制：`dst_base_addr`（input）。
- 数据/控制：`src_stride`（input）。
- 数据/控制：`dst_stride`（input）。
- 数据/控制：`src_w`（input）。
- 数据/控制：`src_h`（input）。
- 数据/控制：`dst_w`（input）。
- 数据/控制：`dst_h`（input）。
- 握手/状态：`busy`（output）。
- 握手/状态：`done`（output）。
- 状态/错误/统计：`error`（output）。
- 握手/状态：`core_start`（output）。
- 握手/状态：`core_busy`（input）。
- 握手/状态：`core_done`（input）。
- 状态/错误/统计：`core_error`（input）。
- 状态/错误/统计：`cache_error`（input）。
- 握手/状态：`row_done`（input）。
- 握手/状态：`wb_start`（output）。
- 数据/控制：`wb_pixel_count`（output）。
- 握手/状态：`wb_busy`（input）。
- 握手/状态：`wb_done_buf`（input）。
- 状态/错误/统计：`wb_error`（input）。
- 握手/状态：`wb_out_start`（output）。
- 握手/状态：`wb_out_done`（input）。
- 握手/状态：`write_start`（output）。
- 数据/控制：`write_addr`（output）。
- 数据/控制：`write_byte_count`（output）。
- 握手/状态：`write_busy`（input）。
- 握手/状态：`write_done`（input）。
- 状态/错误/统计：`write_error`（input）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 状态机负责 idle、配置采样、算法运行、写回等待、完成/错误等阶段。
- 关键寄存器包括当前配置、目标行/像素计数、启动脉冲和错误锁存。
- 状态机 ``state_t``：S_IDLE、S_RUN、S_DONE、S_ERROR。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/ctrl/scaler_ctrl.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``core_done_seen_reg`` | ``logic 1 bit/enum``；声明：``logic core_done_seen_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>case ({wb_done_buf, launch_write_row})；default: pending_row_write_count_reg <= pending_row_write_count_reg;；if (write_done) begin；if (core_done) begin；赋值为 1'b1 |
| ``dst_base_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] dst_base_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，dst_base_addr | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 dst_base_addr |
| ``dst_h_reg`` | ``logic [$clog2(MAX_DST_H+1)-1:0]``；声明：``logic [$clog2(MAX_DST_H+1)-1:0] dst_h_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_h | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 dst_h |
| ``dst_stride_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] dst_stride_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_stride | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 dst_stride |
| ``dst_w_reg`` | ``logic [$clog2(MAX_DST_W+1)-1:0]``；声明：``logic [$clog2(MAX_DST_W+1)-1:0] dst_w_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_w | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 dst_w |
| ``pending_row_start_reg`` | ``logic 1 bit/enum``；声明：``logic pending_row_start_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>if (start) begin；S_RUN: begin；if (launch_first_row) begin；if (launch_next_row) begin；赋值为 1'b0<br>S_RUN: begin；if (launch_first_row) begin；if (launch_next_row) begin；if (row_done && (row_started_count_reg < dst_h_reg)) begin；赋值为 1'b1 |
| ``pending_row_write_count_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] pending_row_write_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，pending_row_write_count_reg + 1'b1，pending_row_write_count_reg - 1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；赋值为 '0<br>if (launch_first_row) begin；if (launch_next_row) begin；if (row_done && (row_started_count_reg < dst_h_reg)) begin；case ({wb_done_buf, launch_write_row})；赋值为 pending_row_write_count_reg + 1'b1<br>if (launch_first_row) begin；if (launch_next_row) begin；if (row_done && (row_started_count_reg < dst_h_reg)) begin；case ({wb_done_buf, launch_write_row})；赋值为 pending_row_write_count_reg - 1'b1<br>if (launch_next_row) begin；if (row_done && (row_started_count_reg < dst_h_reg)) begin；case ({wb_done_buf, launch_write_row})；default: pending_row_write_count_reg <= pending_row_write_count_reg;；赋值为 pending_row_write_count_reg |
| ``row_started_count_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] row_started_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_started_count_reg + 1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_RUN: begin；if (launch_first_row) begin；赋值为 row_started_count_reg + 1'b1<br>if (start) begin；S_RUN: begin；if (launch_first_row) begin；if (launch_next_row) begin；赋值为 row_started_count_reg + 1'b1 |
| ``row_written_count_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] row_written_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_written_count_reg + 1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；case (state_reg)；S_IDLE: begin；赋值为 '0<br>if (row_done && (row_started_count_reg < dst_h_reg)) begin；case ({wb_done_buf, launch_write_row})；default: pending_row_write_count_reg <= pending_row_write_count_reg;；if (write_done) begin；赋值为 row_written_count_reg + 1'b1 |
| ``state_reg`` | ``state_t 1 bit/enum``；声明：``state_t state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``state_t``：``S_IDLE``=0，``S_RUN``=1，``S_DONE``=2，``S_ERROR``=3 | if (sys_rst) begin；赋值为 S_IDLE<br>if (sys_rst) begin；赋值为 state_next<br>if (core_done) begin；S_DONE: begin；S_ERROR: begin；default: begin；赋值为 S_IDLE |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``state_t``，编码位宽：``[1:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``S_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 到 ``S_ERROR``：S_IDLE: begin；if (start) begin；if (invalid_start) begin<br>到 ``S_RUN``：S_IDLE: begin；if (start) begin；if (invalid_start) begin |
| ``S_RUN`` | 1 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``S_ERROR``：S_RUN: begin；if (core_error \|\| cache_error \|\| wb_error \|\| write_error) begin<br>到 ``S_DONE``：S_RUN: begin；if (core_error \|\| cache_error \|\| wb_error \|\| write_error) begin |
| ``S_DONE`` | 2 | 输出、排空或完成阶段。 | 到 ``S_IDLE``：S_DONE: begin |
| ``S_ERROR`` | 3 | 错误处理或错误结果上报阶段。 | 到 ``S_IDLE``：S_ERROR: begin |

<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为 ``frame_config_cdc``。
- 下游为 ``rotate_core_bilinear``、``row_out_buffer``、``ddr_write_engine``，并间接依赖 cache/read 路径。

## 9. 握手协议说明
- 配置使用 ready/valid。
- 算法 start 通常为单拍脉冲，之后依靠 busy/done/error。
- 写 engine 使用 start/ready，未 ready 时控制器必须保持任务字段稳定。

## 10. 错误处理与边界条件
- 下游任一路径 error 应汇总为帧任务 error。
- 尺寸/stride 非法组合是否完全检查需按源码确认。

## 11. 综合/时序/CDC注意事项
- 控制器时序通常低于 cache/算法 core，但跨域配置必须只来自 CDC 输出。
- start/done/error 的脉冲/电平关系影响顶层 sticky 逻辑。

## 12. 维护建议
- 修改流程时先更新 image pipeline 时序说明。
- 若保留 scale core，应明确模式选择。

## 13. 待确认问题
- 待确认：scale-only 路径是否仍为最终功能。
