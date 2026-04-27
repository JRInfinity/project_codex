#!/usr/bin/env python3
"""Add derived metrics and write a compact Stage1 RTL shortlist summary."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path


def num(row: dict[str, str], *keys: str) -> float:
    for key in keys:
        value = row.get(key, "")
        if value not in ("", None):
            try:
                return float(value)
            except ValueError:
                return 0.0
    return 0.0


def enrich(row: dict[str, str]) -> dict[str, str]:
    result = dict(row)
    tile_w = max(1.0, num(row, "tile_w"))
    tile_h = max(1.0, num(row, "tile_h"))
    useful = num(row, "ext_useful_sectors", "useful_source_sectors")
    read_bytes = num(row, "ext_read_bytes", "read_bytes_total", "read_bytes")
    prefetch_hits = num(row, "hits", "rtl_hits")
    prefetches = num(row, "prefetches", "rtl_prefetches")
    cycles = num(row, "total_cycles_rtl", "rtl_cycles")
    result["read_amplification"] = f"{read_bytes / max(1.0, useful * tile_w * tile_h):.6f}"
    result["prefetch_hit_per_dst_pixel"] = f"{prefetch_hits / max(1.0, num(row, 'ext_sample_req', 'sample_req')):.6f}"
    result["prefetch_usefulness"] = f"{prefetch_hits / max(1.0, prefetches):.6f}"
    result["miss_latency_avg"] = f"{num(row, 'ext_miss_lat_sum') / max(1.0, num(row, 'ext_miss_lat_count')):.6f}"
    result["cycles_num"] = f"{cycles:.0f}"
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--out-csv", default="sim_out/rtl_shortlist_stage1/results_enriched.csv")
    parser.add_argument("--out-md", default="sim_out/rtl_shortlist_stage1/summary.md")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    with Path(args.input).open(newline="", encoding="utf-8") as f:
        rows = [enrich(row) for row in csv.DictReader(f)]
    out_csv = Path(args.out_csv)
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    if rows:
        fields = sorted({key for row in rows for key in row})
        with out_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[row.get("stage_workload", row.get("workload_id", ""))].append(row)
    lines = ["# RTL Shortlist Stage1 Summary", "", f"- Rows: {len(rows)}", ""]
    lines += ["| Workload | Best candidate | Default cycles | Best cycles | Delta | Status |", "| --- | --- | ---: | ---: | ---: | --- |"]
    for workload in sorted(groups):
        valid = [r for r in groups[workload] if r.get("rtl_status", "").startswith(("pass", "parsed_pass")) and num(r, "cycles_num") > 0]
        if not valid:
            lines.append(f"| `{workload}` | N/A |  |  |  | no pass rows |")
            continue
        default = next((r for r in valid if r.get("candidate_class") == "default"), valid[0])
        best = min(valid, key=lambda r: num(r, "cycles_num"))
        default_cycles = num(default, "cycles_num")
        best_cycles = num(best, "cycles_num")
        delta = best_cycles - default_cycles
        lines.append(
            f"| `{workload}` | `{best.get('candidate_class','')}` | {default_cycles:.0f} | "
            f"{best_cycles:.0f} | {delta:+.0f} | {best.get('rtl_status','')} |"
        )
    Path(args.out_md).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out_csv)


if __name__ == "__main__":
    main()
