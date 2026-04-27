# tb_image_geo_top_trace_rotate45_downscale

## Purpose

Focused trace testbench for the `64x64 -> 24x24` rotate-45-degree downscale case.

It prints:

- accepted sample requests
- source coordinate footprint
- tile footprint
- demand/prefetch fill events
- final cache-stat summary

## Why It Exists

The top-level sweep still shows no prefetch benefit for this case. This testbench
captures the real request trajectory so the predictor can be tuned against the
actual downscale-plus-rotate access pattern instead of a guessed one.
