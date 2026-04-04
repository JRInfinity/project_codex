# check-sim-doc-sync 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\tools\check-sim-doc-sync.ps1`

## 作用
检查 `rtl/sim` 下 testbench 与同名 Markdown 说明文档是否配套且结构完整。

## 检查内容
- `tb_*.sv` 是否有对应 `tb_*.md`
- testbench 头部是否包含同步提醒
- Markdown 是否包含约定关键标记
- 是否存在“只有 md 没有 sv”的孤立文档

## 输出
- 全部通过时打印 `Simulation doc sync check passed.`
- 有问题时打印所有缺失项并返回非零退出码
