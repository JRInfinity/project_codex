# 仿真说明索引

本目录下每个模块级 testbench 都应有一份同名前缀的说明文档。

当前对应关系：

- `tb_scale_core_nearest.sv` <-> `tb_scale_core_nearest.md`
- `tb_pixel_unpacker.sv` <-> `tb_pixel_unpacker.md`
- `tb_task_cdc.sv` <-> `tb_task_cdc.md`
- `tb_result_cdc.sv` <-> `tb_result_cdc.md`
- `tb_async_word_fifo_xpm.sv` <-> `tb_async_word_fifo_xpm.md`
- `tb_src_line_buffer.sv` <-> `tb_src_line_buffer.md`
- `tb_ddr_read_engine.sv` <-> `tb_ddr_read_engine.md`

维护规则：

- 修改 testbench 的测试样例、检查逻辑、接口假设后，同步更新对应 `.md`
- `.md` 至少包含：模块职责、测试样例、样例设计理由、最近一次仿真结果
- 仿真结果要写清楚是通过还是失败；如果失败，要写明失败点和日志位置
- 新增 testbench 时，必须同时新增对应 `.md`

执行约束：

- 默认使用 `tools/run-module-sim.ps1`
- 默认按 `xvlog -> xelab -> xsim` 分阶段执行
- 默认给 `xsim` 设置短超时
- 超时后先看日志，再决定是否修改 DUT 或 testbench

总原则见：

- `C:\Users\huawei\Desktop\project_codex\PRINCIPLE.md`

状态总表刷新命令：

- `powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\update-module-simulation-table.ps1"`

自动检查命令：

- `powershell -ExecutionPolicy Bypass -File "C:\Users\huawei\Desktop\project_codex\tools\check-sim-doc-sync.ps1"`
