// ============================================================================
// Module      : clk_gen
// File        : clk_gen.sv
// Description : Core clock generation.
//
//   clk_in (board / pad clock) --+--------------------------> bypass input
//                                +--> PLL slot (empty) ------> PLL input
//                                       out = in, lock = 1
//   bypass / PLL --> glitch-free 2:1 mux --> clk_out (the single core clock)
//
//   The select comes from a strap pin, sampled only while the reset pin is
//   asserted (2-FF synchronised to clk_in) and frozen afterwards, so the
//   clock can only change during reset:
//     sel_strap = 0 : bypass (clk_in)        sel_strap = 1 : PLL output
//   The PLL is used only once it reports lock.
//
//   CLK_TECH = "FPGA": pass-through. clk_out is clk_in (no logic in the
//                      clock path); the strap is still latched so software
//                      can read it back. An MMCM would go in the PLL slot.
//   CLK_TECH = "ASIC": the glitch-free mux below is built. The PLL slot is
//                      where a PLL macro is instantiated.
//
//   Glitch-free mux: each input has an enable flop pair (rising edge, then
//   falling edge of its own clock). An input's enable may rise only after
//   the other input's enable has fallen, and every enable changes while its
//   own clock is low, so clk_out never carries a pulse shorter than either
//   input's own high or low phase. The enables are reset (asynchronously,
//   by the reset pin) to "bypass on, PLL off".
// ============================================================================

module clk_gen #(
    parameter string CLK_TECH = "FPGA"
)(
    input  logic clk_in,       // reference clock (pad)
    input  logic rst_pin,      // reset pin, active high, asynchronous
    input  logic sel_strap,    // clock-select strap pin (asynchronous)
    output logic clk_out,      // core clock
    output logic sel_q,        // latched select (for readback)
    output logic pll_lock      // PLL lock (empty slot: 1)
);

    // ---- Reset pin, synchronised to clk_in (async assert, sync release) ----
    (* ASYNC_REG = "TRUE" *) logic [1:0] rst_ref_ff;
    always_ff @(posedge clk_in or posedge rst_pin) begin
        if (rst_pin) rst_ref_ff <= 2'b11;
        else         rst_ref_ff <= {rst_ref_ff[0], 1'b0};
    end

    // ---- Strap: 2-FF synchroniser, sampled only while the reset is held ----
    (* ASYNC_REG = "TRUE" *) logic [1:0] strap_ff;
    always_ff @(posedge clk_in) begin
        strap_ff <= {strap_ff[0], sel_strap};
        if (rst_ref_ff[1]) sel_q <= strap_ff[1];
    end

    // ---- PLL slot (empty): output = input, always locked ----
    logic clk_pll;
    assign clk_pll  = clk_in;
    assign pll_lock = 1'b1;

    generate
        if (CLK_TECH == "FPGA") begin : g_fpga
            // Pass-through: no logic in the clock path.
            assign clk_out = clk_in;
            logic unused;
            assign unused = ^{clk_pll};
        end else if (CLK_TECH == "ASIC") begin : g_mux
            clk_mux_gf u_mux (
                .clk0    (clk_in),
                .clk1    (clk_pll),
                .rst     (rst_pin),
                .sel     (sel_q & pll_lock),
                .clk_out (clk_out)
            );
        end else begin : g_unsupported
            $error("clk_gen: CLK_TECH '%s' is not supported", CLK_TECH);
        end
    endgenerate

endmodule
