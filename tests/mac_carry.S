// mac_carry — accumulate carries across the middle of the 72-bit accumulator.
// The accumulate is split into a low 36-bit half and a high half with a
// registered carry, so every case here carries out of bit 35.
#include "test.h"

    .data
    .balign 4
w1:     .word 0x00000001
wm1:    .word 0xffffffff
wmax:   .word 0x7fffffff
wlow28: .word 0x0fffffff
wff:    .word 0x000000ff

    TEST_BEGIN
    la      a1, w1
    la      a2, wm1
    la      a3, wmax
    la      a4, wlow28
    la      a5, wff

    // -1 + 1 = 0: the carry ripples through all 72 bits
    MAC_CLEAR
    li      a0, 1
    MAC     a0, a2                  // acc = -1
    MAC_RDHI t0
    CHECK   t0, 0xffffffff
    MAC_RDLO t1
    CHECK   t1, 0xffffffff
    MAC     a0, a1                  // acc = 0
    MAC_RDHI t0
    CHECK   t0, 0
    MAC_RDLO t1
    CHECK   t1, 0

    // 2 x (2^31-1)^2 = 0x7ffffffe_00000002 (back-to-back MACs)
    MAC_CLEAR
    li      a0, 0x7fffffff
    MAC     a0, a3
    MAC     a0, a3
    MAC_RDHI t0
    CHECK   t0, 0x7ffffffe
    MAC_RDLO t1
    CHECK   t1, 0x00000002

    // 2^36 - 1, then + 1 = 2^36: exactly the half boundary
    MAC_CLEAR
    li      a0, 0x100
    MAC     a0, a4                  // 0xf_ffff_ff00
    li      a0, 1
    MAC     a0, a5                  // 0xf_ffff_ffff
    MAC_RDHI t0
    CHECK   t0, 0x0000000f
    MAC_RDLO t1
    CHECK   t1, 0xffffffff
    MAC     a0, a1                  // 0x10_0000_0000
    MAC_RDHI t0
    CHECK   t0, 0x00000010
    MAC_RDLO t1
    CHECK   t1, 0
    li      a0, 36
    MAC_RDSHIFT t2, a0              // 2^36 >>> 36 = 1
    CHECK   t2, 1
    MAC_STATUS t3
    CHECK   t3, 0

    TEST_END
