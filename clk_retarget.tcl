# ==============================================================================
# Tool: A2F (ASIC-to-FPGA) Clock Retargeter & Constraint Synthesizer
# Description:
#   Automatically infers clock topologies from synthesized ASIC RTL netlists,
#   prunes low-fanout noise/carry logic, traces physical driver pins/ports,
#   and synthesizes XDC timing constraints with asynchronous clock domain isolation.
#
# Core Capabilities:
#   1. True Clock Sinks Filter: Prunes ripple counters and noise registers
#      by filtering true clock pin fanouts (C / CLK pins >= min_fanout).
#   2. BUFG & Pin Clean Naming: Resolves hierarchical physical driver pins
#      and restores readable clock names from instance/net paths.
#   3. Automated CDC Isolation: Generates global asynchronous clock groups
#      to prevent cross-domain false-path timing congestion during FPGA bring-up.
#   4. Portability: 100% pure ASCII, zero vendor/project hardcoding.
# ==============================================================================

proc retarget_clock_xdc {
    output_xdc_file 
    {min_fanout 4} 
    {default_period 1000.000}
} {
    puts "=================================================================="
    puts ">>> \[1/3\] Scanning True Clock Sinks (C / CLK pins)..."
    puts "=================================================================="

    set clock_sink_pins [get_pins -quiet -hierarchical -filter {IS_CLOCK == 1 || NAME =~ "*/C" || NAME =~ "*/CLK"}]
    set total_sinks [llength $clock_sink_pins]
    puts ">>> Total True Clock Sinks detected: $total_sinks"

    if {$total_sinks == 0} {
        puts "ERROR: No clock sink pins found! Please run 'synth_design -rtl' first!"
        return
    }

    set clock_nets [get_nets -quiet -of_objects $clock_sink_pins]

    puts "=================================================================="
    puts ">>> \[2/3\] Filtering major clocks by True Clock Sinks >= $min_fanout..."
    puts "=================================================================="

    set handled_drivers [list]
    set detected_clocks [list]
    set clock_names     [list]

    foreach net $clock_nets {
        # Strict True Clock Sinks Filter: only count actual clock pins
        set true_sinks [get_pins -quiet -filter {IS_CLOCK == 1 || NAME =~ "*/C" || NAME =~ "*/CLK"} -of_objects $net]
        set true_fanout [llength $true_sinks]

        if {$true_fanout < $min_fanout} {
            continue
        }

        set net_name [get_property NAME $net]

        set driver_ports [get_ports -quiet -filter {DIRECTION == IN}  -of_objects $net]
        set driver_pins  [get_pins  -quiet -leaf -filter {DIRECTION == OUT} -of_objects $net]

        # Scenario A: Primary Input Ports
        foreach port $driver_ports {
            set p_name [get_property NAME $port]
            if {[lsearch -exact $handled_drivers $p_name] != -1} { continue }
            lappend handled_drivers $p_name

            set c_name [regsub -all {[/:\\[\\]]} $p_name _]
            set c_name [string trimright $c_name "_"]

            lappend clock_names $c_name
            lappend detected_clocks [dict create name $c_name fanout $true_fanout type "PORT" target "\[get_ports {$p_name}\]" period $default_period raw $p_name]
        }

        # Scenario B: Leaf Physical Pins (DFF Q or Combinational Gate/BUFG Output)
        foreach pin $driver_pins {
            set pin_name [get_property NAME $pin]
            if {[lsearch -exact $handled_drivers $pin_name] != -1} { continue }
            lappend handled_drivers $pin_name

            set inst_name [lindex [split $pin_name "/"] end-1]
            set clean_inst $inst_name

            regsub {_reg$} $clean_inst "" clean_inst
            regsub {_reg\[([0-9]+)\]$} $clean_inst "_b\\1" clean_inst
            regsub {_BUFG_inst$} $clean_inst "" clean_inst
            regsub {_BUFG$} $clean_inst "" clean_inst
            regsub {_bufg$} $clean_inst "" clean_inst

            set clean_inst [regsub -all {[/:\\[\\]]} $clean_inst _]
            set clean_inst [string trimright $clean_inst "_"]

            set is_reg_q [expr {[string match {*_reg/Q*} $pin_name] || [string match {*/Q*} $pin_name] || [string match {*_reg\[*/Q*} $pin_name]}]

            if {$is_reg_q} {
                set c_name $clean_inst
                set target_str "\[get_pins {$pin_name}\]"
            } else {
                # Prioritize instance name if it is a BUFG, otherwise use leaf net name
                if {[string match {*_BUFG*} [lindex [split $pin_name "/"] end-1]]} {
                    set c_name $clean_inst
                    set target_str "\[get_pins {$pin_name}\]"
                } else {
                    set leaf_net [lindex [split $net_name "/"] end]
                    set clean_net [regsub -all {[/:\\[\\]]} $leaf_net _]
                    set clean_net [string trimright $clean_net "_"]
                    set c_name $clean_net
                    set target_str "\[get_pins -quiet -filter {DIRECTION == OUT} -of_objects \[get_nets {$net_name}\]\]"
                }
            }

            set final_name $c_name
            set dup_cnt 1
            while {[lsearch -exact $clock_names $final_name] != -1} {
                set final_name "${c_name}_${dup_cnt}"
                incr dup_cnt
            }

            lappend clock_names $final_name
            lappend detected_clocks [dict create name $final_name fanout $true_fanout type "INTERNAL" target $target_str period $default_period raw $pin_name]
        }
    }

    # Sort by true clock fanout descending
    set sorted_clocks [lsort -decreasing -integer -index 3 $detected_clocks]
    set num_clocks [llength $sorted_clocks]

    puts ">>> Successfully locked major clock domains: $num_clocks"

    puts "=================================================================="
    puts ">>> \[3/3\] Exporting retargeted XDC constraints to: $output_xdc_file ..."
    puts "=================================================================="

    set fp [open $output_xdc_file "w"]
    puts $fp "# =============================================================================="
    puts $fp "# Auto-Generated by A2F Clock Retargeter (ASIC-to-FPGA Prototyping)"
    puts $fp "# Filter Criterion : True Clock Sinks >= $min_fanout"
    puts $fp "# Total Clocks     : $num_clocks"
    puts $fp "# Generated Time   : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fp "# Note: Modify period for Primary Ports according to on-board oscillator"
    puts $fp "# =============================================================================="
    puts $fp ""

    foreach clk $sorted_clocks {
        set c_name   [dict get $clk name]
        set c_fanout [dict get $clk fanout]
        set c_type   [dict get $clk type]
        set c_target [dict get $clk target]
        set c_period [dict get $clk period]
        set c_raw    [dict get $clk raw]

        if {$c_type eq "PORT"} {
            puts $fp "# (Primary Clock Port) True Sinks: $c_fanout | Source Port: $c_raw"
            puts $fp [format "create_clock -period %-8.3f -name %-20s %s ;# Update period per board clock" $c_period $c_name $c_target]
        } else {
            puts $fp "# (Internal Derived Clock) True Sinks: $c_fanout | Driver Pin/Net: $c_raw"
            puts $fp [format "create_clock -period %-8.3f -name %-20s %s" $c_period $c_name $c_target]
        }
    }

    puts $fp ""
    puts $fp "# =============================================================================="
    puts $fp "# Asynchronous Clock Groups (Prevent cross-domain false timing congestion)"
    puts $fp "# =============================================================================="
    puts $fp "set_clock_groups -asynchronous \\"
    set total [llength $clock_names]
    set idx 0
    foreach c $clock_names {
        incr idx
        if {$idx < $total} {
            puts $fp "    -group \[get_clocks {$c}\] \\"
        } else {
            puts $fp "    -group \[get_clocks {$c}\]"
        }
    }

    close $fp
    puts "=================================================================="
    puts ">>> (SUCCESS) Retargeted constraints successfully written to: $output_xdc_file"
    puts "=================================================================="
}
