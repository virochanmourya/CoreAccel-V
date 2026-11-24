// ============================================================================
// Module      : apb_uart
// File        : apb_uart.sv
// Description : UART0: 8N1 transmitter + receiver with FIFOs, APB4 slave.
//
//   Offset  Name      Access  Contents
//   0x00    TXDATA    W       [7:0] push a byte into the TX FIFO (dropped if full)
//                     R       bit31 = TX FIFO full
//   0x04    RXDATA    R       bit31 = RX FIFO empty; else [7:0] = byte, popped
//   0x08    STATUS    R       bit0 TX idle (FIFO empty, nothing shifting)
//                             bit1 TX full, bit2 RX not empty, bit3 RX full,
//                             bit4 RX overrun, bit5 framing error (sticky),
//                             [12:8] TX level, [20:16] RX level
//                     W       write 1 to bit4 / bit5 clears it
//   0x0C    CTRL      RW      bit0 TX enable, bit1 RX enable, bit2 loopback,
//                             [11:8] TX watermark, [19:16] RX watermark
//                             reset: TX/RX enabled, no loopback, watermarks 0
//   0x10    DIV       RW      [15:0] clocks per bit (minimum 4);
//                             reset CLK_FREQ / BAUD_RATE
//   0x14    IE        RW      bit0 TX watermark, bit1 RX watermark, bit2 error
//   0x18    IP        R       pending: bit0 TX level <= TX watermark,
//                             bit1 RX level > RX watermark,
//                             bit2 overrun | framing error
//   other               PSLVERR
//
//   irq = |(IE & IP), a level (PLIC source). Zero wait states.
//   Loopback: the receiver takes the transmitter's line and the TX pin
//   stays idle (high). RX pin: 2-FF synchroniser; the start bit is found
//   on a falling edge, then each bit is sampled at its middle. A byte with
//   a low stop bit is dropped and sets the framing error; a byte that
//   finds the RX FIFO full is dropped and sets overrun.
// ============================================================================

module apb_uart #(
    parameter int CLK_FREQ   = 100_000_000,
    parameter int BAUD_RATE  = 115_200,
    parameter int FIFO_DEPTH = 16
)(
    input  logic        clk,
    input  logic        reset,

    // ---- APB4 slave ----
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // ---- Pins ----
    output logic        txd,
    input  logic        rxd,          // asynchronous

    output logic        irq
);

    localparam int LW = $clog2(FIFO_DEPTH) + 1;        // level width
    localparam logic [15:0] DIV_RESET = 16'(CLK_FREQ / BAUD_RATE);

    // ------------------------------------------------------------ registers
    logic        tx_en, rx_en, loopback;
    logic [3:0]  tx_wm, rx_wm;
    logic [15:0] div;
    logic [2:0]  ie;
    logic        overrun, frame_err;

    logic        access, wr, rd;
    logic [4:0]  word;                 // paddr[6:2]
    logic        hit;

    assign access = psel & penable;
    assign wr     = access & pwrite;
    assign rd     = access & ~pwrite;
    assign word   = paddr[6:2];
    assign hit    = (paddr[11:7] == 5'd0) & (word <= 5'd6);
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

    // ------------------------------------------------------------ transmitter
    // Frame: start (0), 8 data bits LSB first, stop (1). tx_bits counts the
    // bits left in the frame; tx_cnt counts the clocks of the current bit.
    logic [9:0]  tx_shift;
    logic [3:0]  tx_bits;
    logic [15:0] tx_cnt;
    logic        tx_line, tx_busy;

    assign tx_busy = (tx_bits != 4'd0);
    assign txf_pop = tx_en & ~tx_busy & ~txf_empty;

    always_ff @(posedge clk) begin
        if (reset) begin
            tx_shift <= '1;
            tx_bits  <= '0;
            tx_cnt   <= '0;
        end else if (txf_pop) begin
            tx_shift <= {1'b1, txf_rdata, 1'b0};
            tx_bits  <= 4'd10;
            tx_cnt   <= '0;
        end else if (tx_busy) begin
            if (tx_cnt == div - 1'b1) begin
                tx_cnt   <= '0;
                tx_shift <= {1'b1, tx_shift[9:1]};
                tx_bits  <= tx_bits - 1'b1;
            end else begin
                tx_cnt <= tx_cnt + 1'b1;
            end
        end
    end
    assign tx_line = tx_busy ? tx_shift[0] : 1'b1;
    assign txd     = loopback ? 1'b1 : tx_line;

    // ------------------------------------------------------------ receiver
    (* ASYNC_REG = "TRUE" *) logic [1:0] rx_sync;
    logic        rx_in, rx_prev;
    logic [3:0]  rx_bits;              // bits left to sample (0 = idle)
    logic [15:0] rx_cnt;
    logic [8:0]  rx_shift;             // {stop, data[7:0]} after the frame

    always_ff @(posedge clk) begin
        if (reset) begin
            rx_sync <= 2'b11;
            rx_prev <= 1'b1;
        end else begin
            rx_sync <= {rx_sync[0], loopback ? tx_line : rxd};
            rx_prev <= rx_in;
        end
    end
    assign rx_in = rx_sync[1];

    logic rx_sample, rx_done;
    assign rx_sample = (rx_bits != 4'd0) & (rx_cnt == '0);
    assign rx_done   = rx_sample & (rx_bits == 4'd1);   // stop bit sampled
    assign rx_byte   = rx_shift[7:0];                  // {stop, data} after the stop sample

    always_ff @(posedge clk) begin
        if (reset) begin
            rx_bits  <= '0;
            rx_cnt   <= '0;
            rx_shift <= '0;
        end else if (rx_bits == 4'd0) begin
            // Idle: a falling edge starts a frame; sample the start bit
            // half a bit later, then each bit a full bit later.
            if (rx_en && rx_prev && !rx_in) begin
                rx_bits <= 4'd10;
                rx_cnt  <= {1'b0, div[15:1]} - 1'b1;
            end
        end else if (rx_cnt == '0) begin
            rx_cnt <= div - 1'b1;
            if (rx_bits == 4'd10 && rx_in) begin
                rx_bits <= '0;                          // false start: glitch
            end else begin
                rx_bits <= rx_bits - 1'b1;
                if (rx_bits != 4'd10) rx_shift <= {rx_in, rx_shift[8:1]};
            end
        end else begin
            rx_cnt <= rx_cnt - 1'b1;
        end
    end

    // The byte completes one cycle after the stop bit is shifted in.
    logic rx_frame_end;
    always_ff @(posedge clk) begin
        if (reset) rx_frame_end <= 1'b0;
        else       rx_frame_end <= rx_done;
    end
    assign rxf_push = rx_frame_end & rx_shift[8] & ~rxf_full;   // good stop bit, room

    // ------------------------------------------------------------ control regs
    always_ff @(posedge clk) begin
        if (reset) begin
            tx_en     <= 1'b1;
            rx_en     <= 1'b1;
            loopback  <= 1'b0;
            tx_wm     <= '0;
            rx_wm     <= '0;
            div       <= DIV_RESET;
            ie        <= '0;
            overrun   <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            if (wr && hit && word == 5'd2) begin
                if (pwdata[4]) overrun   <= 1'b0;
                if (pwdata[5]) frame_err <= 1'b0;
            end
            if (wr && hit && word == 5'd3) begin
                tx_en    <= pwdata[0];
                rx_en    <= pwdata[1];
                loopback <= pwdata[2];
                tx_wm    <= pwdata[11:8];
                rx_wm    <= pwdata[19:16];
            end
            if (wr && hit && word == 5'd4) div <= (pwdata[15:0] < 16'd4) ? 16'd4 : pwdata[15:0];
            if (wr && hit && word == 5'd5) ie  <= pwdata[2:0];
            // Error events win over a clear in the same cycle.
            if (rx_frame_end && rx_shift[8] && rxf_full) overrun   <= 1'b1;
            if (rx_frame_end && !rx_shift[8])            frame_err <= 1'b1;
        end
    end

    // ------------------------------------------------------------ interrupts
    logic [2:0] ip;
    assign ip[0] = (txf_level <= LW'(tx_wm));
    assign ip[1] = (rxf_level >  LW'(rx_wm));
    assign ip[2] = overrun | frame_err;
    assign irq   = |(ie & ip);

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        case (word)
            5'd0: prdata = {txf_full, 31'b0};
            5'd1: prdata = rxf_empty ? 32'h8000_0000 : {24'b0, rxf_rdata};
            5'd2: prdata = {11'b0, 5'(rxf_level), 3'b0, 5'(txf_level),
                            2'b0, frame_err, overrun, rxf_full, ~rxf_empty,
                            txf_full, txf_empty & ~tx_busy};
            5'd3: prdata = {12'b0, rx_wm, 4'b0, tx_wm, 5'b0, loopback, rx_en, tx_en};
            5'd4: prdata = {16'b0, div};
            5'd5: prdata = {29'b0, ie};
            5'd6: prdata = {29'b0, ip};
            default: prdata = '0;
        endcase
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0], pwdata[31:20]};

endmodule
