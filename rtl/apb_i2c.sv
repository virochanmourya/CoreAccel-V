// ============================================================================
// Module      : apb_i2c
// File        : apb_i2c.sv
// Description : Hardware I2C master (byte-level commands), APB4 slave.
//
//   Offset  Name      Access  Contents
//   0x00    CTRL      RW      bit0 EN (accept commands), bit1 PAD_SEL (1 = this
//                             master drives the SCL/SDA pads, 0 = the legacy
//                             bit-bang latch does). Reset 0: bit-bang.
//   0x04    PRESC     RW      [PRESC_W-1:0] (minimum 3): SCL quarter period = PRESC + 1
//                             clocks, f_SCL = clk / (4 * (PRESC + 1)) when not
//                             stretched. Reset PRESC_RESET (100 kHz at 100 MHz;
//                             400 kHz: 62).
//   0x08    TXDATA    RW      [7:0] byte for the next WRITE command
//   0x0C    RXDATA    R       [7:0] byte received by the last READ command
//   0x10    CMD       W       bit0 START (START, or repeated START if we own
//                             the bus), bit1 STOP (after the byte, or alone),
//                             bit2 WRITE (send TXDATA, read the ACK bit),
//                             bit3 READ (receive a byte), bit4 NACK (with READ:
//                             answer NACK instead of ACK). Order: START, byte,
//                             STOP. Ignored while a command runs, unless
//                             EN = 1 and PAD_SEL = 1, and unless it has START
//                             or we own the bus (a byte or STOP on a bus we
//                             do not hold would drive SDA while SCL is high;
//                             that case sets STATUS.IGN); WRITE wins over
//                             READ. Reads 0.
//   0x14    STATUS    R       bit0 TIP (command in progress), bit1 RXACK (ACK
//                             bit of the last WRITE: 1 = NACK), bit2 AL (sticky),
//                             bit3 BUS_BUSY (START seen, no STOP yet), bit4 DONE
//                             (sticky: a command finished), bit5 NACKF (sticky:
//                             a WRITE got NACK), bit6 OWN (we hold the bus),
//                             bit7 IGN (sticky: a byte or STOP command was
//                             ignored because we do not own the bus; set only
//                             when it would otherwise have been accepted)
//                     W       write 1 to bits 2 / 4 / 5 / 7 clears them
//   0x18    IE        RW      bit0 DONE, bit1 NACKF, bit2 AL
//   0x1C    IP        R       {AL, NACKF, DONE}
//   other               PSLVERR
//
//   irq = |(IE & IP), a level (PLIC source). Zero wait states.
//
//   Bit timing (quarter periods): data changes a quarter after SCL falls,
//   SCL rises at the half, SDA is sampled at three quarters, SCL falls at
//   the end. After releasing SCL the master waits until it reads SCL high
//   (clock stretching) before it counts on. Arbitration is lost when the
//   master releases SDA for a 1 during a WRITE byte and reads 0 at the
//   sample point, when SDA is low as a START is about to be made, or when a
//   START is asked for while another master holds the bus (BUS_BUSY, not
//   OWN). On AL both lines are released and the command ends without DONE.
//   Pad inputs are raw (asynchronous): 2-FF synchronisers here.
// ============================================================================

module apb_i2c #(
    parameter int PRESC_W     = 16,
    parameter int PRESC_RESET = 249
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

    // ---- Pads (open drain) ----
    output logic        scl_drive_low,
    output logic        sda_drive_low,
    input  logic        scl_pad_in,       // asynchronous
    input  logic        sda_pad_in,
    output logic        pad_sel,          // 1 = this master owns the pads

    output logic        irq
);

    initial begin
        if (PRESC_W < 2 || PRESC_W > 32) $error("apb_i2c: PRESC_W out of range");
    end

    // ------------------------------------------------------------ APB decode
    logic        access, wr, hit;
    logic [4:0]  word;
    assign access  = psel & penable;
    assign wr      = access & pwrite;
    assign word    = paddr[6:2];
    assign hit     = (paddr[11:7] == 5'd0) & (word <= 5'd7);
    assign pready  = 1'b1;
    assign pslverr = ~hit;

    logic               en;
    logic [PRESC_W-1:0] presc;
    logic [7:0]         txdata, rxdata;
    logic [2:0]         ie;
    logic               al, done, nackf, rxack, ign;

    // ------------------------------------------------------------ pad inputs
    (* ASYNC_REG = "TRUE" *) logic [1:0] scl_sync, sda_sync;
    logic scl_in, sda_in, scl_prev, sda_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            scl_sync <= 2'b11;
            sda_sync <= 2'b11;
            scl_prev <= 1'b1;
            sda_prev <= 1'b1;
        end else begin
            scl_sync <= {scl_sync[0], scl_pad_in};
            sda_sync <= {sda_sync[0], sda_pad_in};
            scl_prev <= scl_in;
            sda_prev <= sda_in;
        end
    end
    assign scl_in = scl_sync[1];
    assign sda_in = sda_sync[1];

    // Bus monitor: START = SDA falls while SCL high, STOP = SDA rises while SCL high.
    logic bus_busy, start_seen, stop_seen;
    assign start_seen = scl_in & scl_prev & sda_prev & ~sda_in;
    assign stop_seen  = scl_in & scl_prev & ~sda_prev & sda_in;
    always_ff @(posedge clk) begin
        if (reset)           bus_busy <= 1'b0;
        else if (start_seen) bus_busy <= 1'b1;
        else if (stop_seen)  bus_busy <= 1'b0;
    end

    // ------------------------------------------------------------ engine
    typedef enum logic [2:0] {E_IDLE, E_START, E_BIT, E_STOP} est_t;
    est_t               st;
    logic [1:0]         q;            // quarter within the current step (0..3)
    logic [PRESC_W-1:0] cnt;
    logic [3:0]         bitn;         // 0..8 (8 = ACK bit)
    logic               scl_o, sda_o; // 1 = release
    logic               own;
    logic               c_stop, c_write, c_read, c_nack;
    logic [7:0]         sh;
    logic               tip;

    logic cmd_wr, go, busy_any, cmd_ok, ev_ign;
    logic ev_al, ev_done, ev_nack;      // one-cycle event pulses (registered)
    logic c_start_in, c_stop_in, c_write_in, c_read_in;
    assign cmd_wr     = wr & hit & (word == 5'd4);
    assign c_start_in = pwdata[0];
    assign c_stop_in  = pwdata[1];
    assign c_write_in = pwdata[2];
    assign c_read_in  = pwdata[3] & ~pwdata[2];
    assign tip        = (st != E_IDLE);
    // TIP covers the event cycle too, so TIP = 0 implies the sticky flags are set.
    assign busy_any   = tip | ev_al | ev_done | ev_nack;
    assign cmd_ok     = cmd_wr & en & pad_sel & ~busy_any & (|pwdata[3:0]);
    assign go         = cmd_ok & (c_start_in | own);
    assign ev_ign     = cmd_ok & ~c_start_in & ~own;

    // A quarter elapses when the counter runs out; while the master releases
    // SCL and the line still reads low (stretched, or not yet risen), it waits.
    logic scl_wait, qtick;
    assign scl_wait = scl_o & ~scl_in;
    assign qtick    = tip & (cnt == '0) & ~scl_wait;

    always_ff @(posedge clk) begin
        ev_al   <= 1'b0;
        ev_done <= 1'b0;
        ev_nack <= 1'b0;
        if (reset) begin
            st      <= E_IDLE;
            q       <= '0;
            cnt     <= '0;
            bitn    <= '0;
            scl_o   <= 1'b1;
            sda_o   <= 1'b1;
            own     <= 1'b0;
            c_stop  <= 1'b0;
            c_write <= 1'b0;
            c_read  <= 1'b0;
            c_nack  <= 1'b0;
            sh      <= '0;
            rxdata  <= '0;
            rxack   <= 1'b0;
        end else if (go) begin
            c_stop  <= c_stop_in;
            c_write <= c_write_in;
            c_read  <= c_read_in;
            c_nack  <= pwdata[4];
            sh      <= txdata;
            q       <= '0;
            cnt     <= presc;
            bitn    <= '0;
            if (c_start_in) begin
                if (bus_busy && !own) begin        // someone else holds the bus
                    ev_al <= 1'b1;
                end else begin
                    st <= E_START;
                end
            end else if (c_write_in || c_read_in) begin
                st <= E_BIT;
            end else begin
                st <= E_STOP;
            end
        end else if (tip) begin
            if (cnt != '0 && !scl_wait) cnt <= cnt - 1'b1;
            if (qtick) begin
                cnt <= presc;
                q   <= q + 1'b1;
                case (st)
                    // START: release SDA, release SCL, SDA low, SCL low
                    // (one quarter each; from an idle bus the first two are no-ops).
                    E_START: begin
                        case (q)
                            2'd0: sda_o <= 1'b1;
                            2'd1: scl_o <= 1'b1;
                            2'd2: begin
                                if (!sda_in) begin        // SDA held low: lost
                                    ev_al <= 1'b1;
                                    st    <= E_IDLE;
                                    scl_o <= 1'b1;
                                    sda_o <= 1'b1;
                                    own   <= 1'b0;
                                end else begin
                                    sda_o <= 1'b0;
                                end
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                own   <= 1'b1;
                                if (c_write || c_read) st <= E_BIT;
                                else if (c_stop)       st <= E_STOP;
                                else begin
                                    st      <= E_IDLE;
                                    ev_done <= 1'b1;
                                end
                            end
                        endcase
                    end
                    // One bit: drive data, SCL up, sample, SCL down.
                    E_BIT: begin
                        case (q)
                            2'd0: begin
                                if (bitn == 4'd8) sda_o <= c_write ? 1'b1 : c_nack;
                                else              sda_o <= c_write ? sh[7] : 1'b1;
                            end
                            2'd1: scl_o <= 1'b1;
                            2'd2: begin
                                if (bitn == 4'd8) begin
                                    if (c_write) rxack <= sda_in;
                                end else begin
                                    if (c_write && sda_o && !sda_in) begin  // lost
                                        ev_al <= 1'b1;
                                        st    <= E_IDLE;
                                        scl_o <= 1'b1;
                                        sda_o <= 1'b1;
                                        own   <= 1'b0;
                                    end
                                    sh <= {sh[6:0], sda_in};
                                end
                            end
                            2'd3: begin
                                scl_o <= 1'b0;
                                if (bitn == 4'd8) begin
                                    if (c_read) rxdata <= sh;
                                    if (c_write && rxack) ev_nack <= 1'b1;
                                    if (c_stop) st <= E_STOP;
                                    else begin
                                        st      <= E_IDLE;
                                        ev_done <= 1'b1;
                                    end
                                end
                                bitn <= (bitn == 4'd8) ? 4'd0 : bitn + 1'b1;
                            end
                        endcase
                    end
                    // STOP: SDA low, SCL up, SDA up, bus-free quarter.
                    E_STOP: begin
                        case (q)
                            2'd0: sda_o <= 1'b0;
                            2'd1: scl_o <= 1'b1;
                            2'd2: sda_o <= 1'b1;
                            2'd3: begin
                                st      <= E_IDLE;
                                own     <= 1'b0;
                                ev_done <= 1'b1;
                            end
                        endcase
                    end
                    default: st <= E_IDLE;
                endcase
            end
        end
        // Disabling the block, or handing the pads back, drops everything.
        if (!reset && (!en || !pad_sel)) begin
            st    <= E_IDLE;
            scl_o <= 1'b1;
            sda_o <= 1'b1;
            own   <= 1'b0;
        end
    end

    assign scl_drive_low = ~scl_o;
    assign sda_drive_low = ~sda_o;

    // ------------------------------------------------------------ registers
    always_ff @(posedge clk) begin
        if (reset) begin
            en      <= 1'b0;
            pad_sel <= 1'b0;
            presc   <= PRESC_W'(PRESC_RESET);
            txdata  <= '0;
            ie      <= '0;
            al      <= 1'b0;
            done    <= 1'b0;
            nackf   <= 1'b0;
            ign     <= 1'b0;
        end else begin
            if (wr && hit && word == 5'd0) begin
                en      <= pwdata[0];
                pad_sel <= pwdata[1];
            end
            // Minimum 3: the bus monitor (2-FF synchronised) must see our own
            // STOP before the next command can start.
            if (wr && hit && word == 5'd1)
                presc <= (pwdata[PRESC_W-1:0] < PRESC_W'(3)) ? PRESC_W'(3) : pwdata[PRESC_W-1:0];
            if (wr && hit && word == 5'd2) txdata <= pwdata[7:0];
            if (wr && hit && word == 5'd6) ie     <= pwdata[2:0];
            if (wr && hit && word == 5'd5) begin
                if (pwdata[2]) al    <= 1'b0;
                if (pwdata[4]) done  <= 1'b0;
                if (pwdata[5]) nackf <= 1'b0;
                if (pwdata[7]) ign   <= 1'b0;
            end
            // Events win over a clear in the same cycle.
            if (ev_al)   al    <= 1'b1;
            if (ev_done) done  <= 1'b1;
            if (ev_nack) nackf <= 1'b1;
            if (ev_ign)  ign   <= 1'b1;
        end
    end

    logic [2:0] ip;
    assign ip  = {al, nackf, done};
    assign irq = |(ie & ip);

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        case (word)
            5'd0: prdata = {30'b0, pad_sel, en};
            5'd1: prdata = 32'(presc);
            5'd2: prdata = {24'b0, txdata};
            5'd3: prdata = {24'b0, rxdata};
            5'd5: prdata = {24'b0, ign, own, nackf, done, bus_busy, al, rxack, busy_any};
            5'd6: prdata = {29'b0, ie};
            5'd7: prdata = {29'b0, ip};
            default: prdata = '0;
        endcase
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0], pwdata};

endmodule
