/* ============================================================================
 * CoreAccel-V Bare-Metal Linker Script (Harvard Architecture)
 *
 * CRITICAL: This is a Harvard architecture. The data bus CANNOT read from
 * Instruction Memory, so every object the program reads as data lives in TCM.
 *
 * Memory map:
 *   IMEM  0x0000_0000  8 KB   .text only (crt0 _start first)
 *   TCM   0x8000_0000  4 KB   the ONLY data memory:
 *                               .rodata  (incl. .srodata*)
 *                               .data    (incl. .sdata*)
 *                               .bss     (incl. .sbss*, COMMON)
 *                               stack    (grows down from top of TCM)
 *   No DMEM region exists.
 *
 * .rodata and .data use VMA = LMA in TCM (no AT>, no copy loop). The build
 * tool (scripts/elf2hex.py, run by `make fw`) splits the ELF into
 *   build/fw/imem.hex   loaded into IMEM by hardware
 *   build/fw/tcm.hex    preloaded into TCM by hardware
 * ============================================================================ */

MEMORY
{
    IMEM  (rx)  : ORIGIN = 0x00000000, LENGTH = 8K    /* 2048 × 32-bit ROM, instruction bus  */
    TCM   (rw)  : ORIGIN = 0x80000000, LENGTH = 4K    /* 1024 × 32-bit BRAM, data bus only   */
    /* GPIO MMIO at 0xC0000000 — accessed via volatile pointer, not a linker region */
}

ENTRY(_start)

SECTIONS
{
    /* ==================================================================
     * .text — Code only, in Instruction BRAM (IMEM)
     * ================================================================== */
    .text : {
        . = ALIGN(4);
        *(.text.init)            /* crt0.S _start MUST be at 0x00000000 */
        *(.text .text.*)
        . = ALIGN(4);
    } > IMEM

    /* ==================================================================
     * .rodata — Read-only constants in TCM (VMA = LMA, preloaded)
     * ================================================================== */
    .rodata : {
        . = ALIGN(4);
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > TCM

    /* ==================================================================
     * .data — Initialized globals in TCM
     *
     * HARVARD NOTE: No AT() LMA. These are placed directly at their
     * TCM VMA. The build system extracts this section into tcm.hex
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
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end = .;
    } > TCM

    /* ==================================================================
     * Stack — grows downward from TCM top (0x80001000)
     * ================================================================== */
    _stack_top = ORIGIN(TCM) + LENGTH(TCM);

    /* Sanity: .rodata + .data + .bss must leave at least 256B for the stack */
    ASSERT(_ebss <= ORIGIN(TCM) + LENGTH(TCM) - 256,
           "ERROR: TCM overflow — .rodata/.data/.bss collide with stack!")
}
