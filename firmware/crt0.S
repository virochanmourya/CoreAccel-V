# ===========================================================================
# crt0.S — CoreAccel-V Bare-Metal Boot Sequence (Harvard Architecture)
#
# Executed at reset (PC = 0x00000000, IMEM). This code:
#   1. Initializes the stack pointer (sp/x2) to TCM top (0x80001000)
#   2. Initializes the global pointer (gp/x3) for linker relaxation
#   3. Zeroes .bss (incl. .sbss/COMMON) in TCM with a word loop
#   4. Calls main()
#   5. Spins forever if main() returns
#
# Memory map: IMEM holds .text only. TCM holds .rodata, .data, .bss and the
# stack; there is no DMEM. .rodata and .data are preloaded into TCM by
# hardware (tcm.hex), so there is no .data copy loop here: the data bus
# cannot reach IMEM.
# ===========================================================================

    .section .text.init, "ax", @progbits
    .global _start
    .type   _start, @function
    .balign 4

_start:
    # ================================================================
    # Step 1: Initialize Stack Pointer
    # SP = top of TCM = 0x80001000
    # ================================================================
    lui     sp, %hi(_stack_top)
    addi    sp, sp, %lo(_stack_top)

    # ================================================================
    # Step 2: Initialize Global Pointer (gp/x3)
    #
    # CRITICAL: Must use .option norelax here. If relaxation is
    # enabled, the assembler will try to convert this lui/addi pair
    # into a gp-relative access — but gp isn't set yet, creating
    # a circular dependency that generates a random address.
    # ================================================================
    .option push
    .option norelax
    lui     gp, %hi(__global_pointer$)
    addi    gp, gp, %lo(__global_pointer$)
    .option pop

    # ================================================================
    # Step 3: Zero .bss section in TCM
    # Both _sbss and _ebss are guaranteed ALIGN(4) by the linker script.
    # ================================================================
    lui     a0, %hi(_sbss)
    addi    a0, a0, %lo(_sbss)
    lui     a1, %hi(_ebss)
    addi    a1, a1, %lo(_ebss)

.Lzero_bss:
    bge     a0, a1, .Lzero_bss_done
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       .Lzero_bss
.Lzero_bss_done:

    # ================================================================
    # Step 4: Call main()
    # ================================================================
    jal     ra, main

    # ================================================================
    # Step 5: main() should never return in bare-metal — spin forever
    # ================================================================
.Lhalt:
    j       .Lhalt              # Spin forever

    .size   _start, . - _start
