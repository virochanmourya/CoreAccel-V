// mac_tcm_raw — F4: a store to a weight immediately followed by a MAC that
// reads that weight. Program order says the MAC must see the new value.
#include "test.h"

    .data
    .balign 4
w:      .word 2

    TEST_BEGIN
    la      a1, w
    li      a0, 5
    li      t0, 9
    MAC_CLEAR
    nop

    sw      t0, 0(a1)               // weight := 9
    MAC     a0, a1                  // 5 * 9 = 45
    MAC_RDLO t1
    CHECK   t1, 45

    TEST_END
