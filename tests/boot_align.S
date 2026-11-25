// boot_align — boot ROM test: a misaligned frame address and a misaligned frame length each get ERR 0xE3, then a normal load.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     7
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
