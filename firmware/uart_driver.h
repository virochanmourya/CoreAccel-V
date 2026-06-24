/* ============================================================================
 * uart_driver.h — CoreAccel-V Bare-Metal UART TX Driver
 *
 * MMIO Register: 0xC000_0004
 *   WRITE: Bits 7:0 = byte to transmit (triggers hardware TX)
 *   READ:  Bit 0 = tx_busy flag (1 = byte in transit, poll until 0)
 * ============================================================================ */

#ifndef UART_DRIVER_H
#define UART_DRIVER_H

#include <stdint.h>

#define UART_BASE  ((volatile uint32_t *)0xC0000004)

/* Returns 1 if UART TX is currently busy transmitting */
static inline int uart_busy(void) {
    return (*UART_BASE) & 1;
}

/* Blocking send: waits for TX idle, then writes byte */
void uart_send_byte(uint8_t data);

/* Blocking send of a null-terminated string */
void uart_print(const char *str);

/* Send a 16-bit signed sample as a 4-byte binary packet: [0xAA, hi, lo, 0x55] */
void uart_send_sample(int16_t sample);

/* Send a formatted decimal number (for BPM display) */
void uart_print_int(int32_t val);

#endif /* UART_DRIVER_H */
