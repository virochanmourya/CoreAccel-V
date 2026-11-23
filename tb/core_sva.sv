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
    input logic [31:0] ex_mem_rs2_data
);
    logic mem_tcm_store;
    // Same region rule as the EX-stage TCM write enable (addr[31:30] == 2'b10).
    assign mem_tcm_store = ex_mem_mem_write & (ex_mem_alu_result[31:30] == 2'b10);

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
endmodule

bind cpu_pipeline_top core_sva u_core_sva (
    .clk               (clk),
    .reset             (reset),
    .tcm_wea           (tcm_wea),
    .tcm_addra         (tcm_addra),
    .tcm_dina          (tcm_dina),
    .ex_mem_mem_write  (ex_mem_mem_write),
    .ex_mem_alu_result (ex_mem_alu_result),
    .ex_mem_rs2_data   (ex_mem_rs2_data)
);
