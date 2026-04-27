# row_advance_unit

> 依据文件：``rtl/core/row_advance_unit.sv``。文档结论来自源码、现有文档和可追溯文件名；不能确定处标为“待确认”。

## 1. 模块定位
- `row_advance_unit`：行基坐标推进辅助单元，用多拍分段降低宽坐标加法时序压力。
- 在当前主说明中属于保留、辅助或算法子单元；是否进入最终顶层需看实例化关系。

## 2. 文件路径
- ``rtl/core/row_advance_unit.sv``

## 3. 主要功能
- 行基坐标推进辅助单元，用多拍分段降低宽坐标加法时序压力。
- 通过源码端口与状态机可以追溯其控制、数据和错误路径。

## 4. 参数说明
- ``COORD_W``：默认 ``36``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。
- ``FRAC_W``：默认 ``16``。来源于源码参数声明；用途见本页定位/功能和调用关系，数值约束见源码中的 ``initial``/``$error`` 检查。

## 5. 端口说明
- 时钟/复位：`clk`（input）。
- 时钟/复位：`rst`（input）。
- 握手/状态：`start`（input）。
- 握手/状态：`busy`（output）。
- 握手/状态：`done`（output）。

## 6. 时钟与复位
- 时钟/复位端口见上一节自动提取；若存在多个时钟域，跨域路径必须通过本页或专题文档列出的 CDC/FIFO。
- 对于 package 或纯组合辅助函数，本节不适用。

## 7. 内部结构
- 内部通常为小状态机、坐标/指针寄存器或行存储。
- 若被主链路实例化，时序和边界策略应与调用者一起审查。


<!-- AUTO_INTERNAL_BEGIN -->

### 7.1 内部寄存器定义、作用、编码及变化条件

> 本小节由 ``rtl/core/row_advance_unit.sv`` 中的声明和 ``always_ff`` 非阻塞赋值提取。表中的“变化条件”保留源码条件表达式名称，便于回查；未能从命名确定的语义标为“待确认”。

| 寄存器 | 定义/位宽 | 作用 | 编码/复位取值 | 变化条件 |
|---|---|---|---|---|
| ``axis_reg`` | ``logic 1 bit/enum``；声明：``logic axis_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；if (start && !busy) begin；赋值为 1'b0<br>if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；default: begin；赋值为 1'b1<br>case (seg_idx_reg)；default: begin；case (seg_idx_reg)；default: begin；赋值为 1'b0 |
| ``base_x_hold_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] base_x_hold_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，base_x | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；赋值为 base_x |
| ``base_y_hold_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] base_y_hold_reg;`` | 地址或地址规划寄存器。 | 复位/清零候选：'0，base_y | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；赋值为 base_y |
| ``busy`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务忙/活动窗口标志。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>if (rst) begin；if (start && !busy) begin；赋值为 1'b1<br>case (seg_idx_reg)；default: begin；case (seg_idx_reg)；default: begin；赋值为 1'b0 |
| ``carry_reg`` | ``logic [ROW_SEG_W:0]``；声明：``logic [ROW_SEG_W:0] carry_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，{1'b0, base_x_hold_reg[ROW_SEG_W-1:0]} + | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；赋值为 {1'b0, base_x_hold_reg[ROW_SEG_W-1:0]} +<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)<br>if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；default: begin；赋值为 '0<br>if (!axis_reg) begin；case (seg_idx_reg)；default: begin；case (seg_idx_reg)；赋值为 {1'b0, base_y_hold_reg[ROW_SEG_W-1:0]} + |
| ``done`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 任务完成、结果 pending 或结果状态寄存。 | 复位/清零候选：1'b0，1'b1 | if (rst) begin；赋值为 1'b0<br>case (seg_idx_reg)；default: begin；case (seg_idx_reg)；default: begin；赋值为 1'b1 |
| ``next_x`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，carry_reg[ROW_SEG_W-1:0] | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；赋值为 carry_reg[ROW_SEG_W-1:0]<br>if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；default: begin；赋值为 carry_reg[ROW_SEG_W-1:0]<br>if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；default: begin |
| ``next_y`` | 未在简单声明表中匹配；可能是接口字段、数组元素或局部寄存变量。 | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，carry_reg[ROW_SEG_W-1:0] | if (rst) begin；赋值为 '0<br>if (!axis_reg) begin；case (seg_idx_reg)；default: begin；case (seg_idx_reg)；赋值为 carry_reg[ROW_SEG_W-1:0]<br>case (seg_idx_reg)；default: begin；case (seg_idx_reg)；default: begin；赋值为 carry_reg[ROW_SEG_W-1:0]<br>case (seg_idx_reg)；default: begin；case (seg_idx_reg)；default: begin |
| ``seg_idx_reg`` | ``logic [2:0]``；声明：``logic [2:0] seg_idx_reg;`` | 计数、索引或剩余量寄存器。 | 复位/清零候选：'0，3'd1，3'd2 | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；赋值为 3'd1<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；赋值为 3'd2<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；赋值为 3'd3<br>if (rst) begin；if (start && !busy) begin；if (!axis_reg) begin；case (seg_idx_reg)；赋值为 3'd4 |
| ``step_x_hold_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] step_x_hold_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，step_x | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；赋值为 step_x |
| ``step_y_hold_reg`` | ``logic [COORD_W-1:0]``；声明：``logic signed [COORD_W-1:0] step_y_hold_reg;`` | 内部时序寄存器；具体语义需结合同名赋值和使用位置。 | 复位/清零候选：'0，step_y | if (rst) begin；赋值为 '0<br>if (rst) begin；if (start && !busy) begin；赋值为 step_y |

### 7.2 状态机状态编码与跳转条件

- 未提取到显式 enum 状态机。若模块使用 flag/计数器隐式控制流程，请以上一节寄存器变化条件为准。
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
