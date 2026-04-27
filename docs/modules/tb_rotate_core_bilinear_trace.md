# tb_rotate_core_bilinear_trace

> 依据文件：``rtl/sim/tb_rotate_core_bilinear_trace.sv``。testbench/wrapper 不按可综合 RTL 同等深挖，仅记录验证目标、DUT、场景和日志追溯。

## 1. 模块定位
- testbench/wrapper，验证目标推断为 ``rotate_core_bilinear_trace``。
- 场景类型：波形/轨迹调试场景。

## 2. 文件路径
- ``rtl/sim/tb_rotate_core_bilinear_trace.sv``

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

> 本小节由 ``rtl/sim/tb_rotate_core_bilinear_trace.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``pix_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，pix_count + 1 | if (rst) begin；赋值为 0<br>if (rst) begin；if (sample_req_valid && sample_req_ready) begin；if (pix_valid && pix_ready) begin；赋值为 pix_count + 1 |
| ``req_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，req_count + 1 | if (rst) begin；赋值为 0<br>if (rst) begin；if ((sample_x0 !== exp_x0) \|\| (sample_y0 !== exp_y0) \|\|；赋值为 req_count + 1 |
| ``sample_p00`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p00;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，8'd10 | if (rst) begin；赋值为 '0<br>if (rst) begin；if (sample_req_valid && sample_req_ready) begin；赋值为 8'd10 |
| ``sample_p01`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p01;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，8'd20 | if (rst) begin；赋值为 '0<br>if (rst) begin；if (sample_req_valid && sample_req_ready) begin；赋值为 8'd20 |
| ``sample_p10`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p10;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，8'd30 | if (rst) begin；赋值为 '0<br>if (rst) begin；if (sample_req_valid && sample_req_ready) begin；赋值为 8'd30 |
| ``sample_p11`` | ``logic [PIXEL_W-1:0]``；声明：``logic [PIXEL_W-1:0] sample_p11;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，8'd40 | if (rst) begin；赋值为 '0<br>if (rst) begin；if (sample_req_valid && sample_req_ready) begin；赋值为 8'd40 |
| ``sample_rsp_valid`` | ``logic 1 bit/enum``；声明：``logic sample_rsp_valid;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，sample_req_valid && sample_req_ready | if (rst) begin；赋值为 1'b0<br>if (rst) begin；赋值为 sample_req_valid && sample_req_ready |

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
