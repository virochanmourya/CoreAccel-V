<p align="center">
  <strong>🔬 CoreAccel-V</strong><br/>
  <em>A 5-Stage Pipelined RISC-V RV32I Processor with DSP MAC Extension</em><br/>
  <sub>Architecture Reference Document — Rev 2A · June 2026</sub>
</p>

---

<p align="center">
  <code>RV32I</code> · <code>5-Stage Pipeline</code> · <code>CUSTOM-0 MAC DSP</code> · <code>72-bit Accumulator</code> · <code>Artix-7 FPGA</code>
</p>

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. SoC Block Diagram](#2-soc-block-diagram)
- [3. Top-Level Port Map](#3-top-level-port-map)
- [4. Pipeline Architecture](#4-pipeline-architecture)
- [5. Pipeline Datapath and Forwarding](#5-pipeline-datapath-and-forwarding)
- [6. Memory Hierarchy](#6-memory-hierarchy)
- [7. MAC Unit — DSP Accelerator](#7-mac-unit--dsp-accelerator)
- [8. Pipeline Control and Hazard Logic](#8-pipeline-control-and-hazard-logic)
- [9. Address Decoder and Memory Map](#9-address-decoder-and-memory-map)
- [10. Branch Resolution Logic](#10-branch-resolution-logic)
- [11. ISA and Control Signal Reference](#11-isa-and-control-signal-reference)
- [12. Phase 2A Hardening](#12-phase-2a-hardening)
- [13. Technical Specifications](#13-technical-specifications)
- [14. Module Instantiation Map](#14-module-instantiation-map)

---

## 1. Overview

**CoreAccel-V** is a 5-stage in-order pipelined RISC-V processor implementing the **RV32I** base integer ISA, extended with a **CUSTOM-0** DSP multiply-accumulate (MAC) unit featuring a **72-bit signed accumulator** with saturation arithmetic. The design targets the **Xilinx Artix-7** FPGA (Basys 3) and includes a complete SoC with UART, I2C GPIO, and 7-segment display peripherals.

> [!NOTE]
> This document describes the **Phase 2A hardened** architecture. All signal widths, control paths, and timing have been verified against the RTL source.

### Key Highlights

| Feature | Detail |
|:--------|:-------|
| ISA | RV32I Base Integer + CUSTOM-0 MAC |
| Pipeline | 5-stage in-order: IF → ID → EX → MEM → WB |
| Forwarding | Full 2-stage EX→EX and MEM→EX with priority |
| Hazard Detection | Load-use stall + MAC pipeline stall |
| DSP Extension | 4-cycle signed MAC, 72-bit accumulator, saturation |
| Memory | 8 KB IMEM (LUTRAM) · 256 B DMEM (LUTRAM) · 4 KB TCM (BRAM TDP) |
| Peripherals | UART TX 115200 8N1 · I2C GPIO · 4-digit 7-Segment |
| Target | Xilinx Artix-7 xc7a35tcpg236-1 (Basys 3) |

---

## 2. SoC Block Diagram

```mermaid
graph TB
    subgraph EXTERNAL_IO["External I/O"]
        CLK["clk"]
        RST["reset"]
        I2C_SCL["i2c_scl - bidirectional"]
        I2C_SDA["i2c_sda - bidirectional"]
        UART_TX["uart_tx_out"]
        SEG_OUT["seg 6:0"]
        DP_OUT["dp"]
        AN_OUT["an 3:0"]
        DBG_PC["debug_pc 7:0"]
        DBG_WB["debug_wb 7:0"]
    end

    subgraph TOP["cpu_pipeline_top.sv"]
        direction TB

        subgraph PIPE["5-Stage Pipeline Core"]
            IF_STAGE["IF Stage\npc_pipe + instruction_memory_pipe"]
            ID_STAGE["ID Stage\ncontrol_unit + imm_gen + regfile + hazard"]
            EX_STAGE["EX Stage\nalu + mac_unit + forwarding_unit"]
            MEM_STAGE["MEM Stage\ndata_memory + tcm_ram + peripherals"]
            WB_STAGE["WB Stage\nwriteback mux"]
        end

        IF_STAGE --> ID_STAGE
        ID_STAGE --> EX_STAGE
        EX_STAGE --> MEM_STAGE
        MEM_STAGE --> WB_STAGE
        WB_STAGE -.->|"WB-to-ID Bypass"| ID_STAGE

        subgraph PERIPH["Peripheral Bus"]
            UART["uart_tx\n115200 8N1"]
            SEG["seg_display\n4-digit hex"]
            I2C["I2C GPIO\nMMIO"]
        end
    end

    CLK --> TOP
    RST --> TOP
    MEM_STAGE --> PERIPH
    UART --> UART_TX
    SEG --> SEG_OUT
    SEG --> DP_OUT
    SEG --> AN_OUT
    I2C --> I2C_SCL
    I2C --> I2C_SDA
    IF_STAGE -.-> DBG_PC
    WB_STAGE -.-> DBG_WB
```

---

## 3. Top-Level Port Map

### `cpu_pipeline_top.sv`

| Direction | Port | Width | Description |
|:---------:|:-----|:-----:|:------------|
| `input` | `clk` | 1 | System clock |
| `input` | `reset` | 1 | Active-high synchronous reset |
| `output` | `debug_pc` | `[7:0]` | Lower 8 bits of program counter |
| `output` | `debug_wb` | `[7:0]` | Lower 8 bits of writeback data |
| `inout` | `i2c_scl` | 1 | I2C serial clock — bidirectional |
| `inout` | `i2c_sda` | 1 | I2C serial data — bidirectional |
| `output` | `uart_tx_out` | 1 | UART transmit pin |
| `output` | `seg` | `[6:0]` | 7-segment cathode drivers |
| `output` | `dp` | 1 | 7-segment decimal point |
| `output` | `an` | `[3:0]` | 7-segment anode drivers |

---

## 4. Pipeline Architecture

### 5-Stage Pipeline — Full Module and Signal Map

```mermaid
graph LR
    subgraph IF["IF Stage"]
        PC["u_pc\npc_pipe"]
        IMEM["u_imem\ninstruction_memory_pipe\n8KB LUTRAM"]
        PC -->|"pc 31:0 - addr 12:2"| IMEM
    end

    subgraph IFID["IF/ID Register"]
        IFID_R["u_if_id\nif_id_reg"]
    end

    subgraph ID["ID Stage"]
        CTRL["u_control\ncontrol_unit_pipe"]
        IMMGEN["u_imm_gen\nimm_gen_pipe"]
        REGFILE["u_regfile\nregister_file\n32x32-bit"]
        HAZARD["u_hazard\nhazard_detection_unit"]
    end

    subgraph IDEX["ID/EX Register"]
        IDEX_R["u_id_ex\nid_ex_reg"]
    end

    subgraph EX["EX Stage"]
        FWD["u_forward\nforwarding_unit"]
        ALU["u_alu\nalu\n32-bit + carry"]
        MAC["dsp_core\nmac_unit\n72-bit accum"]
        TCM_B["u_tcm Port B\nMAC weight read"]
        BRANCH["Branch Comparator\nBEQ BNE BLT BGE BLTU BGEU"]
    end

    subgraph EXMEM["EX/MEM Register"]
        EXMEM_R["u_ex_mem\nex_mem_reg"]
    end

    subgraph MEM["MEM Stage"]
        DMEM["u_dmem\ndata_memory\n256B LUTRAM"]
        TCM_A["u_tcm Port A\n4KB BRAM TDP"]
        UART_M["u_uart_tx\nuart_tx"]
        SEGD["u_seg_display\nseg_display"]
        ADDR_DEC["Address Decoder\naddr 31:30"]
    end

    subgraph MEMWB["MEM/WB Register"]
        MEMWB_R["u_mem_wb\nmem_wb_reg"]
    end

    subgraph WB["WB Stage"]
        WB_MUX["WB Mux\nmem_to_reg select"]
    end

    IMEM --> IFID_R
    PC --> IFID_R
    IFID_R --> CTRL
    IFID_R --> IMMGEN
    IFID_R --> REGFILE
    IFID_R --> HAZARD
    CTRL --> IDEX_R
    IMMGEN --> IDEX_R
    REGFILE --> IDEX_R
    IDEX_R --> FWD
    IDEX_R --> ALU
    IDEX_R --> MAC
    IDEX_R --> BRANCH
    FWD --> ALU
    FWD --> BRANCH
    FWD -->|"forwarded_b 11:2"| TCM_B
    TCM_B -->|"tcm_data signed"| MAC
    ALU --> EXMEM_R
    BRANCH -.->|"pc_redirect"| PC
    EXMEM_R --> ADDR_DEC
    ADDR_DEC --> DMEM
    ADDR_DEC --> TCM_A
    ADDR_DEC --> UART_M
    ADDR_DEC --> SEGD
    EXMEM_R --> MEMWB_R
    DMEM --> MEMWB_R
    TCM_A --> MEMWB_R
    MEMWB_R --> WB_MUX
    WB_MUX -.->|"WB-to-ID Bypass"| REGFILE
```

### Pipeline Register Contents

| Register | Signals |
|:---------|:--------|
| **IF/ID** | `pc[31:0]`, `instruction[31:0]` |
| **ID/EX** | `reg_write`, `mem_to_reg`, `mem_read`, `mem_write`, `alu_src`, `alu_control[3:0]`, `alu_src_a`, `pc_to_reg`, `jump`, `branch`, `is_mac`, `is_mac_clear`, `mac_to_reg`, `is_mac_read_hi`, `pc[31:0]`, `rs1_data[31:0]`, `rs2_data[31:0]`, `imm[31:0]`, `rs1_addr[4:0]`, `rs2_addr[4:0]`, `rd_addr[4:0]`, `funct3[2:0]` |
| **EX/MEM** | `reg_write`, `mem_to_reg`, `mem_read`, `mem_write`, `alu_result[31:0]`, `rs2_data[31:0]`, `rd_addr[4:0]` |
| **MEM/WB** | `reg_write`, `mem_to_reg`, `mem_data[31:0]`, `alu_result[31:0]`, `rd_addr[4:0]` |

---

## 5. Pipeline Datapath and Forwarding

### Forwarding and Bypass Network

```mermaid
graph TB
    subgraph REG_FILE["Register File - ID Stage"]
        RS1["rs1_data"]
        RS2["rs2_data"]
    end

    subgraph IDEX_PIPE["ID/EX Pipeline Register"]
        IDEX_RS1["id_ex_rs1_data"]
        IDEX_RS2["id_ex_rs2_data"]
        IDEX_RS1A["id_ex_rs1_addr"]
        IDEX_RS2A["id_ex_rs2_addr"]
    end

    subgraph FWD_UNIT["Forwarding Unit"]
        FWD_LOGIC["Priority Logic\nforward_a, forward_b"]
    end

    subgraph FWD_MUX["Forwarding Muxes - EX Stage"]
        MUX_A["MUX A\n00: reg file\n01: WB result\n10: EX/MEM result"]
        MUX_B["MUX B\n00: reg file\n01: WB result\n10: EX/MEM result"]
    end

    subgraph ALU_MUX["ALU Input Muxes"]
        ALU_MUX1["alu_in1 MUX\nalu_src_a ? pc : forwarded_a"]
        ALU_MUX2["alu_in2 MUX\nalu_src ? imm : forwarded_b"]
    end

    subgraph RESULTS["Pipeline Results"]
        EX_MEM_RES["EX/MEM alu_result\nPriority: HIGH"]
        MEM_WB_RES["MEM/WB wb_data\nPriority: LOW"]
    end

    subgraph WB_BYPASS["WB-to-ID Bypass"]
        WB_MUX_A["Combinational MUX\nSame-cycle read-after-write"]
    end

    RS1 --> IDEX_RS1
    RS2 --> IDEX_RS2
    IDEX_RS1 --> MUX_A
    IDEX_RS2 --> MUX_B
    IDEX_RS1A --> FWD_LOGIC
    IDEX_RS2A --> FWD_LOGIC
    FWD_LOGIC -->|"forward_a"| MUX_A
    FWD_LOGIC -->|"forward_b"| MUX_B
    EX_MEM_RES -->|"2b10"| MUX_A
    EX_MEM_RES -->|"2b10"| MUX_B
    MEM_WB_RES -->|"2b01"| MUX_A
    MEM_WB_RES -->|"2b01"| MUX_B
    MUX_A --> ALU_MUX1
    MUX_B --> ALU_MUX2
    ALU_MUX1 --> ALU_CORE["ALU"]
    ALU_MUX2 --> ALU_CORE
    MEM_WB_RES -.->|"bypass"| WB_BYPASS
    WB_BYPASS -.-> RS1
    WB_BYPASS -.-> RS2
```

### Forwarding Unit Priority Logic

```
forward_a / forward_b encoding:
  2'b10 → EX/MEM result   (highest priority — most recent producer)
  2'b01 → MEM/WB result   (lower priority — older producer)
  2'b00 → Register file   (no hazard)

Condition for EX/MEM forward:
  ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs{1,2}

Condition for MEM/WB forward (only if EX/MEM does NOT forward):
  mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs{1,2}
```

### EX Stage Result Mux — Priority Encoding

```
ex_result (output to EX/MEM pipeline register):
  ┌─ Priority 1: JAL / JALR     → id_ex_pc + 4   (return address)
  ├─ Priority 2: MAC_READ       → sliced_mac_result
  └─ Priority 3: Default        → alu_result
```

### MAC Read Slicer

```
sliced_mac_result = is_mac_read_hi ? mac_result_full[63:32]
                                   : mac_result_full[31:0]
```

---

## 6. Memory Hierarchy

```mermaid
graph TB
    subgraph CPU["Processor Core"]
        IF_PC["IF Stage - PC"]
        EX_MAC["EX Stage - MAC Unit"]
        MEM_PORT["MEM Stage - Load/Store"]
    end

    subgraph IMEM["Instruction Memory"]
        IMEM_BLK["instruction_memory_pipe\n8 KB — 2048 x 32-bit\nLUTRAM — Async Read\naddr = pc 12:2\nInit: firmware.hex"]
    end

    subgraph DMEM["Data Memory"]
        DMEM_BLK["data_memory\n256 B — 64 x 32-bit\nLUTRAM — Async Read\nRegion: 0x0000_0000"]
    end

    subgraph TCM["Tightly Coupled Memory"]
        TCM_BLK["tcm_ram\n4 KB — 1024 x 32-bit\nBRAM — True Dual Port\nSync Read — Write-First\nRegion: 0x8000_0000"]
        PORT_A["Port A\nCPU Load/Store\nMEM Stage"]
        PORT_B["Port B\nMAC Weight Streaming\nEX Stage — Read Only"]
    end

    subgraph PERIPH_MEM["Peripheral MMIO"]
        MMIO["0xC000_0000 Region\nI2C GPIO - UART TX\n7-Seg Display - Debug"]
    end

    IF_PC -->|"Fetch"| IMEM_BLK
    MEM_PORT -->|"addr 31:30 = 2b00"| DMEM_BLK
    MEM_PORT -->|"addr 31:30 = 2b10"| PORT_A
    EX_MAC -->|"forwarded_b 11:2"| PORT_B
    PORT_A --> TCM_BLK
    PORT_B --> TCM_BLK
    MEM_PORT -->|"addr 31:30 = 2b11"| MMIO
```

### Memory Summary

| Memory | Type | Size | Width | Depth | Read Latency | Interface |
|:-------|:-----|:-----|:-----:|:-----:|:------------:|:----------|
| IMEM | LUTRAM | 8 KB | 32-bit | 2048 | Async (0 cycle) | Single-port, word-addressed `[12:2]` |
| DMEM | LUTRAM | 256 B | 32-bit | 64 | Async (0 cycle) | Single-port, word-addressed |
| TCM | BRAM TDP | 4 KB | 32-bit | 1024 | Sync (1 cycle) | True Dual-Port, write-first mode |

> [!IMPORTANT]
> TCM Port A uses an address from the **EX stage** (1-cycle ahead) for reads to compensate for BRAM synchronous read latency. This ensures the read data is available by the time the MEM stage needs it.

---

## 7. MAC Unit — DSP Accelerator

### MAC Unit Block Diagram

```mermaid
graph LR
    subgraph INPUTS["MAC Inputs"]
        OP_A["operand_a\nsigned 31:0\nfrom forwarded_a"]
        TCM_D["tcm_data\nsigned 31:0\nfrom TCM Port B"]
        MAC_CLR["clear_accum\nfrom is_mac_clear"]
        MAC_ABT["mac_abort\nfrom pc_redirect"]
    end

    subgraph MAC_CORE["mac_unit - dsp_core"]
        direction TB
        MULT["Signed Multiplier\n32 x 32 = 64-bit"]
        ACCUM["72-bit Signed Accumulator\nwith Saturation"]
        SAT["Saturation Logic\nSAT_MAX / SAT_MIN"]
        FSM_BLOCK["4-Cycle FSM Controller"]
    end

    subgraph OUTPUTS["MAC Outputs"]
        RESULT["mac_result_full\nsigned 63:0"]
        BUSY["mac_busy"]
    end

    OP_A --> MULT
    TCM_D --> MULT
    MULT --> ACCUM
    ACCUM --> SAT
    SAT --> ACCUM
    MAC_CLR --> ACCUM
    MAC_ABT --> FSM_BLOCK
    FSM_BLOCK --> MULT
    FSM_BLOCK --> ACCUM
    ACCUM -->|"accum 63:0"| RESULT
    FSM_BLOCK --> BUSY
```

### MAC FSM State Diagram

```mermaid
stateDiagram-v2
    [*] --> IDLE

    IDLE --> S_INPUT : mac_start
    IDLE --> IDLE : no start

    S_INPUT --> S_MULTIPLY : "Latch operands"
    S_MULTIPLY --> S_ACCUMULATE : "Product ready"
    S_ACCUMULATE --> IDLE : "Accumulate + Saturate"

    IDLE --> IDLE : mac_abort
    S_INPUT --> IDLE : mac_abort
    S_MULTIPLY --> IDLE : mac_abort
    S_ACCUMULATE --> IDLE : mac_abort

    note right of IDLE
        mac_abort forces FSM → IDLE
        and holds all registers
    end note

    note right of S_ACCUMULATE
        72-bit accumulator with
        SAT_MAX / SAT_MIN clamping
    end note
```

### MAC Operations via CUSTOM-0 Encoding

| Instruction | Opcode | funct3 / funct7 | Description |
|:------------|:-------|:-----------------|:------------|
| `MAC rd, rs1, rs2` | `0001011` | — | Multiply `rs1 × TCM[rs2]`, accumulate into 72-bit register |
| `MAC_CLEAR` | `0001011` | — | Clear the 72-bit accumulator to zero |
| `MAC_READ_LO rd` | `0001011` | — | Read `accumulator[31:0]` into `rd` |
| `MAC_READ_HI rd` | `0001011` | — | Read `accumulator[63:32]` into `rd` |

### MAC Pipeline Stall Logic

```
mac_start_pulse   = is_mac_ex & ~mac_started_reg & ~mac_busy_ex
mac_stall_request = is_mac_ex & ~(mac_started_reg & ~mac_busy_ex)

When MAC is active:
  - Pipeline stalls (IF, ID, EX held)
  - EX/MEM register is flushed
  - MAC runs for 4 cycles: IDLE → S_INPUT → S_MULTIPLY → S_ACCUMULATE → IDLE
```

### Accumulator Saturation

```
Accumulator width: 72 bits (signed)
Output width:      64 bits (signed) = accumulator[63:0]

If accumulator > SAT_MAX  → clamp to SAT_MAX
If accumulator < SAT_MIN  → clamp to SAT_MIN

This prevents silent wraparound in long MAC chains (e.g., neural network dot products).
```

---

## 8. Pipeline Control and Hazard Logic

### Hazard Detection — Load-Use Stall

```mermaid
graph TB
    subgraph HAZARD_IN["Hazard Unit Inputs"]
        IDEX_MR["id_ex_mem_read"]
        IDEX_RD["id_ex_rd"]
        IFID_RS1["if_id_rs1"]
        IFID_RS2["if_id_rs2"]
        RS1_V["rs1_valid"]
        RS2_V["rs2_valid"]
    end

    subgraph HAZARD_LOGIC["hazard_detection_unit"]
        DETECT["Load-Use Detector\nstall = id_ex_mem_read\n  and id_ex_rd != 0\n  and rs1 or rs2 match"]
    end

    subgraph HAZARD_OUT["Stall Signals"]
        STALL["stall signal"]
    end

    IDEX_MR --> DETECT
    IDEX_RD --> DETECT
    IFID_RS1 --> DETECT
    IFID_RS2 --> DETECT
    RS1_V --> DETECT
    RS2_V --> DETECT
    DETECT --> STALL
```

### Load-Use Stall Condition

```verilog
stall = id_ex_mem_read
      && (id_ex_rd != 5'b0)
      && (  (rs1_valid && id_ex_rd == if_id_rs1)
         || (rs2_valid && id_ex_rd == if_id_rs2) );
```

### Pipeline Control Signal Matrix

| Signal | Formula | Purpose |
|:-------|:--------|:--------|
| `pc_redirect` | `branch_taken \| id_ex_jump` | Redirect PC on taken branch or jump |
| `pc_write` | `~(stall \| mac_stall) \| pc_redirect` | Enable PC update; redirect overrides stall |
| `if_id_stall` | `(stall \| mac_stall) & ~pc_redirect` | Freeze IF/ID register |
| `if_id_flush` | `pc_redirect` | Flush IF/ID on redirect |
| `id_ex_flush` | `stall \| pc_redirect` | Insert bubble on stall or redirect |
| `id_ex_stall` | `mac_stall_request` | Freeze ID/EX during MAC |
| `ex_mem_flush` | `mac_stall_request` | Flush EX/MEM during MAC stall |

### Stall and Flush Priority

```
                    ┌──────────────────────────────────────┐
                    │         pc_redirect (highest)        │
                    │   Overrides all stalls, flushes      │
                    │   IF/ID and ID/EX pipeline regs      │
                    ├──────────────────────────────────────┤
                    │         mac_stall_request            │
                    │   Stalls IF, ID, EX stages           │
                    │   Flushes EX/MEM register            │
                    ├──────────────────────────────────────┤
                    │         load-use stall               │
                    │   Stalls IF, ID stages               │
                    │   Inserts bubble in ID/EX            │
                    └──────────────────────────────────────┘
```

---

## 9. Address Decoder and Memory Map

### Address Decoder Diagram

```mermaid
graph TB
    subgraph ADDR_INPUT["Address Input from EX/MEM"]
        ADDR["alu_result 31:0"]
    end

    subgraph DECODE_L1["Level 1 Decode — addr 31:30"]
        D00["2b00\nDMEM Region"]
        D10["2b10\nTCM Region"]
        D11["2b11\nPeripheral Region"]
    end

    subgraph DECODE_L2["Level 2 Decode — addr 3:2"]
        P00["2b00\nI2C GPIO"]
        P01["2b01\nUART TX"]
        P10["2b10\n7-Segment"]
        P11["2b11\nDebug Readback"]
    end

    subgraph TARGETS["Targets"]
        T_DMEM["data_memory\n64 words - 256 B"]
        T_TCM["tcm_ram Port A\n1024 words - 4 KB"]
        T_I2C["I2C GPIO Register"]
        T_UART["uart_tx FIFO"]
        T_SEG["seg_display Data"]
        T_DBG["Debug Status"]
    end

    ADDR --> D00
    ADDR --> D10
    ADDR --> D11
    D00 --> T_DMEM
    D10 --> T_TCM
    D11 --> DECODE_L2
    P00 --> T_I2C
    P01 --> T_UART
    P10 --> T_SEG
    P11 --> T_DBG
```

### Memory Map Table

| Base Address | End Address | Size | Region | Access | Description |
|:-------------|:-----------|:-----|:-------|:------:|:------------|
| `0x0000_0000` | `0x3FFF_FFFF` | 256 B | DMEM | R/W | Data memory — LUTRAM async |
| `0x8000_0000` | `0xBFFF_FFFF` | 4 KB | TCM | R/W | Tightly coupled — BRAM TDP |
| `0xC000_0000` | — | 4 B | I2C GPIO | R/W | I2C SCL/SDA bidirectional |
| `0xC000_0004` | — | 4 B | UART TX | W | UART transmit, 115200 8N1 |
| `0xC000_0008` | — | 4 B | 7-Segment | W | 4-digit hex, 1 kHz refresh |
| `0xC000_000C` | — | 4 B | Debug | R | Debug readback register |

### MEM Read Mux Priority

```
mem_read_data =
    gpio_access  → gpio_rdata
    tcm_access   → tcm_douta
    default      → dmem_read_data
```

---

## 10. Branch Resolution Logic

### Branch Resolution in EX Stage

```mermaid
graph TB
    subgraph OPERANDS["Branch Operands"]
        FWD_A["forwarded_a - rs1"]
        FWD_B["forwarded_b - rs2"]
    end

    subgraph COMPARE["Branch Comparator"]
        BEQ_C["BEQ: a == b"]
        BNE_C["BNE: a != b"]
        BLT_C["BLT: signed a < b"]
        BGE_C["BGE: signed a >= b"]
        BLTU_C["BLTU: unsigned a < b"]
        BGEU_C["BGEU: unsigned a >= b"]
    end

    subgraph TARGET["Target Computation"]
        PC_BR["pc_branch\nid_ex_pc + id_ex_imm"]
        JALR_T["jalr_target\nalu_result AND 0xFFFFFFFE"]
    end

    subgraph SELECT["Redirect MUX"]
        RED_MUX["redirect_target\njump and alu_src ? jalr_target\n: pc_branch"]
    end

    subgraph OUTPUT["Control Output"]
        TAKEN["branch_taken"]
        REDIR["pc_redirect\nbranch_taken OR jump"]
    end

    FWD_A --> COMPARE
    FWD_B --> COMPARE
    COMPARE --> TAKEN
    PC_BR --> RED_MUX
    JALR_T --> RED_MUX
    TAKEN --> REDIR
    RED_MUX -->|"to pc_pipe"| OUTPUT
```

### Branch / Jump Target Summary

| Type | Target Computation | Condition |
|:-----|:-------------------|:----------|
| **BEQ/BNE/BLT/BGE/BLTU/BGEU** | `id_ex_pc + id_ex_imm` | Comparator result on `forwarded_a`, `forwarded_b` |
| **JAL** | `id_ex_pc + id_ex_imm` | Always taken; writes `PC+4` to `rd` |
| **JALR** | `alu_result & 0xFFFFFFFE` | Always taken; writes `PC+4` to `rd` |

### Redirect Target MUX

```
redirect_target = (id_ex_jump && alu_src) ? jalr_target : pc_branch

Where:
  pc_branch   = id_ex_pc + id_ex_imm
  jalr_target = (forwarded_a + id_ex_imm) & 32'hFFFFFFFE
```

---

## 11. ISA and Control Signal Reference

### Supported Instructions — RV32I + CUSTOM-0

| Type | Opcode | Instructions | Count |
|:-----|:-------|:-------------|:-----:|
| **R-type** | `0110011` | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | 10 |
| **I-type ALU** | `0010011` | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | 9 |
| **Load** | `0000011` | LW | 1 |
| **Store** | `0100011` | SW | 1 |
| **Branch** | `1100011` | BEQ, BNE, BLT, BGE, BLTU, BGEU | 6 |
| **LUI** | `0110111` | LUI | 1 |
| **AUIPC** | `0010111` | AUIPC | 1 |
| **JAL** | `1101111` | JAL | 1 |
| **JALR** | `1100111` | JALR | 1 |
| **CUSTOM-0** | `0001011` | MAC, MAC_CLEAR, MAC_READ_LO, MAC_READ_HI | 4 |
| | | **Total** | **35** |

### ALU Operations

| `alu_control[3:0]` | Operation | RTL Expression |
|:-------------------:|:----------|:---------------|
| `0000` | ADD | `{1'b0,a} + {1'b0,b}` — 33-bit carry chain |
| `0001` | SUB | `{1'b0,a} - {1'b0,b}` — 33-bit carry chain |
| `0010` | SLL | `a << b[4:0]` |
| `0011` | SLT | `($signed(a) < $signed(b)) ? 1 : 0` |
| `0100` | SLTU | `(a < b) ? 1 : 0` |
| `0101` | XOR | `a ^ b` |
| `0110` | SRL | `a >> b[4:0]` |
| `0111` | SRA | `$signed(a) >>> b[4:0]` |
| `1000` | OR | `a \| b` |
| `1001` | AND | `a & b` |
| `1010` | PASS_B | `b` — used for LUI pass-through |

### ALU Flags

| Flag | Computation |
|:-----|:------------|
| `zero` | `result == 0` |
| `sign` | `result[31]` |
| `overflow` | Signed overflow detection |
| `carry` | `add_result[32]` or `sub_result[32]` |

### Control Signals by Instruction Type

| Signal | R-type | I-ALU | LW | SW | Branch | LUI | AUIPC | JAL | JALR | MAC |
|:-------|:------:|:-----:|:--:|:--:|:------:|:---:|:-----:|:---:|:----:|:---:|
| `reg_write` | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mem_to_reg` | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `mem_read` | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `mem_write` | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `alu_src` | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| `alu_src_a` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| `branch` | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `jump` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| `is_mac` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### Immediate Generation

| Instruction Type | Bit Assembly | Sign Extension |
|:-----------------|:-------------|:---------------|
| **I-type** | `{instr[31:20]}` | `instr[31]` replicated to 32 bits |
| **S-type** | `{instr[31:25], instr[11:7]}` | `instr[31]` replicated |
| **B-type** | `{instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}` | `instr[31]` replicated |
| **U-type** | `{instr[31:12], 12'b0}` | Upper 20 bits, lower 12 zero |
| **J-type** | `{instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}` | `instr[31]` replicated |

---

## 12. Phase 2A Hardening

The Phase 2A revision applies critical robustness improvements to the MAC datapath and pipeline control. These changes prevent silent data corruption in signed arithmetic chains.

| Area | Issue | Fix Applied |
|:-----|:------|:------------|
| **MAC Port Signedness** | Operand ports were implicitly unsigned | Explicit `signed [31:0]` declarations on `operand_a` and `tcm_data` |
| **Sign Extension** | Missing sign extension on MAC operands entering the multiplier | Explicit sign-extension logic ensures correct 64-bit products for negative values |
| **Saturation Parameters** | Hardcoded magic numbers for saturation bounds | Named parameters `SAT_MAX` and `SAT_MIN` for the 72-bit accumulator |
| **MAC Abort Mechanism** | No mechanism to cancel in-flight MAC on branch/jump | `mac_abort` signal wired to `pc_redirect`; forces FSM → IDLE and holds registers |
| **Accumulator Width** | 64-bit accumulator could overflow during long chains | Extended to 72-bit signed accumulator with headroom for extended MAC sequences |

> [!TIP]
> The `mac_abort` mechanism is critical for correctness: without it, a branch misprediction during a 4-cycle MAC would leave stale data in the accumulator. The abort signal forces an immediate return to IDLE and preserves register state.

---

## 13. Technical Specifications

| Specification | Value |
|:--------------|:------|
| **ISA** | RISC-V RV32I + CUSTOM-0 |
| **Pipeline Depth** | 5 stages (IF → ID → EX → MEM → WB) |
| **Pipeline Type** | In-order, single-issue |
| **Data Width** | 32-bit |
| **Register File** | 32 × 32-bit, x0 hardwired to zero |
| **Register Read** | Async read, 2 read ports |
| **Register Write** | Sync write, 1 write port |
| **ALU** | 32-bit + 33-bit carry chain |
| **MAC Accumulator** | 72-bit signed with saturation |
| **MAC Latency** | 4 cycles (IDLE→INPUT→MULTIPLY→ACCUMULATE) |
| **Instruction Memory** | 8 KB, 2048×32, LUTRAM, async |
| **Data Memory** | 256 B, 64×32, LUTRAM, async |
| **TCM** | 4 KB, 1024×32, BRAM TDP, sync, write-first |
| **Forwarding** | 2-stage: EX→EX, MEM→EX with priority |
| **WB Bypass** | Combinational same-cycle read-after-write |
| **Hazard Detection** | Load-use stall + MAC stall |
| **Branch Resolution** | EX stage, 1-cycle penalty |
| **UART** | TX only, 115200 baud, 8N1 |
| **Display** | 4-digit 7-segment, 1 kHz multiplex refresh |
| **Target FPGA** | Xilinx Artix-7 xc7a35tcpg236-1 |
| **Target Board** | Digilent Basys 3 |
| **HDL** | SystemVerilog |
| **Module Count** | 17 instances in top-level |

---

## 14. Module Instantiation Map

| # | Instance Name | Module | Pipeline Stage | Description |
|:-:|:--------------|:-------|:---------------|:------------|
| 1 | `u_pc` | `pc_pipe` | IF | Program counter with stall, redirect |
| 2 | `u_imem` | `instruction_memory_pipe` | IF | 8 KB instruction memory, LUTRAM |
| 3 | `u_if_id` | `if_id_reg` | IF→ID | Pipeline register |
| 4 | `u_control` | `control_unit_pipe` | ID | Full RV32I + CUSTOM-0 decoder |
| 5 | `u_imm_gen` | `imm_gen_pipe` | ID | Immediate generator (I/S/B/U/J) |
| 6 | `u_regfile` | `register_file` | ID/WB | 32×32 register file, async read |
| 7 | `u_hazard` | `hazard_detection_unit` | ID | Load-use stall detection |
| 8 | `u_id_ex` | `id_ex_reg` | ID→EX | Pipeline register (widest) |
| 9 | `u_forward` | `forwarding_unit` | EX | 2-stage forwarding with priority |
| 10 | `u_alu` | `alu` | EX | 32-bit ALU, 33-bit carry chain |
| 11 | `dsp_core` | `mac_unit` | EX | 4-cycle MAC, 72-bit accumulator |
| 12 | `u_ex_mem` | `ex_mem_reg` | EX→MEM | Pipeline register |
| 13 | `u_dmem` | `data_memory` | MEM | 256 B data memory, LUTRAM |
| 14 | `u_tcm` | `tcm_ram` | MEM+EX | 4 KB TCM, BRAM TDP |
| 15 | `u_uart_tx` | `uart_tx` | MEM | UART transmitter, 115200 8N1 |
| 16 | `u_seg_display` | `seg_display` | MEM | 4-digit 7-segment controller |
| 17 | `u_mem_wb` | `mem_wb_reg` | MEM→WB | Pipeline register |

---

<p align="center">
  <sub>CoreAccel-V Architecture Document · Rev 2A · Generated June 2026</sub><br/>
  <sub>Verified against RTL source · All signal widths and control paths confirmed</sub>
</p>
