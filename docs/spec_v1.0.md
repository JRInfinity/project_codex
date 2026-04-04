# 📘《图像缩放旋转 FPGA 项目规范说明书 v1.0》

------

# 1. 项目概述

## 1.1 项目名称

- 实时图像缩放旋转加速器设计研究
- Vivado工程名：image_scaler_rotate

## 1.2 平台

- FPGA：PYNQ-Z2
- 主频：100MHz
- 存储：PS DDR3
- 工具链：Vivado + SystemVerilog

## 1.3 功能目标

实现一个**可扩展图像缩放硬件平台，拓展功能为同时支持旋转**：

- 输入图像：最大 `7200 × 7200`，灰度图（1 byte/pixel）
- 输出图像：最大 `600 × 600`
- 图像旋转范围：0-90度
- 输入/输出像素均在 DDR，即原图存放在DDR中，最后将处理好的图像再放回DDR中。DDR在板子的PS部分
- 支持三种缩放算法：最邻近，双线性，双三次

------

## 1.4 算法支持规划

| 阶段    | 算法               |
| ------- | ------------------ |
| Phase 1 | 最近邻（Nearest）  |
| Phase 2 | 双线性（Bilinear） |
| Phase 3 | 双三次（Bicubic）  |

------

# 2. 系统架构

## 2.1 总体架构

```
DDR (PS)
   ↓
AXI Read
   ↓
ddr_line_reader
   ↓
line_buffer
   ↓
scale_core_select
   ├── nearest
   ├── bilinear
   └── bicubic
   ↓
row_buffer
   ↓
AXI Write
   ↓
DDR
```

------

## 2.2 分层原则

### 平台层（Platform）

负责：

- AXI读写
- 控制调度
- buffer管理

### 算法层（Core）

负责：

- 像素计算
- 插值

👉 **强制规则：**

```
算法模块禁止直接访问 AXI
AXI模块禁止实现算法
```

------

# 3. 目录结构规范

```
rtl/
├── top/          # 顶层
├── ctrl/         # 控制器
├── axi/          # DDR读写模块
├── buffer/       # line buffer / FIFO
├── core/         # 算法核
├── writeback/    # DDR写回
└── common/       # 公共模块
```

------

# 4. 命名规范

## 4.1 模块命名

统一：

```
image_scaler_top
ddr_line_reader
ddr_row_writer
scale_core_nearest
scale_core_bilinear
scale_core_bicubic
```

禁止：

```
test1 / tmp / final / my_*
```

------

## 4.2 信号命名

| 类型     | 后缀                 |
| -------- | -------------------- |
| 寄存器   | `_reg`               |
| next状态 | `_next`              |
| 握手     | `_valid/_ready`      |
| 控制     | `_start/_done/_busy` |
| 地址     | `_addr`              |
| 数据     | `_data`              |

------

## 4.3 参数命名

全部大写：

```
DATA_W
ADDR_W
BURST_MAX_LEN
MAX_SRC_W
```

------

# 5. RTL 编码规范

## 5.1 基本规则

- 使用 **SystemVerilog**
- 禁止使用传统 `always`
- 强制：

```
always_ff    // 时序逻辑
always_comb  // 组合逻辑
```

SystemVerilog 专门引入这两种结构来区分时序和组合逻辑，可避免错误推断和隐式锁存器问题 

------

## 5.2 赋值规则

| 类型 | 赋值 |
| ---- | ---- |
| 时序 | `<=` |
| 组合 | `=`  |

禁止混用（Vivado 也明确不推荐） 

------

## 5.3 always 规则

- `always_ff`：
  - 只能有一个时钟边沿
  - 只能非阻塞赋值
- `always_comb`：
  - 自动敏感列表
  - 必须给默认值

这些规则是 SystemVerilog 提供的强约束机制，用来避免设计错误 

------

## 5.4 reset 规范

- 默认使用 **同步复位**
- 不对大数组做 reset（如 line buffer）
- reset 只用于关键寄存器

------

## 5.5 FSM 规范

统一格式：

```
typedef enum logic [2:0] {
    S_IDLE,
    S_LOAD,
    S_RUN,
    S_DONE
} state_t;
```

------

# 6. AXI 规范

## 6.1 接口统一

全部使用：

```
taxi_axi_if
```

------

## 6.2 AXI 使用规则

- burst 类型：INCR
- 不允许跨 4KB 边界
- 必须检查：

```
RRESP
BRESP
RLAST
WLAST
```

------

## 6.3 模块职责

| 模块            | 职责  |
| --------------- | ----- |
| ddr_line_reader | DDR读 |
| ddr_row_writer  | DDR写 |
| scale_core_*    | 算法  |
| scaler_ctrl     | 调度  |

------

# 7. Buffer 设计规范

## 7.1 总原则

```
输入整帧 → DDR
输出整帧 → DDR
PL只做局部缓存
```

------

## 7.2 line buffer 规则

| 算法   | 行数 |
| ------ | ---- |
| 最近邻 | 1    |
| 双线性 | 2    |
| 双三次 | 4    |

------

## 7.3 存储实现

优先级：

1. 推断 BRAM
2. XPM
3. vendor primitive

------

# 8. 时钟 & CDC 规范

## 8.1 时钟

- 初期：单时钟域
- 后期：多时钟域必须显式 CDC

------

## 8.2 CDC 规则

禁止：

```
直接跨时钟传多bit信号
```

必须：

- 双触发同步（单bit）
- FIFO（多bit）
- XPM CDC

------

# 9. 算法接口规范

## 9.1 scale_mode 定义

```
localparam SCALE_NEAREST  = 0;
localparam SCALE_BILINEAR = 1;
localparam SCALE_BICUBIC  = 2;
```

------

## 9.2 算法核统一接口

输入：

```
start
src_w / src_h
dst_w / dst_h
y_out
line_buffer
```

输出：

```
pix_valid
pix_ready
pix_data
row_done
done
error
```

------

## 9.3 强制解耦

```
算法核 = 纯计算
平台层 = 数据搬运
```

------

# 10. 仿真规范

## 10.1 必须有 testbench

必须覆盖：

- ddr_line_reader
- scale_core_nearest
- ddr_row_writer

------

## 10.2 覆盖场景

- 正常路径
- 边界尺寸
- burst 分段
- 4KB 边界
- RLAST 错误
- RESP 错误

------

# 11. Codex 协作规范（重点）

## 11.1 提问模板（必须使用）

```
模块：
职责：
输入：
输出：
约束：
状态机：
不负责：
验收标准：
```

------

## 11.2 Codex 输出要求

必须按顺序：

1. 模块说明
2. 状态机设计
3. 接口定义
4. 完整代码
5. 注意事项

------

## 11.3 开发规则

禁止：

```
一次生成整个系统
```

必须：

```
一次只做一个模块
```

------

# 12. 当前开发阶段定义（v1.0）

当前版本目标：

- ⏳ DDR line reader
- ⏳ 最近邻算法核
- ⏳ DDR row writer
- ⏳ 顶层联调

------

# 13. 核心设计原则（必须遵守）

1. 顶层必须算法无关
2. AXI 与算法必须解耦
3. 输入数据永远不进整帧 BRAM
4. 先正确，再优化
5. 先模块仿真，再系统集成

------

# 14.版本记录

v1.0 ChatGPT自动生成

v2.0 用户自己在v1.0的版本基础上进行合理修改

# ✅ 结语（给 Codex）

本项目为**工程级 FPGA 设计**，要求：

- 可扩展
- 可维护
- 可综合
- 可验证

所有实现必须严格遵守本规范。