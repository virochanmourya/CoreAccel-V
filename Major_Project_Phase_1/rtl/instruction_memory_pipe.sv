// ============================================================================
// Module: instruction_memory_pipe
// File:   instruction_memory_pipe.sv
// ============================================================================

module instruction_memory_pipe (
    input  logic [31:0] addr,
    output logic [31:0] instruction
);
    // Memory array: 64 words of 32 bits each (256 bytes)
    logic [31:0] mem [0:63];

    initial begin
        // Initialize memory with NOPs (ADDI x0, x0, 0) just to be safe
        for (int i=0; i<64; i++) mem[i] = 32'h00000013; 
        
        // Dynamically load the external software file at simulation start
        $readmemh("tcm_test.mem", mem);
    end

    // Read: combinational (no clock needed)
    assign instruction = mem[addr[31:2]];

endmodule