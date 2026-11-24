// ============================================================================
// tb_probes.svh — every hierarchical reference into the DUT lives here.
// When RTL signal names change, update this file and the bind port list at
// the bottom of tb/core_sva.sv (the only other place that names DUT internals).
// ============================================================================
`ifndef TB_PROBES_SVH
`define TB_PROBES_SVH

// Backing arrays loaded by the harness
`define PRB_IMEM_ARR   dut.u_imem.g_fpga.u_rom.mem
`define PRB_TCM_ARR    dut.u_tcm.g_fpga.u_ram.mem

// Data-side store, observed at the EX/MEM register (squashed stores never get here)
`define PRB_ST_VALID   dut.ex_mem_mem_write
`define PRB_ST_ADDR    dut.ex_mem_alu_result
`define PRB_ST_DATA    dut.ex_mem_rs2_data

// Data-bus error (load/store to an unmapped address), in MEM: it also traps
// as a load/store access fault (cause 5/7)
`define PRB_DBUS_ERR   dut.dbus_error
`define PRB_DBUS_ADDR  dut.ex_mem_alu_result

// Trap entry (taken in MEM): one cycle per trap, with its cause/PC/tval
`define PRB_TRAP         dut.mem_trap
`define PRB_TRAP_CAUSE   dut.mem_trap_cause
`define PRB_TRAP_PC      dut.ex_mem_pc
`define PRB_TRAP_TVAL    dut.mem_trap_tval

// External interrupt request (tied off in the RTL; the harness forces it)
`define PRB_EXT_IRQ      dut.sim_irq

// EX stage: a TCM store is in EX, and the EX hold signal (forced by the
// +HOLD_EX_STORES hook to emulate a multi-cycle unit / DMA arbiter holding EX)
`define PRB_EX_TCM_STORE (dut.id_ex_mem_write && dut.ex_is_tcm)
`define PRB_EX_HOLD      dut.ex_hold
// RTL driver of PRB_EX_HOLD: the net ex_hold is assigned from. xsim does not
// re-evaluate a continuous assign on `release`, so the hook re-forces ex_hold
// to this net after a hold. It is a single RTL net (the OR of every hold
// source), not a copy of an expression, so new hold sources need no change here.
`define PRB_EX_HOLD_RTL  dut.ex_hold_src

// Data bus: wait-state hook (+BUS_WAIT) and the access it acts on
`define PRB_BUS_WAIT   dut.bus_wait_inj      // tied to 0 in the RTL; forced by the hook
`define PRB_BUS_BUSY   dut.mem_is_bus        // a bus access is in MEM
`define PRB_MEM_STALL  dut.mem_stall         // ... and MEM is waiting for it
`define PRB_BUS_ADDR   dut.ex_mem_alu_result // its address

// UART0 bit time (clocks per bit), for the harness's RX-pin driver
`define PRB_UART0_DIV  dut.u_periph.u_uart0.div
// SPI SCK divider, for the echo target's timing checks
`define PRB_SPI_DIV    dut.u_periph.u_spi.div

// Register write-back port (retirement proxy; no PC is carried to WB yet).
// rf_we is gated by the global stall, so each write is seen once.
`define PRB_WB_WE      dut.rf_we
`define PRB_WB_RD      dut.mem_wb_rd_addr
`define PRB_WB_DATA    dut.wb_data

`endif
