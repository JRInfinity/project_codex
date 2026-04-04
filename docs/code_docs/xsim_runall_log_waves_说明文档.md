# xsim_runall_log_waves 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\tools\xsim_runall_log_waves.tcl`

## 作用
供 `xsim` 批处理执行的 TCL 脚本，用于记录波形并运行完整仿真。

## 工作流程
1. 递归记录全部波形对象。
2. 如果外部设置了 `XSIM_VCD_FILE`，则同时打开 VCD 导出。
3. 执行 `run all`。
4. 仿真结束后关闭 VCD 并退出。
