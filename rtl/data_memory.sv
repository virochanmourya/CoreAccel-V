// ============================================================================
// Module      : data_memory
// File        : data_memory.sv
// Description : Data RAM (64 words / 256 bytes).
//               Synchronous write, 0-cycle combinational read.
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

    // Simulation initialization
    initial begin
        integer i;
        for (i = 0; i < 64; i = i + 1) begin
            mem[i] = 32'd0;
        end
    end

    // 64-word address space mapping
    wire [5:0] word_addr = addr[7:2];

    always @(posedge clk) begin
        if (mem_write) begin
            mem[word_addr] <= write_data;
        end
    end

    // 0-cycle latency required by MEM stage
    assign read_data = (mem_read) ? mem[word_addr] : 32'd0;

endmodule
