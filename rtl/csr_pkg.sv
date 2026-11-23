// ============================================================================
// Package     : csr_pkg
// File        : csr_pkg.sv
// Description : Machine-mode CSR addresses and the "does this CSR exist"
//               decode, shared by the decoder (illegal-instruction check in
//               ID) and the CSR file (read mux / write decode in EX).
//               Machine mode only: no U/S-mode CSRs (mcounteren, menvcfg,
//               s*/u* CSRs do not exist and are illegal).
// ============================================================================

package csr_pkg;

    localparam logic [11:0] CSR_MSTATUS       = 12'h300;
    localparam logic [11:0] CSR_MISA          = 12'h301;
    localparam logic [11:0] CSR_MIE           = 12'h304;
    localparam logic [11:0] CSR_MTVEC         = 12'h305;
    localparam logic [11:0] CSR_MSTATUSH      = 12'h310;
    localparam logic [11:0] CSR_MCOUNTINHIBIT = 12'h320;
    localparam logic [11:0] CSR_MSCRATCH      = 12'h340;
    localparam logic [11:0] CSR_MEPC          = 12'h341;
    localparam logic [11:0] CSR_MCAUSE        = 12'h342;
    localparam logic [11:0] CSR_MTVAL         = 12'h343;
    localparam logic [11:0] CSR_MIP           = 12'h344;
    localparam logic [11:0] CSR_MCYCLE        = 12'hB00;
    localparam logic [11:0] CSR_MINSTRET      = 12'hB02;
    localparam logic [11:0] CSR_MCYCLEH       = 12'hB80;
    localparam logic [11:0] CSR_MINSTRETH     = 12'hB82;
    localparam logic [11:0] CSR_CYCLE         = 12'hC00;
    localparam logic [11:0] CSR_INSTRET       = 12'hC02;
    localparam logic [11:0] CSR_CYCLEH        = 12'hC80;
    localparam logic [11:0] CSR_INSTRETH      = 12'hC82;
    localparam logic [11:0] CSR_MVENDORID     = 12'hF11;
    localparam logic [11:0] CSR_MARCHID       = 12'hF12;
    localparam logic [11:0] CSR_MIMPID        = 12'hF13;
    localparam logic [11:0] CSR_MHARTID       = 12'hF14;
    localparam logic [11:0] CSR_MCONFIGPTR    = 12'hF15;

    // misa: MXL=1 (RV32), extensions I, M and X (non-standard: CUSTOM-0 MAC).
    localparam logic [31:0] MISA_VALUE = 32'h4080_1100;

    // Read-only-zero ranges: mhpmevent3..31, mhpmcounter3..31(h).
    function automatic logic csr_is_hpm(input logic [11:0] a);
        return ((a >= 12'h323) && (a <= 12'h33F)) ||
               ((a >= 12'hB03) && (a <= 12'hB1F)) ||
               ((a >= 12'hB83) && (a <= 12'hB9F));
    endfunction

    function automatic logic csr_exists(input logic [11:0] a);
        case (a)
            CSR_MSTATUS, CSR_MISA, CSR_MIE, CSR_MTVEC, CSR_MSTATUSH,
            CSR_MCOUNTINHIBIT, CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL,
            CSR_MIP, CSR_MCYCLE, CSR_MINSTRET, CSR_MCYCLEH, CSR_MINSTRETH,
            CSR_CYCLE, CSR_INSTRET, CSR_CYCLEH, CSR_INSTRETH,
            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID,
            CSR_MCONFIGPTR:
                return 1'b1;
            default:
                return csr_is_hpm(a);
        endcase
    endfunction

    // A write to an address with csr[11:10] == 2'b11 is illegal (read-only
    // CSR). Read-only *fields* at read/write addresses are WARL instead.
    // Only a[11:10] matter; the full address is passed for readability.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic csr_addr_ro(input logic [11:0] a);
        return (a[11:10] == 2'b11);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

endpackage
