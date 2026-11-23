// tcm_alias_store — stores outside the 4 KB TCM window must raise a data-bus
// error and write nothing, even when their low address bits alias a TCM word.
// The last valid TCM word (0x8000_0FFC) must still work normally.
#include "test.h"

    EXPECT_DBUS_ERRORS 2

    .data
    .balign 4
w0:     .word 0x600dda7a            // first .data word = TCM word 0

    TEST_BEGIN
    la      a0, w0

    li      a1, 0x80001000          // just past TCM; aliases word 0 on [11:2]
    li      t0, 0xbadbad00
    sw      t0, 0(a1)
    nop
    nop
    lw      t1, 0(a0)
    CHECK   t1, 0x600dda7a

    li      a2, 0x80000ffc          // last TCM word: in range
    li      t2, 0x1a571a57
    sw      t2, 0(a2)
    nop
    lw      t3, 0(a2)
    CHECK   t3, 0x1a571a57

    li      a3, 0x7ffffffc          // just below TCM; aliases word 1023
    li      t4, 0xbadbad01
    sw      t4, 0(a3)
    nop
    nop
    lw      t5, 0(a2)
    CHECK   t5, 0x1a571a57

    TEST_END
