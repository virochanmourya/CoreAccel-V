// ============================================================================
// Module: alu (Arithmetic Logic Unit)
// File:   alu.v
//
// PURPOSE:
//   Performs arithmetic operations on two 32-bit inputs.
//   For this minimal CPU, only ADD and SUB are needed.
//
// INPUTS:
//   alu_in1    [31:0] - First operand  (from rs1)
//   alu_in2    [31:0] - Second operand (from rs2 or immediate)
//   alu_control [1:0] - Selects the operation:
//                        2'b00 = ADD
//                        2'b01 = SUB
//
// OUTPUTS:
//   alu_result [31:0] - Result of the operation
// ============================================================================

module alu (
    input  wire [31:0] alu_in1,
    input  wire [31:0] alu_in2,
    input  wire [1:0]  alu_control,
    output reg  [31:0] alu_result
);

    // ALU operation selection
    always @(*) begin
        case (alu_control)
            2'b00:   alu_result = alu_in1 + alu_in2;  // ADD
            2'b01:   alu_result = alu_in1 - alu_in2;  // SUB
            default: alu_result = alu_in1 + alu_in2;  // Default to ADD
        endcase
    end

endmodule
