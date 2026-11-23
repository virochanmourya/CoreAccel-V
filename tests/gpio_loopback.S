// gpio_loopback — B3: open-drain SCL/SDA. Writing 0 drives a line low,
// writing 1 releases it to the testbench pull-up; the input register must
// reflect the pin. NOPs leave room for an input synchroniser.
#include "test.h"

#define GPIO_ADDR 0xC0000000

.macro GPIO_SET val, exp
    li      t0, \val
    sw      t0, 0(a0)
    nop
    nop
    nop
    nop
    lw      t1, 0(a0)
    CHECK   t1, \exp
.endm

    TEST_BEGIN
    li      a0, GPIO_ADDR
    GPIO_SET 0, 0                   // both low
    GPIO_SET 3, 3                   // both released (pulled up)
    GPIO_SET 1, 1                   // SCL released, SDA low
    GPIO_SET 2, 2                   // SCL low, SDA released
    GPIO_SET 3, 3
    TEST_END
