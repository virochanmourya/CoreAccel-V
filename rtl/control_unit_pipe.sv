// ============================================================================
// Module: control_unit_pipe (Full RV32I + CUSTOM-0 DSP)
// File:   control_unit_pipe.sv
// ============================================================================

module control_unit_pipe (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    // Standard pipeline control
    output logic       reg_write,
    output logic       alu_src,        // 0=rs2, 1=immediate for ALU input B
    output logic       mem_read,
    output logic       mem_write,
    output logic       mem_to_reg,
    output logic [3:0] alu_control,    // {funct7[5], funct3} encoding
    output logic       branch,
    // New RV32I control signals
    output logic       alu_src_a,      // 0=rs1, 1=PC for ALU input A (AUIPC)
    output logic       pc_to_reg,      // 1=write PC+4 to rd (JAL/JALR)
    output logic       jump,           // 1=unconditional PC redirect (JAL/JALR)
    // DSP control signals
    output logic       is_mac,
    output logic       is_mac_clear,
    output logic       mac_to_reg,
    output logic       is_mac_read_hi,
    output logic       rs1_valid,
    output logic       rs2_valid
);

    always_comb begin
        // Deterministic defaults — no z, no latches
        reg_write      = 1'b0;
        alu_src        = 1'b0;
        mem_read       = 1'b0;
        mem_write      = 1'b0;
        mem_to_reg     = 1'b0;
        alu_control    = 4'b0000;
        branch         = 1'b0;
        alu_src_a      = 1'b0;
        pc_to_reg      = 1'b0;
        jump           = 1'b0;
        is_mac         = 1'b0;
        is_mac_clear   = 1'b0;
        mac_to_reg     = 1'b0;
        is_mac_read_hi = 1'b0;
        rs1_valid      = 1'b0;
        rs2_valid      = 1'b0;

        case (opcode)

            // ---- R-type: ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND ----
            7'b0110011: begin
                reg_write   = 1'b1;
                alu_control = {funct7[5], funct3};
                rs1_valid   = 1'b1;
                rs2_valid   = 1'b1;
            end

            // ---- I-type ALU: ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI ----
            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                rs1_valid = 1'b1;
                case (funct3)
                    3'b101:  alu_control = {funct7[5], funct3}; // SRLI or SRAI
                    default: alu_control = {1'b0, funct3};
                endcase
            end

            // ---- I-type: LW ----
            7'b0000011: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                mem_read    = 1'b1;
                mem_to_reg  = 1'b1;
                alu_control = 4'b0000;
                rs1_valid   = 1'b1;
            end

            // ---- S-type: SW ----
            7'b0100011: begin
                alu_src     = 1'b1;
                mem_write   = 1'b1;
                alu_control = 4'b0000;
                rs1_valid   = 1'b1;
                rs2_valid   = 1'b1;
            end

            // ---- B-type: BEQ/BNE/BLT/BGE/BLTU/BGEU ----
            7'b1100011: begin
                branch    = 1'b1;
                rs1_valid = 1'b1;
                rs2_valid = 1'b1;
            end

            // ---- U-type: LUI ----
            7'b0110111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_control = 4'b1111;  // PASS_B
            end

            // ---- U-type: AUIPC ----
            7'b0010111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_src_a   = 1'b1;     // ALU input A = PC
                alu_control = 4'b0000;  // ADD: PC + U-imm
            end

            // ---- J-type: JAL ----
            7'b1101111: begin
                reg_write = 1'b1;
                pc_to_reg = 1'b1;       // WB = PC+4
                jump      = 1'b1;
            end

            // ---- I-type: JALR ----
            7'b1100111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;     // ALU B = immediate
                pc_to_reg   = 1'b1;     // WB = PC+4
                jump        = 1'b1;
                alu_control = 4'b0000;  // ADD: rs1 + imm = target
                rs1_valid   = 1'b1;
            end

            // ---- CUSTOM-0: DSP MAC ----
            7'b0001011: begin
                case (funct3)
                    3'b000: begin
                        is_mac = 1'b1;
                        rs1_valid = 1'b1;
                        rs2_valid = 1'b1;
                    end
                    3'b001: is_mac_clear = 1'b1;
                    3'b011: begin
                        mac_to_reg     = 1'b1;
                        is_mac_read_hi = 1'b0;
                        reg_write      = 1'b1;
                    end
                    3'b100: begin
                        mac_to_reg     = 1'b1;
                        is_mac_read_hi = 1'b1;
                        reg_write      = 1'b1;
                    end
                    default: ;
                endcase
            end

            default: ;
        endcase
    end

endmodule
