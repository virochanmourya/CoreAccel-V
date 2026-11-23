// store_load_tcm — B1: TCM store immediately followed by a TCM load to a
// DIFFERENT address. Each load target is pre-initialised to a value that
// differs from the data being stored.
#include "test.h"

    .data
    .balign 4
wa:     .word 0xaaaaaaaa
wb:     .word 0xbbbbbbbb
wc:     .word 0xcccccccc
wd:     .word 0xdddddddd
we:     .word 0xeeeeeeee, 0xeeeeeeee, 0xeeeeeeee, 0xeeeeeeee
src:    .word 0x55aa55aa

    TEST_BEGIN
    la      a0, wa
    li      t0, 0x12345678
    li      t3, 0xcafef00d
    nop

    sw      t0, 0(a0)               // store wa
    lw      t1, 4(a0)               // load wb  -> 0xbbbbbbbb
    CHECK   t1, 0xbbbbbbbb

    sw      t3, 4(a0)               // store wb
    lw      t2, 0(a0)               // load wa  -> 0x12345678 (written above)
    CHECK   t2, 0x12345678

    // both stores landed
    nop
    lw      t4, 0(a0)
    CHECK   t4, 0x12345678
    lw      t5, 4(a0)
    CHECK   t5, 0xcafef00d

    // stack-style: push then reload a different slot
    li      sp, 0x80001000
    addi    sp, sp, -16
    li      a1, 0x600d
    sw      a1, 12(sp)
    nop
    nop
    li      a2, 0x1111
    sw      a2, 8(sp)
    lw      a3, 12(sp)              // must be 0x600d, not 0x1111
    CHECK   a3, 0x600d

    // store followed by load, with the load's base forwarded from EX/MEM
    la      a4, wc
    li      a5, 0x77777777
    sw      a5, 0(a4)
    addi    a6, a4, 4
    nop
    sw      a5, 0(a4)
    lw      a7, 0(a6)               // wd -> 0xdddddddd
    CHECK   a7, 0xdddddddd

    // ---- store data arriving through forwarding, read straight back ----
    la      a0, we
    la      a1, src
    nop
    li      t0, 0x0f0f0f0f          // EX/MEM -> store data (addi right before sw)
    sw      t0, 0(a0)
    lw      t1, 0(a0)
    CHECK   t1, 0x0f0f0f0f

    li      t0, 0x3c3c3c3c          // MEM/WB -> store data
    nop
    sw      t0, 4(a0)
    lw      t1, 4(a0)
    CHECK   t1, 0x3c3c3c3c

    lw      t0, 0(a1)               // load-use -> store data
    sw      t0, 8(a0)
    lw      t1, 8(a0)
    CHECK   t1, 0x55aa55aa

    li      t2, 0x01234567          // forwarded store data, then a different-address load
    sw      t2, 12(a0)
    lw      t3, 0(a0)
    CHECK   t3, 0x0f0f0f0f
    lw      t4, 12(a0)
    CHECK   t4, 0x01234567

    TEST_END
