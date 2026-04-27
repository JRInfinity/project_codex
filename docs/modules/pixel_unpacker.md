# pixel_unpacker

> 依据文件：``rtl/core/pixel_unpacker.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `pixel_unpacker` 是主链路基础模块：AXI word 到 8 bit 像素流转换，服务 DDR 读返回。
- 其设计目的不是实现图像算法，而是把跨域、数据格式或 AXI 公共计算从主控制逻辑中拆出来。

## 2. 文件路径
- ``rtl/core/pixel_unpacker.sv``

## 3. 主要功能
- 主要功能：AXI word 到 8 bit 像素流转换，服务 DDR 读返回。
- 具体字段、宽度和非法参数由源码参数、localparam 和 ``initial`` 检查约束。

## 4. 参数说明
- ``DATA_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``ADDR_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`core_clk`（input）。
- 时钟/复位：`sys_rst`（input）。
- 握手/状态：`task_start`（input）。
- 数据/控制：`task_addr`（input）。
- 数据/控制：`task_byte_count`（input）。
- 数据/控制：`task_row_byte_count`（input）。
- 握手/状态：`reader_status_valid`（input）。
- 握手/状态：`reader_done_evt`（input）。
- 状态/错误/统计：`reader_error_evt`（input）。
- 数据/控制：`fifo_rd_en`（output）。
- 数据/控制：`fifo_rd_data`（input）。
- 数据/控制：`fifo_empty`（input）。
- 数据/控制：`fifo_underflow`（input）。
- 数据/控制：`pixel_data`（output）。
- 握手/状态：`pixel_valid`（output）。
- 握手/状态：`pixel_row_last`（output）。
- 握手/状态：`pixel_ready`（input）。
- 握手/状态：`task_done_level`（output）。
- 状态/错误/统计：`task_error_level`（output）。
- 握手/状态：`task_done_pulse`（output）。
- 状态/错误/统计：`task_error_pulse`（output）。
- 状态/错误/统计：`task_error_flag`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 内部结构以寄存器化控制和小型 FIFO/状态机为主。
- 状态机和状态名见本页自动提取的“内部结构”补充项；若无状态机则以组合函数或 FIFO wrapper 为主。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/core/pixel_unpacker.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``bytes_remaining_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] bytes_remaining_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，task_byte_count，bytes_remaining_reg - 1'b1 | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (task_start) begin；赋值为 task_byte_count<br>if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；if (pixel_fire) begin；赋值为 bytes_remaining_reg - 1'b1 |
| ``current_byte_idx_reg`` | ``logic [OFFSET_W-1:0]``；声明：``logic [OFFSET_W-1:0] current_byte_idx_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，next_word_offset_calc | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (task_start) begin；赋值为 '0<br>if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；赋值为 next_word_offset_calc<br>if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；if (current_valid_bytes_reg == 1) begin；赋值为 current_byte_idx_reg + 1'b1 |
| ``current_valid_bytes_reg`` | ``logic [OFFSET_W:0]``；声明：``logic [OFFSET_W:0] current_valid_bytes_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：'0，next_word_valid_bytes_calc[OFFSET_W:0] | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (task_start) begin；赋值为 '0<br>if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；赋值为 next_word_valid_bytes_calc[OFFSET_W:0]<br>if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；if (current_valid_bytes_reg == 1) begin；赋值为 '0<br>if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；if (current_valid_bytes_reg == 1) begin；赋值为 current_valid_bytes_reg - 1'b1 |
| ``current_word_reg`` | ``logic [DATA_W-1:0]``；声明：``logic [DATA_W-1:0] current_word_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，fifo_rd_data | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (task_start) begin；赋值为 '0<br>if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；赋值为 fifo_rd_data |
| ``current_word_valid_reg`` | ``logic 1 bit/enum``；声明：``logic current_word_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，(next_word_valid_bytes_calc != 0) | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b0<br>if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；赋值为 (next_word_valid_bytes_calc != 0)<br>if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；if (current_valid_bytes_reg == 1) begin；赋值为 1'b0 |
| ``first_offset_reg`` | ``logic [OFFSET_W-1:0]``；声明：``logic [OFFSET_W-1:0] first_offset_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，task_addr[OFFSET_W-1:0] | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (task_start) begin；赋值为 task_addr[OFFSET_W-1:0] |
| ``first_word_reg`` | ``logic 1 bit/enum``；声明：``logic first_word_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b1<br>if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；赋值为 1'b0 |
| ``reader_done_seen_reg`` | ``logic 1 bit/enum``；声明：``logic reader_done_seen_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；if (reader_status_valid && reader_done_evt) reader_done_seen_reg <= 1'b1;；赋值为 1'b1 |
| ``row_bytes_remaining_reg`` | ``logic [31:0]``；声明：``logic [31:0] row_bytes_remaining_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，task_row_byte_count | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (task_start) begin；赋值为 task_row_byte_count<br>if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；赋值为 32'd1) begin<br>if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；赋值为 task_row_byte_count<br>if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；if (load_new_word) begin；if (pixel_fire) begin；if (row_bytes_remaining_reg <= 32'd1) begin；赋值为 row_bytes_remaining_reg - 1'b1 |
| ``task_active_reg`` | ``logic 1 bit/enum``；声明：``logic task_active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b1<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b0 |
| ``task_done_pulse`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b1 |
| ``task_error_flag`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；if (reader_status_valid && reader_done_evt) reader_done_seen_reg <= 1'b1;；if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；赋值为 1'b1<br>if (task_start) begin；if (reader_status_valid && reader_done_evt) reader_done_seen_reg <= 1'b1;；if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；赋值为 1'b1<br>if (reader_status_valid && reader_done_evt) reader_done_seen_reg <= 1'b1;；if (reader_status_valid && reader_error_evt) task_error_flag <= 1'b1;；if (fifo_underflow) task_error_flag <= 1'b1;；if (reader_done_seen_reg && (bytes_remaining_reg != 0) &&；赋值为 1'b1 |
| ``task_error_pulse`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (task_start) begin；赋值为 1'b1 |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上下游关系见 ``image_geo_top.sv`` 和调用模块实例化。
- 在主链路中承担 CDC、格式转换或公共计算职责。

## 9. 握手协议说明
- 所有任务/结果/数据流均以 valid/ready 或 FIFO full/empty 为握手边界。
- CDC 模块要求 payload 在 ``valid`` 未被 ``ready`` 接收前保持稳定。

## 10. 错误处理与边界条件
- 非法参数通过源码检查暴露。
- FIFO full/empty、payload 不稳定、end marker 错位或长度不匹配等错误由对应模块检查。

## 11. 综合/时序/CDC注意事项
- CDC 模块不能被组合跨域旁路。
- 格式转换模块在 ``DATA_W`` 增大时要关注 byte-lane mux 和计数比较。

## 12. 维护建议
- 增删 payload 字段或统计项时同步所有实例和寄存器映射。
- 修改公共函数时同步 reader/writer 和接口专题文档。

## 13. 待确认问题
- 待确认：是否需要把内部错误原因扩展为软件可读枚举。
