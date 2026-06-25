// ============================================================================
// Module      : alu
// File        : alu.sv
// Description : Full RV32I Arithmetic Logic Unit. Purely combinational.
//               Generates condition flags (zero, sign, overflow, carry) for
//               branch resolution and diagnostics.
//               Xilinx Artix-7 (xc7a35tcpg236-1)
// ============================================================================

module alu (
    input  logic [31:0] alu_in1,
    input  logic [31:0] alu_in2,
    input  logic [3:0]  alu_control,
    output logic [31:0] alu_result,
    output logic        zero,
    output logic        sign,
    output logic        overflow,
    output logic        carry
);

    // ========================================================================
    // Internal: 33-bit extended result for carry/borrow extraction
    // ========================================================================
    // Extracts unsigned carry-out for ADD and borrow for SUB.

    logic [32:0] add_result;
    logic [32:0] sub_result;

    assign add_result = {1'b0, alu_in1} + {1'b0, alu_in2};
    assign sub_result = {1'b0, alu_in1} - {1'b0, alu_in2};

    // ========================================================================
    // Internal: Signed overflow detection
    // ========================================================================

    logic add_overflow;
    logic sub_overflow;

    assign add_overflow = (~alu_in1[31] & ~alu_in2[31] &  add_result[31])
                        | ( alu_in1[31] &  alu_in2[31] & ~add_result[31]);

    assign sub_overflow = (~alu_in1[31] &  alu_in2[31] &  sub_result[31])
                        | ( alu_in1[31] & ~alu_in2[31] & ~sub_result[31]);

    // ========================================================================
    // Combinational Logic: ALU Operation Selection
    // ========================================================================

    always_comb begin
        alu_result = 32'd0;
        overflow   = 1'b0;
        carry      = 1'b0;

        case (alu_control)

            // ADD
            4'b0000: begin
                alu_result = add_result[31:0];
                overflow   = add_overflow;
                carry      = add_result[32];
            end

            // SUB
            4'b1000: begin
                alu_result = sub_result[31:0];
                overflow   = sub_overflow;
                carry      = ~sub_result[32];
            end

            // SLL
            4'b0001: begin
                alu_result = alu_in1 << alu_in2[4:0];
            end

            // SLT
            4'b0010: begin
                alu_result = ($signed(alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0;
            end

            // SLTU
            4'b0011: begin
                alu_result = (alu_in1 < alu_in2) ? 32'd1 : 32'd0;
            end

            // XOR
            4'b0100: begin
                alu_result = alu_in1 ^ alu_in2;
            end

            // SRL
            4'b0101: begin
                alu_result = alu_in1 >> alu_in2[4:0];
            end

            // SRA
            4'b1101: begin
                alu_result = $signed(alu_in1) >>> alu_in2[4:0];
            end

            // OR
            4'b0110: begin
                alu_result = alu_in1 | alu_in2;
            end

            // AND
            4'b0111: begin
                alu_result = alu_in1 & alu_in2;
            end

            // PASS_B
            4'b1111: begin
                alu_result = alu_in2;
            end

            default: begin
                alu_result = 32'd0;
            end

        endcase
    end

    // ========================================================================
    // Flag Generation (Continuous Assignments — Always Valid)
    // ========================================================================

    assign zero = (alu_result == 32'd0);
    assign sign = alu_result[31];

endmodule
