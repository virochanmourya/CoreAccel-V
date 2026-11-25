# Multi-run timing measurement, driven by scripts/timing_sweep.sh.
#
#   synth: vivado -mode batch -source vivado_sweep.tcl \
#              -tclargs synth <repo_root> <out_dir> <imem_hex> [<bootrom_hex> <generics>]
#          Synthesises once and writes <out_dir>/post_synth.dcp.
#          BOOT=rom build: bootrom_hex is copied in as bootrom.hex and
#          generics is a space-separated NAME=VALUE list for the top
#          (e.g. "RESET_VECTOR=65536 IMEM_WRITABLE=1").
#   impl:  vivado -mode batch -source vivado_sweep.tcl \
#              -tclargs impl <dcp> <out_dir> <place_directive> <route_directive>
#          Same flow as vivado_impl.tcl (opt, place, phys_opt, route) with the
#          given directives. Writes reports and <out_dir>/result.csv.
#
# A single implementation run moves by ~0.15 ns with any change to the
# netlist; running several directive pairs on the same netlist shows how
# much of a result is placement luck.
set mode [lindex $argv 0]
set part xc7a35tcpg236-1
set_param general.maxThreads 4

if {$mode eq "synth"} {
    set root [file normalize [lindex $argv 1]]
    set out  [file normalize [lindex $argv 2]]
    set imem [file normalize [lindex $argv 3]]
    file mkdir $out
    cd $out
    # imem.hex / tcm.hex in the run directory match the RTL default INIT_FILE names.
    file copy -force $imem $out/imem.hex
    set fh [open $out/tcm.hex w]; puts $fh "00000000"; close $fh
    set gen {}
    if {[llength $argv] > 5} {
        file copy -force [file normalize [lindex $argv 4]] $out/bootrom.hex
        foreach g [lindex $argv 5] { lappend gen -generic $g }
    }
    set fh [open $root/rtl/rtl.f]
    foreach f [split [read $fh] "\n"] {
        set f [string trim $f]
        if {$f ne ""} { read_verilog -sv $root/$f }
    }
    close $fh
    read_xdc $root/constraints/cpu_pipeline_top.xdc
    synth_design -top cpu_pipeline_top -part $part {*}$gen
    write_checkpoint -force $out/post_synth.dcp
    report_utilization -file $out/utilization_synth.rpt
    exit 0
}

if {$mode ne "impl"} { error "mode must be synth or impl" }
set dcp  [file normalize [lindex $argv 1]]
set out  [file normalize [lindex $argv 2]]
set pdir [lindex $argv 3]
set rdir [lindex $argv 4]
file mkdir $out
cd $out
open_checkpoint $dcp
opt_design
place_design -directive $pdir
phys_opt_design
route_design -directive $rdir

report_timing_summary -max_paths 10 -file timing_summary.rpt
report_timing -max_paths 20 -sort_by slack -nworst 1 -file worst_paths.rpt
report_utilization -file utilization.rpt

proc prop {obj name} {
    if {[catch {get_property $name $obj} v]} { return "" }
    return $v
}
set wns [prop [get_timing_paths -setup -max_paths 1] SLACK]
set whs [prop [get_timing_paths -hold  -max_paths 1] SLACK]
# One path per endpoint (-nworst 1): failing endpoints and their TNS.
set fail [get_timing_paths -setup -max_paths 100000 -nworst 1 -slack_lesser_than 0]
set nfail [llength $fail]
set tns 0.0
foreach p $fail { set tns [expr {$tns + [get_property SLACK $p]}] }
set luts [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]
set ffs  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]

set fh [open $out/result.csv w]
puts $fh "place,route,wns,tns,fail_endpoints,whs,luts,ffs"
puts $fh [format "%s,%s,%.3f,%.3f,%d,%.3f,%d,%d" $pdir $rdir $wns $tns $nfail $whs $luts $ffs]
close $fh
# Five worst endpoints: slack, levels, logic/net delay, start -> end
set fh [open $out/paths.csv w]
puts $fh "slack,levels,logic_ns,net_ns,start,end"
foreach p [get_timing_paths -setup -max_paths 5 -nworst 1] {
    puts $fh [format "%.3f,%s,%s,%s,%s,%s" [get_property SLACK $p] \
        [prop $p LOGIC_LEVELS] [prop $p DATAPATH_LOGIC_DELAY] [prop $p DATAPATH_NET_DELAY] \
        [prop $p STARTPOINT_PIN] [prop $p ENDPOINT_PIN]]
}
close $fh
exit 0
