/* CoreAccel-V boot ROM link script: 4 KB at 0x0001_0000, .text only.
 * The loader keeps everything in registers: no .data, .bss or stack.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > ROM

    /DISCARD/ : { *(.data .data.* .sdata .sdata.* .bss .bss.* .sbss .sbss.* .rodata .rodata.* .srodata .srodata.* COMMON) }
}
