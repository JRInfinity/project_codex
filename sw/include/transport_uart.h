#ifndef TRANSPORT_UART_H
#define TRANSPORT_UART_H

#include <stddef.h>
#include <stdint.h>
#include "xstatus.h"
#include "xuartps.h"

/*
 * UART 传输辅助模块。
 *
 * 设计目标：
 * - 面向 Zynq PS UART 裸机轮询场景
 * - 提供“定长收满”和“定长发完”能力
 * - 将串口细节从主业务流程中剥离出来
 */

typedef struct transport_uart_t {
    XUartPs inst;
    uint32_t device_id;
    uint32_t baud_rate;
    uint32_t poll_limit_per_byte;
} transport_uart_t;

/*
 * 初始化 UART。
 *
 * 参数：
 * - uart: UART 对象
 * - device_id: XUartPs 设备号，通常来自 xparameters.h
 * - baud_rate: 波特率，例如 115200 或更高
 * - poll_limit_per_byte: 每个字节允许的最大轮询次数，用于实现简易超时
 *
 * 返回：
 * - XST_SUCCESS: 初始化成功
 * - 其他值: 初始化失败
 */
int transport_uart_init(
    transport_uart_t *uart,
    uint32_t device_id,
    uint32_t baud_rate,
    uint32_t poll_limit_per_byte
);

/*
 * 清空当前 UART 接收 FIFO 中尚未读取的字节。
 */
void transport_uart_drain_rx(transport_uart_t *uart);

/*
 * 从 UART 中接收指定长度的数据。
 *
 * 返回：
 * - XST_SUCCESS: 成功收到全部字节
 * - XST_FAILURE: 参数错误或 UART 未初始化
 * - XST_TIMEOUT: 在限定轮询次数内未收到足够字节
 */
int transport_uart_recv_exact(transport_uart_t *uart, void *buf, size_t len);

/*
 * 向 UART 发送指定长度的数据。
 *
 * 返回：
 * - XST_SUCCESS: 成功发出全部字节
 * - XST_FAILURE: 参数错误或 UART 未初始化
 * - XST_TIMEOUT: 在限定轮询次数内未发送完毕
 */
int transport_uart_send_exact(transport_uart_t *uart, const void *buf, size_t len);

#endif /* TRANSPORT_UART_H */
