# CoreAccel-V roadmap

The goal is one RV32 core, with its SoC, taken from RTL to a GDS on the
GlobalFoundries GF180MCU process (open PDK, LibreLane / OpenROAD flow). After
that, the SoC grows in the stages listed under "After the first GDS".

Each step ends with the same checks: the directed test suite passing in
xsim at every stall setting, Verilator lint clean in every configuration,
and FPGA timing closed (all six implementation runs at 100 MHz).

## Done

| Step | What |
|---|---|
| Core | 5-stage RV32I pipeline with forwarding, load-use and MAC hazards, and the CUSTOM-0 MAC unit (72-bit accumulator, operand streamed from TCM) |
| Verification base | Directed self-checking tests in xsim with a commit monitor and SVA checks, and Verilator lint |
| RV32M | Multiply and divide (`mul_div`), with directed tests and a random test generator |
| Zicsr, traps, interrupts | Machine-mode CSRs and counters, precise traps, MRET, machine timer, external interrupt input; unmapped accesses fault |
| Timing | 100 MHz on Artix-7 closed in all six implementation runs |
| Bus | Data-side AXI4 master, AXI4 demultiplexer with a default error slave, AXI4-to-APB4 bridge, global memory stall for wait states |
| Peripherals | UART0, SPI master, I2C master, GPIO, timers with PWM and input capture, PLIC, system control with a watchdog |
| Clock, reset, boot | Clock select, reset generator, boot ROM with a UART loader, writable IMEM (BOOT=rom build), host loader script |

## Next: FPGA bring-up

1. Program the Basys 3 with both bitstreams (`make bit`, `make bit-rom`).
   Check UART0, the loader (`scripts/load.py --port`), SPI, I2C, GPIO and
   PWM on the board.
2. Fix the pin assignments. The strap, SPI, GPIO, PWM and capture pins in
   `constraints/cpu_pipeline_top.xdc` are provisional.
3. Replace the legacy demo firmware (`firmware/`) with firmware that uses
   the APB peripherals.

## ASIC: GF180MCU

A synthesis and pre-layout timing study on GF180MCU has been done (yosys and
OpenSTA, no place and route). It points to the 5 V, 9-track library and a
sign-off target of about 40 MHz at the slow corner, with 50 MHz as a stretch.
100 MHz is not reachable at the slow corner.

1. **RTL changes for the ASIC configuration.**
   - IMEM and boot ROM as SRAM/ROM macros. Their read is synchronous, so the
     fetch stage has to be re-pipelined (next-PC addressing, or one more
     fetch stage).
   - The register file without a reset on x1..x31, so it can map to a
     register-file macro.
   - Register the TCM data in front of the MAC multiplier. Make the
     multipliers, the divider's negate and the 64-bit counters multi-cycle.
     Move the TCM write enable off the EX-stage critical path.
   - Reset: choose asynchronous assert / synchronous release for the leaf
     flops, or keep the synchronous reset, and plan the reset tree.
   - Review every 2-flop synchroniser (structure, MTBF, multi-bit use).
2. **Pads and top level:** GF180 IO cells, pad ring, and the strap and clock
   pins.
3. **Flow:** synthesis, floorplan with the SRAM macros, place and route,
   clock-tree synthesis, then timing, DRC and LVS sign-off with
   LibreLane / OpenROAD.
4. **Gate-level checks:** the directed tests on the post-synthesis netlist
   where the simulator allows, plus a structural CDC check.
5. **GDS.**

## After the first GDS

These stages come from the design study in
[docs/target_soc_architecture.md](docs/target_soc_architecture.md). None of
them is implemented. Each builds on the one before.

1. **DMA:** a second AXI master, with a 2-master arbiter in front of the
   existing AXI4 demultiplexer.
2. **Cache and external memory:** an external-memory AXI slave and an L1
   data cache in front of it only. TCM and peripherals stay uncached.
3. **FFT accelerator:** reads and writes memory through the DMA.
4. **Dual core with shared memory:** a second hart and a shared memory
   region, with software locks.
5. **Coherency:** MESI snooping between the two data caches, plus LR/SC and
   atomics.

## Verification, alongside

- A retirement scoreboard against a reference ISA model (needs a PC/retire
  port in WB).
- Functional coverage and a UVM environment once the RTL is stable.
- Continuous integration for lint and the regression.
