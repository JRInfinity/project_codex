# async_word_fifo 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\buffer\async_word_fifo.sv`

## 作用
在异步双时钟域之间传递整 word 数据。

## 两种实现
- 综合场景：实例化 `xpm_fifo_async`
- 仿真场景：使用 queue 行为模型作为 fallback

## 接口语义
- `full`：FIFO 已满
- `almost_full`：提前满，用于上游回压
- `overflow`：满时继续写
- `empty`：FIFO 为空
- `underflow`：空时继续读

## 注意事项
- 该封装默认保持 FWFT 语义。
- 设计中不做字节裁剪，读写数据宽度保持一致。
