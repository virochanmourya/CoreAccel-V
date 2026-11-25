// ============================================================================
// Shared body of the boot tests (tests/boot_*.S), run in the BOOT=rom
// snapshot: the boot ROM loads this program over UART0 (or, BOOT_CASE 3,
// finds it preloaded and jumps to it). The includer defines BOOT_CASE and
// BOOT_MODE_EXP (the boot-mode strap the program expects to read back).
//
// Checks: the program and its .data arrived (code runs, a .data word reads
// back), the strap value, and the IMEM window: a word written through it is
// fetched and executed, a partial (sb) write and a read of the window are
// refused (SLVERR -> access fault), and the boot ROM is not readable as data
// (DECERR -> access fault).
// ============================================================================
#define SIG_WORDS 16
#include "test.h"

#define IMEM_WIN   0x10000000
#define PATCH_ADDR 0x1F00              // free IMEM word for the window test

    .globl  test_boot_rom
    .set    test_boot_rom, 1
    .globl  test_boot_case
    .set    test_boot_case, BOOT_CASE
    .globl  test_timeout
    .set    test_timeout, 1000000
#if BOOT_MODE_EXP
    .globl  test_boot_mode
    .set    test_boot_mode, BOOT_MODE_EXP
#endif
    EXPECT_DBUS_ERRORS 3

    .data
    .balign 4
boot_data: .word 0x600DF00D

    TEST_BEGIN
    li      a0, 5
    addi    a0, a0, 7
    CHECK   a0, 12

    LA_ABS  t0, boot_data           // .data came in a TCM frame
    lw      a1, 0(t0)
    CHECK   a1, 0x600DF00D

    li      t0, SYSCTL_BASE         // boot-mode strap as the loader saw it
    lw      a2, 8(t0)
    andi    a2, a2, 3
    CHECK   a2, BOOT_MODE_EXP

    // IMEM window: write "addi a0, zero, 0x55; ret" at PATCH_ADDR and call it
    li      t0, IMEM_WIN + PATCH_ADDR
    li      t1, 0x05500513
    sw      t1, 0(t0)
    li      t1, 0x00008067
    sw      t1, 4(t0)
    li      a0, 0
    li      t2, PATCH_ADDR
    jalr    ra, 0(t2)
    CHECK   a0, 0x55

    // a byte write through the window is refused (store access fault) and
    // leaves the word alone: the patch still returns 0x55
    li      t0, IMEM_WIN + PATCH_ADDR
    li      t1, 0x77
    sb      t1, 1(t0)
    li      a0, 0
    li      t2, PATCH_ADDR
    jalr    ra, 0(t2)
    CHECK   a0, 0x55

    // the window cannot be read, nor the boot ROM (load access faults: rd unchanged)
    li      t0, IMEM_WIN + PATCH_ADDR
    li      a3, 0x1234
    lw      a3, 0(t0)
    CHECK   a3, 0x1234
    li      t0, 0x00010000
    li      a4, 0x5678
    lw      a4, 0(t0)
    CHECK   a4, 0x5678

    TEST_END
