// ============================================================================
// Module: mac_unit (Multi-Cycle DSP Multiply-Accumulate Unit)
// File:   mac_unit.sv
//
// PURPOSE:
//   A standalone 3-cycle latency Multiply-Accumulate unit designed to sit
//   in the EX stage of the CoreAccel-V pipeline. Maintains its own internal
//   32-bit accumulator register, avoiding modifications to the standard
//   2-read-port register file.
//
//   Behavioral Architecture (Strict 3-Cycle Latency):
//     Cycle 1 — Input Stage:      Latch operand_a and operand_b. Assert busy.
//     Cycle 2 — Multiply Stage:   Compute a_reg * b_reg, latch product.
//     Cycle 3 — Accumulate Stage: accumulator += product. Result valid.
//     (Next edge): busy deasserts. mac_result reflects updated accumulator.
//
//   The design uses the standard Verilog '*' operator to allow Vivado to
//   infer DSP48E1 slices on the target Artix-7. The internal register
//   staging (input → multiply → accumulate) mirrors the DSP48E1 pipeline:
//     AREG/BREG → MREG → PREG
//
// TARGET: Xilinx Artix-7 (xc7a35tcpg236-1) — DSP48E1 inference
// LATCHES: None (all outputs assigned in every branch)
// HIGH-Z:  None (all values deterministic)
//
// INPUTS:
//   clk          - Clock signal
//   reset        - Active-high synchronous reset
//   mac_start    - Triggers the 3-cycle MAC computation
//   clear_accum  - Synchronously resets the accumulator to 0
//   operand_a    [31:0] - First source operand
//   operand_b    [31:0] - Second source operand
//
// OUTPUTS:
//   mac_result   [31:0] - Current value of the internal accumulator
//   mac_busy     - High while computing (3 cycles), Low when IDLE
// ============================================================================

module mac_unit (
    input  logic        clk,
    input  logic        reset,
    input  logic        mac_start,
    input  logic        clear_accum,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic [31:0] mac_result,
    output logic        mac_busy
);

    // ========================================================================
    // FSM State Encoding
    // ========================================================================
    //
    // Four states with explicit 2-bit encoding for deterministic synthesis.
    //
    //   IDLE          — Waiting for mac_start. mac_busy = 0.
    //   S_INPUT       — Operands latched into a_reg, b_reg. mac_busy = 1.
    //   S_MULTIPLY    — Product (a_reg * b_reg) latched. mac_busy = 1.
    //   S_ACCUMULATE  — Accumulator updated. mac_busy = 1.
    //                   On the NEXT edge, state returns to IDLE, busy → 0.
    //
    typedef enum logic [1:0] {
        IDLE          = 2'b00,
        S_INPUT       = 2'b01,
        S_MULTIPLY    = 2'b10,
        S_ACCUMULATE  = 2'b11
    } state_t;

    state_t state, next_state;

    // ========================================================================
    // Internal Datapath Registers
    // ========================================================================

    // Input latch registers (maps to DSP48E1 AREG / BREG)
    logic [31:0] a_reg;
    logic [31:0] b_reg;

    // Partial product pipeline register (maps to DSP48E1 MREG)
    // 64-bit to hold the full unsigned multiply result.
    // Only the lower 32 bits are accumulated (matching RV32 word width).
    logic [63:0] product_reg;

    // Internal accumulator register (maps to DSP48E1 PREG)
    logic [31:0] accumulator;

    // ========================================================================
    // Output Assignments (Continuous — No Latches)
    // ========================================================================

    // mac_result always reflects the current accumulator value.
    // The meaningful read occurs when mac_busy == 0.
    assign mac_result = accumulator;

    // mac_busy is high in any state except IDLE.
    assign mac_busy = (state != IDLE);

    // ========================================================================
    // Combinational Logic: Next-State Function
    // ========================================================================
    //
    // Pure combinational block. Every path through the case assigns
    // next_state, preventing latch inference.
    //
    always_comb begin
        case (state)
            IDLE:         next_state = mac_start ? S_INPUT : IDLE;
            S_INPUT:      next_state = S_MULTIPLY;
            S_MULTIPLY:   next_state = S_ACCUMULATE;
            S_ACCUMULATE: next_state = IDLE;
            default:      next_state = IDLE;  // Unreachable; deterministic fallback
        endcase
    end

    // ========================================================================
    // Sequential Logic: State Register
    // ========================================================================
    //
    // Dedicated always_ff for the state register, separate from the
    // datapath. This ensures clean FSM extraction by synthesis tools.
    //
    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ========================================================================
    // Sequential Logic: Datapath Registers
    // ========================================================================
    //
    // All datapath actions are keyed to the CURRENT state. The action
    // described in each state executes at the posedge that EXITS that state
    // (equivalently, the posedge that transitions to the next state).
    //
    // This staging mirrors the DSP48E1 internal pipeline:
    //   AREG/BREG (Cycle 1) → MREG (Cycle 2) → PREG (Cycle 3)
    //
    // clear_accum is evaluated unconditionally and takes priority over
    // the accumulate update, allowing the accumulator to be cleared
    // at any time regardless of FSM state.
    //
    always_ff @(posedge clk) begin
        if (reset) begin
            // ---- Synchronous reset: zero all internal registers ----
            a_reg       <= 32'd0;
            b_reg       <= 32'd0;
            product_reg <= 64'd0;
            accumulator <= 32'd0;
        end
        else begin
            // ---- Accumulator clear (highest priority over accumulate) ----
            if (clear_accum) begin
                accumulator <= 32'd0;
            end

            // ---- Datapath actions based on current FSM state ----
            case (state)
                // --------------------------------------------------------
                // IDLE: If mac_start is asserted, latch the input operands
                // into internal registers. These will be stable for the
                // multiply in the next cycle even if the external operands
                // change.
                // --------------------------------------------------------
                IDLE: begin
                    if (mac_start) begin
                        a_reg <= operand_a;
                        b_reg <= operand_b;
                    end
                end

                // --------------------------------------------------------
                // S_INPUT: Compute the full 64-bit product of the latched
                // operands and store it in the product pipeline register.
                // The '*' operator allows Vivado to infer DSP48E1 slices.
                // --------------------------------------------------------
                S_INPUT: begin
                    product_reg <= a_reg * b_reg;
                end

                // --------------------------------------------------------
                // S_MULTIPLY: Add the lower 32 bits of the product to the
                // accumulator. If clear_accum is also asserted this cycle,
                // the clear (above) takes priority because it is evaluated
                // first and the tools use last-assignment-wins semantics —
                // but here the accumulate is skipped when clear_accum is
                // active to make the intent explicit and portable.
                // --------------------------------------------------------
                S_MULTIPLY: begin
                    if (!clear_accum) begin
                        accumulator <= accumulator + product_reg[31:0];
                    end
                end

                // --------------------------------------------------------
                // S_ACCUMULATE: No datapath action. The accumulator already
                // holds the updated result (latched at the edge entering
                // this state). The FSM will transition to IDLE on the next
                // edge, deasserting mac_busy.
                // --------------------------------------------------------
                S_ACCUMULATE: begin
                    // Result is valid; nothing to do.
                end

                // --------------------------------------------------------
                // Default: unreachable with 2-bit enum, but included for
                // synthesis safety. No datapath changes.
                // --------------------------------------------------------
                default: begin
                    // No action — deterministic, no latch risk.
                end
            endcase
        end
    end

endmodule
