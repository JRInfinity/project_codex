# ddr_write_engine

> 依据文件：``rtl/axi/ddr_write_engine.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- 连接 core 域行像素流与 axi 域 ``axi_burst_writer``。
- 承担任务 CDC、像素 pack、word FIFO CDC 和写响应回传。

## 2. 文件路径
- ``rtl/axi/ddr_write_engine.sv``

## 3. 主要功能
- 接收写地址和 byte_count 任务。
- ``pixel_packer`` 将 8 bit 像素聚合为 AXI word/WSTRB。
- ``axi_burst_writer`` 写 DDR 并返回 done/error。

## 4. 参数说明
- ``DATA_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``ADDR_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``PIXEL_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``BURST_MAX_LEN``：默认 ``256``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``AXI_ID_W``：默认 ``8``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``FIFO_DEPTH_PIXELS``：默认 ``256``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`axi_clk`（input）。
- 时钟/复位：`core_clk`（input）。
- 时钟/复位：`axi_rst`（input）。
- 时钟/复位：`core_rst`（input）。
- 握手/状态：`task_start`（input）。
- 数据/控制：`task_addr`（input）。
- 数据/控制：`task_byte_count`（input）。
- 握手/状态：`task_busy`（output）。
- 握手/状态：`task_done`（output）。
- 状态/错误/统计：`task_error`（output）。
- 数据/控制：`in_data`（input）。
- 握手/状态：`in_valid`（input）。
- 握手/状态：`in_ready`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- ``task_start_accept`` 要求任务未活动、CDC ready 且 ``task_byte_count != 0``。
- ``in_ready = !pixel_fifo_full``，输入是否可接收由像素 FIFO 余量决定。
- result 通过 ``result_cdc`` 回到 core 域。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/axi/ddr_write_engine.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``task_active_reg`` | ``logic 1 bit/enum``；声明：``logic task_active_reg;`` | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (core_rst) begin；赋值为 1'b0<br>if (core_rst) begin；if (task_start_accept) begin；赋值为 1'b1<br>if (core_rst) begin；if (task_start_accept) begin；赋值为 1'b0 |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上游为 ``row_out_buffer``。
- 下游为 ``axi_burst_writer`` 和 AXI 写通道。

## 9. 握手协议说明
- task 使用 start/ready，payload 经 ``task_cdc`` 跨域。
- 像素流使用 ``in_valid/in_ready``，packed word 使用 FIFO valid/ready。
- ``task_error`` 来自 ``result_error_evt_core``。

## 10. 错误处理与边界条件
- byte_count 为 0 的任务不接受。
- ``BRESP`` 错误通过 writer/result CDC 上报。
- 输入像素数量与 byte_count 不匹配需结合 ``pixel_packer`` 错误路径。

## 11. 综合/时序/CDC注意事项
- 输入 FIFO 深度决定 row buffer 被反压余量。
- 所有跨域均经 CDC/FIFO 封装。

## 12. 维护建议
- 修改像素格式时同步 ``pixel_packer``、row buffer 和 byte_count 计算。
- 若要二维写任务，可参考 ``ddr_read_engine`` 的 2D task CDC。

## 13. 待确认问题
- 待确认：当前写回任务是逐行还是整帧连续提交。
