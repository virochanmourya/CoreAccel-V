// fwd_x0 — writes to x0 are discarded and never forwarded
#include "test.h"

    .data
val55:  .word 0x00000055

    TEST_BEGIN
    li      t0, 5
    addi    x0, t0, 1               // write x0 (EX/MEM has rd=0, reg_write=1)
    add     t1, x0, x0
    CHECK   t1, 0

    addi    x0, zero, 7             // MEM/WB path
    nop
    add     t1, x0, zero
    CHECK   t1, 0

    addi    x0, zero, 7             // WB -> ID bypass path
    nop
    nop
    add     t1, zero, x0
    CHECK   t1, 0

    lui     x0, 0x12345
    add     t1, zero, x0
    CHECK   t1, 0

    la      a0, val55               // load into x0, then use x0 (no stall, no forward)
    lw      x0, 0(a0)
    add     t1, x0, x0
    CHECK   t1, 0

    jal     x0, 1f                  // JAL with rd = x0
1:  CHECK   x0, 0

    TEST_END
