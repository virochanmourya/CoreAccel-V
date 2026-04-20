# 5-Stage Pipelined RV32I CPU — Pipeline Architecture

## Overview

This document describes the 5-stage in-order pipeline architecture that replaces the single-cycle datapath. The pipeline implements:
- **Instruction Fetch (IF)** → **Instruction Decode (ID)** → **Execute (EX)** → **Memory Access (MEM)** → **Write Back (WB)**
- **Data forwarding** (EX/MEM → EX, MEM/WB → EX) for RAW hazard resolution
- **Load-use stall detection** (1-cycle bubble insertion)
- **Branch resolution in EX** (BEQ/BNE with 2-cycle flush penalty)
- **WB-to-ID register bypass** for same-cycle write/read correctness

## Pipeline Datapath

```
                                    ┌──────────────────────┐
                                    │   Hazard Detection   │
                                    │   Unit               │── stall ──┐
                                    └──────────┬───────────┘           │
                                               │                      │
    ┌─────────┐     ┌──────────┐     ┌─────────┴──┐     ┌──────────┐  │
    │         │     │          │     │            │     │          │  │
    │   IF    │────►│  IF/ID   │────►│    ID      │────►│  ID/EX   │──┘
    │  stage  │     │  reg     │     │   stage    │     │  reg     │
    │         │     │          │     │            │     │          │
    └────┬────┘     └──────────┘     └────────────┘     └─────┬────┘
         │                                                     │
    ┌────┴────┐                                          ┌─────┴────┐
    │  PC     │◄──── pc_branch ◄──── Branch Comparator ◄─┤   EX     │
    │  pipe   │                      (EX stage)          │  stage   │
    └─────────┘                                          └─────┬────┘
                                                               │
    ┌──────────┐     ┌──────────┐     ┌──────────┐      ┌─────┴────┐
    │          │     │          │     │          │      │          │
    │   WB     │◄────│  MEM/WB  │◄────│   MEM    │◄─────│  EX/MEM  │
    │  stage   │     │  reg     │     │  stage   │      │  reg     │
    │          │     │          │     │          │      │          │
    └──────────┘     └──────────┘     └──────────┘      └──────────┘
         │                                                     │
         │              ┌──────────────────┐                   │
         └─────────────►│  Forwarding Unit │◄──────────────────┘
           wb_data      └────────┬─────────┘  ex_mem_alu_result
                                 │
                          forward_a, forward_b
                                 │
                                 ▼
                         (to EX stage muxes)
```

## Pipeline Register Contents

### IF/ID Register
| Field | Width | Description |
|-------|-------|-------------|
| `pc` | 32 | PC of the fetched instruction |
| `instruction` | 32 | The 32-bit instruction word |

### ID/EX Register
| Field | Width | Description |
|-------|-------|-------------|
| `reg_write` | 1 | WB: enable register write |
| `mem_to_reg` | 1 | WB: select memory data vs ALU result |
| `mem_read` | 1 | MEM: enable data memory read |
| `mem_write` | 1 | MEM: enable data memory write |
| `alu_src` | 1 | EX: select rs2 vs immediate for ALU input B |
| `alu_control` | 2 | EX: ALU operation (00=ADD, 01=SUB) |
| `branch` | 1 | EX: this is a conditional branch |
| `pc` | 32 | PC of this instruction (for branch target calc) |
| `rs1_data` | 32 | Register rs1 value (with WB-to-ID bypass) |
| `rs2_data` | 32 | Register rs2 value (with WB-to-ID bypass) |
| `imm` | 32 | Sign-extended immediate |
| `rs1_addr` | 5 | rs1 register number (for forwarding) |
| `rs2_addr` | 5 | rs2 register number (for forwarding) |
| `rd_addr` | 5 | rd register number (destination) |
| `funct3` | 3 | funct3 field (for branch type: BEQ/BNE) |

### EX/MEM Register
| Field | Width | Description |
|-------|-------|-------------|
| `reg_write` | 1 | WB: enable register write |
| `mem_to_reg` | 1 | WB: select memory data vs ALU result |
| `mem_read` | 1 | MEM: enable data memory read |
| `mem_write` | 1 | MEM: enable data memory write |
| `alu_result` | 32 | ALU computation result |
| `rs2_data` | 32 | Forwarded store data (for SW) |
| `rd_addr` | 5 | Destination register number |

### MEM/WB Register
| Field | Width | Description |
|-------|-------|-------------|
| `reg_write` | 1 | WB: enable register write |
| `mem_to_reg` | 1 | WB: select memory data vs ALU result |
| `mem_data` | 32 | Data memory read output |
| `alu_result` | 32 | ALU result (passthrough) |
| `rd_addr` | 5 | Destination register number |

## Data Forwarding Paths

The forwarding unit detects RAW hazards by comparing source register addresses in the EX stage against destination registers in MEM and WB stages.

### Forwarding Mux Encoding
| `forward_a/b` | Source | Scenario |
|---------------|--------|----------|
| `2'b00` | ID/EX register | No hazard — use register file value |
| `2'b10` | EX/MEM result | 1-instruction gap (most recent producer) |
| `2'b01` | MEM/WB result | 2-instruction gap |

### Priority
EX/MEM forwarding (`2'b10`) takes priority over MEM/WB (`2'b01`) to ensure the most recent value is used when multiple producers write the same register.

### WB-to-ID Bypass
For a 3-instruction gap (producer exits WB while consumer is in ID), the register file read might return a stale value due to non-blocking write semantics. A combinational bypass in `cpu_pipeline_top.sv` checks if WB is writing the same register that ID is reading and substitutes the WB write data directly.

## Load-Use Hazard Stalling

When a LOAD (LW) is in EX and the next instruction in ID reads the load's destination register, the data isn't available until after the MEM stage. The forwarding unit alone cannot resolve this.

**Detection:**
```
stall = id_ex_mem_read
        && (id_ex_rd != x0)
        && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))
```

**Stall effects:**
1. PC freezes (`pc_write = 0`)
2. IF/ID holds current instruction (`stall = 1`)
3. NOP bubble inserted into ID/EX (`flush = 1`)

After the 1-cycle stall, the load result is forwarded from MEM/WB in the next cycle.

## Branch Resolution

Branches (BEQ, BNE) are resolved in the **EX stage** using a dedicated comparator operating on forwarded operands.

### Branch Comparator Logic
```systemverilog
if (id_ex_branch) begin
    case (id_ex_funct3)
        3'b000: branch_taken = (forwarded_a == forwarded_b);  // BEQ
        3'b001: branch_taken = (forwarded_a != forwarded_b);  // BNE
    endcase
end
```

### Branch Target Calculation
```
pc_branch = id_ex_pc + id_ex_imm
```

### Flush Penalty: 2 Cycles
When a branch is taken, the two instructions fetched after the branch (in IF and ID stages) are incorrect and must be flushed:
1. IF/ID register is cleared (flush the instruction in transit)
2. ID/EX register is cleared (flush the instruction being decoded)
3. PC is redirected to the branch target

## Supported Instructions

| Instruction | Type | Opcode | Description |
|-------------|------|--------|-------------|
| ADD | R | 0110011 | rd = rs1 + rs2 |
| SUB | R | 0110011 | rd = rs1 - rs2 |
| ADDI | I | 0010011 | rd = rs1 + imm |
| LW | I | 0000011 | rd = MEM[rs1 + imm] |
| SW | S | 0100011 | MEM[rs1 + imm] = rs2 |
| BEQ | B | 1100011 | if (rs1 == rs2) PC += imm |
| BNE | B | 1100011 | if (rs1 != rs2) PC += imm |

## Module Inventory

| Module | File | Language | Role |
|--------|------|----------|------|
| `pc_pipe` | `pc_pipe.sv` | SV | Program counter with stall/branch |
| `instruction_memory_pipe` | `instruction_memory_pipe.sv` | SV | Instruction ROM (test program) |
| `control_unit_pipe` | `control_unit_pipe.sv` | SV | Control decoder with branch support |
| `imm_gen_pipe` | `imm_gen_pipe.sv` | SV | Immediate generator with B-type |
| `register_file` | `register_file.v` | V | 32×32 register file (original) |
| `alu` | `alu.v` | V | ADD/SUB arithmetic unit (original) |
| `data_memory` | `data_memory.v` | V | Data RAM for LW/SW (original) |
| `if_id_reg` | `if_id_reg.sv` | SV | IF/ID pipeline register |
| `id_ex_reg` | `id_ex_reg.sv` | SV | ID/EX pipeline register |
| `ex_mem_reg` | `ex_mem_reg.sv` | SV | EX/MEM pipeline register |
| `mem_wb_reg` | `mem_wb_reg.sv` | SV | MEM/WB pipeline register |
| `forwarding_unit` | `forwarding_unit.sv` | SV | Data forwarding (RAW resolution) |
| `hazard_detection_unit` | `hazard_detection_unit.sv` | SV | Load-use stall detection |
| `cpu_pipeline_top` | `cpu_pipeline_top.sv` | SV | Top-level pipeline wiring |
