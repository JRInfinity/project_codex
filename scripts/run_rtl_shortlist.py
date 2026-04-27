#!/usr/bin/env python3
"""Run bounded RTL simulations for the top fast-model candidates."""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
from pathlib import Path


PROFILE_RE = re.compile(
    r"cycles=(?P<cycles>\d+).*reads=(?P<reads>\d+).*misses=(?P<misses>\d+).*"
    r"prefetches=(?P<prefetches>\d+).*hits=(?P<hits>\d+)"
    r"(?:.*analytic=(?P<analytic_candidates>\d+)/(?P<analytic_duplicates>\d+)/"
    r"(?P<analytic_blocked>\d+)/(?P<analytic_fills>\d+))?"
)
STATS_EXT_RE = re.compile(r"PERF_SINGLE_STATS_EXT\s+(?P<body>.*)")
EXT_DEFAULT_KEYS = [
    "ext_version",
    "ext_snapshot",
    "ext_frame_cycles",
    "ext_cache_cycles",
    "ext_sample_req",
    "ext_sample_accept",
    "ext_sample_stall",
    "ext_normal_prefetch",
    "ext_evict_unused",
    "ext_fifo_max",
    "ext_read_busy",
    "ext_read_bytes",
    "ext_useful_sectors",
    "ext_replacement_fail",
    "ext_miss_lat_min",
    "ext_miss_lat_max",
    "ext_miss_lat_sum",
    "ext_miss_lat_count",
    "ext_merge_hist",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="sim_out/cache_sweep/fast_model_summary.csv")
    parser.add_argument("--out", default="sim_out/cache_sweep/rtl_shortlist.csv")
    parser.add_argument("--top-n", type=int, default=5)
    parser.add_argument("--workload-id", default="")
    parser.add_argument("--sort-key", default="score",
                        help="Candidate CSV field used for ranking, e.g. score or total_cycles_est.")
    parser.add_argument("--rtl-top", default="tb_image_geo_top_perf_single_1000_600_downscale_on")
    parser.add_argument("--compile-timeout", type=int, default=300)
    parser.add_argument("--elab-timeout", type=int, default=300)
    parser.add_argument("--sim-timeout", type=int, default=900)
    parser.add_argument("--full-profile", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--parse-only", action="store_true",
                        help="Do not launch simulations; rebuild the output CSV from existing xsim logs.")
    return parser.parse_args()


def load_candidates(path: Path, workload_id: str, top_n: int, sort_key: str) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if workload_id:
        rows = [row for row in rows if row["workload_id"] == workload_id]
    rows.sort(key=lambda row: float(row[sort_key]))
    return rows[:top_n]


def parse_profile(log_path: Path) -> dict[str, str]:
    result = {
        "bit_exact": "unknown",
        "total_cycles_rtl": "",
        "reads": "",
        "misses": "",
        "prefetches": "",
        "hits": "",
        "analytic_candidates": "",
        "analytic_duplicates": "",
        "analytic_blocked": "",
        "analytic_fills": "",
    }
    result.update({key: "" for key in EXT_DEFAULT_KEYS})
    if not log_path.exists():
        return result
    text = log_path.read_text(encoding="utf-8", errors="ignore")
    if "Fatal" in text or "ERROR" in text:
        result["bit_exact"] = "fail"
    if "PASS" in text or "completed" in text:
        result["bit_exact"] = "pass"
    for line in text.splitlines():
        match = PROFILE_RE.search(line)
        if match:
            result["total_cycles_rtl"] = match.group("cycles")
            result["reads"] = match.group("reads")
            result["misses"] = match.group("misses")
            result["prefetches"] = match.group("prefetches")
            result["hits"] = match.group("hits")
            for key in ("analytic_candidates", "analytic_duplicates", "analytic_blocked", "analytic_fills"):
                result[key] = match.group(key) or ""
        ext_match = STATS_EXT_RE.search(line)
        if ext_match:
            for token in ext_match.group("body").split():
                if "=" not in token:
                    continue
                key, value = token.split("=", 1)
                result[f"ext_{key}"] = value
    return result


def main() -> None:
    args = parse_args()
    repo = Path(__file__).resolve().parents[1]
    out = repo / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    candidates = load_candidates(repo / args.input, args.workload_id, args.top_n, args.sort_key)
    rows: list[dict[str, str]] = []
    for idx, cand in enumerate(candidates):
        rtl_top = cand.get("rtl_top", "") or args.rtl_top
        runtime_policy = cand.get("runtime_scheduler_policy", cand.get("runtime_policy", ""))
        runtime_merge_min = cand.get("runtime_merge_min_x", cand.get("runtime_merge_min", ""))
        runtime_age = cand.get("runtime_fifo_age_limit", cand.get("runtime_fifo_age", ""))
        runtime_throttle = cand.get("runtime_prefetch_throttle_cycles", cand.get("runtime_throttle", ""))
        row_bucket = cand.get("enable_row_bucket_merge", cand.get("row_bucket_merge", ""))
        row_bucket_min = cand.get("row_bucket_min_x", "")
        row_bucket_suffix = f"_rb{row_bucket}rmin{row_bucket_min or '3'}" if row_bucket != "" else ""
        run_name = (
            f"rtl_{cand['workload_id']}_tw{cand['tile_w']}_th{cand['tile_h']}"
            f"_s{cand['set_num']}_w{cand['way_num']}_m{cand['merge_max_x']}"
            f"_f{cand['fifo_depth']}_l{cand['lead_pixels']}"
            f"_p{runtime_policy or '0'}_mm{runtime_merge_min or '1'}"
            f"_age{runtime_age or '0'}_thr{runtime_throttle or '0'}"
            f"{row_bucket_suffix}"
        )
        command = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(repo / "tools" / "run-cache-perf-case.ps1"),
            "-Top",
            rtl_top,
            "-RunName",
            run_name,
            "-CompileTimeoutSec",
            str(args.compile_timeout),
            "-ElabTimeoutSec",
            str(args.elab_timeout),
            "-SimTimeoutSec",
            str(args.sim_timeout),
            "-BaseTileW",
            cand["tile_w"],
            "-BaseTileH",
            cand["tile_h"],
            "-SectorSetNum",
            cand["set_num"],
            "-SectorWayNum",
            cand["way_num"],
            "-MergeMaxX",
            cand["merge_max_x"],
            "-AnalyticFifoDepth",
            cand["fifo_depth"],
            "-LeadPixels",
            cand["lead_pixels"],
        ]
        optional_args = {
            "enable_merge_min": "-EnableMergeMin",
            "merge_min_x": "-MergeMinX",
            "fifo_age_limit": "-FifoAgeLimit",
            "prefetch_throttle": "-EnablePrefetchThrottle",
            "prefetch_throttle_cycles": "-PrefetchThrottleCycles",
            "enable_row_bucket_merge": "-EnableRowBucketMerge",
            "row_bucket_merge": "-EnableRowBucketMerge",
            "row_bucket_min_x": "-RowBucketMinX",
            "runtime_lead": "-RuntimeLeadPixels",
            "runtime_lead_pixels": "-RuntimeLeadPixels",
            "runtime_merge_max": "-RuntimeMergeMaxX",
            "runtime_merge_max_x_eff": "-RuntimeMergeMaxX",
            "runtime_merge_min": "-RuntimeMergeMinX",
            "runtime_merge_min_x": "-RuntimeMergeMinX",
            "runtime_fifo_depth": "-RuntimeFifoDepth",
            "runtime_fifo_depth_eff": "-RuntimeFifoDepth",
            "runtime_fifo_age": "-RuntimeFifoAgeLimit",
            "runtime_fifo_age_limit": "-RuntimeFifoAgeLimit",
            "runtime_throttle": "-RuntimePrefetchThrottleCycles",
            "runtime_prefetch_throttle_cycles": "-RuntimePrefetchThrottleCycles",
            "runtime_policy": "-RuntimeSchedulerPolicy",
            "runtime_scheduler_policy": "-RuntimeSchedulerPolicy",
            "rd_burst_max_len": "-RdBurstMaxLen",
            "rd_max_outstanding_bursts": "-RdMaxOutstandingBursts",
            "rd_max_outstanding_beats": "-RdMaxOutstandingBeats",
            "rd_fifo_depth_words": "-RdFifoDepthWords",
        }
        for key, flag in optional_args.items():
            if key in cand and cand[key] != "":
                command.extend([flag, cand[key]])
        if args.full_profile:
            command.append("-FullProfile")
        status = "dry_run"
        if args.parse_only:
            profile_probe = parse_profile(repo / "sim_out" / "cache_perf" / run_name / "xsim.log")
            status = "parsed_pass" if profile_probe.get("bit_exact") == "pass" else "parsed"
        elif not args.dry_run:
            try:
                completed = subprocess.run(
                    command,
                    cwd=repo,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    timeout=args.compile_timeout + args.elab_timeout + args.sim_timeout + 60,
                    check=False,
                )
                status = "pass" if completed.returncode == 0 else f"fail:{completed.returncode}"
            except subprocess.TimeoutExpired:
                status = "timeout"
        log_path = repo / "sim_out" / "cache_perf" / run_name / "xsim.log"
        profile = parse_profile(log_path)
        row = {**cand, **profile, "rtl_status": status, "rtl_top": rtl_top, "run_name": run_name}
        rows.append(row)
        print(f"[{idx + 1}/{len(candidates)}] {run_name}: {status}")
    fieldnames = sorted({key for row in rows for key in row.keys()})
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(out)


if __name__ == "__main__":
    main()
