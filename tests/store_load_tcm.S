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

    TEST_END
