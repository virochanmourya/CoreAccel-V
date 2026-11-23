// illegal — F5: encodings the core does not implement raise the
// illegal-instruction error (one per instruction, counted by the harness) and
// have no architectural effect: no register write, no memory access, no
// control transfer. FENCE stays a legal NOP. An illegal encoding in the shadow
// of a taken branch is squashed and must not be counted.
#include "test.h"

    EXPECT_ILLEGAL 13
    EXPECT_OTHER_TRAPS 2            // [2] ECALL, [3] EBREAK trap with their own causes

    .data
    .balign 4
mem0:   .word 0x0badc0de

    TEST_BEGIN
    li      a0, 6
    li      a1, 7
    la      a2, mem0
    LA_ABS  a3, bad_target

    // (MUL/DIV, funct7=0000001, are legal since the M extension: mext_*.S;
    //  CSR instructions since Zicsr: csr_*.S)
    li      t3, 0x88
    .insn r 0x0B, 2, 0, t3, a0, a1  // [1] CUSTOM-0 funct3=010 (reserved)
    CHECK   t3, 0x88
    .word   0x00000073              // [2] ECALL
    .word   0x00100073              // [3] EBREAK
    .word   0x0000007f              // [4] unknown opcode
    .word   0x00000000              // [5] all-zero word

    li      t0, 0x11
    .insn r 0x33, 0, 0x10, t0, a0, a1   // [6]  OP with funct7=0010000
    .insn r 0x33, 1, 0x20, t0, a0, a1   // [7] SLL with funct7=0100000
    .insn i 0x13, 1, t0, a0, 0x405      // [8] SLLI with imm[11:5]=0100000
    .insn i 0x03, 3, t0, a2, 0          // [9] LD (load funct3=011)
    CHECK   t0, 0x11
    li      t4, 0x12345678
    .insn s 0x23, 3, t4, 0(a2)          // [10] SD (store funct3=011): no write
    nop
    lw      t5, 0(a2)
    CHECK   t5, 0x0badc0de

    li      t0, 0x22
    .insn i 0x67, 1, t0, a3, 0          // [11] JALR funct3=001: no jump, no link
    .insn b 0x63, 2, zero, zero, 3f     // [12] BRANCH funct3=010: must not branch
    j       4f                          //      (near, same-section target: no expansion)
3:  li      t0, 0xbad                   //      reached only if [12] branched
4:
    .word   0x0000100f                  // [13] FENCE.I (Zifencei not implemented)
    .insn r 0x0B, 7, 0, t0, a0, a1      // [14] CUSTOM-0 funct3=111 (reserved)
    .insn r 0x0B, 3, 1, t0, x0, x0      // [15] CUSTOM-0 READ_LO with funct7 != 0
    CHECK   t0, 0x22

    // squashed in a taken branch's shadow: not counted
    beq     zero, zero, 1f
    .word   0x00000000
    .word   0x0000007f
1:
    fence                               // legal NOP
    fence   rw, rw
    li      t4, 0x99
    CHECK   t4, 0x99                    // execution continues normally

    TEST_END

    .text
bad_target:                             // reached only if an illegal op transfers control:
    j       bad_target                  // spin -> the test TIMEOUTs (FAIL)
