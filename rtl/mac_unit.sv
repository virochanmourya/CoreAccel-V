// ============================================================================
// Module: mac_unit (TCM-Fed DSP MAC with 64-Bit Signed Saturation)
// File:   mac_unit.sv
//
// CHANGE: operand_b replaced by tcm_data. The MAC now reads its second
//         operand from the TCM Port B output (1-cycle BRAM latency).
//         The S_INPUT state absorbs this latency: address is presented
//         in IDLE, data arrives during S_INPUT, product computed at exit.
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

  // 72-bit signed accumulator saturation limits (parameterized, not magic)
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
      state <= IDLE;          // Abort: kill FSM mid-flight → IDLE
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
      // Normal datapath operation (gated by !mac_abort so that an
      // abort holds ALL registers at their last committed values).
      case (state)
        // IDLE: Latch operand_a. TCM address (forwarded_b) is
        // presented to Port B combinationally in this cycle.
        // BRAM will register it at this posedge and output data
        // 1 cycle later (during S_INPUT).
        IDLE:
        begin
          if (mac_start)
          begin
            a_reg <= operand_a;
          end
        end

        // S_INPUT: TCM data has arrived (1-cycle BRAM latency).
        // Compute full 64-bit signed product.
        S_INPUT:
        begin
          product_reg <= a_reg * tcm_data;
        end

        // S_MULTIPLY: Saturating accumulate.
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
    // else: mac_abort asserted — all datapath registers HOLD.
    //       Accumulator retains its last committed value.
    //       In-flight a_reg/product_reg are abandoned (don't-care).
  end

endmodule
