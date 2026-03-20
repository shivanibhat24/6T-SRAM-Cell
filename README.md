# 6T SRAM Memory Macro — Verilog Repository

A parameterisable, synthesis-ready 6T SRAM RTL implementation targeting
SKY130B (ASIC) and Artix-7 (FPGA). Converted and bug-fixed from VHDL original.

---

## Repository Structure

```
sram_6t/
|
├── rtl/
│   ├── sense_amplifier.v            — Registered differential sense amplifier
│   ├── precharge.v                  — Bitline precharge (active-high PCH)
│   ├── write_driver.v               — BL/BLB write driver
│   ├── sram_cell_6t.v               — 6T bitcell (behavioural RTL)
│   ├── row_decoder.v                — Binary-to-one-hot row decoder
│   ├── column_mux.v                 — Bitline column selector
│   ├── sram_array.v                 — 16x8 array + 4-phase FSM
│   └── sram_memory.v                — Top-level with chip-select
├── tb/
│   ├── sram_memory_tb.v             — Self-checking functional testbench
│   ├── sram_corner_tb.v             — 7-corner access pattern sweep
│   ├── sram_memory_gls_tb.v         — Gate-level sim + glitch checker
│   ├── sram_formal_props.v          — Formal SVA properties
│   ├── sram_formal.sby              — SymbiYosys configuration
│   └── verilator.vlt                — Verilator lint config
├── constraints/
│   └── sram_timing.xdc              — Vivado XDC (100 MHz, Artix-7)
├── synth/
│   ├── vivado/
│   │   └── vivado_run.tcl           — Vivado batch script (sim + synth)
│   └── openroad/
│       ├── config.json              — OpenLane2 RTL-to-GDS config
│       ├── yosys_synth.ys           — Yosys standalone synthesis
│       ├── openroad_flow.tcl        — Manual OpenROAD Tcl flow
│       ├── sram_memory.sdc          — SDC timing constraints
│       ├── sta_run.tcl              — Multi-corner STA (TT/SS/FF)
│       └── power_analysis.tcl       — Post-route power estimation
|── Makefile                         — One-command entry point for all flows

```

---

## Quick Start

```bash
# No EDA licence required — Icarus Verilog:
make sim-iv

# Corner sweep (7 access patterns):
iverilog -o corner_sim rtl/*.v tb/sram_corner_tb.v && vvp corner_sim

# Full RTL-to-GDS:
make openlane
```

---

## Key Bug Fixes vs. Original VHDL

| # | Original VHDL Bug | Verilog Fix |
|---|---|---|
| 1 | `inout` BL/BLB — driver contention between precharge, write driver, cell | Separated into `bl_in`/`bl_out`; explicit priority MUX in `sram_array` |
| 2 | Sense amplifier was a transparent latch (no clock) | Replaced with clocked flip-flop on `posedge clk` |
| 3 | FSM used `integer variable` — not a synthesisable state register | `localparam` state encoding + `always @(posedge clk)` |
| 4 | `'Z'` in combinational blocks — no internal tristate fabric on FPGA | All tristates replaced with enable-gated MUXes |
| 5 | No active-low reset | `rst_n` added throughout; cells initialised with `initial` |
| 6 | No bitline arbitration | Priority: precharge > write driver > cell read |
| 7 | Column mux drove `'Z'` in non-selected state | Replaced with `0`-gated output |

---

## Vivado Steps

### A — Batch Mode (Recommended)

```bash
cd synth/vivado/
vivado -mode batch -source vivado_run.tcl
# Outputs: vivado_project/timing_synth.rpt
#          vivado_project/util_synth.rpt
#          vivado_project/sram_memory_synth_netlist.v
```

### B — GUI Mode Step-by-Step

#### 1. Create Project
```
File > Project > New
  Name: sram_6t
  Type: RTL Project
  Part: xc7a35tcpg236-1  (Basys3 / Nexys A7)
```

#### 2. Add Design Sources
```
Add Sources > Design Sources > Add Files
  Select: rtl/sense_amplifier.v
          rtl/precharge.v
          rtl/write_driver.v
          rtl/sram_cell_6t.v
          rtl/row_decoder.v
          rtl/column_mux.v
          rtl/sram_array.v
          rtl/sram_memory.v
```

#### 3. Add Simulation Sources
```
Add Sources > Simulation Sources > Add Files
  Select: tb/sram_memory_tb.v
          tb/sram_corner_tb.v
```

#### 4. Add Constraints
```
Add Sources > Constraints > Add Files
  Select: constraints/sram_timing.xdc
```

#### 5. Set Top Modules
```
Sources panel:
  Right-click sram_memory    > Set as Top  (Design Sources)
  Right-click sram_memory_tb > Set as Top  (Simulation Sources)
```

#### 6. Check Elaborated Design (Optional but Recommended)
```
Flow Navigator > RTL Analysis > Open Elaborated Design
  Schematic: verify FSM states and module hierarchy are correct
  Report > Report Methodology — flags CDC, reset, fanout issues
```

#### 7. Run Behavioural Simulation
```
Flow Navigator > Simulation > Run Simulation > Run Behavioral Simulation
  Tcl Console: check for "ALL TESTS PASSED"
  Waveform window: add signals:
    clk, rst_n, cs, rw, address[3:0], data_in[7:0], data_out[7:0]
  Run > Run All  (or Run For 10us)
```

#### 8. Run Synthesis
```
Flow Navigator > Synthesis > Run Synthesis
  Settings (optional):
    Strategy: Flow_PerfOptimized_high
    Flatten Hierarchy: rebuilt
  After completion:
    Reports > Timing Summary   (verify WNS > 0 ns)
    Reports > Utilization      (note LUT and FF counts)
    Schematic > view gate-level result
```

#### 9. (FPGA Only) Implementation + Bitstream
```
Flow Navigator > Implementation > Run Implementation
Flow Navigator > Generate Bitstream
Hardware Manager > Open Target > Program Device > sram_memory.bit
```

---

## RTL-to-GDS Flow — OpenROAD / OpenLane2

### Prerequisites

```bash
pip install openlane
pip install volare

export PDK_ROOT=$HOME/.volare
volare enable --pdk sky130 bdc9412b3e468c102d01b7cf6337be06ec6e9c9a

# Verify
openlane --version
ls $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/
```

### Option A — Fully Automated (OpenLane2)

```bash
cd synth/openroad/
openlane config.json

# Outputs:
#   runs/RUN_<timestamp>/final/gds/sram_memory.gds    <- GDSII
#   runs/RUN_<timestamp>/final/lef/sram_memory.lef    <- Abstract for integration
#   runs/RUN_<timestamp>/reports/                     <- DRC, LVS, timing
```

### Option B — Manual Step-by-Step

#### Step 1 — Synthesis (Yosys)
```bash
export PDK_ROOT=$HOME/.volare
mkdir -p synth/openroad/yosys_out
cd synth/openroad && yosys yosys_synth.ys
# -> yosys_out/sram_memory_mapped.v  (gate-level netlist)
# -> yosys_out/stat.txt              (cell counts)
```

#### Step 2 — Floorplan
```tcl
initialize_floorplan -utilization 45 -aspect_ratio 1.0 -core_space 10.0
place_pins -hor_layers met2 -ver_layers met3
```

#### Step 3 — PDN Generation
```tcl
add_global_connection -net VDD -pin_pattern {^VDD$} -power
add_global_connection -net VSS -pin_pattern {^VSS$} -ground
global_connect
pdngen
```

#### Step 4 — Placement
```tcl
global_placement -skip_initial_place
estimate_parasitics -placement
repair_design                    # timing-driven buffer insertion
detailed_placement
check_placement -verbose
```

#### Step 5 — Clock Tree Synthesis
```tcl
clock_tree_synthesis \
    -root_buf sky130_fd_sc_hd__clkbuf_8 \
    -buf_list sky130_fd_sc_hd__clkbuf_4
set_propagated_clock [all_clocks]
repair_timing -setup -hold
detailed_placement
```

#### Step 6 — Routing
```tcl
global_route -congestion_iterations 10
detailed_route -output_drc route_drc.rpt
filler_placement sky130_fd_sc_hd__fill_1
```

#### Step 7 — Final STA
```tcl
estimate_parasitics -global_routing
report_checks -path_delay min_max -format full_clock_expanded
write_def output/sram_memory_final.def
```

#### Step 8 — GDS Export (Magic)
```bash
magic -rcfile $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc -noconsole << 'EOF'
lef read $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef
def read synth/openroad/output/sram_memory_final.def
gds write synth/openroad/output/sram_memory.gds
EOF
```

#### Step 9 — DRC (KLayout)
```bash
klayout -b \
  -r $PDK_ROOT/sky130A/libs.tech/klayout/sky130A.lydrc \
  -rd input=synth/openroad/output/sram_memory.gds \
  -rd report=synth/openroad/output/drc.lyrdb
```

#### Step 10 — LVS (Netgen)
```bash
netgen -batch lvs \
  "synth/openroad/yosys_out/sram_memory_mapped.v sram_memory" \
  "synth/openroad/output/sram_memory.gds sram_memory" \
  $PDK_ROOT/sky130A/libs.tech/netgen/sky130A_setup.tcl \
  synth/openroad/output/lvs_report.txt
```

---

## Multi-Corner Static Timing Analysis

```bash
export PDK_ROOT=$HOME/.volare
export SCL=sky130_fd_sc_hd
sta synth/openroad/sta_run.tcl | tee sim_out/sta.log

# Corners:
#   TT  1.8V  25C  — nominal (setup + hold)
#   SS  1.6V  85C  — worst setup (max path, slowest cells)
#   FF  2.0V -40C  — worst hold  (min path, fastest cells)
# Pass criteria: WNS >= 0 on ALL corners
```

---

## Gate-Level Simulation

```bash
make gls
# Compiles post-Yosys netlist against SKY130 cell models
# Adds: X-propagation check, per-cycle glitch counter, SDF hook
```

---

## Formal Verification

```bash
# Requires oss-cad-suite: https://github.com/YosysHQ/oss-cad-suite-build
cd tb/
sby -f sram_formal.sby

# Modes run:
#   bmc   — Bounded model check (20 cycles)  — finds bugs fast
#   prove — k-induction proof                — proves all reachable states safe
#   cover — Reachability check               — confirms interesting states reached
#
# Properties:
#   P1. data_out = 0 within 1 cycle of reset deassertion
#   P2. No state change when CS=0 (full isolation)
#   P3. data_out never X/Z during a valid read window
#   P4. rd_en and wr_en are mutually exclusive at all times
```

---

## GitHub Actions CI

The `.github/workflows/ci.yml` pipeline runs automatically on every push:

| Job | Tool | Checks |
|---|---|---|
| Lint | Verilator | Undriven signals, width mismatches, implicit nets |
| sim-behavioural | Icarus Verilog | All 16-address write-read, overwrite, CS deassert |
| sim-corners | Icarus Verilog | 7 corner patterns: back-to-back, interleaved, rapid overwrite, hold SNM stress, checkerboard, walking-1 |
| synth-generic | Yosys | Clean synthesis to generic gates (no PDK needed) |

---

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `ADDR_WIDTH` | 4 | Address bits — 2^N rows (default: 16) |
| `DATA_WIDTH` | 8 | Data word width in bits |
| `OUTPUT_TRISTATE` | 0 | 1 = float data_out when CS=0 (multi-chip bus) |

Scale to 256 rows x 32 bits: `ADDR_WIDTH=8, DATA_WIDTH=32`.

---

## Timing Model (100 MHz / 10 ns cycle)

| Phase | Cycles | Signals asserted |
|---|---|---|
| PRECHARGE | 1 | PCH=1, BL/BLB driven to VDD |
| ACCESS | 1 | decoder_en=1, WL asserted |
| SENSE | 1 | SE pulsed, differential captured by sense amp |
| Output register | 1 | data_out updated from sense amp |
| **Total read latency** | **4** | From cs+rw to valid data_out |
| **Write latency** | **1** | Single-cycle direct write |


### My Results 

1. Vivado Synthesized Design
   <img width="1777" height="645" alt="image" src="https://github.com/user-attachments/assets/6cda06c7-493d-40a9-a31a-1f2a29931d4c" />

