#!/usr/bin/env python3
"""Generate the first baseline workload matrix without running RTL simulations."""

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
ANGLES = [0, 1, 3, 5, 15, 30, 45, 60, 75, 90]
STRIDES = [
    ("packed", 0, 0, 0),
    ("aligned64", 64, 0, 0),
    ("unaligned_padded", 64, 0, 3),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="sim_out/cache_baseline/baseline_workloads.csv")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "workload_id",
        "size_class",
        "src_w",
        "src_h",
        "dst_w",
        "dst_h",
        "angle_deg",
        "stride_mode",
        "stride_pad",
        "stride_align_bytes",
        "base_unalign_bytes",
        "status",
    ]
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for size_name, src_w, src_h, dst_w, dst_h in SIZES:
            for angle in ANGLES:
                for stride_name, stride_align, stride_pad, base_unalign in STRIDES:
                    writer.writerow({
                        "workload_id": f"{size_name}_a{angle}_{stride_name}",
                        "size_class": size_name,
                        "src_w": src_w,
                        "src_h": src_h,
                        "dst_w": dst_w,
                        "dst_h": dst_h,
                        "angle_deg": angle,
                        "stride_mode": stride_name,
                        "stride_pad": stride_pad,
                        "stride_align_bytes": stride_align,
                        "base_unalign_bytes": base_unalign,
                        "status": "defined_not_run",
                    })
    print(out)


if __name__ == "__main__":
    main()
