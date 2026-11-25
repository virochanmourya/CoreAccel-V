# Non-project Vivado implementation: reports, and optionally a bitstream.
# Usage (normally through `make bit` / `make bit-rom`):
#   vivado -mode batch -source scripts/vivado_impl.tcl \
#          -tclargs <repo_root> <out_dir> <imem_hex> [tcm_hex] \
#                   [-bootrom <hex>] [-generic NAME=VALUE]... [-bitstream]
#   imem_hex:  IMEM image, copied in as imem.hex. In the default build IMEM
#              synthesises as LUT-ROM, so its contents affect logic and
#              timing; keep it fixed when comparing runs.
#   tcm_hex:   optional TCM image, copied in as tcm.hex (BRAM init only).
#   -bootrom:  boot ROM image, copied in as bootrom.hex (BOOT=rom build).
#   -generic:  top-level parameter, e.g. RESET_VECTOR=65536 IMEM_WRITABLE=1
#              BAUD_RATE=115200 for the BOOT=rom build. Repeatable.
#   -bitstream also write <out_dir>/cpu_pipeline_top.bit.
# Every report starts with the git commit of <repo_root>, the Vivado version
# and the generics, so a report can be traced to the RTL it came from.
set pos {}
set bootrom ""
set gen {}
set want_bit 0
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        -bootrom   { incr i; set bootrom [file normalize [lindex $argv $i]] }
        -generic   { incr i; lappend gen [lindex $argv $i] }
        -bitstream { set want_bit 1 }
        default    { lappend pos $a }
    }
}
if {[llength $pos] < 3 || [llength $pos] > 4} {
    error "usage: -tclargs <repo_root> <out_dir> <imem_hex> \[tcm_hex\] \[-bootrom <hex>\] \[-generic N=V\]... \[-bitstream\]"
}
set root [file normalize [lindex $pos 0]]
set out  [file normalize [lindex $pos 1]]
set imem [file normalize [lindex $pos 2]]
set part xc7a35tcpg236-1

file mkdir $out
cd $out
file copy -force $imem $out/imem.hex
if {[llength $pos] > 3} {
    file copy -force [file normalize [lindex $pos 3]] $out/tcm.hex
} else {
    set fh [open $out/tcm.hex w]; puts $fh "00000000"; close $fh
}
if {$bootrom ne ""} { file copy -force $bootrom $out/bootrom.hex }

# Provenance: commit (with -dirty if the tree has local changes) and tool version
if {[catch {exec git -C $root rev-parse --short HEAD} commit]} { set commit unknown }
if {![catch {exec git -C $root status --porcelain --untracked-files=no -- rtl constraints boot} st] && $st ne ""} {
    append commit "-dirty"
}
set stamp [list \
    "CoreAccel-V commit $commit, [version -short], part $part" \
    "generics: [expr {[llength $gen] ? [join $gen { }] : {none (default build)}}]" \
    "boot ROM: [expr {$bootrom ne {} ? {yes (BOOT=rom build)} : {no}}]"]
set fh [open $out/build_info.txt w]; puts $fh [join $stamp "\n"]; close $fh
proc report_to {file cmd} {
    global out stamp
    eval $cmd -file $out/$file.tmp
    set fh [open $out/$file w]
    foreach l $stamp { puts $fh "# $l" }
    set in [open $out/$file.tmp]; puts -nonewline $fh [read $in]; close $in
    close $fh
    file delete $out/$file.tmp
}

set fh [open $root/rtl/rtl.f]
foreach f [split [read $fh] "\n"] {
    set f [string trim $f]
    if {$f ne ""} { read_verilog -sv $root/$f }
}
close $fh
read_xdc $root/constraints/cpu_pipeline_top.xdc

# imem.hex / tcm.hex / bootrom.hex in the run directory match the RTL
# default INIT_FILE names.
set gargs {}
foreach g $gen { lappend gargs -generic $g }
synth_design -top cpu_pipeline_top -part $part {*}$gargs
opt_design
place_design
phys_opt_design
route_design

report_to timing_summary.rpt      {report_timing_summary -max_paths 10}
report_to worst_paths.rpt         {report_timing -max_paths 10 -sort_by slack -nworst 1}
report_to utilization.rpt         {report_utilization}
report_to power.rpt               {report_power}
report_to methodology.rpt         {report_methodology}
report_to drc.rpt                 {report_drc}

if {$want_bit} {
    write_bitstream -force $out/cpu_pipeline_top.bit
}
