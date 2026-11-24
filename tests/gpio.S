// gpio — GPIO at 0xC000_4000 (APB slot 4, PLIC source 4), 16 pins.
// Testbench: every pin has a weak pull-down, and gpio[7:0] drives
// gpio[15:8] at pull strength, so a low-byte output shows on the high
// byte, an undriven pin reads 0, and a pin the DUT drives reads its own
// value (strong beats the loop).
// - reset values, register widths, SET / CLR, OE
// - edge (rising, falling, both) and level (high, low) status, W1C, a
//   clear never hides an event, level bits ignore W1C and follow the pin
// - STATUS records events with IE = 0; IE gates only the interrupt
// - one interrupt through the PLIC (source 4); PSLVERR on 0x28
#include "test.h"

#define G_OUT    0x00
#define G_OE     0x04
#define G_IN     0x08
#define G_SET    0x0C
#define G_CLR    0x10
#define G_IE     0x14
#define G_MODE   0x18
#define G_POL    0x1C
#define G_BOTH   0x20
#define G_STATUS 0x24

    EXPECT_DBUS_ERRORS 1
    EXPECT_OTHER_TRAPS 1

// Let a pin change pass the 2-FF synchroniser and the edge register.
.macro SETTLE
    nop
    nop
    nop
    nop
.endm
.macro WR off, v
    li      t0, \v
    sw      t0, \off(a4)
.endm
.macro RD off, exp
    lw      t0, \off(a4)
    CHECK   t0, \exp
.endm

    TEST_BEGIN
    li      a4, GPIO_BASE
    li      a6, PLIC_BASE

    // ---- reset values ----
    RD      G_OUT, 0
    RD      G_OE, 0
    RD      G_IN, 0                     // all pulled down
    RD      G_SET, 0
    RD      G_CLR, 0
    RD      G_IE, 0
    RD      G_MODE, 0
    RD      G_POL, 0
    RD      G_BOTH, 0
    RD      G_STATUS, 0

    // ---- widths (16 pins) ----
    WR      G_OUT, -1
    RD      G_OUT, 0xFFFF
    WR      G_IE, -1
    RD      G_IE, 0xFFFF
    WR      G_IE, 0                     // (a level source would latch in the PLIC)
    WR      G_MODE, -1
    RD      G_MODE, 0xFFFF
    WR      G_POL, -1
    RD      G_POL, 0xFFFF
    WR      G_BOTH, -1
    RD      G_BOTH, 0xFFFF
    RD      G_STATUS, 0xFFFF            // all level-low, all pins low
    WR      G_BOTH, 0
    WR      G_POL, 0
    WR      G_MODE, 0
    RD      G_IN, 0                     // OUT set but OE = 0: nothing driven

    // ---- OE, OUT, SET, CLR through the loop ----
    WR      G_OUT, 0x00A5
    WR      G_OE, 0x00FF
    RD      G_OE, 0x00FF                // (OUT holds 0x00A5)
    SETTLE
    RD      G_IN, 0xA5A5                // low byte driven, looped to the high byte
    WR      G_SET, 0x0018
    SETTLE
    RD      G_OUT, 0x00BD
    RD      G_IN, 0xBDBD
    WR      G_CLR, 0x0081
    SETTLE
    RD      G_OUT, 0x003C
    RD      G_IN, 0x3C3C
    WR      G_OE, 0xFF0F                // high byte driven by the DUT itself
    WR      G_OUT, 0x5A0C
    SETTLE
    RD      G_IN, 0x5A0C                // pins 4..7 released: pulled down
    WR      G_OE, 0x00FF
    WR      G_OUT, 0
    SETTLE
    WR      G_STATUS, 0xFFFF            // drop edges seen so far
    RD      G_STATUS, 0

    // ---- edge and level status (IE = 0) ----
    // pin 8 rising, pin 9 falling, pin 10 both, pin 11 level high,
    // pin 12 level low; the low byte drives them (and, rising-edge pins
    // themselves, records its own rising edges).
    WR      G_MODE, 0x1800
    WR      G_POL, 0x1200
    WR      G_BOTH, 0x0400
    RD      G_STATUS, 0x1000            // pin 12 low: level-low true at once
    WR      G_OUT, 0x001F               // pins 0..4 up -> 8..12 rise
    SETTLE
    RD      G_STATUS, 0x0D1F            // 8 rise, 10 edge, 11 high, 12 false; 0..4 rise
    WR      G_STATUS, 0x1F1F            // W1C: edges clear, level 11 stays
    RD      G_STATUS, 0x0800
    WR      G_OUT, 0x0000               // all fall
    SETTLE
    RD      G_STATUS, 0x1600            // 9 fall, 10 edge, 12 low (0..4: rising only)
    WR      G_STATUS, 0x0200            // clear pin 9 only
    RD      G_STATUS, 0x1400
    WR      G_STATUS, 0x0400
    RD      G_STATUS, 0x1000
    WR      G_MODE, 0x0000              // all edge now: level history gone
    RD      G_STATUS, 0
    WR      G_POL, 0
    WR      G_BOTH, 0

    // ---- W1C clears only the bits written ----
    WR      G_OUT, 0x0001               // pins 0 and 8 rise
    SETTLE
    WR      G_STATUS, 0x0200
    RD      G_STATUS, 0x0101
    WR      G_STATUS, 0x0101
    RD      G_STATUS, 0
    WR      G_OUT, 0
    // a pending edge is dropped when its pin goes to level mode
    WR      G_OUT, 0x0001               // pins 0, 8 rise
    SETTLE
    RD      G_STATUS, 0x0101
    WR      G_MODE, 0x0100              // pin 8 -> level-high mode
    WR      G_OUT, 0                    // pin 8 low: level false
    SETTLE
    WR      G_MODE, 0                   // back to edge: no old edge
    RD      G_STATUS, 0x0001
    WR      G_STATUS, 0xFFFF

    // ---- interrupt through the PLIC (source 4): pin 13 rising ----
    li      t0, 3
    sw      t0, 16(a6)                  // priority[4] = 3
    li      t0, 0x10
    li      t1, PLIC_BASE + 0x2000
    sw      t0, 0(t1)                   // enable source 4
    li      t1, PLIC_BASE + 0x1000
    lw      t0, 0(t1)
    CHECK   t0, 0                       // IE = 0: nothing pending yet
    WR      G_IE, 0x2000
    la      t0, gpio_handler
    csrw    mtvec, t0
    li      s6, 0
    li      s9, 0
    li      t0, 0x800
    csrw    mie, t0
    csrsi   mstatus, 8
    WR      G_OUT, 0x0020               // pin 5 -> pin 13 rises
1:  beqz    s6, 1b
    csrci   mstatus, 8
    CHECK   s6, 1
    CHECK   s9, 4                       // claimed source 4
    CHECK   s8, 0x2020                  // STATUS seen by the handler (pins 5, 13)
    RD      G_STATUS, 0                 // the handler cleared it
    li      t1, PLIC_BASE + 0x1000
    lw      t0, 0(t1)
    CHECK   t0, 0
    la      t0, _trap_entry
    csrw    mtvec, t0
    WR      G_IE, 0
    WR      G_OUT, 0
    WR      G_OE, 0

    // ---- PSLVERR ----
    li      t0, 0x77
    li      a3, GPIO_BASE + 0x28
e1: lw      t0, 0(a3)
    CHECK   t0, 0x77
    CHECK_TRAP 5, e1, 0xC0004028

    TEST_END

    .text
    .balign 4
gpio_handler:
    li      t2, PLIC_BASE + 0x200004
    lw      s9, 0(t2)                   // claim
    lw      s8, G_STATUS(a4)
    sw      s8, G_STATUS(a4)            // W1C: the GPIO irq drops
    sw      s9, 0(t2)                   // complete
    addi    s6, s6, 1
    mret
