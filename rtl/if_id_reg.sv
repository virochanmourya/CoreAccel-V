// ============================================================================
// Module: if_id_reg (IF/ID Pipeline Register)
// File:   if_id_reg.sv
//
// PURPOSE:
//   Latches data between the Instruction Fetch (IF) and Instruction Decode (ID)
//   pipeline stages on each rising clock edge.
//
//   Supports:
//   - Flush: Clears outputs to 0 (NOP) on branch taken (from EX stage)
//   - Stall: Holds current values during load-use hazards
//
//   Priority: reset > flush > stall > normal latch
//
//   Flushing to 32'd0 is safe because opcode 7'b0000000 hits the default
//   case of control_unit_pipe, producing all-zero control signals
//   (reg_write=0, mem_write=0, branch=0) — a harmless architectural NOP.
//
// INPUTS:
//   clk            - Clock signal
//   reset          - Active-high synchronous reset
//   flush          - Clear outputs (branch taken)
//   stall          - Hold current values (load-use hazard)
//   pc_in [31:0]   - PC value from IF stage
//   instruction_in [31:0] - Fetched instruction from IF stage
//
// OUTPUTS:
//   pc_out [31:0]          - Latched PC
//   instruction_out [31:0] - Latched instruction
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
            instruction_out <= 32'd0;  // NOP (opcode 0 → all controls off)
        end
        else if (!stall) begin
            pc_out          <= pc_in;
            instruction_out <= instruction_in;
        end
        // else: stall == 1 → hold current values
    end

endmodule
