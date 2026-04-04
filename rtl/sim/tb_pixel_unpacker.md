# tb_pixel_unpacker

## 对应模块

- DUT: `pixel_unpacker`
- Testbench: `tb_pixel_unpacker.sv`
- Version: `v2`

## 模块做什么
`pixel_unpacker` 在核心时钟域内从整字 FIFO 中取出 `DATA_W` 宽数据，按照任务起始地址偏移和任务总字节数，把有效字节拆成连续像素流输出。

它负责：

- 处理首字非对齐偏移
- 处理尾字部分有效字节
- 在 `pixel_ready` 背压下保持输出
- 在 reader 错误、FIFO 下溢或“reader 已完成但仍缺数据”时进入错误路径

## 这个 testbench 测了什么
### 1. `aligned_full_words`

- 起始地址对齐
- 总长度为 8 字节
- 两个完整 32bit 字

目的：
- 验证最基础的整字拆包顺序
- 检查字节输出顺序是否为 little-endian byte lane 顺序

### 2. `unaligned_partial`

- 起始地址偏移为 1
- 总长度为 5 字节

目的：
- 验证首字偏移处理
- 验证跨字后尾部裁剪逻辑

### 3. `tail_three_bytes`

- 任务长度只有 3 字节
- 只消费一个 32bit 字中的前 3 个字节

目的：
- 验证最后一个字并非总是整字输出
- 检查尾部裁剪逻辑在短包场景下是否正确

### 4. `reader_done_without_data`

- reader 报告完成，但 FIFO 中没有足够数据

目的：
- 验证“上游说完成，但实际数据不够”时能进入错误路径

### 5. `reader_error_event`

- 显式注入 `reader_error_evt`

目的：
- 验证 reader 错误能够传递到 unpacker 错误路径

### 6. `fifo_underflow_error`

- 显式注入 `fifo_underflow`

目的：
- 验证 FIFO 下溢时 `task_error_flag/task_error_pulse` 行为

## 检查方式
testbench 通过队列模拟一个带 FWFT 语义的输入 FIFO：

- `fifo_rd_data` 始终指向队首字
- `fifo_rd_en` 拉高时弹出一个字

输出侧逐字节检查：

- 每个 `pixel_valid && pixel_ready` 的字节都与期望队列比较
- 完成场景要求输出总数匹配且最终走 `task_done_pulse`
- 错误场景要求最终走 `task_error_pulse`

## 最近一次仿真结果

- 时间：`2026-04-03`
- 结果：通过
- 执行方式：

```powershell
xvlog -sv rtl/core/pixel_unpacker.sv rtl/sim/tb_pixel_unpacker.sv --log sim_out/pixel_unpacker/xvlog_pixelapi.log
xelab tb_pixel_unpacker -s tb_pixel_unpacker_pixelapi --timescale 1ns/1ps --log sim_out/pixel_unpacker/xelab_pixelapi.log
xsim tb_pixel_unpacker_pixelapi --log sim_out/pixel_unpacker/xsim_pixelapi.log --onfinish quit --runall
```
