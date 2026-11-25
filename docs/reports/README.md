# Implementation reports

Vivado 2026.1, part xc7a35tcpg236-1, 100 MHz clock. Each report is one
`make bit` / `make bit-rom` run (synth, opt, place, phys_opt, route with
default directives), and its first lines give the commit and generics. The
two runs were made at commits a152792 (default) and a728d1a (BOOT=rom).
`rtl/`, `constraints/`, `boot/`, `scripts/` and the `Makefile` are
identical at both commits. The IMEM/TCM image is the legacy demo firmware
(`make fw`). In the default build that image is synthesised into the IMEM
LUT-ROM, so a different program changes the LUT count and the timing
slightly. Local paths and the host name have been removed.

| Build | WNS | WHS | Slice LUTs | LUT as memory | Registers | Block RAM tiles | DSP48E1 | Total power |
|---|---|---|---|---|---|---|---|---|
| default (`make bit`) | +0.277 ns | +0.024 ns | 5443 (26.2%) | 24 | 4198 | 1 | 8 | 0.148 W |
| BOOT=rom (`make bit-rom`) | +0.370 ns | +0.046 ns | 6830 (32.8%) | 1432 | 4326 | 1 | 8 | 0.155 W |

One implementation run varies by about 0.15 ns. The timing sign-off numbers
in the top-level README come from six runs with different placer and router
directives on a fixed reference image (`scripts/timing_sweep.sh`).

Files: `default/` and `rom/`, each with `timing_summary.txt`,
`utilization.txt` and `power.txt`.
