#!/usr/bin/env python3
"""Fast cache parameter sweep using an analytic software model.

The model is intentionally conservative: correctness is still decided by RTL,
but this script filters thousands of candidates down to a small shortlist.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
import math
from collections import deque
from dataclasses import dataclass
from pathlib import Path


ALLOWED_TILE_W = [4, 8, 16, 32]
ALLOWED_TILE_H = [4, 8, 16, 32]
ALLOWED_SET = [16, 32, 64, 128, 256]
ALLOWED_WAY = [2, 4, 8]
ALLOWED_MERGE = [1, 2, 4, 8, 16]
ALLOWED_FIFO = [8, 16, 32, 64, 128]
ALLOWED_LEAD = [0, 8, 16, 32, 64, 128, 256, 512]
ALLOWED_RD_BURST = [8, 16, 32, 64]
ALLOWED_RD_OUTSTANDING_BURSTS = [2, 4, 8]
ALLOWED_RD_OUTSTANDING_BEATS = [16, 32, 64, 128]
ALLOWED_RD_FIFO_WORDS = [64, 128, 256]


@dataclass(frozen=True)
class Workload:
    workload_id: str
    src_w: int
    src_h: int
    dst_w: int
    dst_h: int
    angle_deg: float
    stride_pad: int = 0
    stride_mode: str = "packed"
    stride_align_bytes: int = 0
    base_unalign_bytes: int = 0


@dataclass(frozen=True)
class Params:
    tile_w: int
    tile_h: int
    set_num: int
    way_num: int
    merge_max_x: int
    fifo_depth: int
    lead_pixels: int
    rd_burst_max_len: int
    rd_max_outstanding_bursts: int
    rd_max_outstanding_beats: int
    rd_fifo_depth_words: int


DEFAULT_WORKLOADS = [
    Workload("large_7200_square_a0", 7200, 7200, 600, 600, 0),
    Workload("large_7200_square_a15", 7200, 7200, 600, 600, 15),
    Workload("large_7200_square_a45", 7200, 7200, 600, 600, 45),
    Workload("large_7200_square_a75", 7200, 7200, 600, 600, 75),
    Workload("wide_7200x4096_a15", 7200, 4096, 600, 341, 15),
    Workload("tall_4096x7200_a45", 4096, 7200, 341, 600, 45),
    Workload("hd_1920x1080_a0", 1920, 1080, 600, 338, 0),
    Workload("hd_1920x1080_a15", 1920, 1080, 600, 338, 15),
    Workload("hd_1920x1080_a45", 1920, 1080, 600, 338, 45),
    Workload("mid_1024_square_a0", 1024, 1024, 600, 600, 0),
    Workload("mid_1024_square_a45", 1024, 1024, 600, 600, 45),
    Workload("near_640_square_a0", 640, 640, 600, 600, 0),
    Workload("near_640_square_a45", 640, 640, 600, 600, 45),
]


def parse_int_list(text: str, allowed: list[int]) -> list[int]:
    if text == "all":
        return allowed
    values = [int(x) for x in text.split(",") if x.strip()]
    bad = [x for x in values if x not in allowed]
    if bad:
        raise SystemExit(f"Unsupported values {bad}; allowed={allowed}")
    return values


def sector_set(tile_x: int, tile_y: int, set_num: int) -> int:
    return (tile_x ^ tile_y) & (set_num - 1)


def align_up(value: int, align: int) -> int:
    if align <= 1:
        return value
    return ((value + align - 1) // align) * align


def workload_stride_bytes(w: Workload) -> int:
    stride = w.src_w + w.stride_pad
    if w.stride_align_bytes > 0:
        stride = align_up(stride, w.stride_align_bytes)
    return stride


def geometry_tiles(w: Workload, p: Params, pixel_idx: int) -> tuple[tuple[int, int], ...]:
    dst_x = pixel_idx % w.dst_w
    dst_y = pixel_idx // w.dst_w
    theta = math.radians(w.angle_deg)
    cos_v = math.cos(theta)
    sin_v = math.sin(theta)
    scale_x = w.src_w / w.dst_w
    scale_y = w.src_h / w.dst_h
    src_cx = (w.src_w - 1) * 0.5
    src_cy = (w.src_h - 1) * 0.5
    dst_cx = (w.dst_w - 1) * 0.5
    dst_cy = (w.dst_h - 1) * 0.5
    step_x_x = cos_v * scale_x
    step_y_x = -sin_v * scale_x
    step_x_y = sin_v * scale_y
    step_y_y = cos_v * scale_y
    src_x = src_cx + (dst_x - dst_cx) * step_x_x + (dst_y - dst_cy) * step_x_y
    src_y = src_cy + (dst_x - dst_cx) * step_y_x + (dst_y - dst_cy) * step_y_y
    src_x = min(max(src_x, 0.0), w.src_w - 1.0)
    src_y = min(max(src_y, 0.0), w.src_h - 1.0)
    x0 = int(math.floor(src_x))
    y0 = int(math.floor(src_y))
    x1 = min(x0 + 1, w.src_w - 1)
    y1 = min(y0 + 1, w.src_h - 1)
    tiles = {
        (x0 // p.tile_w, y0 // p.tile_h),
        (x1 // p.tile_w, y0 // p.tile_h),
        (x0 // p.tile_w, y1 // p.tile_h),
        (x1 // p.tile_w, y1 // p.tile_h),
    }
    return tuple(sorted(tiles))


def choose_victim(cache_set: list[dict], current_tiles: set[tuple[int, int]]) -> int | None:
    for i, way in enumerate(cache_set):
        if not way["valid"]:
            return i
    candidates = [
        (i, way)
        for i, way in enumerate(cache_set)
        if way["tag"] not in current_tiles and way["prefetched"] and way["used"]
    ]
    if not candidates:
        candidates = [(i, way) for i, way in enumerate(cache_set) if way["tag"] not in current_tiles]
    if not candidates:
        return None
    return min(candidates, key=lambda item: item[1]["last"])[0]


def estimate_row_bursts(addr: int, byte_count: int, burst_bytes: int) -> int:
    remaining = max(0, byte_count)
    cur = addr
    bursts = 0
    while remaining > 0:
        boundary_left = 4096 - (cur & 4095)
        take = min(remaining, burst_bytes, boundary_left)
        if take <= 0:
            take = min(remaining, burst_bytes)
        bursts += 1
        cur += take
        remaining -= take
    return max(1, bursts)


def estimate_service_cycles(
    w: Workload,
    p: Params,
    tiles: tuple[tuple[int, int], ...],
    byte_count: int,
    row_count: int,
    args: argparse.Namespace,
) -> int:
    burst_bytes = max(1, args.axi_bytes_per_beat * p.rd_burst_max_len)
    stride = workload_stride_bytes(w)
    base_x = tiles[0][0] * p.tile_w
    base_y = tiles[0][1] * p.tile_h
    bursts_total = 0
    for row in range(max(1, row_count)):
        addr = w.base_unalign_bytes + (base_y + row) * stride + base_x
        bursts_total += estimate_row_bursts(addr, byte_count, burst_bytes)
    outstanding_gain = max(1.0, min(float(p.rd_max_outstanding_bursts), float(p.rd_max_outstanding_beats) / max(1, p.rd_burst_max_len)))
    payload_rate = max(1.0, float(args.read_bytes_per_cycle) * min(2.0, outstanding_gain / 2.0))
    payload = max(1, math.ceil(byte_count * row_count / payload_rate))
    return args.read_latency + args.task_overhead + bursts_total * args.burst_overhead + payload


def validate_params(p: Params) -> bool:
    if p.fifo_depth < p.merge_max_x:
        return False
    if p.merge_max_x * p.tile_w > 128:
        return False
    if p.set_num & (p.set_num - 1):
        return False
    if p.rd_fifo_depth_words < p.rd_max_outstanding_beats:
        return False
    return True


def calibrated_feature_values(
    w: Workload,
    p: Params,
    raw_total_cycles: int,
    miss_count: int,
    prefetch_fill: int,
    read_bytes: int,
    unique_source_tiles: int,
    prefetch_hit: int,
    read_busy_cycles: int,
    sample_stall_cycles: int,
    avg_merge_len: float,
) -> dict[str, float]:
    angle = float(w.angle_deg)
    diag = abs(math.sin(math.radians(angle * 2.0)))
    orth = abs(math.cos(math.radians(angle * 2.0)))
    dst_pixels = float(w.dst_w * w.dst_h)
    dst_w = float(w.dst_w)
    dst_h = float(w.dst_h)
    tile_w = float(p.tile_w)
    tile_h = float(p.tile_h)
    lead = float(p.lead_pixels)
    fifo = float(p.fifo_depth)
    merge = float(p.merge_max_x)
    sector_bytes = max(1.0, tile_w * tile_h)
    sectors = float(read_bytes) / sector_bytes
    useful_source_bytes = max(1.0, float(unique_source_tiles) * sector_bytes)
    lead_coverage = lead / max(1.0, dst_w)
    prefetch_hit_coverage = float(prefetch_hit) / max(1.0, dst_pixels)
    read_amplification = float(read_bytes) / useful_source_bytes
    merge_efficiency = avg_merge_len / max(1.0, merge)
    stall_per_read_busy = float(sample_stall_cycles) / max(1.0, float(read_busy_cycles))
    small = 1.0 if dst_pixels <= 2304.0 else 0.0
    mid = 1.0 - small
    tile16 = 1.0 if p.tile_w == 16 else 0.0
    tileh16 = 1.0 if p.tile_h == 16 else 0.0
    tileh8 = 1.0 if p.tile_h == 8 else 0.0
    shortlead = 1.0 if p.lead_pixels <= 16 else 0.0
    return {
        "bias": 1.0,
        "raw": float(raw_total_cycles),
        "pix": dst_pixels,
        "dst_w": dst_w,
        "dst_h": dst_h,
        "sqrtpix": math.sqrt(dst_pixels),
        "miss": float(miss_count),
        "pref": float(prefetch_fill),
        "sectors": sectors,
        "diag": diag,
        "orth": orth,
        "tile_h": tile_h,
        "tile_w": tile_w,
        "lead": lead,
        "fifo": fifo,
        "merge": merge,
        "diag_sectors": diag * sectors,
        "orth_pref": orth * float(prefetch_fill),
        "diag_pref": diag * float(prefetch_fill),
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


def simulate(w: Workload, p: Params, args: argparse.Namespace) -> dict[str, float | int | str]:
    cache = [[{"valid": False, "tag": None, "prefetched": False, "used": False, "last": 0}
              for _ in range(p.way_num)] for _ in range(p.set_num)]
    fifo: deque[tuple[tuple[int, int], int]] = deque()
    pending: list[tuple[int, tuple[tuple[int, int], ...], bool, int]] = []
    touch = 0
    cycle = 0
    read_busy_until = 0
    planner_idx = 0
    full_pixels = w.dst_w * w.dst_h
    if args.mode == "full":
        first_row, last_row = 0, w.dst_h
    else:
        span = min(args.scan_rows, w.dst_h)
        first_row = max(0, (w.dst_h - span) // 2)
        last_row = first_row + span
    first_pixel = first_row * w.dst_w
    last_pixel = min(last_row * w.dst_w, full_pixels)
    planner_idx = first_pixel
    planner_cycle_ref = cycle
    planner_budget = 0.0

    misses = 0
    prefetch_fills = 0
    analytic_fills = 0
    normal_fills = 0
    prefetch_hits = 0
    unused_evict = 0
    read_bytes = 0
    read_busy_cycles = 0
    stall_cycles = 0
    fifo_max = 0
    fifo_blocked = 0
    duplicate = 0
    candidates = 0
    replacement_fail = 0
    merge_hist = {i: 0 for i in range(1, p.merge_max_x + 1)}
    last_real_miss_cycle = -1_000_000_000
    touched_tiles: set[tuple[int, int]] = set()

    def fifo_contains(tile: tuple[int, int]) -> bool:
        return any(entry_tile == tile for entry_tile, _ in fifo)

    def enqueue_planner_pixel(pixel: int) -> None:
        nonlocal candidates, duplicate, fifo_blocked, fifo_max
        for tile in geometry_tiles(w, p, pixel):
            candidates += 1
            if cached(tile) or pending_done(tile) is not None or fifo_contains(tile):
                duplicate += 1
            elif len(fifo) < p.fifo_depth:
                fifo.append((tile, cycle))
                fifo_max = max(fifo_max, len(fifo))
            else:
                fifo_blocked += 1

    def advance_planner(to_cycle: int, lead_limit_pixel: int) -> None:
        nonlocal planner_idx, planner_cycle_ref, planner_budget
        if not prefetch_enabled:
            planner_cycle_ref = to_cycle
            return
        target = min(full_pixels, lead_limit_pixel)
        rate = float(getattr(args, "planner_pixels_per_cycle", 1.0))
        if rate <= 0.0:
            while planner_idx < target:
                enqueue_planner_pixel(planner_idx)
                planner_idx += 1
            planner_cycle_ref = to_cycle
            return
        elapsed = max(0, to_cycle - planner_cycle_ref)
        planner_budget += elapsed * rate
        planner_cycle_ref = to_cycle
        while planner_idx < target and planner_budget >= 1.0:
            enqueue_planner_pixel(planner_idx)
            planner_idx += 1
            planner_budget -= 1.0

    def retire(done_cycle: int) -> None:
        nonlocal touch
        ready = [item for item in pending if item[0] <= done_cycle]
        pending[:] = [item for item in pending if item[0] > done_cycle]
        for _, tiles, is_prefetch, _ in ready:
            for tile in tiles:
                s = sector_set(tile[0], tile[1], p.set_num)
                victim = choose_victim(cache[s], set())
                if victim is None:
                    continue
                way = cache[s][victim]
                way.update(valid=True, tag=tile, prefetched=is_prefetch, used=False, last=touch)
                touch += 1

    def cached(tile: tuple[int, int]) -> bool:
        s = sector_set(tile[0], tile[1], p.set_num)
        return any(way["valid"] and way["tag"] == tile for way in cache[s])

    def pending_done(tile: tuple[int, int]) -> int | None:
        hits = [done for done, tiles, _, _ in pending if tile in tiles]
        return min(hits) if hits else None

    def launch_fill(tiles: tuple[tuple[int, int], ...], is_prefetch: bool, current_tiles: set[tuple[int, int]]) -> bool:
        nonlocal cycle, read_busy_until, read_busy_cycles, misses, prefetch_fills, analytic_fills, normal_fills
        nonlocal read_bytes, unused_evict, replacement_fail
        nonlocal last_real_miss_cycle
        if not tiles:
            return False
        for tile in tiles:
            s = sector_set(tile[0], tile[1], p.set_num)
            victim = choose_victim(cache[s], current_tiles)
            if victim is None:
                replacement_fail += 1
                return False
            old = cache[s][victim]
            if old["valid"] and old["prefetched"] and not old["used"]:
                unused_evict += 1
            old.update(valid=False, tag=None, prefetched=False, used=False, last=touch)
        byte_count = min(len(tiles) * p.tile_w, w.src_w - tiles[0][0] * p.tile_w)
        row_count = min(p.tile_h, w.src_h - tiles[0][1] * p.tile_h)
        bytes_this = max(0, byte_count) * max(0, row_count)
        service = estimate_service_cycles(w, p, tiles, byte_count, row_count, args)
        start_cycle = max(cycle, read_busy_until)
        done_cycle = start_cycle + service
        read_busy_cycles += max(0, done_cycle - start_cycle)
        read_busy_until = done_cycle
        pending.append((done_cycle, tiles, is_prefetch, bytes_this))
        read_bytes += bytes_this
        if is_prefetch:
            prefetch_fills += len(tiles)
        else:
            misses += 1
            last_real_miss_cycle = cycle
        return True

    prefetch_enabled = getattr(args, "prefetch_enabled", True)

    for pixel_idx in range(first_pixel, last_pixel):
        retire(cycle)
        advance_planner(cycle, pixel_idx + p.lead_pixels)

        tiles = geometry_tiles(w, p, pixel_idx)
        current = set(tiles)
        touched_tiles.update(current)
        miss_tiles = [tile for tile in tiles if not cached(tile)]
        if miss_tiles:
            wait_done = [pending_done(tile) for tile in miss_tiles]
            wait_done = [x for x in wait_done if x is not None]
            if wait_done:
                wait_to = min(wait_done)
                stall = max(0, wait_to - cycle)
                advance_planner(wait_to, pixel_idx + p.lead_pixels)
                cycle = wait_to
                stall_cycles += stall
                retire(cycle)
            miss_tiles = [tile for tile in tiles if not cached(tile)]
            if miss_tiles:
                before = cycle
                launch_fill((miss_tiles[0],), False, current)
                done = pending_done(miss_tiles[0])
                if done is not None:
                    advance_planner(done, pixel_idx + p.lead_pixels)
                    cycle = done
                    stall_cycles += max(0, cycle - before)
                    retire(cycle)

        hit_prefetch = False
        for tile in tiles:
            s = sector_set(tile[0], tile[1], p.set_num)
            for way in cache[s]:
                if way["valid"] and way["tag"] == tile:
                    hit_prefetch = hit_prefetch or way["prefetched"]
                    way["prefetched"] = False
                    way["used"] = True
                    way["last"] = touch
                    touch += 1
                    break
        if hit_prefetch:
            prefetch_hits += 1
        cycle += 1
        advance_planner(cycle, pixel_idx + p.lead_pixels)

        retire(cycle)
        throttle_prefetch = (
            bool(getattr(args, "enable_prefetch_throttle", False)) and
            ((cycle - last_real_miss_cycle) < int(getattr(args, "prefetch_throttle_cycles", 0)))
        )
        if prefetch_enabled and fifo and read_busy_until <= cycle and not throttle_prefetch:
            (head_x, head_y), head_cycle = fifo[0]
            run = []
            scan_idx = 0
            while scan_idx < len(fifo) and len(run) < p.merge_max_x:
                (tx, ty), _ = fifo[scan_idx]
                if ty != head_y or tx != head_x + len(run) or cached((tx, ty)) or pending_done((tx, ty)) is not None:
                    break
                run.append((tx, ty))
                scan_idx += 1
            head_age_ready = (
                int(getattr(args, "fifo_age_limit", 0)) > 0 and
                ((cycle - head_cycle) >= int(getattr(args, "fifo_age_limit", 0)))
            )
            merge_min = max(1, int(getattr(args, "merge_min_x", 1)))
            if run and ((len(run) >= merge_min) or head_age_ready):
                for _ in range(len(run)):
                    fifo.popleft()
                merge_hist[len(run)] += 1
                analytic_fills += len(run)
                launch_fill(tuple(run), True, set())
            elif not run:
                fifo.popleft()

    retire(max(cycle, read_busy_until))
    scale = full_pixels / max(1, last_pixel - first_pixel)
    raw_total_cycles = int(cycle * scale) if args.mode == "scan" else int(cycle)
    stall_scaled = int(stall_cycles * scale) if args.mode == "scan" else int(stall_cycles)
    miss_scaled = int(misses * scale) if args.mode == "scan" else misses
    bytes_scaled = int(read_bytes * scale) if args.mode == "scan" else read_bytes
    busy_scaled = int(read_busy_cycles * scale) if args.mode == "scan" else read_busy_cycles
    prefetch_fill_scaled = int(prefetch_fills * scale) if args.mode == "scan" else prefetch_fills
    unique_source_tiles = int(len(touched_tiles) * scale) if args.mode == "scan" else len(touched_tiles)
    prefetch_miss_floor_added = 0
    if prefetch_enabled and args.prefetch_min_miss_ratio > 0.0:
        miss_floor = int(math.ceil(unique_source_tiles * args.prefetch_min_miss_ratio))
        if miss_scaled < miss_floor:
            prefetch_miss_floor_added = miss_floor - miss_scaled
            miss_scaled = miss_floor
    prefetch_read_amp_added = 0
    if prefetch_enabled and args.prefetch_read_amplification > 1.0:
        amp_floor = int(math.ceil(bytes_scaled * args.prefetch_read_amplification))
        prefetch_read_amp_added = max(0, amp_floor - bytes_scaled)
        bytes_scaled = max(bytes_scaled, amp_floor)
    merge_count = max(1, sum(merge_hist.values()))
    avg_merge_len = sum(k * v for k, v in merge_hist.items()) / merge_count
    useful_source_bytes = max(1, unique_source_tiles * p.tile_w * p.tile_h)
    calibration_features = getattr(args, "calibration_features", None)
    if calibration_features:
        feature_values = calibrated_feature_values(
            w, p, raw_total_cycles, miss_scaled, prefetch_fill_scaled, bytes_scaled,
            unique_source_tiles, prefetch_hits, busy_scaled, stall_scaled, avg_merge_len
        )
        total_cycles = int(sum(
            float(coef) * feature_values.get(name, 0.0)
            for name, coef in calibration_features.items()
        ))
    else:
        total_cycles = int(
            raw_total_cycles * args.rtl_raw_cycle_scale
            + args.rtl_frame_overhead
            + (w.dst_w * w.dst_h) * args.rtl_dst_pixel_extra_cycles
            + miss_scaled * args.rtl_demand_miss_extra_cycles
            + prefetch_fill_scaled * args.rtl_prefetch_fill_extra_cycles
            + (miss_scaled + prefetch_fill_scaled) * args.rtl_read_start_extra_cycles
            + (bytes_scaled / max(1, p.tile_w * p.tile_h)) * args.rtl_read_sector_extra_cycles
        )
    score = total_cycles + 5 * stall_scaled + 10 * replacement_fail + int(unused_evict * 2)
    return {
        "workload_id": w.workload_id,
        "src_w": w.src_w,
        "src_h": w.src_h,
        "dst_w": w.dst_w,
        "dst_h": w.dst_h,
        "dst_pixel_count": w.dst_w * w.dst_h,
        "angle_deg": w.angle_deg,
        "stride_mode": w.stride_mode,
        "stride_bytes": workload_stride_bytes(w),
        "base_unalign_bytes": w.base_unalign_bytes,
        "prefetch_mode": "on" if prefetch_enabled else "off",
        "tile_w": p.tile_w,
        "tile_h": p.tile_h,
        "set_num": p.set_num,
        "way_num": p.way_num,
        "merge_max_x": p.merge_max_x,
        "fifo_depth": p.fifo_depth,
        "lead_pixels": p.lead_pixels,
        "merge_min_x": int(getattr(args, "merge_min_x", 1)),
        "fifo_age_limit": int(getattr(args, "fifo_age_limit", 0)),
        "prefetch_throttle": int(bool(getattr(args, "enable_prefetch_throttle", False))),
        "prefetch_throttle_cycles": int(getattr(args, "prefetch_throttle_cycles", 0)),
        "structural_tile_w": p.tile_w,
        "structural_tile_h": p.tile_h,
        "structural_set_num": p.set_num,
        "structural_way_num": p.way_num,
        "structural_fifo_max": p.fifo_depth,
        "structural_merge_max": p.merge_max_x,
        "runtime_lead": p.lead_pixels,
        "runtime_merge_eff": p.merge_max_x,
        "runtime_merge_min": int(getattr(args, "merge_min_x", 1)),
        "runtime_fifo_eff": p.fifo_depth,
        "runtime_age": int(getattr(args, "fifo_age_limit", 0)),
        "runtime_throttle": int(getattr(args, "prefetch_throttle_cycles", 0)),
        "runtime_policy": (1 if (int(getattr(args, "merge_min_x", 1)) > 1 or
                                  int(getattr(args, "fifo_age_limit", 0)) > 0) else 0) |
                          (2 if bool(getattr(args, "enable_prefetch_throttle", False)) else 0),
        "rd_burst_max_len": p.rd_burst_max_len,
        "rd_max_outstanding_bursts": p.rd_max_outstanding_bursts,
        "rd_max_outstanding_beats": p.rd_max_outstanding_beats,
        "rd_fifo_depth_words": p.rd_fifo_depth_words,
        "raw_total_cycles_est": raw_total_cycles,
        "total_cycles_est": total_cycles,
        "score": score,
        "rtl_frame_overhead": args.rtl_frame_overhead,
        "rtl_raw_cycle_scale": args.rtl_raw_cycle_scale,
        "rtl_dst_pixel_extra_cycles": args.rtl_dst_pixel_extra_cycles,
        "rtl_demand_miss_extra_cycles": args.rtl_demand_miss_extra_cycles,
        "rtl_prefetch_fill_extra_cycles": args.rtl_prefetch_fill_extra_cycles,
        "rtl_read_start_extra_cycles": args.rtl_read_start_extra_cycles,
        "rtl_read_sector_extra_cycles": args.rtl_read_sector_extra_cycles,
        "calibration_feature_set": getattr(args, "calibration_feature_set", ""),
        "miss_count": miss_scaled,
        "prefetch_fill": prefetch_fill_scaled,
        "analytic_fill": analytic_fills,
        "normal_prefetch_fill": normal_fills,
        "prefetch_hit": prefetch_hits,
        "unused_evict": unused_evict,
        "read_bytes": bytes_scaled,
        "unique_source_tiles": unique_source_tiles,
        "lead_coverage_ratio": f"{(p.lead_pixels / max(1, w.dst_w)):.6f}",
        "prefetch_hit_coverage": f"{(prefetch_hits / max(1, w.dst_w * w.dst_h)):.6f}",
        "read_amplification": f"{(bytes_scaled / useful_source_bytes):.6f}",
        "merge_efficiency": f"{(avg_merge_len / max(1, p.merge_max_x)):.6f}",
        "stall_per_read_busy": f"{(stall_scaled / max(1, busy_scaled)):.6f}",
        "prefetch_miss_floor_added": prefetch_miss_floor_added,
        "prefetch_read_amp_added": prefetch_read_amp_added,
        "fifo_max_occupancy": fifo_max,
        "analytic_candidate_count": candidates,
        "analytic_duplicate_count": duplicate,
        "analytic_blocked_count": fifo_blocked,
        "sample_stall_cycles": stall_scaled,
        "read_busy_cycles": busy_scaled,
        "replacement_fail_cycles": replacement_fail,
        "merge_hist": ";".join(f"{k}:{v}" for k, v in merge_hist.items()),
        "mode": args.mode,
    }


def load_workloads(path: str | None) -> list[Workload]:
    if not path:
        return DEFAULT_WORKLOADS
    rows: list[Workload] = []
    with Path(path).open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rows.append(Workload(
                workload_id=row["workload_id"],
                src_w=int(row["src_w"]),
                src_h=int(row["src_h"]),
                dst_w=int(row["dst_w"]),
                dst_h=int(row["dst_h"]),
                angle_deg=float(row["angle_deg"]),
                stride_pad=int(row.get("stride_pad", 0) or 0),
                stride_mode=row.get("stride_mode", "packed") or "packed",
                stride_align_bytes=int(row.get("stride_align_bytes", 0) or 0),
                base_unalign_bytes=int(row.get("base_unalign_bytes", 0) or 0),
            ))
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="sim_out/cache_sweep/fast_model_summary.csv")
    parser.add_argument("--workloads")
    parser.add_argument("--mode", choices=["scan", "debug", "full"], default="scan")
    parser.add_argument("--scan-rows", type=int, default=80)
    parser.add_argument("--tile-w", default="4,8,16,32")
    parser.add_argument("--tile-h", default="4,8,16")
    parser.add_argument("--set-num", default="32,64,128")
    parser.add_argument("--way-num", default="2,4")
    parser.add_argument("--merge-max-x", default="1,2,4,8")
    parser.add_argument("--fifo-depth", default="16,32,64")
    parser.add_argument("--lead-pixels", default="16,32,64,128,256")
    parser.add_argument("--prefetch-mode", choices=["on", "off", "both"], default="on")
    parser.add_argument("--merge-min-x", type=int, default=1)
    parser.add_argument("--fifo-age-limit", type=int, default=0)
    parser.add_argument("--enable-prefetch-throttle", action="store_true")
    parser.add_argument("--prefetch-throttle-cycles", type=int, default=0)
    parser.add_argument("--rd-burst-max-len", default="16")
    parser.add_argument("--rd-max-outstanding-bursts", default="4")
    parser.add_argument("--rd-max-outstanding-beats", default="16")
    parser.add_argument("--rd-fifo-depth-words", default="64")
    parser.add_argument("--max-combos", type=int, default=0)
    parser.add_argument("--read-latency", type=int, default=80)
    parser.add_argument("--task-overhead", type=int, default=40)
    parser.add_argument("--burst-overhead", type=int, default=8)
    parser.add_argument("--burst-len", type=int, default=16)
    parser.add_argument("--axi-bytes-per-beat", type=int, default=4)
    parser.add_argument("--read-bytes-per-cycle", type=int, default=4)
    parser.add_argument("--planner-pixels-per-cycle", type=float, default=1.0,
                        help="Analytic planner rate. Use 0 for the old ideal unlimited lead window.")
    parser.add_argument("--prefetch-min-miss-ratio", type=float, default=0.0,
                        help="Optional calibrated floor for demand misses under prefetch, as a ratio of touched source tiles.")
    parser.add_argument("--prefetch-read-amplification", type=float, default=1.0,
                        help="Optional calibrated DDR byte amplification under speculative prefetch.")
    parser.add_argument("--rtl-frame-overhead", type=float, default=0.0,
                        help="Calibrated frame-level RTL overhead added to total_cycles_est.")
    parser.add_argument("--rtl-raw-cycle-scale", type=float, default=1.0,
                        help="Calibrated scale applied to raw_total_cycles_est before additive terms.")
    parser.add_argument("--rtl-dst-pixel-extra-cycles", type=float, default=0.0,
                        help="Calibrated extra cycles per output pixel.")
    parser.add_argument("--rtl-demand-miss-extra-cycles", type=float, default=0.0,
                        help="Calibrated extra cycles per real demand miss.")
    parser.add_argument("--rtl-prefetch-fill-extra-cycles", type=float, default=0.0,
                        help="Calibrated extra cycles per prefetch sector fill.")
    parser.add_argument("--rtl-read-start-extra-cycles", type=float, default=0.0,
                        help="Calibrated extra cycles per estimated read start.")
    parser.add_argument("--rtl-read-sector-extra-cycles", type=float, default=0.0,
                        help="Calibrated extra cycles per read sector worth of DDR bytes.")
    parser.add_argument("--calibration-json",
                        help="JSON produced by fit_model_calibration.py. Overrides scalar calibration terms.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.merge_min_x < 1:
        raise SystemExit("--merge-min-x must be >= 1")
    if args.fifo_age_limit < 0:
        raise SystemExit("--fifo-age-limit must be >= 0")
    if args.prefetch_throttle_cycles < 0:
        raise SystemExit("--prefetch-throttle-cycles must be >= 0")
    if args.prefetch_min_miss_ratio < 0.0:
        raise SystemExit("--prefetch-min-miss-ratio must be >= 0")
    if args.prefetch_read_amplification < 1.0:
        raise SystemExit("--prefetch-read-amplification must be >= 1")
    args.calibration_features = None
    args.calibration_feature_set = ""
    if args.calibration_json:
        data = json.loads(Path(args.calibration_json).read_text(encoding="utf-8"))
        args.calibration_features = data.get("features", {})
        args.calibration_feature_set = data.get("feature_set", "custom")
    workloads = load_workloads(args.workloads)
    grids = [
        parse_int_list(args.tile_w, ALLOWED_TILE_W),
        parse_int_list(args.tile_h, ALLOWED_TILE_H),
        parse_int_list(args.set_num, ALLOWED_SET),
        parse_int_list(args.way_num, ALLOWED_WAY),
        parse_int_list(args.merge_max_x, ALLOWED_MERGE),
        parse_int_list(args.fifo_depth, ALLOWED_FIFO),
        parse_int_list(args.lead_pixels, ALLOWED_LEAD),
        parse_int_list(args.rd_burst_max_len, ALLOWED_RD_BURST),
        parse_int_list(args.rd_max_outstanding_bursts, ALLOWED_RD_OUTSTANDING_BURSTS),
        parse_int_list(args.rd_max_outstanding_beats, ALLOWED_RD_OUTSTANDING_BEATS),
        parse_int_list(args.rd_fifo_depth_words, ALLOWED_RD_FIFO_WORDS),
    ]
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fieldnames: list[str] | None = None
    count = 0
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = None
        prefetch_modes = [args.prefetch_mode] if args.prefetch_mode != "both" else ["off", "on"]
        for values in itertools.product(*grids):
            params = Params(*values)
            if not validate_params(params):
                continue
            for prefetch_mode in prefetch_modes:
                args.prefetch_enabled = (prefetch_mode == "on")
                for workload in workloads:
                    row = simulate(workload, params, args)
                    if writer is None:
                        fieldnames = list(row.keys())
                        writer = csv.DictWriter(f, fieldnames=fieldnames)
                        writer.writeheader()
                    writer.writerow(row)
                    count += 1
                    if args.max_combos and count >= args.max_combos:
                        print(out)
                        return
    print(out)


if __name__ == "__main__":
    main()
