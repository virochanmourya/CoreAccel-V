// ============================================================================
// Module: imm_gen_pipe (Pipeline Immediate Generator with B-Type Support)
// File:   imm_gen_pipe.sv
//
// PURPOSE:
//   SystemVerilog rewrite of imm_gen.v with B-type immediate extraction added.
//   Extracts the immediate value from a 32-bit RISC-V instruction and
//   sign-extends it to 32 bits.
//
//   Supported immediate formats:
//     I-type (ADDI, LW):  imm[11:0]  = instruction[31:20]
//     S-type (SW):        imm[11:5]  = instruction[31:25]
//                         imm[4:0]   = instruction[11:7]
//     B-type (BEQ, BNE):  imm[12]    = instruction[31]
//                         imm[11]    = instruction[7]
//                         imm[10:5]  = instruction[30:25]
//                         imm[4:1]   = instruction[11:8]
//                         imm[0]     = 0 (branch offsets are multiples of 2)
//
// INPUTS:
//   instruction [31:0] - The full 32-bit instruction
//
// OUTPUTS:
//   imm_out [31:0] - Sign-extended 32-bit immediate value
// ============================================================================

module imm_gen_pipe (
    input  logic [31:0] instruction,
    output logic [31:0] imm_out
);

    logic [6:0] opcode;
    assign opcode = instruction[6:0];

    always_comb begin
        case (opcode)
            // I-type: ADDI (0010011), LW (0000011)
            7'b0010011,
            7'b0000011: begin
                // imm[11:0] from instruction[31:20], sign-extended to 32 bits
                imm_out = {{20{instruction[31]}}, instruction[31:20]};
            end

            // S-type: SW (0100011)
            7'b0100011: begin
                // imm[11:5] from instruction[31:25]
                // imm[4:0]  from instruction[11:7]
                imm_out = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end

            // B-type: BEQ, BNE (1100011)
            7'b1100011: begin
                // imm[12]   from instruction[31]     (sign bit)
                // imm[11]   from instruction[7]
                // imm[10:5] from instruction[30:25]
                // imm[4:1]  from instruction[11:8]
                // imm[0]    = 0 (always, branch offsets are multiples of 2)
                imm_out = {{19{instruction[31]}}, instruction[31], instruction[7],
                           instruction[30:25], instruction[11:8], 1'b0};
            end

            // R-type or unknown: no immediate needed
            default: begin
                imm_out = 32'd0;
            end
        endcase
    end

endmodule
