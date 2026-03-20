// =============================================================================
// 6T SRAM Bitcell — Behavioural RTL model
// Description : Models the cross-coupled inverter storage latch with two
//               NMOS access transistors (M5, M6) gated by the word line.
//
// TRANSISTOR MAP (for layout reference):
//   M1(PMOS) + M2(NMOS) = Inverter 1 : output Q
//   M3(PMOS) + M4(NMOS) = Inverter 2 : output QB
//   M5(NMOS) : access — Q  <-> BL  (WL gate)
//   M6(NMOS) : access — QB <-> BLB (WL gate)
//
//   Sizing rules for SKY130 / 180nm:
//     Cell ratio  CR = W/L(M2) / W/L(M5) >= 1.5  (READ SNM)
//     Pull ratio  PR = W/L(M1) / W/L(M5) <= 0.8  (WRITE SNM)
//
// Bug fixes   : Replaced inout tri-state BL/BLB with explicit read_data/
//               write_data ports — synthesis tools cannot infer correct
//               intent from behavioural inout with 'Z' assignments.
//               Removed process sensitivity ambiguity (BL/BLB were both
//               drivers and sensitivity triggers in the VHDL version).
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_cell_6t (
    input  wire wl,          // Word line (M5, M6 gate)
    input  wire wr_en,       // Write enable — high when write driver active
    input  wire bl_in,       // Data from write driver (BL side)
    input  wire blb_in,      // Data from write driver (BLB side)
    output wire bl_out,      // Read data to sense amplifier (BL)
    output wire blb_out      // Read data to sense amplifier (BLB)
);

    // Internal storage nodes (initialised to known state for simulation)
    reg q;
    reg qb;

    initial begin
        q  = 1'b0;
        qb = 1'b1;
    end

    // Write path: WL and WR_EN both high => accept data from write driver
    // Cross-coupled feedback (M1-M4) is overpowered by write driver strength.
    always @(*) begin
        if (wl && wr_en) begin
            q  = bl_in;
            qb = blb_in;
        end
    end

    // Read path: present stored state to sense amplifier when WL is asserted.
    // BL discharges slightly through M5+M2 if Q=0 (small DeltaV from VDD).
    // Behavioural model presents the stored value directly.
    assign bl_out  = (wl && !wr_en) ? q  : 1'bz;
    assign blb_out = (wl && !wr_en) ? qb : 1'bz;

endmodule
`default_nettype wire
