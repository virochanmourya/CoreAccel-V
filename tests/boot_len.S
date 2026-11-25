// boot_len — boot ROM test: frames longer than 4096 bytes or running past the end of IMEM/TCM get ERR 0xE3, then a normal load.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     6
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
