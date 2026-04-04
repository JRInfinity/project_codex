# scale_core_nearest 说明文档

## 文件位置
`C:\Users\huawei\Desktop\project_codex\rtl\core\scale_core_nearest.sv`

## 作用
执行最近邻缩放，根据目标坐标计算源图坐标并输出对应像素。

## 设计特点
- 使用定点步长 `scale_x/scale_y`
- 通过四舍五入得到最近邻源坐标
- 通过源行请求和像素请求与外部缓存系统配合

## 工作流程
1. `start` 时锁存源/目标尺寸并计算横纵缩放步长。
2. 对每个目标像素，先计算当前源 `y` 并请求对应源行。
3. 再根据当前源 `x` 请求像素。
4. 像素返回后经 `pix_valid/pix_ready` 输出。
5. 每完成一行时拉起 `row_done`。

## 注意事项
- 尺寸参数任意一个为 0 会直接报错。
- 超出源图边界时会钳位到最后一个有效坐标。
