// ============================================================================
// CoreAccel-V directed-test macros
//
// Signature convention follows riscv-arch-test: each CHECK stores one word at
// the next slot after begin_signature; the expected value is recorded in the
// non-loaded .expected section, in the same order, right next to the code.
// The harness halts on a store to HALT_ADDR and compares the two.
//
// Reserved registers: s11 = signature pointer, t6 = scratch for TEST_END.
// ============================================================================

#define HALT_ADDR   0xC0000FFC
#define SIG_CANARY  0xDEADBEEF
#define SIG_WORDS   128

// Reset entry: set up the signature pointer.
.macro TEST_BEGIN
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    la      s11, begin_signature
.endm

// Store \reg to the next signature slot and record \exp as its expected value.
// The trailing addi keeps a later TCM load at least two instructions behind
// this store.
.macro CHECK reg, exp
    sw      \reg, 0(s11)
    addi    s11, s11, 4
    .pushsection .expected, "", @progbits
    .word   \exp
    .popsection
.endm

// Halt: magic store to the peripheral region, then spin.
// Also emits the canary-filled signature region.
.macro TEST_END
    li      t6, HALT_ADDR
    sw      zero, 0(t6)
1:  j       1b
    .section .data.signature, "aw", @progbits
    .balign 16
    .globl  begin_signature
begin_signature:
    .fill   SIG_WORDS, 4, SIG_CANARY
    .globl  end_signature
end_signature:
.endm

// Declare how many data-bus errors (accesses to unmapped addresses) the test
// makes on purpose. Default is 0: any unmapped access fails the test.
.macro EXPECT_DBUS_ERRORS count
    .globl  expected_dbus_errors
    .set    expected_dbus_errors, \count
.endm

// Declare intentional illegal-instruction / misaligned-access errors (default 0).
.macro EXPECT_ILLEGAL count
    .globl  expected_illegal_errors
    .set    expected_illegal_errors, \count
.endm
.macro EXPECT_MISALIGNED count
    .globl  expected_misaligned_errors
    .set    expected_misaligned_errors, \count
.endm

// Hold every TCM store in EX for `cycles` cycles in this test (harness hook,
// +HOLD_EX_STORES). Takes precedence over a regression-wide HOLD=<n>.
.macro HOLD_EX_STORES cycles
    .globl  test_hold_ex_stores
    .set    test_hold_ex_stores, \cycles
.endm

// Absolute address of a symbol, no PC-relative arithmetic.
.macro LA_ABS reg, sym
    lui     \reg, %hi(\sym)
    addi    \reg, \reg, %lo(\sym)
.endm

// ---- CUSTOM-0 MAC extension (opcode 0x0B) ----
// MAC: acc += rs1 * TCM[rs2]   (rs2 is a TCM byte address)
.macro MAC rs1, rs2
    .insn r 0x0B, 0, 0, x0, \rs1, \rs2
.endm
.macro MAC_CLEAR
    .insn r 0x0B, 1, 0, x0, x0, x0
.endm
.macro MAC_RDLO rd
    .insn r 0x0B, 3, 0, \rd, x0, x0
.endm
.macro MAC_RDHI rd
    .insn r 0x0B, 4, 0, \rd, x0, x0
.endm
// READ_SHIFT: rd = sat32(round_half_up(acc >>> rs1[5:0]))
.macro MAC_RDSHIFT rd, rs1
    .insn r 0x0B, 5, 0, \rd, \rs1, x0
.endm
// READ_STATUS: rd = {31'b0, sticky overflow}
.macro MAC_STATUS rd
    .insn r 0x0B, 6, 0, \rd, x0, x0
.endm
