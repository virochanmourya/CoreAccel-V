// ============================================================================
// Module      : axi4_demux
// File        : axi4_demux.sv
// Description : AXI4 1-master -> N-slave demultiplexer with a built-in
//               default slave (DECERR).
//
//   - Address decode: NR regions {BASE, MASK, slave index}; the first match
//     wins. An address in no region goes to the default slave, which
//     accepts the transaction and answers DECERR (every beat of a read
//     burst, one B for a write after WLAST).
//   - One outstanding read and one outstanding write: a new AW (AR) is not
//     accepted until the previous B (last R) has been handed back. The
//     selected slave is registered at the address decode, so R/B and W are
//     routed from a flop, never from the address.
//   - W is routed to the slave of the current AW. W is accepted only once
//     AW is valid (a slave may wait for AW before WREADY).
//   - Request payload (address, size, data, ...) is broadcast to every
//     slave; only VALID is demultiplexed.
//
//   Arbitration hook: the upstream (s_*) port is a single AXI4 port. When
//   the DMA arrives, a 2-master arbiter (round-robin, one transaction at a
//   time per master) is placed in front of it, and the slave-index flops
//   here become per-master; nothing in the slaves changes.
//
//   wait_inj: test hook (tied to 0 in the design). While 1, AWREADY, WREADY
//   and ARREADY to the master are held low (legal at any time), which adds
//   wait states in front of every slave, including the default slave.
// ============================================================================

module axi4_demux #(
    parameter int NS = 1,                                   // real slaves
    parameter int NR = 1,                                   // address regions
    parameter logic [NR-1:0][31:0] REGION_BASE = '0,
    parameter logic [NR-1:0][31:0] REGION_MASK = '0,
    parameter logic [NR-1:0][7:0]  REGION_SLV  = '0
)(
    input  logic                 clk,
    input  logic                 reset,
    input  logic                 wait_inj,

    // ---- Upstream: from the master ----
    input  logic                 s_awvalid,
    output logic                 s_awready,
    input  logic [31:0]          s_awaddr,
    input  logic [7:0]           s_awlen,
    input  logic [2:0]           s_awsize,
    input  logic [1:0]           s_awburst,
    input  logic [2:0]           s_awprot,
    input  logic [3:0]           s_awid,
    input  logic                 s_wvalid,
    output logic                 s_wready,
    input  logic [31:0]          s_wdata,
    input  logic [3:0]           s_wstrb,
    input  logic                 s_wlast,
    output logic                 s_bvalid,
    input  logic                 s_bready,
    output logic [1:0]           s_bresp,
    output logic [3:0]           s_bid,
    input  logic                 s_arvalid,
    output logic                 s_arready,
    input  logic [31:0]          s_araddr,
    input  logic [7:0]           s_arlen,
    input  logic [2:0]           s_arsize,
    input  logic [1:0]           s_arburst,
    input  logic [2:0]           s_arprot,
    input  logic [3:0]           s_arid,
    output logic                 s_rvalid,
    input  logic                 s_rready,
    output logic [31:0]          s_rdata,
    output logic [1:0]           s_rresp,
    output logic                 s_rlast,
    output logic [3:0]           s_rid,

    // ---- Downstream: to the slaves (payload broadcast) ----
    output logic [NS-1:0]        m_awvalid,
    input  logic [NS-1:0]        m_awready,
    output logic [31:0]          m_awaddr,
    output logic [7:0]           m_awlen,
    output logic [2:0]           m_awsize,
    output logic [1:0]           m_awburst,
    output logic [2:0]           m_awprot,
    output logic [3:0]           m_awid,
    output logic [NS-1:0]        m_wvalid,
    input  logic [NS-1:0]        m_wready,
    output logic [31:0]          m_wdata,
    output logic [3:0]           m_wstrb,
    output logic                 m_wlast,
    input  logic [NS-1:0]        m_bvalid,
    output logic [NS-1:0]        m_bready,
    input  logic [NS-1:0][1:0]   m_bresp,
    input  logic [NS-1:0][3:0]   m_bid,
    output logic [NS-1:0]        m_arvalid,
    input  logic [NS-1:0]        m_arready,
    output logic [31:0]          m_araddr,
    output logic [7:0]           m_arlen,
    output logic [2:0]           m_arsize,
    output logic [1:0]           m_arburst,
    output logic [2:0]           m_arprot,
    output logic [3:0]           m_arid,
    input  logic [NS-1:0]        m_rvalid,
    output logic [NS-1:0]        m_rready,
    input  logic [NS-1:0][31:0]  m_rdata,
    input  logic [NS-1:0][1:0]   m_rresp,
    input  logic [NS-1:0]        m_rlast,
    input  logic [NS-1:0][3:0]   m_rid
);

    localparam int SW  = $clog2(NS + 1);
    localparam int DEF = NS;              // index of the default slave
    localparam int IW  = (NS > 1) ? $clog2(NS) : 1;   // real-slave index bits

    function automatic logic [SW-1:0] decode(input logic [31:0] a);
        decode = SW'(DEF);
        for (int r = NR - 1; r >= 0; r--)
            if ((a & REGION_MASK[r]) == REGION_BASE[r]) decode = SW'(REGION_SLV[r]);
    endfunction

    // ======================================================================
    //  Write channel
    // ======================================================================
    logic          w_busy;      // AW accepted, waiting for the last W and then B
    logic          w_done;      // last W accepted (still waiting for B)
    logic [SW-1:0] w_sel_q;     // slave of the accepted AW
    logic [SW-1:0] aw_sel;      // decode of the presented AW
    logic [SW-1:0] w_sel;       // slave W is routed to this cycle
    logic          aw_rdy_sel, w_rdy_sel;
    logic          aw_hs, w_hs, b_hs;
    // default slave, write side
    logic          def_b_pend;
    logic [3:0]    def_bid;

    assign aw_sel = decode(s_awaddr);
    assign w_sel  = w_busy ? w_sel_q : aw_sel;

    always_comb begin
        aw_rdy_sel = 1'b1;                        // default slave: always ready
        if (aw_sel != SW'(DEF)) aw_rdy_sel = m_awready[aw_sel[IW-1:0]];
        w_rdy_sel = 1'b1;
        if (w_sel != SW'(DEF)) w_rdy_sel = m_wready[w_sel[IW-1:0]];
    end

    // AW: only when no write is in flight.
    assign s_awready = ~w_busy & ~wait_inj & aw_rdy_sel;
    // W: once AW is valid or accepted, until the last beat.
    logic w_open;
    assign w_open   = ~w_done & (w_busy | s_awvalid);
    assign s_wready = w_open & ~wait_inj & w_rdy_sel;

    assign aw_hs = s_awvalid & s_awready;
    assign w_hs  = s_wvalid  & s_wready;
    assign b_hs  = s_bvalid  & s_bready;

    always_comb begin
        m_awvalid = '0;
        m_wvalid  = '0;
        if (!w_busy && s_awvalid && !wait_inj && aw_sel != SW'(DEF))
            m_awvalid[aw_sel[IW-1:0]] = 1'b1;
        if (w_open && s_wvalid && !wait_inj && w_sel != SW'(DEF))
            m_wvalid[w_sel[IW-1:0]] = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            w_busy     <= 1'b0;
            w_done     <= 1'b0;
            w_sel_q    <= '0;
            def_b_pend <= 1'b0;
            def_bid    <= '0;
        end else begin
            if (aw_hs) begin
                w_busy  <= 1'b1;
                w_sel_q <= aw_sel;
                def_bid <= s_awid;
            end
            if (w_hs && s_wlast) begin
                w_done <= 1'b1;
                if (w_sel == SW'(DEF)) def_b_pend <= 1'b1;
            end
            if (b_hs) begin
                w_busy     <= 1'b0;
                w_done     <= 1'b0;
                def_b_pend <= 1'b0;
            end
        end
    end

    // B: from the selected slave once its write is in flight.
    always_comb begin
        s_bvalid = 1'b0;
        s_bresp  = 2'b00;
        s_bid    = '0;
        m_bready = '0;
        if (w_busy) begin
            if (w_sel_q == SW'(DEF)) begin
                s_bvalid = def_b_pend;
                s_bresp  = 2'b11;                 // DECERR
                s_bid    = def_bid;
            end else begin
                s_bvalid = m_bvalid[w_sel_q[IW-1:0]];
                s_bresp  = m_bresp[w_sel_q[IW-1:0]];
                s_bid    = m_bid[w_sel_q[IW-1:0]];
                m_bready[w_sel_q[IW-1:0]] = s_bready;
            end
        end
    end

    // ======================================================================
    //  Read channel
    // ======================================================================
    logic          r_busy;
    logic [SW-1:0] r_sel_q, ar_sel;
    logic          ar_rdy_sel, ar_hs, r_hs;
    logic [7:0]    def_r_left;        // default slave: beats left - 1
    logic [3:0]    def_rid;

    assign ar_sel = decode(s_araddr);

    always_comb begin
        ar_rdy_sel = 1'b1;
        if (ar_sel != SW'(DEF)) ar_rdy_sel = m_arready[ar_sel[IW-1:0]];
    end

    assign s_arready = ~r_busy & ~wait_inj & ar_rdy_sel;
    assign ar_hs     = s_arvalid & s_arready;
    assign r_hs      = s_rvalid & s_rready;

    always_comb begin
        m_arvalid = '0;
        if (!r_busy && s_arvalid && !wait_inj && ar_sel != SW'(DEF))
            m_arvalid[ar_sel[IW-1:0]] = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            r_busy     <= 1'b0;
            r_sel_q    <= '0;
            def_r_left <= '0;
            def_rid    <= '0;
        end else begin
            if (ar_hs) begin
                r_busy     <= 1'b1;
                r_sel_q    <= ar_sel;
                def_r_left <= s_arlen;
                def_rid    <= s_arid;
            end
            if (r_hs && s_rlast) r_busy <= 1'b0;
            else if (r_hs)       def_r_left <= def_r_left - 1'b1;
        end
    end

    always_comb begin
        s_rvalid = 1'b0;
        s_rdata  = '0;
        s_rresp  = 2'b00;
        s_rlast  = 1'b0;
        s_rid    = '0;
        m_rready = '0;
        if (r_busy) begin
            if (r_sel_q == SW'(DEF)) begin
                s_rvalid = 1'b1;
                s_rresp  = 2'b11;                 // DECERR
                s_rlast  = (def_r_left == 8'd0);
                s_rid    = def_rid;
            end else begin
                s_rvalid = m_rvalid[r_sel_q[IW-1:0]];
                s_rdata  = m_rdata[r_sel_q[IW-1:0]];
                s_rresp  = m_rresp[r_sel_q[IW-1:0]];
                s_rlast  = m_rlast[r_sel_q[IW-1:0]];
                s_rid    = m_rid[r_sel_q[IW-1:0]];
                m_rready[r_sel_q[IW-1:0]] = s_rready;
            end
        end
    end

    // ---- Broadcast payload ----
    assign m_awaddr  = s_awaddr;
    assign m_awlen   = s_awlen;
    assign m_awsize  = s_awsize;
    assign m_awburst = s_awburst;
    assign m_awprot  = s_awprot;
    assign m_awid    = s_awid;
    assign m_wdata   = s_wdata;
    assign m_wstrb   = s_wstrb;
    assign m_wlast   = s_wlast;
    assign m_araddr  = s_araddr;
    assign m_arlen   = s_arlen;
    assign m_arsize  = s_arsize;
    assign m_arburst = s_arburst;
    assign m_arprot  = s_arprot;
    assign m_arid    = s_arid;

endmodule
