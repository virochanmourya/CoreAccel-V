// sysctl — system control at 0xC000_8000 (APB slot 8): chip ID, version,
// boot straps, reset cause, scratch registers, software reset and the
// watchdog. The test resets the chip twice and survives: SCRATCH0 (reset
// by the pin only) holds the stage, SCRATCH1 the signature pointer, so each
// boot appends its CHECKs where the previous one stopped.
//   stage 0 (pin reset): IDs, straps (pins moved after reset: ignored),
//            RST_CAUSE = PIN and W1C, scratch,
//            watchdog reset values and unlocked control, PSLVERR on 0x14,
//            a wrong SW_RESET key is ignored; then the right key resets.
//   stage 1 (software reset): RST_CAUSE = SW, scratch survived, watchdog
//            back at reset values; LOCK: CTRL/LOAD writes ignored; a wrong
//            kick key is ignored, a right one reloads; kicking every ~1000
//            clocks keeps a 3000-clock watchdog from firing for ~8000
//            clocks; then stop kicking and wait for it.
//   stage 2 (watchdog reset): RST_CAUSE = WDT, lock released, scratch kept.
#include "test.h"

#define SC_ID     0x00
#define SC_VER    0x04
#define SC_BOOT   0x08
#define SC_CAUSE  0x0C
#define SC_SWRST  0x10
#define SC_SCR0   0x20
#define SC_SCR1   0x24
#define SC_SCR2   0x28
#define SC_SCR3   0x2C
#define WDT_CTRL  0x40
#define WDT_LOAD  0x44
#define WDT_COUNT 0x48
#define WDT_KICK  0x4C

#define SW_RESET_KEY 0x53525354
#define WDT_KICK_KEY 0x4B49434B
#define WDT_TIMEOUT  3000

    EXPECT_DBUS_ERRORS 1

.macro WR off, v
    li      t0, \v
    sw      t0, \off(a4)
.endm
.macro RD reg, off
    lw      \reg, \off(a4)
.endm
// Store \reg to the next signature slot without an expected value of its
// own: a stage that was entered by a reset fills the slot of the previous
// stage's "still running" CHECK (expected = that stage's number).
.macro MARK reg
    sw      \reg, 0(s11)
    addi    s11, s11, 4
.endm
// ~4 clocks per iteration (addi + taken branch)
.macro DELAY n
    li      t2, \n
1:  addi    t2, t2, -1
    bnez    t2, 1b
.endm

    TEST_BEGIN
    li      a4, SYSCTL_BASE
    RD      t0, SC_SCR0
    li      t1, 1
    beq     t0, t1, stage1
    li      t1, 2
    beq     t0, t1, stage2
    CHECK   t0, 0                   // stage 0: SCRATCH0 is 0 after the pin reset

    // ---------------------------------------------------------------- stage 0
    RD      t0, SC_ID
    CHECK   t0, 0x43415631
    RD      t0, SC_VER
    CHECK   t0, 0x00060004
    RD      t0, SC_BOOT             // straps 0 (harness default), PLL lock
    CHECK   t0, 0x00000200
    li      t1, HALT_ADDR           // move the strap pins: the latch ignores them
    li      t0, SIM_BOOT_STRAP + 3
    sw      t0, 0(t1)
    DELAY   10
    RD      t0, SC_BOOT
    CHECK   t0, 0x00000200
    RD      t0, SC_CAUSE
    CHECK   t0, 1                   // PIN
    WR      SC_CAUSE, 6             // W1C of bits that are 0: no change
    RD      t0, SC_CAUSE
    CHECK   t0, 1
    WR      SC_CAUSE, 1
    RD      t0, SC_CAUSE
    CHECK   t0, 0
    WR      SC_SCR2, 0xA5A55A5A
    WR      SC_SCR3, 0x12345678
    RD      t0, SC_SCR2
    CHECK   t0, 0xA5A55A5A
    RD      t0, SC_SCR3
    CHECK   t0, 0x12345678
    RD      t0, SC_SWRST            // write-only registers read 0
    CHECK   t0, 0
    RD      t0, WDT_KICK
    CHECK   t0, 0

    // watchdog: reset values, COUNT follows LOAD while disabled
    RD      t0, WDT_CTRL
    CHECK   t0, 0
    RD      t0, WDT_LOAD
    CHECK   t0, 0xFFFFFFFF
    RD      t0, WDT_COUNT
    CHECK   t0, 0xFFFFFFFF
    WR      WDT_LOAD, 0x1234
    RD      t0, WDT_LOAD
    CHECK   t0, 0x1234
    RD      t0, WDT_COUNT
    CHECK   t0, 0x1234
    WR      WDT_CTRL, 1             // enable (unlocked)
    RD      t0, WDT_CTRL
    CHECK   t0, 1
    RD      t0, WDT_COUNT
    li      t1, 0x1234
    sltu    t0, t0, t1              // counting down
    CHECK   t0, 1
    WR      WDT_CTRL, 0             // unlocked: can be disabled
    RD      t0, WDT_CTRL
    CHECK   t0, 0
    RD      t0, WDT_COUNT
    CHECK   t0, 0x1234
    WR      WDT_LOAD, -1

    // unused offset: PSLVERR -> load access fault
bad_ld:
    lw      t0, 0x14(a4)
    CHECK_TRAP 5, bad_ld, (SYSCTL_BASE + 0x14)

    // wrong software-reset key: ignored
    WR      SC_SWRST, 0x12345678
    DELAY   20
    li      t0, 0x600D
    CHECK   t0, 0x600D
    RD      t0, SC_CAUSE
    CHECK   t0, 0

    WR      SC_SCR0, 1
    sw      s11, SC_SCR1(a4)
    WR      SC_SWRST, SW_RESET_KEY
    DELAY   200                     // the reset comes long before this ends
    CHECK   zero, 1                 // still running: 0 here fails; stage 1 writes 1
    j       done

    // ---------------------------------------------------------------- stage 1
stage1:
    RD      s11, SC_SCR1
    li      t0, 1
    MARK    t0                      // the slot of stage 0's last CHECK
    RD      t0, SC_CAUSE
    CHECK   t0, 4                   // SW (PIN was cleared in stage 0)
    RD      t0, SC_SCR2
    CHECK   t0, 0xA5A55A5A
    RD      t0, SC_SCR3
    CHECK   t0, 0x12345678
    RD      t0, WDT_CTRL
    CHECK   t0, 0
    RD      t0, WDT_LOAD
    CHECK   t0, 0xFFFFFFFF
    WR      SC_CAUSE, 4
    RD      t0, SC_CAUSE
    CHECK   t0, 0

    WR      WDT_LOAD, WDT_TIMEOUT
    WR      WDT_CTRL, 3             // enable + lock
    RD      t0, WDT_CTRL
    CHECK   t0, 3
    WR      WDT_CTRL, 0             // locked: ignored
    RD      t0, WDT_CTRL
    CHECK   t0, 3
    WR      WDT_LOAD, 0x7FFF        // locked: ignored
    RD      t0, WDT_LOAD
    CHECK   t0, WDT_TIMEOUT
    WR      WDT_KICK, WDT_KICK_KEY
    RD      t3, WDT_COUNT
    WR      WDT_KICK, 0x1234        // wrong key: ignored
    RD      t4, WDT_COUNT
    sltu    t0, t4, t3              // still counting down
    CHECK   t0, 1
    WR      WDT_KICK, WDT_KICK_KEY
    RD      t5, WDT_COUNT
    sltu    t0, t4, t5              // reloaded
    CHECK   t0, 1
    li      t1, WDT_TIMEOUT - 100
    sltu    t0, t1, t5              // ... to about LOAD
    CHECK   t0, 1

    li      a5, 8                   // 8 x ~1000 clocks, kicked each time
2:  DELAY   250
    WR      WDT_KICK, WDT_KICK_KEY
    addi    a5, a5, -1
    bnez    a5, 2b
    li      t0, 0x600D              // still alive after ~8000 clocks
    CHECK   t0, 0x600D

    WR      SC_SCR0, 2
    sw      s11, SC_SCR1(a4)
    DELAY   5000                    // ~20000 clocks: the watchdog fires first
    CHECK   zero, 2                 // no watchdog reset: 0 here fails; stage 2 writes 2
    j       done

    // ---------------------------------------------------------------- stage 2
stage2:
    RD      s11, SC_SCR1
    li      t0, 2
    MARK    t0                      // the slot of stage 1's last CHECK
    RD      t0, SC_CAUSE
    CHECK   t0, 2                   // WDT
    RD      t0, WDT_CTRL
    CHECK   t0, 0                   // the reset released the lock
    RD      t0, WDT_COUNT
    CHECK   t0, 0xFFFFFFFF
    RD      t0, SC_SCR2
    CHECK   t0, 0xA5A55A5A
    RD      t0, SC_SCR0
    CHECK   t0, 2
    RD      t0, SC_BOOT             // pins are 3 since stage 0: not re-sampled by
    CHECK   t0, 0x00000200          //  the software or watchdog reset
    j       done

done:
    TEST_END
