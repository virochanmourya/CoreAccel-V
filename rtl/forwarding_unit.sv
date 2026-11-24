// ============================================================================
// Module      : forwarding_unit
// File        : forwarding_unit.sv
// Description : Resolves Read-After-Write (RAW) data hazards by selecting the
//               most recent producer of each EX-stage source operand:
//               10 = EX/MEM result, 01 = MEM/WB (WB) data, 00 = ID/EX operand.
//               Priority: EX/MEM (most recent producer) over MEM/WB.
//
//               The selects are registered: they are computed one cycle early,
//               for the instruction that will be in EX next cycle, from the
//               producers that will then be in EX/MEM and MEM/WB. The EX-stage
//               forwarding muxes then start from a flop instead of the rd/rs
//               compares, which shortens the forward -> branch compare ->
//               redirect and forward -> AGU -> TCM write-enable paths.
//
//               Next cycle, when EX advances (hold = 0):
//                 EX instruction  <- the ID instruction (fields id_rs1/id_rs2)
//                 EX/MEM producer <- the current ID/EX instruction
//                 MEM/WB producer <- the current EX/MEM instruction
//               When EX is held (hold = 1): the EX instruction stays, EX/MEM
//               gets a bubble and MEM/WB <- the current EX/MEM instruction.
//               Under the global MEM stall (freeze = 1) nothing moves, so
//               the selects keep their value.
//
//               Cases where the next-cycle producer is not exactly the current
//               one (its register write is cleared on the way by an exception,
//               or the pipeline is flushed by a trap) only occur when the EX
//               consumer is a bubble or is killed by the trap that cycle, so
//               the select does not matter there. tb/core_sva.sv checks the
//               registered selects against the combinational definition on
//               every cycle where the EX instruction is valid and not killed.
// ============================================================================

module forwarding_unit (
    input  logic       clk,
    input  logic       reset,
    input  logic       hold,              // EX held this cycle (ex_hold)
    input  logic       freeze,            // global MEM stall: nothing moves
    // Next EX instruction's sources (the ID instruction)
    input  logic [4:0] id_rs1,
    input  logic [4:0] id_rs2,
    // Current EX instruction (stays in EX when held; next EX/MEM producer otherwise)
    input  logic [4:0] id_ex_rs1,
    input  logic [4:0] id_ex_rs2,
    input  logic [4:0] id_ex_rd,
    input  logic       id_ex_reg_write,
    // Current EX/MEM instruction (next MEM/WB producer)
    input  logic [4:0] ex_mem_rd,
    input  logic       ex_mem_reg_write,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    function automatic logic [1:0] sel_next(
        input logic [4:0] rs,
        input logic       ex_wr, input logic [4:0] ex_rd,   // next EX/MEM producer
        input logic       wb_wr, input logic [4:0] wb_rd    // next MEM/WB producer
    );
        if (ex_wr && (ex_rd != 5'd0) && (ex_rd == rs))
            sel_next = 2'b10;
        else if (wb_wr && (wb_rd != 5'd0) && (wb_rd == rs))
            sel_next = 2'b01;
        else
            sel_next = 2'b00;
    endfunction

    logic [1:0] fa_d, fb_d;

    always_comb begin
        if (freeze) begin
            // Every pipeline register holds: same consumer, same producers.
            fa_d = forward_a;
            fb_d = forward_b;
        end else if (hold) begin
            // Same EX instruction; EX/MEM becomes a bubble.
            fa_d = sel_next(id_ex_rs1, 1'b0, 5'd0, ex_mem_reg_write, ex_mem_rd);
            fb_d = sel_next(id_ex_rs2, 1'b0, 5'd0, ex_mem_reg_write, ex_mem_rd);
        end else begin
            fa_d = sel_next(id_rs1, id_ex_reg_write, id_ex_rd, ex_mem_reg_write, ex_mem_rd);
            fb_d = sel_next(id_rs2, id_ex_reg_write, id_ex_rd, ex_mem_reg_write, ex_mem_rd);
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            forward_a <= 2'b00;
            forward_b <= 2'b00;
        end else begin
            forward_a <= fa_d;
            forward_b <= fb_d;
        end
    end

endmodule
