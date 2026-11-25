# CoreAccel-V

CoreAccel-V is a small RISC-V SoC written in SystemVerilog: a 5-stage
RV32IM_Zicsr core with a custom multiply-accumulate (MAC) unit, tightly
coupled data memory, an AXI4 / APB4 peripheral bus, the usual
microcontroller peripherals and a UART boot loader. It targets the Digilent
Basys 3 (Xilinx Artix-7) at 100 MHz today. The goal is to take a single core
to GDS on the GF180MCU open PDK. See [ROADMAP.md](ROADMAP.md).

Details: [docs/current_architecture.md](docs/current_architecture.md).

## Block diagram

```
            clk, reset, straps
                    |
              clk_gen, rst_gen
                    |
  +------------------------- core ---------------------------+
  |  IMEM 8 KB --> IF --> ID --> EX --> MEM --> WB            |
  |  boot ROM 4 KB  |             |  |     |                  |
  |  (BOOT=rom)     |   CSRs, traps, interrupts, mtimer       |
  |                 |             |  |     +--> TCM 4 KB (A)  |
  |                 |   MAC unit <+  +---> RV32M mul/div      |
  |                 |      ^                                  |
  |                 |      +----- TCM operand stream (B)      |
  +-------------------------------------|---------------------+
                                        | AXI4 master (other data addresses)
                                   axi4_demux ---- default slave (DECERR)
                                    |        \
                              axi4_to_apb4    IMEM write window (BOOT=rom)
                                    |
     legacy page | UART0 | SPI | I2C | GPIO | timers/PWM/capture | sysctl+WDT | PLIC
```

## Features

- **Core:** RV32I + M + Zicsr, machine mode, 5-stage in-order pipeline.
  Forwarding to EX, a one-bubble load-use stall, branches resolved in EX
  (2-cycle penalty), precise traps taken in MEM, MRET, and timer and
  external (PLIC) interrupts.
- **MAC unit (CUSTOM-0):** `acc += rs1 x TCM[rs2]` into a 72-bit
  saturating accumulator. The second operand streams from the TCM's second
  port. There are saturating and rounding/shifting reads and a sticky
  overflow flag.
- **Memory:** Harvard. 8 KB IMEM for code, and a 4 KB TCM (block RAM, dual
  port) for all data and the stack.
- **Bus:** AXI4 master with a 256-cycle timeout. The AXI4 demultiplexer has
  a decode-error default slave, and an AXI4-to-APB4 bridge feeds 4 KB
  peripheral slots. Every bus error becomes a precise access fault.
- **Peripherals:** UART0 (FIFOs, interrupts), SPI master (modes 0-3, 2 chip
  selects), I2C master, 16 GPIO with edge and level interrupts, two 32-bit
  timers, 4 PWM outputs, 2 capture inputs, a PLIC, system control (IDs,
  straps, reset cause, software reset, watchdog), and the original legacy
  page (bit-bang I2C, telemetry UART, 7-segment display).
- **Clock, reset, boot:** clock-select strap, reset generator with reset
  causes, and two builds. The default build runs from IMEM. The BOOT=rom
  build adds a boot ROM with a CRC-checked UART loader, a writable IMEM and
  a host script (`scripts/load.py`).

## Memory map

| Address | What |
|---|---|
| 0x0000_0000 | IMEM, 8 KB (instruction fetch only) |
| 0x0001_0000 | boot ROM, 4 KB (BOOT=rom build) |
| 0x1000_0000 | IMEM write window, 8 KB, word writes only (BOOT=rom build) |
| 0x8000_0000 | TCM, 4 KB (data, stack) |
| 0xC000_0000 | legacy page; mtime/mtimecmp at 0xC000_0100 (core-local) |
| 0xC000_1000 | UART0 |
| 0xC000_2000 | SPI |
| 0xC000_3000 | I2C |
| 0xC000_4000 | GPIO |
| 0xC000_5000 | timers, PWM, capture |
| 0xC000_8000 | system control and watchdog |
| 0xC400_0000 | PLIC |
| other | access fault |

Register maps: [docs/current_architecture.md](docs/current_architecture.md#6-peripherals-and-register-maps).

## Tools

| Tool | Used for |
|---|---|
| Vivado 2026.1 (xsim) | simulation, synthesis, implementation |
| Verilator (in the LibreLane container `ghcr.io/librelane/librelane:3.0.17`, via Docker) | lint only |
| xPack `riscv-none-elf-gcc` 15.2 | tests, boot ROM, firmware (`RISCV_PREFIX` in the Makefile) |
| Python 3 | hex conversion, test generator, loader (`pyserial` for `load.py --port`) |

The tool paths are variables at the top of the `Makefile`.

## Commands

```
make regress                 # build and run every test, print a summary
HOLD=2 WAIT=rand make regress  # the same with stores held in EX and random bus wait states
make test T=boot_uart        # one test (tests/<name>.S, or a unit test tb/unit/tb_<name>.sv)
make lint                    # Verilator -Wall: default, BOOT=rom and ASIC clock-mux configurations
make bootrom                 # boot/loader.S -> build/boot/bootrom.hex
make bit                     # default bitstream + reports -> build/bit/default/
make bit-rom                 # BOOT=rom bitstream (115200 baud loader) -> build/bit/rom/
make fw                      # legacy demo firmware -> build/fw/
scripts/timing_sweep.sh <out_dir> <imem_hex>   # several implementation runs on one netlist
```

Loading a program on a BOOT=rom board (boot-mode switches at 0):

```
python3 scripts/load.py --port /dev/ttyUSB1 program.elf
```

## Status

| Item | Result |
|---|---|
| Tests | 60 (directed, unit and generated). All pass at HOLD = 0..3 with WAIT = 0, rand and 3 |
| Lint | Verilator `-Wall`: 0 warnings in all three configurations |
| Timing, default build | closed at 100 MHz: 6 of 6 implementation runs pass, worst WNS +0.138 ns |
| Timing, BOOT=rom build | closed at 100 MHz: 6 of 6 runs pass, worst WNS +0.203 ns |
| Utilisation (one run, demo image) | default 5443 LUTs, 4198 FFs, 1 BRAM tile, 8 DSP48E1; BOOT=rom 6830 LUTs (1432 as LUTRAM), 4326 FFs. See [docs/reports/](docs/reports/) |
| On the board | not yet |

Timing is checked with six implementation runs (different placer and router
directives) on the same netlist, because one run moves by about 0.15 ns.

## Known limitations / not done yet

- **Not yet run on the board.** The bitstreams build cleanly, but nothing
  has been tested on the Basys 3 yet, including `load.py` over the USB-UART.
- **Provisional pins:** the strap, SPI, GPIO, PWM and capture pins in
  `constraints/cpu_pipeline_top.xdc` are placeholders until the board
  bring-up.
- **No DMA, no cache, no external memory.** These are later stages; see
  [ROADMAP.md](ROADMAP.md).
- No `fence.i`. IMEM is writable only in the BOOT=rom build, through the
  window.
- The SPI-flash boot modes (2 and 3) fall back to the UART loader.
- **ASIC items:** the IMEM and boot ROM need SRAM/ROM macros, and their
  synchronous read needs a re-pipelined fetch stage. Also open: register
  file reset, reset style and reset tree, a CDC review of the synchronisers,
  and the pads. A pre-layout synthesis and timing study on GF180MCU has been
  done; place and route has not.
- `firmware/` is a legacy demo for the original peripheral page. It is not
  part of the verification flow. See [firmware/README.md](firmware/README.md).

## Repository layout

```
rtl/          SystemVerilog sources (rtl/rtl.f is the file list)
tb/           testbench: harness, monitors, SVA, bus and device models, unit tests
tests/        directed assembly tests (tests/common: harness macros, linker script)
boot/         boot ROM loader and its linker script
scripts/      hex conversion, test generator, loader, Vivado scripts
constraints/  Basys 3 XDC
docs/         architecture, future-scope study, implementation reports
firmware/     legacy ECG demo firmware
gui/          host GUI for the legacy demo's telemetry stream
```
