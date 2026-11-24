// ============================================================================
// Module      : cpu_pipeline_top
// File        : cpu_pipeline_top.sv
// Description : 5-Stage Pipelined RV32IM + Zicsr + M-mode traps + DSP
// ============================================================================

module cpu_pipeline_top #(
    parameter IMEM_INIT  = "imem.hex",  // $readmemh image for IMEM (.text)
    parameter TCM_INIT   = "tcm.hex",   // $readmemh image for TCM (.rodata/.data)
    // Memories are reached only through imem_wrap / tcm_wrap.
    parameter string MEM_TECH   = "FPGA",  // "FPGA" (LUT-ROM / BRAM) or "ASIC" (macro slot)
    parameter int    IMEM_WORDS = 2048,    // 8 KB at 0x0000_0000 (power of two)
    parameter int    TCM_WORDS  = 1024,    // 4 KB at 0x8000_0000 (power of two)
    parameter int    CLK_FREQ   = 100_000_000,
    parameter bit    SEG_EN     = 1'b1,    // 7-segment controller (FPGA board only)
    parameter int    BUS_TIMEOUT = 256     // cycles before a bus access faults
)(
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

    localparam int          IMEM_AW  = $clog2(IMEM_WORDS);  // IMEM word-address bits
    localparam int          TCM_AW   = $clog2(TCM_WORDS);   // TCM word-address bits
    localparam logic [31:0] TCM_BASE = 32'h8000_0000;

    // ---- IF Stage ----
    logic [31:0] pc_current, if_instruction;

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
    logic        id_is_mac, id_is_mac_clear, id_mac_to_reg, id_is_mac_rdshift;
    logic        id_is_muldiv;
    logic        id_is_csr, id_csr_we;
    logic [1:0]  id_mac_rd_op;
    logic        id_rs1_valid, id_rs2_valid;
    logic        id_illegal;

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
    logic        is_mac_ex, is_mac_clear_ex, mac_to_reg_ex, is_mac_rdshift_ex;
    logic        is_muldiv_ex;
    logic        is_csr_ex, csr_we_ex;
    logic [1:0]  mac_rd_op_ex;

    // ---- EX Stage ----
    logic [31:0] forwarded_a, forwarded_b;
    logic [1:0]  forward_a_sel, forward_b_sel;

    // ---- TCM (Tightly Coupled Memory) ----
    logic [3:0]  tcm_wea; // Port A byte write enables
    logic [TCM_AW-1:0] tcm_addra; // Port A word address
    logic [31:0] tcm_dina; // Port A write data
    logic [31:0] tcm_douta; // Port A read data
    logic [31:0] ex_eff_addr; // AGU: load/store effective address rs1 + imm
    logic        ex_is_tcm; // EX-stage decode: effective address is in TCM (exact)
    logic        ex_hold_src; // OR of every EX-hold source (see "EX hold" below)
    logic        ex_hold; // EX instruction does not advance this cycle
    logic [3:0]  cpu_tcm_we; // CPU port-A request: byte write enables (from EX)
    logic [1:0]  ex_addr_lo; // Effective address [1:0]
    logic [3:0]  ex_store_be; // Store byte lanes for SB/SH/SW
    logic [31:0] ex_store_data; // Store data replicated into its lane(s)
    logic [TCM_AW-1:0] cpu_tcm_addr; // CPU port-A request: word address (from EX)
    logic [31:0] cpu_tcm_wdata; // CPU port-A request: write data (lane-replicated rs2)
    logic [TCM_AW-1:0] tcm_addrb; // Port B address (MAC weight read)
    logic [31:0] tcm_doutb; // Port B read data → MAC tcm_data
    logic        is_tcm_access; // MEM decode: TCM_BASE .. TCM_BASE + 4*TCM_WORDS - 1
    logic [31:0] mem_read_data_muxed; // Muxed read word (TCM / peripheral / 0)
    logic [31:0] mem_load_data; // Load result after byte/half select and extend
    logic [31:0] mem_result;    // MEM: write-back value (load data or EX result)
    logic [2:0]  ex_mem_funct3; // Load/store width in MEM

    // ---- Data-bus decode / unmapped-access fault ----
    logic        is_periph_region; // MEM decode: 0xC000_0000..0xC000_0FFF
    logic        is_tohost; // 0xC000_0FFC: reserved simulation halt (writes ignored)
    logic        is_timer;  // 0xC000_0100..0xC000_010F: mtime / mtimecmp
    logic        timer_we;
    logic [31:0] timer_rdata;
    logic        mem_access; // Load or store in MEM
    // ---- Data bus (MEM) and the global MEM stall ----
    // A load/store in MEM that is not TCM or core-local (mtimer, tohost)
    // is a bus access. It holds MEM until the bus answers: mem_stall
    // freezes the whole pipeline (PC, IF/ID, ID/EX, EX/MEM, MEM/WB, the
    // register-file write and instret) for that time.
    logic        mem_core_local;   // MEM: mtimer page or tohost word (answered in the core)
    logic        mem_is_bus;       // MEM: load/store that goes to the data bus
    logic        bus_rsp_done;     // the bus access in MEM completes this cycle
    logic        bus_rsp_err;      // ... with an error (access fault)
    logic [31:0] bus_rsp_rdata;    // ... and this read data
    logic        mem_stall;        // global stall: MEM waits for the bus
    logic        ex_advance;       // the EX instruction leaves EX this cycle
    logic        rf_we;            // register-file write (WB, not during a stall)
    // Test hook, tied to 0: the testbench forces it to add bus wait states
    // (+BUS_WAIT). Nothing but the bus response path reads it.
    logic        bus_wait_inj;
    // ---- Bus error (MEM): load/store access fault ----
    // A bus access answered with SLVERR/DECERR or timed out traps in MEM in
    // its response cycle (cause 5 load / 7 store, mtval = address): rd is
    // not written. (A store's slave rejected it, so it had no effect.)
    logic        dbus_error;       // MEM: the bus access ends with an error
    logic        ex_misaligned;    // EX:  load/store address not naturally aligned

    logic        scl_pad_in, sda_pad_in;     // raw pad levels (asynchronous)
    logic        scl_drive_low, sda_drive_low;
    logic [3:0]  ex_mem_strb;                // store byte lanes in MEM (AXI WSTRB)

    // ---- AXI4 data-bus master port (MEM) ----
    logic        axi_awvalid, axi_awready, axi_wvalid, axi_wready, axi_wlast;
    logic        axi_bvalid, axi_bready, axi_arvalid, axi_arready;
    logic        axi_rvalid, axi_rready, axi_rlast;
    logic [31:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
    logic [7:0]  axi_awlen, axi_arlen;
    logic [2:0]  axi_awsize, axi_awprot, axi_arsize, axi_arprot;
    logic [1:0]  axi_awburst, axi_arburst, axi_bresp, axi_rresp;
    logic [3:0]  axi_awid, axi_wstrb, axi_bid, axi_arid, axi_rid;

    logic [31:0] alu_in1_final, alu_input_b, alu_result;
    logic        branch_taken, pc_redirect;
    logic [31:0] pc_branch, jalr_target, redirect_target;
    logic [31:0] pc_plus4_ex, ex_stage_result;

    // ---- Multi-cycle EX ops: issue / done handshake (MAC unit and mul_div) ----
    logic        mc_op_ex;        // a multi-cycle op is in EX
    logic        mc_busy;         // the unit running it is busy
    logic        mc_started_reg;  // the op in EX has been issued to its unit
    logic        mc_start_pulse;  // issue it this cycle (unless killed)
    logic        mc_issue;        // start pulse that is not killed
    logic        mc_done_ex;      // its unit has finished: result valid this cycle
    logic        mc_hold;         // EX-hold source: multi-cycle op not done yet

    // ---- MAC ----
    logic        mac_busy_ex, mac_start_pulse;
    logic        mac_clear_commit;   // MAC_CLEAR leaves EX this cycle (not killed)
    logic signed [63:0] mac_result_full_ex; // accumulator saturated to signed 64-bit
    logic [31:0] mac_read_shift_ex;  // READ_SHIFT result (registered in mac_unit)
    logic        mac_overflow_ex;    // sticky overflow (READ_STATUS bit 0)
    logic        mac_op_ex;          // multi-cycle MAC-unit op in EX: MAC or READ_SHIFT
    logic        mac_rd64_strobe;    // READ_LO/HI in EX (may set the sticky flag)
    logic [31:0] sliced_mac_result;

    // ---- Traps (machine mode) ----
    // Exceptions are flagged where they are detected (IF: fetch fault; ID:
    // illegal, ECALL, EBREAK; EX: misaligned load/store or branch/jump
    // target), travel down the pipeline with the instruction, and are taken
    // in MEM from the registered EX/MEM flag.
    logic        if_fetch_fault, if_id_fetch_fault;
    logic        id_is_ecall, id_is_ebreak, id_is_mret;
    logic        id_exc;                    // ID-stage exception
    logic [4:0]  id_cause;                  // {interrupt, code}
    logic        id_ex_exc, id_ex_is_mret;
    logic [4:0]  id_ex_cause;
    logic        ex_target_misaligned;      // taken branch/jump to a target with bit 1 set
    logic        ex_exc;                    // EX instruction traps when it reaches MEM
    logic [4:0]  ex_cause;
    logic [31:0] ex_tval;
    logic        ex_mem_exc, ex_mem_is_mret;
    logic [4:0]  ex_mem_cause;
    logic [31:0] ex_mem_pc, ex_mem_tval;
    logic        mem_trap;                  // take a trap this cycle
    logic [4:0]  mem_trap_cause;            // its cause {interrupt, code}
    logic [31:0] mem_trap_tval;             // its mtval
    logic        mem_mret;                  // MRET returns this cycle
    logic        mem_redirect;              // trap or MRET: PC <= mtvec / mepc
    logic [31:0] mem_redirect_target;
    logic        ex_kill;                   // the EX instruction is younger than a trap/MRET: commit nothing
    logic [31:0] csr_mtvec, csr_mepc;

    // ---- Interrupts ----
    // Taken by tagging the instruction in ID (it becomes a bubble that traps
    // in MEM with mepc = its PC), so an interrupt never cuts into an op held
    // in EX: the tagged instruction simply waits in ID behind it.
    logic        ext_irq;                   // external interrupt request (level)
    (* ASYNC_REG = "TRUE" *) logic [1:0] ext_irq_sync;
    logic        meip;                      // synchronised external line
    logic        mtip;                      // timer compare (registered in mtimer)
    logic [63:0] mtime;
    logic        irq_pending;               // MIE & enabled & pending (registers only)
    logic [4:0]  irq_cause;
    logic        irq_tag;                   // the ID instruction takes the interrupt

    // ---- Valid bits (0 = bubble), one per pipeline register ----
    logic        if_id_valid, id_ex_valid, ex_mem_valid, mem_wb_valid;

    // ---- Zicsr ----
    logic [31:0] csr_rdata;     // CSR read value (EX)
    logic [31:0] csr_wsrc;      // rs1 or zero-extended uimm
    logic        csr_commit;    // CSR write takes effect at this EX->MEM edge

    // ---- M extension (mul_div) ----
    logic        muldiv_start, muldiv_busy;
    logic [31:0] muldiv_result;      // registered in mul_div

    // ---- EX/MEM Register Outputs ----
    logic        ex_mem_reg_write, ex_mem_mem_to_reg, ex_mem_mem_read, ex_mem_mem_write;
    logic [31:0] ex_mem_alu_result;
    // Store data in MEM feeds the peripherals (the timer uses all 32 bits).
    logic [31:0] ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd_addr;

    // ---- MEM Stage (read data handled by address decoder below) ----

    // ---- MEM/WB Register Outputs ----
    logic        mem_wb_reg_write;
    logic [31:0] mem_wb_result;      // write-back value, selected in MEM
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

    // ---- EX hold ----
    // ex_hold is the single net that holds the EX instruction (IF/ID/EX
    // frozen, a bubble into MEM). Every hold source is ORed into ex_hold_src;
    // nothing else may read a hold source directly. The testbench EX-hold
    // hook forces ex_hold and then re-forces it to ex_hold_src, so adding a
    // source here needs no testbench change.
    assign ex_hold_src = mc_hold;
    assign ex_hold     = ex_hold_src;

    // ---- Global MEM stall ----
    // mem_stall freezes every pipeline register. The EX instruction leaves
    // EX only when neither EX nor MEM holds it: every EX commit point (TCM
    // store, CSR write, MAC_CLEAR, READ_LO/HI flag, multi-cycle issue
    // bookkeeping) uses ex_advance. A trap/MRET in MEM never coincides with
    // mem_stall (a stalled access traps, if at all, in its response cycle).
    assign ex_advance = ~ex_hold & ~mem_stall;

    // A trap or MRET in MEM (mem_redirect) is older than everything in
    // IF/ID/EX: it wins over an EX redirect and over any hold, and flushes
    // IF/ID, ID/EX and EX/MEM (ex_kill blocks the EX instruction's commits).
    // A branch/jump in EX during mem_stall keeps redirecting the PC and
    // flushing IF/ID (both idempotent) but must not flush ID/EX: it is
    // still in EX. The ID/EX bubble of a load-use stall waits likewise.
    assign pc_write        = ~(stall | ex_hold | mem_stall) | pc_redirect | mem_redirect;
    // A flush wins over a stall in IF/ID, so pc_redirect is not needed here.
    assign if_id_stall     = stall | ex_hold | mem_stall;
    assign if_id_flush     = pc_redirect | mem_redirect;
    assign id_ex_flush     = ((stall | pc_redirect) & ~mem_stall) | mem_redirect;
    assign id_ex_stall     = ex_hold | mem_stall;
    assign ex_mem_flush_sig = (ex_hold & ~mem_stall) | ex_kill;

    // ========================================================================
    //  IF STAGE
    // ========================================================================

    pc_pipe u_pc (
        .clk       (clk),
        .reset     (reset),
        .pc_write  (pc_write),
        .pc_src    (pc_redirect | mem_redirect),
        .pc_branch (mem_redirect ? mem_redirect_target : redirect_target),
        .pc_out    (pc_current)
    );

    // Instruction access fault: the IMEM is 4*IMEM_WORDS bytes at
    // 0x0000_0000; a PC outside it fetches nothing valid (the instruction
    // is squashed in ID and traps with cause 1 if it reaches MEM).
    assign if_fetch_fault = (pc_current[31:IMEM_AW+2] != '0);

    imem_wrap #(
        .MEM_TECH  (MEM_TECH),
        .WORDS     (IMEM_WORDS),
        .INIT_FILE (IMEM_INIT)
    ) u_imem (
        .word_addr   (pc_current[IMEM_AW+1:2]),
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
        .instruction_out (if_id_instruction),
        .valid_in        (1'b1),
        .valid_out       (if_id_valid),
        .fetch_fault_in  (if_fetch_fault),
        .fetch_fault_out (if_id_fetch_fault)
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
        .imm12          (if_id_instruction[31:20]),
        .rs1_field      (id_rs1),
        .rd_field       (id_rd),
        .squash         (if_id_fetch_fault | irq_tag | ~if_id_valid),
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
        .mac_rd_op      (id_mac_rd_op),
        .is_mac_rdshift (id_is_mac_rdshift),
        .is_muldiv      (id_is_muldiv),
        .is_csr         (id_is_csr),
        .csr_we         (id_csr_we),
        .is_ecall       (id_is_ecall),
        .is_ebreak      (id_is_ebreak),
        .is_mret        (id_is_mret),
        .rs1_valid      (id_rs1_valid),
        .rs2_valid      (id_rs2_valid),
        .illegal        (id_illegal)
    );

    imm_gen_pipe u_imm_gen (
        .instruction (if_id_instruction),
        .imm_out     (id_imm)
    );

    register_file u_regfile (
        .clk        (clk),
        .reset      (reset),
        .we         (rf_we),
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

    // ---- Interrupt tag ----
    // A valid ID instruction takes a pending, enabled interrupt. Not while a
    // CSR instruction is in EX: it may be changing mstatus/mie this very
    // cycle (its write lands at the end of the cycle), so the decision waits
    // one cycle for the new value.
    assign irq_tag = if_id_valid & irq_pending & ~is_csr_ex;

    // ---- ID-stage exceptions (priority: interrupt, fetch fault, illegal,
    //      EBREAK, ECALL). The control unit already turned it into a bubble.
    // A bubble in IF/ID (flushed: stale instruction bits) raises nothing.
    assign id_exc = if_id_valid &
                    (irq_tag | if_id_fetch_fault | id_illegal | id_is_ecall | id_is_ebreak);
    always_comb begin
        if (irq_tag)                id_cause = irq_cause;  // {1, 7 or 11}
        else if (if_id_fetch_fault) id_cause = 5'd1;    // instruction access fault
        else if (id_illegal)   id_cause = 5'd2;    // illegal instruction
        else if (id_is_ebreak) id_cause = 5'd3;    // breakpoint
        else                   id_cause = 5'd11;   // ECALL from M-mode
    end

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
        .mac_rd_op_in    (id_mac_rd_op),    .mac_rd_op_out   (mac_rd_op_ex),
        .is_mac_rdshift_in(id_is_mac_rdshift), .is_mac_rdshift_out(is_mac_rdshift_ex),
        // M extension
        .is_muldiv_in    (id_is_muldiv),    .is_muldiv_out   (is_muldiv_ex),
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
        .funct3_in       (id_funct3),       .funct3_out      (id_ex_funct3),
        // Operand refresh while EX is held (see id_ex_reg)
        .rs1_fwd_in      (forwarded_a),     .rs2_fwd_in      (forwarded_b),
        // Illegal-instruction flag
        .exc_in          (id_exc),          .exc_out         (id_ex_exc),
        // Valid bit, Zicsr
        .valid_in        (if_id_valid),     .valid_out       (id_ex_valid),
        .is_csr_in       (id_is_csr),       .is_csr_out      (is_csr_ex),
        .csr_we_in       (id_csr_we),       .csr_we_out      (csr_we_ex),
        .cause_in        (id_cause),        .cause_out       (id_ex_cause),
        .is_mret_in      (id_is_mret),      .is_mret_out     (id_ex_is_mret)
    );

    // ========================================================================
    //  EX STAGE
    // ========================================================================

    // ---- Forwarding Unit ----
    // Registered selects, computed in the previous cycle (see forwarding_unit).
    forwarding_unit u_forward (
        .clk              (clk),
        .reset            (reset),
        .hold             (ex_hold),
        .freeze           (mem_stall),
        .id_rs1           (id_rs1),
        .id_rs2           (id_rs2),
        .id_ex_rs1        (id_ex_rs1_addr),
        .id_ex_rs2        (id_ex_rs2_addr),
        .id_ex_rd         (id_ex_rd_addr),
        .id_ex_reg_write  (id_ex_reg_write),
        .ex_mem_rd        (ex_mem_rd_addr),
        .ex_mem_reg_write (ex_mem_reg_write),
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
        .alu_result  (alu_result)
    );

    // ---- Multi-cycle EX ops: one issue / done handshake ----
    // MAC-unit ops (MAC, READ_SHIFT) and M-extension ops (mul_div) hold EX
    // until their unit finishes. At most one multi-cycle op is in EX, so the
    // units are never busy at the same time and their busy flags can be ORed.
    //   cycle 0      : op enters EX, start pulse to its unit, EX held
    //   busy cycles  : EX held
    //   done cycle   : unit idle again, result register valid, EX released
    // mc_started_reg marks "the op in EX has been issued". It clears when the
    // op actually leaves EX (~ex_hold), not when its unit finishes, so a
    // second hold source keeping EX held after done can never re-issue the op
    // (F1 was this logic: a back-to-back MAC saw started=1 and was lost).
    // Every unit's result comes from a register, so nothing new sits between
    // the forwarding muxes and the ALU. (Latching mul_div operands at start
    // does add load on the forwarding muxes; see the timing notes.)
    assign mac_op_ex      = is_mac_ex | is_mac_rdshift_ex;
    assign mc_op_ex       = mac_op_ex | is_muldiv_ex;
    assign mc_busy        = mac_busy_ex | muldiv_busy;
    assign mc_start_pulse = mc_op_ex & ~mc_started_reg & ~mc_busy;
    assign mc_done_ex     = mc_op_ex &  mc_started_reg & ~mc_busy;
    assign mc_hold        = mc_op_ex & ~mc_done_ex;

    // A start in the cycle a trap/MRET is taken in MEM is killed: the op is
    // younger and is flushed from EX, so its unit must never start. Nor
    // does it start under mem_stall: the access in MEM may still fault.
    assign mc_issue        = mc_start_pulse & ~ex_kill & ~mem_stall;
    assign mac_start_pulse = mc_issue & mac_op_ex;
    assign muldiv_start    = mc_issue & is_muldiv_ex;

    // Cleared when the op leaves EX (ex_advance), not when its unit is done:
    // a finished op frozen in EX by mem_stall must not be issued again.
    always_ff @(posedge clk) begin
        if (reset || !mc_op_ex || ex_advance)
            mc_started_reg <= 1'b0;
        else if (mc_issue)
            mc_started_reg <= 1'b1;
    end

    // ---- TCM Port A: CPU data access (EX stage) ----
    // Loads and stores both present their address from EX: the 1-cycle BRAM
    // read then lines up with MEM, and a store writes at the EX->MEM edge.
    // Port A therefore never has to choose between two pipeline stages.
    // A store writes exactly once: only on the cycle it leaves EX (ex_advance).
    // A store in EX is never speculative, because an older branch/jump resolves
    // in EX and squashes it while it is still in ID.
    // A store younger than a trap/MRET in MEM is killed (~ex_kill).
    //
    // AGU: a dedicated adder computes the load/store effective address from
    // the forwarded base and the immediate, so the TCM address, byte lanes and
    // the exact range check do not wait for the ALU's operand and result muxes.
    // For loads/stores it equals alu_result (checked by an SVA in tb/core_sva.sv).
    // The write enable is gated with the exact TCM range, so a store outside
    // 0x8000_0000-0x8000_0FFF writes nothing (it faults in MEM: dbus_error).
    assign ex_eff_addr   = forwarded_a + id_ex_imm;
    assign ex_is_tcm     = (ex_eff_addr[31:TCM_AW+2] == TCM_BASE[31:TCM_AW+2]);
    assign cpu_tcm_we    = ex_store_be & {4{id_ex_mem_write & ex_is_tcm & ~ex_misaligned & ex_advance & ~ex_kill}};
    assign cpu_tcm_addr  = ex_eff_addr[TCM_AW+1:2];
    assign cpu_tcm_wdata = ex_store_data;

    // ---- Store width: byte lanes + lane-replicated data (SB/SH/SW) ----
    // The lane is the low two bits of the AGU effective address.
    // Peripherals are word registers and see the replicated data, so e.g.
    // SB to the UART sends rs2[7:0]. Misaligned SH/SW are not trapped yet:
    // addr[0] (SH) / addr[1:0] (SW) are ignored.
    assign ex_addr_lo = ex_eff_addr[1:0];

    // ---- Misaligned LW/SW/LH/SH: detected in EX, access squashed, traps ----
    // A misaligned access has no architectural effect: no TCM write, and its
    // EX/MEM memory and register-write controls are cleared, so it reaches
    // neither a peripheral nor the register file (nor raises dbus_error).
    // It traps in MEM (cause 4 load / 6 store, mtval = address).
    assign ex_misaligned = (id_ex_mem_read | id_ex_mem_write) &
                           (((id_ex_funct3[1:0] == 2'b10) & (ex_addr_lo != 2'b00)) |  // LW/SW
                            ((id_ex_funct3[1:0] == 2'b01) &  ex_addr_lo[0]));         // LH/LHU/SH


    always_comb begin
        case (id_ex_funct3[1:0])
            2'b00: begin    // SB
                ex_store_be   = 4'b0001 << ex_addr_lo;
                ex_store_data = {4{forwarded_b[7:0]}};
            end
            2'b01: begin    // SH
                ex_store_be   = ex_addr_lo[1] ? 4'b1100 : 4'b0011;
                ex_store_data = {2{forwarded_b[15:0]}};
            end
            default: begin  // SW
                ex_store_be   = 4'b1111;
                ex_store_data = forwarded_b;
            end
        endcase
    end

    // Single requester today; a DMA arbiter would sit between cpu_tcm_* and tcm_*.
    assign tcm_wea   = cpu_tcm_we;
    assign tcm_addra = cpu_tcm_addr;
    assign tcm_dina  = cpu_tcm_wdata;

    // ---- TCM Port B: MAC Weight Stream (EX stage) ----
    assign tcm_addrb = forwarded_b[TCM_AW+1:2];

    // ---- MAC Unit (TCM-fed) ----
    // No abort input: a branch/jump resolves in EX and a MAC-unit op holds EX
    // until it finishes, so a redirect can never coincide with an in-flight op.
    mac_unit dsp_core (
        .clk             (clk),
        .reset           (reset),
        .mac_start       (mac_start_pulse),
        .start_is_shift  (is_mac_rdshift_ex),
        .shamt           (forwarded_a[5:0]),  // latched at start (READ_SHIFT)
        .clear_accum     (mac_clear_commit),
        .rd64_strobe     (mac_rd64_strobe),
        .operand_a       (forwarded_a),
        .tcm_data        (tcm_doutb), // Fed by TCM Port B output
        .mac_result_full (mac_result_full_ex),
        .read_shift_result(mac_read_shift_ex),
        .mac_busy        (mac_busy_ex),
        .mac_overflow    (mac_overflow_ex)
    );

    // ---- M extension: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU ----
    // Separate from the MAC multiplier. Operands are latched on the start
    // cycle from the forwarding muxes; the result is a register in mul_div.
    // No kill input yet (nothing can interrupt an op held in EX today).
    mul_div u_mul_div (
        .clk       (clk),
        .reset     (reset),
        .start     (muldiv_start),
        .op        (id_ex_funct3),
        .operand_a (forwarded_a),
        .operand_b (forwarded_b),
        .busy      (muldiv_busy),
        .result    (muldiv_result)
    );

    // ---- Zicsr: CSR file, accessed in EX ----
    // Read: address from the ID/EX immediate, value from registers, so the
    // CSR read is an early input of the EX result mux. Write: at the EX->MEM
    // edge when the CSR instruction leaves EX (~ex_hold), like a store.
    // Immediate forms use the rs1 field (id_ex_rs1_addr) as a 5-bit uimm.
    assign csr_wsrc   = id_ex_funct3[2] ? {27'b0, id_ex_rs1_addr} : forwarded_a;
    assign csr_commit = is_csr_ex & csr_we_ex & ex_advance & ~ex_kill;

    csr_file u_csr (
        .clk         (clk),
        .reset       (reset),
        .addr        (id_ex_imm[11:0]),
        .op          (id_ex_funct3[1:0]),
        .wsrc        (csr_wsrc),
        .we          (csr_commit),
        .rdata       (csr_rdata),
        .instret_inc (mem_wb_valid & ~mem_stall),
        .trap_take   (mem_trap),
        .trap_cause  (mem_trap_cause),
        .trap_pc     (ex_mem_pc),
        .trap_tval   (mem_trap_tval),
        .mret_take   (mem_mret),
        .mtvec_o     (csr_mtvec),
        .mepc_o      (csr_mepc),
        .mtip        (mtip),
        .meip        (meip),
        .mtime       (mtime),
        .irq_pending (irq_pending),
        .irq_cause   (irq_cause)
    );

    // ---- MAC read select (result path into the EX result mux only) ----
    // All inputs are registers inside mac_unit; nothing here depends on the
    // forwarding muxes or the ALU.
    // EX commit points of the MAC that are not start pulses: MAC_CLEAR and the
    // sticky-overflow update of READ_LO/HI. Both commit once, when the
    // instruction leaves EX, and never when it is killed.
    assign mac_rd64_strobe  = mac_to_reg_ex & ~mac_rd_op_ex[1] & ex_advance & ~ex_kill;
    assign mac_clear_commit = is_mac_clear_ex & ex_advance & ~ex_kill;

    always_comb begin
        case (mac_rd_op_ex)
            2'b00:   sliced_mac_result = mac_result_full_ex[31:0];    // READ_LO
            2'b01:   sliced_mac_result = mac_result_full_ex[63:32];   // READ_HI
            2'b10:   sliced_mac_result = mac_read_shift_ex;           // READ_SHIFT
            default: sliced_mac_result = {31'b0, mac_overflow_ex};    // READ_STATUS
        endcase
    end

    // ---- EX Stage Result Mux ----
    assign pc_plus4_ex = id_ex_pc + 32'd4;

    always_comb begin
        if (id_ex_pc_to_reg)
            ex_stage_result = pc_plus4_ex;
        else if (mac_to_reg_ex)
            ex_stage_result = sliced_mac_result;
        else if (is_muldiv_ex)
            ex_stage_result = muldiv_result;
        else if (is_csr_ex)
            ex_stage_result = csr_rdata;
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

    // ---- EX-stage exceptions ----
    // Instruction-address-misaligned: a taken branch / JAL / JALR whose target
    // has bit 1 set (IALIGN = 32). The redirect still happens in EX, but the
    // instruction traps in MEM one cycle later and that trap flushes whatever
    // was fetched from the target, so architecturally no jump happens (and a
    // JAL/JALR writes no link register). Keeping the exception out of
    // pc_redirect keeps it off the redirect cone.
    assign ex_target_misaligned = pc_redirect & redirect_target[1];
    assign ex_exc = id_ex_exc | ex_misaligned | ex_target_misaligned;

    always_comb begin
        if (id_ex_exc) begin
            ex_cause = id_ex_cause;
            ex_tval  = (id_ex_cause == 5'd1) ? id_ex_pc : 32'd0;   // fetch fault: the PC
        end else if (ex_misaligned) begin
            ex_cause = id_ex_mem_write ? 5'd6 : 5'd4;
            ex_tval  = ex_eff_addr;
        end else begin
            ex_cause = 5'd0;                                      // target misaligned
            ex_tval  = redirect_target;
        end
    end

    // ========================================================================
    //  EX/MEM Pipeline Register
    // ========================================================================

    ex_mem_reg u_ex_mem (
        .clk             (clk),
        .reset           (reset),
        .flush           (ex_mem_flush_sig),
        .en              (~mem_stall),
        .reg_write_in    (id_ex_reg_write & ~ex_exc), .reg_write_out (ex_mem_reg_write),
        .mem_to_reg_in   (id_ex_mem_to_reg), .mem_to_reg_out (ex_mem_mem_to_reg),
        .mem_read_in     (id_ex_mem_read  & ~ex_misaligned), .mem_read_out  (ex_mem_mem_read),
        .mem_write_in    (id_ex_mem_write & ~ex_misaligned), .mem_write_out (ex_mem_mem_write),
        .alu_result_in   (ex_stage_result),  .alu_result_out (ex_mem_alu_result),
        .rs2_data_in     (ex_store_data),    .rs2_data_out   (ex_mem_rs2_data),
        .strb_in         (ex_store_be),      .strb_out       (ex_mem_strb),
        .rd_addr_in      (id_ex_rd_addr),    .rd_addr_out    (ex_mem_rd_addr),
        .funct3_in       (id_ex_funct3),     .funct3_out     (ex_mem_funct3),
        .valid_in        (id_ex_valid),      .valid_out      (ex_mem_valid),
        .exc_in          (ex_exc),           .exc_out        (ex_mem_exc),
        .cause_in        (ex_cause),         .cause_out      (ex_mem_cause),
        .pc_in           (id_ex_pc),         .pc_out         (ex_mem_pc),
        .tval_in         (ex_tval),          .tval_out       (ex_mem_tval),
        .is_mret_in      (id_ex_is_mret),    .is_mret_out    (ex_mem_is_mret)
    );

    // ========================================================================
    //  MEM STAGE — trap / MRET
    // ========================================================================
    // Every input is a register (EX/MEM) or the MEM address decode of the
    // registered address, so the trap decision is early: ex_kill gates the
    // EX commit points (TCM store, MAC/mul_div start, MAC_CLEAR, READ_LO/HI
    // sticky flag, CSR write) of the younger instruction in EX, and
    // mem_redirect wins the PC mux.
    // Load/store access fault: a bus access answered with an error
    // (dbus_error, below) traps here, in its response cycle. ex_mem_exc and
    // dbus_error never coincide: an instruction with an earlier exception
    // has its memory controls cleared.
    assign mem_trap            = ex_mem_exc | dbus_error;
    assign mem_trap_cause      = ex_mem_exc ? ex_mem_cause
                               : (ex_mem_mem_write ? 5'd7 : 5'd5);
    assign mem_trap_tval       = ex_mem_exc ? ex_mem_tval : ex_mem_alu_result;
    assign mem_mret            = ex_mem_is_mret;
    assign mem_redirect        = mem_trap | mem_mret;
    assign mem_redirect_target = mem_trap ? csr_mtvec : csr_mepc;
    assign ex_kill             = mem_redirect;

    // ========================================================================
    //  MEM STAGE — Address Decoder & Memory Subsystems
    // ========================================================================
    // Data-side memory map (Harvard; IMEM is not reachable from the data bus):
    //   0x8000_0000 - 0x8000_0FFF  TCM (4 KB): .rodata, .data, .bss, stack (EX fast path)
    //   0xC000_0100 / 0x104        mtime lo / hi           (core-local)
    //   0xC000_0108 / 0x10C        mtimecmp lo / hi        (core-local)
    //   0xC000_0FFC                simulation halt "tohost" (core-local, writes ignored)
    //   anything else              AXI4 data bus (periph_subsys): peripherals on
    //                              APB, holes -> DECERR; an error response or a
    //                              timeout is a load/store access fault
    // This decode is exact and runs on the registered EX/MEM address. The TCM
    // write enable uses the same exact range, decoded in EX from the AGU.
    assign is_tcm_access    = (ex_mem_alu_result[31:TCM_AW+2] == TCM_BASE[31:TCM_AW+2]);
    assign is_periph_region = (ex_mem_alu_result[31:12] == 20'hC0000);
    assign is_tohost        = is_periph_region & (ex_mem_alu_result[11:2] == 10'h3FF);
    assign is_timer         = is_periph_region & (ex_mem_alu_result[11:4] == 8'h10);

    assign mem_access     = ex_mem_mem_read | ex_mem_mem_write;
    assign mem_core_local = is_timer | is_tohost;
    assign mem_is_bus     = mem_access & ~is_tcm_access & ~mem_core_local;
    assign mem_stall      = mem_is_bus & ~bus_rsp_done;
    assign dbus_error     = mem_is_bus & bus_rsp_done & bus_rsp_err;

    // ---- AXI4 master: one access per bus instruction ----
    // The request is captured when the access first appears in MEM; the
    // response comes back registered (bus_rsp_done pulses once), so the
    // stall never depends on an AXI handshake combinationally.
    assign bus_wait_inj = 1'b0;
    assign timer_we     = ex_mem_mem_write & is_timer;

    dbus_axi_master #(.TIMEOUT(BUS_TIMEOUT)) u_dbus (
        .clk       (clk),
        .reset     (reset),
        .req       (mem_is_bus),
        .req_write (ex_mem_mem_write),
        .req_addr  (ex_mem_alu_result),
        .req_wdata (ex_mem_rs2_data),
        .req_strb  (ex_mem_mem_write ? ex_mem_strb : 4'b0000),
        .req_size  ({1'b0, ex_mem_funct3[1:0]}),
        .rsp_done  (bus_rsp_done),
        .rsp_err   (bus_rsp_err),
        .rsp_rdata (bus_rsp_rdata),
        .m_awvalid (axi_awvalid), .m_awready (axi_awready), .m_awaddr (axi_awaddr),
        .m_awlen   (axi_awlen),   .m_awsize  (axi_awsize),  .m_awburst (axi_awburst),
        .m_awprot  (axi_awprot),  .m_awid    (axi_awid),
        .m_wvalid  (axi_wvalid),  .m_wready  (axi_wready),  .m_wdata   (axi_wdata),
        .m_wstrb   (axi_wstrb),   .m_wlast   (axi_wlast),
        .m_bvalid  (axi_bvalid),  .m_bready  (axi_bready),  .m_bresp   (axi_bresp),
        .m_bid     (axi_bid),
        .m_arvalid (axi_arvalid), .m_arready (axi_arready), .m_araddr  (axi_araddr),
        .m_arlen   (axi_arlen),   .m_arsize  (axi_arsize),  .m_arburst (axi_arburst),
        .m_arprot  (axi_arprot),  .m_arid    (axi_arid),
        .m_rvalid  (axi_rvalid),  .m_rready  (axi_rready),  .m_rdata   (axi_rdata),
        .m_rresp   (axi_rresp),   .m_rlast   (axi_rlast),   .m_rid     (axi_rid)
    );

    periph_subsys #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (115_200),
        .SEG_EN    (SEG_EN)
    ) u_periph (
        .clk       (clk),
        .reset     (reset),
        .wait_inj  (bus_wait_inj),
        .s_awvalid (axi_awvalid), .s_awready (axi_awready), .s_awaddr (axi_awaddr),
        .s_awlen   (axi_awlen),   .s_awsize  (axi_awsize),  .s_awburst (axi_awburst),
        .s_awprot  (axi_awprot),  .s_awid    (axi_awid),
        .s_wvalid  (axi_wvalid),  .s_wready  (axi_wready),  .s_wdata   (axi_wdata),
        .s_wstrb   (axi_wstrb),   .s_wlast   (axi_wlast),
        .s_bvalid  (axi_bvalid),  .s_bready  (axi_bready),  .s_bresp   (axi_bresp),
        .s_bid     (axi_bid),
        .s_arvalid (axi_arvalid), .s_arready (axi_arready), .s_araddr  (axi_araddr),
        .s_arlen   (axi_arlen),   .s_arsize  (axi_arsize),  .s_arburst (axi_arburst),
        .s_arprot  (axi_arprot),  .s_arid    (axi_arid),
        .s_rvalid  (axi_rvalid),  .s_rready  (axi_rready),  .s_rdata   (axi_rdata),
        .s_rresp   (axi_rresp),   .s_rlast   (axi_rlast),   .s_rid     (axi_rid),
        .scl_drive_low (scl_drive_low),
        .sda_drive_low (sda_drive_low),
        .scl_pad_in    (scl_pad_in),
        .sda_pad_in    (sda_pad_in),
        .uart_tx_out   (uart_tx_out),
        .seg           (seg),
        .dp            (dp),
        .an            (an)
    );

    // ---- Open-drain I2C pads (driven by the legacy page's GPIO latch) ----
    od_pad u_scl_pad (.drive_low(scl_drive_low), .pad_in(scl_pad_in), .pad(i2c_scl));
    od_pad u_sda_pad (.drive_low(sda_drive_low), .pad_in(sda_pad_in), .pad(i2c_sda));

    // TCM: dual-port memory behind its wrapper
    tcm_wrap #(
        .MEM_TECH  (MEM_TECH),
        .WORDS     (TCM_WORDS),
        .INIT_FILE (TCM_INIT)
    ) u_tcm (
        .clk    (clk),
        .wea    (tcm_wea),
        .addra  (tcm_addra),
        .dina   (tcm_dina),
        .douta  (tcm_douta),
        .addrb  (tcm_addrb),
        .doutb  (tcm_doutb)
    );

    // ========================================================================
    //  Machine timer (0xC000_0100..0x10F) and external interrupt line
    // ========================================================================
    mtimer u_mtimer (
        .clk   (clk),
        .reset (reset),
        .we    (timer_we),
        .sel   (ex_mem_alu_result[3:2]),
        .wdata (ex_mem_rs2_data),
        .rdata (timer_rdata),
        .mtime (mtime),
        .mtip  (mtip)
    );

    // External interrupt: one level-sensitive input, tied off here until the
    // DMA engine drives it. 2-FF synchroniser (the source may be asynchronous).
    assign ext_irq = 1'b0;
    always_ff @(posedge clk) begin
        if (reset) ext_irq_sync <= 2'b00;
        else       ext_irq_sync <= {ext_irq_sync[0], ext_irq};
    end
    assign meip = ext_irq_sync[1];

    // ========================================================================
    //  MEM Read Data Mux — TCM / core-local timer / data bus
    // ========================================================================
    always_comb begin
        if (is_tcm_access)
            mem_read_data_muxed = tcm_douta;
        else if (is_timer)
            mem_read_data_muxed = timer_rdata;
        else
            mem_read_data_muxed = bus_rsp_rdata;     // 0 with an error response
    end

    // ---- Load width: byte/half select by addr[1:0] and sign/zero extend ----
    // Misaligned LH/LW are not trapped yet: addr[0] (LH) / addr[1:0] (LW) ignored.
    logic [7:0]  load_byte;
    logic [15:0] load_half;
    assign load_byte = mem_read_data_muxed[8*ex_mem_alu_result[1:0] +: 8];
    assign load_half = ex_mem_alu_result[1] ? mem_read_data_muxed[31:16]
                                            : mem_read_data_muxed[15:0];

    always_comb begin
        case (ex_mem_funct3)
            3'b000:  mem_load_data = {{24{load_byte[7]}},  load_byte};   // LB
            3'b001:  mem_load_data = {{16{load_half[15]}}, load_half};   // LH
            3'b100:  mem_load_data = {24'b0, load_byte};                 // LBU
            3'b101:  mem_load_data = {16'b0, load_half};                 // LHU
            default: mem_load_data = mem_read_data_muxed;                // LW
        endcase
    end

    // ---- Write-back select, done in MEM ----
    // One registered result, so the WB mux is not between the MEM/WB flops
    // and the forwarding muxes (Phase 5b limiter: mem_to_reg fanout).
    assign mem_result = ex_mem_mem_to_reg ? mem_load_data : ex_mem_alu_result;

    // ========================================================================
    //  MEM/WB Pipeline Register
    // ========================================================================

    mem_wb_reg u_mem_wb (
        .clk             (clk),
        .reset           (reset),
        .en              (~mem_stall),
        .reg_write_in    (ex_mem_reg_write & ~mem_trap), .reg_write_out (mem_wb_reg_write),  // a faulting load writes no rd
        .result_in       (mem_result),         .result_out    (mem_wb_result),
        .rd_addr_in      (ex_mem_rd_addr),     .rd_addr_out    (mem_wb_rd_addr),
        .valid_in        (ex_mem_valid & ~mem_trap), .valid_out (mem_wb_valid)  // a trapping instruction does not retire
    );

    // ========================================================================
    //  WB STAGE
    // ========================================================================

    assign wb_data = mem_wb_result;
    // MEM/WB is frozen during mem_stall: its instruction writes once, in
    // the last cycle (the value is on wb_data for forwarding meanwhile).
    assign rf_we   = mem_wb_reg_write & ~mem_stall;

    // ========================================================================
    //  DEBUG OUTPUTS
    // ========================================================================

    assign debug_pc = pc_current[7:0];
    assign debug_wb = wb_data[7:0];

endmodule
