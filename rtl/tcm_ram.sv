// ============================================================================
// Module      : tcm_ram
// File        : tcm_ram.sv
// Description : 4KB True Dual-Port Tightly Coupled Memory (all data + DSP weights).
//               Infers Xilinx Block RAM (BRAM).
//               - Port A: Sync Read/Write (CPU, address from EX), Write-First mode.
//               - Port B: Sync Read-Only (MAC EX stage), 1-cycle latency.
//               Xilinx Artix-7 (1x BRAM36E1)
// ============================================================================

module tcm_ram #(
    parameter DEPTH  = 1024,
    parameter WIDTH  = 32,
    parameter ADDR_W = 10,
    parameter INIT_FILE = "tcm.hex"   // .rodata/.data image from `make fw`
)(
    // Port A: CPU Read/Write (address from EX stage)
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

    // Initialise with the firmware data image (.rodata/.data, VMA = LMA)
    initial begin
        for (int i = 0; i < DEPTH; i++) mem[i] = '0;
        $readmemh(INIT_FILE, mem);
    end

    // Port A: Write-First mode (Xilinx BRAM WRITE_FIRST template)
    always @(posedge clka) begin
        if (wea) begin
            mem[addra] <= dina;
            douta      <= dina;
        end else begin
            douta      <= mem[addra];
        end
    end

    // Port B: Read-Only (clean BRAM-compatible template)
    // Cross-port collision returns old data — software responsibility.
    always_ff @(posedge clkb) begin
        doutb <= mem[addrb];
    end

endmodule
