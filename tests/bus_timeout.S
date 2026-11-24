// bus_timeout — a bus access that gets no answer ends after 256 cycles in a
// load/store access fault (mcause 5/7, mtval = the address). The harness
// holds every access to 0xC000_000C for 400 cycles (BUS_HANG_ADDR). The
// abandoned transaction still completes on the bus; its late response is
// drained and dropped. The next access is issued while it is still
// pending: it must wait for the drain (not take the late response, nor
// change the pending AR) and then work.
#include "test.h"

    EXPECT_DBUS_ERRORS 2
    BUS_HANG_ADDR 0xC000000C

    TEST_BEGIN
    li      a5, 0xC0000000
    li      s0, 0x55
    sw      s0, 8(a5)               // 7-segment register = 0x55

    // ---- load timeout ----
    li      t0, 0x77
    csrr    s1, mcycle
e1: lw      t0, 12(a5)              // hangs: access fault after 256 cycles
    csrr    s2, mcycle
    CHECK   t0, 0x77                // rd not written
    CHECK_TRAP 5, e1, 0xC000000C
    sub     s2, s2, s1
    sltiu   t1, s2, 256
    CHECK   t1, 0                   // it waited at least the timeout
    lw      t1, 8(a5)               // right behind: waits for the drain
    csrr    s3, mcycle
    CHECK   t1, 0x55
    sub     s3, s3, s1
    sltiu   t1, s3, 400
    CHECK   t1, 0                   // ... which ends 400 cycles after e1

    // ---- store timeout ----
    li      t1, 0x66
e2: sw      t1, 12(a5)
    CHECK_TRAP 7, e2, 0xC000000C
    sw      t1, 8(a5)
    lw      t2, 8(a5)
    CHECK   t2, 0x66
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 2

    TEST_END
