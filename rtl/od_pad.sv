// ============================================================================
// Module      : od_pad
// File        : od_pad.sv
// Description : Open-drain bidirectional pad (I2C SCL/SDA).
//               drive_low = 1 pulls the pad to 0; otherwise the pad is
//               released (Z) and an external pull-up sets it high.
//               pad_in is the raw (unsynchronised) pad level.
//               On FPGA this infers an IOBUF/OBUFT; for an ASIC flow it is
//               the single place to substitute an open-drain pad cell.
// ============================================================================

module od_pad (
    input  logic drive_low,
    output logic pad_in,
    inout  wire  pad
);
    assign pad    = drive_low ? 1'b0 : 1'bz;
    assign pad_in = pad;
endmodule
