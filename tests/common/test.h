// ============================================================================
// CoreAccel-V directed-test macros
//
// Signature convention follows riscv-arch-test: each CHECK stores one word at
// the next slot after begin_signature; the expected value is recorded in the
// non-loaded .expected section, in the same order, right next to the code.
// The harness halts on a store to HALT_ADDR and compares the two.
//
// Reserved registers: s11 = signature pointer, t6 = scratch for TEST_END and
// the trap handler. The handler also uses mscratch (to save t5).
//
// Traps: TEST_BEGIN points mtvec at _trap_entry, which records the trap in
// trap_rec (see TR_* offsets) and resumes: at mepc + 4 for an exception, at
// ra for an instruction access fault (cause 1: mepc is the bad target, so
// "return from the call"), and at mepc for an interrupt.
// ============================================================================

#define HALT_ADDR   0xC0000FFC
#define SIG_CANARY  0xDEADBEEF

// Machine timer (mtime lo/hi at +0/+4, mtimecmp lo/hi at +8/+C)
#define MTIMER_BASE 0xC0000100
// Simulation control words stored to HALT_ADDR (testbench only; the RTL
// ignores writes there): raise / drop the external interrupt line.
#define SIM_EXT_IRQ_ON  1
#define SIM_EXT_IRQ_OFF 2
// UART0 RX-pin stimulus (stored to HALT_ADDR): send a byte / a byte with a
// bad stop bit; external loopback (RX pin = TX pin) on / off.
#define SIM_UART0_SEND      0x100
#define SIM_UART0_BADSTOP   0x200
#define SIM_UART0_LOOP_ON   0x300
#define SIM_UART0_LOOP_OFF  0x301
#define UART0_BASE  0xC0001000
// Signature slots; a test with more checks defines SIG_WORDS before the include.
#ifndef SIG_WORDS
#define SIG_WORDS   128
#endif

// Trap record written by _trap_entry (word offsets into trap_rec)
#define TR_CAUSE     0
#define TR_EPC       4
#define TR_TVAL      8
#define TR_COUNT     12
#define TR_PROBE     16
#define TR_ACC       20
#define TR_MIE       24
#define TR_MACST     28
#define TR_PROBE_PTR 32

// Reset entry: set up the signature pointer.
.macro TEST_BEGIN
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    la      s11, begin_signature
    la      t6, _trap_entry
    csrw    mtvec, t6
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

    // ---- default trap handler ----
    .section .text.trap, "ax", @progbits
    .balign 4
    .globl  _trap_entry
_trap_entry:
    csrw    mscratch, t5
    LA_ABS  t5, trap_rec
    csrr    t6, mcause
    sw      t6, TR_CAUSE(t5)
    csrr    t6, mepc
    sw      t6, TR_EPC(t5)
    csrr    t6, mtval
    sw      t6, TR_TVAL(t5)
    lw      t6, TR_COUNT(t5)
    addi    t6, t6, 1
    sw      t6, TR_COUNT(t5)
    lw      t6, TR_PROBE_PTR(t5)    // the word the test asked to sample
    lw      t6, 0(t6)
    sw      t6, TR_PROBE(t5)
    MAC_STATUS t6                   // MAC sticky overflow at trap entry (read first:
    sw      t6, TR_MACST(t5)        //  the READ_LO below may set it itself)
    MAC_RDLO t6                     // MAC accumulator low word at trap entry
    sw      t6, TR_ACC(t5)
    csrr    t6, mie
    sw      t6, TR_MIE(t5)
    csrr    t6, mcause
    bltz    t6, 4f                  // interrupt: silence it, resume at mepc
    addi    t6, t6, -1
    bnez    t6, 2f
    csrw    mepc, ra                // instruction access fault: back to the caller
    j       3f
2:  csrr    t6, mepc                // exception: skip the instruction
    addi    t6, t6, 4
    csrw    mepc, t6
3:  csrr    t5, mscratch
    mret
4:  li      t5, MTIMER_BASE         // timer: mtimecmp = all ones (never)
    li      t6, -1
    sw      t6, 12(t5)
    sw      t6, 8(t5)
    li      t5, HALT_ADDR           // external: drop the simulated line
    li      t6, SIM_EXT_IRQ_OFF
    sw      t6, 0(t5)
    j       3b

    .section .data.trap, "aw", @progbits
    .balign 4
    .globl  trap_rec
trap_rec:
    .fill   8, 4, 0                 // cause, epc, tval, count, probe, acc_lo, mie, mac status
    .word   trap_rec                // TR_PROBE_PTR: defaults to trap_rec itself

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

// Declare intentional traps (default 0): illegal instruction (mcause 2),
// misaligned load/store (4/6), and every other cause (ECALL, EBREAK,
// instruction address misaligned / access fault, interrupts).
.macro EXPECT_ILLEGAL count
    .globl  expected_illegal_errors
    .set    expected_illegal_errors, \count
.endm
.macro EXPECT_MISALIGNED count
    .globl  expected_misaligned_errors
    .set    expected_misaligned_errors, \count
.endm
.macro EXPECT_OTHER_TRAPS count
    .globl  expected_other_traps
    .set    expected_other_traps, \count
.endm

// Load one trap_rec field into \reg.
.macro TRAP_FIELD reg, off
    LA_ABS  \reg, trap_rec
    lw      \reg, \off(\reg)
.endm
// CHECK the last trap's mcause, mepc and mtval (uses t6).
.macro CHECK_TRAP cause, epc, tval
    TRAP_FIELD t6, TR_CAUSE
    CHECK   t6, \cause
    TRAP_FIELD t6, TR_EPC
    CHECK   t6, \epc
    TRAP_FIELD t6, TR_TVAL
    CHECK   t6, \tval
.endm
// Make the handler sample the word at \sym (into TR_PROBE) at trap entry.
.macro SET_PROBE sym, tmp
    LA_ABS  \tmp, \sym
    LA_ABS  t6, trap_rec
    sw      \tmp, TR_PROBE_PTR(t6)
.endm

// Hold every TCM store in EX for `cycles` cycles in this test (harness hook,
// +HOLD_EX_STORES). Takes precedence over a regression-wide HOLD=<n>.
.macro HOLD_EX_STORES cycles
    .globl  test_hold_ex_stores
    .set    test_hold_ex_stores, \cycles
.endm

// Add \cycles wait states at the start of every data-bus access (harness
// +BUS_WAIT). Takes precedence over a regression-wide WAIT=<n|rand>.
.macro BUS_WAIT cycles
    .globl  test_bus_wait
    .set    test_bus_wait, \cycles
.endm
// Make every bus access to \addr hang past the core's bus timeout (harness
// +BUS_HANG_ADDR): it ends in a load/store access fault.
.macro BUS_HANG_ADDR addr
    .globl  test_bus_hang_addr
    .set    test_bus_hang_addr, \addr
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
