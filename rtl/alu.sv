// ============================================================================
// Module: alu (Full RV32I Arithmetic Logic Unit)
// File:   alu.sv
//
// PURPOSE:
//   Purely combinational ALU supporting all RV32I base integer operations.
//   Replaces the original 2-bit alu.v with a 4-bit alu_control interface.
//
//   Generates four condition flags for branch resolution and diagnostics:
//     zero     — result is zero (used by BEQ/BNE)
//     sign     — MSB of result (used by BLT/BGE)
//     overflow — signed overflow (valid for ADD/SUB only)
//     carry    — unsigned carry-out (ADD) / borrow (SUB)
//
// ENCODING:
//   alu_control is derived from {funct7[5], funct3} in the control unit.
//   This maps naturally to the RV32I instruction encoding.
//
//   alu_control | Operation | Description
//   ------------|-----------|----------------------------------
//    4'b0000    | ADD       | alu_in1 + alu_in2
//    4'b1000    | SUB       | alu_in1 - alu_in2
//    4'b0001    | SLL       | alu_in1 << alu_in2[4:0]
//    4'b0010    | SLT       | (signed)alu_in1 < (signed)alu_in2 ? 1 : 0
//    4'b0011    | SLTU      | (unsigned)alu_in1 < (unsigned)alu_in2 ? 1 : 0
//    4'b0100    | XOR       | alu_in1 ^ alu_in2
//    4'b0101    | SRL       | alu_in1 >> alu_in2[4:0]  (logical)
//    4'b1101    | SRA       | alu_in1 >>> alu_in2[4:0] (arithmetic)
//    4'b0110    | OR        | alu_in1 | alu_in2
//    4'b0111    | AND       | alu_in1 & alu_in2
//    4'b1111    | PASS_B    | alu_in2 (pass-through for LUI routing)
//
// SYNTHESIS:
//   - Pure always_comb — zero latch risk
//   - Zero high-impedance states
//   - $signed() used explicitly for SRA and SLT
//
// TARGET: Xilinx Artix-7 (xc7a35tcpg236-1)
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
    //
    // By computing a 33-bit addition/subtraction, the MSB (bit [32]) is the
    // unsigned carry-out for ADD, or the INVERTED borrow for SUB.
    //
    // For SUB (A - B), we compute A + (~B) + 1 (two's complement):
    //   - If A >= B (unsigned): no borrow → carry-out = 1
    //   - If A <  B (unsigned): borrow    → carry-out = 0
    // This matches the ARM/x86 convention where the carry flag after SUB
    // indicates "no borrow" when set. We invert it so carry=1 means
    // "borrow occurred" (more intuitive for RISC-V SLTU-like checks).
    //

    logic [32:0] add_result;
    logic [32:0] sub_result;

    // Extend to 33 bits with a leading zero for unsigned carry extraction
    assign add_result = {1'b0, alu_in1} + {1'b0, alu_in2};
    assign sub_result = {1'b0, alu_in1} - {1'b0, alu_in2};

    // ========================================================================
    // Internal: Signed overflow detection (valid for ADD and SUB only)
    // ========================================================================
    //
    // ADD overflow: both operands same sign, result has different sign
    //   (+) + (+) = (-)  or  (-) + (-) = (+)
    //
    // SUB overflow: operands have different signs, result sign differs from A
    //   (+) - (-) = (-)  or  (-) - (+) = (+)
    //
    // We compute both and select based on alu_control.
    //

    logic add_overflow;
    logic sub_overflow;

    assign add_overflow = (~alu_in1[31] & ~alu_in2[31] &  add_result[31])   // (+)+(+)=(-)
                        | ( alu_in1[31] &  alu_in2[31] & ~add_result[31]);  // (-)+(-)=(+)

    assign sub_overflow = (~alu_in1[31] &  alu_in2[31] &  sub_result[31])   // (+)-(-)=(-)
                        | ( alu_in1[31] & ~alu_in2[31] & ~sub_result[31]);  // (-)-( +)=(+)

    // ========================================================================
    // Combinational Logic: ALU Operation Selection
    // ========================================================================

    always_comb begin
        // ---- Deterministic defaults: no latch, no z ----
        alu_result = 32'd0;
        overflow   = 1'b0;
        carry      = 1'b0;

        case (alu_control)

            // ---- ADD: rs1 + rs2 / rs1 + imm ----
            4'b0000: begin
                alu_result = add_result[31:0];
                overflow   = add_overflow;
                carry      = add_result[32];  // Unsigned carry-out
            end

            // ---- SUB: rs1 - rs2 ----
            4'b1000: begin
                alu_result = sub_result[31:0];
                overflow   = sub_overflow;
                // Borrow flag: In unsigned subtraction (A - B):
                //   sub_result[32] = 1 when A >= B (no borrow, carry-out of ~B+1)
                //   sub_result[32] = 0 when A <  B (borrow occurred)
                // We INVERT so carry=1 means "borrow occurred":
                carry      = ~sub_result[32];
            end

            // ---- SLL: Shift Left Logical ----
            // Shift amount is the lower 5 bits of alu_in2 (RV32I spec §2.6)
            4'b0001: begin
                alu_result = alu_in1 << alu_in2[4:0];
            end

            // ---- SLT: Set Less Than (Signed) ----
            // Uses $signed() to perform a signed comparison
            4'b0010: begin
                alu_result = ($signed(alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0;
            end

            // ---- SLTU: Set Less Than (Unsigned) ----
            4'b0011: begin
                alu_result = (alu_in1 < alu_in2) ? 32'd1 : 32'd0;
            end

            // ---- XOR ----
            4'b0100: begin
                alu_result = alu_in1 ^ alu_in2;
            end

            // ---- SRL: Shift Right Logical ----
            4'b0101: begin
                alu_result = alu_in1 >> alu_in2[4:0];
            end

            // ---- SRA: Shift Right Arithmetic ----
            // $signed() is CRITICAL: the >>> operator only sign-extends
            // when the left operand is a signed type. Without $signed(),
            // Verilog/SystemVerilog treats it as a logical shift.
            4'b1101: begin
                alu_result = $signed(alu_in1) >>> alu_in2[4:0];
            end

            // ---- OR ----
            4'b0110: begin
                alu_result = alu_in1 | alu_in2;
            end

            // ---- AND ----
            4'b0111: begin
                alu_result = alu_in1 & alu_in2;
            end

            // ---- PASS_B: Pass-through for LUI ----
            // Outputs alu_in2 directly. The immediate generator provides
            // the upper-20-bit immediate, which is passed through the ALU
            // to the register file via the standard WB path.
            4'b1111: begin
                alu_result = alu_in2;
            end

            // ---- Default: deterministic zero (no z, no latch) ----
            default: begin
                alu_result = 32'd0;
            end

        endcase
    end

    // ========================================================================
    // Flag Generation (Continuous Assignments — Always Valid)
    // ========================================================================

    // Zero flag: 1 when the result is all zeros.
    // Used by BEQ (branch if zero) and BNE (branch if not zero).
    assign zero = (alu_result == 32'd0);

    // Sign flag: MSB of the result.
    // Indicates a negative result in two's complement representation.
    // Used by BLT/BGE branch conditions (in combination with overflow).
    assign sign = alu_result[31];

endmodule
