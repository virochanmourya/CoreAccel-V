// irq_ext — external interrupt (one level-sensitive line, tied off in the
// RTL; the harness drives it through the simulation control word:
// SIM_EXT_IRQ_ON / _OFF stored to HALT_ADDR).
// - mip.MEIP follows the line through the 2-FF synchroniser (MIE = 0).
// - Raised with MEIE and MIE set: the line goes high the cycle after the
//   store leaves MEM, and MEIP two cycles later. So the 5th instruction
//   behind the store takes the interrupt (mepc = it).
// - Raised just before a DIV: it arrives while the DIV holds EX and is taken
//   after the DIV completes (mepc = the next instruction; DIV result written).
// - It arrives exactly while a CSR write clearing MIE is in EX: the ID
//   instruction is not tagged (the tag waits for CSR writes), so it is never
//   taken while disabled.
// - External and timer both pending: external first (mcause 11).
// The default handler drops the line and silences the timer.
#include "test.h"

    EXPECT_OTHER_TRAPS 3

    TEST_BEGIN
    li      a0, HALT_ADDR
    li      a1, SIM_EXT_IRQ_ON
    li      a2, SIM_EXT_IRQ_OFF

    // ---- MEIP follows the line ----
    csrr    t0, mip
    CHECK   t0, 0
    sw      a1, 0(a0)
    nop
    nop
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0x800
    sw      a2, 0(a0)
    nop
    nop
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 0

    // ---- taken with MEIE and MIE ----
    li      t1, 0x800
    csrw    mie, t1
    csrsi   mstatus, 8
    nop
    sw      a1, 0(a0)                   // raise
    nop
    nop
    nop
    nop
e1: nop                                 // takes the interrupt
    CHECK_TRAP 0x8000000b, e1, 0
    csrr    t0, mip
    CHECK   t0, 0                       // the handler dropped the line

    // ---- arrives while a DIV holds EX ----
    li      t1, 1000
    li      t2, 3
    sw      a1, 0(a0)                   // raise: MEIP rises during the DIV
    divu    t3, t1, t2
e2: li      t4, 9                       // tagged in ID behind the held DIV
    CHECK   t3, 333
    CHECK   t4, 9
    CHECK_TRAP 0x8000000b, e2, 0

    // ---- arrives exactly as a CSR write disables interrupts: not taken ----
    TRAP_FIELD t5, TR_COUNT
    sw      a1, 0(a0)                   // raise (same timing as e1)
    nop
    nop
    nop
    csrci   mstatus, 8                  // in EX the cycle MEIP rises
    nop                                 // in ID then (the e1 slot): must not be tagged
    nop
    TRAP_FIELD t0, TR_COUNT
    sub     t0, t0, t5
    CHECK   t0, 0
    csrr    t0, mip
    CHECK   t0, 0x800                   // still pending, just disabled
    sw      a2, 0(a0)                   // drop the line
    nop
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0

    // ---- external has priority over timer ----
    csrci   mstatus, 8
    li      t1, 0x880
    csrw    mie, t1
    li      t5, MTIMER_BASE
    sw      zero, 12(t5)                // timer pending
    sw      zero, 8(t5)
    sw      a1, 0(a0)                   // external pending
    nop
    nop
    nop
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0x880
    csrsi   mstatus, 8
    nop                                 // in ID with the CSR write in EX: not tagged
e3: nop
    CHECK_TRAP 0x8000000b, e3, 0
    csrr    t0, mip
    CHECK   t0, 0                       // the handler silenced both
    csrci   mstatus, 8
    csrw    mie, zero

    TEST_END
