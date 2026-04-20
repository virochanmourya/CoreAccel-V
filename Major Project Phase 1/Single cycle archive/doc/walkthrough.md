# Single-Cycle RV32I CPU — Walkthrough

## ✅ All Tests Passed

The CPU correctly executes all 6 instructions in the demo program:

```
x1 = 5    ✓  (ADDI x1, x0, 5)
x2 = 10   ✓  (ADDI x2, x0, 10)
x3 = 15   ✓  (ADD  x3, x1, x2)
x4 = 10   ✓  (SUB  x4, x3, x1)
MEM[0] = 15 ✓ (SW x3, 0(x0))
x5 = 15   ✓  (LW x5, 0(x0))
```

## Project Structure

```
Major Project Phase 1/
├── rtl/
│   ├── pc.v                    ← Program Counter
│   ├── instruction_memory.v    ← ROM with hardcoded program
│   ├── register_file.v         ← 32 x 32-bit register file
│   ├── alu.v                   ← ADD / SUB
│   ├── imm_gen.v               ← Immediate extractor
│   ├── control_unit.v          ← Opcode → control signals
│   ├── data_memory.v           ← RAM for LW/SW
│   └── cpu_top.v               ← Top-level wiring
├── sim/
│   ├── cpu_tb.v                ← Testbench
│   └── cpu_sim.vvp             ← Compiled simulation
├── cpu_waves.vcd               ← Waveform dump
└── docs/
    └── architecture.md         ← Architecture explanation
```

## Simulation Output

```
[Cycle] PC=0   Instr=00500093  ALU_result=5   RegWrite=1  MemWrite=0   ← ADDI x1, x0, 5
[Cycle] PC=4   Instr=00a00113  ALU_result=10  RegWrite=1  MemWrite=0   ← ADDI x2, x0, 10
[Cycle] PC=8   Instr=002081b3  ALU_result=15  RegWrite=1  MemWrite=0   ← ADD  x3, x1, x2
[Cycle] PC=12  Instr=40118233  ALU_result=10  RegWrite=1  MemWrite=0   ← SUB  x4, x3, x1
[Cycle] PC=16  Instr=00302023  ALU_result=0   RegWrite=0  MemWrite=1   ← SW   x3, 0(x0)
[Cycle] PC=20  Instr=00002283  ALU_result=0   RegWrite=1  MemWrite=0   ← LW   x5, 0(x0)

>>> ALL TESTS PASSED! <<<
```

## How to Compile and Run

```bash
# Compile
iverilog -o sim/cpu_sim.vvp rtl/pc.v rtl/instruction_memory.v rtl/register_file.v rtl/alu.v rtl/imm_gen.v rtl/control_unit.v rtl/data_memory.v rtl/cpu_top.v sim/cpu_tb.v

# Run
vvp sim/cpu_sim.vvp

# View waveforms (optional, requires GTKWave)
gtkwave cpu_waves.vcd
```

---

## Module-by-Module Explanation

### 1. [pc.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/pc.v)
**Program Counter** — a 32-bit register that holds the address of the current instruction.
- On **reset**: goes to 0 (start of program)
- Each **clock edge**: increments by 4 (each instruction is 4 bytes)
- Inputs: `clk`, `reset`
- Output: `pc_out[31:0]`

### 2. [instruction_memory.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/instruction_memory.v)
**Instruction ROM** — stores the program as hardcoded 32-bit machine code words.
- Combinational read (no clock needed)
- Uses `addr[31:2]` to index words (byte address ÷ 4)
- Input: `addr[31:0]` (from PC)
- Output: `instruction[31:0]`

### 3. [register_file.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/register_file.v)
**Register File** — 32 registers, each 32 bits wide.
- 2 **read** ports: combinational (instant), used for rs1 and rs2
- 1 **write** port: clocked (writes on rising edge)
- `x0` is hardwired to zero (reads always return 0, writes are ignored)

### 4. [alu.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/alu.v)
**Arithmetic Logic Unit** — performs ADD or SUB.
- `alu_control = 2'b00` → ADD
- `alu_control = 2'b01` → SUB
- Inputs: `alu_in1`, `alu_in2`, `alu_control`
- Output: `alu_result`

### 5. [imm_gen.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/imm_gen.v)
**Immediate Generator** — extracts the immediate value from the instruction and sign-extends it to 32 bits.
- **I-type** (ADDI, LW): `imm[11:0]` from `instruction[31:20]`
- **S-type** (SW): splits across `instruction[31:25]` and `instruction[11:7]`

### 6. [control_unit.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/control_unit.v)
**Control Unit** — decodes the opcode and generates all control signals.

| Instruction | reg_write | alu_src | mem_read | mem_write | mem_to_reg | alu_control |
|-------------|-----------|---------|----------|-----------|------------|-------------|
| ADD         | 1         | 0       | 0        | 0         | 0          | 00          |
| SUB         | 1         | 0       | 0        | 0         | 0          | 01          |
| ADDI        | 1         | 1       | 0        | 0         | 0          | 00          |
| LW          | 1         | 1       | 1        | 0         | 1          | 00          |
| SW          | 0         | 1       | 0        | 1         | 0          | 00          |

### 7. [data_memory.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/data_memory.v)
**Data RAM** — 64 words of read/write memory for LW and SW.
- Write: synchronous (on clock edge, when `mem_write = 1`)
- Read: combinational (when `mem_read = 1`)

### 8. [cpu_top.v](file:///c:/Users/viroc/Coding/Major%20Project%20Phase%201/rtl/cpu_top.v)
**Top Module** — no logic, just wiring. Contains two MUXes:
- **ALUSrc MUX**: selects between rs2 and immediate for ALU input B
- **MemToReg MUX**: selects between ALU result and memory data for register write-back

---

## Future Expansion

### How This Becomes Pipelined

The single-cycle CPU can be converted to a **5-stage pipeline** by inserting **pipeline registers** between each stage:

```
 IF/ID  →  ID/EX  →  EX/MEM  →  MEM/WB
  reg       reg       reg        reg
```

| Stage | Name        | What It Does                    |
|-------|-------------|---------------------------------|
| IF    | Fetch       | Read instruction from IMEM      |
| ID    | Decode      | Read registers, generate control|
| EX    | Execute     | ALU computation                 |
| MEM   | Memory      | Read/write data memory          |
| WB    | Write-Back  | Write result to register file   |

**Key additions for pipelining:**
1. Pipeline registers (flip-flops between stages)
2. Hazard detection unit (detects data dependencies)
3. Forwarding unit (bypasses data to avoid stalls)
4. Branch prediction (for branch instructions, added later)

### Where to Add a MAC Unit (for DSP)

A **MAC (Multiply-Accumulate)** unit computes: `result = A × B + C`

**Integration approach:**
1. Add a new ALU operation code (e.g., `alu_control = 2'b10` for MAC)
2. Add a custom instruction opcode (use RISC-V custom-0: `opcode = 7'b0001011`)
3. Wire the MAC unit parallel to the ALU in the EX stage
4. Update the control unit to recognize the new opcode

```
                 ┌─────────┐
  rs1 ──────────►│  ALU    ├──┐
  rs2/imm ──────►│ (ADD/SUB│  │    ┌─────┐
                 └─────────┘  ├───►│ MUX ├──► result
                 ┌─────────┐  │    └─────┘
  rs1 ──────────►│  MAC    ├──┘
  rs2 ──────────►│ (A*B+C) │
  rs3/acc ──────►│         │
                 └─────────┘
```

This is the natural path from this Phase 1 single-cycle CPU to a DSP-accelerated SoC.
