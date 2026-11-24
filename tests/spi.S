// spi — SPI master at 0xC000_2000 (APB slot 2, PLIC source 2).
// - reset values, register widths, PSLVERR on an undefined offset
// - flash model on CS0: read ID (0x9F) in mode 0 with AUTO_CS, read data
//   (0x03 + 24-bit address) in mode 3 with the manual chip select
// - echo target on CS1 in all four modes (reply n = ~byte n-1), LSB first
// - internal loopback, TX FIFO full (9th byte dropped), RX overrun (sticky,
//   W1C), EN = 0 stops a frame
// - IP bits / watermarks; RX watermark interrupt taken through the PLIC
#include "test.h"

#define SPI_EN    0x01
#define SPI_CPHA  0x02
#define SPI_CPOL  0x04
#define SPI_LSBF  0x08
#define SPI_AUTO  0x10
#define SPI_LOOP  0x20
#define SPI_CS1   0x100

    EXPECT_DBUS_ERRORS 1
    EXPECT_OTHER_TRAPS 1

// Wait until the TX FIFO is empty and no frame is in progress (uses t0).
.macro SPI_WAIT_IDLE
91: lw      t0, 8(a4)
    andi    t0, t0, 5
    addi    t0, t0, -4
    bnez    t0, 91b
.endm
// Pop one RX byte and CHECK it (uses t0).
.macro SPI_POP_CHECK exp
    lw      t0, 4(a4)
    CHECK   t0, \exp
.endm
// Echo target: set its mode, set CTRL, send three bytes, check the replies.
.macro ECHO_MODE m
    li      t0, HALT_ADDR
    li      t1, SIM_SPI_ECHO_MODE + \m
    sw      t1, 0(t0)
    li      t0, SPI_EN | SPI_AUTO | SPI_CS1 | ((\m & 2) << 1) | (\m & 1) * SPI_CPHA
    sw      t0, 0x0C(a4)
    li      t0, 0xA1
    sw      t0, 0(a4)
    li      t0, 0x3C
    sw      t0, 0(a4)
    li      t0, 0x96
    sw      t0, 0(a4)
    SPI_WAIT_IDLE
    SPI_POP_CHECK 0x5A                  // first reply
    SPI_POP_CHECK 0x5E                  // ~0xA1
    SPI_POP_CHECK 0xC3                  // ~0x3C
    lw      t0, 8(a4)
    CHECK   t0, 0x4                     // RX empty again, TX empty, idle
.endm

    TEST_BEGIN
    li      a4, SPI_BASE
    li      a6, PLIC_BASE
    li      a7, PLIC_BASE + 0x200000    // threshold; claim/complete at +4
    li      s4, PLIC_BASE + 0x1000      // pending
    li      s3, PLIC_BASE + 0x2000      // enables

    // ---- reset values ----
    lw      t0, 0x00(a4)
    CHECK   t0, 0                       // TX not full
    lw      t0, 0x04(a4)
    CHECK   t0, 0x80000000              // RX empty
    lw      t0, 0x08(a4)
    CHECK   t0, 0x4                     // TX empty, idle
    lw      t0, 0x0C(a4)
    CHECK   t0, 0
    lw      t0, 0x10(a4)
    CHECK   t0, 4                       // DIV reset
    lw      t0, 0x14(a4)
    CHECK   t0, 0
    lw      t0, 0x18(a4)
    CHECK   t0, 0
    lw      t0, 0x1C(a4)
    CHECK   t0, 0x5                     // TX level <= 0, idle

    // ---- register widths ----
    li      t1, -1
    sw      t1, 0x0C(a4)                // EN with an empty FIFO: nothing starts
    lw      t0, 0x0C(a4)
    CHECK   t0, 0x0F0F013F
    sw      zero, 0x0C(a4)
    sw      t1, 0x10(a4)
    lw      t0, 0x10(a4)
    CHECK   t0, 0xFFFF
    li      t0, 1
    sw      t0, 0x10(a4)                // DIV 1: SCK = clk / 4
    sw      t1, 0x14(a4)
    lw      t0, 0x14(a4)
    CHECK   t0, 3                       // two chip selects
    sw      zero, 0x14(a4)
    sw      t1, 0x18(a4)
    lw      t0, 0x18(a4)
    CHECK   t0, 0xF                     // IE & IP != 0: the SPI irq is high now ...
    sw      zero, 0x18(a4)
    lw      t0, 0(s4)
    CHECK   t0, 4                       // ... and the PLIC latched source 2 (cleared below)
    lw      t0, 0x08(a4)
    CHECK   t0, 0x4                     // still idle, FIFOs empty

    // ---- flash: read ID, mode 0, AUTO_CS on CS0 ----
    li      t0, SPI_EN | SPI_AUTO
    sw      t0, 0x0C(a4)
    li      t0, 0x9F
    sw      t0, 0(a4)
    sw      zero, 0(a4)
    sw      zero, 0(a4)
    sw      zero, 0(a4)
    SPI_WAIT_IDLE
    lw      t0, 0x08(a4)
    CHECK   t0, 0x0004000C              // RX level 4, RX not empty, TX empty
    SPI_POP_CHECK 0xFF                  // during the command byte
    SPI_POP_CHECK 0xC2
    SPI_POP_CHECK 0x20
    SPI_POP_CHECK 0x17

    // ---- flash: read data at 0x001234, mode 3, manual CS0 ----
    li      t0, SPI_EN | SPI_CPOL | SPI_CPHA
    sw      t0, 0x0C(a4)
    li      t0, 1
    sw      t0, 0x14(a4)                // assert CS0
    li      t0, 0x03
    sw      t0, 0(a4)
    sw      zero, 0(a4)
    li      t0, 0x12
    sw      t0, 0(a4)
    li      t0, 0x34
    sw      t0, 0(a4)
    sw      zero, 0(a4)
    sw      zero, 0(a4)
    sw      zero, 0(a4)
    SPI_WAIT_IDLE
    sw      zero, 0x14(a4)              // release CS0
    SPI_POP_CHECK 0xFF
    SPI_POP_CHECK 0xFF
    SPI_POP_CHECK 0xFF
    SPI_POP_CHECK 0xFF
    SPI_POP_CHECK 0x1A                  // 0x3C ^ 0x34 ^ 0x12
    SPI_POP_CHECK 0x1B                  // 0x3C ^ 0x35 ^ 0x12
    SPI_POP_CHECK 0x18                  // 0x3C ^ 0x36 ^ 0x12

    // ---- echo target on CS1, all four modes ----
    ECHO_MODE 0
    ECHO_MODE 1
    ECHO_MODE 2
    ECHO_MODE 3

    // ---- LSB first (mode 0): 0x01 goes out as 0x80 ----
    li      t0, HALT_ADDR
    li      t1, SIM_SPI_ECHO_MODE + 0
    sw      t1, 0(t0)
    li      t0, SPI_EN | SPI_AUTO | SPI_CS1 | SPI_LSBF
    sw      t0, 0x0C(a4)
    li      t0, 0x01
    sw      t0, 0(a4)
    li      t0, 0x0F
    sw      t0, 0(a4)
    SPI_WAIT_IDLE
    SPI_POP_CHECK 0x5A                  // 0x5A is its own bit reverse
    SPI_POP_CHECK 0xFE                  // target got 0x80, replied 0x7F, LSB first

    // ---- internal loopback, slow clock ----
    li      t0, 7
    sw      t0, 0x10(a4)                // DIV 7
    li      t0, SPI_EN | SPI_LOOP
    sw      t0, 0x0C(a4)
    li      t0, 0xC5
    sw      t0, 0(a4)
    lw      t0, 0x08(a4)
    andi    t0, t0, 1
    CHECK   t0, 1                       // busy while the frame runs
    lw      t0, 0x1C(a4)
    CHECK   t0, 1                       // TX FIFO empty but not idle yet
    SPI_WAIT_IDLE
    SPI_POP_CHECK 0xC5
    li      t0, 1
    sw      t0, 0x10(a4)

    // ---- TX FIFO full: 8 kept, the 9th dropped ----
    sw      zero, 0x0C(a4)              // EN = 0: bytes stay in the FIFO
    li      t1, 0x10
    li      t2, 9
1:  sw      t1, 0(a4)
    addi    t1, t1, 1
    addi    t2, t2, -1
    bnez    t2, 1b
    lw      t0, 0x00(a4)
    CHECK   t0, 0x80000000              // TX full
    lw      t0, 0x08(a4)
    CHECK   t0, 0x00000802              // TX level 8, TX full, not busy
    lw      t0, 0x1C(a4)
    CHECK   t0, 0                       // level 8 > watermark 0, not idle (TX not empty)

    // ---- RX overrun: 8 bytes fill RX, a 9th is dropped ----
    li      t0, SPI_EN | SPI_LOOP
    sw      t0, 0x0C(a4)                // the 8 queued bytes go out
    SPI_WAIT_IDLE
    lw      t0, 0x08(a4)
    CHECK   t0, 0x0008001C              // RX level 8, RX full, RX not empty, TX empty
    li      t0, 0x77
    sw      t0, 0(a4)
    SPI_WAIT_IDLE
    lw      t0, 0x08(a4)
    CHECK   t0, 0x0008003C              // + overrun
    lw      t0, 0x1C(a4)
    CHECK   t0, 0xF                     // TX wm, RX wm, idle, overrun
    li      t0, 0x20
    sw      t0, 0x08(a4)                // W1C overrun
    lw      t0, 0x08(a4)
    CHECK   t0, 0x0008001C
    SPI_POP_CHECK 0x10                  // oldest byte
    li      t2, 6
2:  lw      t0, 4(a4)
    addi    t2, t2, -1
    bnez    t2, 2b
    SPI_POP_CHECK 0x17                  // 8th byte; the 9th (0x18) and 0x77 were dropped
    lw      t0, 0x04(a4)
    CHECK   t0, 0x80000000

    // ---- EN = 0 stops a frame at once ----
    li      t0, 200
    sw      t0, 0x10(a4)                // a very slow clock
    li      t0, 0x99
    sw      t0, 0(a4)
    nop
    sw      zero, 0x0C(a4)              // EN = 0 during the first half bit
    lw      t0, 0x08(a4)
    CHECK   t0, 0x4                     // idle, nothing received
    li      t0, 1
    sw      t0, 0x10(a4)

    // ---- watermarks ----
    li      t0, (3 << 24) | (2 << 16)   // RX wm 3, TX wm 2, EN = 0
    sw      t0, 0x0C(a4)
    li      t0, 0xA0
    sw      t0, 0(a4)
    sw      t0, 0(a4)
    lw      t0, 0x1C(a4)
    CHECK   t0, 1                       // TX level 2 <= 2, not idle
    li      t0, 0xA0
    sw      t0, 0(a4)
    lw      t0, 0x1C(a4)
    CHECK   t0, 0                       // TX level 3 > 2
    li      t0, (3 << 24) | (2 << 16) | SPI_EN | SPI_LOOP
    sw      t0, 0x0C(a4)
    SPI_WAIT_IDLE
    lw      t0, 0x1C(a4)
    CHECK   t0, 5                       // RX level 3 is not > 3
    li      t0, 0xA0
    sw      t0, 0(a4)
    SPI_WAIT_IDLE
    lw      t0, 0x1C(a4)
    CHECK   t0, 7                       // RX level 4 > 3
    li      t2, 4
3:  lw      t0, 4(a4)                   // drain
    addi    t2, t2, -1
    bnez    t2, 3b

    // ---- RX watermark interrupt through the PLIC (source 2) ----
    li      t0, SPI_EN | SPI_LOOP       // watermarks 0
    sw      t0, 0x0C(a4)
    li      t0, 2
    sw      t0, 0x18(a4)                // IE: RX watermark
    li      t0, 3
    sw      t0, 8(a6)                   // priority[2] = 3
    li      t0, 4
    sw      t0, 0(s3)                   // enable source 2
    lw      t0, 4(a7)
    CHECK   t0, 2                       // the stale pending from the IE width test
    li      t0, 2
    sw      t0, 4(a7)                   // complete: the source is low, nothing re-pends
    lw      t0, 0(s4)
    CHECK   t0, 0
    la      t0, spi_handler
    csrw    mtvec, t0
    li      s6, 0
    li      s9, 0
    li      s7, 0
    li      t0, 0x800
    csrw    mie, t0
    csrsi   mstatus, 8
    li      t0, 0x6B
    sw      t0, 0(a4)                   // byte -> RX -> source 2 -> MEIP
4:  beqz    s6, 4b
    csrci   mstatus, 8
    CHECK   s6, 1                       // exactly once
    CHECK   s9, 2                       // claimed source 2
    CHECK   s7, 0x6B
    csrr    t0, mcause
    CHECK   t0, 0x8000000b
    lw      t0, 0(s4)
    CHECK   t0, 0                       // nothing pending
    la      t0, _trap_entry
    csrw    mtvec, t0
    sw      zero, 0x18(a4)

    // ---- undefined offset: PSLVERR ----
    li      t0, 0x55
    li      a3, SPI_BASE + 0x20
e1: lw      t0, 0(a3)
    CHECK   t0, 0x55
    CHECK_TRAP 5, e1, 0xC0002020

    TEST_END

    .text
    .balign 4
spi_handler:
    lw      s9, 4(a7)                   // claim
    lw      s7, 4(a4)                   // pop the byte: the SPI irq drops
    sw      s9, 4(a7)                   // complete
    addi    s6, s6, 1
    mret
