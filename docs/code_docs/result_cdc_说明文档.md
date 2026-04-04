# result_cdc 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\axi\result_cdc.sv`

## 作用
在两个时钟域之间传递任务终态事件，例如 done 或 error。

## 特点
- 目标域看到的是单拍脉冲
- 每次只处理一个终态事件
- 通过 toggle 握手避免多比特状态跨域不稳定

## 典型用途
- 把 AXI 域的读引擎结果同步回 core 域
- 把某个计算域的完成事件同步回控制域
