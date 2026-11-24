// ============================================================================
// Module      : mac_unit
// File        : mac_unit.sv
// Description : TCM-fed DSP MAC: 72-bit saturating accumulator, saturating
//               readback and a rounding/shifting fixed-point read.
//
//   MAC        acc += operand_a * TCM[rs2]  (32x32 signed, 72-bit acc,
//              saturates at the 72-bit range)
//              The TCM port-B address is presented on the start cycle; the
//              S_INPUT state absorbs the 1-cycle BRAM latency.
//              The 72-bit accumulate is split over two cycles to halve the
//              carry chain: S_MULTIPLY adds the low 36 bits and registers the
//              carry, S_ACCUMULATE adds the high 36 bits, saturates and writes
//              the accumulator. The accumulator is not observable in between
//              (the op holds EX until the unit is idle again).
//   READ_LO/HI sat64(acc)[31:0] / [63:32]  (combinational from acc_sat64)
//   READ_SHIFT sat32(round_half_up(acc >>> shamt)), shamt = rs1[5:0]
//              (multi-cycle: S_RS_ROUND then S_RS_SHIFT; result registered)
//   READ_STATUS {31'b0, overflow}  (from the overflow output)
//   CLEAR      acc = 0, overflow = 0
//
//   overflow is sticky: set when the accumulator saturates, or when a
//   READ_LO/HI (rd64_strobe) or READ_SHIFT had to saturate its result.
//   Only CLEAR clears it.
// ============================================================================

module mac_unit (
    input  logic               clk,
    input  logic               reset,
    input  logic               mac_start,        // 1-cycle start of a multi-cycle op
    input  logic               start_is_shift,   // with mac_start: 1 = READ_SHIFT, 0 = MAC
    input  logic [5:0]         shamt,            // READ_SHIFT amount (sampled at start)
    input  logic               clear_accum,
    input  logic               rd64_strobe,      // a READ_LO/HI is reading acc_sat64 this cycle
    input  logic signed [31:0] operand_a,
    input  logic signed [31:0] tcm_data,         // Signed weight data from TCM Port B
    output logic signed [63:0] mac_result_full,  // acc saturated to signed 64-bit
    output logic        [31:0] read_shift_result,
    output logic               mac_busy,
    output logic               mac_overflow      // sticky
  );

  typedef enum logic [2:0] {
            IDLE          = 3'd0,
            S_INPUT       = 3'd1,
            S_MULTIPLY    = 3'd2,
            S_ACCUMULATE  = 3'd3,
            S_RS_ROUND    = 3'd4,
            S_RS_SHIFT    = 3'd5
          } state_t;

  state_t state, next_state;

  // Saturation bounds (72-bit accumulator)
  localparam logic signed [71:0] SAT_MAX = {1'b0, {71{1'b1}}};
  localparam logic signed [71:0] SAT_MIN = {1'b1, {71{1'b0}}};

  logic signed [31:0] a_reg;
  logic signed [63:0] product_reg;
  logic signed [71:0] accumulator;
  logic        [35:0] acc_lo_sum;      // S_MULTIPLY: low half of acc + product
  logic               acc_lo_carry;    // ... and its carry into bit 36
  logic               overflow_flag;
  logic        [5:0]  shamt_reg;
  logic signed [72:0] rounded_reg;
  logic        [31:0] rs_result_reg;

  assign mac_busy          = (state != IDLE);
  assign mac_overflow      = overflow_flag;
  assign read_shift_result = rs_result_reg;

  // ---------------------------------------------------------------- readback 64
  // acc fits in signed 64 iff acc[71:63] are all equal.
  logic acc_fits64;
  assign acc_fits64      = (accumulator[71:63] == {9{accumulator[71]}});
  assign mac_result_full = acc_fits64 ? accumulator[63:0]
                         : (accumulator[71] ? {1'b1, {63{1'b0}}}     // INT64_MIN
                                            : {1'b0, {63{1'b1}}});   // INT64_MAX

  // ---------------------------------------------------------------- READ_SHIFT
  // Round half up: add 2^(shamt-1) before the arithmetic shift (none for 0).
  logic signed [72:0] round_add;
  logic signed [72:0] shifted;
  logic               rs_fits32;
  assign round_add = (shamt_reg == 6'd0) ? 73'sd0 : (73'sd1 <<< (shamt_reg - 6'd1));
  assign shifted   = rounded_reg >>> shamt_reg;
  assign rs_fits32 = (shifted[72:31] == {42{shifted[72]}});

  // ---------------------------------------------------------------- next state
  always_comb begin
    case (state)
      IDLE:
        if (mac_start)
          next_state = start_is_shift ? S_RS_ROUND : S_INPUT;
        else
          next_state = IDLE;
      S_INPUT:      next_state = S_MULTIPLY;
      S_MULTIPLY:   next_state = S_ACCUMULATE;
      S_ACCUMULATE: next_state = IDLE;
      S_RS_ROUND:   next_state = S_RS_SHIFT;
      S_RS_SHIFT:   next_state = IDLE;
      default:      next_state = IDLE;
    endcase
  end

  // ---------------------------------------------------------------- accumulate
  // Low half (S_MULTIPLY): acc[35:0] + product[35:0] -> acc_lo_sum, acc_lo_carry.
  // High half (S_ACCUMULATE): acc[71:36] + sext(product)[71:36] + carry.
  // product_reg and accumulator are unchanged between the two cycles.
  logic signed [71:0] product_ext;
  logic        [36:0] lo_sum_comb;
  logic        [35:0] hi_sum_comb;
  logic signed [71:0] next_accum_comb;
  logic               accum_saturates;

  assign product_ext = {{8{product_reg[63]}}, product_reg};
  assign lo_sum_comb = {1'b0, accumulator[35:0]} + {1'b0, product_ext[35:0]};
  assign hi_sum_comb = accumulator[71:36] + product_ext[71:36] + {35'd0, acc_lo_carry};

  always_comb begin
    next_accum_comb = {hi_sum_comb, acc_lo_sum};
    accum_saturates = 1'b0;

    // Overflow if both operands share a sign and the result's sign differs
    if ((accumulator[71] == product_reg[63]) &&
        (next_accum_comb[71] != accumulator[71]))
    begin
      accum_saturates = 1'b1;
      if (accumulator[71] == 1'b0)
        next_accum_comb = SAT_MAX;
      else
        next_accum_comb = SAT_MIN;
    end
  end

  always_ff @(posedge clk)
  begin
    if (reset)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_ff @(posedge clk)
  begin
    if (reset)
    begin
      a_reg         <= 0;
      product_reg   <= 0;
      acc_lo_sum    <= 0;
      acc_lo_carry  <= 0;
      accumulator   <= 0;
      overflow_flag <= 0;
      shamt_reg     <= 0;
      rounded_reg   <= 0;
      rs_result_reg <= 0;
    end
    else
    begin
      case (state)
        IDLE:
          if (mac_start) begin
            a_reg     <= operand_a;
            shamt_reg <= shamt;
          end

        // MAC: product from TCM data (arrives after 1-cycle BRAM latency)
        S_INPUT:
          product_reg <= a_reg * tcm_data;

        // Accumulate, low half
        S_MULTIPLY:
        begin
          acc_lo_sum   <= lo_sum_comb[35:0];
          acc_lo_carry <= lo_sum_comb[36];
        end

        // Accumulate, high half + saturation
        S_ACCUMULATE:
        begin
          accumulator <= next_accum_comb;
          if (accum_saturates) overflow_flag <= 1'b1;
        end

        // READ_SHIFT stage 1: add the rounding constant (73-bit, no overflow)
        S_RS_ROUND:
          rounded_reg <= {accumulator[71], accumulator} + round_add;

        // READ_SHIFT stage 2: shift and saturate to signed 32-bit
        S_RS_SHIFT:
        begin
          if (rs_fits32)
            rs_result_reg <= shifted[31:0];
          else begin
            rs_result_reg <= shifted[72] ? 32'h8000_0000 : 32'h7FFF_FFFF;
            overflow_flag <= 1'b1;
          end
        end

        default: ;
      endcase

      // A READ_LO/HI that had to saturate sets the sticky flag
      if (rd64_strobe && !acc_fits64)
        overflow_flag <= 1'b1;

      if (clear_accum)
      begin
        accumulator   <= 0;
        overflow_flag <= 0;
      end
    end
  end

endmodule
