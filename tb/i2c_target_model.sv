// ============================================================================
// i2c_target_model — minimal I2C target for the testbench (address phase only).
// Detects START/STOP, shifts in the address byte on SCL rising edges, and
// drives ACK (SDA low) during the 9th clock when the 7-bit address matches.
// It drives SDA open-drain, like a real device, so it exercises the DUT's pad
// input path and synchroniser. Prints one line per address phase.
// ============================================================================
`timescale 1ns/1ps
module i2c_target_model #(
    parameter logic [6:0] ADDR = 7'h48      // ADS1115 default address
)(
    inout wire scl,
    inout wire sda
);
    logic       sda_low = 1'b0;
    logic       active  = 1'b0;
    int         bitcnt  = 0;
    logic [7:0] shreg   = '0;

    assign sda = sda_low ? 1'b0 : 1'bz;

    // START: SDA falls while SCL is high
    always @(negedge sda) if (scl === 1'b1) begin
        active = 1'b1;
        bitcnt = 0;
    end

    // STOP: SDA rises while SCL is high
    always @(posedge sda) if (scl === 1'b1) begin
        active  = 1'b0;
        sda_low = 1'b0;
    end

    always @(posedge scl) if (active && bitcnt < 8) begin
        shreg  = {shreg[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
        bitcnt = bitcnt + 1;
    end

    always @(negedge scl) if (active) begin
        if (bitcnt == 8) begin                    // end of address byte
            if (shreg[7:1] == ADDR) sda_low = 1'b1;
            $display("I2C target: addr=0x%02h %s -> %s", shreg[7:1],
                     shreg[0] ? "R" : "W", (shreg[7:1] == ADDR) ? "ACK" : "NACK");
            bitcnt = 9;
        end else if (bitcnt == 9) begin           // end of ACK clock
            sda_low = 1'b0;
            active  = 1'b0;                       // address phase only
        end
    end
endmodule
