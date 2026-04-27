#include <stdint.h>
#include <string.h>

#include "xil_printf.h"
#include "xparameters.h"

#include "image_geo_driver.h"
#include "image_geo_protocol.h"
#include "transport_uart.h"

#ifndef XPAR_XUARTPS_0_DEVICE_ID
#error "当前平台未定义 XPAR_XUARTPS_0_DEVICE_ID，请检查 Vitis 平台中的 PS UART 配置。"
#endif

#define IMAGE_GEO_IP_BASEADDR        ((uintptr_t)0x40000000u)
#define IMAGE_GEO_SRC_DDR_BASE       ((uint32_t)0x10000000u)
#define IMAGE_GEO_DST_DDR_BASE       ((uint32_t)0x12000000u)
#define IMAGE_GEO_SRC_DDR_CAPACITY   (8u * 1024u * 1024u)
#define IMAGE_GEO_DST_DDR_CAPACITY   (8u * 1024u * 1024u)
#define IMAGE_GEO_TIMEOUT_CYCLES     (100000000u)

#define UART_DEVICE_ID               XPAR_XUARTPS_0_DEVICE_ID
#define UART_BAUD_RATE               921600u
#define UART_POLL_LIMIT_PER_BYTE     500000u

static volatile uint8_t *const g_src_buf = (volatile uint8_t *)IMAGE_GEO_SRC_DDR_BASE;
static volatile uint8_t *const g_dst_buf = (volatile uint8_t *)IMAGE_GEO_DST_DDR_BASE;

static void clear_dst_buffer(uint32_t bytes)
{
    uint32_t i;

    for (i = 0; i < bytes; ++i) {
        g_dst_buf[i] = 0u;
    }
}

static void print_request_summary(const image_geo_request_v1_t *req)
{
    xil_printf("收到请求:\r\n");
    xil_printf("  src=%lux%lu stride=%lu\r\n",
        (unsigned long)req->src_w,
        (unsigned long)req->src_h,
        (unsigned long)req->src_stride);
    xil_printf("  dst=%lux%lu stride=%lu\r\n",
        (unsigned long)req->dst_w,
        (unsigned long)req->dst_h,
        (unsigned long)req->dst_stride);
    xil_printf("  rot_sin_q16=%ld rot_cos_q16=%ld\r\n",
        (long)req->rot_sin_q16,
        (long)req->rot_cos_q16);
    xil_printf("  prefetch=%lu payload=%lu\r\n",
        (unsigned long)req->prefetch_enable,
        (unsigned long)req->payload_bytes);
}

static void print_response_summary(const image_geo_response_v1_t *resp)
{
    xil_printf("回包摘要:\r\n");
    xil_printf("  status=%lu output_bytes=%lu hw_status=0x%08lx\r\n",
        (unsigned long)resp->status,
        (unsigned long)resp->output_bytes,
        (unsigned long)resp->hw_status_reg);
    xil_printf("  cache: reads=%lu misses=%lu prefetches=%lu hits=%lu\r\n",
        (unsigned long)resp->cache_reads,
        (unsigned long)resp->cache_misses,
        (unsigned long)resp->cache_prefetches,
        (unsigned long)resp->cache_hits);
}

int main(void)
{
    int status;
    transport_uart_t uart;
    image_geo_driver_limits_t limits;

    memset(&uart, 0, sizeof(uart));
    memset(&limits, 0, sizeof(limits));

    limits.ip_baseaddr = IMAGE_GEO_IP_BASEADDR;
    limits.src_ddr_base = IMAGE_GEO_SRC_DDR_BASE;
    limits.dst_ddr_base = IMAGE_GEO_DST_DDR_BASE;
    limits.src_ddr_capacity = IMAGE_GEO_SRC_DDR_CAPACITY;
    limits.dst_ddr_capacity = IMAGE_GEO_DST_DDR_CAPACITY;
    limits.timeout_cycles = IMAGE_GEO_TIMEOUT_CYCLES;

    xil_printf("\r\n");
    xil_printf("image_geo UART 常驻服务启动\r\n");
    xil_printf("IP base     : 0x%08lx\r\n", (unsigned long)limits.ip_baseaddr);
    xil_printf("SRC DDR     : 0x%08lx (%lu bytes)\r\n",
        (unsigned long)limits.src_ddr_base,
        (unsigned long)limits.src_ddr_capacity);
    xil_printf("DST DDR     : 0x%08lx (%lu bytes)\r\n",
        (unsigned long)limits.dst_ddr_base,
        (unsigned long)limits.dst_ddr_capacity);

    status = transport_uart_init(
        &uart,
        UART_DEVICE_ID,
        UART_BAUD_RATE,
        UART_POLL_LIMIT_PER_BYTE
    );
    if (status != XST_SUCCESS) {
        xil_printf("UART 初始化失败: %d\r\n", status);
        return status;
    }

    xil_printf("UART 初始化完成，波特率=%lu\r\n", (unsigned long)UART_BAUD_RATE);
    xil_printf("等待 PC 请求...\r\n");

    while (1) {
        image_geo_request_v1_t req;
        image_geo_response_v1_t resp;
        uint32_t src_bytes;

        memset(&req, 0, sizeof(req));
        memset(&resp, 0, sizeof(resp));

        status = transport_uart_recv_exact(&uart, &req, sizeof(req));
        if (status != XST_SUCCESS) {
            xil_printf("接收请求头失败: %d\r\n", status);
            continue;
        }

        print_request_summary(&req);

        status = image_geo_driver_validate_request(&req, &limits);
        src_bytes = image_geo_request_expected_bytes(&req);
        if (status != IMAGE_GEO_STATUS_OK) {
            resp.magic = IMAGE_GEO_PROTO_MAGIC_RESP;
            resp.version = IMAGE_GEO_PROTO_VERSION_V1;
            resp.status = (uint32_t)status;
            resp.output_bytes = image_geo_response_expected_bytes(req.dst_stride, req.dst_h);
            resp.hw_status_reg = 0u;
            resp.cache_reads = 0u;
            resp.cache_misses = 0u;
            resp.cache_prefetches = 0u;
            resp.cache_hits = 0u;

            (void)transport_uart_send_exact(&uart, &resp, sizeof(resp));
            xil_printf("请求非法，已回包错误状态=%d\r\n", status);
            continue;
        }

        clear_dst_buffer(image_geo_response_expected_bytes(req.dst_stride, req.dst_h));

        status = transport_uart_recv_exact(&uart, (void *)g_src_buf, src_bytes);
        if (status != XST_SUCCESS) {
            xil_printf("接收图像负载失败: %d\r\n", status);
            resp.magic = IMAGE_GEO_PROTO_MAGIC_RESP;
            resp.version = IMAGE_GEO_PROTO_VERSION_V1;
            resp.status = IMAGE_GEO_STATUS_RX_TIMEOUT;
            resp.output_bytes = 0u;
            resp.hw_status_reg = 0u;
            resp.cache_reads = 0u;
            resp.cache_misses = 0u;
            resp.cache_prefetches = 0u;
            resp.cache_hits = 0u;
            (void)transport_uart_send_exact(&uart, &resp, sizeof(resp));
            continue;
        }

        status = image_geo_driver_run(&req, &limits, &resp);
        print_response_summary(&resp);

        if (transport_uart_send_exact(&uart, &resp, sizeof(resp)) != XST_SUCCESS) {
            xil_printf("发送响应头失败\r\n");
            continue;
        }

        if (resp.status == IMAGE_GEO_STATUS_OK && resp.output_bytes != 0u) {
            if (transport_uart_send_exact(&uart, (const void *)g_dst_buf, resp.output_bytes) != XST_SUCCESS) {
                xil_printf("发送输出负载失败\r\n");
                continue;
            }
        }

        xil_printf("本次请求处理完成，继续等待下一帧\r\n");
    }
}
