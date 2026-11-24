// plic — PLIC at 0xC400_0000 (standard offsets, sources 1..16, 3-bit
// priority, one M-mode context) with UART0 as source 1.
// - reset values; priority / enable / threshold read-back and widths
// - gateway: UART0's RX level makes source 1 pending; MEIP only when
//   enabled and priority > threshold
// - claim returns 1 and clears pending; the source stays blocked until
//   complete; complete with the source still high re-pends it; claim 0
//   when nothing is pending
// - an interrupt taken through mtvec: the handler claims, pops the UART
//   byte (drops the source) and completes; it runs exactly once
// - an offset outside the PLIC map: PSLVERR -> load access fault
#include "test.h"

    EXPECT_DBUS_ERRORS 1
    EXPECT_OTHER_TRAPS 1

    TEST_BEGIN
    li      a4, UART0_BASE
    li      a6, PLIC_BASE
    li      a7, PLIC_BASE + 0x200000    // threshold; claim/complete at +4
    li      s4, PLIC_BASE + 0x1000      // pending
    li      s3, PLIC_BASE + 0x2000      // enables
    li      s2, 0x800                   // mip.MEIP

    // ---- reset values ----
    lw      t0, 4(a6)
    CHECK   t0, 0                       // priority[1]
    lw      t0, 0(s3)
    CHECK   t0, 0                       // enables
    lw      t0, 0(a7)
    CHECK   t0, 0                       // threshold
    lw      t0, 4(a7)
    CHECK   t0, 0                       // claim: nothing pending

    // ---- register widths ----
    li      t0, -1
    sw      t0, 64(a6)                  // priority[16]
    lw      t1, 64(a6)
    CHECK   t1, 7
    sw      zero, 64(a6)
    sw      t0, 0(a6)                   // priority[0]: no such source
    lw      t1, 0(a6)
    CHECK   t1, 0
    sw      t0, 0(s3)
    lw      t1, 0(s3)
    CHECK   t1, 0x1FFFE                 // enable bits 1..16
    sw      zero, 0(s3)
    sw      t0, 0(a7)
    lw      t1, 0(a7)
    CHECK   t1, 7
    sw      zero, 0(a7)

    // ---- UART0 RX not empty -> source 1 pending ----
    li      t0, 16
    sw      t0, 0x10(a4)                // DIV 16
    li      t0, 7
    sw      t0, 0x0C(a4)                // internal loopback
    li      t0, 2
    sw      t0, 0x14(a4)                // IE: RX watermark
    li      t0, 0x61
    sw      t0, 0(a4)
1:  lw      t0, 0(s4)
    beqz    t0, 1b
    CHECK   t0, 2                       // pending bit 1
    csrr    t0, mip
    and     t0, t0, s2
    CHECK   t0, 0                       // priority 0: never
    li      t0, 1
    sw      t0, 4(a6)                   // priority[1] = 1
    li      t0, 2
    sw      t0, 0(s3)                   // enable source 1
2:  csrr    t0, mip
    and     t0, t0, s2
    beqz    t0, 2b                      // MEIP rises (priority 1 > threshold 0)
    li      t0, 1
    sw      t0, 0(a7)                   // threshold 1: masked
    nop
    nop
    nop
    nop
    nop
    csrr    t0, mip
    and     t0, t0, s2
    CHECK   t0, 0
    sw      zero, 0(a7)

    // ---- claim / complete ----
    lw      t0, 4(a7)
    CHECK   t0, 1                       // claim source 1
    lw      t0, 0(s4)
    CHECK   t0, 0                       // pending cleared
    lw      t0, 4(a7)
    CHECK   t0, 0                       // blocked until complete
    li      t0, 1
    sw      t0, 4(a7)                   // complete: UART still high -> pending again
    lw      t0, 0(s4)
    CHECK   t0, 2
    lw      t0, 4(a7)
    CHECK   t0, 1
    lw      t0, 4(a4)
    CHECK   t0, 0x61                    // pop: the source drops
    li      t0, 1
    sw      t0, 4(a7)                   // complete
    lw      t0, 0(s4)
    CHECK   t0, 0
    lw      t0, 4(a7)
    CHECK   t0, 0

    // ---- taken through mtvec: the handler claims, pops, completes ----
    la      t0, plic_handler
    csrw    mtvec, t0
    li      s6, 0                       // handler count
    li      s9, 0                       // claimed id
    li      s7, 0                       // popped byte
    csrw    mie, s2
    csrsi   mstatus, 8
    li      t0, 0x7E
    sw      t0, 0(a4)                   // byte -> RX -> source 1 -> MEIP
3:  beqz    s6, 3b
    csrci   mstatus, 8
    CHECK   s6, 1                       // exactly once
    CHECK   s9, 1
    CHECK   s7, 0x7E
    csrr    t0, mcause
    CHECK   t0, 0x8000000b
    lw      t0, 0(s4)
    CHECK   t0, 0
    la      t0, _trap_entry
    csrw    mtvec, t0

    // ---- outside the map: PSLVERR ----
    li      t0, 0x55
    li      a3, PLIC_BASE + 0x3000
e1: lw      t0, 0(a3)
    CHECK   t0, 0x55
    CHECK_TRAP 5, e1, 0xC4003000

    TEST_END

    .text
    .balign 4
plic_handler:
    lw      s9, 4(a7)                   // claim
    lw      s7, 4(a4)                   // pop the byte: UART0 irq drops
    sw      s9, 4(a7)                   // complete
    addi    s6, s6, 1
    mret
