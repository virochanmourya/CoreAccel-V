# Non-project Vivado implementation for timing/utilization checks.
# Usage:
#   vivado -mode batch -source scripts/vivado_impl.tcl \
#          -tclargs <repo_root> <out_dir> <imem_hex> [tcm_hex]
#   imem_hex: IMEM image, copied in as imem.hex. IMEM synthesises as LUT-ROM,
#             so its contents affect logic and timing; keep it fixed when
#             comparing runs.
#   tcm_hex:  optional TCM image, copied in as tcm.hex (BRAM init only).
if {[llength $argv] < 3} {
    error "usage: -tclargs <repo_root> <out_dir> <imem_hex> \[tcm_hex\]"
}
set root [file normalize [lindex $argv 0]]
set out  [file normalize [lindex $argv 1]]
set imem [file normalize [lindex $argv 2]]
set part xc7a35tcpg236-1

file mkdir $out
cd $out
file copy -force $imem $out/imem.hex
if {[llength $argv] > 3} {
    file copy -force [file normalize [lindex $argv 3]] $out/tcm.hex
} else {
    set fh [open $out/tcm.hex w]; puts $fh "00000000"; close $fh
}

set fh [open $root/rtl/rtl.f]
foreach f [split [read $fh] "\n"] {
    set f [string trim $f]
    if {$f ne ""} { read_verilog -sv $root/$f }
}
close $fh
read_xdc $root/constraints/cpu_pipeline_top.xdc

# imem.hex / tcm.hex in the run directory match the RTL default INIT_FILE names.
synth_design -top cpu_pipeline_top -part $part
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -max_paths 10 -file timing_summary.rpt
report_timing -max_paths 10 -sort_by slack -nworst 1 -file worst_paths.rpt
report_utilization -file utilization.rpt
