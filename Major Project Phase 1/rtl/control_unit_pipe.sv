// ============================================================================
// Module: control_unit_pipe (Pipeline Control Unit with Branch Support)
// File:   control_unit_pipe.sv
//
// PURPOSE:
//   SystemVerilog rewrite of control_unit.v with B-type branch decoding added.
//   Reads the opcode (and funct3/funct7 for R-type) from the instruction
//   and generates all control signals that steer the datapath.
//
//   New vs. original control_unit.v:
//     - Adds 'branch' output signal for BEQ/BNE instructions
//     - Adds B-type opcode case (7'b1100011)
//     - Uses SystemVerilog constructs (logic, always_comb)
//
// INPUTS:
//   opcode  [6:0]  - instruction[6:0]   — identifies instruction type
//   funct3  [2:0]  - instruction[14:12] — sub-type
//   funct7  [6:0]  - instruction[31:25] — distinguishes ADD from SUB
//
// OUTPUTS:
//   reg_write        - 1 = write result to register file
//   alu_src          - 0 = ALU input B is rs2; 1 = ALU input B is immediate
//   mem_read         - 1 = read from data memory (LW)
//   mem_write        - 1 = write to data memory (SW)
//   mem_to_reg       - 0 = register gets ALU result; 1 = register gets mem data
//   alu_control [1:0] - 00 = ADD, 01 = SUB
//   branch           - 1 = instruction is a conditional branch (BEQ/BNE)
// ============================================================================

module control_unit_pipe (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic       reg_write,
    output logic       alu_src,
    output logic       mem_read,
    output logic       mem_write,
    output logic       mem_to_reg,
    output logic [1:0] alu_control,
    output logic       branch,
    // New DSP Control Signals
    output logic       is_mac,
    output logic       is_mac_clear,
    output logic       mac_to_reg
);

    always_comb begin
        // Default: everything off, deterministic zeros (no high-impedance)
        reg_write       = 1'b0;
        alu_src         = 1'b0;
        mem_read        = 1'b0;
        mem_write       = 1'b0;
        mem_to_reg      = 1'b0;
        alu_control     = 2'b00;
        branch          = 1'b0;
        is_mac          = 1'b0;
        is_mac_clear    = 1'b0;
        mac_to_reg      = 1'b0;

        case (opcode)
            // ---- R-type: ADD, SUB ----
            7'b0110011: begin
                reg_write   = 1'b1;
                alu_src     = 1'b0;     // ALU input B = rs2
                mem_to_reg  = 1'b0;     // Write ALU result

                // Distinguish ADD vs SUB using funct7
                if (funct7 == 7'b0100000)
                    alu_control = 2'b01; // SUB
                else
                    alu_control = 2'b00; // ADD
            end

            // ---- I-type: ADDI ----
            7'b0010011: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;     // ALU input B = immediate
                mem_to_reg  = 1'b0;     // Write ALU result
                alu_control = 2'b00;    // ADD (rs1 + imm)
            end

            // ---- I-type: LW (Load Word) ----
            7'b0000011: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;     // ALU input B = immediate (offset)
                mem_read    = 1'b1;
                mem_to_reg  = 1'b1;     // Write memory data to register
                alu_control = 2'b00;    // ADD (rs1 + offset = address)
            end

            // ---- S-type: SW (Store Word) ----
            7'b0100011: begin
                alu_src     = 1'b1;     // ALU input B = immediate (offset)
                mem_write   = 1'b1;
                alu_control = 2'b00;    // ADD (rs1 + offset = address)
            end

            // ---- B-type: BEQ, BNE ----
            7'b1100011: begin
                branch      = 1'b1;     // This IS a branch instruction
                // ALU is not used for branch comparison (dedicated comparator)
                // All other signals remain at safe defaults (0)
                // alu_control = 2'b00 deterministic (no z)
            end

            // --------------------------------------------------------
            // CUSTOM-0 Space: CoreAccel-V DSP Extensions
            // --------------------------------------------------------
            7'b0001011: begin 
                // Default base signals for custom ops
                branch   = 1'b0;
                mem_read = 1'b0;
                mem_write= 1'b0;
                alu_src  = 1'b0; // Not using main ALU

                case (funct3)
                    3'b000: begin // MAC rs1, rs2
                        is_mac       = 1;
                        is_mac_clear = 0;
                        mac_to_reg   = 0;
                        reg_write    = 0; 
                    end
                    
                    3'b001: begin // MAC_CLEAR
                        is_mac       = 0;
                        is_mac_clear = 1;
                        mac_to_reg   = 0;
                        reg_write    = 0;
                    end
                    
                    3'b010: begin // MAC_READ rd
                        is_mac       = 0;
                        is_mac_clear = 0;
                        mac_to_reg   = 1;
                        reg_write    = 1; // We are writing the MAC result to the RegFile
                    end
                    
                    default: begin
                        is_mac       = 0;
                        is_mac_clear = 0;
                        mac_to_reg   = 0;
                        reg_write    = 0;
                    end
                endcase
            end


            // ---- Default: NOP-like behavior ----
            default: begin
                // All outputs already set to 0 by defaults above
            end
        endcase
    end

endmodule
