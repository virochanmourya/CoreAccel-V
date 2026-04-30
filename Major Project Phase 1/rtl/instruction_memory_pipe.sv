// ============================================================================
// Module: instruction_memory_pipe (32-Bit DSP MAC Test Program)
// File:   instruction_memory_pipe.sv
// ============================================================================

module instruction_memory_pipe (
    input  logic [31:0] addr,
    output logic [31:0] instruction
);
    // Memory array: 64 words of 32 bits each (256 bytes)
    logic [31:0] mem [0:63];

    initial begin
        // Initialize everything to NOPs
        for (int i=0; i<64; i++) mem[i] = 32'h00000013; 

        // --- CoreAccel-V DSP Integration Test ---
        mem[0]  = 32'h00500093; // ADDI x1, x0, 5      | x1 = 5
        mem[1]  = 32'h00A00113; // ADDI x2, x0, 10     | x2 = 10
        
        mem[2]  = 32'h0000100B; // MAC_CLEAR           | Accumulator = 0
        
        // TEST 1: First MAC operation (Stall expected here!)
        mem[3]  = 32'h0020800B; // MAC x1, x2          | Accumulator += (5 * 10) -> 50
        mem[4]  = 32'h0000218B; // MAC_READ x3         | x3 = 50
        
        // TEST 2: Accumulation & Forwarding
        mem[5]  = 32'h0010800B; // MAC x1, x1          | Accumulator += (5 * 5) -> 75
        mem[6]  = 32'h0000220B; // MAC_READ x4         | x4 = 75
        
        // TEST 3: Clear Verification
        mem[7]  = 32'h0000100B; // MAC_CLEAR           | Accumulator = 0
        mem[8]  = 32'h0000228B; // MAC_READ x5         | x5 = 0
    end

    // Read: combinational (no clock needed)
    assign instruction = mem[addr[31:2]];

endmodule