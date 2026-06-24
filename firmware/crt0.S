# ===========================================================================
# crt0.S — CoreAccel-V Bare-Metal Boot Sequence (Harvard Architecture)
#
# Executed at reset (PC = 0x00000000). This code:
#   1. Initializes the stack pointer (sp/x2) to TCM top
#   2. Initializes the global pointer (gp/x3) for linker relaxation
#   3. Zeroes the .bss section in TCM
#   4. Zeroes the .fast_scratchpad section in DMEM
#   5. Calls main()
#   6. Enters a diagnostic halt loop if main() returns
#
# NOTE: No .data copy. On this Harvard architecture, the CPU data bus
# cannot reach IMEM. Initialized data is pre-loaded into TCM BRAM via
# $readmemh("tcm_init.hex") at FPGA configuration time.
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
    # Step 4: Zero .fast_scratchpad section in DMEM
    # Same ALIGN(4) guarantee from linker script.
    # ================================================================
    lui     a0, %hi(_s_scratchpad)
    addi    a0, a0, %lo(_s_scratchpad)
    lui     a1, %hi(_e_scratchpad)
    addi    a1, a1, %lo(_e_scratchpad)

.Lzero_scratch:
    bge     a0, a1, .Lzero_scratch_done
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       .Lzero_scratch
.Lzero_scratch_done:

    # ================================================================
    # Step 5: Call main()
    # ================================================================
    jal     ra, main

    # ================================================================
    # Step 6: Halt — main() should never return in bare-metal
    #
    # Write a diagnostic signature to DMEM[0] so we can detect this
    # condition on the logic analyzer or via debug_wb LEDs.
    # ================================================================
    lui     t0, 0xDEAD0         # t0 = 0xDEAD0000
    addi    t0, t0, 0x10        # t0 = 0xDEAD0010 (arbitrary sentinel)
    lui     t1, %hi(0x00010000) # t1 = DMEM base
    sw      t0, 0(t1)           # Write sentinel to DMEM[0]

.Lhalt:
    j       .Lhalt              # Spin forever

    .size   _start, . - _start
