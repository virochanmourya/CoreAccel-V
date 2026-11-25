// ============================================================================
// core_sva — concurrent assertions on cpu_pipeline_top internals.
// Bound into the DUT (sim only); every failure calls tb_top.sva_fail(),
// which forces the test result to FAIL.
// ============================================================================
`timescale 1ns/1ps
module core_sva #(
    parameter int TCM_AW = 10                 // TCM word-address bits
)(
    input logic        clk,
    input logic        reset,
    // TCM port A (CPU data side, driven from EX)
    input logic [3:0]  tcm_wea,
    input logic [TCM_AW-1:0] tcm_addra,
    input logic [31:0] tcm_dina,
    // The same store one cycle later, in MEM
    input logic        ex_mem_mem_write,
    input logic [31:0] ex_mem_alu_result,
    input logic [31:0] ex_mem_rs2_data,
    // EX-stage AGU vs ALU
    input logic        id_ex_mem_read,
    input logic        id_ex_mem_write,
    input logic [31:0] ex_eff_addr,
    input logic [31:0] alu_result,
    // Traps: kill of the EX instruction's commit points, redirect targets
    input logic        ex_kill,
    input logic        mac_start_pulse,
    input logic        muldiv_start,
    input logic        mac_clear_commit,
    input logic        mac_rd64_strobe,
    input logic        csr_commit,
    input logic        mem_trap,
    input logic        mem_mret,
    input logic        ex_mem_valid,
    input logic [31:0] pc_current,
    input logic [31:0] csr_mtvec,
    input logic [31:0] csr_mepc,
    // Bubbles (valid = 0): IF/ID and ID/EX data registers are not flushed,
    // so a bubble must be harmless through its controls alone.
    input logic        if_id_valid,
    input logic        id_ctrl_any,     // OR of every ID control output
    input logic        id_exc,
    input logic        id_ex_valid,
    input logic        id_ex_ctrl_any,  // OR of every ID/EX control bit
    // Forwarding: registered selects vs the combinational definition
    input logic [1:0]  forward_a_sel,
    input logic [1:0]  forward_b_sel,
    input logic [4:0]  id_ex_rs1_addr,
    input logic [4:0]  id_ex_rs2_addr,
    input logic [4:0]  ex_mem_rd_addr,
    input logic        ex_mem_reg_write,
    input logic [4:0]  mem_wb_rd_addr,
    input logic        mem_wb_reg_write,
    // MAC: the accumulator is written in the last busy cycle (split add)
    input logic        mac_busy_ex,
    input logic        mac_to_reg_ex,
    input logic        ex_hold,
    // Global MEM stall: frozen pipeline, no commits
    input logic        mem_stall,
    input logic        rf_we,
    input logic [31:0] id_ex_pc,
    input logic [31:0] ex_mem_pc,
    input logic        mem_wb_valid,
    input logic [31:0] mem_wb_result
);
    logic mem_tcm_store;
    // Same exact range as the EX-stage TCM write enable.
    assign mem_tcm_store = ex_mem_mem_write &
                           (ex_mem_alu_result[31:TCM_AW+2] == 32'h8000_0000 >> (TCM_AW + 2));

    // ---- One write per store -------------------------------------------
    // A store spends exactly one cycle in MEM. So "every TCM write is followed
    // by its store in MEM" plus "every TCM store in MEM was written on the
    // previous cycle, with the same address and data" gives a 1:1 mapping:
    // a store held in EX that wrote twice would break the first property.
    a_tcm_write_then_mem: assert property (
        @(posedge clk) disable iff (reset)
        (|tcm_wea) |=> mem_tcm_store
    ) else begin
        $display("SVA FAIL a_tcm_write_then_mem t=%0t (no TCM store reached MEM after a write)", $time);
        tb_top.sva_fail();
    end

    a_mem_store_written_once: assert property (
        @(posedge clk) disable iff (reset)
        // === : this checks the address/data PATH is the same, so an X value
        // stored by the program (e.g. from an undriven input) is not a violation.
        mem_tcm_store |-> ($past(|tcm_wea)
                           && $past(tcm_addra) === ex_mem_alu_result[TCM_AW+1:2]
                           && $past(tcm_dina)  === ex_mem_rs2_data)
    ) else begin
        $display("SVA FAIL a_mem_store_written_once t=%0t addr=0x%08h", $time,
                 $sampled(ex_mem_alu_result));
        tb_top.sva_fail();
    end

    // ---- AGU == ALU for every load/store ------------------------------------
    // The TCM port and its range check use the dedicated AGU adder; MEM-stage
    // decode and the EX/MEM address use the ALU result. They must agree.
    a_agu_matches_alu: assert property (
        @(posedge clk) disable iff (reset)
        (id_ex_mem_read || id_ex_mem_write) |-> (ex_eff_addr === alu_result)
    ) else begin
        $display("SVA FAIL a_agu_matches_alu t=%0t agu=0x%08h alu=0x%08h", $time,
                 $sampled(ex_eff_addr), $sampled(alu_result));
        tb_top.sva_fail();
    end

    // ---- Precise traps ------------------------------------------------------
    // The instruction in EX is younger than a trap/MRET in MEM: none of its
    // commit points may fire in that cycle.
    a_kill_blocks_ex_commits: assert property (
        @(posedge clk) disable iff (reset)
        ex_kill |-> (tcm_wea == 4'b0 && !mac_start_pulse && !muldiv_start &&
                     !mac_clear_commit && !mac_rd64_strobe && !csr_commit)
    ) else begin
        $display("SVA FAIL a_kill_blocks_ex_commits t=%0t", $time);
        tb_top.sva_fail();
    end

    // Only a real instruction traps (never a bubble).
    a_trap_is_valid: assert property (
        @(posedge clk) disable iff (reset)
        mem_trap |-> ex_mem_valid
    ) else begin
        $display("SVA FAIL a_trap_is_valid t=%0t", $time);
        tb_top.sva_fail();
    end

    // Trap entry goes to mtvec, MRET to mepc, on the next cycle.
    a_trap_to_mtvec: assert property (
        @(posedge clk) disable iff (reset)
        mem_trap |=> (pc_current == $past(csr_mtvec))
    ) else begin
        $display("SVA FAIL a_trap_to_mtvec t=%0t pc=0x%08h", $time, $sampled(pc_current));
        tb_top.sva_fail();
    end
    a_mret_to_mepc: assert property (
        @(posedge clk) disable iff (reset)
        (mem_mret && !mem_trap) |=> (pc_current == $past(csr_mepc))
    ) else begin
        $display("SVA FAIL a_mret_to_mepc t=%0t pc=0x%08h", $time, $sampled(pc_current));
        tb_top.sva_fail();
    end

    // Forwarding selects: the registered (one cycle early) selects must equal
    // the combinational EX-stage definition whenever the EX instruction is
    // valid and not killed by a trap/MRET in MEM.
    // Everything is passed as an argument: in an assertion only the
    // arguments of a function call are sampled, not signals it reads itself.
    function automatic logic [1:0] fwd_ref(input logic [4:0] rs,
                                           input logic ex_wr, input logic [4:0] ex_rd,
                                           input logic wb_wr, input logic [4:0] wb_rd);
        if (ex_wr && (ex_rd != 5'd0) && (ex_rd == rs))
            return 2'b10;
        else if (wb_wr && (wb_rd != 5'd0) && (wb_rd == rs))
            return 2'b01;
        return 2'b00;
    endfunction
    logic [1:0] ref_a, ref_b;
    assign ref_a = fwd_ref(id_ex_rs1_addr, ex_mem_reg_write, ex_mem_rd_addr, mem_wb_reg_write, mem_wb_rd_addr);
    assign ref_b = fwd_ref(id_ex_rs2_addr, ex_mem_reg_write, ex_mem_rd_addr, mem_wb_reg_write, mem_wb_rd_addr);
    a_fwd_sel_matches: assert property (
        @(posedge clk) disable iff (reset)
        (id_ex_valid && !ex_kill) |->
            (forward_a_sel == ref_a && forward_b_sel == ref_b)
    ) else begin
        $display("SVA FAIL a_fwd_sel_matches t=%0t a=%b/%b b=%b/%b", $time,
                 $sampled(forward_a_sel), $sampled(ref_a),
                 $sampled(forward_b_sel), $sampled(ref_b));
        tb_top.sva_fail();
    end

    // The MAC accumulate is split over its last two busy cycles, so nothing
    // may read or clear the accumulator while the unit is busy.
    a_mac_acc_idle_when_used: assert property (
        @(posedge clk) disable iff (reset)
        mac_busy_ex |-> !(mac_clear_commit || mac_rd64_strobe || (mac_to_reg_ex && !ex_hold))
    ) else begin
        $display("SVA FAIL a_mac_acc_idle_when_used t=%0t", $time);
        tb_top.sva_fail();
    end

    // ---- Global MEM stall -----------------------------------------------
    // While MEM waits for the bus, nothing commits and nothing traps: no
    // TCM/CSR/register write, no multi-cycle start, no MAC accumulator
    // update from EX. (A stalled access traps, if at all, when it ends.)
    a_stall_no_commit: assert property (
        @(posedge clk) disable iff (reset)
        mem_stall |-> (!mem_trap && !mem_mret && tcm_wea == 4'b0 && !csr_commit &&
                       !mac_start_pulse && !muldiv_start && !mac_clear_commit &&
                       !mac_rd64_strobe && !rf_we)
    ) else begin
        $display("SVA FAIL a_stall_no_commit t=%0t", $time);
        tb_top.sva_fail();
    end
    // ... and every instruction stays where it is (ID/EX, EX/MEM, MEM/WB
    // and the forwarding selects hold).
    a_stall_frozen: assert property (
        @(posedge clk) disable iff (reset)
        mem_stall |=> ($stable(id_ex_pc) && $stable(id_ex_valid) &&
                       $stable(ex_mem_pc) && $stable(ex_mem_valid) &&
                       $stable(ex_mem_alu_result) && $stable(ex_mem_mem_write) &&
                       $stable(mem_wb_valid) && $stable(mem_wb_result) &&
                       $stable(forward_a_sel) && $stable(forward_b_sel))
    ) else begin
        $display("SVA FAIL a_stall_frozen t=%0t", $time);
        tb_top.sva_fail();
    end

    // A bubble in ID decodes to all-zero controls and raises no exception,
    // whatever stale instruction bits IF/ID holds.
    a_id_bubble_quiet: assert property (
        @(posedge clk) disable iff (reset)
        !if_id_valid |-> (!id_ctrl_any && !id_exc)
    ) else begin
        $display("SVA FAIL a_id_bubble_quiet t=%0t", $time);
        tb_top.sva_fail();
    end
    // A bubble in EX has every control bit clear.
    a_ex_bubble_quiet: assert property (
        @(posedge clk) disable iff (reset)
        !id_ex_valid |-> !id_ex_ctrl_any
    ) else begin
        $display("SVA FAIL a_ex_bubble_quiet t=%0t", $time);
        tb_top.sva_fail();
    end
endmodule

bind cpu_pipeline_top core_sva #(.TCM_AW(TCM_AW)) u_core_sva (
    .clk               (clk_core),
    .reset             (rst_sys),
    .tcm_wea           (tcm_wea),
    .tcm_addra         (tcm_addra),
    .tcm_dina          (tcm_dina),
    .ex_mem_mem_write  (ex_mem_mem_write),
    .ex_mem_alu_result (ex_mem_alu_result),
    .ex_mem_rs2_data   (ex_mem_rs2_data),
    .id_ex_mem_read    (id_ex_mem_read),
    .id_ex_mem_write   (id_ex_mem_write),
    .ex_eff_addr       (ex_eff_addr),
    .alu_result        (alu_result),
    .ex_kill           (ex_kill),
    .mac_start_pulse   (mac_start_pulse),
    .muldiv_start      (muldiv_start),
    .mac_clear_commit  (mac_clear_commit),
    .mac_rd64_strobe   (mac_rd64_strobe),
    .csr_commit        (csr_commit),
    .mem_trap          (mem_trap),
    .mem_mret          (mem_mret),
    .ex_mem_valid      (ex_mem_valid),
    .pc_current        (pc_current),
    .csr_mtvec         (csr_mtvec),
    .csr_mepc          (csr_mepc),
    .if_id_valid       (if_id_valid),
    .id_ctrl_any       (id_reg_write | id_mem_to_reg | id_mem_read | id_mem_write |
                        id_branch | id_jump | id_pc_to_reg | id_is_mac | id_is_mac_clear |
                        id_mac_to_reg | id_is_mac_rdshift | id_is_muldiv | id_is_csr |
                        id_csr_we | id_is_ecall | id_is_ebreak | id_is_mret |
                        id_rs1_valid | id_rs2_valid),
    .id_exc            (id_exc),
    .id_ex_valid       (id_ex_valid),
    .id_ex_ctrl_any    (id_ex_reg_write | id_ex_mem_to_reg | id_ex_mem_read | id_ex_mem_write |
                        id_ex_branch | id_ex_jump | id_ex_pc_to_reg | is_mac_ex | is_mac_clear_ex |
                        mac_to_reg_ex | is_mac_rdshift_ex | is_muldiv_ex | is_csr_ex |
                        csr_we_ex | id_ex_exc | id_ex_is_mret),
    .forward_a_sel     (forward_a_sel),
    .forward_b_sel     (forward_b_sel),
    .id_ex_rs1_addr    (id_ex_rs1_addr),
    .id_ex_rs2_addr    (id_ex_rs2_addr),
    .ex_mem_rd_addr    (ex_mem_rd_addr),
    .ex_mem_reg_write  (ex_mem_reg_write),
    .mem_wb_rd_addr    (mem_wb_rd_addr),
    .mem_wb_reg_write  (mem_wb_reg_write),
    .mac_busy_ex       (mac_busy_ex),
    .mac_to_reg_ex     (mac_to_reg_ex),
    .ex_hold           (ex_hold),
    .mem_stall         (mem_stall),
    .rf_we             (rf_we),
    .id_ex_pc          (id_ex_pc),
    .ex_mem_pc         (ex_mem_pc),
    .mem_wb_valid      (mem_wb_valid),
    .mem_wb_result     (mem_wb_result)
);
