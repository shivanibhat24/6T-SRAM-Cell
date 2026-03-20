// =============================================================================
// Sense Amplifier — Voltage-mode differential latch
// Author      : Converted from VHDL by Shivani Bhat
// Description : Detects small BL/BLB differential and drives full-swing output.
//               In silicon: cross-coupled PMOS/NMOS latch enabled by SE pulse.
//               SE must be asserted AFTER precharge is released and WL is HIGH.
// Bug fixes   : Added explicit reset; output held via registered flop (not latch).
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sense_amplifier (
    input  wire clk,       // System clock (for registered output)
    input  wire rst_n,     // Active-low synchronous reset
    input  wire bl,        // Bit line  (discharged slightly by cell on read)
    input  wire blb,       // Bit line bar
    input  wire se,        // Sense enable — pulsed after WL assert
    output reg  data_out   // Captured read data
);

    // Registered capture: avoids transparent-latch inference.
    // When SE=1 on rising clock edge, the differential is sampled.
    // BL>BLB => '1'; BLB>BL => '0'. Both equal => hold last (X avoidance).
    always @(posedge clk) begin
        if (!rst_n) begin
            data_out <= 1'b0;
        end else if (se) begin
            casez ({bl, blb})
                2'b10:   data_out <= 1'b1;
                2'b01:   data_out <= 1'b0;
                default: data_out <= data_out; // hold — precharge incomplete
            endcase
        end
    end

endmodule
`default_nettype wire
