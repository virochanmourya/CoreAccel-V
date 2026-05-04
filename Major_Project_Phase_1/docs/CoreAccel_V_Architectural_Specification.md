# CoreAccel-V — Phase 1 Architectural Specification

**Project:** CoreAccel-V — 32-Bit Pipelined RISC-V SoC with Custom DSP Extensions  
**Target:** Xilinx Artix-7 xc7a35tcpg236-1 (Basys 3 Board, 100 MHz)  
**Revision:** Phase 1 Final  
**Date:** 2026-05-03

---

## 1. Executive Summary

CoreAccel-V is a custom 32-bit System-on-Chip designed to accelerate fixed-point DSP algorithms — specifically real-time biomedical signal processing pipelines such as the Pan-Tompkins ECG arrhythmia detection algorithm. The architecture pairs a fully compliant RV32I base integer pipeline with a tightly coupled multiply-accumulate (MAC) engine and a dedicated Block RAM-based weight memory, creating a Harvard-bypass datapath that eliminates the Von Neumann memory bottleneck for filter coefficient streaming.

### Phase 1 Deliverables

| Component | Implementation | Status |
|---|---|:---:|
| 5-stage in-order RV32I pipeline | SystemVerilog RTL | ✅ Verified |
| 4-bit ALU (11 operations + flags) | Combinational | ✅ Verified |
| 64-bit signed saturating MAC unit | 4-state FSM, 3-cycle latency | ✅ Verified |
| 4KB Tightly Coupled Memory (TCM) | True Dual-Port BRAM36E1 | ✅ Verified |
| Data forwarding (EX→EX, MEM→EX) | Combinational MUX network | ✅ Verified |
| Hazard detection (load-use + MAC stall) | Combinational + registered | ✅ Verified |
| Full branch datapath (6 conditions) | EX-stage comparator | ✅ Verified |
| Jump-and-link (JAL/JALR) | EX-stage target compute | ✅ Verified |

### RTL Module Inventory (17 files, ~19.5 KB)

| Module | File | Language | Lines |
|---|---|:---:|:---:|
| Program Counter | `pc_pipe.sv` | SystemVerilog | 41 |
| Instruction ROM | `instruction_memory_pipe.sv` | SystemVerilog | 24 |
| IF/ID Register | `if_id_reg.sv` | SystemVerilog | 55 |
| Control Unit | `control_unit_pipe.sv` | SystemVerilog | 121 |
| Immediate Generator | `imm_gen_pipe.sv` | SystemVerilog | 55 |
| Register File | `register_file.v` | Verilog | 52 |
| ID/EX Register | `id_ex_reg.sv` | SystemVerilog | 137 |
| Forwarding Unit | `forwarding_unit.sv` | SystemVerilog | 74 |
| Hazard Detection Unit | `hazard_detection_unit.sv` | SystemVerilog | 39 |
| ALU | `alu.sv` | SystemVerilog | 174 |
| MAC Unit | `mac_unit.sv` | SystemVerilog | 109 |
| TCM (Dual-Port BRAM) | `tcm_ram.sv` | SystemVerilog | 68 |
| EX/MEM Register | `ex_mem_reg.sv` | SystemVerilog | 69 |
| Data Memory | `data_memory.v` | Verilog | 52 |
| MEM/WB Register | `mem_wb_reg.sv` | SystemVerilog | 48 |
| Pipeline Top | `cpu_pipeline_top.sv` | SystemVerilog | 480 |

---

## 2. The Pipeline

### 2.1 Five-Stage Microarchitecture

```
 ┌──────┐   ┌──────┐   ┌──────────────┐   ┌──────┐   ┌──────┐
 │  IF  │──▶│  ID  │──▶│      EX      │──▶│ MEM  │──▶│  WB  │
 │      │   │      │   │  ALU + MAC   │   │      │   │      │
 │ IMEM │   │ RF   │   │  + TCM PortB │   │ DMEM │   │ RF   │
 │ PC   │   │ CTRL │   │  + Branch    │   │ TCM  │   │ Write│
 │      │   │ IMMG │   │  + Jump      │   │PortA │   │      │
 └──────┘   └──────┘   └──────────────┘   └──────┘   └──────┘
     │           │             │                │
   IF/ID       ID/EX        EX/MEM          MEM/WB
  (flush)    (flush/stall)  (flush)
```

**Stage Details:**

- **IF (Instruction Fetch):** `pc_pipe` generates the 32-bit PC. `instruction_memory_pipe` provides single-cycle combinational instruction read. PC source MUX selects between `PC+4`, branch target (`id_ex_pc + imm`), or JALR target (`alu_result & ~1`).

- **ID (Instruction Decode):** `control_unit_pipe` decodes opcode/funct3/funct7 into 15 control signals. `register_file` provides two read ports (combinational) and one write port (posedge clk). `imm_gen_pipe` extracts I/S/B/U/J-type immediates. A WB-to-ID bypass detects same-cycle write-read hazards.

- **EX (Execute):** The ALU, MAC unit, branch comparator, and TCM Port B all operate here. The forwarding MUX selects between `id_ex_rs_data`, `ex_mem_alu_result`, or `wb_data` for each operand. `alu_src_a` selects between `forwarded_a` and `id_ex_pc` (for AUIPC). `alu_src` selects between `forwarded_b` and `id_ex_imm`.

- **MEM (Memory Access):** Address decoder routes accesses: `addr[31:28] == 4'h8` → TCM Port A (BRAM), else → `data_memory` (combinational). Store data comes from `ex_mem_rs2_data`.

- **WB (Write Back):** `wb_data = mem_to_reg ? mem_data : alu_result`. The "alu_result" path carries ALU results, MAC sliced results, or PC+4 depending on the instruction class.

### 2.2 Hazard Detection & Pipeline Control

**Load-Use Hazard (1-cycle stall):**
```
Condition: id_ex_mem_read && (id_ex_rd != 0)
           && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))
Action:    Freeze PC, freeze IF/ID, insert NOP bubble into ID/EX
```

**MAC Computation Stall (3-cycle stall):**
```
Condition: is_mac_ex && !(mac_started_reg && !mac_busy)
Action:    Freeze PC, freeze IF/ID, stall ID/EX, flush EX/MEM
```

**Branch/Jump Flush (2-cycle penalty):**
```
Condition: branch_taken || jump_ex
Action:    Flush IF/ID, flush ID/EX, redirect PC to target
```

### 2.3 Data Forwarding Unit

Two 2-bit MUX selects (`forward_a`, `forward_b`) resolve RAW dependencies:

| Select | Source | Pipeline Stage | Priority |
|:---:|---|---|:---:|
| `2'b10` | `ex_mem_alu_result` | EX→EX (1 cycle ago) | Highest |
| `2'b01` | `wb_data` | MEM→EX (2 cycles ago) | Lower |
| `2'b00` | `id_ex_rs_data` | No hazard (register file) | Default |

Forwarding is gated on: `reg_write == 1` AND `rd != x0`.

### 2.4 ISA Coverage

| Category | Instructions | Count |
|---|---|:---:|
| R-type ALU | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | 10 |
| I-type ALU | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | 9 |
| Load/Store | LW, SW | 2 |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU | 6 |
| Upper Imm. | LUI, AUIPC | 2 |
| Jump | JAL, JALR | 2 |
| **CUSTOM-0** | MAC, MAC_CLEAR, MAC_READ_LO, MAC_READ_HI | 4 |
| **Total** | | **35** |

---

## 3. The DSP Engine

### 3.1 MAC Unit Architecture

The `mac_unit` is a 4-state pipelined multiply-accumulate engine with a hidden 64-bit signed accumulator. It connects to the TCM via a dedicated weight-streaming bus (Port B).

**Interface:**
```systemverilog
input  logic [31:0] operand_a    // Data sample (from forwarded_a)
input  logic [31:0] tcm_data     // Filter weight (from TCM Port B output)
output logic [63:0] mac_result_full  // 64-bit accumulator value
output logic        mac_busy     // High during computation
output logic        mac_overflow // Sticky signed overflow flag
```

### 3.2 Finite State Machine

```
          mac_start=1
    ┌────────────────┐
    │                ▼
  IDLE ──────► S_INPUT ──────► S_MULTIPLY ──────► S_ACCUMULATE
    ▲                                                    │
    └────────────────────────────────────────────────────┘
```

| State | Cycle | Operations |
|---|:---:|---|
| **IDLE** | 0 | Latch `a_reg ← $signed(operand_a)`. TCM address presented on Port B. |
| **S_INPUT** | 1 | TCM data arrives (1-cycle BRAM latency absorbed). `product_reg ← a_reg × $signed(tcm_data)` — full 64-bit signed multiply. |
| **S_MULTIPLY** | 2 | `next_accum = accumulator + product_reg`. Saturation check: if both operands share a sign but the sum flips, clamp to `INT64_MAX` or `INT64_MIN` and set sticky `overflow_flag`. |
| **S_ACCUMULATE** | 3 | Idle return. `mac_busy → 0`. Result valid on `mac_result_full`. |

### 3.3 Signed Saturation Arithmetic

```systemverilog
if ((accumulator[63] == product_reg[63]) &&
    (next_accum[63] != accumulator[63])) begin
    overflow_flag <= 1'b1;              // Sticky — survives across MACs
    accumulator   <= (accumulator[63]) ? 64'h8000000000000000   // INT64_MIN
                                       : 64'h7FFFFFFFFFFFFFFF;  // INT64_MAX
end
```

**Verified corner case:** `0x80000000 × 0x80000000` computed twice:
- First MAC: `ACC = 0x4000000000000000` (positive, fits)
- Second MAC: `ACC + 0x4000000000000000 = 0x8000000000000000` (sign flip!) → saturated to `0x7FFFFFFFFFFFFFFF`

### 3.4 DSP48E1 Inference

The `$signed(a_reg) * $signed(tcm_data)` expression maps to the Artix-7's DSP48E1 25×18 signed multiplier primitive. Vivado infers this automatically when:
1. Both operands use `$signed()` cast
2. The result width (64 bits) accommodates the full product
3. The multiply is inside an `always_ff` (registered, not combinational)

---

## 4. The Memory Subsystem & Harvard Bypass

### 4.1 Memory Map

| Address Range | Target | Access | Latency |
|---|---|---|:---:|
| `0x00000000 – 0x000000FF` | Instruction ROM | Read-only (IF) | 0 cycles |
| `0x00000000 – 0x000000FF` | Data Memory | R/W (MEM) | 0 cycles |
| `0x80000000 – 0x80000FFF` | **TCM (BRAM)** | R/W (MEM, Port A) | 1 cycle |
| TCM internal | **TCM Port B** | Read-only (EX, MAC) | 1 cycle |

### 4.2 TCM Dual-Port Architecture

```
                ┌─────────────────────────────┐
                │     BRAM36E1 (4KB)          │
                │     1024 × 32-bit           │
   CPU Bus      │     (* ram_style="block" *) │      MAC Unit
   (MEM Stage)  │                             │      (EX Stage)
                │                             │
  addra ───────▶│ Port A                      │◀─────── addrb
  dina  ───────▶│ (R/W, Write-First)    Port B│         (forwarded_b[11:2])
  wea   ───────▶│                   (Read-Only)│
  douta ◀───────│                             │───────▶ doutb → tcm_data
                └─────────────────────────────┘
```

**Port A — CPU Bus (Write-First Mode):**
- Connected to the MEM stage via the address decoder
- Write address: `ex_mem_alu_result[11:2]` (MEM stage)
- Read address: `alu_result[11:2]` (EX stage — **critical latency fix**)
- Address MUX: `tcm_addra = tcm_wea ? ex_mem_alu_result[11:2] : alu_result[11:2]`
- Write-First: on simultaneous read+write to same address on Port A, returns **new** data

**Port B — MAC Weight Stream (Read-Only):**
- Address driven by `forwarded_b[11:2]` (rs2 of MAC instruction = TCM byte address)
- 1-cycle read latency absorbed by MAC's `S_INPUT` state
- Continuously reading (every cycle), but MAC only uses data during `S_INPUT`

### 4.3 Timing Alignment (Port B ↔ MAC FSM)

| Cycle | MAC State | TCM Port B | Data Flow |
|:---:|---|---|---|
| N | IDLE (start) | `addrb = forwarded_b[11:2]` | Address presented |
| N+1 | S_INPUT | `doutb = mem[addr]` (valid) | `product_reg ← a_reg × doutb` |
| N+2 | S_MULTIPLY | — | Accumulate with saturation |
| N+3 | S_ACCUMULATE | — | Result valid, busy→0 |

---

## 5. Synthesis & Physical Implementation

### 5.1 Target Device

| Parameter | Value |
|---|---|
| Device | xc7a35tcpg236-1 |
| Board | Digilent Basys 3 |
| Speed grade | -1 (slowest) |
| Clock target | 100 MHz (10 ns period) |
| Clock pin | W5 (LVCMOS33) |
| Reset | U18 — BTNC (active-high) |

### 5.2 Expected Resource Utilization

| Resource | Used | Available | Usage |
|---|:---:|:---:|:---:|
| LUT6 | ~800–1200 | 20,800 | ~5% |
| Flip-Flops | ~600–900 | 41,600 | ~2% |
| BRAM36E1 | 1 (TCM) | 50 | 2% |
| DSP48E1 | 1–3 (MAC multiplier) | 90 | ~2% |
| I/O | 18 (clk+reset+16 LEDs) | 106 | 17% |

### 5.3 Physical I/O — Anchor Logic

The design exposes 16 LED outputs (`debug_pc[7:0]`, `debug_wb[7:0]`) that serve as **anchor logic** — creating a dependency chain from every internal pipeline signal to physical I/O pins. This prevents Vivado's `opt_design` from optimizing away the netlist. The `debug_wb` signal depends on the ALU, MAC, TCM, data memory, forwarding unit, and all 5 pipeline stages, ensuring complete preservation.

### 5.4 Constraint Summary

| Constraint | Value | Purpose |
|---|---|---|
| `create_clock` | 10 ns (100 MHz) | Primary timing target |
| `set_false_path` | Reset input | Exclude async button from Fmax |
| `CFGBVS` | VCCO, 3.3V | Basys 3 I/O bank voltage |
| `SPI_BUSWIDTH` | 4 | Quad-SPI flash programming |
