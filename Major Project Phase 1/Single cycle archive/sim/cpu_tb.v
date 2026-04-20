// ============================================================================
// Testbench: cpu_tb
// File:      cpu_tb.v
//
// PURPOSE:
//   Simulates the single-cycle RV32I CPU.
//   - Generates a clock
//   - Applies reset for the first cycle
//   - Runs the demo program for several cycles
//   - Prints register values to verify correctness
//
// EXPECTED OUTPUT:
//   After the program runs:
//     x1 = 5   (ADDI x1, x0, 5)
//     x2 = 10  (ADDI x2, x0, 10)
//     x3 = 15  (ADD  x3, x1, x2)
//     x4 = 10  (SUB  x4, x3, x1)
//     x5 = 15  (LW   x5, 0(x0)  — loaded from memory after SW)
// ============================================================================

`timescale 1ns / 1ps

module cpu_tb;

    // ---- Clock and Reset ----
    reg clk;
    reg reset;

    // ---- Instantiate the CPU ----
    cpu_top uut (
        .clk   (clk),
        .reset (reset)
    );

    // ---- Clock Generation: 10ns period (100 MHz) ----
    initial begin
        clk = 0;
    end
    always #5 clk = ~clk;  // Toggle every 5ns → 10ns period

    // ---- Simulation ----
    initial begin
        // Optional: dump waveforms for GTKWave viewing
        $dumpfile("cpu_waves.vcd");
        $dumpvars(0, cpu_tb);

        // Apply reset
        reset = 1;
        #10;            // Hold reset for 1 clock cycle
        reset = 0;

        // Let the CPU run for 10 clock cycles (enough for 6 instructions + extra)
        #100;

        // ---- Print Results ----
        $display("============================================");
        $display("  Single-Cycle RV32I CPU — Simulation Results");
        $display("============================================");
        $display("  PC = %0d", uut.u_pc.pc_out);
        $display("");
        $display("  Register File:");
        $display("    x0  = %0d (hardwired zero)", uut.u_regfile.registers[0]);
        $display("    x1  = %0d (expected: 5)",    uut.u_regfile.registers[1]);
        $display("    x2  = %0d (expected: 10)",   uut.u_regfile.registers[2]);
        $display("    x3  = %0d (expected: 15)",   uut.u_regfile.registers[3]);
        $display("    x4  = %0d (expected: 10)",   uut.u_regfile.registers[4]);
        $display("    x5  = %0d (expected: 15)",   uut.u_regfile.registers[5]);
        $display("");
        $display("  Data Memory[0] = %0d (expected: 15)", uut.u_dmem.mem[0]);
        $display("============================================");

        // ---- Verify correctness ----
        if (uut.u_regfile.registers[1] == 32'd5 &&
            uut.u_regfile.registers[2] == 32'd10 &&
            uut.u_regfile.registers[3] == 32'd15 &&
            uut.u_regfile.registers[4] == 32'd10 &&
            uut.u_regfile.registers[5] == 32'd15 &&
            uut.u_dmem.mem[0] == 32'd15) begin
            $display("  >>> ALL TESTS PASSED! <<<");
        end else begin
            $display("  >>> SOME TESTS FAILED — check values above <<<");
        end

        $display("============================================");
        $finish;
    end

    // ---- Cycle-by-cycle trace (optional, helps debugging) ----
    always @(posedge clk) begin
        if (!reset) begin
            $display("[Cycle] PC=%0d  Instr=%h  ALU_result=%0d  RegWrite=%b  MemWrite=%b",
                     uut.u_pc.pc_out,
                     uut.u_imem.instruction,
                     uut.u_alu.alu_result,
                     uut.u_control.reg_write,
                     uut.u_control.mem_write);
        end
    end

endmodule
