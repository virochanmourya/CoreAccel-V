// boot_magic — boot ROM test: a bad byte before the magic: ERR 0xE1, RX flushed, then a normal load.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     2
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
