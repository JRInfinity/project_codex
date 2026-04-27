#!/usr/bin/env python3
"""Generate a bounded proxy1024 RTL shortlist matrix.

This is intentionally small: it is for model calibration, not for a full
workload matrix or final parameter recommendation.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


WORKLOADS = [
    ("proxy1024_r0", "tb_image_geo_top_perf_single_proxy_rotate0_on", 0),
    ("proxy1024_r15", "tb_image_geo_top_perf_single_proxy_rotate15_on", 15),
    ("proxy1024_r45", "tb_image_geo_top_perf_single_proxy_rotate45_on", 45),
    ("proxy1024_r75", "tb_image_geo_top_perf_single_proxy_rotate75_on", 75),
    ("proxy1024_r90", "tb_image_geo_top_perf_single_proxy_rotate90_on", 90),
]


def structural(angle: int, rank: int) -> dict[str, int]:
    if rank == 0:
        return dict(tile_w=8, tile_h=8, set_num=16, way_num=2, merge_max_x=2, fifo_depth=8, lead_pixels=16)
    if angle in (0, 90):
        if rank == 1:
            return dict(tile_w=16, tile_h=16, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=16)
        return dict(tile_w=8, tile_h=8, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)
    if angle == 45:
        if rank == 1:
            return dict(tile_w=16, tile_h=8, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)
        return dict(tile_w=8, tile_h=8, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)
    if angle == 75:
        if rank == 1:
            return dict(tile_w=16, tile_h=8, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)
        return dict(tile_w=16, tile_h=16, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)
    if rank == 1:
        return dict(tile_w=8, tile_h=8, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)
    return dict(tile_w=16, tile_h=16, set_num=32, way_num=2, merge_max_x=4, fifo_depth=16, lead_pixels=64)


def rows() -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    score = 0
    for workload, rtl_top, angle in WORKLOADS:
        candidates = [
            ("default", structural(angle, 0), dict(policy=0, merge_min=1, age=0, throttle=0)),
            ("model_top1", structural(angle, 1), dict(policy=0, merge_min=1, age=0, throttle=0)),
            ("model_top2", structural(angle, 2), dict(policy=0, merge_min=1, age=0, throttle=0)),
            ("policy1_merge_min_age", structural(angle, 0), dict(policy=1, merge_min=4, age=200, throttle=0)),
            ("sanity_bad", dict(tile_w=32, tile_h=16, set_num=16, way_num=2, merge_max_x=1, fifo_depth=8, lead_pixels=512),
             dict(policy=0, merge_min=1, age=0, throttle=0)),
        ]
        for candidate, struct, sched in candidates:
            row = {
                "workload_id": f"{workload}_{candidate}",
                "stage_workload": workload,
                "candidate_class": candidate,
                "angle_deg": str(angle),
                "frame_class": "proxy1024",
                "rtl_top": rtl_top,
                "tile_w": str(struct["tile_w"]),
                "tile_h": str(struct["tile_h"]),
                "set_num": str(struct["set_num"]),
                "way_num": str(struct["way_num"]),
                "merge_max_x": str(struct["merge_max_x"]),
                "fifo_depth": str(struct["fifo_depth"]),
                "lead_pixels": str(struct["lead_pixels"]),
                "runtime_lead_pixels": str(struct["lead_pixels"]),
                "runtime_merge_max_x_eff": str(struct["merge_max_x"]),
                "runtime_merge_min_x": str(sched["merge_min"]),
                "runtime_fifo_depth_eff": str(struct["fifo_depth"]),
                "runtime_fifo_age_limit": str(sched["age"]),
                "runtime_prefetch_throttle_cycles": str(sched["throttle"]),
                "runtime_scheduler_policy": str(sched["policy"]),
                "score": str(score),
            }
            out.append(row)
            score += 1
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="configs/rtl_shortlist_proxy1024.csv")
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
