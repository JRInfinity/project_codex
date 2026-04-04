# 模块：ddr_read_engine

先给你一个总览：这个模块本质上是在做三件事：

1. 接收一次“从 DDR 读若干字节”的任务
2. 把这个任务拆成一个或多个 AXI 突发读 burst
3. 把 AXI 回来的 `DATA_W` 位宽数据，再拆成 8bit 像素流 `out_data`

所以内部寄存器也刚好分成几类：

- **状态机类**
- **当前读任务进度类**
- **当前 burst 进度类**
- **当前返回数据拆字节类**
- **输出/完成/错误标志类**

------

# 1. 状态寄存器

## `state_reg`

类型：`state_t`

这是**主状态机当前状态**。代码里有 4 个状态：

- `S_IDLE`：空闲，等 `read_start`
- `S_PREP`：准备并发出一个 AXI 读地址请求 `AR`
- `S_FETCH`：等待并接收 AXI 返回数据 `R`
- `S_DONE`：本次读任务结束，打一拍 `read_done`

你可以把它理解成“这个读引擎现在处在哪个工作阶段”。

------

## `state_next`

类型：`state_t`

这是**组合逻辑算出来的下一状态**。
 `always_comb` 里先根据当前状态和条件决定“下一拍该去哪”，然后 `always_ff` 在时钟上升沿把它装入 `state_reg`。

这是标准 FSM 写法。

------

# 2. 当前读任务进度相关寄存器

这些寄存器描述的是：**整次 read 命令还剩多少没完成**。

## `curr_addr_reg`

类型：`logic [ADDR_W-1:0]`

表示**当前还要继续读的数据地址**。

- 刚开始时，装入 `read_addr`
- 每完成一个 burst，就往后加 `bytes_in_burst_calc`
- 所以它始终指向“下一次还没读的那一段数据”的起始地址

注意它不一定对齐到 AXI 总线字宽；用户给什么地址，它就从什么地址开始，只不过真正发到 AXI 的 `araddr` 会先对齐。

------

## `bytes_left_reg`

类型：`logic [COUNT_W-1:0]`

表示**整次读任务还剩多少字节没送出去**。

- 开始时 = `read_byte_count`
- 每当 `out_fire`（即一个像素字节真正输出成功）时减 1
- 变成 0 就说明本次任务所有需要的字节都已经输出完了

这个寄存器非常核心。
 它不是“AXI 还剩多少 beat”，而是“用户要求的有效字节还剩多少”。

------

# 3. 当前 burst 相关寄存器

这些寄存器描述的是：**当前这一个 AXI burst 的执行情况**。

## `burst_words_reg`

类型：`logic [COUNT_W-1:0]`

表示**当前 burst 一共要读多少个 AXI word/beat**。

比如：

- 总线 32bit，则 1 个 word = 4 字节
- 如果这次 burst 决定发 16 个 beat，那么 `burst_words_reg = 16`

它是在 `S_PREP` 状态里，根据：

- 剩余数据量
- 最大突发长度 `BURST_MAX_LEN`
- 4KB 边界限制

综合计算出来的。

------

## `burst_rcvd_words_reg`

类型：`logic [COUNT_W-1:0]`

表示**当前 burst 已经收到了多少个 AXI 返回 beat**。

每次 `r_fire` 时加 1。

用途主要有两个：

1. 判断这次收到的是不是 **burst 的第一个 beat**
   - 如果是第一个 beat，要考虑起始地址的 byte offset
2. 判断这次收到的是不是 **最后一个 beat**
   - 用来核对 `rlast` 是否正确

------

## `first_byte_offset_reg`

类型：`logic [AXI_SIZE_W-1:0]`

表示**本次 burst 的第一个 AXI word 中，从第几个字节开始才是有效数据**。

举例，若：

- `DATA_W = 32`，即 1 beat = 4 字节
- 用户要求从地址 `0x1002` 开始读

那么 AXI 必须从对齐地址 `0x1000` 开始读第一个 32bit word，
 但这个 word 里的前两个字节（偏移 0、1）不是用户要的，真正有效的是偏移 2 开始的数据。
 这时：

- `aligned_addr = 0x1000`
- `first_byte_offset_reg = 2`

所以它就是“首拍里要跳过多少个字节”。

------

## `burst_done_reg`

类型：`logic`

表示**当前 burst 是否已经正常结束**。

在接收 `R` 通道时，如果满足：

- 当前 beat 是预期的最后一个 beat
- `rresp == OKAY`
- `rlast == 1`

就把它置 1。

然后状态机在 `S_FETCH` 中看到：

- `burst_done_reg == 1`
- 当前缓存数据也吐干净了
- 且 `bytes_left_reg != 0`

就转去 `S_PREP`，发下一个 burst。

所以这个寄存器可以理解为：
 **“AXI 这趟 burst 已经接收完了，等我把手里缓存的字节吐完就能发下一趟。”**

------

# 4. 返回数据缓存与拆字节相关寄存器

AXI 一次返回的是一个 `DATA_W` 位宽的 word，比如 32bit。
 但模块输出给下游的是 8bit 像素流。所以必须有“缓存当前 word，并逐字节吐出”的机制。

## `data_word_reg`

类型：`logic [DATA_W-1:0]`

表示**当前缓存的一整个 AXI 返回数据 word**。

每次 `r_fire` 时，把 `m_axi_rd.rdata` 存进来。

之后 `out_data` 就从这个寄存器里按字节切片取出：

```
assign out_data = data_word_reg[data_byte_idx_reg*PIXEL_W +: PIXEL_W];
```

如果 `PIXEL_W=8`，那就是按 8bit 一个字节地取。

------

## `data_byte_idx_reg`

类型：`logic [AXI_SIZE_W-1:0]`

表示**当前应该输出 `data_word_reg` 里的第几个字节**。

例如 32bit word 里有 4 个字节：

- 0 → 最低字节
- 1 → 次低字节
- 2
- 3

它在两种情况下会被设置：

### 情况 1：刚收到一个新的 AXI word

- 如果这是本 burst 的第一个返回 word，起始索引 = `first_byte_offset_reg`
- 否则起始索引 = 0

### 情况 2：输出一个字节成功后

- `out_fire` 时自增 1，准备输出下一个字节

所以它本质上是：
 **当前这个 `data_word_reg` 被拆到第几个 byte 了。**

------

## `data_bytes_left_reg`

类型：`logic [AXI_SIZE_W:0]`

表示**当前缓存 word 里还剩多少个有效字节可输出**。

这个“有效”很重要，不一定总是 `BYTE_W` 个，因为：

- 第一个 word 可能要跳过前面的 offset 字节
- 最后一个 word 可能只有前几个字节有效，不满一个整字

所以每次 `r_fire` 时，它会装入 `capture_bytes_calc`，表示：
 “这个新收到的 word 中，真正要输出给用户的有效字节数量”。

然后每次 `out_fire`：

- 若只剩 1 个字节，就清空 `data_valid_reg`
- 否则减 1

------

## `data_valid_reg`

类型：`logic`

表示**当前 `data_word_reg` 里是否有待输出的数据**。

- `r_fire` 收到一个新 word，且其中有有效字节时，置 1
- 当前 word 的最后一个有效字节输出后，清 0

它直接驱动：

```
assign out_valid = data_valid_reg;
```

所以对下游来说，只要 `out_valid=1`，就说明 `out_data` 当前有效。

------

# 5. 完成与错误标志寄存器

## `read_done`

类型：`logic`

表示**本次整个读任务完成**。

在 `S_DONE` 状态拉高一个时钟周期，然后下一拍清零。

它是一个**脉冲信号**，不是电平保持信号。

------

## `read_error`

类型：`logic`

表示**本次读任务出错**。

在以下情况会置 1：

### 1）AXI 返回响应不对

```
if (m_axi_rd.rresp != 2'b00)
```

说明读响应不是 `OKAY`

### 2）`rlast` 和预期不一致

```
if (m_axi_rd.rlast != burst_last_expected)
```

也就是：

- 该结束时没结束
- 不该结束时却结束了

一旦出错：

- `read_error <= 1`
- `rready <= 0`
- 状态机会跳到 `S_DONE`

所以这个寄存器表示整次任务是否发生 AXI 协议级/返回级错误。

------

## `read_busy`

虽然不是 `*_reg`，但很重要

```
assign read_busy = (state_reg != S_IDLE);
```

表示模块是不是正在忙。
 只要不在 `S_IDLE`，就算忙。

------

# 6. 这些“calc”组合量虽然不是寄存器，但也最好一起理解

因为它们和寄存器关系非常紧。

## `aligned_addr_calc`

把 `curr_addr_reg` 向下按总线字宽对齐后的地址。

例子：

- 32bit 总线 → 4 字节对齐
- `0x1002` 会对齐成 `0x1000`

这是发给 AXI 的实际 `araddr`。

------

## `bytes_with_offset_calc`

表示：
 **从对齐地址开始算，要覆盖当前剩余有效数据，一共需要涉及多少字节空间。**

公式：

- 剩余有效字节 `bytes_left_reg`
- 加上首地址在首个 word 内的偏移

------

## `words_left_full_calc` / `words_left_calc`

表示：
 **为了覆盖这些字节，总共还需要多少个 AXI beat。**

本质上是向上取整除以 `BYTE_W`。

------

## `bytes_to_4kb_calc`

表示从当前对齐地址开始，到 4KB 边界前还剩多少字节。

因为 AXI burst **不能跨 4KB 边界**，这在 AXI 规范里是明确要求。这个模块也按这个规则做了限制。相关 AXI 规范说明见 ARM AXI 协议文档和 AMD AXI DMA 文档。 

------

## `words_to_4kb_calc`

把上面的字节数换算成最多还能发多少个 beat。

------

## `burst_words_calc`

这是**本次 burst 最终决定的 beat 数**。
 它取这几个量的最小值：

- 当前总共还需要的 beat 数
- `BURST_MAX_LEN`
- 4KB 边界允许的 beat 数

------

## `bytes_in_burst_calc`

表示**本次 burst 真正能覆盖多少个用户需要的有效字节**。

注意这不是 `burst_words * BYTE_W` 那么简单，
 因为 burst 第一个 word 前面可能有 offset 字节不算有效。

------

## `bytes_this_word_calc`

表示**当前收到的这个 AXI word 理论上能贡献多少个有效字节**。

- 如果是 burst 第一个 word：要减掉 `first_byte_offset_reg`
- 否则就是整 word 的 `BYTE_W`

------

## `capture_bytes_calc`

表示**这一拍新收到的 AXI word，实际要缓存并输出多少个字节**。

因为最后一个 word 可能并不全都需要，所以还要和 `bytes_left_reg` 比较，取较小值。

------

# 7. AXI 接口输出寄存器的含义

这几个虽然属于接口信号，但在你的代码里也是用寄存器方式驱动的，也值得一起说明。

## `m_axi_rd.arid`

AXI 读地址通道 ID。
 这里固定写 0，说明这个模块暂时不做多 ID 并发区分。

------

## `m_axi_rd.araddr`

AXI 读地址。
 装的是 `aligned_addr_calc`，即对齐后的地址。

------

## `m_axi_rd.arlen`

AXI burst 长度字段，等于 **beat 数减 1**。
 例如 burst 读 16 个 beat，则 `arlen = 15`。

AXI 协议中 `ARLEN` 表示的是 “number of transfers - 1”。这一点在 ARM AXI 协议里有定义。

------

## `m_axi_rd.arsize`

每个 beat 的字节数编码。
 比如 4 字节 beat，则编码是 `2`，因为 `2^2 = 4`。

------

## `m_axi_rd.arburst`

这里固定 `2'b01`，表示 **INCR burst**，也就是地址递增 burst。
 AXI 的 burst 类型定义里：

- `00` FIXED
- `01` INCR
- `10` WRAP
   见 AXI 规范。

------

## `m_axi_rd.arlock`

锁访问控制，这里固定 0，不用锁访问。

------

## `m_axi_rd.arcache`

缓存属性，这里固定 `4'b0011`。

直观理解：这是在告诉系统“这个读事务的缓存/缓冲属性是什么”。
 如果你后面要严格优化 DDR 性能，这个位域可以结合系统互连/DDR 控制器策略再细看。

------

## `m_axi_rd.arprot`

保护属性，这里固定 `3'b000`。
 一般表示普通、非特权、数据访问之类的默认配置。

------

## `m_axi_rd.arqos`

QoS，这里固定 0，表示不特别声明优先级。

------

## `m_axi_rd.arregion`

区域号，这里固定 0。

------

## `m_axi_rd.aruser`

用户自定义 sideband，这里固定 0。

------

## `m_axi_rd.arvalid`

表示读地址是否有效。
 在 `S_PREP` 拉高，等 `arready` 握手后拉低。

------

## `m_axi_rd.rready`

表示本模块是否准备好接收读数据。
 这里的策略是：

- 只有当前 `data_valid_reg=0`，也就是内部没有待输出 word 时，才拉高 `rready`
- 一旦收到一个 AXI word，就先把它拆完、吐完，再接下一个

所以这个实现本质上是**单 word 缓冲**，吞吐率不是极致，但逻辑简单。

------

# 8. 各寄存器之间的配合关系

把它们串起来看，就更容易懂了：

## 启动时

- `curr_addr_reg <= read_addr`
- `bytes_left_reg <= read_byte_count`

## 准备 burst 时

- 根据 `curr_addr_reg` 和 `bytes_left_reg` 算出
  - 对齐地址
  - offset
  - 本次 burst 多长
- 存入
  - `burst_words_reg`
  - `burst_rcvd_words_reg <= 0`
  - `first_byte_offset_reg`
  - `burst_done_reg <= 0`

## 收到 AXI 一个 beat 时

- `data_word_reg <= rdata`
- `data_byte_idx_reg <= 首字节索引`
- `data_bytes_left_reg <= 本 word 有效字节数`
- `data_valid_reg <= 1`
- `burst_rcvd_words_reg++`

## 吐出一个字节时

- `bytes_left_reg--`
- `data_byte_idx_reg++`
- `data_bytes_left_reg--`
- 若当前 word 吐完，则 `data_valid_reg <= 0`

## 当前 burst 收完时

- `burst_done_reg <= 1`
- `curr_addr_reg <= curr_addr_reg + bytes_in_burst_calc`

## 全部字节吐完时

- 进入 `S_DONE`
- `read_done` 拉高一拍

------

# 9. 你最该重点理解的几个寄存器

如果你现在不想一次全记住，我建议先把下面 8 个吃透：

- `state_reg`：状态机走到哪了
- `curr_addr_reg`：下一段数据该从哪读
- `bytes_left_reg`：整次任务还剩多少字节
- `burst_words_reg`：当前 burst 有多少 beat
- `burst_rcvd_words_reg`：当前 burst 已收多少 beat
- `first_byte_offset_reg`：首拍要跳过多少字节
- `data_byte_idx_reg`：当前 word 正在输出第几个字节
- `data_bytes_left_reg`：当前 word 还剩多少有效字节

这几个一懂，整个模块就基本通了。

------

# 10. 一句话总结每个内部寄存器

为了方便你复习，我再压缩成一句话版：

- `state_reg`：当前状态
- `state_next`：下一状态
- `curr_addr_reg`：当前剩余任务的起始地址
- `bytes_left_reg`：当前剩余任务还差多少字节
- `burst_words_reg`：当前 burst 总 beat 数
- `burst_rcvd_words_reg`：当前 burst 已收到多少 beat
- `first_byte_offset_reg`：首个 beat 从第几个 byte 才开始有效
- `burst_done_reg`：当前 burst 是否已经完整收完
- `data_word_reg`：当前缓存的一整个 AXI 返回 word
- `data_byte_idx_reg`：当前正在输出这个 word 的第几个 byte
- `data_bytes_left_reg`：这个 word 里还剩多少有效 byte 没输出
- `data_valid_reg`：当前 word 缓存是否有效
- `read_done`：整次读任务完成脉冲
- `read_error`：整次读任务出错标志