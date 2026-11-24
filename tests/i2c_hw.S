// i2c_hw — hardware I2C master at 0xC000_3000 (APB slot 3, PLIC source 3)
// against the TB register target at 0x48 (regs start as 0xA0 + index).
// - reset values (bit-bang owns the pads), register widths, PRESC minimum
// - pad mux: the legacy latch drives the pads only while PAD_SEL = 0
// - register writes (pointer + 2 bytes, STOP), read back with a repeated
//   START: ACK, ACK, NACK + STOP
// - NACK from an absent address (RXACK, sticky NACKF, W1C)
// - clock stretching by the target: the byte waits, data still correct
// - arbitration lost to a second master in the address byte, and a START
//   asked for while the other master holds the bus; recovery afterwards
// - 400 kHz prescaler: one START + byte + STOP takes 44 quarters of 63 clocks
// - DONE interrupt through the PLIC (source 3); PSLVERR on 0x20
#include "test.h"

#define LEGACY_GPIO   0xC0000000    // write: bit0 SCL, bit1 SDA latch (1 = release)
// legacy page: write = SCL/SDA latch, read +0x0 = synchronised pins {SDA, SCL}
#define I2C_START     0x01
#define I2C_STOP      0x02
#define I2C_WRITE     0x04
#define I2C_READ      0x08
#define I2C_NACK      0x10
#define ST_TIP        0x01
#define ST_RXACK      0x02
#define ST_AL         0x04
#define ST_BUSY       0x08
#define ST_DONE       0x10
#define ST_NACKF      0x20
#define ST_OWN        0x40

    EXPECT_DBUS_ERRORS 1
    EXPECT_OTHER_TRAPS 1

// Wait for the command to finish (uses t0).
.macro I2C_WAIT
91: lw      t0, 0x14(a4)
    andi    t0, t0, ST_TIP
    bnez    t0, 91b
.endm
// Send byte \b with command bits \c, wait, clear DONE (uses t0).
.macro I2C_TX b, c
    li      t0, \b
    sw      t0, 0x08(a4)
    li      t0, I2C_WRITE | \c
    sw      t0, 0x10(a4)
    I2C_WAIT
.endm
// Receive with command bits \c, wait, CHECK the byte (uses t0).
.macro I2C_RX c, exp
    li      t0, I2C_READ | \c
    sw      t0, 0x10(a4)
    I2C_WAIT
    lw      t0, 0x0C(a4)
    CHECK   t0, \exp
.endm
.macro SIM v
    li      t0, HALT_ADDR
    li      t1, \v
    sw      t1, 0(t0)
.endm

    TEST_BEGIN
    li      a4, I2C_BASE
    li      a5, LEGACY_GPIO
    li      a6, PLIC_BASE
    li      a7, PLIC_BASE + 0x200000    // threshold; claim/complete at +4

    // ---- reset values ----
    lw      t0, 0x00(a4)
    CHECK   t0, 0                       // EN 0, PAD_SEL 0 (bit-bang)
    lw      t0, 0x04(a4)
    CHECK   t0, 249                     // 100 kHz at 100 MHz
    lw      t0, 0x08(a4)
    CHECK   t0, 0
    lw      t0, 0x0C(a4)
    CHECK   t0, 0
    lw      t0, 0x10(a4)
    CHECK   t0, 0
    lw      t0, 0x14(a4)
    CHECK   t0, 0
    lw      t0, 0x18(a4)
    CHECK   t0, 0
    lw      t0, 0x1C(a4)
    CHECK   t0, 0

    // ---- widths ----
    li      t1, -1
    sw      t1, 0x00(a4)
    lw      t0, 0x00(a4)
    CHECK   t0, 3
    sw      zero, 0x00(a4)
    sw      t1, 0x04(a4)
    lw      t0, 0x04(a4)
    CHECK   t0, 0xFFFF
    li      t0, 1
    sw      t0, 0x04(a4)
    lw      t0, 0x04(a4)
    CHECK   t0, 3                       // minimum 3
    sw      t1, 0x08(a4)
    lw      t0, 0x08(a4)
    CHECK   t0, 0xFF
    sw      t1, 0x18(a4)
    lw      t0, 0x18(a4)
    CHECK   t0, 7
    sw      zero, 0x18(a4)
    li      t0, I2C_START | I2C_WRITE
    sw      t0, 0x10(a4)                // EN = 0: ignored
    lw      t0, 0x14(a4)
    CHECK   t0, 0

    // ---- pad mux ----
    li      t0, 2
    sw      t0, 0(a5)                   // legacy latch: SCL low, SDA released
    nop
    nop
    lw      t0, 0(a5)                   // synchronised pins
    CHECK   t0, 2                       // the legacy latch drives the pads
    li      t0, 2
    sw      t0, 0x00(a4)                // PAD_SEL = 1 (EN 0)
    nop
    nop
    lw      t0, 0(a5)                   // synchronised pins
    CHECK   t0, 3                       // master owns the pads, both released
    li      t0, 3
    sw      t0, 0(a5)                   // latch back to released
    lw      t0, 0x14(a4)
    CHECK   t0, 0                       // no START / STOP seen

    // ---- register write: ptr 3 <- 0x11, 0x22 ----
    li      t0, 3
    sw      t0, 0x00(a4)                // EN + PAD_SEL
    li      t0, 4
    sw      t0, 0x04(a4)                // quarter = 5 clocks
    I2C_TX  0x90, I2C_START
    lw      t0, 0x14(a4)
    CHECK   t0, ST_OWN | ST_DONE | ST_BUSY  // ACK, bus held
    I2C_TX  0x03, 0
    I2C_TX  0x11, 0
    I2C_TX  0x22, I2C_STOP
    lw      t0, 0x14(a4)
    CHECK   t0, ST_DONE                 // released, STOP seen
    li      t0, ST_DONE
    sw      t0, 0x14(a4)                // W1C
    lw      t0, 0x14(a4)
    CHECK   t0, 0

    // ---- read back from ptr 2 with a repeated START ----
    I2C_TX  0x90, I2C_START
    I2C_TX  0x02, 0
    I2C_TX  0x91, I2C_START             // repeated START, read
    lw      t0, 0x14(a4)
    CHECK   t0, ST_OWN | ST_DONE | ST_BUSY
    I2C_RX  0, 0xA2
    I2C_RX  0, 0x11
    I2C_RX  I2C_NACK | I2C_STOP, 0x22
    lw      t0, 0x14(a4)
    CHECK   t0, ST_DONE

    // ---- NACK ----
    I2C_TX  0xA0, I2C_START | I2C_STOP  // nobody at 0x50
    lw      t0, 0x14(a4)
    CHECK   t0, ST_NACKF | ST_DONE | ST_RXACK
    lw      t0, 0x1C(a4)
    CHECK   t0, 3                       // IP: NACKF, DONE
    li      t0, ST_NACKF | ST_DONE
    sw      t0, 0x14(a4)
    lw      t0, 0x14(a4)
    CHECK   t0, ST_RXACK                // RXACK is a level, not sticky
    // a byte or STOP without START on a bus we do not own: ignored
    li      t0, I2C_STOP
    sw      t0, 0x10(a4)
    li      t0, I2C_WRITE | I2C_STOP
    sw      t0, 0x10(a4)
    li      t0, I2C_READ
    sw      t0, 0x10(a4)
    lw      t0, 0x14(a4)
    CHECK   t0, ST_RXACK                // no TIP, no DONE, no START seen

    // ---- EN = 0 aborts a command at once ----
    li      t0, 1000
    sw      t0, 0x04(a4)                // quarter = 1001 clocks: still in START q0
    li      t0, 0x90
    sw      t0, 0x08(a4)
    li      t0, I2C_START | I2C_WRITE
    sw      t0, 0x10(a4)
    lw      t0, 0x14(a4)
    CHECK   t0, ST_TIP | ST_RXACK       // running
    li      t0, 2
    sw      t0, 0x00(a4)                // EN = 0, PAD_SEL kept
    lw      t0, 0x14(a4)
    CHECK   t0, ST_RXACK                // idle, nothing reached the bus
    li      t0, 3
    sw      t0, 0x00(a4)
    li      t0, 4
    sw      t0, 0x04(a4)

    // ---- clock stretching (2 us after every ACK clock) ----
    SIM     SIM_I2C_STRETCH + 2
    I2C_TX  0x90, I2C_START
    I2C_TX  0x05, 0
    csrr    s5, mcycle
    I2C_TX  0x5A, I2C_STOP              // 9 bits of 20 clocks + STOP, + 200 stretched
    csrr    t1, mcycle
    sub     t1, t1, s5
    sltiu   t1, t1, 380
    CHECK   t1, 0                       // took longer than an unstretched byte
    I2C_TX  0x90, I2C_START
    I2C_TX  0x05, 0
    I2C_TX  0x91, I2C_START
    I2C_RX  I2C_NACK | I2C_STOP, 0x5A
    SIM     SIM_I2C_STRETCH + 0
    li      t0, ST_DONE
    sw      t0, 0x14(a4)

    // ---- arbitration lost in the address byte (bit 7 = MSB, a 1) ----
    SIM     SIM_I2C_ARB + 0
    I2C_TX  0x90, I2C_START
    lw      t0, 0x14(a4)
    andi    t0, t0, ST_AL | ST_DONE | ST_OWN | ST_TIP
    CHECK   t0, ST_AL                   // lost: no DONE, bus released
    lw      t0, 0x1C(a4)
    CHECK   t0, 4                       // IP: AL
    li      t0, ST_AL
    sw      t0, 0x14(a4)
    // the other master still holds SDA low: a START now is lost at once
    lw      t0, 0x14(a4)
    CHECK   t0, ST_BUSY
    li      t0, I2C_START | I2C_WRITE
    sw      t0, 0x10(a4)
    I2C_WAIT
    lw      t0, 0x14(a4)
    CHECK   t0, ST_AL | ST_BUSY
    li      t0, ST_AL
    sw      t0, 0x14(a4)
1:  lw      t0, 0x14(a4)                // until the other master's STOP
    andi    t0, t0, ST_BUSY
    bnez    t0, 1b
    I2C_TX  0x90, I2C_START | I2C_STOP  // recovered
    lw      t0, 0x14(a4)
    CHECK   t0, ST_DONE
    li      t0, ST_DONE
    sw      t0, 0x14(a4)

    // ---- START with SDA stuck low (no START seen, bus not busy) ----
    SIM     SIM_I2C_HOG_SDA + 5
5:  lw      t0, 0(a5)                   // pins: SCL high, SDA low
    andi    t0, t0, 3
    addi    t0, t0, -1
    bnez    t0, 5b
    li      t0, I2C_START
    sw      t0, 0x10(a4)
    I2C_WAIT
    lw      t0, 0x14(a4)
    CHECK   t0, ST_AL                   // lost in the START itself, not busy
    li      t0, ST_AL
    sw      t0, 0x14(a4)
6:  lw      t0, 0(a5)                   // until the lines are released
    andi    t0, t0, 3
    addi    t0, t0, -3
    bnez    t0, 6b

    // ---- START while another master holds the bus with SDA high ----
    SIM     SIM_I2C_HOG_BUS + 5
7:  lw      t0, 0x14(a4)
    andi    t0, t0, ST_BUSY
    beqz    t0, 7b
8:  lw      t0, 0(a5)                   // both lines high again
    andi    t0, t0, 3
    addi    t0, t0, -3
    bnez    t0, 8b
    li      t0, I2C_START
    sw      t0, 0x10(a4)
    I2C_WAIT
    lw      t0, 0x14(a4)
    CHECK   t0, ST_AL | ST_BUSY         // lost at once: the bus is not ours
    li      t0, ST_AL
    sw      t0, 0x14(a4)
9:  lw      t0, 0x14(a4)                // until its STOP
    andi    t0, t0, ST_BUSY
    bnez    t0, 9b

    // ---- 400 kHz: START + byte + STOP = 44 quarters of 63 clocks ----
    // PRESC = 62: quarter = 63 clocks, f_SCL = 100 MHz / 252 = 397 kHz.
    // Lower bound: START 4 + 9 bits x 4 + STOP 4 = 44 quarters = 2772.
    // Slack: each of the 10 SCL releases from low (9 bit clocks + STOP)
    // holds the counter for the 2-FF SCL synchroniser (~2-3 clocks, ~30),
    // plus the CMD store, the event cycle, one STATUS poll iteration and
    // the csrr pair under WAIT=3 (~60). Upper bound 2772 + 149 = 2921.
    li      t0, 62
    sw      t0, 0x04(a4)
    li      t0, 0x90
    sw      t0, 0x08(a4)
    csrr    s5, mcycle
    li      t0, I2C_START | I2C_WRITE | I2C_STOP
    sw      t0, 0x10(a4)
    I2C_WAIT
    csrr    t1, mcycle
    sub     t1, t1, s5
    li      t2, 2772
    sub     t1, t1, t2
    sltiu   t1, t1, 150                 // 2772 .. 2921 (sync + polling slack)
    CHECK   t1, 1
    li      t0, 4
    sw      t0, 0x04(a4)
    li      t0, ST_DONE
    sw      t0, 0x14(a4)

    // ---- IE = 0: DONE does not reach the PLIC ----
    I2C_TX  0x90, I2C_START | I2C_STOP
    li      t1, PLIC_BASE + 0x1000
    lw      t0, 0(t1)
    CHECK   t0, 0
    li      t0, ST_DONE
    sw      t0, 0x14(a4)

    // ---- DONE interrupt through the PLIC (source 3) ----
    li      t0, 1
    sw      t0, 0x18(a4)                // IE: DONE
    li      t0, 2
    sw      t0, 12(a6)                  // priority[3] = 2
    li      t0, 8
    li      t1, PLIC_BASE + 0x2000
    sw      t0, 0(t1)                   // enable source 3
    la      t0, i2c_handler
    csrw    mtvec, t0
    li      s6, 0
    li      s9, 0
    li      t0, 0x800
    csrw    mie, t0
    csrsi   mstatus, 8
    li      t0, 0x90
    sw      t0, 0x08(a4)
    li      t0, I2C_START | I2C_WRITE | I2C_STOP
    sw      t0, 0x10(a4)
2:  beqz    s6, 2b
    csrci   mstatus, 8
    CHECK   s6, 1
    CHECK   s9, 3
    li      t1, PLIC_BASE + 0x1000
    lw      t0, 0(t1)
    CHECK   t0, 0
    la      t0, _trap_entry
    csrw    mtvec, t0
    sw      zero, 0x18(a4)

    // ---- pads back to bit-bang ----
    sw      zero, 0x00(a4)
    nop
    nop
    lw      t0, 0(a5)                   // synchronised pins
    CHECK   t0, 3

    // ---- PSLVERR ----
    li      t0, 0x55
    li      a3, I2C_BASE + 0x20
e1: lw      t0, 0(a3)
    CHECK   t0, 0x55
    CHECK_TRAP 5, e1, 0xC0003020

    TEST_END

    .text
    .balign 4
i2c_handler:
    lw      s9, 4(a7)                   // claim
    li      t2, ST_DONE
    sw      t2, 0x14(a4)                // W1C DONE: the I2C irq drops
    sw      s9, 4(a7)                   // complete
    addi    s6, s6, 1
    mret
