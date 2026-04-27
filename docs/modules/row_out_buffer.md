# row_out_buffer

> 依据文件：``rtl/buffer/row_out_buffer.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- 位于 ``rotate_core_bilinear`` 与 ``ddr_write_engine`` 之间。
- 按目标行收集像素，行满后顺序输出给写回路径。

## 2. 文件路径
- ``rtl/buffer/row_out_buffer.sv``

## 3. 主要功能
- 使用行内存/数组保存目标行像素。
- 提供 fill 和 drain 两套指针/活动标志。
- 对算法输出和写 engine 输入进行 valid/ready 解耦。

## 4. 参数说明
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_W``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``BUF_NUM``：默认 ``2``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`sys_rst`（input）。
- 握手/状态：`row_start`（input）。
- 数据/控制：`row_pixel_count`（input）。
- 握手/状态：`row_busy`（output）。
- 握手/状态：`row_done`（output）。
- 状态/错误/统计：`row_error`（output）。
- 数据/控制：`in_data`（input）。
- 握手/状态：`in_valid`（input）。
- 握手/状态：`in_ready`（output）。
- 握手/状态：`out_start`（input）。
- 数据/控制：`out_data`（output）。
- 握手/状态：`out_valid`（output）。
- 握手/状态：`out_ready`（input）。
- 握手/状态：`out_done`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 无显式 enum，核心寄存器为 ``fill_active_reg``、``drain_active_reg``、``wr_ptr_reg``、``rd_ptr_reg``、``fill_pixel_count_reg``、``drain_pixel_count_reg``、``out_valid_reg``。
- ``in_fire`` 推进写指针，``out_fire`` 推进读指针。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/buffer/row_out_buffer.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``drain_active_reg`` | ``logic 1 bit/enum``；声明：``logic drain_active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 1'b1<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 1'b0 |
| ``drain_pixel_count_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] drain_pixel_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，slot_pixel_count_reg[drain_sel_next] | if (sys_rst) begin；赋值为 '0<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 slot_pixel_count_reg[drain_sel_next] |
| ``drain_sel_reg`` | ``logic [BUF_SEL_W-1:0]``；声明：``logic [BUF_SEL_W-1:0] drain_sel_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，drain_sel_next | if (sys_rst) begin；赋值为 '0<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 drain_sel_next |
| ``fill_active_reg`` | ``logic 1 bit/enum``；声明：``logic fill_active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 1'b1<br>if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；赋值为 1'b0 |
| ``fill_pixel_count_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] fill_pixel_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_pixel_count | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 row_pixel_count |
| ``fill_sel_reg`` | ``logic [BUF_SEL_W-1:0]``；声明：``logic [BUF_SEL_W-1:0] fill_sel_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，free_slot_sel | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 free_slot_sel |
| ``out_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] out_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，mem_reg[drain_sel_next][0 +: PIXEL_W] | if (sys_rst) begin；赋值为 '0<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 mem_reg[drain_sel_next][0 +: PIXEL_W]<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 mem_reg[drain_sel_reg][pixel_lsb(rd_ptr_reg[ADDR_W-1:0] + 1'b1) +: PIXEL_W] |
| ``out_done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 1'b1 |
| ``out_valid_reg`` | ``logic 1 bit/enum``；声明：``logic out_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 1'b1<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 1'b0<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 1'b1 |
| ``rd_ptr_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] rd_ptr_reg;`` | FIFO/队列指针寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 '0<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 rd_ptr_reg + 1'b1 |
| ``ready_count_reg`` | ``logic [READY_CNT_W-1:0]``；声明：``logic [READY_CNT_W-1:0] ready_count_reg;`` | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：'0，ready_count_reg + 1'b1，ready_count_reg - 1'b1 | if (sys_rst) begin；赋值为 '0<br>if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；赋值为 ready_count_reg + 1'b1<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 ready_count_reg - 1'b1 |
| ``ready_queue_reg`` | ``logic [BUF_SEL_W-1:0]``；声明：``logic [BUF_SEL_W-1:0] ready_queue_reg [0:BUF_NUM-1];`` | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：'0，fill_sel_reg，ready_queue_reg[queue_idx_ff+1] | if (sys_rst) begin；赋值为 '0<br>if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；赋值为 fill_sel_reg<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 ready_queue_reg[queue_idx_ff+1]<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 '0 |
| ``row_done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；赋值为 1'b1 |
| ``row_error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 1'b1<br>if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；赋值为 1'b1<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 1'b1 |
| ``slot_occupied_reg`` | ``logic [BUF_NUM-1:0]``；声明：``logic [BUF_NUM-1:0] slot_occupied_reg; // 槽位正被占用`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 1'b1<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 1'b0 |
| ``slot_pixel_count_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] slot_pixel_count_reg [0:BUF_NUM-1];`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，row_pixel_count | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 row_pixel_count<br>if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；if (drain_active_reg && out_fire) begin；if (drain_done_fire) begin；赋值为 '0 |
| ``slot_ready_reg`` | ``logic [BUF_NUM-1:0]``；声明：``logic [BUF_NUM-1:0] slot_ready_reg; // 槽位已装满且等待写回`` | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：'0，1'b0，1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 1'b0<br>if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；赋值为 1'b1<br>if (fill_done_fire) begin；if (ready_count_reg == BUF_NUM) begin；if (out_start && !drain_active_reg) begin；if (ready_count_reg == 0) begin；赋值为 1'b0 |
| ``wr_ptr_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] wr_ptr_reg;`` | FIFO/队列指针寄存器。 | 复位/清零候选：'0，wr_ptr_reg + 1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；赋值为 '0<br>if (sys_rst) begin；if (row_start) begin；if ((row_pixel_count == 0) \|\| (row_pixel_count > MAX_DST_W) \|\| fill_active_reg \|\| !have_free_slot) begin；if (fill_active_reg && in_fire) begin；赋值为 wr_ptr_reg + 1'b1 |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为算法核心输出像素。
- 下游为 ``ddr_write_engine`` 输入像素。

## 9. 握手协议说明
- ``in_ready = fill_active_reg && (wr_ptr_reg < fill_pixel_count_reg)``。
- ``out_valid_reg`` 保持到 ``out_ready``。
- fill/drain 是否允许重叠按源码活动标志判断，不能默认是双缓冲。

## 10. 错误处理与边界条件
- 行长度超过 ``MAX_DST_W`` 或输入数量与计划不匹配是主要边界风险。
- 下游长期不 ready 会通过 out_valid 保持逐级反压。

## 11. 综合/时序/CDC注意事项
- 存储资源由 ``MAX_DST_W`` 和 ``PIXEL_W`` 决定。
- 无 CDC。

## 12. 维护建议
- 若改成多行/双缓冲，必须重新写清 fill/drain 并发规则。

## 13. 待确认问题
- 待确认：最终 RTL 是否允许填下一行与写当前行重叠。
