// ============================================================================
// Module      : cpu_pipeline_top
// File        : cpu_pipeline_top.sv
// Description : 5-Stage Pipelined RV32I + DSP - Full ISA
// ============================================================================

module cpu_pipeline_top (
    input  logic       clk,
    input  logic       reset,
    
    // Debug outputs
    output logic [7:0] debug_pc,
    output logic [7:0] debug_wb,

    // I2C GPIO (Open-Drain, Active-Low Drive)
    inout  wire        i2c_scl,
    inout  wire        i2c_sda,

    // UART Telemetry Output (One-Way TX)
    output logic       uart_tx_out,

    // 7-Segment Display (Hardware Multiplexed)
    output logic [6:0] seg,
    output logic       dp,
    output logic [3:0] an
);

    // ========================================================================
    // Signal Declarations
    // ========================================================================

    // ---- IF Stage ----
    logic [31:0] pc_current, pc_plus4, if_instruction;

    // ---- IF/ID Register Outputs ----
    logic [31:0] if_id_pc, if_id_instruction;

    // ---- ID Stage: Instruction Decode ----
    logic [6:0] id_opcode;
    logic [4:0] id_rd, id_rs1, id_rs2;
    logic [2:0] id_funct3;
    logic [6:0] id_funct7;

    // ---- ID Stage: Control Signals ----
    logic        id_reg_write, id_alu_src, id_mem_read, id_mem_write, id_mem_to_reg;
    logic [3:0]  id_alu_control;
    logic        id_branch;
    logic        id_alu_src_a, id_pc_to_reg, id_jump;
    logic        id_is_mac, id_is_mac_clear, id_mac_to_reg, id_is_mac_read_hi;
    logic        id_rs1_valid, id_rs2_valid;

    // ---- ID Stage: Data ----
    logic [31:0] id_imm, rf_read_data1, rf_read_data2, id_rs1_data, id_rs2_data;

    // ---- ID/EX Register Outputs ----
    logic        id_ex_reg_write, id_ex_mem_to_reg, id_ex_mem_read, id_ex_mem_write;
    logic        id_ex_alu_src;
    logic [3:0]  id_ex_alu_control;
    logic        id_ex_alu_src_a, id_ex_pc_to_reg, id_ex_jump;
    logic        id_ex_branch;
    logic [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    logic [2:0]  id_ex_funct3;
    logic        is_mac_ex, is_mac_clear_ex, mac_to_reg_ex, is_mac_read_hi_ex;

    // ---- EX Stage ----
    logic [31:0] forwarded_a, forwarded_b;
    logic [1:0]  forward_a_sel, forward_b_sel;

    // ---- TCM (Tightly Coupled Memory) ----
    logic        tcm_wea; // Port A write enable
    logic [9:0]  tcm_addra; // Port A address (1024 words)
    logic [31:0] tcm_douta; // Port A read data
    logic [9:0]  tcm_addrb; // Port B address (MAC weight read)
    logic [31:0] tcm_doutb; // Port B read data → MAC tcm_data
    logic        is_tcm_access; // Address decoder: 1 = TCM region
    logic        dmem_mem_read; // Gated read for data_memory
    logic        dmem_mem_write; // Gated write for data_memory
    logic [31:0] dmem_read_data; // data_memory output
    logic [31:0] mem_read_data_muxed; // Final muxed read data

    // ---- I2C GPIO MMIO (0xC000_0000) ----
    logic        is_gpio_access; // Address decoder: 1 = peripheral region (0xCxxx)
    logic        is_i2c_access; // Sub-decode: addr[2]=0 → I2C (0xC0000000)
    logic        is_uart_access; // Sub-decode: addr[2]=1 → UART (0xC0000004)
    logic        gpio_we; // I2C GPIO register write enable
    logic [1:0]  gpio_out_reg; // {SDA, SCL} output latch
    logic [31:0] gpio_rdata; // Peripheral read-back data to CPU
    logic        scl_pin_in; // Sampled SCL pin state
    logic        sda_pin_in; // Sampled SDA pin state

    // ---- UART TX MMIO (0xC000_0004) ----
    logic        uart_we; // UART TX trigger write enable
    logic        uart_tx_valid; // 1-cycle pulse to start TX
    logic        uart_tx_busy; // HIGH while byte is in transit

    // ---- 7-Segment Display MMIO (0xC000_0008) ----
    logic        is_seg_access; // Sub-decode: addr[3:2]=10 → 7-seg
    logic        seg_we; // 7-seg register write enable
    logic [15:0] seg_display_data; // Latched 16-bit display value (4 BCD digits)

    logic [31:0] alu_in1_final, alu_input_b, alu_result;
    logic        alu_zero, alu_sign, alu_overflow, alu_carry;
    logic        branch_taken, pc_redirect;
    logic [31:0] pc_branch, jalr_target, redirect_target;
    logic [31:0] pc_plus4_ex, ex_stage_result;

    // ---- MAC ----
    logic        mac_busy_ex, mac_started_reg, mac_start_pulse, mac_stall_request;
    logic signed [63:0] mac_result_full_ex;
    logic        mac_overflow_ex;
    logic [31:0] sliced_mac_result;

    // ---- EX/MEM Register Outputs ----
    logic        ex_mem_reg_write, ex_mem_mem_to_reg, ex_mem_mem_read, ex_mem_mem_write;
    logic [31:0] ex_mem_alu_result, ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd_addr;

    // ---- MEM Stage (read data handled by address decoder below) ----

    // ---- MEM/WB Register Outputs ----
    logic        mem_wb_reg_write, mem_wb_mem_to_reg;
    logic [31:0] mem_wb_mem_data, mem_wb_alu_result;
    logic [4:0]  mem_wb_rd_addr;

    // ---- WB Stage ----
    logic [31:0] wb_data;

    // ---- Hazard / Control ----
    logic stall, pc_write, if_id_stall, if_id_flush, id_ex_flush;
    logic id_ex_stall, ex_mem_flush_sig;

    // ========================================================================
    // Hazard & Control Wiring
    // ========================================================================

    // pc_redirect: branch taken OR unconditional jump
    assign pc_redirect = branch_taken | id_ex_jump;

    assign pc_write        = ~(stall | mac_stall_request) | pc_redirect;
    assign if_id_stall     = (stall | mac_stall_request) & ~pc_redirect;
    assign if_id_flush     = pc_redirect;
    assign id_ex_flush     = stall | pc_redirect;
    assign id_ex_stall     = mac_stall_request;
    assign ex_mem_flush_sig = mac_stall_request;

    // ========================================================================
    //  IF STAGE
    // ========================================================================

    assign pc_plus4 = pc_current + 32'd4;

    pc_pipe u_pc (
        .clk       (clk),
        .reset     (reset),
        .pc_write  (pc_write),
        .pc_src    (pc_redirect),
        .pc_branch (redirect_target),
        .pc_out    (pc_current)
    );

    instruction_memory_pipe u_imem (
        .clk         (clk),
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
    //  ID STAGE
    // ========================================================================

    assign id_opcode = if_id_instruction[6:0];
    assign id_rd     = if_id_instruction[11:7];
    assign id_funct3 = if_id_instruction[14:12];
    assign id_rs1    = if_id_instruction[19:15];
    assign id_rs2    = if_id_instruction[24:20];
    assign id_funct7 = if_id_instruction[31:25];

    control_unit_pipe u_control (
        .opcode         (id_opcode),
        .funct3         (id_funct3),
        .funct7         (id_funct7),
        .reg_write      (id_reg_write),
        .alu_src        (id_alu_src),
        .mem_read       (id_mem_read),
        .mem_write      (id_mem_write),
        .mem_to_reg     (id_mem_to_reg),
        .alu_control    (id_alu_control),
        .branch         (id_branch),
        .alu_src_a      (id_alu_src_a),
        .pc_to_reg      (id_pc_to_reg),
        .jump           (id_jump),
        .is_mac         (id_is_mac),
        .is_mac_clear   (id_is_mac_clear),
        .mac_to_reg     (id_mac_to_reg),
        .is_mac_read_hi (id_is_mac_read_hi),
        .rs1_valid      (id_rs1_valid),
        .rs2_valid      (id_rs2_valid)
    );

    imm_gen_pipe u_imm_gen (
        .instruction (if_id_instruction),
        .imm_out     (id_imm)
    );

    register_file u_regfile (
        .clk        (clk),
        .reset      (reset),
        .we         (mem_wb_reg_write),
        .rs1        (id_rs1),
        .rs2        (id_rs2),
        .rd         (mem_wb_rd_addr),
        .write_data (wb_data),
        .read_data1 (rf_read_data1),
        .read_data2 (rf_read_data2)
    );

    // WB-to-ID bypass
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
        .rs1_valid      (id_rs1_valid),
        .rs2_valid      (id_rs2_valid),
        .stall          (stall)
    );

    // ========================================================================
    //  ID/EX Pipeline Register
    // ========================================================================

    id_ex_reg u_id_ex (
        .clk             (clk),
        .reset           (reset),
        .flush           (id_ex_flush),
        .stall           (id_ex_stall),
        // WB
        .reg_write_in    (id_reg_write),    .reg_write_out   (id_ex_reg_write),
        .mem_to_reg_in   (id_mem_to_reg),   .mem_to_reg_out  (id_ex_mem_to_reg),
        // MEM
        .mem_read_in     (id_mem_read),     .mem_read_out    (id_ex_mem_read),
        .mem_write_in    (id_mem_write),    .mem_write_out   (id_ex_mem_write),
        // EX
        .alu_src_in      (id_alu_src),      .alu_src_out     (id_ex_alu_src),
        .alu_control_in  (id_alu_control),  .alu_control_out (id_ex_alu_control),
        // New RV32I
        .alu_src_a_in    (id_alu_src_a),    .alu_src_a_out   (id_ex_alu_src_a),
        .pc_to_reg_in    (id_pc_to_reg),    .pc_to_reg_out   (id_ex_pc_to_reg),
        .jump_in         (id_jump),         .jump_out        (id_ex_jump),
        // Branch
        .branch_in       (id_branch),       .branch_out      (id_ex_branch),
        // DSP
        .is_mac_in       (id_is_mac),       .is_mac_out      (is_mac_ex),
        .is_mac_clear_in (id_is_mac_clear), .is_mac_clear_out(is_mac_clear_ex),
        .mac_to_reg_in   (id_mac_to_reg),   .mac_to_reg_out  (mac_to_reg_ex),
        .is_mac_read_hi_in(id_is_mac_read_hi), .is_mac_read_hi_out(is_mac_read_hi_ex),
        // Data
        .pc_in           (if_id_pc),        .pc_out          (id_ex_pc),
        .rs1_data_in     (id_rs1_data),     .rs1_data_out    (id_ex_rs1_data),
        .rs2_data_in     (id_rs2_data),     .rs2_data_out    (id_ex_rs2_data),
        .imm_in          (id_imm),          .imm_out         (id_ex_imm),
        // Addresses
        .rs1_addr_in     (id_rs1),          .rs1_addr_out    (id_ex_rs1_addr),
        .rs2_addr_in     (id_rs2),          .rs2_addr_out    (id_ex_rs2_addr),
        .rd_addr_in      (id_rd),           .rd_addr_out     (id_ex_rd_addr),
        // funct3
        .funct3_in       (id_funct3),       .funct3_out      (id_ex_funct3)
    );

    // ========================================================================
    //  EX STAGE
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

    // ---- Forwarding Muxes ----
    always_comb begin
        case (forward_a_sel)
            2'b10:   forwarded_a = ex_mem_alu_result;
            2'b01:   forwarded_a = wb_data;
            default: forwarded_a = id_ex_rs1_data;
        endcase
    end
    always_comb begin
        case (forward_b_sel)
            2'b10:   forwarded_b = ex_mem_alu_result;
            2'b01:   forwarded_b = wb_data;
            default: forwarded_b = id_ex_rs2_data;
        endcase
    end

    // ---- ALU Input A Mux: rs1 or PC (AUIPC) ----
    assign alu_in1_final = id_ex_alu_src_a ? id_ex_pc : forwarded_a;

    // ---- ALU Input B Mux: rs2 or immediate ----
    assign alu_input_b = id_ex_alu_src ? id_ex_imm : forwarded_b;

    // ---- ALU (new 4-bit, full RV32I) ----
    alu u_alu (
        .alu_in1     (alu_in1_final),
        .alu_in2     (alu_input_b),
        .alu_control (id_ex_alu_control),
        .alu_result  (alu_result),
        .zero        (alu_zero),
        .sign        (alu_sign),
        .overflow    (alu_overflow),
        .carry       (alu_carry)
    );

    // ---- MAC Pulse Generator & Stall ----
    always_ff @(posedge clk) begin
        if (reset || !is_mac_ex)
            mac_started_reg <= 0;
        else if (is_mac_ex && !mac_busy_ex)
            mac_started_reg <= 1;
    end

    assign mac_start_pulse   = is_mac_ex & ~mac_started_reg & ~mac_busy_ex;
    assign mac_stall_request = is_mac_ex & ~(mac_started_reg & ~mac_busy_ex);

    // ---- TCM Port B: MAC Weight Stream (EX stage) ----
    assign tcm_addrb = forwarded_b[11:2];

    // ---- MAC Unit (TCM-fed) ----
    // mac_abort is wired to pc_redirect (branch taken | jump) to avoid aborting on load-use stalls.
    mac_unit dsp_core (
        .clk             (clk),
        .reset           (reset),
        .mac_start       (mac_start_pulse),
        .clear_accum     (is_mac_clear_ex),
        .mac_abort       (pc_redirect),
        .operand_a       (forwarded_a),
        .tcm_data        (tcm_doutb), // Fed by TCM Port B output
        .mac_result_full (mac_result_full_ex),
        .mac_busy        (mac_busy_ex),
        .mac_overflow    (mac_overflow_ex)
    );

    // ---- MAC 64-bit Slicer ----
    assign sliced_mac_result = is_mac_read_hi_ex
    ? mac_result_full_ex[63:32]
    : mac_result_full_ex[31:0];

    // ---- EX Stage Result Mux ----
    assign pc_plus4_ex = id_ex_pc + 32'd4;

    always_comb begin
        if (id_ex_pc_to_reg)
            ex_stage_result = pc_plus4_ex;
        else if (mac_to_reg_ex)
            ex_stage_result = sliced_mac_result;
        else
            ex_stage_result = alu_result;
    end

    // ---- Branch Comparator (EX stage, full RV32I) ----
    assign pc_branch = id_ex_pc + id_ex_imm;

    always_comb begin
        branch_taken = 1'b0;
        if (id_ex_branch) begin
            case (id_ex_funct3)
                3'b000:  branch_taken = (forwarded_a == forwarded_b);
                3'b001:  branch_taken = (forwarded_a != forwarded_b);
                3'b100:  branch_taken = ($signed(forwarded_a) < $signed(forwarded_b));
                3'b101:  branch_taken = ($signed(forwarded_a) >= $signed(forwarded_b));
                3'b110:  branch_taken = (forwarded_a < forwarded_b);
                3'b111:  branch_taken = (forwarded_a >= forwarded_b);
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // ---- Jump Target ----
    assign jalr_target = alu_result & 32'hFFFFFFFE;

    always_comb begin
        if (id_ex_jump && id_ex_alu_src)
            redirect_target = jalr_target;
        else
            redirect_target = pc_branch;
    end

    // ========================================================================
    //  EX/MEM Pipeline Register
    // ========================================================================

    ex_mem_reg u_ex_mem (
        .clk             (clk),
        .reset           (reset),
        .flush           (ex_mem_flush_sig),
        .reg_write_in    (id_ex_reg_write),  .reg_write_out  (ex_mem_reg_write),
        .mem_to_reg_in   (id_ex_mem_to_reg), .mem_to_reg_out (ex_mem_mem_to_reg),
        .mem_read_in     (id_ex_mem_read),   .mem_read_out   (ex_mem_mem_read),
        .mem_write_in    (id_ex_mem_write),  .mem_write_out  (ex_mem_mem_write),
        .alu_result_in   (ex_stage_result),  .alu_result_out (ex_mem_alu_result),
        .rs2_data_in     (forwarded_b),      .rs2_data_out   (ex_mem_rs2_data),
        .rd_addr_in      (id_ex_rd_addr),    .rd_addr_out    (ex_mem_rd_addr)
    );

    // ========================================================================
    //  MEM STAGE — Address Decoder & Memory Subsystems
    // ========================================================================
    assign is_tcm_access  = (ex_mem_alu_result[31:30] == 2'b10);
    assign is_gpio_access = (ex_mem_alu_result[31:30] == 2'b11);

    // Gate memory control signals — each region is mutually exclusive
    assign dmem_mem_read  = ex_mem_mem_read  & ~is_tcm_access & ~is_gpio_access;
    assign dmem_mem_write = ex_mem_mem_write & ~is_tcm_access & ~is_gpio_access;
    assign tcm_wea        = ex_mem_mem_write &  is_tcm_access;

    // ---- Peripheral Sub-Decode (0xC000_xxxx region) ----
    assign is_i2c_access  = is_gpio_access & (ex_mem_alu_result[3:2] == 2'b00);
    assign is_uart_access = is_gpio_access & (ex_mem_alu_result[3:2] == 2'b01);
    assign is_seg_access  = is_gpio_access & (ex_mem_alu_result[3:2] == 2'b10);
    assign gpio_we        = ex_mem_mem_write &  is_i2c_access;
    assign uart_we        = ex_mem_mem_write &  is_uart_access;
    assign seg_we         = ex_mem_mem_write &  is_seg_access;

    // TCM Port A Address MUX — BRAM Latency Compensation
    assign tcm_addra = tcm_wea ? ex_mem_alu_result[11:2] : alu_result[11:2];

    // Standard data memory (non-TCM region)
    data_memory u_dmem (
        .clk        (clk),
        .mem_read   (dmem_mem_read),
        .mem_write  (dmem_mem_write),
        .addr       (ex_mem_alu_result),
        .write_data (ex_mem_rs2_data),
        .read_data  (dmem_read_data)
    );

    // TCM: True Dual-Port BRAM
    tcm_ram u_tcm (
        .clka   (clk),
        .wea    (tcm_wea),
        .addra  (tcm_addra),
        .dina   (ex_mem_rs2_data),
        .douta  (tcm_douta),
        .clkb   (clk),
        .addrb  (tcm_addrb),
        .doutb  (tcm_doutb)
    );

    // ========================================================================
    //  I2C GPIO MMIO Register (0xC000_0000)
    // ========================================================================

    // ========================================================================
    //  I2C Bidirectional I/O — Isolated IOBUF Wrapper
    // ========================================================================

    // ---- GPIO Output Register (Write Path) ----
    always_ff @(posedge clk) begin
        if (reset)
            gpio_out_reg <= 2'b11;
        else if (gpio_we)
            gpio_out_reg <= ex_mem_rs2_data[1:0];
    end

    // ---- GPIO Read-Back (Read Path) ----

    // ========================================================================
    //  UART TX Peripheral (0xC000_0004)
    // ========================================================================

    // Generate a single-cycle valid pulse on the write edge.
    assign uart_tx_valid = uart_we;

    uart_tx #(
        .CLK_FREQ  (100_000_000),
        .BAUD_RATE (115_200)
    ) u_uart_tx (
        .clk       (clk),
        .reset     (reset),
        .tx_data   (ex_mem_rs2_data[7:0]),
        .tx_valid  (uart_tx_valid),
        .tx_out    (uart_tx_out),
        .tx_busy   (uart_tx_busy)
    );

    // ========================================================================
    //  7-Segment Display Peripheral (0xC000_0008)
    // ========================================================================

    // ---- Display Data Register ----
    always_ff @(posedge clk) begin
        if (reset)
            seg_display_data <= 16'h0000;
        else if (seg_we)
            seg_display_data <= ex_mem_rs2_data[15:0];
    end

    // ---- Hardware Display Controller ----
    seg_display u_seg_display (
        .clk          (clk),
        .reset        (reset),
        .display_data (seg_display_data),
        .an           (an),
        .seg          (seg),
        .dp           (dp)
    );

    // ========================================================================
    //  Peripheral Read-Back Mux (I2C / UART / 7-Seg / GPIO Debug)
    // ========================================================================
    always_comb begin
        case (ex_mem_alu_result[3:2])
            2'b00:   gpio_rdata = {30'b0, sda_pin_in, scl_pin_in};
            2'b01:   gpio_rdata = {31'b0, uart_tx_busy};
            2'b10:   gpio_rdata = {16'b0, seg_display_data};
            2'b11:   gpio_rdata = {30'b0, gpio_out_reg}; // Debug: output reg
            default: gpio_rdata = 32'b0;
        endcase
    end

    // ========================================================================
    //  MEM Read Data Mux — 3-Way: DMEM / TCM / Peripherals
    // ========================================================================
    always_comb begin
        if (is_gpio_access)
            mem_read_data_muxed = gpio_rdata;
        else if (is_tcm_access)
            mem_read_data_muxed = tcm_douta;
        else
            mem_read_data_muxed = dmem_read_data;
    end

    // ========================================================================
    //  MEM/WB Pipeline Register
    // ========================================================================

    mem_wb_reg u_mem_wb (
        .clk             (clk),
        .reset           (reset),
        .reg_write_in    (ex_mem_reg_write),  .reg_write_out  (mem_wb_reg_write),
        .mem_to_reg_in   (ex_mem_mem_to_reg), .mem_to_reg_out (mem_wb_mem_to_reg),
        .mem_data_in     (mem_read_data_muxed), .mem_data_out (mem_wb_mem_data),
        .alu_result_in   (ex_mem_alu_result),  .alu_result_out (mem_wb_alu_result),
        .rd_addr_in      (ex_mem_rd_addr),     .rd_addr_out    (mem_wb_rd_addr)
    );

    // ========================================================================
    //  WB STAGE
    // ========================================================================

    assign wb_data = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;

    // ========================================================================
    //  DEBUG OUTPUTS
    // ========================================================================

    assign debug_pc = pc_current[7:0];
    assign debug_wb = wb_data[7:0];

endmodule
