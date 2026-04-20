// ============================================================================
// Testbench: cpu_pipeline_tb
// File:      cpu_pipeline_tb.sv
//
// PURPOSE:
//   Simulates the 5-stage pipelined RV32I CPU (cpu_pipeline_top).
//   Runs the comprehensive test program and verifies:
//     - Data forwarding (EX/MEM, MEM/WB paths)
//     - Load-use hazard stalling
//     - Branch taken (BEQ, BNE) with 2-cycle flush
//     - Branch not taken (BEQ)
//
// TARGET: Xilinx Vivado behavioral simulation
//
// EXPECTED FINAL STATE:
//     x1=5, x2=10, x3=15, x4=10, x5=15, x6=16
//     x7=0 (flushed), x8=0 (flushed), x9=42, x10=7, x11=0 (flushed)
//     MEM[0] = 15
// ============================================================================

`timescale 1ns / 1ps

module cpu_pipeline_tb;

    // ---- Clock and Reset ----
    logic clk;
    logic reset;

    // ---- Instantiate the Pipelined CPU ----
    cpu_pipeline_top uut (
        .clk   (clk),
        .reset (reset)
    );

    // ---- Clock Generation: 10ns period (100 MHz) ----
    initial begin
        clk = 1'b0;
    end
    always #5 clk = ~clk;

    // ---- Test result tracking ----
    integer pass_count;
    integer fail_count;

    // ---- Task: Check a register value ----
    task check_reg(input int reg_num, input int expected, input string desc);
        if (uut.u_regfile.registers[reg_num] === expected) begin
            $display("  [PASS] x%0d = %0d  (%s)", reg_num, expected, desc);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] x%0d = %0d, expected %0d  (%s)",
                     reg_num, uut.u_regfile.registers[reg_num], expected, desc);
            fail_count = fail_count + 1;
        end
    endtask

    // ---- Task: Check a memory value ----
    task check_mem(input int addr_word, input int expected, input string desc);
        if (uut.u_dmem.mem[addr_word] === expected) begin
            $display("  [PASS] MEM[%0d] = %0d  (%s)", addr_word, expected, desc);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] MEM[%0d] = %0d, expected %0d  (%s)",
                     addr_word, uut.u_dmem.mem[addr_word], expected, desc);
            fail_count = fail_count + 1;
        end
    endtask

    // ---- Main Simulation ----
    initial begin
        // Waveform dump for inspection
        $dumpfile("cpu_pipeline_waves.vcd");
        $dumpvars(0, cpu_pipeline_tb);

        // Initialize
        pass_count = 0;
        fail_count = 0;

        // Apply reset for 1 clock cycle
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        // Run for 35 clock cycles
        // (enough for 16 instructions + stalls + branch flushes + pipeline drain)
        repeat (35) @(posedge clk);

        // ================================================================
        // Verification
        // ================================================================
        $display("");
        $display("============================================================");
        $display("  5-Stage Pipelined RV32I CPU — Simulation Results");
        $display("============================================================");
        $display("  PC = %0d", uut.u_pc.pc_out);
        $display("");

        // ---- Register checks ----
        $display("  --- Register File ---");
        check_reg( 0,  0, "hardwired zero");
        check_reg( 1,  5, "ADDI x1, x0, 5");
        check_reg( 2, 10, "ADDI x2, x0, 10");
        check_reg( 3, 15, "ADD  x3, x1, x2 (forwarding)");
        check_reg( 4, 10, "SUB  x4, x3, x1 (forwarding)");
        check_reg( 5, 15, "LW   x5, 0(x0)");
        check_reg( 6, 16, "ADDI x6, x5, 1 (load-use stall)");
        check_reg( 7,  0, "FLUSHED by BEQ taken");
        check_reg( 8,  0, "FLUSHED by BEQ taken");
        check_reg( 9, 42, "ADDI x9, x0, 42 (BEQ target)");
        check_reg(10,  7, "ADDI x10, x0, 7 (BEQ not-taken)");
        check_reg(11,  0, "FLUSHED by BNE taken");

        // ---- Memory checks ----
        $display("");
        $display("  --- Data Memory ---");
        check_mem(0, 15, "SW x3, 0(x0)");

        // ---- Summary ----
        $display("");
        $display("============================================================");
        if (fail_count == 0) begin
            $display("  >>> ALL %0d TESTS PASSED! <<<", pass_count);
        end else begin
            $display("  >>> %0d PASSED, %0d FAILED <<<", pass_count, fail_count);
        end
        $display("============================================================");

        $finish;
    end

    // ---- Cycle-by-cycle pipeline trace (for debugging) ----
    always @(posedge clk) begin
        if (!reset) begin
            $display("[Cycle %0t] PC=%0d | IF_instr=%h | stall=%b | branch_taken=%b | fwd_a=%b fwd_b=%b",
                     $time,
                     uut.u_pc.pc_out,
                     uut.u_imem.instruction,
                     uut.u_hazard.stall,
                     uut.branch_taken,
                     uut.forward_a_sel,
                     uut.forward_b_sel);
        end
    end


endmodule
