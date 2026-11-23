// branch_all — 6 branch types x taken / not-taken with signed/unsigned edges.
// The two instructions after a taken branch must be squashed.
#include "test.h"

// Taken: t3 = 0, shadows add 0x100/0x200/0x400 if they leak; result must be 1.
.macro BR_T op, ra, rb
    li      t3, 0
    \op     \ra, \rb, 1f
    addi    t3, t3, 0x100
    addi    t3, t3, 0x200
    addi    t3, t3, 0x400
1:  addi    t3, t3, 1
    CHECK   t3, 1
.endm

// Not taken: fall-through adds 2, result must be 3.
.macro BR_N op, ra, rb
    li      t3, 0
    \op     \ra, \rb, 1f
    addi    t3, t3, 2
1:  addi    t3, t3, 1
    CHECK   t3, 3
.endm

    .data
d0:     .word 0x11111111

    TEST_BEGIN
    li      a0, 1
    li      a1, -1                  // 0xffffffff
    li      a2, 0x80000000
    li      a3, 0x7fffffff
    li      a4, 1
    nop
    nop

    BR_T    beq,  a0, a4
    BR_N    beq,  a0, a1
    BR_T    bne,  a0, a1
    BR_N    bne,  a0, a4

    BR_T    blt,  a1, a0            // -1 < 1
    BR_N    blt,  a0, a1
    BR_T    blt,  a2, a3            // INT_MIN < INT_MAX
    BR_N    blt,  a3, a2
    BR_N    blt,  a0, a4            // equal

    BR_T    bge,  a0, a1
    BR_N    bge,  a1, a0
    BR_T    bge,  a0, a4            // equal
    BR_T    bge,  a3, a2

    BR_T    bltu, a0, a1            // 1 < 0xffffffff
    BR_N    bltu, a1, a0
    BR_T    bltu, a3, a2            // 0x7fffffff < 0x80000000
    BR_N    bltu, a0, a4            // equal

    BR_T    bgeu, a1, a0
    BR_N    bgeu, a0, a1
    BR_T    bgeu, a0, a4            // equal
    BR_T    bgeu, a2, a3

    // operands forwarded from EX/MEM and MEM/WB into the comparator
    li      t3, 0
    li      a5, 42
    li      a6, 42
    beq     a5, a6, 1f
    addi    t3, t3, 0x100
    addi    t3, t3, 0x200
1:  addi    t3, t3, 1
    CHECK   t3, 1

    // backward loop: 5 iterations
    li      t0, 5
    li      t1, 0
2:  addi    t1, t1, 3
    addi    t0, t0, -1
    bnez    t0, 2b
    CHECK   t1, 15

    // a load in the shadow of a taken branch must not write back
    la      a7, d0
    li      t4, 0x77
    beq     zero, zero, 3f
    lw      t4, 0(a7)
    add     t4, t4, t4
3:  CHECK   t4, 0x77

    TEST_END
