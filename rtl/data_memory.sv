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
    input  logic        clk,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

    // Explicitly demand LUTRAM synthesis for a 0-cycle asynchronous read
    (* ram_style = "distributed" *) logic [31:0] mem [0:63];

    // Initialize to 0 for simulation clarity
    initial begin
        integer i;
        for (i = 0; i < 64; i = i + 1) begin
            mem[i] = 32'd0;
        end
    end

    // WRITE: synchronous — store on clock edge
    // 64-word address space: only 6 address bits are meaningful
    wire [5:0] word_addr = addr[7:2];

    always @(posedge clk) begin
        if (mem_write) begin
            mem[word_addr] <= write_data;
        end
    end

    // READ: combinational — output data immediately
    // Keeps the 0-cycle latency required by the standard MEM stage
    assign read_data = (mem_read) ? mem[word_addr] : 32'd0;

endmodule
