// ============================================================================
// Module      : mtimer
// File        : mtimer.sv
// Description : Machine timer (RISC-V mtime / mtimecmp), memory-mapped in the
//               peripheral region:
//                 0xC000_0100  mtime[31:0]      0xC000_0104  mtime[63:32]
//                 0xC000_0108  mtimecmp[31:0]   0xC000_010C  mtimecmp[63:32]
//               mtime counts every clock cycle. A write to one half replaces
//               that half (no increment on that cycle). mtimecmp resets to all
//               ones, so no timer interrupt is pending after reset.
//               mtip = (mtime >= mtimecmp), 64-bit unsigned, registered: it
//               follows a write to either register two cycles later.
//               Word registers: a SB/SH store writes the whole word with the
//               lane-replicated data, like the other peripherals.
// ============================================================================

module mtimer (
    input  logic        clk,
    input  logic        reset,
    input  logic        we,          // store to a timer register (MEM)
    input  logic [1:0]  sel,         // address[3:2]: mtime lo/hi, mtimecmp lo/hi
    input  logic [31:0] wdata,
    output logic [31:0] rdata,       // read of the register selected by sel
    output logic [63:0] mtime,
    output logic        mtip
);

    logic [63:0] mtimecmp;
    logic [63:0] mtime_inc;

    assign mtime_inc = mtime + 64'd1;

    always_comb begin
        case (sel)
            2'b00:   rdata = mtime[31:0];
            2'b01:   rdata = mtime[63:32];
            2'b10:   rdata = mtimecmp[31:0];
            default: rdata = mtimecmp[63:32];
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            mtime    <= '0;
            mtimecmp <= '1;
            mtip     <= 1'b0;
        end else begin
            if (we && sel == 2'b00)      mtime <= {mtime[63:32], wdata};
            else if (we && sel == 2'b01) mtime <= {wdata, mtime[31:0]};
            else                         mtime <= mtime_inc;

            if (we && sel == 2'b10)      mtimecmp[31:0]  <= wdata;
            if (we && sel == 2'b11)      mtimecmp[63:32] <= wdata;

            mtip <= (mtime >= mtimecmp);
        end
    end

endmodule
