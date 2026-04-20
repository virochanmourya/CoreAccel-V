// ============================================================================
// Module: cpu_pipeline_top (5-Stage Pipelined RV32I CPU — Top Level)
// File:   cpu_pipeline_top.sv
//
// PURPOSE:
//   Wires together all sub-modules to form a complete 5-stage in-order
//   pipelined RV32I CPU with:
//     - Data forwarding (EX/MEM → EX, MEM/WB → EX)
//     - Load-use hazard stalling (1-cycle bubble)
//     - Branch resolution in EX stage (BEQ/BNE with 2-cycle flush penalty)
//     - WB-to-ID register bypass for same-cycle write/read correctness
//
//   Pipeline stages: IF → ID → EX → MEM → WB
//
//   Reuses original modules (unchanged .v files):
//     register_file, alu, data_memory
//
//   Uses new SystemVerilog modules:
//     pc_pipe, instruction_memory_pipe, control_unit_pipe, imm_gen_pipe,
//     if_id_reg, id_ex_reg, ex_mem_reg, mem_wb_reg,
//     forwarding_unit, hazard_detection_unit
//
// INPUTS:
//   clk   - Clock signal
//   reset - Active-high synchronous reset
// ============================================================================

module cpu_pipeline_top (
    input logic clk,
    input logic reset
);

    // ========================================================================
    // Signal Declarations
    // ========================================================================

    // ---- IF Stage ----
    logic [31:0] pc_current;
    logic [31:0] pc_plus4;
    logic [31:0] if_instruction;

    // ---- IF/ID Register Outputs ----
    logic [31:0] if_id_pc;
    logic [31:0] if_id_instruction;

    // ---- ID Stage: Instruction Field Decode ----
    logic [6:0]  id_opcode;
    logic [4:0]  id_rd;
    logic [2:0]  id_funct3;
    logic [4:0]  id_rs1;
    logic [4:0]  id_rs2;
    logic [6:0]  id_funct7;

    // ---- ID Stage: Control Signals (from control_unit_pipe) ----
    logic        id_reg_write;
    logic        id_alu_src;
    logic        id_mem_read;
    logic        id_mem_write;
    logic        id_mem_to_reg;
    logic [1:0]  id_alu_control;
    logic        id_branch;

    // ---- ID Stage: Data ----
    logic [31:0] id_imm;
    logic [31:0] rf_read_data1;     // Raw register file output
    logic [31:0] rf_read_data2;     // Raw register file output
    logic [31:0] id_rs1_data;       // After WB-to-ID bypass
    logic [31:0] id_rs2_data;       // After WB-to-ID bypass

    // ---- ID/EX Register Outputs ----
    logic        id_ex_reg_write;
    logic        id_ex_mem_to_reg;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic        id_ex_alu_src;
    logic [1:0]  id_ex_alu_control;
    logic        id_ex_branch;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_rs1_data;
    logic [31:0] id_ex_rs2_data;
    logic [31:0] id_ex_imm;
    logic [4:0]  id_ex_rs1_addr;
    logic [4:0]  id_ex_rs2_addr;
    logic [4:0]  id_ex_rd_addr;
    logic [2:0]  id_ex_funct3;

    // ---- EX Stage: Forwarding Mux Outputs ----
    logic [31:0] forwarded_a;
    logic [31:0] forwarded_b;
    logic [1:0]  forward_a_sel;
    logic [1:0]  forward_b_sel;

    // ---- EX Stage: ALU ----
    logic [31:0] alu_input_b;
    logic [31:0] alu_result;

    // ---- EX Stage: Branch ----
    logic        branch_taken;
    logic [31:0] pc_branch;

    // ---- EX/MEM Register Outputs ----
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_to_reg;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd_addr;

    // ---- MEM Stage ----
    logic [31:0] mem_read_data;

    // ---- MEM/WB Register Outputs ----
    logic        mem_wb_reg_write;
    logic        mem_wb_mem_to_reg;
    logic [31:0] mem_wb_mem_data;
    logic [31:0] mem_wb_alu_result;
    logic [4:0]  mem_wb_rd_addr;

    // ---- WB Stage ----
    logic [31:0] wb_data;

    // ---- Hazard / Control ----
    logic        stall;
    logic        pc_write;
    logic        if_id_stall;
    logic        if_id_flush;
    logic        id_ex_flush;

    // ========================================================================
    // Hazard & Branch Control Wiring
    // ========================================================================

    // PC stalls on load-use hazard, but branch overrides stall
    assign pc_write    = ~stall | branch_taken;

    // IF/ID: stall on load-use (but not if branch is flushing)
    assign if_id_stall = stall & ~branch_taken;

    // IF/ID: flush on branch taken
    assign if_id_flush = branch_taken;

    // ID/EX: flush on load-use stall (insert NOP bubble) OR branch taken
    assign id_ex_flush = stall | branch_taken;

    // ========================================================================
    //  IF STAGE — Instruction Fetch
    // ========================================================================

    assign pc_plus4 = pc_current + 32'd4;

    pc_pipe u_pc (
        .clk       (clk),
        .reset     (reset),
        .pc_write  (pc_write),
        .pc_src    (branch_taken),
        .pc_branch (pc_branch),
        .pc_out    (pc_current)
    );

    instruction_memory_pipe u_imem (
        .addr        (pc_current),
        .instruction (if_instruction)
    );

    // ========================================================================
    //  IF/ID Pipeline Register
    // ========================================================================

    if_id_reg u_if_id (
        .clk             (clk),
        .reset           (reset),
        .flush           (if_id_flush),
        .stall           (if_id_stall),
        .pc_in           (pc_current),
        .instruction_in  (if_instruction),
        .pc_out          (if_id_pc),
        .instruction_out (if_id_instruction)
    );

    // ========================================================================
    //  ID STAGE — Instruction Decode
    // ========================================================================

    // Decode instruction fields
    assign id_opcode = if_id_instruction[6:0];
    assign id_rd     = if_id_instruction[11:7];
    assign id_funct3 = if_id_instruction[14:12];
    assign id_rs1    = if_id_instruction[19:15];
    assign id_rs2    = if_id_instruction[24:20];
    assign id_funct7 = if_id_instruction[31:25];

    // Control Unit (pipeline version with branch support)
    control_unit_pipe u_control (
        .opcode      (id_opcode),
        .funct3      (id_funct3),
        .funct7      (id_funct7),
        .reg_write   (id_reg_write),
        .alu_src     (id_alu_src),
        .mem_read    (id_mem_read),
        .mem_write   (id_mem_write),
        .mem_to_reg  (id_mem_to_reg),
        .alu_control (id_alu_control),
        .branch      (id_branch)
    );

    // Immediate Generator (pipeline version with B-type support)
    imm_gen_pipe u_imm_gen (
        .instruction (if_id_instruction),
        .imm_out     (id_imm)
    );

    // Register File (original .v module — unchanged)
    // Write port driven by WB stage; read ports used by ID stage
    register_file u_regfile (
        .clk        (clk),
        .reg_write  (mem_wb_reg_write),
        .rs1        (id_rs1),
        .rs2        (id_rs2),
        .rd         (mem_wb_rd_addr),
        .write_data (wb_data),
        .read_data1 (rf_read_data1),
        .read_data2 (rf_read_data2)
    );

    // WB-to-ID Bypass: if WB writes a register that ID is reading in the
    // same cycle, use the WB write data instead of the stale register file
    // output. This handles the 3-instruction separation case where the
    // producer has just exited WB and the forwarding unit can no longer
    // catch it (EX/MEM has a different instruction, MEM/WB has moved on).
    assign id_rs1_data = (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0)
                          && (mem_wb_rd_addr == id_rs1))
                         ? wb_data : rf_read_data1;

    assign id_rs2_data = (mem_wb_reg_write && (mem_wb_rd_addr != 5'd0)
                          && (mem_wb_rd_addr == id_rs2))
                         ? wb_data : rf_read_data2;

    // ========================================================================
    //  Hazard Detection Unit
    // ========================================================================

    hazard_detection_unit u_hazard (
        .id_ex_mem_read (id_ex_mem_read),
        .id_ex_rd       (id_ex_rd_addr),
        .if_id_rs1      (id_rs1),
        .if_id_rs2      (id_rs2),
        .stall          (stall)
    );

    // ========================================================================
    //  ID/EX Pipeline Register
    // ========================================================================

    id_ex_reg u_id_ex (
        .clk             (clk),
        .reset           (reset),
        .flush           (id_ex_flush),

        // WB control
        .reg_write_in    (id_reg_write),
        .mem_to_reg_in   (id_mem_to_reg),
        .reg_write_out   (id_ex_reg_write),
        .mem_to_reg_out  (id_ex_mem_to_reg),

        // MEM control
        .mem_read_in     (id_mem_read),
        .mem_write_in    (id_mem_write),
        .mem_read_out    (id_ex_mem_read),
        .mem_write_out   (id_ex_mem_write),

        // EX control
        .alu_src_in      (id_alu_src),
        .alu_control_in  (id_alu_control),
        .alu_src_out     (id_ex_alu_src),
        .alu_control_out (id_ex_alu_control),

        // Branch
        .branch_in       (id_branch),
        .branch_out      (id_ex_branch),

        // Data
        .pc_in           (if_id_pc),
        .rs1_data_in     (id_rs1_data),
        .rs2_data_in     (id_rs2_data),
        .imm_in          (id_imm),
        .pc_out          (id_ex_pc),
        .rs1_data_out    (id_ex_rs1_data),
        .rs2_data_out    (id_ex_rs2_data),
        .imm_out         (id_ex_imm),

        // Register addresses
        .rs1_addr_in     (id_rs1),
        .rs2_addr_in     (id_rs2),
        .rd_addr_in      (id_rd),
        .rs1_addr_out    (id_ex_rs1_addr),
        .rs2_addr_out    (id_ex_rs2_addr),
        .rd_addr_out     (id_ex_rd_addr),

        // Instruction fields
        .funct3_in       (id_funct3),
        .funct3_out      (id_ex_funct3)
    );

    // ========================================================================
    //  EX STAGE — Execute
    // ========================================================================

    // ---- Forwarding Unit ----
    forwarding_unit u_forward (
        .id_ex_rs1        (id_ex_rs1_addr),
        .id_ex_rs2        (id_ex_rs2_addr),
        .ex_mem_rd        (ex_mem_rd_addr),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_rd        (mem_wb_rd_addr),
        .mem_wb_reg_write (mem_wb_reg_write),
        .forward_a        (forward_a_sel),
        .forward_b        (forward_b_sel)
    );

    // ---- Forwarding Mux A (ALU input A / rs1) ----
    always_comb begin
        case (forward_a_sel)
            2'b00:   forwarded_a = id_ex_rs1_data;     // No forwarding
            2'b10:   forwarded_a = ex_mem_alu_result;   // Forward from EX/MEM
            2'b01:   forwarded_a = wb_data;             // Forward from MEM/WB
            default: forwarded_a = id_ex_rs1_data;      // Deterministic default
        endcase
    end

    // ---- Forwarding Mux B (ALU input B / rs2) ----
    always_comb begin
        case (forward_b_sel)
            2'b00:   forwarded_b = id_ex_rs2_data;     // No forwarding
            2'b10:   forwarded_b = ex_mem_alu_result;   // Forward from EX/MEM
            2'b01:   forwarded_b = wb_data;             // Forward from MEM/WB
            default: forwarded_b = id_ex_rs2_data;      // Deterministic default
        endcase
    end

    // ---- ALU Source Mux ----
    //   alu_src = 0 → use forwarded rs2 (R-type: ADD, SUB)
    //   alu_src = 1 → use immediate   (I-type: ADDI, LW; S-type: SW)
    assign alu_input_b = id_ex_alu_src ? id_ex_imm : forwarded_b;

    // ---- ALU (original .v module — unchanged) ----
    alu u_alu (
        .alu_in1     (forwarded_a),
        .alu_in2     (alu_input_b),
        .alu_control (id_ex_alu_control),
        .alu_result  (alu_result)
    );

    // ---- Branch Comparator (EX stage) ----
    // Uses forwarded operands for correct branch evaluation even when
    // source registers were produced by immediately preceding instructions.
    // Branch target = ID/EX.pc + ID/EX.imm (B-type offset)
    assign pc_branch = id_ex_pc + id_ex_imm;

    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_funct3)
                3'b000:  branch_taken = (forwarded_a == forwarded_b);  // BEQ
                3'b001:  branch_taken = (forwarded_a != forwarded_b);  // BNE
                default: branch_taken = 1'b0;  // Deterministic (unsupported branch)
            endcase
        end
    end

    // ========================================================================
    //  EX/MEM Pipeline Register
    // ========================================================================

    ex_mem_reg u_ex_mem (
        .clk             (clk),
        .reset           (reset),

        // WB control
        .reg_write_in    (id_ex_reg_write),
        .mem_to_reg_in   (id_ex_mem_to_reg),
        .reg_write_out   (ex_mem_reg_write),
        .mem_to_reg_out  (ex_mem_mem_to_reg),

        // MEM control
        .mem_read_in     (id_ex_mem_read),
        .mem_write_in    (id_ex_mem_write),
        .mem_read_out    (ex_mem_mem_read),
        .mem_write_out   (ex_mem_mem_write),

        // Data
        .alu_result_in   (alu_result),
        .rs2_data_in     (forwarded_b),  // Forwarded value for SW store data
        .alu_result_out  (ex_mem_alu_result),
        .rs2_data_out    (ex_mem_rs2_data),

        // Destination register
        .rd_addr_in      (id_ex_rd_addr),
        .rd_addr_out     (ex_mem_rd_addr)
    );

    // ========================================================================
    //  MEM STAGE — Memory Access
    // ========================================================================

    // Data Memory (original .v module — unchanged)
    data_memory u_dmem (
        .clk        (clk),
        .mem_read   (ex_mem_mem_read),
        .mem_write  (ex_mem_mem_write),
        .addr       (ex_mem_alu_result),
        .write_data (ex_mem_rs2_data),
        .read_data  (mem_read_data)
    );

    // ========================================================================
    //  MEM/WB Pipeline Register
    // ========================================================================

    mem_wb_reg u_mem_wb (
        .clk             (clk),
        .reset           (reset),

        // WB control
        .reg_write_in    (ex_mem_reg_write),
        .mem_to_reg_in   (ex_mem_mem_to_reg),
        .reg_write_out   (mem_wb_reg_write),
        .mem_to_reg_out  (mem_wb_mem_to_reg),

        // Data
        .mem_data_in     (mem_read_data),
        .alu_result_in   (ex_mem_alu_result),
        .mem_data_out    (mem_wb_mem_data),
        .alu_result_out  (mem_wb_alu_result),

        // Destination register
        .rd_addr_in      (ex_mem_rd_addr),
        .rd_addr_out     (mem_wb_rd_addr)
    );

    // ========================================================================
    //  WB STAGE — Write Back
    // ========================================================================

    // Write-back mux: select ALU result or memory data
    //   mem_to_reg = 0 → ALU result (ADD, SUB, ADDI)
    //   mem_to_reg = 1 → memory data (LW)
    assign wb_data = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;

    // Register file write port is driven by WB stage signals
    // (wired above in the register_file instantiation)

endmodule
