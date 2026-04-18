#include <stdint.h>
#include "xil_cache.h"
#include "xil_printf.h"
#include "image_geo_regs.h"

/*
 * Minimal bare-metal bring-up example for the current PYNQ-Z2 design.
 *
 * Address assumptions from the user's Vivado Address Editor screenshot:
 * - image_geo_top_0/s_axi_ctrl = 0x4000_0000
 * - HP0 DDR window            = 0x0000_0000 ~ 0x1FFF_FFFF
 *
 * This first-stage test keeps everything small and simple:
 * - source image in DDR      : 64 x 64, 8-bit grayscale
 * - destination image in DDR : 64 x 64, 8-bit grayscale
 * - transform                : identity (sin = 0, cos = 1)
 *
 * Expected result:
 * - DONE is asserted
 * - ERROR remains clear
 * - destination buffer matches source buffer exactly
 */

#define IMAGE_GEO_BASEADDR   ((uintptr_t)0x40000000u)
#define SRC_BASEADDR         ((uint32_t)0x10000000u)
#define DST_BASEADDR         ((uint32_t)0x12000000u)
#define IMAGE_GEO_TIMEOUT    (100000000u)

#define TEST_SRC_W           64u
#define TEST_SRC_H           64u
#define TEST_DST_W           64u
#define TEST_DST_H           64u
#define TEST_SRC_STRIDE      64u
#define TEST_DST_STRIDE      64u

static volatile uint8_t *const g_src_buf = (volatile uint8_t *)SRC_BASEADDR;
static volatile uint8_t *const g_dst_buf = (volatile uint8_t *)DST_BASEADDR;

static uint32_t image_geo_src_bytes(void)
{
    return TEST_SRC_STRIDE * TEST_SRC_H;
}

static uint32_t image_geo_dst_bytes(void)
{
    return TEST_DST_STRIDE * TEST_DST_H;
}

static void fill_test_pattern(void)
{
    uint32_t x;
    uint32_t y;

    for (y = 0; y < TEST_SRC_H; ++y) {
        for (x = 0; x < TEST_SRC_W; ++x) {
            uint8_t pixel;

            /*
             * A structured pattern is easier to debug than pure random data:
             * - upper bits follow x
             * - lower bits toggle with y/x regions
             */
            pixel = (uint8_t)(((x * 3u) + (y * 5u) + (((x >> 3) ^ (y >> 3)) * 31u)) & 0xFFu);
            g_src_buf[y * TEST_SRC_STRIDE + x] = pixel;
        }
    }
}

static void clear_destination(void)
{
    uint32_t i;
    uint32_t bytes = image_geo_dst_bytes();

    for (i = 0; i < bytes; ++i) {
        g_dst_buf[i] = 0u;
    }
}

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

static void dump_first_bytes(const char *tag, volatile uint8_t *buf, uint32_t count)
{
    uint32_t i;

    xil_printf("%s first %lu bytes:\r\n", tag, (unsigned long)count);
    for (i = 0; i < count; ++i) {
        xil_printf("%02x ", (unsigned int)buf[i]);
        if (((i + 1u) % 16u) == 0u) {
            xil_printf("\r\n");
        }
    }
    if ((count % 16u) != 0u) {
        xil_printf("\r\n");
    }
}

static int compare_identity_result(void)
{
    uint32_t x;
    uint32_t y;
    uint32_t mismatch_count = 0;

    for (y = 0; y < TEST_DST_H; ++y) {
        for (x = 0; x < TEST_DST_W; ++x) {
            uint8_t exp = g_src_buf[y * TEST_SRC_STRIDE + x];
            uint8_t got = g_dst_buf[y * TEST_DST_STRIDE + x];

            if (exp != got) {
                if (mismatch_count < 8u) {
                    xil_printf(
                        "Mismatch[%lu] at (x=%lu, y=%lu): exp=0x%02x got=0x%02x\r\n",
                        (unsigned long)mismatch_count,
                        (unsigned long)x,
                        (unsigned long)y,
                        (unsigned int)exp,
                        (unsigned int)got
                    );
                }
                ++mismatch_count;
            }
        }
    }

    if (mismatch_count != 0u) {
        xil_printf("Identity compare FAILED, mismatches=%lu\r\n",
            (unsigned long)mismatch_count);
        return -1;
    }

    xil_printf("Identity compare PASSED\r\n");
    return 0;
}

int main(void)
{
    int rc;
    uint32_t src_bytes = image_geo_src_bytes();
    uint32_t dst_bytes = image_geo_dst_bytes();

    xil_printf("\r\n");
    xil_printf("image_geo_top bring-up start\r\n");
    xil_printf("CTRL base : 0x%08lx\r\n", (unsigned long)IMAGE_GEO_BASEADDR);
    xil_printf("SRC DDR   : 0x%08lx (%lu bytes)\r\n",
        (unsigned long)SRC_BASEADDR,
        (unsigned long)src_bytes);
    xil_printf("DST DDR   : 0x%08lx (%lu bytes)\r\n",
        (unsigned long)DST_BASEADDR,
        (unsigned long)dst_bytes);

    fill_test_pattern();
    clear_destination();

    dump_first_bytes("SRC(before)", g_src_buf, 32u);
    dump_first_bytes("DST(before)", g_dst_buf, 32u);

    image_geo_clear_status(IMAGE_GEO_BASEADDR);
    image_geo_set_prefetch(IMAGE_GEO_BASEADDR, 1);

    Xil_DCacheFlushRange((UINTPTR)SRC_BASEADDR, src_bytes);
    Xil_DCacheFlushRange((UINTPTR)DST_BASEADDR, dst_bytes);

    image_geo_program_frame(
        IMAGE_GEO_BASEADDR,
        SRC_BASEADDR,
        DST_BASEADDR,
        TEST_SRC_STRIDE,
        TEST_DST_STRIDE,
        TEST_SRC_W,
        TEST_SRC_H,
        TEST_DST_W,
        TEST_DST_H,
        IMAGE_GEO_Q16_ZERO,
        IMAGE_GEO_Q16_ONE
    );

    xil_printf("Starting identity test\r\n");
    image_geo_start(IMAGE_GEO_BASEADDR, 0);

    rc = image_geo_wait_done(IMAGE_GEO_BASEADDR, IMAGE_GEO_TIMEOUT);
    Xil_DCacheInvalidateRange((UINTPTR)DST_BASEADDR, dst_bytes);

    xil_printf("Final status = 0x%08lx\r\n",
        (unsigned long)image_geo_get_status(IMAGE_GEO_BASEADDR));
    image_geo_dump_stats(IMAGE_GEO_BASEADDR, "identity");
    dump_first_bytes("DST(after)", g_dst_buf, 32u);

    if (rc != 0) {
        xil_printf("Bring-up FAILED before buffer compare\r\n");
        return rc;
    }

    rc = compare_identity_result();
    if (rc != 0) {
        xil_printf("Bring-up FAILED during buffer compare\r\n");
        return rc;
    }

    xil_printf("image_geo_top bring-up PASSED\r\n");
    return 0;
}
