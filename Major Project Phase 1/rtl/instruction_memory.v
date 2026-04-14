// ============================================================================
// Module: instruction_memory (Instruction ROM)
// File:   instruction_memory.v
//
// PURPOSE:
//   A read-only memory that stores the program. The PC gives an address,
//   and this module outputs the 32-bit instruction at that address.
//   Instructions are hardcoded for the demo program:
//     ADDI x1, x0, 5      =>  x1 = 0 + 5  = 5
//     ADDI x2, x0, 10     =>  x2 = 0 + 10 = 10
//     ADD  x3, x1, x2     =>  x3 = 5 + 10 = 15
//     SUB  x4, x3, x1     =>  x4 = 15 - 5 = 10
//     SW   x3, 0(x0)      =>  MEM[0] = x3 = 15
//     LW   x5, 0(x0)      =>  x5 = MEM[0] = 15
//
// INPUTS:
//   addr [31:0] - Byte address from the PC
//
// OUTPUTS:
//   instruction [31:0] - The 32-bit instruction at that address
// ============================================================================

module instruction_memory (
    input  wire [31:0] addr,
    output wire [31:0] instruction
);

    // Memory array: 64 words of 32 bits each (256 bytes, more than enough)
    reg [31:0] mem [0:63];

    // Hardcode the demo program
    // Machine code is derived from the RISC-V ISA encoding
    initial begin
        // ADDI x1, x0, 5     => imm=5, rs1=x0, funct3=000, rd=x1, opcode=0010011
        // Binary: 000000000101 | 00000 | 000 | 00001 | 0010011
        mem[0] = 32'h00500093;  // ADDI x1, x0, 5

        // ADDI x2, x0, 10    => imm=10, rs1=x0, funct3=000, rd=x2, opcode=0010011
        // Binary: 000000001010 | 00000 | 000 | 00010 | 0010011
        mem[1] = 32'h00A00113;  // ADDI x2, x0, 10

        // ADD x3, x1, x2     => funct7=0000000, rs2=x2, rs1=x1, funct3=000, rd=x3, opcode=0110011
        // Binary: 0000000 | 00010 | 00001 | 000 | 00011 | 0110011
        mem[2] = 32'h002081B3;  // ADD x3, x1, x2

        // SUB x4, x3, x1     => funct7=0100000, rs2=x1, rs1=x3, funct3=000, rd=x4, opcode=0110011
        // Binary: 0100000 | 00001 | 00011 | 000 | 00100 | 0110011
        mem[3] = 32'h40118233;  // SUB x4, x3, x1

        // SW x3, 0(x0)       => imm=0, rs2=x3, rs1=x0, funct3=010, opcode=0100011
        // Binary: 0000000 | 00011 | 00000 | 010 | 00000 | 0100011
        mem[4] = 32'h00302023;  // SW x3, 0(x0)

        // LW x5, 0(x0)       => imm=0, rs1=x0, funct3=010, rd=x5, opcode=0000011
        // Binary: 000000000000 | 00000 | 010 | 00101 | 0000011
        mem[5] = 32'h00002283;  // LW x5, 0(x0)

        // NOP (ADDI x0, x0, 0) — fills rest to avoid X values
        mem[6] = 32'h00000013;  // NOP
        mem[7] = 32'h00000013;  // NOP
    end

    // Read is combinational (no clock needed)
    // Divide byte address by 4 to get word index: addr[31:2]
    assign instruction = mem[addr[31:2]];

endmodule
