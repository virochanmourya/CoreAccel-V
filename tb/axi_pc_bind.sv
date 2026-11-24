// ============================================================================
// axi_pc_bind — optional Xilinx AXI protocol checker on the core's AXI4
// master port (make BUS_VIP=1). Uses the precompiled xsim library
// axi_protocol_checker_v2_0_21 (the checker core, without the IP wrapper):
// one read and one write thread (fixed ID 0), so the ID-CAM inputs are
// tied off. Wait-count "recommendation" checks are off (the wait hooks
// hold transfers far longer on purpose). Any status bit -> test FAIL.
// ============================================================================
`timescale 1ns/1ps
module axi_pc_wrap (
    input logic        clk, reset,
    input logic        awvalid, awready, wvalid, wready, wlast, bvalid, bready,
    input logic        arvalid, arready, rvalid, rready, rlast,
    input logic [31:0] awaddr, araddr, wdata, rdata,
    input logic [3:0]  wstrb, awid, arid, bid, rid,
    input logic [7:0]  awlen, arlen,
    input logic [2:0]  awsize, arsize, awprot, arprot,
    input logic [1:0]  awburst, arburst, bresp, rresp
);
    localparam int NERR = 160;
    wire [NERR-1:0] pc_status;

    axi_protocol_checker_v2_0_21_core #(
        .C_ERROR_COUNT (NERR), .C_AXI_ID_WIDTH (4), .C_AXI_DATA_WIDTH (32),
        .C_AXI_ADDR_WIDTH (32), .C_AXI_PROTOCOL (0),
        .MAXRBURSTS (2), .MAXWBURSTS (2),
        .RecommendOn (0), .RecommendWaitOn (0),
        .C_PC_HAS_SYSTEM_RESET (0), .C_NUM_RTHREADS (1), .C_NUM_WTHREADS (1),
        .C_INDEX_WIDTH (1), .C_CHK_ERR_RESP (0)
    ) u_pc (
        .pc_status (pc_status), .resetn (~reset),
        .arid_index (1'b0), .rid_index (1'b0), .rid_mismatch (1'b0), .rcam_overflow (1'b0),
        .awid_index (1'b0), .bid_index (1'b0), .bid_mismatch (1'b0), .wcam_overflow (1'b0),
        .ACLK (clk), .ARST_N (~reset),
        .AWID (awid), .AWADDR (awaddr), .AWLEN (awlen), .AWSIZE (awsize), .AWBURST (awburst),
        .AWLOCK (1'b0), .AWCACHE (4'b0), .AWPROT (awprot), .AWQOS (4'b0), .AWREGION (4'b0),
        .AWUSER (1'b0), .AWVALID (awvalid), .AWREADY (awready),
        .WLAST (wlast), .WDATA (wdata), .WSTRB (wstrb), .WUSER (1'b0), .WVALID (wvalid), .WREADY (wready),
        .BID (bid), .BRESP (bresp), .BUSER (1'b0), .BVALID (bvalid), .BREADY (bready),
        .ARID (arid), .ARADDR (araddr), .ARLEN (arlen), .ARSIZE (arsize), .ARBURST (arburst),
        .ARLOCK (1'b0), .ARCACHE (4'b0), .ARPROT (arprot), .ARQOS (4'b0), .ARREGION (4'b0),
        .ARUSER (1'b0), .ARVALID (arvalid), .ARREADY (arready),
        .RID (rid), .RLAST (rlast), .RDATA (rdata), .RRESP (rresp), .RUSER (1'b0),
        .RVALID (rvalid), .RREADY (rready)
    );

    logic reported = 1'b0;
    always @(posedge clk) begin
        if (!reset && |pc_status && !reported) begin
            $display("SVA FAIL axi_protocol_checker t=%0t status=%h", $time, pc_status);
            tb_top.sva_fail();
            reported = 1'b1;
        end
    end
endmodule

bind dbus_axi_master axi_pc_wrap u_axi_pc (
    .clk (clk), .reset (reset),
    .awvalid (m_awvalid), .awready (m_awready), .wvalid (m_wvalid), .wready (m_wready),
    .wlast (m_wlast), .bvalid (m_bvalid), .bready (m_bready),
    .arvalid (m_arvalid), .arready (m_arready), .rvalid (m_rvalid), .rready (m_rready),
    .rlast (m_rlast), .awaddr (m_awaddr), .araddr (m_araddr), .wdata (m_wdata), .rdata (m_rdata),
    .wstrb (m_wstrb), .awid (m_awid), .arid (m_arid), .bid (m_bid), .rid (m_rid),
    .awlen (m_awlen), .arlen (m_arlen), .awsize (m_awsize), .arsize (m_arsize),
    .awprot (m_awprot), .arprot (m_arprot), .awburst (m_awburst), .arburst (m_arburst),
    .bresp (m_bresp), .rresp (m_rresp)
);
