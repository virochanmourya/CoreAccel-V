// store_load_ctrl — control cases for B1 that must pass today:
// same-address store->load, and store/load separated by one instruction.
#include "test.h"

    .data
    .balign 4
wa:     .word 0xaaaaaaaa
wb:     .word 0xbbbbbbbb

    TEST_BEGIN
    la      a0, wa
    li      t0, 0x13579bdf
    nop

    sw      t0, 0(a0)               // same address, back-to-back
    lw      t1, 0(a0)
    CHECK   t1, 0x13579bdf

    li      t3, 0x2468ace0
    sw      t3, 4(a0)               // different address, one-instruction gap
    nop
    lw      t2, 0(a0)
    CHECK   t2, 0x13579bdf
    lw      t4, 4(a0)
    CHECK   t4, 0x2468ace0

    TEST_END
