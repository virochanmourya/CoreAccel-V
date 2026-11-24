// bus_stall_interplay — the global MEM stall with every kind of instruction
// sitting in EX (and ID) while a data-bus access waits in MEM.
// BUS_WAIT 5: every bus access gets 5 wait states, whatever the regression's
// WAIT setting, so each case below really stalls.
// - bus store then bus load back to back; load-use on a bus load
// - taken branch / JAL in EX during the stall: redirected once, link once
// - MUL, DIV (load-use operand), MAC, MAC_CLEAR, CSR read-modify-write in EX
// - minstret across a stall: frozen cycles retire nothing
// - TCM store / TCM load in EX behind a stalled bus load or store
// - a faulting bus load (hole): the TCM store and the MAC behind it are
//   killed (the handler samples memory / the accumulator at trap entry)
// - an external interrupt that becomes pending during a stall
#include "test.h"

    BUS_WAIT 5
    EXPECT_DBUS_ERRORS 2
    EXPECT_OTHER_TRAPS 1

    .data
    .balign 4
wts:    .word 7
slot:   .word 0x11111111
slot2:  .word 0x22222222
slot3:  .word 0x33333333

    TEST_BEGIN
    li      a5, 0xC0000000          // peripheral page (on the bus)
    li      s0, 0x1234

    // ---- bus store, then bus load right behind it ----
    sw      s0, 8(a5)               // 7-segment register
    lw      t0, 8(a5)
    CHECK   t0, 0x1234

    // ---- load-use on a bus load ----
    lw      t0, 12(a5)              // GPIO output latch: 3 after reset
    addi    t1, t0, 1
    CHECK   t1, 4

    // ---- taken branch in EX while MEM stalls ----
    li      t1, 0
    lw      t0, 12(a5)
    beq     x0, x0, 1f
    addi    t1, t1, 1               // wrong path
    addi    t1, t1, 2               // wrong path
1:  CHECK   t1, 0
    CHECK   t0, 3

    // ---- JAL in EX while MEM stalls ----
    lw      t0, 12(a5)
    jal     ra, 2f
r1: j       3f
2:  ret
3:  CHECK   ra, r1

    // ---- MUL / DIV in EX behind a stalled load ----
    li      t3, 6
    li      t4, 7
    lw      t0, 12(a5)
    mul     t2, t3, t4
    CHECK   t2, 42
    lw      t0, 12(a5)
    div     t2, t4, t0              // load-use into DIV: 7 / 3
    CHECK   t2, 2

    // ---- MAC and MAC_CLEAR in EX behind a stalled load ----
    la      a1, wts
    MAC_CLEAR
    li      a0, 5
    nop
    lw      t0, 12(a5)
    MAC     a0, a1                  // 5 * 7 = 35, accumulated once
    MAC_RDLO t0
    CHECK   t0, 35
    MAC     a0, a1                  // 70
    lw      t0, 12(a5)
    MAC_CLEAR
    MAC_RDLO t0
    CHECK   t0, 0

    // ---- CSR read-modify-write in EX behind a stalled load ----
    li      t1, 8
    csrw    mscratch, t1
    lw      t0, 12(a5)
    csrrsi  t2, mscratch, 1
    csrr    t3, mscratch
    CHECK   t2, 8
    CHECK   t3, 9

    // ---- minstret: the frozen cycles retire nothing ----
    csrr    t1, minstret
    lw      t0, 12(a5)
    csrr    t2, minstret
    sub     t2, t2, t1
    CHECK   t2, 2

    // ---- TCM store / load in EX behind a stalled bus access ----
    la      a2, slot
    li      t1, 0x5555
    lw      t0, 12(a5)
    sw      t1, 0(a2)               // TCM store in EX, written once
    nop
    nop
    lw      t2, 0(a2)
    CHECK   t2, 0x5555
    lw      t0, 12(a5)
    lw      t2, 0(a2)               // TCM load in EX behind a bus load
    CHECK   t2, 0x5555
    sw      s0, 8(a5)
    lw      t2, 4(a2)               // TCM load in EX behind a bus store
    CHECK   t2, 0x22222222

    // ---- faulting bus load: the TCM store behind it is killed ----
    SET_PROBE slot2, t1
    la      a2, slot2
    li      t1, 0x7777
    li      a3, 0x40000000          // hole: access fault after the wait states
    li      t0, 0x99
e1: lw      t0, 0(a3)
    sw      t1, 0(a2)               // killed; executed again after the handler
    CHECK   t0, 0x99                // rd not written
    CHECK_TRAP 5, e1, 0x40000000
    TRAP_FIELD t2, TR_PROBE
    CHECK   t2, 0x22222222          // memory at trap entry: store not done
    lw      t2, 0(a2)
    CHECK   t2, 0x7777              // ... and done once after the return

    // ---- faulting bus load: the MAC behind it never starts ----
    MAC_CLEAR
    li      a0, 2
    la      a1, wts
    nop
e2: lw      t0, 0(a3)
    MAC     a0, a1                  // killed; executed once after the handler
    MAC_RDLO t0
    CHECK   t0, 14
    CHECK_TRAP 5, e2, 0x40000000
    TRAP_FIELD t2, TR_ACC
    CHECK   t2, 0                   // accumulator at trap entry: untouched

    // ---- external interrupt pending during a stall ----
    li      a0, HALT_ADDR
    li      a1, SIM_EXT_IRQ_ON
    li      t1, 0x800
    csrw    mie, t1
    li      t2, 0
    csrsi   mstatus, 8
    nop
    sw      a1, 0(a0)               // raise the line (core-local, no stall)
    lw      t0, 12(a5)              // the line becomes MEIP during this stall
    addi    t2, t2, 1
i2: addi    t2, t2, 2               // in ID during the stall: takes the interrupt
    addi    t2, t2, 4
    csrci   mstatus, 8
    CHECK   t2, 7                   // each executed exactly once
    CHECK   t0, 3
    CHECK_TRAP 0x8000000b, i2, 0

    TEST_END
