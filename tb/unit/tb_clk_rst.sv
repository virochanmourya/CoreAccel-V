// ============================================================================
// tb_clk_rst — unit test for rst_gen, clk_mux_gf and clk_gen (Vivado xsim)
//
//   1. rst_gen: asynchronous assert from the pin (no clock edge needed),
//      release after 2 (rst_por) / 4 (rst_sys) clock edges, watchdog and
//      software requests: rst_sys only, asserted 2 edges after the request,
//      held STRETCH cycles; rst_por unaffected; a pin reset during an
//      internal reset wins.
//   2. clk_mux_gf with two unrelated clocks (10 ns and 7 ns): sel toggled at
//      random times; clk_out must never have a high or low phase shorter
//      than the shorter input half-period, and once switched it must follow
//      the selected clock edge for edge.
//   3. clk_gen (CLK_TECH = "ASIC" and "FPGA"): the strap is latched only
//      while the reset pin is held; the FPGA variant is a pure pass-through.
//
// Output ends with: RESULT PASS|FAIL test=clk_rst cycles=<n> checks=<n>
// ============================================================================
`timescale 1ns/1ps

module tb_clk_rst;

    string test_name = "clk_rst";
    int    errors = 0, checks = 0;
    longint cycles = 0;

    task automatic check(input bit cond, input string what);
        checks++;
        if (!cond) begin
            errors++;
            $display("MISMATCH test=%s check=%0d %s t=%0t", test_name, checks, what, $time);
        end
    endtask

    // ------------------------------------------------------------ rst_gen
    localparam int STRETCH = 16;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    always @(posedge clk) cycles++;

    logic rst_pin = 1'b0, req_wdt = 1'b0, req_sw = 1'b0;
    logic rst_por, rst_sys;

    rst_gen #(.STRETCH(STRETCH)) u_rst (
        .clk (clk), .rst_pin (rst_pin), .req_wdt (req_wdt), .req_sw (req_sw),
        .rst_por (rst_por), .rst_sys (rst_sys)
    );

    // Edges (posedge clk) from now until sig reaches val (bounded).
    task automatic edges_until(ref logic sig, input logic val, output int n);
        n = 0;
        while (sig !== val && n < 1000) begin
            @(posedge clk); #1; n++;
        end
    endtask

    // Pulse a request for one cycle (driven like a flop output after an edge).
    task automatic pulse(ref logic r);
        @(posedge clk); #1 r = 1'b1;
        @(posedge clk); #1 r = 1'b0;
    endtask

    // Measure an internal reset: returns edges from the request edge to
    // rst_sys rising, and how many cycles it stays high.
    task automatic internal_reset(input bit wdt, output int lat, output int len);
        int n;
        @(posedge clk); #1;
        if (wdt) req_wdt = 1'b1; else req_sw = 1'b1;
        @(posedge clk); #1;                     // the request edge
        req_wdt = 1'b0; req_sw = 1'b0;
        lat = 0;
        while (rst_sys !== 1'b1 && lat < 100) begin
            check(rst_por === 1'b0, "rst_por stays low on an internal request");
            @(posedge clk); #1; lat++;
        end
        len = 0;
        while (rst_sys === 1'b1 && len < 1000) begin
            check(rst_por === 1'b0, "rst_por stays low during an internal reset");
            @(posedge clk); #1; len++;
        end
    endtask

    task automatic test_rst_gen();
        int n, lat, len;
        // Asynchronous assert: mid-cycle, no clock edge in between.
        @(posedge clk); #2 rst_pin = 1'b1; #0.5;
        check(rst_por === 1'b1 && rst_sys === 1'b1, "pin asserts both resets without a clock edge");
        repeat (3) @(posedge clk);
        #3 rst_pin = 1'b0;                      // release between edges
        #0.5;
        check(rst_por === 1'b1 && rst_sys === 1'b1, "release is not immediate");
        edges_until(rst_por, 1'b0, n);
        check(n == 2, $sformatf("rst_por released after 2 edges (got %0d)", n));
        check(rst_sys === 1'b1, "rst_sys still held when rst_por releases");
        edges_until(rst_sys, 1'b0, n);
        check(n == 2, $sformatf("rst_sys released 2 edges after rst_por (got %0d)", n));

        internal_reset(1'b1, lat, len);
        check(lat == 2, $sformatf("watchdog: rst_sys 2 edges after the request (got %0d)", lat));
        check(len == STRETCH, $sformatf("watchdog: rst_sys held %0d cycles (got %0d)", STRETCH, len));
        internal_reset(1'b0, lat, len);
        check(lat == 2, $sformatf("software: rst_sys 2 edges after the request (got %0d)", lat));
        check(len == STRETCH, $sformatf("software: rst_sys held %0d cycles (got %0d)", STRETCH, len));

        // Pin reset in the middle of an internal reset: both assert, and the
        // release follows the pin (4 edges), not the stretcher.
        pulse(req_sw);
        repeat (4) @(posedge clk);
        #2 rst_pin = 1'b1; #0.5;
        check(rst_por === 1'b1 && rst_sys === 1'b1, "pin during internal reset asserts rst_por");
        @(posedge clk); #3 rst_pin = 1'b0;
        edges_until(rst_sys, 1'b0, n);
        check(n == 4, $sformatf("after pin release rst_sys releases after 4 edges (got %0d)", n));
        check(rst_por === 1'b0, "rst_por released");
    endtask

    // ------------------------------------------------------------ clk_mux_gf
    logic c0 = 1'b0, c1 = 1'b0, mrst = 1'b1, msel = 1'b0, mout;
    always #5   c0 = ~c0;          // 10 ns
    initial begin #1.3; forever #3.5 c1 = ~c1; end   // 7 ns, offset
    clk_mux_gf u_mux (.clk0 (c0), .clk1 (c1), .rst (mrst), .sel (msel), .clk_out (mout));

    localparam realtime MIN_PHASE = 3.5 - 0.01;
    realtime last_rise = 0, last_fall = 0;
    bit      mon_en = 1'b0;
    int      short_pulses = 0, mux_edges = 0;
    always @(posedge mout) if (mon_en) begin
        mux_edges++;
        if ($realtime - last_fall < MIN_PHASE) begin
            short_pulses++;
            $display("MISMATCH test=%s short low phase %0.3f ns at %0t", test_name,
                     $realtime - last_fall, $time);
        end
        last_rise = $realtime;
    end
    always @(negedge mout) if (mon_en) begin
        if ($realtime - last_rise < MIN_PHASE) begin
            short_pulses++;
            $display("MISMATCH test=%s short high phase %0.3f ns at %0t", test_name,
                     $realtime - last_rise, $time);
        end
        last_fall = $realtime;
    end

    // After a switch has settled, every clk_out edge is an edge of the
    // selected input (and of nothing else).
    task automatic expect_follows(input bit sel, input int n_edges);
        int ok = 1;
        for (int i = 0; i < n_edges; i++) begin
            @(mout);
            if (sel ? (mout !== c1) : (mout !== c0)) ok = 0;
        end
        check(ok, $sformatf("clk_out follows clk%0d after the switch", sel));
    endtask

    task automatic test_mux();
        #20 mrst = 1'b0;
        last_rise = $realtime - 10; last_fall = $realtime - 10; mon_en = 1'b1;
        #50;
        expect_follows(1'b0, 10);
        for (int i = 0; i < 40; i++) begin
            #($urandom_range(5000, 100) / 100.0);   // 1..50 ns, random phase
            msel = ~msel;
            #60;                                    // longer than one switch
            expect_follows(msel, 8);
        end
        mon_en = 1'b0;
        check(short_pulses == 0, $sformatf("no short clk_out pulses (%0d found)", short_pulses));
        // Async reset of the mux forces clk0 back on. (Asserting it may cut a
        // phase short, like any asynchronous reset; only the pin drives it.)
        // clk0 must come out from its first edge after the release: count
        // clk_out rising edges against clk0's over the next 8 periods.
        msel = 1'b1; #60;
        mrst = 1'b1; #0.5 msel = 1'b0;
        @(posedge c0); #1 mrst = 1'b0;          // release while clk0 is high
        begin
            int n_out = 0, n_c0 = 0;
            fork
                begin repeat (8) @(posedge c0); end
                forever @(posedge mout) n_out++;
                forever @(posedge c0) n_c0++;
            join_any
            disable fork;
            check(n_out == n_c0, $sformatf("no clk0 pulse lost after the mux reset (%0d/%0d)",
                                           n_out, n_c0));
        end
        expect_follows(1'b0, 6);
        check(mux_edges > 100, "clk_out kept running");
    endtask

    // ------------------------------------------------------------ clk_gen
    logic g_rst = 1'b1, g_strap = 1'b0;
    logic ga_clk, ga_sel, ga_lock, gf_clk, gf_sel, gf_lock;
    clk_gen #(.CLK_TECH("ASIC")) u_gen_asic (
        .clk_in (clk), .rst_pin (g_rst), .sel_strap (g_strap),
        .clk_out (ga_clk), .sel_q (ga_sel), .pll_lock (ga_lock)
    );
    clk_gen #(.CLK_TECH("FPGA")) u_gen_fpga (
        .clk_in (clk), .rst_pin (g_rst), .sel_strap (g_strap),
        .clk_out (gf_clk), .sel_q (gf_sel), .pll_lock (gf_lock)
    );
    int fpga_diff = 0;
    always @(clk, gf_clk) #0.01 if (gf_clk !== clk) fpga_diff++;

    task automatic gen_cycle(input bit strap_in_reset);
        g_rst = 1'b1; g_strap = strap_in_reset;
        repeat (6) @(posedge clk);
        #3 g_rst = 1'b0;
        repeat (4) @(posedge clk);
        check(ga_sel === strap_in_reset && gf_sel === strap_in_reset,
              $sformatf("strap %0d latched in reset", strap_in_reset));
        g_strap = ~strap_in_reset;                // strap moves after reset
        repeat (8) @(posedge clk); #1;
        check(ga_sel === strap_in_reset && gf_sel === strap_in_reset,
              "strap change after reset ignored");
        check(ga_lock === 1'b1 && gf_lock === 1'b1, "empty PLL slot reports lock");
        begin
            int ok = 1;
            repeat (10) begin @(posedge clk); #0.2; if (ga_clk !== 1'b1) ok = 0;
                              @(negedge clk); #0.2; if (ga_clk !== 1'b0) ok = 0; end
            check(ok, "ASIC clk_out runs at clk_in");
        end
    endtask

    task automatic test_clk_gen();
        gen_cycle(1'b1);
        gen_cycle(1'b0);
        gen_cycle(1'b1);
        check(fpga_diff == 0, $sformatf("FPGA clk_gen is a pass-through (%0d diffs)", fpga_diff));
    endtask

    // ------------------------------------------------------------ main
    initial begin
        process::self().srandom(7);
        fork
            test_rst_gen();
            test_mux();
            test_clk_gen();
        join
        if (errors == 0)
            $display("RESULT PASS test=%s cycles=%0d checks=%0d", test_name, cycles, checks);
        else
            $display("RESULT FAIL test=%s cycles=%0d mismatches=%0d/%0d", test_name, cycles,
                     errors, checks);
        $finish;
    end

    initial begin
        #1ms;
        $display("RESULT TIMEOUT test=%s cycles=%0d", test_name, cycles);
        $finish;
    end

endmodule
