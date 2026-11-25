// ============================================================================
// Module      : instruction_memory_pipe
// File        : instruction_memory_pipe.sv
// Description : Combinational instruction memory.
//               CRITICAL DESIGN DECISION:
//               Combinational (async) fetch is required to present the instruction and PC
//               to the IF/ID register in the same cycle. A synchronous BRAM read would
//               introduce a 1-cycle mismatch, breaking branch/jump target calculations.
//               WRITABLE = 0: read-only, synthesises to LUT-ROM on Artix-7.
//               WRITABLE = 1: adds a synchronous word write port (the boot
//               loader's IMEM window); synthesises to distributed RAM, whose
//               read stays asynchronous, so the fetch path does not change.
//               (An ASIC flow needs a sync-read macro and an IF-stage rework.)
// ============================================================================

module instruction_memory_pipe #(
    parameter int DEPTH     = 2048,          // 32-bit words (8 KB)
    parameter     INIT_FILE = "imem.hex",    // .text image from `make fw`
    parameter bit WRITABLE  = 1'b0,          // 1: synchronous write port
    localparam int AW       = $clog2(DEPTH)
)(
    input  logic          clk,           // write port only
    input  logic          we,            // write one word (ignored if !WRITABLE)
    input  logic [AW-1:0] waddr,
    input  logic [31:0]   wdata,
    input  logic [AW-1:0] word_addr,     // PC[AW+1:2]
    output logic [31:0]   instruction
);
    (* ram_style = "distributed", rom_style = "distributed" *) logic [31:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) mem[i] = 32'h00000013; // NOP
        $readmemh(INIT_FILE, mem);
    end

    generate
        if (WRITABLE) begin : g_wr
            always_ff @(posedge clk)
                if (we) mem[waddr] <= wdata;
        end else begin : g_ro
            logic unused;
            assign unused = &{1'b0, clk, we, waddr, wdata};
        end
    endgenerate

    assign instruction = mem[word_addr];

endmodule
