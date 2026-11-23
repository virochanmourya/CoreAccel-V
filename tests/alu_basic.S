// alu_basic — every RV32I register/immediate ALU op, LUI, AUIPC
#include "test.h"

    TEST_BEGIN
    li      a0, 0x12345678
    li      a1, 0x0000ffff
    li      a2, -5
    li      a3, 3
    li      a4, 33
    nop
    nop
    nop

    // ---- R-type ----
    add     t0, a0, a1
    CHECK   t0, 0x12355677
    sub     t0, a0, a1
    CHECK   t0, 0x12335679
    sub     t0, a3, a1
    CHECK   t0, 0xffff0004
    and     t0, a0, a1
    CHECK   t0, 0x00005678
    or      t0, a0, a1
    CHECK   t0, 0x1234ffff
    xor     t0, a0, a1
    CHECK   t0, 0x1234a987
    sll     t0, a0, a3
    CHECK   t0, 0x91a2b3c0
    sll     t0, a3, a4              // shamt = 33 & 31 = 1
    CHECK   t0, 0x00000006
    srl     t0, a2, a3
    CHECK   t0, 0x1fffffff
    sra     t0, a2, a3
    CHECK   t0, 0xffffffff
    sra     t0, a0, a3
    CHECK   t0, 0x02468acf
    slt     t0, a2, a3
    CHECK   t0, 1
    slt     t0, a3, a2
    CHECK   t0, 0
    sltu    t0, a2, a3
    CHECK   t0, 0
    sltu    t0, a3, a2
    CHECK   t0, 1

    // ---- I-type ----
    addi    t0, a0, -1
    CHECK   t0, 0x12345677
    andi    t0, a1, 0x0f0
    CHECK   t0, 0x000000f0
    ori     t0, zero, 0x7ff
    CHECK   t0, 0x000007ff
    xori    t0, a2, -1
    CHECK   t0, 0x00000004
    slli    t0, a3, 31
    CHECK   t0, 0x80000000
    srli    t0, a2, 31
    CHECK   t0, 0x00000001
    srai    t0, a2, 31
    CHECK   t0, 0xffffffff
    srai    t0, a0, 0
    CHECK   t0, 0x12345678
    slti    t0, a2, -4
    CHECK   t0, 1
    slti    t0, a3, 3
    CHECK   t0, 0
    sltiu   t0, a3, -1              // 3 < 0xffffffff
    CHECK   t0, 1
    sltiu   t0, a2, 5
    CHECK   t0, 0

    // ---- U-type ----
    lui     t0, 0xabcde
    CHECK   t0, 0xabcde000
pc_here:
    auipc   t0, 0x1
    LA_ABS  t1, pc_here + 0x1000
    sub     t0, t0, t1
    CHECK   t0, 0

    TEST_END
