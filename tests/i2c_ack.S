// i2c_ack — bit-banged I2C address phase through the GPIO register.
// The testbench I2C target (address 0x48) must ACK by pulling SDA low, and the
// core must read that externally driven level through its pad + synchroniser.
// A different address must NACK (SDA stays high via the pull-up).
#include "test.h"

#define GPIO_ADDR 0xC0000000        // bit0 = SCL, bit1 = SDA; 1 = release

// Write SCL/SDA, then wait long enough for the 2-FF input synchroniser.
.macro I2C_W val
    li      t0, \val
    sw      t0, 0(a0)
    .rept 6
    nop
    .endr
.endm

.macro I2C_START                    // from idle: SDA falls while SCL high
    I2C_W   1
    I2C_W   0
.endm

.macro I2C_STOP                     // SDA rises while SCL high
    I2C_W   0
    I2C_W   1
    I2C_W   3
.endm

.macro I2C_BIT b                    // data set while SCL low, then clock it
    I2C_W   ((\b) << 1)
    I2C_W   (((\b) << 1) | 1)
    I2C_W   ((\b) << 1)
.endm

.macro I2C_BYTE v
    I2C_BIT (((\v) >> 7) & 1)
    I2C_BIT (((\v) >> 6) & 1)
    I2C_BIT (((\v) >> 5) & 1)
    I2C_BIT (((\v) >> 4) & 1)
    I2C_BIT (((\v) >> 3) & 1)
    I2C_BIT (((\v) >> 2) & 1)
    I2C_BIT (((\v) >> 1) & 1)
    I2C_BIT ((\v) & 1)
.endm

// 9th clock: release SDA, raise SCL, sample SDA (0 = ACK), lower SCL.
.macro I2C_ACK_READ reg
    I2C_W   2
    I2C_W   3
    lw      \reg, 0(a0)
    srli    \reg, \reg, 1
    andi    \reg, \reg, 1
    I2C_W   2
.endm

    TEST_BEGIN
    li      a0, GPIO_ADDR
    I2C_W   3

    I2C_START
    I2C_BYTE 0x90                   // 0x48 << 1 | W
    I2C_ACK_READ t1
    I2C_STOP
    CHECK   t1, 0                   // ACK from the target

    I2C_START
    I2C_BYTE 0xA0                   // 0x50 << 1 | W: nobody there
    I2C_ACK_READ t1
    I2C_STOP
    CHECK   t1, 1                   // NACK

    lw      t2, 0(a0)               // bus idle: both lines high
    CHECK   t2, 3

    TEST_END
