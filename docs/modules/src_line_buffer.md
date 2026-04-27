# src_line_buffer

> 依据文件：``rtl/buffer/src_line_buffer.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `src_line_buffer`：简单源行缓冲，服务早期/辅助缩放路径。
- 在当前主说明中属于保留、辅助或算法子单元；是否进入最终顶层需看实例化关系。

## 2. 文件路径
- ``rtl/buffer/src_line_buffer.sv``

## 3. 主要功能
- 简单源行缓冲，服务早期/辅助缩放路径。
- 通过源码端口与状态机可以追溯其控制、数据和错误路径。

## 4. 参数说明
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_W``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``LINE_NUM``：默认 ``2``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`sys_rst`（input）。
- 握手/状态：`load_start`（input）。
- 数据/控制：`load_line_sel`（input）。
- 数据/控制：`load_pixel_count`（input）。
- 握手/状态：`load_busy`（output）。
- 握手/状态：`load_done`（output）。
- 状态/错误/统计：`load_error`（output）。
- 数据/控制：`in_data`（input）。
- 握手/状态：`in_valid`（input）。
- 握手/状态：`in_ready`（output）。
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
- 状态机 ``state_t``：S_IDLE、S_LOAD、S_DONE。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/buffer/src_line_buffer.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``load_done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (load_pixel_count > MAX_SRC_W) begin；S_LOAD: begin；if (load_fire) begin；S_DONE: begin；赋值为 !load_error |
| ``load_error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (rd0_req_valid) begin；if (rd1_req_valid) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>case (state_reg)；S_IDLE: begin；if (load_start) begin；if (load_pixel_count > MAX_SRC_W) begin；赋值为 1'b1 |
| ``load_line_sel_reg`` | ``logic [LINE_SEL_W-1:0]``；声明：``logic [LINE_SEL_W-1:0] load_line_sel_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，load_line_sel | if (sys_rst) begin；赋值为 '0<br>if (rd1_req_valid) begin；case (state_reg)；S_IDLE: begin；if (load_start) begin；赋值为 load_line_sel |
| ``load_pixel_count_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] load_pixel_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，load_pixel_count | if (sys_rst) begin；赋值为 '0<br>if (rd1_req_valid) begin；case (state_reg)；S_IDLE: begin；if (load_start) begin；赋值为 load_pixel_count |
| ``load_wr_ptr_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] load_wr_ptr_reg;`` | FIFO/队列指针寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (rd1_req_valid) begin；case (state_reg)；S_IDLE: begin；if (load_start) begin；赋值为 '0<br>if (load_start) begin；if (load_pixel_count > MAX_SRC_W) begin；S_LOAD: begin；if (load_fire) begin；赋值为 load_wr_ptr_reg + 1'b1 |
| ``rd0_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] rd0_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，mem_reg[rd0_line_sel][rd0_x] | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid) begin；赋值为 mem_reg[rd0_line_sel][rd0_x] |
| ``rd0_data_valid_reg`` | ``logic 1 bit/enum``；声明：``logic rd0_data_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid) begin；赋值为 1'b1 |
| ``rd1_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] rd1_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，mem_reg[rd1_line_sel][rd1_x] | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (rd0_req_valid) begin；if (rd1_req_valid) begin；赋值为 mem_reg[rd1_line_sel][rd1_x] |
| ``rd1_data_valid_reg`` | ``logic 1 bit/enum``；声明：``logic rd1_data_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (rd0_req_valid) begin；if (rd1_req_valid) begin；赋值为 1'b1 |
| ``state_reg`` | ``state_t 1 bit/enum``；声明：``state_t state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``state_t``：``S_IDLE``=0，``S_LOAD``=1，``S_DONE``=2 | if (sys_rst) begin；赋值为 S_IDLE<br>if (sys_rst) begin；赋值为 state_next<br>S_LOAD: begin；if (load_fire) begin；S_DONE: begin；default: begin；赋值为 S_IDLE |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``state_t``，编码位宽：``[1:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``S_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 到 ``S_LOAD``：S_IDLE: begin；if (load_start && (load_pixel_count != 0)) begin |
| ``S_LOAD`` | 1 | 装载/捕获输入数据或填充缓存。 | 到 ``S_DONE``：S_LOAD: begin；if (load_error) begin |
| ``S_DONE`` | 2 | 输出、排空或完成阶段。 | 到 ``S_IDLE``：S_DONE: begin |

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
