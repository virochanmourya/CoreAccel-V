// mext_mul — M extension, MUL/MULH/MULHSU/MULHU, signed and unsigned mixes.
// Every op on sign edge cases, plus rd = rs1 / rs2 / both, rd = x0 and x0
// operands. Expected values were computed from a Python model of the RISC-V
// spec semantics.
#include "test.h"

    TEST_BEGIN

    // ---- MUL ----
    li      a0, 0x00000000
    li      a1, 0xffffffff
    mul     a2, a0, a1
    CHECK   a2, 0x00000000      // mul(0x00000000, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0x00000001
    mul     a2, a0, a1
    CHECK   a2, 0x00000001      // mul(0x00000001, 0x00000001)
    li      a0, 0x00000006
    li      a1, 0x00000007
    mul     a2, a0, a1
    CHECK   a2, 0x0000002a      // mul(0x00000006, 0x00000007)
    li      a0, 0xfffffffa
    li      a1, 0x00000007
    mul     a2, a0, a1
    CHECK   a2, 0xffffffd6      // mul(0xfffffffa, 0x00000007)
    li      a0, 0x00000006
    li      a1, 0xfffffff9
    mul     a2, a0, a1
    CHECK   a2, 0xffffffd6      // mul(0x00000006, 0xfffffff9)
    li      a0, 0xfffffffa
    li      a1, 0xfffffff9
    mul     a2, a0, a1
    CHECK   a2, 0x0000002a      // mul(0xfffffffa, 0xfffffff9)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    mul     a2, a0, a1
    CHECK   a2, 0x00000001      // mul(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    mul     a2, a0, a1
    CHECK   a2, 0xffffffff      // mul(0xffffffff, 0x00000001)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    mul     a2, a0, a1
    CHECK   a2, 0xffffffff      // mul(0x00000001, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x80000000
    mul     a2, a0, a1
    CHECK   a2, 0x00000000      // mul(0x80000000, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    mul     a2, a0, a1
    CHECK   a2, 0x80000000      // mul(0x80000000, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    mul     a2, a0, a1
    CHECK   a2, 0x80000000      // mul(0xffffffff, 0x80000000)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    mul     a2, a0, a1
    CHECK   a2, 0x00000001      // mul(0x7fffffff, 0x7fffffff)
    li      a0, 0x7fffffff
    li      a1, 0x80000000
    mul     a2, a0, a1
    CHECK   a2, 0x80000000      // mul(0x7fffffff, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0x7fffffff
    mul     a2, a0, a1
    CHECK   a2, 0x80000000      // mul(0x80000000, 0x7fffffff)
    li      a0, 0x80000001
    li      a1, 0xfffffffe
    mul     a2, a0, a1
    CHECK   a2, 0xfffffffe      // mul(0x80000001, 0xfffffffe)
    li      a0, 0x12345678
    li      a1, 0xfedcba98
    mul     a2, a0, a1
    CHECK   a2, 0x35068740      // mul(0x12345678, 0xfedcba98)
    li      a0, 0x0000ffff
    li      a1, 0xffff0000
    mul     a2, a0, a1
    CHECK   a2, 0x00010000      // mul(0x0000ffff, 0xffff0000)

    // ---- MULH ----
    li      a0, 0x00000000
    li      a1, 0xffffffff
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0x00000000, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0x00000001
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0x00000001, 0x00000001)
    li      a0, 0x00000006
    li      a1, 0x00000007
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0x00000006, 0x00000007)
    li      a0, 0xfffffffa
    li      a1, 0x00000007
    mulh    a2, a0, a1
    CHECK   a2, 0xffffffff      // mulh(0xfffffffa, 0x00000007)
    li      a0, 0x00000006
    li      a1, 0xfffffff9
    mulh    a2, a0, a1
    CHECK   a2, 0xffffffff      // mulh(0x00000006, 0xfffffff9)
    li      a0, 0xfffffffa
    li      a1, 0xfffffff9
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0xfffffffa, 0xfffffff9)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    mulh    a2, a0, a1
    CHECK   a2, 0xffffffff      // mulh(0xffffffff, 0x00000001)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    mulh    a2, a0, a1
    CHECK   a2, 0xffffffff      // mulh(0x00000001, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x80000000
    mulh    a2, a0, a1
    CHECK   a2, 0x40000000      // mulh(0x80000000, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0x80000000, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0xffffffff, 0x80000000)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    mulh    a2, a0, a1
    CHECK   a2, 0x3fffffff      // mulh(0x7fffffff, 0x7fffffff)
    li      a0, 0x7fffffff
    li      a1, 0x80000000
    mulh    a2, a0, a1
    CHECK   a2, 0xc0000000      // mulh(0x7fffffff, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0x7fffffff
    mulh    a2, a0, a1
    CHECK   a2, 0xc0000000      // mulh(0x80000000, 0x7fffffff)
    li      a0, 0x80000001
    li      a1, 0xfffffffe
    mulh    a2, a0, a1
    CHECK   a2, 0x00000000      // mulh(0x80000001, 0xfffffffe)
    li      a0, 0x12345678
    li      a1, 0xfedcba98
    mulh    a2, a0, a1
    CHECK   a2, 0xffeb4992      // mulh(0x12345678, 0xfedcba98)
    li      a0, 0x0000ffff
    li      a1, 0xffff0000
    mulh    a2, a0, a1
    CHECK   a2, 0xffffffff      // mulh(0x0000ffff, 0xffff0000)

    // ---- MULHSU ----
    li      a0, 0x00000000
    li      a1, 0xffffffff
    mulhsu  a2, a0, a1
    CHECK   a2, 0x00000000      // mulhsu(0x00000000, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0x00000001
    mulhsu  a2, a0, a1
    CHECK   a2, 0x00000000      // mulhsu(0x00000001, 0x00000001)
    li      a0, 0x00000006
    li      a1, 0x00000007
    mulhsu  a2, a0, a1
    CHECK   a2, 0x00000000      // mulhsu(0x00000006, 0x00000007)
    li      a0, 0xfffffffa
    li      a1, 0x00000007
    mulhsu  a2, a0, a1
    CHECK   a2, 0xffffffff      // mulhsu(0xfffffffa, 0x00000007)
    li      a0, 0x00000006
    li      a1, 0xfffffff9
    mulhsu  a2, a0, a1
    CHECK   a2, 0x00000005      // mulhsu(0x00000006, 0xfffffff9)
    li      a0, 0xfffffffa
    li      a1, 0xfffffff9
    mulhsu  a2, a0, a1
    CHECK   a2, 0xfffffffa      // mulhsu(0xfffffffa, 0xfffffff9)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    mulhsu  a2, a0, a1
    CHECK   a2, 0xffffffff      // mulhsu(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    mulhsu  a2, a0, a1
    CHECK   a2, 0xffffffff      // mulhsu(0xffffffff, 0x00000001)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    mulhsu  a2, a0, a1
    CHECK   a2, 0x00000000      // mulhsu(0x00000001, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x80000000
    mulhsu  a2, a0, a1
    CHECK   a2, 0xc0000000      // mulhsu(0x80000000, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    mulhsu  a2, a0, a1
    CHECK   a2, 0x80000000      // mulhsu(0x80000000, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    mulhsu  a2, a0, a1
    CHECK   a2, 0xffffffff      // mulhsu(0xffffffff, 0x80000000)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    mulhsu  a2, a0, a1
    CHECK   a2, 0x3fffffff      // mulhsu(0x7fffffff, 0x7fffffff)
    li      a0, 0x7fffffff
    li      a1, 0x80000000
    mulhsu  a2, a0, a1
    CHECK   a2, 0x3fffffff      // mulhsu(0x7fffffff, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0x7fffffff
    mulhsu  a2, a0, a1
    CHECK   a2, 0xc0000000      // mulhsu(0x80000000, 0x7fffffff)
    li      a0, 0x80000001
    li      a1, 0xfffffffe
    mulhsu  a2, a0, a1
    CHECK   a2, 0x80000001      // mulhsu(0x80000001, 0xfffffffe)
    li      a0, 0x12345678
    li      a1, 0xfedcba98
    mulhsu  a2, a0, a1
    CHECK   a2, 0x121fa00a      // mulhsu(0x12345678, 0xfedcba98)
    li      a0, 0x0000ffff
    li      a1, 0xffff0000
    mulhsu  a2, a0, a1
    CHECK   a2, 0x0000fffe      // mulhsu(0x0000ffff, 0xffff0000)

    // ---- MULHU ----
    li      a0, 0x00000000
    li      a1, 0xffffffff
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000000      // mulhu(0x00000000, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0x00000001
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000000      // mulhu(0x00000001, 0x00000001)
    li      a0, 0x00000006
    li      a1, 0x00000007
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000000      // mulhu(0x00000006, 0x00000007)
    li      a0, 0xfffffffa
    li      a1, 0x00000007
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000006      // mulhu(0xfffffffa, 0x00000007)
    li      a0, 0x00000006
    li      a1, 0xfffffff9
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000005      // mulhu(0x00000006, 0xfffffff9)
    li      a0, 0xfffffffa
    li      a1, 0xfffffff9
    mulhu   a2, a0, a1
    CHECK   a2, 0xfffffff3      // mulhu(0xfffffffa, 0xfffffff9)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    mulhu   a2, a0, a1
    CHECK   a2, 0xfffffffe      // mulhu(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000000      // mulhu(0xffffffff, 0x00000001)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    mulhu   a2, a0, a1
    CHECK   a2, 0x00000000      // mulhu(0x00000001, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x80000000
    mulhu   a2, a0, a1
    CHECK   a2, 0x40000000      // mulhu(0x80000000, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    mulhu   a2, a0, a1
    CHECK   a2, 0x7fffffff      // mulhu(0x80000000, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    mulhu   a2, a0, a1
    CHECK   a2, 0x7fffffff      // mulhu(0xffffffff, 0x80000000)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    mulhu   a2, a0, a1
    CHECK   a2, 0x3fffffff      // mulhu(0x7fffffff, 0x7fffffff)
    li      a0, 0x7fffffff
    li      a1, 0x80000000
    mulhu   a2, a0, a1
    CHECK   a2, 0x3fffffff      // mulhu(0x7fffffff, 0x80000000)
    li      a0, 0x80000000
    li      a1, 0x7fffffff
    mulhu   a2, a0, a1
    CHECK   a2, 0x3fffffff      // mulhu(0x80000000, 0x7fffffff)
    li      a0, 0x80000001
    li      a1, 0xfffffffe
    mulhu   a2, a0, a1
    CHECK   a2, 0x7fffffff      // mulhu(0x80000001, 0xfffffffe)
    li      a0, 0x12345678
    li      a1, 0xfedcba98
    mulhu   a2, a0, a1
    CHECK   a2, 0x121fa00a      // mulhu(0x12345678, 0xfedcba98)
    li      a0, 0x0000ffff
    li      a1, 0xffff0000
    mulhu   a2, a0, a1
    CHECK   a2, 0x0000fffe      // mulhu(0x0000ffff, 0xffff0000)

    // ---- register aliasing: rd = rs1, rd = rs2, rd = rs1 = rs2, x0 ----
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    mul     a0, a0, a1                  // rd = rs1
    CHECK   a0, 0xc5c41e4d
    li      a0, 0xfff0bdbd
    mul     a1, a0, a1                  // rd = rs2
    CHECK   a1, 0xc5c41e4d
    li      a0, 0xfff0bdbd
    mul     a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0xd5009d89
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    mul     x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    mul     a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    mul     a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0x00000000
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    mulh    a0, a0, a1                  // rd = rs1
    CHECK   a0, 0xffffffff
    li      a0, 0xfff0bdbd
    mulh    a1, a0, a1                  // rd = rs2
    CHECK   a1, 0xffffffff
    li      a0, 0xfff0bdbd
    mulh    a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0x000000e8
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    mulh    x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    mulh    a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    mulh    a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0x00000000
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    mulhsu  a0, a0, a1                  // rd = rs1
    CHECK   a0, 0xffffffff
    li      a0, 0xfff0bdbd
    mulhsu  a1, a0, a1                  // rd = rs2
    CHECK   a1, 0xffffffff
    li      a0, 0xfff0bdbd
    mulhsu  a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0xfff0bea5
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    mulhsu  x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    mulhsu  a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    mulhsu  a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0x00000000
    li      a0, 0xf0000011
    li      a1, 0x00012345
    mulhu   a0, a0, a1                  // rd = rs1
    CHECK   a0, 0x00011110
    li      a0, 0xf0000011
    mulhu   a1, a0, a1                  // rd = rs2
    CHECK   a1, 0x00011110
    li      a0, 0xf0000011
    mulhu   a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0xe100001f
    li      a0, 0xf0000011
    li      a1, 0x00012345
    mulhu   x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    mulhu   a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    mulhu   a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0x00000000
    CHECK   x0, 0                       // x0 never written

    TEST_END
