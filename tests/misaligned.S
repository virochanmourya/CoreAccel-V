// misaligned — F6: LW/SW not 4-byte aligned and LH/LHU/SH not 2-byte aligned
// raise the misaligned error (one per access, counted by the harness) and have
// no architectural effect: loads leave rd unchanged, stores write nothing
// (TCM or peripheral). Byte accesses and aligned halves are legal.
#include "test.h"

    EXPECT_MISALIGNED 12

    .data
    .balign 4
w:      .word 0x11223344
s:      .word 0xaaaaaaaa, 0xbbbbbbbb

    TEST_BEGIN
    la      a0, w
    la      a1, s
    li      t1, 0x777

    lw      t1, 1(a0)               // [1]
    lw      t1, 2(a0)               // [2]
    lw      t1, 3(a0)               // [3]
    lh      t1, 1(a0)               // [4]
    lh      t1, 3(a0)               // [5]
    lhu     t1, 1(a0)               // [6]
    CHECK   t1, 0x777               // rd never written

    lh      t2, 2(a0)               // legal
    CHECK   t2, 0x00001122
    lb      t2, 3(a0)               // legal
    CHECK   t2, 0x00000011

    li      t3, 0xdeadbeef
    sw      t3, 2(a1)               // [7]  no write
    sh      t3, 1(a1)               // [8]  no write
    sh      t3, 7(a1)               // [9]  no write
    nop
    nop
    lw      t4, 0(a1)
    CHECK   t4, 0xaaaaaaaa
    lw      t4, 4(a1)
    CHECK   t4, 0xbbbbbbbb

    li      a2, 0xC0000008          // 7-segment register
    li      t3, 0x4321
    sw      t3, 0(a2)               // legal
    li      t3, 0x9999
    sw      t3, 1(a2)               // [10] misaligned store must not reach the peripheral
    lw      t4, 0(a2)
    CHECK   t4, 0x00004321

    li      a3, 0x40000002          // misaligned AND unmapped: misaligned wins,
    li      t5, 0x55                // the access is squashed, so no dbus_error
    lw      t5, 0(a3)               // [11]
    CHECK   t5, 0x55

    li      a4, 5                   // squashed load followed by a consumer:
    lw      a4, 1(a0)               // [12] (load-use stall, nothing forwarded)
    addi    a5, a4, 1
    CHECK   a5, 6

    TEST_END
