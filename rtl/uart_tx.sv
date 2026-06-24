// ============================================================================
// Module: uart_tx (One-Way UART Transmitter — 8N1)
// File:   uart_tx.sv
//
// PURPOSE:
//   Transmits 8-bit data over a single UART TX line using 8N1 format
//   (1 start bit, 8 data bits LSB-first, 1 stop bit, no parity).
//
//   Interface:
//     tx_valid (pulse) — Loads data and starts transmission
//     tx_data[7:0]     — Byte to transmit (latched on tx_valid)
//     tx_out           — Serial output line (active-high idle)
//     tx_busy          — HIGH while a byte is in transit
//
//   Baud rate is derived from CLKS_PER_BIT = CLK_FREQ / BAUD_RATE.
//   Default: 100 MHz / 115200 = 868 clocks per bit.
//
// TARGET: Xilinx Artix-7 — connects to Basys 3 onboard USB-UART (FTDI)
// ============================================================================

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200,
    // Derived: number of clock cycles per UART bit period
    parameter CLKS_PER_BIT = CLK_FREQ / BAUD_RATE   // 868 for 100M/115200
)(
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] tx_data,       // Byte to transmit
    input  logic       tx_valid,      // Pulse HIGH for 1 cycle to start TX
    output logic       tx_out,        // Serial output (idle HIGH)
    output logic       tx_busy        // HIGH = transmission in progress
);

    // ---- FSM States ----
    typedef enum logic [1:0] {
        S_IDLE  = 2'b00,
        S_START = 2'b01,
        S_DATA  = 2'b10,
        S_STOP  = 2'b11
    } state_t;

    state_t              state;
    logic [15:0]         baud_cnt;     // Baud rate clock divider counter
    logic [2:0]          bit_idx;      // Current data bit index (0-7)
    logic [7:0]          data_reg;     // Latched copy of tx_data

    // ---- Busy Flag ----
    assign tx_busy = (state != S_IDLE);

    // ---- Main FSM ----
    always_ff @(posedge clk) begin
        if (reset) begin
            state    <= S_IDLE;
            tx_out   <= 1'b1;         // UART idle = HIGH
            baud_cnt <= '0;
            bit_idx  <= '0;
            data_reg <= '0;
        end else begin
            case (state)
                // --------------------------------------------------------
                // IDLE: Wait for tx_valid pulse. Line held HIGH.
                // --------------------------------------------------------
                S_IDLE: begin
                    tx_out   <= 1'b1;
                    baud_cnt <= '0;
                    bit_idx  <= '0;

                    if (tx_valid) begin
                        data_reg <= tx_data;       // Latch the byte
                        state    <= S_START;
                    end
                end

                // --------------------------------------------------------
                // START: Drive TX LOW for one bit period.
                // --------------------------------------------------------
                S_START: begin
                    tx_out <= 1'b0;                // Start bit = LOW

                    if (baud_cnt == CLKS_PER_BIT[15:0] - 1) begin
                        baud_cnt <= '0;
                        state    <= S_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // --------------------------------------------------------
                // DATA: Shift out 8 data bits, LSB first.
                // --------------------------------------------------------
                S_DATA: begin
                    tx_out <= data_reg[bit_idx];   // Current data bit

                    if (baud_cnt == CLKS_PER_BIT[15:0] - 1) begin
                        baud_cnt <= '0;

                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;       // All 8 bits sent
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // --------------------------------------------------------
                // STOP: Drive TX HIGH for one bit period, then return to IDLE.
                // --------------------------------------------------------
                S_STOP: begin
                    tx_out <= 1'b1;                // Stop bit = HIGH

                    if (baud_cnt == CLKS_PER_BIT[15:0] - 1) begin
                        baud_cnt <= '0;
                        state    <= S_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
