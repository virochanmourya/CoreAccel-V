// mext_b2b — M extension in the pipeline: back-to-back multi-cycle ops
// sharing the one issue/done handshake (MUL->MUL, DIV->MUL, MUL->DIV,
// DIV->DIV, MUL->MAC, MAC->DIV, DIV->MAC, READ_SHIFT->MUL), load-use into
// MUL/DIV, MUL/DIV results forwarded to the next instruction (EX/MEM and
// MEM/WB), branches right after a DIV and on a DIV result, and MUL/DIV in a
// taken branch's shadow (squashed: must not issue or write).
#include "test.h"

    .data
    .balign 4
w3:     .word 3
v100:   .word 100
vneg9:  .word -9

    TEST_BEGIN
    la      a4, w3                  // MAC weight address (TCM[a4] = 3)
    la      a6, v100
    la      a7, vneg9

    // ---- MUL -> MUL ----
    li      a0, 6
    li      a1, 7
    mul     a2, a0, a1              // 42
    mul     a3, a2, a2              // dependent: 42 forwarded from EX/MEM -> 1764
    CHECK   a2, 42
    CHECK   a3, 1764
    mul     a2, a0, a0              // independent pair: 36
    mulhu   a3, a1, a1              // 0
    CHECK   a2, 36
    CHECK   a3, 0

    // ---- DIV -> MUL, MUL -> DIV, DIV -> DIV ----
    li      a0, 100
    li      a1, -7
    div     a2, a0, a1              // -14
    mul     a3, a2, a1              // dependent: 98
    CHECK   a2, -14
    CHECK   a3, 98
    mul     a2, a0, a0              // 10000
    rem     a3, a2, a1              // dependent: 10000 rem -7 = 4
    CHECK   a2, 10000
    CHECK   a3, 4
    divu    a2, a0, a0              // 1
    remu    a3, a0, a2              // dependent: 100 remu 1 = 0
    div     a5, a0, a1              // independent: -14
    CHECK   a2, 1
    CHECK   a3, 0
    CHECK   a5, -14

    // ---- MUL -> MAC, MAC -> DIV, READ_LO -> DIV, DIV -> MAC ----
    MAC_CLEAR
    li      a0, 5
    li      a1, 3
    mul     a2, a0, a1              // 15
    MAC     a2, a4                  // MAC rs1 forwarded from the MUL: acc = 45
    MAC_RDLO t0
    CHECK   t0, 45
    MAC     a0, a4                  // acc = 60
    divu    a3, a2, a1              // DIV right after a MAC: 15 / 3 = 5
    MAC_RDLO t0                     // 60
    divu    a5, t0, a0              // READ_LO forwarded into a DIV: 12
    CHECK   a3, 5
    CHECK   t0, 60
    CHECK   a5, 12
    div     a2, t0, a1              // 20
    MAC     a2, a4                  // DIV result forwarded into a MAC: acc = 120
    MAC_RDLO t0
    CHECK   t0, 120

    // ---- READ_SHIFT -> MUL ----
    li      t1, 2
    MAC_RDSHIFT t2, t1              // round(120 >> 2) = 30
    mul     a3, t2, t2              // 900
    CHECK   t2, 30
    CHECK   a3, 900

    // ---- load-use into MUL / DIV ----
    lw      t1, 0(a6)               // 100
    mul     t2, t1, t1              // rs1 = rs2 = load result: 10000
    lw      t3, 0(a7)               // -9
    div     t4, t1, t3              // rs2 = load result: 100 / -9 = -11
    lw      t3, 0(a7)
    rem     t5, t3, t1              // rs1 = load result: -9 rem 100 = -9
    CHECK   t2, 10000
    CHECK   t4, -11
    CHECK   t5, -9

    // ---- MUL/DIV results forwarded to the next instructions ----
    mul     t0, a0, a1              // 15
    addi    t1, t0, 1               // EX/MEM forward: 16
    divu    t2, a0, a1              // 1
    nop
    add     t3, t2, t2              // MEM/WB forward: 2
    li      t4, 4
    mul     t5, t4, t4              // 16
    sw      t5, 0(a6)               // store data forwarded from the MUL (v100 = 16)
    li      t4, 12
    divu    t6, t4, t4              // 1
    slli    t6, t6, 2               // 4
    add     t6, a6, t6              // v100 + 4 = vneg9
    lw      t4, 0(a6)               // 16
    lw      a5, 0(t6)               // -9: address built from a DIV result
    CHECK   t1, 16
    CHECK   t3, 2
    CHECK   t4, 16
    CHECK   a5, -9

    // ---- branches right after a DIV and on a DIV result ----
    li      t0, 0
    li      t2, 1
    div     t1, a0, a1              // 5 / 3 = 1
    beq     zero, zero, 1f          // taken, right behind the held DIV
    li      t0, 0xbad
1:  CHECK   t0, 0
    CHECK   t1, 1
    div     t1, a0, a1              // 1
    beq     t1, t2, 2f              // depends on the DIV: taken
    li      t0, 0xbad
2:  CHECK   t0, 0
    li      t0, 0
    rem     t1, a0, a1              // 2
    beq     t1, t2, 3f              // depends on the REM: not taken
    li      t0, 0x600d
3:  CHECK   t0, 0x600d

    // ---- MUL/DIV in a taken branch's shadow: squashed ----
    li      t0, 7
    beq     zero, zero, 4f
    mul     t0, a0, a1              // in ID when the branch resolves: squashed
    div     t0, a0, a1              // in IF: squashed
4:  CHECK   t0, 7
    divu    t1, a0, a1              // the unit still works after the squash: 1
    CHECK   t1, 1

    // ---- JAL right after a MUL; MUL at the jump target ----
    mul     t0, a0, a0              // 25
    jal     t1, 5f
    li      t0, 0xbad
5:  mul     t2, t0, a1              // 75
    CHECK   t0, 25
    CHECK   t2, 75

    TEST_END
