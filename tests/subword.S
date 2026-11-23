// subword — B2: LB/LH/LBU/LHU sign/zero extension at every offset, and
// SB/SH must leave the other bytes of the word untouched.
// Every store target is its own word; stores and loads are kept apart (B1).
#include "test.h"

    .data
    .balign 4
src:    .word 0xf07f8001            // b0=01 b1=80 b2=7f b3=f0
dst:    .rept 9
        .word 0x11223344
        .endr
dst2:   .word 0x11223344, 0x11223344

    TEST_BEGIN
    la      a0, src

    lb      t0, 0(a0)
    CHECK   t0, 0x00000001
    lb      t0, 1(a0)
    CHECK   t0, 0xffffff80
    lb      t0, 2(a0)
    CHECK   t0, 0x0000007f
    lb      t0, 3(a0)
    CHECK   t0, 0xfffffff0
    lbu     t0, 0(a0)
    CHECK   t0, 0x00000001
    lbu     t0, 1(a0)
    CHECK   t0, 0x00000080
    lbu     t0, 2(a0)
    CHECK   t0, 0x0000007f
    lbu     t0, 3(a0)
    CHECK   t0, 0x000000f0
    lh      t0, 0(a0)
    CHECK   t0, 0xffff8001
    lh      t0, 2(a0)
    CHECK   t0, 0xfffff07f
    lhu     t0, 0(a0)
    CHECK   t0, 0x00008001
    lhu     t0, 2(a0)
    CHECK   t0, 0x0000f07f
    lw      t0, 0(a0)
    CHECK   t0, 0xf07f8001

    // ---- stores: one per destination word ----
    la      a1, dst
    li      t1, 0xab
    sb      t1, 0(a1)
    li      t1, 0xcd
    sb      t1, 5(a1)
    li      t1, 0xef
    sb      t1, 10(a1)
    li      t1, 0x5a
    sb      t1, 15(a1)
    li      t1, 0x12345699          // upper bits must be ignored
    sb      t1, 16(a1)
    li      t1, 0xbeef
    sh      t1, 20(a1)
    li      t1, 0xbeef
    sh      t1, 26(a1)
    li      t1, 0xcafe1234          // upper half must be ignored
    sh      t1, 30(a1)
    li      t1, 0x0000ffff
    sw      t1, 32(a1)              // full-word store control case
    nop
    nop

    lw      t0, 0(a1)
    CHECK   t0, 0x112233ab
    lw      t0, 4(a1)
    CHECK   t0, 0x1122cd44
    lw      t0, 8(a1)
    CHECK   t0, 0x11ef3344
    lw      t0, 12(a1)
    CHECK   t0, 0x5a223344
    lw      t0, 16(a1)
    CHECK   t0, 0x11223399
    lw      t0, 20(a1)
    CHECK   t0, 0x1122beef
    lw      t0, 24(a1)
    CHECK   t0, 0xbeef3344
    lw      t0, 28(a1)
    CHECK   t0, 0x12343344
    lw      t0, 32(a1)
    CHECK   t0, 0x0000ffff

    // byte loads from a byte-written word
    lbu     t0, 5(a1)
    CHECK   t0, 0x000000cd
    lb      t0, 10(a1)
    CHECK   t0, 0xffffffef

    // ---- lane from a forwarded base, with a carry out of the low bits ----
    la      a4, dst2
    li      t1, 0x77
    addi    a3, a4, 3               // base produced right before the store
    sb      t1, -2(a3)              // (3 + -2)[1:0] = 1 -> dst2 byte 1
    li      t1, 0x8899
    addi    a3, a4, 6
    sh      t1, 0(a3)               // dst2 + 6 -> word 1, upper half
    nop
    nop
    lw      t0, 0(a4)
    CHECK   t0, 0x11227744
    lw      t0, 4(a4)
    CHECK   t0, 0x88993344
    addi    a3, a4, 1
    lb      t0, 0(a3)               // forwarded base on a byte load
    CHECK   t0, 0x00000077

    // ---- peripherals are word registers: sub-word stores write the
    //      lane-replicated value, sub-word loads select a lane ----
    li      a2, 0xC0000008          // 7-segment data register (16 bits)
    li      t1, 0x1234abcd
    sh      t1, 0(a2)
    lw      t0, 0(a2)
    CHECK   t0, 0x0000abcd
    li      t1, 0x5a
    sb      t1, 1(a2)               // replicated byte -> 0x5a5a
    lw      t0, 0(a2)
    CHECK   t0, 0x00005a5a
    lbu     t0, 1(a2)
    CHECK   t0, 0x0000005a

    TEST_END
