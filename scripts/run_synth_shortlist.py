#!/usr/bin/env python3
"""Screen shortlisted cache parameters for resource and timing risk.

By default this script runs a deterministic resource estimate only. Use
--run-vivado to launch bounded Vivado synthesis for each row.
"""

from __future__ import annotations

import argparse
import csv
import subprocess
from pathlib import Path


PYNQ_Z2_BRAM36_BUDGET = 140
PYNQ_Z2_LUT_BUDGET = 53200


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="sim_out/cache_sweep/rtl_shortlist.csv")
    parser.add_argument("--out", default="sim_out/cache_sweep/synth_shortlist.csv")
    parser.add_argument("--run-vivado", action="store_true")
    parser.add_argument("--timeout-sec", type=int, default=1800)
    parser.add_argument("--part", default="xc7z020clg400-1")
    return parser.parse_args()


def estimate(row: dict[str, str]) -> dict[str, str]:
    tile_w = int(row["tile_w"])
    tile_h = int(row["tile_h"])
    set_num = int(row["set_num"])
    way_num = int(row["way_num"])
    merge_max_x = int(row["merge_max_x"])
    data_bits = tile_w * tile_h * set_num * way_num * 8
    bram36 = (data_bits + 36 * 1024 - 1) // (36 * 1024)
    tag_bits = set_num * way_num * 64
    lut_est = 2500 + set_num * way_num * 6 + way_num * 160 + merge_max_x * 220 + tag_bits // 24
    ff_est = 1800 + set_num * way_num * 8 + merge_max_x * 180
    dsp_est = 0
    timing_risk = "low"
    if way_num >= 8 or merge_max_x >= 16 or set_num >= 256:
        timing_risk = "high"
    elif way_num >= 4 and merge_max_x >= 8:
        timing_risk = "medium"
    resource_pass = bram36 <= PYNQ_Z2_BRAM36_BUDGET and lut_est <= PYNQ_Z2_LUT_BUDGET
    return {
        "LUT_est": str(lut_est),
        "FF_est": str(ff_est),
        "BRAM36_est": str(bram36),
        "URAM_est": "0",
        "DSP_est": str(dsp_est),
        "WNS": "",
        "Fmax_est": "",
        "timing_risk": timing_risk,
        "resource_pass": str(resource_pass).lower(),
        "synth_status": "estimate_only",
    }


def run_vivado(row: dict[str, str], repo: Path, args: argparse.Namespace) -> dict[str, str]:
    run_name = row.get("run_name") or (
        f"synth_tw{row['tile_w']}_th{row['tile_h']}_s{row['set_num']}_w{row['way_num']}"
    )
    out_dir = repo / "sim_out" / "cache_synth" / run_name
    out_dir.mkdir(parents=True, exist_ok=True)
    tcl = out_dir / "run_synth.tcl"
    report = out_dir / "synth_report.txt"
    tcl.write_text(
        "\n".join(
            [
                f"set_part {args.part}",
                "read_verilog -sv [glob ../../../../rtl/**/*.sv]",
                "synth_design -top image_geo_top",
                f"report_utilization -file {report.as_posix()}",
                f"report_timing_summary -file {(out_dir / 'timing_summary.txt').as_posix()}",
                "quit",
                "",
            ]
        ),
        encoding="utf-8",
    )
    try:
        completed = subprocess.run(
            ["vivado", "-mode", "batch", "-source", str(tcl)],
            cwd=out_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=args.timeout_sec,
            check=False,
        )
        return {"synth_status": "pass" if completed.returncode == 0 else f"fail:{completed.returncode}"}
    except subprocess.TimeoutExpired:
        return {"synth_status": "timeout"}


def main() -> None:
    args = parse_args()
    repo = Path(__file__).resolve().parents[1]
    in_path = repo / args.input
    out_path = repo / args.out
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with in_path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    out_rows: list[dict[str, str]] = []
    for row in rows:
        result = estimate(row)
        if args.run_vivado:
            result.update(run_vivado(row, repo, args))
        out_rows.append({**row, **result})
    fieldnames = sorted({key for row in out_rows for key in row.keys()})
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(out_rows)
    print(out_path)


if __name__ == "__main__":
    main()
