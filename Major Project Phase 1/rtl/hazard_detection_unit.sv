// ============================================================================
// Module: hazard_detection_unit
// File:   hazard_detection_unit.sv
//
// PURPOSE:
//   Detects load-use data hazards that the forwarding unit cannot resolve.
//
//   A load-use hazard occurs when a LOAD instruction (LW) is in the EX stage
//   and the immediately following instruction in the ID stage needs the
//   loaded value. The load data is not available until the end of the MEM
//   stage, so a 1-cycle stall (bubble) must be inserted.
//
//   After the stall, the forwarding unit can forward the load result from
//   MEM/WB to the EX stage in the next cycle.
//
//   Stall effects (wired in cpu_pipeline_top.sv):
//     1. pc_write   = ~stall  → PC freezes
//     2. if_id.stall = stall  → IF/ID register holds its value
//     3. id_ex.flush = stall  → NOP bubble inserted into EX stage
//
// INPUTS:
//   id_ex_mem_read - 1 = instruction in EX stage is a load (LW)
//   id_ex_rd [4:0] - Destination register of the load in EX stage
//   if_id_rs1 [4:0] - Source register 1 of instruction in ID stage
//   if_id_rs2 [4:0] - Source register 2 of instruction in ID stage
//
// OUTPUTS:
//   stall - 1 = load-use hazard detected, insert 1-cycle bubble
// ============================================================================

module hazard_detection_unit (
    input  logic       id_ex_mem_read,
    input  logic [4:0] id_ex_rd,
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,
    output logic       stall
);

    always_comb begin
        // Load-use hazard: EX stage has a load whose destination matches
        // a source register of the instruction currently being decoded in ID
        if (id_ex_mem_read
            && (id_ex_rd != 5'd0)
            && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2)))
            stall = 1'b1;
        else
            stall = 1'b0;
    end

endmodule
