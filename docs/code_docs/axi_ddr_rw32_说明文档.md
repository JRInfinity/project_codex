# axi_ddr_rw32 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\axi_ddr_rw32.sv`

## 作用
对上提供简化的 DDR 读写命令接口，对下转换为 AXI4 主机单次突发访问。

## 核心接口
- 写命令：`wr_start`、`wr_addr`、`wr_beats`、`wr_data`、`wr_data_valid`
- 读命令：`rd_start`、`rd_addr`、`rd_beats`、`rd_data_ready`
- AXI 主口：`AW/W/B/AR/R` 五个通道

## 工作流程
1. 空闲态下接受一笔读或写命令。
2. 写路径先发 `AW`，再逐拍发送 `W`，最后等待 `B`。
3. 读路径先发 `AR`，再逐拍接收 `R`，直到 `RLAST`。
4. 任一时刻只允许读或写其中一路工作。

## 注意事项
- 不支持多命令排队。
- `wr_beats`、`rd_beats` 为 0 时命令不会被接受。
- 总线错误通过 `wr_error`、`rd_error` 上报。
