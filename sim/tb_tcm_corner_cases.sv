// ============================================================================
// Testbench: tb_tcm_corner_cases (SystemVerilog)
// File:      tb_tcm_corner_cases.sv
//
// Tests 6 corner cases including a BRAM latency stress test that
// would FAIL if the TCM Port A read address came from MEM stage
// instead of EX stage.
// ============================================================================

`timescale 1ns / 1ps

module tb_tcm_corner_cases;

    logic       clk, reset;
    logic [7:0] debug_pc, debug_wb;

    cpu_pipeline_top uut (
        .clk      (clk),
        .reset    (reset),
        .debug_pc (debug_pc),
        .debug_wb (debug_wb)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_count, fail_count;

    task automatic check_reg(input int rn, input logic [31:0] exp, input string d);
        if (uut.u_regfile.registers[rn] === exp) begin
            $display("  [PASS] x%0d = 0x%08h  (%s)", rn, exp, d);
            pass_count++;
        end else begin
            $display("  [FAIL] x%0d = 0x%08h, expected 0x%08h  (%s)",
                     rn, uut.u_regfile.registers[rn], exp, d);
            fail_count++;
        end
    endtask

    task automatic check_tcm(input int wa, input logic [31:0] exp, input string d);
        if (uut.u_tcm.mem[wa] === exp) begin
            $display("  [PASS] TCM[%0d] = 0x%08h  (%s)", wa, exp, d);
            pass_count++;
        end else begin
            $display("  [FAIL] TCM[%0d] = 0x%08h, expected 0x%08h  (%s)",
                     wa, uut.u_tcm.mem[wa], exp, d);
            fail_count++;
        end
    endtask

    initial begin
        $dumpfile("tcm_corner_cases.vcd");
        $dumpvars(0, tb_tcm_corner_cases);

        pass_count = 0;
        fail_count = 0;

        reset = 1'b1;
        repeat (2) @(posedge clk);
        reset = 1'b0;

        repeat (180) @(posedge clk);

        $display("");
        $display("============================================================");
        $display("  CoreAccel-V TCM Corner Case Verification (SystemVerilog)");
        $display("============================================================");

        $display("  --- TEST 1: CPU Write + TCM Read-back ---");
        check_reg( 2, 32'h80000000, "LUI: TCM base address");
        check_reg( 1, 32'h00000007, "x1 = 7 (weight)");
        check_tcm( 0, 32'h00000007, "TCM[0] = 7 via SW Port A");
        check_tcm( 1, 32'h0000000D, "TCM[1] = 13 via SW Port A");
        check_reg( 3, 32'h00000007, "LW x3 = TCM[0] via Port A = 7");

        $display("  --- TEST 2: MAC via TCM Port B (6*7=42) ---");
        check_reg( 4, 32'h00000006, "x4 = 6 (data)");
        check_reg( 6, 32'h0000002A, "MAC_READ_LO: 6*7 = 42");

        $display("  --- TEST 3: BRAM LATENCY STRESS (critical!) ---");
        $display("       ADDI x20=99 POISONS ALU result before LW from TCM.");
        $display("       If BRAM reads from MEM-stage addr, it reads word 24 (garbage).");
        $display("       Only EX-stage addressing produces correct result.");
        check_reg(20, 32'h00000063, "x20 = 99 (poison ALU value)");
        check_reg(15, 32'h0000000D, "LW x15 = TCM[1] = 13 (BRAM latency OK)");

        $display("  --- TEST 4: Cross-Port RAW Hazard ---");
        check_reg( 7, 32'h0000000B, "x7 = 11 (new weight)");
        check_tcm( 2, 32'h0000000B, "TCM[2] = 11 via SW");
        check_reg(10, 32'h00000021, "MAC_READ_LO: 3*11 = 33");

        $display("  --- TEST 5: MAC Stall Survival ---");
        check_reg(11, 32'h00000037, "ADDI survived stall (55)");
        check_reg(12, 32'h0000002A, "MAC_READ_LO: 6*7 = 42");

        $display("  --- TEST 6: Multi-Accumulate ---");
        check_reg(13, 32'h0000004B, "MAC_READ_LO: (6*7)+(3*11) = 75");

        $display("");
        $display("============================================================");
        if (fail_count == 0)
            $display("  >>> ALL %0d TESTS PASSED! <<<", pass_count + fail_count);
        else
            $display("  >>> %0d PASSED, %0d FAILED <<<", pass_count, fail_count);
        $display("============================================================");

        $finish;
    end

    always @(posedge clk) begin
        if (!reset) begin
            $display("[Cycle %0t] PC=0x%02h | instr=%h | stall=%b | mac_busy=%b | tcm_wea=%b tcm_addra=%0d",
                     $time, uut.u_pc.pc_out, uut.u_imem.instruction,
                     uut.u_hazard.stall, uut.mac_busy_ex,
                     uut.tcm_wea, uut.tcm_addra);
        end
    end

endmodule
