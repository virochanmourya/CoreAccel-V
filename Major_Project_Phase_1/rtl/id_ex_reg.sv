// ============================================================================
// Module: id_ex_reg (ID/EX Pipeline Register — Full RV32I + DSP)
// File:   id_ex_reg.sv
// ============================================================================

module id_ex_reg (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush,
    input  logic        stall,

    // ---- WB control ----
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,
    output logic        reg_write_out,
    output logic        mem_to_reg_out,

    // ---- MEM control ----
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    output logic        mem_read_out,
    output logic        mem_write_out,

    // ---- EX control ----
    input  logic        alu_src_in,
    input  logic [3:0]  alu_control_in,
    output logic        alu_src_out,
    output logic [3:0]  alu_control_out,

    // ---- New RV32I control ----
    input  logic        alu_src_a_in,
    input  logic        pc_to_reg_in,
    input  logic        jump_in,
    output logic        alu_src_a_out,
    output logic        pc_to_reg_out,
    output logic        jump_out,

    // ---- Branch control ----
    input  logic        branch_in,
    output logic        branch_out,

    // ---- DSP control ----
    input  logic        is_mac_in,
    input  logic        is_mac_clear_in,
    input  logic        mac_to_reg_in,
    input  logic        is_mac_read_hi_in,
    output logic        is_mac_out,
    output logic        is_mac_clear_out,
    output logic        mac_to_reg_out,
    output logic        is_mac_read_hi_out,

    // ---- Data ----
    input  logic [31:0] pc_in,
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] rs2_data_in,
    input  logic [31:0] imm_in,
    output logic [31:0] pc_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] rs2_data_out,
    output logic [31:0] imm_out,

    // ---- Register addresses ----
    input  logic [4:0]  rs1_addr_in,
    input  logic [4:0]  rs2_addr_in,
    input  logic [4:0]  rd_addr_in,
    output logic [4:0]  rs1_addr_out,
    output logic [4:0]  rs2_addr_out,
    output logic [4:0]  rd_addr_out,

    // ---- Instruction fields ----
    input  logic [2:0]  funct3_in,
    output logic [2:0]  funct3_out
);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            reg_write_out      <= 1'b0;
            mem_to_reg_out     <= 1'b0;
            mem_read_out       <= 1'b0;
            mem_write_out      <= 1'b0;
            alu_src_out        <= 1'b0;
            alu_control_out    <= 4'b0000;
            alu_src_a_out      <= 1'b0;
            pc_to_reg_out      <= 1'b0;
            jump_out           <= 1'b0;
            branch_out         <= 1'b0;
            is_mac_out         <= 1'b0;
            is_mac_clear_out   <= 1'b0;
            mac_to_reg_out     <= 1'b0;
            is_mac_read_hi_out <= 1'b0;
            pc_out             <= 32'd0;
            rs1_data_out       <= 32'd0;
            rs2_data_out       <= 32'd0;
            imm_out            <= 32'd0;
            rs1_addr_out       <= 5'd0;
            rs2_addr_out       <= 5'd0;
            rd_addr_out        <= 5'd0;
            funct3_out         <= 3'd0;
        end
        else if (!stall) begin
            reg_write_out      <= reg_write_in;
            mem_to_reg_out     <= mem_to_reg_in;
            mem_read_out       <= mem_read_in;
            mem_write_out      <= mem_write_in;
            alu_src_out        <= alu_src_in;
            alu_control_out    <= alu_control_in;
            alu_src_a_out      <= alu_src_a_in;
            pc_to_reg_out      <= pc_to_reg_in;
            jump_out           <= jump_in;
            branch_out         <= branch_in;
            is_mac_out         <= is_mac_in;
            is_mac_clear_out   <= is_mac_clear_in;
            mac_to_reg_out     <= mac_to_reg_in;
            is_mac_read_hi_out <= is_mac_read_hi_in;
            pc_out             <= pc_in;
            rs1_data_out       <= rs1_data_in;
            rs2_data_out       <= rs2_data_in;
            imm_out            <= imm_in;
            rs1_addr_out       <= rs1_addr_in;
            rs2_addr_out       <= rs2_addr_in;
            rd_addr_out        <= rd_addr_in;
            funct3_out         <= funct3_in;
        end
        // else: stall — hold all values
    end

endmodule
