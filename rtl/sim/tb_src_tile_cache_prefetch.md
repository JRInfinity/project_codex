# tb_src_tile_cache_prefetch

## Overview

- DUT: `src_tile_cache`
- Testbench: `tb_src_tile_cache_prefetch.sv`
- Mode: prefetch-enabled cache behavior

This testbench is used to prove that the lightweight directional prefetch path is active and observable.

## Covered Cases

- load tile 0
- cross into tile 1
- access tile 1 again to trigger prefetch scheduling for tile 2
- verify later access to tile 2 does not add extra read tasks

## What This Proves

- prefetch can be enabled independently of core cache correctness tests
- the cache can pull a future neighboring tile before it is directly requested
- prefetched data can be consumed without an additional miss-driven fill

## Latest Result

- Status: pass
- Notes:
  - used as the focused regression for prefetch effectiveness
  - complements `tb_src_tile_cache.sv`, which keeps prefetch disabled
