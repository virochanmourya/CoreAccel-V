// ============================================================================
// Module      : periph_subsys
// File        : periph_subsys.sv
// Description : Data-bus fabric and peripherals behind the core's AXI4 port.
//
//   AXI4 (from dbus_axi_master)
//     -> axi4_demux: 0xC000_0000-0xC000_FFFF and the PLIC region
//                    0xC400_0000-0xC43F_FFFF go to slave 0; with IMEM_WIN,
//                    0x1000_0000-0x1000_1FFF goes to slave 1; anything
//                    else -> built-in default slave (DECERR)
//     -> slave 1 (IMEM_WIN = 1 only): axi4_imem_win, the boot loader's IMEM
//          write window (word writes -> IMEM write port; reads SLVERR).
//          Proposal numbering: S3 (S1 = APB bridge, S2 = DMA, not built).
//     -> slave 0: axi4_to_apb4, APB4 select per 4 KB slot:
//          slot 0  0xC000_0000  legacy page (GPIO bit-bang I2C, UART TX, 7-seg)
//          slot 1  0xC000_1000  UART0 (TX/RX, FIFOs, irq)
//          slot 2  0xC000_2000  SPI master (modes 0-3, FIFOs, NCS chip selects)
//          slot 3  0xC000_3000  I2C master (byte commands; shares the pads
//                               with the legacy bit-bang latch, reset = bit-bang)
//          slot 4  0xC000_4000  GPIO (GPIO_W pins, edge/level interrupts)
//          slot 5  0xC000_5000  timers (2 x 32-bit), PWM, input capture
//          slot 8  0xC000_8000  system control: IDs, straps, reset cause,
//                               scratch, software reset, watchdog
//          6, 7, 9..15          reserved: PSLVERR
//          PLIC    0xC400_0000  standard layout, sources 1..16
//                               (UART0 = 1, SPI = 2, I2C = 3, GPIO = 4,
//                               timers = 5)
//   The core-local words of slot 0 (mtimer 0x100-0x10F, tohost 0xFFC) are
//   answered inside the core and never reach this bus.
//
//   wait_inj: test hook (tied to 0 in the core): wait states on the AXI
//   READYs (demux), on accepting a transfer / showing R-B (bridge), and on
//   PREADY here: while it is 1 the bridge sees PREADY low in ACCESS, and
//   the slaves see PENABLE low (a longer SETUP), so every slave still acts
//   exactly once per transfer, when PSEL & PENABLE are both 1.
// ============================================================================

module periph_subsys #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200,
    parameter bit SEG_EN    = 1'b1,
    parameter int UART0_FIFO_DEPTH = 16,
    parameter int SPI_FIFO_DEPTH = 8,
    parameter int SPI_NCS        = 2,
    parameter int I2C_PRESC_RESET = CLK_FREQ / (4 * 100_000) - 1,   // 100 kHz
    parameter int GPIO_W         = 16,
    parameter int TMR_NPWM       = 4,
    parameter int TMR_NCAP       = 2,
    parameter int PLIC_NSRC  = 16,
    parameter int PLIC_PRIO_W = 3,
    parameter bit IMEM_WIN    = 1'b0,   // IMEM write window at 0x1000_0000
    parameter int IMEM_AW     = 11      // IMEM word-address bits (window size)
)(
    input  logic        clk,
    input  logic        reset,         // rst_sys
    input  logic        rst_por,       // pin reset (system control only)
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
    output logic [3:0]  an,
    output logic        uart0_txd,
    input  logic        uart0_rxd,       // asynchronous
    output logic        spi_sck,
    output logic        spi_mosi,
    input  logic        spi_miso,
    output logic [SPI_NCS-1:0] spi_cs_n,
    output logic [GPIO_W-1:0]  gpio_out,
    output logic [GPIO_W-1:0]  gpio_oe,
    input  logic [GPIO_W-1:0]  gpio_in,  // asynchronous
    output logic [TMR_NPWM-1:0] pwm_out,
    input  logic [TMR_NCAP-1:0] cap_in,  // asynchronous

    // ---- System control: straps in, reset requests out ----
    input  logic [1:0]  boot_strap,      // asynchronous
    input  logic        clk_sel,
    input  logic        pll_lock,
    output logic        rst_req_wdt,
    output logic        rst_req_sw,

    // ---- PLIC output (to the core's MEIP) ----
    output logic        plic_eip,

    // ---- IMEM write port (IMEM_WIN = 1; tied to 0 otherwise) ----
    output logic               imem_we,
    output logic [IMEM_AW-1:0] imem_waddr,
    output logic [31:0]        imem_wdata
);

    // PLIC source map: 1 = UART0, 2 = SPI, 3 = I2C, 4 = GPIO, 5 = timers;
    // 6..PLIC_NSRC reserved (DMA in a later step).
    logic                 uart0_irq, spi_irq, i2c_irq, gpio_irq, tmr_irq;
    logic [PLIC_NSRC:1]   irq_src;
    always_comb begin
        irq_src    = '0;
        irq_src[1] = uart0_irq;
        irq_src[2] = spi_irq;
        irq_src[3] = i2c_irq;
        irq_src[4] = gpio_irq;
        irq_src[5] = tmr_irq;
    end

    // ------------------------------------------------------------ AXI demux
    // slave 0: APB bridge; slave 1: IMEM window (IMEM_WIN only). The window
    // region is always listed; without the window it names the default
    // slave (index NS), so 0x1000_0000 stays DECERR exactly as before.
    localparam int NS = IMEM_WIN ? 2 : 1;
    localparam int NR = 3;
    localparam logic [31:0] WIN_BASE = 32'h1000_0000;
    localparam logic [31:0] WIN_MASK = ~(32'(4 << IMEM_AW) - 32'd1);

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
        .REGION_BASE ({WIN_BASE, 32'hC400_0000, 32'hC000_0000}),
        .REGION_MASK ({WIN_MASK, 32'hFFC0_0000, 32'hFFFF_0000}),
        .REGION_SLV  ({8'(IMEM_WIN ? 1 : NS), 8'd0, 8'd0})
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

    // ------------------------------------------------------------ IMEM window
    generate
        if (IMEM_WIN) begin : g_imem_win
            axi4_imem_win #(.AW (IMEM_AW)) u_imem_win (
                .clk (clk), .reset (reset),
                .s_awvalid (d_awvalid[1]), .s_awready (d_awready[1]), .s_awaddr (d_awaddr),
                .s_awlen (d_awlen), .s_awid (d_awid),
                .s_wvalid (d_wvalid[1]), .s_wready (d_wready[1]), .s_wdata (d_wdata),
                .s_wstrb (d_wstrb), .s_wlast (d_wlast),
                .s_bvalid (d_bvalid[1]), .s_bready (d_bready[1]), .s_bresp (d_bresp[1]),
                .s_bid (d_bid[1]),
                .s_arvalid (d_arvalid[1]), .s_arready (d_arready[1]), .s_arlen (d_arlen),
                .s_arid (d_arid),
                .s_rvalid (d_rvalid[1]), .s_rready (d_rready[1]), .s_rdata (d_rdata[1]),
                .s_rresp (d_rresp[1]), .s_rlast (d_rlast[1]), .s_rid (d_rid[1]),
                .imem_we (imem_we), .imem_waddr (imem_waddr), .imem_wdata (imem_wdata)
            );
        end else begin : g_no_imem_win
            assign imem_we    = 1'b0;
            assign imem_waddr = '0;
            assign imem_wdata = '0;
        end
    endgenerate

    // ------------------------------------------------------------ AXI -> APB4
    localparam int NSLOT = 16;
    localparam int NP    = NSLOT + 1;          // + PLIC
    localparam int P_LEGACY = 0;
    localparam int P_UART0  = 1;
    localparam int P_SPI    = 2;
    localparam int P_I2C    = 3;
    localparam int P_GPIO   = 4;
    localparam int P_TMR    = 5;
    localparam int P_SYSCTL = 8;
    localparam int P_PLIC   = NSLOT;

    logic [31:0]         paddr, pwdata;
    logic [NP-1:0]       psel;
    logic                penable, pwrite;
    logic [3:0]          pstrb;
    logic [2:0]          pprot;
    logic [NP-1:0][31:0] prdata;
    logic [NP-1:0]       pready, pslverr;
    logic [NP-1:0]       pready_raw;        // slaves' own PREADY
    logic                s_penable;         // PENABLE as the slaves see it

    assign s_penable = penable & ~wait_inj;
    assign pready    = pready_raw & {NP{~wait_inj}};

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
    // Slot 0: legacy page (its SCL/SDA latch goes through the pad mux below)
    logic bb_scl_low, bb_sda_low;
    apb_legacy_page #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .SEG_EN    (SEG_EN)
    ) u_legacy (
        .clk (clk), .reset (reset),
        .psel (psel[P_LEGACY]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_LEGACY]), .pready (pready_raw[P_LEGACY]),
        .pslverr (pslverr[P_LEGACY]),
        .scl_drive_low (bb_scl_low), .sda_drive_low (bb_sda_low),
        .scl_pad_in (scl_pad_in), .sda_pad_in (sda_pad_in),
        .uart_tx_out (uart_tx_out), .seg (seg), .dp (dp), .an (an)
    );

    // Slot 1: UART0
    apb_uart #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (UART0_FIFO_DEPTH)
    ) u_uart0 (
        .clk (clk), .reset (reset),
        .psel (psel[P_UART0]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_UART0]), .pready (pready_raw[P_UART0]),
        .pslverr (pslverr[P_UART0]),
        .txd (uart0_txd), .rxd (uart0_rxd), .irq (uart0_irq)
    );

    // Slot 2: SPI master
    apb_spi #(
        .FIFO_DEPTH (SPI_FIFO_DEPTH),
        .NCS        (SPI_NCS)
    ) u_spi (
        .clk (clk), .reset (reset),
        .psel (psel[P_SPI]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_SPI]), .pready (pready_raw[P_SPI]),
        .pslverr (pslverr[P_SPI]),
        .sck (spi_sck), .mosi (spi_mosi), .miso (spi_miso), .cs_n (spi_cs_n),
        .irq (spi_irq)
    );

    // Slot 3: I2C master, and the SCL/SDA pad mux (reset: bit-bang latch)
    logic hw_scl_low, hw_sda_low, i2c_pad_sel;
    apb_i2c #(
        .PRESC_RESET (I2C_PRESC_RESET)
    ) u_i2c (
        .clk (clk), .reset (reset),
        .psel (psel[P_I2C]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_I2C]), .pready (pready_raw[P_I2C]),
        .pslverr (pslverr[P_I2C]),
        .scl_drive_low (hw_scl_low), .sda_drive_low (hw_sda_low),
        .scl_pad_in (scl_pad_in), .sda_pad_in (sda_pad_in),
        .pad_sel (i2c_pad_sel),
        .irq (i2c_irq)
    );
    assign scl_drive_low = i2c_pad_sel ? hw_scl_low : bb_scl_low;
    assign sda_drive_low = i2c_pad_sel ? hw_sda_low : bb_sda_low;

    // Slot 4: GPIO
    apb_gpio #(
        .W (GPIO_W)
    ) u_gpio (
        .clk (clk), .reset (reset),
        .psel (psel[P_GPIO]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_GPIO]), .pready (pready_raw[P_GPIO]),
        .pslverr (pslverr[P_GPIO]),
        .gpio_out (gpio_out), .gpio_oe (gpio_oe), .gpio_in (gpio_in),
        .irq (gpio_irq)
    );

    // Slot 5: timers, PWM, input capture
    apb_timer #(
        .NPWM (TMR_NPWM),
        .NCAP (TMR_NCAP)
    ) u_timer (
        .clk (clk), .reset (reset),
        .psel (psel[P_TMR]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_TMR]), .pready (pready_raw[P_TMR]),
        .pslverr (pslverr[P_TMR]),
        .pwm_out (pwm_out), .cap_in (cap_in),
        .irq (tmr_irq)
    );

    // Slot 8: system control and watchdog
    apb_sysctl u_sysctl (
        .clk (clk), .reset (reset), .rst_por (rst_por),
        .psel (psel[P_SYSCTL]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_SYSCTL]), .pready (pready_raw[P_SYSCTL]),
        .pslverr (pslverr[P_SYSCTL]),
        .boot_strap (boot_strap), .clk_sel (clk_sel), .pll_lock (pll_lock),
        .req_wdt (rst_req_wdt), .req_sw (rst_req_sw)
    );

    // PLIC (its own APB select)
    apb_plic #(
        .NSRC   (PLIC_NSRC),
        .PRIO_W (PLIC_PRIO_W)
    ) u_plic (
        .clk (clk), .reset (reset),
        .psel (psel[P_PLIC]), .penable (s_penable), .pwrite (pwrite), .paddr (paddr),
        .pwdata (pwdata), .prdata (prdata[P_PLIC]), .pready (pready_raw[P_PLIC]),
        .pslverr (pslverr[P_PLIC]),
        .src (irq_src), .eip (plic_eip)
    );

    // Unused selects: answer PSLVERR at once.
    generate
        for (genvar i = 6; i < NSLOT; i++) begin : g_empty
            if (i != P_SYSCTL) begin : g_slot
                assign prdata[i]  = '0;
                assign pready_raw[i] = 1'b1;
                assign pslverr[i] = 1'b1;
            end
        end
    endgenerate

    // PSTRB/PPROT: the slaves are word registers (lane-replicated data).
    logic unused;
    assign unused = ^{pstrb, pprot, psel[NSLOT-1:6]};

endmodule
