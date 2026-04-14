// ============================================================================
// Module: cpu_top (Top-Level CPU)
// File:   cpu_top.v
//
// PURPOSE:
//   Connects all sub-modules together to form the complete single-cycle
//   RV32I CPU. This is the "wiring diagram" — no logic here, just connections.
//
// INPUTS:
//   clk   - Clock signal
//   reset - Active-high synchronous reset
//
// The CPU has no external outputs in this simple version.
// In a real SoC, you would add I/O ports here.
// ============================================================================

module cpu_top (
    input wire clk,
    input wire reset
);

    // ========================================================================
    // Internal wires — these connect the modules together
    // ========================================================================

    // Program Counter
    wire [31:0] pc_current;

    // Instruction Memory
    wire [31:0] instruction;

    // Instruction fields (decoded from the instruction word)
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;

    // Control signals
    wire        reg_write;
    wire        alu_src;
    wire        mem_read;
    wire        mem_write;
    wire        mem_to_reg;
    wire [1:0]  alu_control;

    // Register file outputs
    wire [31:0] read_data1;  // rs1 value
    wire [31:0] read_data2;  // rs2 value

    // Immediate generator output
    wire [31:0] imm_value;

    // ALU
    wire [31:0] alu_input_b;  // Mux output: rs2 or immediate
    wire [31:0] alu_result;

    // Data memory
    wire [31:0] mem_read_data;

    // Write-back data (to register file)
    wire [31:0] write_back_data;

    // ========================================================================
    // Decode instruction fields
    // ========================================================================
    assign opcode = instruction[6:0];
    assign rd     = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1    = instruction[19:15];
    assign rs2    = instruction[24:20];
    assign funct7 = instruction[31:25];

    // ========================================================================
    // MUX: ALU input B selection
    //   alu_src = 0 → use rs2 (R-type: ADD, SUB)
    //   alu_src = 1 → use immediate (I-type: ADDI, LW; S-type: SW)
    // ========================================================================
    assign alu_input_b = (alu_src) ? imm_value : read_data2;

    // ========================================================================
    // MUX: Write-back data selection
    //   mem_to_reg = 0 → write ALU result to register (ADD, SUB, ADDI)
    //   mem_to_reg = 1 → write memory data to register (LW)
    // ========================================================================
    assign write_back_data = (mem_to_reg) ? mem_read_data : alu_result;

    // ========================================================================
    // Module Instantiations
    // ========================================================================

    // 1. Program Counter
    pc u_pc (
        .clk    (clk),
        .reset  (reset),
        .pc_out (pc_current)
    );

    // 2. Instruction Memory
    instruction_memory u_imem (
        .addr        (pc_current),
        .instruction (instruction)
    );

    // 3. Control Unit
    control_unit u_control (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7      (funct7),
        .reg_write   (reg_write),
        .alu_src     (alu_src),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .mem_to_reg  (mem_to_reg),
        .alu_control (alu_control)
    );

    // 4. Immediate Generator
    imm_gen u_imm_gen (
        .instruction (instruction),
        .imm_out     (imm_value)
    );

    // 5. Register File
    register_file u_regfile (
        .clk        (clk),
        .reg_write  (reg_write),
        .rs1        (rs1),
        .rs2        (rs2),
        .rd         (rd),
        .write_data (write_back_data),
        .read_data1 (read_data1),
        .read_data2 (read_data2)
    );

    // 6. ALU
    alu u_alu (
        .alu_in1     (read_data1),
        .alu_in2     (alu_input_b),
        .alu_control (alu_control),
        .alu_result  (alu_result)
    );

    // 7. Data Memory
    data_memory u_dmem (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .addr       (alu_result),
        .write_data (read_data2),
        .read_data  (mem_read_data)
    );

endmodule
