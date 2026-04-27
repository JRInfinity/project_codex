#!/usr/bin/env python3
"""Quality golden for large downscale research pipelines."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

import numpy as np

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None


def parse_csv_list(text: str) -> list[str]:
    return [item.strip() for item in text.split(",") if item.strip()]


def pattern_image(name: str, h: int, w: int) -> np.ndarray:
    yy, xx = np.indices((h, w))
    if name == "checkerboard":
        return (((xx // 5 + yy // 7) & 1) * 255).astype(np.float32)
    if name in ("stripes", "high_frequency_stripes"):
        return (((xx // 5) & 1) * 255).astype(np.float32)
    if name == "diagonal":
        return np.where(np.abs(xx - yy) <= 2, 255, 0).astype(np.float32)
    if name == "ramp":
        return ((xx + yy) * 255.0 / max(1, w + h - 2)).astype(np.float32)
    if name in ("noise", "random_texture"):
        rng = np.random.default_rng(12345)
        return rng.integers(0, 256, size=(h, w)).astype(np.float32)
    if name in ("lowpass", "lowpass_natural_like_noise"):
        rng = np.random.default_rng(54321)
        base = rng.normal(127.0, 45.0, size=(h, w)).astype(np.float32)
        for _ in range(4):
            base = (
                base
                + np.roll(base, 1, 0) + np.roll(base, -1, 0)
                + np.roll(base, 1, 1) + np.roll(base, -1, 1)
            ) / 5.0
        return np.clip(base, 0, 255)
    raise ValueError(f"unknown pattern '{name}'")


def bilinear_resize(src: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = src.shape
    if out_h == in_h and out_w == in_w:
        return src.copy()
    y = (np.arange(out_h, dtype=np.float32) + 0.5) * in_h / out_h - 0.5
    x = (np.arange(out_w, dtype=np.float32) + 0.5) * in_w / out_w - 0.5
    y0 = np.floor(y).astype(np.int32)
    x0 = np.floor(x).astype(np.int32)
    y1 = np.clip(y0 + 1, 0, in_h - 1)
    x1 = np.clip(x0 + 1, 0, in_w - 1)
    y0 = np.clip(y0, 0, in_h - 1)
    x0 = np.clip(x0, 0, in_w - 1)
    wy = (y - y0).reshape(out_h, 1)
    wx = (x - x0).reshape(1, out_w)
    top = src[y0[:, None], x0[None, :]] * (1.0 - wx) + src[y0[:, None], x1[None, :]] * wx
    bot = src[y1[:, None], x0[None, :]] * (1.0 - wx) + src[y1[:, None], x1[None, :]] * wx
    return top * (1.0 - wy) + bot * wy


def area_resize(src: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = src.shape
    if in_h % out_h == 0 and in_w % out_w == 0:
        fy = in_h // out_h
        fx = in_w // out_w
        return src.reshape(out_h, fy, out_w, fx).mean(axis=(1, 3))
    samples = 8
    out = np.zeros((out_h, out_w), dtype=np.float32)
    for sy in range(samples):
        y = (np.arange(out_h) + (sy + 0.5) / samples) * in_h / out_h
        iy = np.clip(y.astype(np.int32), 0, in_h - 1)
        for sx in range(samples):
            x = (np.arange(out_w) + (sx + 0.5) / samples) * in_w / out_w
            ix = np.clip(x.astype(np.int32), 0, in_w - 1)
            out += src[iy[:, None], ix[None, :]]
    return out / (samples * samples)


def separable_box_then_bilinear(src: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = src.shape
    ratio = max(in_w / out_w, in_h / out_h)
    factor = 4 if ratio >= 8 else 2 if ratio >= 4 else 1
    inter_h = max(out_h, in_h // factor)
    inter_w = max(out_w, in_w // factor)
    return bilinear_resize(area_resize(src, inter_h, inter_w), out_h, out_w)


def multistage_box_then_bilinear(src: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    cur = src
    for _ in range(8):
        ratio_y = cur.shape[0] / out_h
        ratio_x = cur.shape[1] / out_w
        if ratio_y <= 1.0 and ratio_x <= 1.0:
            break
        integer_ratio = (
            abs(ratio_y - round(ratio_y)) < 1e-6
            and abs(ratio_x - round(ratio_x)) < 1e-6
            and int(round(ratio_y)) == int(round(ratio_x))
        )
        if not integer_ratio:
            break
        ratio = int(round(ratio_x))
        factor = 1
        for candidate in (4, 3, 2):
            if ratio % candidate == 0:
                factor = candidate
                break
        if factor == 1:
            break
        cur = area_resize(cur, max(out_h, cur.shape[0] // factor), max(out_w, cur.shape[1] // factor))
    return bilinear_resize(cur, out_h, out_w)


def run_method(method: str, src: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    if method == "direct_bilinear":
        return bilinear_resize(src, out_h, out_w)
    if method == "box_area_reference":
        return area_resize(src, out_h, out_w)
    if method == "separable_box_then_bilinear":
        return separable_box_then_bilinear(src, out_h, out_w)
    if method == "multistage_box_then_bilinear":
        return multistage_box_then_bilinear(src, out_h, out_w)
    raise ValueError(f"unknown method '{method}'")


def high_frequency_energy(img: np.ndarray) -> float:
    centered = img - float(np.mean(img))
    spec = np.fft.fftshift(np.fft.fft2(centered))
    power = np.abs(spec) ** 2
    h, w = img.shape
    yy, xx = np.indices((h, w))
    radius = np.sqrt((yy - h / 2) ** 2 + (xx - w / 2) ** 2)
    mask = radius > 0.35 * min(h, w)
    return float(power[mask].mean() / max(1.0, power.mean()))


def edge_aliasing_score(img: np.ndarray) -> float:
    dx = np.abs(np.diff(img, axis=1)).mean()
    dy = np.abs(np.diff(img, axis=0)).mean()
    return float((dx + dy) / 2.0)


def metrics(pattern: str, method: str, src: np.ndarray, out: np.ndarray, ref: np.ndarray) -> dict[str, object]:
    diff = out - ref
    mse = float(np.mean(diff * diff))
    psnr = 99.0 if mse == 0 else 20.0 * math.log10(255.0 / math.sqrt(mse))
    return {
        "pattern": pattern,
        "method": method,
        "mse": f"{mse:.6f}",
        "psnr": f"{psnr:.3f}",
        "max_abs_error": f"{float(np.max(np.abs(diff))):.3f}",
        "edge_aliasing_score": f"{edge_aliasing_score(out):.6f}",
        "high_frequency_energy_before": f"{high_frequency_energy(src):.6f}",
        "high_frequency_energy_after": f"{high_frequency_energy(out):.6f}",
    }


def save_png(path: Path, img: np.ndarray) -> None:
    if Image is None:
        return
    arr = np.clip(np.rint(img), 0, 255).astype(np.uint8)
    Image.fromarray(arr, mode="L").save(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src-w", type=int, required=True)
    parser.add_argument("--src-h", type=int, required=True)
    parser.add_argument("--dst-w", type=int, required=True)
    parser.add_argument("--dst-h", type=int, required=True)
    parser.add_argument("--patterns", default="checkerboard,stripes,diagonal,ramp,noise,lowpass")
    parser.add_argument("--methods", default="direct_bilinear,box_area_reference,separable_box_then_bilinear,multistage_box_then_bilinear")
    parser.add_argument("--out-dir", default="sim_out/large_downscale_quality")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    patterns = parse_csv_list(args.patterns)
    methods = parse_csv_list(args.methods)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, object]] = []
    representative: dict[str, np.ndarray] = {}
    for pattern in patterns:
        src = pattern_image(pattern, args.src_h, args.src_w)
        ref = run_method("box_area_reference", src, args.dst_h, args.dst_w)
        if not representative:
            representative["input"] = src
            representative["area_reference"] = ref
        for method in methods:
            out = run_method(method, src, args.dst_h, args.dst_w)
            rows.append(metrics(pattern, method, src, out, ref))
            if pattern == patterns[0]:
                if method == "direct_bilinear":
                    representative["direct_bilinear"] = out
                    representative["diff_direct_vs_area"] = np.abs(out - ref) * 4.0
                if method == "multistage_box_then_bilinear":
                    representative["multistage"] = out
                    representative["diff_multistage_vs_area"] = np.abs(out - ref) * 4.0

    csv_path = out_dir / "quality_report.csv"
    fields = [
        "pattern", "method", "mse", "psnr", "max_abs_error", "edge_aliasing_score",
        "high_frequency_energy_before", "high_frequency_energy_after",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    for name, img in representative.items():
        save_png(out_dir / f"{name}.png", img)

    direct_rows = [r for r in rows if r["method"] == "direct_bilinear"]
    multi_rows = [r for r in rows if r["method"] == "multistage_box_then_bilinear"]
    direct_mse = float(np.mean([float(r["mse"]) for r in direct_rows])) if direct_rows else 0.0
    multi_mse = float(np.mean([float(r["mse"]) for r in multi_rows])) if multi_rows else 0.0
    conclusion = (
        "direct bilinear shows clear aliasing risk for this scale bucket"
        if direct_mse > max(1.0, multi_mse * 2.0)
        else "direct bilinear risk is pattern-dependent in this smoke"
    )
    md_path = out_dir / "quality_report.md"
    with md_path.open("w", encoding="utf-8") as f:
        f.write("# Large Downscale Quality Report\n\n")
        f.write(f"- Source: {args.src_w}x{args.src_h}\n")
        f.write(f"- Destination: {args.dst_w}x{args.dst_h}\n")
        f.write(f"- Scale ratio: {max(args.src_w / args.dst_w, args.src_h / args.dst_h):.3f}\n")
        f.write(f"- Average direct-bilinear MSE vs area reference: {direct_mse:.3f}\n")
        f.write(f"- Average multistage MSE vs area reference: {multi_mse:.3f}\n")
        f.write(f"- Research conclusion: {conclusion}.\n\n")
        f.write("This report is not RTL bit-exact. It is a quality golden for deciding whether large_downscale_preprocess deserves RTL planning.\n\n")
        f.write("| Pattern | Method | MSE | PSNR | Max abs error | Edge aliasing | HF before | HF after |\n")
        f.write("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |\n")
        for r in rows:
            f.write(
                f"| {r['pattern']} | {r['method']} | {r['mse']} | {r['psnr']} | "
                f"{r['max_abs_error']} | {r['edge_aliasing_score']} | "
                f"{r['high_frequency_energy_before']} | {r['high_frequency_energy_after']} |\n"
            )

    print(f"wrote {csv_path} and {md_path} ({len(rows)} rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
