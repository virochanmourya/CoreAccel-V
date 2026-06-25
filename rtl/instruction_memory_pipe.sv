// ============================================================================
// Module      : instruction_memory_pipe
// File        : instruction_memory_pipe.sv
// Description : Combinational instruction memory.
//               CRITICAL DESIGN DECISION:
//               Combinational (async) fetch is required to present the instruction and PC
//               to the IF/ID register in the same cycle. A synchronous BRAM read would
//               introduce a 1-cycle mismatch, breaking branch/jump target calculations.
//               Distributed RAM (LUTRAM) is used to satisfy this combinational read requirement.
// ============================================================================

module instruction_memory_pipe (
    input  logic        clk,           // Used only for write port (synthesis)
    input  logic [31:0] addr,
    output logic [31:0] instruction
);
    (* ram_style = "distributed" *) logic [31:0] mem [0:2047];

    initial begin
        for (int i = 0; i < 2048; i++) mem[i] = 32'h00000013; // NOP
        $readmemh("firmware.hex", mem);
    end

    assign instruction = mem[addr[12:2]];

endmodule