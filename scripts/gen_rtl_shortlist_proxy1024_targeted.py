#!/usr/bin/env python3
"""Generate a tiny proxy1024 targeted shortlist.

This matrix probes orthogonal and 75-degree behavior around the current
candidate `8x8,set32,way2,merge4,fifo16` with a small lead sweep. It is not a
full workload matrix and should not be used as a final recommendation table.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


WORKLOADS = [
    ("proxy1024_r0", "tb_image_geo_top_perf_single_proxy_rotate0_on", 0),
    ("proxy1024_r75", "tb_image_geo_top_perf_single_proxy_rotate75_on", 75),
    ("proxy1024_r90", "tb_image_geo_top_perf_single_proxy_rotate90_on", 90),
]


def row(
    workload: str,
    rtl_top: str,
    angle: int,
    candidate: str,
    tile_w: int,
    tile_h: int,
    set_num: int,
    way_num: int,
    merge_max_x: int,
    fifo_depth: int,
    lead_pixels: int,
    score: int,
) -> dict[str, str]:
    return {
        "workload_id": f"{workload}_{candidate}",
        "stage_workload": workload,
        "candidate_class": candidate,
        "angle_deg": str(angle),
        "frame_class": "proxy1024",
        "rtl_top": rtl_top,
        "tile_w": str(tile_w),
        "tile_h": str(tile_h),
        "set_num": str(set_num),
        "way_num": str(way_num),
        "merge_max_x": str(merge_max_x),
        "fifo_depth": str(fifo_depth),
        "lead_pixels": str(lead_pixels),
        "runtime_lead_pixels": str(lead_pixels),
        "runtime_merge_max_x_eff": str(merge_max_x),
        "runtime_merge_min_x": "1",
        "runtime_fifo_depth_eff": str(fifo_depth),
        "runtime_fifo_age_limit": "0",
        "runtime_prefetch_throttle_cycles": "0",
        "runtime_scheduler_policy": "0",
        "score": str(score),
    }


def rows() -> list[dict[str, str]]:
    data: list[dict[str, str]] = []
    score = 0
    for workload, rtl_top, angle in WORKLOADS:
        candidates = [
            ("timing_safe_default", 8, 8, 16, 2, 2, 8, 16),
            ("lead32", 8, 8, 32, 2, 4, 16, 32),
            ("lead64", 8, 8, 32, 2, 4, 16, 64),
            ("lead128", 8, 8, 32, 2, 4, 16, 128),
            ("wide_tile_risk", 16, 8, 32, 2, 4, 16, 64),
        ]
        for candidate in candidates:
            name, tile_w, tile_h, set_num, way_num, merge_max_x, fifo_depth, lead_pixels = candidate
            data.append(
                row(
                    workload,
                    rtl_top,
                    angle,
                    name,
                    tile_w,
                    tile_h,
                    set_num,
                    way_num,
                    merge_max_x,
                    fifo_depth,
                    lead_pixels,
                    score,
                )
            )
            score += 1
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="configs/rtl_shortlist_proxy1024_targeted.csv")
    args = parser.parse_args()
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = rows()
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(data[0].keys()))
        writer.writeheader()
        writer.writerows(data)
    print(f"{path} rows={len(data)}")


if __name__ == "__main__":
    main()
