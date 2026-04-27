# Cache 优化迭代经验日志

最后更新：2026-04-25

本文档是 cache / prefetch / DDR 读路径优化的长期经验文档，也是后续每次改动前必须先看的避坑记录。它的目的不是只保存漂亮结果，而是明确记录过去哪些思路有效、哪些思路失败、哪些仿真日志不能再拿来做结论，避免我之后重复犯同样的错误。

每次修改 `src_tile_cache`、DDR 读路径、top 参数、testbench 或性能 sweep 脚本前，都应该先检查本文档中的“已知不安全或排除结果”和“新增迭代模板”。如果新方案踩中了这里已经记录过的问题，必须先说明为什么这次条件不同，否则不要重复执行。

## 记录规则

- 每次 RTL、参数、testbench 或 benchmark 迭代前，先在本文档新增一条计划记录；运行结束或超时后再补齐结果。
- 后续仿真必须使用带 timeout 的命令。单元 smoke 优先使用 `tools/run-module-sim.ps1`，top 单 case 性能仿真优先使用 `tools/run-cache-perf-case.ps1`。
- 只有同时满足以下条件的日志才能作为性能结论：无 `Fatal`、无 timeout、无 AXI 队列 overflow/underflow、输出校验通过。
- 失败和不安全结果也要保留，但必须标记为 `unsafe` 或 `excluded`，不能再被当成最佳配置引用。
- `analytic=a/b/c/d` 统一解释为 `candidates/duplicates/blocked/fills`。
- 如果某次命令卡住、超时或被 watchdog 杀掉，也要记录。它本身就是一条有价值的经验，提醒后面不要裸跑同类命令。
  - 保留 real miss > analytic prefetch > normal prefetch 的调度优先级；保留 `read_error` 清理 fill/read/planner/FIFO 状态。
- 命令：
  - `powershell -ExecutionPolicy Bypass -File tools/run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 30`
  - `powershell -ExecutionPolicy Bypass -File tools/run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 45`
  - `powershell -ExecutionPolicy Bypass -File tools/run-module-sim.ps1 image_geo_top -CompileTimeoutSec 180 -ElabTimeoutSec 180 -SimTimeoutSec 60`
  - `powershell -ExecutionPolicy Bypass -File tools/run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_1000_600_downscale_on -RunName geom_init_unit_compile_check -CompileOnly -CompileTimeoutSec 240`
- 输出目录：`sim_out/src_tile_cache/`、`sim_out/src_tile_cache_prefetch/`、`sim_out/image_geo_top/`、`sim_out/cache_perf/geom_init_unit_compile_check/`
- timeout 策略：全部命令使用进程级 timeout；perf compile-only 在 240s 超时后已由 runner 清理残留进程。

| Case | Params | Cycles | Reads | Misses | Prefetches | Hits | Analytic | FIFO / merge stats | 状态 | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `tb_src_tile_cache` | default sector cache | N/A | N/A | N/A | N/A | N/A | N/A | N/A | pass | 公共 geom 接入未破坏 cache 基本 miss fill。 |
| `tb_src_tile_cache_prefetch` | default sector cache | N/A | 3 TB reads | 1 | 2 | N/A | N/A | merge read bytes `8/8/56` | pass | analytic/prefetch 路径 smoke 通过。 |
| `tb_image_geo_top` | default top smoke | N/A | N/A | N/A | N/A | N/A | N/A | N/A | pass | top compile/elab/sim 通过，rotate core 新几何等待路径可运行。 |
| `perf_single_1000_600_downscale compile-only` | `64x8,N=24,LEAD=64,FIFO=32,SET=64,WAY=4,MERGE=8` | N/A | N/A | N/A | N/A | N/A | N/A | N/A | timeout/excluded | `xvlog` 240s 超时，不能作为编译失败或性能结论；只证明 watchdog 会终止长命令。 |

经验记录：
- 公共几何单元接入后，单元和普通 top smoke 已通过；后续性能 sweep 前仍需先用较小 compile target 或提高有界 timeout，不能裸跑 perf runner。
- 这轮 perf compile timeout 必须记入排除项，不能被误读成 RTL 功能失败，也不能拿来比较 cycles/misses。

top perf 单 case 示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_1000_600_downscale_on -RunName sector_v1_downscale_smoke -CompileTimeoutSec 300 -ElabTimeoutSec 300 -SimTimeoutSec 900
```

### Round 2026-04-26-timing-src-cache-scheduler-cut

- 目标：专门处理 small config timing，不启动 workload matrix；把 `src_tile_cache` 中明显不该落在关键路径上的 FIFO/stat/fill 调度组合链拆短。
- RTL 改动：
  - `src_tile_cache.sv`：analytic FIFO 的 per-entry age 改为单个 `fifo_head_age_reg`，避免 FIFO compact 时为每个 entry 生成深层 reset/CE。
  - `src_tile_cache.sv`：FIFO pop/delete/enqueue 改为 pending operation，下一拍再更新 FIFO 数组，避免 FIFO tile array 直接吃 sample/cache/replace 深组合。
  - `src_tile_cache.sv`：merge histogram、prefetch/miss/evict-unused 等统计从 `fill_request` 组合链移到已寄存的 `fill_plan` 启动阶段。
  - `src_tile_cache.sv`：增加 `sample_miss_pending_reg`，real miss tile 先寄存，下一拍再做 replacement；同时把 `fill_req` 作为独立寄存级，`fill_req` 再进入 `fill_plan`。
  - `src_tile_cache.sv`：normal prefetch 使用寄存后的 `normal_prefetch_pending` tile，不再让当前 `scan_dir` 同拍穿过 choose_way。
  - `src_tile_cache.sv`：无效 merge lane 不再每次写 0，只写 `run_len` 有效前缀，减少无意义 reset/CE。
  - `src_tile_cache.sv`：`stat_replacement_fail` 和 scheduler 产生的 `stat_analytic_blocked` 采用后一拍 pulse 计数，避免统计 CE 直接挂 scheduler 深链。
- 验证命令：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`
- 结果：

| 阶段 | AXI WNS | Core WNS | 最坏 core endpoint | 结论 |
| --- | ---: | ---: | --- | --- |
| CDC FIFO 化后基线 | `-1.082 ns` | `-17.052 ns` | `fifo_age_reg` reset | FIFO age/compact 控制是首要坏路径。 |
| 去掉 per-entry age | `-1.082 ns` 到 `-0.768 ns` 波动 | 约 `-16.365 ns` | `fifo_tile_x/y` CE | 只改 age 不够，FIFO array compact 仍在深链上。 |
| FIFO pending op + 统计后移 | 约 `-0.768 ns` | 约 `-13 ns` 到 `-10 ns` | `fill_req/read_addr/stat` | 有效，但 replacement/choose_way 仍过深。 |
| miss/normal prefetch pending 化后 | `-0.768 ns` | `-8.354 ns` | `fill_req_set_reg[0][0]/CE` | WNS 明显改善，但仍未过 timing。 |

- 经验记录：
  - 不要继续靠“把某个统计寄存器后一拍”这种小修期待过 timing；它只能把 WNS 从 `-17 ns` 拉到约 `-8 ns`，真正瓶颈仍是 `choose_way`/replacement。
  - 下一轮 timing 必须做结构性多周期 replacement：先锁存 fill candidate，再分阶段计算 set、invalid way、used-prefetch victim、oldest victim，最后提交 fill request。
  - 统计计数不能直接挂在调度组合链上；以后新增 stats 必须优先使用已寄存事件。
  - small config timing 仍未 proven，任何参数推荐仍不能标为 timing/resource proven。

### Round 2026-04-25-reset-cdc-stats-preflight

- 目标：在正式 workload sweep 前，把工程收口到可长期自动优化的状态：复位分域同步、CDC payload 有稳定性检查、cache 统计能被 top 读取、cache error 能进入总控 error、analytic merge 不隐藏同一次 fill 内的 way 冲突，所有验证继续使用带 timeout 的 runner。
- RTL / 脚本改动：
  - 新增 `rtl/axi/reset_sync.sv`，`image_geo_top` 分别生成 `axi_sys_rst/core_sys_rst`，top 不再用一个跨域 `sys_rst` 喂 CDC/DDR wrapper。
  - `frame_config_cdc`、`result_cdc`、`cache_stats_cdc`、`task_cdc`、`task_cdc_2d` 改为 `src_rst/dst_rst`；`async_word_fifo` 改为 `wr_rst/rd_rst`，XPM rst 仍由两域 reset OR 得到，仿真 fallback 分别用写/读域 reset。
  - `ddr_read_engine` / `ddr_write_engine` 顶层端口改为 `axi_rst/core_rst`，内部 CDC 和 FIFO 按源/目标域连接。
  - `scaler_ctrl` 增加 `cache_error` 输入，`S_RUN` 中 `core_error || cache_error || wb_error || write_error` 进入 `S_ERROR`；top 连接 `src_cache_error`。
  - `src_tile_cache` 增加扩展统计输出，并补 `stat_total_cycles`、merge histogram flatten；analytic merge 选择 way 时增加同一 fill_request 内 reservation 检查，后续 tile 无法安全 reserve 时只缩短 merge 前缀，不丢弃已可发起的前缀。
  - `cache_stats_cdc` 改为 snapshot payload bus；`image_geo_top` 保留旧 cache 统计寄存器地址，同时新增 `0x040` 起的扩展统计区，含 `stats_version/snapshot_id/frame_cycles/sample_stall/read_busy/read_bytes/miss_latency/merge_hist` 等。
  - top 增加 DDR read/write 参数宏：`IMAGE_GEO_RD_BURST_MAX_LEN`、`IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS`、`IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS`、`IMAGE_GEO_RD_FIFO_DEPTH_WORDS`、`IMAGE_GEO_WR_BURST_MAX_LEN`、`IMAGE_GEO_WR_FIFO_DEPTH_PIXELS`。
  - `axi_burst_reader` / `axi_burst_writer` 增加仿真期 AXI 稳定性断言：AR/AW/W valid 等待 ready 时 payload 不变，burst 不跨 4KB，outstanding 计数不溢出。
  - `scripts/gen_param_header.py`、`scripts/run_cache_sweep.py`、`scripts/run_rtl_shortlist.py`、`tools/run-cache-perf-case.ps1` 支持 DDR 参数；新增 `scripts/gen_baseline_matrix.py`，只生成 baseline workload CSV，不启动大 sweep。
  - `tb_image_geo_top` 增加 idle skew reset smoke、start-while-busy probe、扩展 cache stats AXI-Lite 读取和旧/新统计一致性检查。
  - `tb_image_geo_top_perf_single_case` 增加 `PERF_SINGLE_STATS_EXT` 输出；`scripts/run_rtl_shortlist.py` 解析该行并把扩展统计写入 CSV。
  - `tb_image_geo_top_perf_single_case` 增加 `IMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT` 模式，默认跳过历史重型 profile 探针，只保留 `PERF_SINGLE` 与 `PERF_SINGLE_STATS_EXT`；`tools/run-cache-perf-case.ps1` 默认启用轻量模式，必要时用 `-FullProfile` 恢复深度 profile。
  - `tools/run-cache-perf-case.ps1` 新增 `-TbOnlyCompile`，用于只编译 perf TB 和参数 define，避免每次检查 TB 改动都拉起完整 top source-set。
  - `scripts/run_rtl_shortlist.py` 默认使用轻量 perf TB；新增 `--full-profile` 只在需要深度诊断时传递 `-FullProfile`。
- 命令：
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 task_cdc -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 result_cdc -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 async_word_fifo -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_read_engine -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_write_engine -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 scaler_ctrl -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `powershell -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 40`
  - `python scripts\gen_baseline_matrix.py --out sim_out\cache_baseline\baseline_workloads.csv`
  - `python scripts\run_cache_sweep.py --max-combos 3 --out sim_out\cache_sweep\smoke_fast_model_ddr_params.csv --mode scan --scan-rows 4 --tile-w 8 --tile-h 8 --set-num 64 --way-num 4 --merge-max-x 4 --fifo-depth 16 --lead-pixels 32 --rd-burst-max-len 16,32 --rd-max-outstanding-bursts 4 --rd-max-outstanding-beats 16 --rd-fifo-depth-words 64`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_ext_stats_compile_check -CompileOnly -CompileTimeoutSec 90`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_light_ext_stats_compile_check -CompileOnly -CompileTimeoutSec 90`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_light_tb_only_compile_check -TbOnlyCompile -CompileTimeoutSec 30`
  - `iverilog -g2012 -tnull -DIMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT rtl\sim\tb_image_geo_top_perf_single_case.sv`
  - `powershell -NoProfile -ExecutionPolicy Bypass -Command "[scriptblock]::Create((Get-Content tools\run-cache-perf-case.ps1 -Raw)) | Out-Null; 'ok'"`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_light_compile_240s -CompileOnly -CompileTimeoutSec 240`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_light_new_tb_only_compile -TbOnlyCompile -CompileTimeoutSec 30`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_light_new_compile_120s -CompileOnly -CompileTimeoutSec 120`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_small_rotate45_on -RunName perf_single_light_small_rotate45_on -CompileTimeoutSec 120 -ElabTimeoutSec 60 -SimTimeoutSec 60`
  - `python -m py_compile scripts\run_rtl_shortlist.py`
  - `python scripts\run_rtl_shortlist.py --input sim_out\cache_sweep\smoke_fast_model_ddr_params.csv --out sim_out\cache_sweep\rtl_shortlist_ext_dry.csv --top-n 1 --dry-run`
  - `python scripts\run_rtl_shortlist.py --input sim_out\cache_sweep\smoke_fast_model_ddr_params.csv --out sim_out\cache_sweep\rtl_shortlist_light_small_actual.csv --top-n 1 --rtl-top tb_image_geo_top_perf_single_small_rotate45_on --compile-timeout 120 --elab-timeout 60 --sim-timeout 60`
- 输出目录：
  - `sim_out/task_cdc/`
  - `sim_out/result_cdc/`
  - `sim_out/async_word_fifo/`
  - `sim_out/ddr_read_engine/`
  - `sim_out/ddr_write_engine/`
  - `sim_out/scaler_ctrl/`
  - `sim_out/src_tile_cache/`
  - `sim_out/src_tile_cache_prefetch/`
  - `sim_out/image_geo_top/`
  - `sim_out/cache_baseline/baseline_workloads.csv`
  - `sim_out/cache_sweep/smoke_fast_model_ddr_params.csv`
  - `sim_out/cache_sweep/rtl_shortlist_ext_dry.csv`
  - `sim_out/cache_perf/perf_single_ext_stats_compile_check/`
  - `sim_out/cache_perf/perf_single_light_ext_stats_compile_check/`
  - `sim_out/cache_perf/perf_single_light_tb_only_compile_check/`
  - `sim_out/cache_perf/perf_single_light_compile_240s/`
  - `sim_out/cache_perf/perf_single_light_new_tb_only_compile/`
  - `sim_out/cache_perf/perf_single_light_new_compile_120s/`
  - `sim_out/cache_perf/perf_single_light_small_rotate45_on/`
  - `sim_out/cache_sweep/rtl_shortlist_light_small_actual.csv`

| Case | Params | Cycles | Reads | Misses | Prefetches | Hits | Analytic | FIFO / merge stats | 状态 | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `tb_task_cdc` | src/dst reset toggle CDC | N/A | N/A | N/A | N/A | N/A | N/A | payload stability assertion enabled | pass | toggle CDC 分域 reset 后可用。 |
| `tb_result_cdc` | src/dst reset result CDC | N/A | N/A | N/A | N/A | N/A | N/A | done/error cases | pass | result event CDC 分域 reset 后可用。 |
| `tb_async_word_fifo_xpm` | wr_rst/rd_rst FIFO wrapper | N/A | N/A | N/A | N/A | N/A | N/A | underflow/overflow TB cases | pass | FIFO wrapper 接口改动未破坏现有行为级仿真。 |
| `tb_ddr_read_engine` | axi_rst/core_rst + AXI assertions | N/A | N/A | N/A | N/A | N/A | N/A | rresp/rlast injection included | pass | DDR read wrapper 分域 reset 和 AXI 稳定性断言未误报；错误注入仍按 TB 预期完成。 |
| `tb_ddr_write_engine` | axi_rst/core_rst + AXI assertions | N/A | N/A | N/A | N/A | N/A | N/A | bresp injection included | pass | DDR write wrapper 分域 reset 和 AW/W 稳定性断言未误报。 |
| `tb_src_tile_cache` | reservation + extended stats ports | N/A | N/A | N/A | N/A | N/A | N/A | read_error injection observed | pass | cache error 路径和 real miss fill smoke 仍正常。 |
| `tb_src_tile_cache_prefetch` | reservation + extended stats ports | N/A | N/A | N/A | N/A | N/A | N/A | prefetch smoke | pass | analytic/prefetch smoke 仍正常。 |
| `tb_image_geo_top` | reset sync + stats snapshot bus | small smoke | 6-9 | 0-9 | 0-8 | 0-9 | snapshot id nonzero | `CACHE_EXT_STATS` 覆盖 prefetch off/on、read_busy/read_bytes/fifo/merge/miss latency | pass | top 旧统计地址保留，扩展统计区可读；idle skew reset 无假 start/done/error；start-while-busy 不破坏 busy 状态。 |
| `baseline_workloads.csv` | 5 size classes x 10 angles x 3 stride modes x 2 prefetch modes | N/A | N/A | N/A | N/A | N/A | N/A | 300 rows | defined_not_run | 本轮只固化 baseline 矩阵，不启动大规模 RTL。 |
| `smoke_fast_model_ddr_params.csv` | small fast-model smoke with DDR params | see CSV | N/A | see CSV | see CSV | see CSV | see CSV | includes `rd_burst/rd_outstanding/rd_fifo` columns | pass | 快速模型已能把 DDR 读参数纳入 CSV，仍只作为流程 smoke。 |
| `preflight_compile_only` | perf single full compile, 120s watchdog | N/A | N/A | N/A | N/A | N/A | N/A | `sim_out/cache_perf/preflight_compile_only/` | timeout/excluded | runner 正常终止并清理残留进程；不作为语法失败或性能结论。后续 perf compile 需要更细分 source set 或显式更长但有界 timeout。 |
| `rtl_shortlist_ext_dry.csv` | dry-run parser check | N/A | N/A | N/A | N/A | N/A | N/A | extended CSV columns present | pass | RTL shortlist 脚本能保留扩展 stats 字段；dry-run 不启动 RTL。 |
| `perf_single_ext_stats_compile_check` | perf single full source compile, 90s watchdog | N/A | N/A | N/A | N/A | N/A | N/A | `sim_out/cache_perf/perf_single_ext_stats_compile_check/` | timeout/excluded | 完整 perf source-set 在 90s 内未完成，已终止并清理残留 `xvlog`；不作为语法失败或性能结论。 |
| `perf_single_light_ext_stats_compile_check` | lightweight perf single full source compile, 90s watchdog | N/A | N/A | N/A | N/A | N/A | N/A | `sim_out/cache_perf/perf_single_light_ext_stats_compile_check/` | timeout/excluded | 轻量 TB 仍无法让完整 top source-set 进 90s，说明主要瓶颈是完整 RTL 编译本身；不作为语法失败或性能结论。 |
| `perf_single_light_tb_only_compile_check` | lightweight perf TB only compile, 30s watchdog | N/A | N/A | N/A | N/A | N/A | N/A | `sim_out/cache_perf/perf_single_light_tb_only_compile_check/` | timeout/excluded | Vivado `xvlog` TB-only 30s 仍无日志输出；后续不要用更短 watchdog 判定 TB 语法。 |
| `iverilog_perf_tb_parse` | lightweight perf TB parse | N/A | N/A | N/A | N/A | N/A | N/A | missing `image_geo_top` only | expected_fail | `iverilog` 能快速解析到 elaboration 阶段，唯一错误是未提供 `image_geo_top` 定义；可作为括号/预处理快速兜底，但不能替代 Vivado。 |
| `perf_single_light_compile_240s` | old perf TB with lightweight define, full source compile | N/A | N/A | N/A | N/A | N/A | N/A | `sim_out/cache_perf/perf_single_light_compile_240s/` | timeout/excluded | 旧 perf TB 即使关掉重型 profile，完整 `xvlog` 240s 仍超时；必须切到真正独立的短 TB 文件。 |
| `perf_single_light_new_tb_only_compile` | new short perf TB only | N/A | N/A | N/A | N/A | N/A | N/A | `rtl/sim/tb_image_geo_top_perf_single_light.sv` | pass | 新短 TB 的 Vivado TB-only compile 约 1.5s 通过，证明旧 perf TB 文件本身是 compile 卡顿源。 |
| `perf_single_light_new_compile_120s` | new short perf TB full source compile | N/A | N/A | N/A | N/A | N/A | N/A | full top source set | pass | 新短 TB 接入后完整 source-set compile 在 120s watchdog 内通过，实际约数秒。 |
| `perf_single_light_small_rotate45_on` | `small_rotate45_on`, default runner params | `23072` | `101` | `29` | `72` | `61` | `2304/2236/0/62` | `fifo_max=9 read_busy=9267 bytes=6848 miss_lat=51/290/5177/37 merge_hist=0/97/3/0/1/...` | pass | 新短 TB 可完成 xelab/xsim，并输出 `PERF_SINGLE_STATS_EXT`。该 TB 当前用于性能统计链路 smoke，不做输出 bit-exact 校验。 |
| `rtl_shortlist_light_small_actual.csv` | shortlist runner actual small top | `19050` | `74` | `14` | `60` | `67` | `2304/2235/0/58` | `fifo_max=8 read_busy=7158 bytes=5312 miss_lat=13/290/3174/29 merge_hist=0/67/6/0/1/...` | pass | `run_rtl_shortlist.py` 可实际调用新短 TB runner，并把扩展统计写入 CSV。 |

经验记录：
- 以后不能再把 CDC 复位释放当成“一个 OR 出来的 sys_rst 就够了”。跨域模块必须显式区分源/目标 reset，toggle payload 必须在 ack 回来前保持稳定。
- cache 统计必须通过 snapshot bus 一次性搬运；只看 4 个旧 counter 会让 sweep 无法区分 miss、DDR busy、FIFO blocked、merge 不足和 prefetch 污染。
- AXI error 注入是合法负向测试，不要把 RRESP/BRESP/RLAST 错误本身写成会终止仿真的 `$error`；断言应检查协议稳定性和边界，错误传播由 TB 验证。
- analytic merge 不能假设连续 tile 一定 hash 到不同 way；参数 sweep 后 SET_NUM 很小时，同一次 fill_request 内必须显式 reservation。
- baseline matrix 可以先定义、再分批执行。不要因为生成了 300 个 workload 行就直接批量裸跑 RTL。
- 完整 top perf source-set 的 `xvlog` 可能 90s 仍编不完。以后不要用裸 `xvlog` 试探 perf 单测；必须用 watchdog runner，并在 timeout 后立即检查/清理 `xvlog/xelab/xsim` 残留进程。
- top 小 smoke 已经能读到扩展 stats，后续 sweep CSV 必须优先使用 `PERF_SINGLE_STATS_EXT` / AXI-Lite 扩展统计，不要退回只看 `reads/misses/prefetches/hits`。
- perf runner 默认应使用轻量 TB，不再默认打开历史重型 profile。完整 profile 只在定位具体瓶颈时用 `-FullProfile`，不能作为常规 sweep 路径。
- 如果 Vivado TB-only compile 也被短 watchdog 杀掉，只能说明阈值太短或 Vivado 启动慢，不能直接判定 TB 有语法错。短期用 `iverilog` 做快速括号/预处理兜底，Vivado 完整验证必须安排单独的较长有界窗口。
- 旧 `tb_image_geo_top_perf_single_case.sv` 已确认不适合作为常规 sweep TB，即使 profile 被宏关闭，240s compile 仍会超时。后续自动优化默认使用 `tb_image_geo_top_perf_single_light.sv`；旧 TB 只保留给特殊深度诊断。
- 新短 TB 当前只验证 pipeline 完成和统计输出，不做输出图像 bit-exact。正式 correctness 仍以 `tb_image_geo_top` smoke 和后续专门 bit-exact case 为准，不能把短 TB 的 `pass` 误写成图像逐像素正确证明。

### Round 2026-04-25-shared-geom-and-sweep-flow

- 目标：继续修正共享几何和 cache 正确性，同时建立可重复的“参数扫描 + RTL 验证 + 资源/时序筛选”流程，避免后续靠人工猜参数。
- RTL / 参数改动：
  - `rotate_geom_init_unit` 增加 `start_id/geom_id`，由 `image_geo_top` 唯一例化并锁存 `geom_ready` 后的结果。
  - `rotate_core_bilinear` 删除内部几何单元实例，`S_GEOM_WAIT` 只消费 top 提供的 `geom_ready/geom_*`。
  - `src_tile_cache` 删除内部几何单元实例；real miss 不等待 geom，只有 analytic planner 等待 top 的 `geom_ready`。
  - fill 真正启动时立即清除被选中 way 的 `sector_valid/prefetched/prefetch_fill/used`，避免 DDR 写入过程中旧 tag 误命中。
  - `read_error` 分支补齐 fill stream/run/is_prefetch/is_analytic 和 FIFO 内容清理；`read_error` 仍高于 `read_done`。
  - `BASE_TILE_W/H`、`SET_NUM` 等参数增加编译期检查，tile 坐标和 tile 内偏移改为 shift/mask。
  - `stat_prefetch_evicted_unused` 改为本拍局部计数后一次累加，避免 for 循环多次非阻塞赋值少计。
  - 新增内部层级可读统计：sample stall、normal prefetch fill、FIFO max occupancy、merge length histogram、read busy cycles、read bytes、replacement fail、miss service latency 等。
- 自动化脚本：
  - 新增 `scripts/gen_param_header.py`
  - 新增 `scripts/run_cache_sweep.py`
  - 新增 `scripts/run_rtl_shortlist.py`
  - 新增 `scripts/run_synth_shortlist.py`
  - 新增 `scripts/report_pareto.py`
  - 新增流程文档 `docs/verification/cache_parameter_sweep_workflow.md`
- 命令：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 30`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 45`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 180 -ElabTimeoutSec 180 -SimTimeoutSec 60`
  - `python scripts\run_cache_sweep.py --max-combos 3 --out sim_out\cache_sweep\smoke_fast_model.csv --mode scan --scan-rows 8 --tile-w 8 --tile-h 8 --set-num 64 --way-num 4 --merge-max-x 4 --fifo-depth 16 --lead-pixels 32`
  - `python scripts\run_rtl_shortlist.py --input sim_out\cache_sweep\smoke_fast_model.csv --out sim_out\cache_sweep\rtl_shortlist_dry.csv --top-n 1 --dry-run`
  - `python scripts\run_synth_shortlist.py --input sim_out\cache_sweep\rtl_shortlist_dry.csv --out sim_out\cache_sweep\synth_shortlist_est.csv`
  - `python scripts\report_pareto.py --fast sim_out\cache_sweep\smoke_fast_model.csv --synth sim_out\cache_sweep\synth_shortlist_est.csv --out-dir sim_out\cache_sweep\report_smoke2`
  - `python scripts\run_cache_sweep.py --max-combos 20 --out sim_out\cache_sweep\mini_param_sweep.csv --mode scan --scan-rows 6 --tile-w 8,16 --tile-h 8 --set-num 64 --way-num 4 --merge-max-x 4,8 --fifo-depth 16,32 --lead-pixels 32,64`
- 输出目录：
  - `sim_out/src_tile_cache/`
  - `sim_out/src_tile_cache_prefetch/`
  - `sim_out/image_geo_top/`
  - `sim_out/cache_sweep/`

| Case | Params | Cycles | Reads | Misses | Prefetches | Hits | Analytic | FIFO / merge stats | 状态 | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| `grep rotate_geom_init_unit` | shared top geom | N/A | N/A | N/A | N/A | N/A | N/A | N/A | pass | `rotate_core_bilinear` 和 `src_tile_cache` 内部不再例化，`image_geo_top` 只有一个实例。 |
| `tb_src_tile_cache` | sector cache default | N/A | N/A | N/A | N/A | N/A | N/A | N/A | pass | prefetch off / real miss fill smoke 通过，并补充一次 DDR `read_error` 注入，观察到 cache error。 |
| `tb_src_tile_cache_prefetch` | sector cache default | N/A | N/A | N/A | N/A | N/A | N/A | N/A | pass | prefetch on smoke 通过。 |
| `tb_image_geo_top` | shared geom top smoke | N/A | N/A | N/A | N/A | N/A | N/A | N/A | pass | top 级共享几何、core 等待 geom_ready、cache analytic 等待 geom_ready 均可运行。 |
| `fast_model_smoke` | `8x8,SET64,WAY4,MERGE4,FIFO16,LEAD32` | see CSV | N/A | see CSV | see CSV | see CSV | see CSV | `sim_out/cache_sweep/smoke_fast_model.csv` | pass | 快速模型、dry-run RTL shortlist、资源估算和 Pareto/recommendations 生成链路通过。 |
| `mini_param_sweep` | small scan sweep | see CSV | N/A | see CSV | see CSV | see CSV | see CSV | `sim_out/cache_sweep/mini_param_sweep.csv` | pass | 只作为流程样例数据，不作为最终参数推荐。 |

经验记录：
- 几何结果不能在 core/cache 各自启动计算，否则后续新配置或 busy 期间 start 可能造成配置错配；本轮改成 top 唯一 geom，并加 generation id。
- fill 启动时必须立即 invalid 被选 way；只在 read_done 后置 valid。这个规则之后不能再被优化回退。
- 统计计数不能在 for 循环里对同一个寄存器多次非阻塞 `<= stat + 1`，必须用局部计数后一次累加。
- 自动 sweep 必须先跑快速模型筛选，再跑 RTL shortlist，不能把长时间 top perf 当作第一层筛选工具。

## 已回填的关键迭代

| 轮次 | 来源 | 架构 / 参数 | 用例 | 关键结果 | 状态 | 结论 / 经验 |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-04-08-prefetch-small | `docs/verification/perf_sweep_latest.md` | 早期 runtime tile-cache prefetch | identity、64->32 downscale、小图 45/90 度旋转 | identity miss `4->1`，64->32 downscale miss `16->4`，45 度旋转没有明显改善 | historical | 普通方向预测对顺序扫描/简单缩放有帮助，但对 45 度旋转很弱，不能继续指望它解决主要 miss。 |
| 2026-04-24-final-default | `sim_out/final_default_cache_impl/*.log` | 当时的 analytic/default cache 实现 | `small_rotate45`、`1000_600_downscale`、`1000_600_rotate15` | small `cycles=16669 reads=8 misses=2`；downscale `cycles=21604235 reads=16938 misses=8402`；rotate15 `cycles=32810333 reads=25658 misses=11927` | baseline | 正确性 smoke 可用，但 miss 和 DDR 读次数仍太多。后续优化必须比这个基线更强。 |
| 2026-04-24-sched-fix | `sim_out/sweep_1000_600_sched_fix/summary.csv` | real miss 优先、替换保护更保守；固定 tile 参数来自当时编译配置 | `1000_600_downscale`、`1000_600_rotate15`、`small_rotate45` | downscale 最好行 `TILE_NUM=24 LEAD=64 cycles=21606993 misses=13047`；rotate15 `cycles=31124887 misses=10521`；small `cycles=16669 misses=2` | valid but not winning | 功能调度修复是必要的，但纯靠保守调度会让更多访问变成 demand fill，downscale 性能反而不够好。 |
| 2026-04-24/25-geom-sweep | `sim_out/analytic_fifo_geom/summary.csv` | 固定 tile geometry sweep，analytic FIFO depth 16 | `1000_600_downscale`、`1000_600_rotate15`、`small_rotate45` | downscale 最好：`128x8,N=24 cycles=8951947 misses=919`；rotate15 最好有效点：`64x16,N=24 cycles=27746673 misses=3194`；small 有效点：`64x8,N=24 cycles=19199 misses=2` | valid | 大横向 tile 对纯缩放非常强，但不能因此直接当全局默认；旋转场景更适合 `64x16` 这类折中几何。 |
| 2026-04-25-sector-cache-v1 | 当前 RTL 树 | `8x8` sector cache 候选：`SET=64 WAY=4 FIFO=32 MERGE_MAX_X=8 LEAD=64`；top 兼容默认 `64x8,N=24` | 本文档中尚未重新 benchmark | 只做源码检查 | candidate | 这是适配多输入规格的主方向，但在成为默认推荐前必须补 compile smoke 和 perf 数据。 |
| 2026-04-25-docs-runner | `tools/run-cache-perf-case.ps1`，本文档 | 文档体系 + 带 timeout 的 top perf runner | runner 语法检查和 compile-only watchdog 自测 | PowerShell 解析通过；第一次 `-d NAME=VALUE` 方式在 Vivado 2019.2 下失败，改为生成临时 define 文件；完整 top compile selftest 在 120s watchdog 下被终止并清理残留进程 | workflow | watchdog 已验证会生效。完整 top 编译需要使用更大的有界 timeout，不能裸跑，也不能把 120s compile timeout 当成编译失败结论。 |

## 固定几何 Sweep 细节

数据来自 `sim_out/analytic_fifo_geom/summary.csv`。

| Tile | N | Case | Cycles | Reads | Misses | Prefetches | Hits | Analytic | Evict unused | 状态 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- |
| 128x8 | 24 | 1000_600_downscale | 8,951,947 | 1,244 | 919 | 325 | 325 | `1441243/1440000/0/150` | 0 | valid |
| 128x8 | 16 | 1000_600_downscale | 8,955,951 | 1,246 | 921 | 325 | 325 | `1441245/1440000/0/150` | 0 | valid |
| 128x16 | 16 | 1000_600_downscale | 9,587,809 | 566 | 500 | 66 | 66 | `1440565/1440000/0/63` | 0 | valid |
| 64x8 | 24 | 1000_600_downscale | 9,779,329 | 4,156 | 2,309 | 1,847 | 1,847 | `1444156/1440000/0/946` | 0 | valid |
| 64x16 | 24 | 1000_600_downscale | 10,380,777 | 1,483 | 1,399 | 84 | 84 | `1441483/1440000/0/72` | 0 | valid |
| 64x8 | 16 | 1000_600_downscale | 11,143,271 | 5,775 | 3,237 | 2,538 | 2,512 | `1445725/1440000/0/1209` | 0 | valid |
| 64x16 | 16 | 1000_600_downscale | 12,037,351 | 2,226 | 2,039 | 187 | 173 | `1442152/1440000/0/137` | 0 | valid |
| 32x16 | 24 | 1000_600_downscale | 21,609,349 | 15,600 | 13,048 | 2,552 | 2,514 | `1455599/1440000/0/1168` | 38 | valid |
| 64x16 | 24 | 1000_600_rotate15 | 27,746,673 | 10,984 | 3,194 | 7,790 | 6,226 | `1449317/1439999/0/764` | 1,519 | valid |
| 64x8 | 24 | 1000_600_rotate15 | 28,429,429 | 22,125 | 6,141 | 15,984 | 15,041 | `1459378/1440000/0/1219` | 846 | valid |
| 64x8 | 24 | small_rotate45 | 19,199 | 8 | 2 | 6 | 6 | `2311/2304/0/3` | 0 | valid |
| 64x16 | 24 | small_rotate45 | 20,511 | 4 | 2 | 2 | 2 | `2307/2304/0/1` | 0 | valid |

## 已知不安全或必须排除的结果

这些记录是本文档最重要的部分。后续修改前必须先看，避免重复踩坑。

| 来源 | 现象 | 排除原因 | 后续要求 |
| --- | --- | --- | --- |
| AR queue 修复前的 top timeout 日志 | 多 outstanding AR 时 timeout 或读响应丢失 | 旧 testbench AXI AR 队列模型可能丢掉已接收的 AR 请求 | 不能用于性能结论，只能作为历史 debug 背景。 |
| `sim_out/analytic_fifo_geom/tile128x8_n16_fifo16_rotate15_xsim.log` | `cycles=40000026` 时 `PERF_SINGLE_TIMEOUT_TRACE2`，`read_bytes=128`，unpacker 仍 active | 该 build 中 `128` byte row / tail 处理路径对 rotate15 不安全 | 在 rotate smoke 通过前，不能把 `128x8` 或等价 `MERGE_MAX_X=16` 当全局推荐。 |
| 手工裸跑长时间 `xsim/xelab/xvlog` | 桌面会卡几十分钟甚至数小时 | 没有进程级 watchdog，也没有保证清理残留进程 | 后续必须改用 `tools/run-module-sim.ps1` 或 `tools/run-cache-perf-case.ps1`。 |
| `sim_out/perf_single_large_rotate45_*` 和 `sim_out/proxy_*` 下的大量 trace 目录 | 很多日志是局部探针或预期 timeout | 这些目录用于定位握手和预取问题，不是默认参数选择依据 | 只把有最终 `PERF_SINGLE` pass 行的日志导入性能表。 |
| 单次 sweep 一口气跑太多 case | 某个 case 卡住会拖住整轮实验 | 难以定位是哪个参数导致问题，也不方便保留中间有效结果 | 后续 sweep 必须一组参数一个进程，一个 case 一个独立输出目录。 |
| 只看 miss 不看 cycles/reads | miss 下降但总周期可能仍高 | DDR task 开销、burst 利用率、row tail、CDC 等可能才是瓶颈 | 结论必须同时记录 cycles、reads、misses、prefetches、hits 和关键 profile。 |



## 当前安全运行入口

单元 smoke 示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30
```

### Round 2026-04-25-geom-init-unit

- 目标：把 `rotate_core_bilinear` 和 `src_tile_cache` 中重复的逆映射几何初始化抽到公共模块，避免 scale/center/step/row0 两边公式漂移。
- RTL / 参数改动：
  - 新增 `rtl/core/rotate_geom_init_unit.sv`，内部使用顺序 restoring divider，禁止运行时 `/ dst_w` / `/ dst_h`。
  - `rotate_core_bilinear.sv` 删除旧 `S_DIV_* / S_CENTER / S_STEP_* / S_ROW0_*` 初始化路径，改为 `S_GEOM_WAIT` 等待公共几何单元 `geom_valid` 后进入 `S_PRECALC_INIT`。
  - `src_tile_cache.sv` 删除旧 `PINIT_*` planner 初始化路径，analytic planner 直接使用公共几何单元输出的 `row0/step/bounds`。

### Round 2026-04-26-geom-trace-and-baseline-subset

- 目标：补齐第五项几何共享验证，并启动第七项 baseline 子集；仍然坚持带 timeout 的短任务，不裸跑长仿真。
- RTL / 脚本 / 文档改动：
  - 新增 `rtl/sim/tb_rotate_geom_init_unit.sv`，覆盖角度 `0,1,3,5,15,30,45,60,75,90` 和 `7200/4096/1920/非方形` 尺寸，和 testbench golden 比较 scale/step/row0/bounds。
  - 新增 `rtl/sim/tb_rotate_core_bilinear_trace.sv`，记录 `rotate_core_bilinear` 发出的 sample trace，验证 core 使用共享几何后的逐像素采样坐标。
  - 新增 `rtl/sim/tb_src_tile_cache_analytic_trace.sv`，直接观察 cache analytic planner candidate，验证 `geom_ready` 前不推进、identity 轨迹下候选 tile 覆盖预期未来访问。
  - `tools/run-module-sim.ps1` 增加 `rotate_geom_init_unit` 和 `rotate_core_bilinear_trace` 两个 bounded target。
  - `scripts/run_cache_sweep.py` 增加 `--prefetch-mode off/on/both`，baseline 可以同一 workload 成对比较 prefetch off/on。
  - 新增 `scripts/gen_baseline_subset.py` 和 `scripts/summarize_baseline.py`，先生成小型 baseline 子集和摘要，避免直接启动全矩阵。
- 命令与输出：
  - `tools/run-module-sim.ps1 rotate_geom_init_unit -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`：pass。
  - `tools/run-module-sim.ps1 rotate_core_bilinear_trace -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`：pass。
  - `tools/run-module-sim.ps1 src_tile_cache_analytic_trace -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`：pass，`SRC_TILE_CACHE_ANALYTIC_TRACE_PASS candidates=256 duplicates=254 blocked=0 fifo_max=2`。
  - `tools/run-module-sim.ps1 image_geo_top -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 60`：pass，覆盖 prefetch on/off top smoke 和扩展统计打印。
  - `scripts/run_cache_sweep.py --prefetch-mode both ...`：生成 `sim_out/cache_baseline/baseline_subset_fast.csv`，共 25 个 workload、off/on 50 行。
  - `scripts/summarize_baseline.py`：生成 `sim_out/cache_baseline/baseline_subset_summary.md`。
  - `tools/run-cache-perf-case.ps1` 跑 `small_rotate45_off/on`：两组均 pass，输出在 `sim_out/cache_perf/baseline_light_small_rotate45_*`。
  - `scripts/gen_baseline_matrix.py`：生成 `sim_out/cache_baseline/baseline_workloads.csv`，5 类尺寸 x 10 个角度 x 3 类 stride，共 150 个 workload。
  - `scripts/run_cache_sweep.py --prefetch-mode both ...`：生成完整快速模型 baseline `sim_out/cache_baseline/baseline_report.csv`，共 300 行。
  - `scripts/summarize_baseline.py`：生成 `sim_out/cache_baseline/baseline_summary.md`。
- 第五项验证结果：
  - `rotate_geom_init_unit` golden test 全部通过，说明公共几何单元的 scale/step/row0/bounds 公式在这些角度/尺寸下自洽。
  - `rotate_core_bilinear_trace` 通过 `identity_16_to_8`、`rotate15_20_to_12`、`rotate45_24_to_16`、`rotate75_24_to_16`，逐 sample 坐标和 golden 一致。
  - `src_tile_cache_analytic_trace` 证明 cache planner 在 `geom_ready` 前不会产生 candidate；`geom_ready` 后 identity row 的 tile0/tile1 均被覆盖，没有产生越界 tile。
  - `image_geo_top` smoke 通过，说明共享几何接入 top 后没有破坏 bit-exact 小图路径。
- 第七项 baseline 子集结果：

| 数据源 | 配置 | 覆盖 | 关键结果 | 状态 | 结论 |
| --- | --- | --- | --- | --- | --- |
| `sim_out/cache_baseline/baseline_subset_fast.csv` | `8x8,SET64,WAY4,MERGE8,FIFO32,LEAD64,RD16/OB4/BEATS16` | 5 类尺寸 x 5 个角度，packed stride，prefetch off/on | prefetch on 在 19/25 个 workload 上更快，在 6/25 个 workload 上变慢 | fast-model baseline | 默认 analytic prefetch 对多数小/中角度有收益，但大图 `45/75` 度存在污染或读放大风险，后续必须做 row-bucket merge / throttle / adaptive lead 的 A/B。 |
| `sim_out/cache_baseline/baseline_report.csv` | 同上，stride-aware 读服务估算 | 5 类尺寸 x 10 个角度 x 3 类 stride，prefetch off/on | prefetch on 在 120/150 个 workload 上更快，在 30/150 个 workload 上变慢 | fast-model baseline | 完整 baseline 快速模型已建立；仍需对 shortlist 做 RTL bit-exact 和资源/时序筛选。 |
| `sim_out/cache_perf/baseline_light_small_rotate45_off` | RTL lightweight，prefetch off | `64x64 -> 24x24`，45 度 | `cycles=26840 reads=78 misses=78 sample_stall=7098 read_bytes=4992` | rtl pass | off 模式作为无预取对照可用。 |
| `sim_out/cache_perf/baseline_light_small_rotate45_on` | RTL lightweight，prefetch on | `64x64 -> 24x24`，45 度 | `cycles=23072 reads=101 misses=29 prefetches=72 hits=61 evict_unused=15 sample_stall=5214 read_bytes=6848` | rtl pass | on 模式减少 stall 和 miss，但增加 DDR 读取与 unused evict；后续优化不能只看 miss。 |

经验记录：
- 第五项目前已完成几何单元 golden、core sample trace、cache analytic planner trace 和 top bit-exact smoke。generation-id/忙时新配置主要由 `tb_image_geo_top` 的 start-while-busy probe 覆盖；后续若引入真正的多帧 pipeline，再补恶意 stale-geom 注入测试。
- 第七项目前完成了完整 baseline 的快速模型层和一个 RTL 小 case 成对验证；完整矩阵还没有逐项 RTL 化，不能把 fast-model 结果当最终推荐。
- 大图 45/75 度 prefetch on 变慢再次提醒：`MERGE_MAX_X=8, LEAD64` 不是全角度全尺寸万能默认，必须用扩展统计解释读放大和污染。
- 以后任何“看起来 miss 更少”的配置，如果 `read_bytes/read_busy/sample_stall/evict_unused` 变差，都不能直接升为推荐。

### Round 2026-04-26-error-and-axi-smoke

- 目标：补第三项 cache error 到总控 error 的单元验证，并复查第六项 AXI read/write engine bounded smoke。
- RTL / 测试改动：
  - `rtl/sim/tb_scaler_ctrl.sv` 增加 `cache_error` 注入段，要求控制器进入 error，且离开 busy，不再等待 core/write done。
- 命令：
  - `tools/run-module-sim.ps1 ddr_read_engine -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `tools/run-module-sim.ps1 ddr_write_engine -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `tools/run-module-sim.ps1 scaler_ctrl -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
- 结果：

| Case | 关键覆盖 | 状态 | 结论 |
| --- | --- | --- | --- |
| `tb_ddr_read_engine` | `rresp_error`、`rlast_error`、2D read path | pass | 读引擎 bounded smoke 通过，无 Fatal/ERROR。 |
| `tb_ddr_write_engine` | `bresp_error`、write path | pass | 写引擎 bounded smoke 通过，无 Fatal/ERROR。 |
| `tb_scaler_ctrl` | `SCALER_CTRL_CACHE_ERROR_PASS` | pass | `cache_error` 会显式触发总控 error，避免 pipeline 卡在等待 done。 |

经验记录：
- cache/read error 传播不能只看 top unused wire，必须至少有 scaler_ctrl 单元注入测试。
- AXI 参数继续进入 sweep 前，读写 engine 单测是最低成本守门；如果未来 SVA 报错，先停在 engine 级别修，不要直接跑 top perf。

### Round 2026-04-26-scheduler-fast-model-ab

- 目标：启动第八项 scheduler 可调优化，但先只在快速模型层做 A/B，不改 RTL 调度器。
- 脚本改动：
  - `scripts/run_cache_sweep.py` 增加 `--merge-min-x`、`--fifo-age-limit`、`--enable-prefetch-throttle`、`--prefetch-throttle-cycles`。
  - 快速模型 FIFO 记录 enqueue cycle，merge threshold 支持“达到 `MERGE_MIN_X` 才发射，或 FIFO head age 超过 `FIFO_AGE_LIMIT` 后小 run 也可发射”。
  - 快速模型 read service 估算加入 stride 和 4KB 边界拆分，baseline 的 packed/aligned/unaligned 不再完全等价。
- 命令与输出：
  - 默认 baseline：`sim_out/cache_baseline/baseline_report.csv`，`MERGE_MIN_X=1`。
  - A/B：`sim_out/cache_baseline/baseline_merge_min4_age200.csv`，`MERGE_MIN_X=4,FIFO_AGE_LIMIT=200`。
  - 对比：`sim_out/cache_baseline/merge_min4_age200_vs_default.csv`。
- 结果：

| 对比项 | Workloads | Improved | Regressed | Tie | Total delta cycles | 结论 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| prefetch-on：`MERGE_MIN_X=4,FIFO_AGE_LIMIT=200` vs 默认 | 150 | 48 | 30 | 72 | +134,790 | 不是全局更优；可作为局部策略候选，不能直接作为默认 RTL 参数。 |

经验记录：
- merge threshold 对 `large_tall_a0/a1` 和部分小角度有明显收益，但对 `large_wide_a90` 退化很大，说明单一 merge threshold 不适合所有方向。
- 第八项下一步应优先做“按角度/访问方向选择 scheduler 策略”或 row-bucket merge，而不是把 `MERGE_MIN_X=4` 固化为默认。

### Round 2026-04-26-merge-reservation-test

- 目标：补第四项“同一 analytic merge fill_request 内 way reservation”定向验证，避免参数 sweep 后多个 sector 选到同一 set/way 的隐藏冲突。
- 测试改动：
  - 新增 `rtl/sim/tb_src_tile_cache_merge_reservation.sv`。
  - `tools/run-module-sim.ps1` 增加 `src_tile_cache_merge_reservation` target，并支持 target-local `Defines`。
  - 复用历史经验：Vivado 2019.2 下不用 `xvlog -d NAME=VALUE`，runner 会生成 `sim_out/<target>/module_defines.sv` 作为第一个源码。
- 参数：
  - `SRC_TILE_CACHE_SECTOR_SET_NUM=2`
  - `SRC_TILE_CACHE_SECTOR_WAY_NUM=4`
  - `SRC_TILE_CACHE_MERGE_MAX_X=8`
  - `SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH=16`
  - `SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS=64`
- 命令：`tools/run-module-sim.ps1 src_tile_cache_merge_reservation -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
- 结果：pass，日志包含 `SRC_TILE_CACHE_MERGE_RESERVATION_PASS`。

经验记录：
- 以后需要带参数编译的模块级测试，不要回到 `xvlog -d NAME=VALUE`；用 runner 的临时 define 文件路径。
- 小 `SET_NUM` 是暴露 merge reservation bug 的低成本测试，后续修改 replacement/merge builder 后必须重跑。

### Round 2026-04-26-fire-stats-scheduler-rtl

- 目标：本轮只做“小源码修改 + 小矩阵 RTL 校准”，不启动完整大规模 RTL workload matrix。
- RTL / 脚本改动：
  - `image_geo_top.sv` 新增 `core_cfg_fire = core_cfg_valid && core_cfg_ready`，`scaler_ctrl.start`、`src_tile_cache.start`、geometry config latch、frame cycle clear 均改用 fire。
  - `image_geo_top.sv` 接出 `cache_stats_ready_core`，新增 one-deep pending snapshot、`cache_stats_overrun_reg` 和仿真断言；扩展统计 payload 新增 overrun word。
  - `image_geo_top.sv` 接出 `result_ready_src`，新增 result CDC busy 时重复 result event 的仿真断言。
  - `src_tile_cache.sv` 增加 scheduler 宏：`ENABLE_MERGE_MIN`、`MERGE_MIN_X`、`FIFO_AGE_LIMIT`、`ENABLE_PREFETCH_THROTTLE`、`PREFETCH_THROTTLE_CYCLES`。默认值保持当前行为。
  - `src_tile_cache.sv` 为 analytic FIFO 增加 entry age；打开 `ENABLE_MERGE_MIN` 后支持 merge min/age 发射；打开 throttle 后 real miss 和 miss 后窗口内暂停 speculative prefetch。
  - `gen_param_header.py`、`run-cache-perf-case.ps1`、`run_rtl_shortlist.py` 同步 scheduler 参数。
  - 新增 `tb_cache_stats_cdc_back_to_back.sv`，验证 stats pending 可以吸收第二个 snapshot，第三个在 CDC busy 且 pending 满时 overrun。
  - `tb_image_geo_top.sv` 增加短 deterministic backpressure case，扰动 ARREADY、RVALID 空泡、AWREADY、WREADY；随后又补了 top 级 read `RRESP`、write `BRESP` 错误注入和 reset-during-busy case。
- 验证命令：
  - `tools/run-module-sim.ps1 cache_stats_cdc`
  - `tools/run-module-sim.ps1 src_tile_cache`
  - `tools/run-module-sim.ps1 image_geo_top`
  - `tools/run-module-sim.ps1 src_tile_cache_prefetch_merge_min`
  - `tools/run-module-sim.ps1 src_tile_cache_prefetch_throttle`
  - 模块 smoke 集合：`task_cdc,result_cdc,async_word_fifo,ddr_read_engine,ddr_write_engine,scaler_ctrl,rotate_geom_init_unit,rotate_core_bilinear_trace,src_tile_cache_prefetch,src_tile_cache_merge_reservation`
  - 轻量 perf：`sched_default_small_rotate45_off/on`
- 结果：

| Case | 关键结果 | 状态 | 结论 |
| --- | --- | --- | --- |
| `tb_cache_stats_cdc_back_to_back` | `CACHE_STATS_CDC_BACK_TO_BACK_PASS` | pass | stats CDC 不静默丢第二个 snapshot；第三个过载会置 overrun。 |
| `tb_image_geo_top` | 新增 `identity_32_to_16_random_backpressure`、`identity_32_to_16_read_error_injection`、`identity_32_to_16_write_error_injection`、`reset_during_busy` 通过 | pass | top 短 backpressure、read/write error 传播和 busy 中复位均通过。 |
| `src_tile_cache_prefetch_merge_min` | merge-min 编译/仿真通过 | pass | scheduler 开关可综合路径基本可用，默认未改变。 |
| `src_tile_cache_prefetch_throttle` | throttle 编译/仿真通过 | pass | throttle 开关可编译运行，real miss 优先级未被破坏。 |
| `small_rotate45_off` | `cycles=26840 reads=78 misses=78` | pass | 默认 scheduler 关闭时与上一轮一致。 |
| `small_rotate45_on` | `cycles=23072 reads=101 misses=29 prefetches=72 hits=61` | pass | 默认 scheduler 关闭时与上一轮一致。 |

- 模型/RTL 校准：
  - 输出：`sim_out/model_rtl_calibration/model_rtl_error_report.csv`
  - 摘要：`sim_out/model_rtl_calibration/model_rtl_error_summary.md`
  - `small_rotate45 off` 快速模型误差 `-35.08%`，`on` 误差 `-26.80%`。

经验记录：
- 快速模型当前明显低估小图 RTL cycles，误差超过 10%；因此不能扩大 RTL workload matrix，必须先校准模型的固定开销、CDC/task 延迟和写回开销。
- `core_cfg_valid` 被 hold 不是错误，只有 `core_cfg_fire` 才代表新配置被消费；以后不要再用 raw valid 清帧或启动内部模块。
- stats snapshot 必须先 pending 再 CDC；如果统计 overrun 出现，相关性能数据不能用于参数推荐。
- 本轮 top backpressure 已覆盖 ARREADY/AWREADY/WREADY 扰动和 RVALID 空泡；top 级 RRESP/BRESP 注入已覆盖。
- busy 中复位已经有 top smoke；以后 CDC/reset 相关修改至少重跑 `tools/run-module-sim.ps1 image_geo_top`。

### Round 2026-04-26-model-calibration-and-report-gates

- 目标：在不启动大规模 RTL workload matrix 的前提下，把 fast model 校准入口、Vivado 报告入口和“防卡死”门槛补齐。
- 脚本 / 文档改动：
  - `scripts/run_cache_sweep.py` 新增显式 RTL 校准项：`rtl_frame_overhead`、`rtl_demand_miss_extra_cycles`、`rtl_prefetch_fill_extra_cycles`、`rtl_read_start_extra_cycles`，并在 CSV 中同时输出 `raw_total_cycles_est` 和校准后 `total_cycles_est`。
  - `scripts/run_cache_sweep.py` 的 workload CSV 读取改为 `utf-8-sig`，避免 PowerShell 生成 BOM 后把表头读坏。
  - 新增 `scripts/compare_model_rtl.py`，把 fast-model CSV 与小 RTL 结果 CSV 对齐，输出误差报告。
  - 新增 `scripts/extract_perf_single.py`，从 `xsim.log` 中提取 `PERF_SINGLE` 行生成 RTL 校准 CSV。
  - 新增 `tools/image_geo_reports.tcl` 和 `tools/run-vivado-reports.ps1`，后者带进程级 timeout，避免 Vivado synth/report 无界运行。
  - Vivado 报告脚本补充 XPM FIFO/CDC 源，并支持 `-SmallConfig` 小参数 elaboration；仿真 runner 源列表补齐 `pixel_packer.sv`，避免依赖旧编译库。
  - `tb_image_geo_top_perf_single_light.sv` 新增 `cal128_rotate45_off/on` 两个轻量校准 top。
- 命令与输出：
  - `python scripts/run_cache_sweep.py ... --rtl-frame-overhead 5200 --rtl-demand-miss-extra-cycles 54`：输出 `sim_out/model_rtl_calibration/small_model_calibrated.csv`。
  - `python scripts/compare_model_rtl.py ...`：输出 `sim_out/model_rtl_calibration/model_rtl_error_report_calibrated.csv` 和 `model_rtl_error_summary_calibrated.md`。
  - `tools/run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_mid_rotate45_off ... -SimTimeoutSec 120`：120 秒超时，被 runner 正常终止并清理，不作为性能结论。
  - `tools/run-cache-perf-case.ps1 -Top tb_image_geo_top_perf_single_cal128_rotate45_off/on ... -SimTimeoutSec 90`：两组均 pass。
  - `tools/run-vivado-reports.ps1 -Mode synth -TimeoutSec 300` 和 `-Mode synth -SmallConfig -TimeoutSec 120`：均超时，日志保留在 `reports/vivado_reports.log`；未生成正式 `report_cdc/report_timing_summary`。
  - `tools/run-vivado-reports.ps1 -Mode rtl -SmallConfig -TimeoutSec 120`：pass，生成 `reports/report_elaboration_status.rpt`，仅证明 RTL elaboration/约束读取入口可运行，不等同 CDC/timing pass。
- 结果：

| Case | 原始模型 | 校准模型 | RTL | 误差 | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| `small_rotate45` prefetch off | 17,424 | 26,836 | 26,840 | -0.01% | calibrated small sample |
| `small_rotate45` prefetch on | 16,889 | 23,331 | 23,072 | +1.12% | calibrated small sample |
| `cal128_rotate45` prefetch off | 96,912 | 125,764 | 129,834 | -3.13% | calibrated light mid sample |
| `cal128_rotate45` prefetch on | 100,925 | 114,873 | 108,898 | +5.49% | calibrated light mid sample |
| `mid_rotate45_off` RTL | - | - | - | timeout 120s | 不作为性能结论 |
| Vivado rtl small elaboration | - | - | - | pass 约 56s | 只验证报告入口和 XPM/source list |
| Vivado synth report gate | - | - | - | timeout 120/300s | 正式 CDC/timing 门槛未通过 |

经验记录：
- 以后 fast model 的 CSV 必须同时保存 raw 和 calibrated cycles；否则看不到模型本身误差来源。
- 当前校准覆盖 `small_rotate45` 和 `cal128_rotate45`，说明小/轻中等帧误差可压到 10% 内；仍不能外推成大图结论。
- `2048->256` 这类中等 RTL top 暂时太慢，不适合校准循环；后续先用 `128/256` 级轻量点扩大角度覆盖，再考虑真实 shortlist。
- Vivado 报告必须继续用 `tools/run-vivado-reports.ps1` 这类带 timeout 的入口；裸跑 synth/report_cdc 会重复之前“卡半小时以上”的错误。
- `src_tile_cache` 的当前 3D RAM 综合日志显示大量寄存器实现 warning，这是后续资源/时序筛选必须重点处理的风险，不能只看仿真 cycles。
- `report_cdc/report_timing_summary` 必须在 synthesized design 上生成；`-Mode rtl` 只作为快速 elaboration sanity，不允许写成 CDC 已通过。

### Round 2026-04-26-storage-flatten-and-cal128-angle-gate

- 目标：继续执行“小源码修改 + 小矩阵 RTL 校准”，先把资源/报告入口和模型可信度收口，不启动完整大规模 RTL workload matrix。
- RTL / 脚本改动：
  - `rtl/buffer/src_tile_cache.sv` 将 sector cache 从二维/三维 unpacked 存储改成线性 slot + packed sector row：`SLOT_NUM=SET_NUM*WAY_NUM`，`sector_mem[slot]` 保存一个 packed micro-tile，tag/valid/prefetch/used/touch 也改成按 slot 索引。这样避免 Vivado 把 3D RAM 拆成大量寄存器的警告。
  - `rtl/buffer/row_out_buffer.sv` 将输出行缓存从 `mem[BUF][X]` 改成每个 buffer 一条 packed row，按 `pixel_lsb()` 做切片读写，降低综合器对多维 RAM 的误判风险。
  - `constraints/cdc_image_geo_top.xdc` 改为使用 top-level `axi_clk/core_clk/axi_rstn/core_rstn` 端口建 clock/reset 约束，避免 standalone report 里出现 no clock / empty clock group 的假 Critical Warning。
  - `tools/image_geo_reports.tcl` 支持 `rtl/synth` 两种模式和 `small` 小参数定义；`rtl small` 只做 elaboration sanity，不生成 CDC/timing 结论。
  - `tools/run-module-sim.ps1` 和 `tools/run-cache-perf-case.ps1` 源列表补齐 `rtl/core/pixel_packer.sv`，避免依赖旧的 `xil_defaultlib` 编译残留。
  - `rtl/sim/tb_image_geo_top_perf_single_light.sv` 增加 `cal128_rotate0/15/75/90_off/on`，与已有 `small_rotate45`、`cal128_rotate45` 组成轻量多角度校准集。
  - `scripts/compare_model_rtl.py` 增加 `abs_error_pct`、`within_threshold`、`--max-error-pct`、`--fail-on-threshold`，摘要中明确写出模型是否可信。
- 验证命令：
  - `tools/run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `tools/run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 30`
  - `tools/run-module-sim.ps1 src_tile_cache_merge_reservation -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 20`
  - `tools/run-module-sim.ps1 image_geo_top -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 60`
  - `tools/run-vivado-reports.ps1 -Mode rtl -SmallConfig -TimeoutSec 120`
  - `tools/run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 120`
  - `tools/run-cache-perf-case.ps1` 跑 `cal128_rotate0/15/45/75/90_off/on`，每个 case 独立目录，`SimTimeoutSec=90`。
- 输出：
  - `reports/report_elaboration_status.rpt`
  - `reports/vivado_reports.log`
  - `sim_out/model_rtl_calibration/rtl_calibration_points.csv`
  - `sim_out/model_rtl_calibration/calibration_model_smallfit.csv`
  - `sim_out/model_rtl_calibration/model_rtl_error_report_smallfit.csv`
  - `sim_out/model_rtl_calibration/model_rtl_error_summary_smallfit.md`

验证结果：

| Case | 状态 | 结论 |
| --- | --- | --- |
| `tb_src_tile_cache` | pass | 线性 slot cache 未破坏基本 miss/fill/sample 命中路径。 |
| `tb_src_tile_cache_prefetch` | pass | 默认 prefetch 行为保持可用。 |
| `tb_src_tile_cache_merge_reservation` | pass | 低 `SET_NUM` 下同一 merge request 不重复占用同一 set/way。 |
| `tb_image_geo_top` | pass | top smoke、random backpressure、read/write error injection、reset during busy 仍通过。 |
| `Vivado rtl small elaboration` | pass | RTL elaboration 约十几秒完成；日志中不再出现 cache/row 相关 3D RAM warning，0 design error，0 design critical warning。 |
| `Vivado synth small` | timeout 120s | 停在后续综合/约束阶段附近；正式 `report_cdc/report_timing_summary` 仍未达成，不能写成 timing/CDC pass。 |
| `cal128 0/15/45/75/90 off/on` | pass | 轻量多角度 RTL 校准点已生成，但只用于模型校准，不是最终 workload 结论。 |

模型/RTL 校准结果，阈值为 10%：

| Workload | Prefetch | Raw model | Calibrated model | RTL | Error | 是否可信 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `small_rotate45` | off | 17,424 | 26,836 | 26,840 | -0.01% | yes |
| `small_rotate45` | on | 16,889 | 23,331 | 23,072 | +1.12% | yes |
| `cal128_rotate0` | off | 57,600 | 76,624 | 94,708 | -19.09% | no |
| `cal128_rotate0` | on | 17,999 | 23,253 | 98,936 | -76.50% | no |
| `cal128_rotate15` | off | 55,440 | 73,924 | 92,888 | -20.42% | no |
| `cal128_rotate15` | on | 42,136 | 47,552 | 80,936 | -41.25% | no |
| `cal128_rotate45` | off | 96,912 | 125,764 | 129,834 | -3.13% | yes |
| `cal128_rotate45` | on | 100,925 | 114,873 | 108,898 | +5.49% | yes |
| `cal128_rotate75` | off | 55,008 | 73,384 | 92,524 | -20.69% | no |
| `cal128_rotate75` | on | 52,609 | 58,727 | 83,570 | -29.73% | no |
| `cal128_rotate90` | off | 57,600 | 76,624 | 94,708 | -19.09% | no |
| `cal128_rotate90` | on | 56,191 | 61,445 | 89,042 | -30.99% | no |

经验记录：
- 这是一个明确的拦截点：当前 fast model 最大绝对误差 `76.50%`，摘要已写 `Trusted for RTL shortlist expansion: no`。因此不能扩大 RTL sweep，更不能用这版模型生成最终推荐。
- 简单的 `frame_overhead + demand_miss_extra` 校准只适合 45 度附近；规则方向 `0/90` 和小角度 `15` 的 core/pipeline/sample 接受节拍没有被模型描述出来，prefetch-on 时尤其过于乐观。
- storage flatten 后再看资源/时序；不要继续引用“3D RAM warning”作为当前最新风险。最新风险已经转为：small synth 仍然超时，正式 CDC/timing report 尚未产出。
- `pixel_packer.sv` 必须在所有 top/perf 编译源列表中显式出现；以后若仿真只因旧库通过，要视为不可信。
- 任何后续大矩阵 RTL 或参数推荐前，必须先让 `model_rtl_error_summary_*.md` 的最大误差低于门槛，或把模型标注为仅能筛角度/策略、不能筛 cycles。

### Round 2026-04-26-fast-model-linear-calibration

- 目标：针对上一轮 `0/15/75/90` 误差过大的问题，先修快速模型和校准流程，不动 RTL，不启动大规模 RTL workload matrix。
- 脚本改动：
  - `scripts/extract_perf_single.py` 扩展解析 `PERF_SINGLE_STATS_EXT`，现在能输出 `frame_cycles/cache_cycles/sample_stall/read_busy/read_bytes/useful_sectors/normal_prefetch/fifo_max/merge_hist` 等扩展统计。
  - `scripts/run_cache_sweep.py` 增加校准项：`--rtl-raw-cycle-scale`、`--rtl-dst-pixel-extra-cycles`、`--rtl-read-sector-extra-cycles`、`--planner-pixels-per-cycle`、`--prefetch-min-miss-ratio`、`--prefetch-read-amplification`。默认值保持旧含义或关闭校准。
  - `scripts/compare_model_rtl.py` 保留 `abs_error_pct/within_threshold`，并把新增校准项写入对比 CSV。
  - 新增 `scripts/fit_model_calibration.py`，从 fast-model CSV 和 RTL CSV 拟合当前 `run_cache_sweep.py` 支持的线性校准参数，输出 JSON 和 Markdown 摘要。
- 命令：
  - `python scripts/extract_perf_single.py --out sim_out/model_rtl_calibration/rtl_calibration_points_ext.csv ...`
  - `python scripts/run_cache_sweep.py --workloads sim_out/model_rtl_calibration/calibration_workloads.csv --out sim_out/model_rtl_calibration/calibration_model_planner1.csv ...`
  - `python scripts/fit_model_calibration.py --model sim_out/model_rtl_calibration/calibration_model_planner1.csv --rtl sim_out/model_rtl_calibration/rtl_calibration_points_ext.csv --out-json sim_out/model_rtl_calibration/linear_calibration_params.json --out-md sim_out/model_rtl_calibration/linear_calibration_fit.md`
  - `python scripts/run_cache_sweep.py ... --rtl-frame-overhead 152 --rtl-raw-cycle-scale -0.38715 --rtl-dst-pixel-extra-cycles 27.035 --rtl-demand-miss-extra-cycles 95.251 --rtl-prefetch-fill-extra-cycles 31.443 --rtl-read-sector-extra-cycles 126.694`
  - `python scripts/compare_model_rtl.py --model sim_out/model_rtl_calibration/calibration_model_linear_smallfit.csv --rtl sim_out/model_rtl_calibration/rtl_calibration_points_ext.csv --out sim_out/model_rtl_calibration/model_rtl_error_report_linear_smallfit.csv --summary sim_out/model_rtl_calibration/model_rtl_error_summary_linear_smallfit.md --max-error-pct 10`
  - `python -m py_compile scripts/run_cache_sweep.py scripts/compare_model_rtl.py scripts/extract_perf_single.py scripts/fit_model_calibration.py`
- 输出：
  - `sim_out/model_rtl_calibration/rtl_calibration_points_ext.csv`
  - `sim_out/model_rtl_calibration/linear_calibration_params.json`
  - `sim_out/model_rtl_calibration/linear_calibration_fit.md`
  - `sim_out/model_rtl_calibration/calibration_model_linear_smallfit.csv`
  - `sim_out/model_rtl_calibration/model_rtl_error_report_linear_smallfit.csv`
  - `sim_out/model_rtl_calibration/model_rtl_error_summary_linear_smallfit.md`

结果：

| 校准集 | 行数 | 最大绝对误差 | 可信状态 | 结论 |
| --- | ---: | ---: | --- | --- |
| `small_rotate45` + `cal128_rotate0/15/45/75/90` off/on | 12 | `8.77%` | `Trusted for RTL shortlist expansion: yes` | 轻量 RTL 校准域内可以继续用于 shortlist 粗筛。 |

关键行：

| Workload | Prefetch | Model | RTL | Error |
| --- | --- | ---: | ---: | ---: |
| `cal128_rotate0` | on | 96,019 | 98,936 | -2.95% |
| `cal128_rotate15` | on | 85,443 | 80,936 | +5.57% |
| `cal128_rotate45` | on | 114,670 | 108,898 | +5.30% |
| `cal128_rotate75` | on | 81,743 | 83,570 | -2.19% |
| `cal128_rotate90` | on | 81,233 | 89,042 | -8.77% |

经验记录：
- 这轮证明“只用 `frame_overhead + miss_extra`”不够；必须把 output pixel 固定节拍、read sector、prefetch fill 等项纳入校准，才能覆盖规则方向和对角方向。
- 当前拟合中 `rtl_raw_cycle_scale` 为负，说明特征之间仍然有强相关，不能把这组系数解释成物理含义；它只是当前轻量校准域内的经验回归。后续如果扩大到 `256` 或真实 workload，必须重新拟合并重新看最大误差。
- `model_rtl_error_summary_linear_smallfit.md` 通过 10% 门槛，只允许进入“小规模 RTL shortlist 粗筛”；仍不允许直接出最终参数推荐。
- 以后新增 RTL 校准点后，必须先跑 `fit_model_calibration.py`，再跑 `compare_model_rtl.py`。如果摘要写 `Trusted ... no`，立即停止扩大 sweep。

### Round 2026-04-26-cal128-shortlist-rtl

- 目标：在模型通过轻量校准后，只跑一轮小规模 RTL shortlist，验证模型是否能帮助选择参数；不启动完整 workload matrix。
- 参数空间：
  - Workload：`cal128_rotate0/15/45/75/90`，prefetch on。
  - `BASE_TILE_W={8,16}`，`BASE_TILE_H={8,16}`。
  - `SET_NUM=64`，`WAY_NUM=4`。
  - `MERGE_MAX_X={4,8}`，`FIFO_DEPTH={16,32}`，`LEAD={16,32,64}`。
  - DDR 参数固定为 `RD_BURST=16, OUTSTANDING_BURSTS=4, OUTSTANDING_BEATS=16, FIFO_WORDS=64`。
- 脚本改动：
  - `scripts/run_rtl_shortlist.py` 增加 `--sort-key`，本轮可按 `total_cycles_est` 或 `score` 选择候选。默认仍为 `score`，兼容旧流程。
- 命令与输出：
  - Fast model：`sim_out/model_rtl_calibration/cal128_shortlist_model.csv`。
  - RTL shortlist：
    - `sim_out/model_rtl_calibration/rtl_shortlist_cal128_rotate0_top1.csv`
    - `sim_out/model_rtl_calibration/rtl_shortlist_cal128_rotate15_score_top1.csv`
    - `sim_out/model_rtl_calibration/rtl_shortlist_cal128_rotate45_top1.csv`
    - `sim_out/model_rtl_calibration/rtl_shortlist_cal128_rotate45_score_top1.csv`
    - `sim_out/model_rtl_calibration/rtl_shortlist_cal128_rotate75_score_top1.csv`
    - `sim_out/model_rtl_calibration/rtl_shortlist_cal128_rotate90_top1.csv`
  - 汇总：`sim_out/model_rtl_calibration/rtl_shortlist_cal128_summary.csv`。
  - 所有 RTL case 均通过 bounded runner，每个 case 约 14-18 秒结束，无 timeout。

结果：

| Workload | Sort | Params | RTL cycles | Default cycles | Delta | Misses | Prefetches | Read bytes | Sample stall | Read busy | 结论 |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `cal128_rotate0` | `total_cycles_est` | `16x16,m4,f16,l16` | 79,934 | 98,936 | -19.21% | 0 | 47 | 16,384 | 15,909 | 20,809 | 规则方向短 lead 大 tile 有效。 |
| `cal128_rotate15` | `score` | `16x16,m8,f16,l64` | 74,768 | 80,936 | -7.62% | 21 | 61 | 22,528 | 13,326 | 28,734 | 小角度更需要保留 lead。 |
| `cal128_rotate45` | `total_cycles_est` | `16x16,m4,f16,l16` | 133,234 | 108,898 | +22.35% | 19 | 146 | 44,800 | 42,559 | 57,155 | 仅按 estimated cycles 误选，读放大严重。 |
| `cal128_rotate45` | `score` | `16x8,m4,f16,l64` | 69,926 | 108,898 | -35.79% | 29 | 136 | 21,888 | 10,905 | 28,515 | 对角访问更适合矮 tile 和较长 lead。 |
| `cal128_rotate75` | `score` | `16x16,m4,f16,l64` | 72,242 | 83,570 | -13.56% | 16 | 68 | 21,760 | 12,063 | 27,788 | 大角度但非正交时较长 lead 有效。 |
| `cal128_rotate90` | `total_cycles_est` | `16x16,m4,f16,l16` | 80,258 | 89,042 | -9.87% | 0 | 64 | 16,384 | 16,071 | 20,928 | 正交方向短 lead 大 tile 有效。 |

经验记录：
- `total_cycles_est` 在 `rotate45` 上会误选，因为模型仍低估 `16x16` 对角访问的 DDR 读放大；`score` 由于包含 stall 惩罚，反而选到更好的 `16x8,LEAD64`。
- 轻量域下不能只按一个排序字段选候选。下一轮 shortlist 建议每个 workload 同时取 `total_cycles_est top1` 和 `score top1`，再由 RTL 验证。
- `16x16,LEAD16` 适合 `0/90` 这类规则方向；`16x8,LEAD64` 明显适合 `45` 度；`15/75` 暂时倾向 `16x16,LEAD64`。
- 本轮只是 `128x128 -> 48x48` 轻量域结果，不允许直接升级为 `7200->600` 或 `1000->600` 的默认推荐。

### Round 2026-04-26-cal256-scale-check

- 目标：把 `cal128` 的角度分桶规律上推到 `256x256 -> 96x96`，验证参数规律是否随帧长保持；仍然只跑少量 bounded RTL，不跑大矩阵。
- RTL 改动：
  - `rtl/sim/tb_image_geo_top_perf_single_light.sv` 新增：
    - `tb_image_geo_top_perf_single_cal256_rotate0_on`
    - `tb_image_geo_top_perf_single_cal256_rotate45_on`
    - `tb_image_geo_top_perf_single_cal256_rotate90_on`
  - 尺寸为 `256x256 -> 96x96`，stride 为 `256/128`，timeout 为 `12,000,000` core cycles。
- 运行策略：
  - 默认对照：`8x8,MERGE8,FIFO32,LEAD64`。
  - 从 `cal128` 迁移的候选：
    - `0/90`：`16x16,MERGE4,FIFO16,LEAD16`。
    - `45`：`16x8,MERGE4,FIFO16,LEAD64`。
  - 针对 `0/90` 退化，补跑 `16x16,MERGE8,FIFO16,LEAD64` 判断是否只是 lead 太短。
- 输出：
  - `sim_out/model_rtl_calibration/rtl_cal256_points_ext.csv`
  - `sim_out/model_rtl_calibration/rtl_cal256_summary.csv`
  - 对应 xsim 日志均在 `sim_out/cache_perf/cal256_*` 下。

结果：

| Workload | Params | RTL cycles | Default cycles | Delta | Reads | Misses | Prefetches | Hits | Read bytes | Sample stall | Read busy | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `cal256_rotate0` | `8x8,m8,f32,l64` | 263,740 | 263,740 | 0.00% | 215 | 11 | 204 | 1027 | 66,432 | 37,780 | 84,545 | 默认对照。 |
| `cal256_rotate0` | `16x16,m4,f16,l16` | 321,220 | 263,740 | +21.79% | 176 | 1 | 175 | 256 | 65,792 | 66,520 | 83,472 | lead 太短，prefetch hit 大幅下降。 |
| `cal256_rotate0` | `16x16,m8,f16,l64` | 313,012 | 263,740 | +18.68% | 73 | 5 | 68 | 257 | 67,072 | 62,416 | 84,351 | 加长 lead 仍不如默认。 |
| `cal256_rotate45` | `8x8,m8,f32,l64` | 515,978 | 515,978 | 0.00% | 2341 | 723 | 1618 | 1768 | 181,632 | 163,899 | 243,427 | 默认对照。 |
| `cal256_rotate45` | `16x8,m4,f16,l64` | 304,968 | 515,978 | -40.90% | 788 | 196 | 592 | 578 | 102,656 | 58,394 | 133,836 | 对角方向规律成功迁移。 |
| `cal256_rotate90` | `8x8,m8,f32,l64` | 274,434 | 274,434 | 0.00% | 1033 | 9 | 1024 | 1024 | 66,112 | 43,127 | 89,871 | 默认对照。 |
| `cal256_rotate90` | `16x16,m4,f16,l16` | 322,838 | 274,434 | +17.64% | 257 | 1 | 256 | 256 | 65,792 | 67,329 | 84,039 | lead/预取覆盖不足。 |
| `cal256_rotate90` | `16x16,m8,f16,l64` | 309,182 | 274,434 | +12.66% | 259 | 3 | 256 | 256 | 66,304 | 60,501 | 84,693 | 加长 lead 仍不如默认。 |

经验记录：
- `cal128` 的 `0/90 -> 16x16,LEAD16` 规律不能外推到更长帧；`cal256` 下 default `8x8,LEAD64` 的 prefetch hits 约 `1024`，而 `16x16` 只有约 `256`，sample stall 明显更高。
- `45` 度的 `16x8,LEAD64` 规律迁移成功，read bytes 从 `181,632` 降到 `102,656`，sample stall 从 `163,899` 降到 `58,394`，这是目前最稳的角度分桶证据。
- 下一轮不要继续扩大所有角度；优先补 `15/75` 的 `cal256`，确认小/大斜角是否更接近 `0/90` 还是更接近 `45`。
- 模型需要加入“帧长/lead 覆盖比例”特征；否则会继续把短帧 `cal128` 的短 lead 收益错误外推到较长帧。

### Round 2026-04-26-cal256-rotate15-75-check

- 目标：补齐 `cal256 rotate15/75`，判断小角度/大角度在中等帧长下更接近正交方向还是对角方向。
- RTL 改动：
  - `rtl/sim/tb_image_geo_top_perf_single_light.sv` 新增：
    - `tb_image_geo_top_perf_single_cal256_rotate15_on`
    - `tb_image_geo_top_perf_single_cal256_rotate75_on`
- 运行策略：
  - 默认对照：`8x8,MERGE8,FIFO32,LEAD64`。
  - 候选 1：`16x16,MERGE8,FIFO16,LEAD64`，来自 `cal128 rotate15/75` 的较优方向。
  - 候选 2：`16x8,MERGE4,FIFO16,LEAD64`，验证是否向 `45` 度对角规律靠拢。
- 输出：
  - `sim_out/model_rtl_calibration/rtl_cal256_points_ext.csv`
  - `sim_out/model_rtl_calibration/rtl_cal256_summary.csv`
  - 对应日志在 `sim_out/cache_perf/cal256_default_rotate15_on`、`cal256_default_rotate75_on`、`cal256_bucket_rotate15_*`、`cal256_bucket_rotate75_*`。
- 所有新增 RTL case 均 pass，每个 case 约 20-23 秒完成，无 timeout。

结果：

| Workload | Params | RTL cycles | Default cycles | Delta | Reads | Misses | Prefetches | Hits | Read bytes | Sample stall | Read busy | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `cal256_rotate15` | `8x8,m8,f32,l64` | 320,082 | 320,082 | 0.00% | 1289 | 370 | 919 | 1329 | 112,256 | 65,951 | 149,343 | 默认最好。 |
| `cal256_rotate15` | `16x16,m8,f16,l64` | 324,610 | 320,082 | +1.41% | 416 | 79 | 337 | 366 | 119,296 | 68,215 | 152,032 | reads/miss 降低但 stall/read_busy 稍升。 |
| `cal256_rotate15` | `16x8,m4,f16,l64` | 334,296 | 320,082 | +4.44% | 831 | 192 | 639 | 755 | 123,776 | 73,058 | 160,537 | 不适合。 |
| `cal256_rotate75` | `8x8,m8,f32,l64` | 312,852 | 312,852 | 0.00% | 1556 | 426 | 1130 | 1050 | 101,568 | 62,336 | 137,852 | 默认对照。 |
| `cal256_rotate75` | `16x16,m8,f16,l64` | 306,052 | 312,852 | -2.17% | 389 | 95 | 294 | 287 | 100,352 | 58,936 | 128,163 | 小幅收益。 |
| `cal256_rotate75` | `16x8,m4,f16,l64` | 295,482 | 312,852 | -5.55% | 739 | 179 | 560 | 508 | 95,104 | 53,651 | 124,053 | 当前最好，略向对角规律靠拢。 |

经验记录：
- `15` 度在 `cal256` 下不能照搬 `cal128` 的 `16x16` 收益；默认 `8x8,LEAD64` 更稳，说明小角度中等帧仍依赖较密的 micro-tile prefetch 覆盖。
- `75` 度开始受益于 `16x8,LEAD64`，但收益只有 `5.55%`，远小于 `45` 度的 `40.90%`；角度分桶不能简单二分为正交/对角。
- 当前中等帧角度分桶更合理的表达是：
  - `0/15/90`：默认 `8x8,LEAD64` 安全。
  - `45`：`16x8,LEAD64` 强收益。
  - `75`：`16x8,LEAD64` 小收益，可作为候选。
- 下一轮应把 `cal256` 结果加入 fast-model 重新拟合，因为当前线性校准只覆盖到 `cal128`，已经暴露了帧长/lead 覆盖比例缺项。

### Round 2026-04-26-rich-model-with-cal256-and-proxy-sanity

- 目标：把 `cal256` 数据纳入模型校准，重新判断 fast model 是否可以继续外推到更接近真实的 `1024x1024 -> 256x256` proxy workload。
- 脚本改动：
  - `scripts/fit_model_calibration.py` 和 `scripts/compare_model_rtl.py` 支持带参数的匹配键：`workload_id + prefetch_mode + tile_w/tile_h/merge/fifo/lead`。这样同一个 workload 下的多个参数组合不会互相错配。
  - `scripts/fit_model_calibration.py` 新增 `--feature-set {legacy,tilelead,rich}`。
  - `scripts/run_cache_sweep.py` 新增 `--calibration-json`，可直接读取 `fit_model_calibration.py` 输出的 rich feature 系数。
- 校准输入：
  - `sim_out/model_rtl_calibration/rtl_calibration_param_points.csv`：合并 `small/cal128`、`cal128 shortlist`、`cal256` 共 26 个带参数 RTL 点。
  - `sim_out/model_rtl_calibration/calibration_workloads_with_cal256.csv`。
  - `sim_out/model_rtl_calibration/calibration_model_with_cal256_grid.csv`。
- rich 校准输出：
  - `sim_out/model_rtl_calibration/rich_calibration_params_with_cal256.json`
  - `sim_out/model_rtl_calibration/rich_calibration_fit_with_cal256.md`
  - `sim_out/model_rtl_calibration/model_rtl_error_summary_rich_with_cal256.md`

校准结果：

| 数据集 | 行数 | 最大绝对误差 | 状态 | 结论 |
| --- | ---: | ---: | --- | --- |
| `small/cal128/cal256` 参数化 RTL 点 | 26 | `6.61%` | `Trusted for RTL shortlist expansion: yes` | 在当前轻量/中等校准域内通过 10% 门槛。 |

- 注意：`rich` 特征很多，且有负系数，仍是经验回归，不是物理模型。它只能说明“在已覆盖校准域内可用于 shortlist 粗筛”。

Proxy sanity：

| Workload | Params | Model cycles | RTL cycles | Error | Default cycles | Delta vs default | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `proxy_rotate45` | `8x8,m8,f32,l64` | 3,950,146 | 5,999,702 | -34.16% | 5,999,702 | 0.00% | 模型低估默认。 |
| `proxy_rotate45` | `16x8,m4,f16,l64` | 2,391,261 | 5,916,118 | -59.58% | 5,999,702 | -1.39% | 模型严重高估收益，RTL 只有小幅提升。 |

经验记录：
- `cal256` 加入后，模型在校准域内可压到 `6.61%`，但一外推到 `1024->256` 就失败，最大误差 `59.58%`。因此不能继续扩大 proxy/full RTL sweep。
- `proxy` full fast-model 单次小网格也接近 2 分钟并触发工具层 timeout，虽然 CSV 写完整了；后续 proxy 只能用 scan 模式或极窄参数集，不要再用 full 模式做大网格。
- `16x8,LEAD64` 对角方向收益随尺寸增大显著下降：`cal256 rotate45 -40.90%`，到 `proxy_rotate45` 只剩 `-1.39%`。这说明还缺少更大帧下 DDR/write/core 固定节拍或 cache 污染项。
- 下一步不要跑更多 proxy 角度；先改模型，加入尺寸/输出像素规模下的非线性项或分段模型，再用少量 proxy 点验证。

## 新增迭代模板

每次新优化前复制此模板。

```markdown
### Round YYYY-MM-DD-short-name

- 目标：
- RTL / 参数改动：
- 命令：
- 输出目录：
- timeout 策略：
- 用例：

| Case | Params | Cycles | Reads | Misses | Prefetches | Hits | Analytic | FIFO / merge stats | 状态 | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| | | | | | | | | | planned | |

经验记录：
- 
```

### Round 2026-04-26-stage1-5-runtime-stats-model-proxy512

- 目标：完成“源码/约束收口 + 中小矩阵校准 + shortlist”的 Stage 3-5，不启动完整大规模 RTL workload matrix。
- RTL / 脚本改动：
  - `cache_stats_cdc.sv` 已从大 bundled payload CDC 改为 32-bit word snapshot FIFO 方式，接口保持不变。
  - `frame_config_cdc.sv`、`image_geo_top.sv`、`src_tile_cache.sv` 已接入 runtime scheduler knobs：lead、merge max/min、FIFO effective depth、age limit、throttle cycles、policy。默认 policy=0 时保持原调度行为。
  - `src_tile_cache.sv` 增加 row-bucket 机会观测统计：`fifo_head_run_len`、`fifo_same_row_adjacent_count`、`fifo_reverse_x_adjacent_count`、`merge_opportunity_missed_count`，本轮只观测，不改 merge 行为。
  - `tb_image_geo_top_perf_single_light.sv` 新增 `proxy512_rotate0/15/45/75/90_on`，用于中间尺度 RTL 校准。
  - `scripts/run_cache_sweep.py` 修复 `read_busy_cycles` 未累计导致 `stall_per_read_busy` 特征不可用的问题，并把 rich calibration 所需特征补齐。
  - `scripts/extract_perf_single.py` 增加 scheduler/merge-observation 扩展统计字段。
- 关键输出：
  - `sim_out/model_rtl_calibration/model_fit_stage3_rich_refit.json`
  - `sim_out/model_rtl_calibration/model_fit_stage3_rich_refit.md`
  - `sim_out/model_rtl_calibration/model_rtl_error_summary_stage3_rich_refit.md`
  - `sim_out/model_rtl_calibration/stage4_proxy512_rtl_points.csv`
  - `reports/report_cdc.rpt`
  - `reports/report_timing_summary.rpt`

结果：

| 项目 | 结果 | 结论 |
| --- | --- | --- |
| `cache_stats_cdc` 单测 | pass | snapshot FIFO 方案可继续作为 stats CDC 基线。 |
| runtime knobs small smoke | default 与非默认 runtime 配置均 pass | AXI-Lite 可调路径已生效，默认保持旧行为。 |
| rich model refit | 26 行，最大误差 `2.14%` | 仅在 `small/cal128/cal256` 校准域内可用于 shortlist 粗筛。 |
| small Vivado report | report 已生成 | 但 `report_cdc` 仍有 unsafe/unknown，`report_timing_summary` 仍有 setup violation，不能标记 proven。 |
| `proxy512_rotate45` default | `cycles=2,169,786`, `read_bytes=784,128`, `sample_stall=712,486`, `merge_opp_missed=59,006` | default 可作为中尺度对照，但 merge 机会大量错过。 |
| `proxy512_rotate45` `16x8,m4,f16,l64` | `cycles=1,449,828`, `read_bytes=529,920`, `sample_stall=352,507`, `merge_opp_missed=8,286` | 相比 default 约 `-33.18%` cycles，本轮最有价值的中尺度证据。 |
| `cal256_rotate45` default post-runtime | `cycles=516,004` | 与旧基线 `515,978` 基本一致，runtime/stats 接入没有造成明显回退。 |

经验记录：
- 不要用缺字段的旧模型 CSV 做 rich fit。旧 `calibration_model_with_cal256_grid.csv` 里 `read_busy_cycles` 为空，会把 `stall_per_read_busy` 训练成伪特征；必须先用修复后的 `run_cache_sweep.py` 重新生成 raw CSV，再 fit。
- `fit_model_calibration.py` 的 10% 通过只代表校准域可信；proxy512 仍要用 RTL 校准，不能直接拿 fast-model top1 当结论。
- Vivado 2019.2 的 `xsim --testplusarg key=value` 在当前环境会报参数错误；runtime smoke 改为由 perf TB 通过 AXI-Lite 写寄存器，脚本用 TB-only define 传入写寄存器的值。
- 不要并行启动多个共享 `xil_defaultlib` 的 `xvlog/xelab/xsim`，否则会污染 snapshot 和日志，产生假的性能结论。
- stats snapshot 现在需要跨 CDC 串行搬运；testbench 在 IRQ/done 后必须等待 `stats_snapshot_id` 更新，再读扩展统计。
- `report_cdc.rpt` 生成不等于 CDC 通过。本轮还有 unsafe/unknown，下一轮要优先分类或继续收敛 CDC/约束。

### Round 2026-04-26-cdc-fifo-conversion

- 目标：继续收口 Stage 1 的 CDC/report gate，减少 `report_cdc` 中由 bundled-data toggle CDC 带来的 unsafe/unknown。
- RTL / 脚本改动：
  - `cache_stats_cdc.sv` 改为复用 `async_word_fifo`，综合时走 XPM async FIFO，不再使用手写灰码 FIFO。
  - `frame_config_cdc.sv` 改为 `async_word_fifo` 传输完整配置 payload，并在 core 域增加 skid register，保证 `cfg_valid_dst` 持有稳定 payload 直到 `cfg_ready_dst`。
  - `task_cdc.sv`、`task_cdc_2d.sv` 改为 `async_word_fifo` 传输任务 payload；`task_ready_src` 保持 one-deep 等价语义，避免 source 在目的端接收前过早 ready。
  - `result_cdc.sv` 改为 `async_word_fifo` 传输 done/error 小 payload。
  - `tools/run-module-sim.ps1` 给相关 CDC 单测补入 `async_word_fifo.sv` source。
  - `tools/image_geo_reports.tcl` 增加 `report_cdc -details`，输出 `reports/report_cdc_details.rpt`。
  - 新增 `reports/cdc_classification.md`，记录 CDC 分类和剩余风险。
- 验证命令：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 cache_stats_cdc -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 90`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 task_cdc -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 60`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 result_cdc -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 60`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_read_engine -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_write_engine -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`

结果：

| 项目 | 结果 | 结论 |
| --- | --- | --- |
| CDC 单测 / ddr / top smoke | 均 pass | FIFO 化没有破坏基本功能。 |
| `report_cdc` core->axi | endpoints `146`, safe `113`, unsafe `0`, unknown `33` | bundled-data unsafe 已消除；剩余主要是 XPM FIFO reset/control unknown。 |
| `report_cdc` axi->core | endpoints `146`, safe `106`, unsafe `0`, unknown `40` | bundled-data unsafe 已消除；剩余主要是 XPM FIFO reset/control unknown。 |
| input port -> axi | unsafe `36`, unknown `31` | OOC AXI input 端口缺 wrapper/input-delay 约束，不能算 clean。 |
| timing summary | AXI WNS `-1.082 ns`，core WNS `-17.052 ns` | small config report 可生成，但 timing 仍未过。 |

经验记录：
- 单纯把 `cache_stats_cdc` 从 bundled-data 改为手写 FIFO 还不够；Vivado CDC 对手写 RAM/灰码 FIFO 仍会报大量 unknown。综合侧要尽量使用 XPM async FIFO。
- 改 `task_cdc` 为 FIFO 时不能让 `task_ready_src` 过早拉高；`tb_task_cdc` 的 dst_stall case 正好抓到了这个语义回退。
- `frame_config_cdc` 不能直接把 FIFO head 组合接给 top；在 FIFO pop 同拍会造成仿真竞争。必须在 core 域加 skid register，再对外提供稳定的 `cfg_valid_dst/payload`。
- 当前 CDC 已经从结构性 bundled-data 风险转为 XPM reset/OOC input 约束分类问题；下一轮不要再靠肉眼猜，要针对 `reports/cdc_classification.md` 逐项 waiver 或改 reset 策略。
- timing 仍未证明，不能把任何参数配置写成 resource/timing proven。

## 2026-04-26 replacement pipeline timing gate

本轮目标：不要继续靠统计后一拍这类边角小修碰 timing，而是把 `src_tile_cache` 的 replacement/choose_way 单拍组合路径拆成多周期流水。经验结论必须记住：之前最坏路径是 `fifo_tile_x_reg[0][0] -> fill_req_set_reg[0][0]/CE`，不能再让 FIFO/head/sample 直接组合穿过 `cache_lookup + coord_pending + protected_coord + choose_way + reservation` 打到 `fill_req_*`。

RTL / 工具改动：
- `rtl/buffer/src_tile_cache.sv`
  - 新增 `REPL_IDLE/PRECHECK/INVALID/PREFETCH/OLDEST/COMMIT` replacement pipeline。
  - Stage A 只捕获 candidate：real miss、analytic FIFO、normal prefetch，优先级保持 `real miss > analytic prefetch > normal prefetch`。
  - Stage B 做 coord/cache/pending precheck；Stage C 扫 invalid way；Stage D 扫 used-prefetch victim；Stage E 扫 oldest/LRU victim；Stage F 做同 request reservation 和提交。
  - speculative analytic/normal candidate 在新 real miss 出现时丢弃；real miss pending 保留到命中、pending 或成功提交 demand fill。
  - `busy` 加入 replacement pipeline active。
  - analytic planner 的 duplicate/enqueue 评估寄存一拍，避免 `coord_in_fifo/cache_lookup` 直接控制 planner phase。
- `tools/run-vivado-reports.ps1`
  - 新增 `-SmallTimingSafe` profile。
- `tools/image_geo_reports.tcl`
  - 支持 `small_timing_safe` 参数，生成 `8x8,SET32,WAY2,MERGE4,FIFO16,LEAD16` 的 timing-safe 对照配置。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass，覆盖 `read_error/write_error/random_backpressure/reset_during_busy`。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallTimingSafe -TimeoutSec 600`：timeout，脚本已杀掉 Vivado，不可作为 timing 结论。

Timing 结果：
| 配置 | 旧 WNS | 新 WNS | 最坏路径 | 结论 |
| --- | ---: | ---: | --- | --- |
| `SmallConfig` core | `-8.354 ns` | `-2.953 ns` | `cfg_src_x_max_q16_reg[17] -> planner_eval_blocked_reg/D` | replacement 最坏路径已移除，core WNS 明显收敛，但仍未过 timing。 |
| `SmallConfig` AXI | `-0.768 ns` | `-0.768 ns` | `u_ddr_read_engine/row_index_reg[4] -> reader_task_addr_reg[0]/CE` | AXI 侧未改，仍需后续 skid/register slice 或 read task 地址路径拆分。 |
| `SmallTimingSafe` | source unavailable | timeout at 600s | 未生成 timing summary | 该 profile 当前不能作为 gate；后续要拆 OOC `src_tile_cache` 或进一步降低 profile。 |

功能观察：
- top smoke 中 `identity_32_to_16_prefetch_on` 仍有 prefetch fills，说明保留的一拍 planner eval 没有把小图 prefetch 覆盖打成 0。
- 尝试过额外的 planner tile-capture 二级流水，但会导致 `identity_32_to_16_prefetch_on` 报 “prefetch-on run reported zero prefetch fills”，已回退。经验：不能为了 timing 盲目增加 planner 延迟，必须同步检查 prefetch 覆盖。

下一步：
1. 若继续追 timing，优先拆 `planner_eval_blocked` 这条 candidate duplicate/block 路径，但必须保留小图 prefetch fills。
2. AXI WNS 仍为 `-0.768 ns`，等 core 接近过约后再单独加 AXI read task/skid register，不和 replacement 混改。
3. `SmallTimingSafe` 不能再裸等；下次改为 `src_tile_cache` OOC synth 或更小 profile，保持 bounded timeout。
4. 在 timing gate 过之前，不跑完整 workload matrix，不给最终参数推荐。

### 2026-04-26 planner enqueue decouple update

继续 timing 收口时，将 analytic planner 改为“candidate tile 捕获时立即推进 phase，duplicate/block/enqueue 后一拍独立处理”。这样 `cache_lookup/coord_in_fifo/coord_pending` 不再回打 planner phase/row advance 控制。

验证：
- `src_tile_cache`：pass。
- `src_tile_cache_prefetch`：pass。
- `image_geo_top`：pass。
- `SmallConfig` synth/report：report generated。

Timing 更新：
| 配置 | 上一版 WNS | 本版 WNS | 最坏路径 | 结论 |
| --- | ---: | ---: | --- | --- |
| `SmallConfig` core | `-2.953 ns` | `-1.510 ns` | `u_rotate_core_bilinear/sample_x0_reg[6] -> u_src_tile_cache/sample_miss_pending_tile_x_reg[0]/CE` | 已达到阶段目标 `-2 ns` 内，replacement/planner duplicate 路径不再是最坏路径。 |
| `SmallConfig` AXI | `-0.768 ns` | `-0.768 ns` | `u_ddr_read_engine/row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 未改变。 |

小样本功能/性能：
- `rotate45_20_prefetch_on`: `frame=4712 total=4163 reads=9 misses=2 prefetch=7 hits=7 stall=259`。
- `identity_32_to_16_prefetch_on`: `frame=5819 total=5261 reads=8 misses=3 prefetch=5 hits=5 stall=306`。
- 说明 planner 解耦后 prefetch 仍有效，没有复现 “prefetch fills = 0”。

尝试但回退：
- 尝试将 sample miss capture 再打一拍，结果 `SmallConfig` core WNS 从 `-1.510 ns` 退到 `-2.056 ns`，且最坏路径又转回 planner reset/advance；该改动已回退。

下一步：
1. 若继续追 core timing，优先处理当前 sample hit/miss 到 `sample_miss_pending_*` 的路径，可能需要更系统地重构 sample request accept/lookup pipeline，而不是简单打一拍。
2. 之后单独处理 AXI `ddr_read_engine` read task 地址路径。
3. 在 timing 正式过约束前，继续禁止完整大矩阵 RTL sweep。
### 2026-04-26 sample miss / stats timing 收敛

目标：继续收敛 `src_tile_cache` core timing，但不启动大规模 RTL workload matrix。只做小源码修改、cache/top smoke、SmallConfig synth/report。

RTL 改动：
- `rtl/buffer/src_tile_cache.sv`
  - demand fill 对 analytic FIFO 的按坐标删除从 `fill_request` 组合提交路径中解耦，改为 `fifo_delete_req_*` 小寄存请求，再由 FIFO update 阶段处理。语义仍是按 tile 坐标删除匹配项，但不让 demand fill 同拍控制 FIFO compact。
  - sample miss 捕获改为先锁存四个 sample tile 坐标，再用寄存后的 tile 做 miss/pending 判断；这样 `rotate_core_bilinear sample_x/y` 不再直接打到 `sample_miss_pending_tile_*` 的 CE。
  - planner candidate valid 去掉冗余 `coord_valid(planner_candidate_tile)` gating。planner 坐标已经 clamp 到 `src_x/y_max`，在非零尺寸下 candidate tile 必然有效；删除该 gating 后，`cfg_src_x_max_q16 -> planner_advance_phase` 长比较链被切断。
  - `stat_useful_source_sectors` 改为 pending count 下一拍累计，避免 sample hit/duplicate sector 统计路径直接打到 32-bit stat adder。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。

Timing 更新：
| 配置 | 上一稳定版 WNS | 本轮稳定版 WNS | 最坏路径 | 结论 |
| --- | ---: | ---: | --- | --- |
| `SmallConfig` core | `-1.510 ns` | `-1.479 ns` | `sector_tag_x_reg[22][1] -> repl_evict_unused_reg[0]/D` | 小幅改善；当前最坏点已是 replacement 统计/evict-unused 路径，不是 fill request 主控制。 |
| `SmallConfig` AXI | `-0.768 ns` | `-0.768 ns` | `u_ddr_read_engine/row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 未改变，后续需要单独拆 read task 地址路径。 |

尝试但回退 / 排除：
- 去掉 sample miss capture 的 `coord_pending` 防重复条件后，core WNS 从 `-1.510 ns` 退到 `-1.981 ns`，最坏路径转为 `sample_y0 -> fifo_delete_pending_tile_x_reg/CE`；该思路不可取，必须保留 pending 防重复，并把 FIFO delete 解耦。
- 把 sample miss probe 再拆成 eval 额外一拍后，Vivado 放置把 FIFO compact 路径重新推成最坏，core WNS 退到 `-8.756 ns`；该改动已回退。经验：并不是所有“多打一拍”都会改善 timing，必须每次用 report 验证。
- 将 evict-unused 统计完全移到 fill 启动阶段后，最坏路径转为 sample miss probe，core WNS 约 `-1.986 ns`，比当前稳定版差；该改动已回退。经验：统计迁移也会改变放置和暴露次坏路径，不能只看逻辑层数。
- 尝试把 `ddr_read_engine` 下一行读地址从 `row_base + row_index * stride` 改成递推 `row_next_addr += stride`，功能 smoke 通过，但 SmallConfig timing 退化：AXI WNS `-0.768 ns -> -1.133 ns`，core WNS 也被放置扰动到约 `-2.181 ns`；该改动已回退。经验：AXI 侧需要单独做 reader/register-slice 级别的结构优化，不要用看似更简单的地址递推替代报告验证。

经验记录：
- 当前有效组合是：replacement 多周期化 + planner enqueue 解耦 + sample miss tile probe + useful-sector 统计后一拍。
- 不要再尝试“盲目增加 probe/eval 拍数”来修 sample miss；如果继续做，需要整体重构 sample request lookup/accept pipeline，并同步检查 prefetch-on 小图覆盖。
- 当前 core 已稳定在 `-2 ns` 内，但还未过 timing；下一步可选方向是更彻底拆 `repl_evict_unused` 统计路径，或先单独处理 AXI `ddr_read_engine` read task 地址路径。

### 2026-04-26 repl_evict_unused / ddr row prep 定向尝试

目标：只处理两条最新 SmallConfig 最坏路径，不启动 workload matrix，不调整解析式 planner、lead/fifo/merge 默认行为。

尝试内容：
- `src_tile_cache.sv`：按计划尝试新增 `REPL_EVICT_FLAG` 状态，让 `REPL_OLDEST` 只选择 victim，不再同拍计算 `repl_evict_unused_reg`；新增状态只根据已寄存的 `repl_set_reg/repl_victim_way_reg` 和 sector 属性计算 evict-unused。
- `ddr_read_engine.sv`：按计划尝试新增 `R_PREP_NEXT` 状态，在一行读完成后先寄存 `row_next_index_reg`，下一拍再写 `reader_task_addr_reg/reader_task_valid_reg`。

功能验证：
- `src_tile_cache`：pass。
- `src_tile_cache_prefetch`：pass。
- `ddr_read_engine`：pass。
- `image_geo_top`：pass。
- `SmallConfig` synth/report：两次均能生成报告，分别用于尝试版和回退后稳定版。

Timing 结果：
| 配置 | core WNS | core 最坏路径 | AXI WNS | AXI 最坏路径 | 结论 |
| --- | ---: | --- | ---: | --- | --- |
| 尝试前稳定版 | `-1.479 ns` | `sector_tag_x_reg[22][1] -> repl_evict_unused_reg[0]/D` | `-0.768 ns` | `row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 当前可信基线。 |
| `REPL_EVICT_FLAG` + `R_PREP_NEXT` 尝试版 | `-8.682 ns` | `fifo_delete_pending_tile_x_reg[4] -> fifo_tile_x_reg[0][0]/CE` | `-1.350 ns` | `row_index_reg[4] -> reader_task_addr_reg1/CEB2` | 功能通过但 timing 大幅退化，已回退。 |
| 回退后稳定版 | `-1.479 ns` | `sector_tag_x_reg[22][1] -> repl_evict_unused_reg[0]/D` | `-0.768 ns` | `row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 已恢复可信基线。 |

经验记录：
- `REPL_EVICT_FLAG` 本身切掉了 `sector_tag_x/y -> repl_evict_unused_reg` 的直达路径，但引入的状态/控制扰动使 FIFO delete/compact CE 重新成为最坏路径，core WNS 退到 `-8.682 ns`。不要在没有先重构 FIFO compact/删除路径之前重复该方案。
- 单状态 `R_PREP_NEXT` 没有解决 AXI 地址路径，反而让路径落到 DSP48 enable，AXI WNS 从 `-0.768 ns` 退到 `-1.350 ns`。后续若继续处理 AXI，应考虑真正拆成 `R_PREP_NEXT_MUL/R_PREP_NEXT_COMMIT` 或在 reader/task 边界加寄存/切片，而不是重复这一拍 prep。
- 本轮两个修改都按功能 smoke 通过，但 synth timing 证明为负收益；代码已回退。结论必须以回退后的 `-1.479 ns / -0.768 ns` 稳定版为准。

### 2026-04-26 REPL_PROTECT + FIFO compact timing 收敛

目标：继续专门收敛 SmallConfig timing，不跑 workload matrix，不调整解析式 planner、lead/fifo/merge 默认策略。

RTL 改动：
- `rtl/buffer/src_tile_cache.sv`
  - 在 replacement pipeline 中新增 `REPL_PROTECT` 状态，先寄存每个 lane/way 的 protected mask。
  - `REPL_PREFETCH/REPL_OLDEST` 不再直接调用 `protected_coord(sector_tag_x/y)`，只读取 `repl_protected_mask_reg`。
  - analytic FIFO update 从“整队列同拍 compact”改成多周期逐项 compact：每拍最多搬移一个 FIFO entry，最后再可选追加 enqueue entry。
  - 保留 `real miss > analytic prefetch > normal prefetch`、fill immediate invalidate、read_error 清理、merge reservation。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_read_engine -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。

Timing 结果：
| 配置 | core WNS | core 最坏路径 | AXI WNS | AXI 最坏路径 | 结论 |
| --- | ---: | --- | ---: | --- | --- |
| 上一稳定版 | `-1.479 ns` | `sector_tag_x_reg[22][1] -> repl_evict_unused_reg[0]/D` | `-0.768 ns` | `row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 本轮起点。 |
| 只加 `REPL_PROTECT`，未拆 FIFO compact | `-8.112 ns` | `fifo_delete_pending_tile_y_reg[5] -> fifo_tile_x_reg[0][0]/CE` | `-0.768 ns` | 同上 | protected mask 有效切掉 evict path，但整队列 compact 重新成为最坏路径。 |
| `REPL_PROTECT` + 多周期 FIFO compact | `-1.263 ns` | `sample_miss_probe_tile_y_reg[0][0] -> sample_miss_pending_tile_x_reg[0]/CE` | `-0.768 ns` | `row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 有效改善；replacement/evict/FIFO compact 均退出最坏路径。 |

尝试但回退：
- `ddr_read_engine.sv` 尝试 `R_PREP_NEXT_MUL/R_PREP_NEXT_COMMIT` 两阶段拆分，功能 smoke 通过，但 AXI WNS 从 `-0.768 ns` 退到 `-1.350 ns`，最坏路径变为 `row_index_reg[4] -> row_next_addr_calc_reg1/CEB2`。该改动已回退。

经验记录：
- 只加 replacement mask 不够，必须同时避免 FIFO compact 的整队列组合搬移；否则任何 replacement 拆拍都会把 FIFO compact CE 顶成最坏路径。
- 多周期 FIFO compact 是本轮有效改动，但会让 analytic FIFO pop/delete/enqueue 多耗若干拍；后续性能 A/B 前要用小样本确认 prefetch 覆盖没有明显下降。
- AXI 行地址路径不能靠在同一模块里增加乘法中间寄存器解决，Vivado 仍会把 DSP enable 推成最坏。后续 AXI 优化应优先考虑 reader task 边界 register slice 或改写 result/issue 控制 CE，而不是继续增加乘法 prep 状态。
- 当前可信 SmallConfig timing：core `-1.263 ns`，AXI `-0.768 ns`。timing 仍未过，继续禁止完整 workload matrix 和最终参数推荐。

### 2026-04-26 sample eval / AXI CE 小步收敛

目标：继续只收敛 SmallConfig timing，不跑 workload matrix，不修改 planner 策略和 runtime scheduler 默认行为。

RTL 改动：
- `rtl/buffer/src_tile_cache.sv`
  - sample miss probe 增加 `sample_miss_eval_*` 结果寄存级。probe 阶段只找出第一个未命中的 tile，下一拍再用寄存后的 tile 做 `coord_pending` 和 demand miss pending 提交。
  - 这次不是盲目增加 sample capture 拍，而是把 cache/tag lookup 结果与 pending 提交拆开；保留 miss fallback 和 real miss 优先级。
- `rtl/axi/ddr_read_engine.sv`
  - 行读成功时统一预计算下一行 `reader_task_addr_reg/reader_task_byte_count_reg`，即使当前是最后一行也写入无害的下一行地址，从而让这些寄存器的 CE 不再依赖 last-row 比较。
  - 行读成功时统一递增 `row_index_reg`；最后一行之后该值不会再被使用，功能 smoke 已覆盖。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_read_engine -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。

Timing 结果：
| 配置 | overall WNS | core WNS / worst path | AXI WNS / worst path | 结论 |
| --- | ---: | --- | --- | --- |
| 上一稳定版 | `-1.263 ns` | `-1.263 ns`, `sample_miss_probe_tile_y_reg[0][0] -> sample_miss_pending_tile_x_reg[0]/CE` | `-0.768 ns`, `row_index_reg[4] -> reader_task_addr_reg[0]/CE` | 起点。 |
| sample miss eval 后 | `-0.768 ns` | `-0.039 ns`, `sample_x0_reg[3] -> repl_is_analytic_reg/CE` | `-0.768 ns`, `row_index_reg[4] -> reader_task_addr_reg[0]/CE` | core 基本收口，overall 转为 AXI 限制。 |
| DDR 行地址/行号 CE 简化后 | `-0.647 ns` | `-0.039 ns`, 同上 | `-0.647 ns`, `issue_commit_valid_reg -> FSM state_reg[1]/D` | 本轮最终保留版本。 |

尝试但回退：
- `axi_burst_reader.sv` 尝试让 FSM DONE/DRAIN 判断只看寄存后的 `beats_inflight_reg`，避免 `issue_commit_valid -> beats_inflight_next -> state` 同拍路径。功能 smoke 通过，但 AXI WNS 从 `-0.647 ns` 退到 `-0.845 ns`，最坏路径转为 `reader_task_byte_count_reg[3] -> request_remaining_nonzero_reg/D`。该改动已回退。

经验记录：
- sample miss eval 拆分这次有效，说明当前 core 侧关键是把 cache lookup 结果和 demand pending 提交拆开，而不是继续改 planner 或 FIFO。
- core WNS 已到 `-0.039 ns`，下一轮不宜再大动 cache 调度；更合理的是先处理 AXI `axi_burst_reader` 的 commit/outstanding/state 路径。
- `axi_burst_reader` 的 state 判断不能简单从 `beats_inflight_next` 改到 `beats_inflight_reg`；这会暴露 task byte count 到 request remaining 的更坏路径。后续若继续处理 AXI，需要把 request size/remaining 计算预寄存或拆 issue commit 更新路径，而不是只替换状态判断条件。
- 当前可信 SmallConfig timing：overall `-0.647 ns`，core `-0.039 ns`，AXI `-0.647 ns`。仍未过 timing，继续禁止完整 workload matrix 和最终推荐表。
### 2026-04-26 AXI reader/writer timing 收敛

目标：继续专门收敛 SmallConfig timing，不跑 workload matrix，不调整解析式 planner 策略，不调整 lead/fifo/merge 默认行为。

保留的 RTL 改动：
- `rtl/axi/axi_burst_reader.sv`
  - task 接收时 `request_remaining_nonzero_reg` 不再由 `task_words_total_calc != 0` 直接驱动，改为基于 `ddr_read_engine` 已过滤非零行任务的假设置 1。
  - FSM DONE/DRAIN 判断继续使用寄存后的 `request_remaining_nonzero_reg`，避免宽 `words_request_remaining_reg == 0` 直接进入 state 判断。
- `rtl/axi/ddr_read_engine.sv`
  - 增加 `row_rows_remaining_reg` 和 `row_more_after_current_reg`，让下一行 `reader_task_valid_reg` 只依赖已寄存的 “当前行后是否还有行” 标志。
  - 保留之前有效的 reader row 地址/byte_count CE 简化；不重复 `R_PREP_NEXT`、`R_PREP_NEXT_MUL/COMMIT`、地址递推等已验证退化方案。
- `rtl/axi/axi_burst_writer.sv`
  - 去掉 `S_PREP_LIMIT/S_PREP` 内部对零长度任务的冗余防御分支；零长度任务由 `ddr_write_engine` 在 `task_start_accept` 前过滤。
  - 这样 `words_write_remaining_reg == 0` 不再控制 `aw_prep_addr_reg/aw_prep_len_reg` 的 CE。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_read_engine -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 ddr_write_engine -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。

Timing 结果：
| 阶段 | overall WNS | AXI WNS / worst path | core WNS / worst path | 结论 |
| --- | ---: | --- | --- | --- |
| 起点 | `-0.647 ns` | `-0.647 ns`, `issue_commit_valid_reg -> FSM state_reg[1]/D` | `-0.039 ns`, `sample_x0_reg -> repl_is_analytic_reg/CE` | AXI 限制 overall。 |
| reader nonzero 改动后 | `-0.529 ns` | `-0.529 ns`, `row_index_reg[4] -> reader_task_valid_reg/D` | `-0.039 ns`, 同上 | 切掉 `task_byte_count -> request_remaining_nonzero` 后，AXI 最坏点转移到行任务 valid。 |
| row_more_after_current 后 | `-0.175 ns` | `-0.175 ns`, `words_write_remaining_reg[17] -> aw_prep_addr_reg[10]/CE` | `-0.039 ns`, 同上 | 读侧行任务 valid 路径基本收口，AXI 最坏点转移到写侧 AW prep。 |
| writer 零长度冗余分支删除后 | `-0.039 ns` | `+0.051 ns`, `next_issue_words_to_4kb_reg[1] -> next_issue_words_to_4kb_reg[11]/R` | `-0.039 ns`, `sample_x0_reg[3] -> repl_is_analytic_reg/CE` | AXI 域已转正，overall 只剩 core 侧 39ps。 |

尝试但回退：
- 尝试把 cache speculative prefetch 的 miss 阻断改成 `sample_miss_probe/eval/pending` 寄存信号，切掉 `sample_x0 -> sample_miss_present -> repl_capture` 的组合路径。
- `src_tile_cache` 和 `src_tile_cache_prefetch` 单测通过，但 top smoke 在 `identity_32_to_16_prefetch_on` 失败：`prefetch-on run reported zero prefetch fills`。
- 已回退。经验：不能用“延后阻断 speculative prefetch”来换 core timing；这会把小图 prefetch 覆盖打成 0。若继续处理 core `-0.039 ns`，必须重构 sample lookup / replacement capture 边界，同时保持 prefetch-on 小图覆盖。

当前可信结论：
- SmallConfig AXI timing 已过：`image_geo_axi_clk WNS = +0.051 ns`。
- SmallConfig core timing 接近过约束但仍未完全通过：`image_geo_core_clk WNS = -0.039 ns`。
- 继续禁止完整 workload matrix；下一步若继续收敛，应只处理 core 侧 `sample_x0 -> repl_is_analytic_reg/CE`，并且每次都先跑 `identity_32_to_16_prefetch_on` 类小图 prefetch 覆盖检查。
### 2026-04-26 replacement capture CE 最小切分，SmallConfig timing 过约束

目标：在上一轮 AXI 已转正、core 只剩 `-0.039 ns` 的基础上，继续只处理当前 core 最坏路径，不跑 workload matrix，不修改 analytic planner 策略，不调整 lead/fifo/merge 默认行为。

RTL 改动：
- `rtl/buffer/src_tile_cache.sv`
  - 在 `REPL_IDLE` 中让 `repl_is_prefetch_reg` / `repl_is_analytic_reg` 每拍刷新为当前 `repl_capture_*` 类型标志。
  - `repl_capture_present` 仍然只控制是否锁存 tile/run/set 并进入 `REPL_PRECHECK`。
  - 这样切掉了 `sample_x -> cache_lookup -> repl_capture_present -> repl_is_analytic_reg/CE` 的长 CE 路径，但没有改变 fill 调度优先级。
  - 保持 `real miss > analytic prefetch > normal prefetch`，保持 fill immediate invalidate、read_error 清理、merge reservation、prefetch_enable=0 fallback。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。

Timing 结果：
| 阶段 | overall WNS | AXI WNS / worst path | core WNS / worst path | 结论 |
| --- | ---: | --- | --- | --- |
| 上一轮可信结果 | `-0.039 ns` | `+0.051 ns`, `next_issue_words_to_4kb_reg[1] -> next_issue_words_to_4kb_reg[11]/R` | `-0.039 ns`, `sample_x0_reg[3] -> repl_is_analytic_reg/CE` | 只剩 core 侧 39ps。 |
| 本轮结果 | `+0.051 ns` | `+0.051 ns`, `next_issue_words_to_4kb_reg[1] -> next_issue_words_to_4kb_reg[11]/R` | `+0.184 ns`, `sample_x1_reg[6] -> sector_last_touch_reg[10][0]/CE` | SmallConfig setup timing 已过约束。 |

经验记录：
- 本轮有效点不是延后 miss 阻断，也不是改变 prefetch 调度，而是把 capture 类型寄存器的 CE 从长组合 `repl_capture_present` 链上拿掉。
- 之前尝试把 speculative prefetch 阻断改成寄存信号会导致 top 小图 `prefetch-on run reported zero prefetch fills`，仍然不要重复。
- 当前 SmallConfig timing gate 首次达到正 WNS。下一阶段可以开始小矩阵 scheduler A/B，但仍禁止直接跑完整 7200 workload matrix，也不能把 SmallConfig 资源 profile 当作最终性能推荐。
### 2026-04-26 scheduler runtime policy 小矩阵 A/B

前提：
- SmallConfig timing 已过约束：overall WNS `+0.051 ns`，AXI WNS `+0.051 ns`，core WNS `+0.184 ns`。
- 本轮不跑完整 workload matrix，不改 RTL 调度结构，不改解析式 planner 策略。
- 只使用已接入 RTL 的 runtime scheduler knobs 做小矩阵 A/B。

脚本/配置改动：
- `scripts/run_rtl_shortlist.py`
  - 支持 candidate CSV 中每行指定 `rtl_top`，避免多 workload 只能共用一个 top。
  - run name 加入 runtime policy、merge_min、age、throttle，避免不同策略覆盖同一日志目录。
- `configs/cache_scheduler_ab_small.csv`
  - 第一批 12 组：`cal128_r0`、`cal128_r45`、`cal256_r45`，每组 policy 0/1/2/3。
- `configs/cache_scheduler_ab_extend.csv`
  - 第二批 12 组：`cal128_r75`、`cal256_r75`、`proxy512_r45`，每组 policy 0/1/2/3。

固定结构参数：
- `BASE_TILE=8x8`
- `SET_NUM=32`
- `WAY_NUM=2`
- `MERGE_MAX_X=4`
- `ANALYTIC_FIFO_DEPTH=16`
- `ANALYTIC_LEAD_PIXELS=16`

Policy 含义：
- `0`: default
- `1`: merge_min_age (`MERGE_MIN_X=4`, `FIFO_AGE_LIMIT=200`)
- `2`: throttle_on_miss (`PREFETCH_THROTTLE_CYCLES=64`)
- `3`: merge_min_age + throttle_on_miss

验证命令：
- `python -m py_compile scripts\run_rtl_shortlist.py scripts\extract_perf_single.py scripts\run_cache_sweep.py`：pass。
- `python scripts\run_rtl_shortlist.py --input configs/cache_scheduler_ab_small.csv --out sim_out/cache_scheduler_ab/small_ab_results.csv --top-n 12 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 300`：12/12 pass。
- `python scripts\run_rtl_shortlist.py --input configs/cache_scheduler_ab_extend.csv --out sim_out/cache_scheduler_ab/extend_ab_results.csv --top-n 12 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 420`：12/12 pass。

汇总输出：
- `sim_out/cache_scheduler_ab/small_ab_results.csv`
- `sim_out/cache_scheduler_ab/extend_ab_results.csv`
- `sim_out/cache_scheduler_ab/combined_summary.csv`
- `sim_out/cache_scheduler_ab/summary.md`

结果摘要：
| Workload | 最优 policy | default cycles | best cycles | 改善 |
| --- | ---: | ---: | ---: | ---: |
| `cal128_r0` | 1 | 74394 | 74368 | -26 (-0.035%) |
| `cal128_r45` | 1 | 172086 | 171782 | -304 (-0.177%) |
| `cal128_r75` | 0 | 96392 | 96392 | 0 (0.000%) |
| `cal256_r45` | 0 | 744170 | 744170 | 0 (0.000%) |
| `cal256_r75` | 1 | 427312 | 425362 | -1950 (-0.456%) |
| `proxy512_r45` | 1 | 3193896 | 3191196 | -2700 (-0.085%) |

阶段结论：
- `merge_min_age` 在部分 workload 有小幅收益，但幅度很小，且会让部分 workload 退化；不能固化为默认。
- `throttle_on_miss` 在本轮 workload 中基本没有独立收益，policy 2 与 default 相同，policy 3 与 policy 1 相同；当前 `64` cycle throttle 不是明显瓶颈解法。
- `cal128_r75` 和 `cal256_r45` 的 default 最稳，继续支持“不同角度/规模需要不同策略”的判断。
- 本轮只是 timing gate 后的 RTL 小矩阵校准，不生成最终推荐表，不外推到 7200->600。

下一步建议：
- 继续补 `cal256_r0/r15/r90` 和 `proxy512_r0/r75/r90` 的 shortlist，但仍保持每轮 8-12 组、每组独立 timeout。
- 若要提升收益，下一类机制不应继续只改 throttle 数值，而应先用 merge opportunity 统计判断是否需要 row-bucket/direction-aware merge 的单独 A/B 分支。

### 2026-04-27 scheduler runtime policy 补充小矩阵

目标：
- 继续上一轮小矩阵 A/B，但仍不跑完整 7200 workload matrix。
- 补齐 `cal256_r0/r15/r90` 与 `proxy512_r0/r75/r90`，每批 12 组以内，所有仿真带 timeout。

新增配置：
- `configs/cache_scheduler_ab_cal256_more.csv`
- `configs/cache_scheduler_ab_proxy512_more.csv`

验证命令：
- `python scripts\run_rtl_shortlist.py --input configs/cache_scheduler_ab_cal256_more.csv --out sim_out/cache_scheduler_ab/cal256_more_results.csv --top-n 12 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 420`：12/12 pass。
- `python scripts\run_rtl_shortlist.py --input configs/cache_scheduler_ab_proxy512_more.csv --out sim_out/cache_scheduler_ab/proxy512_more_results.csv --top-n 12 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 600`：12/12 pass。

累计输出：
- `sim_out/cache_scheduler_ab/combined_summary_all.csv`
- `sim_out/cache_scheduler_ab/summary_all.md`

累计结果摘要：
| Workload | 最优 policy | default cycles | best cycles | 改善 |
| --- | ---: | ---: | ---: | ---: |
| `cal128_r0` | 1 | 74394 | 74368 | -26 (-0.035%) |
| `cal128_r45` | 1 | 172086 | 171782 | -304 (-0.177%) |
| `cal128_r75` | 0 | 96392 | 96392 | 0 (0.000%) |
| `cal256_r0` | 1 | 294830 | 294804 | -26 (-0.009%) |
| `cal256_r15` | 2 | 436036 | 436028 | -8 (-0.002%) |
| `cal256_r45` | 0 | 744170 | 744170 | 0 (0.000%) |
| `cal256_r75` | 1 | 427312 | 425362 | -1950 (-0.456%) |
| `cal256_r90` | 0 | 315298 | 315298 | 0 (0.000%) |
| `proxy512_r0` | 0 | 2101546 | 2101546 | 0 (0.000%) |
| `proxy512_r45` | 1 | 3193896 | 3191196 | -2700 (-0.085%) |
| `proxy512_r75` | 1 | 2509470 | 2509154 | -316 (-0.013%) |
| `proxy512_r90` | 0 | 2348166 | 2348166 | 0 (0.000%) |

阶段结论：
- 累计 48 组 RTL A/B 全部 pass，无 timeout。
- `merge_min_age` 的收益存在但很小，通常低于 0.5%；不能作为全局默认。
- `throttle_on_miss` 在当前 `PREFETCH_THROTTLE_CYCLES=64` 下几乎没有独立收益；继续扫 throttle 数值的优先级较低。
- 0/90 度更偏向 default，部分 45/75 度可由 `merge_min_age` 小幅受益，进一步证明 scheduler policy 需要按 workload 分类。
- 下一轮应优先使用已有 merge opportunity / same-row / reverse-x 统计判断是否值得开 direction-aware / row-bucket merge 分支，而不是继续盲调 policy。

### 2026-04-27 merge opportunity 统计提取修正与方向判断

背景：
- `PERF_SINGLE` 日志中已经输出 `analytic=candidates/duplicates/blocked/fills`，但 `scripts/run_rtl_shortlist.py` 之前没有解析这四个字段。
- 旧的 `merge_opportunity_analysis.md` 因此错误地退回用 `prefetches` 作为分母，导致 `same_row_ratio/missed_merge_ratio` 不可信。
- 本轮不重新跑 RTL，只修 extractor 并复用已通过的 48 组 scheduler A/B 日志。

脚本/数据改动：
- `scripts/run_rtl_shortlist.py`
  - `PROFILE_RE` 增加 `analytic_candidates`、`analytic_duplicates`、`analytic_blocked`、`analytic_fills` 解析。
  - 增加 `--parse-only`，可直接从既有 `xsim.log` 重建 CSV，避免重复启动仿真。
- 重新生成：
  - `sim_out/cache_scheduler_ab/small_ab_results_reparsed.csv`
  - `sim_out/cache_scheduler_ab/extend_ab_results_reparsed.csv`
  - `sim_out/cache_scheduler_ab/cal256_more_results_reparsed.csv`
  - `sim_out/cache_scheduler_ab/proxy512_more_results_reparsed.csv`
  - `sim_out/cache_scheduler_ab/merge_opportunity_analysis.csv`
  - `sim_out/cache_scheduler_ab/merge_opportunity_analysis.md`

验证：
- `python -m py_compile scripts\run_rtl_shortlist.py`：pass。
- 4 批 parse-only 均从既有日志得到 `parsed_pass`，没有启动新的 RTL 仿真。

关键观察：
| Workload | policy | same_row/cand | reverse_x/cand | missed/cand | avg_merge | merge1_ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `cal128_r45` default | 0 | 0.755 | 0.018 | 0.603 | 1.324 | 0.682 |
| `cal256_r45` default | 0 | 1.052 | 0.027 | 0.754 | 1.426 | 0.577 |
| `proxy512_r45` default | 0 | 1.227 | 0.035 | 0.830 | 1.488 | 0.516 |
| `proxy512_r75` default | 0 | 0.273 | 0.003 | 0.239 | 1.190 | 0.811 |
| `proxy512_r0` default | 0 | 0.076 | 0.001 | 0.002 | 2.972 | 0.002 |
| `proxy512_r90` default | 0 | 0.082 | 0.000 | 0.082 | 1.000 | 1.000 |

阶段结论：
- 45 度 workload 的同 row 相邻事件与 missed merge 事件密度明显较高，当前 FIFO-head +X merge 确实漏掉一部分可合并机会。
- `reverse_x/cand` 在当前样本里整体很低，不支持马上做完整 direction-aware merge 大改。
- 下一步若继续优化 scheduler，应只开一个小分支做“同 row bucket merge A/B”：同 `tile_y`、连续 `tile_x`、不跨 row、不乱序影响 real miss。
- 不要把本轮观察写成最终推荐；它只是说明 row-bucket 值得单独验证。

经验记录：
- 统计字段缺失时不能临时换分母继续下结论；先修 extractor，再重算 CSV。
- 新的分析脚本/报告必须保留 `analytic_candidates`，否则 `same_row/missed_merge` 的比例没有可比性。

### 2026-04-27 row-bucket merge v0 小样本 A/B

目标：
- 基于上一节的 merge opportunity 观察，新增一个默认关闭的同 row bucket merge 实验分支。
- 不改默认行为，不改解析式 planner，不跑大矩阵。

RTL/脚本改动：
- `rtl/buffer/src_tile_cache.sv`
  - 新增宏 `SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE`，默认 `0`。
  - 当宏为 `1` 且 analytic FIFO head 的 `+X` prefix 长度不超过 1 时，在同一 `tile_y` 内寻找 `head_x+1/head_x+2...`，形成连续 DDR read。
  - v0 只 pop FIFO head；被提前填好的后续 FIFO 项到队头后由 cache-hit precheck 清理。
  - 保持 `real miss > analytic prefetch > normal prefetch`，保持 fill immediate invalidate 和 read_error 清理。
- `tools/run-cache-perf-case.ps1`
  - 增加 `-EnableRowBucketMerge`，生成对应 define。
- `scripts/gen_param_header.py`
  - 增加 `--enable-row-bucket-merge`。
- `scripts/run_rtl_shortlist.py`
  - 支持 candidate CSV 字段 `enable_row_bucket_merge` / `row_bucket_merge`。
- `configs/cache_row_bucket_ab_smoke.csv`
  - 只包含 3 个 45 度 row-bucket smoke case。

验证：
- `python -m py_compile scripts\run_rtl_shortlist.py scripts\gen_param_header.py`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 src_tile_cache_prefetch -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cache-perf-case.ps1 ... -EnableRowBucketMerge 1 -CompileOnly`：pass。
- `python scripts\run_rtl_shortlist.py --input configs/cache_row_bucket_ab_smoke.csv --out sim_out/cache_scheduler_ab/row_bucket_smoke_results.csv --top-n 3 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 600`：3/3 pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated，默认关闭 row-bucket 时 timing 仍过约束。

Timing：
- overall WNS `+0.051 ns`
- AXI WNS `+0.051 ns`
- core WNS `+0.180 ns`
- 当前 core worst path：`u_rotate_core_bilinear/sample_x1_reg_reg[6] -> u_src_tile_cache/fifo_delete_pending_tile_x_reg_reg[0]/CE`

结果摘要：
| Workload | default cycles | row-bucket cycles | delta | 主要变化 |
| --- | ---: | ---: | ---: | --- |
| `cal128_r45` | 172086 | 172352 | +266 (+0.155%) | reads/misses 下降，但 read_bytes/read_busy/stall 上升。 |
| `cal256_r45` | 744170 | 744494 | +324 (+0.044%) | reads/misses 下降，但 evict_unused 与 read_busy 上升。 |
| `proxy512_r45` | 3193896 | 3221148 | +27252 (+0.853%) | reads/misses 下降明显，但 read_bytes/read_busy/stall 上升更多。 |

阶段结论：
- row-bucket v0 证明“同 row 合并机会”真实存在，也能减少 read/miss 数。
- 但 v0 没有处理多坐标 FIFO delete，且缺少 read amplification guard，导致 stale FIFO 项和读放大抵消收益，cycles 反而退化。
- 本分支必须保持默认关闭，不能写入推荐策略。
- 下一步如果继续 row-bucket，应先做：
  1. 支持一次 fill 后删除多个 FIFO 坐标，避免 stale 项在 FIFO 中堆积；
  2. 加 read amplification guard，例如只允许 bucket run 覆盖率高于阈值时发射；
  3. 再做小样本 A/B，不要直接扩大到完整矩阵。

经验记录：
- 不要只看 `reads/misses` 改善；本轮 cycles 退化的直接原因是 `read_bytes/read_busy/sample_stall` 上升。
- row-bucket 需要和 FIFO 删除策略一起设计，单独“多合并一点”并不自动提升总周期。

### 2026-04-27 row-bucket v1 尝试与 timing 回退

目标：
- 沿着上一节结论继续收口 row-bucket，但仍不跑大矩阵。
- 尝试两个护栏：
  1. `SRC_TILE_CACHE_ROW_BUCKET_MIN_X`，默认 `3`；
  2. 多坐标 FIFO delete，用于删除 bucket fill 中除 head 外的后续 FIFO 坐标。

结果：
- `ROW_BUCKET_MIN_X=3`：`cal128_r45/cal256_r45/proxy512_r45` 三个样本完全退回 default，避免 v0 退化，但没有收益。
- `ROW_BUCKET_MIN_X=2 + 多坐标 FIFO delete`：3/3 pass，结果如下：

| Workload | default cycles | min2+multi-delete cycles | delta | 主要变化 |
| --- | ---: | ---: | ---: | --- |
| `cal128_r45` | 172086 | 172150 | +64 (+0.037%) | reads/misses 降，但 read_bytes/read_busy/stall 略升。 |
| `cal256_r45` | 744170 | 740328 | -3842 (-0.516%) | sample_stall 下降，取得小幅收益。 |
| `proxy512_r45` | 3193896 | 3202508 | +8612 (+0.270%) | reads/misses 降，但 read_bytes/read_busy/stall 上升更多。 |

Timing 检查：
- 加入多坐标 FIFO delete 后，即使 row-bucket 默认关闭，SmallConfig core WNS 退到 `-0.861 ns`。
- 新 worst path：`u_rotate_core_bilinear/sample_x1_reg_reg[3] -> u_src_tile_cache/repl_protected_mask_reg_reg[0][0]/CE`。
- 这违反 timing gate 纪律，因此已回退多坐标 FIFO delete 逻辑，只保留 `SRC_TILE_CACHE_ROW_BUCKET_MIN_X` 和默认关闭的 row-bucket 入口。

回退后验证：
- `tools/run-module-sim.ps1 src_tile_cache ...`：pass。
- `tools/run-module-sim.ps1 image_geo_top ...`：pass。
- `tools/run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。
- 回退后 timing 恢复：overall WNS `+0.051 ns`，AXI WNS `+0.051 ns`，core WNS `+0.180 ns`。

经验记录：
- 多坐标 FIFO delete 不能直接挂在当前 `src_tile_cache` 主时序结构里，会破坏已收敛的 SmallConfig timing。
- 后续如果仍要做 row-bucket，必须把“FIFO 多删除/压缩”拆成独立低速队列或多周期后台事务，不能让它进入 sample/replacement 关键路径。
- 当前可保留的安全结论是：row-bucket 机会存在，但 v0/v1 都不能作为默认或推荐。

### 2026-04-27 CDC 小修：cache stats overrun AXI 同步

背景：
- SmallConfig timing 已恢复正 WNS 后，复查 `report_cdc`。
- 发现一个真实的 top 级 CDC：`cache_stats_overrun_reg` 属于 `core_clk`，但 `REG_SCHED_STATUS` 的 AXI-Lite read path 直接读它，CDC report 中表现为 `cache_stats_overrun_reg_reg/C -> s_axi_ctrl_rdata_reg[0]/D`。

RTL 改动：
- `rtl/top/image_geo_top.sv`
  - 新增 `cache_stats_overrun_axi_sync1_reg/cache_stats_overrun_axi_sync2_reg` 两级同步器，带 `ASYNC_REG` 属性。
  - `REG_SCHED_STATUS` 改为读取 `cache_stats_overrun_axi_sync2_reg`。
  - 不改变 AXI-Lite 地址，不改变 stats payload。

验证：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`：pass。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated。

Timing：
- overall WNS `+0.051 ns`
- AXI WNS `+0.051 ns`
- core WNS `+0.180 ns`
- timing gate 保持通过。

CDC 状态：
- `cache_stats_overrun_reg` 现在被识别为 `CDC-3 Info: 1-bit synchronized with ASYNC_REG property`。
- `report_cdc` 仍有 Critical/Unknown，主要来自 XPM async FIFO reset/control 内部路径，以及 input port clock -> AXI clock 的 OOC 顶层端口分类。
- 当前这些不再是已知的直接业务状态位跨域，但还需要后续单独做 CDC report 分类/waiver 文档，不能把 CDC gate 写成 fully clean。
### 2026-04-27 CDC 约束清理：删除旧 bundled-data max-delay

目标：
- stats/config/task/result CDC 已经统一改为 async FIFO / multi-word snapshot 结构后，清理旧的宽 bundled-data payload 约束。
- 避免 `report_exceptions.rpt` 继续出现无效的 `stats_payload_dst_reg` / payload hold regexp 路径，污染 CDC/timing gate 判断。

修改：
- `constraints/cdc_image_geo_top.xdc`
  - 删除旧 `set_max_delay 10.000 -datapath_only` 宽 payload regexp。
  - 增加注释：当前 config/task/result/cache-stat payload 已经 FIFO 化；若未来重新引入 req/ack bundled-data CDC，应在所属 wrapper 中对具体 payload 精确约束，不能恢复 broad hierarchical regexp。
- `reports/cdc_classification.md`
  - 改为中文分类文档。
  - 更新到当前 SmallConfig report 状态。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`

验证结果：
- report 正常生成，没有卡死。
- `report_exceptions.rpt` 中旧 bundled-data `set_max_delay` 的 `Invalid startpoint` 已消失。
- SmallConfig timing 保持通过：
  - overall WNS `+0.051 ns`
  - AXI WNS `+0.051 ns`
  - core WNS `+0.180 ns`
- 当前 worst paths：
  - AXI setup：`u_ddr_read_engine/u_axi_burst_reader/next_issue_words_to_4kb_reg_reg[1]/C -> next_issue_words_to_4kb_reg_reg[11]/R`
  - core setup：`u_rotate_core_bilinear/sample_x1_reg_reg[6]/C -> u_src_tile_cache/fifo_delete_pending_tile_x_reg_reg[0]/CE`

CDC 状态：
- `report_cdc.rpt` 中 core/axi 双向业务路径仍为 `Unsafe=0`。
- 剩余 Critical/Unknown 主要分为两类：
  1. XPM async FIFO reset/control、Gray pointer synchronizer、LUTRAM read/write 内部结构；
  2. OOC 顶层 AXI input port 缺少 wrapper/input-delay 模型导致的 input-port CDC 分类。
- 这些不能写成 fully clean；后续需要 wrapper 级约束或 waiver 文档继续收口。

经验记录：
- stats payload FIFO 化后，旧 bundled-data max-delay 必须删除；否则 `report_exceptions` 会保留无效 startpoint，后续参数优化时容易误判 CDC/timing 状态。
- 以后任何 CDC report 的 Critical/Unknown 都必须先分类来源，不能只看 summary 数字就下结论。
### 2026-04-27 cache_stats_cdc 最小 FIFO 深度修复

背景：
- 清理 CDC 约束后补跑 `cache_stats_cdc` 单测，发现功能日志已经打印 `CACHE_STATS_CDC_BACK_TO_BACK_PASS`，但 runner 仍判失败。
- 原因是 `cache_stats_cdc` 对小 payload 选择 `FIFO_DEPTH=8`，而底层 `async_word_fifo` / XPM async FIFO 要求深度至少为 16，仿真 0 ps 报出 `async_word_fifo DEPTH must be >= 16 for XPM async FIFO`。

修改：
- `rtl/axi/cache_stats_cdc.sv`
  - 将 `WORDS <= 4` 时的内部 FIFO depth 从 `8` 改为 `16`。
  - 该修改只修正小 payload/unit-test 配置；top 当前大 payload 路径原本已使用更深 FIFO，不改变 AXI-Lite register map，也不改变 scheduler 行为。

验证命令：
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 cache_stats_cdc -CompileTimeoutSec 60 -ElabTimeoutSec 60 -SimTimeoutSec 60`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-module-sim.ps1 image_geo_top -CompileTimeoutSec 120 -ElabTimeoutSec 120 -SimTimeoutSec 180`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`

验证结果：
- `cache_stats_cdc`：pass。
- `image_geo_top`：pass。
- SmallConfig report 正常生成，timing 保持通过：overall WNS `+0.051 ns`，AXI WNS `+0.051 ns`，core WNS `+0.180 ns`。
- `report_exceptions.rpt` 仍无 `Invalid startpoint`。

经验记录：
- 单测打印 PASS 但 runner 判失败时，要看完整 simulator log；0 ps 的 `$error` 也会让结果不可信。
- CDC/FIFO 类模块的 unit-test 参数也必须满足底层 XPM primitive 约束，不能只满足 top 大配置。
### 2026-04-27 timing_safe_smallconfig_2026_04_27 基线冻结

目标：
- 停止无目标 timing 微调，将当前 SmallConfig 正 WNS 状态冻结为后续 RTL shortlist 的回退基线。
- 基线名：`timing_safe_smallconfig_2026_04_27`。

版本标识：
- Git HEAD：`c7143cb`。
- Worktree：dirty；本基线以当前工作区文件和 `reports/` 生成报告共同标识，不等价于干净 commit。

SmallConfig 参数：
- `BASE_TILE_W/H=8x8`
- `SET_NUM=16`
- `WAY_NUM=2`
- `MERGE_MAX_X=2`
- `ANALYTIC_FIFO_DEPTH=8`
- `ANALYTIC_LEAD_PIXELS=16`
- `RD_BURST_MAX_LEN=8`
- `RD_MAX_OUTSTANDING_BURSTS=2`
- `RD_MAX_OUTSTANDING_BEATS=8`
- `RD_FIFO_DEPTH_WORDS=32`
- `WR_BURST_MAX_LEN=8`
- `WR_FIFO_DEPTH_PIXELS=64`

Timing：
- overall WNS `+0.051 ns`
- AXI WNS `+0.051 ns`
- core WNS `+0.180 ns`
- AXI worst path：`u_ddr_read_engine/u_axi_burst_reader/next_issue_words_to_4kb_reg_reg[1]/C -> next_issue_words_to_4kb_reg_reg[11]/R`
- core worst path：`u_rotate_core_bilinear/sample_x1_reg_reg[6]/C -> u_src_tile_cache/fifo_delete_pending_tile_x_reg_reg[0]/CE`

规则：
- 后续主线改动若让 SmallConfig WNS 变负，默认回退到本基线，除非该改动明确标为独立 performance experiment。
- 不再为几十 ps 做高风险 timing hack。
- 必须继续保持：`real miss > analytic prefetch > normal prefetch`、fill immediate invalidate、read_error cleanup、merge reservation、共享 geometry、runtime scheduler 默认行为不变、row-bucket 默认关闭。

输出：
- `reports/timing_gate_summary.md`
- `reports/cdc_classification.md`
- `constraints/ooc_image_geo_top_axi_input_delay_template.xdc`
- `docs/verification/row_bucket_v2_design.md`
## 2026-04-27 Stage1 bounded RTL shortlist 与模型校准

本轮目标：冻结 `timing_safe_smallconfig_2026_04_27`，不再做无目标 timing 微调；在 SmallConfig timing 已过约束的前提下，只跑有界 RTL shortlist，不启动完整 `7200->600` RTL matrix，不修改默认 lead/fifo/merge，不把 row-bucket 或 merge_min 固化为默认。

基线状态：
- Baseline id：`timing_safe_smallconfig_2026_04_27`
- Git HEAD：`c7143cb`，worktree dirty；本基线由当前文件状态和 `reports/` 报告共同标识。
- SmallConfig：`8x8,set16,way2,merge2,fifo8,lead16`
- Timing：overall WNS `+0.051 ns`，AXI WNS `+0.051 ns`，core WNS `+0.180 ns`
- AXI worst path：`u_ddr_read_engine/u_axi_burst_reader/next_issue_words_to_4kb_reg_reg[1]/C -> next_issue_words_to_4kb_reg_reg[11]/R`
- Core worst path：`u_rotate_core_bilinear/sample_x1_reg_reg[6]/C -> u_src_tile_cache/fifo_delete_pending_tile_x_reg_reg[0]/CE`

验证：
- `tools/run-module-sim.ps1 src_tile_cache`：pass
- `tools/run-module-sim.ps1 src_tile_cache_prefetch`：pass
- `tools/run-module-sim.ps1 ddr_read_engine`：pass
- `tools/run-module-sim.ps1 ddr_write_engine`：pass
- `tools/run-module-sim.ps1 image_geo_top`：pass
- `tools/run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`：report generated，WNS 保持正数

CDC/report：
- 输出：`reports/timing_gate_summary.md`、`reports/cdc_classification.md`
- 业务层 core/axi 双向 CDC unsafe count 为 `0`。
- 剩余 Critical/Unknown 已按来源分类：XPM async FIFO 内部项、OOC input-port 缺少 wrapper/input-delay 模型项、waiver candidate。
- 旧的大宽度 bundled-data `set_max_delay` 不恢复；后续新增 CDC 继续坚持“小 payload 两级同步，大 payload async FIFO”。

RTL shortlist：
- 配置文件：`configs/rtl_shortlist_stage1.csv`
- 输出：`sim_out/rtl_shortlist_stage1/results.csv`、`results_enriched.csv`、`summary.md`
- 范围：`small_rotate45 off/on`、`cal128 0/15/45/75/90`、`cal256 0/15/45/75/90`、`proxy512 0/45/75/90`
- 每个 workload 只跑 6 类候选：default、model top1、model top2、policy1 merge_min_age、policy2 throttle_on_miss、sanity bad
- 结果：96/96 pass，无 Fatal/timeout。

主要观察：
- `cal256/proxy512` 中 model 候选能显著降低 cycles，说明 SmallConfig timing-safe profile 只是 gate，不是性能推荐。
- `policy1 merge_min_age` 的收益多数低于 `0.5%`，只有 `cal256_r75` 达到约 `-0.61%`，仍不能固化为全局默认。
- `policy2 throttle_on_miss` 在当前参数下没有明显独立收益。
- `sanity_bad` 在 small 和部分正交 case 反而胜出，说明它不是全局坏配置；后续应重新定义 sanity 候选，并把正交 bucket 单独建模，不能把该结果写成推荐。

模型校准：
- 输出：`sim_out/model_calibration_stage1/linear_calibration_params_stage1.json`
- 输出：`sim_out/model_calibration_stage1/model_rtl_error_report_stage1.csv`
- 输出：`sim_out/model_calibration_stage1/model_rtl_error_summary_stage1.md`
- 当前模型是 Stage1 empirical bucket average，只能用于本轮 bucket 内校准，不能外推到 `7200->600`。
- 可信 bucket：`cal256` 的 orthogonal、`cal128/cal256/proxy512` 的 diagonal、`cal128/cal256` 的 small/steep angle。
- 粗筛 bucket：small diagonal 误差约 `19.17%`，cal128 orthogonal 误差约 `13.94%`，proxy512 orthogonal 误差约 `141.23%`。

Merge opportunity / row-bucket：
- 输出：`sim_out/merge_opportunity/analysis_stage1.csv|md`
- 45 度和部分 15 度 case 存在 same-row/missed-merge 机会，row-bucket 仍值得单独 A/B。
- 当前结论仍是：row-bucket v0/v1 不能进主线默认；若继续，需要 `ENABLE_ROW_BUCKET_MERGE_V2` 单独分支、后台低速多坐标 delete/compact、read amplification guard、coverage threshold。
- 设计文档：`docs/verification/row_bucket_v2_design.md`

经验约束：
- 不要再为了几十 ps 做高风险 timing hack；SmallConfig 正 WNS 已足够进入有界 RTL shortlist。
- 任何主线改动让 SmallConfig WNS 变负，默认回退到 `timing_safe_smallconfig_2026_04_27`。
- Fast model top1 不能直接当 RTL 最优；必须通过 bounded RTL shortlist 验证。
- 不跑完整 `7200->600` RTL matrix，直到 CDC/report、模型误差和 proxy shortlist 都稳定。
## 2026-04-27 proxy1024 bounded shortlist 与 Stage2 模型校准

本轮目标：在不跑完整 `7200->600` RTL matrix 的前提下，补一个 `1024x1024 -> 256x256` 的 proxy1024 小矩阵，专门验证 Stage1 中 `proxy512 orthogonal` 误差过大、以及 75 度参数迁移不稳定的问题。

源码/脚本改动：
- `rtl/sim/tb_image_geo_top_perf_single_light.sv`
  - 只新增两个轻量 testbench wrapper：`tb_image_geo_top_perf_single_proxy_rotate0_on`、`tb_image_geo_top_perf_single_proxy_rotate90_on`。
  - 不改设计 RTL，不改默认 scheduler，不改 AXI-Lite register map。
- `scripts/gen_rtl_shortlist_proxy1024.py`
  - 新增 bounded proxy1024 shortlist 生成脚本。
  - 角度：`0/15/45/75/90`。
  - 每角度只跑 5 类候选：default、model_top1、model_top2、policy1_merge_min_age、sanity_bad。

运行：
- `python scripts/gen_rtl_shortlist_proxy1024.py --out configs/rtl_shortlist_proxy1024.csv`：25 rows。
- `python scripts/run_rtl_shortlist.py --input configs/rtl_shortlist_proxy1024.csv --out sim_out/rtl_shortlist_proxy1024/results.csv --top-n 999 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 600`
- 总耗时约 56 分钟，所有单组都有 timeout 上限，没有裸跑。

结果：
- `sim_out/rtl_shortlist_proxy1024/results.csv`
- `sim_out/rtl_shortlist_proxy1024/results_enriched.csv`
- `sim_out/rtl_shortlist_proxy1024/summary.md`
- 25 组中 20 组 pass，5 组 fail。
- 失败原因全部是 testbench bounded timeout：`PERF_SINGLE_TIMEOUT ... cycles=12000006 status=0x00000001`，不是仿真进程卡死。
- timeout 组合：
  - `proxy1024_r15 sanity_bad`
  - `proxy1024_r45 sanity_bad`
  - `proxy1024_r75 model_top1`
  - `proxy1024_r75 sanity_bad`
  - `proxy1024_r90 sanity_bad`

阶段性性能观察：

| Workload | default cycles | best pass candidate | best cycles | delta |
| --- | ---: | --- | ---: | ---: |
| `proxy1024_r0` | 6,096,090 | `model_top2` | 5,501,186 | -594,904 |
| `proxy1024_r15` | 7,467,950 | `model_top1` | 6,761,548 | -706,402 |
| `proxy1024_r45` | 8,452,818 | `model_top2` | 8,016,688 | -436,130 |
| `proxy1024_r75` | 7,823,170 | `default` | 7,823,170 | 0 |
| `proxy1024_r90` | 6,622,982 | `model_top2` | 6,289,210 | -333,772 |

关键结论：
- `proxy1024_r75 model_top1(16x8,lead64)` timeout，说明 `16x8` 不能简单从 `cal256/proxy512` 外推到更大尺度和 75 度。
- `policy1_merge_min_age` 在 proxy1024 上几乎无收益：`proxy1024_r45` 仅 `-0.007%`，其余为 0 或回退；继续不作为默认。
- `sanity_bad` 在 proxy1024 中多数变成真正坏配置或 timeout，后续可以继续作为压力/反例，但不能混入候选推荐。
- orthogonal proxy1024 中 `model_top2(8x8,set32,merge4,fifo16,lead64)` 比 timing-safe default 更快，但仍未经过 synth/timing/resource 筛选，状态为 candidate。

Stage2 模型校准：
- 合并输入：Stage1 96 组 + proxy1024 25 组，其中 pass rows 116。
- 输出：
  - `sim_out/model_calibration_stage2/stage1_proxy1024_combined.csv`
  - `sim_out/model_calibration_stage2/linear_calibration_params_stage2.json`
  - `sim_out/model_calibration_stage2/model_rtl_error_report_stage2.csv`
  - `sim_out/model_calibration_stage2/model_rtl_error_summary_stage2.md`
- 注意：当前仍是 empirical bucket average，许多 proxy1024 bucket 是单点自拟合，不能写成外推可信。

Merge/scheduler 分析：
- `sim_out/merge_opportunity_proxy1024/analysis_stage1.csv|md`
- `sim_out/scheduler_policy_buckets_proxy1024/policy_bucket_stage1.csv|md`
- proxy1024 中 same-row/missed-merge 机会在 15/45 度仍明显，但 row-bucket 仍只适合作为单独 V2 分支；主线保持关闭。

经验记录：
- 不要把 `16x8` 视为 75 度大尺度通用候选；`proxy1024_r75 model_top1` 已 timeout。
- 不要把 empirical 单点 0% 误差当作模型泛化能力。
- 继续避免完整 `7200->600` RTL matrix；下一步若扩展，应先做 proxy1024 少量补点或针对 orthogonal/75 度单独建模。
## 2026-04-27 proxy1024 orthogonal/75 targeted lead 补点

本轮目标：不跑完整 `7200->600` RTL matrix，只对 `proxy1024` 的正交 `0/90` 和 `75°` 做少量补点，验证 `8x8,set32,merge4,fifo16` 下 `lead32/64/128` 的影响，并继续保留一个 `16x8` 风险对照。

源码/脚本改动：
- `scripts/gen_rtl_shortlist_proxy1024_targeted.py`
  - 新增 15 组 targeted shortlist 生成脚本。
  - Workload：`proxy1024_r0`、`proxy1024_r75`、`proxy1024_r90`。
  - Candidate：`timing_safe_default`、`lead32`、`lead64`、`lead128`、`wide_tile_risk(16x8,lead64)`。
- 本轮没有修改设计 RTL、默认 scheduler、AXI-Lite register map 或 analytic planner。

运行：
- `python scripts/gen_rtl_shortlist_proxy1024_targeted.py --out configs/rtl_shortlist_proxy1024_targeted.csv`
- `python scripts/run_rtl_shortlist.py --input configs/rtl_shortlist_proxy1024_targeted.csv --out sim_out/rtl_shortlist_proxy1024_targeted/results.csv --top-n 999 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 600`

结果：
- `sim_out/rtl_shortlist_proxy1024_targeted/results.csv`
- `sim_out/rtl_shortlist_proxy1024_targeted/results_enriched.csv`
- `sim_out/rtl_shortlist_proxy1024_targeted/summary.md`
- 15 组中 14 组 pass，1 组 fail。
- 唯一 fail：`proxy1024_r75 wide_tile_risk(16x8,lead64)`，原因仍是 bounded timeout：`PERF_SINGLE_TIMEOUT ... cycles=12000006`。

性能观察：

| Workload | best pass candidate | cycles | 相对 timing_safe_default |
| --- | --- | ---: | ---: |
| `proxy1024_r0` | `wide_tile_risk(16x8,lead64)` | 5,479,164 | -616,926 |
| `proxy1024_r75` | `lead32(8x8,set32,merge4,fifo16)` | 7,642,092 | -181,078 |
| `proxy1024_r90` | `lead128(8x8,set32,merge4,fifo16)` | 6,287,816 | -335,166 |

细节结论：
- `proxy1024_r0` 中 `16x8` 可以略快于 `8x8 lead64`，但同一 `16x8` 在 `proxy1024_r90` 退化到 11,502,844 cycles，在 `proxy1024_r75` timeout，因此不能作为正交通用配置。
- `proxy1024_r90` 中 `lead64/lead128` 很接近，`lead32` 明显退化并产生大量 miss，说明 90 度下 lead 太短会导致预取覆盖不足。
- `proxy1024_r75` 中 `lead32` 最优，`lead64/lead128` 稍差但可用；`16x8` 继续 timeout。

Stage3 模型校准：
- 合并输入：Stage1 + proxy1024 shortlist + proxy1024 targeted，合计 136 rows，其中 pass rows 130。
- 输出：
  - `sim_out/model_calibration_stage3/stage1_proxy1024_targeted_combined.csv`
  - `sim_out/model_calibration_stage3/linear_calibration_params_stage3.json`
  - `sim_out/model_calibration_stage3/model_rtl_error_report_stage3.csv`
  - `sim_out/model_calibration_stage3/model_rtl_error_summary_stage3.md`
- `proxy1024 orthogonal` 最大误差升至 `54.97%`，标记为 `coarse only`。

经验记录：
- 正交 bucket 不能只按 angle/frame/candidate 平均，必须纳入 `lead_pixels` 和结构参数，否则同一 bucket 内 `lead32/64/128` 会被模型混在一起，形成误导。
- `proxy1024_r75` 不应继续优先尝试 `16x8`；后续应围绕 `8x8,set32,merge4,fifo16,lead32/64/128` 做更窄的策略验证。
- 仍然不允许把任何 proxy1024 结果外推为 `7200->600` proven。
## 2026-04-27 Stage5 参数感知经验模型修复

本轮目标：修复 Stage3 模型把 `lead32/64/128`、`0/90`、small off/on 混在同一 bucket 的问题。只改模型校准/比较脚本，不新增 RTL 仿真，不改主线 RTL。

脚本改动：
- `scripts/fit_model_calibration.py`
  - Stage empirical key 从 `angle_bucket/frame/candidate` 改为参数感知 key。
  - key 现在包含：`angle_bucket`、精确 `angle_deg`、`frame_class`、`prefetch_mode`、`tile_w/h`、`set_num/way_num`、`merge_max_x`、`fifo_depth`、`lead_pixels`、runtime scheduler policy/min/age/throttle。
- `scripts/compare_model_rtl.py`
  - 支持新的 `stage_empirical_param_bucket_average` JSON。
  - summary 中不再把低误差直接写成 trusted；若 bucket 只有单点，标记为 `lookup only`。

输出：
- `sim_out/model_calibration_stage5/param_bucket_angle_calibration_stage5.json`
- `sim_out/model_calibration_stage5/param_bucket_angle_fit_stage5.md`
- `sim_out/model_calibration_stage5/param_bucket_angle_error_report_stage5.csv`
- `sim_out/model_calibration_stage5/param_bucket_angle_error_summary_stage5.md`

结果：
- 130 pass rows 被分成 125 个参数感知 groups。
- 各 angle/frame bucket 的误差为 `0%`，但 `Min group count=1`，全部标记为 `lookup only`。

经验记录：
- 这不是预测模型，只是“已观测参数组合查表/聚合”。它的价值是防止不同 lead/tile/方向被错误平均。
- 后续要做真正推荐，需要在同一参数 key 周围增加相邻补点，或恢复/改进 fast model 的特征回归；不能拿 `lookup only` 当作未见 workload 的 cycles 预测。
- 当前仍不能外推到 `7200->600`。
## 2026-04-27 proxy1024 lead48/96 相邻补点

本轮目标：在不扩大为完整矩阵的前提下，只改一类参数 `lead_pixels`，固定结构为 `8x8,set32,way2,merge4,fifo16`，对 `proxy1024_r0/r75/r90` 补 `lead48/96`。本轮不改 RTL，不改默认调度，不扫 `fifo32`。

脚本/配置：
- 新增 `scripts/gen_rtl_shortlist_proxy1024_lead_refine.py`
- 生成 `configs/rtl_shortlist_proxy1024_lead_refine.csv`
- 运行命令：
  - `python scripts/run_rtl_shortlist.py --input configs/rtl_shortlist_proxy1024_lead_refine.csv --out sim_out/rtl_shortlist_proxy1024_lead_refine/results.csv --top-n 999 --sort-key score --compile-timeout 120 --elab-timeout 120 --sim-timeout 600`

结果：
- `sim_out/rtl_shortlist_proxy1024_lead_refine/results.csv`
- `sim_out/rtl_shortlist_proxy1024_lead_refine/results_enriched.csv`
- `sim_out/rtl_shortlist_proxy1024_lead_refine/summary.md`
- 6/6 pass，无 timeout/Fatal。

合并 `lead32/64/128` 后的 lead 曲线：

| Workload | lead32 | lead48 | lead64 | lead96 | lead128 | 当前观察 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `proxy1024_r0` | 5,764,168 | 5,503,138 | 5,501,186 | 5,498,882 | 5,562,678 | `lead96` 略优，`48/64/96` 接近 |
| `proxy1024_r75` | 7,642,092 | 7,672,454 | 7,666,628 | 7,666,192 | 7,666,138 | `lead32` 最优 |
| `proxy1024_r90` | 7,804,216 | 6,291,066 | 6,289,210 | 6,288,934 | 6,287,816 | `lead64/96/128` 接近，`lead32` 明显不足 |

Stage6 lookup：
- 合并输入：Stage1 + proxy1024 shortlist + proxy1024 targeted + lead refine，合计 142 rows，其中 pass rows 136。
- 输出：
  - `sim_out/model_calibration_stage6/stage1_proxy1024_lead_refine_combined.csv`
  - `sim_out/model_calibration_stage6/param_bucket_angle_calibration_stage6.json`
  - `sim_out/model_calibration_stage6/param_bucket_angle_error_report_stage6.csv`
  - `sim_out/model_calibration_stage6/param_bucket_angle_error_summary_stage6.md`
- 仍为 `lookup only`，不是外推预测模型。

经验记录：
- `lead` 的最优值明显依赖角度：不能为 proxy1024 统一写一个固定 lead。
- `proxy1024_r75` 不适合盲目加大 lead；`lead32` 反而比 `64/96/128` 更快。
- `proxy1024_r90` 对 lead 太短非常敏感，`lead32` 产生大量 miss/stall，至少需要 `lead64` 左右。
- 下一轮如果继续，只能再选一类参数，例如固定 `lead64/96` 看 `fifo16 -> fifo32`，不要同时扫 lead 和 fifo。
## 2026-04-27 proxy1024 fifo32 小补点

本轮目标：固定 `8x8,set32,way2,merge4` 和已选 lead，只改一类结构参数 `ANALYTIC_FIFO_DEPTH`：`fifo16 -> fifo32`。不改 RTL 默认策略，不跑大矩阵。

脚本/配置：
- 新增 `scripts/gen_rtl_shortlist_proxy1024_fifo_refine.py`
- 生成 `configs/rtl_shortlist_proxy1024_fifo_refine.csv`
- 只跑 5 组：
  - `proxy1024_r0 lead64/96`
  - `proxy1024_r75 lead32`
  - `proxy1024_r90 lead64/96`

运行结果：
- `sim_out/rtl_shortlist_proxy1024_fifo_refine/results.csv`
- `sim_out/rtl_shortlist_proxy1024_fifo_refine/results_enriched.csv`
- `sim_out/rtl_shortlist_proxy1024_fifo_refine/summary.md`
- 5/5 pass，无 timeout/Fatal。

与 `fifo16` 对比：

| Workload | lead | fifo16 cycles | fifo32 cycles | delta |
| --- | ---: | ---: | ---: | ---: |
| `proxy1024_r0` | 64 | 5,501,186 | 5,923,256 | +422,070 |
| `proxy1024_r0` | 96 | 5,498,882 | 5,563,064 | +64,182 |
| `proxy1024_r75` | 32 | 7,642,092 | 7,270,196 | -371,896 |
| `proxy1024_r90` | 64 | 6,289,210 | 7,799,666 | +1,510,456 |
| `proxy1024_r90` | 96 | 6,288,934 | 6,549,032 | +260,098 |

结论：
- `fifo32` 不是全局更优。
- `proxy1024_r75 lead32` 受益明显，sample stall 和 read_busy 都下降。
- `proxy1024_r0` 与 `proxy1024_r90` 使用 fifo32 会退化，尤其 `r90 lead64` 退化很大。
- FIFO 深度也需要按角度/lead 分桶，不能作为统一默认。

Stage7 lookup：
- 合并输入增加到 147 rows，其中 pass rows 141。
- 输出：
  - `sim_out/model_calibration_stage7/stage1_proxy1024_fifo_refine_combined.csv`
  - `sim_out/model_calibration_stage7/param_bucket_angle_calibration_stage7.json`
  - `sim_out/model_calibration_stage7/param_bucket_angle_error_report_stage7.csv`
  - `sim_out/model_calibration_stage7/param_bucket_angle_error_summary_stage7.md`

经验记录：
- 不能为了减少 blocked 或增加 future window 盲目加 FIFO；更深 FIFO 可能引入更早/更多 speculative prefetch，增加 stall 或污染调度。
- 下一轮若继续，只应针对 `r75 fifo32 lead32` 看是否值得做 timing/resource 检查；不要把 fifo32 放入全局默认。
