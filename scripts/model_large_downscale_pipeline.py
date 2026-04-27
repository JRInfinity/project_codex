#!/usr/bin/env python3
"""Estimate large downscale preprocessing pipelines.

This is a research model only. The cycle numbers are relative screening
estimates, not RTL performance conclusions.
"""

from __future__ import annotations

import argparse
import csv
import math
from dataclasses import dataclass
from pathlib import Path


BOX_FACTORS = (2, 3, 4, 6, 8, 12)


@dataclass(frozen=True)
class ImageSize:
    w: int
    h: int


def parse_size(text: str) -> ImageSize:
    parts = text.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"bad size '{text}', expected WxH")
    return ImageSize(int(parts[0]), int(parts[1]))


def parse_size_list(text: str) -> list[ImageSize]:
    if not text:
        return []
    return [parse_size(item.strip()) for item in text.split(",") if item.strip()]


def packed_stride(width: int, pixel_w: int) -> int:
    return width * pixel_w


def image_bytes(size: ImageSize, stride: int, pixel_w: int) -> int:
    row_bytes = stride if stride > 0 else packed_stride(size.w, pixel_w)
    return row_bytes * size.h


def scale_ratio(src: ImageSize, dst: ImageSize) -> tuple[float, float, float]:
    sx = src.w / dst.w
    sy = src.h / dst.h
    return sx, sy, max(sx, sy)


def accumulator_bits(pixel_w: int, factor_x: float, factor_y: float) -> int:
    taps = max(1, int(math.ceil(factor_x) * math.ceil(factor_y)))
    return pixel_w * 8 + math.ceil(math.log2(taps))


def locality_for_direct(ratio: float, angle_deg: float) -> float:
    angle_penalty = min(abs(math.sin(math.radians(angle_deg))), 1.0) * 0.20
    ratio_penalty = min(max((ratio - 1.0) / 12.0, 0.0), 0.75)
    return max(0.05, 1.0 - ratio_penalty - angle_penalty)


def base_fields(args: argparse.Namespace, src: ImageSize, dst: ImageSize) -> dict[str, object]:
    sx, sy, ratio = scale_ratio(src, dst)
    return {
        "src_w": src.w,
        "src_h": src.h,
        "dst_w": dst.w,
        "dst_h": dst.h,
        "angle_deg": args.angle_deg,
        "scale_x": f"{sx:.4f}",
        "scale_y": f"{sy:.4f}",
        "scale_ratio": f"{ratio:.4f}",
    }


def row_for_direct(args: argparse.Namespace, src: ImageSize, dst: ImageSize) -> dict[str, object]:
    _, _, ratio = scale_ratio(src, dst)
    dst_bytes = image_bytes(dst, args.dst_stride, args.pixel_w)
    src_reads = dst.w * dst.h * 4 * args.pixel_w
    random_cost = 5.0 if ratio > 4.0 else 2.5 if ratio > 2.0 else 1.3
    locality = locality_for_direct(ratio, args.angle_deg)
    cycles = int(src_reads * random_cost / max(locality, 0.05) + dst.w * dst.h * 20)
    notes = "aliasing_risk=high" if ratio > 4.0 else "aliasing_risk=moderate" if ratio > 2.0 else "aliasing_risk=low"
    row = {
        "mode": "direct_bilinear",
        **base_fields(args, src, dst),
        "intermediate_w": 0,
        "intermediate_h": 0,
        "num_passes": 1,
        "estimated_src_read_bytes": int(src_reads),
        "estimated_intermediate_write_bytes": 0,
        "estimated_intermediate_read_bytes": 0,
        "estimated_dst_write_bytes": int(dst_bytes),
        "estimated_total_bytes": int(src_reads + dst_bytes),
        "estimated_total_cycles": cycles,
        "cache_locality_score": f"{locality:.3f}",
        "required_line_buffer_rows": 2,
        "accumulator_bit_width": 0,
        "bram_estimate_bytes": dst.w * 2 * args.pixel_w,
        "notes": notes + "; current RTL equivalent; random_tile_read_cost weighted",
    }
    return row


def row_for_box(args: argparse.Namespace, src: ImageSize, dst: ImageSize, inter: ImageSize) -> dict[str, object]:
    fx = src.w / inter.w
    fy = src.h / inter.h
    inter_to_dst_ratio = max(inter.w / dst.w, inter.h / dst.h)
    src_bytes = image_bytes(src, args.src_stride, args.pixel_w)
    inter_stride = packed_stride(inter.w, args.pixel_w)
    inter_bytes = image_bytes(inter, inter_stride, args.pixel_w)
    dst_bytes = image_bytes(dst, args.dst_stride, args.pixel_w)
    inter_read = dst.w * dst.h * 4 * args.pixel_w
    inter_random_cost = 2.0 if inter_to_dst_ratio > 2.0 else 1.3
    cycles = int(src_bytes + inter_bytes * 1.2 + inter_read * inter_random_cost + dst_bytes)
    integer_factor = abs(fx - round(fx)) < 1e-6 and abs(fy - round(fy)) < 1e-6
    supported = int(round(fx)) in BOX_FACTORS and int(round(fy)) in BOX_FACTORS and integer_factor
    notes = "integer_factor_box" if supported else "nonlisted_factor_estimate"
    return {
        "mode": "prefilter_box",
        **base_fields(args, src, dst),
        "intermediate_w": inter.w,
        "intermediate_h": inter.h,
        "num_passes": 2,
        "estimated_src_read_bytes": int(src_bytes),
        "estimated_intermediate_write_bytes": int(inter_bytes),
        "estimated_intermediate_read_bytes": int(inter_read),
        "estimated_dst_write_bytes": int(dst_bytes),
        "estimated_total_bytes": int(src_bytes + inter_bytes + inter_read + dst_bytes),
        "estimated_total_cycles": cycles,
        "cache_locality_score": f"{min(0.95, 0.55 + 0.05 * min(fx, fy)):.3f}",
        "required_line_buffer_rows": int(max(2, math.ceil(fy))),
        "accumulator_bit_width": accumulator_bits(args.pixel_w, fx, fy),
        "bram_estimate_bytes": int(max(2, math.ceil(fy)) * src.w * args.pixel_w),
        "notes": notes + "; sequential prefilter pass improves locality and antialiasing",
    }


def default_multistage(src: ImageSize, dst: ImageSize, intermediates: list[ImageSize]) -> list[list[ImageSize]]:
    stages: list[list[ImageSize]] = []
    if intermediates:
        stages.append(intermediates)
    candidates = [
        [ImageSize(max(dst.w, src.w // 4), max(dst.h, src.h // 4)), ImageSize(max(dst.w, src.w // 8), max(dst.h, src.h // 8))],
        [ImageSize(max(dst.w, src.w // 6), max(dst.h, src.h // 6))],
        [ImageSize(max(dst.w, src.w // 3), max(dst.h, src.h // 3)), ImageSize(max(dst.w, src.w // 6), max(dst.h, src.h // 6))],
    ]
    seen = {tuple((s.w, s.h) for s in chain) for chain in stages}
    for chain in candidates:
        key = tuple((s.w, s.h) for s in chain)
        if key not in seen and chain[-1] != dst:
            stages.append(chain)
    return stages


def row_for_multistage(args: argparse.Namespace, src: ImageSize, dst: ImageSize, chain: list[ImageSize]) -> dict[str, object]:
    sizes = [src] + chain
    src_read = 0
    inter_write = 0
    inter_read = 0
    max_rows = 2
    max_acc_bits = 0
    cycles = 0.0
    for prev, cur in zip(sizes, sizes[1:]):
        fx = prev.w / cur.w
        fy = prev.h / cur.h
        prev_bytes = image_bytes(prev, packed_stride(prev.w, args.pixel_w), args.pixel_w)
        cur_bytes = image_bytes(cur, packed_stride(cur.w, args.pixel_w), args.pixel_w)
        if prev == src:
            src_read += prev_bytes
        else:
            inter_read += prev_bytes
        inter_write += cur_bytes
        cycles += prev_bytes + cur_bytes * 1.2
        max_rows = max(max_rows, int(math.ceil(fy)))
        max_acc_bits = max(max_acc_bits, accumulator_bits(args.pixel_w, fx, fy))
    final_read = dst.w * dst.h * 4 * args.pixel_w
    inter_read += final_read
    dst_bytes = image_bytes(dst, args.dst_stride, args.pixel_w)
    cycles += final_read * 1.25 + dst_bytes
    notes_chain = " -> ".join([f"{s.w}x{s.h}" for s in [src] + chain + [dst]])
    return {
        "mode": "prefilter_multistage",
        **base_fields(args, src, dst),
        "intermediate_w": chain[-1].w if chain else 0,
        "intermediate_h": chain[-1].h if chain else 0,
        "num_passes": len(chain) + 1,
        "estimated_src_read_bytes": int(src_read),
        "estimated_intermediate_write_bytes": int(inter_write),
        "estimated_intermediate_read_bytes": int(inter_read),
        "estimated_dst_write_bytes": int(dst_bytes),
        "estimated_total_bytes": int(src_read + inter_write + inter_read + dst_bytes),
        "estimated_total_cycles": int(cycles),
        "cache_locality_score": "0.900",
        "required_line_buffer_rows": max_rows,
        "accumulator_bit_width": max_acc_bits,
        "bram_estimate_bytes": int(max_rows * max(s.w for s in sizes) * args.pixel_w),
        "notes": f"chain={notes_chain}; extra DDR passes but each pass is regular",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src-w", type=int, required=True)
    parser.add_argument("--src-h", type=int, required=True)
    parser.add_argument("--dst-w", type=int, required=True)
    parser.add_argument("--dst-h", type=int, required=True)
    parser.add_argument("--angle-deg", type=float, default=0.0)
    parser.add_argument("--pixel-w", type=int, default=1, help="Pixel width in bytes.")
    parser.add_argument("--src-stride", type=int, default=0, help="Source stride bytes, 0 means packed.")
    parser.add_argument("--dst-stride", type=int, default=0, help="Destination stride bytes, 0 means packed.")
    parser.add_argument("--intermediate-list", default="")
    parser.add_argument("--mode", choices=("direct_bilinear", "prefilter_box", "prefilter_multistage", "all"), default="all")
    parser.add_argument("--out-dir", default="sim_out/large_downscale_model")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    src = ImageSize(args.src_w, args.src_h)
    dst = ImageSize(args.dst_w, args.dst_h)
    intermediates = parse_size_list(args.intermediate_list)
    rows: list[dict[str, object]] = []
    if args.mode in ("direct_bilinear", "all"):
        rows.append(row_for_direct(args, src, dst))
    if args.mode in ("prefilter_box", "all"):
        for inter in intermediates:
            rows.append(row_for_box(args, src, dst, inter))
    if args.mode in ("prefilter_multistage", "all"):
        for chain in default_multistage(src, dst, intermediates):
            rows.append(row_for_multistage(args, src, dst, chain))

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_csv = out_dir / "summary.csv"
    fields = [
        "mode", "src_w", "src_h", "dst_w", "dst_h", "angle_deg", "scale_x", "scale_y", "scale_ratio",
        "intermediate_w", "intermediate_h", "num_passes", "estimated_src_read_bytes",
        "estimated_intermediate_write_bytes", "estimated_intermediate_read_bytes", "estimated_dst_write_bytes",
        "estimated_total_bytes", "estimated_total_cycles", "cache_locality_score", "required_line_buffer_rows",
        "accumulator_bit_width", "bram_estimate_bytes", "notes",
    ]
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {out_csv} ({len(rows)} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
