# Rotate Tile Cache Guide

## 目标

这份文档说明当前 `image_geo_top` 里旋转缩放通路的几个关键能力：

- 统一逆映射公式
- 递推式坐标生成
- `src_tile_cache` 分块缓存
- 运行时 prefetch 开关
- cache 统计寄存器读取方法

适用对象：

- 软件驱动联调
- 板上功能验证
- 性能观察与参数对比

## 当前数据通路

当前顶层左侧链路已经从“按行缓存”升级成：

`DDR -> ddr_read_engine -> src_tile_cache -> rotate_core_bilinear -> row_out_buffer -> ddr_write_engine`

其中：

- `rotate_core_bilinear` 负责对目标像素做逆向坐标映射，再从源图连续坐标做 bilinear 采样
- `src_tile_cache` 负责把源图按 tile 缓存起来，避免任意角度访问时频繁碎读 DDR

## 统一映射

当前旋转缩放不是“先缩放再旋转”，也不是“先旋转再缩放”，而是：

1. 对每个输出像素 `(x_d, y_d)` 直接反推出源图连续坐标 `(x_s, y_s)`
2. 在源图四邻域上一次性做 bilinear 插值

这样只有一次重采样，图像质量和结构复杂度都更合适。

## 递推坐标

RTL 没有对每个像素都重新做完整乘法，而是先算好步进：

- 沿目标图 `x` 方向每走一个像素，源坐标加固定步进
- 沿目标图 `y` 方向每换一行，行起点加固定步进

所以核心运行时主要靠加法递推，不是逐像素“傻算”。

## Tile Cache

当前 `src_tile_cache` 的缓存单位是 tile，而不是整行。

这更适合：

- 任意角度旋转
- 斜向访问
- 同一输出行跨多个源行/源列

当前还包含：

- baseline miss/fill/load
- 替换时尽量保护当前请求已命中的 tile
- 轻量级方向感知预取

## AXI-Lite 寄存器

### 基本配置

- `0x000`: `CTRL`
  - bit0: start
  - bit1: irq enable
- `0x004`: `SRC_BASE_ADDR`
- `0x008`: `DST_BASE_ADDR`
- `0x00C`: `SRC_STRIDE`
- `0x010`: `DST_STRIDE`
- `0x014`: `SRC_SIZE`
  - `[15:0]` src_w
  - `[31:16]` src_h
- `0x018`: `DST_SIZE`
  - `[15:0]` dst_w
  - `[31:16]` dst_h
- `0x01C`: `STATUS`
  - bit0: busy
  - bit1: done sticky
  - bit2: error sticky
  - bit8: read busy
  - bit9: write busy

### 旋转参数

- `0x020`: `ROT_SIN_Q16`
- `0x024`: `ROT_COS_Q16`

这两个寄存器使用 Q16 定点格式。

常见值示例：

- `sin(0°) = 0x0000_0000`
- `cos(0°) = 0x0001_0000`
- `sin(90°) = 0x0001_0000`
- `cos(90°) = 0x0000_0000`
- `sin(45°) ≈ 0x0000_B505`
- `cos(45°) ≈ 0x0000_B505`

### Cache 统计与控制

- `0x028`: `CACHE_READ_STARTS`
  - tile cache 发起的 DDR 行读任务总数
- `0x02C`: `CACHE_MISSES`
  - miss 驱动的 tile 填充次数
- `0x030`: `CACHE_PREFETCH_STARTS`
  - 预取驱动的 tile 填充次数
- `0x034`: `CACHE_PREFETCH_HITS`
  - 请求命中已挂起/已准备好的预取结果次数
- `0x038`: `CACHE_CTRL`
  - bit0: `cache_prefetch_en`

## 推荐使用流程

### 功能验证

1. 写入源/目标地址、stride、尺寸
2. 写入 `ROT_SIN_Q16` / `ROT_COS_Q16`
3. 可选写 `0x038[0]` 控制是否打开 prefetch
4. 写 `CTRL.start = 1`
5. 轮询 `STATUS.done` 或等待 `irq`

### 统计观察

任务完成后读取：

- `0x028`
- `0x02C`
- `0x030`
- `0x034`

可用来观察：

- 一次任务发了多少次 DDR 行读取
- miss 大概有多少
- 预取有没有真正启动
- 预取是否真的带来了命中

## 如何比较 Prefetch 开关收益

推荐方法：

1. 固定输入图、输出图、角度、stride、地址
2. 先把 `0x038[0] = 0` 跑一遍
3. 记录 `0x028/0x02C/0x030/0x034`
4. 再把 `0x038[0] = 1` 跑同一遍
5. 再记录一次

重点比较：

- `CACHE_READ_STARTS`
- `CACHE_MISSES`
- `CACHE_PREFETCH_STARTS`
- `CACHE_PREFETCH_HITS`

一般期望是：

- 开预取后，`CACHE_PREFETCH_STARTS` 非零
- 某些访问模式下，`CACHE_PREFETCH_HITS` 非零
- 某些场景下，后续请求等待变少

注意：

- 不是所有旋转角度和访问序列都会明显触发预取收益
- 模块级 `tb_src_tile_cache_prefetch.sv` 已经验证了预取机制本身是生效的
- 顶层是否明显受益，取决于实际访问轨迹

## 当前验证覆盖

当前工程里已经有这些回归：

- `tb_image_geo_top.sv`
  - identity
  - 90° rotation
  - 45° bilinear
  - 跨 tile 顶层回归
  - 统计寄存器读回
- `tb_src_tile_cache.sv`
  - baseline cache miss/fill/replace
- `tb_src_tile_cache_prefetch.sv`
  - prefetch 收益验证

## 当前边界

当前 prefetch 还是轻量级版本：

- 一次只挂一个待预取 tile
- 主要利用相邻 tile 方向局部性
- 还不是完整的多步扫描预取器

如果后面继续提升，优先建议：

- 把 prefetch 扩成行扫描/列扫描的连续预取
- 增加更细的性能计数器
- 在软件侧加入自动 on/off 对比流程
