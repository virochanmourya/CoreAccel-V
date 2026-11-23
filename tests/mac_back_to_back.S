// mac_back_to_back — F1: consecutive MAC instructions must each accumulate.
#include "test.h"

    .data
    .balign 4
w3:     .word 3

    TEST_BEGIN
    la      a1, w3
    li      a0, 5
    MAC_CLEAR
    nop

    MAC     a0, a1
    MAC     a0, a1                  // 2 x 15
    MAC_RDLO t0
    CHECK   t0, 30

    MAC_CLEAR
    MAC     a0, a1
    MAC     a0, a1
    MAC     a0, a1                  // 3 x 15
    MAC_RDLO t0
    CHECK   t0, 45

    TEST_END
