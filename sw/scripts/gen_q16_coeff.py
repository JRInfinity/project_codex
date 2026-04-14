#!/usr/bin/env python3
"""
Generate signed Q16 sine/cosine coefficients for image_geo_top.

Examples:
    python sw/scripts/gen_q16_coeff.py 45
    python sw/scripts/gen_q16_coeff.py 90 --format c
"""

from __future__ import annotations

import argparse
import math


Q16_SCALE = 1 << 16


def clamp_q16(value: float) -> int:
    scaled = int(round(value * Q16_SCALE))
    if scaled > 0x7FFFFFFF:
        scaled = 0x7FFFFFFF
    if scaled < -0x80000000:
        scaled = -0x80000000
    return scaled


def to_u32(value: int) -> int:
    return value & 0xFFFFFFFF


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Q16 sine/cosine coefficients.")
    parser.add_argument("angle_deg", type=float, help="Rotation angle in degrees")
    parser.add_argument(
        "--format",
        choices=("text", "c"),
        default="text",
        help="Output style",
    )
    args = parser.parse_args()

    rad = math.radians(args.angle_deg)
    sin_q16 = clamp_q16(math.sin(rad))
    cos_q16 = clamp_q16(math.cos(rad))

    if args.format == "c":
        print(f"/* angle = {args.angle_deg:g} deg */")
        print(f"#define IMAGE_GEO_SIN_Q16 0x{to_u32(sin_q16):08X}u")
        print(f"#define IMAGE_GEO_COS_Q16 0x{to_u32(cos_q16):08X}u")
        return

    print(f"angle_deg : {args.angle_deg:g}")
    print(f"sin       : {math.sin(rad): .8f}")
    print(f"cos       : {math.cos(rad): .8f}")
    print(f"sin_q16   : 0x{to_u32(sin_q16):08X}")
    print(f"cos_q16   : 0x{to_u32(cos_q16):08X}")


if __name__ == "__main__":
    main()
