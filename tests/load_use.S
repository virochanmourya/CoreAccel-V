// load_use — load-use stall + forwarding into ALU, branch, store data/address
// No TCM store is ever directly followed by a TCM load here (that is B1).
#include "test.h"

    .data
d0:     .word 0x11111111
d1:     .word 0x22222222
pd1:    .word d1                    // pointer to d1
pscr:   .word scratch               // pointer to scratch
scratch:.word 0x0badf00d

    TEST_BEGIN
    la      a0, d0
    li      t2, 0x11111111

    // ALU consumer, rs1 and rs2
    lw      t0, 0(a0)
    add     t1, t0, t0
    CHECK   t1, 0x22222222
    lw      t0, 4(a0)
    sub     t1, zero, t0
    CHECK   t1, 0xddddddde

    // MEM/WB forwarding of load data (one gap, no stall needed)
    lw      t0, 0(a0)
    nop
    add     t1, t0, zero
    CHECK   t1, 0x11111111

    // back-to-back loads, then a consumer of both
    lw      t0, 0(a0)
    lw      t1, 4(a0)
    add     t3, t0, t1
    CHECK   t3, 0x33333333

    // branch consumer: taken
    li      t3, 0
    lw      t0, 0(a0)
    beq     t0, t2, 1f
    addi    t3, t3, 0x100
1:  addi    t3, t3, 1
    CHECK   t3, 1

    // branch consumer: not taken
    li      t3, 0
    lw      t0, 4(a0)
    beq     t0, t2, 1f
    addi    t3, t3, 0x100
1:  addi    t3, t3, 1
    CHECK   t3, 0x101

    // store-data consumer (CHECK's sw uses t0 as rs2)
    lw      t0, 0(a0)
    CHECK   t0, 0x11111111

    // load-use into a load address
    la      a1, pd1
    lw      t0, 0(a1)
    lw      t1, 0(t0)
    CHECK   t1, 0x22222222

    // load-use into a store address, then read back (gap avoids B1)
    la      a1, pscr
    li      a2, 0x5a5a5a5a
    lw      t0, 0(a1)
    sw      a2, 0(t0)
    nop
    nop
    lw      t1, 0(t0)
    CHECK   t1, 0x5a5a5a5a

    // load into the base register itself
    la      a3, pd1
    lw      a3, 0(a3)
    lw      a3, 0(a3)
    CHECK   a3, 0x22222222

    TEST_END
