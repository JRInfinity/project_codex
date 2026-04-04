# tb_async_word_fifo_xpm

## 对应模块

- DUT: `async_word_fifo`
- Testbench: `tb_async_word_fifo_xpm.sv`
- Version: `v1`

## 模块做什么

`async_word_fifo` 是一个异步字宽 FIFO，用于在 `wr_clk` 和 `rd_clk` 两个时钟域之间传递整字数据。它需要保证：

- 基本读写功能正确
- `empty/full` 指示正确
- `almost_full` 阈值行为正确
- 空读时 `underflow` 正确
- 满写时 `overflow` 正确

## 这个 testbench 测了什么

### 1. 复位后空 FIFO 基本状态

检查：

- `empty == 1`
- `full == 0`

目的：

- 验证复位后状态是否干净
- 这是后面所有写入/读取检查的前提

### 2. 三次写入后逐次读出

写入数据：

- `32'h1122_3344`
- `32'h5566_7788`
- `32'h99AA_BBCC`

检查：

- 读出顺序与写入顺序一致
- 每次读出数据与 `expected_mem` 一致
- 全部读完后 FIFO 应回到空状态

目的：

- 验证最基础的数据保持和 FIFO 顺序
- 验证跨时钟域传输后数据没有乱序

### 3. 空 FIFO 继续读，检查 `underflow`

目的：

- 验证异常操作下的错误指示
- 确认空读不会静默失败

### 4. 写到 `almost_full`

检查：

- `almost_full` 最终拉高
- 拉高位置不能早于 `PROG_FULL_THRESH`

目的：

- 验证预警阈值行为
- 这对上游限流逻辑很关键

### 5. 写到 `full` 后继续写，检查 `overflow`

检查：

- FIFO 最终进入 `full`
- 额外写入后出现 `overflow`

目的：

- 验证满写保护
- 覆盖边界容量场景

## 为什么这么设计这些样例

这组样例覆盖的是 FIFO 最核心的五类风险：

- 复位后初始状态错误
- 基本读写顺序错误
- 空读保护缺失
- 几乎写满阈值错误
- 满写保护缺失

它们不是随机堆样例，而是按“正常路径 -> 空边界 -> 满边界 -> 阈值路径”来组织的。

## 最近一次仿真结果

时间：`2026-04-02`

结果：通过

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" async_word_fifo -Clean
```

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" async_word_fifo -Clean
```

关键结果：

- 基本读写样例通过
- `underflow` 样例通过
- `almost_full` 样例通过
- `full/overflow` 样例通过
- 统一仿真脚本可在当前环境下稳定完成该模块仿真

相关输出：

- 日志：`C:\Users\huawei\Desktop\project_codex\sim_out\async_word_fifo\xsim.log`

## 当前结论

- 当前工作区中的 `async_word_fifo` 模块级仿真已经通过
- 这次修复同时处理了两个问题：
- testbench 不再依赖 DUT 内部未公开的 `*_rst_busy` 名字
- 仿真 fallback 改为更稳定的行为级 FIFO 模型，避免旧 fallback 在当前环境下长时间卡住

## 后续维护要求

- 如果调整了 `empty/full/almost_full` 的时序语义，要同步修改本文档
- 如果修复了失败，必须更新“最近一次仿真结果”和“当前结论”
