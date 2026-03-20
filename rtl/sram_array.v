// =============================================================================
// SRAM Array — (2^ADDR_WIDTH) rows × DATA_WIDTH columns of 6T bitcells
// Description : Instantiates the full bitcell matrix, row decoder, column
//               mux, sense amplifiers, write drivers, and precharge circuit.
//               A 4-phase control FSM sequences: IDLE -> PRECHARGE -> ACCESS
//               -> SENSE/WRITE -> IDLE, matching real SRAM timing.
//
// FSM Phases  :
//   IDLE      : All control signals deasserted. Outputs held.
//   PRECHARGE : PCH=1, BL/BLB driven to VDD. WL deasserted.
//   ACCESS    : PCH=0, decoder_en=1. WL for addressed row asserted.
//   SENSE     : (read)  SE pulsed — sense amp captures BL/BLB differential.
//   WRITE     : (write) wr_cell_en=1 — write driver overpowers cell.
//
// Bug fixes   :
//   1. Eliminated inout tristates on BL/BLB — replaced with explicit signal
//      arbitration (precharge / write-driver / cell-read paths separated).
//   2. FSM uses enumerated state type (not integer variable) for synthesis.
//   3. Precharge and write driver outputs ORed onto bitlines with proper
//      enable gating to avoid bus contention.
//   4. Read-data collection uses wired-OR with cell drive enables.
//   5. data_out registered after sense enable to avoid glitching.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_array #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 8,
    parameter NUM_ROWS   = (1 << ADDR_WIDTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,     // Active-low synchronous reset
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  [DATA_WIDTH-1:0] data_out,
    input  wire                  rd_en,
    input  wire                  wr_en
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    wire [NUM_ROWS-1:0]   word_lines;
    wire [DATA_WIDTH-1:0] bl_cell  [0:NUM_ROWS-1];  // Read output from each row
    wire [DATA_WIDTH-1:0] blb_cell [0:NUM_ROWS-1];
    wire [DATA_WIDTH-1:0] bl_bus;                   // OR-reduced bitline bus
    wire [DATA_WIDTH-1:0] blb_bus;
    wire [DATA_WIDTH-1:0] pch_bl, pch_blb;
    wire [DATA_WIDTH-1:0] wr_bl,  wr_blb;
    wire [DATA_WIDTH-1:0] bl_muxed, blb_muxed;
    wire [DATA_WIDTH-1:0] sa_out;

    reg decoder_en;
    reg sense_en;
    reg col_sel;
    reg pch;
    reg wr_cell_en;

    // -------------------------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_PRECHARGE = 3'd1,
        S_ACCESS    = 3'd2,
        S_SENSE     = 3'd3,
        S_WRITE     = 3'd4;

    reg [2:0] state, next_state;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = S_IDLE;
        case (state)
            S_IDLE      : next_state = rd_en ? S_PRECHARGE :
                                       wr_en ? S_WRITE     : S_IDLE;
            S_PRECHARGE : next_state = S_ACCESS;
            S_ACCESS    : next_state = S_SENSE;
            S_SENSE     : next_state = S_IDLE;
            S_WRITE     : next_state = S_IDLE;
            default     : next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Output (Moore) control signals
    // -------------------------------------------------------------------------
    always @(*) begin
        // Defaults
        decoder_en  = 1'b0;
        sense_en    = 1'b0;
        col_sel     = 1'b0;
        wr_cell_en  = 1'b0;
        pch         = 1'b0;

        case (state)
            S_PRECHARGE : begin pch = 1'b1; col_sel = 1'b1; end
            S_ACCESS    : begin decoder_en = 1'b1; col_sel = 1'b1; end
            S_SENSE     : begin decoder_en = 1'b1; sense_en = 1'b1; col_sel = 1'b1; end
            S_WRITE     : begin decoder_en = 1'b1; wr_cell_en = 1'b1; col_sel = 1'b1; end
            default     : ; // all deasserted
        endcase
    end

    // -------------------------------------------------------------------------
    // Sub-module instantiations
    // -------------------------------------------------------------------------

    // Row decoder
    row_decoder #(.ADDR_WIDTH(ADDR_WIDTH), .NUM_ROWS(NUM_ROWS)) u_dec (
        .address    (address),
        .en         (decoder_en),
        .word_lines (word_lines)
    );

    // Precharge drivers
    precharge #(.DATA_WIDTH(DATA_WIDTH)) u_pch (
        .pch     (pch),
        .pch_bl  (pch_bl),
        .pch_blb (pch_blb)
    );

    // Write drivers
    write_driver #(.DATA_WIDTH(DATA_WIDTH)) u_wd (
        .wr_en   (wr_cell_en),
        .data_in (data_in),
        .wr_bl   (wr_bl),
        .wr_blb  (wr_blb)
    );

    // Bitcell array — generate NUM_ROWS rows × DATA_WIDTH columns
    genvar row, col;
    generate
        for (row = 0; row < NUM_ROWS; row = row + 1) begin : gen_rows
            for (col = 0; col < DATA_WIDTH; col = col + 1) begin : gen_cols
                sram_cell_6t u_cell (
                    .wl      (word_lines[row]),
                    .wr_en   (wr_cell_en),
                    .bl_in   (wr_bl[col]),
                    .blb_in  (wr_blb[col]),
                    .bl_out  (bl_cell[row][col]),
                    .blb_out (blb_cell[row][col])
                );
            end
        end
    endgenerate

    // OR-reduce per column across all rows.
    // Only the addressed row drives a valid '0'/'1'; others drive 'Z' (ignored
    // in synthesis — wired-OR on real metal via shared bitline).
    // For synthesis we select the active row using a MUX on word_lines.
    genvar c;
    generate
        for (c = 0; c < DATA_WIDTH; c = c + 1) begin : gen_blbus
            wire [NUM_ROWS-1:0] bl_col_bits;
            wire [NUM_ROWS-1:0] blb_col_bits;
            genvar r;
            for (r = 0; r < NUM_ROWS; r = r + 1) begin : gen_bits
                assign bl_col_bits[r]  = bl_cell[r][c]  & word_lines[r] & decoder_en;
                assign blb_col_bits[r] = blb_cell[r][c] & word_lines[r] & decoder_en;
            end
            assign bl_bus[c]  = |bl_col_bits;
            assign blb_bus[c] = |blb_col_bits;
        end
    endgenerate

    // Bitline arbitration:
    //   Precharge phase  : pch_bl/blb override cell
    //   Access/Sense     : cell drives bl_bus/blb_bus
    //   Write            : wr_bl/blb override cell
    wire [DATA_WIDTH-1:0] bl_driven, blb_driven;
    assign bl_driven  = pch ? pch_bl  : wr_cell_en ? wr_bl  : bl_bus;
    assign blb_driven = pch ? pch_blb : wr_cell_en ? wr_blb : blb_bus;

    // Column mux
    column_mux #(.DATA_WIDTH(DATA_WIDTH)) u_cmux (
        .bl_array  (bl_driven),
        .blb_array (blb_driven),
        .col_sel   (col_sel),
        .bl_out    (bl_muxed),
        .blb_out   (blb_muxed)
    );

    // Sense amplifiers — one per column
    generate
        for (c = 0; c < DATA_WIDTH; c = c + 1) begin : gen_sa
            sense_amplifier u_sa (
                .clk      (clk),
                .rst_n    (rst_n),
                .bl       (bl_muxed[c]),
                .blb      (blb_muxed[c]),
                .se       (sense_en),
                .data_out (sa_out[c])
            );
        end
    endgenerate

    // Register data_out from sense amplifiers on sense phase
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_out <= {DATA_WIDTH{1'b0}};
        else if (sense_en)
            data_out <= sa_out;
    end

endmodule
`default_nettype wire
