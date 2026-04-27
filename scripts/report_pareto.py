#!/usr/bin/env python3
"""Create Pareto summaries and recommendations from sweep CSV files."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fast", default="sim_out/cache_sweep/fast_model_summary.csv")
    parser.add_argument("--rtl", default="")
    parser.add_argument("--synth", default="")
    parser.add_argument("--out-dir", default="sim_out/cache_sweep")
    return parser.parse_args()


def load_csv(path: Path) -> list[dict[str, str]]:
    if not path or not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def key_for(row: dict[str, str]) -> tuple[str, str, str, str, str, str, str]:
    return (
        row["tile_w"],
        row["tile_h"],
        row["set_num"],
        row["way_num"],
        row["merge_max_x"],
        row["fifo_depth"],
        row["lead_pixels"],
    )


def better(row: dict[str, str], current: dict[str, str] | None) -> bool:
    if current is None:
        return True
    return int(float(row.get("score", row.get("total_cycles_est", "0")))) < int(
        float(current.get("score", current.get("total_cycles_est", "0")))
    )


def main() -> None:
    args = parse_args()
    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = load_csv(repo / args.fast)
    rtl_rows = load_csv(repo / args.rtl) if args.rtl else []
    synth_rows = load_csv(repo / args.synth) if args.synth else []
    synth_by_key = {key_for(row): row for row in synth_rows if {"tile_w", "tile_h", "set_num"} <= set(row)}

    best_by_workload: dict[str, dict[str, str]] = {}
    global_score: dict[tuple[str, str, str, str, str, str, str], float] = {}
    for row in rows:
        if better(row, best_by_workload.get(row["workload_id"])):
            best_by_workload[row["workload_id"]] = row
        global_score[key_for(row)] = global_score.get(key_for(row), 0.0) + float(row["score"])

    best_global_key = min(global_score, key=global_score.get) if global_score else None
    best_global = next((row for row in rows if key_for(row) == best_global_key), None) if best_global_key else None

    rec_path = out_dir / "recommendations.csv"
    fields = [
        "workload_class",
        "src_w_range",
        "src_h_range",
        "dst_w_range",
        "dst_h_range",
        "angle_range",
        "scale_x_range",
        "scale_y_range",
        "recommended_tile_w",
        "recommended_tile_h",
        "recommended_set_num",
        "recommended_way_num",
        "recommended_merge_max_x",
        "recommended_fifo_depth",
        "recommended_lead_pixels",
        "expected_cycles",
        "expected_speedup",
        "resource_estimate",
        "notes",
    ]
    with rec_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for workload_id, row in sorted(best_by_workload.items()):
            synth = synth_by_key.get(key_for(row), {})
            writer.writerow(
                {
                    "workload_class": workload_id,
                    "src_w_range": row["src_w"],
                    "src_h_range": row["src_h"],
                    "dst_w_range": row["dst_w"],
                    "dst_h_range": row["dst_h"],
                    "angle_range": row["angle_deg"],
                    "scale_x_range": f"{float(row['src_w']) / float(row['dst_w']):.3f}",
                    "scale_y_range": f"{float(row['src_h']) / float(row['dst_h']):.3f}",
                    "recommended_tile_w": row["tile_w"],
                    "recommended_tile_h": row["tile_h"],
                    "recommended_set_num": row["set_num"],
                    "recommended_way_num": row["way_num"],
                    "recommended_merge_max_x": row["merge_max_x"],
                    "recommended_fifo_depth": row["fifo_depth"],
                    "recommended_lead_pixels": row["lead_pixels"],
                    "expected_cycles": row["total_cycles_est"],
                    "expected_speedup": "",
                    "resource_estimate": f"LUT={synth.get('LUT_est', '')};BRAM36={synth.get('BRAM36_est', '')}",
                    "notes": "fast-model candidate; confirm with RTL and timing before marking proven",
                }
            )
        if best_global:
            writer.writerow(
                {
                    "workload_class": "global_default_candidate",
                    "src_w_range": "<7200",
                    "src_h_range": "<7200",
                    "dst_w_range": "<600",
                    "dst_h_range": "<600",
                    "angle_range": "0-90",
                    "scale_x_range": "mixed",
                    "scale_y_range": "mixed",
                    "recommended_tile_w": best_global["tile_w"],
                    "recommended_tile_h": best_global["tile_h"],
                    "recommended_set_num": best_global["set_num"],
                    "recommended_way_num": best_global["way_num"],
                    "recommended_merge_max_x": best_global["merge_max_x"],
                    "recommended_fifo_depth": best_global["fifo_depth"],
                    "recommended_lead_pixels": best_global["lead_pixels"],
                    "expected_cycles": "",
                    "expected_speedup": "",
                    "resource_estimate": "",
                    "notes": "minimum summed fast-model score across loaded workloads",
                }
            )

    pareto_path = out_dir / "pareto_summary.csv"
    with pareto_path.open("w", newline="", encoding="utf-8") as f:
        fields2 = ["tile_w", "tile_h", "set_num", "way_num", "merge_max_x", "fifo_depth", "lead_pixels", "summed_score"]
        writer = csv.DictWriter(f, fieldnames=fields2)
        writer.writeheader()
        for key, score in sorted(global_score.items(), key=lambda item: item[1])[:100]:
            writer.writerow(
                {
                    "tile_w": key[0],
                    "tile_h": key[1],
                    "set_num": key[2],
                    "way_num": key[3],
                    "merge_max_x": key[4],
                    "fifo_depth": key[5],
                    "lead_pixels": key[6],
                    "summed_score": int(score),
                }
            )
    print(rec_path)
    print(pareto_path)


if __name__ == "__main__":
    main()
