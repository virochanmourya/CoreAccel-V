// ============================================================================
// File:   include.sv (RTL Design)
// Purpose: Consolidates all RTL files for easy compilation in EDA Playground.
//          Simply `include this file in the 'design.sv' tab.
// ============================================================================

// --- Core Logic & Execution Units ---
`include "alu.sv"
`include "mac_unit.sv"
`include "imm_gen_pipe.sv"
`include "control_unit_pipe.sv"
`include "forwarding_unit.sv"
`include "hazard_detection_unit.sv"

// --- Memory & Registers ---
`include "register_file.sv"
`include "data_memory.sv"
`include "tcm_ram.sv"
`include "instruction_memory_pipe.sv"
`include "pc_pipe.sv"

// --- Pipeline Registers ---
`include "if_id_reg.sv"
`include "id_ex_reg.sv"
`include "ex_mem_reg.sv"
`include "mem_wb_reg.sv"

// --- Peripherals ---
`include "uart_tx.sv"
`include "seg_display.sv"

// --- Top Level ---
`include "cpu_pipeline_top.sv"
