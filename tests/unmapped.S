// unmapped — data accesses outside TCM and the defined peripheral registers
// raise the dbus_error stub and have no architectural effect: loads return 0,
// stores change nothing. The halt address 0xC000_0FFC is reserved, not an error.
#include "test.h"

    EXPECT_DBUS_ERRORS 6

    .data
    .balign 4
sentinel: .word 0x5ee5ee55

    TEST_BEGIN
    li      t3, 0x77777777

    li      a0, 0x00000100          // IMEM address: not reachable from the data bus
    li      t0, 0x11
    lw      t0, 0(a0)
    CHECK   t0, 0

    li      a0, 0x40000000          // hole
    li      t0, 0x22
    lw      t0, 0(a0)
    CHECK   t0, 0
    sw      t3, 0(a0)               // store to a hole: dropped

    li      a0, 0xC0000010          // peripheral page, undefined register
    li      t0, 0x33
    lw      t0, 0(a0)
    CHECK   t0, 0
    sw      t3, 0(a0)

    li      a0, 0xC0001000          // past the peripheral page
    li      t0, 0x44
    lw      t0, 0(a0)
    CHECK   t0, 0

    // mapped neighbours still work
    li      a0, 0xC0000008
    li      t0, 0x0abc
    sw      t0, 0(a0)
    lw      t1, 0(a0)
    CHECK   t1, 0x0abc

    // TCM untouched by the dropped stores
    la      a1, sentinel
    lw      t2, 0(a1)
    CHECK   t2, 0x5ee5ee55

    TEST_END
