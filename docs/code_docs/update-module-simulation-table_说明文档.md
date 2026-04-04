# update-module-simulation-table 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\tools\update-module-simulation-table.ps1`

## 作用
根据真实 RTL、testbench、Markdown 和仿真日志状态，刷新 `docs/module_simulation.md` 里的模块状态表。

## 工作流程
1. 读取每个模块的规则定义。
2. 检查 RTL 文件、testbench 文件、说明文档是否存在。
3. 从 Markdown 里提取 `Version`。
4. 从 `sim_out/<target>/xsim.log` 判定仿真结果。
5. 只替换状态表锚点之间的文本。

## 注意事项
- 结果完全依赖当前工作区现有日志，不会主动重新跑仿真。
- 文档中的表格锚点注释必须存在。
