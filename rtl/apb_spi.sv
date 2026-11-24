// ============================================================================
// Module      : apb_spi
// File        : apb_spi.sv
// Description : SPI master (8-bit frames, modes 0-3), APB4 slave.
//
//   Offset  Name      Access  Contents
//   0x00    TXDATA    W       [7:0] push a byte into the TX FIFO (dropped if full)
//                     R       bit31 = TX FIFO full
//   0x04    RXDATA    R       bit31 = RX FIFO empty; else [7:0] = byte, popped
//   0x08    STATUS    R       bit0 busy (a frame is in progress), bit1 TX full,
//                             bit2 TX empty, bit3 RX not empty, bit4 RX full,
//                             bit5 RX overrun (sticky), [12:8] TX level,
//                             [20:16] RX level
//                     W       write 1 to bit5 clears the overrun
//   0x0C    CTRL      RW      bit0 EN, bit1 CPHA, bit2 CPOL, bit3 LSB first,
//                             bit4 AUTO_CS, bit5 LOOP (MISO := MOSI inside),
//                             [8+CSW-1:8] CS_SEL (chip select for AUTO_CS),
//                             [19:16] TX watermark, [27:24] RX watermark.
//                             Reset 0. Change CPOL/CPHA/LSB only while idle.
//   0x10    DIV       RW      [DIV_W-1:0]: SCK = clk / (2 * (DIV + 1)); reset DIV_RESET
//   0x14    CS        RW      [NCS-1:0] manual chip selects (1 = asserted, pin low)
//   0x18    IE        RW      bit0 TX watermark, bit1 RX watermark, bit2 idle,
//                             bit3 overrun
//   0x1C    IP        R       bit0 TX level <= TX watermark,
//                             bit1 RX level > RX watermark,
//                             bit2 idle (TX FIFO empty and not busy), bit3 overrun
//   other               PSLVERR
//
//   irq = |(IE & IP), a level (PLIC source). Zero wait states.
//
//   Engine: with EN set and a byte in the TX FIFO, a frame starts: the byte
//   is popped, AUTO_CS asserts CS_SEL, and the first SCK edge comes half a
//   SCK period later. 16 SCK edges per byte; CPHA = 0 samples MISO on the
//   leading edge and shifts MOSI on the trailing edge, CPHA = 1 the other
//   way round. Each received byte is pushed into the RX FIFO (dropped and
//   overrun set if it is full). Bytes in the TX FIFO follow back to back
//   with CS held; after the last one CS is held half a period more. Clearing
//   EN stops the engine at once (SCK back to CPOL). The chip selects are the
//   OR of the manual bits and the AUTO_CS line, active low on the pins.
//   MISO is sampled in the clk cycle of the sampling edge; the slave drives
//   it from the edge half a SCK period earlier (DIV >= 1 recommended for
//   off-chip devices).
// ============================================================================

module apb_spi #(
    parameter int FIFO_DEPTH = 8,          // power of two, <= 16
    parameter int NCS        = 2,          // chip selects, 1..16
    parameter int DIV_W      = 16,
    parameter int DIV_RESET  = 4            // 10 MHz SCK at 100 MHz
)(
    input  logic           clk,
    input  logic           reset,

    // ---- APB4 slave ----
    input  logic           psel,
    input  logic           penable,
    input  logic           pwrite,
    input  logic [31:0]    paddr,
    input  logic [31:0]    pwdata,
    output logic [31:0]    prdata,
    output logic           pready,
    output logic           pslverr,

    // ---- Pins ----
    output logic           sck,
    output logic           mosi,
    input  logic           miso,
    output logic [NCS-1:0] cs_n,

    output logic           irq
);

    localparam int LW  = $clog2(FIFO_DEPTH) + 1;
    localparam int CSW = (NCS > 1) ? $clog2(NCS) : 1;

    initial begin
        if (FIFO_DEPTH > 16 || NCS < 1 || NCS > 16 || DIV_W < 1 || DIV_W > 32)
            $error("apb_spi: parameter out of range");
    end

    // ------------------------------------------------------------ registers
    logic             en, cpha, cpol, lsbf, auto_cs, loop;
    logic [CSW-1:0]   cs_sel;
    logic [3:0]       tx_wm, rx_wm;
    logic [DIV_W-1:0] div;
    logic [NCS-1:0]   cs_man;
    logic [3:0]       ie;
    logic             overrun;

    logic        access, wr, rd, hit;
    logic [4:0]  word;

    assign access  = psel & penable;
    assign wr      = access & pwrite;
    assign rd      = access & ~pwrite;
    assign word    = paddr[6:2];
    assign hit     = (paddr[11:7] == 5'd0) & (word <= 5'd7);
    assign pready  = 1'b1;
    assign pslverr = ~hit;

    // ------------------------------------------------------------ FIFOs
    logic          txf_push, txf_pop, txf_empty, txf_full;
    logic [7:0]    txf_rdata;
    logic [LW-1:0] txf_level;
    logic          rxf_push, rxf_pop, rxf_empty, rxf_full;
    logic [7:0]    rxf_rdata, rx_byte;
    logic [LW-1:0] rxf_level;

    assign txf_push = wr & hit & (word == 5'd0);
    assign rxf_pop  = rd & hit & (word == 5'd1);

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_txf (
        .clk(clk), .reset(reset),
        .push(txf_push), .wdata(pwdata[7:0]),
        .pop(txf_pop), .rdata(txf_rdata),
        .empty(txf_empty), .full(txf_full), .level(txf_level)
    );
    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_rxf (
        .clk(clk), .reset(reset),
        .push(rxf_push), .wdata(rx_byte),
        .pop(rxf_pop), .rdata(rxf_rdata),
        .empty(rxf_empty), .full(rxf_full), .level(rxf_level)
    );

    function automatic logic [7:0] rev8(input logic [7:0] b);
        for (int i = 0; i < 8; i++) rev8[i] = b[7-i];
    endfunction

    // ------------------------------------------------------------ engine
    typedef enum logic [1:0] {S_IDLE, S_XFER, S_TAIL} state_t;
    state_t           state;
    logic [DIV_W-1:0] cnt;          // clocks left in this half period
    logic [3:0]       edge_idx;     // next SCK edge, 0..15 (even = leading)
    logic             sck_q;
    logic [7:0]       tx_sh, rx_sh, tx_load;
    logic             mosi_q;
    logic             tick, leading, sample_now, out_now, last_edge;
    logic             miso_in;
    logic [7:0]       rx_next, rx_full_byte;

    assign tick       = (state == S_XFER || state == S_TAIL) & (cnt == '0);
    assign leading    = ~edge_idx[0];
    assign last_edge  = (edge_idx == 4'd15);
    // CPHA 0: sample on leading edges, next MOSI bit on trailing edges (not
    //         after the last bit; the first bit goes out when the frame starts).
    // CPHA 1: next MOSI bit on every leading edge, sample on trailing edges.
    assign sample_now = (state == S_XFER) & tick & (leading ^ cpha);
    assign out_now    = (state == S_XFER) & tick & ~(leading ^ cpha) & ~(~cpha & last_edge);
    assign mosi       = mosi_q;
    assign miso_in    = loop ? mosi_q : miso;
    assign rx_next    = {rx_sh[6:0], miso_in};
    // CPHA 1 takes its 8th bit on the last edge itself.
    assign rx_full_byte = cpha ? rx_next : rx_sh;
    assign rx_byte    = lsbf ? rev8(rx_full_byte) : rx_full_byte;
    assign tx_load    = lsbf ? rev8(txf_rdata) : txf_rdata;

    logic byte_done, start;
    assign byte_done = (state == S_XFER) & tick & last_edge;
    assign start     = en & ~txf_empty & ((state == S_IDLE) | byte_done);
    assign txf_pop   = start;
    assign rxf_push  = byte_done & ~rxf_full;

    always_ff @(posedge clk) begin
        if (reset || !en) begin
            state    <= S_IDLE;
            cnt      <= '0;
            edge_idx <= '0;
            sck_q    <= 1'b0;
            tx_sh    <= '0;
            rx_sh    <= '0;
            mosi_q   <= 1'b0;
        end else begin
            if (state != S_IDLE)
                cnt <= (cnt == '0) ? div : cnt - 1'b1;
            if (state == S_XFER && tick) begin
                sck_q    <= ~sck_q;
                edge_idx <= edge_idx + 1'b1;    // 15 -> 0 at the end of a byte
            end
            if (sample_now) rx_sh <= rx_next;
            if (out_now) begin
                mosi_q <= tx_sh[7];
                tx_sh  <= {tx_sh[6:0], 1'b0};
            end
            if (start) begin
                state <= S_XFER;
                cnt   <= div;
                if (cpha) begin
                    tx_sh <= tx_load;               // first bit on the first leading edge
                end else begin
                    mosi_q <= tx_load[7];           // first bit now
                    tx_sh  <= {tx_load[6:0], 1'b0};
                end
            end else if (byte_done) begin
                state <= S_TAIL;
            end else if (state == S_TAIL && tick) begin
                state <= S_IDLE;
            end
        end
    end

    // 16 toggles per byte: sck_q is back to 0 between bytes.
    assign sck = sck_q ^ cpol;

    logic auto_line, busy;
    assign busy      = (state != S_IDLE);
    assign auto_line = auto_cs & busy;
    always_comb begin
        for (int i = 0; i < NCS; i++)
            cs_n[i] = ~(cs_man[i] | (auto_line & (32'(cs_sel) == i)));
    end

    // ------------------------------------------------------------ control regs
    always_ff @(posedge clk) begin
        if (reset) begin
            en      <= 1'b0;
            cpha    <= 1'b0;
            cpol    <= 1'b0;
            lsbf    <= 1'b0;
            auto_cs <= 1'b0;
            loop    <= 1'b0;
            cs_sel  <= '0;
            tx_wm   <= '0;
            rx_wm   <= '0;
            div     <= DIV_W'(DIV_RESET);
            cs_man  <= '0;
            ie      <= '0;
            overrun <= 1'b0;
        end else begin
            if (wr && hit && word == 5'd2 && pwdata[5]) overrun <= 1'b0;
            if (wr && hit && word == 5'd3) begin
                en      <= pwdata[0];
                cpha    <= pwdata[1];
                cpol    <= pwdata[2];
                lsbf    <= pwdata[3];
                auto_cs <= pwdata[4];
                loop    <= pwdata[5];
                cs_sel  <= pwdata[8 +: CSW];
                tx_wm   <= pwdata[19:16];
                rx_wm   <= pwdata[27:24];
            end
            if (wr && hit && word == 5'd4) div    <= pwdata[DIV_W-1:0];
            if (wr && hit && word == 5'd5) cs_man <= pwdata[NCS-1:0];
            if (wr && hit && word == 5'd6) ie     <= pwdata[3:0];
            // An overrun event wins over a clear in the same cycle.
            if (byte_done && rxf_full) overrun <= 1'b1;
        end
    end

    // ------------------------------------------------------------ interrupts
    logic [3:0] ip;
    assign ip[0] = (txf_level <= LW'(tx_wm));
    assign ip[1] = (rxf_level >  LW'(rx_wm));
    assign ip[2] = txf_empty & ~busy;
    assign ip[3] = overrun;
    assign irq   = |(ie & ip);

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        case (word)
            5'd0: prdata = {txf_full, 31'b0};
            5'd1: prdata = rxf_empty ? 32'h8000_0000 : {24'b0, rxf_rdata};
            5'd2: prdata = {11'b0, 5'(rxf_level), 3'b0, 5'(txf_level),
                            2'b0, overrun, rxf_full, ~rxf_empty, txf_empty,
                            txf_full, busy};
            5'd3: prdata = {4'b0, rx_wm, 4'b0, tx_wm, 4'b0, 4'(cs_sel),
                            2'b0, loop, auto_cs, lsbf, cpol, cpha, en};
            5'd4: prdata = 32'(div);
            5'd5: prdata = 32'(cs_man);
            5'd6: prdata = {28'b0, ie};
            5'd7: prdata = {28'b0, ip};
            default: prdata = '0;
        endcase
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0], pwdata};

endmodule
