# tb_ddr_read_engine

> 依据文件：``rtl/sim/tb_ddr_read_engine.sv``。testbench/wrapper 不按可综合 RTL 同等深挖，仅记录验证目标、DUT、场景和日志追溯。

## 1. 模块定位
- testbench/wrapper，验证目标推断为 ``ddr_read_engine``。
- 场景类型：基础功能。

## 2. 文件路径
- ``rtl/sim/tb_ddr_read_engine.sv``

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

> 本小节由 ``rtl/sim/tb_ddr_read_engine.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``active_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] active_addr_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：'0，ar_addr_queue[ar_head_reg] | if (sys_rst) begin；赋值为 '0<br>if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；赋值为 ar_addr_queue[ar_head_reg]<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 ar_addr_queue[ar_head_reg] |
| ``active_beat_idx_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务忙/活动窗口标志。 | 复位/清零候选：0，active_beat_idx_reg + 1 | if (sys_rst) begin；赋值为 0<br>if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；赋值为 0<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 active_beat_idx_reg + 1<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 0 |
| ``active_beats_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务忙/活动窗口标志。 | 复位/清零候选：0，ar_beats_queue[ar_head_reg] | if (sys_rst) begin；赋值为 0<br>if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；赋值为 ar_beats_queue[ar_head_reg]<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 ar_beats_queue[ar_head_reg] |
| ``active_cmd_valid_reg`` | ``bit 1 bit/enum``；声明：``bit active_cmd_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；赋值为 1'b1<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 1'b1<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 1'b0 |
| ``ar_addr_queue`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] ar_addr_queue [0:63];`` | 地址或地址规划寄存器。 | 复位/清零候选：m_axi_rd.araddr | if (m_axi_rd.arburst != 2'b01) $fatal(1, "ARBURST must be INCR.");；if (m_axi_rd.arsize != AXI_SIZE) $fatal(1, "ARSIZE mismatch.");；if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 m_axi_rd.araddr |
| ``ar_beats_queue`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：m_axi_rd.arlen + 1 | if (m_axi_rd.arburst != 2'b01) $fatal(1, "ARBURST must be INCR.");；if (m_axi_rd.arsize != AXI_SIZE) $fatal(1, "ARSIZE mismatch.");；if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 m_axi_rd.arlen + 1 |
| ``ar_count_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，ar_count_reg + 1，ar_count_reg - 1 | if (sys_rst) begin；赋值为 0<br>if (m_axi_rd.arburst != 2'b01) $fatal(1, "ARBURST must be INCR.");；if (m_axi_rd.arsize != AXI_SIZE) $fatal(1, "ARSIZE mismatch.");；if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 ar_count_reg + 1<br>if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；赋值为 ar_count_reg - 1<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 ar_count_reg - 1 |
| ``ar_head_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列指针寄存器。 | 复位/清零候选：0，(ar_head_reg + 1) % 64 | if (sys_rst) begin；赋值为 0<br>if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；赋值为 (ar_head_reg + 1) % 64<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 (ar_head_reg + 1) % 64 |
| ``ar_tail_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列指针寄存器。 | 复位/清零候选：0，(ar_tail_reg + 1) % 64 | if (sys_rst) begin；赋值为 0<br>if (m_axi_rd.arburst != 2'b01) $fatal(1, "ARBURST must be INCR.");；if (m_axi_rd.arsize != AXI_SIZE) $fatal(1, "ARSIZE mismatch.");；if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；赋值为 (ar_tail_reg + 1) % 64 |
| ``arready`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；赋值为 1'b1 |
| ``core_cycle_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，core_cycle_count + 1 | if (sys_rst) begin；赋值为 0<br>if (sys_rst) begin；赋值为 core_cycle_count + 1 |
| ``global_rbeat_idx_reg`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，global_rbeat_idx_reg + 1 | if (sys_rst) begin；赋值为 0<br>if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；赋值为 global_rbeat_idx_reg + 1 |
| ``observed`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：out_data | if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 out_data |
| ``observed_count`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 计数、索引或剩余量寄存器。 | 复位/清零候选：0，observed_count + 1 | if (sys_rst) begin；赋值为 0<br>if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 observed_count + 1 |
| ``out_ready`` | ``logic 1 bit/enum``；声明：``logic out_ready;`` | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：1'b0，1'b1，((core_cycle_count % 5) != 2) | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (!enable_backpressure) begin；赋值为 1'b1<br>if (sys_rst) begin；if (!enable_backpressure) begin；赋值为 ((core_cycle_count % 5) != 2) |
| ``rdata`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0 |
| ``rid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0 |
| ``rlast`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 1'b0 |
| ``rresp`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：2'b00 | if (sys_rst) begin；赋值为 2'b00<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 2'b00 |
| ``ruser`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0 |
| ``rvalid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；if ((active_beat_idx_reg + 1) < active_beats_reg) begin；赋值为 1'b0 |
| ``saw_axi_accept_while_out_stalled`` | ``bit 1 bit/enum``；声明：``bit saw_axi_accept_while_out_stalled;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；if (!out_ready) begin；赋值为 1'b1 |
| ``saw_first_rlast`` | ``bit 1 bit/enum``；声明：``bit saw_first_rlast;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；if (!m_axi_rd.rvalid && !active_cmd_valid_reg && (ar_count_reg != 0)) begin；if (m_axi_rd.rlast) begin；赋值为 1'b1 |
| ``saw_second_ar_before_first_rlast`` | ``bit 1 bit/enum``；声明：``bit saw_second_ar_before_first_rlast;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (m_axi_rd.arsize != AXI_SIZE) $fatal(1, "ARSIZE mismatch.");；if ((m_axi_rd.arlen + 1) > BURST_MAX_LEN) $fatal(1, "ARLEN exceeds BURST_MAX_LEN.");；if (((m_axi_rd.araddr[11:0]) + ((m_axi_rd.arlen + 1) * BYTE_W)) > 4096) $fatal(1, "Burst crosses 4KB boundary.");；if (!saw_first_rlast && ((ar_count_reg != 0) \|\| active_cmd_valid_reg)) begin；赋值为 1'b1 |
| ``task_addr`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] task_addr;`` | 地址或地址规划寄存器。 | 复位/清零候选：addr | if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 addr |
| ``task_byte_count`` | ``logic [31:0]``；声明：``logic [31:0] task_byte_count;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：byte_count | if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 byte_count |
| ``task_row_count`` | ``logic [15:0]``；声明：``logic [15:0] task_row_count;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：16'd1 | if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 16'd1 |
| ``task_row_stride`` | ``logic [31:0]``；声明：``logic [31:0] task_row_stride;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：byte_count | if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 byte_count |
| ``task_start`` | ``logic 1 bit/enum``；声明：``logic task_start;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b1，1'b0 | if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 1'b1<br>if (sys_rst) begin；if (!enable_backpressure) begin；if (out_valid && out_ready) begin；赋值为 1'b0 |

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
