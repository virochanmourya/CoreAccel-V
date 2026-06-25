// ============================================================================
// Module      : if_id_reg
// File        : if_id_reg.sv
// Description : IF/ID Pipeline Register
//               Latches data between the IF and ID stages.
//               Supports pipeline flushes (on branch taken) and stalls (load-use hazards).
//               Priority: reset > flush > stall.
//               Note: Flushing to 32'd0 safely decodes as a NOP since opcode 0 produces
//               all-zero control signals in the downstream decoder.
// ============================================================================

module if_id_reg (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush,
    input  logic        stall,
    input  logic [31:0] pc_in,
    input  logic [31:0] instruction_in,
    output logic [31:0] pc_out,
    output logic [31:0] instruction_out
);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            pc_out          <= 32'd0;
            instruction_out <= 32'd0;
        end
        else if (!stall) begin
            pc_out          <= pc_in;
            instruction_out <= instruction_in;
        end
    end

endmodule
