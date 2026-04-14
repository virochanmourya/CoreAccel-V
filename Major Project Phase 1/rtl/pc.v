// ============================================================================
// Module: pc (Program Counter)
// File:   pc.v
// 
// PURPOSE:
//   Holds the address of the current instruction. On every rising clock edge,
//   it advances to the next instruction (PC + 4). On reset, it goes back to 0.
//
// INPUTS:
//   clk   - Clock signal
//   reset - Active-high synchronous reset
//
// OUTPUTS:
//   pc_out [31:0] - Current instruction address
// ============================================================================

module pc (
    input  wire        clk,
    input  wire        reset,
    output reg  [31:0] pc_out
);

    // On every clock edge: reset to 0, or advance by 4 (next word)
    always @(posedge clk) begin
        if (reset)
            pc_out <= 32'd0;        // Start from address 0
        else
            pc_out <= pc_out + 32'd4; // Move to next instruction (4 bytes each)
    end

endmodule
