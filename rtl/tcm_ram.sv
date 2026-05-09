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
//           the NEW data is returned on douta (standard BRAM WRITE_FIRST).
//
//   Port B: Synchronous Read-Only — MAC unit (EX stage).
//           Streams weights directly to the multiplier.
//           1-cycle read latency (registered output, standard BRAM).
//
//   Cross-port behavior: If Port A writes and Port B reads the SAME
//   address in the SAME cycle, Xilinx 7-series TDP BRAM returns the
//   OLD value on Port B (NO_CHANGE / READ_FIRST mode). No metastability,
//   no data corruption in the array. This is a software data race —
//   the programmer must insert a NOP/fence between a TCM store and a
//   MAC read to the same address. No hardware interlock is needed.
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

    // Port A: Write-First mode (Xilinx BRAM WRITE_FIRST template)
    // On write: store data AND return the new value on douta.
    // On read-only: return the stored value.
    always_ff @(posedge clka) begin
        if (wea) begin
            mem[addra] <= dina;
            douta      <= dina;       // Write-First: read returns new data
        end else begin
            douta      <= mem[addra]; // Normal synchronous read
        end
    end

    // Port B: Read-Only (clean BRAM-compatible template)
    // Cross-port collision returns old data — software responsibility.
    always_ff @(posedge clkb) begin
        doutb <= mem[addrb];
    end

endmodule
