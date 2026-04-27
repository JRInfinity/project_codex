`timescale 1ns/1ps

module tb_cache_stats_cdc_back_to_back;

    localparam int PAYLOAD_W = 64;

    logic src_clk;
    logic dst_clk;
    logic src_rst;
    logic dst_rst;
    logic stats_event;
    logic [PAYLOAD_W-1:0] event_payload;
    logic stats_ready_src;
    logic stats_valid_dst;
    logic [PAYLOAD_W-1:0] stats_payload_dst;
    logic pending_valid_reg;
    logic [PAYLOAD_W-1:0] pending_payload_reg;
    logic overrun_reg;
    int dst_count;
    int dst_base_count;

    initial src_clk = 1'b0;
    always #5 src_clk = ~src_clk;

    initial dst_clk = 1'b0;
    always #9 dst_clk = ~dst_clk;

    cache_stats_cdc #(
        .PAYLOAD_W(PAYLOAD_W)
    ) dut (
        .src_clk(src_clk),
        .src_rst(src_rst),
        .stats_valid_src(pending_valid_reg),
        .stats_payload_src(pending_payload_reg),
        .stats_ready_src(stats_ready_src),
        .dst_clk(dst_clk),
        .dst_rst(dst_rst),
        .stats_valid_dst(stats_valid_dst),
        .stats_payload_dst(stats_payload_dst)
    );

    always_ff @(posedge src_clk) begin
        if (src_rst) begin
            pending_valid_reg <= 1'b0;
            pending_payload_reg <= '0;
            overrun_reg <= 1'b0;
        end else begin
            if (stats_event) begin
                if (pending_valid_reg && !stats_ready_src) begin
                    overrun_reg <= 1'b1;
                end else begin
                    pending_valid_reg <= 1'b1;
                    pending_payload_reg <= event_payload;
                end
            end else if (pending_valid_reg && stats_ready_src) begin
                pending_valid_reg <= 1'b0;
            end
        end
    end

    always_ff @(posedge dst_clk) begin
        if (dst_rst) begin
            dst_count <= 0;
        end else if (stats_valid_dst) begin
            dst_count <= dst_count + 1;
        end
    end

    task automatic pulse_event(input logic [PAYLOAD_W-1:0] payload);
        begin
            @(posedge src_clk);
            event_payload <= payload;
            stats_event <= 1'b1;
            @(posedge src_clk);
            stats_event <= 1'b0;
        end
    endtask

    initial begin
        src_rst = 1'b1;
        dst_rst = 1'b1;
        stats_event = 1'b0;
        event_payload = '0;
        repeat (4) @(posedge src_clk);
        src_rst <= 1'b0;
        repeat (3) @(posedge dst_clk);
        dst_rst <= 1'b0;

        pulse_event(64'h1111);
        wait (!stats_ready_src);
        pulse_event(64'h2222);
        pulse_event(64'h3333);
        repeat (80) @(posedge dst_clk);
        if (overrun_reg) begin
            $fatal(1, "stats FIFO should absorb a short back-to-back burst");
        end
        if (dst_count != 3) begin
            $fatal(1, "expected three delivered snapshots for back-to-back events, got %0d", dst_count);
        end

        src_rst <= 1'b1;
        dst_rst <= 1'b1;
        repeat (4) @(posedge src_clk);
        src_rst <= 1'b0;
        repeat (4) @(posedge dst_clk);
        dst_rst <= 1'b0;
        dst_base_count = dst_count;

        pulse_event(64'h5555);
        wait (!stats_ready_src);
        pulse_event(64'h6666);
        pulse_event(64'h7777);
        repeat (80) @(posedge dst_clk);
        if (overrun_reg) begin
            $fatal(1, "internal stats FIFO should absorb this short burst without overrun");
        end
        if ((dst_count - dst_base_count) != 3) begin
            $fatal(1, "expected three delivered snapshots for queued burst, got delta=%0d total=%0d",
                   dst_count - dst_base_count, dst_count);
        end

        src_rst <= 1'b1;
        dst_rst <= 1'b1;
        repeat (4) @(posedge src_clk);
        src_rst <= 1'b0;
        repeat (3) @(posedge dst_clk);
        dst_rst <= 1'b0;
        repeat (4) @(posedge src_clk);

        pulse_event(64'h8888);
        wait (stats_ready_src);
        repeat (4) @(posedge src_clk);
        pulse_event(64'h9999);
        repeat (40) @(posedge dst_clk);
        if (overrun_reg) begin
            $fatal(1, "spaced stats events should not raise overrun");
        end
        if (dst_count != 2) begin
            $fatal(1, "expected two delivered snapshots for spaced events, got %0d", dst_count);
        end

        $display("CACHE_STATS_CDC_BACK_TO_BACK_PASS");
        $display("tb_cache_stats_cdc_back_to_back completed");
        $finish;
    end

endmodule
