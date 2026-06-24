/* ============================================================================
 * CoreAccel-V Bare-Metal Linker Script (Harvard Architecture)
 *
 * CRITICAL: This is a Harvard architecture. The CPU data bus CANNOT read
 * from Instruction Memory. All initialized data must be placed directly
 * at its VMA — runtime LMA→VMA copies are physically impossible.
 *
 * Initialized data (.data) is baked into tcm_init.hex at build time.
 * The FPGA loads it via $readmemh at configuration.
 * ============================================================================ */

MEMORY
{
    IMEM  (rx)  : ORIGIN = 0x00000000, LENGTH = 8K    /* 1024 × 32-bit BRAM   */
    DMEM  (rw)  : ORIGIN = 0x00010000, LENGTH = 256   /* 64 × 32-bit LUTRAM   */
    TCM   (rw)  : ORIGIN = 0x80000000, LENGTH = 4K    /* 1024 × 32-bit BRAM   */
    /* GPIO MMIO at 0xC0000000 — accessed via volatile pointer, not a linker region */
}

ENTRY(_start)

SECTIONS
{
    /* ==================================================================
     * .text — Code segment in Instruction BRAM
     * ================================================================== */
    .text : {
        . = ALIGN(4);
        *(.text.init)            /* crt0.S _start MUST be at 0x00000000 */
        *(.text .text.*)
        *(.rodata .rodata.*)     /* Read-only constants co-located with code */
        . = ALIGN(4);
    } > IMEM

    /* ==================================================================
     * .fast_scratchpad — Latency-critical variables in DMEM (LUTRAM)
     *
     * DMEM has COMBINATIONAL read (0-cycle latency) vs. TCM's
     * synchronous BRAM read (1-cycle). Use this for tight-loop flags
     * and ISR state that must be read in the same cycle as the LW.
     * ================================================================== */
    .fast_scratchpad (NOLOAD) : {
        . = ALIGN(4);
        _s_scratchpad = .;
        *(.fast_scratchpad .fast_scratchpad.*)
        . = ALIGN(4);
        _e_scratchpad = .;
    } > DMEM

    /* Sanity: ensure scratchpad doesn't overflow DMEM */
    ASSERT((_e_scratchpad - _s_scratchpad) <= 256,
           "ERROR: .fast_scratchpad exceeds 256-byte DMEM limit!")

    /* ==================================================================
     * .data — Initialized globals in TCM
     *
     * HARVARD NOTE: No AT() LMA. These are placed directly at their
     * TCM VMA. The build system extracts this section into tcm_init.hex
     * for $readmemh loading at FPGA configuration time.
     * ================================================================== */
    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _edata = .;
    } > TCM

    /* ==================================================================
     * Global Pointer anchor — MUST be in .sdata range
     *
     * GCC linker relaxation converts lui/addi pairs for globals within
     * ±2048 bytes of __global_pointer$ into single gp-relative loads
     * (e.g., lw a0, offset(gp)). This saves 1 instruction per access.
     *
     * Place gp at _sdata + 0x800 to center the ±2KB window over the
     * most frequently accessed .sdata/.sbss variables.
     * ================================================================== */
    PROVIDE(__global_pointer$ = _sdata + 0x800);

    /* ==================================================================
     * .bss — Uninitialized globals in TCM (zeroed by crt0.S)
     *
     * ALIGN(4) on BOTH boundaries prevents misaligned-store exceptions
     * when crt0.S uses 32-bit sw instructions to zero this region.
     * ================================================================== */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _sbss = .;
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end = .;
    } > TCM

    /* ==================================================================
     * Stack — grows downward from TCM top
     * ================================================================== */
    _stack_top = ORIGIN(TCM) + LENGTH(TCM);   /* 0x80001000 */

    /* Sanity: .data + .bss must leave room for 256B stack minimum */
    ASSERT(_ebss <= (_stack_top - 256),
           "ERROR: TCM overflow — .data + .bss collides with stack!")
}
