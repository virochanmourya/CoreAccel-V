// uart0 — UART0 at 0xC000_1000 (APB slot 1): reset values, internal and
// external loopback, 16-deep FIFOs (TX full, RX overrun), RX from the pin
// (good byte, framing error), watermarks and pending bits, TX enable,
// write-1-to-clear status, PSLVERR on an undefined offset.
// Bit time DIV = 16 clocks (one frame = 160 clocks).
#include "test.h"

    EXPECT_DBUS_ERRORS 1

    TEST_BEGIN
    li      a4, UART0_BASE
    li      a0, HALT_ADDR

    // ---- reset values ----
    lw      t0, 0x0C(a4)
    CHECK   t0, 3                       // CTRL: TX and RX enabled
    lw      t0, 0x10(a4)
    CHECK   t0, 868                     // DIV: 100 MHz / 115200
    lw      t0, 0x08(a4)
    CHECK   t0, 1                       // STATUS: TX idle, FIFOs empty
    lw      t0, 0x18(a4)
    CHECK   t0, 1                       // IP: TX level 0 <= watermark 0
    lw      t0, 0x04(a4)
    CHECK   t0, 0x80000000              // RXDATA: empty
    li      t0, 1
    sw      t0, 0x10(a4)
    lw      t0, 0x10(a4)
    CHECK   t0, 4                       // DIV is at least 4
    li      t0, 16
    sw      t0, 0x10(a4)

    // ---- internal loopback: three bytes ----
    li      t0, 7
    sw      t0, 0x0C(a4)
    li      t0, 0x41
    sw      t0, 0(a4)
    li      t0, 0x42
    sw      t0, 0(a4)
    li      t0, 0x43
    sw      t0, 0(a4)
1:  lw      t0, 8(a4)
    srli    t0, t0, 16
    andi    t0, t0, 0x1f
    li      t1, 3
    bne     t0, t1, 1b
    lw      t0, 0x18(a4)
    CHECK   t0, 3                       // IP: TX watermark + RX level 3 > 0
    lw      t0, 4(a4)
    CHECK   t0, 0x41
    lw      t0, 4(a4)
    CHECK   t0, 0x42
    lw      t0, 4(a4)
    CHECK   t0, 0x43
    lw      t0, 4(a4)
    CHECK   t0, 0x80000000

    // ---- 18 bytes: 1 shifting + 16 queued, the 18th dropped (TX full);
    //      RX keeps 16, the 17th overruns ----
    li      t2, 0
2:  sw      t2, 0(a4)
    addi    t2, t2, 1
    li      t1, 18
    bne     t2, t1, 2b
    lw      t0, 8(a4)
    srli    t0, t0, 1
    andi    t0, t0, 1
    CHECK   t0, 1                       // TX full
3:  lw      t0, 8(a4)
    andi    t0, t0, 1
    beqz    t0, 3b                      // wait for TX idle
    lw      t0, 8(a4)
    CHECK   t0, 0x0010001D              // RX level 16, overrun, RX full, RX not empty, TX idle
    li      t3, 0                       // sum of the 16 bytes
    li      t2, 16
4:  lw      t0, 4(a4)
    add     t3, t3, t0
    addi    t2, t2, -1
    bnez    t2, 4b
    CHECK   t3, 120                     // bytes 0..15
    CHECK   t0, 15
    lw      t0, 4(a4)
    CHECK   t0, 0x80000000
    li      t0, 0x10
    sw      t0, 8(a4)                   // clear overrun (W1C)
    lw      t0, 8(a4)
    CHECK   t0, 1

    // ---- external loopback through the pins ----
    li      t0, SIM_UART0_LOOP_ON
    sw      t0, 0(a0)
    li      t0, 3
    sw      t0, 0x0C(a4)                // no internal loopback
    li      t0, 0x5A
    sw      t0, 0(a4)
5:  lw      t0, 8(a4)
    andi    t0, t0, 4
    beqz    t0, 5b
    lw      t0, 4(a4)
    CHECK   t0, 0x5A
    li      t0, SIM_UART0_LOOP_OFF
    sw      t0, 0(a0)

    // ---- RX from the pin: good byte, then a framing error ----
    li      t0, SIM_UART0_SEND | 0xC3
    sw      t0, 0(a0)
6:  lw      t0, 8(a4)
    andi    t0, t0, 4
    beqz    t0, 6b
    lw      t0, 4(a4)
    CHECK   t0, 0xC3
    li      t0, SIM_UART0_BADSTOP | 0x99
    sw      t0, 0(a0)
7:  lw      t0, 8(a4)
    andi    t0, t0, 0x20
    beqz    t0, 7b                      // framing error
    lw      t0, 4(a4)
    CHECK   t0, 0x80000000              // the bad frame was dropped
    lw      t0, 0x18(a4)
    CHECK   t0, 5                       // IP: TX watermark + error
    li      t0, 0x20
    sw      t0, 8(a4)
    lw      t0, 0x18(a4)
    CHECK   t0, 1

    // ---- RX watermark 1: pending only above one byte ----
    li      t0, 0x10007                 // loopback, RX watermark 1
    sw      t0, 0x0C(a4)
    li      t0, 0x11
    sw      t0, 0(a4)
8:  lw      t0, 8(a4)
    andi    t0, t0, 4
    beqz    t0, 8b
    lw      t0, 0x18(a4)
    andi    t0, t0, 2
    CHECK   t0, 0
    li      t0, 0x22
    sw      t0, 0(a4)
9:  lw      t0, 8(a4)
    srli    t0, t0, 16
    andi    t0, t0, 0x1f
    li      t1, 2
    bne     t0, t1, 9b
    lw      t0, 0x18(a4)
    andi    t0, t0, 2
    CHECK   t0, 2
    li      t0, 7
    sw      t0, 0x14(a4)
    lw      t0, 0x14(a4)
    CHECK   t0, 7                       // IE
    sw      zero, 0x14(a4)

    // ---- TX disabled: the byte stays queued ----
    li      t0, 0x10006
    sw      t0, 0x0C(a4)
    li      t0, 0x33
    sw      t0, 0(a4)
    lw      t0, 8(a4)
    srli    t0, t0, 8
    andi    t0, t0, 0x1f
    CHECK   t0, 1

    // ---- undefined offset: PSLVERR -> load access fault ----
    li      t0, 0x55
e1: lw      t0, 0x1C(a4)
    CHECK   t0, 0x55
    CHECK_TRAP 5, e1, 0xC000101C

    TEST_END
