// ============================================================================
// Module      : imm_gen_pipe
// File        : imm_gen_pipe.sv
// Description : Full RV32I Immediate Generator
// ============================================================================

module imm_gen_pipe (
    input  logic [31:0] instruction,
    output logic [31:0] imm_out
);

    logic [6:0] opcode;
    assign opcode = instruction[6:0];

    always_comb begin
        case (opcode)

            // I-type: ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI, LW, JALR
            7'b0010011,
            7'b0000011,
            7'b1100111: begin
                imm_out = {{20{instruction[31]}}, instruction[31:20]};
            end

            // S-type: SW
            7'b0100011: begin
                imm_out = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end

            // B-type: BEQ/BNE/BLT/BGE/BLTU/BGEU
            7'b1100011: begin
                imm_out = {{19{instruction[31]}}, instruction[31], instruction[7],
                           instruction[30:25], instruction[11:8], 1'b0};
            end

            // U-type: LUI, AUIPC
            7'b0110111,
            7'b0010111: begin
                imm_out = {instruction[31:12], 12'b0};
            end

            // J-type: JAL
            7'b1101111: begin
                imm_out = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                           instruction[20], instruction[30:21], 1'b0};
            end

            default: begin
                imm_out = 32'd0;
            end
        endcase
    end

endmodule
