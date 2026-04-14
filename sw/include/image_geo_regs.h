#ifndef IMAGE_GEO_REGS_H
#define IMAGE_GEO_REGS_H

#include <stdint.h>

/*
 * image_geo_top AXI-Lite register map
 *
 * Current implementation assumptions:
 * - 32-bit AXI-Lite data bus
 * - register offsets are byte offsets from the IP base address
 */

#define IMAGE_GEO_REG_CTRL                 0x000u
#define IMAGE_GEO_REG_SRC_BASE_ADDR        0x004u
#define IMAGE_GEO_REG_DST_BASE_ADDR        0x008u
#define IMAGE_GEO_REG_SRC_STRIDE           0x00Cu
#define IMAGE_GEO_REG_DST_STRIDE           0x010u
#define IMAGE_GEO_REG_SRC_SIZE             0x014u
#define IMAGE_GEO_REG_DST_SIZE             0x018u
#define IMAGE_GEO_REG_STATUS               0x01Cu
#define IMAGE_GEO_REG_ROT_SIN_Q16          0x020u
#define IMAGE_GEO_REG_ROT_COS_Q16          0x024u
#define IMAGE_GEO_REG_CACHE_READS          0x028u
#define IMAGE_GEO_REG_CACHE_MISSES         0x02Cu
#define IMAGE_GEO_REG_CACHE_PREFETCHES     0x030u
#define IMAGE_GEO_REG_CACHE_PREFETCH_HITS  0x034u
#define IMAGE_GEO_REG_CACHE_CTRL           0x038u

/* CTRL register bits */
#define IMAGE_GEO_CTRL_START_MASK          (1u << 0)
#define IMAGE_GEO_CTRL_IRQ_EN_MASK         (1u << 1)

/* STATUS register bits */
#define IMAGE_GEO_STATUS_BUSY_MASK         (1u << 0)
#define IMAGE_GEO_STATUS_DONE_MASK         (1u << 1)
#define IMAGE_GEO_STATUS_ERROR_MASK        (1u << 2)

/* CACHE_CTRL register bits */
#define IMAGE_GEO_CACHE_CTRL_PREFETCH_EN   (1u << 0)

/* Common Q16 coefficients */
#define IMAGE_GEO_Q16_ONE                  0x00010000
#define IMAGE_GEO_Q16_ZERO                 0x00000000
#define IMAGE_GEO_Q16_SIN_45               0x0000B505
#define IMAGE_GEO_Q16_COS_45               0x0000B505
#define IMAGE_GEO_Q16_SIN_90               0x00010000
#define IMAGE_GEO_Q16_COS_90               0x00000000

typedef struct image_geo_cache_stats_t {
    uint32_t reads;
    uint32_t misses;
    uint32_t prefetches;
    uint32_t hits;
} image_geo_cache_stats_t;

static inline void image_geo_write32(uintptr_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(base + offset) = value;
}

static inline uint32_t image_geo_read32(uintptr_t base, uint32_t offset)
{
    return *(volatile uint32_t *)(base + offset);
}

static inline uint32_t image_geo_pack_size(uint16_t w, uint16_t h)
{
    return ((uint32_t)h << 16) | (uint32_t)w;
}

static inline void image_geo_clear_status(uintptr_t base)
{
    image_geo_write32(base, IMAGE_GEO_REG_STATUS,
        IMAGE_GEO_STATUS_DONE_MASK | IMAGE_GEO_STATUS_ERROR_MASK);
}

static inline void image_geo_set_prefetch(uintptr_t base, int enable)
{
    image_geo_write32(base, IMAGE_GEO_REG_CACHE_CTRL,
        enable ? IMAGE_GEO_CACHE_CTRL_PREFETCH_EN : 0u);
}

static inline void image_geo_program_frame(
    uintptr_t base,
    uint32_t src_base,
    uint32_t dst_base,
    uint32_t src_stride,
    uint32_t dst_stride,
    uint16_t src_w,
    uint16_t src_h,
    uint16_t dst_w,
    uint16_t dst_h,
    int32_t rot_sin_q16,
    int32_t rot_cos_q16
)
{
    image_geo_write32(base, IMAGE_GEO_REG_SRC_BASE_ADDR, src_base);
    image_geo_write32(base, IMAGE_GEO_REG_DST_BASE_ADDR, dst_base);
    image_geo_write32(base, IMAGE_GEO_REG_SRC_STRIDE, src_stride);
    image_geo_write32(base, IMAGE_GEO_REG_DST_STRIDE, dst_stride);
    image_geo_write32(base, IMAGE_GEO_REG_SRC_SIZE, image_geo_pack_size(src_w, src_h));
    image_geo_write32(base, IMAGE_GEO_REG_DST_SIZE, image_geo_pack_size(dst_w, dst_h));
    image_geo_write32(base, IMAGE_GEO_REG_ROT_SIN_Q16, (uint32_t)rot_sin_q16);
    image_geo_write32(base, IMAGE_GEO_REG_ROT_COS_Q16, (uint32_t)rot_cos_q16);
}

static inline void image_geo_start(uintptr_t base, int irq_enable)
{
    uint32_t ctrl = IMAGE_GEO_CTRL_START_MASK;
    if (irq_enable) {
        ctrl |= IMAGE_GEO_CTRL_IRQ_EN_MASK;
    }
    image_geo_write32(base, IMAGE_GEO_REG_CTRL, ctrl);
}

static inline int image_geo_is_busy(uintptr_t base)
{
    return (image_geo_read32(base, IMAGE_GEO_REG_STATUS) & IMAGE_GEO_STATUS_BUSY_MASK) != 0u;
}

static inline int image_geo_is_done(uintptr_t base)
{
    return (image_geo_read32(base, IMAGE_GEO_REG_STATUS) & IMAGE_GEO_STATUS_DONE_MASK) != 0u;
}

static inline int image_geo_has_error(uintptr_t base)
{
    return (image_geo_read32(base, IMAGE_GEO_REG_STATUS) & IMAGE_GEO_STATUS_ERROR_MASK) != 0u;
}

static inline uint32_t image_geo_get_status(uintptr_t base)
{
    return image_geo_read32(base, IMAGE_GEO_REG_STATUS);
}

static inline void image_geo_get_cache_stats(uintptr_t base, image_geo_cache_stats_t *stats)
{
    if (stats == 0) {
        return;
    }

    stats->reads      = image_geo_read32(base, IMAGE_GEO_REG_CACHE_READS);
    stats->misses     = image_geo_read32(base, IMAGE_GEO_REG_CACHE_MISSES);
    stats->prefetches = image_geo_read32(base, IMAGE_GEO_REG_CACHE_PREFETCHES);
    stats->hits       = image_geo_read32(base, IMAGE_GEO_REG_CACHE_PREFETCH_HITS);
}

#endif /* IMAGE_GEO_REGS_H */
