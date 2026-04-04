# task_cdc 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\axi\task_cdc.sv`

## 作用
在两个时钟域之间安全传递一笔任务。

## 设计方式
- 使用请求/确认双 toggle 握手
- 多比特载荷先在源域锁存，再在目标域读取
- 在收到确认之前，源域不会覆盖上一笔载荷

## 适用场景
- 任务频率不高
- 一次只传一笔载荷
- 比起吞吐更重视 CDC 正确性
