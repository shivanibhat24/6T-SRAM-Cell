# =============================================================================
# Vivado XDC Constraints — 6T SRAM Macro (Artix-7 xc7a35t target)
# Adjust for your board — default here matches Basys3 / Nexys A7
# =============================================================================

# -----------------------------------------------------------------------------
# Primary Clock — 100 MHz
# -----------------------------------------------------------------------------
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# -----------------------------------------------------------------------------
# Input timing (setup/hold relative to clk)
# Memory controller drives inputs 2 ns after clock edge.
# -----------------------------------------------------------------------------
set_input_delay  -clock clk -max 3.0 [get_ports {address[*] data_in[*] cs rw rst_n}]
set_input_delay  -clock clk -min 0.5 [get_ports {address[*] data_in[*] cs rw rst_n}]

# -----------------------------------------------------------------------------
# Output timing
# Consumer captures output 3 ns before next clock edge.
# -----------------------------------------------------------------------------
set_output_delay -clock clk -max 3.0 [get_ports {data_out[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {data_out[*]}]

# -----------------------------------------------------------------------------
# False paths — async reset deassert (reset synchroniser assumed external)
# -----------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# -----------------------------------------------------------------------------
# Pin placement (Basys3 example — remove/override for custom board)
# Uncomment and assign per your board's XDC.
# -----------------------------------------------------------------------------
# set_property PACKAGE_PIN W5  [get_ports clk]
# set_property IOSTANDARD  LVCMOS33 [get_ports clk]

# -----------------------------------------------------------------------------
# Bitstream settings
# -----------------------------------------------------------------------------
set_property CFGBVS         VCCO [current_design]
set_property CONFIG_VOLTAGE  3.3  [current_design]
