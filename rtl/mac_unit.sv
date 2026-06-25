// ============================================================================
// Module      : mac_unit
// File        : mac_unit.sv
// Description : TCM-Fed DSP MAC with 64-Bit Signed Saturation
//               Reads operand_a directly and operand_b from the TCM Port B output, which
//               incurs a 1-cycle BRAM latency. The S_INPUT state absorbs this latency:
//               the address is presented in IDLE, data arrives during S_INPUT, and the
//               product is computed at exit.
// ============================================================================

module mac_unit (
    input  logic        clk,
    input  logic        reset,
    input  logic        mac_start,
    input  logic        clear_accum,
    input  logic        mac_abort,        // Pipeline redirect: kill in-flight op
    input  logic signed [31:0] operand_a,
    input  logic signed [31:0] tcm_data,       // Signed weight data from TCM Port B
    output logic signed [63:0] mac_result_full,
    output logic        mac_busy,
    output logic        mac_overflow
  );

  typedef enum logic [1:0] {
            IDLE          = 2'b00,
            S_INPUT       = 2'b01,
            S_MULTIPLY    = 2'b10,
            S_ACCUMULATE  = 2'b11
          } state_t;

  state_t state, next_state;

  // 72-bit signed accumulator saturation limits
  localparam logic signed [71:0] SAT_MAX = {1'b0, {71{1'b1}}};
  localparam logic signed [71:0] SAT_MIN = {1'b1, {71{1'b0}}};

  logic signed [31:0] a_reg;
  logic signed [63:0] product_reg;
  logic signed [71:0] accumulator;
  logic               overflow_flag;

  assign mac_result_full = accumulator[63:0];
  assign mac_busy        = (state != IDLE);
  assign mac_overflow    = overflow_flag;

  always_comb
  begin
    case (state)
      IDLE:
      begin
        if (mac_start)
          next_state = S_INPUT;
        else
          next_state = IDLE;
      end
      S_INPUT:
        next_state = S_MULTIPLY;
      S_MULTIPLY:
        next_state = S_ACCUMULATE;
      S_ACCUMULATE:
        next_state = IDLE;
      default:
        next_state = IDLE;
    endcase
  end

  logic signed [71:0] next_accum_comb;
  logic               next_overflow_comb;

  always_comb begin
    next_accum_comb = accumulator + {{8{product_reg[63]}}, product_reg};
    next_overflow_comb = overflow_flag;

    if ((accumulator[71] == product_reg[63]) &&
        (next_accum_comb[71] != accumulator[71]))
    begin
      next_overflow_comb = 1'b1;
      if (accumulator[71] == 1'b0)
        next_accum_comb = SAT_MAX;
      else
        next_accum_comb = SAT_MIN;
    end
  end

  always_ff @(posedge clk)
  begin
    if (reset || mac_abort)
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
      accumulator   <= 0;
      overflow_flag <= 0;
    end
    else if (!mac_abort)
    begin
      // Gated by !mac_abort to hold registers at last committed values on abort
      case (state)
        // TCM address presented to Port B; BRAM outputs data in S_INPUT
        IDLE:
        begin
          if (mac_start)
          begin
            a_reg <= operand_a;
          end
        end

        // TCM data arrived; compute 64-bit signed product
        S_INPUT:
        begin
          product_reg <= a_reg * tcm_data;
        end

        // Saturating accumulate
        S_MULTIPLY:
        begin
          accumulator <= next_accum_comb;
          overflow_flag <= next_overflow_comb;
        end

        S_ACCUMULATE:
          ;
        default:
          ;
      endcase

      if (clear_accum)
      begin
        accumulator   <= 0;
        overflow_flag <= 0;
      end
    end
  end

endmodule
