// ============================================================================
// Module      : mul_div
// File        : mul_div.sv
// Description : RV32M multiply / divide unit (separate from the MAC's
//               multiplier). One operation at a time, started by a 1-cycle
//               `start` pulse that also samples op, operand_a and operand_b.
//
//   op = funct3 of OP / funct7 = 0000001:
//     000 MUL     rs1 * rs2, low 32 bits
//     001 MULH    signed   x signed,   high 32 bits
//     010 MULHSU  signed   x unsigned, high 32 bits
//     011 MULHU   unsigned x unsigned, high 32 bits
//     100 DIV     101 DIVU     110 REM     111 REMU
//
//   MUL family: operands latched sign- or zero-extended to 33 bits, so a
//     single signed 33x33 product covers all four ops. Latency after start:
//     S_MUL (product register) and S_MULOUT (hi/lo select into result) =
//     2 busy cycles. Input, product and result registers let synthesis map
//     the multiply onto DSP48E1 slices with their A/B and M/P registers.
//   DIV family: magnitudes latched, then a radix-2 restoring divider runs a
//     fixed 32 iterations (S_DIV), and S_DIVOUT applies the signs: 33 busy
//     cycles. Special cases follow the RISC-V spec with no extra logic:
//       x / 0      -> quotient all ones (the quotient sign fix is suppressed),
//                     remainder = dividend (remainder takes the dividend sign)
//       INT_MIN/-1 -> quotient INT_MIN (|INT_MIN| = 0x8000_0000 unsigned,
//                     negated back), remainder 0
//
//   busy is registered (state != IDLE). result is written on the last busy
//   cycle, so it is valid on the first cycle busy is low and is held until
//   the next start. No kill input yet: today nothing can interrupt an op
//   held in EX (see design notes for precise traps).
// ============================================================================

module mul_div (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,      // 1-cycle start; op and operands sampled here
    input  logic [2:0]  op,         // funct3
    input  logic [31:0] operand_a,  // rs1
    input  logic [31:0] operand_b,  // rs2
    output logic        busy,
    output logic [31:0] result      // registered
);

    typedef enum logic [2:0] {
        IDLE     = 3'd0,
        S_MUL    = 3'd1,
        S_MULOUT = 3'd2,
        S_DIV    = 3'd3,
        S_DIVOUT = 3'd4
    } state_t;

    state_t state;

    // ---- MUL datapath ----
    logic signed [32:0] mul_a, mul_b;      // 33-bit sign/zero-extended operands
    logic               mul_hi;            // 1: high word (MULH/MULHSU/MULHU)
    /* verilator lint_off UNUSEDSIGNAL */
    logic signed [65:0] mul_full;          // [65:64] are sign copies, unused
    /* verilator lint_on UNUSEDSIGNAL */
    logic        [63:0] product;

    // ---- DIV datapath ----
    logic [31:0] quo;        // dividend shifts out of the top, quotient bits in at the bottom
    logic [31:0] rem;        // partial remainder (always < divisor)
    logic [31:0] dvsr;       // divisor magnitude
    logic [4:0]  count;      // iteration 0..31
    logic        neg_q, neg_r, is_rem;

    logic [32:0] shifted;    // {rem, next dividend bit}: up to 33 bits
    // shifted - dvsr, unsigned, borrow in [33]. When there is no borrow the
    // difference is < dvsr < 2^32, so [32] is always 0 and is not read.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [33:0] diff;
    /* verilator lint_on UNUSEDSIGNAL */

    // ---- Start-cycle operand preparation ----
    logic        a_signed, b_signed;
    logic        a_neg, b_neg;

    assign busy = (state != IDLE);

    // MULH/MULHSU: rs1 signed; MULH only: rs2 signed. MUL (low word) is the
    // same for any signedness. DIV/REM: both signed; DIVU/REMU: unsigned.
    assign a_signed = op[2] ? ~op[0] : (op[1:0] == 2'b01) || (op[1:0] == 2'b10);
    assign b_signed = op[2] ? ~op[0] : (op[1:0] == 2'b01);
    assign a_neg    = a_signed & operand_a[31];
    assign b_neg    = b_signed & operand_b[31];

    assign mul_full = mul_a * mul_b;

    assign shifted  = {rem, quo[31]};
    assign diff     = {1'b0, shifted} - {2'b00, dvsr};

    always_ff @(posedge clk) begin
        if (reset) begin
            state   <= IDLE;
            mul_a   <= '0;
            mul_b   <= '0;
            mul_hi  <= 1'b0;
            product <= '0;
            quo     <= '0;
            rem     <= '0;
            dvsr    <= '0;
            count   <= '0;
            neg_q   <= 1'b0;
            neg_r   <= 1'b0;
            is_rem  <= 1'b0;
            result  <= '0;
        end else begin
            case (state)
                IDLE:
                    if (start) begin
                        if (!op[2]) begin
                            mul_a  <= {a_neg, operand_a};
                            mul_b  <= {b_neg, operand_b};
                            mul_hi <= (op[1:0] != 2'b00);
                            state  <= S_MUL;
                        end else begin
                            quo    <= a_neg ? -operand_a : operand_a;
                            dvsr   <= b_neg ? -operand_b : operand_b;
                            rem    <= '0;
                            count  <= '0;
                            neg_q  <= (a_neg ^ b_neg) & (operand_b != 32'd0);
                            neg_r  <= a_neg;
                            is_rem <= op[1];
                            state  <= S_DIV;
                        end
                    end

                S_MUL: begin
                    product <= mul_full[63:0];
                    state   <= S_MULOUT;
                end

                S_MULOUT: begin
                    result <= mul_hi ? product[63:32] : product[31:0];
                    state  <= IDLE;
                end

                // One restoring step per cycle: shift in the next dividend
                // bit; subtract the divisor if it fits.
                S_DIV: begin
                    if (!diff[33]) begin
                        rem <= diff[31:0];
                        quo <= {quo[30:0], 1'b1};
                    end else begin
                        rem <= shifted[31:0];
                        quo <= {quo[30:0], 1'b0};
                    end
                    count <= count + 5'd1;
                    if (count == 5'd31)
                        state <= S_DIVOUT;
                end

                S_DIVOUT: begin
                    if (is_rem)
                        result <= neg_r ? -rem : rem;
                    else
                        result <= neg_q ? -quo : quo;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
