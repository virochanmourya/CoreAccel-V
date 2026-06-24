/* ============================================================================
 * ads1115_driver.c — ADS1115 I2C Bit-Bang Driver for CoreAccel-V
 *
 * All I2C transactions are bit-banged through the GPIO MMIO register at
 * 0xC000_0000. The open-drain tristate buffers in the RTL handle the
 * physical signaling (write 1 = high-Z, write 0 = drive low).
 *
 * I2C timing is calibrated for Fast-mode (400 kHz) on a 100 MHz CPU.
 * Quarter-period delay = 100MHz / (4 * 400kHz) = 62.5 cycles ≈ 63 NOPs.
 * We use a conservative 125-cycle half-period for reliability.
 * ============================================================================ */

#include "ads1115_driver.h"
#include "gpio.h"

/* ---- I2C Timing Delays ----
 * At 100 MHz, each NOP ≈ 1-2 cycles (depends on pipeline).
 * For ~400 kHz I2C: half-period ≈ 1.25 µs = 125 cycles.
 * For 100 kHz I2C (Standard Mode): half-period = 5.0 µs = 500 cycles.
 * We set the loop to 100 iterations (100 * 5 = 500 cycles).
 * We use a loop-based delay for precise control. */
static void i2c_delay(void) {
    /* ~125 CPU cycles at 100 MHz → ~1.25 µs half-period → ~400 kHz */
    for (volatile int i = 0; i < 100; i++) { __asm__ volatile(""); }
}

/* ---- I2C Primitives ---- */

static void i2c_start(void) {
    i2c_sda_high(); i2c_delay();
    i2c_scl_high(); i2c_delay();
    i2c_sda_low();  i2c_delay();   /* SDA ↓ while SCL HIGH = START */
    i2c_scl_low();  i2c_delay();
}

static void i2c_stop(void) {
    i2c_sda_low();  i2c_delay();
    i2c_scl_high(); i2c_delay();
    i2c_sda_high(); i2c_delay();   /* SDA ↑ while SCL HIGH = STOP */
}

/* Transmit 8 bits MSB-first, return ACK (0=ACK, 1=NACK) */
static int i2c_write_byte(uint8_t byte) {
    for (int bit = 7; bit >= 0; bit--) {
        if (byte & (1 << bit)) i2c_sda_high();
        else                   i2c_sda_low();
        i2c_delay();
        i2c_scl_high(); i2c_delay();
        i2c_scl_low();  i2c_delay();
    }
    /* Read ACK: release SDA, clock SCL, read SDA */
    i2c_sda_high(); i2c_delay();
    i2c_scl_high(); i2c_delay();
    int ack = i2c_sda_read();
    i2c_scl_low();  i2c_delay();
    return ack;  /* 0 = ACK received */
}

/* Receive 8 bits MSB-first, send ACK or NACK */
static uint8_t i2c_read_byte(int send_ack) {
    uint8_t byte = 0;
    i2c_sda_high();  /* Release SDA for slave to drive */
    for (int bit = 7; bit >= 0; bit--) {
        i2c_delay();
        i2c_scl_high(); i2c_delay();
        if (i2c_sda_read()) byte |= (1 << bit);
        i2c_scl_low();
    }
    /* Send ACK (SDA LOW) or NACK (SDA HIGH) */
    if (send_ack) i2c_sda_low();
    else          i2c_sda_high();
    i2c_delay();
    i2c_scl_high(); i2c_delay();
    i2c_scl_low();  i2c_delay();
    i2c_sda_high();
    return byte;
}

/* ---- ADS1115 Register Access ---- */

/* Write a 16-bit value to an ADS1115 register */
static void ads1115_write_reg(uint8_t reg, uint16_t value) {
    i2c_start();
    i2c_write_byte((ADS1115_ADDR << 1) | 0);   /* Addr + Write */
    i2c_write_byte(reg);                        /* Register pointer */
    i2c_write_byte((uint8_t)(value >> 8));       /* MSB */
    i2c_write_byte((uint8_t)(value & 0xFF));     /* LSB */
    i2c_stop();
}

/* Read a 16-bit value from the current register pointer */
static int16_t ads1115_read_reg(void) {
    int16_t result;
    i2c_start();
    i2c_write_byte((ADS1115_ADDR << 1) | 1);   /* Addr + Read */
    uint8_t hi = i2c_read_byte(1);              /* MSB + ACK */
    uint8_t lo = i2c_read_byte(0);              /* LSB + NACK */
    i2c_stop();
    result = (int16_t)((hi << 8) | lo);
    return result;
}

/* ---- Public API ---- */
/* Updated I2C Addresses for ADDR pin tied to GND */
#define ADS1115_ADDR_WRITE 0x90
#define ADS1115_ADDR_READ  0x91

void ads1115_init(void) {
    /* Set both I2C lines idle (high-Z) */
    gpio_write(GPIO_SCL | GPIO_SDA);

    /* Small power-on delay (~10ms) */
    for (volatile int i = 0; i < 250000; i++) { __asm__ volatile(""); }

    /* 1. Write the new Single-Ended Configuration */
    i2c_start();
    i2c_write_byte(ADS1115_ADDR_WRITE);
    i2c_write_byte(0x01); /* Point to Config Register */
    i2c_write_byte(0xC2); /* MSB: OS=1 (start), MUX=100 (AIN0-GND), PGA=001 (±4.096V), MODE=0 */
    i2c_write_byte(0xA3); /* LSB: DR=101 (250 SPS), COMP=disabled */
    i2c_stop();

    /* 2. Reset the internal pointer to the Conversion Data Register */
    i2c_start();
    i2c_write_byte(ADS1115_ADDR_WRITE);
    i2c_write_byte(0x00); /* Point to Conversion Register */
    i2c_stop();
}

int16_t ads1115_read(void) {
    return ads1115_read_reg();
}
