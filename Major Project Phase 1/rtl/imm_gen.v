// ============================================================================
// Module: imm_gen (Immediate Generator)
// File:   imm_gen.v
//
// PURPOSE:
//   Extracts the immediate value from a 32-bit RISC-V instruction and
//   sign-extends it to 32 bits. Different instruction types place the
//   immediate bits in different positions:
//
//   I-type (ADDI, LW):  imm[11:0] = instruction[31:20]
//   S-type (SW):        imm[11:5] = instruction[31:25], imm[4:0] = instruction[11:7]
//
// INPUTS:
//   instruction [31:0] - The full 32-bit instruction
//
// OUTPUTS:
//   imm_out [31:0] - Sign-extended 32-bit immediate value
// ============================================================================

module imm_gen (
    input  wire [31:0] instruction,
    output reg  [31:0] imm_out
);

    wire [6:0] opcode;
    assign opcode = instruction[6:0];

    always @(*) begin
        case (opcode)
            // I-type: ADDI (0010011), LW (0000011)
            7'b0010011,
            7'b0000011: begin
                // imm[11:0] from instruction[31:20], sign-extended
                imm_out = {{20{instruction[31]}}, instruction[31:20]};
            end

            // S-type: SW (0100011)
            7'b0100011: begin
                // imm[11:5] from instruction[31:25], imm[4:0] from instruction[11:7]
                imm_out = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end

            // R-type or unknown: no immediate needed
            default: begin
                imm_out = 32'd0;
            end
        endcase
    end

endmodule
