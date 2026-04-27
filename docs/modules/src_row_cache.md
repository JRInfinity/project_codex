# src_row_cache

> 依据文件：``rtl/buffer/src_row_cache.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `src_row_cache`：多行源行缓存，维护相邻源行命中和 fill。
- 在当前主说明中属于保留、辅助或算法子单元；是否进入最终顶层需看实例化关系。

## 2. 文件路径
- ``rtl/buffer/src_row_cache.sv``

## 3. 主要功能
- 多行源行缓存，维护相邻源行命中和 fill。
- 通过源码端口与状态机可以追溯其控制、数据和错误路径。

## 4. 参数说明
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``ADDR_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_W``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_H``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``LINE_NUM``：默认 ``2``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`sys_rst`（input）。
- 握手/状态：`start`（input）。
- 数据/控制：`src_base_addr`（input）。
- 数据/控制：`src_stride`（input）。
- 数据/控制：`src_w`（input）。
- 数据/控制：`src_h`（input）。
- 握手/状态：`busy`（output）。
- 握手/状态：`prefill_done`（output）。
- 状态/错误/统计：`error`（output）。
- 握手/状态：`read_start`（output）。
- 数据/控制：`read_addr`（output）。
- 数据/控制：`read_byte_count`（output）。
- 握手/状态：`read_busy`（input）。
- 握手/状态：`read_done`（input）。
- 状态/错误/统计：`read_error`（input）。
- 数据/控制：`in_data`（input）。
- 握手/状态：`in_valid`（input）。
- 握手/状态：`in_ready`（output）。
- 握手/状态：`line_req_valid`（input）。
- 数据/控制：`line_req_y`（input）。
- 握手/状态：`line_req_ready`（output）。
- 数据/控制：`line_req_sel0`（output）。
- 数据/控制：`line_req_sel1`（output）。
- 握手/状态：`rd0_req_valid`（input）。
- 数据/控制：`rd0_line_sel`（input）。
- 数据/控制：`rd0_x`（input）。
- 数据/控制：`rd0_data`（output）。
- 握手/状态：`rd0_data_valid`（output）。
- 握手/状态：`rd1_req_valid`（input）。
- 数据/控制：`rd1_line_sel`（input）。
- 数据/控制：`rd1_x`（input）。
- 数据/控制：`rd1_data`（output）。
- 握手/状态：`rd1_data_valid`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 内部通常为小状态机、坐标/指针寄存器或行存储。
- 若被主链路实例化，时序和边界策略应与调用者一起审查。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/buffer/src_row_cache.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``active_reg`` | ``logic 1 bit/enum``；声明：``logic active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 1'b1<br>if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；赋值为 1'b0<br>if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；赋值为 1'b0<br>if (fill_active_reg && fill_fire) begin；if (fill_done_fire) begin；if ((fill_y_reg + 1'b1) >= prefill_target_reg) begin；if (read_done && fill_active_reg && (wr_ptr_reg != fill_pixel_count_reg)) begin；赋值为 1'b0 |
| ``error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 1'b0<br>if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；赋值为 1'b1<br>if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；赋值为 1'b1<br>if (fill_active_reg && fill_fire) begin；if (fill_done_fire) begin；if ((fill_y_reg + 1'b1) >= prefill_target_reg) begin；if (read_done && fill_active_reg && (wr_ptr_reg != fill_pixel_count_reg)) begin；赋值为 1'b1 |
| ``fill_active_reg`` | ``logic 1 bit/enum``；声明：``logic fill_active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 1'b0<br>if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；赋值为 1'b0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 1'b1<br>if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；if (fill_active_reg && fill_fire) begin；if (fill_done_fire) begin；赋值为 1'b0 |
| ``fill_pixel_count_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] fill_pixel_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 src_w_reg |
| ``fill_sel_reg`` | ``logic [LINE_SEL_W-1:0]``；声明：``logic [LINE_SEL_W-1:0] fill_sel_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 free_slot_sel |
| ``fill_y_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] fill_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 next_prefetch_y_reg |
| ``next_prefetch_y_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] next_prefetch_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 next_prefetch_y_reg + 1'b1 |
| ``prefill_done_reg`` | ``logic 1 bit/enum``；声明：``logic prefill_done_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 1'b0<br>if (launch_read) begin；if (fill_active_reg && fill_fire) begin；if (fill_done_fire) begin；if ((fill_y_reg + 1'b1) >= prefill_target_reg) begin；赋值为 1'b1 |
| ``prefill_target_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] prefill_target_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，(src_h < LINE_NUM) ? src_h[SRC_Y_W-1:0] : SRC_Y_W'(LINE_NUM) | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 (src_h < LINE_NUM) ? src_h[SRC_Y_W-1:0] : SRC_Y_W'(LINE_NUM) |
| ``rd0_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] rd0_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，mem_reg[rd0_line_sel][rd0_x] | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；赋值为 mem_reg[rd0_line_sel][rd0_x] |
| ``rd0_data_valid_reg`` | ``logic 1 bit/enum``；声明：``logic rd0_data_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；赋值为 1'b1 |
| ``rd1_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] rd1_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，mem_reg[rd1_line_sel][rd1_x] | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；赋值为 mem_reg[rd1_line_sel][rd1_x] |
| ``rd1_data_valid_reg`` | ``logic 1 bit/enum``；声明：``logic rd1_data_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；赋值为 1'b1 |
| ``slot_occupied_reg`` | ``logic [LINE_NUM-1:0]``；声明：``logic [LINE_NUM-1:0] slot_occupied_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，1'b0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；赋值为 1'b0<br>if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；赋值为 1'b0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 1'b1 |
| ``slot_ready_reg`` | ``logic [LINE_NUM-1:0]``；声明：``logic [LINE_NUM-1:0] slot_ready_reg;`` | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：'0，1'b0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；赋值为 1'b0<br>if ((src_w_reg == 0) \|\| (src_h_reg == 0)) begin；if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；赋值为 1'b0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 1'b0<br>if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；if (fill_active_reg && fill_fire) begin；if (fill_done_fire) begin；赋值为 1'b1 |
| ``slot_y_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] slot_y_reg [0:LINE_NUM-1];`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 next_prefetch_y_reg |
| ``src_base_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] src_base_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，src_base_addr | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 src_base_addr |
| ``src_h_reg`` | ``logic [$clog2(MAX_SRC_H+1)-1:0]``；声明：``logic [$clog2(MAX_SRC_H+1)-1:0] src_h_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_h | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 src_h |
| ``src_stride_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] src_stride_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_stride | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 src_stride |
| ``src_w_reg`` | ``logic [$clog2(MAX_SRC_W+1)-1:0]``；声明：``logic [$clog2(MAX_SRC_W+1)-1:0] src_w_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_w | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 src_w |
| ``wr_ptr_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] wr_ptr_reg;`` | FIFO/队列指针寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid && slot_ready_reg[rd0_line_sel]) begin；if (rd1_req_valid && slot_ready_reg[rd1_line_sel]) begin；if (start) begin；赋值为 '0<br>if (read_error) begin；if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；赋值为 '0<br>if (line_req_valid) begin；if (slot_ready_reg[slot_idx_rel] && (slot_y_reg[slot_idx_rel] < line_req_y)) begin；if (launch_read) begin；if (fill_active_reg && fill_fire) begin；赋值为 wr_ptr_reg + 1'b1 |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游/下游以源码实例化为准；未被 ``image_geo_top`` 直接实例化的模块在系统中按辅助路径记录。

## 9. 握手协议说明
- 使用 start/done、valid/ready、line_req/pixel_req 或读写指针完成局部握手。
- 输出 valid 必须保持到下游 ready。

## 10. 错误处理与边界条件
- 零尺寸、行长度越界、坐标越界或 fill 数量不匹配是主要边界条件。
- 无法从源码确定的系统级策略标为待确认。

## 11. 综合/时序/CDC注意事项
- 坐标乘加、宽加法、行存储读写是主要 timing 关注点。
- 除非源码声明双时钟，本类模块按单 core 域理解。

## 12. 维护建议
- 若重新接入顶层，需要补充模式选择、端口连线和验证状态。
- 保留模块应明确是否为 legacy，以免答辩时与主链路混淆。

## 13. 待确认问题
- 待确认：该模块是否纳入最终综合/演示配置。
