# 时序优化记录

本文档按轮次记录 `image_geo_top` 近期 RTL 时序优化过程，重点记录：
- 改了什么
- 解决了哪一类热点
- 时序改善到什么程度
- 是否引入功能回归

后续每继续做一轮时序优化，统一在本文档末尾追加新条目。

## 记录规则

1. 每一轮都记录“目标热点”“RTL改动”“验证结果”“时序变化”。
2. 若某次尝试导致功能回归，必须记录并注明已回退。
3. 时序数值以当轮 Vivado implementation 报告或用户截图为准，允许写近似值。
4. 若同一热点连续优化多轮，保留每一轮的独立记录，便于回看哪一刀有效。

## 当前结论

- 工程已经从“几十纳秒级严重违例”收敛到“2ns 左右收尾阶段”。
- 当前主热点已经高度集中在 `core_clk` 域 [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 的：
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`
- `axi_clk` 域热点已从主矛盾降为次矛盾，仍需关注，但不再是最差路径来源。

## 轮次记录

### Round 1

目标热点：
- `rotate_core_bilinear` 初始化阶段从配置量一路推到 `step_* / row0_* / cur_*`
- 典型违例量级约 `-90ns ~ -96ns`

RTL改动：
- 将 `rotate_core_bilinear` 的启动初始化从“一拍大组合”拆成多状态初始化。
- 初步把 bilinear 混合链从“同拍直出”拆成多拍。

效果：
- 最差违例从约 `-96ns` 降到约 `-72ns`

备注：
- 证明方向正确，但说明“只加状态、不拆组合锥”还不够。

### Round 2

目标热点：
- `rotate_core_bilinear` 内大 `always_comb` 仍然把 `scale_* / step_* / row0_*` 综合成共享巨型组合锥

RTL改动：
- 将初始化相关计算从大一统组合块拆成更局部的组合/时序结构。
- 各状态只在本状态真正寄存对应结果。

效果：
- WNS 基本仍在 `-72ns` 量级，但 TNS 开始下降

备注：
- 暴露出真正的核心问题是可变除法，而不是简单的表达式组织方式。

### Round 3

目标热点：
- `scale_x_q16` / `scale_y_q16` 组合除法

RTL改动：
- 把 `scale_x_q16` / `scale_y_q16` 改成顺序 divider。
- 初始化流程改成：
  - `S_DIV_X_INIT/RUN`
  - `S_DIV_Y_INIT/RUN`
  - 后续再计算 center、step、row0

效果：
- WNS 从约 `-72ns` 大幅下降到约 `-12.9ns`

备注：
- 这是一次决定性改动，说明“每帧一次的重算术逻辑”必须顺序化。

### Round 4

目标热点：
- `src_tile_cache` 中 `src_w/src_h` 直接扇出到 fill/sample/mix 相关逻辑
- 典型热点：
  - `fill_row_width_reg`
  - `fill_tile_height_reg`
  - `top_mix_reg`
  - `bot_mix_reg`

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中先锁存配置：
  - `cfg_src_base_addr_reg`
  - `cfg_src_stride_reg`
  - `cfg_src_w_reg`
  - `cfg_src_h_reg`
  - `cfg_prefetch_enable_reg`
- 后续 fill/prefetch/sample 全部改用本地配置寄存器。

效果：
- 热点从跨模块配置直扇出，收敛到缓存内部派生量

### Round 5

目标热点：
- `src_tile_cache` 内部仍反复用 `src_w/src_h` 计算 tile 边界

RTL改动：
- 预先寄存：
  - `cfg_tile_count_x_reg`
  - `cfg_tile_count_y_reg`
  - `cfg_last_tile_width_reg`
  - `cfg_last_tile_height_reg`

效果：
- `src_h/src_w -> fill_*` 类型路径被进一步压缩

### Round 6

目标热点：
- `rotate_core_bilinear` 采样前级和 mix 前级仍直接吃配置量
- `sample_x1/sample_y1` 边界判断与 clamp/index 链条较长

RTL改动：
- 本地锁存配置：
  - `cfg_src_w_reg`
  - `cfg_src_h_reg`
  - `cfg_dst_w_reg`
  - `cfg_dst_h_reg`
  - `cfg_angle_sin_reg`
  - `cfg_angle_cos_reg`
- 新增并寄存：
  - `cfg_src_x_max_q16_reg`
  - `cfg_src_y_max_q16_reg`
  - `cfg_src_x_last_reg`
  - `cfg_src_y_last_reg`
- 将采样前级拆成：
  - `S_CLAMP`
  - `S_INDEX`
  - `S_REQ`

效果：
- `frame_config_cdc -> rotate_core_bilinear` 的直扇出热点明显减少

### Round 7

目标热点：
- `axi_burst_reader` 中 `aligned_start_addr_reg / words_requested_reg / beats_inflight_reg` 直接扇到 AR 发起链

RTL改动：
- 将 `axi_burst_reader` 改成多级 issue pipeline：
  - `issue_seed_*`
  - `issue_gate_*`
  - `issue_plan_*`
  - `issue_calc_*`
  - `issue_prep_*`
  - `issue_commit_*`
- 把 `ar_fire` 后的队列更新、beat 计数更新推迟到 commit 级。
- 新增：
  - `beats_credit_reg`
  - `next_issue_words_to_4kb_reg`
  - `issue_calc_words_to_4kb_reg`

效果：
- AXI 读侧最差路径由十几纳秒级逐步收敛到约 `-3ns ~ -5ns`

### Round 8

目标热点：
- `axi_burst_writer` 的 `words_sent_total_reg -> awlen/awaddr` 链

RTL改动：
- 在 [axi_burst_writer.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_writer.sv) 引入：
  - `next_write_addr_reg`
  - `words_write_remaining_reg`
  - `next_write_words_to_4kb_reg`
  - `aw_prep_addr_reg`
  - `aw_prep_len_reg`
  - `S_AWCFG`

效果：
- 写侧从主要热点退为次热点

### Round 9

目标热点：
- `rotate_core_bilinear` 换行递推
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`

RTL改动：
- 初始将换行递推拆成多级状态：
  - `S_ROW_X_*`
  - `S_ROW_Y_*`
  - `S_ROW_ADV`
- 后续继续引入：
  - `row_x_base_hold_reg`
  - `row_y_base_hold_reg`
  - `row_x_step_hold_reg`
  - `row_y_step_hold_reg`
- 把换行操作数锁存成本地 hold，再分段加法。

效果：
- `core` 域热点开始从 mix/配置边界转移到纯局部 row-base 递推

### Round 10

目标热点：
- `rotate_core_bilinear/sample_* -> top_mix/bot_mix`
- 顶层 `core_pix_* -> row_out_buffer`
- `src_tile_cache -> rotate_core_bilinear` 的高净延迟采样返回

RTL改动：
- 在 [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 新增 mix 本地寄存：
  - `mix_p00_reg..mix_p11_reg`
  - `mix_frac_x_reg`
  - `mix_frac_y_reg`
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 把 sample 路径改成两拍：
  - 第 1 拍锁存命中 slot 和 tile 内偏移
  - 第 2 拍输出 `sample_p00~p11`
- 在 [image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/top/image_geo_top.sv) 顶层增加：
  - sample 响应 staging
  - `rotate_core_bilinear -> row_out_buffer` 输出 staging

效果：
- `sample -> mix` 及 `core -> row_out_buffer` 高净延迟热点显著减轻

### Round 11

目标热点：
- `COORD_W=48` 导致 row-base 递推位宽过宽，carry 链过长

尝试与结果：
- 直接尝试 `COORD_W=32`
  - 功能失败
  - `identity 4x4` 第一个点即报错
- 原因分析：
  - `S_ROW0_X / S_ROW0_Y` 初始化乘法在 32bit 下中间结果溢出
  - 整条坐标链路在当前实现下工程余量不足

最终处理：
- 回退到稳定位宽
- 进一步试探 `COORD_W=40`，功能通过
- 再试探 `COORD_W=36`，顶层回归通过

效果：
- `36bit` 成为当前安全可用的更优位宽点

### Round 12

目标热点：
- `row_x_base/row_y_base` 仍是 `core_clk` 域最后主热点

RTL改动：
- 将原来的 row-base 分段递推继续强化：
  - 5 段链式求和
  - 中间部分和寄存
  - `row_x_next_reg / row_y_next_reg`
- 尝试过 6 段版本

结果：
- 6 段版本功能回归失败：
  - `Transform ref mismatch at dst(0,1): got=38 exp=35`
- 已回退到稳定的 5 段版本

备注：
- 该失败尝试已验证并撤销，不作为当前基线。

### Round 13

目标热点：
- `row_x_next/row_y_next -> row_x_base/row_y_base`

RTL改动：
- 依次引入：
  - `S_ROW_COMMIT`
  - `S_ROW_COMMIT2`
- 将：
  - `row_x_commit_reg`
  - `row_y_commit_reg`
  - `row_x_commit2_reg`
  - `row_y_commit2_reg`
 作为回写前的专用提交寄存器

效果：
- 换行递推求和结果到最终基址寄存器之间又多了两层隔离拍

### Round 14

目标热点：
- `row_x_base_reg / row_y_base_reg / cur_x_reg / cur_y_reg` 的 D 端仍在大状态机中，带有较大的状态 mux

RTL改动：
- 将以上 4 个关键寄存器从主 `always_ff case` 中拆出，分别建立独立 `always_ff`
- 仅在真正需要的状态更新：
  - `S_ROW0_X`
  - `S_ROW0_Y`
  - `S_LOAD0`
  - `S_OUT && pix_fire && !last_col`
  - `S_ROW_COMMIT2`

效果：
- 去掉这些关键寄存器 D 端的大多路选择器
- 当前最新 `core_clk` 热点仍在 row-base 递推，但已经压缩到约 `-2.1ns ~ -2.3ns`

### Round 15

目标热点：
- 在 `COORD_W=36` 的当前稳定基线上，继续进一步压 `row_x_base / row_y_base` 的换行递推链

RTL改动：
- 先尝试更大刀的“等宽 6 段链式求和”：
  - `ROW_SEG_W = COORD_W / 6`
  - 新增 `ROW_SEG5_L`
  - 新增：
    - `S_ROW_X_S5`
    - `S_ROW_Y_S5`
- 目标是把当前 5 段 row-base 递推进一步切细

结果：
- 编译通过
- 顶层回归失败：
  - `Transform ref mismatch at dst(0,1): got=38 exp=35`

处理：
- 已完整回退到稳定的 5 段版本
- 说明“把 36bit row-base 递推继续机械细分成 6 段”在当前实现里不是安全路线

结论：
- 后续继续优化这条链时，应优先考虑：
  - 去掉关键寄存器 D 端大 mux
  - 专用 row-advance datapath
  - 或实现策略收尾
- 不优先再沿“简单多加一段”继续推进

### Round 16

目标热点：
- `core_clk` 域最后主热点持续集中在：
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`

RTL改动：
- 不再继续在主状态机里堆 `S_ROW_X_S* / S_ROW_Y_S*` 细分状态
- 将换行递推改成“同模块内专用 row-advance datapath”：
  - 主状态机在行尾只负责进入 `S_ROW_ADV`
  - 新增独立时序 datapath 维护：
    - `row_adv_busy_reg`
    - `row_adv_done_reg`
    - `row_adv_axis_reg`
    - `row_adv_seg_idx_reg`
    - `row_adv_carry_reg`
  - 行推进操作数继续先锁存到：
    - `row_x_base_hold_reg`
    - `row_y_base_hold_reg`
    - `row_x_step_hold_reg`
    - `row_y_step_hold_reg`
  - row advance 自己在 datapath 中分段完成 `x` 和 `y` 的 5 段链式求和
  - 主状态机只在 `row_adv_done_reg` 拉高后，进入 `S_ROW_COMMIT`

效果：
- 将 row advance 的细节从主 FSM 中抽走
- 主 FSM 不再直接承载 `S_ROW_X_S0 ~ S_ROW_Y_S4` 的状态链
- 后续更利于继续单独针对 row advance datapath 做优化

验证：
- [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 编译通过
- 顶层回归 [tb_image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top.sv) 通过

备注：
- 这一轮属于“结构重构”，主要目的是把最后局部热点从主状态机中解耦出来，方便继续收尾。

### Round 17

目标热点：
- `core_clk` 域仍持续集中在：
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`
- 继续单纯在主状态机内细分状态，收益开始变小

RTL改动：
- 将 row advance 真正重构为“同模块内专用 datapath”
- 主状态机保留：
  - `S_ROW_ADV`
  - `S_ROW_COMMIT`
  - `S_ROW_COMMIT2`
- 原先显式的：
  - `S_ROW_X_S0 ~ S_ROW_X_S4`
  - `S_ROW_Y_S0 ~ S_ROW_Y_S4`
  从主 FSM 中移除
- 新增 row-advance 内部控制寄存器：
  - `row_adv_busy_reg`
  - `row_adv_done_reg`
  - `row_adv_axis_reg`
  - `row_adv_seg_idx_reg`
  - `row_adv_carry_reg`
- row advance 在独立 always_ff 中自行推进分段加法，主 FSM 只在 `row_adv_done_reg` 有效时进入 commit

效果：
- row-base 递推细节彻底从主 FSM 中抽离
- 主 FSM 只保留“发起/等待/提交”级别控制
- 这一结构比继续堆 `S_ROW_X_S* / S_ROW_Y_S*` 更适合后续继续压时序

验证：
- [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 编译通过
- 顶层回归 [tb_image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top.sv) 通过

### Round 18

目标热点：
- 验证 Round 17 的专用 row-advance datapath 对 `core_clk` 最终热点的真实收益
- 观察 `row_y_base_reg -> row_y_base_reg` 是否进一步下降

implementation 结果：
- 用户提供的新 timing 截图显示，`image_geo_core_clk` 最差路径仍集中在：
  - `row_y_base_reg -> row_y_base_reg`
- 当前最差 slack 约为：
  - `-2.578 ns`
- 路径特征：
  - `High Fanout = 2`
  - `Logic Delay ≈ 9.1 ns`
  - `Net Delay ≈ 3.1 ns`

结论：
- Round 17 的 row-advance datapath 重构在“结构清晰度”和后续可维护性上是有价值的
- 但就这一轮 implementation 结果看，**没有继续把最终 WNS 压低**，甚至相对前一版略有回弹
- 说明当前热点已经非常纯粹地收敛成：
  - `row_y_base + step_y_y` 回写链
- 再继续在当前 36bit/5段/专用 datapath 结构上做小改，预期收益已经明显变小

建议：
- 这之后不宜继续只靠局部加拍去“机械切” row-base 链
- 下一步应优先考虑：
  - 更激进的 implementation/phys_opt 收尾
  - 或者重新评估坐标格式/算法，把 row-base 递推本身换成更短的数据路径

### Round 19

目标热点：
- 尝试继续冲掉 `row_y_base / row_x_base` 这条最终递推链
- 验证“整数部分 + 小数部分”两段递推是否能缩短统一 Q16 宽加法链

RTL改动：
- 在 row-advance datapath 内尝试将：
  - `row_x_base + step_x_y`
  - `row_y_base + step_y_y`
  改成
  - `frac + frac`
  - `int + int + carry`
  两步递推

结果：
- 编译通过
- 顶层仿真失败：
  - `Top-level simulation timed out waiting for irq`

处理：
- 已完整回退到此前稳定的专用 row-advance datapath 基线
- 回退后重新验证：
  - [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 编译通过
  - 顶层回归 [tb_image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top.sv) 通过

结论：
- “整数+小数拆分递推”在当前实现里不是低风险的直接优化路线
- 继续在 row-base 算术表达层面做重构，已经开始出现明显功能风险
- 后续若继续冲 0 slack，更建议优先依赖 implementation/phys_opt 收尾，而不是继续在这条递推链上做激进 RTL 变更

### Round 20

目标热点：
- 在当前稳定基线下，观察 implementation 后 `image_geo_core_clk` 最终热点的物理特征

implementation 结果：
- 用户提供截图显示当前最差路径约：
  - `WNS ≈ -2.191 ns`
- 热点仍集中在：
  - `row_y_base_reg -> row_y_base_reg`
  - `row_x_base_reg -> row_x_base_reg`
- 路径统计特征：
  - `High Fanout = 2`
  - `Total Delay ≈ 12.0 ns`
  - `Logic Delay ≈ 9.1 ns`
  - `Net Delay ≈ 2.8~2.9 ns`

版图观察结论：
- 该路径已经不是“高扇出跨模块长连线”问题
- 物理图上虽然存在一定跨区域连线，但从时序构成看：
  - 逻辑延迟远大于布线延迟
- 因此当前主矛盾是：
  - `row_x_base / row_y_base` 局部递推加法链本身
- 而不是 placement 完全失控

结论：
- 当前稳定 RTL 基线已经把外围热点基本清干净
- 继续单纯依赖局部小幅 RTL 切分，收益会越来越有限
- 若继续冲 0 slack：
  - implementation/phys_opt 仍值得继续尝试
  - 但若想有更明显改善，需要更换 row-base 递推的数据路径形式，而不是继续做轻量补丁

## 当前稳定基线

当前基线特征：
- 顶层 [image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/top/image_geo_top.sv) 中 `rotate_core_bilinear` 使用 `COORD_W=36`
- `src_tile_cache` sample 返回已两拍化
- 顶层 `sample_rsp` 和 `core_pix` 边界已加 staging
- `axi_burst_reader / axi_burst_writer` 都已多级 issue/prep/commit 化
- `rotate_core_bilinear` 的 row-base 递推已：
  - 分段求和
  - hold 操作数
  - 双 commit 级
  - 独立 always_ff 更新关键基址寄存器

当前功能状态：
- 顶层回归 [tb_image_geo_top.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top.sv) 通过

当前时序状态：
- `core_clk` 域最差路径约收敛到 `-2.082ns` 量级，后续继续优化中

### Round 21

目标热点：
- 在继续做 row-base 回写链精细切分、边界 staging 和 sample 两拍化之后，重新观察 `core_clk` 域是否还能继续明显下降
- 验证热点是否仍然集中在：
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`

implementation 结果：
- 用户最新截图显示，`image_geo_core_clk` 最差路径约为：
  - `WNS ≈ -2.420 ns`
- 路径仍高度集中在：
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`
- 该轮路径统计特征仍然是：
  - `High Fanout = 2`
  - `Logic Delay` 明显大于 `Net Delay`

结论：
- 经过多轮局部 RTL 切分后，外围高扇出、跨模块净延迟热点已经基本被清走
- 当前剩余热点几乎完全收敛成 row-base 局部递推加法链本体
- 继续在这条链上做 RTL 小修小补仍可能有收益，但已进入“单轮只收零点几纳秒”的阶段
- 后续若继续冲 0 slack，应把主要预期放在：
  - implementation / phys_opt 收尾
  - 或更换 row-base 递推数据表示

### Round 22

目标热点：
- 在保持当前稳定 RTL 基线的前提下，记录当前已取得的最佳 implementation 结果
- 明确当前 best-known WNS，作为后续策略尝试和 RTL 调整的比较基准

implementation 结果：
- 用户当前截图显示：
  - `image_geo_axi_clk` 组约 `-2.503 ns`
  - `image_geo_core_clk` 组约 `-2.191 ns`
- `image_geo_core_clk` 最差路径仍集中在：
  - `row_x_base_reg -> row_x_base_reg`
  - `row_y_base_reg -> row_y_base_reg`

结论：
- 当前可确认的稳定成绩应以：
  - `core_clk WNS ≈ -2.191 ns`
  作为基线
- 这说明：
  - 现有 RTL 优化总体有效
  - 但最终瓶颈仍然是 row-base 局部递推链
- 后续如果继续优化，应始终与这一版结果对比，避免把比 `-2.191 ns` 更差的试验版误当成前进

### Round 23

目标热点：
- 不再继续在 [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 主状态机内部叠加 row-base 切分拍数
- 尝试把 `row_x_base / row_y_base` 的换行递推抽成真正独立的小单元，观察是否能改善综合/布局边界

### Round 32

目标热点：
- 将 `row_x_base/row_y_base` 从主处理闭环中拿掉，避免继续形成逐行自反馈关键链。

操作：
- 主处理阶段不再实时递推 `row_x_base/row_y_base`。
- 在任务开始前预计算每个输出行的起点坐标，存入行基址表。
- 换行时只做“查表 + 行内递推”，不再在主处理阶段执行 `row_base += step`。

结果：
- 顶层回归通过。
- `image_geo_core_clk` WNS 从约 `-2.191 ns` 明显改善到约 `-1.371 ns`。
- 这是 row-base 路线中第一次真正显著的结构性收益。

### Round 33

目标热点：
- 继续压缩首行起点 `row0_x_base/row0_y_base` 初始化链。

操作：
- 将 `row0_x_base / row0_y_base` 初始化改成 `mul -> sum -> commit` 三拍流水。
- 拆开原来单拍内完成的乘法、求和和写回。

结果：
- 顶层回归通过。
- 热点从逐行 row-base 递推进一步转移到 row0 初始化链。

### Round 34

目标热点：
- 进一步压缩 `step_y_x_reg -> row0_y_base` 这条初始化关键路径。

操作：
- 给 row0 初始化引入专用 hold 操作数寄存器。
- 提前锁存 `dst_cx_q16 / dst_cy_q16 / step_y_x / step_y_y / step_x_y`，再进入 `mul -> sum`。

结果：
- 顶层回归通过。
- `image_geo_core_clk` WNS 改善到约 `-0.198 ns`，成为后续比较的最佳稳定基线。

### Round 35

目标热点：
- 尝试继续细切 `row0_y` 初始化中的“移位 + 求和/减法”链。

操作：
- 将两路 `row0_y_mul* >>> FRAC_W` 先分别寄存为中间项，再下一拍做最终求和。

结果：
- 功能通过。
- 但 implementation 明显回退，`core_clk` WNS 恶化到约 `-0.803 ns`。
- 结论：这条“继续切 row0_y shift 链”的思路不值得保留，随后已回退。

### Round 36

目标热点：
- 回到最佳稳定基线，继续隔离 row0 初始化中共享的 step 依赖。

操作：
- 回退 Round 35 的无效切分。
- 保持 row0 初始化优先使用局部专用操作数，避免回到共享寄存器链。

结果：
- 顶层回归通过。
- 重新确立 `image_geo_core_clk WNS ≈ -0.198 ns` 的 best-known baseline。

### Round 37

目标热点：
- 继续压缩双线性插值最后一级 `mix -> out` 路径。

操作：
- 将 `S_MIX0 -> S_MIX1 -> S_OUT` 细化为：
  - `S_MIX0_MUL`
  - `S_MIX0_SUM`
  - `S_MIX1`
  - `S_OUT`
- 先锁存横向混合四个乘法项，再做横向求和，再做纵向混合，最后输出像素。

结果：
- 顶层回归通过。
- 热点开始从 row-base 初始化链转移到 mix/sample 边界。

### Round 38

目标热点：
- 压缩 `src_tile_cache` 中 sample 请求到 sample 返回的解码路径。

操作：
- 在 `src_tile_cache.sv` 中增加 request-decode staging。
- 第一拍锁存 `sample_x0/x1/y0/y1`。
- 第二拍再进行 `hit_slot/row/col` 解码并准备 sample 返回。
- decode/issue 期间禁止 fill/prefetch 修改 slot 状态。

结果：
- 顶层回归通过。
- `sample_x1/sample_y* -> sample_p**` 这组热点被明显压低。

### Round 39

目标热点：
- 继续降低 row0 初始化对共享 step 路径的耦合。

操作：
- 再次收紧 row0 初始化用到的局部 hold 操作数路径。
- 尽量让 `step_y_x` 等信号不直接扇到 `row0_y` 的初始化乘法和求和链。

结果：
- 顶层回归通过。
- `core_clk` WNS 继续稳定在约 `-0.198 ns` 附近。

### Round 40

目标热点：
- 再试一次细切 row0_y 初始化链，验证是否还能吃掉最后几百皮秒。

操作：
- 继续拆开 `row0_y` 初始化中的局部 shift / sum 路径。

结果：
- 功能通过，但 implementation 再次明显回退。
- 热点前移到 `step_y_x_reg -> row0_y_mul0_reg` 一侧。
- 结论：继续在这条链上机械加拍不值得，已回退。

### Round 41

目标热点：
- 回到更优稳定版，重新以最佳点为基线推进。

操作：
- 完整回退 Round 40 相关改动。

结果：
- 顶层回归通过。
- `image_geo_core_clk WNS ≈ -0.198 ns` 重新作为 best-known baseline。

### Round 42

目标热点：
- 在保留 best-known baseline 的前提下，继续清理 row0 初始化链中的共享 step / center 依赖。

操作：
- 调整 row0 初始化路径，使 row0 专用 `step/center` 在 step 生成阶段就被局部化。

结果：
- 顶层回归通过。
- 没有突破 best-known baseline，但结构更干净。

### Round 43

目标热点：
- 继续压缩 `step_y_x_reg -> row0_y_base_wide_reg / row0_y_mul0_reg` 这组路径。

操作：
- 让 row0 初始化整组操作数进一步本地化，形成更明确的专用局部链。

结果：
- 顶层回归通过。
- WNS 维持在 `-0.198 ns` 左右，是后续所有实验的比较基准。

### Round 44

目标热点：
- 保持稳定基线，继续尝试从 row0 初始化链中再挤出一点时序余量。

操作：
- 继续整理 row0 初始化用到的局部操作数与 mux 路径。

结果：
- 功能稳定，但没有超越 best-known baseline。
- 说明 row0 初始化链的小修补收益已开始变小。

### Round 45

目标热点：
- 固定“当前最佳稳定结果”，避免后续实验污染基线。

操作：
- 明确以 `image_geo_core_clk WNS ≈ -0.198 ns` 作为 best-known stable baseline。
- 后续只保留优于该点的新方案。

结果：
- 稳定基线建立完成。

### Round 46

目标热点：
- 继续压缩 `mix_frac_x -> out_mix` 这一条新的 core 域热点。

操作：
- 将横向混合进一步拆成：
  - `S_MIX0_MUL`
  - `S_MIX0_SUM`
  - `S_MIX1`
  - `S_OUT`
- 在 `S_MIX0_MUL` 先锁存四个横向混合乘法项。
- 在 `S_MIX0_SUM` 再做求和与右移，避免 `mix_frac_x` 直接顶到 `top_mix / bot_mix`。

结果：
- 顶层回归通过。
- 热点开始明显向 sample/fill 边界转移。

### Round 47

目标热点：
- 继续压缩 `src_tile_cache` 中 `sample_x1 / slot_tile_x -> fill_row_width / fill_tile_height` 这组剩余热点。

操作：
- 在 `src_tile_cache.sv` 中引入 fill-plan staging。
- 第一拍只生成并锁存 fill plan：
  - `fill_plan_slot_reg`
  - `fill_plan_tile_x_reg`
  - `fill_plan_tile_y_reg`
  - `fill_plan_row_width_reg`
  - `fill_plan_tile_height_reg`
- 下一拍才真正装载：
  - `fill_active_reg`
  - `fill_slot_reg`
  - `fill_tile_x_reg`
  - `fill_tile_y_reg`
  - `fill_row_width_reg`
  - `fill_tile_height_reg`

结果：
- 顶层回归通过。
- `core_clk` 热点缩小到：
  - `sample_x1_reg -> fill_row_width_reg`
  - `sample_x1_reg -> fill_tile_height_reg`
- implementation 结果逼近 `-0.24 ns` 到 `-0.16 ns` 区间。

### Round 48

目标热点：
- 继续冲击最后几百皮秒，压缩 `src_tile_cache` 与 `rotate_core_bilinear` 边界上的剩余路径。

操作：
- 进一步加强 `src_tile_cache` sample/fill 边界隔离。
- 配合此前对 `mix` 路径的分拍，使 core 域最差路径从 row-base / row0 初始化链基本转移出去。

结果：
- implementation 结果显示：
  - 最差路径约为 `-0.241 ns ~ -0.003 ns`
  - 主要集中在：
    - `sample_x1_reg -> fill_row_width_reg`
    - `sample_x1_reg -> fill_tile_height_reg`
    - `slot_tile_x_reg -> fill_tile_height_reg`
- 设计已经进入“最后几百皮秒收尾”阶段。

### Round 49

目标热点：
- 继续压缩 `mix_frac_x -> out_mix` 与 `src_tile_cache` 的 sample/fill 边界路径，争取把 WNS 压到 0 附近。

操作：
- 在 `rotate_core_bilinear.sv` 中继续细化 `out_mix` 输出链。
- 在 `src_tile_cache.sv` 中增加 fill-plan staging，并确认主回归稳定通过。

结果：
- 顶层回归通过。
- 用户给出的最新实现结果显示，`image_geo_core_clk` 最差路径已收敛到：
  - `sample_x1_reg -> fill_row_width_reg`
  - `sample_x1_reg -> fill_tile_height_reg`
  - `mix_frac_x_reg -> out_mix_reg`
- 当前最差 slack 已逼近 `-0.241 ns ~ -0.215 ns`。

### Round 50

目标热点：
- 继续压缩 `src_tile_cache` 中 `sample_y0 -> fill_plan_tile_height` 这组剩余热点。
- 验证 fill-plan staging 是否已经把 `fill_row_width` 路径压到正 slack。

操作：
- 保持 `fill_plan` 两拍结构：
  - 第一拍只锁存 fill plan
  - 第二拍再真正装载 fill 工作寄存器
- 重新跑 implementation，观察 `fill_plan_tile_height_reg` 与 `fill_plan_row_width_reg` 两组寄存器的差异。

结果：
- 用户最新 implementation 结果显示：
  - `sample_y0_reg -> fill_plan_tile_height_reg[*]` 约为 `-0.010 ns`
  - `sample_y0_reg -> fill_plan_row_width_reg[*]` 已转正，约为 `+0.105 ns`
- 说明本轮优化已经把问题压缩到“最后 10ps 量级”的极小残余热点。
- 当前设计已经非常接近 setup 完全收敛，剩余问题主要集中在 `fill_plan_tile_height` 这一个极小局部路径。

### Round 51

目标热点：
- 继续清理 `sample_y0 -> fill_plan_tile_height` 这条最后的几十皮秒热点。
- 避免在 fill-plan 阶段就计算 tile height。

操作：
- 在 `src_tile_cache.sv` 中取消 `fill_plan_tile_height_reg` 在 fill-plan 生成拍的直接计算。
- fill-plan 阶段只锁存：
  - `fill_plan_slot_reg`
  - `fill_plan_tile_x_reg`
  - `fill_plan_tile_y_reg`
  - `fill_plan_row_width_reg`
- 真正进入 fill active 的那一拍，再根据 `fill_plan_tile_y_reg` 计算并装载 `fill_tile_height_reg`。

结果：
- 顶层回归通过。
- 这一步已经把 `fill_plan_tile_height` 的计算从 sample/fill 共享边界再后推一拍。
- 下一步应重新跑 implementation，验证最后 `-0.010 ns` 量级热点是否被完全吃掉。

### Round 52

目标热点：
- 把 `fill_plan_tile_height` 这条路径的 RTL 修改真正收尾，确认代码状态稳定可继续用于 implementation。

操作：
- 完成 `src_tile_cache.sv` 中 `fill_plan_tile_height` 相关路径的重构：
  - fill-plan 生成拍不再直接计算 `fill_plan_tile_height_reg`
  - fill 激活拍根据 `fill_plan_tile_y_reg` 和本地配置寄存器生成 `fill_tile_height_reg`
- 重新执行顶层功能回归，确认修改后主链路行为保持正确。

结果：
- 顶层回归通过。
- 当前代码状态已经完成“把刚才那个改完”的收尾动作，可以直接进入下一轮 implementation 验证。
- 后续若这条路径仍是热点，再决定是否继续针对 `fill_plan_tile_height` 单独加拍，或转去处理新的最差路径。

### Round 53

目标热点：
- 清理 `src_tile_cache.sv` 中 `fill_plan_tile_height_reg` 这类已不再参与主流程、但仍可能制造最后几十皮秒控制路径的残留寄存器。

操作：
- 删除 `fill_plan_tile_height_reg` 的声明。
- 删除 reset 阶段对 `fill_plan_tile_height_reg` 的清零赋值。
- 保留当前已经生效的做法：
  - fill-plan 阶段只锁存 `fill_plan_tile_y_reg`
  - 真正进入 fill active 的那一拍，再根据 `fill_plan_tile_y_reg` 生成 `fill_tile_height_reg`

结果：
- 顶层回归通过，`tb_image_geo_top completed`。
- 这一步属于“最后几十皮秒清尾巴”的 RTL 清理，目的是消掉无意义寄存器对 setup/control 路径的干扰。
- 下一步应重新跑 implementation，确认最后一组 `sample_y0 -> fill_plan_tile_height` / `fill_plan_tile_height_reg` 相关热点是否彻底消失。

### Round 54

目标热点：
- 开始转向 `image_geo_axi_clk` 域，处理用户最新截图中的主热点：
  - `issue_commit_valid_reg_reg_replica/C -> beats_inflight_reg[*]/D`
  - `issue_commit_valid_reg_reg_replica/C -> FSM_sequential_state_reg_reg[*]/D`
  - `bursts_inflight_reg[0]/C -> bursts_inflight_reg[*]/D`
- 路径特征说明当前 `axi_burst_reader.sv` 中 issue commit 后的 inflight 计数更新仍然带着偏宽的加法链和控制扇出。

RTL改动：
- 在 [axi_burst_reader.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_reader.sv) 中将仅用于 outstanding 统计的本地计数器按真实上限缩位宽：
  - `beats_inflight_reg` / `beats_credit_reg` 改为 `BEAT_COUNT_W = clog2(MAX_OUTSTANDING_BEATS+1)`
  - `bursts_inflight_reg` 改为 `BURSTS_COUNT_W = clog2(MAX_OUTSTANDING_BURSTS+1)`
  - 不再继续用原来的 33bit `COUNT_W` 去承载最多 32/4 的小计数器，直接缩短无意义 carry 链。
- 将 `AR handshake -> inflight/queue 更新` 从原来的 `issue_commit_valid_reg` 直接提交，拆成：
  - `issue_commit_valid_reg`
  - `issue_apply_valid_reg`
  两级。
- 现在 `ar_fire` 之后先锁存 `issue_commit_beats_reg`，下一拍再由 `issue_apply_valid_reg` 统一更新：
  - `burst_beats_q`
  - `words_requested_reg`
  - `next_issue_addr_reg`
  - `words_request_remaining_reg`
  - `beats_inflight_reg`
  - `bursts_inflight_reg`
- 同时把 `can_issue_ar_calc` 加入 `!issue_apply_valid_reg` 约束，避免在 counters 尚未提交时提前按旧 credit 再发下一笔 AR。
- 顺手修复了一个参数化问题：
  - `issue_prep_beats_reg` 缩位宽后，`arlen <= issue_prep_beats_reg[7:0] - 1'b1` 在小 `BURST_MAX_LEN` 配置下会越界
  - 已改成参数安全的 `arlen <= issue_prep_beats_reg - 1'b1`

验证结果：
- 模块级回归 [tb_ddr_read_engine.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_ddr_read_engine.sv) 通过。
- 仿真命令：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 ddr_read_engine`
- 首次回归曾暴露 `issue_prep_beats_reg[7:0]` 越界导致的超时问题，修复后重新回归通过。

时序判断：
- 这轮修改的主要目的不是改变协议行为，而是把截图里最集中的两类 setup 热点一起切掉：
  - 过宽的 outstanding counter 加法链
  - `issue_commit_valid` 直接驱动 inflight 更新与状态相关控制
- 还需要重新跑 implementation 才能确认 `image_geo_axi_clk` 的真实 WNS 改善幅度。

### Round 55

目标热点：
- 用户重新跑 implementation 后发现：
  - `image_geo_core_clk` 回退到 `sample_x1_reg -> fill_plan_row_width_reg[*]`，约 `-0.337 ns`
  - `image_geo_axi_clk` 也仍有明显违例，且热点转为：
    - `words_request_remaining_reg -> issue_seed_valid_reg`
    - `issue_calc_words_remaining_reg -> issue_prep_beats_reg`
    - `words_write_remaining_reg -> aw_prep_len_reg`
- 说明 Round 54 虽然处理掉了原先的 `issue_commit/inflight` 热点，但没有击中新的主路径，而且实现层面还把 `core_clk` 的 sample/fill 边界重新放大。

RTL改动：
- 在 [axi_burst_reader.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_reader.sv) 中撤回 Round 54 的 `issue_apply_valid_reg` 额外提交级，避免继续增加读侧局部控制面积和实现扰动。
- 保留 Round 54 中低风险、确定有益的部分：
  - `beats_inflight_reg / bursts_inflight_reg / beats_credit_reg` 缩位宽
  - 参数安全的 `arlen <= issue_prep_beats_reg - 1'b1`
- 进一步针对当前新热点补刀：
  - 新增 `request_remaining_nonzero_reg`
  - 新增 `next_issue_words_remaining_limited_reg`
  - 新增 `next_issue_words_to_4kb_limited_reg`
  - 新增 `limit_burst_words()`，把宽 `remaining` 计数先截成 `BURST_COUNT_W` 的局部寄存器，再送到 issue pipeline
  - `issue_gate_words_remaining_reg / issue_plan_words_remaining_reg / issue_calc_words_remaining_reg / issue_calc_words_to_4kb_reg` 全部改成窄位宽，只服务于 burst 规划本身
  - `can_issue_ar_calc` 不再直接吃宽 `words_request_remaining_reg` 的 burst 计算链，而是改看 `request_remaining_nonzero_reg`
- 在 [axi_burst_writer.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_writer.sv) 中同步做写侧同类优化：
  - 新增 `BURST_COUNT_W`
  - 新增 `words_write_remaining_limited_reg`
  - 新增 `next_write_words_to_4kb_limited_reg`
  - `burst_words_reg / burst_sent_words_reg / burst_words_calc` 改成窄位宽
  - `aw_prep_len_reg` 改为从窄位宽 `burst_words_calc` 生成
  - 修复参数化问题：`aw_prep_len_reg <= burst_words_calc - 1'b1`，不再固定切 `[7:0]`
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中为 fill-plan 再前插一拍 seed 级：
  - 新增 `fill_plan_seed_valid_reg`
  - 新增 `fill_plan_seed_slot_reg`
  - 新增 `fill_plan_seed_tile_x_reg`
  - 新增 `fill_plan_seed_tile_y_reg`
  - 新增 `fill_plan_seed_is_prefetch_reg`
  - 第 1 拍只锁存 fill 请求元信息
  - 第 2 拍才根据 `fill_plan_seed_tile_x_reg` 计算 `fill_plan_row_width_reg`
- 这一步的目的就是把当前重新冒头的：
  - `sample_x1_reg -> fill_plan_row_width_reg`
  再重新切开，避免 sample/fill 边界直接相连。

验证结果：
- 模块级回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 ddr_read_engine`
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 ddr_write_engine`
- 顶层回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 image_geo_top`
- 本轮调试过程中，写侧回归还额外暴露了一个参数化问题：
  - `burst_words_calc[7:0]` 在小 `BURST_MAX_LEN` 配置下越界，且导致 `WLAST mismatch`
  - 修复为参数安全写法后回归恢复通过

时序判断：
- 这一轮属于“承认 Round 54 实现结果不理想后，做定向回撤与重新补刀”。
- 当前 RTL 的预期是：
  - `core_clk` 重新压回 `sample_x1 -> fill_plan_row_width` 之前的状态
  - `axi_clk` 不再让宽 `remaining` 计数直接顶到 `issue_seed/issue_prep/aw_prep_len`
- 但真实改善幅度仍需要新的 implementation 结果确认。

### Round 56

目标热点：
- 新 implementation 结果显示两域都继续收敛，但仍有残余违例：
  - `image_geo_core_clk` 约 `-0.053 ns`
  - 热点转为 `rotate_core_bilinear` 初始化链：
    - `step_x_x_reg -> row0_x_mul0_reg`
  - `image_geo_axi_clk` 约 `-0.657 ns`
  - 热点集中在读侧：
    - `issue_commit_beats_reg -> next_issue_words_to_4kb_limited_reg`
    - `words_request_remaining_reg -> next_issue_words_remaining_limited_reg`
- 这说明上一轮已经把 `sample_x1 -> fill_plan_row_width` 基本压回去，但读侧新引入的 `*_limited_reg` 自己又成了瓶颈。

RTL改动：
- 在 [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv) 中，为 `row0_x` 初始化再插入一个专用 operand prep 级：
  - 新增状态 `S_ROW0_X_PREP`
  - 新增本地乘法输入寄存器：
    - `row0_x_dst_cx_mul_reg`
    - `row0_x_dst_cy_mul_reg`
    - `row0_x_step_x_x_mul_reg`
    - `row0_x_step_x_y_mul_reg`
- 现在流程改为：
  - `S_STEP_YY`
  - `S_ROW0_X_PREP`
  - `S_ROW0_X_MUL`
  - `S_ROW0_X_SUM`
- 目的就是把当前只剩几十皮秒的：
  - `step_x_x -> row0_x_mul0`
  再切开一拍，避免 `step_x_x` 直接驱动 `row0_x` 初始化乘法器输入。
- 在 [axi_burst_reader.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_reader.sv) 中进一步简化读侧 issue pipeline：
  - 删除：
    - `next_issue_words_remaining_limited_reg`
    - `next_issue_words_to_4kb_limited_reg`
  - 不再把“limited 值”做成额外状态寄存器
  - 改为在真正进入：
    - `issue_gate`
    - `issue_plan`
    两级时，按需用 `limit_burst_words(...)` 从全宽计数器截位
- 这样直接去掉了这轮 implementation 中最差的两类路径终点：
  - `*_limited_reg/D`
  - `*_limited_reg/R`
- `can_issue_ar_calc` 仍然只看 `request_remaining_nonzero_reg`，继续避免宽 burst 计算链重新回到 seed 发起条件。

验证结果：
- 模块级回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 ddr_read_engine`
- 顶层回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 image_geo_top`

时序判断：
- 这一轮属于“针对已经收敛到最后 0.x ns 的局部热点继续精修”。
- 预期收益方向是：
  - `core_clk`：继续冲掉 `row0_x` 初始化链最后几十皮秒
  - `axi_clk`：把当前读侧 `*_limited_reg` 相关热点整体移除
- 真实改善幅度仍以新的 implementation 结果为准。

### Round 57

目标热点：
- 用户新 implementation 结果显示：
  - `image_geo_core_clk` 已经转正，约 `+0.230 ns`，当前不再作为主矛盾
  - `image_geo_axi_clk` 继续收敛到最后几十皮秒，但热点转移到写侧：
    - `next_write_words_to_4kb_reg -> next_write_words_to_4kb_limited_reg`
    - `words_write_remaining_reg -> words_write_remaining_limited_reg`
- 这与上一轮读侧的情况一致，说明写侧引入的 `*_limited_reg` 现在也成了最后的 setup 终点。

RTL改动：
- 本轮刻意**不修改** [rotate_core_bilinear.sv](/C:/Users/huawei/Desktop/project_codex/rtl/core/rotate_core_bilinear.sv)，避免把已经转正的 `core_clk` 域重新扰动回违例。
- 在 [axi_burst_writer.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_writer.sv) 中按与读侧相同的思路继续简化：
  - 删除：
    - `words_write_remaining_limited_reg`
    - `next_write_words_to_4kb_limited_reg`
  - 新增组合截位信号：
    - `words_write_remaining_limited_calc`
    - `next_write_words_to_4kb_limited_calc`
  - `burst_words_calc` 现在直接由：
    - `limit_burst_words(words_write_remaining_reg)`
    - `limit_burst_words(next_write_words_to_4kb_reg)`
    组合得到
  - `S_IDLE` / `WDATA` 中不再维护写侧 `*_limited_reg` 状态
- 这样做的目的就是把当前最差的两类写侧热点终点整体删掉，而不是继续围着它们补寄存器。

验证结果：
- 模块级回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 ddr_write_engine`
- 顶层回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 image_geo_top`

时序判断：
- 当前策略是：
  - `core_clk` 先稳住，不追求继续动它
  - 只集中收尾 `axi_clk` 写侧最后几十皮秒
- 下一步需要新的 implementation 结果确认：
  - 写侧 `*_limited_reg` 相关热点是否已经消失
  - `core_clk` 是否保持正 slack、没有反弹

### Round 58

目标热点：
- 用户新 implementation 结果表明：
  - `core_clk` 仍保持正 slack，没有反弹
  - 但 `axi_clk` 反而明显变差，热点重新回到了写侧宽计数器直达 burst 配置链：
    - `words_write_remaining_reg -> aw_prep_len_reg`
    - `words_write_remaining_reg -> burst_words_reg`
    - `next_write_words_to_4kb_reg -> aw_prep_len_reg`
- 这说明 Round 57 “完全去掉写侧 limited 状态寄存器、只留组合截位”的做法虽然逻辑更简单，但把宽 remaining 计数再次直接推回了 `aw_prep_len / burst_words` 的 D 端。

RTL改动：
- 本轮继续坚持：
  - **不修改** `core_clk` 相关 RTL
  - 只处理 [axi_burst_writer.sv](/C:/Users/huawei/Desktop/project_codex/rtl/axi/axi_burst_writer.sv)
- 将写侧 burst 计划改成明确的两拍结构：
  - 新增状态 `S_PREP_LIMIT`
  - 保留 `S_PREP`
- 恢复并重新引入写侧局部限幅寄存器：
  - `words_write_remaining_limited_reg`
  - `next_write_words_to_4kb_limited_reg`
- 新的 burst 规划流程为：
  - `S_PREP_LIMIT`
    - 先把 `words_write_remaining_reg / next_write_words_to_4kb_reg` 限幅并锁存
  - `S_PREP`
    - 再根据这两个窄位宽限幅寄存器计算 `burst_words_reg`
    - 同拍生成 `aw_prep_len_reg`
- 同时将启动和每次 `BRESP` 后的下一轮 burst 准备，都改为先进入 `S_PREP_LIMIT`，而不是直接进入 `S_PREP`
- 这样做的目的就是重新切开：
  - `wide remaining counter -> aw_prep_len`
  - `wide remaining counter -> burst_words`
  这两组当前最差路径，但避免回到 Round 57 的“纯组合截位”直通形式。

验证结果：
- 模块级回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 ddr_write_engine`
- 顶层回归通过：
  - `powershell -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 image_geo_top`

时序判断：
- 这一轮的核心不是继续删逻辑，而是修正 Round 57 的判断偏差：
  - 对写侧最后这条链来说，**适度增加一拍专用 burst planning staging** 比“完全组合化”更有效
- 下一步新的 implementation 结果应重点确认：
  - `axi_clk` 的 `aw_prep_len / burst_words` 热点是否重新回落
  - `core_clk` 是否继续保持正 slack、不反弹
