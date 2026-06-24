/* ============================================================================
 * seg_driver.c — CoreAccel-V 7-Segment Display Driver
 *
 * Converts a base-10 integer into packed BCD and writes it to the
 * hardware 7-segment MMIO register at 0xC000_0008.
 *
 * The hardware's hex decoder maps each 4-bit nibble to segments:
 *   nibble 0x0 → displays "0"
 *   nibble 0x7 → displays "7"
 *   nibble 0x2 → displays "2"
 *
 * So to display the decimal number 72 on a hex decoder, the firmware
 * must write 0x0072 (not 0x0048 which is 72 in hex). This is what
 * the binary-to-BCD conversion below achieves.
 *
 * Example:
 *   seg_display_int(72)  → writes 0x0072 → displays "0072"
 *   seg_display_int(120) → writes 0x0120 → displays "0120"
 * ============================================================================ */

#include "seg_driver.h"

/* ---- Convert unsigned integer to packed BCD and display ----
 *
 * Packed BCD format for a 4-digit display:
 *   Bits [15:12] = thousands digit (0-9)
 *   Bits [11:8]  = hundreds digit  (0-9)
 *   Bits [7:4]   = tens digit      (0-9)
 *   Bits [3:0]   = ones digit      (0-9)
 *
 * Values > 9999 are clamped to 9999 to prevent display corruption.
 */
void seg_display_int(uint16_t value) {
    if (value > 9999)
        value = 9999;

    /* Extract digits via repeated subtraction — NO division */
    uint16_t thousands = 0;
    while (value >= 1000) { value -= 1000; thousands++; }
    uint16_t hundreds = 0;
    while (value >= 100) { value -= 100; hundreds++; }
    uint16_t tens = 0;
    while (value >= 10) { value -= 10; tens++; }
    uint16_t ones = value;

    uint16_t bcd = (thousands << 12) | (hundreds << 8) | (tens << 4) | ones;
    seg_write_raw(bcd);
}
