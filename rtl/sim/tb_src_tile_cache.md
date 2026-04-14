# tb_src_tile_cache

## Overview

- DUT: `src_tile_cache`
- Testbench: `tb_src_tile_cache.sv`
- Mode: baseline cache behavior with prefetch disabled

This testbench focuses on cache correctness rather than top-level image processing.

## Covered Cases

- first miss fills one tile row-by-row
- same-tile hit does not trigger extra reads
- horizontal cross-tile request loads the next tile
- vertical cross-tile request handles bottom edge tile height correctly
- replacement behavior with `TILE_NUM=2`
- displaced tile revisit triggers refill as expected

## Expected Signals

- `stat_read_starts`: non-zero and consistent with row-fill count
- `stat_misses`: increments on true miss-driven fills
- `stat_prefetch_starts`: zero in this testbench
- `stat_prefetch_hits`: zero in this testbench

## Latest Result

- Status: pass
- Notes:
  - cache fill / hit / replace behavior is verified in isolation
  - this testbench is the no-prefetch baseline for later comparisons
