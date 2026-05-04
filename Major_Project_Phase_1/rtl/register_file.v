// ============================================================================
// Module: register_file
// File:   register_file.v
//
// PURPOSE:
//   The register file holds 32 general-purpose registers, each 32 bits wide.
//   - Two registers can be READ at the same time (combinational, no clock)
//   - One register can be WRITTEN on the rising clock edge
//   - Register x0 is ALWAYS zero (hardwired by RISC-V spec)
//
// INPUTS:
//   clk       - Clock signal
//   reg_write - Write enable (1 = write to rd)
//   rs1       [4:0]  - Address of first source register
//   rs2       [4:0]  - Address of second source register
//   rd        [4:0]  - Address of destination register
//   write_data[31:0] - Data to write into rd
//
// OUTPUTS:
//   read_data1 [31:0] - Value of register rs1
//   read_data2 [31:0] - Value of register rs2
// ============================================================================

module register_file (
    input  wire        clk,
    input  wire        reg_write,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] write_data,
    output wire [31:0] read_data1,
    output wire [31:0] read_data2
);

    // 32 registers, each 32 bits
    reg [31:0] registers [0:31];

    // Initialize all registers to 0 (for simulation clarity)
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            registers[i] = 32'd0;
    end

    // READ: combinational (instant, no clock)
    // x0 always reads as 0
    assign read_data1 = (rs1 == 5'd0) ? 32'd0 : registers[rs1];
    assign read_data2 = (rs2 == 5'd0) ? 32'd0 : registers[rs2];

    // WRITE: on rising clock edge, only if reg_write is enabled AND rd != x0
    always @(posedge clk) begin
        if (reg_write && rd != 5'd0) begin
            registers[rd] <= write_data;
        end
    end

endmodule
