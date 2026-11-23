// mac_fwd — MAC operands arriving through forwarding and load-use stalls,
// and a MAC read result forwarded to the next instruction.
#include "test.h"

    .data
    .balign 4
wts:    .word 3, -2
ten:    .word 10
pw1:    .word wts + 4               // pointer to wts[1]

    TEST_BEGIN
    // rs2 (weight address) from MEM/WB, rs1 from EX/MEM
    MAC_CLEAR
    la      a1, wts + 4
    li      a0, 6
    MAC     a0, a1                  // 6 * -2 = -12
    MAC_RDLO t0
    CHECK   t0, 0xfffffff4
    MAC_RDHI t1
    CHECK   t1, 0xffffffff

    // rs1 from a load (load-use stall)
    MAC_CLEAR
    la      a2, ten
    la      a1, wts
    lw      a0, 0(a2)
    MAC     a0, a1                  // 10 * 3 = 30
    MAC_RDLO t0
    CHECK   t0, 30

    // rs2 from a load (load-use stall on the weight address)
    MAC_CLEAR
    la      a3, pw1
    li      a0, 7
    lw      a4, 0(a3)
    MAC     a0, a4                  // 7 * -2 = -14
    MAC_RDLO t0
    addi    t1, t0, 1               // READ result forwarded EX/MEM -> EX
    CHECK   t1, 0xfffffff3

    TEST_END
