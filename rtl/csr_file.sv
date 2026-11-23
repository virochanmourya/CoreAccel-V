// ============================================================================
// Module      : csr_file
// File        : csr_file.sv
// Description : Machine-mode CSR file (Zicsr) and counters.
//
//   Access: the CSR instruction in EX reads `rdata` (address from the ID/EX
//   immediate, all sources registers) and, when `we` is high, writes the
//   new value at the EX->MEM edge: RW = src, RS = old | src, RC = old & ~src.
//   The caller only raises `we` on the cycle the instruction leaves EX and is
//   not killed, and only for instructions with write intent.
//
//   Implemented (M-mode only; WARL fields read back legalised):
//     mstatus   MIE[3], MPIE[7] RW; MPP[12:11] = 11 (read-only); rest 0
//     misa      0x4080_1100 (RV32 I M X), writes ignored
//     mie       MTIE[7], MEIE[11] RW; rest 0
//     mip       MTIP[7], MEIP[11] read-only (0 until the interrupt sources exist)
//     mtvec     BASE[31:2] RW, MODE = 00 (direct only)
//     mepc      [31:2] RW, [1:0] = 0 (IALIGN = 32)
//     mcause    [31] and [3:0] RW (WLRL: other bits read 0)
//     mtval, mscratch  32-bit RW
//     mcycle(h), minstret(h)  64-bit RW counters; mcycle counts every cycle,
//               minstret counts retired instructions (instret_inc from WB)
//     cycle(h), instret(h)    read-only shadows (Zicntr)
//     mstatush, mcountinhibit, mhpmcounter3..31(h), mhpmevent3..31,
//     mvendorid, marchid, mimpid, mhartid, mconfigptr: read 0, writes ignored
//   A write to a counter half replaces that half for this cycle (no
//   increment, no carry between halves on that cycle).
// ============================================================================

module csr_file
    import csr_pkg::*;
(
    input  logic        clk,
    input  logic        reset,
    // CSR instruction in EX
    input  logic [11:0] addr,
    input  logic [1:0]  op,          // funct3[1:0]: 01 RW, 10 RS, 11 RC
    input  logic [31:0] wsrc,        // rs1 value or zero-extended uimm
    input  logic        we,          // commit the write this cycle
    output logic [31:0] rdata,
    // Counters
    input  logic        instret_inc  // one instruction retired this cycle
);

    // ---- State ----
    logic        mstatus_mie, mstatus_mpie;
    logic        mie_mtie, mie_meie;
    logic [29:0] mtvec_base;
    logic [29:0] mepc_q;
    logic        mcause_int;
    logic [3:0]  mcause_code;
    logic [31:0] mtval_q, mscratch_q;
    logic [63:0] mcycle_q, minstret_q;

    logic [31:0] mstatus_rd, mie_rd, mip_rd;
    logic [31:0] wdata;
    logic [63:0] mcycle_inc, minstret_inc;

    assign mstatus_rd = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
    assign mie_rd     = {20'b0, mie_meie, 3'b0, mie_mtie, 7'b0};
    assign mip_rd     = 32'b0;

    // ---- Read mux ----
    always_comb begin
        case (addr)
            CSR_MSTATUS:                  rdata = mstatus_rd;
            CSR_MISA:                     rdata = MISA_VALUE;
            CSR_MIE:                      rdata = mie_rd;
            CSR_MTVEC:                    rdata = {mtvec_base, 2'b00};
            CSR_MSCRATCH:                 rdata = mscratch_q;
            CSR_MEPC:                     rdata = {mepc_q, 2'b00};
            CSR_MCAUSE:                   rdata = {mcause_int, 27'b0, mcause_code};
            CSR_MTVAL:                    rdata = mtval_q;
            CSR_MIP:                      rdata = mip_rd;
            CSR_MCYCLE,   CSR_CYCLE:      rdata = mcycle_q[31:0];
            CSR_MCYCLEH,  CSR_CYCLEH:     rdata = mcycle_q[63:32];
            CSR_MINSTRET, CSR_INSTRET:    rdata = minstret_q[31:0];
            CSR_MINSTRETH, CSR_INSTRETH:  rdata = minstret_q[63:32];
            default:                      rdata = 32'b0;   // read-only-zero CSRs
        endcase
    end

    // ---- New value for RW / RS / RC ----
    always_comb begin
        case (op)
            2'b10:   wdata = rdata | wsrc;
            2'b11:   wdata = rdata & ~wsrc;
            default: wdata = wsrc;
        endcase
    end

    assign mcycle_inc   = mcycle_q + 64'd1;
    assign minstret_inc = minstret_q + {63'd0, instret_inc};

    always_ff @(posedge clk) begin
        if (reset) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b0;
            mie_mtie     <= 1'b0;
            mie_meie     <= 1'b0;
            mtvec_base   <= '0;
            mepc_q       <= '0;
            mcause_int   <= 1'b0;
            mcause_code  <= '0;
            mtval_q      <= '0;
            mscratch_q   <= '0;
            mcycle_q     <= '0;
            minstret_q   <= '0;
        end else begin
            // Counters (a CSR write to a half takes precedence this cycle)
            if (we && addr == CSR_MCYCLE)        mcycle_q <= {mcycle_q[63:32], wdata};
            else if (we && addr == CSR_MCYCLEH)  mcycle_q <= {wdata, mcycle_inc[31:0]};
            else                                 mcycle_q <= mcycle_inc;

            if (we && addr == CSR_MINSTRET)       minstret_q <= {minstret_q[63:32], wdata};
            else if (we && addr == CSR_MINSTRETH) minstret_q <= {wdata, minstret_inc[31:0]};
            else                                  minstret_q <= minstret_inc;

            if (we) begin
                case (addr)
                    CSR_MSTATUS: begin
                        mstatus_mie  <= wdata[3];
                        mstatus_mpie <= wdata[7];
                    end
                    CSR_MIE: begin
                        mie_mtie <= wdata[7];
                        mie_meie <= wdata[11];
                    end
                    CSR_MTVEC:    mtvec_base <= wdata[31:2];
                    CSR_MSCRATCH: mscratch_q <= wdata;
                    CSR_MEPC:     mepc_q     <= wdata[31:2];
                    CSR_MCAUSE: begin
                        mcause_int  <= wdata[31];
                        mcause_code <= wdata[3:0];
                    end
                    CSR_MTVAL:    mtval_q    <= wdata;
                    default: ;    // read-only / read-only-zero: ignored
                endcase
            end
        end
    end

endmodule
