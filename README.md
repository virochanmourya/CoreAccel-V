<div align="center">
  
# 🚀 CoreAccel-V 
**A custom RISC-V SoC Architecture featuring an integrated DSP/MAC unit for hardware-accelerated algorithms.**

</div>

## 📊 Architecture Block Diagram

<div align="center">
  <img src="docs/architecture_block_diagram.png" alt="CoreAccel-V Architecture" width="800"/>
</div>

> 🔍 *For a high-resolution version, please see the [Architecture PDF](docs/architecture_block_diagram.pdf).*

---

## ⚙️ Core Architecture Details

* **5-Stage RV32I Pipeline**: In-order execution with full 2-stage (`EX→EX` and `MEM→EX`) data forwarding and hazard detection logic.
* **CUSTOM-0 DSP MAC**: A dedicated 4-cycle Multiply-Accumulate coprocessor featuring a 72-bit signed accumulator with hardware saturation to prevent overflow during heavy FIR/IIR filtering.
* **Tightly Coupled Memory (TCM)**: Dual-port BRAM allowing simultaneous CPU execution and 1-cycle lookahead weight streaming directly into the DSP engine.

---

## 🌟 Current Milestone: FPGA ECG Monitoring System

CoreAccel-V has been successfully implemented and validated on physical FPGA hardware. For a detailed breakdown of the exact hardware structures running on the FPGA right now, see the [Current Architecture Report](docs/current_architecture.md).

### 🫀 Application Focus: Real-Time Heart Monitoring
To prove the computational efficiency of the architecture, I developed a complete hardware/software system for real-time ECG analysis:

* **Algorithm Implementation**: The firmware implements the **Pan-Tompkins algorithm** for QRS detection. It utilizes **dynamic thresholding** to precisely detect the R-peak and accurately calculates the BPM using the **R-R interval**.
* **Hardware Acceleration**: The processor utilizes its custom DSP/MAC unit to analyze the ECG waveform and classify abnormalities (e.g., *Tachycardia*, *Bradycardia*, and *Irregular Rhythms*) with extremely low latency.
* **Accuracy Verified**: The processor's calculated BPM was cross-verified against a commercial pulse oximeter. The results rarely diverged, proving the mathematical and timing accuracy of the custom CPU core.
* **Host GUI (`gui/`)**: Developed a high-performance Python/PyQt OpenGL GUI that interfaces with the processor via UART to stream and visualize the live ECG waveform and classification status.

> 📝 *(Note: The `sim/` folder containing the advanced testbenches is currently being updated with new verification features and will be pushed to the repository soon!)*

---

## 📈 Implementation Metrics (Xilinx Artix-7)

The design successfully meets all physical constraints targeting a Xilinx Artix-7 device.

| Metric | Value | Detail |
| :--- | :--- | :--- |
| **Maximum Frequency ($F_{max}$)** | **100.75 MHz** | Targeted 100 MHz clock with a WNS of +0.075 ns. |
| **LUTs** | **2,449** | Highly optimized logic footprint. |
| **Flip-Flops** | **1,595** | Efficient register utilization. |
| **BRAMs** | **1** | Maps exactly to one RAMB36E1 tile. |
| **DSPs** | **4** | Mapped cleanly to four DSP48E1 slices. |
| **Power Consumption** | **0.189 W** | Dynamic: 0.117 W, Static: 0.072 W. |

**Raw EDA Reports:**  
🔗 [Timing](docs/timing_report.txt) | 🔗 [Power](docs/power_report.txt) | 🔗 [Utilization](docs/utilization_report.txt) | 🔗 [Methodology](docs/methodology_report.txt)

---

## 🔮 Future Plans: Path to ASIC

While the FPGA implementation proves the design works flawlessly in a physical system, the ultimate goal for CoreAccel-V is a tape-out as a **custom ASIC**. 

The architecture will be expanded into a complete SoC, featuring advanced memory hierarchies, AXI interconnects, and external memory controllers. For a deep dive into the planned final design, please read the [Target SoC Architecture](docs/target_soc_architecture.md) document.

* Immediate next steps include finalizing the advanced UVM/layered testbench suite to achieve **100% functional and code coverage**.
* Refining the RTL to meet strict ASIC design rules.

---

## 📁 Repository Structure

```text
CoreAccel-V/
├── rtl/           # SystemVerilog source files (CPU pipeline, DSP unit, peripherals)
├── firmware/      # C/Assembly source code, linker scripts, Makefiles
├── gui/           # Python host application for visualizing UART telemetry
├── constraints/   # Physical constraints used for the FPGA implementation
└── docs/          # Block diagrams, architecture documentation, EDA reports
```