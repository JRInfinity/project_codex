# tb_image_geo_top_perf_sweep

## Purpose

Top-level performance regression for the dual-clock rotate/scale pipeline.

It runs multiple transform cases twice:

- prefetch disabled
- prefetch enabled

For each run it checks:

- final image data against the software bilinear reference
- top-level done/error status
- source tile-cache statistics

## Clocking

- `axi_clk = 200 MHz`
- `core_clk = 100 MHz`

## Cases

- `identity_64x16`
- `downscale_64_to_32`
- `rotate45_48_to_32`
- `rotate90_32x48`
- `rotate45_downscale_64_to_24`

Each case prints a single `PERF` line with:

- case name
- prefetch on/off
- source and destination size
- sine/cosine Q16 coefficients
- demand read count
- demand miss count
- prefetch start count
- prefetch hit count

The regression does not require prefetch to improve every case. Some rotated
access patterns can still regress with the current lightweight prefetcher, and
that is exactly what this sweep is meant to reveal.

These lines are intended to be parsed by the performance sweep helper script.
