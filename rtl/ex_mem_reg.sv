// ============================================================================
// Module      : ex_mem_reg
// File        : ex_mem_reg.sv
// Description : Latches data between the Execute (EX) and Memory (MEM) pipeline
//               stages on each rising clock edge.
//               Carries forward:
//               - WB control:  reg_write, mem_to_reg
//               - MEM control: mem_read, mem_write
//               - Data:        alu_result, rs2_data (store data for SW)
//               - Address:     rd_addr (destination register)
//               - funct3:      load/store width and sign (LB/LH/LW/LBU/LHU)
// ============================================================================

module ex_mem_reg (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush,
    input  logic        en,          // 0: hold (global MEM stall)

    // WB control
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,
    output logic        reg_write_out,
    output logic        mem_to_reg_out,

    // MEM control
    input  logic        mem_read_in,
    input  logic        mem_write_in,
    output logic        mem_read_out,
    output logic        mem_write_out,

    // Data
    input  logic [31:0] alu_result_in,
    input  logic [31:0] rs2_data_in,
    output logic [31:0] alu_result_out,
    output logic [31:0] rs2_data_out,
    // Store byte lanes (bus WSTRB)
    input  logic [3:0]  strb_in,
    output logic [3:0]  strb_out,

    // Destination register address
    input  logic [4:0]  rd_addr_in,
    output logic [4:0]  rd_addr_out,

    // Load/store width
    input  logic [2:0]  funct3_in,
    output logic [2:0]  funct3_out,
    // Valid instruction (0 for a bubble)
    input  logic        valid_in,
    output logic        valid_out,
    // Exception: this instruction traps in MEM
    input  logic        exc_in,
    output logic        exc_out,
    // Trap cause {interrupt, code[3:0]}
    input  logic [4:0]  cause_in,
    output logic [4:0]  cause_out,
    // Instruction PC (mepc on a trap)
    input  logic [31:0] pc_in,
    output logic [31:0] pc_out,
    // Trap value (mtval)
    input  logic [31:0] tval_in,
    output logic [31:0] tval_out,
    // MRET: return from trap in MEM
    input  logic        is_mret_in,
    output logic        is_mret_out
);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            is_mret_out <= 1'b0;
            tval_out <= '0;
            pc_out <= '0;
            cause_out <= '0;
            exc_out <= 1'b0;
            valid_out <= 1'b0;
            reg_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            alu_result_out  <= 32'd0;
            rs2_data_out    <= 32'd0;
            strb_out        <= 4'd0;
            rd_addr_out     <= 5'd0;
            funct3_out      <= 3'd0;
        end
        else if (en) begin
            is_mret_out <= is_mret_in;
            tval_out <= tval_in;
            pc_out <= pc_in;
            cause_out <= cause_in;
            exc_out <= exc_in;
            valid_out <= valid_in;
            reg_write_out   <= reg_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            alu_result_out  <= alu_result_in;
            rs2_data_out    <= rs2_data_in;
            strb_out        <= strb_in;
            rd_addr_out     <= rd_addr_in;
            funct3_out      <= funct3_in;
        end
    end

endmodule
