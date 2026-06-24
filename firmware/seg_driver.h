/* ============================================================================
 * seg_driver.h — CoreAccel-V 7-Segment Display Driver
 *
 * MMIO Register: 0xC000_0008
 *   WRITE: Bits 15:0 = 4 BCD/hex digits {d3, d2, d1, d0}
 *          Hardware latches value and refreshes display at 1 kHz.
 *   READ:  Returns currently latched display value.
 *
 * The hardware hex decoder displays raw nibble values (0-F).
 * To show base-10 numbers (like BPM), firmware must convert
 * to packed BCD before writing. E.g., 72 → 0x0072.
 * ============================================================================ */

#ifndef SEG_DRIVER_H
#define SEG_DRIVER_H

#include <stdint.h>

#define SEG_BASE  ((volatile uint32_t *)0xC0000008)

/* Write raw 16-bit hex/BCD value to the display */
static inline void seg_write_raw(uint16_t val) {
    *SEG_BASE = (uint32_t)val;
}

/* Display a base-10 integer (0-9999) on the 7-segment display.
 * Converts to packed BCD so hardware hex decoder shows decimal. */
void seg_display_int(uint16_t value);

/* Display a 4-character hex value directly (no BCD conversion) */
static inline void seg_display_hex(uint16_t value) {
    seg_write_raw(value);
}

/* Blank the display (all segments off) */
static inline void seg_blank(void) {
    /* Writing 0x0000 shows "0000". To truly blank, we'd need
     * a blanking bit in hardware. For now, just show 0. */
    seg_write_raw(0x0000);
}

#endif /* SEG_DRIVER_H */
