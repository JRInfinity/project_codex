#!/usr/bin/env python3
"""Extract PERF_SINGLE lines from xsim logs into a compact CSV."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


PERF_RE = re.compile(
    r"PERF_SINGLE case=(?P<workload_id>\S+) prefetch=(?P<prefetch_bit>[01]) "
    r"src=(?P<src_w>\d+)x(?P<src_h>\d+) dst=(?P<dst_w>\d+)x(?P<dst_h>\d+) "
    r".* cycles=(?P<rtl_cycles>\d+) reads=(?P<rtl_reads>\d+) "
    r"misses=(?P<rtl_misses>\d+) prefetches=(?P<rtl_prefetches>\d+) "
    r"hits=(?P<rtl_hits>\d+)"
)

STATS_RE = re.compile(r"PERF_SINGLE_STATS_EXT (?P<body>.*)")


EXTRA_FIELDS = [
    "stats_version",
    "stats_snapshot",
    "frame_cycles",
    "cache_cycles",
    "sample_req",
    "sample_accept",
    "sample_stall",
    "normal_prefetch",
    "evict_unused",
    "fifo_max",
    "read_busy",
    "read_bytes",
    "useful_sectors",
    "replacement_fail",
    "miss_lat_min",
    "miss_lat_max",
    "miss_lat_sum",
    "miss_lat_count",
    "sched_policy",
    "sched_lead",
    "sched_merge",
    "sched_fifo",
    "sched_throttle",
    "fifo_head_run",
    "fifo_same_row_adj",
    "fifo_reverse_x_adj",
    "merge_opp_missed",
    "merge_hist",
]


def parse_stats_body(body: str) -> dict[str, str]:
    stats: dict[str, str] = {}
    for token in body.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        if key == "version":
            key = "stats_version"
        elif key == "snapshot":
            key = "stats_snapshot"
        stats[key] = value
    return stats


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True)
    parser.add_argument("--input", help="Directory to scan recursively for xsim.log files.")
    parser.add_argument("logs", nargs="*")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    log_list = list(args.logs)
    if args.input:
        log_list.extend(str(path) for path in Path(args.input).rglob("xsim.log"))
    if not log_list:
        raise SystemExit("No logs provided. Use positional logs or --input <dir>.")
    rows = []
    for log_path in log_list:
        text = Path(log_path).read_text(encoding="utf-8", errors="ignore")
        pending_stats: dict[str, str] | None = None
        for line in text.splitlines():
            stats_match = STATS_RE.search(line)
            if stats_match and rows:
                rows[-1].update(parse_stats_body(stats_match.group("body")))
                pending_stats = None
                continue
            match = PERF_RE.search(line)
            if not match:
                continue
            row = match.groupdict()
            row["prefetch_mode"] = "on" if row.pop("prefetch_bit") == "1" else "off"
            if pending_stats:
                row.update(pending_stats)
            rows.append(row)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "workload_id",
        "prefetch_mode",
        "src_w",
        "src_h",
        "dst_w",
        "dst_h",
        "rtl_cycles",
        "rtl_reads",
        "rtl_misses",
        "rtl_prefetches",
        "rtl_hits",
        *EXTRA_FIELDS,
    ]
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})
    print(out)


if __name__ == "__main__":
    main()
