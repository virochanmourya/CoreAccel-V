// mmio — 7-seg write/readback, GPIO output register readback, UART busy poll.
// (GPIO pin input is covered separately by gpio_loopback.)
#include "test.h"

#define PERIPH_BASE 0xC0000000
#define GPIO_OFF    0x0
#define UART_OFF    0x4
#define SEG_OFF     0x8
#define GPIO_DBG    0xC

    TEST_BEGIN
    li      a0, PERIPH_BASE

    // 7-segment data register (16 bits)
    li      t0, 0x1234
    sw      t0, SEG_OFF(a0)
    lw      t1, SEG_OFF(a0)
    CHECK   t1, 0x00001234
    li      t0, 0xabcdf00d
    sw      t0, SEG_OFF(a0)
    lw      t1, SEG_OFF(a0)
    CHECK   t1, 0x0000f00d

    // GPIO output latch, read back through the debug slot
    li      t0, 2
    sw      t0, GPIO_OFF(a0)
    lw      t1, GPIO_DBG(a0)
    CHECK   t1, 2
    li      t0, -3                  // only bits [1:0] are kept
    sw      t0, GPIO_OFF(a0)
    lw      t1, GPIO_DBG(a0)
    CHECK   t1, 1
    li      t0, 3                   // release both lines
    sw      t0, GPIO_OFF(a0)

    // UART: idle, busy right after a write, idle again after the byte
    lw      t1, UART_OFF(a0)
    CHECK   t1, 0
    li      t0, 0x41                // 'A'
    sw      t0, UART_OFF(a0)
    lw      t1, UART_OFF(a0)
    CHECK   t1, 1
1:  lw      t1, UART_OFF(a0)
    bnez    t1, 1b
    CHECK   t1, 0

    TEST_END
