// mac_readshift — READ_SHIFT: rd = sat32(round_half_up(acc >>> rs1[5:0])).
// Shift 0 / 15 (Q15) / 16 / 31 (Q31) / 63, positive and negative, rounding
// edges at exactly +-0.5 LSB, and 32-bit saturation both ways.
// acc is set with a single MAC: acc = a0 * TCM[weight].
#include "test.h"

    .data
    .balign 4
w1:     .word 1
w15:    .word 0x00008000            // 2^15
w30:    .word 0x40000000            // 2^30
wmin:   .word 0x80000000
wmax:   .word 0x7fffffff

// SETACC val, weight: acc = val * weight
.macro SETACC val, weight
    MAC_CLEAR
    li      a0, \val
    la      a1, \weight
    MAC     a0, a1
.endm

    TEST_BEGIN
    // ---- shift 0 ----
    SETACC  12345, w1
    li      t0, 0
    MAC_RDSHIFT t1, t0
    CHECK   t1, 12345
    SETACC  -7, w1
    li      t0, 0
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0xfffffff9

    // ---- shift 15 (Q15); shift amount forwarded from the previous instr ----
    SETACC  0x12345, w15            // acc = 0x12345 << 15
    li      t0, 15
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0x00012345
    SETACC  -0x12345, w15
    li      t0, 15
    MAC_RDSHIFT t1, t0
    addi    t2, t1, 0               // READ_SHIFT result forwarded
    CHECK   t2, 0xfffedcbb
    SETACC  0x12345, w15            // only rs1[5:0] is used: 79 & 63 = 15
    li      t0, 79
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0x00012345

    // ---- rounding, shift 16 (round half up) ----
    li      t0, 16
    SETACC  0x18000, w1             //  1.5     ->  2
    MAC_RDSHIFT t1, t0
    CHECK   t1, 2
    SETACC  0x17fff, w1             //  1.49998 ->  1
    MAC_RDSHIFT t1, t0
    CHECK   t1, 1
    SETACC  -0x18000, w1            // -1.5     -> -1
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0xffffffff
    SETACC  -0x8000, w1             // -0.5     ->  0
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0
    SETACC  -0x8001, w1             // -0.50002 -> -1
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0xffffffff

    // ---- shift 31 (Q31) ----
    li      t0, 31
    SETACC  3, w30                  //  3*2^30 / 2^31 =  1.5 ->  2
    MAC_RDSHIFT t1, t0
    CHECK   t1, 2
    SETACC  -3, w30                 // -1.5 -> -1
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0xffffffff

    // ---- shift 63 ----
    li      t0, 63
    SETACC  0x80000000, wmin        // 2^62 / 2^63 = 0.5 -> 1
    MAC_RDSHIFT t1, t0
    CHECK   t1, 1

    // ---- 32-bit saturation ----
    li      t0, 15
    SETACC  0x80000000, wmin        //  2^62 >> 15 = 2^47 -> INT32_MAX
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0x7fffffff
    SETACC  0x80000000, wmax        // (-2^62 + 2^31) >> 15 -> INT32_MIN
    MAC_RDSHIFT t1, t0
    CHECK   t1, 0x80000000

    TEST_END
