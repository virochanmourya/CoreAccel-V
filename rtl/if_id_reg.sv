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
    output logic [31:0] instruction_out,
    // Valid instruction (0 after reset/flush: a bubble)
    input  logic        valid_in,
    output logic        valid_out,
    // Instruction access fault: fetched from outside IMEM
    input  logic        fetch_fault_in,
    output logic        fetch_fault_out
);

    always_ff @(posedge clk) begin
        if (reset || flush) begin
            fetch_fault_out <= 1'b0;
            valid_out <= 1'b0;
            pc_out          <= 32'd0;
            instruction_out <= 32'h0000_0013;   // canonical NOP (addi x0, x0, 0)
        end
        else if (!stall) begin
            fetch_fault_out <= fetch_fault_in;
            valid_out <= valid_in;
            pc_out          <= pc_in;
            instruction_out <= instruction_in;
        end
    end

endmodule
