# start-workspace 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\tools\start-workspace.ps1`

## 作用
按配置文件一次性启动 Codex、Chrome、VS Code 和指定文档。

## 输入配置
默认读取：
`C:\Users\huawei\Desktop\project_codex\tools\workday-startup.json`

## 支持内容
- 启动 Codex 桌面应用
- 打开预设网页
- 打开 VS Code 工程或文件
- 打开文档，或交给 VS Code 统一打开

## 注意事项
- `-DryRun` 只打印计划动作，不实际启动程序。
- 如果配置路径、命令路径或目标文件不存在，会直接报错终止。
