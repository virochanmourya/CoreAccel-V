// boot_range — boot ROM test: a frame outside IMEM/TCM gets ERR 0xE3, then resync and a normal load.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     5
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
