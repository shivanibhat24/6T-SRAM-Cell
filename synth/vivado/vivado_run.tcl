# =============================================================================
# Vivado TCL Script — Simulation + Synthesis for 6T SRAM
# Usage (Vivado Tcl Console or batch):
#   vivado -mode batch -source vivado_run.tcl
# =============================================================================

# -----------------------------------------------------------------------------
# 0. Configuration
# -----------------------------------------------------------------------------
set project_name  "sram_6t"
set project_dir   "./vivado_project"
set part          "xc7a35tcpg236-1"   ;# Artix-7 Basys3 / Nexys A7

set rtl_files {
    ../rtl/sense_amplifier.v
    ../rtl/precharge.v
    ../rtl/write_driver.v
    ../rtl/sram_cell_6t.v
    ../rtl/row_decoder.v
    ../rtl/column_mux.v
    ../rtl/sram_array.v
    ../rtl/sram_memory.v
}

set tb_files {
    ../tb/sram_memory_tb.v
}

set xdc_files {
    ../constraints/sram_timing.xdc
}

# -----------------------------------------------------------------------------
# 1. Create Project
# -----------------------------------------------------------------------------
create_project $project_name $project_dir -part $part -force

# Set Verilog as the target language
set_property target_language Verilog [current_project]

# -----------------------------------------------------------------------------
# 2. Add Sources
# -----------------------------------------------------------------------------
add_files -norecurse $rtl_files
add_files -fileset sim_1 -norecurse $tb_files
add_files -fileset constrs_1 -norecurse $xdc_files

# Mark top modules
set_property top sram_memory          [current_fileset]
set_property top sram_memory_tb       [get_filesets sim_1]
set_property top_lib xil_defaultlib   [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# -----------------------------------------------------------------------------
# 3. Run Simulation (Behavioural)
# -----------------------------------------------------------------------------
puts "=== Running Behavioural Simulation ==="
launch_simulation -simset sim_1 -mode behavioral

# Run for 10 µs (covers all test phases)
run 10us

puts "=== Simulation complete — check Tcl console for PASS/FAIL ==="
close_sim

# -----------------------------------------------------------------------------
# 4. Synthesis
# -----------------------------------------------------------------------------
puts "=== Running Synthesis ==="
synth_design \
    -top sram_memory \
    -part $part \
    -flatten_hierarchy rebuilt \
    -directive PerformanceOptimized

# Report timing and utilisation
report_timing_summary -file ./vivado_project/timing_synth.rpt
report_utilization    -file ./vivado_project/util_synth.rpt

# Write synthesised netlist (for OpenROAD handoff)
write_verilog -force -mode funcsim ./vivado_project/sram_memory_synth_netlist.v

# -----------------------------------------------------------------------------
# 5. Implementation (optional — FPGA only, skip for ASIC flow)
# -----------------------------------------------------------------------------
# Uncomment the following for full Vivado FPGA implementation:
#
# puts "=== Running Implementation ==="
# opt_design
# place_design
# route_design
# report_timing_summary -file ./vivado_project/timing_impl.rpt
# write_bitstream -force ./vivado_project/sram_memory.bit

puts "=== Script complete ==="
