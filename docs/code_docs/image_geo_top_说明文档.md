# image_geo_top 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\image_geo_top.sv`

## 作用
`image_geo_top` 是图像几何处理链路的顶层封装，主要负责三件事：

1. 通过 AXI4-Lite 暴露控制寄存器，供 PS/主控配置任务参数。
2. 把寄存器中的配置送给内部的 `scaler_ctrl`、`ddr_read_engine`、`scale_core_nearest`、`src_line_buffer`、`row_out_buffer`、`ddr_write_engine`。
3. 汇总完成/错误状态，并通过 `irq` 对外发中断。

## 接口总览

### 1. 控制面接口
- `s_axi_ctrl_*`

这是 AXI4-Lite 从接口，用来访问控制寄存器。

### 2. 读数据面接口
- `m_axi_rd_*`

这是 AXI4 主读口，用来从 DDR 读取源图像数据。

### 3. 写数据面接口
- `m_axi_wr_*`

这是 AXI4 主写口，用来把处理结果写回 DDR。

### 4. 中断接口
- `irq`

当 `reg_irq_en=1` 且 `done_sticky_reg=1` 或 `error_sticky_reg=1` 时拉高。

---

## 寄存器映射总表

当前 AXI-Lite 地址宽度为 12bit，寄存器按 4 字节对齐。

| 名称 | 偏移地址 | 宽度 | 访问属性 | 作用 |
| --- | --- | --- | --- | --- |
| `CTRL` | `0x000` | 32bit | `RW` | 启动任务、中断使能 |
| `SRC_BASE_ADDR` | `0x004` | 32bit | `RW` | 源图 DDR 基地址 |
| `DST_BASE_ADDR` | `0x008` | 32bit | `RW` | 目标图 DDR 基地址 |
| `SRC_STRIDE` | `0x00C` | 32bit | `RW` | 源图每行步长，单位字节 |
| `DST_STRIDE` | `0x010` | 32bit | `RW` | 目标图每行步长，单位字节 |
| `SRC_SIZE` | `0x014` | 32bit | `RW` | 源图宽高配置 |
| `DST_SIZE` | `0x018` | 32bit | `RW` | 目标图宽高配置 |
| `STATUS` | `0x01C` | 32bit | `RO + W1C` | 总体状态、sticky 状态、子模块 busy |

说明：
- `RO` = 只读。
- `RW` = 可读可写。
- `W1C` = Write 1 to Clear，写 1 清零。

---

## 寄存器逐项说明

## 1. `CTRL` 寄存器

### 基本信息
- 名称：`CTRL`
- 偏移地址：`0x000`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[0]` | `start` | `WO/读回固定0` | 写 1 启动一次任务 |
| `[1]` | `irq_en` | `RW` | 中断使能 |
| `[31:2]` | `reserved` | 保留 | 当前未使用，建议写 0 |

### 编码规则

#### `[0] start`
- 写 `1`：当 `ctrl_busy=0` 时，产生一个单拍 `start_pulse_reg`，启动一次完整任务。
- 写 `0`：无效果。
- 读：固定读回 `0`，因为它不是状态位，而是“触发脉冲”。

#### `[1] irq_en`
- `0`：关闭中断输出。
- `1`：打开中断输出。

### 写入行为细节
- 只有 `WSTRB[0]=1` 时，`start` 和 `irq_en` 所在的低字节才会被更新。
- 当写 `start=1` 且当前 `ctrl_busy=0` 时：
  - 产生启动脉冲；
  - 同时清零 `done_sticky_reg`；
  - 同时清零 `error_sticky_reg`。

### 典型写法

#### 只开中断，不启动
```text
地址 0x000 写入 0x00000002
```

#### 启动任务并同时开中断
```text
地址 0x000 写入 0x00000003
```

---

## 2. `SRC_BASE_ADDR` 寄存器

### 基本信息
- 名称：`SRC_BASE_ADDR`
- 偏移地址：`0x004`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[31:0]` | `src_base_addr` | `RW` | 源图像在 DDR 中的基地址 |

### 编码规则
- 按 32bit 无符号地址解释。
- 单位是字节地址，不是 word 地址。
- 会送给 `scaler_ctrl`，由它进一步生成每一行的读取地址。

### 写入行为细节
- 支持按字节写入，`WSTRB[3:0]` 分别控制 `[31:24] [23:16] [15:8] [7:0]`。

---

## 3. `DST_BASE_ADDR` 寄存器

### 基本信息
- 名称：`DST_BASE_ADDR`
- 偏移地址：`0x008`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[31:0]` | `dst_base_addr` | `RW` | 目标图像在 DDR 中的基地址 |

### 编码规则
- 按 32bit 无符号地址解释。
- 单位是字节地址。
- 会送给 `scaler_ctrl`，用于计算每条输出行的写回地址。

### 写入行为细节
- 同样支持 `WSTRB` 按字节写。

---

## 4. `SRC_STRIDE` 寄存器

### 基本信息
- 名称：`SRC_STRIDE`
- 偏移地址：`0x00C`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[31:0]` | `src_stride` | `RW` | 源图每行步长 |

### 编码规则
- 单位是字节。
- 含义是“从当前行起始地址跳到下一行起始地址，需要增加多少字节”。
- 常见情况下，若源图为单字节灰度图且行内无填充，则：
  - `src_stride = src_w`

### 注意
- `src_stride` 不要求一定等于 `src_w`，允许大于宽度，用于处理有行对齐填充的图像缓存布局。

---

## 5. `DST_STRIDE` 寄存器

### 基本信息
- 名称：`DST_STRIDE`
- 偏移地址：`0x010`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[31:0]` | `dst_stride` | `RW` | 目标图每行步长 |

### 编码规则
- 单位是字节。
- 含义是“从当前输出行起始地址跳到下一输出行起始地址，需要增加多少字节”。
- 对 8bit 灰度单通道目标图，如果没有对齐填充，通常：
  - `dst_stride = dst_w`

---

## 6. `SRC_SIZE` 寄存器

### 基本信息
- 名称：`SRC_SIZE`
- 偏移地址：`0x014`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[15:0]` | `src_w` | `RW` | 源图宽度 |
| `[31:16]` | `src_h` | `RW` | 源图高度 |

### 编码规则
- `src_w`：单位为像素。
- `src_h`：单位为行。
- 采用“低 16 位放宽，高 16 位放高”的编码方式：

```text
SRC_SIZE[15:0]   = src_w
SRC_SIZE[31:16]  = src_h
```

### 写入行为细节
- `WSTRB[0]` 控制 `src_w[7:0]`
- `WSTRB[1]` 控制 `src_w[15:8]`
- `WSTRB[2]` 控制 `src_h[7:0]`
- `WSTRB[3]` 控制 `src_h[15:8]`

### 示例
如果：
- `src_w = 640 = 0x0280`
- `src_h = 480 = 0x01E0`

则应写入：
```text
SRC_SIZE = 0x01E00280
```

---

## 7. `DST_SIZE` 寄存器

### 基本信息
- 名称：`DST_SIZE`
- 偏移地址：`0x018`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[15:0]` | `dst_w` | `RW` | 目标图宽度 |
| `[31:16]` | `dst_h` | `RW` | 目标图高度 |

### 编码规则
- `dst_w`：单位为像素。
- `dst_h`：单位为行。
- 编码方式与 `SRC_SIZE` 相同：

```text
DST_SIZE[15:0]   = dst_w
DST_SIZE[31:16]  = dst_h
```

### 写入行为细节
- `WSTRB[0]` 控制 `dst_w[7:0]`
- `WSTRB[1]` 控制 `dst_w[15:8]`
- `WSTRB[2]` 控制 `dst_h[7:0]`
- `WSTRB[3]` 控制 `dst_h[15:8]`

### 示例
如果：
- `dst_w = 320 = 0x0140`
- `dst_h = 240 = 0x00F0`

则应写入：
```text
DST_SIZE = 0x00F00140
```

---

## 8. `STATUS` 寄存器

### 基本信息
- 名称：`STATUS`
- 偏移地址：`0x01C`
- 复位值：`0x00000000`

### 位定义

| 位段 | 名称 | 访问属性 | 说明 |
| --- | --- | --- | --- |
| `[0]` | `ctrl_busy` | `RO` | 整体控制器忙 |
| `[1]` | `done_sticky` | `RO + W1C` | 任务完成 sticky 位 |
| `[2]` | `error_sticky` | `RO + W1C` | 任务错误 sticky 位 |
| `[7:3]` | `reserved` | 保留 | 当前读回 0 |
| `[8]` | `read_busy` | `RO` | 读引擎忙 |
| `[9]` | `write_busy` | `RO` | 写引擎忙 |
| `[31:10]` | `reserved` | 保留 | 当前读回 0 |

### 编码规则

#### `[0] ctrl_busy`
- `0`：整体控制器空闲
- `1`：整体任务正在运行

#### `[1] done_sticky`
- 当 `ctrl_done` 出现时自动置 1。
- 启动新任务时自动清 0。
- 向 `STATUS` 寄存器写入 bit1=1 时清 0。

#### `[2] error_sticky`
- 当 `ctrl_error` 出现时自动置 1。
- 启动新任务时自动清 0。
- 向 `STATUS` 寄存器写入 bit2=1 时清 0。

#### `[8] read_busy`
- `0`：DDR 读引擎空闲
- `1`：DDR 读引擎正在工作

#### `[9] write_busy`
- `0`：DDR 写引擎空闲
- `1`：DDR 写引擎正在工作

### 写入行为细节
只有最低字节的 bit1 和 bit2 有清零作用：

```text
写 STATUS:
- bit1 = 1 -> 清 done_sticky
- bit2 = 1 -> 清 error_sticky
```

其它位写入没有实际效果。

### 示例

#### 清除 done sticky
```text
地址 0x01C 写入 0x00000002
```

#### 清除 error sticky
```text
地址 0x01C 写入 0x00000004
```

#### 同时清除 done 和 error sticky
```text
地址 0x01C 写入 0x00000006
```

---

## 读写访问规则补充

## 1. 无效地址访问

### 写无效地址
- 返回 `SLVERR`

### 读无效地址
- 返回 `SLVERR`
- `RDATA` 为 0

---

## 2. `WSTRB` 行为

所有可写寄存器都支持 AXI-Lite 按字节写。

也就是说：
- `WSTRB[0]` 对应 `WDATA[7:0]`
- `WSTRB[1]` 对应 `WDATA[15:8]`
- `WSTRB[2]` 对应 `WDATA[23:16]`
- `WSTRB[3]` 对应 `WDATA[31:24]`

只有对应 `WSTRB` 位置为 1 的字节才会被真正写入寄存器。

---

## 3. 复位后的寄存器状态

复位后以下寄存器全部清零：
- `CTRL.irq_en`
- `SRC_BASE_ADDR`
- `DST_BASE_ADDR`
- `SRC_STRIDE`
- `DST_STRIDE`
- `SRC_SIZE`
- `DST_SIZE`
- `STATUS.done_sticky`
- `STATUS.error_sticky`

因此上电后需要至少完成以下配置：
1. `SRC_BASE_ADDR`
2. `DST_BASE_ADDR`
3. `SRC_STRIDE`
4. `DST_STRIDE`
5. `SRC_SIZE`
6. `DST_SIZE`
7. `CTRL` 中的 `irq_en`（如果需要）
8. `CTRL.start`

---

## 典型配置顺序

建议的软件侧配置顺序如下：

1. 写 `SRC_BASE_ADDR`
2. 写 `DST_BASE_ADDR`
3. 写 `SRC_STRIDE`
4. 写 `DST_STRIDE`
5. 写 `SRC_SIZE`
6. 写 `DST_SIZE`
7. 如有旧任务残留，写 `STATUS` 清 sticky 位
8. 写 `CTRL`，设置 `irq_en`
9. 写 `CTRL.start=1` 启动任务
10. 轮询 `STATUS` 或等待 `irq`

---

## 示例：640x480 缩放到 320x240

假设：
- `src_base_addr = 0x10000000`
- `dst_base_addr = 0x11000000`
- `src_stride = 640`
- `dst_stride = 320`
- `src_w = 640`
- `src_h = 480`
- `dst_w = 320`
- `dst_h = 240`

则典型寄存器写入值为：

| 寄存器 | 地址 | 写入值 |
| --- | --- | --- |
| `SRC_BASE_ADDR` | `0x004` | `0x10000000` |
| `DST_BASE_ADDR` | `0x008` | `0x11000000` |
| `SRC_STRIDE` | `0x00C` | `0x00000280` |
| `DST_STRIDE` | `0x010` | `0x00000140` |
| `SRC_SIZE` | `0x014` | `0x01E00280` |
| `DST_SIZE` | `0x018` | `0x00F00140` |
| `CTRL` | `0x000` | `0x00000003` |

其中最后一步 `CTRL=0x3` 的含义是：
- bit0=`1`：启动
- bit1=`1`：使能中断

---

## 当前限制
- 当前实现要求 `AXIL_DATA_W = 32`
- 当前实现要求 `AXI_DATA_W = 32`
- 当前实现要求 `PIXEL_W = 8`
- 寄存器里的宽高字段当前只实现为 16bit
- `core_clk` 端口存在，但当前内部数据通路主体运行在 `axi_clk`
