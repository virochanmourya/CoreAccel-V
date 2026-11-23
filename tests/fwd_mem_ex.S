// fwd_mem_ex — MEM/WB -> EX forwarding (one instruction between producer and consumer)
#include "test.h"

    TEST_BEGIN
    li      a0, 11
    nop
    add     t0, a0, a0
    CHECK   t0, 22

    li      a1, 3
    nop
    sub     t1, zero, a1
    CHECK   t1, 0xfffffffd

    li      a2, 0x40
    nop
    addi    t2, a2, 1
    CHECK   t2, 0x41

    lui     a3, 0x80000
    nop
    srai    t3, a3, 4
    CHECK   t3, 0xf8000000

    li      a4, 6                   // rs1 from MEM/WB, rs2 from EX/MEM
    li      a5, 2
    sub     t4, a4, a5
    CHECK   t4, 4

    TEST_END
