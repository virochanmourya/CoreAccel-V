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
// ============================================================================

module ex_mem_reg (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush,

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

    // Destination register address
    input  logic [4:0]  rd_addr_in,
    output logic [4:0]  rd_addr_out
);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            reg_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            alu_result_out  <= 32'd0;
            rs2_data_out    <= 32'd0;
            rd_addr_out     <= 5'd0;
        end
        else begin
            reg_write_out   <= reg_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            alu_result_out  <= alu_result_in;
            rs2_data_out    <= rs2_data_in;
            rd_addr_out     <= rd_addr_in;
        end
    end

endmodule
