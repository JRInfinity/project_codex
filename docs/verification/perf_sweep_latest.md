# Performance Sweep Report

Generated: 2026-04-08 20:46:30

| Case | Prefetch | Src | Dst | Reads | Misses | Prefetches | Hits |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| identity_64x16 | 0 | 64x16 | 64x16 | 64 | 4 | 0 | 0 |
| identity_64x16 | 1 | 64x16 | 64x16 | 64 | 1 | 3 | 3 |
| downscale_64_to_32 | 0 | 64x64 | 32x32 | 256 | 16 | 0 | 0 |
| downscale_64_to_32 | 1 | 64x64 | 32x32 | 256 | 4 | 12 | 12 |
| rotate45_48_to_32 | 0 | 48x48 | 32x32 | 1312 | 82 | 0 | 0 |
| rotate45_48_to_32 | 1 | 48x48 | 32x32 | 1312 | 82 | 0 | 0 |
| rotate90_32x48 | 0 | 32x48 | 32x48 | 128 | 8 | 0 | 0 |
| rotate90_32x48 | 1 | 32x48 | 32x48 | 128 | 5 | 3 | 3 |
| rotate45_downscale_64_to_24 | 0 | 64x64 | 24x24 | 1872 | 117 | 0 | 0 |
| rotate45_downscale_64_to_24 | 1 | 64x64 | 24x24 | 1872 | 117 | 0 | 0 |

## Notes

- prefetch=0 is the baseline.
- prefetch=1 enables the runtime tile-cache prefetch path.
- Compare misses and hits first when judging whether prefetch helps a case.
