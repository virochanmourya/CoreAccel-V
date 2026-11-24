// ============================================================================
// tb_top — CoreAccel-V directed-test harness (Vivado xsim)
//
// Plusargs (all paths absolute):
//   +IMEM=<hex>        IMEM image (required)
//   +TCM=<hex>         TCM image (optional)
//   +EXPECTED=<hex>    expected signature, one word per line
//   +SIG_BEGIN=<hex>   signature base address (in TCM)
//   +SIG_WORDS=<n>     number of signature words to compare
//   +SIGOUT=<file>     dump the observed signature here
//   +TIMEOUT=<cycles>  default 200000
//   +TEST=<name>       label used in the RESULT line
//   +TRACE=<file>      register write-back log (commit_monitor)
//   +DBUS_ERRORS=<n>   expected number of unmapped data accesses (default 0)
//   +ILLEGAL_ERRORS=<n>    expected illegal-instruction traps (mcause 2, default 0)
//   +MISALIGNED_ERRORS=<n> expected misaligned load/store traps (mcause 4/6, default 0)
//   +OTHER_TRAPS=<n>       expected traps with any other cause (default 0)
//   +HOLD_EX_STORES=<n> hold every TCM store in EX for n cycles (forces the EX
//                     hold) to check that a held store still writes exactly once
//
// Simulation control word at HALT_ADDR (the RTL ignores writes there):
//   store 1 -> raise the external interrupt line, store 2 -> drop it,
//   any other value -> halt and check (TEST_END stores 0).
// Output ends with exactly one line:
//   RESULT PASS|FAIL|TIMEOUT test=<name> cycles=<n> ...
// ============================================================================
`timescale 1ns/1ps
`include "tb_probes.svh"

module tb_top;

    localparam logic [31:0] HALT_ADDR  = 32'hC000_0FFC;
    localparam logic [31:0] TCM_BASE   = 32'h8000_0000;
    localparam int          TCM_WORDS  = 1024;
    localparam int          IMEM_WORDS = 2048;
    localparam int          MAX_SIG    = 1024;
    localparam int          DRAIN      = 8;    // cycles after halt before checking

    // ---------------------------------------------------------------- DUT
    logic       clk   = 1'b0;
    logic       reset = 1'b1;
    logic [7:0] debug_pc, debug_wb;
    logic       uart_tx_out;
    logic [6:0] seg;
    logic       dp;
    logic [3:0] an;
    wire        i2c_scl, i2c_sda;

    pullup (i2c_scl);
    pullup (i2c_sda);

    always #5 clk = ~clk;   // 100 MHz

    cpu_pipeline_top dut (
        .clk         (clk),
        .reset       (reset),
        .debug_pc    (debug_pc),
        .debug_wb    (debug_wb),
        .i2c_scl     (i2c_scl),
        .i2c_sda     (i2c_sda),
        .uart_tx_out (uart_tx_out),
        .seg         (seg),
        .dp          (dp),
        .an          (an)
    );

    commit_monitor u_commit (
        .clk     (clk),
        .reset   (reset),
        .wb_we   (`PRB_WB_WE),
        .wb_rd   (`PRB_WB_RD),
        .wb_data (`PRB_WB_DATA)
    );

    uart_monitor u_uart (.clk(clk), .rx(uart_tx_out));

    // I2C target at 0x48 (ADS1115 address), open-drain on the pulled-up bus
    i2c_target_model #(.ADDR(7'h48)) u_i2c_target (.scl(i2c_scl), .sda(i2c_sda));

    // ---------------------------------------------------------------- config
    string       test_name, imem_file, tcm_file, exp_file, sig_out;
    logic [31:0] sig_begin;
    int          sig_words;
    longint      timeout;
    longint      cycles = 0;
    bit          halted = 1'b0;
    int          sva_errors = 0;   // bumped via sva_fail() by bound assertion modules
    int          dbus_errors = 0;  // unmapped data accesses observed
    int          dbus_expected;    // ... and how many the test declared
    int          bus_faults = 0;   // load/store access-fault traps (cause 5/7): one per dbus error
    int          illegal_errors = 0, illegal_expected;
    int          misal_errors   = 0, misal_expected;
    int          other_traps    = 0, other_expected;

    // External interrupt line driven by the test through the control word
    logic ext_irq_tb = 1'b0;
    initial force `PRB_EXT_IRQ = ext_irq_tb;

    function automatic void sva_fail();
        sva_errors++;
    endfunction
    logic [31:0] expected [0:MAX_SIG-1];

    initial begin
        if (!$value$plusargs("TEST=%s", test_name))      test_name = "unnamed";
        if (!$value$plusargs("IMEM=%s", imem_file)) begin
            $display("RESULT FAIL test=%s reason=no_IMEM_plusarg", test_name);
            $finish;
        end
        if (!$value$plusargs("TCM=%s", tcm_file))        tcm_file  = "";
        if (!$value$plusargs("EXPECTED=%s", exp_file))   exp_file  = "";
        if (!$value$plusargs("SIG_BEGIN=%h", sig_begin)) sig_begin = '0;
        if (!$value$plusargs("SIG_WORDS=%d", sig_words)) sig_words = 0;
        if (!$value$plusargs("SIGOUT=%s", sig_out))      sig_out   = "";
        if (!$value$plusargs("TIMEOUT=%d", timeout))     timeout   = 200_000;
        if (!$value$plusargs("DBUS_ERRORS=%d", dbus_expected)) dbus_expected = 0;
        if (!$value$plusargs("ILLEGAL_ERRORS=%d", illegal_expected)) illegal_expected = 0;
        if (!$value$plusargs("MISALIGNED_ERRORS=%d", misal_expected)) misal_expected = 0;
        if (!$value$plusargs("OTHER_TRAPS=%d", other_expected)) other_expected = 0;
        if (sig_words > MAX_SIG) begin
            $display("RESULT FAIL test=%s reason=SIG_WORDS_too_large", test_name);
            $finish;
        end

        // Load memories after the RTL's own initial blocks (t=0), during reset.
        #1;
        for (int i = 0; i < IMEM_WORDS; i++) `PRB_IMEM_ARR[i] = 32'h0000_0013;  // NOP
        for (int i = 0; i < TCM_WORDS;  i++) `PRB_TCM_ARR[i]  = 32'h0000_0000;
        $readmemh(imem_file, `PRB_IMEM_ARR);
        if (tcm_file != "") $readmemh(tcm_file, `PRB_TCM_ARR);
        if (sig_words > 0)  $readmemh(exp_file, expected, 0, sig_words - 1);

        repeat (5) @(posedge clk);
        reset <= 1'b0;
    end

    // ---------------------------------------------------------------- EX-hold hook
    // Emulates a future multi-cycle EX unit or DMA arbiter: whenever a TCM store
    // reaches EX, force the EX hold for hold_cycles cycles, then let it go.
    int hold_cycles = 0;
    int holds_done  = 0;
    initial begin
        if ($value$plusargs("HOLD_EX_STORES=%d", hold_cycles) && hold_cycles > 0) begin
            forever begin
                @(posedge clk); #1;
                if (!reset && !halted && `PRB_EX_TCM_STORE) begin
                    force `PRB_EX_HOLD = 1'b1;
                    repeat (hold_cycles) @(posedge clk);
                    #1 force `PRB_EX_HOLD = `PRB_EX_HOLD_RTL;   // back to the RTL driver
                    holds_done++;
                    @(posedge clk);      // let this store leave EX before re-arming
                end
            end
        end
    end

    // ---------------------------------------------------------------- halt / timeout
    always @(posedge clk) begin
        if (!reset && !halted) begin
            cycles <= cycles + 1;
            if (`PRB_DBUS_ERR === 1'b1) begin
                dbus_errors++;
                $display("TB: data-bus error (unmapped) addr=0x%08h cycle=%0d", `PRB_DBUS_ADDR, cycles);
            end
            if (`PRB_TRAP === 1'b1) begin
                $display("TB: trap mcause=0x%08h mepc=0x%08h mtval=0x%08h cycle=%0d",
                         {`PRB_TRAP_CAUSE[4], 27'b0, `PRB_TRAP_CAUSE[3:0]},
                         `PRB_TRAP_PC, `PRB_TRAP_TVAL, cycles);
                case (`PRB_TRAP_CAUSE)
                    5'd2:      illegal_errors++;
                    5'd4, 5'd6: misal_errors++;
                    5'd5, 5'd7: bus_faults++;      // checked against dbus_errors
                    default:   other_traps++;
                endcase
            end
            if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA == 32'd1) begin
                ext_irq_tb <= 1'b1;
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA == 32'd2) begin
                ext_irq_tb <= 1'b0;
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR) begin
                halted = 1'b1;
                fork check_and_finish(); join_none
            end else if (cycles >= timeout) begin
                $display("RESULT TIMEOUT test=%s cycles=%0d", test_name, cycles);
                $finish;
            end
        end
    end

    function automatic logic [31:0] tcm_word(logic [31:0] addr);
        return `PRB_TCM_ARR[(addr - TCM_BASE) >> 2];
    endfunction

    task automatic check_and_finish();
        int fd = 0;
        int mismatches = 0;
        logic [31:0] got;
        repeat (DRAIN) @(posedge clk);

        if (sig_out != "") fd = $fopen(sig_out, "w");
        for (int i = 0; i < sig_words; i++) begin
            got = tcm_word(sig_begin + 4 * i);
            if (fd != 0) $fdisplay(fd, "%08h", got);
            if (got !== expected[i]) begin
                mismatches++;
                $display("MISMATCH test=%s idx=%0d addr=0x%08h got=0x%08h exp=0x%08h",
                         test_name, i, sig_begin + 4 * i, got, expected[i]);
            end
        end
        if (fd != 0) $fclose(fd);

        if (sig_words == 0)
            $display("RESULT FAIL test=%s cycles=%0d reason=no_signature", test_name, cycles);
        else if (dbus_errors != dbus_expected || illegal_errors != illegal_expected ||
                 misal_errors != misal_expected || other_traps != other_expected ||
                 bus_faults != dbus_errors)
            $display("RESULT FAIL test=%s cycles=%0d errors(dbus/illegal/misaligned/other)=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d bus_fault_traps=%0d mismatches=%0d/%0d",
                     test_name, cycles, dbus_errors, illegal_errors, misal_errors, other_traps,
                     dbus_expected, illegal_expected, misal_expected, other_expected, bus_faults,
                     mismatches, sig_words);
        else if (sva_errors != 0)
            $display("RESULT FAIL test=%s cycles=%0d sva_errors=%0d mismatches=%0d/%0d",
                     test_name, cycles, sva_errors, mismatches, sig_words);
        else if (mismatches == 0)
            $display("RESULT PASS test=%s cycles=%0d checks=%0d%s", test_name, cycles, sig_words,
                     hold_cycles > 0 ? $sformatf(" ex_holds=%0d", holds_done) : "");
        else
            $display("RESULT FAIL test=%s cycles=%0d mismatches=%0d/%0d",
                     test_name, cycles, mismatches, sig_words);
        $finish;
    endtask

endmodule
