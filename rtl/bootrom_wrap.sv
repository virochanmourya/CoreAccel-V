// ============================================================================
// Module      : bootrom_wrap
// File        : bootrom_wrap.sv
// Description : Boot ROM wrapper (instruction side only, 0x0001_0000).
//                 MEM_TECH = "FPGA": combinational LUT-ROM
//                                    (instruction_memory_pipe, read-only,
//                                    $readmemh image built by `make bootrom`).
//                 MEM_TECH = "ASIC": slot for a ROM macro or a synthesised
//                                    ROM. Not built yet.
//               The data bus cannot read it (DECERR): the loader has no
//               .rodata and no tables.
// ============================================================================

module bootrom_wrap #(
    parameter string MEM_TECH  = "FPGA",
    parameter int    WORDS     = 1024,
    parameter        INIT_FILE = "bootrom.hex",
    localparam int   AW        = $clog2(WORDS)
)(
    input  logic [AW-1:0] word_addr,
    output logic [31:0]   instruction
);

    generate
        if (MEM_TECH == "FPGA") begin : g_fpga
            instruction_memory_pipe #(
                .DEPTH     (WORDS),
                .INIT_FILE (INIT_FILE),
                .WRITABLE  (1'b0)
            ) u_rom (
                .clk         (1'b0),
                .we          (1'b0),
                .waddr       ('0),
                .wdata       ('0),
                .word_addr   (word_addr),
                .instruction (instruction)
            );
        end else begin : g_unsupported
            $error("bootrom_wrap: MEM_TECH '%s' has no ROM implementation yet", MEM_TECH);
        end
    endgenerate

endmodule
