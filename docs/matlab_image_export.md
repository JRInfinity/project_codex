# MATLAB 灰度图导出说明

## 推荐格式

如果图像最终要写入 FPGA 的 **PS DDR**，推荐主格式使用：

- `*.bin` 原始二进制

原因：

- 每个像素就是 `1 byte`
- 灰度值范围正好是 `0-255`
- 不带文件头，不带压缩，不需要解析图片协议
- PS 侧可以直接按字节搬运到 DDR
- PL 侧读取时可直接按地址顺序取像素

## 内存布局

推荐采用 **row-major** 行优先布局：

```text
addr_base + y * width + x
```

其中：

- `x` 范围：`0 ~ width-1`
- `y` 范围：`0 ~ height-1`

也就是：

- 先存第 0 行全部像素
- 再存第 1 行全部像素
- 依次类推

## 与当前 RTL 的关系

当前工程中：

- 像素宽度是 `8 bit`
- AXI 读数据宽度是 `32 bit`

因此 DDR 中最自然的组织方式就是：

- 每像素 `1 byte`
- 连续 4 个像素会被 AXI 一次读成一个 `32-bit word`

例如 DDR 连续 4 字节：

```text
b0 b1 b2 b3
```

被 AXI 读入后，会组成一个 32-bit 数据拍；`pixel_unpacker` 再按字节顺序拆出像素。

## 不同格式用途

- `bin`
  - 给 PS DDR/裸内存搬运使用
- `png`
  - 给人眼检查图像内容是否正确
- `coe`
  - 仅在你想把图像预初始化到 BRAM/ROM 时有用

如果目标是 **PS DDR**，通常只需要重点使用 `bin`。

## 图案选项

推荐优先用下面几类：

- `horizontal_gradient`
  - 适合检查左右方向、行列是否写反、插值和缩放是否平滑
- `vertical_gradient`
  - 适合检查上下方向、行列是否写反
- `checkerboard`
  - 适合检查地址错位、丢字节、跨行跳变、缓存拼接错误
- `noisy_gradient`
  - 在梯度基础上加随机扰动，同时兼顾人眼可读性和随机性
- `random_blocks`
  - 适合看块状搬运、tile、burst 对齐是否正确
- `impulse_points`
  - 稀疏随机亮点，适合定位地址偏移、单点丢失、重复读取
- `rings`
  - 适合看旋转、缩放后几何形变是否异常
- `diagonal_ramp`
  - 适合看 x/y 同时参与时的坐标映射是否正确
- `random`
  - 随机性最强，但不方便直接人眼判断几何关系

## 人眼检查图

脚本现在会额外导出一张：

- `*_preview.png`

它会在图像右侧附带一个灰度标尺：

- 顶部接近 `255`
- 底部接近 `0`

这样你在看图时可以直接知道亮度值对应关系。

## MATLAB 脚本

脚本位置：

- [generate_gray_image.m](/C:/Users/huawei/Desktop/project_codex/matlab/generate_gray_image.m)

示例：

```matlab
[img, meta] = generate_gray_image(640, 480, "horizontal_gradient", "out/test_640x480");
```

输出文件：

- `out/test_640x480.png`
- `out/test_640x480_preview.png`
- `out/test_640x480.bin`
- `out/test_640x480.coe`
- `out/test_640x480_meta.txt`
