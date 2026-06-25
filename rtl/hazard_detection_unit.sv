// ============================================================================
// Module      : hazard_detection_unit
// File        : hazard_detection_unit.sv
// Description : Detects Load-Use hazards. Asserts stall if an instruction in
//               the EX stage is a Load (LW) and the ID stage needs its
//               destination register.
//               Note: Multi-cycle DSP stalls are handled explicitly in
//               cpu_pipeline_top.sv
// ============================================================================

module hazard_detection_unit (
    input  logic       id_ex_mem_read,
    input  logic [4:0] id_ex_rd,
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,
    input  logic       rs1_valid,
    input  logic       rs2_valid,
    output logic       stall
);

    always_comb begin
        // Load-Use Hazard Detection Condition:
        // 1. The instruction in the EX stage is a memory read (LW)
        // 2. Its destination register matches either source register of the ID stage instruction
        // 3. The destination register is not x0
        
        if (id_ex_mem_read 
            && (id_ex_rd != 5'd0) 
            && ((rs1_valid && (id_ex_rd == if_id_rs1)) || 
                (rs2_valid && (id_ex_rd == if_id_rs2)))) begin
            stall = 1'b1;
        end 
        
        else begin
            stall = 1'b0;
        end
        
    end

endmodule