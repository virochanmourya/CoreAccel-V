# Single-Cycle RV32I CPU — Implementation Plan

## Goal
Build a **minimal, working single-cycle RV32I processor** in Verilog supporting 5 instructions: `ADD`, `SUB`, `ADDI`, `LW`, `SW`. This is Phase 1 of a DSP-accelerated SoC project.

## Architecture Overview

```
                 +4
                  │
    ┌────┐   ┌───┴───┐   ┌──────────┐   ┌─────────┐
    │ PC ├──►│  IMEM  ├──►│  CONTROL │   │  IMM    │
    └──┬─┘   └───┬───┘   │  UNIT    │   │  GEN    │
       │         │instr   └────┬─────┘   └────┬────┘
       │         │             │ctrl sigs      │imm
       │    ┌────▼────┐        │          ┌────▼────┐
       │    │ REG FILE │◄──────┘          │         │
       │    │ rs1, rs2 ├─────────────────►│  ALU    │
       │    └────┬─────┘                  └────┬────┘
       │         │wr_data                      │result
       │         │◄────────────────────────────┤
       │         │         ┌──────────┐        │
       │         │◄────────┤  DMEM    │◄───────┘
       │                   └──────────┘
       └──────────────────────────────────────────────►
```

## Supported Instructions (5 total)

| Instruction | Type | Opcode    | Operation |
|-------------|------|-----------|-----------|
| `ADD`       | R    | `0110011` | rd = rs1 + rs2 |
| `SUB`       | R    | `0110011` | rd = rs1 - rs2 |
| `ADDI`      | I    | `0010011` | rd = rs1 + imm |
| `LW`        | I    | `0000011` | rd = MEM[rs1+imm] |
| `SW`        | S    | `0100011` | MEM[rs1+imm] = rs2 |

## Proposed File Structure

```
Major Project Phase 1/
├── rtl/
│   ├── pc.v                    # Program Counter
│   ├── instruction_memory.v    # Instruction ROM (hardcoded)
│   ├── register_file.v         # 32x32-bit register file
│   ├── alu.v                   # ALU (add/sub only)
│   ├── imm_gen.v               # Immediate generator
│   ├── control_unit.v          # Main control + ALU control
│   ├── data_memory.v           # Data RAM (read/write)
│   └── cpu_top.v               # Top-level wiring
├── sim/
│   └── cpu_tb.v                # Testbench
└── docs/
    └── architecture.md         # Architecture explanation
```

## Module Descriptions

### 1. `pc.v` — Program Counter
- Holds current instruction address
- Increments by 4 each clock cycle
- Synchronous reset to 0

### 2. `instruction_memory.v` — Instruction ROM
- Read-only, combinational
- Hardcoded with sample program
- Addressed by PC, word-aligned

### 3. `register_file.v` — Register File
- 32 registers × 32 bits
- 2 read ports (combinational), 1 write port (clocked)
- x0 hardwired to 0

### 4. `alu.v` — ALU
- Supports ADD and SUB
- 2-bit control signal selects operation

### 5. `imm_gen.v` — Immediate Generator
- Extracts and sign-extends immediate from instruction
- Handles I-type and S-type formats

### 6. `control_unit.v` — Control Unit
- Decodes opcode + funct3 + funct7
- Generates: RegWrite, MemRead, MemWrite, ALUSrc, MemToReg, ALUOp

### 7. `data_memory.v` — Data Memory
- 256 bytes of read/write memory
- Synchronous write, combinational read

### 8. `cpu_top.v` — Top Module
- Wires all modules together
- Single-cycle datapath

## Test Program
```
ADDI x1, x0, 5      → x1 = 5
ADDI x2, x0, 10     → x2 = 10
ADD  x3, x1, x2     → x3 = 15
```

## Verification Plan

### Automated Tests
- Run `iverilog` to compile all modules + testbench
- Run `vvp` to execute simulation
- Verify register values x1=5, x2=10, x3=15 in `$display` output

### Manual Verification
- Inspect waveforms if needed (VCD dump included)

## Future Expansion Notes
- **Pipelining**: Split into IF → ID → EX → MEM → WB stages with pipeline registers
- **MAC Unit**: Add as a custom ALU operation or coprocessor for DSP acceleration
