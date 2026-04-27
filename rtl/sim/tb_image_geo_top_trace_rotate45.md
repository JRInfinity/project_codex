# tb_image_geo_top_trace_rotate45

## Purpose

Focused trace testbench for the rotate-45-degree case.

It runs one top-level transform:

- source: `48x48`
- destination: `32x32`
- angle: `45 deg`
- prefetch: enabled

## What It Prints

- accepted sample requests from the rotate core to the source cache
- source coordinate footprint for each request
- tile footprint for each request
- cache fill events marked as `demand` or `prefetch`
- a final cache-stat summary

## Why It Exists

This testbench is for understanding the real access trajectory before changing
the cache predictor again. It helps answer:

- whether rotate-45 walks tiles diagonally, alternates between axes, or sticks
  to a small boundary working set
- whether the cache is issuing only demand fills
- whether the current predictor has any chance to schedule useful prefetches
