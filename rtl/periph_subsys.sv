// ============================================================================
// Module      : periph_subsys
// File        : periph_subsys.sv
// Description : Data-bus fabric and peripherals behind the core's AXI4 port.
//
//   AXI4 (from dbus_axi_master)
//     -> axi4_demux: 0xC000_0000-0xC000_FFFF and the PLIC region
//                    0xC400_0000-0xC43F_FFFF go to slave 0; anything else
//                    -> built-in default slave (DECERR)
//     -> slave 0: axi4_to_apb4, APB4 select per 4 KB slot:
//          slot 0  0xC000_0000  legacy page (GPIO bit-bang I2C, UART TX, 7-seg)
//          slot 1  0xC000_1000  UART0              (step 3; PSLVERR until then)
//          2..15                reserved: PSLVERR
//          PLIC    0xC400_0000  (step 4; PSLVERR until then)
//   The core-local words of slot 0 (mtimer 0x100-0x10F, tohost 0xFFC) are
//   answered inside the core and never reach this bus.
//
//   wait_inj: test hook (tied to 0 in the core): wait states on the AXI
//   READYs and on PREADY.
// ============================================================================

module periph_subsys #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200,
    parameter bit SEG_EN    = 1'b1
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        wait_inj,

    // ---- AXI4 slave port (single master) ----
    input  logic        s_awvalid,
    output logic        s_awready,
    input  logic [31:0] s_awaddr,
    input  logic [7:0]  s_awlen,
    input  logic [2:0]  s_awsize,
    input  logic [1:0]  s_awburst,
    input  logic [2:0]  s_awprot,
    input  logic [3:0]  s_awid,
    input  logic        s_wvalid,
    output logic        s_wready,
    input  logic [31:0] s_wdata,
    input  logic [3:0]  s_wstrb,
    input  logic        s_wlast,
    output logic        s_bvalid,
    input  logic        s_bready,
    output logic [1:0]  s_bresp,
    output logic [3:0]  s_bid,
    input  logic        s_arvalid,
    output logic        s_arready,
    input  logic [31:0] s_araddr,
    input  logic [7:0]  s_arlen,
    input  logic [2:0]  s_arsize,
    input  logic [1:0]  s_arburst,
    input  logic [2:0]  s_arprot,
    input  logic [3:0]  s_arid,
    output logic        s_rvalid,
    input  logic        s_rready,
    output logic [31:0] s_rdata,
    output logic [1:0]  s_rresp,
    output logic        s_rlast,
    output logic [3:0]  s_rid,

    // ---- Pins ----
    output logic        scl_drive_low,
    output logic        sda_drive_low,
    input  logic        scl_pad_in,
    input  logic        sda_pad_in,
    output logic        uart_tx_out,
    output logic [6:0]  seg,
    output logic        dp,
    output logic [3:0]  an
);

    // ------------------------------------------------------------ AXI demux
    localparam int NS = 1;      // slave 0: APB bridge
    localparam int NR = 2;

    logic [NS-1:0]       d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
    logic [NS-1:0]       d_arvalid, d_arready, d_rvalid, d_rready, d_rlast;
    logic [NS-1:0][1:0]  d_bresp, d_rresp;
    logic [NS-1:0][3:0]  d_bid, d_rid;
    logic [NS-1:0][31:0] d_rdata;
    logic [31:0]         d_awaddr, d_araddr, d_wdata;
    logic [7:0]          d_awlen, d_arlen;
    logic [2:0]          d_awsize, d_arsize, d_awprot, d_arprot;
    logic [1:0]          d_awburst, d_arburst;
    logic [3:0]          d_awid, d_arid, d_wstrb;
    logic                d_wlast;

    axi4_demux #(
        .NS          (NS),
        .NR          (NR),
        .REGION_BASE ({32'hC400_0000, 32'hC000_0000}),
        .REGION_MASK ({32'hFFC0_0000, 32'hFFFF_0000}),
        .REGION_SLV  ({8'd0, 8'd0})
    ) u_demux (
        .clk (clk), .reset (reset), .wait_inj (wait_inj),
        .s_awvalid (s_awvalid), .s_awready (s_awready), .s_awaddr (s_awaddr), .s_awlen (s_awlen),
        .s_awsize (s_awsize), .s_awburst (s_awburst), .s_awprot (s_awprot), .s_awid (s_awid),
        .s_wvalid (s_wvalid), .s_wready (s_wready), .s_wdata (s_wdata), .s_wstrb (s_wstrb),
        .s_wlast (s_wlast),
        .s_bvalid (s_bvalid), .s_bready (s_bready), .s_bresp (s_bresp), .s_bid (s_bid),
        .s_arvalid (s_arvalid), .s_arready (s_arready), .s_araddr (s_araddr), .s_arlen (s_arlen),
        .s_arsize (s_arsize), .s_arburst (s_arburst), .s_arprot (s_arprot), .s_arid (s_arid),
        .s_rvalid (s_rvalid), .s_rready (s_rready), .s_rdata (s_rdata), .s_rresp (s_rresp),
        .s_rlast (s_rlast), .s_rid (s_rid),
        .m_awvalid (d_awvalid), .m_awready (d_awready), .m_awaddr (d_awaddr), .m_awlen (d_awlen),
        .m_awsize (d_awsize), .m_awburst (d_awburst), .m_awprot (d_awprot), .m_awid (d_awid),
        .m_wvalid (d_wvalid), .m_wready (d_wready), .m_wdata (d_wdata), .m_wstrb (d_wstrb),
        .m_wlast (d_wlast),
        .m_bvalid (d_bvalid), .m_bready (d_bready), .m_bresp (d_bresp), .m_bid (d_bid),
        .m_arvalid (d_arvalid), .m_arready (d_arready), .m_araddr (d_araddr), .m_arlen (d_arlen),
        .m_arsize (d_arsize), .m_arburst (d_arburst), .m_arprot (d_arprot), .m_arid (d_arid),
        .m_rvalid (d_rvalid), .m_rready (d_rready), .m_rdata (d_rdata), .m_rresp (d_rresp),
        .m_rlast (d_rlast), .m_rid (d_rid)
    );

    // ------------------------------------------------------------ AXI -> APB4
    localparam int NSLOT = 16;
    localparam int NP    = NSLOT + 1;          // + PLIC
    localparam int P_LEGACY = 0;
    localparam int P_UART0  = 1;
    localparam int P_PLIC   = NSLOT;

    logic [31:0]         paddr, pwdata;
    logic [NP-1:0]       psel;
    logic                penable, pwrite;
    logic [3:0]          pstrb;
    logic [2:0]          pprot;
    logic [NP-1:0][31:0] prdata;
    logic [NP-1:0]       pready, pslverr;

    axi4_to_apb4 #(
        .NSLOT      (NSLOT),
        .SLOT_BASE  (32'hC000_0000),
        .EXTRA_BASE (32'hC400_0000),
        .EXTRA_MASK (32'hFFC0_0000)
    ) u_bridge (
        .clk (clk), .reset (reset), .wait_inj (wait_inj),
        .s_awvalid (d_awvalid[0]), .s_awready (d_awready[0]), .s_awaddr (d_awaddr), .s_awlen (d_awlen),
        .s_awsize (d_awsize), .s_awburst (d_awburst), .s_awprot (d_awprot), .s_awid (d_awid),
        .s_wvalid (d_wvalid[0]), .s_wready (d_wready[0]), .s_wdata (d_wdata), .s_wstrb (d_wstrb),
        .s_wlast (d_wlast),
        .s_bvalid (d_bvalid[0]), .s_bready (d_bready[0]), .s_bresp (d_bresp[0]), .s_bid (d_bid[0]),
        .s_arvalid (d_arvalid[0]), .s_arready (d_arready[0]), .s_araddr (d_araddr), .s_arlen (d_arlen),
        .s_arsize (d_arsize), .s_arburst (d_arburst), .s_arprot (d_arprot), .s_arid (d_arid),
        .s_rvalid (d_rvalid[0]), .s_rready (d_rready[0]), .s_rdata (d_rdata[0]), .s_rresp (d_rresp[0]),
        .s_rlast (d_rlast[0]), .s_rid (d_rid[0]),
        .paddr (paddr), .psel (psel), .penable (penable), .pwrite (pwrite), .pwdata (pwdata),
        .pstrb (pstrb), .pprot (pprot), .prdata (prdata), .pready (pready), .pslverr (pslverr)
    );

    // ------------------------------------------------------------ APB slaves
    // Slot 0: legacy page
    apb_legacy_page #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .SEG_EN    (SEG_EN)
    ) u_legacy (
        .clk (clk), .reset (reset),
        .psel (psel[P_LEGACY]), .penable (penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_LEGACY]), .pready (pready[P_LEGACY]),
        .pslverr (pslverr[P_LEGACY]),
        .scl_drive_low (scl_drive_low), .sda_drive_low (sda_drive_low),
        .scl_pad_in (scl_pad_in), .sda_pad_in (sda_pad_in),
        .uart_tx_out (uart_tx_out), .seg (seg), .dp (dp), .an (an)
    );

    // Unused selects: answer PSLVERR at once.
    generate
        for (genvar i = 1; i < NP; i++) begin : g_empty
            assign prdata[i]  = '0;
            assign pready[i]  = 1'b1;
            assign pslverr[i] = 1'b1;
        end
    endgenerate

    // PSTRB/PPROT: the slaves are word registers (lane-replicated data).
    logic unused;
    assign unused = ^{pstrb, pprot, psel[NP-1:1], P_UART0, P_PLIC};

endmodule
