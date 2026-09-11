# ==============================================================================
# Tool: A2F Automated Batch Runner (Headless & Zero-GUI)
# Usage:
#   vivado -mode batch -notrace -source auto_run_retarget.tcl -tclargs <project.xpr> [output_xdc] [min_fanout]
# ==============================================================================

if {[llength $argv] < 1} {
    puts "ERROR: Missing project path (.xpr)!"
    puts "Usage: vivado -mode batch -notrace -source auto_run_retarget.tcl -tclargs <project.xpr> \[output_xdc\] \[min_fanout\]"
    exit 1
}

set xpr_norm [file normalize [lindex $argv 0]]
set xpr_dir  [file dirname $xpr_norm]

# Output XDC: default to <xpr_dir>/auto_clock_fix.xdc
if {[llength $argv] > 1 && [lindex $argv 1] ne ""} {
    set output_xdc [file normalize [lindex $argv 1]]
} else {
    set output_xdc [file join $xpr_dir "auto_clock_fix.xdc"]
}

# Min Fanout: default to 4
set min_fanout 4
if {[llength $argv] > 2 && [lindex $argv 2] ne ""} {
    set min_fanout [lindex $argv 2]
}

puts "=================================================================="
puts ">>> \[A2F Batch\] 1. Loading Project: $xpr_norm"
puts "=================================================================="
if {![file exists $xpr_norm]} {
    puts "ERROR: Project file not found: $xpr_norm"
    exit 1
}
open_project $xpr_norm

puts "=================================================================="
puts ">>> \[A2F Batch\] 2. Elaborating RTL Netlist (synth_design -rtl)..."
puts "=================================================================="
synth_design -rtl -name rtl_1

# Load core retargeter logic
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir "clk_retarget.tcl"]

puts "=================================================================="
puts ">>> \[A2F Batch\] 3. Running Clock Analysis..."
puts ">>> Destination: $output_xdc (min_fanout: $min_fanout)"
puts "=================================================================="
retarget_clock_xdc $output_xdc $min_fanout

puts "=================================================================="
puts ">>> \[A2F Batch\] 4. Closing Project..."
puts "=================================================================="
close_project

puts "=================================================================="
puts ">>> \[A2F Batch\] ALL DONE! Target XDC: $output_xdc"
puts "=================================================================="
exit 0
