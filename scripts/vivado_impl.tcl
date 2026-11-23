# Non-project Vivado implementation for timing/utilization checks.
# Usage: vivado -mode batch -source scripts/vivado_impl.tcl -tclargs <repo_root> <out_dir> [imem_hex]
#   imem_hex: IMEM image copied in as firmware.hex (IMEM synthesises as LUT-ROM,
#             so its contents affect logic and timing; keep it fixed when comparing).
set root [file normalize [lindex $argv 0]]
set out  [file normalize [lindex $argv 1]]
set imem [expr {[llength $argv] > 2 ? [file normalize [lindex $argv 2]] : "$root/rtl/firmware.hex"}]
set part xc7a35tcpg236-1

file mkdir $out
cd $out
file copy -force $imem $out/firmware.hex

set fh [open $root/rtl/rtl.f]
foreach f [split [read $fh] "\n"] {
    set f [string trim $f]
    if {$f ne ""} { read_verilog -sv $root/$f }
}
close $fh
read_xdc $root/constraints/cpu_pipeline_top.xdc

synth_design -top cpu_pipeline_top -part $part
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -max_paths 10 -file timing_summary.rpt
report_timing -max_paths 10 -sort_by slack -nworst 1 -file worst_paths.rpt
report_utilization -file utilization.rpt
