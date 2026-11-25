// ============================================================================
// Module      : axi4_imem_win
// File        : axi4_imem_win.sv
// Description : IMEM write window: AXI4 slave that turns single-beat word
//               writes into writes on the instruction memory's write port.
//               Used only by the boot loader (BOOT=rom builds).
//
//   - Write, AWLEN = 0, WSTRB = 4'hF: one IMEM word written (registered:
//     the write port sees it the cycle after the W handshake), B = OKAY.
//   - Write with a partial WSTRB (sb/sh), or a burst: nothing written,
//     every W beat accepted, one B = SLVERR after WLAST.
//   - Read: SLVERR (every beat of a burst, RDATA = 0). The window is
//     write-only; instructions are fetched on the instruction side.
//   One write and one read can be in flight at a time (as the demux does).
//   The window decodes the low address bits only; the demux selects it.
// ============================================================================

module axi4_imem_win #(
    parameter int AW = 11                  // IMEM word-address bits
)(
    input  logic          clk,
    input  logic          reset,

    input  logic          s_awvalid,
    output logic          s_awready,
    input  logic [31:0]   s_awaddr,
    input  logic [7:0]    s_awlen,
    input  logic [3:0]    s_awid,
    input  logic          s_wvalid,
    output logic          s_wready,
    input  logic [31:0]   s_wdata,
    input  logic [3:0]    s_wstrb,
    input  logic          s_wlast,
    output logic          s_bvalid,
    input  logic          s_bready,
    output logic [1:0]    s_bresp,
    output logic [3:0]    s_bid,
    input  logic          s_arvalid,
    output logic          s_arready,
    input  logic [7:0]    s_arlen,
    input  logic [3:0]    s_arid,
    output logic          s_rvalid,
    input  logic          s_rready,
    output logic [31:0]   s_rdata,
    output logic [1:0]    s_rresp,
    output logic          s_rlast,
    output logic [3:0]    s_rid,

    // ---- IMEM write port ----
    output logic          imem_we,
    output logic [AW-1:0] imem_waddr,
    output logic [31:0]   imem_wdata
);

    localparam logic [1:0] OKAY = 2'b00, SLVERR = 2'b10;

    logic unused;
    assign unused = &{1'b0, s_awaddr[31:AW+2], s_awaddr[1:0]};

    // ---------------------------------------------------------------- write
    logic          aw_got;        // AW accepted, W beats still to come
    logic          single;        // the accepted AW is a single beat
    logic [AW-1:0] waddr_q;
    logic          bad_q;         // a beat so far was not a full word

    assign s_awready = ~aw_got & ~s_bvalid;
    assign s_wready  = aw_got;

    always_ff @(posedge clk) begin
        if (reset) begin
            aw_got     <= 1'b0;
            single     <= 1'b0;
            waddr_q    <= '0;
            bad_q      <= 1'b0;
            s_bvalid   <= 1'b0;
            s_bresp    <= OKAY;
            s_bid      <= '0;
            imem_we    <= 1'b0;
            imem_waddr <= '0;
            imem_wdata <= '0;
        end else begin
            imem_we <= 1'b0;
            if (s_awvalid && s_awready) begin
                aw_got  <= 1'b1;
                single  <= (s_awlen == 8'd0);
                waddr_q <= s_awaddr[AW+1:2];
                bad_q   <= 1'b0;
                s_bid   <= s_awid;
            end
            if (s_wvalid && s_wready) begin
                if (s_wlast) begin
                    aw_got   <= 1'b0;
                    s_bvalid <= 1'b1;
                    s_bresp  <= (single && !bad_q && s_wstrb == 4'hF) ? OKAY : SLVERR;
                end
                if (s_wstrb != 4'hF) bad_q <= 1'b1;
                if (single && s_wlast && s_wstrb == 4'hF) begin
                    imem_we    <= 1'b1;
                    imem_waddr <= waddr_q;
                    imem_wdata <= s_wdata;
                end
            end
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- read
    logic [7:0] r_left;           // beats left - 1

    assign s_arready = ~s_rvalid;
    assign s_rdata   = '0;
    assign s_rresp   = SLVERR;
    assign s_rlast   = s_rvalid & (r_left == 8'd0);

    always_ff @(posedge clk) begin
        if (reset) begin
            s_rvalid <= 1'b0;
            r_left   <= '0;
            s_rid    <= '0;
        end else if (s_arvalid && s_arready) begin
            s_rvalid <= 1'b1;
            r_left   <= s_arlen;
            s_rid    <= s_arid;
        end else if (s_rvalid && s_rready) begin
            if (r_left == 8'd0) s_rvalid <= 1'b0;
            else                r_left   <= r_left - 8'd1;
        end
    end

endmodule
