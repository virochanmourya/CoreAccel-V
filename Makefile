# ============================================================================
# CoreAccel-V — firmware build, directed tests, xsim simulation, lint
#
#   make regress            build + run every test (tests/*.S + generated), print summary
#   make test T=<name>      build + run one test (tests/<name>.S, or generated)
#   MEXT_SEED=<n> make ...  seed for the generated mext_random test
#   HOLD=<n> make regress   ... with every TCM store held in EX for n cycles
#   make tests              build all test images only
#   make sim-build          compile + elaborate the xsim snapshot
#   make fw                 build firmware/ into build/fw/{imem,tcm}.hex
#   make lint               Verilator -Wall lint (LibreLane container)
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
ARCH    := -march=rv32im -mabi=ilp32

# ---------------------------------------------------------------- sources
RTL_F   := $(ROOT)/rtl/rtl.f
RTL_SRC := $(addprefix $(ROOT)/,$(shell cat $(RTL_F)))
TB_SV   := $(ROOT)/tb/commit_monitor.sv $(ROOT)/tb/uart_monitor.sv $(ROOT)/tb/core_sva.sv \
           $(ROOT)/tb/i2c_target_model.sv \
           $(ROOT)/tb/tb_top.sv
TB_DEPS := $(TB_SV) $(wildcard $(ROOT)/tb/*.svh)

TEST_DIR    := $(ROOT)/tests
TEST_COMMON := $(TEST_DIR)/common/test.h $(TEST_DIR)/common/link.ld
# Generated tests (built from build/gen/<name>.S, see "generated tests" below)
GEN_TESTS   := mext_random
TESTS       := $(sort $(basename $(notdir $(wildcard $(TEST_DIR)/*.S)))) $(GEN_TESTS)
TEST_CFLAGS := $(ARCH) -nostdlib -nostartfiles -static \
               -I$(TEST_DIR)/common -T $(TEST_DIR)/common/link.ld

ELF2HEX := $(ROOT)/scripts/elf2hex.py

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

# ---------------------------------------------------------------- xsim
SIM_DIR   := $(BUILD)/sim
SIM_STAMP := $(SIM_DIR)/.elab.stamp
# settings64.sh returns non-zero even on success, so do not chain it with &&
XSIM_ENV  := source $(VIVADO_SETTINGS) >/dev/null 2>&1; cd $(SIM_DIR)

.PHONY: sim-build
sim-build: $(SIM_STAMP)

$(SIM_STAMP): $(RTL_SRC) $(RTL_F) $(TB_DEPS)
	@rm -f $(BUILD)/regress_summary.txt
	@mkdir -p $(SIM_DIR)
	@$(XSIM_ENV) && xvlog -sv -i $(ROOT)/tb $(RTL_SRC) $(TB_SV) > xvlog.log 2>&1 \
	    || { grep -E 'ERROR|WARNING' xvlog.log; exit 1; }
	@$(XSIM_ENV) && xelab tb_top -s tb_top -timescale 1ns/1ps -debug off > xelab.log 2>&1 \
	    || { grep -E 'ERROR|WARNING' xelab.log; exit 1; }
	@touch $@
	@echo "xsim snapshot ready: $(SIM_DIR)"

# run_xsim <test-name>
define run_xsim
	@$(XSIM_ENV) && xsim tb_top -R \
	    $$(sed '/^$$/d; s/^/-testplusarg /' $(BUILD)/tests/$(1)/plusargs.txt) \
	    -testplusarg TEST=$(1) \
	    -testplusarg TIMEOUT=$(TIMEOUT) \
	    $(if $(HOLD),-testplusarg HOLD_EX_STORES=$(HOLD)) \
	    -testplusarg SIGOUT=$(BUILD)/tests/$(1)/signature.txt \
	    -testplusarg TRACE=$(BUILD)/tests/$(1)/commit.log \
	    -log $(BUILD)/tests/$(1)/xsim.log > /dev/null 2>&1; \
	grep -hE '^(RESULT|MISMATCH)' $(BUILD)/tests/$(1)/xsim.log \
	    || echo "RESULT FAIL test=$(1) reason=no_result_line(see $(BUILD)/tests/$(1)/xsim.log)"
endef

.PHONY: test
test: $(BUILD)/tests/$(T)/plusargs.txt $(SIM_STAMP)
	$(call run_xsim,$(T))

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

# ---------------------------------------------------------------- misc
.PHONY: clean
clean:
	rm -rf $(BUILD)

# Keep intermediate ELFs for debugging.
.SECONDARY:
