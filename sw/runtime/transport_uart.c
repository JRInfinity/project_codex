#include "transport_uart.h"

#include <stddef.h>

static int transport_uart_validate(const transport_uart_t *uart)
{
    if (uart == 0) {
        return XST_FAILURE;
    }

    if (uart->poll_limit_per_byte == 0u) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int transport_uart_init(
    transport_uart_t *uart,
    uint32_t device_id,
    uint32_t baud_rate,
    uint32_t poll_limit_per_byte
)
{
    XUartPs_Config *cfg;
    int status;

    if (uart == 0 || baud_rate == 0u || poll_limit_per_byte == 0u) {
        return XST_FAILURE;
    }

    cfg = XUartPs_LookupConfig(device_id);
    if (cfg == 0) {
        return XST_FAILURE;
    }

    status = XUartPs_CfgInitialize(&uart->inst, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XUartPs_SelfTest(&uart->inst);
    if (status != XST_SUCCESS) {
        return status;
    }

    status = XUartPs_SetBaudRate(&uart->inst, baud_rate);
    if (status != XST_SUCCESS) {
        return status;
    }

    uart->device_id = device_id;
    uart->baud_rate = baud_rate;
    uart->poll_limit_per_byte = poll_limit_per_byte;

    /*
     * 第一版先用最直接的轮询模式。
     * 主流程在协议层保证定长接收和发送，不在这里引入中断复杂度。
     */
    XUartPs_SetOperMode(&uart->inst, XUARTPS_OPER_MODE_NORMAL);
    transport_uart_drain_rx(uart);

    return XST_SUCCESS;
}

void transport_uart_drain_rx(transport_uart_t *uart)
{
    uint8_t byte_buf[16];

    if (transport_uart_validate(uart) != XST_SUCCESS) {
        return;
    }

    while (XUartPs_IsReceiveData(uart->inst.Config.BaseAddress) != 0u) {
        (void)XUartPs_Recv(&uart->inst, byte_buf, sizeof(byte_buf));
    }
}

int transport_uart_recv_exact(transport_uart_t *uart, void *buf, size_t len)
{
    uint8_t *dst;
    size_t total_rx;
    uint32_t idle_poll_count;

    if (transport_uart_validate(uart) != XST_SUCCESS || buf == 0) {
        return XST_FAILURE;
    }

    dst = (uint8_t *)buf;
    total_rx = 0u;
    idle_poll_count = 0u;

    while (total_rx < len) {
        s32 rx_now;

        rx_now = XUartPs_Recv(&uart->inst, &dst[total_rx], (u32)(len - total_rx));
        if (rx_now > 0) {
            total_rx += (size_t)rx_now;
            idle_poll_count = 0u;
            continue;
        }

        ++idle_poll_count;
        if (idle_poll_count >= uart->poll_limit_per_byte) {
            return XST_TIMEOUT;
        }
    }

    return XST_SUCCESS;
}

int transport_uart_send_exact(transport_uart_t *uart, const void *buf, size_t len)
{
    const uint8_t *src;
    size_t total_tx;
    uint32_t idle_poll_count;

    if (transport_uart_validate(uart) != XST_SUCCESS || buf == 0) {
        return XST_FAILURE;
    }

    src = (const uint8_t *)buf;
    total_tx = 0u;
    idle_poll_count = 0u;

    while (total_tx < len) {
        s32 tx_now;

        tx_now = XUartPs_Send(&uart->inst, (u8 *)&src[total_tx], (u32)(len - total_tx));
        if (tx_now > 0) {
            total_tx += (size_t)tx_now;
            idle_poll_count = 0u;
            continue;
        }

        ++idle_poll_count;
        if (idle_poll_count >= uart->poll_limit_per_byte) {
            return XST_TIMEOUT;
        }
    }

    return XST_SUCCESS;
}
