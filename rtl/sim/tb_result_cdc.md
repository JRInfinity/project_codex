# tb_result_cdc

## 对应模块

- DUT: `result_cdc`
- Testbench: `tb_result_cdc.sv`
- Version: `v2`

## 模块做什么
`result_cdc` 把一条终态结果事件从 `src_clk` 域传到 `dst_clk` 域。事件内容包含：

- `result_done`
- `result_error`

目标域看到的是单拍 `result_valid_dst` 脉冲。

## 这个 testbench 测了什么
### 1. `done_event`

- 发送 done 事件
- 检查 done 路径的单次事件传递

### 2. `error_event`

- 发送 error 事件
- 检查 error 路径的单次事件传递

### 3. `back_to_back_result`

- 连续发送 `done` 再发送 `error`
- 检查源端 `result_ready_src` 恢复时序
- 检查连续事件不会丢失

## 最近一次仿真结果

- 时间: `2026-04-03`
- 结果: 通过
- 执行方式:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" result_cdc -Clean
```
