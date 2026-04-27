#ifndef IMAGE_GEO_PROTOCOL_H
#define IMAGE_GEO_PROTOCOL_H

#include <stdint.h>

/*
 * PC 与 Zynq PS 应用程序之间的运行时请求/响应协议。
 *
 * v1 设计目标：
 * - 使用固定长度请求头和响应头，便于裸机侧解析
 * - 负载紧跟在请求头或响应头之后发送
 * - 既容易在 bare-metal C 中处理，也容易在 Python 中打包/解包
 * - 头部字段足够描述一次 image_geo_top 运行，不需要为每种参数重新编译板端程序
 *
 * 当前传输假设：
 * - 基于 UART 这类字节流接口
 * - 两端都按小端格式解释头部字段
 */

#define IMAGE_GEO_PROTO_MAGIC_REQ   0x51454749u /* "IGEQ" */
#define IMAGE_GEO_PROTO_MAGIC_RESP  0x53454749u /* "IGES" */
#define IMAGE_GEO_PROTO_VERSION_V1  1u

enum image_geo_proto_command_e {
    IMAGE_GEO_CMD_RUN_FRAME = 1u,
};

enum image_geo_proto_status_e {
    IMAGE_GEO_STATUS_OK = 0u,
    IMAGE_GEO_STATUS_BAD_MAGIC = 1u,
    IMAGE_GEO_STATUS_BAD_VERSION = 2u,
    IMAGE_GEO_STATUS_BAD_COMMAND = 3u,
    IMAGE_GEO_STATUS_BAD_PARAM = 4u,
    IMAGE_GEO_STATUS_RX_TIMEOUT = 5u,
    IMAGE_GEO_STATUS_PAYLOAD_SIZE_MISMATCH = 6u,
    IMAGE_GEO_STATUS_HW_ERROR = 7u,
    IMAGE_GEO_STATUS_HW_TIMEOUT = 8u,
    IMAGE_GEO_STATUS_TX_ERROR = 9u,
};

typedef struct image_geo_request_v1_t {
    uint32_t magic;
    uint32_t version;
    uint32_t command;
    uint32_t src_w;
    uint32_t src_h;
    uint32_t src_stride;
    uint32_t dst_w;
    uint32_t dst_h;
    uint32_t dst_stride;
    int32_t rot_sin_q16;
    int32_t rot_cos_q16;
    uint32_t prefetch_enable;
    uint32_t payload_bytes;
} image_geo_request_v1_t;

typedef struct image_geo_response_v1_t {
    uint32_t magic;
    uint32_t version;
    uint32_t status;
    uint32_t output_bytes;
    uint32_t hw_status_reg;
    uint32_t cache_reads;
    uint32_t cache_misses;
    uint32_t cache_prefetches;
    uint32_t cache_hits;
} image_geo_response_v1_t;

static inline uint32_t image_geo_request_expected_bytes(const image_geo_request_v1_t *req)
{
    if (req == 0) {
        return 0u;
    }

    return req->src_stride * req->src_h;
}

static inline uint32_t image_geo_response_expected_bytes(uint32_t dst_stride, uint32_t dst_h)
{
    return dst_stride * dst_h;
}

#endif /* IMAGE_GEO_PROTOCOL_H */
