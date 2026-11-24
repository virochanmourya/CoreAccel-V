// bus_err — AXI/APB error responses become precise access faults, and
// sub-word accesses over the bus.
// - SLVERR (PSLVERR from the legacy page, undefined offset): load / store
// - DECERR (AXI default slave: hole, ext-memory region not present): load / store
// - PSLVERR from an unused APB slot: load / store
//   Each: mcause 5/7, mepc = the access, mtval = the address, a load leaves
//   rd unchanged, a store changes nothing.
// - SB/SH to a word register take the lane-replicated data; LB/LBU/LH/LHU
//   from a bus register select and extend like TCM loads.
// - A misaligned bus access traps in EX (cause 4) and never reaches the bus.
#include "test.h"

    EXPECT_DBUS_ERRORS 6
    EXPECT_MISALIGNED 1

    TEST_BEGIN
    li      a5, 0xC0000000
    li      s0, 0x1234
    sw      s0, 8(a5)               // 7-segment register = 0x1234

    // ---- SLVERR: legacy page, undefined offset ----
    li      t0, 0x11
e1: lw      t0, 0x10(a5)
    CHECK   t0, 0x11
    CHECK_TRAP 5, e1, 0xC0000010
    li      t1, 0x99
e2: sw      t1, 0x14(a5)
    CHECK_TRAP 7, e2, 0xC0000014
    lw      t2, 8(a5)
    CHECK   t2, 0x1234              // nothing written

    // ---- DECERR: hole, ext-memory region (not present yet) ----
    li      a3, 0x40000000
    li      t0, 0x22
e3: lw      t0, 4(a3)
    CHECK   t0, 0x22
    CHECK_TRAP 5, e3, 0x40000004
    li      a3, 0x90000000
e4: sw      t1, 0(a3)
    CHECK_TRAP 7, e4, 0x90000000

    // ---- PSLVERR: unused APB slots ----
    li      a3, 0xC000F000
    li      t0, 0x33
e5: lw      t0, 8(a3)
    CHECK   t0, 0x33
    CHECK_TRAP 5, e5, 0xC000F008
    li      a3, 0xC0002000
e6: sb      t1, 3(a3)
    CHECK_TRAP 7, e6, 0xC0002003
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 6

    // ---- sub-word stores to a word register ----
    li      t1, 0x5AB
    sb      t1, 8(a5)               // data 0xABABABAB -> 7-seg [15:0] = 0xABAB
    lw      t2, 8(a5)
    CHECK   t2, 0xABAB
    li      t1, 0xBEEF
    sh      t1, 10(a5)              // data 0xBEEFBEEF -> 0xBEEF
    lw      t2, 8(a5)
    CHECK   t2, 0xBEEF

    // ---- sub-word loads from a bus register ----
    lbu     t2, 9(a5)
    CHECK   t2, 0xBE
    lb      t2, 9(a5)
    CHECK   t2, 0xFFFFFFBE
    lh      t2, 8(a5)
    CHECK   t2, 0xFFFFBEEF
    lhu     t2, 8(a5)
    CHECK   t2, 0xBEEF
    lhu     t2, 10(a5)
    CHECK   t2, 0
    lbu     t2, 12(a5)              // GPIO output latch: 3
    CHECK   t2, 3

    // ---- misaligned: trapped in EX, no bus access ----
    li      t0, 0x44
e7: lw      t0, 6(a5)
    CHECK   t0, 0x44
    CHECK_TRAP 4, e7, 0xC0000006

    TEST_END
