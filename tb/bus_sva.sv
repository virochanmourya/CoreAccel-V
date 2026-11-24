// ============================================================================
// bus_sva — protocol assertions on the data bus (sim only). Bound into:
//   - dbus_axi_master: AXI4 master-side rules, one access per bus request
//   - axi4_to_apb4:    APB4 rules, one APB transfer per AXI beat
// Every failure calls tb_top.sva_fail(), which makes the test FAIL.
// xsim note: an unsupported construct (e.g. '->' inside a boolean, $onehot0)
// makes xelab silently drop every assertion elaborated after it, so the
// Makefile fails sim-build on those warnings (XSIM 43-4127 / 43-4455).
// ============================================================================
`timescale 1ns/1ps

// ---------------------------------------------------------------- AXI4
module axi4_master_sva (
    input logic        clk,
    input logic        reset,
    input logic        req,          // core request (bus access in MEM)
    input logic        rsp_done,
    input logic        rsp_err,
    input logic        busy,         // master in BUSY (not draining an abandoned access)
    input logic        awvalid, awready, wvalid, wready, wlast, bvalid, bready,
    input logic        arvalid, arready, rvalid, rready, rlast,
    input logic [31:0] awaddr, araddr, wdata,
    input logic [3:0]  wstrb,
    input logic [7:0]  awlen, arlen,
    input logic [2:0]  awsize, arsize
);
    `define AXI_FAIL(name) begin $display("SVA FAIL %s t=%0t", name, $time); tb_top.sva_fail(); end

    // VALID stays up, payload stable, until the handshake (AXI4 A3.2.1).
    a_aw_stable: assert property (@(posedge clk) disable iff (reset)
        (awvalid && !awready) |=> (awvalid && $stable(awaddr) && $stable(awlen) && $stable(awsize)))
        else `AXI_FAIL("a_aw_stable")
    a_w_stable: assert property (@(posedge clk) disable iff (reset)
        (wvalid && !wready) |=> (wvalid && $stable(wdata) && $stable(wstrb) && $stable(wlast)))
        else `AXI_FAIL("a_w_stable")
    a_ar_stable: assert property (@(posedge clk) disable iff (reset)
        (arvalid && !arready) |=> (arvalid && $stable(araddr) && $stable(arlen) && $stable(arsize)))
        else `AXI_FAIL("a_ar_stable")
    // Single beats only: AxLEN = 0, WLAST and RLAST on every beat.
    a_single_beat: assert property (@(posedge clk) disable iff (reset)
        (!awvalid || awlen == 8'd0) && (!arvalid || arlen == 8'd0) &&
        (!wvalid || wlast) && (!rvalid || rlast))
        else `AXI_FAIL("a_single_beat")
    a_no_x: assert property (@(posedge clk) disable iff (reset)
        !$isunknown({awvalid, wvalid, arvalid, bvalid, rvalid, awready, wready, arready}))
        else `AXI_FAIL("a_no_x")

    // Transaction bookkeeping: at most one outstanding read or write, and
    // a response only for an outstanding transaction.
    int rd_out = 0, wr_aw = 0, wr_w = 0, n_addr = 0;
    always @(posedge clk) begin
        if (reset) begin
            rd_out = 0; wr_aw = 0; wr_w = 0; n_addr = 0;
        end else begin
            if (arvalid && arready) begin rd_out++; if (busy) n_addr++; end
            if (awvalid && awready) begin wr_aw++;  if (busy) n_addr++; end
            if (wvalid && wready)   wr_w++;
            if (rd_out + wr_aw > 1 || wr_w > 1) `AXI_FAIL("a_one_outstanding")
            if (rvalid && rready) begin
                if (rd_out == 0) `AXI_FAIL("a_r_without_ar")
                rd_out--;
            end
            if (bvalid && bready) begin
                if (wr_aw == 0 || wr_w == 0) `AXI_FAIL("a_b_without_aw_w")
                wr_aw--; wr_w--;
            end
            // One address handshake per completed (not timed-out) access;
            // a drained, abandoned transaction does not count.
            if (rsp_done) begin
                if (!rsp_err && n_addr != 1) `AXI_FAIL("a_one_access_per_request")
                n_addr = 0;
            end
        end
    end

    // The core's response is a single-cycle pulse while a request is up.
    a_rsp_pulse: assert property (@(posedge clk) disable iff (reset)
        rsp_done |=> !rsp_done)
        else `AXI_FAIL("a_rsp_pulse")
    a_rsp_has_req: assert property (@(posedge clk) disable iff (reset)
        rsp_done |-> req)
        else `AXI_FAIL("a_rsp_has_req")
    `undef AXI_FAIL
endmodule

// ---------------------------------------------------------------- APB4
module apb4_sva #(
    parameter int NP = 17
)(
    input logic          clk,
    input logic          reset,
    input logic [NP-1:0] psel,
    input logic          penable,
    input logic          pwrite,
    input logic [31:0]   paddr,
    input logic [31:0]   pwdata,
    input logic [3:0]    pstrb,
    input logic          sel_ready,     // PREADY of the selected slave
    input logic          rvalid, rready, bvalid, bready,
    input logic          err_beat       // the current AXI beat is answered without APB
);
    `define APB_FAIL(name) begin $display("SVA FAIL %s t=%0t", name, $time); tb_top.sva_fail(); end
    logic any_sel, done;
    assign any_sel = |psel;
    assign done    = any_sel & penable & sel_ready;

    a_psel_onehot: assert property (@(posedge clk) disable iff (reset) (psel & (psel - 1'b1)) == '0)
        else `APB_FAIL("a_psel_onehot")
    // ACCESS follows SETUP: PENABLE rises only after a cycle of PSEL without it.
    a_setup_first: assert property (@(posedge clk) disable iff (reset)
        $rose(penable) |-> ($past(any_sel) && !$past(penable) && $stable(psel)))
        else `APB_FAIL("a_setup_first")
    a_enable_has_sel: assert property (@(posedge clk) disable iff (reset)
        penable |-> any_sel)
        else `APB_FAIL("a_enable_has_sel")
    // SETUP always moves to ACCESS.
    a_setup_to_access: assert property (@(posedge clk) disable iff (reset)
        (any_sel && !penable) |=> (penable && $stable(psel)))
        else `APB_FAIL("a_setup_to_access")
    // Everything stable from SETUP through ACCESS until PREADY.
    a_stable: assert property (@(posedge clk) disable iff (reset)
        (any_sel && !done) |=> ($stable(paddr) && $stable(pwrite) && $stable(pwdata) &&
                                $stable(pstrb) && $stable(psel)))
        else `APB_FAIL("a_stable")
    // A transfer ends after PREADY: PENABLE drops.
    a_end: assert property (@(posedge clk) disable iff (reset)
        done |=> !penable)
        else `APB_FAIL("a_end")
    a_read_strb: assert property (@(posedge clk) disable iff (reset)
        (any_sel && !pwrite) |-> pstrb == 4'b0)
        else `APB_FAIL("a_read_strb")

    // Exactly one APB transfer per AXI response (none for an error beat).
    int n = 0;
    always @(posedge clk) begin
        if (reset) n = 0;
        else begin
            if (done) n++;
            if ((rvalid && rready) || (bvalid && bready)) begin
                if (n != (err_beat ? 0 : 1)) `APB_FAIL("a_one_apb_per_beat")
                n = 0;
            end
        end
    end
    `undef APB_FAIL
endmodule

bind dbus_axi_master axi4_master_sva u_axi_sva (
    .clk (clk), .reset (reset), .req (req), .rsp_done (rsp_done), .rsp_err (rsp_err),
    .busy (state == S_BUSY),
    .awvalid (m_awvalid), .awready (m_awready), .wvalid (m_wvalid), .wready (m_wready),
    .wlast (m_wlast), .bvalid (m_bvalid), .bready (m_bready),
    .arvalid (m_arvalid), .arready (m_arready), .rvalid (m_rvalid), .rready (m_rready),
    .rlast (m_rlast), .awaddr (m_awaddr), .araddr (m_araddr), .wdata (m_wdata),
    .wstrb (m_wstrb), .awlen (m_awlen), .arlen (m_arlen), .awsize (m_awsize), .arsize (m_arsize)
);

bind axi4_to_apb4 apb4_sva #(.NP(NP)) u_apb_sva (
    .clk (clk), .reset (reset), .psel (psel), .penable (penable), .pwrite (pwrite),
    .paddr (paddr), .pwdata (pwdata), .pstrb (pstrb),
    .sel_ready (sel_ready),
    .rvalid (s_rvalid), .rready (s_rready), .bvalid (s_bvalid), .bready (s_bready),
    .err_beat (idx_q == NONE || state == S_RBURST || state == S_WBURST)
);
