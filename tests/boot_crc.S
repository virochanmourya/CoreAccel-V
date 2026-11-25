// boot_crc — boot ROM test: one corrupted CRC byte: exactly one NAK, then the resent frame is accepted.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     1
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
