// =============================================================================
// Write Driver — Per bitline-pair
// Description : Strongly drives BL/BLB during a write to overpower cell
//               pull-up transistors (M1/M3). Requires cell pull-ratio < 1.
//               In silicon: NMOS pull-down pair gated by write data.
// Bug fixes   : Drives dedicated wr_bl/wr_blb signals (no inout ambiguity).
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module write_driver #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  wr_en,   // Write enable (active-high)
    input  wire [DATA_WIDTH-1:0] data_in, // Data word to write
    output wire [DATA_WIDTH-1:0] wr_bl,   // Driven BL values
    output wire [DATA_WIDTH-1:0] wr_blb   // Driven BLB values (complement)
);

    // BL driven to data; BLB driven to complement.
    // When wr_en=0, outputs are '0' — bus is released (arbitrated at top level).
    assign wr_bl  = wr_en ? data_in        : {DATA_WIDTH{1'b0}};
    assign wr_blb = wr_en ? ~data_in       : {DATA_WIDTH{1'b0}};

endmodule
`default_nettype wire
