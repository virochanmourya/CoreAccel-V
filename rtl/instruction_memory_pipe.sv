// ============================================================================
// Module: instruction_memory_pipe
// File:   instruction_memory_pipe.sv
//
// Instruction memory for CoreAccel-V. Loaded at synthesis via $readmemh.
//
// CRITICAL DESIGN DECISION:
//   This pipeline was designed for COMBINATIONAL (async) instruction fetch.
//   The PC and instruction must be available in the SAME cycle for the
//   IF/ID register to capture a consistent {PC, instruction} pair.
//
//   Using synchronous BRAM would introduce a 1-cycle latency mismatch:
//   the IF/ID register would see the CURRENT PC but the PREVIOUS cycle's
//   instruction. This breaks all branch/jump target calculations.
//
//   Therefore, we use DISTRIBUTED RAM (LUTRAM) which supports async reads.
//   For 2048×32 = 8KB, this uses ~2048 LUTs (the xc7a35t has 20,800).
//   This is acceptable for this design.
//
// Memory: 8KB = 2048 × 32-bit words
// ============================================================================

module instruction_memory_pipe (
    input  logic        clk,           // Used only for write port (synthesis)
    input  logic [31:0] addr,
    output logic [31:0] instruction
);
    // Force DISTRIBUTED RAM for combinational (async) read
    // This is mandatory — the pipeline expects instruction to be available
    // in the SAME cycle that the PC is presented.
    (* ram_style = "distributed" *) logic [31:0] mem [0:2047];

    initial begin
        for (int i = 0; i < 2048; i++) mem[i] = 32'h00000013; // NOP
        $readmemh("firmware.hex", mem);
    end

    // COMBINATIONAL read — NO clock, NO register
    // The instruction is available in the same cycle as the address.
    assign instruction = mem[addr[12:2]];

endmodule