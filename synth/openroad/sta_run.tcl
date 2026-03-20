# =============================================================================
# OpenSTA Multi-Corner Timing Analysis — 6T SRAM Memory
# Tool   : OpenSTA (standalone) or OpenROAD sta command
# Usage  : sta synth/openroad/sta_run.tcl
#
# Corners analysed:
#   TT 1.8V 25°C  — nominal
#   SS 1.6V 85°C  — slow-slow (worst setup)
#   FF 2.0V -40°C — fast-fast (worst hold)
# =============================================================================

set PDK_ROOT $::env(PDK_ROOT)
set SCL      sky130_fd_sc_hd
set NETLIST  synth/openroad/yosys_out/sram_memory_mapped.v
set SDC      synth/openroad/sram_memory.sdc

# ---------------------------------------------------------------------------
# Helper proc: run STA for one corner
# ---------------------------------------------------------------------------
proc run_corner {corner_name lib_path} {
    global NETLIST SDC

    puts "\n============================================================"
    puts "Corner: $corner_name"
    puts "============================================================"

    read_liberty $lib_path
    read_verilog $NETLIST
    link_design sram_memory
    read_sdc $SDC

    # Setup (max path)
    report_checks -path_delay max \
                  -format full_clock_expanded \
                  -fields {slew cap input_pins nets} \
                  -digits 3 \
                  -group_count 5

    # Hold (min path)
    report_checks -path_delay min \
                  -format full_clock_expanded \
                  -digits 3 \
                  -group_count 5

    # Worst negative slack summary
    report_wns
    report_tns
    report_check_types -max_slew -max_cap -max_fanout

    # Clock skew
    report_clock_skew

    puts "--- $corner_name complete ---\n"
}

# ---------------------------------------------------------------------------
# TT Corner — Nominal (25°C, 1.8V)
# ---------------------------------------------------------------------------
run_corner "TT 1.8V 25C" \
    $PDK_ROOT/sky130A/libs.ref/$::env(SCL)/lib/${SCL}__tt_025C_1v80.lib

# ---------------------------------------------------------------------------
# SS Corner — Worst Setup (85°C, 1.6V)
# ---------------------------------------------------------------------------
run_corner "SS 1.6V 85C" \
    $PDK_ROOT/sky130A/libs.ref/$::env(SCL)/lib/${SCL}__ss_100C_1v60.lib

# ---------------------------------------------------------------------------
# FF Corner — Worst Hold (-40°C, 2.0V)
# ---------------------------------------------------------------------------
run_corner "FF 2.0V -40C" \
    $PDK_ROOT/sky130A/libs.ref/$::env(SCL)/lib/${SCL}__ff_n40C_1v95.lib

puts "\n=== Multi-corner STA complete ==="
