// trap_sync — every synchronous trap cause with its mcause / mepc / mtval:
// illegal (2), ECALL (11), EBREAK (3), misaligned LW/LH (4) and SW/SH (6,
// no write), instruction address misaligned (0) for JAL, a taken branch and
// JALR (no jump, no link), a not-taken branch to a misaligned target and a
// JALR to an odd address (both legal), instruction access fault (1) for a
// jump outside IMEM. Then MRET (returns to mepc, MIE <= MPIE, MPIE <= 1) and
// the trap-entry MIE -> MPIE save.
#include "test.h"

    EXPECT_ILLEGAL 1
    EXPECT_MISALIGNED 4
    EXPECT_OTHER_TRAPS 8

    .data
    .balign 4
wdat:   .word 0x11223344

    TEST_BEGIN
t_ill:  .word   0x0000007f              // illegal
    CHECK_TRAP 2, t_ill, 0
t_ecall: ecall
    CHECK_TRAP 11, t_ecall, 0
t_ebrk: ebreak
    CHECK_TRAP 3, t_ebrk, 0

    // ---- misaligned loads / stores: mtval = address, no access ----
    la      a0, wdat
    li      t0, 0x77
t_lw:   lw      t0, 1(a0)
    CHECK   t0, 0x77                    // rd not written
    CHECK_TRAP 4, t_lw, wdat+1
t_lh:   lh      t0, 3(a0)
    CHECK_TRAP 4, t_lh, wdat+3
t_sw:   sw      t0, 2(a0)
    CHECK_TRAP 6, t_sw, wdat+2
t_sh:   sh      t0, 1(a0)
    CHECK_TRAP 6, t_sh, wdat+1
    lw      t1, 0(a0)
    CHECK   t1, 0x11223344              // neither store wrote

    // ---- instruction address misaligned: no jump, no link ----
    li      ra, 0x5a5a
t_jal:  .word   0x006000ef              // jal ra, .+6
    CHECK   ra, 0x5a5a
    CHECK_TRAP 0, t_jal, t_jal+6
t_beq:  .word   0x00000363              // beq x0, x0, .+6 (taken)
    CHECK_TRAP 0, t_beq, t_beq+6
    .word   0x00001363                  // bne x0, x0, .+6: not taken, no trap
    LA_ABS  t0, t_jr_tgt
    addi    t0, t0, 2
t_jalr: jalr    ra, 0(t0)               // target bit 1 set
    CHECK   ra, 0x5a5a
    CHECK_TRAP 0, t_jalr, t_jr_tgt+2
    LA_ABS  t0, t_jr_tgt
    addi    t0, t0, 1                   // bit 0 is cleared by JALR: legal
t_jr_ok: jalr   ra, 0(t0)
    li      t1, 0xbad                   // skipped by the jump
t_jr_tgt:
    li      t1, 0x600d
    CHECK   t1, 0x600d
    CHECK   ra, t_jr_ok+4

    // ---- instruction access fault: jump outside IMEM (handler returns to ra) ----
    li      t0, 0x2000                  // first word past the 8 KB IMEM
t_ff1:  jalr    ra, 0(t0)
    CHECK   ra, t_ff1+4
    CHECK_TRAP 1, 0x2000, 0x2000
    li      t0, 0x80000000              // TCM: data only
    jalr    ra, 0(t0)
    CHECK_TRAP 1, 0x80000000, 0x80000000
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 12                      // 7 + 3 + 2 traps so far

    // ---- MRET: PC <= mepc, MIE <= MPIE, MPIE <= 1 ----
    LA_ABS  t0, t_mret_tgt
    csrw    mepc, t0
    li      t1, 0x80                    // MPIE = 1, MIE = 0
    csrw    mstatus, t1
    li      t2, 0
    mret
    li      t2, 0xbad                   // never executed
    li      t2, 0xbad
t_mret_tgt:
    csrr    t1, mstatus
    CHECK   t1, 0x1888                  // MIE = 1, MPIE = 1, MPP = 11
    CHECK   t2, 0
    csrw    mstatus, zero

    // ---- trap entry: MPIE <= MIE, MIE <= 0; the handler's MRET restores ----
    li      t1, 0x8                     // MIE = 1, MPIE = 0
    csrw    mstatus, t1
    ecall
    csrr    t1, mstatus
    CHECK   t1, 0x1888                  // MIE came back from MPIE = 1
    csrw    mstatus, zero

    TEST_END
