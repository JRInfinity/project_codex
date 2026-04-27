# async_word_fifo

> 依据文件：``rtl/buffer/async_word_fifo.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `async_word_fifo` 是主链路基础模块：通用异步 word FIFO，优先使用 Xilinx ``xpm_fifo_async``，为任务、结果、统计和 AXI word 提供 CDC。
- 其设计目的不是实现图像算法，而是把跨域、数据格式或 AXI 公共计算从主控制逻辑中拆出来。

## 2. 文件路径
- ``rtl/buffer/async_word_fifo.sv``

## 3. 主要功能
- 主要功能：通用异步 word FIFO，优先使用 Xilinx ``xpm_fifo_async``，为任务、结果、统计和 AXI word 提供 CDC。
- 具体字段、宽度和非法参数由源码参数、localparam 和 ``initial`` 检查约束。

## 4. 参数说明
- ``DATA_W``：默认 ``32``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``DEPTH``：默认 ``64``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``ALMOST_FULL_MARGIN``：默认 ``4``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`wr_clk`（input）。
- 时钟/复位：`wr_rst`（input）。
- 数据/控制：`wr_en`（input）。
- 数据/控制：`wr_data`（input）。
- 数据/控制：`full`（output）。
- 数据/控制：`almost_full`（output）。
- 数据/控制：`wr_count`（output）。
- 数据/控制：`overflow`（output）。
- 时钟/复位：`rd_clk`（input）。
- 时钟/复位：`rd_rst`（input）。
- 数据/控制：`rd_en`（input）。
- 数据/控制：`rd_data`（output）。
- 数据/控制：`empty`（output）。
- 数据/控制：`rd_count`（output）。
- 数据/控制：`underflow`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 内部结构以寄存器化控制和小型 FIFO/状态机为主。
- 状态机和状态名见本页自动提取的“内部结构”补充项；若无状态机则以组合函数或 FIFO wrapper 为主。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/buffer/async_word_fifo.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``overflow`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，wr_en && full | if (wr_rst) begin；赋值为 1'b0<br>if (wr_rst) begin；赋值为 wr_en && full |
| ``underflow`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，rd_en && empty | if (rd_rst) begin；赋值为 1'b0<br>if (rd_rst) begin；赋值为 rd_en && empty |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
<!-- AUTO_INTERNAL_END -->

## 8. 上游/下游连接关系
- 上下游关系见 ``image_geo_top.sv`` 和调用模块实例化。
- 在主链路中承担 CDC、格式转换或公共计算职责。

## 9. 握手协议说明
- 所有任务/结果/数据流均以 valid/ready 或 FIFO full/empty 为握手边界。
- CDC 模块要求 payload 在 ``valid`` 未被 ``ready`` 接收前保持稳定。

## 10. 错误处理与边界条件
- 非法参数通过源码检查暴露。
- FIFO full/empty、payload 不稳定、end marker 错位或长度不匹配等错误由对应模块检查。

## 11. 综合/时序/CDC注意事项
- CDC 模块不能被组合跨域旁路。
- 格式转换模块在 ``DATA_W`` 增大时要关注 byte-lane mux 和计数比较。

## 12. 维护建议
- 增删 payload 字段或统计项时同步所有实例和寄存器映射。
- 修改公共函数时同步 reader/writer 和接口专题文档。

## 13. 待确认问题
- 待确认：是否需要把内部错误原因扩展为软件可读枚举。
