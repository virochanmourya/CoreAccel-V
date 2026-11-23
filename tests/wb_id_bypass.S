// wb_id_bypass — producer in WB while consumer reads registers in ID
#include "test.h"

    TEST_BEGIN
    li      a0, 0x77
    nop
    nop
    add     t0, a0, zero            // a0 in WB when add is in ID
    CHECK   t0, 0x77

    li      a1, 0x123
    nop
    nop
    nop
    add     t1, a1, a1              // from register file
    CHECK   t1, 0x246

    li      a2, 5
    nop
    nop
    sub     t2, zero, a2            // rs2 via bypass
    CHECK   t2, 0xfffffffb

    li      a3, 0x10
    li      a4, 0x20
    nop
    add     t3, a3, a4              // a3 via WB->ID, a4 via MEM/WB->EX
    CHECK   t3, 0x30

    TEST_END
