# rotate_geom_init_unit

> 依据文件：``rtl/core/rotate_geom_init_unit.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `rotate_geom_init_unit`：旋转几何初始化单元，为 rotate core 计算起始坐标和步进。
- 在当前主说明中属于保留、辅助或算法子单元；是否进入最终顶层需看实例化关系。

## 2. 文件路径
- ``rtl/core/rotate_geom_init_unit.sv``

## 3. 主要功能
- 旋转几何初始化单元，为 rotate core 计算起始坐标和步进。
- 通过源码端口与状态机可以追溯其控制、数据和错误路径。

## 4. 参数说明
- ``MAX_SRC_W``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_H``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_W``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_H``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``FRAC_W``：默认 ``16``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``COORD_W``：默认 ``48``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``GEOM_ID_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`rst`（input）。
- 握手/状态：`start`（input）。
- 握手/状态：`start_id`（input）。
- 数据/控制：`src_w`（input）。
- 数据/控制：`src_h`（input）。
- 数据/控制：`dst_w`（input）。
- 数据/控制：`dst_h`（input）。
- 握手/状态：`geom_valid`（output）。
- 握手/状态：`geom_busy`（output）。
- 状态/错误/统计：`geom_error`（output）。
- 数据/控制：`geom_id`（output）。
- 握手/状态：`src_x_last`（output）。
- 握手/状态：`src_y_last`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 内部通常为小状态机、坐标/指针寄存器或行存储。
- 若被主链路实例化，时序和边界策略应与调用者一起审查。
- 状态机 ``geom_state_t``：G_IDLE、G_DIV_X_INIT、G_DIV_X_RUN、G_DIV_Y_INIT、G_DIV_Y_RUN、G_CENTER、G_STEP_XX、G_STEP_YX_MUL、G_STEP_YX、G_STEP_XY、G_STEP_YY、G_ROW_X_MUL、G_ROW_X_COMMIT、G_ROW_Y_MUL、G_ROW_Y_COMMIT。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/core/rotate_geom_init_unit.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``cfg_dst_h_reg`` | ``logic [DST_CFG_H-1:0]``；声明：``logic [DST_CFG_H-1:0] cfg_dst_h_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_h | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 dst_h |
| ``cfg_dst_w_reg`` | ``logic [DST_CFG_W-1:0]``；声明：``logic [DST_CFG_W-1:0] cfg_dst_w_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_w | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 dst_w |
| ``cfg_id_reg`` | ``logic [GEOM_ID_W-1:0]``；声明：``logic [GEOM_ID_W-1:0] cfg_id_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，start_id | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 start_id |
| ``cfg_rot_cos_q16_reg`` | ``logic [31:0]``；声明：``logic signed [31:0] cfg_rot_cos_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，rot_cos_q16 | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 rot_cos_q16 |
| ``cfg_rot_sin_q16_reg`` | ``logic [31:0]``；声明：``logic signed [31:0] cfg_rot_sin_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，rot_sin_q16 | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 rot_sin_q16 |
| ``cfg_src_h_reg`` | ``logic [SRC_CFG_H-1:0]``；声明：``logic [SRC_CFG_H-1:0] cfg_src_h_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_h | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 src_h |
| ``cfg_src_w_reg`` | ``logic [SRC_CFG_W-1:0]``；声明：``logic [SRC_CFG_W-1:0] cfg_src_w_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，src_w | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 src_w |
| ``div_count_reg`` | ``logic [5:0]``；声明：``logic [5:0] div_count_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，6'd32，div_count_reg - 1'b1 | if (rst) begin；赋值为 '0<br>G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；赋值为 6'd32<br>if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；赋值为 div_count_reg - 1'b1<br>G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；赋值为 6'd32<br>G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；赋值为 div_count_reg - 1'b1 |
| ``div_dividend_reg`` | ``logic [31:0]``；声明：``logic [31:0] div_dividend_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，32'(cfg_src_w_reg) << FRAC_W，div_dividend_next_calc | if (rst) begin；赋值为 '0<br>G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；赋值为 32'(cfg_src_w_reg) << FRAC_W<br>if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；赋值为 div_dividend_next_calc<br>G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；赋值为 32'(cfg_src_h_reg) << FRAC_W<br>G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；赋值为 div_dividend_next_calc |
| ``div_divisor_reg`` | ``logic [31:0]``；声明：``logic [31:0] div_divisor_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，32'(cfg_dst_w_reg) | if (rst) begin；赋值为 '0<br>G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；赋值为 32'(cfg_dst_w_reg)<br>G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；赋值为 32'(cfg_dst_h_reg) |
| ``div_quotient_reg`` | ``logic [31:0]``；声明：``logic [31:0] div_quotient_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，div_quotient_next_calc | if (rst) begin；赋值为 '0<br>G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；赋值为 '0<br>if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；赋值为 div_quotient_next_calc<br>G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；赋值为 '0<br>G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；赋值为 div_quotient_next_calc |
| ``div_remainder_reg`` | ``logic [32:0]``；声明：``logic [32:0] div_remainder_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，div_remainder_next_calc | if (rst) begin；赋值为 '0<br>G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；赋值为 '0<br>if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；赋值为 div_remainder_next_calc<br>G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；赋值为 '0<br>G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；赋值为 div_remainder_next_calc |
| ``dst_cx_q16_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] dst_cx_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin；G_CENTER: begin；赋值为 ($signed(COORD_W'({1'b0, cfg_dst_w_reg})) - 1) <<< (FRAC_W-1) |
| ``dst_cy_q16_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] dst_cy_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin；G_CENTER: begin；赋值为 ($signed(COORD_W'({1'b0, cfg_dst_h_reg})) - 1) <<< (FRAC_W-1) |
| ``geom_error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；case (state_reg)；G_IDLE: begin；if (start) begin；赋值为 1'b0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 1'b1<br>G_ROW_X_COMMIT: begin；G_ROW_Y_MUL: begin；G_ROW_Y_COMMIT: begin；default: begin；赋值为 1'b1 |
| ``geom_id`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_ROW_X_MUL: begin；G_ROW_X_COMMIT: begin；G_ROW_Y_MUL: begin；G_ROW_Y_COMMIT: begin；赋值为 cfg_id_reg |
| ``geom_valid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>G_ROW_X_MUL: begin；G_ROW_X_COMMIT: begin；G_ROW_Y_MUL: begin；G_ROW_Y_COMMIT: begin；赋值为 1'b1 |
| ``row_mul0_reg`` | ``logic [INIT_MUL_W-1:0]``；声明：``logic signed [INIT_MUL_W-1:0] row_mul0_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_STEP_YX: begin；G_STEP_XY: begin；G_STEP_YY: begin；G_ROW_X_MUL: begin；赋值为 $signed(dst_cx_q16_reg) * $signed(step_x_x)<br>G_STEP_YY: begin；G_ROW_X_MUL: begin；G_ROW_X_COMMIT: begin；G_ROW_Y_MUL: begin；赋值为 $signed(dst_cx_q16_reg) * $signed(step_y_x) |
| ``row_mul1_reg`` | ``logic [INIT_MUL_W-1:0]``；声明：``logic signed [INIT_MUL_W-1:0] row_mul1_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_STEP_YX: begin；G_STEP_XY: begin；G_STEP_YY: begin；G_ROW_X_MUL: begin；赋值为 $signed(dst_cy_q16_reg) * $signed(step_x_y)<br>G_STEP_YY: begin；G_ROW_X_MUL: begin；G_ROW_X_COMMIT: begin；G_ROW_Y_MUL: begin；赋值为 $signed(dst_cy_q16_reg) * $signed(step_y_y) |
| ``row0_x`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_STEP_XY: begin；G_STEP_YY: begin；G_ROW_X_MUL: begin；G_ROW_X_COMMIT: begin；赋值为 src_cx_q16_reg |
| ``row0_y`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_ROW_X_MUL: begin；G_ROW_X_COMMIT: begin；G_ROW_Y_MUL: begin；G_ROW_Y_COMMIT: begin；赋值为 src_cy_q16_reg |
| ``scale_x_q16`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，$signed(div_quotient_next_calc) | if (rst) begin；赋值为 '0<br>if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；赋值为 $signed(div_quotient_next_calc) |
| ``scale_y_q16`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin；赋值为 $signed(div_quotient_next_calc) |
| ``src_cx_q16_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] src_cx_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin；G_CENTER: begin；赋值为 ($signed(COORD_W'({1'b0, cfg_src_w_reg})) - 1) <<< (FRAC_W-1) |
| ``src_cy_q16_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] src_cy_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_DIV_Y_INIT: begin；G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin；G_CENTER: begin；赋值为 ($signed(COORD_W'({1'b0, cfg_src_h_reg})) - 1) <<< (FRAC_W-1) |
| ``src_x_last`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，SRC_X_W'(src_w - 1'b1) | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 SRC_X_W'(src_w - 1'b1) |
| ``src_x_max_q16`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，($signed(COORD_W'({1'b0, src_w})) - 1) <<< FRAC_W | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 ($signed(COORD_W'({1'b0, src_w})) - 1) <<< FRAC_W |
| ``src_y_last`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，SRC_Y_W'(src_h - 1'b1) | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 SRC_Y_W'(src_h - 1'b1) |
| ``src_y_max_q16`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，($signed(COORD_W'({1'b0, src_h})) - 1) <<< FRAC_W | if (rst) begin；赋值为 '0<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 ($signed(COORD_W'({1'b0, src_h})) - 1) <<< FRAC_W |
| ``state_reg`` | ``geom_state_t 1 bit/enum``；声明：``geom_state_t state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``geom_state_t``：``G_IDLE``=0，``G_DIV_X_INIT``=1，``G_DIV_X_RUN``=2，``G_DIV_Y_INIT``=3，``G_DIV_Y_RUN``=4，``G_CENTER``=5，``G_STEP_XX``=6，``G_STEP_YX_MUL``=7，``G_STEP_YX``=8，``G_STEP_XY``=9，``G_STEP_YY``=10，``G_ROW_X_MUL``=11，``G_ROW_X_COMMIT``=12，``G_ROW_Y_MUL``=13，``G_ROW_Y_COMMIT``=14 | if (rst) begin；赋值为 G_IDLE<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 G_IDLE<br>case (state_reg)；G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；赋值为 G_DIV_X_INIT<br>G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；赋值为 G_DIV_X_RUN<br>if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin；G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；赋值为 G_DIV_Y_INIT<br>G_DIV_X_INIT: begin；G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin；G_DIV_Y_INIT: begin；赋值为 G_DIV_Y_RUN |
| ``step_x_x`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin；G_CENTER: begin；G_STEP_XX: begin；赋值为 ($signed(cfg_rot_cos_q16_reg) * $signed(scale_x_q16)) >>> FRAC_W |
| ``step_x_y`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_STEP_XX: begin；G_STEP_YX_MUL: begin；G_STEP_YX: begin；G_STEP_XY: begin；赋值为 ($signed(cfg_rot_sin_q16_reg) * $signed(scale_y_q16)) >>> FRAC_W |
| ``step_y_x`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_CENTER: begin；G_STEP_XX: begin；G_STEP_YX_MUL: begin；G_STEP_YX: begin；赋值为 -($signed(step_y_x_mul_reg) >>> FRAC_W) |
| ``step_y_x_mul_reg`` | ``logic [INIT_MUL_W-1:0]``；声明：``logic signed [INIT_MUL_W-1:0] step_y_x_mul_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (div_count_reg == 6'd1) begin；G_CENTER: begin；G_STEP_XX: begin；G_STEP_YX_MUL: begin；赋值为 $signed(cfg_rot_sin_q16_reg) * $signed(scale_x_q16) |
| ``step_y_y`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>G_STEP_YX_MUL: begin；G_STEP_YX: begin；G_STEP_XY: begin；G_STEP_YY: begin；赋值为 ($signed(cfg_rot_cos_q16_reg) * $signed(scale_y_q16)) >>> FRAC_W |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``geom_state_t``，编码位宽：``[3:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``G_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 到 ``G_IDLE``：G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin<br>到 ``G_DIV_X_INIT``：G_IDLE: begin；if (start) begin；if ((src_w == '0) \|\| (src_h == '0) \|\| (dst_w == '0) \|\| (dst_h == '0)) begin |
| ``G_DIV_X_INIT`` | 1 | 初始化、预计算或准备阶段。 | 到 ``G_DIV_X_RUN``：G_DIV_X_INIT: begin |
| ``G_DIV_X_RUN`` | 2 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_DIV_Y_INIT``：G_DIV_X_RUN: begin；if (div_count_reg == 6'd1) begin |
| ``G_DIV_Y_INIT`` | 3 | 初始化、预计算或准备阶段。 | 到 ``G_DIV_Y_RUN``：G_DIV_Y_INIT: begin |
| ``G_DIV_Y_RUN`` | 4 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_CENTER``：G_DIV_Y_RUN: begin；if (div_count_reg == 6'd1) begin |
| ``G_CENTER`` | 5 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_STEP_XX``：G_CENTER: begin |
| ``G_STEP_XX`` | 6 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_STEP_YX_MUL``：G_STEP_XX: begin |
| ``G_STEP_YX_MUL`` | 7 | 插值乘加或混合计算阶段。 | 到 ``G_STEP_YX``：G_STEP_YX_MUL: begin |
| ``G_STEP_YX`` | 8 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_STEP_XY``：G_STEP_YX: begin |
| ``G_STEP_XY`` | 9 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_STEP_YY``：G_STEP_XY: begin |
| ``G_STEP_YY`` | 10 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_ROW_X_MUL``：G_STEP_YY: begin |
| ``G_ROW_X_MUL`` | 11 | 插值乘加或混合计算阶段。 | 到 ``G_ROW_X_COMMIT``：G_ROW_X_MUL: begin |
| ``G_ROW_X_COMMIT`` | 12 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_ROW_Y_MUL``：G_ROW_X_COMMIT: begin |
| ``G_ROW_Y_MUL`` | 13 | 插值乘加或混合计算阶段。 | 到 ``G_ROW_Y_COMMIT``：G_ROW_Y_MUL: begin |
| ``G_ROW_Y_COMMIT`` | 14 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``G_IDLE``：G_ROW_Y_COMMIT: begin |

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
