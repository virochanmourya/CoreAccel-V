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

// Register write-back port (retirement proxy; no PC is carried to WB yet)
`define PRB_WB_WE      dut.mem_wb_reg_write
`define PRB_WB_RD      dut.mem_wb_rd_addr
`define PRB_WB_DATA    dut.wb_data

`endif
