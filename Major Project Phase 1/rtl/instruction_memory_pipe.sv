// ============================================================================
// Module: instruction_memory_pipe (Pipeline Test Program ROM)
// File:   instruction_memory_pipe.sv
//
// PURPOSE:
//   A read-only memory storing a comprehensive test program that exercises:
//     - Data forwarding (EX/MEM and MEM/WB paths)
//     - Load-use hazard stalling
//     - Branch taken (BEQ, BNE)
//     - Branch not taken (BEQ)
//
//   Test Program:
//     Addr  PC   Instruction            Expected
//     ----  ---  -----------            --------
//      0     0   ADDI x1, x0, 5        x1 = 5
//      1     4   ADDI x2, x0, 10       x2 = 10
//      2     8   ADD  x3, x1, x2       x3 = 15  (forwarding: x1 EX/MEM, x2 MEM/WB)
//      3    12   SUB  x4, x3, x1       x4 = 10  (forwarding: x3 EX/MEM)
//      4    16   SW   x3, 0(x0)        MEM[0] = 15
//      5    20   LW   x5, 0(x0)        x5 = 15
//      6    24   ADDI x6, x5, 1        x6 = 16  (load-use stall, then MEM/WB fwd)
//      7    28   BEQ  x1, x1, +12      TAKEN → PC 40 (x1==x1)
//      8    32   ADDI x7, x0, 99       FLUSHED (x7 stays 0)
//      9    36   ADDI x8, x0, 99       FLUSHED (x8 stays 0)
//     10    40   ADDI x9, x0, 42       x9 = 42  (branch target)
//     11    44   BNE  x1, x2, +12      TAKEN → PC 56 (5 != 10)
//     12    48   ADDI x10, x0, 99      FLUSHED (x10 stays 0 for now)
//     13    52   ADDI x11, x0, 99      FLUSHED (x11 stays 0)
//     14    56   BEQ  x1, x2, +12      NOT TAKEN (5 != 10), fall through
//     15    60   ADDI x10, x0, 7       x10 = 7  (branch not taken, executes)
//     16-19      NOP                   Pipeline drain
//
//   Expected Final State:
//     x1=5, x2=10, x3=15, x4=10, x5=15, x6=16
//     x7=0, x8=0, x9=42, x10=7, x11=0
//     MEM[0] = 15
//
// INPUTS:
//   addr [31:0] - Byte address from the PC
//
// OUTPUTS:
//   instruction [31:0] - The 32-bit instruction at that address
// ============================================================================

module instruction_memory_pipe (
    input  logic [31:0] addr,
    output logic [31:0] instruction
);

    // Memory array: 64 words of 32 bits each (256 bytes)
    logic [31:0] mem [0:63];

    // Hardcode the comprehensive pipeline test program
    initial begin
        // --- Basic arithmetic (tests forwarding) ---
        mem[0]  = 32'h00500093;  // ADDI x1, x0, 5
        mem[1]  = 32'h00A00113;  // ADDI x2, x0, 10
        mem[2]  = 32'h002081B3;  // ADD  x3, x1, x2     → fwd x1 EX/MEM, x2 MEM/WB
        mem[3]  = 32'h40118233;  // SUB  x4, x3, x1     → fwd x3 EX/MEM

        // --- Memory operations (tests load-use stall) ---
        mem[4]  = 32'h00302023;  // SW   x3, 0(x0)      → MEM[0] = 15
        mem[5]  = 32'h00002283;  // LW   x5, 0(x0)      → x5 = 15
        mem[6]  = 32'h00128313;  // ADDI x6, x5, 1      → load-use stall, x6 = 16

        // --- Branch taken: BEQ (tests flush) ---
        mem[7]  = 32'h00108663;  // BEQ  x1, x1, +12    → TAKEN, target PC=40 (addr 10)
        mem[8]  = 32'h06300393;  // ADDI x7, x0, 99     → FLUSHED
        mem[9]  = 32'h06300413;  // ADDI x8, x0, 99     → FLUSHED

        // --- Branch target ---
        mem[10] = 32'h02A00493;  // ADDI x9, x0, 42     → x9 = 42

        // --- Branch taken: BNE (tests flush) ---
        mem[11] = 32'h00209663;  // BNE  x1, x2, +12    → TAKEN, target PC=56 (addr 14)
        mem[12] = 32'h06300513;  // ADDI x10, x0, 99    → FLUSHED
        mem[13] = 32'h06300593;  // ADDI x11, x0, 99    → FLUSHED

        // --- Branch not taken: BEQ ---
        mem[14] = 32'h00208663;  // BEQ  x1, x2, +12    → NOT TAKEN (5 != 10)
        mem[15] = 32'h00700513;  // ADDI x10, x0, 7     → x10 = 7 (executes normally)

        // --- NOP padding (pipeline drain) ---
        mem[16] = 32'h00000013;  // NOP
        mem[17] = 32'h00000013;  // NOP
        mem[18] = 32'h00000013;  // NOP
        mem[19] = 32'h00000013;  // NOP
    end

    // Read: combinational (no clock needed)
    // Divide byte address by 4 to get word index: addr[31:2]
    assign instruction = mem[addr[31:2]];

endmodule
