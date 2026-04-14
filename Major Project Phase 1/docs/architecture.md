# Single-Cycle RV32I CPU — Architecture

## What is a Single-Cycle CPU?

A single-cycle CPU completes **one instruction per clock cycle**. Every instruction — 
whether it reads memory, writes a register, or computes a result — finishes in exactly 
one tick of the clock. This is the simplest way to build a CPU.

## How an Instruction Flows Through the CPU

Every clock cycle, the CPU does these steps **all at once** (combinationally):

```
1. FETCH      →  PC points to instruction memory, which outputs the instruction
2. DECODE     →  Control unit reads the opcode and generates control signals
                  Register file reads rs1 and rs2
                  Immediate generator extracts/sign-extends the immediate
3. EXECUTE    →  ALU performs the operation (add, subtract)
4. MEMORY     →  For LW: read data memory.  For SW: write data memory.
5. WRITE-BACK →  Result (from ALU or memory) is written to the register file
```

At the end of the clock cycle, the PC increments by 4 to point to the next instruction.

## Datapath Diagram

```
         +4
          │
  ┌────┐  │   ┌──────────────┐
  │ PC ├──┴──►│  Instruction │──────────────────────────────┐
  └─┬──┘      │  Memory      │─── instr[31:0] ──┐          │
    │         └──────────────┘                   │          │
    │                                            ▼          ▼
    │                                    ┌──────────┐  ┌────────┐
    │                                    │ Control  │  │ Imm    │
    │                                    │ Unit     │  │ Gen    │
    │                                    └────┬─────┘  └───┬────┘
    │                                         │ctrl        │imm
    │         ┌──────────────┐                │            │
    │         │  Register    │◄───────────────┘            │
    │         │  File        │                             │
    │         │  rs1_data ───┼──────────────► ALU_A        │
    │         │  rs2_data ───┼───┐            │            │
    │         └──────┬───────┘   │     ┌──────▼──────┐     │
    │                │           │     │    MUX      │◄────┘
    │                │           │     │ (ALUSrc)    │
    │                │           │     └──────┬──────┘
    │                │           │            │ALU_B
    │                │           │     ┌──────▼──────┐
    │                │           │     │    ALU      │
    │                │           │     └──────┬──────┘
    │                │           │            │alu_result
    │                │           │     ┌──────▼──────┐
    │         wr_data│           └────►│ Data Memory │
    │           ┌────┴────┐           └──────┬──────┘
    │           │  MUX    │◄─────────────────┘ read_data
    │           │(MemToReg│◄─────────────────── alu_result
    │           └─────────┘
    └────────────────────────────────────────────────────► (next PC)
```

## Supported Instructions

| Instruction | Example          | Meaning               | Type |
|-------------|------------------|-----------------------|------|
| ADD         | `ADD x3, x1, x2`| x3 = x1 + x2         | R    |
| SUB         | `SUB x3, x1, x2`| x3 = x1 - x2         | R    |
| ADDI        | `ADDI x1, x0, 5`| x1 = x0 + 5          | I    |
| LW          | `LW x4, 0(x1)`  | x4 = Memory[x1 + 0]  | I    |
| SW          | `SW x4, 0(x1)`  | Memory[x1 + 0] = x4  | S    |

## Control Signals

| Signal   | Purpose                                          |
|----------|--------------------------------------------------|
| RegWrite | Enable writing to register file                  |
| ALUSrc   | 0 = ALU input B is rs2; 1 = ALU input B is imm  |
| MemRead  | Enable reading from data memory                  |
| MemWrite | Enable writing to data memory                    |
| MemToReg | 0 = write ALU result to reg; 1 = write mem data  |
| ALUOp    | Tells ALU what operation to perform              |

## Module Summary

| Module             | Role                                      |
|--------------------|-------------------------------------------|
| `pc.v`             | Holds and increments instruction address  |
| `instruction_memory.v` | ROM storing the program               |
| `register_file.v`  | 32 registers, 2 read + 1 write port       |
| `alu.v`            | Arithmetic: add and subtract              |
| `imm_gen.v`        | Extracts immediate from instruction       |
| `control_unit.v`   | Decodes opcode into control signals       |
| `data_memory.v`    | RAM for load/store instructions           |
| `cpu_top.v`        | Wires everything together                 |
