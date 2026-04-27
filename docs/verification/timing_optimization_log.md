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

## 当前性能基线

### 旋转 Cache 已知提升

针对同一类 `large_rotate45_downscale_7200_to_600` 单-case profile，可比的“早期基线”和“当前稳定基线”如下：

- 早期可比基线：
  - [perf_single_large_rotate45_prefetchprofile xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_prefetchprofile/xsim.log)
  - `req_cycles=4841095`
  - `wait_cycles=44919`
  - `cache_misses=9982`
  - `cache_prefetch=248`
  - `cache_hits=240`
- 当前稳定基线：
  - [perf_single_large_rotate45_trace2uniq_dedup_revertbase xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_dedup_revertbase/xsim.log)
  - `req_cycles=4841365`
  - `wait_cycles=44838`
  - `cache_misses=8917`
  - `cache_prefetch=1327`
  - `cache_hits=352`

按这两组可比数据计算：
- `cache_misses`：`9982 -> 8917`
  - 少 `1065`
  - 降幅约 `10.7%`
- `cache_hits`：`240 -> 352`
  - 多 `112`
  - 提升约 `46.7%`
- `cache_prefetch`：`248 -> 1327`
  - 多 `1079`
  - 提升约 `4.35x`
- `wait_cycles`：`44919 -> 44838`
  - 改善约 `0.18%`
- `req_cycles`：`4841095 -> 4841365`
  - 基本持平，可视为暂无显著整机吞吐改善

当前结论：
- cache predictor 的“猜中 tile”能力已经比最初明显更强；
- 但这些收益还没有充分转化成总周期收益，说明当前主瓶颈已经不只是“有没有预到”，而是“预到的 tile 是否足够贴近真实访问链路”。

## 后续优化优先级

### P1 解析式 Tile Scheduler

目标：
- 用仿射步进的确定式 tile 过界规划，逐步替代当前 heuristic predictor 的“猜下一块”方式。
- 优先覆盖“任意角度 + 中大比例缩小”场景。
- 下一阶段主目标先调整为输入边长 `<=2000` 的工作点，把“任意角度旋转下 predictor 精度做扎实”放在第一位，而不是继续一开始就追 `7200` 极限规模。

执行顺序：
1. 先在 `src_tile_cache` 内补一个不改 sample 命中路径的 scheduler 骨架。
2. 再让 scheduler 先接管“下一块 tile”的预测，和现有 heuristic 并行比对。
3. 验证稳定后，再逐步把 `primary/secondary/tertiary` 的候选生成切到解析式来源。

### P2 任意角度优先的 Lookahead

目标：
- 针对“任意角度旋转 + 缩小”场景，优先支持未来 `2~4` 个 tile 的 lookahead，而不是只看当前下一块。
- 当前先把 `<=2000` 输入规模下的角度覆盖做扎实，再回头放大到 `7200` 级别。

执行顺序：
1. 先量化连续 sample 的 tile 跨越密度。
2. 再扩展 `prefetch_pending` 为更深的待发结构或短队列。

### P3 多个 Outstanding Prefetch

目标：
- 让 predictor 在 DDR 返回前还能继续保留后续候选，减少单个 `prefetch_pending` 的堵塞。

执行顺序：
1. 先补轻量 pending queue。
2. 再评估是否需要和 fill/replacement 策略联动。

### P4 大图压力 Sweep

目标：
- 用真实目标规模验证各角度和缩放比下的 miss/hit/cycle，而不是只看当前小图回归。

建议覆盖：
- 第一阶段：
  - 输入尺寸：接近 `2000`
  - 输出尺寸：按当前常见缩放比覆盖
- 第二阶段：
  - 再回到接近 `7200 -> 600` 的极限压力点
- 角度：`0/15/30/45/60/75/90`
- 模式：纯旋转、纯缩小、旋转+缩小

### P5 Tile 形状与容量调优

目标：
- 在算法侧稳定后，再评估 `TILE_W/H` 和 `TILE_NUM` 是否需要进一步调优。

原则：
- 这一项排在算法性优化之后，避免用 cache 容量去掩盖 predictor 本身的问题。

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

### Round 13

目标热点：
- `src_tile_cache` 中任意角度 predictor 新增后，`core_clk` 域热点转移到 prefetch predictor 的组合链。
- 用户截图显示最差路径曾集中在：
  - `sample_y0_reg -> prefetch_pending_tile_*`
  - `sample_decode_valid_reg -> prefetch_select_*`
  - `sample_hold_* -> prefetch_geom/eval_*`

RTL改动：
- 保留命中路径的保守两拍 sample 返回结构，不再压 hit fast path。
- 将 predictor 分阶段切开，形成当前稳定链路：
  - `sample_hold_*`
  - `prefetch_geom_*`
  - `prefetch_eval_*`
  - `prefetch_select_*`
  - `prefetch_pending_*`
- 新增并锁存解析候选所需的几何信息，避免一拍内同时完成：
  - predicted tile 算术
  - x/y/diag 候选生成
  - primary/secondary/tertiary 排序
  - pending 发起
- 保留 `secondary` 的完整选择逻辑，避免因为过度简化导致预取失效。
- 将 `trajectory` 分支中的 `tertiary` 候选改成更便宜的兜底逻辑，优先为时序让路。

失败尝试与处理：
- 直接插入 `prefetch_base_*` 新级虽然进一步切短路径，但会破坏 predictor 行为，已回退。
- 过度简化 `secondary` 候选去重逻辑会导致 `prefetches=0`，已回退。

当前稳定基线：
- focused regression 通过：
  - [src_tile_cache_timing_opt10 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/src_tile_cache_timing_opt10/xsim.log)
- top-level perf sweep 通过：
  - [image_geo_top_perf_sweep_timing_opt10 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_sweep_timing_opt10/xsim.log)

性能结果：
- `identity_64x16`：`misses 4 -> 1`
- `downscale_64_to_32`：`16 -> 1`
- `rotate45_48_to_32`：`9 -> 4`
- `rotate90_32x48`：`6 -> 1`
- `rotate45_downscale_64_to_24`：`17 -> 4`

备注：
- 这一轮的目标是“先保住任意角度收益，再把 predictor 内部路径切浅”，当前代码已达到这个基线。
- 后续进入 P1 时，优先做“解析式 tile scheduler 骨架”，避免继续在 heuristic predictor 上无止境堆比较与猜测。

### Round 14

目标热点：
- 为 P1“解析式 tile scheduler”先补基础信息源，但不打断当前 sample 命中路径，也不直接替换现有 primary heuristic。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增一组 `prefetch_scheduler_*` 候选：
  - `prefetch_scheduler_x_*`
  - `prefetch_scheduler_y_*`
  - `prefetch_scheduler_diag_*`
- 这些候选根据连续 sample 的真实 `delta_x/delta_y` 与当前离 tile 边界的距离，形成“下一次过界”的确定式候选。
- 新增 `prefetch_geom_scheduler_*` 寄存级，把 scheduler 候选作为并联信息源带入 `prefetch_geom -> prefetch_eval`。
- 当前策略保持克制：
  - 不改 primary 选择
  - 只在 trajectory 分支里，当原有 `secondary/tertiary` 不足时，用 scheduler 候选补位

验证结果：
- focused regression 通过：
  - [src_tile_cache_p1_step1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/src_tile_cache_p1_step1/xsim.log)
- top-level perf sweep 通过：
  - [image_geo_top_perf_sweep_p1_step1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_sweep_p1_step1/xsim.log)

性能结果：
- `identity_64x16`：`misses 4 -> 1`
- `downscale_64_to_32`：`16 -> 1`
- `rotate45_48_to_32`：`9 -> 4`
- `rotate90_32x48`：`6 -> 1`
- `rotate45_downscale_64_to_24`：`17 -> 4`

备注：
- 这一轮主要完成的是 P1 的“骨架接入”，先把解析式候选安全地挂到 predictor 上。
- 后续下一步应继续推进为：让 scheduler 逐步接管 trajectory 分支中的候选排序，而不是仅作为补位来源。

### Round 15

目标热点：
- 推进 P1 第二步，让解析式 scheduler 不再只做补位，而是开始参与 `trajectory` 分支中的主候选排序。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 的 `prefetch_geom -> prefetch_eval` 选择阶段中：
  - 将原先的 trajectory footprint 候选拆成 `legacy_primary/secondary/tertiary`
  - 让 `prefetch_geom_scheduler_x/y/diag_*` 先参与排序
  - 当 `x/y` 都有效时，按 `steps_to_x_edge` 和 `steps_to_y_edge` 先决定 scheduler 优先级
  - 当 scheduler 候选不足时，再回退到 legacy footprint 候选补齐 `secondary/tertiary`

验证结果：
- focused regression 通过：
  - [src_tile_cache_p1_step2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/src_tile_cache_p1_step2/xsim.log)
- top-level perf sweep 通过：
  - [image_geo_top_perf_sweep_p1_step2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_sweep_p1_step2/xsim.log)

性能结果：
- `identity_64x16`：`misses 4 -> 1`
- `downscale_64_to_32`：`16 -> 1`
- `rotate45_48_to_32`：`9 -> 4`
- `rotate90_32x48`：`6 -> 1`
- `rotate45_downscale_64_to_24`：`17 -> 4`

备注：
- 这一轮说明“解析式 scheduler 接管排序”在当前小规模场景下已经功能稳定。
- 但结果与 Round 14 基本持平，说明下一阶段的收益点不再是简单重排，而是更深的 lookahead 和更大工作集验证。

### Round 16

目标热点：
- 推进 P2 第一步，把单个 `prefetch_pending` 扩成浅队列，让 predictor 在 fill 忙碌期间至少能保留 2 个待发候选。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中将：
  - `prefetch_pending_reg`
  - `prefetch_pending_tile_x_reg`
  - `prefetch_pending_tile_y_reg`
  替换为 2-deep 队列：
  - `prefetch_pending0_*`
  - `prefetch_pending1_*`
- 新增 `tile_is_pending()`，查重范围从单个 pending 扩展到两个队列项。
- fill request 仍然只消费队首，但现在支持：
  - 已命中 stale pending 自动清理
  - prefetch 发起时队首出队、队尾前移
  - `prefetch_select` 在不重复时补进队尾
- queue 更新改成统一的 next-state 处理，避免“同拍出队+入队”时的覆盖问题。

验证结果：
- focused regression 通过：
  - [src_tile_cache_p2_step1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/src_tile_cache_p2_step1/xsim.log)
- top-level perf sweep 通过：
  - [image_geo_top_perf_sweep_p2_step1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_sweep_p2_step1/xsim.log)

性能结果：
- `identity_64x16`：`misses 4 -> 1`
- `downscale_64_to_32`：`16 -> 1`
- `rotate45_48_to_32`：`9 -> 4`
- `rotate90_32x48`：`6 -> 1`
- `rotate45_downscale_64_to_24`：`17 -> 4`

备注：
- 当前小规模 sweep 结果与 Round 15 持平，说明 2-deep queue 已稳定接入，但现有用例还没有把它压满。
- 下一步若要看到更明显收益，应优先补“更强 minify / 更大输入”的压力用例，或者继续做更深 lookahead。

### Round 17

目标热点：
- 在继续推进 P2 时兼顾大小缩放比，避免为了大步幅 lookahead 破坏小步幅场景的稳定收益。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增 `prefetch_aggressive_mode`：
  - 由连续 sample 的 `delta_x/delta_y` 幅度决定
  - 只有步幅达到阈值时，才进入更积极的双候选预取模式
- 新增 `prefetch_geom_aggressive_reg` 和 `prefetch_eval_aggressive_reg`，把 aggressiveness 带入 `geom -> eval` 流水。
- 新增第二路选择寄存：
  - `prefetch_select2_*`
  - 小步幅场景保持只入一个候选
  - 大步幅场景允许在同一轮把第二候选也塞进 2-deep pending queue

验证结果：
- focused regression 通过：
  - [src_tile_cache_p2_step2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/src_tile_cache_p2_step2/xsim.log)
- top-level perf sweep 通过：
  - [image_geo_top_perf_sweep_p2_step2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_sweep_p2_step2/xsim.log)

性能结果：
- `identity_64x16`：`misses 4 -> 1`
- `downscale_64_to_32`：`16 -> 1`
- `rotate45_48_to_32`：`9 -> 4`
- `rotate90_32x48`：`6 -> 1`
- `rotate45_downscale_64_to_24`：`17 -> 4`

备注：
- 这一轮确认了“自适应双候选”不会伤到当前小缩放和中等缩放场景。
- 但现有小图 sweep 仍未把 2-deep + aggressive lookahead 完全压出来，下一步应优先补更大输入、更强缩放比的压力用例。

### Round 18

目标：
- 补一组同时覆盖“小图、大图、带旋转”的压力结果，为下一步优化决策提供基线。

RTL/验证改动：
- 新增 [tb_image_geo_top_perf_scale_stress.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_scale_stress.sv)
- bench 使用“按地址生成源像素”的方式驱动 `7200x7200` 级别源图，避免真的分配整幅源图内存。
- 大图 bench 以 cache/perf 统计为主，不做整帧参考比对；小图正确性仍以现有 verified sweep 为准。

小图结果：
- [image_geo_top_perf_scale_stress xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_scale_stress/xsim.log)
- `small_identity_64x16`
  - `prefetch=0`: `cycles=29363 misses=4`
  - `prefetch=1`: `cycles=28986 misses=1 prefetches=3 hits=3`
- `small_rotate45_downscale_64_to_24`
  - `prefetch=0`: `cycles=31378 misses=17`
  - `prefetch=1`: `cycles=37666 misses=6 prefetches=20 hits=19`
- `small_rotate90_32x48`
  - `prefetch=0`: `cycles=44672 misses=6`
  - `prefetch=1`: `cycles=43684 misses=1 prefetches=5 hits=5`

大图结果：
- [image_geo_top_perf_large_stress xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_large_stress/xsim.log)
  - `large_downscale_7200_to_600`, `prefetch=0`
  - `cycles=95603019 reads=1440000 misses=90000`
- [image_geo_top_perf_large_downscale_on2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_large_downscale_on2/xsim.log)
  - `large_downscale_7200_to_600`, `prefetch=1`
  - `cycles=95453507 reads=1459184 misses=1199 prefetches=90000 hits=88801`
- [image_geo_top_perf_large_rotate45_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top_perf_large_rotate45_on/xsim.log)
  - `large_rotate45_downscale_7200_to_600`, `prefetch=1`
  - 在 `TIMEOUT_CYCLES=120000000` 下仍未完成，可视为当前实现对“大图 + 45° + 强缩放”仍明显偏弱

结论：
- 大图纯缩小时，当前 cache/predictor 已经非常有效，`misses 90000 -> 1199`，但总周期改善很有限，说明瓶颈开始转向 core/输出链。
- 小图和中小缩放场景基本稳定，但 `small_rotate45_downscale_64_to_24` 出现了“miss 降了、cycles 反而升”的现象，说明 aggressive prefetch 在部分小图场景有过度预取副作用。
- 大图带旋转，尤其 `45° + 7200 -> 600`，仍是下一阶段的主矛盾。

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

### Rotation Cache Follow-up 1

目标：
- 收掉 `small_rotate45_downscale_64_to_24` 的过度预取副作用，同时不误伤大缩放纯缩小路径。
- 把旋转 cache 压力验证切换到固定单-case bench，避免整套 stress bench 意外长跑。

RTL改动：
- 在 [tb_image_geo_top_perf_single_case.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_single_case.sv) 中补了固定入口的单-case perf bench，新增：
  - `tb_image_geo_top_perf_single_small_rotate45_off/on`
  - `tb_image_geo_top_perf_single_large_downscale_off/on`
  - `tb_image_geo_top_perf_single_large_rotate45_off/on`
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增：
  - `prefetch_eval_dual_axis_reg`
  - `prefetch_eval_dual_frontier_reg`
- 将双轴旋转路径的 prefetch 准入改成：
  - 只有 `hold_prefetched_hit_now` 已经形成预取链，或 scheduler 明确看到双 frontier 时，才允许继续发旋转路径预取
  - 单轴场景保持原策略，不额外收紧

验证结果：
- `small_rotate45` 单-case 复现基线：
  - `prefetch=0`: `cycles=31377 reads=272 misses=17`
  - 日志：[perf_single_small_rotate45_off xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_small_rotate45_off/xsim.log)
- 旧逻辑问题确认：
  - `prefetch=1`: `cycles=37665 reads=416 misses=6 prefetches=20 hits=19`
  - 日志：[perf_single_small_rotate45_fixed xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_small_rotate45_fixed/xsim.log)
- 本轮收紧后：
  - `prefetch=0`: `cycles=31377 reads=272 misses=17`
  - `prefetch=1`: `cycles=31363 reads=272 misses=16 prefetches=1 hits=1`
  - 日志：
    - [perf_single_small_rotate45_off_gate4 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_small_rotate45_off_gate4/xsim.log)
    - [perf_single_small_rotate45_on_gate4 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_small_rotate45_on_gate4/xsim.log)
- `large_downscale` 新版单-case `prefetch=1` 已正常启动，但在当前桌面工具 20 分钟 timeout 内尚未跑完：
  - 日志：[perf_single_large_downscale_on_gate4 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_downscale_on_gate4/xsim.log)

结论：
- 之前的小图性能恶化，根因更像是“双轴旋转场景里预取链启动过于积极”，而不是单纯 cache 命中率不够。
- 本轮改动已经把 `small_rotate45` 从“明显变差”拉回到接近 baseline，同时保留了少量有效预取。
- 下一步应优先继续验证和优化：
  - `large_rotate45_downscale_7200_to_600`
  - 在保证 `large_downscale_7200_to_600` 不退化的前提下，继续做双轴旋转路径的远期 scheduler/lookahead

### Rotation Cache Follow-up 2

目标：
- 在 `large_rotate45_downscale_7200_to_600` 上继续细化双轴旋转路径，但坚持“先保住 hit-path 时序、只改 miss/prefetch 路径”的安全方向。
- 验证最近一轮 aggressive gate 放宽是否真的带来有效收益，而不是只制造更多选择活动。

RTL改动与对比：
- 保留当前已证实有效、且功能稳定的两项改动：
  - `fill_active` tile 的已填行早命中旁路
  - `sample_req_ready` 接受当拍直接发出 `sample_issue_valid_reg`
- 对 prefetch gate 做对比验证：
  - 放宽版本：
    - `prefetch_eval_aggressive_reg && !prefetch_pending1_valid_reg`
  - 收回后的稳态版本：
    - `prefetch_eval_aggressive_reg && !fill_active_reg && !prefetch_pending0_valid_reg && !prefetch_pending1_valid_reg`
- 对比结果显示：
  - 放宽版本只把 `prefetch_sel1` / `pending_cycles` 从约 `1377` 拉高到约 `9483`
  - 但 `req_cycles / wait_cycles / pix / cache_misses / cache_prefetch / cache_hits` 基本不变
  - 说明额外开放出来的大量 selection 并没有转成真实的 DDR 预取收益

当前判断：
- 这一轮应以“回到更稳的 conservative aggressive gate”为基线继续向前，而不是保留 `!prefetch_pending1_only` 的放宽版。
- 当前真正有价值的收益仍主要来自：
  - miss-path 上把 sample issue 和 fill row visible 更早化
  - 双轴旋转时减少无效预取，而不是单纯提高 `prefetch_select` 计数

后续优先级保持不变：
1. 继续推进 P1/P2 的解析式 scheduler 与更准的 primary 候选，优先提高 `large_rotate45_downscale_7200_to_600` 的真实 hit/miss 效率。
2. 在不伤小缩放比和纯 downscale 的前提下，再评估是否需要更深的 pending/lookahead。
3. `TILE_W/H`、`TILE_NUM` 这类容量参数仍排在算法性优化之后，避免用 cache 容量掩盖 predictor 精度问题。

### Rotation Cache Follow-up 3

目标：
- 沿着 Follow-up 2 的“更准 primary 候选”继续前进，但仍然只改 miss/prefetch 路径，不碰 hit-path 时序。
- 针对 profile 中 `scheduler_diag` 几乎从不成为 `primary` 的现象，补一条仅在强 minify 双轴场景生效的排序优化。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中，当满足以下条件时：
  - `prefetch_geom_scheduler_x_valid_reg`
  - `prefetch_geom_scheduler_y_valid_reg`
  - `prefetch_geom_scheduler_diag_valid_reg`
  - `prefetch_geom_aggressive_reg`
- 不再默认从 `x/y` 里选 `primary`，而是：
  - 先把 `diag` 提升为 `primary`
  - 再按 `steps_to_x_edge` / `steps_to_y_edge` 决定 `secondary`
  - 另一条轴向候选作为 `tertiary`

设计意图：
- 当前大角度强缩放 profile 里，`diag` 候选几乎没有真正进入 `primary_src`。
- 对 `45° + 强缩放` 这类双轴同时跨 tile 的场景，单独追 `x` 或 `y` 很可能还是偏保守，优先追 `diag` 更符合“下一次真正会被访问到的 tile”。
- 这条改动被严格限制在 `aggressive` 路径内，避免误伤小缩放比、单轴扫动和常规 downscale。

当前验证状态：
- 顶层 compile-only 通过：
  - [image_geo_top xvlog.log](/C:/Users/huawei/Desktop/project_codex/sim_out/image_geo_top/xvlog.log)
- 轻量 `src_tile_cache_prefetch` bench 目前存在“run -all 长时间不退出”的旧问题，本轮未把它作为功能失败处理。
- 因此，这一刀当前只确认了：
  - 语法/集成无误
  - 下一步需要用 `large_rotate45_downscale_7200_to_600` 的单-case profile 再确认真实收益

### Rotation Cache Follow-up 4

目标：
- 继续用 `large_rotate45_downscale_7200_to_600` 的 10M-cycle 单-case profile 驱动优化，而不是只看代码直觉。
- 先回答两个问题：
  - `diag -> primary` 这种排序调整是否真的有收益
  - 2-deep pending queue 为什么长期 `prefetch_sel2=0`

验证与结论：
- 完整单-case profile 已重新跑通：
  - [perf_single_large_rotate45_trace2uniq_diag_primary xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_diag_primary/xsim.log)
- 结果显示，`diag -> primary` 这刀在 10M-cycle 下几乎没有带来可见变化：
  - `req_cycles=4841365`
  - `cache_misses=8917`
  - `cache_prefetch=1327`
  - `cache_hits=352`
  - `primary_src` 仍然基本来自 scheduler `x/y`
- 因此已将这条“diag 直接升 primary”的改动回退，不把无收益改动留在基线里。

进一步分析：
- 为了定位 `prefetch_sel2=0` 的原因，在 [tb_image_geo_top_perf_single_case.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_single_case.sv) 中新增了 `sel2_opp` 计数：
  - `sel2_window`
  - `sel2_primary_secondary`
  - `sel2_frontier`
- profile 结果：
  - [perf_single_large_rotate45_trace2uniq_sel2probe xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_sel2probe/xsim.log)
  - `sel2_opp=11700/0/0`
- 这说明：
  - aggressive + `pending1` 为空的窗口很多
  - 但当前逻辑下，几乎从来没有出现“`primary` 和 `secondary` 同时 usable”的情况
  - 也几乎没有靠 `dual_frontier + tertiary` 走到第二候选

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中补了更直接的 fallback：
  - 当 `primary` 已选中
  - `aggressive`
  - `pending1` 为空
  - `secondary` 不可用
  - 但 `tertiary` 可用且与 `primary` 不重复
  - 则允许 `tertiary` 直接作为 `select2`
- 同时当 `secondary` 作为 `select1` 时，也允许 `tertiary` 在同样约束下作为 `select2`

结果：
- 新 profile：
  - [perf_single_large_rotate45_trace2uniq_sel2tertiary xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_sel2tertiary/xsim.log)
- 关键变化：
  - `prefetch_sel2: 0 -> 60`
  - `pending_cycles: 1377 -> 1437`
- 但 10M-cycle 主指标暂时仍未变化：
  - `req_cycles` 仍约 `4841365`
  - `cache_misses` 仍约 `8917`
  - `cache_prefetch` 仍约 `1327`
  - `cache_hits` 仍约 `352`

当前判断：
- 这轮至少证明了：
  - 2-deep queue 终于开始被第二候选实际使用，不再是完全“摆设”
  - 但当前真正更硬的瓶颈，已经转到 aggressive gate 本身过于保守
- 下一步更可能有效的方向是：
  - 不盲目全局放宽 gate
  - 而是专门分析“`pending0` 已占用但 `pending1` 为空”的情况下，是否可以只为 `select2` 开更窄的口子

### Rotation Cache Follow-up 5

目标：
- 继续验证 Follow-up 4 的判断：问题究竟卡在 `pending1` 放行，还是更早的 candidate 生成本身。
- 避免继续在 queue/gate 末端反复试错。

RTL与验证：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中尝试补了一个更窄的 `pending1` 填充口：
  - 仅在
    - `prefetch_eval_aggressive_reg`
    - `!fill_active_reg`
    - `prefetch_pending0_valid_reg`
    - `!prefetch_pending1_valid_reg`
    的情况下
  - 允许把当前 `primary/secondary/tertiary` 中最优的 usable 候选直接走 `select2`
- 同时在 [tb_image_geo_top_perf_single_case.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_single_case.sv) 中继续新增 `p1fill` 计数：
  - `pending1_fill_window`
  - `pending1_fill_primary`
  - `pending1_fill_secondary`
  - `pending1_fill_tertiary`

结果：
- 新日志：
  - [perf_single_large_rotate45_trace2uniq_pending1fill xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_pending1fill/xsim.log)
  - [perf_single_large_rotate45_trace2uniq_p1fillprobe xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_p1fillprobe/xsim.log)
- profile 结果表明：
  - `prefetch_sel2` 仍为 `60`
  - 主指标仍不变：
    - `req_cycles=4841365`
    - `cache_misses=8917`
    - `cache_prefetch=1327`
    - `cache_hits=352`
  - 新增的 `p1fill=0/0/0/0`

结论：
- “`pending0` 占用、`pending1` 空闲时再塞一个候选”这条路，在当前 `large_rotate45` 10M-cycle profile 里根本没有机会窗口。
- 因此当前 2-deep queue / `select2` 相关问题已经基本定位完：
  - 它不是主瓶颈
  - 真正更早的限制来自 candidate 生成与 `usable` 条件本身

下一步方向：
- 停止继续在 queue 尾端做小修小补。
- 回到更前面的候选生成阶段，优先分析：
  - 为什么 `secondary_usable` 长期为 0
  - 为什么 `tertiary_usable` 虽然有一定数量，但大多不能转成更早、更连续的有效预取链
- 更具体地说，下一轮应该优先检查 `primary/secondary/tertiary` 的去重、与当前 request footprint 的重叠判定，以及 scheduler/legacy 融合后的候选覆盖率，而不是继续扩 gate。

### Rotation Cache Follow-up 6

目标：
- 把“candidate 生成问题”与“queue / gate 时机问题”彻底区分开，避免继续盲目修改 pending queue。

验证动作：
- 在 [tb_image_geo_top_perf_single_case.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_single_case.sv) 中继续增加两类 profile：
  - `eval_evt`
    - 只统计 `prefetch_eval_valid_reg` 当拍的 `primary/secondary/tertiary` valid/usable 组合
  - `aggr_evt`
    - 只统计 `aggressive` 场景下，这些 usable 组合与 `pending1` 状态的重叠关系
- 重新运行：
  - [perf_single_large_rotate45_trace2uniq_evalevt xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_evalevt/xsim.log)
  - [perf_single_large_rotate45_trace2uniq_aggrevt xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_aggrevt/xsim.log)

关键结果：
- `eval_evt=10188/2526/919/2464/919/2464/919`
  - 解释为：
    - `primary_valid=10188`
    - `secondary_valid=2526`
    - `tertiary_valid=919`
    - `secondary_usable=2464`
    - `tertiary_usable=919`
    - `primary+secondary usable=2464`
    - `primary+tertiary usable=919`
- 这说明在真正的 eval 当拍里：
  - `secondary/tertiary` 并不是“生成不出来”
  - 而且大量场景里它们确实与 `primary` 同时 usable
- `aggr_evt=2463/918/2463/918/0/0`
  - 解释为：
    - `aggressive + primary+secondary usable = 2463`
    - `aggressive + primary+tertiary usable = 918`
    - 但这两类事件在 `pending1` 为空时的计数都是 `0`
- 结论非常明确：
  - 当前 `select2` 起不来，不是因为 usable 组合不存在
  - 而是因为这些真正有价值的组合一出现时，`pending1` 总是已经被占住

额外尝试：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中尝试过一个保守的 `pending1 refresh`：
  - 当 `prefetch_select2` 到达且两个 pending 都满时，用更新的 `select2` 覆盖 `pending1`
- 回归结果：
  - [perf_single_large_rotate45_trace2uniq_p1refresh xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_p1refresh/xsim.log)
  - 主指标完全不变
- 因此该改动已回退，不保留在基线中。

当前结论：
- 这轮已经把“queue 尾端继续微调能否带来收益”基本证伪。
- 下一步不应继续围绕 `pending1 refresh`、`select2 fallback` 之类末端机制做文章。
- 更可能有效的方向已经收敛为两条：
  1. 增加 pending 深度到 3-deep，承认 2-deep 本身不够装下旋转大缩放场景的有效候选。
  2. 更前移地改变 scheduler/legacy 候选的生成节奏，让更有价值的候选更早进入 `pending0/pending1`，而不是在队列已满后才出现。

### Rotation Cache Follow-up 7

目标：
- 在不继续放宽 `prefetch` 主门控的前提下，回收 `fill_active` 窗口里被“一拍即失效”的 eval 候选。
- 保持“更安全的方向”：不改变 hit-path 结构，不把固定气泡往命中路径下压。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中调整 `prefetch_eval_valid_reg` 的生命周期：
  - 旧行为：`prefetch_eval_valid_reg` 产生后一拍即清零
  - 新行为：只有当 `prefetch_select_valid_next` 或 `prefetch_select2_valid_next` 真正消费掉当前 eval 候选时才清零
- 这样做的目的不是增加实时选择活动，而是让最近一组候选在 gate 暂时关闭时仍可被后续窗口消费。

设计意图：
- 当前 profile 已经说明：
  - 很多旋转大缩放场景的机会不是“候选算不出来”
  - 而是 `eval` 出现时刚好遇到 `fill_active` / conservative gate 关闭，随后候选直接蒸发
- 这一轮尝试把“eval 生命周期”和“gate 开窗时机”错位的问题先补上，再看真实 top-level perf 是否跟着改善

待验证标准：
- 如果只看到内部 `prefetch_sel1/sel2` 或 activity 计数上涨，但：
  - `req_cycles`
  - `wait_cycles`
  - `cache_misses`
  - `cache_hits`
  没有方向性改善，则这一轮应回退，不作为新基线保留。

验证结果：
- 已在：
  - [perf_single_large_rotate45_trace2uniq_evalhold xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_evalhold/xsim.log)
  上完成 `large_rotate45_downscale_7200_to_600` 单-case 验证。
- 结果显示该方向明显无效，且带来副作用：
  - 基线近似值：
    - `req_cycles=4841365`
    - `wait_cycles=44838`
    - `cache_misses=8917`
    - `cache_prefetch=1327`
    - `cache_hits=352`
    - `prefetch_eval=14946`
    - `prefetch_sel1=1377`
    - `prefetch_sel2=60`
  - 本轮结果：
    - `req_cycles=4841725`
    - `wait_cycles=44730`
    - `cache_misses=8922`
    - `cache_prefetch=1333`
    - `cache_hits=337`
    - `prefetch_eval=3200677`
    - `prefetch_sel1=9133`
    - `prefetch_sel2=570`

结论：
- “让 eval 挂住直到被消费”虽然回收了大量窗口，但主要放大的是无效 activity，不是真实有效预取。
- 顶层 miss/hit 没有改善，`cache_hits` 反而下降，因此该改动已回退，不保留在稳定基线中。
- 这再次说明：
  - 当前瓶颈不是单纯 `eval` 生命周期过短
  - 真正需要优化的是“哪些候选值得保留”，而不是把所有候选都延后保留

补充实验：
- 之后又尝试过一版更窄的“单槽 deferred candidate”实验：
  - 宽版条件：
    - `fill_active`
    - `aggressive + dual_axis`
    - pending 队列全空
    - `primary/secondary` 同时 usable 且互异
  - 结果：
    - `defer=539/538/222278`
    - 说明这条支路几乎每次都存、都发，但主指标变差：
      - `cache_misses=8939`
      - `cache_prefetch=1311`
      - `cache_hits=310`
  - 说明“只缓存一个 secondary 候选”仍然过宽，会覆盖掉更新鲜、更有效的后续机会
- 再收窄到 `dual_frontier` 后复测：
  - `defer=0/0/0`
  - profile 完全回到基线
  - 说明真正会触发的机会并不集中在 `dual_frontier`

最终处理：
- 整套 `deferred` 实验已经全部回退，不保留在 RTL 基线中。
- 这条线到此可以认为已被证伪：
  - “在 fill 窗口里挂一个简化候选槽”不是当前 `large_rotate45` 的有效优化方向

后续补充实验：
- 又尝试过一版更前移的候选重排：
  - 只在 `prefetch_geom_scheduler_x_valid_reg && prefetch_geom_scheduler_y_valid_reg`
  - 且 `steps_to_x_edge == steps_to_y_edge`
  - 且 `scheduler_diag_valid`
  的情况下，把 `diag` 从 `tertiary` 提到 `primary`
- 目的：
  - 验证 `large_rotate45` 中对角 frontier 是否只是被排位压后了

验证结果：
- [perf_single_large_rotate45_trace2uniq_diagprimary1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_diagprimary1/xsim.log)
- 内部候选统计确实变化明显：
  - `p_valid=4708199/419953/15246`
  - `p_usable=9491/646/17`
  - `prefetch_sel2=74`
- 但顶层关键指标完全不动：
  - `req_cycles=4841365`
  - `cache_misses=8917`
  - `cache_prefetch=1327`
  - `cache_hits=352`

结论：
- `diag` 候选“排位偏后”并不是当前主矛盾。
- 把 equal-step 场景里的 `diag` 提前，只改变了内部候选分布，没有带来真实 miss/hit 改善。
- 该改动已回退，不保留在基线中。

继续验证：
- 基于新增的 `p0blk` 统计，进一步确认了高价值 `primary+secondary` 机会的阻塞来源：
  - `p0blk=585/0/525/60/525/0/525`
  - 解释为：
    - `p0_clear=585`
    - `p0_set=0`
    - `fill=525`
    - `nofill=60`
    - `gateblocked=525`
    - `gateblocked_p0set=0`
    - `gateblocked_fill=525`
- 这说明从“现象”上看，`pending0` 并不是主挡点，几乎所有没转成 `select2` 的高价值机会都死在 `fill_active` 窗口。

窄门控实验：
- 针对上面的 `525` 次窗口，尝试过一个非常窄的 gate 放开：
  - 仅当：
    - `prefetch_eval_aggressive_reg`
    - `fill_active_reg`
    - `pending0/1/2` 全空
    - `primary/secondary` 同时 usable 且互异
  时，允许进入主 prefetch gate
- 验证日志：
  - [perf_single_large_rotate45_trace2uniq_fill525 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_fill525/xsim.log)
- 结果：
  - 内部活动显著放大：
    - `prefetch_sel1: 1377 -> 1902`
    - `prefetch_sel2: 60 -> 585`
  - 但顶层关键指标仍完全不变：
    - `req_cycles=4841365`
    - `cache_misses=8917`
    - `cache_prefetch=1327`
    - `cache_hits=352`

最终结论：
- “被 `fill_active` 挡住”是表象，不是根因。
- 就算把这 525 个窗口放开，这些候选依然没有转成真实有效的 miss 覆盖。
- 该窄门控实验已回退，不保留在 RTL 基线中。

进一步诊断：
- 新增了两组与真实 miss 对齐的 profile：
  - `missov`
    - 只看 `miss_present` 与 `prefetch_eval_valid_reg` 同拍重合
  - `lastmiss`
    - 记录最近一次真实 miss tile，并在后续 `8` 拍 eval 窗口中检查 `primary/secondary/tertiary` 是否命中它

关键结果：
- [perf_single_large_rotate45_trace2uniq_lastmiss xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_lastmiss/xsim.log)
- `missov=0/0/0/0/0`
  - 说明 `miss_present` 和 `prefetch_eval_valid_reg` 根本不同拍
- `lastmiss=84/47/0/131/9345`
  - 解释为：
    - `primary hit last miss = 84`
    - `secondary hit last miss = 47`
    - `tertiary hit last miss = 0`
    - `any hit last miss = 131`
    - `none hit last miss = 9345`

结论：
- 当前 predictor 的核心问题已经非常明确：
  - 不是 gate 太紧
  - 不是 `fill_active` 把有效机会挡住
  - 而是 `primary/secondary/tertiary` 在绝大多数情况下根本没有覆盖到“最近真实 miss tile”

失败尝试：
- 基于上述结论，又尝试过一版“recent miss feedback”：
  - 记录最近 `8` 拍内的真实 miss tile
  - 仅在 `aggressive + dual-axis` 下，将它先作为补位 candidate
  - 先试过只在 `secondary/tertiary` 缺位时补入
  - 再试过直接覆盖 `tertiary`
- 两次实验在：
  - [perf_single_large_rotate45_trace2uniq_missfeedback1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_missfeedback1/xsim.log)
  - [perf_single_large_rotate45_trace2uniq_missfeedback2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_missfeedback2/xsim.log)
  上验证后，profile 与基线完全一致

最终处理：
- `recent miss feedback` RTL 实验已全部回退，不保留在基线中。
- 这说明仅靠“把最近 miss 塞进现有 3-candidate 框架”还不够，下一步应优先考虑：
  - 在更前级直接重构 candidate 生成来源
  - 或者把 current sample footprint 与 recent miss trajectory 做融合，而不是事后补一个附加候选

补充定位：
- 又进一步量化了“最近 miss 相对当前 footprint 的几何关系”：
  - [perf_single_large_rotate45_trace2uniq_lmrel xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_lmrel/xsim.log)
- 结果：
  - `lm_src=0/0/0/0/0/0`
    - 最近 miss 既不在 `scheduler_x/y/diag` 原始源里
    - 也不在 `legacy primary/secondary/tertiary` 原始源里
  - `lm_rel=755/671/0/8050`
    - 最近 miss 更常表现为相对当前 footprint 的 `x-like` / `y-like` 邻块
    - 几乎不是 `diag-like`

失败尝试：
- 基于 `lm_rel` 结果，又试过一版更窄的 `x/y-like recent miss feedback`：
  - 仅在：
    - `last_miss_age <= 8`
    - `aggressive + dual-axis`
    - `recent miss` 与当前请求 footprint 不重合
    - 且几何关系被识别为 `x-like` 或 `y-like`
  时，把 `recent miss` 作为 `secondary/tertiary` 的补位候选
- 验证日志：
  - [perf_single_large_rotate45_trace2uniq_xyfeedback1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_xyfeedback1/xsim.log)
- 结果：
  - profile 与基线完全一致
  - 说明“在候选尾部补一个 x/y-like recent miss”仍然不足以进入有效预取链

当前判断：
- 问题不在候选尾部，而在更早的 source construction：
  - 需要直接生成“以 recent miss 方向为中心”的新 source
  - 而不是把 recent miss 当成 `secondary/tertiary` 的附加补丁

继续验证：
- 又进一步尝试了一版更前级的 `x/y recent miss source`：
  - 不再把 `recent miss` 补到 `secondary/tertiary` 尾部
  - 而是只在：
    - `recent miss age <= 8`
    - `aggressive + dual-axis`
    - `recent miss` 被识别为 `x-like` 或 `y-like`
    - 且原生 `scheduler_x/y` 当拍没有给出候选
  时，把 `recent miss` 直接注入 `scheduler_x / scheduler_y` 这一层
- 验证日志：
  - [perf_single_large_rotate45_trace2uniq_xysource1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_xysource1/xsim.log)

结果：
- profile 与基线完全一致，没有任何可见变化

结论：
- 即使把 `recent miss x/y-like` 提前到 source construction 层，只要它仍然只是“替换单个 `scheduler_x/y` 候选”的小修补，依然无法进入有效预取链。
- 这进一步说明下一步应考虑的不是局部 patch，而是更大一级的结构调整，例如：
  - 在 `prefetch_geom` 前新增一套独立的 `miss-driven source`
  - 或者重写 `scheduler_x/y` 的生成准则，使其本身能吸收 recent miss 反馈，而不是事后覆盖输出

### Rotation Cache Follow-up 5

目标：
- 继续沿着“更前级 source construction”方向试探，但坚持只改 miss/prefetch 路径，不碰 hit-path。
- 回答两个更具体的问题：
  - `x-like / y-like` 候选是不是因为锚在 `y00 / x00` 上，导致和真实 leading edge 偏了一格
  - 前面组合出的 `candidate_primary/secondary/tertiary` 是否真的进入了有效 eval 链路

实验 A：lead-edge anchored x/y source
- RTL尝试：
  - 在 `aggressive + trajectory` 下，把 `scheduler_x` / `candidate_x` 的正交锚点从固定 `y00` 改为沿 `dir_y` 的 leading edge。
  - 同理，把 `scheduler_y` / `candidate_y` 的正交锚点从固定 `x00` 改为沿 `dir_x` 的 leading edge。
- 验证日志：
  - [perf_single_large_rotate45_trace2uniq_leadedge1 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_leadedge1/xsim.log)
- 结果：
  - 顶层 profile 与基线完全一致：
    - `cache_misses=8917`
    - `cache_prefetch=1327`
    - `cache_hits=352`
    - `prefetch_sel2=60`
- 结论：
  - 单纯把 `x-like / y-like` source 的锚点从固定角换到 leading edge，并没有改变真实 top-level 行为。
  - 说明问题不是“选对了 source 类型但锚点偏了一格”这么简单。

实验 B：让 eval 直接消费 candidate 排序
- RTL尝试：
  - 将 `sample_decode` 阶段已经组合出的 `candidate_primary/secondary/tertiary` 直接打拍进入 `prefetch_geom_*`。
  - 在 eval 阶段不再按 `predicted_tile_*` 重新拼 legacy 候选，而是直接使用前级 `candidate_*` 的排序结果。
- 验证日志：
  - [perf_single_large_rotate45_trace2uniq_leadedge2 xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/perf_single_large_rotate45_trace2uniq_leadedge2/xsim.log)
- 结果：
  - 出现明显退化：
    - `prefetch_sel2: 60 -> 0`
    - `cache_prefetch: 1327 -> 1327`（总量不变）
    - `cache_hits: 352 -> 352`（主指标不变）
    - 但内部 aggressive/secondary 机会几乎被清空：
      - `aggr_evt=0/...`
      - `p0blk=0/...`
      - `lastmiss=0/0/0/0/9476`
- 处理：
  - 这条改动已经回退，不保留在基线中。

本轮结论：
- `candidate_*` 这套前级排序逻辑并不能直接替代当前 eval 里的 legacy reconstruction；两者虽然表面相近，但和后端有效预取链路的契合度不同。
- 到这里可以更明确地下结论：
  - 继续做局部 source 锚点微调，价值已经很低
  - 下一步更值得做的是“新增一套更远 lookahead 的独立 source”，而不是继续在现有 `x/y/diag + legacy reconstruction` 上补丁式修修补补

### Rotation Cache Follow-up 6

目标：
- 把优化目标从一开始就追 `7200 -> 600` 调整为更务实的“先把 `<=2000` 级别、任意角度旋转做扎实”。
- 先回答两个基础问题：
  - 当前实现在 `2000` 量级下是否已经能稳定覆盖任意角度
  - 若不能，最薄弱的角度段是哪些

bench 扩展：
- 在 [tb_image_geo_top_perf_single_case.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_single_case.sv) 中新增两组角度 sweep：
  - `mid_rotate{15,30,45,60,75}_{off,on}`
    - `2048x2048 -> 256x256`
  - `proxy_rotate{15,45,75}_{off,on}`
    - `1024x1024 -> 256x256`
- 设计意图：
  - `2048` 组直接对应新的阶段目标
  - `1024` 组作为更快的 proxy，用来继续驱动 RTL 迭代

验证结果 A：`2048 -> 256`
- 日志目录：
  - [mid_rotate_sweep](/C:/Users/huawei/Desktop/project_codex/sim_out/mid_rotate_sweep)
- 当前已跑到的代表点：
  - `15° off/on`
  - `30° off/on`
  - `45° off/on`
- 结果：
  - 全部在 `TIMEOUT_CYCLES=20000000` 内未完成
- 结论：
  - 当前问题已经不是只有 `7200` 极限规模太难，而是“任意角度旋转链路在 `2000` 量级上仍明显偏弱”

验证结果 B：`1024 -> 256`
- 日志目录：
  - [proxy_rotate_sweep](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_sweep)
- 结果：
  - `15° off`
    - `req_cycles=5585043`
    - `cache_misses=12243`
    - `cache_prefetch=0`
    - `cache_hits=0`
  - `15° on`
    - `req_cycles=5585353`
    - `cache_misses=12204`
    - `cache_prefetch=42`
    - `cache_hits=29`
  - `45° off`
    - `req_cycles=5619549`
    - `cache_misses=12111`
  - `45° on`
    - `req_cycles=5620339`
    - `cache_misses=11664`
    - `cache_prefetch=445`
    - `cache_hits=418`
  - `75° off`
    - `req_cycles=5592849`
    - `cache_misses=12006`
  - `75° on`
    - `req_cycles=5593349`
    - `cache_misses=11496`
    - `cache_prefetch=518`
    - `cache_hits=422`
- 结论：
  - `45° / 75°` 上 prefetch 已经能明显减少 miss，但仍然没有转化成总周期收益
  - `15°` 最薄弱，prefetch 仅带来极小 miss 改善，几乎没有真实收益
  - 这说明下一步不应只盯住“强双轴对角”，还要补“浅角度、双轴但非 aggressive”的 candidate/source 精度

失败尝试：dual-frontier 放宽 `sel2`
- RTL尝试：
  - 把 `select2` 的放行条件从仅 `prefetch_eval_aggressive_reg` 放宽为：
    - `prefetch_eval_aggressive_reg || prefetch_eval_dual_frontier_reg`
- 验证日志：
  - [proxy_rotate_dualfrontier2](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_dualfrontier2)
- 结果：
  - `proxy_rotate15_on`
    - `prefetch_sel2: 9 -> 154`
    - 顶层 `req_cycles/cache_misses/cache_hits` 不变
  - `proxy_rotate45_on`
    - `prefetch_sel2: 0 -> 355`
    - 顶层主指标不变
  - `proxy_rotate75_on`
    - `prefetch_sel2: 0 -> 549`
    - 顶层主指标不变
- 处理：
  - 该改动已回退，不保留在基线中。

本轮结论：
- 当前阶段已经可以明确把优化重点从“纯扩大 pending / 增加 sel2 数量”转向“让 candidate 更贴近浅角度真实访问链”。
- 下一步更值得做的方向：
  - 单独针对 `15°/30°` 一类 shallow-angle 旋转补 source construction
  - 不再单纯依赖现有 `aggressive` 判据来决定是否值得追第二候选

### Rotation Cache Follow-up 7

目标：
- 优先优化 `1024 -> 256, 15°` 这类浅角度旋转 proxy case。
- 同时保证已有稳定场景不倒退，至少覆盖：
  - `proxy_rotate45_on`
  - `proxy_rotate75_on`
  - `small_rotate45_on`
  - `large_rotate45_on_trace2uniq`

有效 RTL 改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增浅角度判定：
  - `prefetch_shallow_mode`
  - `prefetch_geom_shallow_reg`
  - `prefetch_eval_shallow_reg`
- 判定方式：
  - 同时存在 `delta_x` 和 `delta_y`
  - 且 `abs(delta_x)` 与 `abs(delta_y)` 至少有一边达到另一边的 `2x`
  - 也就是只覆盖 `15°/75°` 这类一个轴明显主导的浅角度，不覆盖 `45°`
- 新增安全窗口 `prefetch_shallow_idle_window`：
  - `dual_axis`
  - `shallow`
  - `!aggressive`
  - 当前没有 `fill_active`
  - pending0/1/2 都为空
  - tile 数量至少 `32x32`
- 只有满足该窗口时，才允许浅角度旋转启动第一候选预取链。
- 这条路径只影响 prefetch/miss-path，不碰 sample hit-path。

主目标验证：`1024 -> 256, 15°`
- 基线日志：
  - [proxy_rotate_sweep/tb_image_geo_top_perf_single_proxy_rotate15_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_sweep/tb_image_geo_top_perf_single_proxy_rotate15_on/xsim.log)
- 新日志：
  - [proxy_rotate_shallow_only1/tb_image_geo_top_perf_single_proxy_rotate15_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_shallow_only1/tb_image_geo_top_perf_single_proxy_rotate15_on/xsim.log)
- 对比：
  - `req_cycles: 5585353 -> 5585003`
  - `cache_misses: 12204 -> 9346`
  - `cache_prefetch: 42 -> 2921`
  - `cache_hits: 29 -> 1501`
- 结论：
  - `15°` 的 cache 行为有实质改善，miss 下降约 `23.4%`
  - prefetch hit 从 `29` 提升到 `1501`
  - 总周期仍只小幅改善，说明后续还需要继续提升“预取命中转化为等待周期收益”的能力

不倒退验证：
- `proxy_rotate45_on`
  - 基线：[proxy_rotate_sweep/tb_image_geo_top_perf_single_proxy_rotate45_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_sweep/tb_image_geo_top_perf_single_proxy_rotate45_on/xsim.log)
  - 新日志：[proxy_rotate_shallow_only1/tb_image_geo_top_perf_single_proxy_rotate45_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_shallow_only1/tb_image_geo_top_perf_single_proxy_rotate45_on/xsim.log)
  - 主指标完全持平：
    - `req_cycles=5620339`
    - `cache_misses=11664`
    - `cache_prefetch=445`
    - `cache_hits=418`
- `proxy_rotate75_on`
  - 基线：[proxy_rotate_sweep/tb_image_geo_top_perf_single_proxy_rotate75_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_sweep/tb_image_geo_top_perf_single_proxy_rotate75_on/xsim.log)
  - 新日志：[proxy_rotate_shallow_only1/tb_image_geo_top_perf_single_proxy_rotate75_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_rotate_shallow_only1/tb_image_geo_top_perf_single_proxy_rotate75_on/xsim.log)
  - 对比：
    - `req_cycles: 5593349 -> 5591989`
    - `cache_misses: 11496 -> 7677`
    - `cache_prefetch: 518 -> 4387`
    - `cache_hits: 422 -> 3274`
  - `75°` 也受益，且没有周期倒退。
- `small_rotate45_on`
  - 新日志：[shallow_only_regression/tb_image_geo_top_perf_single_small_rotate45_on xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/shallow_only_regression/tb_image_geo_top_perf_single_small_rotate45_on/xsim.log)
  - `cycles=24473`
  - `misses=17`
  - `prefetches=1`
  - `hits=1`
  - 小图不满足 `32x32` tile 保护条件，不会重新进入过度预取路径。
- `large_rotate45_on_trace2uniq`
  - 新日志：[shallow_only_regression/tb_image_geo_top_perf_single_large_rotate45_on_trace2uniq xsim.log](/C:/Users/huawei/Desktop/project_codex/sim_out/shallow_only_regression/tb_image_geo_top_perf_single_large_rotate45_on_trace2uniq/xsim.log)
  - 对比当前稳定基线：
    - `req_cycles=4841365` 保持不变
    - `wait_cycles=44838` 保持不变
    - `cache_misses: 8917 -> 8910`
    - `cache_prefetch: 1327 -> 1334`
    - `cache_hits=352` 保持不变

失败尝试与回退：
- 曾尝试只用 `dual_frontier` 放宽 `select2`：
  - `prefetch_sel2` 明显增加
  - 但所有 top-level 主指标不变
  - 已回退
- 曾尝试不区分浅角度、对所有非 aggressive 中大图双轴场景放宽第一候选：
  - `15°` 有收益
  - 但会轻微影响 `45°` 的总周期
  - 已收窄为 `shallow` 判定版本

本轮结论：
- 对 `15°/75°` 这类浅角度，一个轴明显主导时，原来的 prefetch gate 过于保守。
- 使用 `shallow + idle + 中大图 tile 数保护` 可以显著降低 miss，同时不影响 `45°` 和小图稳定场景。
- 下一轮应继续沿这个方向做第二步：
  - 让浅角度候选更准，而不只是更早启动第一候选链
  - 重点观察 wait_cycles 为什么没有随 miss 大幅下降而同步下降

### Rotation Cache Follow-up 8

目标：
- 继续优先优化 `1024 -> 256, 15°`。
- 先解释“miss 明显下降但周期收益很小”的原因，再做不倒退的小步 RTL 优化。

验证/诊断改动：
- 在 [tb_image_geo_top_perf_single_case.sv](/C:/Users/huawei/Desktop/project_codex/rtl/sim/tb_image_geo_top_perf_single_case.sv) 中新增 `PERF_SINGLE_PROFILE_DETAIL` 级别计数。
- 重点拆分：
  - `S_REQ` 被 miss、demand fill、prefetch fill、read_busy 卡住的周期
  - `S_WAIT` 固定响应流水周期
  - demand/prefetch fill 的占用周期

诊断结果：
- `proxy_rotate15_on` 当前浅角度基线：
  - [proxy_profile_detail1/proxy15_rerun.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_profile_detail1/proxy15_rerun.log)
  - `corewait=5543945/0/0/1293788/4222119/4796800/0`
  - `waitpipe=82115/41058/41058`
  - `fillcyc=1402080/4485821/5102851/5495373`
- 结论：
  - `S_WAIT` 主要是固定两拍 sample response，不是当前主瓶颈。
  - 主瓶颈仍在 `S_REQ` 等 tile，尤其 demand fill 占用约 `4222119` 周期。
  - 因此下一步应继续降低真实 demand miss，同时避免盲目增加 prefetch fill 占用。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增 `PREFETCH_SHALLOW_EARLY_STEPS`。
- 对 x-dominant 浅角度场景增加提前窗口：
  - 当 `abs(delta_x) >= 2 * abs(delta_y)`
  - 且距离 x 方向 tile 边界不超过约 `3/4 tile`
  - 即使下一 sample 尚未真正跨 tile，也提前把 x 方向相邻 tile 作为 scheduler 候选。
- 该改动只作用在 prefetch/scheduler 路径，不改 sample hit-path。

验证结果：
- `proxy_rotate15_on`
  - 新日志：[proxy_shallow_xearly1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly1/proxy15.log)
  - 对比 Follow-up 7 浅角度基线：
    - `req_cycles: 5585003 -> 5582940`
    - `cache_misses: 9346 -> 9271`
    - `cache_prefetch: 2921 -> 3076`
    - `cache_hits: 1501 -> 1603`
  - 结论：15° 有小幅正向改善，但还不是决定性突破。
- `proxy_rotate45_on`
  - 新日志：[proxy_shallow_early1/proxy45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_early1/proxy45.log)
  - 与浅角度基线完全持平：
    - `req_cycles=5620339`
    - `cache_misses=11664`
    - `cache_prefetch=445`
    - `cache_hits=418`
- `proxy_rotate75_on`
  - 新日志：[proxy_shallow_xearly1/proxy75.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly1/proxy75.log)
  - 回到 Follow-up 7 基线：
    - `req_cycles=5591989`
    - `cache_misses=7677`
    - `cache_prefetch=4387`
    - `cache_hits=3274`
- `small_rotate45_on`
  - 新日志：[proxy_shallow_xearly1/small45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly1/small45.log)
  - `cycles=24473`
  - `misses=17`
  - `prefetches=1`
  - `hits=1`
  - 小图保护项不退。

失败尝试与回退：
- 曾尝试对浅角度同时开启 x/y dominant 提前窗口：
  - `15°` 小幅改善
  - 但 `75°` 轻微退步：`req_cycles 5591989 -> 5597977`
  - 已撤掉 y-dominant 提前窗口，仅保留当前对 `15°` 有益且不伤现有基线的 x-dominant 版本。
- 曾尝试在浅角度 idle 窗口额外带第二候选：
  - `prefetch_sel2` 仅 `9 -> 11`
  - miss/周期完全不动
  - 已回退。

下一步：
- 当前方向有效但幅度较小，说明简单“更早一点”还不够。
- 后续应优先做更明确的多步 lookahead，特别是 dominant 方向连续 tile 的提前排队，同时继续用 profile 确认 prefetch fill 没有反过来抢占 demand fill。

### Rotation Cache Follow-up 9

目标：
- 继续围绕 `1024 -> 256, 15°` 优化 dominant 方向提前预取。
- 保持原则：
  - 不碰 sample hit-path
  - 不扩大到 `45°`
  - 不让 `75°` 和小图保护项退步

RTL改动：
- 将 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中 `PREFETCH_SHALLOW_EARLY_STEPS` 从约 `3/4 tile` 扩到接近 `1 tile`：
  - 当前保留值：`max(TILE_W,TILE_H)-1`
  - 仍只作用于 x-dominant 浅角度：
    - `prefetch_shallow_mode`
    - `abs(delta_x) >= 2 * abs(delta_y)`
  - y-dominant 提前窗口仍不打开，避免再次伤到 `75°`。

保留版本验证：
- `proxy_rotate15_on`
  - 新日志：[proxy_shallow_xearly_full1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly_full1/proxy15.log)
  - 对比 Follow-up 8 的 x-dominant `3/4 tile` 版本：
    - `req_cycles: 5582940 -> 5582600`
    - `cache_misses: 9271 -> 9276`
    - `cache_prefetch: 3076 -> 3080`
    - `cache_hits: 1603 -> 1606`
  - 结论：miss 略升，但总请求等待周期更低，说明更早补到少数关键 tile 后，对吞吐略有帮助。
- `proxy_rotate45_on`
  - 新日志：[proxy_shallow_xearly_full1/proxy45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly_full1/proxy45.log)
  - 与基线完全持平：
    - `req_cycles=5620339`
    - `cache_misses=11664`
    - `cache_prefetch=445`
    - `cache_hits=418`
- `proxy_rotate75_on`
  - 新日志：[proxy_shallow_xearly_full1/proxy75.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly_full1/proxy75.log)
  - 与 Follow-up 8 / Follow-up 7 基线完全持平：
    - `req_cycles=5591989`
    - `cache_misses=7677`
    - `cache_prefetch=4387`
    - `cache_hits=3274`
- `small_rotate45_on`
  - 新日志：[proxy_shallow_xearly_full1/small45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly_full1/small45.log)
  - `cycles=24473`
  - `misses=17`
  - `prefetches=1`
  - `hits=1`

失败尝试与回退：
- 尝试把 `scheduler_diag` 借作 x 方向第 2 个 lookahead tile：
  - 日志：[proxy_shallow_xlook2_exp1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xlook2_exp1/proxy15.log)
  - 主指标与 Follow-up 8 完全一致
  - 但内部 secondary/tertiary 活跃度明显增加
  - 已回退，不保留无收益复杂度。
- 尝试折中阈值 `max(TILE_W,TILE_H)-2`：
  - 日志：[proxy_shallow_xearly_14step1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_shallow_xearly_14step1/proxy15.log)
  - `req_cycles=5582750`
  - 介于 `3/4 tile` 与 `tile-1` 之间
  - 不如当前保留的 `tile-1`，因此不保留。

当前结论：
- `15°` 的收益继续向前推进了一点，但已经进入小步收益阶段。
- 仅靠 x-dominant 单候选提前窗口，无法大幅削减 demand fill。
- 下一轮若继续追 15°，应考虑更结构化的“dominant 方向跨 tile 事件队列”，而不是继续增加单拍候选数量。

### Rotation Cache Follow-up 10

目标：
- 按计划搭建更结构化的 dominant 方向 lookahead 队列。
- 先只覆盖 `1024 -> 256, 15°` 这类 x-dominant 浅角度，不扩大到 `45°/75°`。
- 仍然不碰 sample hit-path。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增 2-deep dominant event queue：
  - `prefetch_dom0_*`
  - `prefetch_dom1_*`
- 队列种入条件：
  - `prefetch_eval_dual_axis_reg`
  - `prefetch_eval_shallow_reg`
  - `prefetch_eval_x_dominant_reg`
  - `!prefetch_eval_aggressive_reg`
  - tile grid 至少 `32x32`
- 队列消费方式：
  - demand miss 仍然最高优先级
  - 普通 `prefetch_pending0/1/2` 仍优先于 dominant queue
  - 当普通 pending 为空时，dominant queue 作为后备 prefetch 源
  - 已命中或已发起 fill 的 event 会自动出队
- 队列去重范围包含：
  - 普通 pending
  - dominant queue 自身
  - 当前 request
  - cache 已命中 tile

验证结果：
- `proxy_rotate15_on`
  - 新日志：[proxy_dom_queue_exp1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_exp1/proxy15.log)
  - 对比 Follow-up 9：
    - `req_cycles: 5582600 -> 5582520`
    - `cache_misses: 9276 -> 9282`
    - `cache_prefetch: 3080 -> 3081`
    - `cache_hits: 1606 -> 1603`
  - 结论：
    - 队列确实被消费，但当前只带来极小周期收益。
    - miss/hit 没有同步改善，说明队列目前更多是结构性骨架，还不是最终有效调度策略。
- `proxy_rotate45_on`
  - 新日志：[proxy_dom_queue_exp1/proxy45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_exp1/proxy45.log)
  - 与基线完全持平：
    - `req_cycles=5620339`
    - `cache_misses=11664`
    - `cache_prefetch=445`
    - `cache_hits=418`
- `proxy_rotate75_on`
  - 新日志：[proxy_dom_queue_exp1/proxy75.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_exp1/proxy75.log)
  - 与基线完全持平：
    - `req_cycles=5591989`
    - `cache_misses=7677`
    - `cache_prefetch=4387`
    - `cache_hits=3274`
- `small_rotate45_on`
  - 新日志：[proxy_dom_queue_exp1/small45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_exp1/small45.log)
  - `cycles=24473`
  - `misses=17`
  - `prefetches=1`
  - `hits=1`

当前结论：
- dominant event queue 已安全接入，且不影响 `45°/75°/小图`。
- 但当前调度策略过于保守，只多触发了极少量 prefetch，收益很小。
- 下一步若继续优化，应在这个队列骨架上改“种入/消费节奏”，例如：
  - 只在 fill 空闲前若干周期预热，而不是等普通 pending 全空才消费
  - 对队列 event 加 age/优先级，避免太晚才被 fill
  - 用 profile 观察 dominant queue 被 pending 队列阻塞的比例

### Rotation Cache Follow-up 11

目标：
- 不再使用固定 `+2/+3` tile 偏移来生成 dominant queue event。
- 改成更贴合实际轨迹的 `2-step/3-step` projected tile，让 x 前进时 y 也随当前旋转轨迹一起漂移。

RTL改动：
- 在 [src_tile_cache.sv](/C:/Users/huawei/Desktop/project_codex/rtl/buffer/src_tile_cache.sv) 中新增：
  - `predicted2_tile_*`
  - `predicted3_tile_*`
  - 对应的 `prefetch_geom_pred2_*` / `prefetch_geom_pred3_*` 流水寄存器
- 计算方式：
  - `2-step`: 当前 sample 坐标 + `2 * delta`
  - `3-step`: 当前 sample 坐标 + `3 * delta`
  - 之后做 clamp，再转换为 tile 坐标
- dominant queue 改为：
  - 正向 x-dominant：取 `predicted2_tile_x01/y00` 与 `predicted3_tile_x01/y00`
  - 反向 x-dominant：取 `predicted2_tile_x00/y00` 与 `predicted3_tile_x00/y00`
- 保持不变：
  - demand miss 仍最高优先级
  - `45°/75°/小图` 的启用保护条件不变

验证结果：
- `proxy_rotate15_on`
  - 新日志：[proxy_dom_queue_proj1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_proj1/proxy15.log)
  - 对比 Follow-up 10：
    - `req_cycles: 5582520 -> 5582226`
    - `cache_misses: 9282 -> 9279`
    - `cache_prefetch: 3081 -> 3082`
    - `cache_hits: 1603 -> 1614`
    - `domq: 79898/74913/4985 -> 32151/31568/583`
  - 结论：
    - projected event 比固定 `+2/+3` 更有效，队列非空周期和“被普通 pending 挡住”的比例都明显下降
    - 同时主指标也终于是同向改善
- `proxy_rotate45_on`
  - 新日志：[proxy_dom_queue_proj1/proxy45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_proj1/proxy45.log)
  - 完全持平：
    - `req_cycles=5620339`
    - `cache_misses=11664`
    - `cache_prefetch=445`
    - `cache_hits=418`
    - `domq=0/0/0`
- `proxy_rotate75_on`
  - 新日志：[proxy_dom_queue_proj1/proxy75.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_proj1/proxy75.log)
  - 完全持平：
    - `req_cycles=5591989`
    - `cache_misses=7677`
    - `cache_prefetch=4387`
    - `cache_hits=3274`
    - `domq=1/1/0`
- `small_rotate45_on`
  - 新日志：[proxy_dom_queue_proj1/small45.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_proj1/small45.log)
  - `cycles=24473`
  - `misses=17`
  - `prefetches=1`
  - `hits=1`
  - `domq=0/0/0`

失败尝试与回退：
- `x+4/x+5` 固定远距 future tile：
  - `req_cycles` 恶化到 `5619645`
  - 已回退
- “沿 `scheduler_x` 串链再向前推”：
  - `cache_hits` 增长，但 `req_cycles` 退化到 `5584873`
  - 已回退

当前结论：
- dominant queue 的方向是对的，但 event 生成必须跟着轨迹走，不能用固定 tile 偏移。
- `2-step/3-step` projected tile 已经证明比固定 `+2/+3` 更有效，而且不伤保护项。

### Rotation Cache Follow-up 12

目标：
- 在 Follow-up 11 的 projected future tile 基础上，尝试把 dominant queue 的 lookahead 步数改成“按当前 x 步幅自适应”。

RTL改动：
- 新增 `4-step` projected tile 计算链：
  - `predicted4_tile_*`
  - `prefetch_geom_pred4_*`
- 新增 `prefetch_shallow_fast_x` / `prefetch_geom_shallow_fast_x_reg` / `prefetch_eval_shallow_fast_x_reg`
- 初版尝试：
  - x-dominant 浅角度且 `abs(delta_x)` 足够大时，dominant queue 从 `2/3-step` 改成 `3/4-step`
- 收窄后保留条件：
  - 只有同时满足“x 步幅较大”且“已经接近 x 边界”时，才允许升级到 `3/4-step`

验证结果：
- `proxy_rotate15_on`
  - 初版自适应日志：[proxy_dom_queue_proj_adapt1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_proj_adapt1/proxy15.log)
  - 对比 Follow-up 11：
    - `req_cycles: 5582226 -> 5582150`
    - `cache_misses: 9279 -> 9282`
    - `cache_prefetch: 3082 -> 3080`
    - `cache_hits: 1614 -> 1613`
  - 结论：
    - 周期只改善极小量
    - miss/hit 反而略退
    - 说明 `3/4-step` 触发过于频繁
- 收窄后的近边界自适应日志：
  - [proxy_dom_queue_proj_adapt2/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_proj_adapt2/proxy15.log)
  - 与 Follow-up 11 完全一致：
    - `req_cycles=5582226`
    - `cache_misses=9279`
    - `cache_prefetch=3082`
    - `cache_hits=1614`
    - `domq=32158/31575/583`

当前结论：
- 自适应 `3/4-step` 这个方向本身没有带来额外收益。
- 收窄到“近边界才升级”后，行为退回到 Follow-up 11 的 projected 基线。
- 当前最优保留版本仍是 Follow-up 11 的 projected future tile 方案。

### Rotation Cache Follow-up 13

目标：
- 直接细化 dominant queue 的 event 选择逻辑，减少和近端 scheduler 的重合，而不是继续调 lookahead 步数。

尝试 1：
- 按 x-dominant 的“热区/近端 x scheduler”做 x 维粗过滤：
  - 若 projected tile 的 `tile_x` 仍落在当前请求热区 x 边界，或与 `scheduler_x` 的 `tile_x` 相同，则不入 dominant queue。

验证结果：
- `proxy_rotate15_on`
  - 日志：[proxy_dom_queue_eventsel1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_eventsel1/proxy15.log)
  - 结果退回旧稳定值：
    - `req_cycles=5582600`
    - `cache_misses=9276`
    - `cache_prefetch=3080`
    - `cache_hits=1606`
    - `domq=0/0/0`
  - 结论：
    - 这层 x 维粗过滤过于激进，几乎把 dominant queue 整体杀掉了。
    - 不属于我们要的“更聪明的选择”，因此不保留。

尝试 2：
- 收窄成 exact tile 级别过滤：
  - 只有当 `dom_seed0` 与 `scheduler_x` 完全同 tile 时，才丢弃并用 `dom_seed1` 顶上。
  - `dom_seed1` 只在与 `scheduler_x` 或 `dom_seed0` 完全同 tile 时丢弃。

验证结果：
- `proxy_rotate15_on`
  - 日志：[proxy_dom_queue_eventsel2/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_eventsel2/proxy15.log)
  - 对比 Follow-up 11：
    - `req_cycles: 5582226 -> 5582270`
    - `cache_misses: 9279 -> 9279`
    - `cache_prefetch: 3082 -> 3081`
    - `cache_hits: 1614 -> 1613`
    - `domq: 32151/31568/583 -> 23652/23069/583`
  - 结论：
    - dominant queue 没被杀掉，但有效消费和顶层收益都略退。
    - 说明单纯“避开近端 scheduler_x 重合”并不能提升候选质量，反而减少了可用 future event。

最终处理：
- 两个 event-selection 版本都已回退。
- RTL 保持在 Follow-up 11/12 的 projected future tile 稳定版。

当前结论：
- event 选择逻辑不能只靠“过滤与近端 scheduler 的重合”来变聪明。
- 下一步若继续优化，应改成“基于跨 tile 边界时刻/首次离开热区时刻”的事件生成，而不是在现有 `2-step/3-step` projected tile 上做静态丢弃。

### Rotation Cache Follow-up 14

目标：
- 直接尝试“基于 x 边界跨越时刻”的 dominant event 生成。
- 不是继续固定取 `pred2/pred3`，而是扫描 `pred1..pred4`，找出第 1/2/3 个真正跨入新 x tile 的 projected event，再据此给 dominant queue 选 seed。

RTL尝试：
- 对 x-dominant 浅角度场景：
  - 正向扫描 `pred1/pred2/pred3/pred4` 的 `tile_x01`
  - 反向扫描 `pred1/pred2/pred3/pred4` 的 `tile_x00`
- 只要 projected sample 第一次进入新的 x tile，就记为第一个 crossing event；之后再找第二、第三个不同 x tile。
- dom queue 优先取更远的 crossing：
  - 有 3 个 crossing 时，取第 2/3 个
  - 有 2 个 crossing 时，取第 1/2 个
  - 只有 1 个 crossing 时，退化成只发 1 个 seed

验证结果：
- `proxy_rotate15_on`
  - 日志：[proxy_dom_queue_cross1/proxy15.log](/C:/Users/huawei/Desktop/project_codex/sim_out/proxy_dom_queue_cross1/proxy15.log)
  - 对比 Follow-up 11：
    - `req_cycles: 5582226 -> 5612456`
    - `cache_misses: 9279 -> 9753`
    - `cache_prefetch: 3082 -> 2615`
    - `cache_hits: 1614 -> 749`
    - `domq: 32151/31568/583 -> 43078/42415/1599`
  - 结论：
    - 直接把“最早 crossing 序列”喂给 dominant queue 会显著退化。
    - 根因不是队列没工作，反而是工作得太多、太近：
      - `domq` 非空和被消费都明显升高
      - 但命中价值大幅下降，说明 crossing-based seed 把大量近端、低价值事件重新塞回了队列

最终处理：
- 本轮 crossing-based seed 已全部回退。
- RTL 保持在 Follow-up 11/12 的 projected future tile 稳定版。

当前结论：
- “基于边界跨越时刻”这个思路本身不能直接等价成“按 crossing 顺序选 future tile”。
- 如果后续还要继续用 crossing 信息，应该把它作为：
  - projected seed 的距离修正
  - 或 scheduler / dominant 的优先级修正
- 而不是把 crossing event 本身直接塞进 dominant queue。
