// =============================================================================
// Corner Sweep Testbench — 6T SRAM Memory
// Description : Runs write-read patterns under three timing scenarios that
//               stress the FSM pipeline and back-to-back access patterns:
//
//   Corner A — Normal:          single write then read, full idle gap
//   Corner B — Back-to-back:    consecutive writes to different addresses,
//                               then consecutive reads (no idle between)
//   Corner C — Interleaved:     alternating single writes and reads
//   Corner D — Same-address:    rapid overwrite of one address (5× in a row)
//   Corner E — All-ones/zeros:  flood with 0xFF then 0x00 (hold SNM stress)
//   Corner F — Checkerboard:    alternating addresses with inverted data
//
// This TB does not model process/voltage/temperature (PVT) corners — those
// are handled by SDF back-annotation in GLS. This file stress-tests FSM
// sequencing and data integrity under functional access patterns.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_corner_tb;

    localparam ADDR_WIDTH   = 4;
    localparam DATA_WIDTH   = 8;
    localparam CLK_PERIOD   = 10;
    localparam READ_LATENCY = 4;

    reg                   clk     = 0;
    reg                   rst_n   = 0;
    reg                   cs      = 0;
    reg                   rw      = 0;
    reg  [ADDR_WIDTH-1:0] address = 0;
    reg  [DATA_WIDTH-1:0] data_in = 0;
    wire [DATA_WIDTH-1:0] data_out;

    integer fail_count;
    integer total_tests;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    sram_memory #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .cs(cs), .rw(rw),
        .address(address), .data_in(data_in), .data_out(data_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task do_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] wdata;
        begin
            @(negedge clk);
            cs = 1; rw = 0; address = addr; data_in = wdata;
            @(posedge clk); #1;
            cs = 0;
        end
    endtask

    task do_read_check;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] expected;
        input [127:0] label;   // corner label string (truncated for display)
        reg [DATA_WIDTH-1:0] got;
        begin
            @(negedge clk);
            cs = 1; rw = 1; address = addr;
            repeat (READ_LATENCY) @(posedge clk);
            #1;
            got = data_out;
            cs  = 0;
            total_tests = total_tests + 1;
            if (got !== expected) begin
                $error("[%s] FAIL addr=%0d exp=%08b got=%08b", label, addr, expected, got);
                fail_count = fail_count + 1;
            end else begin
                $display("[%s] PASS addr=%0d data=%08b", label, addr, got);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Reset helper
    // -------------------------------------------------------------------------
    task do_reset;
        begin
            rst_n = 0; cs = 0;
            repeat (5) @(posedge clk);
            rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    integer i;

    initial begin
        fail_count  = 0;
        total_tests = 0;

        $dumpfile("corner_sim.vcd");
        $dumpvars(0, sram_corner_tb);

        // ===================================================================
        // CORNER A — Normal single-access pattern
        // ===================================================================
        $display("\n=== CORNER A: Normal single write-read ===");
        do_reset;
        do_write(4'h3, 8'hA5);
        repeat (2) @(posedge clk);
        do_read_check(4'h3, 8'hA5, "CORNER_A");

        // ===================================================================
        // CORNER B — Back-to-back writes then back-to-back reads
        // ===================================================================
        $display("\n=== CORNER B: Back-to-back writes then reads ===");
        do_reset;
        for (i = 0; i < 16; i = i + 1)
            do_write(i[3:0], 8'hF0 ^ i[7:0]);  // Unique pattern per address

        for (i = 0; i < 16; i = i + 1)
            do_read_check(i[3:0], 8'hF0 ^ i[7:0], "CORNER_B");

        // ===================================================================
        // CORNER C — Interleaved write-read (no pipeline flush between)
        // ===================================================================
        $display("\n=== CORNER C: Interleaved write-read ===");
        do_reset;
        for (i = 0; i < 16; i = i + 1) begin
            do_write(i[3:0], i[7:0]);
            do_read_check(i[3:0], i[7:0], "CORNER_C");
        end

        // ===================================================================
        // CORNER D — Rapid overwrite of same address
        // ===================================================================
        $display("\n=== CORNER D: Rapid overwrite same address (5x) ===");
        do_reset;
        do_write(4'h7, 8'hAA);
        do_write(4'h7, 8'h55);
        do_write(4'h7, 8'hFF);
        do_write(4'h7, 8'h00);
        do_write(4'h7, 8'hC3);
        do_read_check(4'h7, 8'hC3, "CORNER_D");

        // ===================================================================
        // CORNER E — All-ones then all-zeros (hold SNM stress)
        // ===================================================================
        $display("\n=== CORNER E: All-ones then all-zeros hold stress ===");
        do_reset;
        for (i = 0; i < 16; i = i + 1)
            do_write(i[3:0], 8'hFF);
        repeat (20) @(posedge clk);  // Hold for 20 cycles
        for (i = 0; i < 16; i = i + 1)
            do_read_check(i[3:0], 8'hFF, "CORNER_E_hold1");

        for (i = 0; i < 16; i = i + 1)
            do_write(i[3:0], 8'h00);
        repeat (20) @(posedge clk);
        for (i = 0; i < 16; i = i + 1)
            do_read_check(i[3:0], 8'h00, "CORNER_E_hold0");

        // ===================================================================
        // CORNER F — Checkerboard: even addr=0xAA, odd addr=0x55
        // ===================================================================
        $display("\n=== CORNER F: Checkerboard pattern ===");
        do_reset;
        for (i = 0; i < 16; i = i + 1)
            do_write(i[3:0], (i[0] == 0) ? 8'hAA : 8'h55);
        for (i = 0; i < 16; i = i + 1)
            do_read_check(i[3:0], (i[0] == 0) ? 8'hAA : 8'h55, "CORNER_F");

        // ===================================================================
        // CORNER G — Walking 1s across all addresses
        // ===================================================================
        $display("\n=== CORNER G: Walking 1 pattern ===");
        do_reset;
        for (i = 0; i < 8; i = i + 1)
            do_write(i[3:0], 8'b1 << i);
        for (i = 0; i < 8; i = i + 1)
            do_read_check(i[3:0], 8'b1 << i, "CORNER_G");

        // ===================================================================
        // Summary
        // ===================================================================
        $display("\n===================================================");
        $display("CORNER SWEEP COMPLETE");
        $display("Total tests : %0d", total_tests);
        $display("Failures    : %0d", fail_count);
        if (fail_count == 0) $display("RESULT: ALL TESTS PASSED");
        else                 $display("RESULT: %0d FAILURES", fail_count);
        $display("===================================================");

        #50; $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "TIMEOUT: corner sweep exceeded 100 us");
    end

endmodule
`default_nettype wire
