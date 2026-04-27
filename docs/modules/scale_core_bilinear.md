# scale_core_bilinear

> 依据文件：``rtl/core/scale_core_bilinear.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `scale_core_bilinear`：双线性缩放核心，保留/辅助算法路径。
- 在当前主说明中属于保留、辅助或算法子单元；是否进入最终顶层需看实例化关系。

## 2. 文件路径
- ``rtl/core/scale_core_bilinear.sv``

## 3. 主要功能
- 双线性缩放核心，保留/辅助算法路径。
- 通过源码端口与状态机可以追溯其控制、数据和错误路径。

## 4. 参数说明
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_W``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_H``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_W``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_H``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``FRAC_W``：默认 ``16``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``LINE_NUM``：默认 ``2``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`rst`（input）。
- 握手/状态：`start`（input）。
- 数据/控制：`src_w`（input）。
- 数据/控制：`src_h`（input）。
- 数据/控制：`dst_w`（input）。
- 数据/控制：`dst_h`（input）。
- 握手/状态：`busy`（output）。
- 握手/状态：`done`（output）。
- 状态/错误/统计：`error`（output）。
- 握手/状态：`line_req_valid`（output）。
- 数据/控制：`line_req_y`（output）。
- 握手/状态：`line_req_ready`（input）。
- 数据/控制：`line_req_sel`（input）。
- 握手/状态：`pixel_req_valid`（output）。
- 数据/控制：`pixel_req_x`（output）。
- 数据/控制：`rd0_rsp_data`（input）。
- 握手/状态：`rd0_rsp_valid`（input）。
- 数据/控制：`rd1_rsp_data`（input）。
- 握手/状态：`rd1_rsp_valid`（input）。
- 数据/控制：`pix_data`（output）。
- 握手/状态：`pix_valid`（output）。
- 握手/状态：`pix_ready`（input）。
- 握手/状态：`row_done`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 内部通常为小状态机、坐标/指针寄存器或行存储。
- 若被主链路实例化，时序和边界策略应与调用者一起审查。
- 状态机 ``state_t``：S_IDLE、S_PREP_ROW、S_REQ_LINES、S_REQ_X0、S_WAIT_X0、S_REQ_X1、S_WAIT_X1、S_OUT。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/core/scale_core_bilinear.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 1'b1 |
| ``dst_x_reg`` | ``logic [DST_X_W-1:0]``；声明：``logic [DST_X_W-1:0] dst_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 '0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 '0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 dst_x_reg + 1'b1 |
| ``dst_y_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] dst_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 '0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 dst_y_reg + 1'b1 |
| ``error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>case (state_reg)；S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；赋值为 1'b1 |
| ``frac_x_reg`` | ``logic [FRAC_W-1:0]``；声明：``logic [FRAC_W-1:0] frac_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，frac_x_calc | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；赋值为 frac_x_calc<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 next_frac_x_calc |
| ``frac_y_reg`` | ``logic [FRAC_W-1:0]``；声明：``logic [FRAC_W-1:0] frac_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，frac_y_calc | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；赋值为 frac_y_calc |
| ``line_sel0_reg`` | ``logic [LINE_SEL_W-1:0]``；声明：``logic [LINE_SEL_W-1:0] line_sel0_reg; // 当前行所需的两条源行在 line buffer 中的选择信号`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，line_req_sel | if (rst) begin；赋值为 '0<br>if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；S_REQ_LINES: begin；if (line_req_valid && line_req_ready) begin；赋值为 line_req_sel |
| ``line_sel1_reg`` | ``logic [LINE_SEL_W-1:0]``；声明：``logic [LINE_SEL_W-1:0] line_sel1_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，line_req_sel ^ ((LINE_NUM == 2) ? 1'b1 : 1'b0) | if (rst) begin；赋值为 '0<br>if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；S_REQ_LINES: begin；if (line_req_valid && line_req_ready) begin；赋值为 line_req_sel ^ ((LINE_NUM == 2) ? 1'b1 : 1'b0) |
| ``p00_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] p00_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ_LINES: begin；if (line_req_valid && line_req_ready) begin；S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；赋值为 rd0_rsp_data |
| ``p01_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] p01_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；S_WAIT_X1: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；赋值为 rd0_rsp_data |
| ``p10_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] p10_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ_LINES: begin；if (line_req_valid && line_req_ready) begin；S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；赋值为 rd1_rsp_data |
| ``p11_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] p11_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；S_WAIT_X1: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；赋值为 rd1_rsp_data |
| ``pix_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] pix_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；S_WAIT_X1: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；赋值为 out_pix_live_calc |
| ``pix_valid_reg`` | ``logic 1 bit/enum``；声明：``logic pix_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；S_WAIT_X1: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；赋值为 1'b1<br>S_WAIT_X1: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin；S_OUT: begin；if (pix_fire) begin；赋值为 1'b0 |
| ``row_done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>if (rd0_rsp_valid && rd1_rsp_valid) begin；S_OUT: begin；if (pix_fire) begin；if (last_col) begin；赋值为 1'b1 |
| ``scale_x_reg`` | ``logic [SCALE_W-1:0]``；声明：``logic [SCALE_W-1:0] scale_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，(src_w << FRAC_W) / dst_w | if (rst) begin；赋值为 '0<br>case (state_reg)；S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；赋值为 (src_w << FRAC_W) / dst_w |
| ``scale_y_reg`` | ``logic [SCALE_W-1:0]``；声明：``logic [SCALE_W-1:0] scale_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，(src_h << FRAC_W) / dst_h | if (rst) begin；赋值为 '0<br>case (state_reg)；S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；赋值为 (src_h << FRAC_W) / dst_h |
| ``src_x0_reg`` | ``logic [SRC_X_W-1:0]``；声明：``logic [SRC_X_W-1:0] src_x0_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_x0_calc | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；赋值为 src_x0_calc<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 next_src_x0_calc |
| ``src_x1_reg`` | ``logic [SRC_X_W-1:0]``；声明：``logic [SRC_X_W-1:0] src_x1_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_x1_calc | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；赋值为 src_x1_calc<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 next_src_x1_calc |
| ``src_y0_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] src_y0_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_y0_calc | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；赋值为 src_y0_calc |
| ``src_y1_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] src_y1_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_y1_calc | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；if ((src_w == 0) \|\| (src_h == 0) \|\| (dst_w == 0) \|\| (dst_h == 0)) begin；S_PREP_ROW: begin；赋值为 src_y1_calc |
| ``state_reg`` | ``state_t 1 bit/enum``；声明：``state_t state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``state_t``：``S_IDLE``=0，``S_PREP_ROW``=1，``S_REQ_LINES``=2，``S_REQ_X0``=3，``S_WAIT_X0``=4，``S_REQ_X1``=5，``S_WAIT_X1``=6，``S_OUT``=7 | if (rst) begin；赋值为 S_IDLE<br>if (rst) begin；赋值为 state_next |
| ``x_pos_reg`` | ``logic [SCALE_W-1:0]``；声明：``logic [SCALE_W-1:0] x_pos_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 '0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 '0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 x_pos_next_calc |
| ``y_pos_reg`` | ``logic [SCALE_W-1:0]``；声明：``logic [SCALE_W-1:0] y_pos_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 '0<br>S_OUT: begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 y_pos_next_calc |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``state_t``，编码位宽：``[2:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``S_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 到 ``S_PREP_ROW``：S_IDLE: begin；if (start) begin |
| ``S_PREP_ROW`` | 1 | 初始化、预计算或准备阶段。 | 到 ``S_IDLE``：S_PREP_ROW: begin；if (error) begin<br>到 ``S_REQ_LINES``：S_PREP_ROW: begin；if (error) begin |
| ``S_REQ_LINES`` | 2 | 发起请求或地址通道阶段。 | 到 ``S_REQ_X0``：S_REQ_LINES: begin；if (line_req_valid && line_req_ready) begin |
| ``S_REQ_X0`` | 3 | 发起请求或地址通道阶段。 | 到 ``S_WAIT_X0``：S_REQ_X0: begin |
| ``S_WAIT_X0`` | 4 | 等待下游响应或返回数据。 | 到 ``S_REQ_X1``：S_WAIT_X0: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin |
| ``S_REQ_X1`` | 5 | 发起请求或地址通道阶段。 | 到 ``S_WAIT_X1``：S_REQ_X1: begin |
| ``S_WAIT_X1`` | 6 | 等待下游响应或返回数据。 | 到 ``S_OUT``：S_WAIT_X1: begin；if (rd0_rsp_valid && rd1_rsp_valid) begin |
| ``S_OUT`` | 7 | 输出、排空或完成阶段。 | 到 ``S_IDLE``：S_OUT: begin；if (pix_fire) begin；if (last_col && last_row) begin<br>到 ``S_PREP_ROW``：S_OUT: begin；if (pix_fire) begin；if (last_col && last_row) begin<br>到 ``S_REQ_X0``：S_OUT: begin；if (pix_fire) begin；if (last_col && last_row) begin |

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
