#!/usr/bin/env python3
"""Generate a tiny proxy1024 FIFO-depth refinement matrix.

Only one structural parameter changes here versus the latest lead-refine
candidate set: analytic FIFO depth is increased from 16 to 32. Tile geometry,
set/way count, merge limit, and scheduler policy stay fixed.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


CASES = [
    # workload, top, angle, lead
    ("proxy1024_r0", "tb_image_geo_top_perf_single_proxy_rotate0_on", 0, 64),
    ("proxy1024_r0", "tb_image_geo_top_perf_single_proxy_rotate0_on", 0, 96),
    ("proxy1024_r75", "tb_image_geo_top_perf_single_proxy_rotate75_on", 75, 32),
    ("proxy1024_r90", "tb_image_geo_top_perf_single_proxy_rotate90_on", 90, 64),
    ("proxy1024_r90", "tb_image_geo_top_perf_single_proxy_rotate90_on", 90, 96),
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="configs/rtl_shortlist_proxy1024_fifo_refine.csv")
    args = parser.parse_args()
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    for score, (workload, rtl_top, angle, lead) in enumerate(CASES):
        rows.append({
            "workload_id": f"{workload}_fifo32_lead{lead}",
            "stage_workload": workload,
            "candidate_class": f"fifo32_lead{lead}",
            "angle_deg": str(angle),
            "frame_class": "proxy1024",
            "rtl_top": rtl_top,
            "tile_w": "8",
            "tile_h": "8",
            "set_num": "32",
            "way_num": "2",
            "merge_max_x": "4",
            "fifo_depth": "32",
            "lead_pixels": str(lead),
            "runtime_lead_pixels": str(lead),
            "runtime_merge_max_x_eff": "4",
            "runtime_merge_min_x": "1",
            "runtime_fifo_depth_eff": "32",
            "runtime_fifo_age_limit": "0",
            "runtime_prefetch_throttle_cycles": "0",
            "runtime_scheduler_policy": "0",
            "score": str(score),
        })
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"{path} rows={len(rows)}")


if __name__ == "__main__":
    main()
