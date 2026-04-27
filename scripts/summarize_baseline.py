#!/usr/bin/env python3
"""Summarize quick baseline CSV with prefetch off/on deltas."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="sim_out/cache_baseline/baseline_subset_fast.csv")
    parser.add_argument("--out-md", default="sim_out/cache_baseline/baseline_subset_summary.md")
    return parser.parse_args()


def to_int(row: dict[str, str], key: str) -> int:
    return int(float(row.get(key, "0") or 0))


def main() -> None:
    args = parse_args()
    path = Path(args.input)
    rows = list(csv.DictReader(path.open(newline="", encoding="utf-8")))
    grouped: dict[str, dict[str, dict[str, str]]] = {}
    for row in rows:
        grouped.setdefault(row["workload_id"], {})[row["prefetch_mode"]] = row

    lines = [
        "# Baseline Summary",
        "",
        "说明：这是快速软件模型的 baseline 结果，不是 RTL 性能结论。目标是先筛出 prefetch on/off 的趋势和明显风险点。",
        "",
        "| workload | off cycles | on cycles | delta | off miss | on miss | on read bytes | note |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    regressions = 0
    wins = 0
    ties = 0
    for workload_id in sorted(grouped):
        pair = grouped[workload_id]
        off = pair.get("off")
        on = pair.get("on")
        if not off or not on:
            continue
        off_cycles = to_int(off, "total_cycles_est")
        on_cycles = to_int(on, "total_cycles_est")
        off_miss = to_int(off, "miss_count")
        on_miss = to_int(on, "miss_count")
        on_bytes = to_int(on, "read_bytes")
        delta = on_cycles - off_cycles
        if delta < 0:
            wins += 1
            note = "prefetch faster"
        elif delta > 0:
            regressions += 1
            note = "prefetch slower"
        else:
            ties += 1
            note = "tie"
        lines.append(
            f"| `{workload_id}` | {off_cycles} | {on_cycles} | {delta:+d} | "
            f"{off_miss} | {on_miss} | {on_bytes} | {note} |"
        )
    lines.extend([
        "",
        f"- prefetch faster: {wins}",
        f"- prefetch slower: {regressions}",
        f"- prefetch tie: {ties}",
        f"- total workloads compared: {wins + regressions + ties}",
    ])
    out = Path(args.out_md)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out)


if __name__ == "__main__":
    main()
