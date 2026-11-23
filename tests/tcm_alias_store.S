// tcm_alias_store — a store just past the 4 KB TCM (0x8000_1000) is unmapped:
// it must raise dbus_error AND leave TCM unchanged. Today the EX-stage write
// enable decodes only addr[31:30], so the store also lands on the aliased TCM
// word 0 (tracked in known_failures.txt until the EX-stage fault check exists).
#include "test.h"

    EXPECT_DBUS_ERRORS 1

    .data
    .balign 4
w0:     .word 0x600dda7a            // first .data word = TCM word 0

    TEST_BEGIN
    la      a0, w0
    li      a1, 0x80001000          // aliases TCM word 0 under addr[11:2]
    li      t0, 0xbadbad00
    sw      t0, 0(a1)
    nop
    nop
    lw      t1, 0(a0)
    CHECK   t1, 0x600dda7a
    TEST_END
