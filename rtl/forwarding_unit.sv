// ============================================================================
// Module      : forwarding_unit
// File        : forwarding_unit.sv
// Description : Resolves Read-After-Write (RAW) data hazards by detecting when an
//               instruction in the EX stage needs a result that is still in the
//               EX/MEM or MEM/WB pipeline register.
//               Generates mux select signals to forward the most recent result
//               directly to the ALU inputs, bypassing the register file.
//               Priority: EX/MEM forwarding (most recent producer) takes precedence
//               over MEM/WB forwarding.
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

    // Forward A (ALU input A / rs1)
    always_comb begin
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

    // Forward B (ALU input B / rs2)
    always_comb begin
        forward_b = 2'b00;

        // EX hazard (highest priority — most recent producer)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            forward_b = 2'b10;

        // MEM hazard (lower priority — only if no EX hazard)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            forward_b = 2'b01;
    end

endmodule
