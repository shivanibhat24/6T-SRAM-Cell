# =============================================================================
# OpenROAD / OpenLane RTL-to-GDS Flow — 6T SRAM Memory (SKY130B PDK)
# =============================================================================
#
# PREREQUISITES:
#   1. OpenLane2 installed: https://openlane2.readthedocs.io
#      pip install openlane
#   2. SKY130B PDK installed via volare:
#      pip install volare
#      volare enable --pdk sky130 <latest-hash>
#   3. This file lives in: sram_6t/synth/openroad/
#
# DIRECTORY LAYOUT EXPECTED BY THIS SCRIPT:
#   sram_6t/
#   ├── rtl/          (all .v files)
#   ├── synth/openroad/
#   │   ├── config.json      (OpenLane2 config — see below)
#   │   └── openroad_flow.tcl (this file, for manual OpenROAD)
#
# =============================================================================

# -----------------------------------------------------------------------------
# OPTION A — OpenLane2 (recommended, fully automated RTL-to-GDS)
# -----------------------------------------------------------------------------
# Run from sram_6t/synth/openroad/:
#
#   openlane config.json
#
# This invokes: Yosys synthesis → OpenROAD floorplan → placement → CTS →
#               routing → KLayout DRC/LVS → Magic → final GDS.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OPTION B — Manual OpenROAD Tcl (step-by-step, for debugging)
# Run: openroad -no_init openroad_flow.tcl
# -----------------------------------------------------------------------------

# ---  B.0 Read Liberty and LEF  ----------------------------------------------
read_liberty  $::env(PDK_ROOT)/sky130B/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_lef      $::env(PDK_ROOT)/sky130B/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef
read_lef      $::env(PDK_ROOT)/sky130B/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef

# ---  B.1 Read synthesised netlist (from Yosys, see yosys_synth.ys)  ---------
read_verilog  ../../vivado_project/sram_memory_synth_netlist.v
# OR use Yosys output directly:
# read_verilog  yosys_out/sram_memory_mapped.v

link_design sram_memory

# ---  B.2 Read SDC timing constraints  ---------------------------------------
read_sdc      sram_memory.sdc

# ---  B.3 Floorplan  ---------------------------------------------------------
# Die area: 200 µm × 200 µm (adjust to achieve ~40-60 % utilisation)
initialize_floorplan \
    -utilization    45 \
    -aspect_ratio   1.0 \
    -core_space     10.0

# Add I/O pins
place_pins -hor_layers met2 -ver_layers met3

# ---  B.4 PDN (Power Distribution Network) generation  ----------------------
add_global_connection -net {VDD} -pin_pattern {^VDD$} -power
add_global_connection -net {VSS} -pin_pattern {^VSS$} -ground
global_connect

pdngen

# ---  B.5 Macro placement (if hardened SRAM macro is used, place here) ------
# Not needed for synthesised SRAM — handled by standard cell placement below.

# ---  B.6 Global Placement  --------------------------------------------------
global_placement -skip_initial_place

# ---  B.7 Resize / Timing repair (hold & setup)  -----------------------------
estimate_parasitics -placement
repair_design

# ---  B.8 Detailed Placement  ------------------------------------------------
detailed_placement
check_placement -verbose

# ---  B.9 Clock Tree Synthesis  ----------------------------------------------
clock_tree_synthesis -root_buf sky130_fd_sc_hd__clkbuf_8 \
                     -buf_list sky130_fd_sc_hd__clkbuf_4
set_propagated_clock [all_clocks]

# ---  B.10 Timing repair after CTS  -----------------------------------------
repair_timing -setup -hold
detailed_placement

# ---  B.11 Global Routing  ---------------------------------------------------
global_route \
    -guide_file route_guide.txt \
    -congestion_iterations 10

# ---  B.12 Detailed Routing  -------------------------------------------------
detailed_route -output_drc route_drc.rpt

# ---  B.13 Filler insertion  -------------------------------------------------
filler_placement sky130_fd_sc_hd__fill_1

# ---  B.14 Parasitics extraction and final STA  ------------------------------
estimate_parasitics -global_routing
report_checks -path_delay min_max -format full_clock_expanded

# ---  B.15 Write outputs  ----------------------------------------------------
write_def      output/sram_memory_final.def
write_verilog  output/sram_memory_final_netlist.v

# GDS/GDSII written by Magic or KLayout post-route (invoked by OpenLane):
# magic -rcfile $PDK_ROOT/sky130B/libs.tech/magic/sky130A.magicrc \
#       -noconsole -dnull << EOF
# gds read output/sram_memory_final.gds
# EOF

puts "=== OpenROAD flow complete ==="
