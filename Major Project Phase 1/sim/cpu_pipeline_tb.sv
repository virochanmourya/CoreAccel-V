// ============================================================================
// Testbench: cpu_pipeline_tb (32-Bit MAC Integration Verification)
// File:      cpu_pipeline_tb.sv
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

    // ---- Main Simulation ----
    initial begin
        $dumpfile("cpu_pipeline_waves.vcd");
        $dumpvars(0, cpu_pipeline_tb);

        pass_count = 0;
        fail_count = 0;

        // Apply reset
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        // Run for 30 clock cycles (plenty of time for MAC stalls + pipeline drain)
        repeat (30) @(posedge clk);

        // ================================================================
        // Verification
        // ================================================================
        $display("");
        $display("============================================================");
        $display("  32-Bit CoreAccel-V DSP Integration Results");
        $display("============================================================");

        check_reg( 1,  5, "ADDI x1, x0, 5");
        check_reg( 2, 10, "ADDI x2, x0, 10");
        check_reg( 3, 50, "MAC_READ x3 (5*10)");
        check_reg( 4, 75, "MAC_READ x4 (50 + 5*5)");
        check_reg( 5,  0, "MAC_READ x5 (After MAC_CLEAR)");

        $display("============================================================");
        if (fail_count == 0) begin
            $display("  >>> ALL %0d TESTS PASSED! PIPELINE IS PERFECT! <<<", pass_count);
        end else begin
            $display("  >>> %0d PASSED, %0d FAILED <<<", pass_count, fail_count);
        end
        $display("============================================================");

        $finish;
    end

    // ---- Cycle-by-cycle pipeline trace ----
    always @(posedge clk) begin
        if (!reset) begin
            $display("[Cycle %0t] PC=%0d | IF_instr=%h | stall=%b | mac_busy=%b",
                     $time,
                     uut.u_pc.pc_out,
                     uut.u_imem.instruction,
                     uut.u_hazard.stall,
                     uut.mac_busy_ex); // Tracing the MAC stall wire specifically
        end
    end

endmodule