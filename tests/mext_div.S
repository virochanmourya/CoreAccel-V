// mext_div — M extension, DIV/DIVU/REM/REMU, divide by zero and INT_MIN / -1.
// Every op on sign edge cases, plus rd = rs1 / rs2 / both, rd = x0 and x0
// operands. Expected values were computed from a Python model of the RISC-V
// spec semantics.
#include "test.h"

    TEST_BEGIN

    // ---- DIV ----
    li      a0, 0x00000007
    li      a1, 0x00000002
    div     a2, a0, a1
    CHECK   a2, 0x00000003      // div(0x00000007, 0x00000002)
    li      a0, 0xfffffff9
    li      a1, 0x00000002
    div     a2, a0, a1
    CHECK   a2, 0xfffffffd      // div(0xfffffff9, 0x00000002)
    li      a0, 0x00000007
    li      a1, 0xfffffffe
    div     a2, a0, a1
    CHECK   a2, 0xfffffffd      // div(0x00000007, 0xfffffffe)
    li      a0, 0xfffffff9
    li      a1, 0xfffffffe
    div     a2, a0, a1
    CHECK   a2, 0x00000003      // div(0xfffffff9, 0xfffffffe)
    li      a0, 0x00000007
    li      a1, 0x00000000
    div     a2, a0, a1
    CHECK   a2, 0xffffffff      // div(0x00000007, 0x00000000)
    li      a0, 0xfffffff9
    li      a1, 0x00000000
    div     a2, a0, a1
    CHECK   a2, 0xffffffff      // div(0xfffffff9, 0x00000000)
    li      a0, 0x00000000
    li      a1, 0x00000000
    div     a2, a0, a1
    CHECK   a2, 0xffffffff      // div(0x00000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0x00000000
    div     a2, a0, a1
    CHECK   a2, 0xffffffff      // div(0x80000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    div     a2, a0, a1
    CHECK   a2, 0x80000000      // div(0x80000000, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x00000001
    div     a2, a0, a1
    CHECK   a2, 0x80000000      // div(0x80000000, 0x00000001)
    li      a0, 0x80000000
    li      a1, 0x80000000
    div     a2, a0, a1
    CHECK   a2, 0x00000001      // div(0x80000000, 0x80000000)
    li      a0, 0x00000005
    li      a1, 0x80000000
    div     a2, a0, a1
    CHECK   a2, 0x00000000      // div(0x00000005, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    div     a2, a0, a1
    CHECK   a2, 0x00000000      // div(0xffffffff, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    div     a2, a0, a1
    CHECK   a2, 0x00000001      // div(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    div     a2, a0, a1
    CHECK   a2, 0xffffffff      // div(0xffffffff, 0x00000001)
    li      a0, 0xfffffffe
    li      a1, 0xffffffff
    div     a2, a0, a1
    CHECK   a2, 0x00000002      // div(0xfffffffe, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    div     a2, a0, a1
    CHECK   a2, 0xffffffff      // div(0x00000001, 0xffffffff)
    li      a0, 0x00000000
    li      a1, 0x00000005
    div     a2, a0, a1
    CHECK   a2, 0x00000000      // div(0x00000000, 0x00000005)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    div     a2, a0, a1
    CHECK   a2, 0x00000001      // div(0x7fffffff, 0x7fffffff)
    li      a0, 0x12345678
    li      a1, 0x00001234
    div     a2, a0, a1
    CHECK   a2, 0x00010004      // div(0x12345678, 0x00001234)
    li      a0, 0x80000000
    li      a1, 0x00000002
    div     a2, a0, a1
    CHECK   a2, 0xc0000000      // div(0x80000000, 0x00000002)
    li      a0, 0x7fffffff
    li      a1, 0xffffffff
    div     a2, a0, a1
    CHECK   a2, 0x80000001      // div(0x7fffffff, 0xffffffff)

    // ---- DIVU ----
    li      a0, 0x00000007
    li      a1, 0x00000002
    divu    a2, a0, a1
    CHECK   a2, 0x00000003      // divu(0x00000007, 0x00000002)
    li      a0, 0xfffffff9
    li      a1, 0x00000002
    divu    a2, a0, a1
    CHECK   a2, 0x7ffffffc      // divu(0xfffffff9, 0x00000002)
    li      a0, 0x00000007
    li      a1, 0xfffffffe
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0x00000007, 0xfffffffe)
    li      a0, 0xfffffff9
    li      a1, 0xfffffffe
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0xfffffff9, 0xfffffffe)
    li      a0, 0x00000007
    li      a1, 0x00000000
    divu    a2, a0, a1
    CHECK   a2, 0xffffffff      // divu(0x00000007, 0x00000000)
    li      a0, 0xfffffff9
    li      a1, 0x00000000
    divu    a2, a0, a1
    CHECK   a2, 0xffffffff      // divu(0xfffffff9, 0x00000000)
    li      a0, 0x00000000
    li      a1, 0x00000000
    divu    a2, a0, a1
    CHECK   a2, 0xffffffff      // divu(0x00000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0x00000000
    divu    a2, a0, a1
    CHECK   a2, 0xffffffff      // divu(0x80000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0x80000000, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x00000001
    divu    a2, a0, a1
    CHECK   a2, 0x80000000      // divu(0x80000000, 0x00000001)
    li      a0, 0x80000000
    li      a1, 0x80000000
    divu    a2, a0, a1
    CHECK   a2, 0x00000001      // divu(0x80000000, 0x80000000)
    li      a0, 0x00000005
    li      a1, 0x80000000
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0x00000005, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    divu    a2, a0, a1
    CHECK   a2, 0x00000001      // divu(0xffffffff, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    divu    a2, a0, a1
    CHECK   a2, 0x00000001      // divu(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    divu    a2, a0, a1
    CHECK   a2, 0xffffffff      // divu(0xffffffff, 0x00000001)
    li      a0, 0xfffffffe
    li      a1, 0xffffffff
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0xfffffffe, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0x00000001, 0xffffffff)
    li      a0, 0x00000000
    li      a1, 0x00000005
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0x00000000, 0x00000005)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    divu    a2, a0, a1
    CHECK   a2, 0x00000001      // divu(0x7fffffff, 0x7fffffff)
    li      a0, 0x12345678
    li      a1, 0x00001234
    divu    a2, a0, a1
    CHECK   a2, 0x00010004      // divu(0x12345678, 0x00001234)
    li      a0, 0x80000000
    li      a1, 0x00000002
    divu    a2, a0, a1
    CHECK   a2, 0x40000000      // divu(0x80000000, 0x00000002)
    li      a0, 0x7fffffff
    li      a1, 0xffffffff
    divu    a2, a0, a1
    CHECK   a2, 0x00000000      // divu(0x7fffffff, 0xffffffff)

    // ---- REM ----
    li      a0, 0x00000007
    li      a1, 0x00000002
    rem     a2, a0, a1
    CHECK   a2, 0x00000001      // rem(0x00000007, 0x00000002)
    li      a0, 0xfffffff9
    li      a1, 0x00000002
    rem     a2, a0, a1
    CHECK   a2, 0xffffffff      // rem(0xfffffff9, 0x00000002)
    li      a0, 0x00000007
    li      a1, 0xfffffffe
    rem     a2, a0, a1
    CHECK   a2, 0x00000001      // rem(0x00000007, 0xfffffffe)
    li      a0, 0xfffffff9
    li      a1, 0xfffffffe
    rem     a2, a0, a1
    CHECK   a2, 0xffffffff      // rem(0xfffffff9, 0xfffffffe)
    li      a0, 0x00000007
    li      a1, 0x00000000
    rem     a2, a0, a1
    CHECK   a2, 0x00000007      // rem(0x00000007, 0x00000000)
    li      a0, 0xfffffff9
    li      a1, 0x00000000
    rem     a2, a0, a1
    CHECK   a2, 0xfffffff9      // rem(0xfffffff9, 0x00000000)
    li      a0, 0x00000000
    li      a1, 0x00000000
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x00000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0x00000000
    rem     a2, a0, a1
    CHECK   a2, 0x80000000      // rem(0x80000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x80000000, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x00000001
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x80000000, 0x00000001)
    li      a0, 0x80000000
    li      a1, 0x80000000
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x80000000, 0x80000000)
    li      a0, 0x00000005
    li      a1, 0x80000000
    rem     a2, a0, a1
    CHECK   a2, 0x00000005      // rem(0x00000005, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    rem     a2, a0, a1
    CHECK   a2, 0xffffffff      // rem(0xffffffff, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0xffffffff, 0x00000001)
    li      a0, 0xfffffffe
    li      a1, 0xffffffff
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0xfffffffe, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x00000001, 0xffffffff)
    li      a0, 0x00000000
    li      a1, 0x00000005
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x00000000, 0x00000005)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x7fffffff, 0x7fffffff)
    li      a0, 0x12345678
    li      a1, 0x00001234
    rem     a2, a0, a1
    CHECK   a2, 0x00000da8      // rem(0x12345678, 0x00001234)
    li      a0, 0x80000000
    li      a1, 0x00000002
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x80000000, 0x00000002)
    li      a0, 0x7fffffff
    li      a1, 0xffffffff
    rem     a2, a0, a1
    CHECK   a2, 0x00000000      // rem(0x7fffffff, 0xffffffff)

    // ---- REMU ----
    li      a0, 0x00000007
    li      a1, 0x00000002
    remu    a2, a0, a1
    CHECK   a2, 0x00000001      // remu(0x00000007, 0x00000002)
    li      a0, 0xfffffff9
    li      a1, 0x00000002
    remu    a2, a0, a1
    CHECK   a2, 0x00000001      // remu(0xfffffff9, 0x00000002)
    li      a0, 0x00000007
    li      a1, 0xfffffffe
    remu    a2, a0, a1
    CHECK   a2, 0x00000007      // remu(0x00000007, 0xfffffffe)
    li      a0, 0xfffffff9
    li      a1, 0xfffffffe
    remu    a2, a0, a1
    CHECK   a2, 0xfffffff9      // remu(0xfffffff9, 0xfffffffe)
    li      a0, 0x00000007
    li      a1, 0x00000000
    remu    a2, a0, a1
    CHECK   a2, 0x00000007      // remu(0x00000007, 0x00000000)
    li      a0, 0xfffffff9
    li      a1, 0x00000000
    remu    a2, a0, a1
    CHECK   a2, 0xfffffff9      // remu(0xfffffff9, 0x00000000)
    li      a0, 0x00000000
    li      a1, 0x00000000
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0x00000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0x00000000
    remu    a2, a0, a1
    CHECK   a2, 0x80000000      // remu(0x80000000, 0x00000000)
    li      a0, 0x80000000
    li      a1, 0xffffffff
    remu    a2, a0, a1
    CHECK   a2, 0x80000000      // remu(0x80000000, 0xffffffff)
    li      a0, 0x80000000
    li      a1, 0x00000001
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0x80000000, 0x00000001)
    li      a0, 0x80000000
    li      a1, 0x80000000
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0x80000000, 0x80000000)
    li      a0, 0x00000005
    li      a1, 0x80000000
    remu    a2, a0, a1
    CHECK   a2, 0x00000005      // remu(0x00000005, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0x80000000
    remu    a2, a0, a1
    CHECK   a2, 0x7fffffff      // remu(0xffffffff, 0x80000000)
    li      a0, 0xffffffff
    li      a1, 0xffffffff
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0xffffffff, 0xffffffff)
    li      a0, 0xffffffff
    li      a1, 0x00000001
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0xffffffff, 0x00000001)
    li      a0, 0xfffffffe
    li      a1, 0xffffffff
    remu    a2, a0, a1
    CHECK   a2, 0xfffffffe      // remu(0xfffffffe, 0xffffffff)
    li      a0, 0x00000001
    li      a1, 0xffffffff
    remu    a2, a0, a1
    CHECK   a2, 0x00000001      // remu(0x00000001, 0xffffffff)
    li      a0, 0x00000000
    li      a1, 0x00000005
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0x00000000, 0x00000005)
    li      a0, 0x7fffffff
    li      a1, 0x7fffffff
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0x7fffffff, 0x7fffffff)
    li      a0, 0x12345678
    li      a1, 0x00001234
    remu    a2, a0, a1
    CHECK   a2, 0x00000da8      // remu(0x12345678, 0x00001234)
    li      a0, 0x80000000
    li      a1, 0x00000002
    remu    a2, a0, a1
    CHECK   a2, 0x00000000      // remu(0x80000000, 0x00000002)
    li      a0, 0x7fffffff
    li      a1, 0xffffffff
    remu    a2, a0, a1
    CHECK   a2, 0x7fffffff      // remu(0x7fffffff, 0xffffffff)

    // ---- register aliasing: rd = rs1, rd = rs2, rd = rs1 = rs2, x0 ----
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    div     a0, a0, a1                  // rd = rs1
    CHECK   a0, 0xfffffc01
    li      a0, 0xfff0bdbd
    div     a1, a0, a1                  // rd = rs2
    CHECK   a1, 0xfffffc01
    li      a0, 0xfff0bdbd
    div     a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0x00000001
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    div     x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    div     a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    div     a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0xffffffff
    li      a0, 0xf0000011
    li      a1, 0x00012345
    divu    a0, a0, a1                  // rd = rs1
    CHECK   a0, 0x0000d2f0
    li      a0, 0xf0000011
    divu    a1, a0, a1                  // rd = rs2
    CHECK   a1, 0x0000d2f0
    li      a0, 0xf0000011
    divu    a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0x00000001
    li      a0, 0xf0000011
    li      a1, 0x00012345
    divu    x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    divu    a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    divu    a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0xffffffff
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    rem     a0, a0, a1                  // rd = rs1
    CHECK   a0, 0xfffffdec
    li      a0, 0xfff0bdbd
    rem     a1, a0, a1                  // rd = rs2
    CHECK   a1, 0xfffffdec
    li      a0, 0xfff0bdbd
    rem     a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0x00000000
    li      a0, 0xfff0bdbd
    li      a1, 0x000003d1
    rem     x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    rem     a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    rem     a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0xfff0bdbd
    li      a0, 0xf0000011
    li      a1, 0x00012345
    remu    a0, a0, a1                  // rd = rs1
    CHECK   a0, 0x00005561
    li      a0, 0xf0000011
    remu    a1, a0, a1                  // rd = rs2
    CHECK   a1, 0x00005561
    li      a0, 0xf0000011
    remu    a0, a0, a0                  // rd = rs1 = rs2
    CHECK   a0, 0x00000000
    li      a0, 0xf0000011
    li      a1, 0x00012345
    remu    x0, a0, a1                  // rd = x0: no write, no forward
    addi    t0, x0, 5
    CHECK   t0, 5
    li      a2, 0x5a5a5a5a
    remu    a2, x0, a1                  // rs1 = x0
    CHECK   a2, 0x00000000
    li      a2, 0x5a5a5a5a
    remu    a2, a0, x0                  // rs2 = x0
    CHECK   a2, 0xf0000011
    CHECK   x0, 0                       // x0 never written

    TEST_END
