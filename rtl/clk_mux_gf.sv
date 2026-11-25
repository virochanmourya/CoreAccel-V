// ============================================================================
// Module      : clk_mux_gf
// File        : clk_mux_gf.sv
// Description : Glitch-free 2:1 clock mux (sel = 0: clk0, 1: clk1), used by
//               clk_gen when CLK_TECH = "ASIC".
//               rst (asynchronous, active high; the reset pin) forces clk0
//               on and clk1 off. See clk_gen for how it avoids glitches.
// In an ASIC flow the enable flops are dont_touch and the AND/OR gates are
// clock cells (or the library's clock-gating cells).
// ============================================================================
module clk_mux_gf (
    input  logic clk0,
    input  logic clk1,
    input  logic rst,
    input  logic sel,        // quasi-static (changes only during reset)
    output logic clk_out
);
    logic en0_p, en0_n, en1_p, en1_n;

    always_ff @(posedge clk0 or posedge rst)
        if (rst) en0_p <= 1'b1; else en0_p <= ~sel & ~en1_n;
    always_ff @(negedge clk0 or posedge rst)
        if (rst) en0_n <= 1'b1; else en0_n <= en0_p;

    always_ff @(posedge clk1 or posedge rst)
        if (rst) en1_p <= 1'b0; else en1_p <= sel & ~en0_n;
    always_ff @(negedge clk1 or posedge rst)
        if (rst) en1_n <= 1'b0; else en1_n <= en1_p;

    assign clk_out = (clk0 & en0_n) | (clk1 & en1_n);
endmodule
