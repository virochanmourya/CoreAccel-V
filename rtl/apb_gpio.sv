// ============================================================================
// Module      : apb_gpio
// File        : apb_gpio.sv
// Description : General-purpose I/O, W pins (W <= 32), APB4 slave.
//
//   Offset  Name    Access  Contents (bit i = pin i)
//   0x00    OUT     RW      output latch
//   0x04    OE      RW      1 = drive the pin from OUT, 0 = input (reset 0)
//   0x08    IN      R       pin levels through a 2-FF synchroniser
//   0x0C    SET     W       OUT |= value (reads 0)
//   0x10    CLR     W       OUT &= ~value (reads 0)
//   0x14    IE      RW      interrupt enable
//   0x18    MODE    RW      0 = edge, 1 = level
//   0x1C    POL     RW      edge: 0 rising, 1 falling; level: 0 high, 1 low
//   0x20    BOTH    RW      edge mode: 1 = both edges (POL ignored)
//   0x24    STATUS  R       edge pins: sticky event; level pins: the
//                           current level matches POL (follows the pin)
//                   W       write 1 clears a sticky edge bit (level bits
//                           ignore it); an event wins over a clear
//   other           PSLVERR
//
//   STATUS records events whatever IE is; irq = |(STATUS & IE), a level
//   (one PLIC source). Edges and levels are taken from the synchronised
//   input, so a pin driven as an output also sees its own edges.
//   Zero wait states. Pads are outside (tri-state / pad cells at the top).
// ============================================================================

module apb_gpio #(
    parameter int W = 16
)(
    input  logic         clk,
    input  logic         reset,

    // ---- APB4 slave ----
    input  logic         psel,
    input  logic         penable,
    input  logic         pwrite,
    input  logic [31:0]  paddr,
    input  logic [31:0]  pwdata,
    output logic [31:0]  prdata,
    output logic         pready,
    output logic         pslverr,

    // ---- Pins ----
    output logic [W-1:0] gpio_out,
    output logic [W-1:0] gpio_oe,
    input  logic [W-1:0] gpio_in,      // asynchronous

    output logic         irq
);

    initial begin
        if (W < 1 || W > 32) $error("apb_gpio: W out of range");
    end

    logic        wr, hit;
    logic [4:0]  word;
    assign wr      = psel & penable & pwrite;
    assign word    = paddr[6:2];
    assign hit     = (paddr[11:7] == 5'd0) & (word <= 5'd9);
    assign pready  = 1'b1;
    assign pslverr = ~hit;

    logic [W-1:0] wdat;
    assign wdat = pwdata[W-1:0];

    // ------------------------------------------------------------ inputs
    (* ASYNC_REG = "TRUE" *) logic [W-1:0] sync1, sync2;
    logic [W-1:0] prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            sync1 <= '0;
            sync2 <= '0;
            prev  <= '0;
        end else begin
            sync1 <= gpio_in;
            sync2 <= sync1;
            prev  <= sync2;
        end
    end

    // ------------------------------------------------------------ registers
    logic [W-1:0] ie, mode, pol, both, edge_q;
    logic [W-1:0] rise, fall, ev, lvl, status;
    assign rise   = sync2 & ~prev;
    assign fall   = ~sync2 & prev;
    // per pin: both edges, or the edge POL selects (bitwise, not a vector ?:)
    assign ev     = ~mode & ((both & (rise | fall)) | (~both & pol & fall) |
                             (~both & ~pol & rise));
    assign lvl    = mode & (sync2 ^ pol);
    assign status = (mode & lvl) | (~mode & edge_q);

    always_ff @(posedge clk) begin
        if (reset) begin
            gpio_out <= '0;
            gpio_oe  <= '0;
            ie       <= '0;
            mode     <= '0;
            pol      <= '0;
            both     <= '0;
            edge_q   <= '0;
        end else begin
            if (wr && hit) begin
                case (word)
                    5'd0: gpio_out <= wdat;
                    5'd1: gpio_oe  <= wdat;
                    5'd3: gpio_out <= gpio_out | wdat;
                    5'd4: gpio_out <= gpio_out & ~wdat;
                    5'd5: ie       <= wdat;
                    5'd6: mode     <= wdat;
                    5'd7: pol      <= wdat;
                    5'd8: both     <= wdat;
                    default: ;
                endcase
            end
            // Sticky edge bits: W1C, an event in the same cycle wins; a
            // pin in level mode keeps no edge history.
            edge_q <= ((edge_q & ~((wr && hit && word == 5'd9) ? wdat : '0)) | ev) & ~mode;
        end
    end

    assign irq = |(status & ie);

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        case (word)
            5'd0: prdata[W-1:0] = gpio_out;
            5'd1: prdata[W-1:0] = gpio_oe;
            5'd2: prdata[W-1:0] = sync2;
            5'd5: prdata[W-1:0] = ie;
            5'd6: prdata[W-1:0] = mode;
            5'd7: prdata[W-1:0] = pol;
            5'd8: prdata[W-1:0] = both;
            5'd9: prdata[W-1:0] = status;
            default: prdata = '0;
        endcase
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0], pwdata};

endmodule
