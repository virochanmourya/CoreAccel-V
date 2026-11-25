// ============================================================================
// Module      : imem_wrap
// File        : imem_wrap.sv
// Description : Instruction memory wrapper. The core instantiates this, never
//               a memory directly, so the technology can change underneath.
//                 MEM_TECH = "FPGA": instruction_memory_pipe ($readmemh image):
//                                    LUT-ROM, or distributed RAM with an
//                                    asynchronous read when WRITABLE = 1.
//                 MEM_TECH = "ASIC": slot for an SRAM macro. Not built yet: a
//                                    macro has a synchronous read, which needs
//                                    the IF-stage rework (next-PC address).
//               WRITABLE = 1 adds the write port used by the boot loader
//               (IMEM window on the data bus); 0 leaves IMEM read-only.
// ============================================================================

module imem_wrap #(
    parameter string MEM_TECH  = "FPGA",
    parameter int    WORDS     = 2048,
    parameter        INIT_FILE = "imem.hex",
    parameter bit    WRITABLE  = 1'b0,
    localparam int   AW        = $clog2(WORDS)
)(
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [31:0]   wdata,
    input  logic [AW-1:0] word_addr,
    output logic [31:0]   instruction
);

    generate
        if (MEM_TECH == "FPGA") begin : g_fpga
            instruction_memory_pipe #(
                .DEPTH     (WORDS),
                .INIT_FILE (INIT_FILE),
                .WRITABLE  (WRITABLE)
            ) u_rom (
                .clk         (clk),
                .we          (we),
                .waddr       (waddr),
                .wdata       (wdata),
                .word_addr   (word_addr),
                .instruction (instruction)
            );
        end else begin : g_unsupported
            $error("imem_wrap: MEM_TECH '%s' has no memory implementation yet", MEM_TECH);
        end
    endgenerate

endmodule
