#!/usr/bin/env python3
"""Generate a tiny proxy1024 lead-refinement matrix.

Only one mechanism changes in this matrix: runtime/compile-time analytic lead.
The structural cache parameters are fixed at 8x8,set32,way2,merge4,fifo16.
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


def rows() -> list[dict[str, str]]:
    data: list[dict[str, str]] = []
    score = 0
    for workload, rtl_top, angle in WORKLOADS:
        for lead in (48, 96):
            data.append({
                "workload_id": f"{workload}_lead{lead}",
                "stage_workload": workload,
                "candidate_class": f"lead{lead}",
                "angle_deg": str(angle),
                "frame_class": "proxy1024",
                "rtl_top": rtl_top,
                "tile_w": "8",
                "tile_h": "8",
                "set_num": "32",
                "way_num": "2",
                "merge_max_x": "4",
                "fifo_depth": "16",
                "lead_pixels": str(lead),
                "runtime_lead_pixels": str(lead),
                "runtime_merge_max_x_eff": "4",
                "runtime_merge_min_x": "1",
                "runtime_fifo_depth_eff": "16",
                "runtime_fifo_age_limit": "0",
                "runtime_prefetch_throttle_cycles": "0",
                "runtime_scheduler_policy": "0",
                "score": str(score),
            })
            score += 1
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="configs/rtl_shortlist_proxy1024_lead_refine.csv")
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
