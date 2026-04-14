`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_async_word_fifo_xpm.md。

// Keep tb_async_word_fifo_xpm.md in sync
module tb_async_word_fifo_xpm;

    // 测试目标：
    // 1. 覆盖异步 FIFO 的基本读写、近满和溢出/下溢行为
    // 2. 检查双时钟域下的数据顺序与计数器状态

    localparam int DATA_W             = 32;
    localparam int DEPTH              = 16;
    localparam int ALMOST_FULL_MARGIN = 4;
    localparam int COUNT_W            = $clog2(DEPTH+1);
    localparam int PROG_FULL_THRESH_MIN = 7;
    localparam int PROG_FULL_THRESH_MAX = DEPTH - 5;
    localparam int PROG_FULL_THRESH_REQ = DEPTH - ALMOST_FULL_MARGIN;
    localparam int PROG_FULL_THRESH     =
        (PROG_FULL_THRESH_REQ < PROG_FULL_THRESH_MIN) ? PROG_FULL_THRESH_MIN :
        (PROG_FULL_THRESH_REQ > PROG_FULL_THRESH_MAX) ? PROG_FULL_THRESH_MAX :
        PROG_FULL_THRESH_REQ;

    logic wr_clk;
    logic rd_clk;
    logic sys_rst;

    logic              wr_en;
    logic [DATA_W-1:0] wr_data;
    logic              full;
    logic              almost_full;
    logic [COUNT_W-1:0] wr_count;
    logic              overflow;

    logic              rd_en;
    logic [DATA_W-1:0] rd_data;
    logic              empty;
    logic [COUNT_W-1:0] rd_count;
    logic              underflow;

    logic [DATA_W-1:0] expected_mem [0:DEPTH-1];
    int                expected_words;
    int                read_words;
    logic              accepted;

    async_word_fifo #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH),
        .ALMOST_FULL_MARGIN(ALMOST_FULL_MARGIN)
    ) dut (
        .wr_clk(wr_clk),
        .sys_rst(sys_rst),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .almost_full(almost_full),
        .wr_count(wr_count),
        .overflow(overflow),
        .rd_clk(rd_clk),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty),
        .rd_count(rd_count),
        .underflow(underflow)
    );

    initial wr_clk = 1'b0;
    always #2.5 wr_clk = ~wr_clk;

    initial rd_clk = 1'b0;
    always #5 rd_clk = ~rd_clk;

    task automatic apply_reset;
        begin
            wr_en          = 1'b0;
            rd_en          = 1'b0;
            wr_data        = '0;
            expected_words = 0;
            read_words     = 0;
            sys_rst        = 1'b1;
            repeat (6) @(posedge wr_clk);
            repeat (4) @(posedge rd_clk);
            @(posedge wr_clk);
            sys_rst = 1'b0;
            // The FIFO interface does not expose internal reset-busy signals.
            // Give both clock domains enough cycles to settle after reset release.
            repeat (6) @(posedge wr_clk);
            repeat (6) @(posedge rd_clk);
        end
    endtask

    task automatic write_word(
        input  logic [DATA_W-1:0] value,
        output logic              accepted
    );
        begin
            accepted = 1'b0;
            @(posedge wr_clk);
            if (full) begin
                return;
            end
            wr_en   <= 1'b1;
            wr_data <= value;
            expected_mem[expected_words] = value;
            expected_words = expected_words + 1;
            accepted = 1'b1;

            @(posedge wr_clk);
            wr_en <= 1'b0;
        end
    endtask

    task automatic read_and_check;
        logic [DATA_W-1:0] observed;
        begin
            wait (!empty);
            @(posedge rd_clk);
            observed = rd_data;
            rd_en    <= 1'b1;
            @(posedge rd_clk);
            rd_en <= 1'b0;

            $display("[%0t] read idx=%0d observed=%h empty=%0b rd_count=%0d wr_count=%0d",
                     $time, read_words, observed, empty, rd_count, wr_count);

            if (observed !== expected_mem[read_words]) begin
                $fatal(1, "Read mismatch idx=%0d got=%h exp=%h", read_words, observed, expected_mem[read_words]);
            end
            read_words = read_words + 1;
        end
    endtask

    task automatic expect_underflow;
        int wait_cycles;
        begin
            wait (empty);
            @(posedge rd_clk);
            rd_en <= 1'b1;
            @(posedge rd_clk);
            rd_en <= 1'b0;

            wait_cycles = 0;
            while (!underflow && (wait_cycles < 8)) begin
                @(posedge rd_clk);
                wait_cycles = wait_cycles + 1;
            end

            if (!underflow) begin
                $fatal(1, "Expected underflow pulse after reading empty FIFO");
            end
        end
    endtask

    task automatic fill_until_full_and_overflow;
        int safety;
        int attempts;
        logic accepted;
        begin
            safety = 0;
            attempts = 0;
            while (!full && (safety < DEPTH + 4) && (attempts < DEPTH + 16)) begin
                write_word(32'hA500_0000 + safety, accepted);
                attempts = attempts + 1;
                if (accepted) begin
                    safety = safety + 1;
                end
            end

            if (!full) begin
                $fatal(1, "FIFO never asserted full during fill test accepted=%0d attempts=%0d wr_count=%0d rd_count=%0d empty=%0b",
                    safety, attempts, wr_count, rd_count, empty);
            end

            @(posedge wr_clk);
            wr_en   <= 1'b1;
            wr_data <= 32'hDEAD_BEEF;
            @(posedge wr_clk);
            wr_en <= 1'b0;
            @(posedge wr_clk);
            if (!overflow) begin
                $fatal(1, "Expected overflow pulse after writing while full");
            end
        end
    endtask

    task automatic fill_until_almost_full;
        int safety;
        int attempts;
        logic accepted;
        begin
            safety = 0;
            attempts = 0;
            while (!almost_full && (safety < DEPTH + 4) && (attempts < DEPTH + 16)) begin
                write_word(32'h0000_1000 + safety, accepted);
                attempts = attempts + 1;
                if (accepted) begin
                    safety = safety + 1;
                end
            end

            if (!almost_full) begin
                $fatal(1, "FIFO never asserted almost_full/prog_full accepted=%0d attempts=%0d wr_count=%0d rd_count=%0d empty=%0b",
                    safety, attempts, wr_count, rd_count, empty);
            end

            if (expected_words < PROG_FULL_THRESH) begin
                $fatal(1, "almost_full asserted too early: words=%0d threshold=%0d", expected_words, PROG_FULL_THRESH);
            end
        end
    endtask

    initial begin
        #10us;
        $fatal(1, "tb_async_word_fifo_xpm timeout");
    end

    initial begin
        $display("Stage: basic reset/read/write");
        apply_reset();

        if (!empty) $fatal(1, "FIFO should be empty after reset");
        if (full)   $fatal(1, "FIFO should not be full after reset");

        write_word(32'h1122_3344, accepted);
        if (!accepted) $fatal(1, "First write was not accepted after reset");
        write_word(32'h5566_7788, accepted);
        if (!accepted) $fatal(1, "Second write was not accepted after reset");
        write_word(32'h99AA_BBCC, accepted);
        if (!accepted) $fatal(1, "Third write was not accepted after reset");

        read_and_check();
        read_and_check();
        read_and_check();

        repeat (4) @(posedge rd_clk);
        $display("[%0t] after drain empty=%0b rd_count=%0d wr_count=%0d",
                 $time, empty, rd_count, wr_count);
        if (!empty) begin
            $fatal(1, "FIFO should return to empty after draining");
        end

        $display("Stage: underflow");
        expect_underflow();

        $display("Stage: almost_full");
        apply_reset();
        fill_until_almost_full();

        $display("Stage: full/overflow");
        apply_reset();
        fill_until_full_and_overflow();

        $display("tb_async_word_fifo_xpm completed");
        $finish;
    end

endmodule
