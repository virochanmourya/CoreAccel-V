// ============================================================================
// Module      : dbus_axi_master
// File        : dbus_axi_master.sv
// Description : Core-side AXI4 master for MEM-stage data accesses that are
//               not TCM or core-local (peripherals, holes).
//
//   - One outstanding transaction, single beat (AxLEN = 0, INCR), fixed ID 0.
//   - The request is captured on the issue cycle and every AXI output comes
//     from a flop, so AXI VALID/payload never depend on the pipeline and
//     stay stable until their handshake even if the core gives up (timeout).
//   - The response is registered: rsp_done is a one-cycle pulse, the cycle
//     after R/B arrives (RREADY/BREADY are always 1). rsp_done / rsp_err /
//     rsp_rdata are the only outputs the pipeline reads, all flops.
//   - Timeout: TIMEOUT cycles after issue without a response, rsp_done
//     pulses with rsp_err = 1 (the core takes an access fault). The
//     transaction is still in flight, so the master drains it (DRAIN) and
//     discards its response; a new request waits until then. If the fabric
//     never answers, each further request also ends in a timeout error
//     without being issued, so a wedged bus can't hang the core.
//
//   Request interface (from MEM; held stable by the stall until rsp_done):
//     req        : a bus access is in MEM (may stay 1 in the rsp_done cycle)
//     req_write, req_addr, req_wdata (lane-replicated), req_strb, req_size
// ============================================================================

module dbus_axi_master #(
    parameter int TIMEOUT = 256
)(
    input  logic        clk,
    input  logic        reset,

    // ---- Core request / response ----
    input  logic        req,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_strb,
    input  logic [2:0]  req_size,
    output logic        rsp_done,      // one-cycle pulse, registered
    output logic        rsp_err,       // with rsp_done: SLVERR/DECERR or timeout
    output logic [31:0] rsp_rdata,     // with rsp_done (reads)

    // ---- AXI4 master: write address ----
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [31:0] m_awaddr,
    output logic [7:0]  m_awlen,
    output logic [2:0]  m_awsize,
    output logic [1:0]  m_awburst,
    output logic [2:0]  m_awprot,
    output logic [3:0]  m_awid,
    // ---- write data ----
    output logic        m_wvalid,
    input  logic        m_wready,
    output logic [31:0] m_wdata,
    output logic [3:0]  m_wstrb,
    output logic        m_wlast,
    // ---- write response ----
    input  logic        m_bvalid,
    output logic        m_bready,
    input  logic [1:0]  m_bresp,
    input  logic [3:0]  m_bid,
    // ---- read address ----
    output logic        m_arvalid,
    input  logic        m_arready,
    output logic [31:0] m_araddr,
    output logic [7:0]  m_arlen,
    output logic [2:0]  m_arsize,
    output logic [1:0]  m_arburst,
    output logic [2:0]  m_arprot,
    output logic [3:0]  m_arid,
    // ---- read data ----
    input  logic        m_rvalid,
    output logic        m_rready,
    input  logic [31:0] m_rdata,
    input  logic [1:0]  m_rresp,
    input  logic        m_rlast,
    input  logic [3:0]  m_rid
);

    localparam int CW = $clog2(TIMEOUT + 1);

    typedef enum logic [1:0] { S_IDLE, S_BUSY, S_DRAIN } state_t;
    state_t state;

    logic          is_write;      // the transaction in flight is a write
    logic [31:0]   addr_q, wdata_q;
    logic [3:0]    strb_q;
    logic [2:0]    size_q;
    logic [CW-1:0] cnt;
    logic          issue, resp, timed_out;

    // A new request: only from IDLE, and not in the cycle its own response
    // is being handed to the core (req is still 1 then).
    assign issue     = req & (state == S_IDLE) & ~rsp_done;
    assign resp      = is_write ? m_bvalid : m_rvalid;  // RREADY/BREADY = 1
    assign timed_out = (cnt == CW'(TIMEOUT - 1));

    always_ff @(posedge clk) begin
        if (reset) begin
            state     <= S_IDLE;
            is_write  <= 1'b0;
            m_awvalid <= 1'b0;
            m_wvalid  <= 1'b0;
            m_arvalid <= 1'b0;
            addr_q    <= '0;
            wdata_q   <= '0;
            strb_q    <= '0;
            size_q    <= '0;
            cnt       <= '0;
            rsp_done  <= 1'b0;
            rsp_err   <= 1'b0;
            rsp_rdata <= '0;
        end else begin
            rsp_done <= 1'b0;

            // Address/data valids drop on their own handshake, whatever the state.
            if (m_awvalid && m_awready) m_awvalid <= 1'b0;
            if (m_wvalid  && m_wready)  m_wvalid  <= 1'b0;
            if (m_arvalid && m_arready) m_arvalid <= 1'b0;

            case (state)
                S_IDLE: begin
                    cnt <= '0;
                    if (issue) begin
                        state     <= S_BUSY;
                        is_write  <= req_write;
                        addr_q    <= req_addr;
                        wdata_q   <= req_wdata;
                        strb_q    <= req_strb;
                        size_q    <= req_size;
                        m_awvalid <= req_write;
                        m_wvalid  <= req_write;
                        m_arvalid <= ~req_write;
                    end
                end
                S_BUSY: begin
                    cnt <= cnt + 1'b1;
                    if (resp) begin
                        state     <= S_IDLE;
                        rsp_done  <= 1'b1;
                        rsp_err   <= is_write ? m_bresp[1] : m_rresp[1];
                        rsp_rdata <= m_rdata;
                    end else if (timed_out) begin
                        state     <= S_DRAIN;
                        rsp_done  <= 1'b1;
                        rsp_err   <= 1'b1;
                        rsp_rdata <= '0;
                        cnt       <= '0;
                    end
                end
                default: begin  // S_DRAIN: discard the orphan response
                    if (resp) begin
                        state <= S_IDLE;
                        cnt   <= '0;
                    end else if (req && !rsp_done) begin
                        // A request waiting behind a wedged bus also times out.
                        cnt <= cnt + 1'b1;
                        if (timed_out) begin
                            rsp_done  <= 1'b1;
                            rsp_err   <= 1'b1;
                            rsp_rdata <= '0;
                            cnt       <= '0;
                        end
                    end else begin
                        cnt <= '0;
                    end
                end
            endcase
        end
    end

    // ---- AXI payload: from the captured request ----
    assign m_awaddr  = addr_q;
    assign m_awlen   = 8'd0;
    assign m_awsize  = size_q;
    assign m_awburst = 2'b01;        // INCR
    assign m_awprot  = 3'b000;       // data, secure, unprivileged (M-mode only core)
    assign m_awid    = 4'd0;
    assign m_wdata   = wdata_q;
    assign m_wstrb   = strb_q;
    assign m_wlast   = 1'b1;
    assign m_bready  = 1'b1;
    assign m_araddr  = addr_q;
    assign m_arlen   = 8'd0;
    assign m_arsize  = size_q;
    assign m_arburst = 2'b01;
    assign m_arprot  = 3'b000;
    assign m_arid    = 4'd0;
    assign m_rready  = 1'b1;

    // IDs are fixed at 0 and every transaction is a single beat.
    logic unused;
    assign unused = ^{m_bid, m_rid, m_rlast, m_bresp[0], m_rresp[0]};  // resp[0]: EXOKAY vs OKAY, DECERR vs SLVERR

endmodule
