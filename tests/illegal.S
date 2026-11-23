// illegal — F5: encodings the core does not implement must not change
// architectural state (until traps exist, "do nothing" is the expected result).
// Also checks that execution continues normally afterwards.
#include "test.h"

    TEST_BEGIN
    li      a0, 6
    li      a1, 7

    li      t0, 0x55
    .insn r 0x33, 0, 1, t0, a0, a1  // MUL t0, a0, a1   (M ext, not implemented)
    CHECK   t0, 0x55

    li      t1, 0x66
    .insn r 0x33, 4, 1, t1, a0, a1  // DIV t1, a0, a1
    CHECK   t1, 0x66

    li      t2, 0x77
    .insn i 0x73, 1, t2, a0, 0x340  // CSRRW t2, mscratch, a0 (no CSRs)
    CHECK   t2, 0x77

    li      t3, 0x88
    .insn r 0x0B, 2, 0, t3, a0, a1  // CUSTOM-0 funct3=2 (unassigned)
    CHECK   t3, 0x88

    .word   0x00000073              // ECALL (no trap support: must act as NOP)
    fence                           // FENCE: legal NOP on this core
    li      t4, 0x99
    CHECK   t4, 0x99

    TEST_END
