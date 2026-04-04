# tb_task_cdc

## 对应模块

- DUT: `task_cdc`
- Testbench: `tb_task_cdc.sv`
- Version: `v2`

## 模块做什么
`task_cdc` 用 req/ack toggle 握手机制，把一条 `task_addr + task_byte_count` 任务从 `src_clk` 域安全传到 `dst_clk` 域，避免多 bit 负载裸跨时钟域。

## 这个 testbench 测了什么
### 1. `single_transfer`

- 单条任务跨时钟域传输
- 检查目标域收到的地址和字节数正确

### 2. `dst_stall`

- 目标域暂时不 ready
- 检查 `task_valid_dst` 和 payload 在等待期间保持稳定

### 3. `back_to_back`

- 第一条任务完成后立即发送第二条
- 检查源端 `task_ready_src` 会在 ack 返回后恢复
- 检查连续任务不会丢失或串包

## 最近一次仿真结果

- 时间: `2026-04-03`
- 结果: 通过
- 执行方式:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" task_cdc -Clean
```
