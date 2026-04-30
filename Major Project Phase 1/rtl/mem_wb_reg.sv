// ============================================================================
// Module: mem_wb_reg (MEM/WB Pipeline Register)
// File:   mem_wb_reg.sv
//
// PURPOSE:
//   Latches data between the Memory (MEM) and Write Back (WB) pipeline stages
//   on each rising clock edge.
//
//   Carries forward:
//     - WB control: reg_write, mem_to_reg
//     - Data:       mem_data (from data memory read), alu_result (passthrough)
//     - Address:    rd_addr (destination register)
//
// INPUTS/OUTPUTS:
//   All signals have _in (input) and _out (output) pairs.
// ============================================================================

module mem_wb_reg (
    input  logic        clk,
    input  logic        reset,

    // ---- WB control signals ----
    input  logic        reg_write_in,
    input  logic        mem_to_reg_in,
    output logic        reg_write_out,
    output logic        mem_to_reg_out,

    // ---- Data ----
    input  logic [31:0] mem_data_in,
    input  logic [31:0] alu_result_in,
    output logic [31:0] mem_data_out,
    output logic [31:0] alu_result_out,

    // ---- Destination register address ----
    input  logic [4:0]  rd_addr_in,
    output logic [4:0]  rd_addr_out
);

    always_ff @(posedge clk) begin
        if (reset) begin
            reg_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            mem_data_out    <= 32'd0;
            alu_result_out  <= 32'd0;
            rd_addr_out     <= 5'd0;
        end
        else begin
            reg_write_out   <= reg_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            mem_data_out    <= mem_data_in;
            alu_result_out  <= alu_result_in;
            rd_addr_out     <= rd_addr_in;
        end
    end

endmodule
