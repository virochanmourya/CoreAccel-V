// fwd_ex_ex — EX/MEM -> EX forwarding (producer immediately before consumer)
#include "test.h"

    TEST_BEGIN
    li      a0, 5
    add     t0, a0, a0              // rs1 and rs2 both forwarded
    CHECK   t0, 10

    li      a1, 7
    add     t1, a1, zero            // rs1 only
    CHECK   t1, 7

    li      a2, 9
    add     t2, zero, a2            // rs2 only
    CHECK   t2, 9

    li      a3, 1
    sub     t3, zero, a3            // rs2 into SUB
    CHECK   t3, 0xffffffff

    li      t0, 1                   // dependency chain
    addi    t0, t0, 1
    addi    t0, t0, 1
    addi    t0, t0, 1
    CHECK   t0, 4

    lui     t1, 0x12345             // LUI result forwarded into ADDI
    addi    t1, t1, 0x678
    CHECK   t1, 0x12345678

    li      a4, 4
    sll     t2, a3, a4              // shift amount forwarded (a3 = 1)
    CHECK   t2, 16

    TEST_END
