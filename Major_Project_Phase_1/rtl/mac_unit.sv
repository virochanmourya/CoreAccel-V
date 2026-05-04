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
    input  logic [31:0] operand_a,
    input  logic [31:0] tcm_data,       // CHANGED: from operand_b — fed by TCM Port B
    output logic [63:0] mac_result_full,
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

    logic signed [31:0] a_reg;
    logic signed [63:0] product_reg;
    logic signed [63:0] accumulator;
    logic               overflow_flag;
    logic signed [63:0] next_accum;

    assign mac_result_full = accumulator;
    assign mac_busy        = (state != IDLE);
    assign mac_overflow    = overflow_flag;

    always_comb begin
        case (state)
            IDLE:         begin if (mac_start) next_state = S_INPUT; else next_state = IDLE; end
            S_INPUT:      next_state = S_MULTIPLY;
            S_MULTIPLY:   next_state = S_ACCUMULATE;
            S_ACCUMULATE: next_state = IDLE;
            default:      next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) state <= IDLE;
        else       state <= next_state;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            a_reg         <= 0;
            product_reg   <= 0;
            accumulator   <= 0;
            overflow_flag <= 0;
        end
        else begin
            case (state)
                // IDLE: Latch operand_a. TCM address (forwarded_b) is
                // presented to Port B combinationally in this cycle.
                // BRAM will register it at this posedge and output data
                // 1 cycle later (during S_INPUT).
                IDLE: begin
                    if (mac_start) begin
                        a_reg <= $signed(operand_a);
                    end
                end

                // S_INPUT: TCM data has arrived (1-cycle BRAM latency).
                // Compute full 64-bit signed product.
                S_INPUT: begin
                    product_reg <= $signed(a_reg) * $signed(tcm_data);
                end

                // S_MULTIPLY: Saturating accumulate.
                S_MULTIPLY: begin
                    next_accum = accumulator + product_reg;

                    if ((accumulator[63] == product_reg[63]) &&
                        (next_accum[63] != accumulator[63])) begin
                        overflow_flag <= 1'b1;
                        if (accumulator[63] == 1'b0)
                            accumulator <= 64'h7FFFFFFFFFFFFFFF;
                        else
                            accumulator <= 64'h8000000000000000;
                    end else begin
                        accumulator <= next_accum;
                    end
                end

                S_ACCUMULATE: ;
                default: ;
            endcase

            if (clear_accum) begin
                accumulator   <= 0;
                overflow_flag <= 0;
            end
        end
    end

endmodule