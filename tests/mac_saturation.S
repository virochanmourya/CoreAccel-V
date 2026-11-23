// mac_saturation — F2: READ_LO/READ_HI saturate the 72-bit accumulator to
// signed 64-bit (INT64_MAX / INT64_MIN) instead of wrapping, and a saturating
// readback sets the sticky overflow flag.
#include "test.h"

    .data
    .balign 4
wmin:   .word 0x80000000
wmax:   .word 0x7fffffff

    TEST_BEGIN
    la      a1, wmin
    la      a2, wmax

    // +2^62 + 2^62 = 2^63  -> above INT64_MAX
    MAC_CLEAR
    li      a0, 0x80000000
    nop
    MAC     a0, a1
    nop
    MAC     a0, a1
    MAC_RDHI t0
    CHECK   t0, 0x7fffffff
    MAC_RDLO t1
    CHECK   t1, 0xffffffff

    // 3 x (INT_MIN * INT_MAX) = 3 * (-2^62 + 2^31) -> below INT64_MIN
    MAC_CLEAR
    nop
    MAC     a0, a2
    nop
    MAC     a0, a2
    nop
    MAC     a0, a2
    MAC_RDHI t0
    CHECK   t0, 0x80000000
    MAC_RDLO t1
    CHECK   t1, 0x00000000
    MAC_STATUS t2
    CHECK   t2, 1

    TEST_END
