# Timing Gate Summary - timing_safe_smallconfig_2026_04_27

## Baseline

- Baseline id: `timing_safe_smallconfig_2026_04_27`
- Git HEAD at freeze: `c7143cb`
- Worktree: dirty; this baseline is identified by the checked files and generated reports in this workspace, not by a clean commit.
- Report command: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-vivado-reports.ps1 -Mode synth -SmallConfig -TimeoutSec 600`

## SmallConfig Defines

| Parameter | Value |
| --- | ---: |
| `SRC_TILE_CACHE_BASE_TILE_W` | 8 |
| `SRC_TILE_CACHE_BASE_TILE_H` | 8 |
| `SRC_TILE_CACHE_SECTOR_SET_NUM` | 16 |
| `SRC_TILE_CACHE_SECTOR_WAY_NUM` | 2 |
| `SRC_TILE_CACHE_MERGE_MAX_X` | 2 |
| `SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH` | 8 |
| `SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS` | 16 |
| `IMAGE_GEO_RD_BURST_MAX_LEN` | 8 |
| `IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS` | 2 |
| `IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS` | 8 |
| `IMAGE_GEO_RD_FIFO_DEPTH_WORDS` | 32 |
| `IMAGE_GEO_WR_BURST_MAX_LEN` | 8 |
| `IMAGE_GEO_WR_FIFO_DEPTH_PIXELS` | 64 |

## Timing Result

| Clock/group | WNS |
| --- | ---: |
| Overall | `+0.051 ns` |
| `image_geo_axi_clk` | `+0.051 ns` |
| `image_geo_core_clk` | `+0.180 ns` |

Current worst setup paths:

- AXI: `u_ddr_read_engine/u_axi_burst_reader/next_issue_words_to_4kb_reg_reg[1]/C -> next_issue_words_to_4kb_reg_reg[11]/R`
- Core: `u_rotate_core_bilinear/sample_x1_reg_reg[6]/C -> u_src_tile_cache/fifo_delete_pending_tile_x_reg_reg[0]/CE`

## CDC Gate

- Core/AXI business CDC unsafe count: `0`.
- `report_exceptions.rpt` has no old bundled-data `Invalid startpoint`.
- Remaining CDC items are classified in `reports/cdc_classification.md`.
- Formal CDC signoff is not fully closed until XPM FIFO internal paths and OOC input-port paths are handled by wrapper constraints or waivers.

## Gate Decision

- Allowed: bounded RTL shortlist and model calibration.
- Not allowed: full `7200->600` RTL matrix, global scheduler default changes, row-bucket default enable.
- Regression rule: any mainline change that makes SmallConfig WNS negative should be reverted unless explicitly isolated as a performance experiment branch.

