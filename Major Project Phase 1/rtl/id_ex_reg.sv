// ============================================================================
// Module: id_ex_reg (ID/EX Pipeline Register)
// File:   id_ex_reg.sv
//
// PURPOSE:
//   Latches decoded operands and control signals between the Instruction
//   Decode (ID) and Execute (EX) pipeline stages.
//
//   Carries three groups of control signals forward:
//     - WB group:  reg_write, mem_to_reg (used in WB stage)
//     - MEM group: mem_read, mem_write   (used in MEM stage)
//     - EX group:  alu_src, alu_control  (used in EX stage)
//     - Branch:    branch               (used in EX stage for compare)
//
//   Also carries funct3 to the EX stage for the branch comparator
//   to distinguish BEQ (funct3=000) from BNE (funct3=001).
//
//   Supports:
//   - Flush: Clears all outputs to 0 (NOP bubble) on load-use stall
//            or branch taken
//
//   Priority: reset > flush > normal latch
//
// INPUTS/OUTPUTS:
//   All data and control signals have _in (input) and _out (output) pairs.
//   See port list below for full signal inventory.
// ============================================================================

module id_ex_reg (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush,

    // ---- WB control signals ----
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,
    output logic        reg_write_out,
    output logic        mem_to_reg_out,

    // ---- MEM control signals ----
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    output logic        mem_read_out,
    output logic        mem_write_out,

    // ---- EX control signals ----
    input  logic        alu_src_in,
    input  logic [1:0]  alu_control_in,
    output logic        alu_src_out,
    output logic [1:0]  alu_control_out,

    // ---- Branch control ----
    input  logic        branch_in,
    output logic        branch_out,

    // ---- Data ----
    input  logic [31:0] pc_in,
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] rs2_data_in,
    input  logic [31:0] imm_in,
    output logic [31:0] pc_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] rs2_data_out,
    output logic [31:0] imm_out,

    // ---- Register addresses (for forwarding unit) ----
    input  logic [4:0]  rs1_addr_in,
    input  logic [4:0]  rs2_addr_in,
    input  logic [4:0]  rd_addr_in,
    output logic [4:0]  rs1_addr_out,
    output logic [4:0]  rs2_addr_out,
    output logic [4:0]  rd_addr_out,

    // ---- Instruction fields (for branch comparator) ----
    input  logic [2:0]  funct3_in,
    output logic [2:0]  funct3_out
);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            // Insert NOP bubble: all control signals off, all data zeroed
            reg_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            alu_src_out     <= 1'b0;
            alu_control_out <= 2'b00;
            branch_out      <= 1'b0;
            pc_out          <= 32'd0;
            rs1_data_out    <= 32'd0;
            rs2_data_out    <= 32'd0;
            imm_out         <= 32'd0;
            rs1_addr_out    <= 5'd0;
            rs2_addr_out    <= 5'd0;
            rd_addr_out     <= 5'd0;
            funct3_out      <= 3'd0;
        end
        else begin
            // Normal latch: capture all inputs
            reg_write_out   <= reg_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            alu_src_out     <= alu_src_in;
            alu_control_out <= alu_control_in;
            branch_out      <= branch_in;
            pc_out          <= pc_in;
            rs1_data_out    <= rs1_data_in;
            rs2_data_out    <= rs2_data_in;
            imm_out         <= imm_in;
            rs1_addr_out    <= rs1_addr_in;
            rs2_addr_out    <= rs2_addr_in;
            rd_addr_out     <= rd_addr_in;
            funct3_out      <= funct3_in;
        end
    end

endmodule
