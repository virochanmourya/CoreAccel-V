// ============================================================================
// tb_probes.svh — every hierarchical reference into the DUT lives here.
// When RTL signal names change, update this file and the bind port list at
// the bottom of tb/core_sva.sv (the only other place that names DUT internals).
// ============================================================================
`ifndef TB_PROBES_SVH
`define TB_PROBES_SVH

// Backing arrays loaded by the harness
`define PRB_IMEM_ARR   dut.u_imem.mem
`define PRB_TCM_ARR    dut.u_tcm.mem

// Data-side store, observed at the EX/MEM register (squashed stores never get here)
`define PRB_ST_VALID   dut.ex_mem_mem_write
`define PRB_ST_ADDR    dut.ex_mem_alu_result
`define PRB_ST_DATA    dut.ex_mem_rs2_data

// Data-bus error stub (load/store to an unmapped address), in MEM
`define PRB_DBUS_ERR   dut.dbus_error
`define PRB_DBUS_ADDR  dut.ex_mem_alu_result

// EX-stage error pulses (one per offending instruction) and the EX PC
`define PRB_ILLEGAL_ERR  dut.illegal_insn_err
`define PRB_MISALIGN_ERR dut.misaligned_err
`define PRB_EX_PC        dut.id_ex_pc

// EX stage: a TCM store is in EX, and the EX hold signal (forced by the
// +HOLD_EX_STORES hook to emulate a multi-cycle unit / DMA arbiter holding EX)
`define PRB_EX_TCM_STORE (dut.id_ex_mem_write && dut.ex_is_tcm)
`define PRB_EX_HOLD      dut.ex_hold
// RTL driver of PRB_EX_HOLD: the net ex_hold is assigned from. xsim does not
// re-evaluate a continuous assign on `release`, so the hook re-forces ex_hold
// to this net after a hold. It is a single RTL net (the OR of every hold
// source), not a copy of an expression, so new hold sources need no change here.
`define PRB_EX_HOLD_RTL  dut.ex_hold_src

// Register write-back port (retirement proxy; no PC is carried to WB yet)
`define PRB_WB_WE      dut.mem_wb_reg_write
`define PRB_WB_RD      dut.mem_wb_rd_addr
`define PRB_WB_DATA    dut.wb_data

`endif
