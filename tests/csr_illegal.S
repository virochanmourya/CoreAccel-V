// csr_illegal — Zicsr illegal cases: CSR addresses that do not exist
// (M-mode only: no U/S CSRs, nothing past the implemented hpm ranges), writes
// to read-only addresses (csr[11:10] = 11, including RS/RC(I) whose rs1 field
// is non-zero even when the register holds 0), the reserved SYSTEM funct3 100,
// SRET, and WFI with rd != 0. An illegal CSR instruction writes neither rd nor
// the CSR. Reads of read-only CSRs (rs1 = x0 / uimm = 0) stay legal.
#include "test.h"

    EXPECT_ILLEGAL 13

    TEST_BEGIN
    li      t0, 0x11
    csrr    t0, 0x7c0               // [1] no such CSR
    csrr    t0, 0x306               // [2] mcounteren: no U-mode
    csrr    t0, 0x180               // [3] satp: no S-mode
    csrr    t0, 0x100               // [4] sstatus: no S-mode
    csrr    t0, 0xB20               // [5] one past mhpmcounter31
    csrr    t0, 0x322               // [6] one below mhpmevent3
    CHECK   t0, 0x11                // rd never written

    li      t1, 5
    li      a0, 0
    li      t0, 0x33
    csrrw   t0, mvendorid, t1       // [7] write to a read-only address
    csrrw   t0, mhartid, t1         // [8]
    csrrsi  t0, cycle, 1            // [9] set with uimm != 0
    csrrc   t0, instret, a0         // [10] rs1 field != x0: a write, even with a0 = 0
    CHECK   t0, 0x33

    .insn i 0x73, 4, t0, x0, 0      // [11] SYSTEM funct3 = 100 (reserved)
    .word   0x10200073              // [12] SRET (no S-mode)
    .insn i 0x73, 0, t0, x0, 0x105  // [13] WFI encoding with rd = t0
    CHECK   t0, 0x33

    // still legal: reads of read-only CSRs
    csrrs   t0, mhartid, x0
    CHECK   t0, 0
    csrrsi  t0, mvendorid, 0
    CHECK   t0, 0
    csrrci  t0, marchid, 0
    CHECK   t0, 0
    li      t0, 0x44
    csrrs   t0, cycle, x0           // legal read: non-zero
    snez    t0, t0
    CHECK   t0, 1

    TEST_END
