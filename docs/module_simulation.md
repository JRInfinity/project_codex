# 模块级仿真入口

统一入口脚本：

`C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1`

工程守则汇总见：

`C:\Users\huawei\Desktop\project_codex\PRINCIPLE.md`

每个 testbench 的说明文档放在：

`C:\Users\huawei\Desktop\project_codex\rtl\sim\`

并与 testbench 同名前缀对应。例如：

- `tb_scale_core_nearest.sv` 对应 `tb_scale_core_nearest.md`
- `tb_pixel_unpacker.sv` 对应 `tb_pixel_unpacker.md`
- `tb_task_cdc.sv` 对应 `tb_task_cdc.md`
- `tb_result_cdc.sv` 对应 `tb_result_cdc.md`
- `tb_async_word_fifo_xpm.sv` 对应 `tb_async_word_fifo_xpm.md`
- `tb_src_line_buffer.sv` 对应 `tb_src_line_buffer.md`
- `tb_ddr_read_engine.sv` 对应 `tb_ddr_read_engine.md`

## 实时状态总表

<!-- STATUS_TABLE_BEGIN -->

说明：

- `模块完成` 只表示对应 RTL 文件确实存在于 `rtl/`。
- `仿真文件` 只有在 `tb_*.sv` 和对应 `.md` 都真实存在时才记为有效。
- `已仿真` 只有在对应 `sim_out/<target>/xsim.log` 真实存在时才填写版本。
- `仿真结果` 只根据当前工作区日志中的真实结果填写。
- 缺少证据时，保持保守显示为 `无`、`未验证` 或 `未知`。
| 模块 | 模块完成 | 仿真文件 | 已仿真 | 仿真结果 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `image_geo_top` | 是 | `tb_image_geo_top.sv (v1)` | `v1` | 通过 | 顶层 Stage A 联调仿真 |
| `axi_burst_reader` | 是 | `无` | `无` | 未验证 | 还没有独立模块级 testbench |
| `ddr_read_engine` | 是 | `tb_ddr_read_engine.sv (版本未知)` | `版本未知` | 通过 | 已完成模块级联调 |
| `task_cdc` | 是 | `tb_task_cdc.sv (v2)` | `v2` | 通过 | CDC task 通道已验证 |
| `result_cdc` | 是 | `tb_result_cdc.sv (v2)` | `v2` | 通过 | CDC result 通道已验证 |
| `async_word_fifo` | 是 | `tb_async_word_fifo_xpm.sv (v1)` | `v1` | 通过 | 仿真 fallback 已修复并验证 |
| `src_line_buffer` | 是 | `tb_src_line_buffer.sv (v1)` | `v1` | 通过 | 双读口和错误路径已验证 |
| `pixel_unpacker` | 是 | `tb_pixel_unpacker.sv (v1)` | `v1` | 通过 | 拆包与错误处理已验证 |
| `scale_core_nearest` | 是 | `tb_scale_core_nearest.sv (v1)` | `v1` | 通过 | 最近邻核心已验证 |
<!-- STATUS_TABLE_END -->

## 当前支持的模块

- `scale_core_nearest`
- `pixel_unpacker`
- `task_cdc`
- `result_cdc`
- `async_word_fifo`
- `src_line_buffer`
- `ddr_read_engine`
- `all`

## 默认执行策略

脚本现在默认采用以下策略：

- 先 `xvlog`
- 再 `xelab`
- 最后单独 `xsim`
- `xsim` 默认超时为 `20` 秒
- 一旦超时，立即停止并保留日志

这样做是为了避免仿真卡住时长时间盲等。

## 文档同步检查

自动检查脚本：

`C:\Users\huawei\Desktop\project_codex\tools\check-sim-doc-sync.ps1`

状态表刷新脚本：

`C:\Users\huawei\Desktop\project_codex\tools\update-module-simulation-table.ps1`

它会检查：

- `rtl/sim` 下每个 `tb_*.sv` 是否都有同名前缀 `.md`
- 每个 `tb_*.md` 是否都有对应的 `.sv`
- testbench 头部是否包含同步提醒注释
- `.md` 是否包含最基本的说明标记

执行命令：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\check-sim-doc-sync.ps1"
```

刷新状态总表：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\update-module-simulation-table.ps1"
```

## 常用命令

只跑最近邻核：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" scale_core_nearest
```

跑最近邻核并导出波形：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" scale_core_nearest -Wave
```

跑最近邻核并导出给 `gtkwave` 的 `VCD`：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" scale_core_nearest -GtkWave
```

一口气跑全部模块级仿真：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" all
```

重建单个目标输出目录后再跑：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" ddr_read_engine -Clean
```

只编译，不展开不运行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" async_word_fifo -CompileOnly
```

编译并展开，但不运行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" async_word_fifo -ElabOnly
```

把单次仿真超时改成 8 秒：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" async_word_fifo -SimTimeoutSec 8
```

## 输出位置

每个目标的日志和波形都放在：

`C:\Users\huawei\Desktop\project_codex\sim_out\<target>\`

例如最近邻核的波形数据库：

`C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\tb_scale_core_nearest.wdb`

例如最近邻核给 `gtkwave` 使用的波形文件：

`C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\tb_scale_core_nearest.vcd`

## 看波形

先导出 `.wdb`：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" scale_core_nearest -Wave
```

然后在 XSIM GUI 中打开对应 snapshot：

```powershell
xsim "tb_scale_core_nearest_auto" -gui
```

波形数据库文件路径：

`C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\tb_scale_core_nearest.wdb`

## 用 GTKWave 看波形

先导出 `VCD`：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1" scale_core_nearest -GtkWave
```

然后打开：

```powershell
gtkwave "C:\Users\huawei\Desktop\project_codex\sim_out\scale_core_nearest\tb_scale_core_nearest.vcd"
```

