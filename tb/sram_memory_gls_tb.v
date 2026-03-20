// =============================================================================
// Gate-Level Simulation Wrapper — 6T SRAM Memory
// Description : Instantiates the post-synthesis netlist for GLS. Supports
//               SDF back-annotation for timing-accurate simulation.
//               Includes a glitch checker on data_out to flag metastability.
//
// Usage (Icarus):
//   iverilog -DFUNCTIONAL -DUNIT_DELAY='#1' \
//     $PDK_ROOT/sky130A/.../sky130_fd_sc_hd.v \
//     yosys_out/sram_memory_mapped.v \
//     tb/sram_memory_gls_tb.v
//   vvp sram_gls_sim
//
// Usage (VCS with SDF):
//   vcs -sdf max:dut:sram_memory.sdf ...
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_memory_gls_tb;

    localparam ADDR_WIDTH   = 4;
    localparam DATA_WIDTH   = 8;
    localparam CLK_PERIOD   = 10;
    localparam READ_LATENCY = 4;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg                   clk     = 0;
    reg                   rst_n   = 0;
    reg                   cs      = 0;
    reg                   rw      = 0;
    reg  [ADDR_WIDTH-1:0] address = 0;
    reg  [DATA_WIDTH-1:0] data_in = 0;
    wire [DATA_WIDTH-1:0] data_out;

    // -------------------------------------------------------------------------
    // DUT — post-synthesis gate-level netlist
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
    // SDF back-annotation (uncomment for timing sim)
    // -------------------------------------------------------------------------
    // `ifdef SDF_ANNOTATE
    // initial $sdf_annotate("sram_memory.sdf", dut);
    // `endif

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // X-propagation checker on data_out
    // Flags any X/Z output during the valid output window.
    // -------------------------------------------------------------------------
    reg check_output;
    always @(posedge clk) begin
        if (check_output) begin
            if (^data_out === 1'bx) begin
                $error("[GLS] X-propagation detected on data_out at time %0t", $time);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Glitch detector — counts output transitions in a single cycle
    // -------------------------------------------------------------------------
    integer glitch_count;
    reg [DATA_WIDTH-1:0] data_prev;

    always @(data_out) begin
        if (check_output && ($time > 0)) begin
            glitch_count = glitch_count + 1;
            if (glitch_count > 1)
                $warning("[GLS] Glitch on data_out: transition #%0d at time %0t",
                         glitch_count, $time);
            data_prev = data_out;
        end
    end

    always @(posedge clk) glitch_count = 0;  // Reset per cycle

    // -------------------------------------------------------------------------
    // Reuse functional test patterns from RTL TB
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] test_data [0:15];
    reg [DATA_WIDTH-1:0] rd_data;
    integer i, fail_count;

    initial begin
        test_data[0]  = 8'b1010_1010;
        test_data[1]  = 8'b1100_1100;
        test_data[2]  = 8'b1111_0000;
        test_data[3]  = 8'b0000_1111;
        test_data[4]  = 8'b1111_1111;
        test_data[5]  = 8'b0000_0000;
        test_data[6]  = 8'b1000_0001;
        test_data[7]  = 8'b0111_1110;
        test_data[8]  = 8'b0011_0011;
        test_data[9]  = 8'b1100_1100;
        test_data[10] = 8'b0101_0101;
        test_data[11] = 8'b1010_1010;
        test_data[12] = 8'b1110_0111;
        test_data[13] = 8'b0001_1000;
        test_data[14] = 8'b1001_1001;
        test_data[15] = 8'b0110_0110;
    end

    task write_word;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] wdata;
        begin
            @(negedge clk);
            cs = 1; rw = 0; address = addr; data_in = wdata;
            @(posedge clk); #1;
            cs = 0;
        end
    endtask

    task read_word;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] rdata;
        begin
            @(negedge clk);
            cs = 1; rw = 1; address = addr;
            check_output = 0;
            repeat (READ_LATENCY) @(posedge clk);
            #1;
            check_output = 1;
            rdata = data_out;
            @(posedge clk);
            check_output = 0;
            cs = 0;
        end
    endtask

    initial begin
        fail_count   = 0;
        check_output = 0;
        glitch_count = 0;

        $dumpfile("gls_sim.vcd");
        $dumpvars(0, sram_memory_gls_tb);

        $display("=== GLS: Gate-Level Simulation ===");

        rst_n = 0; repeat (5) @(posedge clk);
        rst_n = 1; repeat (2) @(posedge clk);

        // Write phase
        $display("--- Write phase ---");
        for (i = 0; i < 16; i = i + 1)
            write_word(i[3:0], test_data[i]);
        repeat (2) @(posedge clk);

        // Read-back phase
        $display("--- Read & verify phase ---");
        for (i = 0; i < 16; i = i + 1) begin
            read_word(i[3:0], rd_data);
            if (rd_data !== test_data[i]) begin
                $error("[GLS] FAIL addr=%0d expected=%08b got=%08b", i, test_data[i], rd_data);
                fail_count = fail_count + 1;
            end else begin
                $display("[GLS] PASS addr=%0d data=%08b", i, rd_data);
            end
        end

        // Summary
        if (fail_count == 0) $display("[GLS] ALL TESTS PASSED");
        else                 $display("[GLS] %0d FAILURES", fail_count);

        #50; $finish;
    end

    initial begin
        #20_000;
        $fatal(1, "[GLS] TIMEOUT");
    end

endmodule
`default_nettype wire
