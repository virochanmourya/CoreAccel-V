// ============================================================================
// Module      : instruction_memory_pipe
// File        : instruction_memory_pipe.sv
// Description : Combinational instruction memory.
//               CRITICAL DESIGN DECISION:
//               Combinational (async) fetch is required to present the instruction and PC
//               to the IF/ID register in the same cycle. A synchronous BRAM read would
//               introduce a 1-cycle mismatch, breaking branch/jump target calculations.
//               It is read-only (no write port) and synthesises to LUT-ROM on
//               Artix-7, which satisfies the combinational read requirement.
//               (An ASIC flow needs a sync-read macro and an IF-stage rework.)
// ============================================================================

module instruction_memory_pipe #(
    parameter INIT_FILE = "imem.hex"     // .text image from `make fw`
)(
    input  logic [10:0] word_addr,     // PC[12:2]: 2048 x 32-bit words (8 KB)
    output logic [31:0] instruction
);
    (* ram_style = "distributed" *) logic [31:0] mem [0:2047];

    initial begin
        for (int i = 0; i < 2048; i++) mem[i] = 32'h00000013; // NOP
        $readmemh(INIT_FILE, mem);
    end

    assign instruction = mem[word_addr];

endmodule
