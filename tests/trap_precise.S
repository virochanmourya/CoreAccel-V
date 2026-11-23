// trap_precise — traps are precise. A trap in a taken branch's shadow is
// squashed. An older store before a trap has written. A faulting store does
// not write. The instruction directly behind a trapping one (in EX when the
// trap is taken in MEM) commits nothing: a store, MAC_CLEAR, MAC, MUL, DIV,
// a CSR write, a READ_LO that would set the sticky overflow. It then executes
// exactly once after the handler returns. An older DIV completes before the
// trap. Back-to-back traps are each taken. The handler samples memory, the
// MAC and mie at trap entry (trap_rec), which is what "blocked" is checked
// against.
#include "test.h"

    EXPECT_ILLEGAL 3
    EXPECT_MISALIGNED 1
    EXPECT_OTHER_TRAPS 10

    .data
    .balign 4
wA:     .word 0x1111
wB:     .word 0x2222
w3:     .word 3
wmin:   .word 0x80000000

    TEST_BEGIN
    la      a0, wA
    la      a1, wB
    la      a4, w3

    // ---- 1. trap in a taken branch's shadow: squashed, no trap ----
    beq     zero, zero, 1f
    .word   0x0000007f
    ecall
1:  TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 0

    // ---- 2. trap right after a store: the store has happened ----
    SET_PROBE wA, t2
    li      t1, 0x3333
    sw      t1, 0(a0)
    ecall
    TRAP_FIELD t0, TR_PROBE
    CHECK   t0, 0x3333

    // ---- 3. faulting (misaligned) store: no write ----
    li      t1, 0x4444
t_p3:   sw      t1, 2(a1)
    CHECK_TRAP 6, t_p3, wB+2
    lw      t0, 0(a1)
    CHECK   t0, 0x2222

    // ---- 4. younger store: blocked at the trap, written once after it ----
    SET_PROBE wB, t2
    li      t1, 0x5555
    ecall
    sw      t1, 0(a1)               // in EX when the ECALL traps in MEM
    TRAP_FIELD t0, TR_PROBE
    CHECK   t0, 0x2222
    lw      t0, 0(a1)
    CHECK   t0, 0x5555

    // ---- 5. younger MAC_CLEAR: blocked ----
    MAC_CLEAR
    li      a2, 5
    MAC     a2, a4                  // acc = 15
    ecall
    MAC_CLEAR
    TRAP_FIELD t0, TR_ACC
    CHECK   t0, 15
    MAC_RDLO t0
    CHECK   t0, 0                   // executed after the return

    // ---- 6. younger MAC: no start at the trap, accumulates exactly once ----
    MAC     a2, a4                  // acc = 15
    ecall
    MAC     a2, a4
    TRAP_FIELD t0, TR_ACC
    CHECK   t0, 15
    MAC_RDLO t0
    CHECK   t0, 30

    // ---- 7. younger MUL / DIV: no start at the trap, correct afterwards ----
    li      t1, 7
    li      t2, 6
    ecall
    mul     t3, t1, t2
    CHECK   t3, 42
    ecall
    divu    t4, t1, t2
    CHECK   t4, 1

    // ---- 8. an older DIV completes before a trap right behind it ----
    li      a3, 100
    divu    a5, a3, t1              // 14
t_p8:   .word   0x0000007f
    CHECK   a5, 14
    CHECK_TRAP 2, t_p8, 0

    // ---- 9. younger CSR write: blocked ----
    csrw    mie, zero
    li      a3, 0x80
    ecall
    csrw    mie, a3
    TRAP_FIELD t0, TR_MIE
    CHECK   t0, 0
    csrr    t0, mie
    CHECK   t0, 0x80
    csrw    mie, zero

    // ---- 10. younger READ_LO on an accumulator that does not fit 64 bits:
    //          the sticky overflow is not set at the trap ----
    MAC_CLEAR
    la      a2, wmin
    li      a3, 0x80000000
    MAC     a3, a2
    MAC     a3, a2                  // acc = 2^63: does not fit in signed 64
    MAC_STATUS t0
    CHECK   t0, 0
    ecall
    MAC_RDLO t1                     // saturating read: sets the sticky flag
    TRAP_FIELD t0, TR_MACST
    CHECK   t0, 0                   // not at the trap
    MAC_STATUS t0
    CHECK   t0, 1                   // after the READ_LO ran once
    MAC_CLEAR

    // ---- 11. back-to-back traps ----
    TRAP_FIELD t5, TR_COUNT
t_b1:   .word   0x0000007f
t_b2:   .word   0x0000007f
    CHECK_TRAP 2, t_b2, 0
t_b3:   ecall
t_b4:   ebreak
    CHECK_TRAP 3, t_b4, 0
    TRAP_FIELD t0, TR_COUNT
    sub     t0, t0, t5
    CHECK   t0, 4

    TEST_END
