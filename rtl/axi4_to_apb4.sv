// ============================================================================
// Module      : axi4_to_apb4
// File        : axi4_to_apb4.sv
// Description : AXI4 slave -> APB4 master bridge, one transfer at a time.
//
//   - Single-beat transfers go to APB: SETUP (PSEL) -> ACCESS (PENABLE) ->
//     wait for PREADY. PSLVERR becomes SLVERR on R or B. A burst (AxLEN > 0)
//     is not forwarded: every beat answers SLVERR (all W beats consumed).
//   - A write is accepted only with its data (AWREADY and WREADY together,
//     when both AWVALID and WVALID are present). A read wins a tie.
//   - APB select: NSLOT slots of 4 KB from SLOT_BASE (PSEL[0..NSLOT-1]),
//     plus one extra region (EXTRA_BASE/EXTRA_MASK) on PSEL[NSLOT]. The
//     address is decoded once, at the AXI handshake, into a flop.
//   - PADDR is the full address; each APB slave decodes its own offset.
//   - PWDATA/PSTRB are the AXI WDATA/WSTRB (the core replicates sub-word
//     store data into every lane, so word-register slaves may ignore PSTRB).
//     PSTRB is 0 for reads (APB4).
//   - R/B come from flops (RVALID/BVALID registered).
//
//   wait_inj: test hook (tied to 0 in the design). While 1, no new AXI
//   transfer is accepted and a pending R/B is not shown yet (once RVALID /
//   BVALID is up it stays up until the handshake). The APB transfer itself
//   is never stretched past the slave's PREADY: that would repeat the
//   access for a slave with side effects (e.g. a FIFO pop).
// ============================================================================

module axi4_to_apb4 #(
    parameter int          NSLOT      = 16,
    parameter logic [31:0] SLOT_BASE  = 32'hC000_0000,
    parameter logic [31:0] EXTRA_BASE = 32'hC400_0000,
    parameter logic [31:0] EXTRA_MASK = 32'hFFC0_0000,
    localparam int         NP         = NSLOT + 1
)(
    input  logic                clk,
    input  logic                reset,
    input  logic                wait_inj,

    // ---- AXI4 slave ----
    input  logic                s_awvalid,
    output logic                s_awready,
    input  logic [31:0]         s_awaddr,
    input  logic [7:0]          s_awlen,
    input  logic [2:0]          s_awsize,
    input  logic [1:0]          s_awburst,
    input  logic [2:0]          s_awprot,
    input  logic [3:0]          s_awid,
    input  logic                s_wvalid,
    output logic                s_wready,
    input  logic [31:0]         s_wdata,
    input  logic [3:0]          s_wstrb,
    input  logic                s_wlast,
    output logic                s_bvalid,
    input  logic                s_bready,
    output logic [1:0]          s_bresp,
    output logic [3:0]          s_bid,
    input  logic                s_arvalid,
    output logic                s_arready,
    input  logic [31:0]         s_araddr,
    input  logic [7:0]          s_arlen,
    input  logic [2:0]          s_arsize,
    input  logic [1:0]          s_arburst,
    input  logic [2:0]          s_arprot,
    input  logic [3:0]          s_arid,
    output logic                s_rvalid,
    input  logic                s_rready,
    output logic [31:0]         s_rdata,
    output logic [1:0]          s_rresp,
    output logic                s_rlast,
    output logic [3:0]          s_rid,

    // ---- APB4 master (shared bus, one PSEL per slave) ----
    output logic [31:0]         paddr,
    output logic [NP-1:0]       psel,
    output logic                penable,
    output logic                pwrite,
    output logic [31:0]         pwdata,
    output logic [3:0]          pstrb,
    output logic [2:0]          pprot,
    input  logic [NP-1:0][31:0] prdata,
    input  logic [NP-1:0]       pready,
    input  logic [NP-1:0]       pslverr
);

    localparam int PW = $clog2(NP + 1);
    localparam logic [PW-1:0] NONE = PW'(NP);     // no slave: SLVERR

    typedef enum logic [2:0] { S_IDLE, S_SETUP, S_ACCESS, S_RRESP, S_BRESP,
                               S_RBURST, S_WBURST } state_t;
    state_t state;

    logic [31:0]   addr_q, wdata_q, rdata_q;
    logic [3:0]    strb_q, id_q;
    logic [2:0]    prot_q;
    logic          write_q, err_q;
    logic [PW-1:0] idx_q;
    logic [7:0]    beats_left;     // RBURST: beats still to send - 1

    function automatic logic [PW-1:0] slot_of(input logic [31:0] a);
        if ((a & EXTRA_MASK) == EXTRA_BASE)
            slot_of = PW'(NSLOT);
        else if (a[31:16] == SLOT_BASE[31:16] && 32'(a[15:12]) < NSLOT)
            slot_of = PW'(a[15:12]);
        else
            slot_of = NONE;
    endfunction

    logic take_rd, take_wr;
    assign take_rd   = (state == S_IDLE) & ~wait_inj & s_arvalid;
    assign take_wr   = (state == S_IDLE) & ~wait_inj & ~s_arvalid & s_awvalid & s_wvalid;
    assign s_arready = take_rd;
    assign s_awready = take_wr;
    assign s_wready  = take_wr | (state == S_WBURST);

    logic sel_ready, sel_err;
    logic [31:0] sel_rdata;
    always_comb begin
        sel_ready = 1'b1;
        sel_err   = 1'b1;
        sel_rdata = '0;
        if (idx_q != NONE) begin
            sel_ready = pready[idx_q];
            sel_err   = pslverr[idx_q];
            sel_rdata = prdata[idx_q];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= S_IDLE;
            addr_q     <= '0;
            wdata_q    <= '0;
            rdata_q    <= '0;
            strb_q     <= '0;
            id_q       <= '0;
            prot_q     <= '0;
            write_q    <= 1'b0;
            err_q      <= 1'b0;
            idx_q      <= NONE;
            beats_left <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (take_rd) begin
                        addr_q     <= s_araddr;
                        id_q       <= s_arid;
                        prot_q     <= s_arprot;
                        strb_q     <= 4'b0000;
                        write_q    <= 1'b0;
                        idx_q      <= slot_of(s_araddr);
                        beats_left <= s_arlen;
                        err_q      <= 1'b1;
                        rdata_q    <= '0;
                        state      <= (s_arlen == 8'd0) ? S_SETUP : S_RBURST;
                    end else if (take_wr) begin
                        addr_q  <= s_awaddr;
                        id_q    <= s_awid;
                        prot_q  <= s_awprot;
                        wdata_q <= s_wdata;
                        strb_q  <= s_wstrb;
                        write_q <= 1'b1;
                        idx_q   <= slot_of(s_awaddr);
                        err_q   <= 1'b1;
                        if (s_awlen == 8'd0)   state <= S_SETUP;
                        else if (s_wlast)      state <= S_BRESP;    // malformed: treat as done
                        else                   state <= S_WBURST;
                    end
                end
                S_SETUP:  state <= S_ACCESS;
                S_ACCESS: if (sel_ready) begin
                    err_q   <= sel_err;
                    rdata_q <= sel_rdata;
                    state   <= write_q ? S_BRESP : S_RRESP;
                end
                S_RRESP:  if (s_rvalid && s_rready) state <= S_IDLE;
                S_BRESP:  if (s_bvalid && s_bready) state <= S_IDLE;
                S_RBURST: if (s_rvalid && s_rready) begin
                    if (beats_left == 8'd0) state <= S_IDLE;
                    else beats_left <= beats_left - 1'b1;
                end
                default:  if (s_wvalid && s_wlast) state <= S_BRESP;   // S_WBURST
            endcase
        end
    end

    // ---- AXI responses (registered state) ----
    // rsp_shown: RVALID/BVALID has been up; it must stay up until the handshake.
    logic rsp_shown, rsp_ok;
    always_ff @(posedge clk) begin
        if (reset) rsp_shown <= 1'b0;
        else       rsp_shown <= (s_rvalid & ~s_rready) | (s_bvalid & ~s_bready);
    end
    assign rsp_ok   = rsp_shown | ~wait_inj;
    assign s_rvalid = ((state == S_RRESP) | (state == S_RBURST)) & rsp_ok;
    assign s_rdata  = rdata_q;
    assign s_rresp  = err_q ? 2'b10 : 2'b00;           // SLVERR / OKAY
    assign s_rlast  = (state == S_RRESP) | (beats_left == 8'd0);
    assign s_rid    = id_q;
    assign s_bvalid = (state == S_BRESP) & rsp_ok;
    assign s_bresp  = err_q ? 2'b10 : 2'b00;
    assign s_bid    = id_q;

    // ---- APB ----
    logic apb_active;
    assign apb_active = (state == S_SETUP) | (state == S_ACCESS);
    always_comb begin
        psel = '0;
        if (apb_active && idx_q != NONE) psel[idx_q] = 1'b1;
    end
    assign penable = (state == S_ACCESS);
    assign paddr   = addr_q;
    assign pwrite  = write_q;
    assign pwdata  = wdata_q;
    assign pstrb   = strb_q;
    assign pprot   = prot_q;

    // Burst type and size are not used: one beat per APB transfer.
    logic unused;
    assign unused = ^{s_awsize, s_awburst, s_arsize, s_arburst};

endmodule
