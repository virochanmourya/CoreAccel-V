// csr_counters — mcycle / minstret and their cycle / instret shadows.
// The pipeline is deterministic, so deltas are exact: mcycle counts every
// cycle; minstret counts instructions reaching WB and skips bubbles (load-use
// stall, taken-branch flush, MUL hold). Writes: a written half reads back
// as written; a write to mcycle's low half carries into the high half later.
#include "test.h"

    .data
    .balign 4
word:   .word 41

    TEST_BEGIN
    la      a0, word
    nop
    nop
    nop

    // ---- straight-line code: +4 cycles, +4 instructions ----
    csrr    t0, mcycle
    nop
    nop
    nop
    csrr    t1, mcycle
    sub     a1, t1, t0
    nop
    nop
    csrr    t0, minstret
    nop
    nop
    nop
    csrr    t1, minstret
    sub     a2, t1, t0
    CHECK   a1, 4
    CHECK   a2, 4

    // ---- load-use stall: one bubble (cycle, no instruction) ----
    nop
    nop
    csrr    t0, mcycle
    lw      t3, 0(a0)
    addi    t4, t3, 1
    nop
    nop
    nop
    csrr    t1, mcycle
    sub     a1, t1, t0
    nop
    nop
    csrr    t0, minstret
    lw      t3, 0(a0)
    addi    t4, t3, 1
    nop
    nop
    nop
    csrr    t1, minstret
    sub     a2, t1, t0
    CHECK   a1, 7
    CHECK   a2, 6
    CHECK   t4, 42

    // ---- taken branch: two flushed slots ----
    nop
    nop
    csrr    t0, mcycle
    beq     zero, zero, 1f
    nop
    nop
1:  nop
    nop
    nop
    csrr    t1, mcycle
    sub     a1, t1, t0
    nop
    nop
    csrr    t0, minstret
    beq     zero, zero, 2f
    nop
    nop
2:  nop
    nop
    nop
    csrr    t1, minstret
    sub     a2, t1, t0
    CHECK   a1, 7
    CHECK   a2, 5

    // ---- MUL holds EX for 3 cycles ----
    li      t5, 3
    nop
    nop
    csrr    t0, mcycle
    mul     t6, t5, t5
    nop
    nop
    nop
    csrr    t1, mcycle
    sub     a1, t1, t0
    nop
    nop
    csrr    t0, minstret
    mul     t6, t5, t5
    nop
    nop
    nop
    csrr    t1, minstret
    sub     a2, t1, t0
    CHECK   a1, 8
    CHECK   a2, 5

    // ---- shadows: cycle / instret read the same counters ----
    nop
    nop
    csrr    t0, mcycle
    csrr    t1, cycle
    sub     a1, t1, t0
    csrr    t0, minstret
    csrr    t1, instret
    sub     a2, t1, t0
    CHECK   a1, 1
    CHECK   a2, 1

    // ---- writes ----
    li      t0, 5
    csrw    mcycleh, t0
    csrr    t1, mcycleh
    csrr    t2, cycleh
    CHECK   t1, 5
    CHECK   t2, 5
    li      t0, -8
    csrw    mcycle, t0              // low half = 0xfffffff8: wraps 8 cycles later
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    csrr    t1, mcycleh             // 10 nops later: carried
    csrr    t2, mcycle
    CHECK   t1, 6
    CHECK   t2, 3
    li      t0, 0x77
    csrw    minstreth, t0
    csrr    t1, minstreth
    csrr    t2, instreth
    CHECK   t1, 0x77
    CHECK   t2, 0x77
    li      t0, 0x1000
    csrw    minstret, t0
    csrr    t1, minstret            // the write wins over that cycle's increment
    CHECK   t1, 0x1000

    TEST_END
