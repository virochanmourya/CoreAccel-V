// ============================================================================
// Module      : control_unit_pipe
// File        : control_unit_pipe.sv
// Description : Full RV32I + CUSTOM-0 DSP Control Unit
// ============================================================================

module control_unit_pipe (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    // Standard pipeline control
    output logic       reg_write,
    output logic       alu_src,
    output logic       mem_read,
    output logic       mem_write,
    output logic       mem_to_reg,
    output logic [3:0] alu_control,
    output logic       branch,
    // Extended RV32I control signals
    output logic       alu_src_a,
    output logic       pc_to_reg,
    output logic       jump,
    // DSP control signals
    output logic       is_mac,
    output logic       is_mac_clear,
    output logic       mac_to_reg,
    output logic [1:0] mac_rd_op,      // MAC read: 00 LO, 01 HI, 10 SHIFT, 11 STATUS
    output logic       is_mac_rdshift, // READ_SHIFT (multi-cycle, uses the MAC FSM)
    output logic       rs1_valid,
    output logic       rs2_valid
);

    always_comb begin
        // Deterministic default assignments to prevent latches
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
        mac_rd_op      = 2'b00;
        is_mac_rdshift = 1'b0;
        rs1_valid      = 1'b0;
        rs2_valid      = 1'b0;

        case (opcode)

            // R-type
            7'b0110011: begin
                reg_write   = 1'b1;
                alu_control = {funct7[5], funct3};
                rs1_valid   = 1'b1;
                rs2_valid   = 1'b1;
            end

            // I-type ALU
            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                rs1_valid = 1'b1;
                case (funct3)
                    3'b101:  alu_control = {funct7[5], funct3};
                    default: alu_control = {1'b0, funct3};
                endcase
            end

            // I-type: LW
            7'b0000011: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                mem_read    = 1'b1;
                mem_to_reg  = 1'b1;
                alu_control = 4'b0000;
                rs1_valid   = 1'b1;
            end

            // S-type: SW
            7'b0100011: begin
                alu_src     = 1'b1;
                mem_write   = 1'b1;
                alu_control = 4'b0000;
                rs1_valid   = 1'b1;
                rs2_valid   = 1'b1;
            end

            // B-type
            7'b1100011: begin
                branch    = 1'b1;
                rs1_valid = 1'b1;
                rs2_valid = 1'b1;
            end

            // U-type: LUI
            7'b0110111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_control = 4'b1111;
            end

            // U-type: AUIPC
            7'b0010111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                alu_src_a   = 1'b1;
                alu_control = 4'b0000;
            end

            // J-type: JAL
            7'b1101111: begin
                reg_write = 1'b1;
                pc_to_reg = 1'b1;
                jump      = 1'b1;
            end

            // I-type: JALR
            7'b1100111: begin
                reg_write   = 1'b1;
                alu_src     = 1'b1;
                pc_to_reg   = 1'b1;
                jump        = 1'b1;
                alu_control = 4'b0000;
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
                    3'b011: begin                       // READ_LO
                        mac_to_reg     = 1'b1;
                        mac_rd_op      = 2'b00;
                        reg_write      = 1'b1;
                    end
                    3'b100: begin                       // READ_HI
                        mac_to_reg     = 1'b1;
                        mac_rd_op      = 2'b01;
                        reg_write      = 1'b1;
                    end
                    3'b101: begin                       // READ_SHIFT rd, rs1
                        mac_to_reg     = 1'b1;
                        mac_rd_op      = 2'b10;
                        is_mac_rdshift = 1'b1;
                        reg_write      = 1'b1;
                        rs1_valid      = 1'b1;
                    end
                    3'b110: begin                       // READ_STATUS rd
                        mac_to_reg     = 1'b1;
                        mac_rd_op      = 2'b11;
                        reg_write      = 1'b1;
                    end
                    default: ;
                endcase
            end

            default: ;
        endcase
    end

endmodule
