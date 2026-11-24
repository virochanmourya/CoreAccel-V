// ============================================================================
// Module      : apb_timer
// File        : apb_timer.sv
// Description : General timers, PWM outputs and input capture, APB4 slave.
//
//   Groups of four words (n = group index):
//   0x00    STATUS   R/W1C  events (sticky; write 1 clears, an event wins):
//                           [NT-1:0] timer match, then NCAP capture, then
//                           NCAP capture overflow, then NPWM PWM wrap.
//                           Defaults: 0-1 T, 2-3 CAP, 4-5 OVF, 6-9 PWM.
//   0x04    IE       RW     same layout; irq = |(STATUS & IE), a level
//   0x08    PWM_PRESC RW    [15:0] all PWM counters step every PRESC+1 clocks
//   0x10 + 0x10*t  timer t (NT = 2, 32 bits):
//     +0 CTRL  RW  bit0 EN, bit1 ONESHOT
//     +4 PRESC RW  [15:0] COUNT steps every PRESC+1 clocks while EN
//     +8 CMP   RW  match value (reset 0xFFFF_FFFF)
//     +C COUNT RW  at a step with COUNT == CMP: match event, COUNT <= 0, and
//                  with ONESHOT, EN <= 0. Period = (CMP+1)*(PRESC+1) clocks.
//   0x40 + 0x10*k  PWM channel k (NPWM, PWM_W bits):
//     +0 CTRL   RW  bit0 EN, bit1 POL (1 = inverted; also the idle level)
//     +4 PERIOD RW  counter runs 0..PERIOD: period = (PERIOD+1)*(PWM_PRESC+1)
//     +8 DUTY   RW  output active while counter < DUTY (DUTY > PERIOD: 100 %)
//     +C COUNT  R   the channel counter
//     PERIOD/DUTY are shadowed: written values take effect at the next wrap
//     (counter == PERIOD at a step), or at once while EN = 0. Wrap event.
//     The output is registered.
//   0x80 + 0x10*j  capture channel j (NCAP, 32-bit counter of its own):
//     +0 CTRL  RW  bit0 EN, bit1 rising, bit2 falling (both = both edges)
//     +4 PRESC RW  [15:0] COUNT steps every PRESC+1 clocks while EN
//     +8 COUNT R   free-running while EN, 0 while EN = 0
//     +C CAPT  R   COUNT at the last selected edge (input 2-FF synchronised)
//     A capture sets STATUS.CAPj; a capture while CAPj is still set (not yet
//     acknowledged by W1C) also sets OVFj; CAPT always keeps the newest.
//   other            PSLVERR
//   Zero wait states.
// ============================================================================

module apb_timer #(
    parameter int NPWM  = 4,
    parameter int NCAP  = 2,
    parameter int PWM_W = 16
)(
    input  logic            clk,
    input  logic            reset,

    // ---- APB4 slave ----
    input  logic            psel,
    input  logic            penable,
    input  logic            pwrite,
    input  logic [31:0]     paddr,
    input  logic [31:0]     pwdata,
    output logic [31:0]     prdata,
    output logic            pready,
    output logic            pslverr,

    // ---- Pins ----
    output logic [NPWM-1:0] pwm_out,
    input  logic [NCAP-1:0] cap_in,        // asynchronous

    output logic            irq
);
    localparam int NT  = 2;
    localparam int NEV = NT + 2 * NCAP + NPWM;
    localparam int E_CAP = NT, E_OVF = NT + NCAP, E_PWM = NT + 2 * NCAP;

    initial begin
        if (NPWM < 1 || NPWM > 4)   $error("apb_timer: NPWM out of range");
        if (NCAP < 1 || NCAP > 4)   $error("apb_timer: NCAP out of range");
        if (PWM_W < 2 || PWM_W > 32) $error("apb_timer: PWM_W out of range");
    end

    // ------------------------------------------------------------ APB decode
    logic       wr, hit;
    logic [3:0] grp;
    logic [1:0] rg;
    assign wr   = psel & penable & pwrite;
    assign grp  = paddr[7:4];
    assign rg   = paddr[3:2];
    always_comb begin
        hit = 1'b0;
        if (paddr[11:8] == 4'd0) begin
            if (grp == 4'd0)                               hit = (rg != 2'd3);
            else if (grp >= 4'd1 && grp <= 4'(NT))         hit = 1'b1;
            else if (grp >= 4'd4 && grp <  4'(4 + NPWM))   hit = 1'b1;
            else if (grp >= 4'd8 && grp <  4'(8 + NCAP))   hit = 1'b1;
        end
    end
    assign pready  = 1'b1;
    assign pslverr = ~hit;

    logic [NEV-1:0] ev, status, ie;

    // ------------------------------------------------------------ timers
    logic [NT-1:0]   t_en, t_os;
    logic [15:0]     t_presc [NT];
    logic [15:0]     t_pcnt  [NT];
    logic [31:0]     t_cmp   [NT];
    logic [31:0]     t_cnt   [NT];
    for (genvar t = 0; t < NT; t++) begin : g_tmr
        logic tick, wsel;
        assign tick = t_en[t] & (t_pcnt[t] == t_presc[t]);
        assign wsel = wr & hit & (grp == 4'(1 + t));
        assign ev[t] = tick & (t_cnt[t] == t_cmp[t]);
        always_ff @(posedge clk) begin
            if (reset) begin
                t_en[t]    <= 1'b0;
                t_os[t]    <= 1'b0;
                t_presc[t] <= '0;
                t_pcnt[t]  <= '0;
                t_cmp[t]   <= '1;
                t_cnt[t]   <= '0;
            end else begin
                t_pcnt[t] <= (t_en[t] && !tick) ? t_pcnt[t] + 1'b1 : '0;
                if (tick) begin
                    if (t_cnt[t] == t_cmp[t]) begin
                        t_cnt[t] <= '0;
                        if (t_os[t]) t_en[t] <= 1'b0;
                    end else begin
                        t_cnt[t] <= t_cnt[t] + 1'b1;
                    end
                end
                if (wsel) begin                     // a register write wins
                    case (rg)
                        2'd0: begin t_en[t] <= pwdata[0]; t_os[t] <= pwdata[1]; end
                        2'd1: t_presc[t] <= pwdata[15:0];
                        2'd2: t_cmp[t]   <= pwdata;
                        2'd3: t_cnt[t]   <= pwdata;
                    endcase
                end
            end
        end
    end

    // ------------------------------------------------------------ PWM
    logic [15:0]      pwm_presc, pwm_pcnt;
    logic             pwm_tick;
    assign pwm_tick = (pwm_pcnt == pwm_presc);
    always_ff @(posedge clk) begin
        if (reset) pwm_pcnt <= '0;
        else       pwm_pcnt <= pwm_tick ? '0 : pwm_pcnt + 1'b1;
    end

    logic [NPWM-1:0]  p_en, p_pol;
    logic [PWM_W-1:0] p_per_sh [NPWM];
    logic [PWM_W-1:0] p_duty_sh[NPWM];
    logic [PWM_W-1:0] p_per    [NPWM];
    logic [PWM_W-1:0] p_duty   [NPWM];
    logic [PWM_W-1:0] p_cnt    [NPWM];
    for (genvar k = 0; k < NPWM; k++) begin : g_pwm
        logic wrap, wsel;
        assign wrap = p_en[k] & pwm_tick & (p_cnt[k] == p_per[k]);
        assign wsel = wr & hit & (grp == 4'(4 + k));
        assign ev[E_PWM + k] = wrap;
        always_ff @(posedge clk) begin
            if (reset) begin
                p_en[k]      <= 1'b0;
                p_pol[k]     <= 1'b0;
                p_per_sh[k]  <= '0;
                p_duty_sh[k] <= '0;
                p_per[k]     <= '0;
                p_duty[k]    <= '0;
                p_cnt[k]     <= '0;
                pwm_out[k]   <= 1'b0;
            end else begin
                if (!p_en[k] || wrap) begin
                    p_cnt[k]  <= '0;
                    p_per[k]  <= p_per_sh[k];
                    p_duty[k] <= p_duty_sh[k];
                end else if (pwm_tick) begin
                    p_cnt[k] <= p_cnt[k] + 1'b1;
                end
                pwm_out[k] <= p_en[k] ? ((p_cnt[k] < p_duty[k]) ^ p_pol[k]) : p_pol[k];
                if (wsel) begin
                    case (rg)
                        2'd0: begin p_en[k] <= pwdata[0]; p_pol[k] <= pwdata[1]; end
                        2'd1: p_per_sh[k]  <= pwdata[PWM_W-1:0];
                        2'd2: p_duty_sh[k] <= pwdata[PWM_W-1:0];
                        default: ;
                    endcase
                end
            end
        end
    end

    // ------------------------------------------------------------ capture
    logic [NCAP-1:0] c_en, c_rise, c_fall;
    logic [15:0]     c_presc[NCAP];
    logic [15:0]     c_pcnt [NCAP];
    logic [31:0]     c_cnt  [NCAP];
    logic [31:0]     c_capt [NCAP];
    (* ASYNC_REG = "TRUE" *) logic [NCAP-1:0] c_s1, c_s2;
    logic [NCAP-1:0] c_prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            c_s1   <= '0;
            c_s2   <= '0;
            c_prev <= '0;
        end else begin
            c_s1   <= cap_in;
            c_s2   <= c_s1;
            c_prev <= c_s2;
        end
    end
    for (genvar j = 0; j < NCAP; j++) begin : g_cap
        logic tick, wsel, cap;
        assign tick = c_en[j] & (c_pcnt[j] == c_presc[j]);
        assign wsel = wr & hit & (grp == 4'(8 + j));
        assign cap  = c_en[j] & ((c_rise[j] & c_s2[j] & ~c_prev[j]) |
                                 (c_fall[j] & ~c_s2[j] & c_prev[j]));
        assign ev[E_CAP + j] = cap;
        assign ev[E_OVF + j] = cap & status[E_CAP + j];
        always_ff @(posedge clk) begin
            if (reset) begin
                c_en[j]    <= 1'b0;
                c_rise[j]  <= 1'b0;
                c_fall[j]  <= 1'b0;
                c_presc[j] <= '0;
                c_pcnt[j]  <= '0;
                c_cnt[j]   <= '0;
                c_capt[j]  <= '0;
            end else begin
                c_pcnt[j] <= (c_en[j] && !tick) ? c_pcnt[j] + 1'b1 : '0;
                if (!c_en[j])  c_cnt[j] <= '0;
                else if (tick) c_cnt[j] <= c_cnt[j] + 1'b1;
                if (cap)       c_capt[j] <= c_cnt[j];
                if (wsel) begin
                    case (rg)
                        2'd0: begin
                            c_en[j]   <= pwdata[0];
                            c_rise[j] <= pwdata[1];
                            c_fall[j] <= pwdata[2];
                        end
                        2'd1: c_presc[j] <= pwdata[15:0];
                        default: ;
                    endcase
                end
            end
        end
    end

    // ------------------------------------------------------------ global
    logic gsel;
    assign gsel = wr & hit & (grp == 4'd0);
    always_ff @(posedge clk) begin
        if (reset) begin
            status    <= '0;
            ie        <= '0;
            pwm_presc <= '0;
        end else begin
            status <= (status & ~((gsel && rg == 2'd0) ? pwdata[NEV-1:0] : '0)) | ev;
            if (gsel && rg == 2'd1) ie        <= pwdata[NEV-1:0];
            if (gsel && rg == 2'd2) pwm_presc <= pwdata[15:0];
        end
    end
    assign irq = |(status & ie);

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        if (grp == 4'd0) begin
            case (rg)
                2'd0: prdata[NEV-1:0] = status;
                2'd1: prdata[NEV-1:0] = ie;
                2'd2: prdata[15:0]    = pwm_presc;
                default: ;
            endcase
        end
        for (int t = 0; t < NT; t++) if (grp == 4'(1 + t)) begin
            case (rg)
                2'd0: prdata[1:0]  = {t_os[t], t_en[t]};
                2'd1: prdata[15:0] = t_presc[t];
                2'd2: prdata       = t_cmp[t];
                2'd3: prdata       = t_cnt[t];
            endcase
        end
        for (int k = 0; k < NPWM; k++) if (grp == 4'(4 + k)) begin
            case (rg)
                2'd0: prdata[1:0]       = {p_pol[k], p_en[k]};
                2'd1: prdata[PWM_W-1:0] = p_per_sh[k];
                2'd2: prdata[PWM_W-1:0] = p_duty_sh[k];
                2'd3: prdata[PWM_W-1:0] = p_cnt[k];
            endcase
        end
        for (int j = 0; j < NCAP; j++) if (grp == 4'(8 + j)) begin
            case (rg)
                2'd0: prdata[2:0]  = {c_fall[j], c_rise[j], c_en[j]};
                2'd1: prdata[15:0] = c_presc[j];
                2'd2: prdata       = c_cnt[j];
                2'd3: prdata       = c_capt[j];
            endcase
        end
    end

    logic unused;
    assign unused = ^{paddr[31:12], paddr[1:0], pwdata};

endmodule
