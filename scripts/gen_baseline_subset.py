#!/usr/bin/env python3
"""Generate a bounded baseline subset for quick prefetch off/on comparison."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


SIZES = [
    ("large_square", 7200, 7200, 600, 600),
    ("large_wide", 7200, 4096, 600, 600),
    ("large_tall", 4096, 7200, 600, 600),
    ("hd", 1920, 1080, 600, 600),
    ("mid_square", 1024, 1024, 600, 600),
]
ANGLES = [0, 15, 45, 75, 90]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="sim_out/cache_baseline/baseline_subset_workloads.csv")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "workload_id",
                "src_w",
                "src_h",
                "dst_w",
                "dst_h",
                "angle_deg",
                "stride_pad",
            ],
        )
        writer.writeheader()
        for size_name, src_w, src_h, dst_w, dst_h in SIZES:
            for angle in ANGLES:
                writer.writerow({
                    "workload_id": f"{size_name}_a{angle}_packed",
                    "src_w": src_w,
                    "src_h": src_h,
                    "dst_w": dst_w,
                    "dst_h": dst_h,
                    "angle_deg": angle,
                    "stride_pad": 0,
                })
    print(out)


if __name__ == "__main__":
    main()
