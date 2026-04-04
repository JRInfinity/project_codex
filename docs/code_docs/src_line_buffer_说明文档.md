# src_line_buffer 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\buffer\src_line_buffer.sv`

## 作用
缓存若干条源图像行，为缩放核心提供随机像素读取。

## 主要能力
- 支持按行装载
- 支持两个独立读端口并发读取
- 支持按 `line_sel + x` 访问指定像素

## 工作流程
1. `load_start` 选定一条行缓存并开始写入。
2. 按输入有效信号顺序写满 `load_pixel_count` 个像素。
3. 读端口在任意时刻可根据请求返回对应像素。

## 注意事项
- 单次只装载一条线。
- `load_pixel_count` 超过 `MAX_SRC_W` 会报错。
