#include <stdint.h>
#include "xil_cache.h"
#include "xil_printf.h"
#include "image_geo_regs.h"

/*
 * Bare-metal example for PYNQ-Z2 / Zynq-7000.
 *
 * Replace IMAGE_GEO_BASEADDR with the address assigned in Vivado Address Editor
 * or xparameters.h.
 *
 * Replace the source/destination DDR addresses with valid buffers that are
 * accessible through the PS DDR memory map and coherent with your software
 * flow.
 */

#define IMAGE_GEO_BASEADDR   ((uintptr_t)0x43C00000u)
#define SRC_BASEADDR         ((uint32_t)0x10000000u)
#define DST_BASEADDR         ((uint32_t)0x11000000u)
#define IMAGE_GEO_TIMEOUT    (100000000u)

static int image_geo_wait_done(uintptr_t base, uint32_t timeout_cycles)
{
    uint32_t count = 0;

    while (!image_geo_is_done(base)) {
        if (image_geo_has_error(base)) {
            xil_printf("image_geo_top reported ERROR, status=0x%08lx\r\n",
                (unsigned long)image_geo_get_status(base));
            return -1;
        }

        if (count++ >= timeout_cycles) {
            xil_printf("image_geo_top timeout, status=0x%08lx\r\n",
                (unsigned long)image_geo_get_status(base));
            return -2;
        }
    }

    return 0;
}

static void image_geo_dump_stats(uintptr_t base, const char *tag)
{
    image_geo_cache_stats_t stats;

    image_geo_get_cache_stats(base, &stats);
    xil_printf("%s stats: reads=%lu misses=%lu prefetches=%lu hits=%lu\r\n",
        tag,
        (unsigned long)stats.reads,
        (unsigned long)stats.misses,
        (unsigned long)stats.prefetches,
        (unsigned long)stats.hits);
}

static int image_geo_run_case(
    const char *tag,
    uint16_t src_w,
    uint16_t src_h,
    uint16_t dst_w,
    uint16_t dst_h,
    uint32_t src_stride,
    uint32_t dst_stride,
    int32_t rot_sin_q16,
    int32_t rot_cos_q16,
    int prefetch_enable
)
{
    int rc;
    uint32_t src_bytes;
    uint32_t dst_bytes;

    xil_printf("Running %s\r\n", tag);
    image_geo_clear_status(IMAGE_GEO_BASEADDR);
    image_geo_set_prefetch(IMAGE_GEO_BASEADDR, prefetch_enable);

    src_bytes = src_stride * (uint32_t)src_h;
    dst_bytes = dst_stride * (uint32_t)dst_h;

    /*
     * PYNQ-Z2 uses PS caches in front of DDR. Flush source before PL reads it
     * and invalidate destination after PL writes it back.
     */
    Xil_DCacheFlushRange((UINTPTR)SRC_BASEADDR, src_bytes);
    Xil_DCacheFlushRange((UINTPTR)DST_BASEADDR, dst_bytes);

    image_geo_program_frame(
        IMAGE_GEO_BASEADDR,
        SRC_BASEADDR,
        DST_BASEADDR,
        src_stride,
        dst_stride,
        src_w,
        src_h,
        dst_w,
        dst_h,
        rot_sin_q16,
        rot_cos_q16
    );

    image_geo_start(IMAGE_GEO_BASEADDR, 1);
    rc = image_geo_wait_done(IMAGE_GEO_BASEADDR, IMAGE_GEO_TIMEOUT);
    Xil_DCacheInvalidateRange((UINTPTR)DST_BASEADDR, dst_bytes);
    image_geo_dump_stats(IMAGE_GEO_BASEADDR, tag);

    if (rc != 0) {
        return rc;
    }

    return 0;
}

int image_geo_run_example(void)
{
    int rc;

    xil_printf("image_geo_top bare-metal demo start\r\n");

    rc = image_geo_run_case(
        "identity_7200_to_600_prefetch_on",
        7200u, 7200u,
        600u,  600u,
        7200u,
        600u,
        IMAGE_GEO_Q16_ZERO,
        IMAGE_GEO_Q16_ONE,
        1
    );
    if (rc != 0) {
        return rc;
    }

    rc = image_geo_run_case(
        "rotate90_7200_to_600_prefetch_on",
        7200u, 7200u,
        600u,  600u,
        7200u,
        600u,
        IMAGE_GEO_Q16_SIN_90,
        IMAGE_GEO_Q16_COS_90,
        1
    );
    if (rc != 0) {
        return rc;
    }

    xil_printf("image_geo_top bare-metal demo done\r\n");
    return 0;
}
