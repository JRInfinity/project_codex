# tb_image_geo_top_prefetch_stress

## Overview

- DUT: `image_geo_top`
- Testbench: `tb_image_geo_top_prefetch_stress.sv`
- Scope: larger top-level stress regression for tile-cache prefetch visibility

This testbench uses a `64x64`-capable DUT instance and a `48x16 -> 48x16` sweep so the source access crosses at least three horizontal tiles. That gives the full top-level path enough room to show non-zero prefetch counters, not just the module-level cache testbench.

## Covered Cases

- `48x16 -> 48x16` identity sweep with prefetch disabled
- `48x16 -> 48x16` identity sweep with prefetch enabled
- per-pixel reference comparison for both runs
- top-level cache statistic register checks

## Expected Prefetch Behavior

- With `0x038[0] = 0`, `0x030` and `0x034` must stay zero
- With `0x038[0] = 1`, `0x030` must become non-zero
- Prefetch-enabled demand misses must be lower than the no-prefetch baseline

## Latest Result

- Status: pending rerun
- Notes:
  - complements `tb_src_tile_cache_prefetch.sv`
  - proves runtime prefetch activity and lower demand-miss count at full top-level integration scale
