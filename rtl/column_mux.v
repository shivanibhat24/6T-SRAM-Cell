// =============================================================================
// Column Mux — Bitline selection
// Description : Routes selected bitline pairs to the sense amplifier bank.
//               In a wider array (e.g., 64-bit with 8:1 mux), col_sel[2:0]
//               would choose 8 columns out of 64. Here: passthrough (1:1).
// Bug fixes   : Removed 'Z' assignment — replaced with registered gating.
//               Synthesis cannot map 'Z' to FPGA fabric; use enable instead.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module column_mux #(
    parameter DATA_WIDTH = 8
)(
    input  wire [DATA_WIDTH-1:0] bl_array,   // BL bus from cell array
    input  wire [DATA_WIDTH-1:0] blb_array,  // BLB bus from cell array
    input  wire                  col_sel,    // Column select (1 = pass through)
    output wire [DATA_WIDTH-1:0] bl_out,
    output wire [DATA_WIDTH-1:0] blb_out
);

    // Gate column output — tools infer correct mux primitive
    assign bl_out  = col_sel ? bl_array  : {DATA_WIDTH{1'b0}};
    assign blb_out = col_sel ? blb_array : {DATA_WIDTH{1'b0}};

endmodule
`default_nettype wire
