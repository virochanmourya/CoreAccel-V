// jal_jalr — link values, targets, JALR LSB clear, rd == rs1, call/return,
// and a jump sitting in the shadow of a taken branch.
#include "test.h"

    TEST_BEGIN
    // JAL: target and link
    li      t3, 0
j1: jal     t0, 1f
    addi    t3, t3, 0x100
    addi    t3, t3, 0x200
1:  addi    t3, t3, 1
    CHECK   t3, 1
    LA_ABS  t1, j1 + 4
    sub     t2, t0, t1
    CHECK   t2, 0

    // JALR: target and link
    LA_ABS  t1, 2f
    li      t3, 0
j2: jalr    ra, 0(t1)
    addi    t3, t3, 0x100
    addi    t3, t3, 0x200
2:  addi    t3, t3, 1
    CHECK   t3, 1
    LA_ABS  t1, j2 + 4
    sub     t2, ra, t1
    CHECK   t2, 0

    // JALR: odd offset -> LSB cleared; base forwarded from EX/MEM
    li      t3, 0
    LA_ABS  t1, 3f
    addi    t1, t1, -4
    jalr    ra, 5(t1)               // (3f - 4 + 5) & ~1 = 3f
    addi    t3, t3, 0x100
    addi    t3, t3, 0x200
3:  addi    t3, t3, 1
    CHECK   t3, 1

    // JALR with rd == rs1
    LA_ABS  ra, 4f
    li      t3, 0
j4: jalr    ra, 0(ra)
    addi    t3, t3, 0x100
    addi    t3, t3, 0x200
4:  addi    t3, t3, 1
    CHECK   t3, 1
    LA_ABS  t1, j4 + 4
    sub     t2, ra, t1
    CHECK   t2, 0

    // call / return
    li      a0, 0
    jal     ra, func
    addi    a0, a0, 1
    CHECK   a0, 8

    // JAL in the shadow of a taken branch must be squashed
    li      t3, 0
    beq     zero, zero, 5f
    jal     x0, bad
    addi    t3, t3, 0x100
5:  addi    t3, t3, 1
    CHECK   t3, 1

    TEST_END

    .text
func:
    addi    a0, a0, 7
    ret

bad:
    li      t3, 0x7ff
    j       5b
