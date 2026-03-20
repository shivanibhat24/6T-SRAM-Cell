// =============================================================================
// SRAM Memory — Top-level with chip-select and R/W decode
// Description : Wraps sram_array with CS gating. When CS=0, no read or write
//               operation is initiated and data_out is held at zero.
//               rw=1 => Read, rw=0 => Write (industry-standard convention).
// Bug fixes   : data_out tristated to 'Z' (open-drain) when cs=0 to allow
//               correct bus sharing in multi-chip configurations, or held to
//               0 if a pull-down is preferred (set OUTPUT_TRISTATE=0).
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_memory #(
    parameter ADDR_WIDTH      = 4,
    parameter DATA_WIDTH      = 8,
    parameter OUTPUT_TRISTATE = 0   // 1: float data_out when CS=0
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  cs,      // Chip select (active-high)
    input  wire                  rw,      // 1 = Read, 0 = Write
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire [DATA_WIDTH-1:0] data_in,
    output wire [DATA_WIDTH-1:0] data_out
);

    wire rd_en = cs &  rw;
    wire wr_en = cs & ~rw;

    wire [DATA_WIDTH-1:0] core_dout;

    sram_array #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .address  (address),
        .data_in  (data_in),
        .data_out (core_dout),
        .rd_en    (rd_en),
        .wr_en    (wr_en)
    );

    // Output enable: drive bus only when CS active and in read mode
    generate
        if (OUTPUT_TRISTATE) begin : gen_tristate
            assign data_out = (cs & rw) ? core_dout : {DATA_WIDTH{1'bz}};
        end else begin : gen_zero
            assign data_out = cs ? core_dout : {DATA_WIDTH{1'b0}};
        end
    endgenerate

endmodule
`default_nettype wire
