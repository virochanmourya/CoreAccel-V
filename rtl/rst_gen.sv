// ============================================================================
// Module      : rst_gen
// File        : rst_gen.sv
// Description : Reset synchroniser and reset sources for the core clock.
//
//   rst_por : power-on / pin reset. The reset pin, asynchronous assert and
//             synchronous release through 2 flops. Resets only what must
//             survive a watchdog or software reset (system control's reset
//             cause, scratch registers and strap latch).
//   rst_sys : system reset, used by every other block. Asserted by rst_por
//             (and asynchronously by the pin itself) or by an internal
//             request (watchdog timeout, software reset), released through
//             2 flops. An internal request is a one-cycle pulse from a flop
//             in this clock domain; it is stretched to STRETCH cycles first,
//             so every block sees a reset several clocks long.
//
//   Timing (reset pin released before clock edge 1): rst_por falls after
//   edge 2, rst_sys after edge 4. An internal request at edge n asserts
//   rst_sys after edge n + 2 for STRETCH cycles.
//
//   The pin is used only as the asynchronous input of the synchroniser
//   flops (false path in the XDC). The blocks themselves keep synchronous
//   resets on rst_sys (ASIC open item: async-assert leaf flops / reset tree,
//   see the CDC/reset note in the design notes).
// ============================================================================

module rst_gen #(
    parameter int STRETCH = 16          // internal-request reset length (cycles)
)(
    input  logic clk,
    input  logic rst_pin,               // reset pin, active high, asynchronous
    input  logic req_wdt,               // watchdog timeout (1-cycle pulse)
    input  logic req_sw,                // software reset request (1-cycle pulse)
    output logic rst_por,
    output logic rst_sys
);

    localparam int CW = $clog2(STRETCH + 1);

    // ---- Pin reset synchroniser ----
    (* ASYNC_REG = "TRUE" *) logic [1:0] por_ff;
    always_ff @(posedge clk or posedge rst_pin) begin
        if (rst_pin) por_ff <= 2'b11;
        else         por_ff <= {por_ff[0], 1'b0};
    end
    assign rst_por = por_ff[1];

    // ---- Internal request stretcher ----
    logic [CW-1:0] stretch_cnt;
    always_ff @(posedge clk) begin
        if (rst_por)                  stretch_cnt <= '0;
        else if (req_wdt | req_sw)    stretch_cnt <= CW'(STRETCH);
        else if (stretch_cnt != '0)   stretch_cnt <= stretch_cnt - 1'b1;
    end

    // ---- System reset synchroniser ----
    // Its D input is synchronous (rst_por, the stretcher), and it is still
    // 1 when the pin releases, so these flops cannot go metastable: no
    // ASYNC_REG. rst_sys fans out to every flop in the design, so the last
    // stage may be replicated (same cycle, no extra latency).
    logic sys_ff0;
    (* max_fanout = 256 *) logic sys_ff1;
    always_ff @(posedge clk or posedge rst_pin) begin
        if (rst_pin) begin
            sys_ff0 <= 1'b1;
            sys_ff1 <= 1'b1;
        end else begin
            sys_ff0 <= rst_por | (stretch_cnt != '0);
            sys_ff1 <= sys_ff0;
        end
    end
    assign rst_sys = sys_ff1;

endmodule
