# axi_burst_writer

> 依据文件：``rtl/axi/axi_burst_writer.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- 位于 ``ddr_write_engine`` 的 AXI 侧，上游接收 packed word/strobe，下游写 DDR。
- 设计重点是保证写 burst 不跨 4KB，最后 partial word 的 ``WSTRB`` 正确。

## 2. 文件路径
- ``rtl/axi/axi_burst_writer.sv``

## 3. 主要功能
- 按 ``BURST_MAX_LEN`` 和 4KB 边界拆分写任务。
- 驱动 ``AW``、``W`` 并等待 ``B`` 响应。
- 将 ``BRESP`` 汇总为 ``result_error``。

## 4. 参数说明
- ``DATA_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``ADDR_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``BURST_MAX_LEN``：默认 ``256``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``AXI_ID_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`sys_rst`（input）。
- 握手/状态：`task_valid`（input）。
- 握手/状态：`task_ready`（output）。
- 数据/控制：`task_addr`（input）。
- 数据/控制：`task_byte_count`（input）。
- 数据/控制：`word_data`（input）。
- 数据/控制：`word_strb`（input）。
- 握手/状态：`word_valid`（input）。
- 握手/状态：`word_ready`（output）。
- 握手/状态：`task_busy`（output）。
- 握手/状态：`result_valid`（output）。
- 握手/状态：`result_ready`（input）。
- 握手/状态：`result_done`（output）。
- 状态/错误/统计：`result_error`（output）。
- 数据/控制：`words`（input）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 状态机包括 ``S_IDLE``、``S_AW``、``S_WDATA``、``S_BRESP``、``S_DONE``、``S_ERROR``。
- ``word_buf_valid_reg`` 在 W 通道反压时保存 word。
- ``calc_last_wstrb`` 等函数用于末尾 strobe 规划。
- 状态机 ``state_t``：S_IDLE、S_PREP_LIMIT、S_PREP、S_AWCFG、S_AW、S_WDATA、S_BRESP、S_DONE。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/axi/axi_burst_writer.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``aligned_start_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] aligned_start_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，align_addr(task_addr, AXI_SIZE_W) | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 align_addr(task_addr, AXI_SIZE_W) |
| ``aw_prep_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] aw_prep_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；赋值为 current_burst_addr_calc |
| ``aw_prep_len_reg`` | ``logic [7:0]``；声明：``logic [7:0] aw_prep_len_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；赋值为 burst_words_calc - 1'b1 |
| ``aw_stall_assert_reg`` | ``logic 1 bit/enum``；声明：``logic aw_stall_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (m_axi_wr.awvalid) begin；if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；赋值为 1'b1<br>if (m_axi_wr.awvalid) begin；if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；赋值为 1'b0 |
| ``awaddr`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 地址或地址规划寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 aw_prep_addr_reg |
| ``awaddr_hold_assert_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] awaddr_hold_assert_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，m_axi_wr.awaddr | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awvalid) begin；if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；赋值为 m_axi_wr.awaddr |
| ``awburst`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：2'b01 | if (sys_rst) begin；赋值为 2'b01<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 2'b01 |
| ``awburst_hold_assert_reg`` | ``logic [1:0]``；声明：``logic [1:0] awburst_hold_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，m_axi_wr.awburst | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awvalid) begin；if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；赋值为 m_axi_wr.awburst |
| ``awcache`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：4'b0011 | if (sys_rst) begin；赋值为 4'b0011<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 4'b0011 |
| ``awid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 '0 |
| ``awlen`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 aw_prep_len_reg |
| ``awlen_hold_assert_reg`` | ``logic [7:0]``；声明：``logic [7:0] awlen_hold_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，m_axi_wr.awlen | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awvalid) begin；if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；赋值为 m_axi_wr.awlen |
| ``awlock`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 1'b0 |
| ``awprot`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：3'b000 | if (sys_rst) begin；赋值为 3'b000<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 3'b000 |
| ``awqos`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | FIFO/队列或流水级寄存器。 | 复位/清零候选：4'd0 | if (sys_rst) begin；赋值为 4'd0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 4'd0 |
| ``awregion`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：4'd0 | if (sys_rst) begin；赋值为 4'd0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 4'd0 |
| ``awsize`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：AXI_SIZE | if (sys_rst) begin；赋值为 AXI_SIZE<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 AXI_SIZE |
| ``awsize_hold_assert_reg`` | ``logic [2:0]``；声明：``logic [2:0] awsize_hold_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，m_axi_wr.awsize | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awvalid) begin；if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；赋值为 m_axi_wr.awsize |
| ``awuser`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 '0 |
| ``awvalid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (result_pending_reg && result_ready) begin；if (state_reg == S_DONE) begin；if (word_ready && word_valid) begin；if (aw_fire) begin；赋值为 1'b0<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 1'b1<br>if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；赋值为 1'b0 |
| ``bready`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | ready/可接收状态的寄存或辅助判断。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (word_ready && word_valid) begin；if (aw_fire) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；if (next_write_words_to_4kb_reg == 1) begin；if (burst_last_word) begin；赋值为 1'b1<br>if (next_write_words_to_4kb_reg == 1) begin；if (burst_last_word) begin；S_BRESP: begin；if (b_fire) begin；赋值为 1'b0<br>if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；赋值为 1'b0 |
| ``burst_sent_words_reg`` | ``logic [BURST_COUNT_W-1:0]``；声明：``logic [BURST_COUNT_W-1:0] burst_sent_words_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 '0<br>S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；赋值为 '0<br>if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；赋值为 burst_sent_words_reg + 1'b1 |
| ``burst_words_reg`` | ``logic [BURST_COUNT_W-1:0]``；声明：``logic [BURST_COUNT_W-1:0] burst_words_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；赋值为 burst_words_calc |
| ``error_latched_reg`` | ``logic 1 bit/enum``；声明：``logic error_latched_reg;`` | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (word_ready && word_valid) begin；if (aw_fire) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>if (burst_last_word) begin；S_BRESP: begin；if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；赋值为 1'b1 |
| ``next_write_addr_reg`` | ``logic [ADDR_W-1:0]``；声明：``logic [ADDR_W-1:0] next_write_addr_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，align_addr(task_addr, AXI_SIZE_W) | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 align_addr(task_addr, AXI_SIZE_W)<br>if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；赋值为 next_write_addr_reg + (1'b1 << AXI_SIZE_W) |
| ``next_write_words_to_4kb_limited_reg`` | ``logic [BURST_COUNT_W-1:0]``；声明：``logic [BURST_COUNT_W-1:0] next_write_words_to_4kb_limited_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 '0<br>case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；赋值为 limit_burst_words(next_write_words_to_4kb_reg) |
| ``next_write_words_to_4kb_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] next_write_words_to_4kb_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，calc_words_to_4kb(align_addr(task_addr, AXI_SIZE_W), BYTE_W) | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 calc_words_to_4kb(align_addr(task_addr, AXI_SIZE_W), BYTE_W)<br>S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；if (next_write_words_to_4kb_reg == 1) begin；赋值为 4096 / BYTE_W<br>S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；if (next_write_words_to_4kb_reg == 1) begin；赋值为 next_write_words_to_4kb_after_fire |
| ``result_done_reg`` | ``logic 1 bit/enum``；声明：``logic result_done_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，!error_latched_reg | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；赋值为 1'b0<br>if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；if (!result_pending_reg) begin；赋值为 !error_latched_reg |
| ``result_error_reg`` | ``logic 1 bit/enum``；声明：``logic result_error_reg;`` | 错误锁存或错误事件标志。 | 复位/清零候选：1'b0，error_latched_reg | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；赋值为 1'b0<br>if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；if (!result_pending_reg) begin；赋值为 error_latched_reg |
| ``result_pending_reg`` | ``logic 1 bit/enum``；声明：``logic result_pending_reg;`` | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；赋值为 1'b0<br>if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；if (!result_pending_reg) begin；赋值为 1'b1 |
| ``state_reg`` | ``state_t 1 bit/enum``；声明：``state_t state_reg;`` | 状态机当前状态或状态相关寄存器。 | 枚举 ``state_t``：``S_IDLE``=0，``S_PREP_LIMIT``=1，``S_PREP``=2，``S_AWCFG``=3，``S_AW``=4，``S_WDATA``=5，``S_BRESP``=6，``S_DONE``=7 | if (sys_rst) begin；赋值为 S_IDLE<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；if (state_reg == S_DONE) begin；赋值为 S_IDLE<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 S_PREP_LIMIT<br>case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；赋值为 S_PREP<br>S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；赋值为 S_AWCFG<br>if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；S_PREP: begin；S_AWCFG: begin；赋值为 S_AW |
| ``w_stall_assert_reg`` | ``logic 1 bit/enum``；声明：``logic w_stall_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；if (m_axi_wr.wvalid && !m_axi_wr.wready) begin；赋值为 1'b1<br>if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；if (m_axi_wr.wvalid && !m_axi_wr.wready) begin；赋值为 1'b0 |
| ``wdata`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>S_AW: begin；if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；赋值为 word_buf_data_reg |
| ``wdata_hold_assert_reg`` | ``logic [DATA_W-1:0]``；声明：``logic [DATA_W-1:0] wdata_hold_assert_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，m_axi_wr.wdata | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；if (m_axi_wr.wvalid && !m_axi_wr.wready) begin；赋值为 m_axi_wr.wdata |
| ``wlast`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (word_ready && word_valid) begin；if (aw_fire) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>S_AW: begin；if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；赋值为 burst_last_word<br>if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；赋值为 1'b0 |
| ``wlast_hold_assert_reg`` | ``logic 1 bit/enum``；声明：``logic wlast_hold_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，m_axi_wr.wlast | if (sys_rst) begin；赋值为 1'b0<br>if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；if (m_axi_wr.wvalid && !m_axi_wr.wready) begin；赋值为 m_axi_wr.wlast |
| ``word_buf_data_reg`` | ``logic [DATA_W-1:0]``；声明：``logic [DATA_W-1:0] word_buf_data_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，word_data | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；if (state_reg == S_DONE) begin；if (word_ready && word_valid) begin；赋值为 word_data |
| ``word_buf_strb_reg`` | ``logic [BYTE_W-1:0]``；声明：``logic [BYTE_W-1:0] word_buf_strb_reg;`` | 数据、像素、word 或 sample 缓冲寄存器。 | 复位/清零候选：'0，word_strb | if (sys_rst) begin；赋值为 '0<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；if (state_reg == S_DONE) begin；if (word_ready && word_valid) begin；赋值为 word_strb |
| ``word_buf_valid_reg`` | ``logic 1 bit/enum``；声明：``logic word_buf_valid_reg;`` | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0，1'b1 | if (sys_rst) begin；赋值为 1'b0<br>if (sys_rst) begin；if (result_pending_reg && result_ready) begin；if (state_reg == S_DONE) begin；if (word_ready && word_valid) begin；赋值为 1'b1<br>if (word_ready && word_valid) begin；if (aw_fire) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>S_AW: begin；if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；赋值为 1'b0<br>if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；赋值为 1'b0 |
| ``words_sent_total_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] words_sent_total_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 '0<br>if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；赋值为 words_sent_total_reg + 1'b1 |
| ``words_total_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] words_total_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，calc_total_words(task_byte_count, task_addr[AXI_SIZE_W-1:0], BYTE_W) | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 calc_total_words(task_byte_count, task_addr[AXI_SIZE_W-1:0], BYTE_W) |
| ``words_write_remaining_limited_reg`` | ``logic [BURST_COUNT_W-1:0]``；声明：``logic [BURST_COUNT_W-1:0] words_write_remaining_limited_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 '0<br>case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；S_PREP_LIMIT: begin；赋值为 limit_burst_words(words_write_remaining_reg) |
| ``words_write_remaining_reg`` | ``logic [COUNT_W-1:0]``；声明：``logic [COUNT_W-1:0] words_write_remaining_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，calc_total_words(task_byte_count, task_addr[AXI_SIZE_W-1:0], BYTE_W) | if (sys_rst) begin；赋值为 '0<br>if (aw_fire) begin；case (state_reg)；S_IDLE: begin；if (task_valid && task_ready) begin；赋值为 calc_total_words(task_byte_count, task_addr[AXI_SIZE_W-1:0], BYTE_W)<br>if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；赋值为 words_write_remaining_after_fire |
| ``wstrb`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0<br>S_AW: begin；if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；赋值为 word_buf_strb_reg |
| ``wstrb_hold_assert_reg`` | ``logic [(DATA_W/8)-1:0]``；声明：``logic [(DATA_W/8)-1:0] wstrb_hold_assert_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，m_axi_wr.wstrb | if (sys_rst) begin；赋值为 '0<br>if (m_axi_wr.awlen > 8'd255) begin；if ((m_axi_wr.awaddr[11:0] + aw_burst_bytes_assert) > 4096) begin；if (m_axi_wr.awvalid && !m_axi_wr.awready) begin；if (m_axi_wr.wvalid && !m_axi_wr.wready) begin；赋值为 m_axi_wr.wstrb |
| ``wuser`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0 | if (sys_rst) begin；赋值为 '0 |
| ``wvalid`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | valid 有效标志，用于保持握手事务直到被接收。 | 复位/清零候选：1'b0 | if (sys_rst) begin；赋值为 1'b0<br>if (word_ready && word_valid) begin；if (aw_fire) begin；case (state_reg)；S_IDLE: begin；赋值为 1'b0<br>S_AW: begin；if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；赋值为 1'b1<br>if (aw_fire) begin；S_WDATA: begin；if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；赋值为 1'b0<br>if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin；S_DONE: begin；赋值为 1'b0 |

### 7.2 状态机状态编码与跳转条件

- 状态类型 ``state_t``，编码位宽：``[2:0]``。

| 状态 | 编码 | 状态作用 | 主要跳转条件 |
|---|---|---|---|
| ``S_IDLE`` | 0 | 空闲/等待新任务或新事务。 | 到 ``S_PREP_LIMIT``：S_IDLE: begin；if (task_valid && task_ready) begin |
| ``S_PREP_LIMIT`` | 1 | 初始化、预计算或准备阶段。 | 到 ``S_PREP``：S_PREP_LIMIT: begin |
| ``S_PREP`` | 2 | 初始化、预计算或准备阶段。 | 到 ``S_AWCFG``：S_PREP: begin |
| ``S_AWCFG`` | 3 | 发起请求或地址通道阶段。 | 到 ``S_AW``：S_AWCFG: begin |
| ``S_AW`` | 4 | 发起请求或地址通道阶段。 | 到 ``S_WDATA``：S_AW: begin；if (aw_fire) begin |
| ``S_WDATA`` | 5 | 状态含义从命名可部分推断，详细行为见源码 case 分支。 | 到 ``S_BRESP``：if (!m_axi_wr.wvalid && word_buf_valid_reg) begin；if (w_fire) begin；if (next_write_words_to_4kb_reg == 1) begin；if (burst_last_word) begin |
| ``S_BRESP`` | 6 | 等待下游响应或返回数据。 | 到 ``S_DONE``：S_BRESP: begin；if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin<br>到 ``S_PREP_LIMIT``：S_BRESP: begin；if (b_fire) begin；if (m_axi_wr.bresp != 2'b00) begin；if ((m_axi_wr.bresp != 2'b00) \|\| (words_write_remaining_reg == 0)) begin |
| ``S_DONE`` | 7 | 输出、排空或完成阶段。 | 到 ``S_IDLE``：S_DONE: begin；if (!result_pending_reg) begin |

<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为 ``ddr_write_engine`` axi 域 word FIFO。
- 下游为顶层 AXI 写通道。
- ``pixel_packer`` 负责生成 ``word_data``/``word_strb``。

## 9. 握手协议说明
- ``task_ready`` 在空闲且无 pending result 时接受任务。
- ``aw_fire`` 后进入 WDATA，``w_fire`` 推进 beat，``b_fire`` 采样响应。
- ``word_ready = (state_reg == S_WDATA) && !word_buf_valid_reg``。

## 10. 错误处理与边界条件
- ``BRESP`` 非 OKAY 上报错误。
- 仿真断言覆盖 AWLEN、4KB crossing、AW/W stalled 稳定性。
- 上游数据数量与任务长度不一致的完整保护需结合 packer 与源码断言判断。

## 11. 综合/时序/CDC注意事项
- 地址规划、WSTRB 和 W 通道缓冲是主要 timing 点。
- 本模块无 CDC。

## 12. 维护建议
- 修改 WSTRB 规则时同步 ``pixel_packer`` 和 ``ddr_axi_pkg``。
- 若未来支持多 outstanding 写响应，需要重构当前单任务状态机。

## 13. 待确认问题
- 待确认：系统是否允许未对齐写起始地址。
