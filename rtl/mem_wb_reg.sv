// ============================================================================
// Module      : mem_wb_reg
// File        : mem_wb_reg.sv
// Description : MEM/WB pipeline register. Latches data and control signals
//               between the Memory (MEM) and Write Back (WB) stages.
//               The write-back value is selected in MEM (load data or the
//               EX result) and registered here as one word, so WB and the
//               forwarding / WB->ID bypass paths start at a flop.
// ============================================================================

module mem_wb_reg (
    input  logic        clk,
    input  logic        reset,

    // WB control signals
    input  logic        reg_write_in,
    output logic        reg_write_out,

    // Write-back value (selected in MEM)
    input  logic [31:0] result_in,
    output logic [31:0] result_out,

    // Destination register address
    input  logic [4:0]  rd_addr_in,
    output logic [4:0]  rd_addr_out,
    // Valid instruction: retires this cycle in WB (minstret)
    input  logic        valid_in,
    output logic        valid_out
);

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_out <= 1'b0;
            reg_write_out   <= 1'b0;
            result_out      <= 32'd0;
            rd_addr_out     <= 5'd0;
        end
        else begin
            valid_out <= valid_in;
            reg_write_out   <= reg_write_in;
            result_out      <= result_in;
            rd_addr_out     <= rd_addr_in;
        end
    end

endmodule
