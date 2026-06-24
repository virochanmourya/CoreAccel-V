/* ============================================================================
 * ads1115_driver.h — ADS1115 16-Bit ADC I2C Driver (Bit-Banged)
 *
 * Target: ADS1115 connected to AD8232 ECG analog front-end
 * Interface: Software I2C via GPIO MMIO at 0xC000_0000
 * I2C Address: 0x48 (ADDR pin tied to GND)
 * ============================================================================ */

#ifndef ADS1115_DRIVER_H
#define ADS1115_DRIVER_H

#include <stdint.h>

#define SYS_CLK_FREQ    100000000   /* 100 MHz CPU clock */

/* ADS1115 I2C slave address (7-bit, ADDR=GND) */
#define ADS1115_ADDR    0x48

/* ADS1115 register pointer values */
#define ADS1115_REG_CONVERSION  0x00
#define ADS1115_REG_CONFIG      0x01

/* ADS1115 config register fields:
 * Bit 15:    OS   = 1 (start single-shot / no effect in continuous)
 * Bit 14-12: MUX  = 000 (AINp=AIN0, AINn=AIN1, differential)
 * Bit 11-9:  PGA  = 001 (±4.096V — matches AD8232 output range)
 * Bit 8:     MODE = 0 (Continuous conversion)
 * Bit 7-5:   DR   = 100 (128 SPS) or 101 (250 SPS)
 * Bit 4:     COMP_MODE = 0
 * Bit 3:     COMP_POL  = 0
 * Bit 2:     COMP_LAT  = 0
 * Bit 1-0:   COMP_QUE  = 11 (disable comparator)
 */
#define ADS1115_CONFIG_250SPS   0xC2A3  /* Continuous, AIN0-AIN1, ±4.096V, 250SPS */

/* Initialize the ADS1115 for continuous conversion at 250 SPS */
void ads1115_init(void);

/* Read the latest 16-bit conversion result (blocking I2C read) */
int16_t ads1115_read(void);

#endif /* ADS1115_DRIVER_H */
