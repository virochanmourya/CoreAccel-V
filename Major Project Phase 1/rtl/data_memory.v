// ============================================================================
// Module: data_memory (Data RAM)
// File:   data_memory.v
//
// PURPOSE:
//   Read/write memory for LW and SW instructions.
//   - WRITE is synchronous (happens on clock edge when mem_write = 1)
//   - READ is combinational (instant output when mem_read = 1)
//   - 64 words = 256 bytes of data memory
//
// INPUTS:
//   clk        - Clock signal
//   mem_read   - 1 = output the data at the given address
//   mem_write  - 1 = write data to the given address
//   addr [31:0]     - Byte address (will be word-aligned: addr[31:2])
//   write_data [31:0] - Data to store (for SW)
//
// OUTPUTS:
//   read_data [31:0] - Data loaded from memory (for LW)
// ============================================================================

module data_memory (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output wire [31:0] read_data
);

    // 64 words of 32-bit memory
    reg [31:0] mem [0:63];

    // Initialize to 0 for simulation clarity
    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1)
            mem[i] = 32'd0;
    end

    // WRITE: synchronous — store on clock edge
    always @(posedge clk) begin
        if (mem_write) begin
            mem[addr[31:2]] <= write_data;
        end
    end

    // READ: combinational — output data immediately
    assign read_data = (mem_read) ? mem[addr[31:2]] : 32'd0;

endmodule
