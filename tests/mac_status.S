// mac_status — READ_STATUS bit 0 = sticky overflow. Set by 72-bit accumulator
// saturation, by a saturating READ_LO/HI, or by a saturating READ_SHIFT.
// Stays set through non-saturating reads; only CLEAR clears it.
#include "test.h"

    .data
    .balign 4
w1:     .word 1
wmin:   .word 0x80000000
wmax:   .word 0x7fffffff

    TEST_BEGIN
    la      a1, wmin
    la      a2, w1

    // reset / CLEAR state
    MAC_CLEAR
    MAC_STATUS t1
    CHECK   t1, 0

    // non-saturating MAC + reads leave it clear
    li      a0, 100
    MAC     a0, a2
    MAC_RDLO t2
    MAC_RDHI t2
    li      t0, 4
    MAC_RDSHIFT t2, t0
    MAC_STATUS t1
    CHECK   t1, 0

    // a saturating READ_HI sets it (acc = 2^63: fits 72 bits, not 64)
    MAC_CLEAR
    li      a0, 0x80000000
    MAC     a0, a1
    nop
    MAC     a0, a1
    MAC_STATUS t1
    CHECK   t1, 0                   // accumulator itself did not saturate
    MAC_RDHI t2
    CHECK   t2, 0x7fffffff
    MAC_STATUS t1
    CHECK   t1, 1

    // sticky: a later non-saturating read does not clear it
    li      t0, 40                  // 2^63 >> 40 = 2^23: fits 32 bits
    MAC_RDSHIFT t2, t0
    CHECK   t2, 0x00800000
    MAC_STATUS t1
    CHECK   t1, 1

    // bring acc back into 64-bit range: 2^63 + 2 x (-2^62 + 2^31) = 2^32,
    // then a non-saturating READ_LO/READ_HI must not clear the flag
    la      a3, wmax
    MAC     a0, a3
    nop
    MAC     a0, a3
    MAC_RDLO t2
    CHECK   t2, 0
    MAC_RDHI t2
    CHECK   t2, 1
    MAC_STATUS t1
    CHECK   t1, 1

    // CLEAR clears it
    MAC_CLEAR
    MAC_STATUS t1
    CHECK   t1, 0

    // a saturating READ_SHIFT sets it
    li      a0, 0x80000000
    MAC     a0, a1                  // acc = 2^62
    MAC_STATUS t1
    CHECK   t1, 0
    li      t0, 0
    MAC_RDSHIFT t2, t0
    CHECK   t2, 0x7fffffff
    MAC_STATUS t1
    CHECK   t1, 1
    MAC_CLEAR

    // 72-bit accumulator saturation sets it with no read at all:
    // 520 x 2^62 > 2^71 (saturates at the 512th MAC)
    li      a0, 0x80000000
    li      t3, 520
1:  MAC     a0, a1
    addi    t3, t3, -1
    bnez    t3, 1b
    MAC_STATUS t1
    CHECK   t1, 1
    MAC_RDHI t2
    CHECK   t2, 0x7fffffff
    MAC_RDLO t2
    CHECK   t2, 0xffffffff
    MAC_CLEAR
    MAC_STATUS t1
    CHECK   t1, 0

    TEST_END
