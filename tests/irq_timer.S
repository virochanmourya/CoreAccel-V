// irq_timer — machine timer and timer interrupt.
// - mtime counts every cycle (and matches the time CSR); writes replace a half,
//   and the low half carries into the high half.
// - mtimecmp resets to all ones. mip.MTIP = mtime >= mtimecmp, compared as 64
//   bits: a low-word-only compare would be wrong across the word boundary.
// - The interrupt is taken only with MIE and MTIE both set. The instruction in
//   ID while the enabling CSR write is in EX is not tagged (MIE is still 0
//   until that write lands at the end of the cycle) and executes; the next
//   one takes the interrupt and executes after the return (mepc = it).
// - Pending while a DIV holds EX: taken after the DIV completes.
// - Pending behind an ECALL: the exception is taken first, the interrupt right
//   after its return.
// The default handler silences the timer (mtimecmp = all ones).
#include "test.h"

    EXPECT_OTHER_TRAPS 4

    TEST_BEGIN
    li      a0, MTIMER_BASE

    // ---- registers ----
    lw      t0, 8(a0)
    lw      t1, 12(a0)
    CHECK   t0, 0xffffffff
    CHECK   t1, 0xffffffff
    lw      t0, 0(a0)
    nop
    nop
    lw      t1, 0(a0)
    sub     t2, t1, t0
    CHECK   t2, 3                       // one per cycle
    csrr    t0, time
    lw      t1, 0(a0)
    sub     t2, t1, t0
    CHECK   t2, 2                       // CSR read in EX, load reads in MEM
    li      t1, 7
    sw      t1, 4(a0)                   // mtime hi = 7
    li      t1, -16
    sw      t1, 0(a0)                   // mtime lo = 0xfffffff0
    .rept   24
    nop
    .endr
    lw      t2, 4(a0)
    csrr    t3, timeh
    CHECK   t2, 8                       // the low half wrapped into the high half
    CHECK   t3, 8

    // ---- MTIP is a 64-bit compare (MIE = 0: no interrupt) ----
    csrr    t0, mip
    CHECK   t0, 0
    sw      zero, 4(a0)                 // mtime    = 0x00000000_fffffff0
    li      t1, -16
    sw      t1, 0(a0)
    li      t1, 1
    sw      t1, 12(a0)                  // mtimecmp = 0x00000001_00000000
    sw      zero, 8(a0)
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0                       // lo(mtime) >= lo(mtimecmp), but not as 64 bits
    li      t2, 30
1:  addi    t2, t2, -1
    bnez    t2, 1b
    csrr    t0, mip
    CHECK   t0, 0x80                    // pending once mtime passes 0x1_00000000
    li      t1, -1
    sw      t1, 12(a0)                  // mtimecmp = all ones: never
    sw      t1, 8(a0)
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0

    // ---- MTIE = 1, MIE = 0: pending, not taken ----
    li      t1, 0x80
    csrw    mie, t1
    sw      zero, 12(a0)                // mtimecmp = 0: always pending
    sw      zero, 8(a0)
    nop
    nop
    nop
    csrr    t0, mip
    CHECK   t0, 0x80
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 0

    // ---- MIE = 1, MTIE = 0: not taken ----
    csrw    mie, zero
    csrsi   mstatus, 8
    nop
    nop
    nop
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 0
    csrci   mstatus, 8

    // ---- MIE = 1, MTIE = 1: taken ----
    li      t1, 0x80
    csrw    mie, t1
    li      a5, 0
    li      a6, 0
    csrsi   mstatus, 8
i1: li      a5, 1                       // in ID with the CSR write in EX: MIE still 0
i2: li      a6, 2                       // takes the interrupt, runs after the return
    CHECK   a5, 1
    CHECK   a6, 2
    CHECK_TRAP 0x80000007, i2, 0
    TRAP_FIELD t0, TR_COUNT
    CHECK   t0, 1
    csrr    t0, mstatus
    CHECK   t0, 0x1888                  // MRET restored MIE
    csrci   mstatus, 8

    // ---- pending while a DIV holds EX: taken after it completes ----
    sw      zero, 12(a0)
    sw      zero, 8(a0)
    li      t1, 100
    li      t2, 7
    nop
    nop
    nop
    csrsi   mstatus, 8
    divu    t3, t1, t2                  // in ID with the CSR write in EX (MIE 0); then held
i3: li      t4, 5                       // tagged in ID during the hold, waits
    CHECK   t3, 14
    CHECK   t4, 5
    CHECK_TRAP 0x80000007, i3, 0
    csrci   mstatus, 8

    // ---- pending behind an ECALL: the exception first ----
    sw      zero, 12(a0)
    sw      zero, 8(a0)
    nop
    nop
    nop
    TRAP_FIELD t5, TR_COUNT
    csrsi   mstatus, 8
    ecall                               // not tagged (MIE 0); traps, flushes the tagged one
i4: li      t4, 6                       // takes the interrupt after the ECALL returns
    CHECK   t4, 6
    CHECK_TRAP 0x80000007, i4, 0
    TRAP_FIELD t0, TR_COUNT
    sub     t0, t0, t5
    CHECK   t0, 2
    csrci   mstatus, 8
    csrw    mie, zero

    TEST_END
