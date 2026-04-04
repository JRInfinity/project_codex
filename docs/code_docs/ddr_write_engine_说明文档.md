# ddr_write_engine 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\axi\ddr_write_engine.sv`

## 作用
把逐字节输入数据打包成 AXI 写数据，按不跨 4KB 的突发规则写回 DDR。

## 主要能力
- 自动处理起始地址未对齐情况
- 自动生成 `WSTRB`
- 自动切分突发并执行 `AW/W/B` 三通道握手

## 工作流程
1. 接收写任务起始地址和总字节数。
2. 计算本轮突发的对齐地址、word 数和有效字节数。
3. 在 `S_COLLECT` 状态逐字节收集输入数据。
4. 在 `S_WDATA` 状态把当前打包好的一个 word 送上 AXI。
5. 等待 `B` 响应后进入下一轮突发或结束。

## 注意事项
- 当前输入粒度默认是 8bit 像素。
- `write_done` 只在成功结束时拉高单拍。
