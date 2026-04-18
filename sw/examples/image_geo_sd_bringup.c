#include <stdint.h>
#include "ff.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "image_geo_regs.h"

/*
 * Bare-metal SD-card driven example:
 * 1. read a MATLAB-generated raw grayscale .bin file from SD card
 * 2. copy it into PS DDR
 * 3. start image_geo_top
 * 4. write the output DDR buffer back to SD card as another .bin file
 *
 * Assumptions:
 * - SD card is FAT32 formatted
 * - the input file is 8-bit grayscale, row-major, 1 byte/pixel
 * - file size equals src_stride * src_h
 */

#define IMAGE_GEO_BASEADDR    ((uintptr_t)0x40000000u)
#define SRC_BASEADDR          ((uint32_t)0x10000000u)
#define DST_BASEADDR          ((uint32_t)0x12000000u)
#define IMAGE_GEO_TIMEOUT     (100000000u)

#define SRC_W                 640u
#define SRC_H                 480u
#define DST_W                 640u
#define DST_H                 480u
#define SRC_STRIDE            640u
#define DST_STRIDE            640u

#define INPUT_BIN_PATH        "0:/test_640x480.bin"
#define OUTPUT_BIN_PATH       "0:/out_640x480.bin"

static FATFS g_fatfs;
static volatile uint8_t *const g_src_buf = (volatile uint8_t *)SRC_BASEADDR;
static volatile uint8_t *const g_dst_buf = (volatile uint8_t *)DST_BASEADDR;

static uint32_t src_bytes(void)
{
    return SRC_STRIDE * SRC_H;
}

static uint32_t dst_bytes(void)
{
    return DST_STRIDE * DST_H;
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

static int mount_sd_card(void)
{
    FRESULT fr;

    fr = f_mount(&g_fatfs, "0:/", 1);
    if (fr != FR_OK) {
        xil_printf("f_mount failed: %d\r\n", (int)fr);
        return -1;
    }

    return 0;
}

static int load_bin_from_sd(const char *path, volatile uint8_t *dst, uint32_t expected_bytes)
{
    FIL fil;
    FRESULT fr;
    FSIZE_t size;
    UINT br = 0;

    fr = f_open(&fil, path, FA_READ);
    if (fr != FR_OK) {
        xil_printf("f_open(read) failed for %s: %d\r\n", path, (int)fr);
        return -1;
    }

    size = f_size(&fil);
    if ((uint32_t)size != expected_bytes) {
        xil_printf("Input size mismatch: file=%lu expected=%lu\r\n",
            (unsigned long)size,
            (unsigned long)expected_bytes);
        (void)f_close(&fil);
        return -2;
    }

    fr = f_read(&fil, (void *)dst, expected_bytes, &br);
    (void)f_close(&fil);
    if (fr != FR_OK) {
        xil_printf("f_read failed for %s: %d\r\n", path, (int)fr);
        return -3;
    }

    if ((uint32_t)br != expected_bytes) {
        xil_printf("Short read: got=%lu expected=%lu\r\n",
            (unsigned long)br,
            (unsigned long)expected_bytes);
        return -4;
    }

    xil_printf("Loaded %s into DDR (%lu bytes)\r\n",
        path,
        (unsigned long)expected_bytes);
    return 0;
}

static int save_bin_to_sd(const char *path, volatile uint8_t *src, uint32_t bytes)
{
    FIL fil;
    FRESULT fr;
    UINT bw = 0;

    fr = f_open(&fil, path, FA_CREATE_ALWAYS | FA_WRITE);
    if (fr != FR_OK) {
        xil_printf("f_open(write) failed for %s: %d\r\n", path, (int)fr);
        return -1;
    }

    fr = f_write(&fil, (const void *)src, bytes, &bw);
    (void)f_close(&fil);
    if (fr != FR_OK) {
        xil_printf("f_write failed for %s: %d\r\n", path, (int)fr);
        return -2;
    }

    if ((uint32_t)bw != bytes) {
        xil_printf("Short write: got=%lu expected=%lu\r\n",
            (unsigned long)bw,
            (unsigned long)bytes);
        return -3;
    }

    xil_printf("Saved %s from DDR (%lu bytes)\r\n",
        path,
        (unsigned long)bytes);
    return 0;
}

static void clear_destination(void)
{
    uint32_t i;
    uint32_t bytes = dst_bytes();

    for (i = 0; i < bytes; ++i) {
        g_dst_buf[i] = 0u;
    }
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

int main(void)
{
    int rc;
    uint32_t in_bytes = src_bytes();
    uint32_t out_bytes = dst_bytes();

    xil_printf("\r\n");
    xil_printf("image_geo_top SD bring-up start\r\n");
    xil_printf("CTRL base : 0x%08lx\r\n", (unsigned long)IMAGE_GEO_BASEADDR);
    xil_printf("SRC DDR   : 0x%08lx (%lu bytes)\r\n",
        (unsigned long)SRC_BASEADDR,
        (unsigned long)in_bytes);
    xil_printf("DST DDR   : 0x%08lx (%lu bytes)\r\n",
        (unsigned long)DST_BASEADDR,
        (unsigned long)out_bytes);

    rc = mount_sd_card();
    if (rc != 0) {
        return rc;
    }

    clear_destination();
    rc = load_bin_from_sd(INPUT_BIN_PATH, g_src_buf, in_bytes);
    if (rc != 0) {
        return rc;
    }

    dump_first_bytes("SRC(file->DDR)", g_src_buf, 32u);

    image_geo_clear_status(IMAGE_GEO_BASEADDR);
    image_geo_set_prefetch(IMAGE_GEO_BASEADDR, 1);

    Xil_DCacheFlushRange((UINTPTR)SRC_BASEADDR, in_bytes);
    Xil_DCacheFlushRange((UINTPTR)DST_BASEADDR, out_bytes);

    image_geo_program_frame(
        IMAGE_GEO_BASEADDR,
        SRC_BASEADDR,
        DST_BASEADDR,
        SRC_STRIDE,
        DST_STRIDE,
        SRC_W,
        SRC_H,
        DST_W,
        DST_H,
        IMAGE_GEO_Q16_ZERO,
        IMAGE_GEO_Q16_ONE
    );

    xil_printf("Starting file-driven test\r\n");
    image_geo_start(IMAGE_GEO_BASEADDR, 0);

    rc = image_geo_wait_done(IMAGE_GEO_BASEADDR, IMAGE_GEO_TIMEOUT);
    Xil_DCacheInvalidateRange((UINTPTR)DST_BASEADDR, out_bytes);

    xil_printf("Final status = 0x%08lx\r\n",
        (unsigned long)image_geo_get_status(IMAGE_GEO_BASEADDR));
    image_geo_dump_stats(IMAGE_GEO_BASEADDR, "file_driven");
    dump_first_bytes("DST(DDR->file)", g_dst_buf, 32u);

    if (rc != 0) {
        xil_printf("Run failed before saving output\r\n");
        return rc;
    }

    rc = save_bin_to_sd(OUTPUT_BIN_PATH, g_dst_buf, out_bytes);
    if (rc != 0) {
        return rc;
    }

    xil_printf("image_geo_top SD bring-up PASSED\r\n");
    return 0;
}
