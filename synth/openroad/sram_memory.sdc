# =============================================================================
# SDC Constraints — 6T SRAM Memory
# Used by both OpenROAD STA and Vivado (equivalent XDC also provided)
# =============================================================================

# 100 MHz clock
create_clock -name clk -period 10.0 [get_ports clk]

# Input delays (source synchronous — 2 ns after clk edge)
set_input_delay  -clock clk -max 3.0 [get_ports {address[*] data_in[*] cs rw}]
set_input_delay  -clock clk -min 0.5 [get_ports {address[*] data_in[*] cs rw}]

# Output delays (consumer captures 3 ns before next clk edge)
set_output_delay -clock clk -max 3.0 [get_ports {data_out[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {data_out[*]}]

# Reset is asynchronous (or driven by a synchroniser external to this block)
set_false_path -from [get_ports rst_n]

# Max transition / capacitance (sky130_fd_sc_hd typical)
set_max_transition 0.5 [current_design]
set_max_capacitance 0.2 [current_design]

# Drive strength on inputs (assume 4× buffer driving this module)
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 [all_inputs]
set_load 0.05 [all_outputs]
