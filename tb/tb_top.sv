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
//   +CLK_SEL=<0/1>     clock-select strap pin level during reset (default 0)
//   +BOOT_MODE=<0..3>  boot-mode strap pins during reset (default 0)
//   +DBUS_ERRORS=<n>   expected number of unmapped data accesses (default 0)
//   +ILLEGAL_ERRORS=<n>    expected illegal-instruction traps (mcause 2, default 0)
//   +MISALIGNED_ERRORS=<n> expected misaligned load/store traps (mcause 4/6, default 0)
//   +OTHER_TRAPS=<n>       expected traps with any other cause (default 0)
//   +HOLD_EX_STORES=<n> hold every TCM store in EX for n cycles (forces the EX
//                     hold) to check that a held store still writes exactly once
//   +BUS_WAIT=<n>|rand add wait states to every data-bus access: n cycles at
//                     the start of each access, or (rand) a random 1-in-3
//                     chance on every cycle an access is in flight
//   +BUS_SEED=<n>      seed for BUS_WAIT=rand (default 1)
//   BOOT=rom snapshot only (tb_top_rom, elaborated with BOOT_ROM=1: reset at
//   the boot ROM, writable IMEM, UART0 at 3.125 Mbaud = 32 clocks per bit):
//   +BOOTROM=<hex>     boot ROM image (required; build/boot/bootrom.hex)
//   +FRAMES=<file>     UART frame stream from scripts/load.py --emit
//   +BOOT_CASE=<n>     0: load the test over UART0 (IMEM starts all zero,
//                      TCM empty; 0 NAK expected); 1: the same, with one CRC
//                      byte of the first data frame corrupted once (exactly
//                      1 NAK expected); 2: a bad byte before the magic (one
//                      ERR 0xE1 expected); 3: no load: IMEM/TCM preloaded,
//                      boot mode 1 (+BOOT_MODE=1), the ROM jumps to 0;
//                      4: the first data frame's CRC is bad on every try (3
//                      NAKs, then ERR 0xE2), then the whole load again;
//                      5: a frame header outside IMEM/TCM (ERR 0xE3), then
//                      the whole load again
//                      Every case requires UART0 RX overrun to stay 0.
//   +BUS_HANG_ADDR=<hex> every bus access to this address is held for
//                     BUS_HANG_CYCLES (default 400) cycles: longer than the
//                     core's bus timeout (256), so it ends in an access fault
//
// Simulation control word at HALT_ADDR (the RTL ignores writes there):
//   store 1 -> raise the external interrupt line, store 2 -> drop it,
//   0x1xx -> send byte xx to UART0's RX pin (8N1 at UART0's current DIV),
//   0x2xx -> the same with a low stop bit (framing error),
//   0x300 / 0x301 -> UART0 external loopback (RX pin = TX pin) on / off,
//   0x40m -> SPI echo target (CS1) mode m = {CPOL, CPHA},
//   0x5nn -> I2C target stretches SCL nn us after every ACK clock (0 = off),
//   0x6kk -> I2C target acts as a second master at address bit kk,
//   0x7nn -> timer capture input 1 = pwm_out[nn],
//   0x8nn -> I2C bus hog for nn us: nn < 0x80 SDA stuck low (no START),
//            nn >= 0x80 another master holds the bus (START, lines high),
//   0x90m -> boot-mode strap pins = m (the latch must ignore it after reset),
//   any other value -> halt and check (TEST_END stores 0).
// Output ends with exactly one line:
//   RESULT PASS|FAIL|TIMEOUT test=<name> cycles=<n> ...
// ============================================================================
`timescale 1ns/1ps
`include "tb_probes.svh"

module tb_top #(
    parameter bit BOOT_ROM = 1'b0      // 1: BOOT=rom configuration (tb_top_rom snapshot)
);

    localparam logic [31:0] HALT_ADDR  = 32'hC000_0FFC;
    localparam logic [31:0] TCM_BASE   = 32'h8000_0000;
    localparam int          TCM_WORDS  = 1024;
    localparam int          IMEM_WORDS = 2048;
    localparam int          MAX_SIG    = 1024;
    localparam int          DRAIN      = 8;    // cycles after halt before checking
    localparam int          ROM_WORDS  = 1024;

    // ---------------------------------------------------------------- DUT
    logic       clk   = 1'b0;
    logic       reset = 1'b1;           // reset pin (the core runs on its synchronised rst_sys)
    logic       clk_sel_strap = 1'b0;   // clock select strap (+CLK_SEL=1: PLL)
    logic [1:0] boot_mode_strap = 2'd0; // boot-mode strap (+BOOT_MODE=<n>)
    logic [7:0] debug_pc, debug_wb;
    logic       uart_tx_out;
    logic [6:0] seg;
    logic       dp;
    logic [3:0] an;
    wire        i2c_scl, i2c_sda;
    logic       uart0_tx, uart0_rx;
    logic       uart0_rx_drv = 1'b1;     // harness driver of UART0's RX pin
    bit         uart0_loop   = 1'b0;     // external loopback
    assign uart0_rx = uart0_loop ? uart0_tx : uart0_rx_drv;
    // SPI: flash model on CS0, any-mode echo target on CS1, MISO pulled up
    wire        spi_sck, spi_mosi, spi_miso;
    wire [1:0]  spi_cs_n;
    logic [1:0] spi_echo_mode = 2'b00;
    pullup (spi_miso);

    // GPIO: weak pull-downs on every pin; gpio[7:0] drives gpio[15:8] at
    // pull strength (a pin the DUT drives itself wins).
    wire [15:0] gpio;
    for (genvar i = 0; i < 16; i++) begin : g_gpio_pd
        pulldown (weak0) u_pd (gpio[i]);
    end
    for (genvar i = 0; i < 8; i++) begin : g_gpio_loop
        assign (pull1, pull0) gpio[i + 8] = gpio[i];
    end

    // Timers: cap_in[0] = pwm_out[0], cap_in[1] = pwm_out[cap1_sel]
    wire  [3:0] pwm;
    wire  [1:0] cap;
    logic [1:0] cap1_sel = 2'd1;
    assign cap = {pwm[cap1_sel], pwm[0]};

    pullup (i2c_scl);
    pullup (i2c_sda);

    always #5 clk = ~clk;   // 100 MHz

    cpu_pipeline_top #(
        .RESET_VECTOR  (BOOT_ROM ? 32'h0001_0000 : 32'h0000_0000),
        .IMEM_WRITABLE (BOOT_ROM),
        .BAUD_RATE     (BOOT_ROM ? 3_125_000 : 115_200)
    ) dut (
        .clk         (clk),
        .reset       (reset),
        .clk_sel_strap (clk_sel_strap),
        .boot_mode_strap (boot_mode_strap),
        .debug_pc    (debug_pc),
        .debug_wb    (debug_wb),
        .i2c_scl     (i2c_scl),
        .i2c_sda     (i2c_sda),
        .uart_tx_out (uart_tx_out),
        .uart0_tx_out (uart0_tx),
        .uart0_rx_in  (uart0_rx),
        .spi_sck     (spi_sck),
        .spi_mosi    (spi_mosi),
        .spi_miso    (spi_miso),
        .spi_cs_n    (spi_cs_n),
        .gpio        (gpio),
        .pwm_out     (pwm),
        .cap_in      (cap),
        .seg         (seg),
        .dp          (dp),
        .an          (an)
    );

    commit_monitor u_commit (
        .clk     (clk),
        .reset   (`PRB_RST),
        .wb_we   (`PRB_WB_WE),
        .wb_rd   (`PRB_WB_RD),
        .wb_data (`PRB_WB_DATA)
    );

    uart_monitor u_uart (.clk(clk), .rx(uart_tx_out));

    // I2C target at 0x48 (ADS1115 address), open-drain on the pulled-up bus
    i2c_target_model #(.ADDR(7'h48)) u_i2c_target (.scl(i2c_scl), .sda(i2c_sda));

    spi_flash_model u_spi_flash (.cs_n(spi_cs_n[0]), .sck(spi_sck), .mosi(spi_mosi), .miso(spi_miso));
    spi_echo_model  u_spi_echo  (.cs_n(spi_cs_n[1]), .sck(spi_sck), .mosi(spi_mosi), .miso(spi_miso),
                                 .mode(spi_echo_mode), .div(16'(`PRB_SPI_DIV)));

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

    // Boot (BOOT_ROM only): what the loader answered
    int  boot_case = 0;
    int  boot_acks = 0, boot_naks = 0, boot_errs = 0, boot_bad = 0;
    bit  boot_done = 1'b0;
    initial if (!$value$plusargs("BOOT_CASE=%d", boot_case)) boot_case = 0;

    initial begin
        if (!$value$plusargs("TEST=%s", test_name))      test_name = "unnamed";
        if ($value$plusargs("CLK_SEL=%d", clk_sel_strap)) ;
        if ($value$plusargs("BOOT_MODE=%d", boot_mode_strap)) ;
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
        for (int i = 0; i < TCM_WORDS;  i++) `PRB_TCM_ARR[i]  = 32'h0000_0000;
        if (BOOT_ROM && boot_case != 3) begin
            // the boot ROM loads the program: IMEM starts all zero (illegal)
            for (int i = 0; i < IMEM_WORDS; i++) `PRB_IMEM_ARR[i] = 32'h0000_0000;
        end else begin
            for (int i = 0; i < IMEM_WORDS; i++) `PRB_IMEM_ARR[i] = 32'h0000_0013;  // NOP
            $readmemh(imem_file, `PRB_IMEM_ARR);
            if (tcm_file != "") $readmemh(tcm_file, `PRB_TCM_ARR);
        end
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
                if (!`PRB_RST && !halted && `PRB_EX_TCM_STORE) begin
                    force `PRB_EX_HOLD = 1'b1;
                    repeat (hold_cycles) @(posedge clk);
                    #1 force `PRB_EX_HOLD = `PRB_EX_HOLD_RTL;   // back to the RTL driver
                    holds_done++;
                    @(posedge clk);      // let this store leave EX before re-arming
                end
            end
        end
    end

    // ---------------------------------------------------------------- bus wait hook
    // Emulates a slow bus: forces the RTL hook net (tied to 0) high, which
    // holds the bus response back. The pipeline must give the same results
    // with any number of wait states.
    string bus_wait_arg;
    int    bus_wait_n = 0, bus_seed = 1, bus_waits = 0;
    bit    bus_wait_rand = 1'b0, bus_hook = 1'b0;
    bit    prev_stall = 1'b0;
    logic [31:0] hang_addr;
    int    hang_cycles = 400;
    bit    hang_en = 1'b0;
    initial begin
        hang_en = $value$plusargs("BUS_HANG_ADDR=%h", hang_addr);
        if (!$value$plusargs("BUS_HANG_CYCLES=%d", hang_cycles)) hang_cycles = 400;
        if ($value$plusargs("BUS_WAIT=%s", bus_wait_arg)) begin
            if (bus_wait_arg == "rand") bus_wait_rand = 1'b1;
            else                        bus_wait_n = bus_wait_arg.atoi();
        end
        if (!$value$plusargs("BUS_SEED=%d", bus_seed)) bus_seed = 1;
        process::self().srandom(bus_seed);
        bus_hook = bus_wait_rand || bus_wait_n > 0 || hang_en;
        force `PRB_BUS_WAIT = 1'b0;
        if (bus_hook) begin
            forever begin
                @(posedge clk); #1;
                if (!`PRB_RST && !halted && `PRB_BUS_BUSY) begin
                    if (hang_en && !prev_stall && `PRB_BUS_ADDR == hang_addr) begin
                        force `PRB_BUS_WAIT = 1'b1;
                        repeat (hang_cycles) @(posedge clk);
                        #1 force `PRB_BUS_WAIT = 1'b0;
                        bus_waits += hang_cycles;
                    end else if (bus_wait_rand) begin
                        if ($urandom_range(2) == 0) begin
                            force `PRB_BUS_WAIT = 1'b1;
                            bus_waits++;
                        end else begin
                            force `PRB_BUS_WAIT = 1'b0;
                        end
                    end else if (!prev_stall) begin     // first cycle of a new access
                        force `PRB_BUS_WAIT = 1'b1;
                        repeat (bus_wait_n) @(posedge clk);
                        #1 force `PRB_BUS_WAIT = 1'b0;
                        bus_waits += bus_wait_n;
                    end
                end else begin
                    force `PRB_BUS_WAIT = 1'b0;
                end
                prev_stall = `PRB_MEM_STALL;
            end
        end
    end

    // ---------------------------------------------------------------- halt / timeout
    always @(posedge clk) begin
        if (!`PRB_RST && !halted) begin
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
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR &&
                         (`PRB_ST_DATA[31:8] == 24'h1 || `PRB_ST_DATA[31:8] == 24'h2)) begin
                fork uart0_send(`PRB_ST_DATA[7:0], `PRB_ST_DATA[31:8] == 24'h1); join_none
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA == 32'h300) begin
                uart0_loop = 1'b1;
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA == 32'h301) begin
                uart0_loop = 1'b0;
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA[31:2] == 30'h100) begin
                spi_echo_mode <= `PRB_ST_DATA[1:0];
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA[31:8] == 24'h5) begin
                u_i2c_target.stretch_ns = 1000 * `PRB_ST_DATA[7:0];
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA[31:8] == 24'h6) begin
                u_i2c_target.al_bit = `PRB_ST_DATA[7:0];
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA[31:8] == 24'h7) begin
                cap1_sel <= `PRB_ST_DATA[1:0];
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA[31:8] == 24'h8) begin
                u_i2c_target.hog_kind = `PRB_ST_DATA[7];
                u_i2c_target.hog_ns   = 1000 * `PRB_ST_DATA[6:0];
                u_i2c_target.hog_go   = 1'b1;
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR && `PRB_ST_DATA[31:2] == 30'h240) begin
                boot_mode_strap <= `PRB_ST_DATA[1:0];
            end else if (`PRB_ST_VALID && `PRB_ST_ADDR == HALT_ADDR) begin
                halted = 1'b1;
                fork check_and_finish(); join_none
            end else if (cycles >= timeout) begin
                $display("RESULT TIMEOUT test=%s cycles=%0d", test_name, cycles);
                $finish;
            end
        end
    end

    // One 8N1 frame on UART0's RX pin at UART0's current bit time.
    task automatic uart0_send(input logic [7:0] b, input bit good_stop);
        int div = `PRB_UART0_DIV;
        logic [9:0] frame = {good_stop, b, 1'b0};
        for (int i = 0; i < 10; i++) begin
            uart0_rx_drv <= frame[i];
            repeat (div) @(posedge clk);
        end
        uart0_rx_drv <= 1'b1;
    endtask

    // ---------------------------------------------------------------- boot ROM
    if (BOOT_ROM) begin : g_boot
        string rom_file;
        initial begin
            if (!$value$plusargs("BOOTROM=%s", rom_file)) begin
                $display("RESULT FAIL test=%s reason=no_BOOTROM_plusarg", test_name);
                $finish;
            end
            #1;
            for (int i = 0; i < ROM_WORDS; i++) `PRB_ROM_ARR[i] = 32'h0000_0000;
            $readmemh(rom_file, `PRB_ROM_ARR);
        end
    end

    // UART0 TX decoder (loader replies): free-running, so a reply that starts
    // while the harness is still finishing a send is never missed.
    logic [7:0] rx_q [$];
    initial if (BOOT_ROM) begin
        logic [7:0] b;
        int div;
        forever begin
            @(negedge uart0_tx);
            if (`PRB_RST !== 1'b0) continue;
            div = `PRB_UART0_DIV;
            repeat (div / 2) @(posedge clk);
            if (uart0_tx !== 1'b0) continue;          // glitch, not a start bit
            for (int i = 0; i < 8; i++) begin
                repeat (div) @(posedge clk);
                b[i] = uart0_tx;
            end
            repeat (div) @(posedge clk);              // stop bit
            rx_q.push_back(b);
        end
    end

    task automatic boot_reply(output logic [7:0] r);
        wait (rx_q.size() > 0);
        r = rx_q.pop_front();
    endtask

    // Send one line of the frame stream; flip = index of a byte to corrupt (-1: none)
    task automatic boot_send_line(input string line, input int flip);
        logic [7:0] b;
        for (int i = 0; i < line.len() / 2; i++) begin
            b = line.substr(2 * i, 2 * i + 1).atohex();
            if (i == flip) b = ~b;
            uart0_send(b, 1'b1);
        end
    endtask

    initial if (BOOT_ROM && boot_case != 3) begin
        string frames_file, line;
        string lines [$];
        int fd, tries, flip;
        bit flipped = 1'b0;
        logic [7:0] r;
        if (!$value$plusargs("FRAMES=%s", frames_file)) begin
            $display("RESULT FAIL test=%s reason=no_FRAMES_plusarg", test_name);
            $finish;
        end
        fd = $fopen(frames_file, "r");
        while ($fgets(line, fd)) begin
            while (line.len() > 0 && (line[line.len() - 1] == "\n" || line[line.len() - 1] == "\r"))
                line = line.substr(0, line.len() - 2);
            if (line.len() > 0) lines.push_back(line);
        end
        $fclose(fd);
        wait (`PRB_RST === 1'b0);
        @(posedge clk);
        // Pass 0 carries the case's fault; an expected ERR ends it, and the
        // harness starts again from the magic (pass 1, clean), like a host.
        for (int pass = 0; pass < 2 && boot_bad == 0 && !boot_done; pass++) begin
            if (pass > 0) repeat (30 * `PRB_UART0_DIV) @(posedge clk);  // let the flush finish
            if (boot_case == 2 && pass == 0) begin    // garbage before the magic
                uart0_send(8'h00, 1'b1);
                boot_reply(r);
                if (r == 8'hE1) boot_errs++; else boot_bad++;
                continue;
            end
            boot_send_line(lines[0], -1);             // magic
            boot_reply(r);
            if (r == 8'h06) boot_acks++; else boot_bad++;
            if (boot_case == 5 && pass == 0 && boot_bad == 0) begin
                // header of a frame outside IMEM and TCM: addr 0x4000_0000, len 4
                boot_send_line("0000004004000000", -1);
                boot_reply(r);
                if (r == 8'hE3) boot_errs++; else boot_bad++;
                continue;
            end
            boot_done = 1'b1;
            for (int k = 1; k < lines.size() && boot_bad == 0 && boot_done; k++) begin
                tries = 0;
                do begin
                    // case 1: corrupt the first data frame's last CRC byte once;
                    // case 4: on every try (the 4th bad CRC is answered ERR 0xE2)
                    flip = ((boot_case == 1 && !flipped) || (boot_case == 4 && pass == 0)) && k == 1
                           ? lines[k].len() / 2 - 1 : -1;
                    if (flip >= 0) flipped = 1'b1;
                    boot_send_line(lines[k], flip);
                    boot_reply(r);
                    tries++;
                    if (r == 8'h15) boot_naks++;
                end while (r == 8'h15 && tries < 4);
                if (r == 8'h06) boot_acks++;
                else if (r == 8'hE2 && boot_case == 4 && pass == 0) begin
                    boot_errs++;
                    boot_done = 1'b0;                 // resync and send it all again
                end else begin
                    boot_bad++;
                    $display("TB: boot frame %0d answered 0x%02h", k, r);
                end
            end
        end
        boot_done = boot_done && (boot_bad == 0);
        $display("TB: boot load done=%0d acks=%0d naks=%0d errs=%0d cycle=%0d",
                 boot_done, boot_acks, boot_naks, boot_errs, cycles);
    end

    // Expected loader answers per case: NAKs and ERRs (0xE1 / 0xE2 / 0xE3)
    function automatic bit boot_ok();
        int exp_naks, exp_errs;
        if (!BOOT_ROM) return 1'b1;
        if (`PRB_UART0_OVR !== 1'b0) return 1'b0;
        if (boot_case == 3) return boot_acks == 0 && boot_bad == 0;
        exp_naks = boot_case == 1 ? 1 : boot_case == 4 ? 3 : 0;
        exp_errs = (boot_case == 2 || boot_case == 4 || boot_case == 5) ? 1 : 0;
        return boot_done && boot_naks == exp_naks && boot_errs == exp_errs && boot_bad == 0;
    endfunction

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
        else if (!boot_ok())
            $display("RESULT FAIL test=%s cycles=%0d reason=boot case=%0d done=%0d acks/naks/errs/bad=%0d/%0d/%0d/%0d rx_overrun=%0d mismatches=%0d/%0d",
                     test_name, cycles, boot_case, boot_done, boot_acks, boot_naks, boot_errs,
                     boot_bad, `PRB_UART0_OVR, mismatches, sig_words);
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
            $display("RESULT PASS test=%s cycles=%0d checks=%0d%s%s%s", test_name, cycles, sig_words,
                     BOOT_ROM ? $sformatf(" boot=%0d/%0d/%0d", boot_acks, boot_naks, boot_errs) : "",
                     hold_cycles > 0 ? $sformatf(" ex_holds=%0d", holds_done) : "",
                     bus_hook ? $sformatf(" bus_waits=%0d", bus_waits) : "");
        else
            $display("RESULT FAIL test=%s cycles=%0d mismatches=%0d/%0d",
                     test_name, cycles, mismatches, sig_words);
        $finish;
    endtask

endmodule
