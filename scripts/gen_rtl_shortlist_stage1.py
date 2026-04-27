#!/usr/bin/env python3
"""Generate the bounded Stage1 RTL shortlist matrix."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


WORKLOADS = [
    ("small_rotate45_off", "tb_image_geo_top_perf_single_small_rotate45_off", 45, "small"),
    ("small_rotate45_on", "tb_image_geo_top_perf_single_small_rotate45_on", 45, "small"),
    ("cal128_r0", "tb_image_geo_top_perf_single_cal128_rotate0_on", 0, "cal128"),
    ("cal128_r15", "tb_image_geo_top_perf_single_cal128_rotate15_on", 15, "cal128"),
    ("cal128_r45", "tb_image_geo_top_perf_single_cal128_rotate45_on", 45, "cal128"),
    ("cal128_r75", "tb_image_geo_top_perf_single_cal128_rotate75_on", 75, "cal128"),
    ("cal128_r90", "tb_image_geo_top_perf_single_cal128_rotate90_on", 90, "cal128"),
    ("cal256_r0", "tb_image_geo_top_perf_single_cal256_rotate0_on", 0, "cal256"),
    ("cal256_r15", "tb_image_geo_top_perf_single_cal256_rotate15_on", 15, "cal256"),
    ("cal256_r45", "tb_image_geo_top_perf_single_cal256_rotate45_on", 45, "cal256"),
    ("cal256_r75", "tb_image_geo_top_perf_single_cal256_rotate75_on", 75, "cal256"),
    ("cal256_r90", "tb_image_geo_top_perf_single_cal256_rotate90_on", 90, "cal256"),
    ("proxy512_r0", "tb_image_geo_top_perf_single_proxy512_rotate0_on", 0, "proxy512"),
    ("proxy512_r45", "tb_image_geo_top_perf_single_proxy512_rotate45_on", 45, "proxy512"),
    ("proxy512_r75", "tb_image_geo_top_perf_single_proxy512_rotate75_on", 75, "proxy512"),
    ("proxy512_r90", "tb_image_geo_top_perf_single_proxy512_rotate90_on", 90, "proxy512"),
]


def structural_for_angle(angle: int, rank: int) -> dict[str, int]:
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


def candidate_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    score = 0
    for workload, rtl_top, angle, frame_class in WORKLOADS:
        candidates = [
            ("default", structural_for_angle(angle, 0), dict(policy=0, merge_min=1, age=0, throttle=0)),
            ("model_top1", structural_for_angle(angle, 1), dict(policy=0, merge_min=1, age=0, throttle=0)),
            ("model_top2", structural_for_angle(angle, 2), dict(policy=0, merge_min=1, age=0, throttle=0)),
            ("policy1_merge_min_age", structural_for_angle(angle, 0), dict(policy=1, merge_min=4, age=200, throttle=0)),
            ("policy2_throttle", structural_for_angle(angle, 0), dict(policy=2, merge_min=1, age=0, throttle=64)),
            ("sanity_bad", dict(tile_w=32, tile_h=16, set_num=16, way_num=2, merge_max_x=1, fifo_depth=8, lead_pixels=512),
             dict(policy=0, merge_min=1, age=0, throttle=0)),
        ]
        for candidate_class, struct, sched in candidates:
            row = {
                "workload_id": f"{workload}_{candidate_class}",
                "stage_workload": workload,
                "candidate_class": candidate_class,
                "angle_deg": str(angle),
                "frame_class": frame_class,
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
            rows.append(row)
            score += 1
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="configs/rtl_shortlist_stage1.csv")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = candidate_rows()
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"{out} rows={len(rows)}")


if __name__ == "__main__":
    main()
