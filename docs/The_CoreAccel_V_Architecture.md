# The CoreAccel-V Architecture
### Phase 1 Architectural Specification — 5-Stage Pipelined RV32I + DSP MAC SoC

---

## 1. Design Philosophy

CoreAccel-V is a custom System-on-Chip designed to answer a specific question: **can a general-purpose RISC-V processor be augmented with a tightly-coupled DSP engine and still close timing at 100 MHz on a low-cost Artix-7 FPGA?**

The answer required making deliberate, physical hardware choices at every level of the design — from the pipeline microarchitecture, to the memory hierarchy, to the silicon-level inference templates used for synthesis. This document describes the baseline architecture that was achieved.

> [!NOTE]
> **Target Device**: Xilinx Artix-7 xc7a35tcpg236-1 (Basys 3 board)
> **Target Frequency**: 100 MHz (10.000 ns period)
> **ISA**: RV32I Base Integer + CUSTOM-0 DSP Extensions
> **HDL**: SystemVerilog (IEEE 1800-2017)

---

## 2. The CPU: A 5-Stage In-Order Pipeline

### 2.1 Pipeline Overview

The processor implements the classic textbook 5-stage RISC pipeline, but constructed entirely with modern SystemVerilog constructs. Every sequential element uses `always_ff`; every combinational block uses `always_comb`. There are no legacy `reg` types or `always @(*)` constructs anywhere in the design. This was a deliberate choice — not for stylistic purity, but because `always_ff` and `always_comb` provide stronger latch-inference checking and simulation-synthesis equivalence guarantees that are critical when debugging timing violations at the gate level.

```
┌──────┐    ┌──────┐    ┌──────┐    ┌──────┐    ┌──────┐
│  IF  │───▶│  ID  │───▶│  EX  │───▶│ MEM  │───▶│  WB  │
│      │    │      │    │      │    │      │    │      │
│ PC   │    │Decode│    │ ALU  │    │ BRAM │    │ Reg  │
│ IMEM │    │RegFile│   │ MAC  │    │ DMEM │    │Write │
│      │    │ImmGen│    │Branch│    │ Mux  │    │ Mux  │
└──────┘    └──────┘    └──────┘    └──────┘    └──────┘
   │            │            │            │
   ▼            ▼            ▼            ▼
┌──────┐    ┌──────┐    ┌──────┐    ┌──────┐
│IF/ID │    │ID/EX │    │EX/MEM│    │MEM/WB│
│ Reg  │    │ Reg  │    │ Reg  │    │ Reg  │
└──────┘    └──────┘    └──────┘    └──────┘
```

### 2.2 Stage-by-Stage Microarchitecture

#### IF — Instruction Fetch

The Program Counter (`pc_pipe`) is a pipeline-aware register that supports three modes:

| Mode | Condition | Action |
|------|-----------|--------|
| **Normal** | `pc_write=1, pc_src=0` | `PC ← PC + 4` |
| **Redirect** | `pc_write=1, pc_src=1` | `PC ← redirect_target` |
| **Stall** | `pc_write=0` | `PC` holds current value |

The Instruction Memory (`instruction_memory_pipe`) is a 64-word (256-byte) combinational ROM. Instructions are loaded via `$readmemh` at simulation start and synthesize to LUT-based lookup tables. The read is fully combinational — no clock latency — so the fetched instruction is available immediately for the IF/ID register.

#### ID — Instruction Decode

Three units operate in parallel during the ID stage:

1. **Control Unit** (`control_unit_pipe`): A fully combinational decoder that maps the 7-bit opcode (plus funct3/funct7 for R-type and shift instructions) to 14 control signals. It supports all RV32I base instructions plus four CUSTOM-0 DSP opcodes.

2. **Immediate Generator** (`imm_gen_pipe`): Extracts and sign-extends immediates for all five RV32I encoding formats (I/S/B/U/J) based on the opcode.

3. **Register File** (`register_file`): 32 × 32-bit registers with two combinational read ports and one synchronous write port. Register x0 is hardwired to zero per the RISC-V specification. A WB-to-ID bypass path is implemented at the top level to forward write-back data directly when the WB stage is writing to a register that the ID stage is reading, avoiding a structural hazard.

#### EX — Execute

The EX stage is the computational heart of the processor and contains five major functional units:

1. **Forwarding Muxes**: Two 3-input multiplexers select the source of ALU operands A and B. Each can choose between the ID/EX register value (no forwarding), the EX/MEM ALU result (EX→EX forwarding), or the WB write-back data (MEM→EX forwarding).

2. **ALU** (`alu`): A fully combinational unit supporting all 11 RV32I operations via a 4-bit control encoding derived from `{funct7[5], funct3}`. It generates four condition flags: zero, sign, overflow, and carry. A 33-bit extended computation extracts the unsigned carry/borrow for ADD/SUB.

3. **Branch Comparator**: Evaluates all six RV32I branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU) using the forwarded operands. Branch resolution occurs in the EX stage — a 1-cycle penalty on taken branches.

4. **MAC Unit** (`mac_unit`): The DSP coprocessor (detailed in Section 3).

5. **Result Mux**: A priority multiplexer selects the EX stage output:
   - `pc_to_reg` → `PC + 4` (JAL/JALR link address)
   - `mac_to_reg` → Sliced MAC result (low or high 32 bits)
   - Default → ALU result

#### MEM — Memory Access

The MEM stage contains the memory address decoder and two memory subsystems:

- **Address Decoder**: Bit 31:28 of `ex_mem_alu_result` selects the memory region:
  - `0x8xxx_xxxx` → Tightly Coupled Memory (TCM, Port A)
  - All other addresses → Data Memory (64-word distributed RAM)

- **Data Memory** (`data_memory`): 64 × 32-bit distributed RAM with synchronous write and combinational read. Explicitly annotated with `(* ram_style = "distributed" *)` to guarantee zero-latency reads for the standard load path.

- **TCM Port A**: The CPU-side port of the True Dual-Port BRAM (detailed in Section 4).

#### WB — Write Back

A single 2-input mux selects between the ALU result passthrough and the memory read data, controlled by `mem_to_reg`. The selected value is written to the register file on the next clock edge.

### 2.3 Hazard Resolution

#### Data Hazards — Forwarding Unit

The forwarding unit resolves Read-After-Write (RAW) hazards by comparing the destination register of instructions in the MEM stage (EX/MEM.rd) and WB stage (MEM/WB.rd) against the source registers of the instruction in the EX stage (ID/EX.rs1, ID/EX.rs2). EX/MEM forwarding takes priority over MEM/WB forwarding, ensuring the most recent producer is always selected.

#### Data Hazards — Load-Use Stall

The hazard detection unit identifies load-use hazards: when the instruction in the EX stage is a load (`mem_read = 1`) and the instruction in the ID stage reads its destination register. A 1-cycle pipeline bubble is inserted by:
- Freezing the PC and IF/ID register
- Flushing the ID/EX register (injecting a NOP)

This is the standard RISC-V load-use penalty and applies equally to Data Memory and TCM loads.

#### Control Hazards — Flush on Redirect

When a branch is taken or a jump is executed (detected in EX), the IF/ID register is flushed (instruction replaced with NOP) and the ID/EX register is flushed. The PC is redirected to the branch/jump target. This results in a fixed 1-cycle branch penalty.

---

## 3. The DSP Engine: 64-Bit Saturating MAC

### 3.1 Design Rationale

General-purpose DSP workloads — FIR/IIR filters, matrix multiplication, neural network inference — are dominated by multiply-accumulate operations. Rather than relying on software loops of discrete MUL/ADD instructions (which the RV32I base ISA doesn't even include), CoreAccel-V integrates a dedicated hardware MAC unit directly into the EX stage.

The MAC unit is designed to exploit the Artix-7's DSP48E1 hard multiplier slices. A 32×32-bit signed multiply requires 4 DSP48E1 tiles (each natively supports 25×18 signed), and Vivado automatically decomposes and maps this through its wide-multiplier inference engine.

### 3.2 ISA Encoding (CUSTOM-0 Opcode Space)

The MAC uses the RISC-V CUSTOM-0 opcode (`7'b0001011`), which is reserved for implementation-specific extensions:

| Instruction | funct3 | Operation |
|-------------|--------|-----------|
| `MAC rs1, rs2` | `3'b000` | Accumulator += rs1 × TCM[rs2] |
| `MAC_CLEAR` | `3'b001` | Accumulator ← 0, Overflow ← 0 |
| `MAC_READ_LO rd` | `3'b011` | rd ← Accumulator[31:0] |
| `MAC_READ_HI rd` | `3'b100` | rd ← Accumulator[63:32] |

### 3.3 Microarchitecture

The MAC operates as a **multi-cycle coprocessor** with a 4-state FSM:

```
         mac_start
  IDLE ───────────▶ S_INPUT ───────▶ S_MULTIPLY ───────▶ S_ACCUMULATE ───▶ IDLE
   │                  │                  │                    │
   │ Latch rs1        │ BRAM data       │ product +=         │ (NOP)
   │ Present addr     │ arrives         │ accumulator        │
   │ to TCM Port B    │ Compute product │ Saturation check   │
```

**Cycle-by-cycle timeline for a MAC instruction:**

| Cycle | State | Action |
|-------|-------|--------|
| 0 | IDLE | `mac_start` asserted. `a_reg ← rs1`. `forwarded_b[11:2]` presented to TCM Port B address. |
| 1 | S_INPUT | BRAM output valid (1-cycle latency). `product_reg ← a_reg × tcm_data` (64-bit signed). |
| 2 | S_MULTIPLY | Saturating accumulate: `accumulator ← accumulator + product_reg`. Overflow detection with signed saturation to ±2⁶³. |
| 3 | S_ACCUMULATE | No-op. FSM returns to IDLE. `mac_busy` deasserts. |

**Stall mechanism**: While `mac_busy` is asserted, the pipeline stalls (IF, ID, EX frozen; EX/MEM flushed with bubble). This prevents subsequent instructions from corrupting the MAC's input operands or consuming stale results.

### 3.4 Saturation Logic

The accumulator uses signed saturation to prevent silent wraparound:

```
if (accumulator[63] == product[63]) && (sum[63] != accumulator[63]):
    // Signed overflow: both operands same sign, result different sign
    if (accumulator[63] == 0):
        accumulator ← +2⁶³ - 1    // 0x7FFF_FFFF_FFFF_FFFF
    else:
        accumulator ← -2⁶³        // 0x8000_0000_0000_0000
    overflow_flag ← 1
```

---

## 4. The Memory Subsystem: True Dual-Port BRAM TCM

### 4.1 Design Rationale

The most critical architectural decision in CoreAccel-V was the memory subsystem. We explicitly rejected a cache-coherent hierarchy in favor of a **Tightly Coupled Memory (TCM)** implemented in Xilinx Block RAM.

The reasoning is physical:

| Property | Cache | TCM (BRAM) |
|----------|-------|------------|
| **Latency** | Variable (hit/miss) | Fixed 1-cycle |
| **Determinism** | Non-deterministic | Fully deterministic |
| **Area** | Tag RAM + comparators + FSM | 1 BRAM36E1 tile |
| **DSP Integration** | Requires coherence protocol | Direct port connection |
| **Predictability for RT** | Poor | Excellent |

For DSP workloads, the MAC unit needs to stream weight coefficients at full pipeline bandwidth. A cache miss during coefficient fetch would stall the MAC for 10–100+ cycles (depending on backing store latency), destroying throughput. The TCM guarantees every read completes in exactly 1 clock cycle, every time.

### 4.2 Physical Implementation

The TCM is implemented as a **True Dual-Port** memory using a single Xilinx BRAM36E1 tile:

```
                    ┌───────────────────────────────┐
                    │        BRAM36E1 (36 Kb)       │
                    │        1024 × 32-bit          │
                    │                               │
     CPU Bus        │  Port A          Port B       │        MAC Unit
    (MEM Stage)     │                               │       (EX Stage)
                    │                               │
   addra[9:0] ────▶│  ADDRA     ADDRB  │◀──── addrb[9:0]
    dina[31:0] ───▶│  DINA      DOUTB  │────▶ tcm_data[31:0]
     wea ─────────▶│  WEA               │
   douta[31:0] ◀───│  DOUTA             │
                    │                               │
     clka ─────────│  CLKA      CLKB   │───── clkb
                    │                               │
                    └───────────────────────────────┘
```

- **Port A** (CPU Bus): Read/write port connected to the MEM stage. Used for `LW`/`SW` instructions targeting the TCM address region (`0x8000_0000` – `0x8000_0FFF`). Operates in **Write-First** mode: on a simultaneous read+write to the same address, the new data appears on `douta`.

- **Port B** (MAC Streaming): Read-only port hardwired to the MAC unit's second operand input. The address comes from `forwarded_b[11:2]` (the rs2 forwarded value, treated as a TCM byte address). The MAC presents the address in its IDLE cycle; data arrives via BRAM registered output in the S_INPUT cycle.

### 4.3 Memory Address Map

```
  0x0000_0000 ┌─────────────────────┐
              │  Instruction Memory │  64 words (256 bytes)
              │  (Combinational ROM)│  Read-only, LUT-based
  0x0000_00FF ├─────────────────────┤
              │                     │
              │   (Unmapped)        │
              │                     │
  0x0000_0100 ├─────────────────────┤
              │    Data Memory      │  64 words (256 bytes)
              │  (Distributed RAM)  │  Combinational read, sync write
  0x0000_01FF ├─────────────────────┤
              │                     │
              │   (Unmapped)        │
              │                     │
  0x8000_0000 ├─────────────────────┤
              │   TCM (BRAM)        │  1024 words (4096 bytes)
              │  True Dual-Port     │  Port A: CPU, Port B: MAC
  0x8000_0FFF ├─────────────────────┤
              │                     │
              │   (Unmapped)        │
              │                     │
  0xFFFF_FFFF └─────────────────────┘
```

### 4.4 BRAM Inference Contract

For Vivado to map the `tcm_ram` module to a physical BRAM36E1 tile rather than distributed LUTRAM, the RTL must conform to specific inference templates:

1. **`(* ram_style = "block" *)`** attribute on the memory array declaration
2. **Synchronous read**: All read outputs must be registered (`always_ff`)
3. **No cross-port bypass logic**: The `always_ff` block for each port must reference only that port's signals — no conditional forwarding between ports
4. **Standard write mode**: Write-First, Read-First, or No-Change — not custom muxed logic

Violating any of these constraints causes Vivado to silently fall back to distributed LUTRAM, with catastrophic consequences for timing (see Engineering Crucible, Section 3).

### 4.5 Cross-Port Collision Handling

When Port A writes and Port B reads the same address on the same clock edge, the Xilinx 7-series TDP BRAM returns the **old value** on Port B. This is defined behavior — no metastability, no data corruption in the BRAM array.

CoreAccel-V treats this scenario as a **software data race**: the programmer must insert a NOP or fence instruction between a TCM store and a subsequent MAC read targeting the same address. This is the same contract that exists in ARM Cortex-M TCMs, MIPS Tightly-Coupled Memories, and any shared-memory system without hardware coherence.

No hardware interlock is implemented for this case. The rationale for this decision — and the timing consequences of the alternative — are documented in the Engineering Crucible.

---

## 5. Physical Constraints & Board Mapping

The design is constrained for the **Digilent Basys 3** board:

| Signal | Direction | Pin | Purpose |
|--------|-----------|-----|---------|
| `clk` | Input | W5 | 100 MHz CMOS oscillator |
| `reset` | Input | U18 | Center pushbutton (active-high) |
| `debug_pc[7:0]` | Output | U16, E19, U19, V19, W18, U15, U14, V14 | Lower byte of PC → LEDs 0-7 |
| `debug_wb[7:0]` | Output | V13, V3, W3, U3, P3, N3, P1, L1 | Lower byte of WB data → LEDs 8-15 |

The debug outputs serve a dual purpose: they provide visual feedback during board-level testing, and they act as **anchor logic** that prevents Vivado's optimizer from removing the entire design (see Engineering Crucible, Section 1).

**Timing exceptions:**
- `reset`: False path (asynchronous human input, no timing relevance)
- `debug_pc[*]`, `debug_wb[*]`: False path (LED outputs, no external timing requirement)

---

## 6. Resource Utilization Summary

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUT6 | ~1,200 | 20,800 | ~5.8% |
| Flip-Flops | ~1,500 | 41,600 | ~3.6% |
| BRAM36E1 | 1 | 50 | 2.0% |
| DSP48E1 | 4 | 90 | 4.4% |
| BUFG | 1 | 32 | 3.1% |

The design comfortably fits within the xc7a35t with substantial headroom for Phase 2 expansion (interrupt controller, UART, additional TCM banks).
