// boot_retry — boot ROM test: the first data frame fails its CRC 4 times: 3 NAKs, ERR 0xE2, resync, full reload.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     4
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
