/* ============================================================================
 * uart_driver.c — CoreAccel-V Bare-Metal UART TX Driver
 *
 * Implements blocking UART TX over the hardware 8N1 transmitter at
 * MMIO address 0xC000_0004. The driver polls the hardware busy flag
 * before each byte to prevent data corruption.
 *
 * Telemetry Packet Format (for ECG streaming):
 *   [0xAA] [sample_hi] [sample_lo] [0x55]
 *   Header    MSB          LSB      Footer
 *
 * The laptop GUI synchronizes on the 0xAA header byte and validates
 * with the 0x55 footer to reject corrupted frames.
 * ============================================================================ */

#include "uart_driver.h"

/* ---- Blocking single-byte transmit ---- */
void uart_send_byte(uint8_t data) {
    /* Spin until the hardware TX FSM is idle.
     * At 115200 baud, one byte = ~87 µs = ~8,680 CPU cycles at 100 MHz.
     * This is acceptable for telemetry — the DSP loop budget is 4 ms. */
    while (uart_busy())
        ;

    /* Write the byte. The hardware latches bits [7:0] and auto-starts
     * the 8N1 transmission on the write edge. */
    *UART_BASE = (uint32_t)data;
}

/* ---- Blocking string transmit ---- */
void uart_print(const char *str) {
    while (*str) {
        uart_send_byte((uint8_t)*str);
        str++;
    }
}

/* ---- Send a 16-bit ECG sample as a framed binary packet ----
 *
 * Format: [0xAA] [hi_byte] [lo_byte] [0x55]
 *
 * The GUI parser scans for the 0xAA sync byte, reads 2 payload bytes,
 * and validates the 0x55 footer. This provides robust framing over a
 * raw byte stream without needing a line-based ASCII protocol.
 *
 * Throughput: 4 bytes × 10 bits/byte × (1/115200) = 347 µs per sample.
 * At 250 Hz sample rate (4 ms period), this uses 8.7% of bandwidth. */
void uart_send_sample(int16_t sample) {
    uint16_t raw = (uint16_t)sample;
    uart_send_byte(0xAA);              /* Sync header */
    uart_send_byte((uint8_t)(raw >> 8));  /* MSB */
    uart_send_byte((uint8_t)(raw & 0xFF)); /* LSB */
    uart_send_byte(0x55);              /* Footer */
}

/* ---- Print a signed integer as ASCII decimal ----
 * NO .data dependency — builds place values at runtime.
 * Uses repeated subtraction (no __divsi3). */
void uart_print_int(int32_t val) {
    if (val < 0) {
        uart_send_byte('-');
        val = -val;
    }
    if (val == 0) {
        uart_send_byte('0');
        return;
    }

    /* Build powers of 10 at runtime — lives in stack, not .data */
    int32_t p10[10];
    p10[0] = 1;
    for (int i = 1; i < 10; i++) {
        /* p10[i] = p10[i-1] * 10, using shifts: x*10 = x*8 + x*2 */
        int32_t prev = p10[i - 1];
        p10[i] = (prev << 3) + (prev << 1);
    }
    /* p10 = {1, 10, 100, ..., 1000000000} */

    int started = 0;
    for (int i = 9; i >= 0; i--) {
        int32_t div = p10[i];
        int digit = 0;
        while (val >= div) {
            val -= div;
            digit++;
        }
        if (digit > 0 || started) {
            uart_send_byte('0' + digit);
            started = 1;
        }
    }
}
