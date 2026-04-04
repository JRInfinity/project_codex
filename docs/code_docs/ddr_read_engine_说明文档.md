# ddr_read_engine 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\axi\ddr_read_engine.sv`

## 作用
把“任务跨域 + AXI 突发读 + 异步 FIFO + 像素拆包”串成完整的 DDR 读链路。

## 子模块关系
- `task_cdc`：任务从 core 域跨到 AXI 域
- `axi_burst_reader`：执行 AXI 读突发
- `async_word_fifo`：跨时钟缓存整 word 数据
- `result_cdc`：结果从 AXI 域跨回 core 域
- `pixel_unpacker`：把整 word 拆成像素流

## 工作流程
1. core 域接受 `task_start`，记录地址和字节数。
2. 任务跨域后，AXI 域发起 DDR 读。
3. 返回数据以整 word 形式写入异步 FIFO。
4. core 域按字节偏移和长度限制输出像素流。
5. 像素全部消费后拉起 `task_done`；出错时拉起 `task_error`。

## 注意事项
- 当前要求 `PIXEL_W == 8`。
- `sys_rst` 被两个时钟域共享，适用于启动期统一复位。
