# firmware/ (legacy)

This is the original application for CoreAccel-V: an ECG / heart-rate demo
for the Basys 3 board. It is kept so the demo can still be built. It is
**not** part of the verification flow. Nothing in the regression, lint or
timing flow depends on it, and it has no tests of its own.

## What it does

- Reads an ADS1115 ADC (I2C address 0x48, 250 samples/s, AIN0 single-ended). The
  I2C is bit-banged through the legacy page GPIO (`gpio.h`), not through
  the APB I2C controller.
- Filters the samples (DC removal, FIR low-pass) and detects beats with a
  rising-edge detector and blanking period (`main.c`). The filters are
  plain C. `mac_intrinsics.h` has inline-assembly wrappers for the CUSTOM-0
  MAC instructions, but `main.c` does not use them.
- Shows the heart rate on the 7-segment display. It streams the filtered
  sample, the BPM and a status value on the legacy one-way telemetry UART
  (JB1, 115200 8N1). The host GUI for that
  stream is in `gui/`, and `serial_terminal_v2.ps1` is a plain Windows
  serial terminal for the same port.

It only uses the legacy peripheral page at 0xC000_0000:

| Address     | Register                                   |
|-------------|--------------------------------------------|
| 0xC000_0000 | GPIO: bit0 SCL, bit1 SDA (open drain)      |
| 0xC000_0004 | telemetry UART TX: write = send, bit0 busy |
| 0xC000_0008 | 7-segment value [15:0]                     |

The newer APB peripherals (UART0, SPI, I2C, GPIO, timers, PLIC, system
control) are not used. Tests for those are under `tests/`.

## Building

From the repository root:

```
make fw        # -> build/fw/firmware.elf, imem.hex (IMEM .text), tcm.hex (TCM .data)
make bit       # default bitstream with this program in IMEM (see the top-level README)
```

The toolchain is the one the Makefile names in `RISCV_PREFIX` (xPack
riscv-none-elf-gcc), built with `-march=rv32im_zicsr`. The linker script
`coreaccel_v.ld` follows the Harvard memory map: `.text` in IMEM at
0x0000_0000 (8 KB), everything else (data, bss, stack) in TCM at
0x8000_0000 (4 KB).

Generated images are not checked in. `make fw` writes them to `build/fw/`.
