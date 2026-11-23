// ============================================================================
// core_sva — concurrent assertions on cpu_pipeline_top internals.
// Bound into the DUT (sim only); every failure calls tb_top.sva_fail(),
// which forces the test result to FAIL.
// ============================================================================
`timescale 1ns/1ps
module core_sva (
    input logic        clk,
    input logic        reset,
    // TCM port A (CPU data side, driven from EX)
    input logic [3:0]  tcm_wea,
    input logic [9:0]  tcm_addra,
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
    input logic [31:0] csr_mepc
);
    logic mem_tcm_store;
    // Same exact range as the EX-stage TCM write enable (0x8000_0000-0x8000_0FFF).
    assign mem_tcm_store = ex_mem_mem_write & (ex_mem_alu_result[31:12] == 20'h80000);

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
                           && $past(tcm_addra) === ex_mem_alu_result[11:2]
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
endmodule

bind cpu_pipeline_top core_sva u_core_sva (
    .clk               (clk),
    .reset             (reset),
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
    .csr_mepc          (csr_mepc)
);
