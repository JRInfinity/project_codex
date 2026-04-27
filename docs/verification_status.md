# 验证状态汇总

## 说明
- 本页只汇总可从 `docs/verification/*.md`、`reports/*.rpt`、`sim_out/**/summary.txt` 或 testbench 源码追溯的状态。
- 未找到最新日志的 testbench 在逐模块页标为待确认。

## 分类口径
- pass：日志或报告明确通过。
- candidate：已有候选结果，但还需要 sweep、timing 或 CDC 复核。
- unsafe：日志、timing 或 CDC 记录表明存在风险。
- excluded：明确不作为当前主链路交付项。
- needs sweep：需要参数扫描或更多角度/尺寸覆盖。

## 当前结论
- 主链路 RTL 已有 testbench 覆盖：`tb_image_geo_top`、`tb_ddr_read_engine`、`tb_ddr_write_engine`、`tb_src_tile_cache`、`tb_pixel_unpacker`、`tb_result_cdc`、`tb_task_cdc` 等。
- cache/prefetch 性能 wrapper 数量较多，复杂性能 wrapper 结果应统一从 `sim_out` 和 `docs/verification/cache_*` 文档追溯。
- timing 结论以 `reports/*.rpt` 和 `docs/verification/timing_optimization_log.md` 为准；未在报告中闭合的优化不能写作已通过。

## 待补
- 为每个 `tb_image_geo_top_perf_*` wrapper 绑定最新 `sim_out` 目录、状态和配置参数。
- 把 cache 参数 sweep 结果整理成 pass/candidate/unsafe/excluded/needs sweep 表格。
