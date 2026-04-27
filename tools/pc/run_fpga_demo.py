#!/usr/bin/env python3
"""
PC 端 UART 图像传输与显示工具。

功能：
1. 读取输入 .bin
2. 按约定协议通过串口发送请求头和图像负载
3. 接收板端响应头和输出负载
4. 保存输出 .bin
5. 在 PC 上显示输入图和输出图
"""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


IMAGE_GEO_PROTO_MAGIC_REQ = 0x51454749
IMAGE_GEO_PROTO_MAGIC_RESP = 0x53454749
IMAGE_GEO_PROTO_VERSION_V1 = 1
IMAGE_GEO_CMD_RUN_FRAME = 1

STATUS_TEXT = {
    0: "成功",
    1: "请求 magic 错误",
    2: "协议版本错误",
    3: "命令字错误",
    4: "参数错误",
    5: "接收超时",
    6: "负载长度不匹配",
    7: "硬件处理报错",
    8: "硬件处理超时",
    9: "发送失败",
}

REQ_STRUCT = struct.Struct("<IIIIIIIIIiiII")
RESP_STRUCT = struct.Struct("<IIIIIIIII")


@dataclass
class RequestArgs:
    src_w: int
    src_h: int
    src_stride: int
    dst_w: int
    dst_h: int
    dst_stride: int
    rot_sin_q16: int
    rot_cos_q16: int
    prefetch_enable: int
    payload_bytes: int


@dataclass
class ResponsePacket:
    magic: int
    version: int
    status: int
    output_bytes: int
    hw_status_reg: int
    cache_reads: int
    cache_misses: int
    cache_prefetches: int
    cache_hits: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="通过 UART 将图像发送到 FPGA 板端并显示返回结果。")
    parser.add_argument("--port", required=True, help="串口号，例如 COM5")
    parser.add_argument("--baudrate", type=int, default=921600, help="串口波特率，默认 921600")
    parser.add_argument("--input-bin", required=True, help="输入灰度图 .bin 文件路径")
    parser.add_argument("--output-bin", default=None, help="输出 .bin 文件路径，默认与输入同目录")
    parser.add_argument("--src-w", type=int, required=True, help="输入图宽")
    parser.add_argument("--src-h", type=int, required=True, help="输入图高")
    parser.add_argument("--src-stride", type=int, default=None, help="输入图 stride，默认等于 src_w")
    parser.add_argument("--dst-w", type=int, required=True, help="输出图宽")
    parser.add_argument("--dst-h", type=int, required=True, help="输出图高")
    parser.add_argument("--dst-stride", type=int, default=None, help="输出图 stride，默认等于 dst_w")
    parser.add_argument("--rot-sin-q16", type=int, default=0, help="旋转正弦 Q16 值")
    parser.add_argument("--rot-cos-q16", type=int, default=65536, help="旋转余弦 Q16 值")
    parser.add_argument("--prefetch-enable", type=int, choices=(0, 1), default=1, help="是否开启预取")
    parser.add_argument("--timeout", type=float, default=20.0, help="串口读超时秒数")
    parser.add_argument("--no-show", action="store_true", help="只保存输出，不显示图像")
    return parser.parse_args()


def build_request(req: RequestArgs) -> bytes:
    return REQ_STRUCT.pack(
        IMAGE_GEO_PROTO_MAGIC_REQ,
        IMAGE_GEO_PROTO_VERSION_V1,
        IMAGE_GEO_CMD_RUN_FRAME,
        req.src_w,
        req.src_h,
        req.src_stride,
        req.dst_w,
        req.dst_h,
        req.dst_stride,
        req.rot_sin_q16,
        req.rot_cos_q16,
        req.prefetch_enable,
        req.payload_bytes,
    )


def read_exact(ser, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = ser.read(size - len(data))
        if not chunk:
            raise TimeoutError(f"串口读取超时，期望 {size} 字节，实际只收到 {len(data)} 字节")
        data.extend(chunk)
    return bytes(data)


def recv_response(ser) -> ResponsePacket:
    raw = read_exact(ser, RESP_STRUCT.size)
    fields = RESP_STRUCT.unpack(raw)
    return ResponsePacket(*fields)


def ensure_input_size(path: Path, expected_bytes: int) -> bytes:
    payload = path.read_bytes()
    if len(payload) != expected_bytes:
        raise ValueError(f"输入文件大小不匹配：实际 {len(payload)} 字节，期望 {expected_bytes} 字节")
    return payload


def choose_output_path(input_path: Path, output_arg: str | None) -> Path:
    if output_arg:
        return Path(output_arg)
    return input_path.with_name(f"{input_path.stem}_fpga_out.bin")


def show_images(input_payload: bytes, output_payload: bytes, req: RequestArgs) -> None:
    import matplotlib.pyplot as plt
    import numpy as np

    src_img = np.frombuffer(input_payload, dtype=np.uint8).reshape(req.src_h, req.src_stride)[:, :req.src_w]
    dst_img = np.frombuffer(output_payload, dtype=np.uint8).reshape(req.dst_h, req.dst_stride)[:, :req.dst_w]

    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    axes[0].imshow(src_img, cmap="gray", vmin=0, vmax=255)
    axes[0].set_title("输入图")
    axes[0].axis("off")

    axes[1].imshow(dst_img, cmap="gray", vmin=0, vmax=255)
    axes[1].set_title("输出图")
    axes[1].axis("off")

    fig.tight_layout()
    plt.show()


def main() -> int:
    args = parse_args()

    try:
        import serial
    except ImportError as exc:
        print("缺少 pyserial，请先执行: pip install pyserial", file=sys.stderr)
        raise SystemExit(1) from exc

    input_path = Path(args.input_bin)
    output_path = choose_output_path(input_path, args.output_bin)

    src_stride = args.src_stride if args.src_stride is not None else args.src_w
    dst_stride = args.dst_stride if args.dst_stride is not None else args.dst_w
    payload_bytes = src_stride * args.src_h

    req = RequestArgs(
        src_w=args.src_w,
        src_h=args.src_h,
        src_stride=src_stride,
        dst_w=args.dst_w,
        dst_h=args.dst_h,
        dst_stride=dst_stride,
        rot_sin_q16=args.rot_sin_q16,
        rot_cos_q16=args.rot_cos_q16,
        prefetch_enable=args.prefetch_enable,
        payload_bytes=payload_bytes,
    )

    payload = ensure_input_size(input_path, payload_bytes)
    req_header = build_request(req)

    print(f"打开串口: {args.port} @ {args.baudrate}")
    print(f"输入文件: {input_path}")
    print(f"输出文件: {output_path}")
    print(f"输入参数: src={req.src_w}x{req.src_h} stride={req.src_stride}")
    print(f"输出参数: dst={req.dst_w}x{req.dst_h} stride={req.dst_stride}")
    print(f"旋转参数: sin_q16={req.rot_sin_q16} cos_q16={req.rot_cos_q16}")

    with serial.Serial(args.port, args.baudrate, timeout=args.timeout, write_timeout=args.timeout) as ser:
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print("发送请求头...")
        ser.write(req_header)
        ser.flush()

        print(f"发送图像负载，共 {len(payload)} 字节...")
        ser.write(payload)
        ser.flush()

        print("等待板端响应头...")
        resp = recv_response(ser)

        print("收到响应头：")
        print(f"  magic        = 0x{resp.magic:08X}")
        print(f"  version      = {resp.version}")
        print(f"  status       = {resp.status} ({STATUS_TEXT.get(resp.status, '未知状态')})")
        print(f"  output_bytes = {resp.output_bytes}")
        print(f"  hw_status    = 0x{resp.hw_status_reg:08X}")
        print(
            "  cache        = "
            f"reads={resp.cache_reads}, misses={resp.cache_misses}, "
            f"prefetches={resp.cache_prefetches}, hits={resp.cache_hits}"
        )

        if resp.magic != IMAGE_GEO_PROTO_MAGIC_RESP:
            raise RuntimeError(f"响应 magic 错误：0x{resp.magic:08X}")
        if resp.version != IMAGE_GEO_PROTO_VERSION_V1:
            raise RuntimeError(f"响应版本错误：{resp.version}")
        if resp.status != 0:
            raise RuntimeError(f"板端返回错误状态：{resp.status} ({STATUS_TEXT.get(resp.status, '未知状态')})")

        print("接收输出负载...")
        output_payload = read_exact(ser, resp.output_bytes)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(output_payload)
    print(f"输出已保存到: {output_path}")

    if not args.no_show:
        try:
            show_images(payload, output_payload, req)
        except ImportError:
            print("缺少 numpy 或 matplotlib，无法显示图像。可执行: pip install numpy matplotlib", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
