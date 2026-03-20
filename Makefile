# =============================================================================
# Makefile — 6T SRAM Memory Macro
# Targets  : sim-iv, sim-vcs, sim-questa, synth-yosys, synth-vivado,
#            gls, sta, openlane, clean
# =============================================================================

DESIGN     := sram_memory
TOP_TB     := sram_memory_tb
PDK_ROOT   ?= $(HOME)/.volare
PDK        := sky130A
SCL        := sky130_fd_sc_hd
LIB_TT     := $(PDK_ROOT)/$(PDK)/libs.ref/$(SCL)/lib/$(SCL)__tt_025C_1v80.lib
TECHMAP    := $(PDK_ROOT)/$(PDK)/libs.ref/$(SCL)/techlef/$(SCL).tlef
CELLLEF    := $(PDK_ROOT)/$(PDK)/libs.ref/$(SCL)/lef/$(SCL).lef

RTL_SRCS   := rtl/sense_amplifier.v \
              rtl/precharge.v        \
              rtl/write_driver.v     \
              rtl/sram_cell_6t.v     \
              rtl/row_decoder.v      \
              rtl/column_mux.v       \
              rtl/sram_array.v       \
              rtl/sram_memory.v

TB_SRCS    := tb/sram_memory_tb.v
GLS_SRCS   := synth/openroad/yosys_out/$(DESIGN)_mapped.v

IVFLAGS    := -Wall -Wno-timescale
VCSFLAGS   := -full64 -sverilog +v2k -timescale=1ns/1ps
QUEFLAGS   := -sv -timescale 1ns/1ps

.PHONY: all sim-iv sim-vcs sim-questa synth-yosys synth-vivado \
        gls sta openlane wave lint clean help

all: sim-iv

# ---------------------------------------------------------------------------
# Behavioural simulation — Icarus Verilog (free)
# ---------------------------------------------------------------------------
sim-iv: $(RTL_SRCS) $(TB_SRCS)
	@echo "=== Icarus Verilog simulation ==="
	@mkdir -p sim_out
	iverilog $(IVFLAGS) -o sim_out/$(DESIGN)_sim $(RTL_SRCS) $(TB_SRCS)
	vvp sim_out/$(DESIGN)_sim | tee sim_out/sim_results.log
	@grep -E "PASS|FAIL|COMPLETE" sim_out/sim_results.log

# ---------------------------------------------------------------------------
# Behavioural simulation — Synopsys VCS
# ---------------------------------------------------------------------------
sim-vcs: $(RTL_SRCS) $(TB_SRCS)
	@echo "=== VCS simulation ==="
	@mkdir -p sim_out
	vcs $(VCSFLAGS) -o sim_out/$(DESIGN)_vcs $(RTL_SRCS) $(TB_SRCS) \
	    -l sim_out/vcs_compile.log
	sim_out/$(DESIGN)_vcs -l sim_out/vcs_sim.log
	@grep -E "PASS|FAIL|COMPLETE" sim_out/vcs_sim.log

# ---------------------------------------------------------------------------
# Behavioural simulation — Mentor Questa / ModelSim
# ---------------------------------------------------------------------------
sim-questa: $(RTL_SRCS) $(TB_SRCS)
	@echo "=== Questa simulation ==="
	@mkdir -p sim_out/questa_work
	vlib sim_out/questa_work
	vmap work sim_out/questa_work
	vlog $(QUEFLAGS) $(RTL_SRCS) $(TB_SRCS) -l sim_out/questa_compile.log
	vsim -batch -do "run -all; quit -f" work.$(TOP_TB) \
	     -l sim_out/questa_sim.log
	@grep -E "PASS|FAIL|COMPLETE" sim_out/questa_sim.log

# ---------------------------------------------------------------------------
# Waveform viewer (GTKWave)
# ---------------------------------------------------------------------------
wave: sim_out/sram_sim.vcd
	gtkwave sim_out/sram_sim.vcd &

sim_out/sram_sim.vcd: sim-iv

# ---------------------------------------------------------------------------
# Lint — Verilator
# ---------------------------------------------------------------------------
lint:
	@echo "=== Verilator lint ==="
	verilator --lint-only -Wall \
	    --top-module $(DESIGN) $(RTL_SRCS) 2>&1 | tee lint_report.txt
	@echo "Lint report: lint_report.txt"

# ---------------------------------------------------------------------------
# Yosys synthesis (standalone, pre-OpenROAD)
# ---------------------------------------------------------------------------
synth-yosys: $(RTL_SRCS)
	@echo "=== Yosys synthesis ==="
	@mkdir -p synth/openroad/yosys_out
	cd synth/openroad && \
	    PDK_ROOT=$(PDK_ROOT) yosys yosys_synth.ys 2>&1 | tee ../../sim_out/yosys.log
	@echo "Netlist: synth/openroad/yosys_out/$(DESIGN)_mapped.v"

# ---------------------------------------------------------------------------
# Vivado batch synthesis + simulation
# ---------------------------------------------------------------------------
synth-vivado: $(RTL_SRCS) $(TB_SRCS)
	@echo "=== Vivado batch flow ==="
	cd synth/vivado && vivado -mode batch -source vivado_run.tcl \
	    2>&1 | tee ../../sim_out/vivado.log

# ---------------------------------------------------------------------------
# Gate-level simulation (post-Yosys netlist)
# ---------------------------------------------------------------------------
gls: synth-yosys
	@echo "=== Gate-level simulation ==="
	@mkdir -p sim_out
	iverilog $(IVFLAGS) \
	    -o sim_out/$(DESIGN)_gls \
	    -DFUNCTIONAL -DUNIT_DELAY='#1' \
	    $(PDK_ROOT)/$(PDK)/libs.ref/$(SCL)/verilog/$(SCL).v \
	    $(GLS_SRCS) $(TB_SRCS)
	vvp sim_out/$(DESIGN)_gls | tee sim_out/gls_results.log
	@grep -E "PASS|FAIL|COMPLETE" sim_out/gls_results.log

# ---------------------------------------------------------------------------
# Static Timing Analysis — OpenROAD sta (standalone)
# ---------------------------------------------------------------------------
sta: synth-yosys
	@echo "=== OpenSTA analysis ==="
	@mkdir -p sim_out
	sta synth/openroad/sta_run.tcl 2>&1 | tee sim_out/sta.log
	@echo "STA log: sim_out/sta.log"

# ---------------------------------------------------------------------------
# Full RTL-to-GDS — OpenLane2
# ---------------------------------------------------------------------------
openlane:
	@echo "=== OpenLane2 RTL-to-GDS ==="
	cd synth/openroad && openlane config.json

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	rm -rf sim_out/ lint_report.txt
	rm -rf synth/openroad/yosys_out/
	rm -rf synth/vivado/vivado_project/
	rm -rf vivado*.jou vivado*.log
	rm -rf *.vcd

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo ""
	@echo "6T SRAM Makefile targets:"
	@echo "  make sim-iv       — Icarus Verilog behavioural sim (free)"
	@echo "  make sim-vcs      — Synopsys VCS behavioural sim"
	@echo "  make sim-questa   — Mentor Questa/ModelSim sim"
	@echo "  make wave         — Open GTKWave with VCD"
	@echo "  make lint         — Verilator lint check"
	@echo "  make synth-yosys  — Yosys synthesis to SKY130 gates"
	@echo "  make synth-vivado — Vivado synthesis (FPGA)"
	@echo "  make gls          — Gate-level simulation (post-synth)"
	@echo "  make sta          — OpenSTA static timing analysis"
	@echo "  make openlane     — Full RTL-to-GDS via OpenLane2"
	@echo "  make clean        — Remove all generated files"
	@echo ""
	@echo "Key variables (override on command line):"
	@echo "  PDK_ROOT=$(PDK_ROOT)"
	@echo ""
