# =============================================================================
# Power Analysis — 6T SRAM Memory
# Tool   : OpenROAD power_analysis (post-route) OR OpenSTA with switching
# Usage  : openroad -no_init power_analysis.tcl
#
# Requires:
#   - Post-route netlist (DEF + SPEF or estimated parasitics)
#   - VCD from simulation for activity annotation
# =============================================================================

set PDK_ROOT $::env(PDK_ROOT)
set SCL      sky130_fd_sc_hd

# ---------------------------------------------------------------------------
# Read Liberty (TT corner for power)
# ---------------------------------------------------------------------------
read_liberty $PDK_ROOT/sky130A/libs.ref/$SCL/lib/${SCL}__tt_025C_1v80.lib

# ---------------------------------------------------------------------------
# Read post-synthesis netlist
# ---------------------------------------------------------------------------
read_verilog synth/openroad/yosys_out/sram_memory_mapped.v
link_design  sram_memory

read_sdc synth/openroad/sram_memory.sdc

# ---------------------------------------------------------------------------
# Estimate parasitics (post-placement or post-route)
# ---------------------------------------------------------------------------
if {[file exists synth/openroad/output/sram_memory_final.spef]} {
    read_spef synth/openroad/output/sram_memory_final.spef
    puts "=== Using extracted SPEF parasitics ==="
} else {
    estimate_parasitics -placement
    puts "=== Using estimated parasitics (no SPEF found) ==="
}

# ---------------------------------------------------------------------------
# Annotate switching activity from simulation VCD (if available)
# ---------------------------------------------------------------------------
if {[file exists sim_out/sram_sim.vcd]} {
    read_vcd -scope tb/dut sim_out/sram_sim.vcd
    puts "=== VCD activity annotation applied ==="
} else {
    # Default activity factors when no VCD is available:
    #   clock:   1.0 (toggles every half-cycle)
    #   internal: 0.2 (20% toggle rate — typical for SRAM at moderate load)
    #   inputs:   0.1
    set_power_activity -input         -activity 0.10 -duty 0.5
    set_power_activity -input_port clk -activity 1.0  -duty 0.5
    puts "=== Using default activity factors (no VCD) ==="
}

# ---------------------------------------------------------------------------
# Report power
# ---------------------------------------------------------------------------
report_power -corner [list TT] \
             -instances [all_registers] \
             -stdout

report_power -hierarchy -stdout

puts "\n=== Power analysis complete ==="
puts "Breakdown interpretation:"
puts "  Internal : short-circuit power + cell internal capacitance"
puts "  Switching : dynamic power = alpha * C * V^2 * f"
puts "  Leakage  : sub-threshold + gate-oxide leakage (dominant at idle)"
