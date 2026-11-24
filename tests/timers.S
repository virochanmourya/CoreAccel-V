// timers — timers / PWM / capture at 0xC000_5000 (APB slot 5, PLIC
// source 5). Testbench: cap_in[0] = pwm_out[0], cap_in[1] = pwm_out[sel]
// (sel = 1 at reset, SIM_CAP1_SEL + n selects pwm n).
// - reset values and register widths
// - timer COUNT write, auto-reload period (mcycle window), one-shot stops
// - PWM period and duty measured exactly by the capture channels
//   (PWM_PRESC 3: period (PERIOD+1)*4, high DUTY*4 clocks)
// - capture source select, overflow (capture while unacknowledged)
// - POL: idle level and the active phase moved to the end of the period
// - PERIOD/DUTY shadowing: a new PERIOD takes effect at the next wrap
// - timer match interrupt through the PLIC (source 5); PSLVERR on 0x0C
//
// Polling bounds. One STATUS poll iteration (lw + andi + branch) costs
// P <= 12 clocks at the slowest corner (measured: 120 polls = 1200 clocks
// at WAIT=0, 1440 at WAIT=3, flat over HOLD). An interval measured from
// "poll saw event 1, W1C, csrr" to "poll saw event 2, csrr" is the true
// interval plus at most P, minus at most P plus the W1C store (< 2P):
// windows are true - 3P .. true + 2P, rounded out. Measured over HOLD 0..3 x
// WAIT {0, rand, 3}: T0 987..991 (true 1000), PWM3 new period 25..44 (true
// 44), POL counter 3..6 / 53..56 steps, CAP1 acknowledge 23..41 clocks after
// the edge (the PWM1 high phase is 120), T1 one-shot from the enable store
// to the poll that sees it 215..227 (true 200).
#include "test.h"

#define TM_ST     0x00
#define TM_IE     0x04
#define TM_PPRESC 0x08
#define T0        0x10
#define T1        0x20
#define PWM0      0x40
#define PWM1      0x50
#define PWM2      0x60
#define PWM3      0x70
#define CAP0      0x80
#define CAP1      0x90
// within a group
#define CTRL      0x0
#define PRESC     0x4
#define CMP       0x8
#define COUNT     0xC
#define PERIOD    0x4
#define DUTY      0x8
#define PCOUNT    0xC
#define CCOUNT    0x8
#define CAPT      0xC
// STATUS bits
#define S_T0      0x001
#define S_T1      0x002
#define S_CAP0    0x004
#define S_CAP1    0x008
#define S_OVF0    0x010
#define S_OVF1    0x020
#define S_PWM3    0x200

    EXPECT_DBUS_ERRORS 1
    EXPECT_OTHER_TRAPS 1

.macro WR off, v
    li      t0, \v
    sw      t0, \off(a4)
.endm
.macro RD off, exp
    lw      t0, \off(a4)
    CHECK   t0, \exp
.endm
// Spin until STATUS & \m != 0 (uses t0).
.macro WAITST m
91: lw      t0, TM_ST(a4)
    andi    t0, t0, \m
    beqz    t0, 91b
.endm
// Wait for a capture on channel \c (status bit \m), read CAPT into \r,
// acknowledge it (uses t0).
.macro CAPWAIT c, m, r
    WAITST  \m
    lw      \r, \c + CAPT(a4)
    li      t0, \m
    sw      t0, TM_ST(a4)
.endm
.macro SIM v
    li      t0, HALT_ADDR
    li      t1, \v
    sw      t1, 0(t0)
.endm

    TEST_BEGIN
    li      a4, TIMER_BASE
    li      a6, PLIC_BASE

    // ---- reset values ----
    RD      TM_ST, 0
    RD      TM_IE, 0
    RD      TM_PPRESC, 0
    RD      T0 + CTRL, 0
    RD      T0 + PRESC, 0
    RD      T0 + CMP, 0xFFFFFFFF
    RD      T0 + COUNT, 0
    RD      T1 + CMP, 0xFFFFFFFF
    RD      PWM0 + CTRL, 0
    RD      PWM3 + PERIOD, 0
    RD      PWM3 + DUTY, 0
    RD      PWM3 + PCOUNT, 0
    RD      CAP0 + CTRL, 0
    RD      CAP1 + PRESC, 0
    RD      CAP1 + CCOUNT, 0
    RD      CAP1 + CAPT, 0

    // ---- widths ----
    WR      TM_IE, -1
    RD      TM_IE, 0x3FF
    WR      TM_IE, 0
    WR      TM_PPRESC, -1
    RD      TM_PPRESC, 0xFFFF
    WR      T0 + PRESC, -1
    RD      T0 + PRESC, 0xFFFF
    WR      T0 + PRESC, 0
    WR      T1 + CTRL, 2                // ONESHOT, not enabled
    RD      T1 + CTRL, 2
    WR      T1 + CTRL, 0
    WR      PWM0 + PERIOD, -1
    RD      PWM0 + PERIOD, 0xFFFF
    WR      PWM0 + DUTY, -1
    RD      PWM0 + DUTY, 0xFFFF
    WR      PWM0 + CTRL, 2              // POL only (EN = 0)
    RD      PWM0 + CTRL, 2
    WR      PWM0 + CTRL, 0
    WR      CAP0 + CTRL, 6              // edges selected, EN = 0
    RD      CAP0 + CTRL, 6
    WR      CAP0 + PRESC, -1
    RD      CAP0 + PRESC, 0xFFFF
    WR      CAP0 + PRESC, 0
    WR      TM_ST, 0x3FF
    RD      TM_ST, 0                    // idle: no events (POL toggle unseen: EN = 0)

    // ---- timer COUNT write with EN = 0 ----
    WR      T0 + COUNT, 1234
    RD      T0 + COUNT, 1234
    WR      T0 + COUNT, 0

    // ---- T0 auto-reload: CMP 999, PRESC 0 -> a match every 1000 ----
    WR      T0 + CMP, 999
    WR      T0 + CTRL, 1
    WAITST  S_T0
    WR      TM_ST, S_T0
    csrr    s4, mcycle
    WAITST  S_T0
    csrr    s5, mcycle
    WR      TM_ST, S_T0
    sub     t1, s5, s4
    addi    t1, t1, -950
    sltiu   t1, t1, 100                 // 950 .. 1049 (1000 - 3P .. + 2P)
    CHECK   t1, 1
    lw      t1, T0 + COUNT(a4)
    sltiu   t1, t1, 1000                // wrapped, never past CMP
    CHECK   t1, 1
    WR      T0 + CTRL, 0
    WR      TM_ST, S_T0

    // ---- T1 one-shot: CMP 49, PRESC 3 -> one match after 200, then stop ----
    WR      T1 + PRESC, 3
    WR      T1 + CMP, 49
    csrr    s4, mcycle
    WR      T1 + CTRL, 3
    WAITST  S_T1
    csrr    s5, mcycle
    sub     t1, s5, s4                  // enable store + 200 + poll:
    addi    t1, t1, -180
    sltiu   t1, t1, 80                  // 180 .. 259 (200 - 20 .. 200 + 3P + 20)
    CHECK   t1, 1                       // (prescaler ignored: about 50)
    RD      T1 + CTRL, 2                // EN cleared, ONESHOT kept
    RD      T1 + COUNT, 0
    WR      TM_ST, S_T1
    li      t1, 120                     // >= 120 * 10 clocks > 2 periods (400)
1:  lw      t0, TM_ST(a4)
    addi    t1, t1, -1
    bnez    t1, 1b
    andi    t0, t0, S_T1
    CHECK   t0, 0                       // no second match
    RD      T1 + COUNT, 0

    // ---- PWM period and duty, measured by the capture channels ----
    WR      TM_PPRESC, 3                // PWM step = 4 clocks
    WR      PWM0 + PERIOD, 99           // period 400
    WR      PWM0 + DUTY, 50
    WR      PWM1 + PERIOD, 99           // period 400, high 120
    WR      PWM1 + DUTY, 30
    WR      CAP0 + CTRL, 3              // EN, rising
    WR      CAP1 + CTRL, 7              // EN, both edges
    WR      PWM0 + CTRL, 1
    WR      PWM1 + CTRL, 1
    WR      TM_ST, 0x3FF
    CAPWAIT CAP0, S_CAP0, s1
    CAPWAIT CAP0, S_CAP0, s2
    sub     t1, s2, s1
    CHECK   t1, 400                     // PWM0 period, exact
    WR      TM_ST, 0x3FF
    CAPWAIT CAP1, S_CAP1, s1
    CAPWAIT CAP1, S_CAP1, s2
    CAPWAIT CAP1, S_CAP1, s3
    sub     t1, s2, s1                  // one phase
    sub     t2, s3, s2                  // the other
    add     t3, t1, t2
    CHECK   t3, 400                     // PWM1 period
    bltu    t1, t2, 2f
    mv      t1, t2
2:  CHECK   t1, 120                     // PWM1 high time (the shorter phase)
    lw      t0, TM_ST(a4)
    andi    t0, t0, S_OVF1              // (CAP0 runs unacknowledged meanwhile)
    CHECK   t0, 0                       // every CAP1 capture was acknowledged in time

    // ---- capture source select: pwm2 -> cap1 ----
    WR      PWM2 + PERIOD, 49           // period 200
    WR      PWM2 + DUTY, 10
    WR      PWM2 + CTRL, 1
    WR      CAP1 + CTRL, 3              // rising only
    SIM     SIM_CAP1_SEL + 2
    WR      TM_ST, 0x3FF
    CAPWAIT CAP1, S_CAP1, s1
    CAPWAIT CAP1, S_CAP1, s2
    sub     t1, s2, s1
    CHECK   t1, 200                     // PWM2's period, not PWM1's
    SIM     SIM_CAP1_SEL + 1
    WR      PWM2 + CTRL, 0

    // ---- overflow: two captures without an acknowledge ----
    WR      TM_ST, 0x3FF
    WAITST  S_CAP0
    li      t0, 0x40                    // two more PWM0 wraps
    sw      t0, TM_ST(a4)
    WAITST  0x40
    li      t0, 0x40
    sw      t0, TM_ST(a4)
    WAITST  0x40
    lw      t0, TM_ST(a4)
    andi    t0, t0, S_CAP0 | S_OVF0
    CHECK   t0, S_CAP0 | S_OVF0
    lw      t1, CAP0 + CCOUNT(a4)
    lw      t2, CAP0 + CAPT(a4)
    sub     t1, t1, t2
    sltiu   t1, t1, 400                 // CAPT keeps the newest capture
    CHECK   t1, 1
    WR      TM_ST, S_CAP0 | S_OVF0
    lw      t0, TM_ST(a4)
    andi    t0, t0, S_OVF0
    CHECK   t0, 0

    // ---- POL ----
    // PWM1 DUTY 50 (of 100 steps); cap1 rising on pwm1. Normal: the rising
    // edge is at the wrap, so the counter reads 0..39 when the capture is
    // seen; inverted: it is at counter = DUTY, so it reads 50..69. Edge to
    // read: output register + 2-FF sync + edge (4) + poll (P) + the PCOUNT
    // read (P) < 30 clocks < 8 steps; window 20 steps.
    WR      CAP1 + CTRL, 3
    WR      PWM1 + DUTY, 50
    WR      TM_ST, 0x3FF
    WAITST  S_CAP1                      // let the new DUTY take effect
    WR      TM_ST, S_CAP1
    WAITST  S_CAP1
    lw      t1, PWM1 + PCOUNT(a4)
    sltiu   t1, t1, 20
    CHECK   t1, 1
    WR      PWM1 + CTRL, 3              // EN + POL
    WR      TM_ST, S_CAP1
    WAITST  S_CAP1                      // (may be the POL switch itself)
    WR      TM_ST, S_CAP1
    WAITST  S_CAP1
    lw      t1, PWM1 + PCOUNT(a4)
    addi    t1, t1, -50
    sltiu   t1, t1, 20
    CHECK   t1, 1
    WR      PWM1 + CTRL, 0              // disabled, POL 0: idle low
    WR      TM_ST, S_CAP1
    WR      PWM1 + CTRL, 2              // disabled, POL 1: idle high -> a rise
    WAITST  S_CAP1
    WR      PWM1 + CTRL, 0
    WR      TM_ST, S_CAP1

    // ---- shadowed PERIOD: takes effect at the next wrap ----
    WR      PWM3 + PERIOD, 999          // 4000 clocks
    WR      PWM3 + CTRL, 1
3:  lw      t0, PWM3 + PCOUNT(a4)
    sltiu   t0, t0, 21
    bnez    t0, 3b                      // counter past 20
    WR      PWM3 + PERIOD, 10
    RD      PWM3 + PERIOD, 10           // reads the written value
    lw      t1, PWM3 + PCOUNT(a4)
    sltiu   t1, t1, 21
    CHECK   t1, 0                       // still counting toward 999
    WR      TM_ST, S_PWM3
    WAITST  S_PWM3                      // the old period's wrap
    WR      TM_ST, S_PWM3
    csrr    s4, mcycle
    WAITST  S_PWM3                      // the new period: 11 steps = 44
    csrr    s5, mcycle
    sub     t1, s5, s4
    addi    t1, t1, -8
    sltiu   t1, t1, 72                  // 8 .. 79 (44 - 3P .. 44 + 2P, rounded out)
    CHECK   t1, 1
    WR      PWM3 + CTRL, 0
    WR      PWM0 + CTRL, 0
    WR      CAP0 + CTRL, 0
    WR      CAP1 + CTRL, 0
    RD      CAP1 + CCOUNT, 0            // EN = 0: counter cleared

    // ---- T0 match interrupt through the PLIC (source 5) ----
    WR      TM_ST, 0x3FF
    WR      T0 + CMP, 199
    WR      T0 + COUNT, 0
    WR      TM_IE, S_T0
    li      t0, 1
    sw      t0, 20(a6)                  // priority[5] = 1
    li      t0, 0x20
    li      t1, PLIC_BASE + 0x2000
    sw      t0, 0(t1)                   // enable source 5
    la      t0, tmr_handler
    csrw    mtvec, t0
    li      s6, 0
    li      s9, 0
    li      t0, 0x800
    csrw    mie, t0
    csrsi   mstatus, 8
    WR      T0 + CTRL, 1
4:  beqz    s6, 4b
    csrci   mstatus, 8
    CHECK   s6, 1
    CHECK   s9, 5                       // claimed source 5
    RD      T0 + CTRL, 0                // the handler stopped T0
    li      t1, PLIC_BASE + 0x1000
    lw      t0, 0(t1)
    CHECK   t0, 0
    la      t0, _trap_entry
    csrw    mtvec, t0
    WR      TM_IE, 0

    // ---- PSLVERR ----
    li      t0, 0x66
    li      a3, TIMER_BASE + 0x0C
e1: lw      t0, 0(a3)
    CHECK   t0, 0x66
    CHECK_TRAP 5, e1, 0xC000500C

    TEST_END

    .text
    .balign 4
tmr_handler:
    li      t2, PLIC_BASE + 0x200004
    lw      s9, 0(t2)                   // claim
    sw      zero, T0 + CTRL(a4)         // stop T0
    li      t3, S_T0
    sw      t3, TM_ST(a4)               // W1C: the timer irq drops
    sw      s9, 0(t2)                   // complete
    addi    s6, s6, 1
    mret
