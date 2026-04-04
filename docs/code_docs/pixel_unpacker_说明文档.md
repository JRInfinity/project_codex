# pixel_unpacker 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\core\pixel_unpacker.sv`

## 作用
把 DDR 读回来的整 word 数据拆成逐像素输出流。

## 关键处理
- 首 word 跳过地址偏移对应的无效字节
- 尾 word 根据剩余字节数裁掉无效数据
- 只有当像素被 `out_valid && out_ready` 真正接收后，才算任务完成

## 工作流程
1. `task_start` 初始化剩余字节数和首地址偏移。
2. FIFO 有数据时按 word 装载到内部寄存器。
3. 每次输出一个字节宽像素，并更新剩余字节数。
4. 所有有效字节消费完后输出 `task_done_pulse`。

## 错误来源
- 读引擎显式上报错误
- FIFO 下溢
- 理论应有数据但 FIFO 已空
