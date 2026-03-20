// =============================================================================
// Precharge Circuit — Per bitline-pair
// Description : Drives BL and BLB to VDD before a read access.
//               In silicon: two PMOS transistors gated by PCH_B (active-low).
//               Modelled here with active-high PCH for clarity.
// Bug fixes   : Removed inout/tri ambiguity. Precharge drives dedicated
//               pch_bl/pch_blb signals; arbitration done in top-level.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module precharge #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  pch,      // Precharge enable (active-high)
    output wire [DATA_WIDTH-1:0] pch_bl,   // Precharge drive to BL
    output wire [DATA_WIDTH-1:0] pch_blb   // Precharge drive to BLB
);

    // When PCH=1, both lines are driven to logic '1'.
    // When PCH=0, outputs are '0' — top-level mux decides which driver wins.
    assign pch_bl  = pch ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};
    assign pch_blb = pch ? {DATA_WIDTH{1'b1}} : {DATA_WIDTH{1'b0}};

endmodule
`default_nettype wire
