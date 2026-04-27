#!/usr/bin/env python3
"""Build Stage1 scheduler policy bucket summary."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path


def n(row: dict[str, str], *keys: str) -> float:
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
    parser.add_argument("--out-dir", default="sim_out/scheduler_policy_buckets")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    with Path(args.input).open(newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if r.get("candidate_class") in ("default", "policy1_merge_min_age", "policy2_throttle")]
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        groups[row.get("stage_workload", row.get("workload_id", ""))].append(row)
    out_rows = []
    for workload, items in sorted(groups.items()):
        passed = [r for r in items if r.get("rtl_status", "").startswith(("pass", "parsed_pass")) and n(r, "total_cycles_rtl") > 0]
        if not passed:
            continue
        default = next((r for r in passed if r.get("candidate_class") == "default"), passed[0])
        best = min(passed, key=lambda r: n(r, "total_cycles_rtl"))
        default_cycles = n(default, "total_cycles_rtl")
        best_cycles = n(best, "total_cycles_rtl")
        delta_pct = (best_cycles - default_cycles) * 100.0 / max(1.0, default_cycles)
        conclusion = "marginal" if abs(delta_pct) < 0.5 else ("benefit" if delta_pct < 0 else "regression")
        out_rows.append({
            "workload": workload,
            "angle": best.get("angle_deg", ""),
            "frame_class": best.get("frame_class", ""),
            "best_policy": best.get("runtime_scheduler_policy", ""),
            "best_candidate": best.get("candidate_class", ""),
            "default_cycles": f"{default_cycles:.0f}",
            "best_cycles": f"{best_cycles:.0f}",
            "delta_cycles": f"{best_cycles - default_cycles:.0f}",
            "delta_pct": f"{delta_pct:.3f}",
            "read_bytes_delta": f"{n(best, 'ext_read_bytes') - n(default, 'ext_read_bytes'):.0f}",
            "read_busy_delta": f"{n(best, 'ext_read_busy') - n(default, 'ext_read_busy'):.0f}",
            "sample_stall_delta": f"{n(best, 'ext_sample_stall') - n(default, 'ext_sample_stall'):.0f}",
            "evict_unused_delta": f"{n(best, 'ext_evict_unused') - n(default, 'ext_evict_unused'):.0f}",
            "conclusion": conclusion,
        })
    csv_path = out_dir / "policy_bucket_stage1.csv"
    if out_rows:
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()))
            writer.writeheader()
            writer.writerows(out_rows)
    lines = ["# Scheduler Policy Bucket Stage1", "", f"- Workloads: {len(out_rows)}", ""]
    lines += ["| Workload | Best policy | Default | Best | Delta % | Conclusion |", "| --- | ---: | ---: | ---: | ---: | --- |"]
    for row in out_rows:
        lines.append(
            f"| `{row['workload']}` | {row['best_policy']} | {row['default_cycles']} | "
            f"{row['best_cycles']} | {row['delta_pct']} | {row['conclusion']} |"
        )
    (out_dir / "policy_bucket_stage1.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(csv_path)


if __name__ == "__main__":
    main()
