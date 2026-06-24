#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

#define GPIO_BASE   ((volatile uint32_t *)0xC0000000)

#define GPIO_SCL    (1u << 0)
#define GPIO_SDA    (1u << 1)

/* ---- Shadow Register ----
 * CRITICAL: The I2C helpers must NOT use gpio_read() for read-modify-write.
 *
 * gpio_read() returns the PHYSICAL pin state. When a slave pulls SDA LOW
 * (for ACK or data), gpio_read() sees SDA=0. If we then OR in GPIO_SCL,
 * we write back SDA=0, which makes the FPGA DRIVE SDA LOW — taking over
 * from the slave and locking the bus.
 *
 * Fix: Track the INTENDED output state in a shadow register. The helpers
 * modify the shadow and write it to hardware. gpio_read() is ONLY used
 * for reading the actual pin state (i2c_sda_read).
 */
static uint32_t gpio_shadow = 0x03;  /* Both lines idle (released) */

/* Write SCL and SDA simultaneously, update shadow */
static inline void gpio_write(uint32_t val) {
    gpio_shadow = val;
    *GPIO_BASE = val;
}

/* Read current PHYSICAL pin state (for SDA data/ACK detection only) */
static inline uint32_t gpio_read(void) {
    return *GPIO_BASE;
}

/* I2C helpers — use shadow register, NOT physical pin readback */
static inline void i2c_scl_high(void) { gpio_shadow |= GPIO_SCL;  *GPIO_BASE = gpio_shadow; }
static inline void i2c_scl_low(void)  { gpio_shadow &= ~GPIO_SCL; *GPIO_BASE = gpio_shadow; }
static inline void i2c_sda_high(void) { gpio_shadow |= GPIO_SDA;  *GPIO_BASE = gpio_shadow; }
static inline void i2c_sda_low(void)  { gpio_shadow &= ~GPIO_SDA; *GPIO_BASE = gpio_shadow; }

/* Read SDA from the PHYSICAL pin — the only place we use gpio_read() */
static inline int  i2c_sda_read(void) { return (gpio_read() >> 1) & 1; }

#endif
