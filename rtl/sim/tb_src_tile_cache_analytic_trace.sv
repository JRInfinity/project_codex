`timescale 1ns/1ps

module tb_src_tile_cache_analytic_trace;

    localparam int PIXEL_W   = 8;
    localparam int ADDR_W    = 32;
    localparam int MAX_SRC_W = 64;
    localparam int MAX_SRC_H = 32;
    localparam int MAX_DST_W = 64;
    localparam int MAX_DST_H = 32;
    localparam int COORD_W   = 48;
    localparam signed [COORD_W-1:0] ONE_Q16 = 48'sd65536;

    logic clk;
    logic sys_rst;
    logic start;
    logic geom_ready;
    logic busy;
    logic error;
    logic read_start;
    logic [ADDR_W-1:0] read_addr;
    logic [31:0] read_row_stride;
    logic [31:0] read_byte_count;
    logic [15:0] read_row_count;
    logic in_ready;
    logic sample_req_ready;
    logic [PIXEL_W-1:0] sample_p00;
    logic [PIXEL_W-1:0] sample_p01;
    logic [PIXEL_W-1:0] sample_p10;
    logic [PIXEL_W-1:0] sample_p11;
    logic sample_rsp_valid;
    logic [31:0] stat_analytic_candidates;
    logic [31:0] stat_analytic_duplicates;
    logic [31:0] stat_analytic_blocked;
    logic [31:0] stat_fifo_max_occupancy;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    src_tile_cache #(
        .PIXEL_W(PIXEL_W),
        .ADDR_W(ADDR_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .COORD_W(COORD_W),
        .TILE_W(16),
        .TILE_H(16),
        .TILE_NUM(4)
    ) dut (
        .clk(clk),
        .sys_rst(sys_rst),
        .start(start),
        .src_base_addr(32'h0000_0100),
        .src_stride(32'd64),
        .src_w(7'd16),
        .src_h(6'd8),
        .dst_w(7'd16),
        .dst_h(6'd8),
        .rot_sin_q16(32'sd0),
        .rot_cos_q16(32'sh0001_0000),
        .geom_ready(geom_ready),
        .geom_error(1'b0),
        .geom_step_x_x(ONE_Q16),
        .geom_step_y_x('0),
        .geom_step_x_y('0),
        .geom_step_y_y(ONE_Q16),
        .geom_row0_x('0),
        .geom_row0_y('0),
        .geom_src_x_last(6'd15),
        .geom_src_y_last(5'd7),
        .geom_src_x_max_q16(48'sd983040),
        .geom_src_y_max_q16(48'sd458752),
        .prefetch_enable(1'b1),
        .runtime_lead_pixels(16'd64),
        .runtime_merge_max_x_eff(8'd8),
        .runtime_merge_min_x(8'd1),
        .runtime_fifo_depth_eff(16'd32),
        .runtime_fifo_age_limit(16'd0),
        .runtime_prefetch_throttle_cycles(16'd0),
        .runtime_scheduler_policy(2'd0),
        .scan_dir_x(2'sd1),
        .scan_dir_y(2'sd0),
        .scan_dir_valid(1'b1),
        .busy(busy),
        .error(error),
        .read_start(read_start),
        .read_addr(read_addr),
        .read_row_stride(read_row_stride),
        .read_byte_count(read_byte_count),
        .read_row_count(read_row_count),
        .read_start_ready(1'b0),
        .read_busy(1'b0),
        .read_done(1'b0),
        .read_error(1'b0),
        .in_data('0),
        .in_valid(1'b0),
        .in_row_last(1'b0),
        .in_ready(in_ready),
        .sample_req_valid(1'b0),
        .sample_x0('0),
        .sample_y0('0),
        .sample_x1('0),
        .sample_y1('0),
        .sample_req_ready(sample_req_ready),
        .sample_p00(sample_p00),
        .sample_p01(sample_p01),
        .sample_p10(sample_p10),
        .sample_p11(sample_p11),
        .sample_rsp_valid(sample_rsp_valid),
        .stat_analytic_candidates(stat_analytic_candidates),
        .stat_analytic_duplicates(stat_analytic_duplicates),
        .stat_analytic_blocked(stat_analytic_blocked),
        .stat_fifo_max_occupancy(stat_fifo_max_occupancy)
    );

    logic seen_tile0;
    logic seen_tile1;
    int candidate_trace_count;
    int pre_geom_candidate_count;

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            seen_tile0 <= 1'b0;
            seen_tile1 <= 1'b0;
            candidate_trace_count <= 0;
            pre_geom_candidate_count <= 0;
        end else begin
            if (dut.planner_candidate_valid) begin
                candidate_trace_count <= candidate_trace_count + 1;
                if (!geom_ready) begin
                    pre_geom_candidate_count <= pre_geom_candidate_count + 1;
                end
                if (dut.planner_candidate_tile_y !== 0) begin
                    $fatal(1, "analytic planner produced unexpected y tile %0d", dut.planner_candidate_tile_y);
                end
                if (dut.planner_candidate_tile_x > 1) begin
                    $fatal(1, "analytic planner produced unexpected x tile %0d", dut.planner_candidate_tile_x);
                end
                if (dut.planner_candidate_tile_x == 0) begin
                    seen_tile0 <= 1'b1;
                end
                if (dut.planner_candidate_tile_x == 1) begin
                    seen_tile1 <= 1'b1;
                end
            end
        end
    end

    initial begin
        sys_rst = 1'b1;
        start = 1'b0;
        geom_ready = 1'b0;

        repeat (5) @(posedge clk);
        sys_rst <= 1'b0;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        repeat (12) @(posedge clk);
        if (pre_geom_candidate_count != 0 || stat_analytic_candidates != 0) begin
            $fatal(1, "analytic planner advanced before geom_ready: trace=%0d stat=%0d",
                   pre_geom_candidate_count, stat_analytic_candidates);
        end

        geom_ready <= 1'b1;
        repeat (300) @(posedge clk);

        if (error) begin
            $fatal(1, "src_tile_cache analytic trace raised error");
        end
        if (candidate_trace_count == 0 || stat_analytic_candidates == 0) begin
            $fatal(1, "analytic planner did not emit candidates");
        end
        if (!seen_tile0 || !seen_tile1) begin
            $fatal(1, "analytic planner did not cover expected identity row tiles: seen0=%0b seen1=%0b",
                   seen_tile0, seen_tile1);
        end
        if (stat_fifo_max_occupancy == 0) begin
            $fatal(1, "analytic FIFO never accepted a candidate");
        end

        $display("SRC_TILE_CACHE_ANALYTIC_TRACE_PASS candidates=%0d duplicates=%0d blocked=%0d fifo_max=%0d",
                 stat_analytic_candidates, stat_analytic_duplicates, stat_analytic_blocked,
                 stat_fifo_max_occupancy);
        $display("tb_src_tile_cache_analytic_trace completed");
        $finish;
    end

endmodule
