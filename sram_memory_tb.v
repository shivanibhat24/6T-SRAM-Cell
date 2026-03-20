// =============================================================================
// SRAM Testbench — Self-checking with $error / $fatal
// Description : Tests all 16 addresses: write phase, read-back, overwrite,
//               and chip-select deassert. Accounts for 3-cycle read latency
//               (PRECHARGE -> ACCESS -> SENSE) introduced by the FSM.
// Simulator   : Vivado XSim / ModelSim / Icarus Verilog (SystemVerilog assert)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_memory_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam ADDR_WIDTH   = 4;
    localparam DATA_WIDTH   = 8;
    localparam CLK_PERIOD   = 10;  // 10 ns => 100 MHz
    localparam READ_LATENCY = 4;   // Cycles: PRECHARGE(1) + ACCESS(1) + SENSE(1) + output reg(1)

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg                   clk     = 1'b0;
    reg                   rst_n   = 1'b0;
    reg                   cs      = 1'b0;
    reg                   rw      = 1'b0;
    reg  [ADDR_WIDTH-1:0] address = 4'b0;
    reg  [DATA_WIDTH-1:0] data_in = 8'b0;
    wire [DATA_WIDTH-1:0] data_out;

    // -------------------------------------------------------------------------
    // Test data: 16 unique patterns covering common fault modes
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] test_data [0:15];
    integer i;
    integer fail_count;

    initial begin
        test_data[0]  = 8'b1010_1010;  // Alternating bits
        test_data[1]  = 8'b1100_1100;  // Alternating pairs
        test_data[2]  = 8'b1111_0000;  // Half-half
        test_data[3]  = 8'b0000_1111;  // Inverted half-half
        test_data[4]  = 8'b1111_1111;  // All ones (hold stability)
        test_data[5]  = 8'b0000_0000;  // All zeros (hold stability)
        test_data[6]  = 8'b1000_0001;  // Boundary bits only
        test_data[7]  = 8'b0111_1110;  // Inverse boundary
        test_data[8]  = 8'b0011_0011;  // Nibble alternating
        test_data[9]  = 8'b1100_1100;  // Repeated
        test_data[10] = 8'b0101_0101;  // Inverted alternating
        test_data[11] = 8'b1010_1010;  // Repeated
        test_data[12] = 8'b1110_0111;  // Mixed
        test_data[13] = 8'b0001_1000;  // Centre bits
        test_data[14] = 8'b1001_1001;  // Random-like
        test_data[15] = 8'b0110_0110;  // Random-like inverse
    end

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    sram_memory #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .cs       (cs),
        .rw       (rw),
        .address  (address),
        .data_in  (data_in),
        .data_out (data_out)
    );

    // -------------------------------------------------------------------------
    // 100 MHz clock
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task write_word;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] wdata;
        begin
            @(negedge clk);
            cs      = 1'b1;
            rw      = 1'b0;
            address = addr;
            data_in = wdata;
            @(posedge clk); #1;  // One write cycle
            cs = 1'b0;
        end
    endtask

    task read_word;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] rdata;
        integer cyc;
        begin
            @(negedge clk);
            cs      = 1'b1;
            rw      = 1'b1;
            address = addr;
            // Wait READ_LATENCY cycles for FSM pipeline
            repeat (READ_LATENCY) @(posedge clk);
            #1;
            rdata = data_out;
            cs = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] rd_data;

    initial begin
        fail_count = 0;

        // Waveform dump (works in XSim, ModelSim, Icarus)
        $dumpfile("sram_sim.vcd");
        $dumpvars(0, sram_memory_tb);

        // ---------------------------------------------------------------
        // PHASE 0: Reset
        // ---------------------------------------------------------------
        $display("=== PHASE 0: Reset ===");
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------
        // PHASE 1: Write all 16 addresses
        // ---------------------------------------------------------------
        $display("=== PHASE 1: Write 16 addresses ===");
        for (i = 0; i < 16; i = i + 1) begin
            write_word(i[ADDR_WIDTH-1:0], test_data[i]);
            $display("  WRITE addr=%0d data=%08b", i, test_data[i]);
        end
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------
        // PHASE 2: Read back and verify all 16 addresses
        // ---------------------------------------------------------------
        $display("=== PHASE 2: Read & verify all 16 addresses ===");
        for (i = 0; i < 16; i = i + 1) begin
            read_word(i[ADDR_WIDTH-1:0], rd_data);
            if (rd_data !== test_data[i]) begin
                $error("FAIL addr=%0d: expected %08b, got %08b", i, test_data[i], rd_data);
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS addr=%0d data=%08b", i, rd_data);
            end
        end

        // ---------------------------------------------------------------
        // PHASE 3: Overwrite test — write inverted pattern, verify old gone
        // ---------------------------------------------------------------
        $display("=== PHASE 3: Overwrite test (addr 0) ===");
        write_word(4'h0, 8'b0101_0101);
        repeat (2) @(posedge clk);
        read_word(4'h0, rd_data);
        if (rd_data !== 8'b0101_0101) begin
            $error("FAIL overwrite: expected 01010101, got %08b", rd_data);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS overwrite addr=0 data=%08b", rd_data);
        end

        // ---------------------------------------------------------------
        // PHASE 4: Chip-select deassert — write attempt without CS
        // ---------------------------------------------------------------
        $display("=== PHASE 4: CS deassert test ===");
        // Attempt write to addr 5 with CS=0 (should be ignored)
        @(negedge clk);
        cs      = 1'b0;   // CS LOW — no operation
        rw      = 1'b0;
        address = 4'h5;
        data_in = 8'hFF;
        repeat (3) @(posedge clk);
        cs = 1'b0;

        // Read addr 5 — must still hold test_data[5]
        read_word(4'h5, rd_data);
        if (rd_data !== test_data[5]) begin
            $error("FAIL CS deassert: addr 5 should be %08b, got %08b", test_data[5], rd_data);
            fail_count = fail_count + 1;
        end else begin
            $display("  PASS CS deassert: addr 5 unchanged data=%08b", rd_data);
        end

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("=== SIMULATION COMPLETE ===");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED — see $error messages above", fail_count);

        repeat (5) @(posedge clk);
        $finish;
    end

    // Timeout watchdog — 10 µs max sim time
    initial begin
        #10_000;
        $fatal(1, "TIMEOUT: simulation exceeded 10 us");
    end

endmodule
`default_nettype wire
