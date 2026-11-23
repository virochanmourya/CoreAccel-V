// mac_single — CLEAR, single (non-consecutive) MACs, READ_LO/READ_HI, signed
// operand corners. MACs are never back-to-back here (that is F1).
#include "test.h"

    .data
    .balign 4
wts:    .word 3, -2, 0x7fffffff, 0x80000000

    TEST_BEGIN
    la      a1, wts

    MAC_CLEAR
    li      a0, 5
    nop
    MAC     a0, a1                  // 5 * 3 = 15
    MAC_RDLO t0
    CHECK   t0, 15
    MAC_RDHI t1
    CHECK   t1, 0

    li      a0, -4
    addi    a2, a1, 4               // w = -2
    nop
    MAC     a0, a2                  // 15 + 8 = 23
    MAC_RDLO t0
    CHECK   t0, 23

    MAC_CLEAR                       // INT_MAX * INT_MAX
    li      a0, 0x7fffffff
    addi    a2, a1, 8
    nop
    MAC     a0, a2
    MAC_RDLO t0
    CHECK   t0, 0x00000001
    MAC_RDHI t1
    CHECK   t1, 0x3fffffff

    MAC_CLEAR                       // -1 * INT_MAX
    li      a0, -1
    nop
    MAC     a0, a2
    MAC_RDLO t0
    CHECK   t0, 0x80000001
    MAC_RDHI t1
    CHECK   t1, 0xffffffff

    MAC_CLEAR                       // INT_MIN * INT_MIN = 2^62
    li      a0, 0x80000000
    addi    a2, a1, 12
    nop
    MAC     a0, a2
    MAC_RDLO t0
    CHECK   t0, 0
    MAC_RDHI t1
    CHECK   t1, 0x40000000

    MAC_CLEAR                       // clear really clears
    MAC_RDLO t0
    CHECK   t0, 0
    MAC_RDHI t1
    CHECK   t1, 0

    TEST_END
