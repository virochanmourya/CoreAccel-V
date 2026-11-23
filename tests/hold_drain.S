// hold_drain — H1: a consumer held in EX while its producer drains out of
// MEM/WB must still use the producer's value. Every TCM store in this test is
// held in EX for 3 cycles (harness hook), so by the time a store leaves EX its
// producer has retired and forwarding no longer covers it.
#include "test.h"

    HOLD_EX_STORES 3

    .data
    .balign 4
buf:    .fill 6, 4, 0xeeeeeeee
src:    .word 0x13572468

    TEST_BEGIN
    la      a0, buf
    la      a1, src
    nop
    nop

    li      t0, 0x11                // store data from EX/MEM at hold start
    sw      t0, 0(a0)

    li      t1, 0x22                // store data from MEM/WB at hold start
    nop
    sw      t1, 4(a0)

    li      t2, 0x33                // producer two ahead (WB at ID, then gone)
    nop
    nop
    sw      t2, 8(a0)

    addi    a2, a0, 12              // store BASE from EX/MEM
    sw      t0, 0(a2)

    lw      t3, 0(a1)               // load producer: load-use stall, then hold
    sw      t3, 16(a0)

    li      t4, 0x66                // data from MEM/WB and base from EX/MEM
    addi    a3, a0, 20
    sw      t4, 0(a3)

    nop
    nop
    lw      t5, 0(a0)
    CHECK   t5, 0x11
    lw      t5, 4(a0)
    CHECK   t5, 0x22
    lw      t5, 8(a0)
    CHECK   t5, 0x33
    lw      t5, 12(a0)
    CHECK   t5, 0x11
    lw      t5, 16(a0)
    CHECK   t5, 0x13572468
    lw      t5, 20(a0)
    CHECK   t5, 0x66

    TEST_END
