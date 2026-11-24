// ============================================================================
// Module      : apb_legacy_page
// File        : apb_legacy_page.sv
// Description : The original peripheral page (0xC000_0000) as an APB4 slave.
//               Same registers and behaviour as before Phase 6:
//                 +0x0  GPIO: write bit0 = SCL, bit1 = SDA (1 = release,
//                       0 = drive low; open drain). Read: synchronised pins.
//                 +0x4  UART TX: write starts a byte (data[7:0]); read bit0 = busy
//                 +0x8  7-segment value [15:0] (only with SEG_EN = 1)
//                 +0xC  GPIO output latch (read-only debug)
//               Word registers: they take the lane-replicated write data
//               and ignore PSTRB, so SB to the UART sends rs2[7:0].
//               Any other offset answers PSLVERR (the core-local mtimer and
//               tohost words in this page never reach the bus).
//               Zero wait states (PREADY = 1).
//
//               SEG_EN = 0 (ASIC): no 7-segment controller; +0x8 is
//               PSLVERR and the display outputs are tied off.
// ============================================================================

module apb_legacy_page #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200,
    parameter bit SEG_EN    = 1'b1
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
    output logic        scl_drive_low,
    output logic        sda_drive_low,
    input  logic        scl_pad_in,       // raw pad level (asynchronous)
    input  logic        sda_pad_in,
    output logic        uart_tx_out,
    output logic [6:0]  seg,
    output logic        dp,
    output logic [3:0]  an
);

    logic        in_page0, hit, access;
    logic [1:0]  reg_sel;
    logic        gpio_we, uart_we, seg_we;
    logic [1:0]  gpio_out_reg;
    (* ASYNC_REG = "TRUE" *) logic [1:0] i2c_sync1, i2c_sync2;  // {SDA, SCL}
    logic        uart_tx_busy;
    logic [15:0] seg_display_data;

    assign in_page0 = (paddr[11:4] == 8'h00);
    assign reg_sel  = paddr[3:2];
    assign hit      = in_page0 & (SEG_EN | (reg_sel != 2'b10));
    assign access   = psel & penable;          // ACCESS phase (PREADY = 1)

    assign pready  = 1'b1;
    assign pslverr = ~hit;

    assign gpio_we = access & pwrite & hit & (reg_sel == 2'b00);
    assign uart_we = access & pwrite & hit & (reg_sel == 2'b01);
    assign seg_we  = access & pwrite & hit & (reg_sel == 2'b10);

    // ---- GPIO output latch (open-drain I2C lines) ----
    always_ff @(posedge clk) begin
        if (reset)        gpio_out_reg <= 2'b11;   // both released
        else if (gpio_we) gpio_out_reg <= pwdata[1:0];
    end
    assign scl_drive_low = ~gpio_out_reg[0];
    assign sda_drive_low = ~gpio_out_reg[1];

    // ---- Pin input synchroniser ----
    always_ff @(posedge clk) begin
        if (reset) begin
            i2c_sync1 <= 2'b11;
            i2c_sync2 <= 2'b11;
        end else begin
            i2c_sync1 <= {sda_pad_in, scl_pad_in};
            i2c_sync2 <= i2c_sync1;
        end
    end

    // ---- UART TX ----
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk),
        .reset    (reset),
        .tx_data  (pwdata[7:0]),
        .tx_valid (uart_we),
        .tx_out   (uart_tx_out),
        .tx_busy  (uart_tx_busy)
    );

    // ---- 7-segment (FPGA board only) ----
    generate
        if (SEG_EN) begin : g_seg
            always_ff @(posedge clk) begin
                if (reset)       seg_display_data <= 16'h0000;
                else if (seg_we) seg_display_data <= pwdata[15:0];
            end
            seg_display u_seg_display (
                .clk          (clk),
                .reset        (reset),
                .display_data (seg_display_data),
                .an           (an),
                .seg          (seg),
                .dp           (dp)
            );
        end else begin : g_no_seg
            assign seg_display_data = 16'h0000;
            assign seg = 7'h7F;      // segments off (active low)
            assign dp  = 1'b1;
            assign an  = 4'hF;
        end
    endgenerate

    // ---- Read-back ----
    always_comb begin
        case (reg_sel)
            2'b00:   prdata = {30'b0, i2c_sync2};            // {SDA, SCL} pins
            2'b01:   prdata = {31'b0, uart_tx_busy};
            2'b10:   prdata = {16'b0, seg_display_data};
            default: prdata = {30'b0, gpio_out_reg};         // debug: output latch
        endcase
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0], pwdata[31:16], seg_we & ~SEG_EN};

endmodule
