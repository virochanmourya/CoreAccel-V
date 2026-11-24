// plic2 — PLIC arbitration with two live sources: UART0 (source 1, IE =
// TX watermark: high while its TX FIFO is empty) and SPI (source 2, IE =
// idle: high while it is idle). Both are level sources the test switches
// with their IE registers.
// - both pending; higher priority wins the claim, then the other
// - equal priority: the lower id wins
// - a disabled source is never claimed, even with the higher priority
// - threshold is strict (priority > threshold) and MEIP follows the best
//   pending, enabled, unclaimed source (eip is registered: allow a cycle)
// - taken through mtvec: two interrupts, handled in priority order
#include "test.h"

    EXPECT_OTHER_TRAPS 2

// Read mip.MEIP into \reg (after a few cycles for the registered eip and
// the core's 2-FF synchroniser).
.macro MEIP reg
    nop
    nop
    nop
    nop
    csrr    \reg, mip
    srli    \reg, \reg, 11
    andi    \reg, \reg, 1
.endm

    TEST_BEGIN
    li      a4, UART0_BASE
    li      a5, SPI_BASE
    li      a6, PLIC_BASE
    li      a7, PLIC_BASE + 0x200000    // threshold; claim/complete at +4
    li      s4, PLIC_BASE + 0x1000      // pending
    li      s3, PLIC_BASE + 0x2000      // enables

    // ---- both sources high -> both pending ----
    li      t0, 1
    sw      t0, 0x14(a4)                // UART0 IE: TX watermark (TX empty)
    li      t0, 4
    sw      t0, 0x18(a5)                // SPI IE: idle
    lw      t0, 0(s4)
    CHECK   t0, 6
    MEIP    t0
    CHECK   t0, 0                       // nothing enabled
    li      t0, 6
    sw      t0, 0(s3)                   // enable 1 and 2
    MEIP    t0
    CHECK   t0, 0                       // priorities 0: never

    // ---- priority: 2 (prio 2) beats 1 (prio 1) ----
    li      t0, 1
    sw      t0, 4(a6)
    li      t0, 2
    sw      t0, 8(a6)
    MEIP    t0
    CHECK   t0, 1
    lw      t0, 4(a7)
    CHECK   t0, 2
    lw      t0, 4(a7)
    CHECK   t0, 1                       // 2 is in flight: next best
    lw      t0, 4(a7)
    CHECK   t0, 0                       // both in flight
    lw      t0, 0(s4)
    CHECK   t0, 0
    MEIP    t0
    CHECK   t0, 0
    li      t0, 1
    sw      t0, 4(a7)                   // complete 1 (still high: re-pends)
    li      t0, 2
    sw      t0, 4(a7)                   // complete 2
    lw      t0, 0(s4)
    CHECK   t0, 6

    // ---- swap priorities: 1 (prio 5) beats 2 (prio 4) ----
    li      t0, 5
    sw      t0, 4(a6)
    li      t0, 4
    sw      t0, 8(a6)
    lw      t0, 4(a7)
    CHECK   t0, 1
    li      t0, 1
    sw      t0, 4(a7)
    lw      t0, 4(a7)
    CHECK   t0, 1                       // completed and still high: wins again
    li      t0, 1
    sw      t0, 4(a7)

    // ---- tie: equal priority -> the lower id ----
    li      t0, 3
    sw      t0, 4(a6)
    sw      t0, 8(a6)
    lw      t0, 4(a7)
    CHECK   t0, 1
    lw      t0, 4(a7)
    CHECK   t0, 2
    li      t0, 1
    sw      t0, 4(a7)
    li      t0, 2
    sw      t0, 4(a7)

    // ---- disabled source: never claimed ----
    li      t0, 7
    sw      t0, 8(a6)                   // 2 has the higher priority ...
    li      t0, 2
    sw      t0, 0(s3)                   // ... but only 1 is enabled
    lw      t0, 4(a7)
    CHECK   t0, 1
    li      t0, 1
    sw      t0, 4(a7)
    li      t0, 6
    sw      t0, 0(s3)

    // ---- threshold (strict) ----
    li      t0, 2
    sw      t0, 4(a6)                   // prio1 = 2
    li      t0, 3
    sw      t0, 8(a6)                   // prio2 = 3
    li      t0, 3
    sw      t0, 0(a7)                   // threshold 3: nothing above it
    MEIP    t0
    CHECK   t0, 0
    li      t0, 2
    sw      t0, 0(a7)                   // threshold 2: source 2 (3 > 2)
    MEIP    t0
    CHECK   t0, 1
    lw      t0, 4(a7)
    CHECK   t0, 2
    MEIP    t0
    CHECK   t0, 0                       // left: source 1, prio 2, not > 2
    li      t0, 1
    sw      t0, 0(a7)                   // threshold 1: source 1 shows
    MEIP    t0
    CHECK   t0, 1
    sw      zero, 0x18(a5)              // SPI IE off: source 2 drops
    li      t0, 2
    sw      t0, 4(a7)                   // complete 2: low, does not re-pend
    lw      t0, 0(s4)
    CHECK   t0, 2                       // only source 1 pending
    sw      zero, 0(a7)

    // ---- taken: two interrupts, in priority order ----
    li      t0, 4
    sw      t0, 0x18(a5)                // SPI source high again (prio 3)
    lw      t0, 0(s4)
    CHECK   t0, 6
    la      t0, plic2_handler
    csrw    mtvec, t0
    li      s6, 0                       // handler count
    li      s7, 0                       // claimed ids, shifted in (first in bits 15:8)
    li      t0, 0x800
    csrw    mie, t0
    csrsi   mstatus, 8
1:  li      t0, 2
    blt     s6, t0, 1b
    csrci   mstatus, 8
    CHECK   s6, 2
    CHECK   s7, 0x0201                  // 2 first, then 1
    lw      t0, 0(s4)
    CHECK   t0, 0
    lw      t0, 4(a7)
    CHECK   t0, 0
    la      t0, _trap_entry
    csrw    mtvec, t0

    TEST_END

    .text
    .balign 4
// Claim, silence that source at the peripheral, complete.
plic2_handler:
    lw      t1, 4(a7)                   // claim
    slli    s7, s7, 8
    or      s7, s7, t1
    li      t2, 1
    bne     t1, t2, 2f
    sw      zero, 0x14(a4)              // source 1: UART0 IE off
    j       3f
2:  sw      zero, 0x18(a5)              // source 2: SPI IE off
3:  sw      t1, 4(a7)                   // complete
    addi    s6, s6, 1
    mret
