// ============================================================================
// Module: forwarding_unit
// File:   forwarding_unit.sv
//
// PURPOSE:
//   Resolves Read-After-Write (RAW) data hazards by detecting when an
//   instruction in the EX stage needs a result that is still in the
//   EX/MEM or MEM/WB pipeline register (not yet written to the register file).
//
//   Generates mux select signals to forward the most recent result
//   directly to the ALU inputs, bypassing the register file.
//
//   Priority: EX/MEM forwarding (most recent producer) takes precedence
//   over MEM/WB forwarding.
//
// INPUTS:
//   id_ex_rs1        [4:0] - Source register 1 address in EX stage
//   id_ex_rs2        [4:0] - Source register 2 address in EX stage
//   ex_mem_rd        [4:0] - Destination register in MEM stage
//   ex_mem_reg_write       - RegWrite signal from MEM stage
//   mem_wb_rd        [4:0] - Destination register in WB stage
//   mem_wb_reg_write       - RegWrite signal from WB stage
//
// OUTPUTS:
//   forward_a [1:0] - Forwarding mux select for ALU input A:
//                      2'b00 = no forwarding (use ID/EX register value)
//                      2'b10 = forward from EX/MEM (ALU result)
//                      2'b01 = forward from MEM/WB (write-back data)
//   forward_b [1:0] - Forwarding mux select for ALU input B (same encoding)
// ============================================================================

module forwarding_unit (
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,
    input  logic [4:0] ex_mem_rd,
    input  logic       ex_mem_reg_write,
    input  logic [4:0] mem_wb_rd,
    input  logic       mem_wb_reg_write,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    // ---- Forward A (ALU input A / rs1) ----
    always_comb begin
        // Default: no forwarding
        forward_a = 2'b00;

        // EX hazard (highest priority — most recent producer)
        // Producer is in MEM stage (just finished EX), consumer is in EX stage
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            forward_a = 2'b10;

        // MEM hazard (lower priority — only if no EX hazard)
        // Producer is in WB stage (just finished MEM), consumer is in EX stage
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1))
            forward_a = 2'b01;
    end

    // ---- Forward B (ALU input B / rs2) ----
    always_comb begin
        // Default: no forwarding
        forward_b = 2'b00;

        // EX hazard (highest priority)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            forward_b = 2'b10;

        // MEM hazard (lower priority)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            forward_b = 2'b01;
    end

endmodule
