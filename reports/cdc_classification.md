# CDC Classification - 2026-04-27

This file classifies the current `SmallConfig` `report_cdc` output. It is a signoff aid, not a performance recommendation.

Source reports:

- `reports/report_cdc.rpt`
- `reports/report_cdc_details.rpt`
- `reports/report_clock_interaction.rpt`
- `reports/report_exceptions.rpt`

## Summary

| Clock pair | Endpoints | Safe | Unsafe | Unknown | Classification |
| --- | ---: | ---: | ---: | ---: | --- |
| `image_geo_core_clk -> image_geo_axi_clk` | 146 | 113 | 0 | 33 | No true business CDC unsafe. Remaining unknowns are XPM async FIFO internals. |
| `image_geo_axi_clk -> image_geo_core_clk` | 146 | 106 | 0 | 40 | No true business CDC unsafe. Remaining unknowns are XPM async FIFO internals. |
| `input port clock -> image_geo_axi_clk` | 68 | 1 | 36 | 31 | OOC input-port model issue. Needs wrapper input-delay model or waiver. |
| `input port clock -> image_geo_core_clk` | 1 | 1 | 0 | 0 | Reset synchronizer. |

## Remaining Critical/Unknown Classes

| Class | Report IDs / examples | Category | Action |
| --- | --- | --- | --- |
| XPM Gray pointer synchronizers | `CDC-6`, `gen_cdc_pntr.*src_gray_ff_reg -> dest_graysync_ff_reg` | XPM async FIFO internal expected | Waiver candidate. Keep using XPM FIFO; no RTL fix planned. |
| XPM LUTRAM read/write collision | `CDC-26`, `xpm_memory_base_inst/gen_sdpram` | XPM async FIFO internal expected | Waiver candidate. This is async FIFO storage structure. |
| XPM reset/control FSM | `CDC-1`, `u_axi_reset_sync/u_core_reset_sync -> xpm_fifo_rst_inst/*` | XPM async FIFO internal expected | Waiver candidate. Review with Xilinx XPM CDC/reset guidance before formal signoff. |
| OOC AXI input ports | `CDC-13`, `m_axi_rd_rdata/rresp -> u_ddr_read_engine/u_async_word_fifo/*` | OOC input-port no wrapper timing model | Use wrapper/BD constraints or `constraints/ooc_image_geo_top_axi_input_delay_template.xdc` as a starting point. |
| Business control status | `cache_stats_overrun_reg -> cache_stats_overrun_axi_sync1_reg` | true business CDC, fixed | Two-flop `ASYNC_REG`; classified as `CDC-3 Info`. |
| Wide stats/config/task/result payloads | `cache_stats_cdc`, `frame_config_cdc`, `task_cdc`, `task_cdc_2d`, `result_cdc` | true business CDC, fixed | Payloads cross through async FIFO, not bundled-data toggle CDC. |

## Explicit Non-Issues

- The old broad bundled-data `set_max_delay` regexp is intentionally removed; `report_exceptions.rpt` no longer shows its `Invalid startpoint`.
- Do not reintroduce a wide payload bundled-data CDC for stats/config/task/result. Use async FIFO for medium/large payloads.
- `SmallConfig` timing is currently positive: overall `+0.051 ns`, AXI `+0.051 ns`, core `+0.180 ns`.

## Gate Status

- Bounded RTL shortlist may proceed.
- Full CDC signoff still needs wrapper-level AXI input timing or an explicit OOC waiver package for input-port classifications and XPM FIFO internals.

