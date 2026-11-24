// ============================================================================
// Module      : tcm_wrap
// File        : tcm_wrap.sv
// Description : TCM wrapper (data memory + MAC weights). The core
//               instantiates this, never a memory directly.
//                 MEM_TECH = "FPGA": true dual-port BRAM (tcm_ram): port A
//                                    read/write with byte enables, port B read.
//                 MEM_TECH = "ASIC": slot for SRAM macro(s) with the same
//                                    synchronous ports (two single-port macros
//                                    or a dual-port macro). Not built yet.
// ============================================================================

module tcm_wrap #(
    parameter string MEM_TECH  = "FPGA",
    parameter int    WORDS     = 1024,
    parameter        INIT_FILE = "tcm.hex",
    localparam int   AW        = $clog2(WORDS)
)(
    input  logic          clk,
    // Port A: CPU (address from EX), byte write enables
    input  logic [3:0]    wea,
    input  logic [AW-1:0] addra,
    input  logic [31:0]   dina,
    output logic [31:0]   douta,
    // Port B: MAC weights, read only
    input  logic [AW-1:0] addrb,
    output logic [31:0]   doutb
);

    generate
        if (MEM_TECH == "FPGA") begin : g_fpga
            tcm_ram #(
                .DEPTH     (WORDS),
                .WIDTH     (32),
                .ADDR_W    (AW),
                .INIT_FILE (INIT_FILE)
            ) u_ram (
                .clka  (clk),
                .wea   (wea),
                .addra (addra),
                .dina  (dina),
                .douta (douta),
                .clkb  (clk),
                .addrb (addrb),
                .doutb (doutb)
            );
        end else begin : g_unsupported
            $error("tcm_wrap: MEM_TECH '%s' has no memory implementation yet", MEM_TECH);
        end
    endgenerate

endmodule
