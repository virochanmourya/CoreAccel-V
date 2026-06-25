// ============================================================================
// Module      : register_file
// File        : register_file.sv
// Description : 32x32-bit general-purpose register file.
//               Features two combinational read ports and one synchronous write
//               port. Register x0 is hardwired to zero.
// ============================================================================

module register_file (
    input  logic clk,
    input  logic reset,
    input  logic we,
    input  logic [4:0] rs1, rs2, rd,
    input  logic [31:0] write_data,
    output logic [31:0] read_data1, read_data2
);
    logic [31:0] registers [0:31];

    // Combinational reads
    assign read_data1 = (rs1 == 5'b0) ? 32'b0 : registers[rs1];
    assign read_data2 = (rs2 == 5'b0) ? 32'b0 : registers[rs2];

    always_ff @(posedge clk) begin
        if (reset) begin
            integer i;
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'b0;
        end else if (we && rd != 5'b0) begin
            registers[rd] <= write_data;
        end
    end
endmodule
