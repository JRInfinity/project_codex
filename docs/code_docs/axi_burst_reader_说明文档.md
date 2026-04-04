# axi_burst_reader 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\axi\axi_burst_reader.sv`

## 作用
在 AXI 时钟域执行 DDR 读突发，把返回的整 word 数据推入异步 FIFO。

## 主要能力
- 自动按 beat 宽度对齐起始地址
- 自动切分不跨 4KB 的 AXI INCR 突发
- 限制最大在途 burst 数和在途 beat 数
- 检查 `RRESP`、`RLAST` 和 FIFO 溢出

## 工作流程
1. 接收一笔读命令并计算总共需要读取的 word 数。
2. 根据 4KB 边界、FIFO 空间和最大突发长度决定下一次 `ARLEN`。
3. 每次发出 `AR` 后，在内部队列记录该 burst 剩余 beat 数。
4. 收到 `R` 时更新在途计数并写入 FIFO。
5. 全部完成后上报 done；若响应错误或节拍异常则上报 error。

## 注意事项
- 输入命令接口一次只处理一笔任务。
- 状态输出采用 valid/done/error 三元组形式。
