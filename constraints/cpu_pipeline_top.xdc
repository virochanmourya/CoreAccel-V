## ============================================================================
## Master Constraints: CoreAccel-V Pipelined RV32I + DSP MAC + TCM
## File:               cpu_pipeline_top.xdc
## Board:              Digilent Basys 3 (Artix-7 xc7a35tcpg236-1)
## ============================================================================
##
## DESIGN CONTEXT:
##   This constraint file maps the cpu_pipeline_top module's I/O ports to the
##   Basys 3 board. The module has only 2 inputs (clk, reset) and 2 output
##   buses (debug_pc, debug_wb). These debug outputs serve a critical role:
##   they act as "anchor logic" that prevents Vivado's opt_design pass from
##   removing the entire netlist.
##
##   Without physical outputs, the synthesis optimizer determines that no
##   internal signal can influence the outside world and removes every
##   register, LUT, BRAM, and DSP slice — producing the fatal error:
##     [Place 30-494] "The design is empty"
##
##   By tying debug_pc (PC register, lower 8 bits) and debug_wb (write-back
##   data, lower 8 bits) to the 16 on-board LEDs, a dependency chain is
##   created from every pipeline stage, the ALU, the MAC unit, the TCM BRAM,
##   the forwarding unit, and the hazard detection unit — all the way to
##   physical I/O pins. This forces the synthesizer to preserve the complete
##   processor datapath.
##
## ============================================================================

## ============================================================================
## 1. CLOCK — 100 MHz Basys 3 On-Board Oscillator
## ============================================================================
## The Basys 3 has a single 100 MHz CMOS oscillator connected to FPGA pin W5.
## Period = 10.000 ns, 50% duty cycle.

set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports clk]

## ============================================================================
## 2. RESET — Center Push Button (BTNC)
## ============================================================================
## Active-high synchronous reset. The Basys 3 center button is active-high
## (logic 1 when pressed, logic 0 when released).

set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports reset]

## ============================================================================
## 3. ANCHOR LOGIC — debug_pc[7:0] → LED0 through LED7 (Lower Bank)
## ============================================================================
## These 8 LEDs display the lower byte of the Program Counter (PC).
## As the PC drives the instruction fetch address, this output creates a
## dependency on: pc_pipe → instruction_memory → IF/ID register →
## control_unit → hazard_detection_unit → forwarding_unit, ensuring the
## entire front-end of the pipeline is preserved during optimization.

set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[7]}]

## ============================================================================
## 4. ANCHOR LOGIC — debug_wb[7:0] → LED8 through LED15 (Upper Bank)
## ============================================================================
## These 8 LEDs display the lower byte of the Write-Back data (wb_data).
## This is the final mux output that selects between ALU result, memory
## read data (from data_memory or TCM BRAM), MAC sliced result, and PC+4.
## This single signal creates a dependency chain through EVERY execution
## path in the processor:
##   - ALU (all 11 operations)       → keeps the full ALU + forwarding MUXes
##   - data_memory (LW path)         → keeps the load/store unit
##   - TCM BRAM Port A (LW path)     → keeps the Tightly Coupled Memory
##   - MAC unit (MAC_READ_LO/HI)     → keeps the DSP multiply-accumulate
##   - PC+4 (JAL/JALR return addr)   → keeps the jump/link logic
##   - Register file (write port)    → keeps all 32 registers

set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {debug_wb[0]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[1]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[2]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[3]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[4]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[5]}]
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[6]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {debug_wb[7]}]

## ============================================================================
## 5. TIMING EXCEPTIONS
## ============================================================================
## The reset button is an asynchronous human input. Its setup/hold timing
## relative to the clock is meaningless. Declaring it as a false path
## prevents it from artificially constraining Fmax in the timing report.

set_false_path -from [get_ports reset]

## Debug outputs are LEDs — no external setup/hold timing requirement.
## This eliminates TIMING-18 warnings about missing output delays.
set_false_path -to [get_ports {debug_pc[*]}]
set_false_path -to [get_ports {debug_wb[*]}]

## ============================================================================
## 6. CONFIGURATION & BITSTREAM
## ============================================================================
## Required for Basys 3 board programming via USB-JTAG and SPI flash.

set_property CFGBVS VCCO                    [current_design]
set_property CONFIG_VOLTAGE 3.3              [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33  [current_design]

## ============================================================================
## 7. I2C GPIO — Pmod JA Header (Open-Drain, Active-Low)
## ============================================================================
## Directly drives the AD8232 → ADS1115 I2C bus via software bit-bang.
## Both pins are bidirectional (inout tri) for open-drain signaling.
## External 2.2kΩ pull-up resistors to 3.3V are REQUIRED on SCL and SDA.
##
##   JA Pin 4 (G2) = SCL  |  JA Pin 3 (J2) = SDA

set_property -dict { PACKAGE_PIN G2  IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports i2c_scl]
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports i2c_sda]

## I2C runs at ~100 kHz — 10,000× slower than the 100 MHz fabric clock.
## These pins have zero timing relevance to internal pipeline closure.
set_false_path -to   [get_ports i2c_scl]
set_false_path -to   [get_ports i2c_sda]
set_false_path -from [get_ports i2c_scl]
set_false_path -from [get_ports i2c_sda]

## ============================================================================
## 8. UART TX — Basys 3 Onboard USB-UART Bridge (FTDI FT2232HQ)
## ============================================================================
## One-way telemetry output at 115200 baud, 8N1. Directly connected to the
## FTDI USB-UART chip on the Basys 3 board — no external wiring needed.
## Pin A18 = RsTx per Digilent official Basys 3 XDC (FPGA transmit direction).

set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports uart_tx_out]

## UART baud rate (115200) is ~1000× slower than fabric clock.
## No timing relevance to internal pipeline closure.
set_false_path -to [get_ports uart_tx_out]

## ============================================================================
## 9. 7-SEGMENT DISPLAY — Basys 3 Onboard 4-Digit Common-Anode
## ============================================================================
## Hardware-multiplexed at ~1 kHz. All outputs are active-low.
## Cathode segment mapping: seg[0]=a, seg[1]=b, ..., seg[6]=g
## Anode mapping: an[0]=rightmost digit, an[3]=leftmost digit

## Cathode segments (active-low)
set_property -dict { PACKAGE_PIN W7  IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
set_property -dict { PACKAGE_PIN W6  IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
set_property -dict { PACKAGE_PIN U5  IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
set_property -dict { PACKAGE_PIN V5  IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]

## Decimal point (active-low, tied OFF in RTL)
set_property -dict { PACKAGE_PIN V7  IOSTANDARD LVCMOS33 } [get_ports dp]

## Anode enables (active-low)
set_property -dict { PACKAGE_PIN U2  IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN U4  IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN V4  IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN W4  IOSTANDARD LVCMOS33 } [get_ports {an[3]}]

## Display runs at 1 kHz — no timing relevance to internal pipeline.
set_false_path -to [get_ports {seg[*]}]
set_false_path -to [get_ports dp]
set_false_path -to [get_ports {an[*]}]

## ============================================================================
## END OF CONSTRAINTS
## ============================================================================
