# tb_scale_core_nearest

> 依据文件：``rtl/sim/tb_scale_core_nearest.sv``。testbench/wrapper 不按可综合 RTL 同等深挖，仅记录验证目标、DUT、场景和日志追溯。

## 1. 模块定位
- testbench/wrapper，验证目标推断为 ``scale_core_nearest``。
- 场景类型：基础功能。

## 2. 文件路径
- ``rtl/sim/tb_scale_core_nearest.sv``

## 3. 主要功能
- 产生仿真时钟/复位、配置 DUT、驱动输入事务并检查输出或性能指标。
- 具体 pass/fail 条件以本文件中的 ``$fatal``、``$error``、``$display`` 和 sim_out 日志为准。

## 4. 参数说明
- testbench 参数用于覆盖不同图像尺寸、角度、cache 开关或压力配置；不是综合接口参数。

## 5. 端口说明
- testbench 顶层通常无综合端口，内部信号按 DUT 接口连接。

## 6. 时钟与复位
- 仿真内部生成时钟和复位；多时钟 DUT 会分别驱动 AXI/control/core 时钟。

## 7. 内部结构
- 包括 DUT 实例、激励任务、参考模型/计分板、timeout 或性能统计打印。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/sim/tb_scale_core_nearest.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``cycle_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，cycle_count + 1 | if (rst) begin；赋值为 0<br>if (rst) begin；赋值为 cycle_count + 1 |
| ``line_req_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：line_req_count + 1 | if (rst) begin；if (line_req_valid && line_req_ready) begin；赋值为 line_req_count + 1 |
| ``out_x`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：0，out_x + 1 | if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；if (pix_valid && pix_ready) begin；if (out_x == (case_dst_w - 1)) begin；赋值为 0<br>if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；if (pix_valid && pix_ready) begin；if (out_x == (case_dst_w - 1)) begin；赋值为 out_x + 1 |
| ``out_y`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：out_y + 1 | if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；if (pix_valid && pix_ready) begin；if (out_x == (case_dst_w - 1)) begin；赋值为 out_y + 1 |
| ``pending_line_sel`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：expected_src_y[LINE_SEL_W-1:0] | if (line_req_valid && line_req_ready) begin；if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；赋值为 expected_src_y[LINE_SEL_W-1:0] |
| ``pending_pixel_rsp`` | ``bit 1 bit/enum``；声明：``bit pending_pixel_rsp;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (line_req_valid && line_req_ready) begin；if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；赋值为 1'b1<br>if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；赋值为 1'b0 |
| ``pending_src_x`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：expected_src_x | if (line_req_valid && line_req_ready) begin；if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；赋值为 expected_src_x |
| ``pending_src_y`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：expected_src_y | if (line_req_valid && line_req_ready) begin；if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；赋值为 expected_src_y |
| ``pixel_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：pixel_count + 1 | if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；if (pix_valid && pix_ready) begin；赋值为 pixel_count + 1 |
| ``pixel_rsp_data`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] pixel_rsp_data;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，src_img[pending_src_y][pending_src_x] | if (rst) begin；赋值为 '0<br>if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；赋值为 src_img[pending_src_y][pending_src_x] |
| ``pixel_rsp_valid`` | ``logic 1 bit/enum``；声明：``logic pixel_rsp_valid;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (pixel_req_valid) begin；if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin；if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin；if (pending_pixel_rsp) begin；赋值为 1'b1 |
| ``row_done_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 普通寄存器 | if (pending_pixel_rsp) begin；if (pix_valid && pix_ready) begin；if (out_x == (case_dst_w - 1)) begin；if (row_done) begin；赋值为 row_done_count + 1 |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为仿真激励，下游为 DUT 输出检查和日志。

## 9. 握手协议说明
- 通过仿真驱动 AXI、valid/ready、start/done 等握手；协议违反通常以 ``$fatal``/timeout 暴露。

## 10. 错误处理与边界条件
- timeout、数据不一致、AXI 响应错误或性能未达预期均应在日志中追溯。

## 11. 综合/时序/CDC注意事项
- testbench 不综合；但用于暴露 CDC、FIFO、cache 和 AXI 时序协议风险。

## 12. 维护建议
- 新增 DUT 端口或寄存器时同步更新 testbench 连接和期望输出。
- 性能 wrapper 的结果统一汇总到 ``docs/verification_status.md``，不要在单页写成未追溯结论。

## 13. 待确认问题
- 待确认：该 testbench 最新一次有效日志路径和 pass/fail 状态。
