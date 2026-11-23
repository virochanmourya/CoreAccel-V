#ifndef MAC_INTRINSICS_H
#define MAC_INTRINSICS_H

#include <stdint.h>

/* ---- CUSTOM-0 opcode: 0x0B (0001011) ----
 * Encoding: funct7[6:0] | rs2[4:0] | rs1[4:0] | funct3[2:0] | rd[4:0] | opcode[6:0]
 *
 *   MAC rs1, rs2            → funct3=000: acc += rs1 * TCM[rs2]  (holds EX 5 cycles)
 *   MAC_CLEAR               → funct3=001: acc = 0, sticky overflow = 0
 *   (reserved)              → funct3=010
 *   MAC_READ_LO rd          → funct3=011: rd = sat64(acc)[31:0]
 *   MAC_READ_HI rd          → funct3=100: rd = sat64(acc)[63:32]
 *   MAC_READ_SHIFT rd, rs1  → funct3=101: rd = sat32(round_half_up(acc >>> rs1[5:0]))  (holds EX 4 cycles)
 *   MAC_READ_STATUS rd      → funct3=110: rd[0] = sticky overflow, rd[31:1] = 0
 *   (reserved)              → funct3=111
 *
 * funct7 = 0 for all instructions.
 * MAC_READ_LO/HI saturate the 72-bit acc to signed 64-bit (no wraparound).
 * Sticky overflow flag: set when acc saturates, or when MAC_READ_LO/HI or
 * MAC_READ_SHIFT saturates its result. Cleared only by MAC_CLEAR.
 */

/* MAC rs1, rs2: accumulate += rs1 * TCM[rs2_as_addr] */
#define mac_multiply_accumulate(data_val, tcm_addr)                \
    do {                                                            \
        register uint32_t _a __asm__("a0") = (uint32_t)(data_val); \
        register uint32_t _b __asm__("a1") = (uint32_t)(tcm_addr); \
        __asm__ volatile (                                          \
            ".insn r 0x0B, 0, 0, x0, %0, %1"                      \
            : /* no output */                                       \
            : "r"(_a), "r"(_b)                                     \
            : /* no clobber */                                      \
        );                                                          \
    } while (0)

/* MAC_CLEAR: zero the accumulator and overflow flag */
#define mac_clear()                                                 \
    __asm__ volatile (".insn r 0x0B, 1, 0, x0, x0, x0")

/* MAC_READ_LO: read accumulator[31:0] into a C variable */
#define mac_read_lo(dest)                                           \
    do {                                                            \
        uint32_t _tmp;                                              \
        __asm__ volatile (                                          \
            ".insn r 0x0B, 3, 0, %0, x0, x0"                      \
            : "=r"(_tmp)                                            \
        );                                                          \
        (dest) = _tmp;                                              \
    } while (0)

/* MAC_READ_HI: read accumulator[63:32] into a C variable */
#define mac_read_hi(dest)                                           \
    do {                                                            \
        uint32_t _tmp;                                              \
        __asm__ volatile (                                          \
            ".insn r 0x0B, 4, 0, %0, x0, x0"                      \
            : "=r"(_tmp)                                            \
        );                                                          \
        (dest) = _tmp;                                              \
    } while (0)

/* MAC_READ_SHIFT rs1: rd = sat32(round_half_up(acc >>> shift[5:0])).
 * Returns int32_t. Shift 15 gives Q15, shift 31 gives Q31. Holds EX for 4 cycles. */
#define mac_read_shift(shift)                                       \
    ({                                                              \
        int32_t _res;                                               \
        __asm__ volatile (                                          \
            ".insn r 0x0B, 5, 0, %0, %1, x0"                        \
            : "=r"(_res)                                            \
            : "r"((uint32_t)(shift))                                \
        );                                                          \
        _res;                                                       \
    })

/* MAC_READ_STATUS: rd[0] = sticky overflow flag, rd[31:1] = 0 */
#define mac_read_status()                                           \
    ({                                                              \
        uint32_t _sts;                                              \
        __asm__ volatile (                                          \
            ".insn r 0x0B, 6, 0, %0, x0, x0"                        \
            : "=r"(_sts)                                            \
        );                                                          \
        _sts;                                                       \
    })

/* Convenience: Q15 / Q31 readback via MAC_READ_SHIFT */
#define mac_read_q15()  mac_read_shift(15)
#define mac_read_q31()  mac_read_shift(31)

/* ---- High-level helper: FIR filter using MAC ----
 * Computes: sum += coeff[i] * sample[i] for i in [0, n_taps)
 * Coefficients MUST be pre-loaded in TCM at tcm_base_addr.
 * Returns lower 32 bits (Q15 result after shift).
 */
static inline int32_t mac_fir_filter(
    const int32_t *samples,     /* Pointer to sample buffer (in TCM) */
    uint32_t tcm_coeff_base,    /* TCM byte address of first coefficient */
    uint32_t n_taps)
{
    int32_t result;

    mac_clear();

    for (uint32_t i = 0; i < n_taps; i++) {
        mac_multiply_accumulate(samples[i], tcm_coeff_base + (i << 2));
    }

    mac_read_lo(result);
    return result >> 15;  /* Q15 descale */
}

#endif
