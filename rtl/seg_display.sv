// ============================================================================
// Module      : seg_display
// File        : seg_display.sv
// Description : 4-Digit 7-Segment Hardware Multiplexer.
//               Drives a common-anode 4-digit 7-segment display with ~1 kHz
//               multiplexing and hex/BCD decoding.
// ============================================================================

module seg_display #(
    parameter CLK_FREQ      = 100_000_000,
    parameter REFRESH_HZ    = 1_000,        // ~1 kHz multiplex rate
    parameter CLKS_PER_MUX  = CLK_FREQ / REFRESH_HZ   // 100,000
)(
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] display_data,  // 4 hex/BCD digits: {d3, d2, d1, d0}

    output logic [3:0]  an,            // Anode enables (active-low)
    output logic [6:0]  seg,           // Cathode segments a-g (active-low)
    output logic        dp             // Decimal point (active-low, tied OFF)
);

    // Refresh Counter
    logic [16:0] refresh_cnt;          // Counts to CLKS_PER_MUX (100,000)
    logic [1:0]  digit_sel;            // Active digit selector (0-3)

    always_ff @(posedge clk) begin
        if (reset) begin
            refresh_cnt <= '0;
            digit_sel   <= '0;
        end else if (refresh_cnt == CLKS_PER_MUX[16:0] - 1) begin
            refresh_cnt <= '0;
            digit_sel   <= digit_sel + 1;
        end else begin
            refresh_cnt <= refresh_cnt + 1;
        end
    end

    // Anode Selector (Active-Low)
    // Only one digit is ON at a time. The rest are driven HIGH (OFF).
    always_comb begin
        case (digit_sel)
            2'd0: an = 4'b1110;   // Digit 0 (rightmost) ON
            2'd1: an = 4'b1101;   // Digit 1 ON
            2'd2: an = 4'b1011;   // Digit 2 ON
            2'd3: an = 4'b0111;   // Digit 3 (leftmost) ON
            default: an = 4'b1111; // All OFF
        endcase
    end

    // Digit Data Selector
    logic [3:0] current_nibble;

    always_comb begin
        case (digit_sel)
            2'd0: current_nibble = display_data[3:0];    // Ones
            2'd1: current_nibble = display_data[7:4];    // Tens
            2'd2: current_nibble = display_data[11:8];   // Hundreds
            2'd3: current_nibble = display_data[15:12];  // Thousands
            default: current_nibble = 4'h0;
        endcase
    end

    // 7-Segment Hex Decoder (Active-Low Cathodes)
    //
    //   Segment layout:     a
    //                       ---
    //                    f |   | b
    //                       -g-
    //                    e |   | c
    //                       ---
    //                        d
    //
    //   seg[6:0] = {g, f, e, d, c, b, a}
    //   0 = segment ON (active-low)
    //
    always_comb begin
        case (current_nibble)
            //                 gfedcba
            4'h0: seg = 7'b1000000;   // 0
            4'h1: seg = 7'b1111001;   // 1
            4'h2: seg = 7'b0100100;   // 2
            4'h3: seg = 7'b0110000;   // 3
            4'h4: seg = 7'b0011001;   // 4
            4'h5: seg = 7'b0010010;   // 5
            4'h6: seg = 7'b0000010;   // 6
            4'h7: seg = 7'b1111000;   // 7
            4'h8: seg = 7'b0000000;   // 8
            4'h9: seg = 7'b0010000;   // 9
            4'hA: seg = 7'b0001000;   // A
            4'hB: seg = 7'b0000011;   // b
            4'hC: seg = 7'b1000110;   // C
            4'hD: seg = 7'b0100001;   // d
            4'hE: seg = 7'b0000110;   // E
            4'hF: seg = 7'b0001110;   // F
            default: seg = 7'b1111111; // All OFF
        endcase
    end

    // Decimal Point (OFF)
    assign dp = 1'b1;  // Active-low: 1 = OFF

endmodule
