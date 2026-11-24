// ============================================================================
// spi_echo_model — SPI target for the testbench that works in any mode.
// The mode (CPOL, CPHA) is set by the harness (`mode`, from a simulation
// control word) and checked: SCK must idle at CPOL when CS falls.
// It replies to byte n with ~(byte n-1); the first reply after CS falls is
// FIRST_REPLY. MSB first. It samples MOSI on its sampling edge and changes
// MISO on the other edge (CPHA 0: first bit as soon as CS falls).
// Received bytes go to rx_log[] (rx_count of them) for the harness.
// Strict timing (clk period CLK_NS, DUT divider `div`): every SCK half
// period is exactly (div + 1) clocks, CS falls at least that long before
// the first edge and rises at least that long after the last one, and
// MISO is only valid at the sampling edge (X from HOLD_NS after it).
// Violations call tb_top.sva_fail().
// ============================================================================
`timescale 1ns/1ps
module spi_echo_model #(
    parameter logic [7:0] FIRST_REPLY = 8'h5A,
    parameter int         CLK_NS      = 10,
    parameter int         HOLD_NS     = 1
)(
    input  wire       cs_n,
    input  wire       sck,
    input  wire       mosi,
    output wire       miso,
    input  logic [1:0] mode,         // {CPOL, CPHA}
    input  logic [15:0] div          // DUT SCK divider (half period = div + 1 clocks)
);
    realtime t_cs = 0, t_edge = 0;
    bit      seen_edge = 1'b0;
    function automatic void timing_fail(string what);
        $display("SPI echo: %s t=%0t (div=%0d)", what, $time, div);
        tb_top.sva_fail();
    endfunction
    always @(sck) if (cs_n === 1'b0) begin
        if (!seen_edge) begin
            if ($realtime - t_cs < (div + 1) * CLK_NS) timing_fail("CS setup too short");
        end else if ($realtime - t_edge != (div + 1) * CLK_NS) begin
            timing_fail("SCK half period wrong");
        end
        seen_edge = 1'b1;
        t_edge    = $realtime;
    end
    logic       drive = 1'b0, miso_q = 1'b1;
    logic [7:0] in_sh = '0, out_sh = '0;
    int         nbits = 0;
    logic [7:0] rx_log [0:63];
    int         rx_count = 0;

    wire cpol = mode[1];
    wire cpha = mode[0];
    assign miso = drive ? miso_q : 1'bz;

    always @(negedge cs_n) begin
        if (sck !== cpol) begin
            $display("SPI echo: SCK=%b at CS fall, CPOL=%b t=%0t", sck, cpol, $time);
            tb_top.sva_fail();
        end
        nbits  = 0;
        t_cs   = $realtime;
        seen_edge = 1'b0;
        drive  = 1'b1;
        out_sh = FIRST_REPLY;
        miso_q = cpha ? 1'b1 : out_sh[7];
    end
    always @(posedge cs_n) if (!$isunknown(cs_n)) begin
        drive = 1'b0;
        if (seen_edge && $realtime - t_edge < (div + 1) * CLK_NS) timing_fail("CS hold too short");
        if (nbits % 8 != 0) begin
            $display("SPI echo: CS rose after %0d bits t=%0t", nbits, $time);
            tb_top.sva_fail();
        end
    end

    // sampling edge: rising when CPOL == CPHA
    task automatic sample_edge();
        in_sh = {in_sh[6:0], (mosi === 1'b1)};
        nbits++;
        if (nbits % 8 == 0) begin
            if (rx_count < 64) rx_log[rx_count] = in_sh;
            rx_count++;
            out_sh = ~in_sh;                    // next reply
        end
        // MISO is only guaranteed at the sampling edge.
        fork begin #(HOLD_NS); if (cs_n === 1'b0) miso_q = 1'bx; end join_none
    endtask
    task automatic shift_edge();
        if (cpha) begin
            // CPHA 1: this edge starts a bit
            miso_q = out_sh[7 - (nbits % 8)];
        end else if (nbits % 8 != 0) begin
            miso_q = out_sh[7 - (nbits % 8)];
        end else begin
            miso_q = out_sh[7];                 // first bit of the next byte
        end
    endtask

    always @(posedge sck) if (cs_n === 1'b0) begin
        if (cpol == cpha) sample_edge(); else shift_edge();
    end
    always @(negedge sck) if (cs_n === 1'b0) begin
        if (cpol == cpha) shift_edge(); else sample_edge();
    end
endmodule
