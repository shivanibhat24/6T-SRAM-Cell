// =============================================================================
// Row Decoder — Binary to one-hot
// Description : Decodes ADDR_WIDTH-bit address to (2^ADDR_WIDTH) word lines.
//               Exactly one WL asserted per cycle when en=1.
//               In silicon: NAND/NOR tree or standard-cell decoder.
// Bug fixes   : Pure combinational (no clock needed); synthesis-clean.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module row_decoder #(
    parameter ADDR_WIDTH = 4,
    parameter NUM_ROWS   = (1 << ADDR_WIDTH)  // 2^ADDR_WIDTH
)(
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire                  en,
    output reg  [NUM_ROWS-1:0]   word_lines
);

    integer i;

    always @(*) begin
        word_lines = {NUM_ROWS{1'b0}};
        if (en) begin
            // One-hot: only the addressed row is driven high
            for (i = 0; i < NUM_ROWS; i = i + 1) begin
                if (address == i[ADDR_WIDTH-1:0])
                    word_lines[i] = 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
