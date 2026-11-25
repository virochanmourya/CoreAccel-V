// ============================================================================
// Module      : pc_pipe
// File        : pc_pipe.sv
// Description : Pipeline-aware Program Counter. Supports stalling and branching.
// ============================================================================

module pc_pipe #(
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        pc_write,
    input  logic        pc_src,
    input  logic [31:0] pc_branch,
    output logic [31:0] pc_out
);

    always_ff @(posedge clk) begin
        if (reset)
            pc_out <= RESET_VECTOR;
        else if (pc_write) begin
            if (pc_src)
                pc_out <= pc_branch;
            else
                pc_out <= pc_out + 32'd4;
        end
    end

endmodule
