# tb_src_line_buffer

## 对应模块

- DUT: `src_line_buffer`
- Testbench: `tb_src_line_buffer.sv`
- Version: `v1`

## 模块做什么

`src_line_buffer` 用于装载若干条源图像行，并提供两个独立读口按行号和横坐标读取像素。

它负责：

- 装载指定行
- 按 `load_pixel_count` 接收像素
- 提供双读口随机访问
- 对非法装载长度给出错误

## 这个 testbench 测了什么

### 1. `basic_load_and_read`

- 装载 1 条 4 像素行
- 从同一行的两个位置并行读取

目的：

- 验证最基础的装载和双读口读数正确性

### 2. `two_line_isolation`

- 分别装载 line0 和 line1
- 同时读取两条不同行

目的：

- 验证多行之间不会串写或串读

### 3. `overflow_count_error`

- 装载长度大于 `MAX_SRC_W`

目的：

- 验证非法配置时进入错误路径

## 为什么这样设计这些样例

这个模块的核心风险是：

- 装载状态机是否正确收数
- 读口是否读到正确行、正确位置
- 不同行之间是否隔离
- 越界长度是否能及时报错

## 最近一次仿真结果

时间：`2026-04-02`

结果：通过

执行方式：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" src_line_buffer -Clean
```

关键结果：

- `basic_load_and_read` 通过
- `two_line_isolation` 通过
- `overflow_count_error` 通过

相关输出：

- 日志：`C:\Users\huawei\Desktop\project_codex\sim_out\src_line_buffer\xsim.log`
