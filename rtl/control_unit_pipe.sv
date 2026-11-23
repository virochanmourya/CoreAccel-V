// ============================================================================
// Module      : control_unit_pipe
// File        : control_unit_pipe.sv
// Description : RV32IM + Zicsr (traps not yet) + CUSTOM-0 DSP Control Unit.
//               Any encoding the core does not implement is flagged `illegal`
//               and decodes as a bubble: all control outputs are 0, so it has
//               no architectural effect. FENCE (funct3 000) is a legal NOP.
//               Illegal: unknown opcodes (incl. 0x00000000 and compressed),
//               SYSTEM other than the CSR instructions and WFI (ECALL/EBREAK/
//               MRET not yet), a CSR access to an address that does not exist
//               or a write to a read-only CSR address, OP/OP-IMM funct7 values other than
//               0000000, 0100000 (SUB/SRA/SRAI) and 0000001 (M extension, OP only),
//               reserved load/store/branch/JALR/MISC-MEM funct3, and
//               CUSTOM-0 funct3 010/111 or funct7 != 0.
// ============================================================================

module control_unit_pipe
    import csr_pkg::*;
(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [11:0] imm12,     // instr[31:20]: CSR address / SYSTEM function
    input  logic [4:0] rs1_field,  // instr[19:15]: rs1 or CSR uimm
    input  logic [4:0] rd_field,   // instr[11:7]
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
    // M extension: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU (op = funct3)
    output logic       is_muldiv,
    // Zicsr: CSR instruction (op = funct3) and whether it writes the CSR
    output logic       is_csr,
    output logic       csr_we,
    output logic       rs1_valid,
    output logic       rs2_valid,
    // Unsupported / reserved encoding (becomes the illegal-instruction trap cause)
    output logic       illegal
);

    // ---- SYSTEM decode ----
    // CSR ops: funct3 != 000/100. They write the CSR unless they are CSRRS/
    // CSRRC(I) with rs1 = x0 / uimm = 0 (the rs1 field is zero).
    // funct3 000: only WFI (a legal NOP here) for now.
    logic sys_csr, sys_csr_we, sys_wfi;
    assign sys_csr    = (funct3[1:0] != 2'b00);
    assign sys_csr_we = (funct3[1:0] == 2'b01) || (rs1_field != 5'd0);
    assign sys_wfi    = (funct3 == 3'b000) && (imm12 == 12'h105) &&
                        (rs1_field == 5'd0) && (rd_field == 5'd0);

    // ---- Illegal / unsupported encoding decode ----
    always_comb begin
        case (opcode)
            7'b1110011: // SYSTEM
                if (sys_csr)
                    illegal = !csr_exists(imm12) || (sys_csr_we && csr_addr_ro(imm12));
                else
                    illegal = !sys_wfi;
            7'b0110011: // OP: funct7 0000000, 0100000 for SUB/SRA, 0000001 (M: all funct3)
                illegal = !((funct7 == 7'b0000000) ||
                            (funct7 == 7'b0000001) ||
                            (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)));
            7'b0010011: // OP-IMM: shift-immediates constrain funct7
                case (funct3)
                    3'b001:  illegal = (funct7 != 7'b0000000);                            // SLLI
                    3'b101:  illegal = (funct7 != 7'b0000000) && (funct7 != 7'b0100000);  // SRLI/SRAI
                    default: illegal = 1'b0;
                endcase
            7'b0000011: illegal = (funct3 == 3'b011) || (funct3[2:1] == 2'b11);  // LOAD: no LD/LWU/...
            7'b0100011: illegal = (funct3 == 3'b011) || funct3[2];               // STORE: SB/SH/SW only
            7'b1100011: illegal = (funct3[2:1] == 2'b01);                         // BRANCH: 010/011
            7'b1100111: illegal = (funct3 != 3'b000);                             // JALR
            7'b0110111,                                                           // LUI
            7'b0010111,                                                           // AUIPC
            7'b1101111: illegal = 1'b0;                                           // JAL
            7'b0001111: illegal = (funct3 != 3'b000);   // FENCE ok; FENCE.I (Zifencei) not implemented
            7'b0001011: illegal = (funct7 != 7'b0000000) || (funct3 == 3'b010) || (funct3 == 3'b111);
            default:    illegal = 1'b1;                 // SYSTEM, unknown, compressed, all-zero
        endcase
    end

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
        is_muldiv      = 1'b0;
        is_csr         = 1'b0;
        csr_we         = 1'b0;
        rs1_valid      = 1'b0;
        rs2_valid      = 1'b0;

        case (opcode)

            // R-type (funct7 0000001: M extension, result from mul_div)
            7'b0110011: begin
                reg_write   = 1'b1;
                alu_control = {funct7[5], funct3};
                is_muldiv   = (funct7 == 7'b0000001);
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

            // ---- SYSTEM: Zicsr (WFI decodes to all-zero controls: a NOP) ----
            7'b1110011: begin
                if (sys_csr) begin
                    is_csr    = 1'b1;
                    csr_we    = sys_csr_we;
                    reg_write = 1'b1;
                    rs1_valid = !funct3[2];     // register forms read rs1
                end
            end

            default: ;
        endcase

        // An illegal encoding is a bubble: no register, memory, branch or MAC effect.
        if (illegal) begin
            reg_write      = 1'b0;
            mem_read       = 1'b0;
            mem_write      = 1'b0;
            mem_to_reg     = 1'b0;
            branch         = 1'b0;
            jump           = 1'b0;
            pc_to_reg      = 1'b0;
            is_mac         = 1'b0;
            is_mac_clear   = 1'b0;
            mac_to_reg     = 1'b0;
            is_mac_rdshift = 1'b0;
            is_muldiv      = 1'b0;
            is_csr         = 1'b0;
            csr_we         = 1'b0;
            rs1_valid      = 1'b0;
            rs2_valid      = 1'b0;
        end
    end

endmodule
