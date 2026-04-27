#!/usr/bin/env python3
"""Compare fast-model CSV rows with a small RTL result CSV."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def parse_params_string(text: str) -> dict[str, str]:
    params: dict[str, str] = {}
    if not text:
        return params
    for token in text.split(","):
        token = token.strip()
        if "x" in token and token[0].isdigit():
            tile_w, tile_h = token.split("x", 1)
            params["tile_w"] = tile_w
            params["tile_h"] = tile_h
        elif token.startswith("m"):
            params["merge_max_x"] = token[1:]
        elif token.startswith("f"):
            params["fifo_depth"] = token[1:]
        elif token.startswith("l"):
            params["lead_pixels"] = token[1:]
    return params


def normalized_row(row: dict[str, str]) -> dict[str, str]:
    result = dict(row)
    result.update(parse_params_string(row.get("params", "")))
    if "prefetch_mode" not in result or result.get("prefetch_mode", "") == "":
        result["prefetch_mode"] = "on"
    return result


def row_key(row: dict[str, str], include_params: bool) -> tuple[str, ...]:
    norm = normalized_row(row)
    base = (norm["workload_id"], norm.get("prefetch_mode", "on"))
    param_fields = ("tile_w", "tile_h", "merge_max_x", "fifo_depth", "lead_pixels")
    if include_params and all(norm.get(field, "") != "" for field in param_fields):
        return base + tuple(norm[field] for field in param_fields)
    return base


def get_value(row: dict[str, str], *names: str, default: str = "") -> str:
    for name in names:
        value = row.get(name, "")
        if value != "":
            return value
    return default


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True)
    parser.add_argument("--rtl", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--summary")
    parser.add_argument("--max-error-pct", type=float, default=10.0,
                        help="Error threshold used to mark model/RTL rows as trusted.")
    parser.add_argument("--fail-on-threshold", action="store_true",
                        help="Return non-zero if any compared row exceeds --max-error-pct.")
    return parser.parse_args()


def angle_bucket(angle: float) -> str:
    if angle in (0.0, 90.0):
        return "orthogonal"
    if angle <= 15.0:
        return "small_angle"
    if 30.0 <= angle <= 60.0:
        return "diagonal"
    return "steep_angle"


def prefetch_bucket(row: dict[str, str]) -> str:
    mode = row.get("prefetch_mode", "")
    if mode:
        return mode
    workload = row.get("stage_workload", row.get("workload_id", ""))
    if workload.endswith("_off"):
        return "off"
    return "on"


def empirical_key(row: dict[str, str]) -> tuple[str, ...]:
    return (
        angle_bucket(float(row.get("angle_deg", 0) or 0)),
        str(int(float(row.get("angle_deg", 0) or 0))),
        row.get("frame_class", "unknown"),
        prefetch_bucket(row),
        row.get("tile_w", ""),
        row.get("tile_h", ""),
        row.get("set_num", ""),
        row.get("way_num", ""),
        row.get("merge_max_x", ""),
        row.get("fifo_depth", ""),
        row.get("lead_pixels", ""),
        row.get("runtime_scheduler_policy", row.get("runtime_policy", "")),
        row.get("runtime_merge_min_x", row.get("runtime_merge_min", "")),
        row.get("runtime_fifo_age_limit", row.get("runtime_fifo_age", "")),
        row.get("runtime_prefetch_throttle_cycles", row.get("runtime_throttle", "")),
    )


def compare_stage1_json(args: argparse.Namespace, model_path: Path) -> bool:
    payload = json.loads(model_path.read_text(encoding="utf-8"))
    if payload.get("mode") not in ("stage1_empirical_bucket_average", "stage_empirical_param_bucket_average"):
        return False
    groups = payload.get("groups", {})
    param_aware = payload.get("mode") == "stage_empirical_param_bucket_average"
    rows = []
    with Path(args.rtl).open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            cycles_s = get_value(row, "total_cycles_rtl", "rtl_cycles", default="")
            if cycles_s == "":
                continue
            status = row.get("rtl_status", "")
            if status and not status.startswith(("pass", "parsed_pass")):
                continue
            if param_aware:
                key = "|".join(empirical_key(row))
            else:
                key = "|".join([
                    angle_bucket(float(row.get("angle_deg", 0) or 0)),
                    row.get("frame_class", "unknown"),
                    row.get("candidate_class", "unknown"),
                ])
            model_cycles = float(groups.get(key, {}).get("avg_cycles", 0.0))
            model_count = int(groups.get(key, {}).get("count", 0))
            rtl_cycles = float(cycles_s)
            error_pct = (model_cycles - rtl_cycles) * 100.0 / rtl_cycles if rtl_cycles else 0.0
            rows.append({
                "workload_id": row.get("stage_workload", row.get("workload_id", "")),
                "angle_bucket": key.split("|")[0],
                "frame_class": row.get("frame_class", ""),
                "candidate_class": row.get("candidate_class", ""),
                "tile_w": row.get("tile_w", ""),
                "tile_h": row.get("tile_h", ""),
                "merge_max_x": row.get("merge_max_x", ""),
                "fifo_depth": row.get("fifo_depth", ""),
                "lead_pixels": row.get("lead_pixels", ""),
                "model_cycles": f"{model_cycles:.0f}",
                "model_count": str(model_count),
                "rtl_cycles": f"{rtl_cycles:.0f}",
                "error_pct": f"{error_pct:.2f}",
                "abs_error_pct": f"{abs(error_pct):.2f}",
                "within_threshold": "1" if abs(error_pct) <= args.max_error_pct else "0",
                "trusted_for_cycles": "1" if abs(error_pct) <= args.max_error_pct else "0",
            })
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if rows:
        with out.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
    summary = Path(args.summary or out.with_name("model_rtl_error_summary_stage1.md"))
    bucket_stats: dict[tuple[str, str], list[float]] = {}
    bucket_counts: dict[tuple[str, str], list[int]] = {}
    for row in rows:
        bucket_stats.setdefault((row["angle_bucket"], row["frame_class"]), []).append(float(row["abs_error_pct"]))
        bucket_counts.setdefault((row["angle_bucket"], row["frame_class"]), []).append(int(row.get("model_count", "0")))
    lines = [
        "# Model RTL Error Summary Stage1",
        "",
        f"- Compared rows: {len(rows)}",
        f"- Threshold: {args.max_error_pct:.2f}%",
        f"- Model type: {payload.get('mode')}; do not extrapolate to 7200->600.",
        "- In parameter-aware mode, low error means the row matched an observed parameter bucket. It is not proof of prediction quality for unseen parameters.",
        "",
        "| Angle bucket | Frame bucket | Max abs error | Min group count | Status |",
        "| --- | --- | ---: | ---: | --- |",
    ]
    for key, values in sorted(bucket_stats.items()):
        max_err = max(values)
        min_count = min(bucket_counts.get(key, [0]))
        if max_err > args.max_error_pct:
            status = "coarse only"
        elif min_count < 2:
            status = "lookup only"
        else:
            status = "calibrated bucket"
        lines.append(f"| `{key[0]}` | `{key[1]}` | {max_err:.2f}% | {min_count} | {status} |")
    summary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out)
    if args.fail_on_threshold and any(row["within_threshold"] != "1" for row in rows):
        raise SystemExit(2)
    return True


def main() -> None:
    args = parse_args()
    model_path = Path(args.model)
    if model_path.suffix.lower() == ".json" and compare_stage1_json(args, model_path):
        return
    if not args.summary:
        raise SystemExit("--summary is required when comparing model CSV input.")
    rtl_rows = {}
    with Path(args.rtl).open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            norm = normalized_row(row)
            has_params = any(norm.get(field, "") != "" for field in ("tile_w", "tile_h", "merge_max_x", "fifo_depth", "lead_pixels"))
            rtl_rows[row_key(norm, has_params)] = norm

    rows = []
    with Path(args.model).open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            full_key = row_key(row, True)
            simple_key = row_key(row, False)
            if full_key in rtl_rows:
                key = full_key
            elif simple_key in rtl_rows:
                key = simple_key
            else:
                continue
            rtl = rtl_rows[key]
            model_cycles = int(float(row["total_cycles_est"]))
            raw_cycles = int(float(row.get("raw_total_cycles_est", model_cycles)))
            rtl_cycles = int(float(get_value(rtl, "rtl_cycles", "total_cycles_rtl", default="0")))
            error_pct = (model_cycles - rtl_cycles) * 100.0 / rtl_cycles if rtl_cycles else 0.0
            abs_error_pct = abs(error_pct)
            rows.append({
                "workload_id": key[0],
                "prefetch_mode": key[1],
                "tile_w": row.get("tile_w", ""),
                "tile_h": row.get("tile_h", ""),
                "merge_max_x": row.get("merge_max_x", ""),
                "fifo_depth": row.get("fifo_depth", ""),
                "lead_pixels": row.get("lead_pixels", ""),
                "raw_model_cycles": raw_cycles,
                "model_cycles": model_cycles,
                "rtl_cycles": rtl_cycles,
                "error_pct": f"{error_pct:.2f}",
                "abs_error_pct": f"{abs_error_pct:.2f}",
                "within_threshold": "1" if abs_error_pct <= args.max_error_pct else "0",
                "rtl_reads": get_value(rtl, "rtl_reads", "reads"),
                "rtl_misses": get_value(rtl, "rtl_misses", "misses"),
                "rtl_prefetches": get_value(rtl, "rtl_prefetches", "prefetches"),
                "rtl_hits": get_value(rtl, "rtl_hits", "hits"),
                "model_misses": row.get("miss_count", ""),
                "model_prefetch_fill": row.get("prefetch_fill", ""),
                "rtl_frame_overhead": row.get("rtl_frame_overhead", "0"),
                "rtl_raw_cycle_scale": row.get("rtl_raw_cycle_scale", "1"),
                "rtl_dst_pixel_extra_cycles": row.get("rtl_dst_pixel_extra_cycles", "0"),
                "rtl_demand_miss_extra_cycles": row.get("rtl_demand_miss_extra_cycles", "0"),
                "rtl_prefetch_fill_extra_cycles": row.get("rtl_prefetch_fill_extra_cycles", "0"),
                "rtl_read_start_extra_cycles": row.get("rtl_read_start_extra_cycles", "0"),
                "rtl_read_sector_extra_cycles": row.get("rtl_read_sector_extra_cycles", "0"),
                "unique_source_tiles": row.get("unique_source_tiles", ""),
                "prefetch_miss_floor_added": row.get("prefetch_miss_floor_added", ""),
                "prefetch_read_amp_added": row.get("prefetch_read_amp_added", ""),
            })

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if rows:
        with out.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
    else:
        out.write_text("", encoding="utf-8")

    max_abs_error = max((float(row["abs_error_pct"]) for row in rows), default=0.0)
    failing_rows = [row for row in rows if row["within_threshold"] != "1"]
    trusted = not failing_rows

    summary_lines = [
        "# Model vs RTL Error Summary",
        "",
        f"- Compared rows: {len(rows)}",
        f"- Error threshold: {args.max_error_pct:.2f}%",
        f"- Max abs error: {max_abs_error:.2f}%",
        f"- Trusted for RTL shortlist expansion: {'yes' if trusted else 'no'}",
        "",
    ]
    for row in rows:
        param_text = ""
        if row.get("tile_w", ""):
            param_text = (
                f" params={row['tile_w']}x{row['tile_h']},m{row['merge_max_x']},"
                f"f{row['fifo_depth']},l{row['lead_pixels']}"
            )
        summary_lines.append(
            f"- {row['workload_id']} prefetch {row['prefetch_mode']}: "
            f"raw={row['raw_model_cycles']}, model={row['model_cycles']}, "
            f"rtl={row['rtl_cycles']}, error={row['error_pct']}%, "
            f"within_threshold={row['within_threshold']}{param_text}"
        )
    Path(args.summary).write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    print(out)
    if args.fail_on_threshold and failing_rows:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
