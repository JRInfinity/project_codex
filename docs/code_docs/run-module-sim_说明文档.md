# run-module-sim 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\tools\run-module-sim.ps1`

## 作用
统一执行模块级仿真，并把日志、波形和结果写入 `sim_out/`。

## 主要参数
- `Target`：目标模块名，默认 `all`
- `Wave`：生成 XSIM 波形数据库
- `GtkWave`：额外导出 VCD
- `Clean`：先清理旧输出目录
- `SimTimeoutSec`：xsim 超时秒数
- `CompileOnly` / `ElabOnly`：只执行到指定阶段

## 工作流程
1. 根据目标名称找到对应 testbench 和源码清单。
2. 调用 `xvlog` 编译。
3. 调用 `xelab` 建立 snapshot。
4. 调用 `xsim` 运行仿真并做超时保护。
5. 扫描日志中的错误关键词并输出摘要。
