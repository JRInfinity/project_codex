# tb_image_geo_top

## Overview

- DUT: `image_geo_top`
- Testbench: `tb_image_geo_top.sv`
- Scope: top-level functional regression for rotate + scale + tile-cache pipeline

This testbench verifies the integrated path:

- AXI-Lite register programming
- DDR read path
- `src_tile_cache`
- unified inverse-mapping rotate/scale core
- row output buffering
- DDR write-back

## Covered Cases

- `4x4 -> 4x4` identity check
- `4x4 -> 4x4` 90-degree clockwise rotation check
- `4x4 -> 4x4` 45-degree bilinear reference check
- `20x20 -> 20x20` 45-degree bilinear reference check across multiple tiles
- cache statistics register readback
- runtime prefetch enable/disable register programming

## Cache Statistic Registers

- `0x028`: cache read-start count
- `0x02C`: cache miss count
- `0x030`: cache prefetch-start count
- `0x034`: cache prefetch-hit count
- `0x038[0]`: cache prefetch enable

## Latest Result

- Status: pass
- Notes:
  - top-level rotate/scale path is functionally verified
  - cache statistic registers are readable at AXI-Lite level
  - prefetch enable can be toggled at runtime without breaking functional flow
