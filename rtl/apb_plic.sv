// ============================================================================
// Module      : apb_plic
// File        : apb_plic.sv
// Description : RISC-V PLIC, one context (hart 0, M-mode), APB4 slave.
//               Standard register offsets (from the PLIC base):
//                 0x00_0000 + 4*id  priority of source id (PRIO_W bits; 0 = never)
//                 0x00_1000         pending bits (read only)
//                 0x00_2000         enable bits, context 0
//                 0x20_0000         priority threshold, context 0
//                 0x20_0004         claim (read) / complete (write), context 0
//               Any other offset answers PSLVERR. Zero wait states.
//
//   Sources 1..NSRC (NSRC <= 31; source 0 does not exist, its bits read 0).
//   Level-triggered gateways: a high source becomes pending unless it is
//   already pending or claimed and not yet completed. A claim returns the
//   pending, enabled source with the highest priority (ties: lowest id),
//   clears its pending bit and holds the gateway until the complete write
//   with that id; 0 if none. eip (to the core's MEIP) is registered:
//   1 when some pending, enabled source has priority > threshold.
//   Sources must be synchronous to clk (all on-chip peripherals are).
// ============================================================================

module apb_plic #(
    parameter int NSRC   = 16,
    parameter int PRIO_W = 3
)(
    input  logic          clk,
    input  logic          reset,

    // ---- APB4 slave ----
    input  logic          psel,
    input  logic          penable,
    input  logic          pwrite,
    input  logic [31:0]   paddr,
    input  logic [31:0]   pwdata,
    output logic [31:0]   prdata,
    output logic          pready,
    output logic          pslverr,

    input  logic [NSRC:1] src,
    output logic          eip
);

    localparam int IW = $clog2(NSRC + 1);

    logic [PRIO_W-1:0] prio [1:NSRC];
    logic [NSRC:1]     pending, enable, inflight;
    logic [PRIO_W-1:0] threshold;

    // ------------------------------------------------------------ decode
    logic [21:0] off;
    logic        access, wr, rd;
    logic        is_prio, is_pend, is_en, is_thr, is_claim, hit;
    logic [9:0]  prio_id;                 // off[11:2]

    assign off      = paddr[21:0];
    assign access   = psel & penable;
    assign wr       = access & pwrite;
    assign rd       = access & ~pwrite;
    assign prio_id  = off[11:2];
    assign is_prio  = (off[21:12] == 10'h000) & (32'(prio_id) <= NSRC);
    assign is_pend  = (off == 22'h00_1000);
    assign is_en    = (off == 22'h00_2000);
    assign is_thr   = (off == 22'h20_0000);
    assign is_claim = (off == 22'h20_0004);
    assign hit      = is_prio | is_pend | is_en | is_thr | is_claim;
    assign pready   = 1'b1;
    assign pslverr  = ~hit;

    // ------------------------------------------------------------ arbitration
    logic [IW-1:0]     best_id;
    logic [PRIO_W-1:0] best_prio;
    always_comb begin
        best_id   = '0;
        best_prio = '0;
        for (int i = 1; i <= NSRC; i++)
            if (pending[i] && enable[i] && prio[i] > best_prio) begin
                best_id   = IW'(i);
                best_prio = prio[i];
            end
    end

    logic claim_rd, complete_wr;
    assign claim_rd    = rd & is_claim;
    assign complete_wr = wr & is_claim;

    always_ff @(posedge clk) begin
        if (reset) begin
            pending   <= '0;
            inflight  <= '0;
            enable    <= '0;
            threshold <= '0;
            eip       <= 1'b0;
            for (int i = 1; i <= NSRC; i++) prio[i] <= '0;
        end else begin
            for (int i = 1; i <= NSRC; i++) begin
                // gateway
                if (src[i] && !inflight[i]) pending[i] <= 1'b1;
                // claim
                if (claim_rd && best_id == IW'(i)) begin
                    pending[i]  <= 1'b0;
                    inflight[i] <= 1'b1;
                end
                // complete (only an id that was claimed and is enabled)
                if (complete_wr && pwdata[IW-1:0] == IW'(i) && 32'(pwdata) <= NSRC && enable[i])
                    inflight[i] <= 1'b0;
                if (wr && is_prio && prio_id == 10'(i)) prio[i] <= pwdata[PRIO_W-1:0];
            end
            if (wr && is_en)  enable    <= pwdata[NSRC:1];
            if (wr && is_thr) threshold <= pwdata[PRIO_W-1:0];
            eip <= (best_prio > threshold);
        end
    end

    // ------------------------------------------------------------ read mux
    always_comb begin
        prdata = '0;
        if (is_prio && prio_id != 10'd0) prdata = 32'(prio[prio_id[IW-1:0]]);
        else if (is_pend)                prdata = 32'({pending, 1'b0});
        else if (is_en)                  prdata = 32'({enable, 1'b0});
        else if (is_thr)                 prdata = 32'(threshold);
        else if (is_claim)               prdata = 32'(best_id);
    end

    logic unused;
    assign unused = ^{paddr[31:22], paddr[1:0], pwdata};

endmodule
