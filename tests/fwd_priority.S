// fwd_priority — when EX/MEM and MEM/WB both hold rs, the younger (EX/MEM) wins
#include "test.h"

    TEST_BEGIN
    li      t0, 1
    li      t0, 2
    add     t1, t0, zero            // rs1: must see 2
    CHECK   t1, 2

    li      t0, 3
    li      t0, 4
    add     t1, zero, t0            // rs2: must see 4
    CHECK   t1, 4

    li      t0, 5
    li      t0, 6
    nop
    add     t1, t0, t0              // only MEM/WB holds t0 (=6)
    CHECK   t1, 12

    li      t0, 9
    addi    t0, t0, 1
    addi    t0, t0, 1
    add     t1, t0, zero
    CHECK   t1, 11

    li      t0, 0x10                // same reg as both sources, three writers in flight
    li      t0, 0x20
    li      t0, 0x30
    add     t1, t0, t0
    CHECK   t1, 0x60

    TEST_END
