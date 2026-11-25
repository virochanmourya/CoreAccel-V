// boot_imem — boot ROM test: boot mode 1: no load, the ROM jumps to the preloaded IMEM.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     3
#define BOOT_MODE_EXP 1
#include "boot_prog.S"
