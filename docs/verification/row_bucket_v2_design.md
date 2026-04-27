# Row-Bucket Merge V2 Design Note

## Goal

Investigate same-row merge opportunity without damaging the current timing-safe mainline. V2 must remain default-off and must not place multi-coordinate FIFO delete/compact logic on the sample or replacement critical path.

## Constraints

- Keep `real miss > analytic prefetch > normal prefetch`.
- Keep fill immediate invalidate, read_error cleanup, merge reservation, shared geometry, and runtime scheduler default behavior.
- Do not modify `sample_req_ready` semantics.
- Do not enable row-bucket by default.

## Proposed V2 Shape

- Add `ENABLE_ROW_BUCKET_MERGE_V2`, default `0`.
- Capture a row-bucket fill as a normal analytic candidate only when:
  - all sectors share one `tile_y`;
  - `tile_x` is contiguous;
  - estimated useful coverage exceeds a configurable threshold;
  - estimated read amplification remains below a configurable limit.
- Move multi-coordinate FIFO delete into a background low-speed transaction:
  - record filled bucket coordinates into a small delete queue;
  - compact/delete at most one FIFO coordinate per cycle when replacement is idle;
  - never feed delete fanout into the sample/replacement stage CE path.
- Keep the initial A/B limited to `cal256_r45` and `proxy512_r45`.

## Risks

- Larger merged reads can reduce read/miss count while increasing `read_bytes`, `read_busy`, and `sample_stall`.
- Multi-coordinate FIFO delete previously broke SmallConfig timing; V2 must prove timing before any performance interpretation.

## Acceptance for Any Future Implementation

- Default-off mainline timing remains at or above the frozen timing-safe baseline.
- `src_tile_cache`, `src_tile_cache_prefetch`, and `image_geo_top` smoke pass.
- A/B shows total cycles improvement, not just miss/read count reduction.

