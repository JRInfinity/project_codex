# tb_ddr_write_engine

> 依据文件：``rtl/sim/tb_ddr_write_engine.sv``。testbench/wrapper 不按可综合 RTL 同等深挖，仅记录验证目标、DUT、场景和日志追溯。

## 1. 模块定位
- testbench/wrapper，验证目标推断为 ``ddr_write_engine``。
- 场景类型：基础功能。

## 2. 文件路径
- ``rtl/sim/tb_ddr_write_engine.sv``

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

> 本小节由 ``rtl/sim/tb_ddr_write_engine.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``active_awaddr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] active_awaddr_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：'0，m_axi_wr.awaddr | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awburst != 2'b01) $fatal(1, "AWBURST must be INCR.");；if (m_axi_wr.awsize != AXI_SIZE) $fatal(1, "AWSIZE mismatch.");；if ((m_axi_wr.awlen + 1) > BURST_MAX_LEN) $fatal(1, "AWLEN exceeds BURST_MAX_LEN.");；if (((m_axi_wr.awaddr[11:0]) + ((m_axi_wr.awlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 m_axi_wr.awaddr |
| ``active_awbeats_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务忙/活动窗口标志。 | 复位/清零候选：0，m_axi_wr.awlen + 1 | if (sys_rst) begin；赋值为 0<br>if (m_axi_wr.awburst != 2'b01) $fatal(1, "AWBURST must be INCR.");；if (m_axi_wr.awsize != AXI_SIZE) $fatal(1, "AWSIZE mismatch.");；if ((m_axi_wr.awlen + 1) > BURST_MAX_LEN) $fatal(1, "AWLEN exceeds BURST_MAX_LEN.");；if (((m_axi_wr.awaddr[11:0]) + ((m_axi_wr.awlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 m_axi_wr.awlen + 1 |
| ``active_wbeat_idx_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务忙/活动窗口标志。 | 复位/清零候选：0，active_wbeat_idx_reg + 1 | if (sys_rst) begin；赋值为 0<br>if (m_axi_wr.awburst != 2'b01) $fatal(1, "AWBURST must be INCR.");；if (m_axi_wr.awsize != AXI_SIZE) $fatal(1, "AWSIZE mismatch.");；if ((m_axi_wr.awlen + 1) > BURST_MAX_LEN) $fatal(1, "AWLEN exceeds BURST_MAX_LEN.");；if (((m_axi_wr.awaddr[11:0]) + ((m_axi_wr.awlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 0<br>if (!active_write_reg) $fatal(1, "W channel fired before AW.");；if (m_axi_wr.wstrb[byte_idx]) begin；if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin；if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin；赋值为 active_wbeat_idx_reg + 1 |
| ``active_write_reg`` | ``bit 1 bit/enum``；声明：``bit active_write_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (m_axi_wr.awburst != 2'b01) $fatal(1, "AWBURST must be INCR.");；if (m_axi_wr.awsize != AXI_SIZE) $fatal(1, "AWSIZE mismatch.");；if ((m_axi_wr.awlen + 1) > BURST_MAX_LEN) $fatal(1, "AWLEN exceeds BURST_MAX_LEN.");；if (((m_axi_wr.awaddr[11:0]) + ((m_axi_wr.awlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 1'b1<br>if (!active_write_reg) $fatal(1, "W channel fired before AW.");；if (m_axi_wr.wstrb[byte_idx]) begin；if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin；if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin；赋值为 1'b0 |
| ``awready`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；赋值为 1'b1 |
| ``bid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0 |
| ``bresp`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：2'b00，inject_bresp_error ? 2'b10 : 2'b00 | if (sys_rst) begin；赋值为 2'b00<br>if (!active_write_reg) $fatal(1, "W channel fired before AW.");；if (m_axi_wr.wstrb[byte_idx]) begin；if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin；if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin；赋值为 inject_bresp_error ? 2'b10 : 2'b00<br>if (m_axi_wr.wstrb[byte_idx]) begin；if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin；if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin；if (m_axi_wr.bvalid && m_axi_wr.bready) begin；赋值为 2'b00 |
| ``buser`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0 |
| ``bvalid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (!active_write_reg) $fatal(1, "W channel fired before AW.");；if (m_axi_wr.wstrb[byte_idx]) begin；if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin；if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin；赋值为 1'b1<br>if (m_axi_wr.wstrb[byte_idx]) begin；if (m_axi_wr.wlast != (active_wbeat_idx_reg == (active_awbeats_reg - 1))) begin；if (active_wbeat_idx_reg == (active_awbeats_reg - 1)) begin；if (m_axi_wr.bvalid && m_axi_wr.bready) begin；赋值为 1'b0 |
| ``cycle_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：cycle_count + 1 | if (sys_rst) begin；赋值为 cycle_count + 1 |
| ``input_idx_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：input_idx_reg + 1 | if (sys_rst) begin；if (in_valid && in_ready) begin；赋值为 input_idx_reg + 1 |
| ``wready`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；赋值为 1'b1 |
| ``written`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：m_axi_wr.wdata[byte_idx*8 +: 8] | if (((m_axi_wr.awaddr[11:0]) + ((m_axi_wr.awlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (m_axi_wr.wvalid && m_axi_wr.wready) begin；if (!active_write_reg) $fatal(1, "W channel fired before AW.");；if (m_axi_wr.wstrb[byte_idx]) begin；赋值为 m_axi_wr.wdata[byte_idx*8 +: 8] |

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
