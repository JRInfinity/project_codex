# row_out_buffer 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\buffer\row_out_buffer.sv`

## 作用
缓存一整行输出像素，并在需要写回时顺序重新输出。

## 工作流程
1. `row_start` 启动一行装载。
2. 在 `S_FILL` 状态持续接收输入像素并写入行缓存。
3. 装载完成后进入 `S_READY` 等待输出启动。
4. `out_start` 到来后进入 `S_DRAIN`，逐像素输出该行内容。

## 注意事项
- 行宽超过 `MAX_DST_W` 时会报错。
- 适合和写回模块解耦，使缩放核心与写 DDR 节拍分离。
