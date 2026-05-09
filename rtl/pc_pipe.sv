// ============================================================================
// Module: pc_pipe (Pipeline-Aware Program Counter)
// File:   pc_pipe.sv
//
// PURPOSE:
//   Holds the address of the current instruction. Supports:
//   - Stalling (pc_write=0): PC holds its value during load-use hazards
//   - Branching (pc_src=1):  PC loads the branch target address
//   - Normal   (default):    PC increments by 4
//
// INPUTS:
//   clk       - Clock signal
//   reset     - Active-high synchronous reset
//   pc_write  - 1 = update PC, 0 = stall (hold current value)
//   pc_src    - 0 = PC+4, 1 = load branch target
//   pc_branch [31:0] - Branch target address (used when pc_src=1)
//
// OUTPUTS:
//   pc_out [31:0] - Current instruction address
// ============================================================================

module pc_pipe (
    input  logic        clk,
    input  logic        reset,
    input  logic        pc_write,
    input  logic        pc_src,
    input  logic [31:0] pc_branch,
    output logic [31:0] pc_out
);

    always_ff @(posedge clk) begin
        if (reset)
            pc_out <= 32'd0;
        else if (pc_write) begin
            if (pc_src)
                pc_out <= pc_branch;    // Branch taken: redirect PC
            else
                pc_out <= pc_out + 32'd4; // Normal: next sequential instruction
        end
        // else: pc_write == 0 → PC retains its value (stall)
    end

endmodule
