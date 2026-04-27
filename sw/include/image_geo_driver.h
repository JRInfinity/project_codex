#ifndef IMAGE_GEO_DRIVER_H
#define IMAGE_GEO_DRIVER_H

#include <stdint.h>
#include "image_geo_protocol.h"
#include "image_geo_regs.h"

/*
 * image_geo_top 裸机驱动辅助层。
 *
 * 这一层负责：
 * - 校验一次请求是否合理
 * - 根据请求配置寄存器
 * - 启动硬件并等待完成
 * - 汇总响应头中的状态和统计信息
 */

typedef struct image_geo_driver_limits_t {
    uintptr_t ip_baseaddr;
    uint32_t src_ddr_base;
    uint32_t dst_ddr_base;
    uint32_t src_ddr_capacity;
    uint32_t dst_ddr_capacity;
    uint32_t timeout_cycles;
} image_geo_driver_limits_t;

int image_geo_driver_validate_request(
    const image_geo_request_v1_t *req,
    const image_geo_driver_limits_t *limits
);

int image_geo_driver_run(
    const image_geo_request_v1_t *req,
    const image_geo_driver_limits_t *limits,
    image_geo_response_v1_t *resp
);

#endif /* IMAGE_GEO_DRIVER_H */
