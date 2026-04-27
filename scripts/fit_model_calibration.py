#!/usr/bin/env python3
"""Fit run_cache_sweep RTL calibration knobs from model and RTL CSV files."""

from __future__ import annotations

import argparse
import csv
import json
import math
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


def get_value(row: dict[str, str], *names: str, default: str = "0") -> str:
    for name in names:
        value = row.get(name, "")
        if value != "":
            return value
    return default


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", help="Fast-model CSV with raw_total_cycles_est.")
    parser.add_argument("--rtl", help="RTL CSV from extract_perf_single.py.")
    parser.add_argument("--out-json")
    parser.add_argument("--out-md")
    parser.add_argument("--input", help="Stage1 RTL-only CSV; writes empirical bucket calibration.")
    parser.add_argument("--output", help="Alias for --out-json in Stage1 RTL-only mode.")
    parser.add_argument("--feature-set", choices=["legacy", "tilelead", "rich"], default="legacy")
    parser.add_argument("--ridge", type=float, default=1e-6,
                        help="Small diagonal regularization for near-collinear calibration features.")
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


def run_stage1_empirical(args: argparse.Namespace) -> None:
    in_path = Path(args.input)
    out_json = Path(args.output or args.out_json or "sim_out/model_calibration_stage1/linear_calibration_params_stage1.json")
    out_md = Path(args.out_md or out_json.with_suffix(".md"))
    rows = []
    with in_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            cycles = get_value(row, "total_cycles_rtl", "rtl_cycles", default="")
            if cycles == "":
                continue
            status = row.get("rtl_status", "")
            if status and not status.startswith(("pass", "parsed_pass")):
                continue
            rows.append(row)
    groups: dict[tuple[str, ...], list[float]] = {}
    for row in rows:
        bucket = empirical_key(row)
        groups.setdefault(bucket, []).append(float(get_value(row, "total_cycles_rtl", "rtl_cycles", default="0")))
    payload = {
        "mode": "stage_empirical_param_bucket_average",
        "key_fields": [
            "angle_bucket",
            "angle_deg",
            "frame_class",
            "prefetch_mode",
            "tile_w",
            "tile_h",
            "set_num",
            "way_num",
            "merge_max_x",
            "fifo_depth",
            "lead_pixels",
            "runtime_scheduler_policy",
            "runtime_merge_min_x",
            "runtime_fifo_age_limit",
            "runtime_prefetch_throttle_cycles",
        ],
        "note": "Parameter-aware empirical fit for shortlist calibration only; not a physical model and not valid for 7200->600 extrapolation.",
        "groups": {
            "|".join(key): {
                "avg_cycles": sum(values) / len(values),
                "count": len(values),
            }
            for key, values in sorted(groups.items())
        },
    }
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# Parameter-Aware Empirical Model Calibration",
        "",
        f"- Input rows: {len(rows)}",
        f"- Groups: {len(groups)}",
        "- Status: empirical fit only; parameter buckets with sparse rows are coarse-screen only.",
        "",
        "| Angle bucket | Frame bucket | Params | Count | Avg cycles |",
        "| --- | --- | --- | ---: | ---: |",
    ]
    for key, values in sorted(groups.items()):
        params = (
            f"angle{key[1]},{key[3]},{key[4]}x{key[5]},set{key[6]},way{key[7]},m{key[8]},"
            f"f{key[9]},l{key[10]},p{key[11]},mm{key[12]},age{key[13]},thr{key[14]}"
        )
        lines.append(f"| `{key[0]}` | `{key[2]}` | `{params}` | {len(values)} | {sum(values)/len(values):.0f} |")
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out_json)


def solve_linear_system(a: list[list[float]], b: list[float]) -> list[float]:
    n = len(b)
    aug = [row[:] + [rhs] for row, rhs in zip(a, b)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if abs(aug[pivot][col]) < 1e-9:
            raise SystemExit("Singular calibration matrix; add more diverse calibration rows.")
        aug[col], aug[pivot] = aug[pivot], aug[col]
        div = aug[col][col]
        aug[col] = [x / div for x in aug[col]]
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col]
            aug[row] = [x - factor * y for x, y in zip(aug[row], aug[col])]
    return [aug[i][-1] for i in range(n)]


def least_squares(x_rows: list[list[float]], y_values: list[float], ridge: float) -> list[float]:
    cols = len(x_rows[0])
    xtx = [[0.0 for _ in range(cols)] for _ in range(cols)]
    xty = [0.0 for _ in range(cols)]
    for x, y in zip(x_rows, y_values):
        for i in range(cols):
            xty[i] += x[i] * y
            for j in range(cols):
                xtx[i][j] += x[i] * x[j]
    for i in range(cols):
        xtx[i][i] += ridge
    return solve_linear_system(xtx, xty)


def feature_values(row: dict[str, str]) -> dict[str, float]:
    angle = float(row.get("angle_deg", 0.0) or 0.0)
    diag = abs(math.sin(math.radians(angle * 2.0)))
    orth = abs(math.cos(math.radians(angle * 2.0)))
    dst_pixels = float(int(row["dst_w"]) * int(row["dst_h"]))
    dst_w = float(row["dst_w"])
    dst_h = float(row["dst_h"])
    tile_w = float(row["tile_w"])
    tile_h = float(row["tile_h"])
    lead = float(row["lead_pixels"])
    fifo = float(row.get("fifo_depth", 0) or 0)
    merge = float(row.get("merge_max_x", 0) or 0)
    raw = float(row["raw_total_cycles_est"])
    miss = float(row.get("miss_count", 0) or 0)
    pref = float(row.get("prefetch_fill", 0) or 0)
    sector_bytes = max(1.0, tile_w * tile_h)
    sectors = float(row.get("read_bytes", 0) or 0) / sector_bytes
    read_bytes = float(row.get("read_bytes", 0) or 0)
    unique_tiles = float(row.get("unique_source_tiles", 0) or 0)
    useful_source_bytes = max(1.0, unique_tiles * sector_bytes)
    prefetch_hit = float(row.get("prefetch_hit", row.get("prefetch_hits", 0)) or 0)
    read_busy = float(row.get("read_busy_cycles", row.get("ext_read_busy", 0)) or 0)
    sample_stall = float(row.get("sample_stall_cycles", row.get("ext_sample_stall", 0)) or 0)
    lead_coverage = lead / max(1.0, dst_w)
    prefetch_hit_coverage = prefetch_hit / max(1.0, dst_pixels)
    read_amplification = read_bytes / useful_source_bytes
    merge_efficiency = float(row.get("merge_efficiency", 0) or 0)
    if merge_efficiency == 0.0 and merge > 0.0:
        merge_efficiency = min(1.0, max(0.0, sectors / max(1.0, float(row.get("prefetch_fill", 0) or 0) + miss) / merge))
    stall_per_read_busy = sample_stall / max(1.0, read_busy)
    small = 1.0 if dst_pixels <= 2304.0 else 0.0
    mid = 1.0 - small
    tile16 = 1.0 if int(tile_w) == 16 else 0.0
    tileh16 = 1.0 if int(tile_h) == 16 else 0.0
    tileh8 = 1.0 if int(tile_h) == 8 else 0.0
    shortlead = 1.0 if lead <= 16.0 else 0.0
    return {
        "bias": 1.0,
        "raw": raw,
        "pix": dst_pixels,
        "dst_w": dst_w,
        "dst_h": dst_h,
        "sqrtpix": math.sqrt(dst_pixels),
        "miss": miss,
        "pref": pref,
        "sectors": sectors,
        "diag": diag,
        "orth": orth,
        "tile_h": tile_h,
        "tile_w": tile_w,
        "lead": lead,
        "fifo": fifo,
        "merge": merge,
        "diag_sectors": diag * sectors,
        "orth_pref": orth * pref,
        "diag_pref": diag * pref,
        "small": small,
        "mid": mid,
        "small_diag": small * diag,
        "mid_diag": mid * diag,
        "tile16_diag": tile16 * diag,
        "tileh16_diag": tileh16 * diag,
        "tileh8_diag": tileh8 * diag,
        "shortlead_mid": shortlead * mid,
        "shortlead_orth": shortlead * orth,
        "lead_coverage": lead_coverage,
        "prefetch_hit_coverage": prefetch_hit_coverage,
        "read_amplification": read_amplification,
        "merge_efficiency": merge_efficiency,
        "stall_per_read_busy": stall_per_read_busy,
        "diag_read_amp": diag * read_amplification,
        "orth_lead_coverage": orth * lead_coverage,
        "diag_merge_eff": diag * merge_efficiency,
    }


FEATURE_SETS = {
    "legacy": [
        "bias",
        "raw",
        "pix",
        "miss",
        "pref",
        "sectors",
    ],
    "tilelead": [
        "bias",
        "raw",
        "pix",
        "miss",
        "pref",
        "sectors",
        "diag",
        "orth",
        "tile_h",
        "tile_w",
        "lead",
        "diag_sectors",
        "tileh16_diag",
        "tileh8_diag",
        "shortlead_mid",
        "shortlead_orth",
    ],
    "rich": [
        "bias",
        "raw",
        "pix",
        "dst_w",
        "dst_h",
        "sqrtpix",
        "miss",
        "pref",
        "sectors",
        "diag",
        "orth",
        "tile_h",
        "tile_w",
        "lead",
        "fifo",
        "merge",
        "diag_sectors",
        "orth_pref",
        "diag_pref",
        "small",
        "mid",
        "small_diag",
        "mid_diag",
        "tile16_diag",
        "tileh16_diag",
        "tileh8_diag",
        "shortlead_mid",
        "shortlead_orth",
        "lead_coverage",
        "prefetch_hit_coverage",
        "read_amplification",
        "merge_efficiency",
        "stall_per_read_busy",
        "diag_read_amp",
        "orth_lead_coverage",
        "diag_merge_eff",
    ],
}


def main() -> None:
    args = parse_args()
    if args.input:
        run_stage1_empirical(args)
        return
    if not (args.model and args.rtl and args.out_json and args.out_md):
        raise SystemExit("Either use --input/--output for Stage1 mode, or provide --model --rtl --out-json --out-md.")
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
                rows.append((row, rtl_rows[full_key], full_key))
            elif simple_key in rtl_rows:
                rows.append((row, rtl_rows[simple_key], simple_key))

    if len(rows) < 6:
        raise SystemExit("Need at least 6 matched rows for the current calibration feature set.")

    x_rows = []
    y_values = []
    keys = []
    names = FEATURE_SETS[args.feature_set]
    for model, rtl, key in rows:
        features = feature_values(model)
        x_rows.append([features[name] for name in names])
        y_values.append(float(get_value(rtl, "rtl_cycles", "total_cycles_rtl")))
        keys.append(key)

    coef = least_squares(x_rows, y_values, args.ridge)
    params = {
        "feature_set": args.feature_set,
        "features": {name: value for name, value in zip(names, coef)},
    }

    predictions = []
    for key, x, y in zip(keys, x_rows, y_values):
        pred = sum(a * b for a, b in zip(coef, x))
        err = (pred - y) * 100.0 / y if y else 0.0
        predictions.append((key, pred, y, err))

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(params, indent=2) + "\n", encoding="utf-8")

    max_abs = max((abs(item[3]) for item in predictions), default=0.0)
    lines = [
        "# Fast Model Calibration Fit",
        "",
        f"- Matched rows: {len(predictions)}",
        f"- Feature set: {args.feature_set}",
        f"- Max abs error: {max_abs:.2f}%",
        "",
        "## Parameters",
        "",
    ]
    for name in names:
        lines.append(f"- `{name}` = `{params['features'][name]:.6f}`")
    lines.extend(["", "## Rows", ""])
    for key, pred, actual, err in predictions:
        lines.append(
            f"- `{'/'.join(key)}`: "
            f"pred={pred:.0f}, rtl={actual:.0f}, error={err:.2f}%"
        )
    Path(args.out_md).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out_json)


if __name__ == "__main__":
    main()
