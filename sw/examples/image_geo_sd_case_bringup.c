#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "ff.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "image_geo_regs.h"

#define IMAGE_GEO_BASEADDR    ((uintptr_t)0x40000000u)
#define SRC_BASEADDR          ((uint32_t)0x10000000u)
#define DST_BASEADDR          ((uint32_t)0x12000000u)
#define IMAGE_GEO_TIMEOUT     (100000000u)

#define CASE_CFG_PATH         "0:/test_640x480_case.txt"
#define DEFAULT_INPUT_BIN     "0:/test_640x480.bin"
#define DEFAULT_OUTPUT_BIN    "0:/out_test_640x480.bin"

#define MAX_PATH_LEN          96
#define MAX_LINE_LEN          160

typedef struct image_geo_case_cfg_t {
    char input_bin[MAX_PATH_LEN];
    char output_bin[MAX_PATH_LEN];
    uint16_t src_w;
    uint16_t src_h;
    uint32_t src_stride;
    uint16_t dst_w;
    uint16_t dst_h;
    uint32_t dst_stride;
    int32_t rot_sin_q16;
    int32_t rot_cos_q16;
    int prefetch_enable;
} image_geo_case_cfg_t;

static FATFS g_fatfs;
static volatile uint8_t *const g_src_buf = (volatile uint8_t *)SRC_BASEADDR;
static volatile uint8_t *const g_dst_buf = (volatile uint8_t *)DST_BASEADDR;

static void cfg_set_defaults(image_geo_case_cfg_t *cfg)
{
    if (cfg == 0) {
        return;
    }

    memset(cfg, 0, sizeof(*cfg));
    strncpy(cfg->input_bin, DEFAULT_INPUT_BIN, MAX_PATH_LEN - 1);
    strncpy(cfg->output_bin, DEFAULT_OUTPUT_BIN, MAX_PATH_LEN - 1);
    cfg->src_w = 640u;
    cfg->src_h = 480u;
    cfg->src_stride = 640u;
    cfg->dst_w = 640u;
    cfg->dst_h = 480u;
    cfg->dst_stride = 640u;
    cfg->rot_sin_q16 = (int32_t)IMAGE_GEO_Q16_ZERO;
    cfg->rot_cos_q16 = (int32_t)IMAGE_GEO_Q16_ONE;
    cfg->prefetch_enable = 1;
}

static uint32_t cfg_src_bytes(const image_geo_case_cfg_t *cfg)
{
    return cfg->src_stride * (uint32_t)cfg->src_h;
}

static uint32_t cfg_dst_bytes(const image_geo_case_cfg_t *cfg)
{
    return cfg->dst_stride * (uint32_t)cfg->dst_h;
}

static void trim_line(char *s)
{
    size_t len;

    if (s == 0) {
        return;
    }

    len = strlen(s);
    while (len > 0u && (s[len - 1u] == '\r' || s[len - 1u] == '\n' || s[len - 1u] == ' ' || s[len - 1u] == '\t')) {
        s[len - 1u] = '\0';
        --len;
    }

    while (*s == ' ' || *s == '\t') {
        memmove(s, s + 1, strlen(s));
    }
}

static int join_sd_root_path(char *dst, size_t dst_len, const char *name)
{
    int written;

    if (dst == 0 || name == 0 || dst_len == 0u) {
        return -1;
    }

    if (strncmp(name, "0:/", 3) == 0) {
        written = snprintf(dst, dst_len, "%s", name);
    } else {
        written = snprintf(dst, dst_len, "0:/%s", name);
    }

    if (written < 0 || (size_t)written >= dst_len) {
        return -1;
    }

    return 0;
}

static int parse_cfg_line(image_geo_case_cfg_t *cfg, const char *line)
{
    char work[MAX_LINE_LEN];
    char *eq;
    char *key;
    char *value;

    if (cfg == 0 || line == 0) {
        return -1;
    }

    strncpy(work, line, sizeof(work) - 1u);
    work[sizeof(work) - 1u] = '\0';
    trim_line(work);

    if (work[0] == '\0' || work[0] == '#') {
        return 0;
    }

    eq = strchr(work, '=');
    if (eq == 0) {
        return 0;
    }

    *eq = '\0';
    key = work;
    value = eq + 1;
    trim_line(key);
    trim_line(value);

    if (strcmp(key, "input_bin") == 0) {
        return join_sd_root_path(cfg->input_bin, sizeof(cfg->input_bin), value);
    }
    if (strcmp(key, "output_bin") == 0) {
        return join_sd_root_path(cfg->output_bin, sizeof(cfg->output_bin), value);
    }
    if (strcmp(key, "src_w") == 0) {
        cfg->src_w = (uint16_t)strtoul(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "src_h") == 0) {
        cfg->src_h = (uint16_t)strtoul(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "src_stride") == 0) {
        cfg->src_stride = (uint32_t)strtoul(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "dst_w") == 0) {
        cfg->dst_w = (uint16_t)strtoul(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "dst_h") == 0) {
        cfg->dst_h = (uint16_t)strtoul(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "dst_stride") == 0) {
        cfg->dst_stride = (uint32_t)strtoul(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "rot_sin_q16") == 0) {
        cfg->rot_sin_q16 = (int32_t)strtol(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "rot_cos_q16") == 0) {
        cfg->rot_cos_q16 = (int32_t)strtol(value, 0, 0);
        return 0;
    }
    if (strcmp(key, "prefetch_enable") == 0) {
        cfg->prefetch_enable = (int)strtol(value, 0, 0);
        return 0;
    }

    return 0;
}

static int load_case_cfg(const char *path, image_geo_case_cfg_t *cfg)
{
    FIL fil;
    FRESULT fr;
    char line[MAX_LINE_LEN];

    if (cfg == 0) {
        return -1;
    }

    cfg_set_defaults(cfg);

    fr = f_open(&fil, path, FA_READ);
    if (fr != FR_OK) {
        xil_printf("f_open(case cfg) failed for %s: %d\r\n", path, (int)fr);
        return -1;
    }

    while (f_gets(line, sizeof(line), &fil) != 0) {
        if (parse_cfg_line(cfg, line) != 0) {
            (void)f_close(&fil);
            xil_printf("Failed to parse case config line: %s\r\n", line);
            return -2;
        }
    }

    (void)f_close(&fil);
    return 0;
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

static void clear_destination(uint32_t bytes)
{
    uint32_t i;

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

int main(void)
{
    int rc;
    image_geo_case_cfg_t cfg;
    uint32_t in_bytes;
    uint32_t out_bytes;

    xil_printf("\r\n");
    xil_printf("image_geo_top SD case bring-up start\r\n");
    xil_printf("CTRL base : 0x%08lx\r\n", (unsigned long)IMAGE_GEO_BASEADDR);

    rc = mount_sd_card();
    if (rc != 0) {
        return rc;
    }

    rc = load_case_cfg(CASE_CFG_PATH, &cfg);
    if (rc != 0) {
        return rc;
    }

    in_bytes = cfg_src_bytes(&cfg);
    out_bytes = cfg_dst_bytes(&cfg);

    xil_printf("Case file : %s\r\n", CASE_CFG_PATH);
    xil_printf("Input bin : %s\r\n", cfg.input_bin);
    xil_printf("Output bin: %s\r\n", cfg.output_bin);
    xil_printf("SRC       : %ux%u stride=%lu bytes=%lu\r\n",
        (unsigned int)cfg.src_w,
        (unsigned int)cfg.src_h,
        (unsigned long)cfg.src_stride,
        (unsigned long)in_bytes);
    xil_printf("DST       : %ux%u stride=%lu bytes=%lu\r\n",
        (unsigned int)cfg.dst_w,
        (unsigned int)cfg.dst_h,
        (unsigned long)cfg.dst_stride,
        (unsigned long)out_bytes);
    xil_printf("ROT Q16   : sin=%ld cos=%ld\r\n",
        (long)cfg.rot_sin_q16,
        (long)cfg.rot_cos_q16);

    clear_destination(out_bytes);
    rc = load_bin_from_sd(cfg.input_bin, g_src_buf, in_bytes);
    if (rc != 0) {
        return rc;
    }

    dump_first_bytes("SRC(file->DDR)", g_src_buf, 32u);

    image_geo_clear_status(IMAGE_GEO_BASEADDR);
    image_geo_set_prefetch(IMAGE_GEO_BASEADDR, cfg.prefetch_enable);

    Xil_DCacheFlushRange((UINTPTR)SRC_BASEADDR, in_bytes);
    Xil_DCacheFlushRange((UINTPTR)DST_BASEADDR, out_bytes);

    image_geo_program_frame(
        IMAGE_GEO_BASEADDR,
        SRC_BASEADDR,
        DST_BASEADDR,
        cfg.src_stride,
        cfg.dst_stride,
        cfg.src_w,
        cfg.src_h,
        cfg.dst_w,
        cfg.dst_h,
        cfg.rot_sin_q16,
        cfg.rot_cos_q16
    );

    xil_printf("Starting case-driven test\r\n");
    image_geo_start(IMAGE_GEO_BASEADDR, 0);

    rc = image_geo_wait_done(IMAGE_GEO_BASEADDR, IMAGE_GEO_TIMEOUT);
    Xil_DCacheInvalidateRange((UINTPTR)DST_BASEADDR, out_bytes);

    xil_printf("Final status = 0x%08lx\r\n",
        (unsigned long)image_geo_get_status(IMAGE_GEO_BASEADDR));
    image_geo_dump_stats(IMAGE_GEO_BASEADDR, "case_driven");
    dump_first_bytes("DST(DDR->file)", g_dst_buf, 32u);

    if (rc != 0) {
        xil_printf("Run failed before saving output\r\n");
        return rc;
    }

    rc = save_bin_to_sd(cfg.output_bin, g_dst_buf, out_bytes);
    if (rc != 0) {
        return rc;
    }

    xil_printf("image_geo_top SD case bring-up PASSED\r\n");
    return 0;
}
