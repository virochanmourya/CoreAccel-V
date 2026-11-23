/* CoreAccel-V directed-test link script (Harvard map)
 *   IMEM 0x0000_0000  8 KB  .text only
 *   TCM  0x8000_0000  4 KB  .rodata, .data, .bss, stack (VMA = LMA)
 * .expected is a non-loaded section holding the expected signature.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    TCM  (rwx) : ORIGIN = 0x80000000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > IMEM

    .rodata : {
        *(.rodata .rodata.* .srodata .srodata.*)
    } > TCM

    .data : {
        *(.data .data.* .sdata .sdata.*)
    } > TCM

    .bss (NOLOAD) : {
        *(.bss .bss.* .sbss .sbss.* COMMON)
    } > TCM

    _stack_top = ORIGIN(TCM) + LENGTH(TCM);

    .expected 0 (INFO) : { KEEP(*(.expected)) }
}
