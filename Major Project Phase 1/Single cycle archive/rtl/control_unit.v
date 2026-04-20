// ============================================================================
// Module: control_unit
// File:   control_unit.v
//
// PURPOSE:
//   Reads the opcode (and funct3/funct7 for R-type) from the instruction 
//   and generates all control signals that steer the datapath.
//
// INPUTS:
//   opcode  [6:0]  - instruction[6:0]   — identifies instruction type
//   funct3  [2:0]  - instruction[14:12] — sub-type (used for R-type)
//   funct7  [6:0]  - instruction[31:25] — distinguishes ADD from SUB
//
// OUTPUTS:
//   reg_write   - 1 = write result to register file
//   alu_src     - 0 = ALU input B is rs2; 1 = ALU input B is immediate
//   mem_read    - 1 = read from data memory (LW)
//   mem_write   - 1 = write to data memory (SW)
//   mem_to_reg  - 0 = register gets ALU result; 1 = register gets memory data
//   alu_control [1:0] - 00 = ADD, 01 = SUB
// ============================================================================

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,
    output reg        alu_src,
    output reg        mem_read,
    output reg        mem_write,
    output reg        mem_to_reg,
    output reg  [1:0] alu_control
);

    always @(*) begin
        // Default: everything off (safe defaults)
        reg_write   = 1'b0;
        alu_src     = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mem_to_reg  = 1'b0;
        alu_control = 2'b00;

        case (opcode)
            // ---- R-type: ADD, SUB ----
            // opcode = 0110011
            7'b0110011: begin
                reg_write   = 1'b1;     // Write result to rd
                alu_src     = 1'b0;     // ALU input B = rs2
                mem_read    = 1'b0;     // No memory read
                mem_write   = 1'b0;     // No memory write
                mem_to_reg  = 1'b0;     // Write ALU result (not memory)

                // Distinguish ADD vs SUB using funct7
                if (funct7 == 7'b0100000)
                    alu_control = 2'b01; // SUB
                else
                    alu_control = 2'b00; // ADD
            end

            // ---- I-type: ADDI ----
            // opcode = 0010011
            7'b0010011: begin
                reg_write   = 1'b1;     // Write result to rd
                alu_src     = 1'b1;     // ALU input B = immediate
                mem_read    = 1'b0;     // No memory read
                mem_write   = 1'b0;     // No memory write
                mem_to_reg  = 1'b0;     // Write ALU result
                alu_control = 2'b00;    // ADD (rs1 + imm)
            end

            // ---- I-type: LW (Load Word) ----
            // opcode = 0000011
            7'b0000011: begin
                reg_write   = 1'b1;     // Write loaded data to rd
                alu_src     = 1'b1;     // ALU input B = immediate (offset)
                mem_read    = 1'b1;     // Read from data memory
                mem_write   = 1'b0;     // No memory write
                mem_to_reg  = 1'b1;     // Write memory data to register
                alu_control = 2'b00;    // ADD (rs1 + offset = address)
            end

            // ---- S-type: SW (Store Word) ----
            // opcode = 0100011
            7'b0100011: begin
                reg_write   = 1'b0;     // Do NOT write to register file
                alu_src     = 1'b1;     // ALU input B = immediate (offset)
                mem_read    = 1'b0;     // No memory read
                mem_write   = 1'b1;     // Write to data memory
                mem_to_reg  = 1'b0;     // Don't care (no reg write)
                alu_control = 2'b00;    // ADD (rs1 + offset = address)
            end

            // ---- Default: NOP-like behavior ----
            default: begin
                reg_write   = 1'b0;
                alu_src     = 1'b0;
                mem_read    = 1'b0;
                mem_write   = 1'b0;
                mem_to_reg  = 1'b0;
                alu_control = 2'b00;
            end
        endcase
    end

endmodule
