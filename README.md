# **CoreAccel-V**

**A 5-Stage Pipelined RV32I System-on-Chip with Tightly-Coupled DSP Acceleration**

CoreAccel-V is a custom RISC-V soft-core designed to prove that a general-purpose processor can be augmented with a tightly coupled DSP engine and successfully close timing at **100 MHz on a low-cost Xilinx Artix-7 FPGA**.

Written entirely in modern **SystemVerilog (IEEE 1800-2017)**, the architecture prioritizes deterministic execution, cycle-accurate physical memory mappings, and strict synthesis equivalency over high-level abstractions.

## **🚀 Key Architectural Features**

* **5-Stage In-Order Pipeline**: Classic IF → ID → EX → MEM → WB datapath with full hazard resolution (data forwarding, load-use stalls, and 1-cycle branch flush penalties).  
* **64-Bit Saturating MAC Unit**: A dedicated multi-cycle DSP coprocessor integrated directly into the Execute (EX) stage. It maps automatically to Xilinx DSP48E1 hard multiplier slices to accelerate FIR/IIR filters and vector workloads.  
* **Dual Memory Architecture**:  
  * **Tightly Coupled Memory (TCM)**: A 4KB True Dual-Port memory mapped to a single Xilinx BRAM36E1 tile. Port A acts as a standard CPU interface, while Port B streams DSP weights directly to the MAC unit with a guaranteed deterministic 1-cycle latency.  
  * **Data Memory**: Distributed RAM for general-purpose CPU loads and stores, preventing standard memory accesses from stalling the DSP pipeline.  
* **Zero-Latch Design**: Fully compliant SystemVerilog utilizing strict always\_ff and always\_comb structures to guarantee simulation-to-synthesis parity.

## **🛠 Target Hardware & Utilization**

The design is constrained and physically validated for the **Digilent Basys 3 (Xilinx Artix-7 xc7a35tcpg236-1)**.

| Resource | Used | Available | Utilization |
| :---- | :---- | :---- | :---- |
| **LUT6** | \~1,200 | 20,800 | \~5.8% |
| **Flip-Flops** | \~1,500 | 41,600 | \~3.6% |
| **BRAM36E1** | 1 | 50 | 2.0% |
| **DSP48E1** | 4 | 90 | 4.4% |
| **Max Freq** | 100 MHz | \- | \- |

## **📂 Repository Structure**

CoreAccel-V/  
├── rtl/               \# Synthesizable SystemVerilog IP core files  
├── sim/               \# Verification environments, testbenches, and memory payloads  
├── docs/              \# Detailed microarchitecture specs and timing reports  
├── constraints/       \# Xilinx XDC physical constraint files  
└── scripts/           \# Automation scripts for synthesis and simulation

## **🧮 Custom DSP ISA (CUSTOM-0)**

CoreAccel-V extends the base RV32I instruction set using the CUSTOM-0 opcode space (7'b0001011) to expose the MAC unit to software:

| Instruction | funct3 | Operation | Description |
| :---- | :---- | :---- | :---- |
| MAC rs1, rs2 | 000 | Acc \+= rs1 × TCM\[rs2\] | Multiplies rs1 by the TCM weight at byte-address rs2 |
| MAC\_CLEAR | 001 | Acc ← 0, OVF ← 0 | Resets the 64-bit accumulator and overflow flags |
| MAC\_READ\_LO rd | 011 | rd ← Acc\[31:0\] | Reads the lower 32 bits of the accumulator |
| MAC\_READ\_HI rd | 100 | rd ← Acc\[63:32\] | Reads the upper 32 bits of the accumulator |

*Note: The accumulator utilizes signed saturation to ±2⁶³ to prevent silent wraparound on overflow.*

## **⚙️ Getting Started**

### **Prerequisites**

* **Fast Functional Simulation**: Icarus Verilog (iverilog) or Verilator.  
* **Synthesis & Implementation**: Xilinx Vivado 2020.2 or newer.  
* **Target Hardware**: Digilent Basys 3 (Artix-7 xc7a35t).

### **1\. Lightweight Verification (Icarus Verilog)**

To quickly run the core testbenches and verify hazard logic without spinning up a Vivado project:

cd sim  
iverilog \-g2012 \-I ../rtl \-o sim\_build/tcm\_test tb\_tcm\_corner\_cases.sv ../rtl/\*.sv  
vvp sim\_build/tcm\_test

*(View generated waveforms using GTKWave by opening the resulting .vcd file).*

### **2\. FPGA Synthesis (Vivado)**

The project relies on standard Xilinx Vivado flows for physical mapping:

1. Create a new Vivado project targeting the xc7a35tcpg236-1 device.  
2. Add all SystemVerilog (.sv) files from the rtl/ directory as design sources.  
3. Add the physical constraints found in constraints/cpu\_pipeline\_top.xdc.  
4. Run Synthesis, Implementation, and generate the bitstream to program the Basys 3 board.

*(Note: Vivado xsim can also be used for simulation by importing the sim/ directory as simulation sources).*

## **📄 Documentation**

For a deep dive into the memory map, hazard handling, pipeline forwarding architecture, and physical inference strategies, please refer to the primary architectural spec:

* [The CoreAccel-V Architecture](http://docs.google.com/docs/The_CoreAccel_V_Architecture.md)  
* [Engineering Methodology & Timing](http://docs.google.com/docs/methodology_report.txt)