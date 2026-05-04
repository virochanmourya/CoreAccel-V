// ============================================================================
// Module: tcm_ram (4KB True Dual-Port Tightly Coupled Memory)
// File:   tcm_ram.sv
//
// PURPOSE:
//   4KB (1024 x 32-bit) True Dual-Port RAM for DSP weight storage.
//   Infers Xilinx Block RAM (BRAM) via (* ram_style = "block" *).
//
//   Port A: Synchronous Read/Write — CPU bus (MEM stage).
//           Write-First mode: on simultaneous read+write to same address,
//           the NEW data is returned on douta (prevents RAW hazards).
//
//   Port B: Synchronous Read-Only — MAC unit (EX stage).
//           Streams weights directly to the multiplier.
//
//   Cross-port behavior: If Port A writes and Port B reads the SAME
//   address in the SAME cycle, Port B returns the OLD value (standard
//   Xilinx BRAM behavior). Software must insert a NOP/stall between
//   a TCM write and a MAC read to the same address.
//
// TARGET: Xilinx Artix-7 — maps to one BRAM36E1 (36Kb) tile
// ============================================================================

module tcm_ram #(
    parameter DEPTH  = 1024,
    parameter WIDTH  = 32,
    parameter ADDR_W = 10
)(
    // Port A: CPU Read/Write (MEM stage)
    input  logic              clka,
    input  logic              wea,
    input  logic [ADDR_W-1:0] addra,
    input  logic [WIDTH-1:0]  dina,
    output logic [WIDTH-1:0]  douta,

    // Port B: MAC Read-Only (EX stage)
    input  logic              clkb,
    input  logic [ADDR_W-1:0] addrb,
    output logic [WIDTH-1:0]  doutb
);

    // Force BRAM inference — do NOT use distributed LUTRAM
    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Initialize to zero for simulation
    initial begin
        for (int i = 0; i < DEPTH; i++) mem[i] = '0;
    end

    // Port A: Write-First mode
    // On write: store data AND return the new value on douta.
    // On read-only: return the stored value.
    always_ff @(posedge clka) begin
        if (wea) begin
            mem[addra] <= dina;
            douta      <= dina;       // Write-First: read returns new data
        end else begin
            douta      <= mem[addra]; // Normal read
        end
    end

    // Port B: Read-Only (1-cycle latency)
    always_ff @(posedge clkb) begin
        doutb <= mem[addrb];
    end

endmodule
