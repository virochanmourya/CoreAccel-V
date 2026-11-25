// ============================================================================
// Module      : apb_sysctl
// File        : apb_sysctl.sv
// Description : System control (APB slot 8, 0xC000_8000): chip ID, boot
//               straps, reset cause, scratch registers, software reset and a
//               watchdog.
//
//   Offset  Name       Access  Contents
//   0x00    CHIP_ID    R       CHIP_ID parameter ("CAV1")
//   0x04    VERSION    R       VERSION parameter {major[31:24], minor[23:16], patch[15:0]}
//   0x08    BOOT       R       [1:0] boot-mode strap, [8] clock-select strap,
//                              [9] PLL lock (straps latched during the pin reset)
//   0x0C    RST_CAUSE  R/W1C   [0] PIN, [1] WDT, [2] SW: sticky until written
//                              with 1. A pin reset sets PIN and clears the
//                              rest. A new cause wins over a same-cycle clear.
//   0x10    SW_RESET   W       write SW_RESET_KEY: system reset (other values
//                              are ignored); reads 0
//   0x20    SCRATCH0   RW      \
//   0x24    SCRATCH1   RW       | reset by the pin only: they survive a
//   0x28    SCRATCH2   RW       | watchdog or software reset
//   0x2C    SCRATCH3   RW      /
//   0x40    WDT_CTRL   RW      [0] EN, [1] LOCK. LOCK can only be set; once set,
//                              WDT_CTRL and WDT_LOAD writes are ignored until
//                              the next reset (EN cannot be cleared)
//   0x44    WDT_LOAD   RW      timeout in clock cycles (reset WDT_LOAD_RESET)
//   0x48    WDT_COUNT  R       current count
//   0x4C    WDT_KICK   W       write WDT_KICK_KEY: COUNT = LOAD (other values
//                              are ignored, also while locked); reads 0
//   other              PSLVERR
//
//   Watchdog: while EN = 0, COUNT follows LOAD. While EN = 1, COUNT counts
//   down once per clock; a correct kick reloads it. When COUNT is 0 with
//   EN = 1, req_wdt pulses for one cycle (and COUNT reloads): rst_gen then
//   holds the system reset, which clears EN and LOCK.
//
//   Two resets: rst_por (pin only) for RST_CAUSE, the scratch registers and
//   the boot-strap latch; reset (rst_sys) for everything else, including the
//   watchdog and the request flops, so a request clears itself when the
//   reset it caused arrives. req_wdt / req_sw are flop outputs (rst_gen
//   treats them as synchronous pulses). Zero wait states.
// ============================================================================

module apb_sysctl #(
    parameter logic [31:0] CHIP_ID        = 32'h4341_5631,   // "CAV1"
    parameter logic [31:0] VERSION        = 32'h0006_0004,   // 0.6.4 (phase 6d)
    parameter logic [31:0] WDT_LOAD_RESET = 32'hFFFF_FFFF,
    parameter logic [31:0] SW_RESET_KEY   = 32'h5352_5354,   // "SRST"
    parameter logic [31:0] WDT_KICK_KEY   = 32'h4B49_434B    // "KICK"
)(
    input  logic        clk,
    input  logic        reset,         // rst_sys
    input  logic        rst_por,       // pin reset (synchronised)

    // ---- APB4 slave ----
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // ---- Straps and clock status ----
    input  logic [1:0]  boot_strap,    // boot-mode strap pins (asynchronous)
    input  logic        clk_sel,       // latched clock-select strap (clk_gen)
    input  logic        pll_lock,

    // ---- Reset requests to rst_gen (1-cycle pulses, registered) ----
    output logic        req_wdt,
    output logic        req_sw
);

    localparam logic [4:0] W_ID = 5'd0, W_VER = 5'd1, W_BOOT = 5'd2, W_CAUSE = 5'd3,
                           W_SWRST = 5'd4,
                           W_SCR0 = 5'd8, W_SCR3 = 5'd11,
                           W_WCTRL = 5'd16, W_WLOAD = 5'd17, W_WCOUNT = 5'd18, W_WKICK = 5'd19;

    logic        wr, hit;
    logic [4:0]  word;
    assign wr      = psel & penable & pwrite;
    assign word    = paddr[6:2];
    assign hit     = (paddr[11:7] == 5'd0) &
                     (word <= W_SWRST || (word >= W_SCR0 && word <= W_SCR3) ||
                      (word >= W_WCTRL && word <= W_WKICK));
    assign pready  = 1'b1;
    assign pslverr = ~hit;

    logic wr_hit;
    assign wr_hit = wr & hit;

    // ------------------------------------------------------------ boot strap
    // 2-FF synchroniser; the latch follows it only while the pin reset is held.
    (* ASYNC_REG = "TRUE" *) logic [1:0] strap_s1, strap_s2;
    logic [1:0] boot_q;
    always_ff @(posedge clk) begin
        strap_s1 <= boot_strap;
        strap_s2 <= strap_s1;
        if (rst_por) boot_q <= strap_s2;
    end

    // ------------------------------------------------------------ pin-reset domain
    logic [2:0]  cause;          // {SW, WDT, PIN}
    logic [31:0] scratch [4];
    always_ff @(posedge clk) begin
        if (rst_por) begin
            cause <= 3'b001;
            for (int i = 0; i < 4; i++) scratch[i] <= '0;
        end else begin
            cause <= (cause & ~((wr_hit && word == W_CAUSE) ? pwdata[2:0] : 3'b000))
                   | {req_sw, req_wdt, 1'b0};
            if (wr_hit && word >= W_SCR0 && word <= W_SCR3)
                scratch[word[1:0]] <= pwdata;
        end
    end

    // ------------------------------------------------------------ system-reset domain
    logic        wdt_en, wdt_lock;
    logic [31:0] wdt_load, wdt_count;
    logic        kick;
    assign kick = wr_hit && word == W_WKICK && pwdata == WDT_KICK_KEY;

    always_ff @(posedge clk) begin
        if (reset) begin
            wdt_en    <= 1'b0;
            wdt_lock  <= 1'b0;
            wdt_load  <= WDT_LOAD_RESET;
            wdt_count <= WDT_LOAD_RESET;
            req_wdt   <= 1'b0;
            req_sw    <= 1'b0;
        end else begin
            req_sw  <= wr_hit && word == W_SWRST && pwdata == SW_RESET_KEY;
            req_wdt <= 1'b0;
            if (wr_hit && !wdt_lock) begin
                if (word == W_WCTRL) begin
                    wdt_en   <= pwdata[0];
                    wdt_lock <= pwdata[1];
                end
                if (word == W_WLOAD) wdt_load <= pwdata;
            end
            if (!wdt_en || kick) begin
                wdt_count <= wdt_load;
            end else if (wdt_count == '0) begin
                req_wdt   <= 1'b1;
                wdt_count <= wdt_load;
            end else begin
                wdt_count <= wdt_count - 1'b1;
            end
        end
    end

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        case (word)
            W_ID:     prdata = CHIP_ID;
            W_VER:    prdata = VERSION;
            W_BOOT:   prdata = {22'd0, pll_lock, clk_sel, 6'd0, boot_q};
            W_CAUSE:  prdata = {29'd0, cause};
            W_WCTRL:  prdata = {30'd0, wdt_lock, wdt_en};
            W_WLOAD:  prdata = wdt_load;
            W_WCOUNT: prdata = wdt_count;
            default:  if (word >= W_SCR0 && word <= W_SCR3) prdata = scratch[word[1:0]];
        endcase
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0]};

endmodule
