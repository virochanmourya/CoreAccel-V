# ============================================================================
# CoreAccel-V — firmware build, directed tests, xsim simulation, lint
#
#   make regress            build + run every test (tests/*.S + generated), print summary
#   make test T=<name>      build + run one test (tests/<name>.S, or generated)
#   make test T=clk_rst     ... or a unit test (tb/unit/tb_<name>.sv, own snapshot)
#   MEXT_SEED=<n> make ...  seed for the generated mext_random test
#   HOLD=<n> make regress   ... with every TCM store held in EX for n cycles
#   WAIT=<n>|rand make ...  ... with bus wait states on every data-bus access
#                           (BUS_SEED=<n> seeds WAIT=rand)
#   make tests              build all test images only
#   make sim-build          compile + elaborate the xsim snapshot
#   make fw                 build firmware/ into build/fw/{imem,tcm}.hex
#   make lint               Verilator -Wall lint (LibreLane container), default
#                           and BOOT=rom configurations
#   make bootrom            build the boot ROM (boot/loader.S -> build/boot/bootrom.hex)
#   make test T=boot_uart   boot tests (tests/boot_*.S) run in the BOOT=rom
#                           snapshot (tb_top_rom): the boot ROM loads the test
#                           over UART0 from frames made by scripts/load.py
#   BUS_VIP=1 make ...      add the Xilinx AXI protocol checker on the core's
#                           AXI port (precompiled xsim library; separate snapshot)
#   make clean
# ============================================================================
SHELL := /bin/bash
ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD := $(ROOT)/build

RISCV_PREFIX    ?= /opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
VIVADO_SETTINGS ?= /tools/Xilinx/2026.1/settings64.sh
LIBRELANE_IMAGE ?= ghcr.io/librelane/librelane:3.0.17
PYTHON          ?= python3 -I
TIMEOUT         ?= 200000

CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
ARCH    := -march=rv32im_zicsr -mabi=ilp32

# ---------------------------------------------------------------- sources
RTL_F   := $(ROOT)/rtl/rtl.f
RTL_SRC := $(addprefix $(ROOT)/,$(shell cat $(RTL_F)))
TB_SV   := $(ROOT)/tb/commit_monitor.sv $(ROOT)/tb/uart_monitor.sv $(ROOT)/tb/core_sva.sv \
           $(ROOT)/tb/bus_sva.sv \
           $(ROOT)/tb/i2c_target_model.sv \
           $(ROOT)/tb/spi_flash_model.sv $(ROOT)/tb/spi_echo_model.sv \
           $(ROOT)/tb/tb_top.sv
ifeq ($(BUS_VIP),1)
TB_SV   += $(ROOT)/tb/axi_pc_bind.sv
VIP_LIBS := -L axi_protocol_checker_v2_0_21
endif
TB_DEPS := $(TB_SV) $(wildcard $(ROOT)/tb/*.svh)

TEST_DIR    := $(ROOT)/tests
TEST_COMMON := $(TEST_DIR)/common/test.h $(TEST_DIR)/common/link.ld $(TEST_DIR)/common/boot_prog.S
# Generated tests (built from build/gen/<name>.S, see "generated tests" below)
GEN_TESTS   := mext_random
# Unit tests: tb/unit/tb_<name>.sv, a standalone xsim snapshot each (no CPU
# program; HOLD/WAIT do not apply). Listed in TESTS so regress counts them.
UNIT_TESTS  := clk_rst
TESTS       := $(sort $(basename $(notdir $(wildcard $(TEST_DIR)/*.S)))) $(GEN_TESTS) $(UNIT_TESTS)
# Boot tests: run in the BOOT=rom snapshot, loaded by the boot ROM over UART0
BOOT_TESTS  := $(filter boot_%,$(TESTS))
TEST_CFLAGS := $(ARCH) -nostdlib -nostartfiles -static \
               -I$(TEST_DIR)/common -T $(TEST_DIR)/common/link.ld

ELF2HEX := $(ROOT)/scripts/elf2hex.py

# BOOT=rom configuration (boot ROM at 0x0001_0000, UART loader, writable IMEM).
# The same values go to lint and Vivado; the ROM xsim snapshot sets them
# through tb_top's BOOT_ROM parameter.
BOOT_ROM_GENERICS := RESET_VECTOR=65536 IMEM_WRITABLE=1

# ---------------------------------------------------------------- tests
.PHONY: tests
tests: $(foreach t,$(TESTS),$(BUILD)/tests/$(t)/plusargs.txt)

$(BUILD)/tests/%/test.elf: $(TEST_DIR)/%.S $(TEST_COMMON)
	@mkdir -p $(@D)
	$(CC) $(TEST_CFLAGS) -o $@ $<
	$(OBJDUMP) -d $@ > $(@D)/test.dis

$(BUILD)/tests/%/plusargs.txt: $(BUILD)/tests/%/test.elf $(ELF2HEX)
	$(PYTHON) $(ELF2HEX) $< $(@D)

# ---------------------------------------------------------------- generated tests
# mext_random: random RV32M vectors with expected values from the generator's
# reference model. The seed is fixed so the regression is reproducible; pass
# MEXT_SEED=<n> (and MEXT_OPS=<n>) to try others. The generator only rewrites
# the .S when its content changes, so a new seed rebuilds and an unchanged
# one does not.
MEXT_SEED ?= 20261124
MEXT_OPS  ?= 360
GEN_DIR   := $(BUILD)/gen
GEN_MEXT  := $(ROOT)/scripts/gen_mext_random.py

$(GEN_DIR)/mext_random.S: $(GEN_MEXT) FORCE
	@mkdir -p $(@D)
	@$(PYTHON) $(GEN_MEXT) --seed $(MEXT_SEED) --ops $(MEXT_OPS) --out $@

$(BUILD)/tests/mext_random/test.elf: $(GEN_DIR)/mext_random.S $(TEST_COMMON)
	@mkdir -p $(@D)
	$(CC) $(TEST_CFLAGS) -o $@ $<
	$(OBJDUMP) -d $@ > $(@D)/test.dis

.PHONY: FORCE
FORCE:

# ---------------------------------------------------------------- boot ROM
BOOT_DIR  := $(BUILD)/boot
BOOTROM   := $(BOOT_DIR)/bootrom.hex
LOAD_PY   := $(ROOT)/scripts/load.py

.PHONY: bootrom
bootrom: $(BOOTROM)

$(BOOTROM): $(ROOT)/boot/loader.S $(ROOT)/boot/boot.ld $(ELF2HEX)
	@mkdir -p $(@D)
	$(CC) -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -static \
	    -T $(ROOT)/boot/boot.ld -o $(BOOT_DIR)/loader.elf $(ROOT)/boot/loader.S
	$(OBJDUMP) -d $(BOOT_DIR)/loader.elf > $(BOOT_DIR)/loader.dis
	$(PYTHON) $(ELF2HEX) --rom $(BOOT_DIR)/loader.elf $(BOOT_DIR)

# UART frame stream for a boot test (its imem.hex, plus tcm.hex if any)
$(BUILD)/tests/%/frames.txt: $(BUILD)/tests/%/plusargs.txt $(LOAD_PY)
	$(PYTHON) $(LOAD_PY) --emit $@ $(@D)/imem.hex $(wildcard $(@D)/tcm.hex)

# ---------------------------------------------------------------- unit tests
UNIT_DIR  := $(BUILD)/sim_unit
UNIT_RTL_clk_rst := $(ROOT)/rtl/clk_mux_gf.sv $(ROOT)/rtl/clk_gen.sv $(ROOT)/rtl/rst_gen.sv

$(UNIT_DIR)/%.stamp: $(ROOT)/tb/unit/tb_%.sv $(RTL_SRC)
	@mkdir -p $(UNIT_DIR)/$*
	@source $(VIVADO_SETTINGS) >/dev/null 2>&1; cd $(UNIT_DIR)/$* && \
	    xvlog -sv $(UNIT_RTL_$*) $< > xvlog.log 2>&1 && \
	    xelab tb_$* -s tb_$* -timescale 1ns/1ps -debug off > xelab.log 2>&1 \
	    || { grep -E 'ERROR|WARNING' xvlog.log xelab.log; exit 1; }
	@touch $@

$(foreach u,$(UNIT_TESTS),$(BUILD)/tests/$(u)/plusargs.txt): $(BUILD)/tests/%/plusargs.txt:
	@mkdir -p $(@D)
	@echo "UNIT=$*" > $@

# ---------------------------------------------------------------- xsim
SIM_DIR   := $(BUILD)/sim$(if $(filter 1,$(BUS_VIP)),_vip)
SIM_STAMP := $(SIM_DIR)/.elab.stamp
# settings64.sh returns non-zero even on success, so do not chain it with &&
XSIM_ENV  := source $(VIVADO_SETTINGS) >/dev/null 2>&1; cd $(SIM_DIR)

.PHONY: sim-build
sim-build: $(SIM_STAMP)

$(SIM_STAMP): $(RTL_SRC) $(RTL_F) $(TB_DEPS)
	@rm -f $(BUILD)/regress_summary.txt
	@mkdir -p $(SIM_DIR)
	@$(XSIM_ENV) && xvlog -sv -i $(ROOT)/tb $(VIP_LIBS) $(RTL_SRC) $(TB_SV) > xvlog.log 2>&1 \
	    || { grep -E 'ERROR|WARNING' xvlog.log; exit 1; }
	@$(XSIM_ENV) && xelab tb_top -s tb_top -timescale 1ns/1ps -debug off $(VIP_LIBS) > xelab.log 2>&1 \
	    || { grep -E 'ERROR|WARNING' xelab.log; exit 1; }
	@# xelab drops unsupported assertions (and every one after them) with only a warning
	@! grep -E 'XSIM 43-(4127|4455)' $(SIM_DIR)/xelab.log $(SIM_DIR)/xvlog.log \
	    || { echo "xsim ignored assertions (see above)"; exit 1; }
	@touch $@
	@echo "xsim snapshot ready: $(SIM_DIR)"

# Second snapshot from the same compiled library: BOOT=rom configuration
SIM_ROM_STAMP := $(SIM_DIR)/.elab_rom.stamp
$(SIM_ROM_STAMP): $(SIM_STAMP)
	@$(XSIM_ENV) && xelab tb_top -s tb_top_rom -generic_top "BOOT_ROM=1" -timescale 1ns/1ps \
	    -debug off $(VIP_LIBS) > xelab_rom.log 2>&1 \
	    || { grep -E 'ERROR|WARNING' xelab_rom.log; exit 1; }
	@! grep -E 'XSIM 43-(4127|4455)' $(SIM_DIR)/xelab_rom.log \
	    || { echo "xsim ignored assertions (see above)"; exit 1; }
	@touch $@
	@echo "xsim snapshot ready: $(SIM_DIR) (tb_top_rom)"

# run_xsim <test-name>[,<snapshot>,<extra plusargs>]
define run_xsim
	@$(XSIM_ENV) && xsim $(or $(2),tb_top) -R \
	    $$(sed '/^$$/d; s/^/-testplusarg /' $(BUILD)/tests/$(1)/plusargs.txt) \
	    -testplusarg TEST=$(1) \
	    -testplusarg TIMEOUT=$(TIMEOUT) \
	    $(if $(HOLD),-testplusarg HOLD_EX_STORES=$(HOLD)) \
	    $(if $(WAIT),-testplusarg BUS_WAIT=$(WAIT)) \
	    $(if $(BUS_SEED),-testplusarg BUS_SEED=$(BUS_SEED)) \
	    -testplusarg SIGOUT=$(BUILD)/tests/$(1)/signature.txt \
	    -testplusarg TRACE=$(BUILD)/tests/$(1)/commit.log $(3) \
	    -log $(BUILD)/tests/$(1)/xsim.log > /dev/null 2>&1; \
	grep -hE '^(RESULT|MISMATCH)' $(BUILD)/tests/$(1)/xsim.log \
	    || echo "RESULT FAIL test=$(1) reason=no_result_line(see $(BUILD)/tests/$(1)/xsim.log)"
endef

.PHONY: test
ifneq ($(filter $(T),$(UNIT_TESTS)),)
test: $(BUILD)/tests/$(T)/plusargs.txt $(UNIT_DIR)/$(T).stamp
	@source $(VIVADO_SETTINGS) >/dev/null 2>&1; cd $(UNIT_DIR)/$(T) && \
	    xsim tb_$(T) -R -log $(BUILD)/tests/$(T)/xsim.log > /dev/null 2>&1; \
	grep -hE '^(RESULT|MISMATCH)' $(BUILD)/tests/$(T)/xsim.log \
	    || echo "RESULT FAIL test=$(T) reason=no_result_line(see $(BUILD)/tests/$(T)/xsim.log)"
else ifneq ($(filter $(T),$(BOOT_TESTS)),)
test: $(BUILD)/tests/$(T)/frames.txt $(BOOTROM) $(SIM_ROM_STAMP)
	$(call run_xsim,$(T),tb_top_rom,-testplusarg BOOTROM=$(BOOTROM) -testplusarg FRAMES=$(BUILD)/tests/$(T)/frames.txt)
else
test: $(BUILD)/tests/$(T)/plusargs.txt $(SIM_STAMP)
	$(call run_xsim,$(T))
endif

.PHONY: regress
regress: tests $(SIM_STAMP)
	@rm -f $(BUILD)/regress_summary.txt
	@for t in $(TESTS); do $(MAKE) --no-print-directory -s test T=$$t; done
	@$(PYTHON) $(ROOT)/scripts/regress_summary.py $(BUILD)/tests $(TEST_DIR)/known_failures.txt $(TESTS)

# ---------------------------------------------------------------- firmware
FW_DIR    := $(ROOT)/firmware
FW_SRC    := $(FW_DIR)/crt0.S $(FW_DIR)/main.c $(FW_DIR)/uart_driver.c \
             $(FW_DIR)/seg_driver.c $(FW_DIR)/ads1115_driver.c
FW_CFLAGS := $(ARCH) -O1 -ffreestanding -nostartfiles -Wall -T $(FW_DIR)/coreaccel_v.ld
FW_OUT    := $(BUILD)/fw

.PHONY: fw
fw: $(FW_OUT)/plusargs.txt

$(FW_OUT)/firmware.elf: $(FW_SRC) $(wildcard $(FW_DIR)/*.h) $(FW_DIR)/coreaccel_v.ld
	@mkdir -p $(@D)
	$(CC) $(FW_CFLAGS) -Wl,-Map=$(@D)/firmware.map -o $@ $(FW_SRC) -lgcc
	$(OBJDUMP) -d $@ > $(@D)/firmware.dis

$(FW_OUT)/plusargs.txt: $(FW_OUT)/firmware.elf $(ELF2HEX)
	$(PYTHON) $(ELF2HEX) $< $(@D)

# ---------------------------------------------------------------- lint
.PHONY: lint
lint:
	docker run --rm -u $$(id -u):$$(id -g) -v $(ROOT):/w:ro -w /w $(LIBRELANE_IMAGE) \
	    verilator --lint-only -Wall --top-module cpu_pipeline_top $(shell cat $(RTL_F))
	@# BOOT=rom configuration: boot ROM, fetch mux, writable IMEM + window
	docker run --rm -u $$(id -u):$$(id -g) -v $(ROOT):/w:ro -w /w $(LIBRELANE_IMAGE) \
	    verilator --lint-only -Wall --top-module cpu_pipeline_top $(BOOT_ROM_GENERICS:%=-G%) $(shell cat $(RTL_F))
	@# the glitch-free mux branch of clk_gen is not elaborated in the FPGA build
	docker run --rm -u $$(id -u):$$(id -g) -v $(ROOT):/w:ro -w /w $(LIBRELANE_IMAGE) \
	    verilator --lint-only -Wall --top-module clk_gen -GCLK_TECH='"ASIC"' rtl/clk_mux_gf.sv rtl/clk_gen.sv

# ---------------------------------------------------------------- misc
.PHONY: clean
clean:
	rm -rf $(BUILD)

# Keep intermediate ELFs for debugging.
.SECONDARY:
