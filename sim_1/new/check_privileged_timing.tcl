# Run from a disposable build directory containing the intended imem.mem.
# vivado -mode batch -source <absolute path to this file> -tclargs board
set root [file normalize [file join [file dirname [info script]] ../..]]
set board [expr {[llength $argv] > 0 && [lindex $argv 0] eq "board"}]
set_property include_dirs [list $root/sources_1/new] [current_fileset]
read_verilog [glob $root/sources_1/new/*.v]
if {$board} {
    set ip [file normalize $root/../QXW_RV32I_CPU.gen/sources_1/ip/clk_main_100mhz]
    read_verilog [list $ip/clk_main_100mhz.v $ip/clk_main_100mhz_clk_wiz.v]
    synth_design -top top -part xc7a100tcsg324-1
    read_xdc $root/constrs_1/new/xc7a100tcsg324.xdc
    create_clock -name board_clk -period 10.000 [get_ports clk]
    set_input_jitter [get_clocks board_clk] 0.100
} else {
    synth_design -top cpu -part xc7a100tcsg324-1
    set fd [open $root/sources_1/new/defines.v r]
    set defines [read $fd]
    close $fd
    regexp {CPU_CLK_FREQ_HZ ([0-9_]+)} $defines -> cpu_hz
    set cpu_hz [string map {_ ""} $cpu_hz]
    create_clock -name cpu_clk -period [expr {1.0e9/$cpu_hz}] [get_ports clk]
}
opt_design -directive Explore
report_utilization -file utilization.rpt
report_timing_summary -file timing_synth.rpt
write_checkpoint -force synthesized.dcp
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore -tns_cleanup
phys_opt_design -directive Explore
report_timing_summary -file timing_routed.rpt
report_timing -max_paths 20 -file critical_paths.rpt
report_route_status -file route_status.rpt
report_utilization -file utilization_routed.rpt
write_checkpoint -force routed.dcp
