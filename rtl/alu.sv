// ============================================================================
// Module      : alu
// File        : alu.sv
// Description : RV32I Arithmetic Logic Unit. Purely combinational.
//               Branch conditions are evaluated by the dedicated comparator
//               in the EX stage, so the ALU produces no condition flags.
//               Xilinx Artix-7 (xc7a35tcpg236-1)
// ============================================================================
//   alu_control = {funct7[5], funct3} for R/I-type ALU ops:
//     0000 ADD   1000 SUB   0001 SLL   0010 SLT   0011 SLTU
//     0100 XOR   0101 SRL   1101 SRA   0110 OR    0111 AND
//     1111 pass alu_in2 (LUI)
// ============================================================================

module alu (
    input  logic [31:0] alu_in1,
    input  logic [31:0] alu_in2,
    input  logic [3:0]  alu_control,
    output logic [31:0] alu_result
);

    always_comb begin
        case (alu_control)
            4'b0000: alu_result = alu_in1 + alu_in2;                                  // ADD
            4'b1000: alu_result = alu_in1 - alu_in2;                                  // SUB
            4'b0001: alu_result = alu_in1 << alu_in2[4:0];                            // SLL
            4'b0010: alu_result = ($signed(alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0; // SLT
            4'b0011: alu_result = (alu_in1 < alu_in2) ? 32'd1 : 32'd0;                // SLTU
            4'b0100: alu_result = alu_in1 ^ alu_in2;                                  // XOR
            4'b0101: alu_result = alu_in1 >> alu_in2[4:0];                            // SRL
            4'b1101: alu_result = $signed(alu_in1) >>> alu_in2[4:0];                  // SRA
            4'b0110: alu_result = alu_in1 | alu_in2;                                  // OR
            4'b0111: alu_result = alu_in1 & alu_in2;                                  // AND
            4'b1111: alu_result = alu_in2;                                            // LUI
            default: alu_result = 32'd0;
        endcase
    end

endmodule
