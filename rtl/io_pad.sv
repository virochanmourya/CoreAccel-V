// ============================================================================
// Module      : io_pad
// File        : io_pad.sv
// Description : Tri-state bidirectional pad (GPIO).
//               oe = 1 drives the pad with out; otherwise it is released (Z).
//               pad_in is the raw (unsynchronised) pad level.
//               On FPGA this infers an IOBUF; for an ASIC flow it is the
//               single place to substitute a bidirectional pad cell.
// ============================================================================

module io_pad (
    input  logic oe,
    input  logic out,
    output logic pad_in,
    inout  wire  pad
);
    assign pad    = oe ? out : 1'bz;
    assign pad_in = pad;
endmodule
