#ifndef MAC_INTRINSICS_H
#define MAC_INTRINSICS_H

#include <stdint.h>

/* ---- CUSTOM-0 opcode: 0x0B (0001011) ----
 * Encoding: funct7[6:0] | rs2[4:0] | rs1[4:0] | funct3[2:0] | rd[4:0] | opcode[6:0]
 *
 *   MAC rs1, rs2    → funct3=000: accumulator += rs1 * TCM[rs2]
 *   MAC_CLEAR       → funct3=001: accumulator = 0
 *   MAC_READ_LO rd  → funct3=011: rd = accumulator[31:0]
 *   MAC_READ_HI rd  → funct3=100: rd = accumulator[63:32]
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
