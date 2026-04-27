#include "image_geo_driver.h"

#include "xil_cache.h"

static void image_geo_driver_fill_common_response(
    uintptr_t ip_baseaddr,
    uint32_t status,
    uint32_t output_bytes,
    image_geo_response_v1_t *resp
)
{
    image_geo_cache_stats_t stats;

    if (resp == 0) {
        return;
    }

    resp->magic = IMAGE_GEO_PROTO_MAGIC_RESP;
    resp->version = IMAGE_GEO_PROTO_VERSION_V1;
    resp->status = status;
    resp->output_bytes = output_bytes;
    resp->hw_status_reg = image_geo_get_status(ip_baseaddr);

    image_geo_get_cache_stats(ip_baseaddr, &stats);
    resp->cache_reads = stats.reads;
    resp->cache_misses = stats.misses;
    resp->cache_prefetches = stats.prefetches;
    resp->cache_hits = stats.hits;
}

static int image_geo_driver_wait_done(uintptr_t ip_baseaddr, uint32_t timeout_cycles)
{
    uint32_t count = 0u;

    while (!image_geo_is_done(ip_baseaddr)) {
        if (image_geo_has_error(ip_baseaddr)) {
            return IMAGE_GEO_STATUS_HW_ERROR;
        }

        if (count++ >= timeout_cycles) {
            return IMAGE_GEO_STATUS_HW_TIMEOUT;
        }
    }

    return IMAGE_GEO_STATUS_OK;
}

int image_geo_driver_validate_request(
    const image_geo_request_v1_t *req,
    const image_geo_driver_limits_t *limits
)
{
    uint32_t src_bytes;
    uint32_t dst_bytes;

    if (req == 0 || limits == 0) {
        return IMAGE_GEO_STATUS_BAD_PARAM;
    }

    if (req->magic != IMAGE_GEO_PROTO_MAGIC_REQ) {
        return IMAGE_GEO_STATUS_BAD_MAGIC;
    }

    if (req->version != IMAGE_GEO_PROTO_VERSION_V1) {
        return IMAGE_GEO_STATUS_BAD_VERSION;
    }

    if (req->command != IMAGE_GEO_CMD_RUN_FRAME) {
        return IMAGE_GEO_STATUS_BAD_COMMAND;
    }

    if (req->src_w == 0u || req->src_h == 0u || req->dst_w == 0u || req->dst_h == 0u) {
        return IMAGE_GEO_STATUS_BAD_PARAM;
    }

    if (req->src_stride < req->src_w || req->dst_stride < req->dst_w) {
        return IMAGE_GEO_STATUS_BAD_PARAM;
    }

    src_bytes = image_geo_request_expected_bytes(req);
    dst_bytes = image_geo_response_expected_bytes(req->dst_stride, req->dst_h);

    if (req->payload_bytes != src_bytes) {
        return IMAGE_GEO_STATUS_PAYLOAD_SIZE_MISMATCH;
    }

    if (src_bytes > limits->src_ddr_capacity || dst_bytes > limits->dst_ddr_capacity) {
        return IMAGE_GEO_STATUS_BAD_PARAM;
    }

    return IMAGE_GEO_STATUS_OK;
}

int image_geo_driver_run(
    const image_geo_request_v1_t *req,
    const image_geo_driver_limits_t *limits,
    image_geo_response_v1_t *resp
)
{
    int status;
    uint32_t src_bytes;
    uint32_t dst_bytes;

    status = image_geo_driver_validate_request(req, limits);
    src_bytes = image_geo_request_expected_bytes(req);
    dst_bytes = image_geo_response_expected_bytes(req->dst_stride, req->dst_h);

    if (status != IMAGE_GEO_STATUS_OK) {
        image_geo_driver_fill_common_response(
            limits != 0 ? limits->ip_baseaddr : 0u,
            (uint32_t)status,
            dst_bytes,
            resp
        );
        return status;
    }

    /*
     * 这里默认源图数据已经被上层接收到 limits->src_ddr_base 所指向的 DDR 区域，
     * 目标缓冲区也已经由上层清零或做好准备。
     */
    image_geo_clear_status(limits->ip_baseaddr);
    image_geo_set_prefetch(limits->ip_baseaddr, req->prefetch_enable != 0u);

    Xil_DCacheFlushRange((UINTPTR)limits->src_ddr_base, src_bytes);
    Xil_DCacheFlushRange((UINTPTR)limits->dst_ddr_base, dst_bytes);

    image_geo_program_frame(
        limits->ip_baseaddr,
        limits->src_ddr_base,
        limits->dst_ddr_base,
        req->src_stride,
        req->dst_stride,
        (uint16_t)req->src_w,
        (uint16_t)req->src_h,
        (uint16_t)req->dst_w,
        (uint16_t)req->dst_h,
        req->rot_sin_q16,
        req->rot_cos_q16
    );

    image_geo_start(limits->ip_baseaddr, 0);
    status = image_geo_driver_wait_done(limits->ip_baseaddr, limits->timeout_cycles);

    Xil_DCacheInvalidateRange((UINTPTR)limits->dst_ddr_base, dst_bytes);

    image_geo_driver_fill_common_response(
        limits->ip_baseaddr,
        (uint32_t)status,
        dst_bytes,
        resp
    );

    return status;
}
