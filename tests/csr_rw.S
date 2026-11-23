// csr_rw — Zicsr: every instruction form (CSRRW/RS/RC and the I forms) on
// mscratch, x0 rules (rd = x0 writes only; RS/RC with rs1 = x0 / uimm = 0 do
// not write), rd = rs1, forwarding into and out of CSR ops (EX/MEM, load-use,
// MUL/DIV), and the read/write behaviour of every machine CSR: WARL fields
// (mstatus, mie, mip, mtvec, mepc, mcause), read-only-zero CSRs at read/write
// addresses (writes legal and ignored) and the read-only ID CSRs.
#include "test.h"

    .data
    .balign 4
word:   .word 0xcafef00d

    TEST_BEGIN
    csrr    s0, mtvec               // restored at the end (TEST_BEGIN may set it)

    // ---- mscratch: all six forms ----
    li      t0, 0x12345678
    csrw    mscratch, t0
    csrr    t1, mscratch
    CHECK   t1, 0x12345678
    li      t0, 0x0000ff00
    csrrs   t1, mscratch, t0        // returns the old value, then sets bits
    CHECK   t1, 0x12345678
    csrr    t1, mscratch
    CHECK   t1, 0x1234ff78
    li      t0, 0x12000078
    csrrc   t1, mscratch, t0
    CHECK   t1, 0x1234ff78
    csrr    t1, mscratch
    CHECK   t1, 0x0034ff00
    csrrwi  t1, mscratch, 0x15
    CHECK   t1, 0x0034ff00
    csrrsi  t1, mscratch, 0x0a      // 0x15 | 0x0a = 0x1f
    CHECK   t1, 0x15
    csrrci  t1, mscratch, 0x03      // 0x1f & ~3 = 0x1c
    CHECK   t1, 0x1f
    csrr    t1, mscratch
    CHECK   t1, 0x1c

    // ---- rd = rs1, rd = x0, rs1 = x0 / uimm = 0 ----
    li      t2, 0xabcd0001
    csrrw   t2, mscratch, t2        // swap
    CHECK   t2, 0x1c
    csrr    t1, mscratch
    CHECK   t1, 0xabcd0001
    li      t0, 0x5555
    csrrw   x0, mscratch, t0        // write only
    csrr    t1, mscratch
    CHECK   t1, 0x5555
    csrrs   t1, mscratch, x0        // read only
    CHECK   t1, 0x5555
    csrrci  t1, mscratch, 0         // read only
    csrrc   t2, mscratch, x0        // read only
    CHECK   t1, 0x5555
    CHECK   t2, 0x5555

    // ---- forwarding ----
    li      t0, 0x100
    addi    t0, t0, 0x23            // EX/MEM forward into the CSR source
    csrw    mscratch, t0
    csrr    t1, mscratch            // CSR write then read, back to back
    addi    t2, t1, 1               // CSR result forwarded
    CHECK   t2, 0x124
    la      a0, word
    lw      t0, 0(a0)
    csrw    mscratch, t0            // load-use into a CSR write
    csrr    t1, mscratch
    CHECK   t1, 0xcafef00d
    li      t0, 6
    li      t1, 7
    mul     t2, t0, t1              // MUL result into a CSR
    csrw    mscratch, t2
    csrr    t3, mscratch
    divu    t4, t3, t0              // CSR result into a DIV: 42 / 6
    CHECK   t3, 42
    CHECK   t4, 7

    // ---- mstatus: MIE[3], MPIE[7] RW, MPP[12:11] = 11, rest 0 ----
    li      t0, -1
    csrw    mstatus, t0
    csrr    t1, mstatus
    csrw    mstatus, zero
    csrr    t2, mstatus
    CHECK   t1, 0x1888
    CHECK   t2, 0x1800
    csrsi   mstatus, 0x8            // set MIE
    csrr    t1, mstatus
    csrci   mstatus, 0x8
    csrr    t2, mstatus
    CHECK   t1, 0x1808
    CHECK   t2, 0x1800
    li      t0, -1
    csrw    mstatush, t0            // legal, ignored
    csrr    t1, mstatush
    CHECK   t1, 0

    // ---- misa: read-only value, writes legal and ignored ----
    csrr    t1, misa
    CHECK   t1, 0x40801100
    csrw    misa, zero
    csrr    t1, misa
    CHECK   t1, 0x40801100

    // ---- mie: MTIE[7], MEIE[11]; mip: read-only bits, writes ignored ----
    csrw    mie, t0                 // t0 = -1
    csrr    t1, mie
    csrw    mie, zero
    csrr    t2, mie
    CHECK   t1, 0x880
    CHECK   t2, 0
    csrw    mip, t0
    csrr    t1, mip
    CHECK   t1, 0

    // ---- mtvec: BASE RW, MODE = 00 (direct only) ----
    csrw    mtvec, t0
    csrr    t1, mtvec
    li      t2, 0x00001235
    csrw    mtvec, t2
    csrr    t2, mtvec
    CHECK   t1, 0xfffffffc
    CHECK   t2, 0x00001234
    csrw    mtvec, s0

    // ---- mepc: [1:0] = 0 ----
    csrw    mepc, t0
    csrr    t1, mepc
    li      t2, 0x103
    csrw    mepc, t2
    csrr    t2, mepc
    CHECK   t1, 0xfffffffc
    CHECK   t2, 0x100

    // ---- mcause: [31] and [3:0] ----
    csrw    mcause, t0
    csrr    t1, mcause
    li      t2, 0x0000000b
    csrw    mcause, t2
    csrr    t2, mcause
    li      t3, 0x7ffffff0
    csrw    mcause, t3
    csrr    t3, mcause
    CHECK   t1, 0x8000000f
    CHECK   t2, 0xb
    CHECK   t3, 0

    // ---- mtval: 32-bit RW ----
    li      t2, 0xdeadbeef
    csrw    mtval, t2
    csrr    t1, mtval
    CHECK   t1, 0xdeadbeef
    csrw    mtval, zero
    csrr    t1, mtval
    CHECK   t1, 0

    // ---- read-only-zero CSRs at read/write addresses: writes ignored ----
    csrw    0x320, t0               // mcountinhibit
    csrr    t1, 0x320
    CHECK   t1, 0
    csrw    0xB03, t0               // mhpmcounter3
    csrr    t1, 0xB03
    CHECK   t1, 0
    csrw    0xB9F, t0               // mhpmcounter31h
    csrr    t1, 0xB9F
    CHECK   t1, 0
    csrw    0x323, t0               // mhpmevent3
    csrr    t1, 0x323
    CHECK   t1, 0
    csrw    0x33F, t0               // mhpmevent31
    csrr    t1, 0x33F
    CHECK   t1, 0

    // ---- read-only ID CSRs (reads are legal) ----
    csrr    t1, mvendorid
    CHECK   t1, 0
    csrr    t1, marchid
    CHECK   t1, 0
    csrr    t1, mimpid
    CHECK   t1, 0
    csrr    t1, mhartid
    CHECK   t1, 0
    csrr    t1, 0xF15               // mconfigptr
    CHECK   t1, 0

    // ---- WFI is a legal NOP ----
    li      t1, 0x77
    wfi
    addi    t1, t1, 1
    CHECK   t1, 0x78

    TEST_END
