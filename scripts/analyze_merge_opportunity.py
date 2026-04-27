#!/usr/bin/env python3
"""Compute merge opportunity derived metrics from RTL shortlist results."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def val(row: dict[str, str], *keys: str) -> float:
    for key in keys:
        raw = row.get(key, "")
        if raw != "":
            try:
                return float(raw)
            except ValueError:
                return 0.0
    return 0.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--out-dir", default="sim_out/merge_opportunity")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    with Path(args.input).open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    out_rows = []
    for row in rows:
        candidates = max(1.0, val(row, "analytic_candidates"))
        tile_w = max(1.0, val(row, "tile_w"))
        tile_h = max(1.0, val(row, "tile_h"))
        useful_bytes = max(1.0, val(row, "ext_useful_sectors") * tile_w * tile_h)
        out = {
            "workload": row.get("stage_workload", row.get("workload_id", "")),
            "candidate_class": row.get("candidate_class", ""),
            "policy": row.get("runtime_scheduler_policy", ""),
            "cycles": row.get("total_cycles_rtl", ""),
            "same_row_opportunity_ratio": f"{val(row, 'ext_fifo_same_row_adj') / candidates:.6f}",
            "reverse_x_opportunity_ratio": f"{val(row, 'ext_fifo_reverse_x_adj') / candidates:.6f}",
            "missed_merge_ratio": f"{val(row, 'ext_merge_opp_missed') / candidates:.6f}",
            "read_amplification": f"{val(row, 'ext_read_bytes') / useful_bytes:.6f}",
            "prefetch_usefulness": f"{val(row, 'hits') / max(1.0, val(row, 'prefetches')):.6f}",
            "merge_hist": row.get("ext_merge_hist", ""),
            "evict_unused": row.get("ext_evict_unused", ""),
            "sample_stall": row.get("ext_sample_stall", ""),
            "read_busy": row.get("ext_read_busy", ""),
        }
        out_rows.append(out)
    csv_path = out_dir / "analysis_stage1.csv"
    if out_rows:
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()))
            writer.writeheader()
            writer.writerows(out_rows)
    interesting = sorted(out_rows, key=lambda r: float(r["missed_merge_ratio"]), reverse=True)[:12]
    lines = ["# Merge Opportunity Analysis Stage1", "", f"- Rows: {len(out_rows)}", ""]
    lines += ["| Workload | Candidate | Missed merge | Same row | Reverse X | Read amp | Note |", "| --- | --- | ---: | ---: | ---: | ---: | --- |"]
    for row in interesting:
        note = "row-bucket candidate" if float(row["missed_merge_ratio"]) > 0.2 else "observe"
        if float(row["read_amplification"]) > 1.5:
            note += "; read amplification risk"
        lines.append(
            f"| `{row['workload']}` | `{row['candidate_class']}` | {row['missed_merge_ratio']} | "
            f"{row['same_row_opportunity_ratio']} | {row['reverse_x_opportunity_ratio']} | "
            f"{row['read_amplification']} | {note} |"
        )
    (out_dir / "analysis_stage1.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(csv_path)


if __name__ == "__main__":
    main()
