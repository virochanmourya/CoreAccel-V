// boot_jump_crc — boot ROM test: the jump frame arrives once with a corrupted entry address: NAK, resend, ACK, then the program runs.
// Body: tests/common/boot_prog.S
#define BOOT_CASE     8
#define BOOT_MODE_EXP 0
#include "boot_prog.S"
