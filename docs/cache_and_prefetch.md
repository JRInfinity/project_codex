# Cache 与 Prefetch 说明

## src_tile_cache 定位
- `src_tile_cache` 是主读侧性能模块，把算法 sample 请求转换为 tile/sector cache 访问和 DDR fill。
- 文档依据 `rtl/buffer/src_tile_cache.sv`、`docs/verification/cache_parameter_strategy.md`、`docs/verification/cache_optimization_iteration_log.md` 和 timing 优化记录整理。

## 组织方式
- 参数包含 `TILE_W`、`TILE_H`、`TILE_NUM`、sector/set/way 相关 localparam。
- 源码检查 tile 宽高为 2 的幂，way/set/merge/throttle/FIFO depth 等配置合法。
- metadata 包括 valid、tag_x/tag_y、prefetched、prefetch_fill 等字段。

## Prefetch / Merge / Scheduler
- analytic prefetch 使用 scan direction 和 `SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS` 提前生成候选。
- merge 参数如 `MERGE_MAX_X`、`MERGE_MIN_X` 控制横向合并范围。
- throttle 参数如 `ENABLE_PREFETCH_THROTTLE`、`PREFETCH_THROTTLE_CYCLES` 控制预取节流。
- FIFO age、row bucket merge 等属于调度策略，未验证组合不得写成 pass。

## 统计寄存器
- `stat_*` 覆盖 sample、hit、miss、prefetch、merge、stall、fill 等事件。
- 统计通过 `cache_stats_cdc` 形成 AXI-Lite 域快照。

## 已知风险
- replacement choose_way、planner_eval_blocked、sample miss、FIFO compact/merge 在 timing 文档中被标为潜在关键路径。
- 性能结论必须引用 `sim_out/**/summary.txt`、`reports/*.rpt` 或 `docs/verification/*.md`；timeout、回退方案和 candidate 不视为已验证 pass。
