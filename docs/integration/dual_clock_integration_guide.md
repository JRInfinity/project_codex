# Dual-Clock Integration Guide

## Clock split

`image_geo_top` now runs as a true dual-clock design:

- `axi_clk`: 200 MHz in simulation
- `core_clk`: 100 MHz in simulation

The intended partition is:

- AXI domain: AXI-Lite register block, `ddr_read_engine`, `ddr_write_engine`
- Core domain: `src_tile_cache`, `rotate_core_bilinear`, `row_out_buffer`, `scaler_ctrl`

This matches the target architecture where DDR traffic runs faster than the
image-processing pipeline.

## CDC boundaries

The design currently crosses clock domains in five places:

1. `frame_config_cdc`
   Sends the frame start pulse and all frame configuration registers from the
   AXI control domain into the core domain.

2. `ddr_read_engine`
   Uses `task_cdc` for the read command, `result_cdc` for completion/error, and
   `async_word_fifo` for the actual read data stream.

3. `ddr_write_engine`
   Uses `task_cdc` for the write command, `result_cdc` for completion/error, and
   `async_word_fifo` as an async pixel FIFO from `core_clk` to `axi_clk`.

4. `u_ctrl_result_cdc`
   Sends frame-level done/error status from the core domain back to the AXI
   register domain.

5. `cache_stats_cdc`
   Snapshots the source tile cache statistics into the AXI domain so software
   reads stable counters instead of peeking into core-domain signals.

## Counter semantics

`src_tile_cache` now reports:

- `stat_read_starts`: demand read launches
- `stat_misses`: demand misses
- `stat_prefetch_starts`: prefetch launches
- `stat_prefetch_hits`: demand requests that actually hit a previously
  prefetched tile

The `prefetch_hits` counter is no longer the old pending-prefetch approximation.
It now reflects a real prefetched-tile hit.

## AXI-Lite registers

Relevant addresses in the current top level:

- `0x020`: rotation sine in signed Q16
- `0x024`: rotation cosine in signed Q16
- `0x028`: source cache demand read count
- `0x02C`: source cache miss count
- `0x030`: source cache prefetch launch count
- `0x034`: source cache prefetch hit count
- `0x038[0]`: source cache prefetch enable

Frame launch still happens through the existing control/start register path; the
full frame configuration is captured in AXI clock domain and then sent across
with `frame_config_cdc`.

## Simulation status

The current dual-clock regressions run with:

- `axi_clk = 200 MHz`
- `core_clk = 100 MHz`

Key regressions that pass in this configuration:

- `tb_ddr_write_engine`
- `tb_scaler_ctrl`
- `tb_src_tile_cache_prefetch`
- `tb_image_geo_top`
- `tb_image_geo_top_prefetch_stress`

In the current top-level stress run, prefetch improves source-cache demand
misses from `4` to `2`, while the prefetch counters show `prefetches=2` and
`hits=2`.

## Constraint guidance

See [cdc_image_geo_top.xdc](/C:/Users/huawei/Desktop/project_codex/constraints/cdc_image_geo_top.xdc)
for an example of:

- defining the two clocks
- marking async reset paths false
- excluding toggle-based CDC synchronizers from normal timing
- excluding the async FIFO CDC paths from normal timing

Treat that XDC as a starting point and align the final hierarchy names with the
wrapper used in implementation. The checked-in file is a pure XDC version, so
the default clock/reset endpoints target the BD instance name used by the
example script: `*image_geo_top_0*`. If your wrapper uses a different instance
name, update those `get_pins -hier ...` patterns. If you synthesize
`image_geo_top` directly as the top module, swap those endpoints to
`get_ports ...`.
