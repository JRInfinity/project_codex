# rotate_core_bilinear

> 依据文件：``rtl/core/rotate_core_bilinear.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- 位于 cache sample 和 row buffer 之间，是主算法核心。
- 每个目标像素映射到源坐标，读取邻域并做 Q 格式权重混合。

## 2. 文件路径
- ``rtl/core/rotate_core_bilinear.sv``

## 3. 主要功能
- 调用 ``rotate_geom_init_unit`` 初始化几何参数。
- 使用 ``row_advance_unit`` 和 ``xpm_memory_sdpram`` 预计算/保存行基坐标。
- 发 sample 请求并在返回后完成双线性插值。

## 4. 参数说明
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_W``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_SRC_H``：默认 ``7200``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_W``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``MAX_DST_H``：默认 ``600``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``FRAC_W``：默认 ``16``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``COORD_W``：默认 ``48``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`rst`（input）。
- 握手/状态：`start`（input）。
- 数据/控制：`src_w`（input）。
- 数据/控制：`src_h`（input）。
- 数据/控制：`dst_w`（input）。
- 数据/控制：`dst_h`（input）。
- 握手/状态：`geom_ready`（input）。
- 状态/错误/统计：`geom_error`（input）。
- 握手/状态：`geom_src_x_last`（input）。
- 握手/状态：`geom_src_y_last`（input）。
- 握手/状态：`busy`（output）。
- 握手/状态：`done`（output）。
- 状态/错误/统计：`error`（output）。
- 握手/状态：`sample_req_valid`（output）。
- 数据/控制：`sample_x0`（output）。
- 数据/控制：`sample_y0`（output）。
- 数据/控制：`sample_x1`（output）。
- 数据/控制：`sample_y1`（output）。
- 握手/状态：`sample_req_ready`（input）。
- 数据/控制：`sample_p00`（input）。
- 数据/控制：`sample_p01`（input）。
- 数据/控制：`sample_p10`（input）。
- 数据/控制：`sample_p11`（input）。
- 握手/状态：`sample_rsp_valid`（input）。
- 握手/状态：`scan_dir_valid`（output）。
- 数据/控制：`pix_data`（output）。
- 握手/状态：`pix_valid`（output）。
- 握手/状态：`pix_ready`（input）。
- 握手/状态：`row_done`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 状态机包含 ``S_GEOM_WAIT``、``S_PRECALC_*``、``S_CLAMP``、``S_INDEX``、``S_REQ``、``S_WAIT``、``S_MIX*``、``S_OUT`` 等阶段。
- ``sample_req_valid = (state_reg == S_REQ)``。
- ``pix_fire = pix_valid_reg && pix_ready`` 控制目标像素推进。
- 状态机 ``state_t``：S_IDLE、S_GEOM_WAIT、S_PRECALC_INIT、S_PRECALC_RUN、S_PRECALC_WAIT、S_PRECALC_STORE、S_LOAD0、S_LOAD1、S_LOAD2、S_CLAMP、S_INDEX、S_REQ、S_WAIT、S_MIX0_MUL、S_MIX0_SUM、S_MIX1、S_OUT。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/core/rotate_core_bilinear.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``bot_mix_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] bot_mix_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_WAIT: begin；if (sample_rsp_valid) begin；S_MIX0_MUL: begin；S_MIX0_SUM: begin；赋值为 bot_mix_calc |
| ``bot_mul0_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] bot_mul0_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；S_MIX0_MUL: begin；赋值为 bot_mul0_calc |
| ``bot_mul1_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] bot_mul1_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；S_MIX0_MUL: begin；赋值为 bot_mul1_calc |
| ``cfg_dst_h_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] cfg_dst_h_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_h | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 dst_h |
| ``cfg_dst_w_reg`` | ``logic [DST_X_W-1:0]``；声明：``logic [DST_X_W-1:0] cfg_dst_w_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，dst_w | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 dst_w |
| ``cfg_src_x_last_reg`` | ``logic [SRC_X_W-1:0]``；声明：``logic [SRC_X_W-1:0] cfg_src_x_last_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，geom_src_x_last | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_src_x_last |
| ``cfg_src_x_max_q16_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] cfg_src_x_max_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，geom_src_x_max_q16 | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_src_x_max_q16 |
| ``cfg_src_y_last_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] cfg_src_y_last_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，geom_src_y_last | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_src_y_last |
| ``cfg_src_y_max_q16_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] cfg_src_y_max_q16_reg;`` | FIFO/队列或流水级寄存器。 | 复位/清零候选：'0，geom_src_y_max_q16 | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_src_y_max_q16 |
| ``clamp_x_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] clamp_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD0: begin；S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；赋值为 clamped_x_q16_calc |
| ``clamp_y_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] clamp_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD0: begin；S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；赋值为 clamped_y_q16_calc |
| ``cur_x_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] cur_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，row_base_rd_data[COORD_W-1:0]，next_x_calc | if (rst) begin；赋值为 '0<br>if (rst) begin；if (state_reg == S_LOAD2) begin；赋值为 row_base_rd_data[COORD_W-1:0]<br>if (rst) begin；if (state_reg == S_LOAD2) begin；赋值为 next_x_calc |
| ``cur_y_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] cur_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，row_base_rd_data[2*COORD_W-1:COORD_W]，next_y_calc | if (rst) begin；赋值为 '0<br>if (rst) begin；if (state_reg == S_LOAD2) begin；赋值为 row_base_rd_data[2*COORD_W-1:COORD_W]<br>if (rst) begin；if (state_reg == S_LOAD2) begin；赋值为 next_y_calc |
| ``done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 1'b1 |
| ``dst_x_reg`` | ``logic [DST_X_W-1:0]``；声明：``logic [DST_X_W-1:0] dst_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 '0<br>if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 '0<br>if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 dst_x_reg + 1'b1 |
| ``dst_y_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] dst_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 '0<br>if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin；赋值为 dst_y_reg + 1'b1 |
| ``error`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 1'b1 |
| ``frac_x_reg`` | ``logic [FRAC_W-1:0]``；声明：``logic [FRAC_W-1:0] frac_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD0: begin；S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；赋值为 clamped_x_q16_calc[FRAC_W-1:0] |
| ``frac_y_reg`` | ``logic [FRAC_W-1:0]``；声明：``logic [FRAC_W-1:0] frac_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD0: begin；S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；赋值为 clamped_y_q16_calc[FRAC_W-1:0] |
| ``mix_frac_x_reg`` | ``logic [FRAC_W-1:0]``；声明：``logic [FRAC_W-1:0] mix_frac_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 frac_x_reg |
| ``mix_frac_y_reg`` | ``logic [FRAC_W-1:0]``；声明：``logic [FRAC_W-1:0] mix_frac_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 frac_y_reg |
| ``mix_p00_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] mix_p00_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p00 |
| ``mix_p01_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] mix_p01_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p01 |
| ``mix_p10_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] mix_p10_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p10 |
| ``mix_p11_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] mix_p11_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p11 |
| ``out_mix_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] out_mix_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (sample_rsp_valid) begin；S_MIX0_MUL: begin；S_MIX0_SUM: begin；S_MIX1: begin；赋值为 out_mix_calc |
| ``pix_data_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] pix_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_MIX0_SUM: begin；S_MIX1: begin；S_OUT: begin；if (!pix_valid_reg) begin；赋值为 out_mix_reg[PIXEL_W-1:0] |
| ``pix_valid_reg`` | ``logic 1 bit/enum``；声明：``logic pix_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>S_MIX0_SUM: begin；S_MIX1: begin；S_OUT: begin；if (!pix_valid_reg) begin；赋值为 1'b1<br>S_MIX1: begin；S_OUT: begin；if (!pix_valid_reg) begin；if (pix_fire) begin；赋值为 1'b0 |
| ``precalc_base_x_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] precalc_base_x_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，row0_x_base_reg | if (rst) begin；赋值为 '0<br>if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；S_PRECALC_INIT: begin；赋值为 row0_x_base_reg<br>S_PRECALC_RUN: begin；S_PRECALC_WAIT: begin；if (row_adv_done_reg) begin；S_PRECALC_STORE: begin；赋值为 row_x_next_reg |
| ``precalc_base_y_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] precalc_base_y_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，row0_y_base_reg | if (rst) begin；赋值为 '0<br>if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；S_PRECALC_INIT: begin；赋值为 row0_y_base_reg<br>S_PRECALC_RUN: begin；S_PRECALC_WAIT: begin；if (row_adv_done_reg) begin；S_PRECALC_STORE: begin；赋值为 row_y_next_reg |
| ``precalc_idx_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] precalc_idx_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；S_PRECALC_INIT: begin；赋值为 '0<br>S_PRECALC_WAIT: begin；if (row_adv_done_reg) begin；S_PRECALC_STORE: begin；if ((precalc_idx_reg + 1'b1) >= (cfg_dst_h_reg - 1'b1)) begin；赋值为 precalc_idx_reg + 1'b1 |
| ``row_base_rd_addr_reg`` | ``logic [DST_Y_W-1:0]``；声明：``logic [DST_Y_W-1:0] row_base_rd_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，dst_y_reg | if (rst) begin；赋值为 '0<br>if (rst) begin；if (state_reg == S_LOAD0) begin；赋值为 dst_y_reg |
| ``row_base_rd_en_reg`` | ``logic 1 bit/enum``；声明：``logic row_base_rd_en_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：1'b0，(state_reg == S_LOAD0) | if (rst) begin；赋值为 1'b0<br>if (rst) begin；赋值为 (state_reg == S_LOAD0) |
| ``row_done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0 | if (rst) begin；赋值为 1'b0<br>S_OUT: begin；if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；赋值为 1'b1 |
| ``row_x_next_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] row_x_next_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (cfg_dst_h_reg == 1) begin；S_PRECALC_RUN: begin；S_PRECALC_WAIT: begin；if (row_adv_done_reg) begin；赋值为 row_adv_next_x |
| ``row_y_next_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] row_y_next_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (cfg_dst_h_reg == 1) begin；S_PRECALC_RUN: begin；S_PRECALC_WAIT: begin；if (row_adv_done_reg) begin；赋值为 row_adv_next_y |
| ``row0_x_base_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] row0_x_base_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，geom_row0_x | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_row0_x |
| ``row0_y_base_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] row0_y_base_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，geom_row0_y | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_row0_y |
| ``sample_p00_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p00_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p00 |
| ``sample_p01_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p01_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p01 |
| ``sample_p10_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p10_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p10 |
| ``sample_p11_reg`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p11_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_REQ: begin；if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；赋值为 sample_p11 |
| ``sample_x0_reg`` | ``logic [SRC_X_W-1:0]``；声明：``logic [SRC_X_W-1:0] sample_x0_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；S_INDEX: begin；赋值为 sample_x0_calc |
| ``sample_x1_reg`` | ``logic [SRC_X_W-1:0]``；声明：``logic [SRC_X_W-1:0] sample_x1_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；S_INDEX: begin；赋值为 sample_x1_calc |
| ``sample_y0_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] sample_y0_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；S_INDEX: begin；赋值为 sample_y0_calc |
| ``sample_y1_reg`` | ``logic [SRC_Y_W-1:0]``；声明：``logic [SRC_Y_W-1:0] sample_y1_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_LOAD1: begin；S_LOAD2: begin；S_CLAMP: begin；S_INDEX: begin；赋值为 sample_y1_calc |
| ``state_reg`` | ``state_t 1 bit/enum``；声明：``state_t state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``state_t``：``S_IDLE``=0，``S_GEOM_WAIT``=1，``S_PRECALC_INIT``=2，``S_PRECALC_RUN``=3，``S_PRECALC_WAIT``=4，``S_PRECALC_STORE``=5，``S_LOAD0``=6，``S_LOAD1``=7，``S_LOAD2``=8，``S_CLAMP``=9，``S_INDEX``=10，``S_REQ``=11，``S_WAIT``=12，``S_MIX0_MUL``=13，``S_MIX0_SUM``=14，``S_MIX1``=15，``S_OUT``=16 | if (rst) begin；赋值为 S_IDLE<br>if (rst) begin；case (state_reg)；S_IDLE: begin；if (start) begin；赋值为 S_GEOM_WAIT<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 S_IDLE<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 S_PRECALC_INIT<br>S_GEOM_WAIT: begin；if (geom_error) begin；S_PRECALC_INIT: begin；if (cfg_dst_h_reg == 1) begin；赋值为 S_LOAD0<br>S_GEOM_WAIT: begin；if (geom_error) begin；S_PRECALC_INIT: begin；if (cfg_dst_h_reg == 1) begin；赋值为 S_PRECALC_RUN |
| ``step_x_x_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] step_x_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，geom_step_x_x | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_step_x_x |
| ``step_x_y_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] step_x_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，geom_step_x_y | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_step_x_y |
| ``step_y_x_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] step_y_x_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，geom_step_y_x | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_step_y_x |
| ``step_y_y_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] step_y_y_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，geom_step_y_y | if (rst) begin；赋值为 '0<br>S_IDLE: begin；if (start) begin；S_GEOM_WAIT: begin；if (geom_error) begin；赋值为 geom_step_y_y |
| ``top_mix_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] top_mix_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>S_WAIT: begin；if (sample_rsp_valid) begin；S_MIX0_MUL: begin；S_MIX0_SUM: begin；赋值为 top_mix_calc |
| ``top_mul0_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] top_mul0_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；S_MIX0_MUL: begin；赋值为 top_mul0_calc |
| ``top_mul1_reg`` | ``logic [MIX_W-1:0]``；声明：``logic [MIX_W-1:0] top_mul1_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (rst) begin；赋值为 '0<br>if (sample_req_valid && sample_req_ready) begin；S_WAIT: begin；if (sample_rsp_valid) begin；S_MIX0_MUL: begin；赋值为 top_mul1_calc |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``state_t``，编码位宽：``[5:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``S_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 到 ``S_GEOM_WAIT``：S_IDLE: begin；if (start) begin |
| ``S_GEOM_WAIT`` | 1 | 初始化、预计算或准备阶段。 | 到 ``S_IDLE``：S_GEOM_WAIT: begin；if (geom_error) begin<br>到 ``S_PRECALC_INIT``：S_GEOM_WAIT: begin；if (geom_error) begin |
| ``S_PRECALC_INIT`` | 2 | 初始化、预计算或准备阶段。 | 到 ``S_LOAD0``：S_PRECALC_INIT: begin；if (cfg_dst_h_reg == 1) begin<br>到 ``S_PRECALC_RUN``：S_PRECALC_INIT: begin；if (cfg_dst_h_reg == 1) begin |
| ``S_PRECALC_RUN`` | 3 | 初始化、预计算或准备阶段。 | 到 ``S_PRECALC_WAIT``：S_PRECALC_RUN: begin |
| ``S_PRECALC_WAIT`` | 4 | 初始化、预计算或准备阶段。 | 到 ``S_PRECALC_STORE``：S_PRECALC_WAIT: begin；if (row_adv_done_reg) begin |
| ``S_PRECALC_STORE`` | 5 | 初始化、预计算或准备阶段。 | 到 ``S_LOAD0``：S_PRECALC_STORE: begin；if ((precalc_idx_reg + 1'b1) >= (cfg_dst_h_reg - 1'b1)) begin<br>到 ``S_PRECALC_RUN``：S_PRECALC_STORE: begin；if ((precalc_idx_reg + 1'b1) >= (cfg_dst_h_reg - 1'b1)) begin |
| ``S_LOAD0`` | 6 | 装载/捕获输入数据或填充缓存。 | 到 ``S_LOAD1``：S_LOAD0: begin |
| ``S_LOAD1`` | 7 | 装载/捕获输入数据或填充缓存。 | 到 ``S_LOAD2``：S_LOAD1: begin |
| ``S_LOAD2`` | 8 | 装载/捕获输入数据或填充缓存。 | 到 ``S_CLAMP``：S_LOAD2: begin |
| ``S_CLAMP`` | 9 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``S_INDEX``：S_CLAMP: begin |
| ``S_INDEX`` | 10 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``S_REQ``：S_INDEX: begin |
| ``S_REQ`` | 11 | 发起请求或地址通道阶段。 | 到 ``S_WAIT``：S_REQ: begin；if (sample_req_valid && sample_req_ready) begin |
| ``S_WAIT`` | 12 | 等待下游响应或返回数据。 | 到 ``S_MIX0_MUL``：S_WAIT: begin；if (sample_rsp_valid) begin |
| ``S_MIX0_MUL`` | 13 | 插值乘加或混合计算阶段。 | 到 ``S_MIX0_SUM``：S_MIX0_MUL: begin |
| ``S_MIX0_SUM`` | 14 | 插值乘加或混合计算阶段。 | 到 ``S_MIX1``：S_MIX0_SUM: begin |
| ``S_MIX1`` | 15 | 插值乘加或混合计算阶段。 | 到 ``S_OUT``：S_MIX1: begin |
| ``S_OUT`` | 16 | 输出、排空或完成阶段。 | 到 ``S_IDLE``：if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin<br>到 ``S_LOAD0``：if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin<br>到 ``S_CLAMP``：if (!pix_valid_reg) begin；if (pix_fire) begin；if (last_col) begin；if (last_row) begin |

<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为 ``scaler_ctrl`` 的 start/config。
- 下游 sample 为 ``src_tile_cache``，像素输出为 ``row_out_buffer``。

## 9. 握手协议说明
- sample ready 决定是否能离开请求阶段，cache miss 会反压本核心。
- 输出 valid 保持到 ``pix_ready``，避免写回路径反压时丢像素。
- ``scan_dir_valid`` 在 busy 且 X 步进非零时提示 cache 预取方向。

## 10. 错误处理与边界条件
- ``geom_error`` 会中断处理并置 error。
- 源坐标边界通过 clamp/index 阶段处理；具体边界策略需与源码表达式和 MATLAB 参考对齐。

## 11. 综合/时序/CDC注意事项
- 乘加拆成 ``S_MIX0_MUL``、``S_MIX0_SUM``、``S_MIX1`` 多拍以降低 timing。
- 行基预计算避免每像素重复宽位几何计算。
- 无 CDC，必须与 cache/row buffer 同域。

## 12. 维护建议
- 修改 Q 格式时同步 ``rotate_geom_init_unit``、``row_advance_unit``、cache 坐标和 MATLAB 模型。
- 增加算法模式时明确 sample 个数和握手变化。

## 13. 待确认问题
- 待确认：边界像素策略的最终论文表述。
