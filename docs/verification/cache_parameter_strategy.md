# Cache 参数策略文档

最后更新：2026-04-26

本文档用于逐步沉淀不同输入规格下的 cache 参数选择策略，目标覆盖工程要求：输入图小于 `7200x7200`，输出图小于 `600x600`，旋转角度 `0-90` 度。

这里记录的不是一次性结论，而是会随着仿真和 RTL 优化持续更新的参数矩阵。每个推荐都必须有来源日志、状态和适用范围，避免把某个单一 case 的最优点误当成全局默认。

## 当前默认与证据状态

2026-04-25 检查到的当前 RTL 默认值：

| 区域 | 默认值 | 含义 |
| --- | --- | --- |
| top 兼容 tile 宏 | `IMAGE_GEO_SRC_TILE_W=64`，`IMAGE_GEO_SRC_TILE_H=8`，`IMAGE_GEO_SRC_TILE_NUM=24` | 仍保留的 legacy/top cache 尺寸参数。 |
| sector cache 基本粒度 | `BASE_TILE_W=8`，`BASE_TILE_H=8` | 自适应 cache 的 micro-tile 存储粒度。 |
| sector 容量 | `SET_NUM=64`，`WAY_NUM=4` | 256 个 sector，8-bit 像素下约 16 KiB 数据容量。 |
| analytic 队列 | `ANALYTIC_FIFO_DEPTH=32`，`ANALYTIC_LEAD_PIXELS=64` | 解析未来窗口的默认深度和提前量。 |
| DDR 横向合并 | `MERGE_MAX_X=8` | 最多合并为 `64` bytes x `8` rows 的横向 run。 |

状态标记：

- `proven`：smoke 通过，并且已有可比较的性能日志。
- `candidate`：方向合理，但 benchmark 覆盖还不够。
- `unsafe`：存在 timeout、Fatal、协议风险或正确性失败。
- `needs sweep`：还没有可信数据，需要补 sweep。

## 初始推荐矩阵

| 输入规格 | 角度范围 | 推荐参数 | 状态 | 证据 / 原因 |
| --- | --- | --- | --- | --- |
| `1000x1000 -> 600x600` | `0` | 固定 tile 参考：`128x8,N=16/24,FIFO=16`；自适应候选：`8x8,SET64,WAY4,FIFO32,MERGE8,LEAD64` | 固定 tile 为局部有效；自适应为 `candidate` | 固定 `128x8,N=24` 达到 `8.951M cycles`、`919 misses`，但 rotate15 下 128 byte row 曾 timeout，不能当全局默认。 |
| `1000x1000 -> 600x600` | `<=15` | 固定 tile 参考：`64x16,N=24,FIFO=16`；自适应候选仍为 `8x8,SET64,WAY4,FIFO32,MERGE8,LEAD64` | 固定参考为 `proven`，自适应为 `candidate` | `64x16,N=24` 达到 `27.747M cycles`、`3194 misses`，优于 `64x8,N=24` 的 rotate15 结果。 |
| 小图约 `64x64 -> 24x24` | `45` smoke | 任何候选配置都必须达到或优于当前 smoke：`misses=2` 且无 timeout | `proven smoke` | `64x8,N=24` 和 `64x16,N=24` 都通过；此项主要作为回归保护，不是主性能目标。 |
| 近似 `640x640 -> 600x600` | `0-90` | 自适应候选：`8x8,SET64,WAY4,FIFO32,MERGE4/8,LEAD16/32/64` | `needs sweep` | 近似等比例输入复用较强，lead 太大可能自我驱逐，优先扫小 lead。 |
| 约 `1920x1080 -> 600x338` | `0,15,45` | 自适应候选：`8x8,SET64,WAY4,FIFO32,MERGE8,LEAD32/64/96` | `needs sweep` | 代表 HD 宽高比输入，需要验证非方形图像下的 row crop 和访问局部性。 |
| 大缩放约 `7200x7200 -> 600x600` | `0` | 自适应候选：`8x8,SET64,WAY4,FIFO32/64,MERGE8,LEAD64/128` | `needs sweep` | 大固定 tile 可能严重 overfetch，micro-tile 应能减少无效 DDR 读取。 |
| 大缩放约 `7200x7200 -> 600x600` | `15,45,75` | 保守自适应候选：`8x8,SET64,WAY4,FIFO32/64,MERGE4/8,LEAD32/64` | `needs sweep` | 旋转会打散未来窗口；在 128 byte row timeout 被证明修复前，默认 merge 不超过 64 byte row。 |

## 参数选择规则

- 正确性优先：任何参数组合只要有 `Fatal`、timeout、输出不匹配、AXI queue overflow/underflow，就不能作为推荐默认值。
- 最终排序看 `cycles`，但诊断必须同时看 `misses`、`reads`、`evict_unused`、`analytic_blocked`、FIFO 占用和 merge shrink。
- 如果 `misses` 高但 `analytic_blocked` 低，优先增加 lead 或改善 future window 覆盖。
- 如果 `evict_unused` 高，优先减小 lead 或 FIFO depth，不要盲目加容量。
- 如果 miss 已经下降但 cycles 仍高，瓶颈很可能转到 DDR/read task 开销；可以尝试更大的 merge 或 burst 参数，但在 `128` byte row rotate timeout 被证明修复前，默认保持 `MERGE_MAX_X<=8`。
- 如果 FIFO 经常满，或者候选常被 protected sector 阻塞，先比较 `FIFO=32` 和 `FIFO=64`，再讨论更大容量或更多 way 的资源代价。
- 针对 PYNQ-Z2，默认资源点先保持 `SET64/WAY4`，除非综合数据证明更大 way 数可以接受。

## 大比例缩小 scale bucket 策略

定义：

```text
scale_x = src_w / dst_w
scale_y = src_h / dst_h
scale_ratio = max(scale_x, scale_y)
```

分类建议：

| scale bucket | 范围 | 策略 |
| --- | --- | --- |
| near / mild scale | `scale <= 2` | 当前解析式 cache + bilinear 主链路继续优化。 |
| medium scale | `2 < scale <= 4` | 当前解析式 cache + bilinear 主链路仍作为主方案。 |
| large scale | `4 < scale <= 8` | 当前主链路可用于功能验证，但需要记录 aliasing 风险；同时进入 `large_downscale_preprocess` candidate。 |
| very_large scale | `scale > 8` | 不建议只靠 direct bilinear + cache 参数优化；需要评估 prefilter / area / box / multi-stage downscale。 |

特别标注：

- `7200 -> 600` 的 `scale_ratio ~= 12`，属于 very_large downscale。
- 该场景不能只靠 tile/lead/fifo/merge 参数解决质量问题。
- cache/prefetch 解决的是“访问效率”：读哪些 tile、何时读、怎么合并读。
- prefilter/area/multistage 解决的是“大比例缩小时的采样质量和局部性”：先降低源图高频能量，再交给现有旋转/缩放链路。
- 当前主线 RTL 不变；`rotate_core_bilinear`、`src_tile_cache` 和 `image_geo_top` 主数据通路不因该研究分支调整。
- 大比例缩小作为 `large_downscale_preprocess` 研究分支，不作为当前默认功能，也不替代 `timing_safe_smallconfig` gate。

## 必跑 Sweep 矩阵

这里每一行完成后，都要同步在 `cache_optimization_iteration_log.md` 中追加对应记录。

| Sweep ID | Source | Dst | Angle | Params | 通过用例 | Cycles | Reads | Misses | Merge/FIFO 备注 | 状态 |
| --- | --- | --- | ---: | --- | --- | ---: | ---: | ---: | --- | --- |
| sector-v1-1000-downscale | `1000x1000` | `600x600` | 0 | `8x8,SET64,WAY4,FIFO32,MERGE8,LEAD64` | pending | | | | | planned |
| sector-v1-1000-rot15 | `1000x1000` | `600x600` | 15 | `8x8,SET64,WAY4,FIFO32,MERGE8,LEAD64` | pending | | | | | planned |
| sector-v1-7200-downscale | `7200x7200` | `600x600` | 0 | `8x8,SET64,WAY4,FIFO32/64,MERGE8,LEAD64/128` | pending | | | | | planned |
| sector-v1-7200-rotate | `7200x7200` | `600x600` | 15/45/75 | `8x8,SET64,WAY4,FIFO32/64,MERGE4/8,LEAD32/64` | pending | | | | | planned |
| sector-v1-hd-aspect | `1920x1080` | `600x338` | 0/15/45 | `8x8,SET64,WAY4,FIFO32,MERGE8,LEAD32/64/96` | pending | | | | | planned |
| sector-v1-near-identity | `640x640` | `600x600` | 0/45 | `8x8,SET64,WAY4,FIFO32,MERGE4/8,LEAD16/32/64` | pending | | | | | planned |

## 防卡死仿真策略

- cache perf 工作中不要裸跑长时间 `xvlog`、`xelab` 或 `xsim`。
- top perf 单 case 使用 `tools/run-cache-perf-case.ps1`，并显式设置 `-CompileTimeoutSec`、`-ElabTimeoutSec` 和 `-SimTimeoutSec`。当前 top perf 建议起点为 `300/300/900` 秒。
- 每次 sweep 只跑一个参数组合、一个 case、一个进程。不要在没有单 case 验证的情况下直接启动多小时 batch。
- timeout 后保留日志目录，并在 `cache_optimization_iteration_log.md` 追加 `unsafe` 记录；如果没有新的假设或修复，不要重复跑同一配置。
- 任何新增 runner 或自定义脚本，在用于无人值守运行前，都必须实现 timeout 后清理 `xsim`、`xelab`、`xvlog` 残留进程。
## 自动参数优化流程（2026-04-25 新增）

后续参数推荐必须来自可重复流水线，不能只靠人工猜测。固定入口见 `docs/verification/cache_parameter_sweep_workflow.md`。

推荐执行顺序：

1. `scripts/gen_param_header.py`：生成参数 define header。
2. `scripts/run_cache_sweep.py`：用快速软件/cache 模型做大规模粗扫。
3. `scripts/run_rtl_shortlist.py`：对快速模型 top N 参数跑带 timeout 的 RTL shortlist。
4. `scripts/run_synth_shortlist.py`：对最终候选做资源估算，必要时再跑 Vivado。
5. `scripts/report_pareto.py`：生成 `pareto_summary.csv` 和 `recommendations.csv`。

当前只完成 smoke 级验证：

| 文件 | 状态 | 说明 |
| --- | --- | --- |
| `sim_out/cache_sweep/smoke_fast_model.csv` | pass | 快速模型小规模 smoke 输出。 |
| `sim_out/cache_sweep/mini_param_sweep.csv` | pass | 快速模型小规模参数变化样例，不作为最终推荐。 |
| `sim_out/cache_sweep/rtl_shortlist_dry.csv` | pass | RTL shortlist dry-run 输出，未启动长 RTL 仿真。 |
| `sim_out/cache_sweep/synth_shortlist_est.csv` | pass | 资源估算输出。 |
| `sim_out/cache_sweep/report_smoke2/recommendations.csv` | pass | 推荐表生成 smoke。 |

这些 smoke 文件只证明流程能跑通，不能当作最终参数结论。正式推荐必须来自完整 workload matrix、RTL bit-exact 验证和资源/时序筛选。

## 2026-04-25 收口更新：统计、CDC、DDR 参数

本轮新增的默认可扫 DDR 读写参数如下，后续推荐表必须同时记录 cache 参数和 DDR 参数，不能只记录 tile/lead/fifo：

| 参数 | 当前默认 | 第一轮允许扫描值 | 说明 |
| --- | ---: | --- | --- |
| `IMAGE_GEO_RD_BURST_MAX_LEN` | `16` | `8,16,32,64` | 影响 DDR read burst 长度。 |
| `IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS` | `4` | `2,4,8` | 影响 AXI read outstanding burst 数。 |
| `IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS` | `16` | `16,32,64,128` | 影响 read FIFO/背压前可挂起 beat 数。 |
| `IMAGE_GEO_RD_FIFO_DEPTH_WORDS` | `64` | `64,128,256` | 读 FIFO 深度，必须覆盖 outstanding beat 预算。 |
| `IMAGE_GEO_WR_BURST_MAX_LEN` | `16` | 暂不作为首轮 sweep 主变量 | 写回路径后续再扫。 |
| `IMAGE_GEO_WR_FIFO_DEPTH_PIXELS` | `256` | 暂不作为首轮 sweep 主变量 | 写 FIFO 深度后续再扫。 |

统计读取策略：

- 旧地址 `0x028/0x02C/0x030/0x034` 保留，继续分别返回 read starts、misses、prefetch starts、prefetch hits。
- 扩展统计从 `0x040` 起，每个 32-bit word 一个统计项；word0 是 `stats_version`，word1 是 `stats_snapshot_id`。
- 正式 sweep CSV 至少要包含 `sample_stall_cycles`、`read_busy_cycles`、`read_bytes_total`、`fifo_max_occupancy`、`analytic_blocked`、`replacement_fail_cycles`、`miss_latency` 和 `merge_len_hist`。

baseline matrix 已固化到 `sim_out/cache_baseline/baseline_workloads.csv`。当前 `sim_out/cache_baseline/baseline_report.csv` 已完成快速模型 off/on 对比，但仍不代表 RTL 性能结论：

| 维度 | 覆盖 |
| --- | --- |
| 尺寸 | `7200x7200`、`7200x4096`、`4096x7200`、`1920x1080`、`1024x1024` 到 `600x600` |
| 角度 | `0,1,3,5,15,30,45,60,75,90` |
| stride | packed、64-byte aligned、unaligned+padded |
| prefetch | off、on_default |

下一轮若开始 baseline，必须一组 workload 一个进程、一个输出目录，并先比较 prefetch off/on；如果 prefetch on 变慢，必须用扩展统计解释原因。

## 2026-04-26 Baseline 子集初步结论

本节只记录快速模型和轻量 RTL smoke 的阶段性结论，不作为最终推荐。完整 baseline matrix 已完成快速模型层执行，后续仍需按 shortlist 分批做 RTL bit-exact 验证。

快速模型子集：

| 文件 | 参数 | 覆盖 | 结果 | 状态 |
| --- | --- | --- | --- | --- |
| `sim_out/cache_baseline/baseline_subset_fast.csv` | `8x8,SET64,WAY4,MERGE8,FIFO32,LEAD64,RD16/OB4/BEATS16` | 5 类尺寸 x 5 个角度，packed stride，prefetch off/on | prefetch on 在 `19/25` 个 workload 上更快，在 `6/25` 个 workload 上变慢 | `fast-model only` |
| `sim_out/cache_baseline/baseline_subset_summary.md` | 同上 | 同上 | 明确标出大图 `45/75` 度下 prefetch on 可能变慢 | `diagnostic` |
| `sim_out/cache_baseline/baseline_report.csv` | 同上，读服务估算考虑 stride 和 4KB 边界 | 5 类尺寸 x 10 个角度 x 3 类 stride，prefetch off/on | prefetch on 在 `120/150` 个 workload 上更快，在 `30/150` 个 workload 上变慢 | `fast-model baseline` |
| `sim_out/cache_baseline/baseline_summary.md` | 同上 | 同上 | 完整 baseline 快速模型摘要 | `diagnostic` |

轻量 RTL 成对验证：

| Case | Prefetch | Cycles | Reads | Misses | Prefetches | Hits | Read bytes | Evict unused | 状态 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `small_rotate45` | off | 26,840 | 78 | 78 | 0 | 0 | 4,992 | 0 | pass |
| `small_rotate45` | on | 23,072 | 101 | 29 | 72 | 61 | 6,848 | 15 | pass |

当前参数策略更新：

- `8x8,SET64,WAY4,MERGE8,FIFO32,LEAD64` 可以继续作为自适应 cache 的默认候选，但不是最终推荐。
- 对 `7200x7200/7200x4096/4096x7200 -> 600x600` 且角度接近 `45/75` 度的场景，默认 prefetch 可能因为读放大、FIFO 过早、merge 方向不匹配而变慢；这些场景下一轮优先验证 `MERGE4`、更小 `LEAD`、prefetch throttle、row-bucket merge。
- 完整快速模型显示 `30/45/60/75` 度的大图 workload 是主要退化来源；下一轮 scheduler A/B 应优先覆盖这些角度，而不是只看 `0/15/90`。
- 对 `1920x1080`、`1024x1024`、以及 `0/15/90` 度这类较规则访问，当前默认候选在快速模型中大多更快，可以作为精扫的起点。
- 任何最终推荐都必须来自 RTL bit-exact + 扩展统计 + 资源/时序筛选，快速模型只负责缩小候选范围。

## 2026-04-26 Scheduler A/B 记录

快速模型增加了 scheduler 策略参数：

| 参数 | 默认 | 说明 |
| --- | ---: | --- |
| `MERGE_MIN_X` | 1 | FIFO head 形成至少多少连续 sector 才优先发射。 |
| `FIFO_AGE_LIMIT` | 0 | 非 0 时，FIFO head 等待超过该周期后允许短 merge 发射。 |
| `PREFETCH_THROTTLE` | 0 | 快速模型开关，后续用于验证 real miss 后暂停 speculative prefetch 的收益。 |

第一组 A/B：

| 配置 | 数据 | 结论 |
| --- | --- | --- |
| 默认 `MERGE_MIN_X=1` | `sim_out/cache_baseline/baseline_report.csv` | 当前默认候选，prefetch on 在 `120/150` workload 快于 off。 |
| `MERGE_MIN_X=4,FIFO_AGE_LIMIT=200` | `sim_out/cache_baseline/baseline_merge_min4_age200.csv`，对比表 `merge_min4_age200_vs_default.csv` | 相对默认 prefetch-on：`48` 个 workload 改善，`30` 个退化，`72` 个持平，总 delta `+134,790` cycles；不能作为全局默认。 |

策略结论：

- `MERGE_MIN_X=4` 对某些大图小角度/规则方向有帮助，但会明显伤害 `large_wide_a90` 这类访问方向不适配的 workload。
- 后续不应只扫一个全局 merge threshold；更合理的方向是按角度/主访问方向切换 merge 策略，或者实现 row-bucket merge。

## 2026-04-26 RTL Scheduler 接入与模型校准状态

RTL 已接入以下 scheduler 宏，默认保持旧行为：

| 宏 | 默认值 | 状态 |
| --- | ---: | --- |
| `SRC_TILE_CACHE_ENABLE_MERGE_MIN` | 0 | 已接入 RTL 和脚本。 |
| `SRC_TILE_CACHE_MERGE_MIN_X` | 1 | 已接入 RTL 和脚本。 |
| `SRC_TILE_CACHE_FIFO_AGE_LIMIT` | 0 | 已接入 RTL 和脚本。 |
| `SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE` | 0 | 已接入 RTL 和脚本。 |
| `SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES` | 0 | 已接入 RTL 和脚本。 |

默认行为校验：

| Case | 当前结果 | 对比 |
| --- | --- | --- |
| `small_rotate45_off` | `cycles=26840 reads=78 misses=78` | 与上一轮一致。 |
| `small_rotate45_on` | `cycles=23072 reads=101 misses=29 prefetches=72 hits=61` | 与上一轮一致。 |

模型校准提醒：

| 文件 | 结论 |
| --- | --- |
| `sim_out/model_rtl_calibration/model_rtl_error_summary.md` | 当前快速模型对 `small_rotate45` 低估 `26-35%` cycles，超过 10% 阈值。 |

因此下一步不能直接扩大 RTL sweep。先校准模型固定开销、CDC/task 往返、写回和短帧启动/收尾开销，再用 RTL shortlist 验证。

## 2026-04-26 校准后策略状态

快速模型现在支持显式校准项，当前小样本校准参数为：

| 参数 | 当前校准值 | 说明 |
| --- | ---: | --- |
| `rtl_frame_overhead` | 5200 | 小帧启动、收尾、CDC/task 等固定开销的合并近似。 |
| `rtl_demand_miss_extra_cycles` | 54 | real miss 服务在 RTL 中相对快速模型的额外等待近似。 |
| `rtl_prefetch_fill_extra_cycles` | 0 | 暂未单独校准。 |
| `rtl_read_start_extra_cycles` | 0 | 暂未单独校准。 |

校准后 `small_rotate45` 结果：

| Case | Raw model | Calibrated model | RTL | Error |
| --- | ---: | ---: | ---: | ---: |
| prefetch off | 17,424 | 26,836 | 26,840 | -0.01% |
| prefetch on | 16,889 | 23,331 | 23,072 | +1.12% |

使用限制：

- 后续又加入 `cal128_rotate45` 轻量校准点，当前同一组校准参数下误差为 off `-3.13%`、on `+5.49%`，仍低于 10% 门槛。
- 这组校准证明小帧和轻中等帧入口可用，但不能直接外推到 `7200->600`、`1920->600` 或 `2048->256`。
- `mid_rotate45_off` 在 120 秒 RTL 上限内未完成，不能作为校准点；下一轮应继续增加 `128/256` 级轻量角度点，或优化 testbench 运行速度后再扩大 RTL 校准集合。
- Vivado 报告入口已建立；`-Mode rtl -SmallConfig` 可在约 56 秒内完成 RTL elaboration 并生成 `reports/report_elaboration_status.rpt`，但正式 `synth/report_cdc/report_timing_summary` 仍在 120/300 秒上限内未完成。
- 后续参数推荐表必须标注数据来源：`fast-model raw`、`fast-model calibrated-small-only`、`RTL small`、`RTL shortlist`、`synth/report`。只有 `RTL shortlist + synth/report` 通过的组合才能升级为正式推荐。

轻量 RTL 校准点：

| Workload | Prefetch | Raw model | Calibrated model | RTL | Error | 状态 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `small_rotate45` | off | 17,424 | 26,836 | 26,840 | -0.01% | 可用于校准 |
| `small_rotate45` | on | 16,889 | 23,331 | 23,072 | +1.12% | 可用于校准 |
| `cal128_rotate45` | off | 96,912 | 125,764 | 129,834 | -3.13% | 可用于校准 |
| `cal128_rotate45` | on | 100,925 | 114,873 | 108,898 | +5.49% | 可用于校准 |

## 2026-04-26 多角度校准拦截结论

新增 `cal128_rotate0/15/75/90_off/on` 后，当前同一组小样本校准参数不能覆盖所有角度。`sim_out/model_rtl_calibration/model_rtl_error_summary_smallfit.md` 的结论是：

- Compared rows: `12`
- Error threshold: `10%`
- Max abs error: `76.50%`
- Trusted for RTL shortlist expansion: `no`

轻量多角度结果：

| Workload | Prefetch | Calibrated model | RTL | Error | 状态 |
| --- | --- | ---: | ---: | ---: | --- |
| `cal128_rotate0` | off | 76,624 | 94,708 | -19.09% | 模型不可信 |
| `cal128_rotate0` | on | 23,253 | 98,936 | -76.50% | 模型严重低估 |
| `cal128_rotate15` | off | 73,924 | 92,888 | -20.42% | 模型不可信 |
| `cal128_rotate15` | on | 47,552 | 80,936 | -41.25% | 模型严重低估 |
| `cal128_rotate45` | off | 125,764 | 129,834 | -3.13% | 当前可用 |
| `cal128_rotate45` | on | 114,873 | 108,898 | +5.49% | 当前可用 |
| `cal128_rotate75` | off | 73,384 | 92,524 | -20.69% | 模型不可信 |
| `cal128_rotate75` | on | 58,727 | 83,570 | -29.73% | 模型不可信 |
| `cal128_rotate90` | off | 76,624 | 94,708 | -19.09% | 模型不可信 |
| `cal128_rotate90` | on | 61,445 | 89,042 | -30.99% | 模型不可信 |

策略更新：

- 不能用当前 fast model 的 `total_cycles_est` 扩大 RTL shortlist，也不能据此生成最终推荐表。
- 当前模型只能临时用于观察趋势和生成诊断候选；凡涉及“最快参数”的判断，必须等待模型重新校准后再做。
- 下一轮模型校准要优先解释 `0/15/75/90` 的固定节拍差异和 prefetch-on 过度乐观问题，而不是继续扩大 workload 数量。
- 在模型可信前，RTL 只跑轻量校准点和少量 smoke；避免回到长时间卡死的跑法。

## 2026-04-26 轻量线性校准后状态

基于扩展统计和 `small_rotate45 + cal128_rotate0/15/45/75/90` off/on 共 12 个轻量 RTL 点，当前快速模型已经补了一层经验线性校准。最新文件：

- 参数：`sim_out/model_rtl_calibration/linear_calibration_params.json`
- 拟合摘要：`sim_out/model_rtl_calibration/linear_calibration_fit.md`
- 对比摘要：`sim_out/model_rtl_calibration/model_rtl_error_summary_linear_smallfit.md`

当前拟合参数：

| 参数 | 值 | 说明 |
| --- | ---: | --- |
| `rtl_frame_overhead` | `152.428491` | 经验截距。 |
| `rtl_raw_cycle_scale` | `-0.387150` | 经验回归项；当前为负，说明特征相关性强，不能作物理解释。 |
| `rtl_dst_pixel_extra_cycles` | `27.035176` | 输出像素固定节拍/写回尾部等合并项。 |
| `rtl_demand_miss_extra_cycles` | `95.250717` | demand miss 额外代价经验项。 |
| `rtl_prefetch_fill_extra_cycles` | `31.443590` | prefetch fill 额外代价经验项。 |
| `rtl_read_sector_extra_cycles` | `126.693846` | DDR read sector 额外代价经验项。 |

最新误差：

| 校准集 | 行数 | 最大绝对误差 | 状态 |
| --- | ---: | ---: | --- |
| `small_rotate45 + cal128 multi-angle` | 12 | `8.77%` | `smallfit trusted` |

使用边界：

- 这组校准只允许用于轻量 shortlist 粗筛，不能直接外推到 `7200->600` 或最终推荐。
- 一旦加入 `256` 级或真实 workload RTL 点，必须重新运行 `scripts/fit_model_calibration.py`，不能继续沿用这组参数。
- 如果重新比较后最大误差超过 `10%`，必须停止扩大 sweep，先修模型。
- `rtl_raw_cycle_scale` 为负是一个提醒：当前模型仍然不是完全物理化的 DDR/cache pipeline 模型，后续应继续把 `read_busy_cycles`、`sample_stall_cycles` 和 write tail 拆成更明确的预测项。

## 2026-04-26 资源/报告入口状态

本轮已把 `src_tile_cache` 和 `row_out_buffer` 的主要存储改成 packed/linear 结构，`tools/run-vivado-reports.ps1 -Mode rtl -SmallConfig -TimeoutSec 120` 已经能稳定完成 RTL elaboration，并且最新日志不再出现 cache/row 相关 3D RAM warning。

仍未完成：

- `tools/run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 120` 仍 timeout。
- 正式 `report_cdc.rpt`、`report_clock_interaction.rpt`、`report_exceptions.rpt`、`report_timing_summary.rpt` 还不能作为通过结论。
- 因此参数推荐表中的资源/时序状态仍必须标记为 `needs synth/report`，不能写成 `proven`。

## 2026-04-26 cal128 轻量 RTL shortlist 结果

这一节只适用于 `128x128 -> 48x48` 轻量校准域，用来指导下一轮 shortlist 的候选生成；不能直接作为大图最终推荐。

| 角度类 | 当前较优 RTL 参数 | 对默认 `8x8,m8,f32,l64` 的变化 | 状态 | 说明 |
| --- | --- | ---: | --- | --- |
| `0/90` 正交方向 | `16x16,MERGE4,FIFO16,LEAD16` | `rotate0 -19.21%`，`rotate90 -9.87%` | `cal128 proven` | 规则方向源 tile 复用稳定，短 lead 降低无效预取，大 tile 降低 tag/fill 频率。 |
| `15/75` 小/大斜角 | `16x16,MERGE4/8,FIFO16,LEAD64` | `rotate15 -7.62%`，`rotate75 -13.56%` | `cal128 candidate` | 仍需要较长 lead 覆盖 DDR/read 延迟，但大 tile 暂时收益为正。 |
| `45` 对角方向 | `16x8,MERGE4,FIFO16,LEAD64` | `rotate45 -35.79%` | `cal128 proven` | 对角访问下 `16x16,LEAD16` 会造成 read_bytes/sample_stall/read_busy 激增，矮 tile 更稳。 |

shortlist 选择规则更新：

- 后续每个 workload 不要只取 `total_cycles_est top1`。至少同时取：
  - `total_cycles_est top1`
  - `score top1`
  - 当前默认参数
  - 一个故意偏差参数作为 sanity
- 如果两个排序字段给出的候选冲突，优先用小 RTL 验证，不要直接相信 fast model。
- `rotate45` 的反例必须记住：`16x16,LEAD16` 的模型估计是 `63,840 cycles`，但 RTL 实际为 `133,234 cycles`，比默认还慢 `22.35%`。
- 下一步可以把这套候选策略扩展到 `256` 级轻量 workload；在 `256` 级仍稳定后，再尝试 `1000->600` 或真实 shortlist。

## 2026-04-26 cal256 尺度检查结果

`256x256 -> 96x96` 轻量 RTL 表明，`cal128` 的角度分桶规律只有一部分能迁移：

| 角度类 | `cal128` 结论 | `cal256` 结果 | 策略状态 |
| --- | --- | --- | --- |
| `0/90` 正交方向 | `16x16,LEAD16` 更快 | `16x16,LEAD16` 退化 `+21.79%/+17.64%`；`16x16,LEAD64` 仍退化 `+18.68%/+12.66%` | 对较长帧先保留默认 `8x8,LEAD64`，不要外推短帧结论。 |
| `45` 对角方向 | `16x8,LEAD64` 明显更快 | `16x8,LEAD64` 继续提升 `40.90%` | 该方向成为当前最可靠候选。 |

原因摘要：

- `cal256 0/90` 下 default `8x8,LEAD64` 的 prefetch hits 约 `1024`，而 `16x16` 候选只有约 `256`，即使 reads 更少，sample stall 仍显著增加。
- `cal256 45` 下 `16x8,LEAD64` 同时降低 read bytes、sample stall 和 read busy，说明矮 tile 对对角访问的 DDR 读放大控制有效。

策略更新：

- 后续参数分桶必须加入帧长/输出像素数，不再只按角度决定。
- 当前暂定：
  - 小帧正交：`16x16,LEAD16` 是候选。
  - 中帧及以上正交：继续以 `8x8,LEAD64` 为安全基线，等待更多 sweep。
  - 对角：`16x8,LEAD64` 是优先候选。
- 下一步优先补 `cal256 rotate15/75`，判断小角度/大角度是否需要 `16x16,LEAD64`，还是也应保持 `8x8`。

## 2026-04-26 cal256 rotate15/75 补充结论

`cal256 rotate15/75` 已补齐，结果说明中等帧下的角度分桶不能只按“离 45 度近不近”粗暴判断。

| 角度 | 默认 `8x8,m8,f32,l64` | `16x16,m8,f16,l64` | `16x8,m4,f16,l64` | 当前判断 |
| --- | ---: | ---: | ---: | --- |
| `15` | 320,082 | 324,610 `(+1.41%)` | 334,296 `(+4.44%)` | 默认最好，属于正交/小角度安全区。 |
| `75` | 312,852 | 306,052 `(-2.17%)` | 295,482 `(-5.55%)` | `16x8,LEAD64` 有小幅收益，接近斜向区。 |

中等帧 `256x256 -> 96x96` 当前推荐状态：

| 角度范围 | 候选参数 | 状态 | 依据 |
| --- | --- | --- | --- |
| `0/15/90` | `8x8,MERGE8,FIFO32,LEAD64` | `cal256 proven safe` | `16x16` 候选会降低 prefetch hit 覆盖，sample stall 上升。 |
| `45` | `16x8,MERGE4,FIFO16,LEAD64` | `cal256 proven` | 相对默认 `-40.90%` cycles。 |
| `75` | `16x8,MERGE4,FIFO16,LEAD64` | `cal256 candidate` | 相对默认 `-5.55%` cycles，收益较小但方向一致。 |

后续策略：

- 下一次 fast-model 拟合必须纳入 `cal256` 数据，否则模型仍会把短帧 `cal128` 的规律外推过头。
- 参数推荐表需要新增“输出像素规模/帧长”维度：小帧和中帧的正交方向最优参数已经不同。
- 在跑 `1000->600` 前，先用 `cal256` 数据重拟合模型，再用 `proxy 1024->256` 或更小真实比例 case 做一次 sanity。

## 2026-04-26 rich 模型与 proxy sanity

`cal256` 已纳入 fast-model 校准，当前 rich feature 模型在 `small/cal128/cal256` 26 个参数化 RTL 点上最大误差为 `6.61%`，文件为：

- `sim_out/model_rtl_calibration/rich_calibration_params_with_cal256.json`
- `sim_out/model_rtl_calibration/model_rtl_error_summary_rich_with_cal256.md`

但是 `proxy_rotate45` sanity 显示，模型仍不能外推到 `1024x1024 -> 256x256`：

| Params | Model cycles | RTL cycles | Error | Delta vs default |
| --- | ---: | ---: | ---: | ---: |
| `8x8,m8,f32,l64` | 3,950,146 | 5,999,702 | -34.16% | 0.00% |
| `16x8,m4,f16,l64` | 2,391,261 | 5,916,118 | -59.58% | -1.39% |

策略更新：

- `rich` 模型只在 `small/cal128/cal256` 校准域内可信，不能直接用于 `1024->256`、`1000->600` 或 `7200->600` 推荐。
- `16x8,LEAD64` 仍是对角方向候选，但收益随尺寸增大明显变弱；不能再写成“对角方向总是大幅提升”。
- proxy/full 模型 sweep 不能用 full 模式大网格，后续应改成 `scan` 模式或极窄参数集。
- 下一轮优化模型时，要显式加入输出像素规模或分段模型：`<=96x96`、`256x256`、`600x600` 不应共用同一组线性外推。

## 2026-04-26 Stage 3-5 更新：runtime knobs 与 proxy512 校准

当前状态：
- scheduler 已经具备运行时可调能力，结构参数仍为编译期：`BASE_TILE_W/H`、`SET_NUM/WAY_NUM`、物理 `MERGE_MAX_X`、物理 `ANALYTIC_FIFO_DEPTH`。
- 运行时可调参数包括：`lead_pixels`、`merge_max_x_eff`、`merge_min_x`、`fifo_depth_eff`、`fifo_age_limit`、`prefetch_throttle_cycles`、`scheduler_policy`。
- 默认 runtime policy=0 保持旧行为；非默认参数已通过 small smoke 证明可生效。

模型状态：
- 使用修复后的 raw model CSV 重新训练 rich 模型后，`small/cal128/cal256` 26 个带参数 RTL 点最大误差为 `2.14%`。
- 这只代表当前校准域可用，不能直接外推为 `1000->600` 或 `7200->600` 的 proven 结论。
- 旧缺字段 CSV 已标记为不适合 rich fit：缺少 `read_busy_cycles` 会污染 `stall_per_read_busy` 特征。

新增中尺度 RTL 证据：

| Workload | 参数 | cycles | read_bytes | sample_stall | read_busy | missed merge | 状态 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `proxy512_rotate45` | `8x8,m8,f32,l64` | 2,169,786 | 784,128 | 712,486 | 1,038,253 | 59,006 | proxy512 baseline |
| `proxy512_rotate45` | `16x8,m4,f16,l64` | 1,449,828 | 529,920 | 352,507 | 688,951 | 8,286 | proxy512 candidate |
| `cal256_rotate45` | `8x8,m8,f32,l64` | 516,004 | 181,632 | 163,899 | 243,427 | 12,979 | post-runtime regression check |

策略影响：
- `16x8,m4,f16,l64` 在 `proxy512_rotate45` 上仍然有效，相比默认约 `-33.18%` cycles；这比之前 `proxy1024_rotate45` 的收益更明显，说明不同 proxy 尺度仍需分别验证。
- `proxy512_rotate45` default 的 `merge_opportunity_missed_count=59,006`，说明 FIFO 中确实存在大量当前 head +X merge 没抓住的同 row 相邻机会；后续 row-bucket merge 值得单独 A/B，但本轮不能直接打开。
- `report_cdc` 和 timing 仍未过门槛，因此本表不能写成最终推荐，只能作为 candidate evidence。

下一轮优先级：
1. 先处理 `report_cdc.rpt` 中的 unsafe/unknown 分类，必要时继续收敛 stats/result/config/task CDC 或补详细约束说明。
2. 再看 small config timing 的主要失败路径；当前 small synth report 已生成，但 setup 仍违反，不能标记 timing proven。
3. 对 `proxy512` 补少量 `0/75/90` RTL shortlist，而不是扩大到完整 7200 matrix。
4. 如要做 row-bucket merge，必须新开分支，只做 `ENABLE_ROW_BUCKET_MERGE=1` A/B，不和其他调度机制混改。

## 2026-04-26 CDC/report gate 更新

本轮把 `frame_config_cdc`、`task_cdc`、`task_cdc_2d`、`result_cdc`、`cache_stats_cdc` 统一推进到 `async_word_fifo` / XPM async FIFO 路线，减少 bundled-data CDC 对后续参数优化可信度的影响。

当前门槛状态：
- 功能 smoke：通过。
- `report_cdc`：core/axi 两个方向已经没有 `Unsafe`，但仍有 XPM FIFO reset/control unknown，以及 OOC input port unsafe/unknown。
- `report_timing_summary`：small config 仍有 setup violation，不能标记 timing proven。
- 因此所有参数策略仍只能标记为 `candidate` 或 `calibration evidence`，不能标记为 `proven for hardware`。

后续优化策略约束：
1. 在 CDC/timing 完全收口前，不跑完整 7200 workload RTL matrix。
2. 允许继续跑小规模 RTL shortlist，但结论只能用于模型校准和候选筛选。
3. 如果新增 CDC 或 runtime knob，必须优先使用 FIFO 或明确的同步器结构，不再新增大 bundled payload toggle CDC。
4. 若要正式推荐参数组合，必须同时满足功能 pass、统计可信、CDC 分类清楚、small timing 至少可解释或过约束。

## 2026-04-26 replacement pipeline 后的 timing 状态

- `src_tile_cache` replacement/choose_way 已拆成多周期流水，`SmallConfig` core WNS 从约 `-8.354 ns` 收敛到 `-2.953 ns`。
- 当前最坏 core 路径已经不再是 FIFO/head 到 `fill_req_*`，而是 analytic planner candidate duplicate/block 到 `planner_eval_blocked_reg`。
- `SmallConfig` AXI WNS 仍为约 `-0.768 ns`，后续需要单独处理 `ddr_read_engine` read task 地址路径或 AXI skid/register slice。
- `SmallTimingSafe(8x8,SET32,WAY2,MERGE4,FIFO16,LEAD16)` 在 600 秒 timeout，不能作为 timing gate 结论。
- 参数推荐状态不变：所有 cache/tile/scheduler 组合仍是 `candidate`，不能写成硬件 timing-proven。

### 2026-04-26 timing 状态更新

- analytic planner enqueue/advance 已解耦，`SmallConfig` core WNS 进一步从 `-2.953 ns` 收敛到 `-1.510 ns`。
- 当前 core 最坏路径变为 sample hit/miss 捕获：`rotate_core_bilinear/sample_x0_reg -> src_tile_cache/sample_miss_pending_tile_x_reg/CE`。
- 这说明 replacement 和 planner duplicate/block 已不再是首要最坏路径；下一步若继续追 core timing，应系统性处理 sample lookup/ready/miss pipeline。
- AXI WNS 仍为 `-0.768 ns`，后续需要单独作为 AXI/read-task timing 轮次处理。
- `SmallConfig` 仍未 timing proven，只是已经达到阶段目标 `-2 ns` 内；参数策略状态仍保持 `candidate`。

### 2026-04-27 timing gate 与 scheduler A/B 状态更新

Timing 状态：
- `SmallConfig` 已生成正 WNS 报告：overall WNS `+0.051 ns`，AXI WNS `+0.051 ns`，core WNS `+0.184 ns`。
- 该结果只证明 `SmallConfig` / timing-safe profile 可以作为后续小矩阵 RTL gate，不代表高性能 profile 或最终硬件资源配置已经 proven。
- 参数策略文档中所有 `1000->600`、`7200->600`、高性能 tile 组合仍保持 `candidate/needs sweep`，不能因为 SmallConfig timing 过约束而升级为最终推荐。

Runtime scheduler A/B 观察：
- 已完成 48 组小矩阵 RTL A/B：`cal128/cal256/proxy512` 的若干 `0/15/45/75/90` 角度，policy 0/1/2/3 全部 pass。
- `merge_min_age` 在部分 workload 有小幅收益，但最大也低于 0.5%；不能设为全局默认。
- `throttle_on_miss=64` 当前基本没有独立收益，不应继续优先扫 throttle 数值。
- 0/90 度偏向 default；45/75 度有时受益于 `merge_min_age`，继续支持“按 workload 分类选择 scheduler policy”的方向。

Row-bucket 观察：
- 修正 extractor 后，`merge_opportunity_analysis.csv` 使用 `analytic_candidates` 作为分母重新计算。
- 45 度 workload 的 same-row 与 missed-merge 事件密度较高，例如 `proxy512_r45` default：`same_row/cand=1.227`、`missed/cand=0.830`、`avg_merge=1.488`、`merge1_ratio=0.516`。
- reverse-x 事件密度整体很低，例如 `proxy512_r45` default 只有 `0.035`。
- 因此下一步策略候选应是“小范围同 row bucket merge A/B”，不是完整 direction-aware merge 重写。

Row-bucket v0 A/B 结果：
- 已实现默认关闭的 `SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE=1` 实验分支，并在 `cal128_r45/cal256_r45/proxy512_r45` 上做 3 组 smoke。
- 结果全部 pass，但 cycles 全部小幅退化：
  - `cal128_r45`: `172086 -> 172352`，`+0.155%`
  - `cal256_r45`: `744170 -> 744494`，`+0.044%`
  - `proxy512_r45`: `3193896 -> 3221148`，`+0.853%`
- 虽然 reads/misses 下降，但 read_bytes/read_busy/sample_stall 上升，说明当前 v0 存在读放大和 FIFO stale 项问题。
- 策略状态：`unsafe/candidate only`，保持默认关闭。后续若继续，应先做多坐标 FIFO delete 与 read amplification guard。

Row-bucket v1 状态：
- `ROW_BUCKET_MIN_X=3` 可避免 v0 退化，但三个 45 度样本都退回 default，没有收益。
- `ROW_BUCKET_MIN_X=2 + 多坐标 FIFO delete` 可让 `cal256_r45` 小幅变快 `-0.516%`，但 `proxy512_r45` 仍退化 `+0.270%`。
- 更重要的是，多坐标 FIFO delete 破坏 SmallConfig timing，core WNS 退到 `-0.861 ns`，因此已回退。
- 当前策略结论：row-bucket 仍是 `unsafe`，只保留默认关闭入口；下一次若要继续，必须先把 FIFO 多删除做成独立多周期/后台结构，再重新过 timing gate。
## 2026-04-27 CDC/timing gate 更新

当前 `SmallConfig` 可以作为后续 RTL 小矩阵 gate：

| 项目 | 当前状态 |
| --- | --- |
| overall WNS | `+0.051 ns` |
| AXI WNS | `+0.051 ns` |
| core WNS | `+0.180 ns` |
| `report_exceptions` | 旧 bundled-data max-delay 的 `Invalid startpoint` 已清理 |
| 业务层 CDC | core/axi 双向 `Unsafe=0` |
| formal CDC | 仍需 XPM FIFO 内部项和 OOC input-port 项的 wrapper/waiver 分类 |

策略含义：
- 后续可以继续跑 `cal128/cal256/proxy512` 级别的 bounded RTL shortlist。
- 仍然不要直接启动完整 `7200->600` RTL workload matrix。
- 结构性 cache 参数、row-bucket、scheduler policy 仍需要逐项 A/B；不能因为 SmallConfig timing 过了就把某个性能参数标为全局 proven。
- 当前 row-bucket 仍保持 `unsafe/candidate only`，默认关闭。

经验约束：
- stats/config/task/result CDC 已经 FIFO 化，后续不要再为旧 bundled-data payload 加宽 regexp `set_max_delay`。
- 如果新增运行时控制或统计输出，优先走同步器或 FIFO；不要新增大宽度 bundled-data toggle CDC。
## 2026-04-27 timing_safe_smallconfig_2026_04_27

当前冻结一个 timing-safe gate，而不是高性能推荐配置。

| 项目 | 值 |
| --- | --- |
| Baseline id | `timing_safe_smallconfig_2026_04_27` |
| Git HEAD | `c7143cb` |
| SmallConfig | `8x8,set16,way2,merge2,fifo8,lead16` |
| overall WNS | `+0.051 ns` |
| AXI WNS | `+0.051 ns` |
| core WNS | `+0.180 ns` |
| Gate 用途 | 允许进入 bounded RTL shortlist |
| 非用途 | 不代表高性能 profile 或最终硬件推荐 proven |

后续策略：
- 任何参数/RTL 主线修改都必须保持该 timing gate 不回退到负 WNS。
- scheduler policy、row-bucket、tile shape 仍然只作为候选分桶分析，不固化为全局默认。
- 完整 `7200->600` RTL matrix 仍延后；先使用 `small/cal128/cal256/proxy512` 的 bounded shortlist 校准模型。
## 2026-04-27 Stage1 参数策略更新

本节只记录阶段性策略，不给最终推荐表。当前 `timing_safe_smallconfig_2026_04_27` 已作为 RTL gate 通过，但它是时序安全基线，不是高性能默认配置。

### Timing-safe gate

| 项目 | 状态 |
| --- | --- |
| Baseline id | `timing_safe_smallconfig_2026_04_27` |
| SmallConfig | `8x8,set16,way2,merge2,fifo8,lead16` |
| overall WNS | `+0.051 ns` |
| AXI WNS | `+0.051 ns` |
| core WNS | `+0.180 ns` |
| 用途 | 允许后续 bounded RTL shortlist |
| 非用途 | 不代表高性能 profile 或最终硬件推荐 proven |

### Stage1 shortlist 结论

数据来源：
- `sim_out/rtl_shortlist_stage1/results.csv`
- `sim_out/rtl_shortlist_stage1/results_enriched.csv`
- `sim_out/rtl_shortlist_stage1/summary.md`

当前阶段性观察：
- `cal256/proxy512` 比 `cal128` 更能暴露参数迁移问题；不能再用 cal128 结论直接外推。
- `model_top1/model_top2` 在中等帧和 proxy512 上经常明显优于 timing-safe default，但这些候选还没有经过完整 synth/timing/resource 筛选，只能标记为 candidate。
- `policy1 merge_min_age` 收益很小，多数低于 `0.5%`；仅 `cal256_r75` 约 `-0.61%`，属于按 workload 分桶的 candidate，不是全局默认。
- `policy2 throttle_on_miss` 当前没有明显独立收益，暂不继续盲扫 throttle 数值。
- `sanity_bad` 在 small/orthogonal case 可能胜出，说明该候选并不总是 bad；后续 sanity 配置需要重新定义，orthogonal bucket 也需要单独建模。

### 当前分桶状态

| Bucket | 状态 | 策略说明 |
| --- | --- | --- |
| small diagonal | `coarse only` | Stage1 empirical model 误差约 `19.17%`，不能用于 cycles 推荐。 |
| cal128 orthogonal | `coarse only` | 误差约 `13.94%`；正交访问需要单独建模。 |
| cal256 orthogonal | `candidate trusted` | Stage1 误差低，但仍只在当前 shortlist 内可信。 |
| proxy512 orthogonal | `coarse only` | 误差约 `141.23%`，禁止外推到 `7200->600`。 |
| diagonal cal128/cal256/proxy512 | `candidate trusted` | 当前 empirical bucket 内误差低，可用于下一轮 shortlist 粗筛。 |
| steep angle cal128/cal256/proxy512 | `candidate trusted` | 仍需 proxy1024 或更多 RTL 点验证。 |

### Row-bucket 状态

数据来源：
- `sim_out/merge_opportunity/analysis_stage1.csv`
- `sim_out/merge_opportunity/analysis_stage1.md`
- `docs/verification/row_bucket_v2_design.md`

结论：
- 45 度和部分 15 度 workload 存在 same-row/missed-merge 机会。
- 但是历史 v0/v1 已证明：直接 row-bucket 或多坐标 FIFO delete 会增加 read amplification 或破坏 timing。
- 下一步若继续，只能做 `ENABLE_ROW_BUCKET_MERGE_V2` 单独实验分支，默认关闭。

### 下一步门槛

1. 若 Stage1 模型误差超过 `10%` 的 bucket，不允许生成 cycles 推荐，只能粗筛。
2. 若继续扩大 RTL，优先跑 proxy1024 shortlist，而不是完整 `7200->600` matrix。
3. 若任何候选要升级为 proven，必须同时满足：功能 pass、SmallConfig/timing gate 不回退、CDC 分类无新增真实业务 unsafe、资源/时序报告可解释。
4. 不固化 `MERGE_MIN_X=4`、row-bucket 或任何单点 tile 参数为全局默认。
## 2026-04-27 proxy1024 策略补充

数据来源：
- `sim_out/rtl_shortlist_proxy1024/results.csv`
- `sim_out/rtl_shortlist_proxy1024/summary.md`
- `sim_out/model_calibration_stage2/model_rtl_error_summary_stage2.md`
- `sim_out/merge_opportunity_proxy1024/analysis_stage1.md`
- `sim_out/scheduler_policy_buckets_proxy1024/policy_bucket_stage1.md`

本轮只用于补充模型校准和候选筛选，不生成最终推荐。

### proxy1024 结果

| Workload | 当前 default | best pass candidate | 结论状态 |
| --- | ---: | --- | --- |
| `proxy1024_r0` | 6,096,090 | `model_top2` 5,501,186 | orthogonal candidate |
| `proxy1024_r15` | 7,467,950 | `model_top1` 6,761,548 | small-angle candidate |
| `proxy1024_r45` | 8,452,818 | `model_top2` 8,016,688 | diagonal candidate |
| `proxy1024_r75` | 7,823,170 | default 7,823,170 | 保持 default，`16x8` 风险高 |
| `proxy1024_r90` | 6,622,982 | `model_top2` 6,289,210 | orthogonal candidate |

### 参数含义更新

- `model_top2` 在 proxy1024 的 0/45/90 度胜出，说明 `8x8,set32,merge4,fifo16,lead64` 这一类“仍保持小 sector，但提高 set/merge/fifo/lead”的配置值得继续作为中大帧候选。
- `proxy1024_r75 model_top1(16x8,merge4,fifo16,lead64)` timeout，不能把 `16x8` 写成大角度通用推荐。
- `policy1 merge_min_age` 在 proxy1024 中收益为 marginal；不固化为默认。
- `sanity_bad` 在 proxy1024 多个角度 timeout，可继续作为压力反例，不作为推荐候选。

### 模型可信范围更新

- Stage2 合并校准仍是 empirical bucket average，不是物理模型。
- proxy1024 bucket 中许多配置是单点自拟合，即使报告误差为 `0%`，也只能标记为 `candidate / needs more RTL`。
- `proxy512 orthogonal` 在 Stage1 中误差极大，proxy1024 补点说明 orthogonal 必须按 frame class 独立建模，不能跨尺度直接外推。
- `7200->600` 仍未进入 RTL proven 范围。

### 下一步建议

1. 不跑完整 `7200->600` matrix。
2. 优先对 `orthogonal` 和 `75°` 做少量针对性补点：
   - `8x8,set32,merge4,fifo16,lead32/64/128`
   - default timing-safe
   - 一个明确 timeout/污染风险反例
3. 若要继续 row-bucket，只能开 V2 单独分支，并先在 `proxy1024_r45` 做 A/B。
4. 若要升级某组参数为 proven，必须补 small synth/timing/resource，而不是只看 RTL cycles。
## 2026-04-27 proxy1024 targeted lead 策略更新

数据来源：
- `sim_out/rtl_shortlist_proxy1024_targeted/results.csv`
- `sim_out/rtl_shortlist_proxy1024_targeted/summary.md`
- `sim_out/model_calibration_stage3/model_rtl_error_summary_stage3.md`
- `sim_out/merge_opportunity_proxy1024_targeted/analysis_stage1.md`

本轮只对 `proxy1024` 的 `0/75/90` 做 lead 补点，不作为最终推荐。

### 观测结果

| Bucket | 当前最佳通过候选 | 策略状态 |
| --- | --- | --- |
| `proxy1024_r0` | `16x8,set32,merge4,fifo16,lead64` | 单点最快，但不可作为正交通用 |
| `proxy1024_r75` | `8x8,set32,merge4,fifo16,lead32` | 当前更稳，`16x8` timeout |
| `proxy1024_r90` | `8x8,set32,merge4,fifo16,lead128` | `lead64` 接近，`lead32` 明显不足 |

### 对策略表的影响

- `16x8` 不再作为 proxy1024 大角度默认候选；它在 `r75` timeout，在 `r90` 明显退化。
- `8x8,set32,merge4,fifo16` 是 proxy1024 当前更稳的结构候选。
- `lead` 需要按角度分桶：
  - 0 度可接受 `lead64`，但 `16x8` 的单点收益不能泛化。
  - 75 度当前优先看 `lead32`。
  - 90 度需要 `lead64/128`，`lead32` 预取覆盖不足。
- `merge_min_age` 仍不作为默认；本轮没有观察到足够独立收益。

### 模型可信范围修正

- Stage3 中 `proxy1024 orthogonal` 最大误差 `54.97%`，必须标记为 `coarse only`。
- 误差上升的原因不是 RTL 错，而是 empirical bucket 把不同 lead/结构参数混在同一 orthogonal bucket 里。
- 下一轮模型必须至少把 `lead_pixels`、`tile_w/h`、`merge_max_x`、`fifo_depth` 纳入 bucket/key 或特征，否则不能用来推荐正交方向 cycles。

### 下一步

1. 先修模型分桶，不要继续盲跑 RTL。
2. 若继续 RTL 补点，只补 `8x8,set32,merge4,fifo16` 下的少数 lead/angle 点。
3. 不进入完整 `7200->600` RTL matrix。
4. 不把 `16x8`、`lead32`、`lead128` 任一单点固化为全局默认。
## 2026-04-27 Stage5 模型分桶策略修正

当前模型策略更新为两层：

1. 参数感知 observed lookup：
   - key 包含精确角度、frame class、prefetch on/off、tile、set/way、merge、fifo、lead、runtime scheduler 参数。
   - 输出：`sim_out/model_calibration_stage5/param_bucket_angle_calibration_stage5.json`
   - 用途：记录已经跑过的 RTL 参数组合，防止把不同 lead/tile 的结果错误平均。
   - 限制：所有 bucket 当前都是 `lookup only`，不能预测未跑过的参数。

2. 真正 fast model / 回归模型：
   - 暂未在本轮升级。
   - 后续必须把 `lead_pixels`、`tile_w/h`、`merge_max_x`、`fifo_depth`、精确角度或方向类纳入特征。
   - 只有验证误差低于阈值，才能用于 shortlist 排序；否则只能粗筛。

策略影响：
- `proxy1024 orthogonal` 之前的 `54.97%` 误差来自粗 bucket 混合，不是 RTL 功能错误。
- 精确参数 lookup 可以作为“已测证据库”，但不能替代预测。
- 下一轮若继续优化，优先补同一结构附近的少量相邻点，而不是扩大到完整矩阵：
  - `8x8,set32,way2,merge4,fifo16,lead32/64/128`
  - angle `0/75/90`
  - 必要时补 `lead96` 或 `fifo32`，每次只改一类参数。

仍然禁止：
- 不把 lookup-only 结果写成 final recommendation。
- 不进入完整 `7200->600` RTL matrix。
- 不把 `16x8` 或某个 lead 固化为全局默认。
## 2026-04-27 proxy1024 lead refine 策略更新

数据来源：
- `sim_out/rtl_shortlist_proxy1024_lead_refine/results.csv`
- `sim_out/rtl_shortlist_proxy1024_lead_refine/results_enriched.csv`
- `sim_out/model_calibration_stage6/param_bucket_angle_error_summary_stage6.md`

固定结构：`8x8,set32,way2,merge4,fifo16`。本轮只补 `lead48/96`，并和已有 `lead32/64/128` 对比。

| Workload | 当前较优 lead | 状态 |
| --- | --- | --- |
| `proxy1024_r0` | `lead96`，但 `lead48/64/96` 很接近 | candidate |
| `proxy1024_r75` | `lead32` | candidate，且不宜盲目加大 lead |
| `proxy1024_r90` | `lead64/96/128` 接近，`lead128` 略优 | candidate，`lead32` 不足 |

策略含义：
- proxy1024 不能用一套 lead 覆盖全部角度。
- 如果必须给 proxy1024 一个保守 runtime 起点，`lead64` 比 `lead32` 更稳，因为它同时覆盖 `r0/r90`，但在 `r75` 上不是最优。
- 若软件侧能按角度配置 runtime lead：
  - `0°`：优先试 `lead64/96`
  - `75°`：优先试 `lead32`
  - `90°`：优先试 `lead64/96/128`
- 这些仍是 `candidate`，不是最终硬件推荐；需要后续资源/时序和更多尺寸验证。

下一步建议：
- 如果继续参数补点，固定 lead 后只改 `fifo_depth`，例如：
  - `proxy1024_r0`: `lead64/96, fifo16 -> fifo32`
  - `proxy1024_r75`: `lead32, fifo16 -> fifo32`
  - `proxy1024_r90`: `lead64/96, fifo16 -> fifo32`
- 仍然不要进入完整 `7200->600` RTL matrix。
## 2026-04-27 proxy1024 fifo32 策略更新

数据来源：
- `sim_out/rtl_shortlist_proxy1024_fifo_refine/results.csv`
- `sim_out/rtl_shortlist_proxy1024_fifo_refine/fifo16_vs_fifo32.csv`
- `sim_out/model_calibration_stage7/param_bucket_angle_error_summary_stage7.md`

固定结构基础：`8x8,set32,way2,merge4`。本轮只比较 `fifo16 -> fifo32`。

| Workload | lead | fifo32 效果 | 策略状态 |
| --- | ---: | --- | --- |
| `proxy1024_r0` | 64 | 退化 `+422,070 cycles` | 保持 `fifo16` |
| `proxy1024_r0` | 96 | 小幅退化 `+64,182 cycles` | 保持 `fifo16` |
| `proxy1024_r75` | 32 | 改善 `-371,896 cycles` | `fifo32` 成为候选 |
| `proxy1024_r90` | 64 | 严重退化 `+1,510,456 cycles` | 保持 `fifo16` |
| `proxy1024_r90` | 96 | 退化 `+260,098 cycles` | 保持 `fifo16` |

策略含义：
- FIFO 深度不能统一加大。
- 当前 proxy1024 分桶候选变为：
  - `0°`: `8x8,set32,merge4,fifo16,lead64/96`
  - `75°`: `8x8,set32,merge4,fifo32,lead32`
  - `90°`: `8x8,set32,merge4,fifo16,lead64/96/128`
- `fifo32` 只在 `75° lead32` 这一类 workload 上表现出明显收益。

后续门槛：
- 若要把 `r75 fifo32 lead32` 提升为更强 candidate，需要补 SmallConfig 或局部 synth/timing/resource 检查，因为 FIFO 深度增加会影响资源和时序。
- 仍然不进入完整 `7200->600` RTL matrix。
- 仍然不把 `fifo32` 固化为全局默认。
