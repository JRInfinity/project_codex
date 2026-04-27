`timescale 1ns/1ps
module tb_src_tile_cache_prefetch;

    localparam int PIXEL_W   = 8;
    localparam int ADDR_W    = 32;
    localparam int MAX_SRC_W = 128;
    localparam int MAX_SRC_H = 32;
    localparam int MAX_DST_W = 128;
    localparam int MAX_DST_H = 32;
    localparam int TILE_W    = 16;
    localparam int TILE_H    = 16;
    localparam int TILE_NUM  = 3;
    localparam int COORD_W   = 48;
    localparam int MEM_BYTES = 8192;
    localparam signed [COORD_W-1:0] GEOM_ONE_Q16 = 48'sd65536;

    logic clk;
    logic sys_rst;

    logic                           start;
    logic [ADDR_W-1:0]              src_base_addr;
    logic [ADDR_W-1:0]              src_stride;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h;
    logic [$clog2(MAX_DST_W+1)-1:0] dst_w;
    logic [$clog2(MAX_DST_H+1)-1:0] dst_h;
    logic                           busy;
    logic                           error;
    logic signed [1:0]              scan_dir_x;
    logic signed [1:0]              scan_dir_y;
    logic                           scan_dir_valid;

    logic               read_start;
    logic [ADDR_W-1:0]  read_addr;
    logic [31:0]        read_row_stride;
    logic [31:0]        read_byte_count;
    logic [15:0]        read_row_count;
    logic               read_start_ready;
    logic               read_busy;
    logic               read_done;
    logic               read_error;
    logic [PIXEL_W-1:0] in_data;
    logic               in_valid;
    logic               in_row_last;
    logic               in_ready;

    logic                                               sample_req_valid;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x0;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y0;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] sample_x1;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] sample_y1;
    logic                                               sample_req_ready;
    logic [PIXEL_W-1:0]                                 sample_p00;
    logic [PIXEL_W-1:0]                                 sample_p01;
    logic [PIXEL_W-1:0]                                 sample_p10;
    logic [PIXEL_W-1:0]                                 sample_p11;
    logic                                               sample_rsp_valid;
    logic [31:0]                                        stat_read_starts;
    logic [31:0]                                        stat_misses;
    logic [31:0]                                        stat_prefetch_starts;
    logic [31:0]                                        stat_prefetch_hits;
    logic signed [COORD_W-1:0]                          geom_src_x_max_q16;
    logic signed [COORD_W-1:0]                          geom_src_y_max_q16;

    assign geom_src_x_max_q16 = (src_w == '0) ? '0 : (($signed(COORD_W'({1'b0, src_w})) - 1) <<< 16);
    assign geom_src_y_max_q16 = (src_h == '0) ? '0 : (($signed(COORD_W'({1'b0, src_h})) - 1) <<< 16);

    byte src_mem [0:MEM_BYTES-1];

    logic [ADDR_W-1:0] rd_addr_reg;
    logic [31:0]       rd_row_stride_reg;
    logic [31:0]       rd_row_width_reg;
    int                rd_remaining_reg;
    int                rd_index_reg;
    int                read_start_count;
    int                max_read_byte_count;

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
        .TILE_W(TILE_W),
        .TILE_H(TILE_H),
        .TILE_NUM(TILE_NUM)
    ) dut (
        .clk(clk),
        .sys_rst(sys_rst),
        .start(start),
        .src_base_addr(src_base_addr),
        .src_stride(src_stride),
        .src_w(src_w),
        .src_h(src_h),
        .dst_w(dst_w),
        .dst_h(dst_h),
        .rot_sin_q16(32'sd0),
        .rot_cos_q16(32'sh0001_0000),
        .geom_ready(1'b1),
        .geom_error(1'b0),
        .geom_step_x_x(GEOM_ONE_Q16),
        .geom_step_y_x('0),
        .geom_step_x_y('0),
        .geom_step_y_y(GEOM_ONE_Q16),
        .geom_row0_x('0),
        .geom_row0_y('0),
        .geom_src_x_last((src_w == '0) ? '0 : src_w[$clog2(MAX_SRC_W)-1:0] - 1'b1),
        .geom_src_y_last((src_h == '0) ? '0 : src_h[$clog2(MAX_SRC_H)-1:0] - 1'b1),
        .geom_src_x_max_q16(geom_src_x_max_q16),
        .geom_src_y_max_q16(geom_src_y_max_q16),
        .prefetch_enable(1'b1),
        .runtime_lead_pixels(16'd64),
        .runtime_merge_max_x_eff(8'd8),
        .runtime_merge_min_x(8'd1),
        .runtime_fifo_depth_eff(16'd32),
        .runtime_fifo_age_limit(16'd0),
        .runtime_prefetch_throttle_cycles(16'd0),
        .runtime_scheduler_policy(2'd0),
        .scan_dir_x(scan_dir_x),
        .scan_dir_y(scan_dir_y),
        .scan_dir_valid(scan_dir_valid),
        .busy(busy),
        .error(error),
        .read_start(read_start),
        .read_addr(read_addr),
        .read_row_stride(read_row_stride),
        .read_byte_count(read_byte_count),
        .read_row_count(read_row_count),
        .read_start_ready(read_start_ready),
        .read_busy(read_busy),
        .read_done(read_done),
        .read_error(read_error),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_row_last(in_row_last),
        .in_ready(in_ready),
        .sample_req_valid(sample_req_valid),
        .sample_x0(sample_x0),
        .sample_y0(sample_y0),
        .sample_x1(sample_x1),
        .sample_y1(sample_y1),
        .sample_req_ready(sample_req_ready),
        .sample_p00(sample_p00),
        .sample_p01(sample_p01),
        .sample_p10(sample_p10),
        .sample_p11(sample_p11),
        .sample_rsp_valid(sample_rsp_valid),
        .stat_read_starts(stat_read_starts),
        .stat_misses(stat_misses),
        .stat_prefetch_starts(stat_prefetch_starts),
        .stat_prefetch_hits(stat_prefetch_hits)
    );

    task automatic init_memory;
        int x;
        int y;
        begin
            for (x = 0; x < MEM_BYTES; x = x + 1) begin
                src_mem[x] = 8'h00;
            end
            for (y = 0; y < 24; y = y + 1) begin
                for (x = 0; x < 96; x = x + 1) begin
                    src_mem[32'h0000_0100 + y*96 + x] = byte'(((y * 31) + (x * 5) + 9) & 8'hFF);
                end
            end
        end
    endtask

    task automatic reset_dut;
        begin
            sys_rst           = 1'b1;
            start             = 1'b0;
            src_base_addr     = 32'h0000_0100;
            src_stride        = 32'd96;
            src_w             = 96;
            src_h             = 24;
            dst_w             = 96;
            dst_h             = 24;
            sample_req_valid  = 1'b0;
            scan_dir_x        = 2'sd1;
            scan_dir_y        = 2'sd0;
            scan_dir_valid    = 1'b1;
            sample_x0         = '0;
            sample_y0         = '0;
            sample_x1         = '0;
            sample_y1         = '0;
            read_busy         = 1'b0;
            read_done         = 1'b0;
            read_error        = 1'b0;
            in_valid          = 1'b0;
            rd_addr_reg       = '0;
            rd_row_stride_reg = '0;
            rd_row_width_reg  = '0;
            rd_remaining_reg  = 0;
            rd_index_reg      = 0;
            read_start_count  = 0;
            max_read_byte_count = 0;
            init_memory();
            repeat (5) @(posedge clk);
            sys_rst = 1'b0;
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    task automatic expect_sample(
        input int x0,
        input int y0,
        input int x1,
        input int y1
    );
        byte exp00;
        byte exp01;
        byte exp10;
        byte exp11;
        begin
            exp00 = src_mem[src_base_addr + y0*src_stride + x0];
            exp01 = src_mem[src_base_addr + y0*src_stride + x1];
            exp10 = src_mem[src_base_addr + y1*src_stride + x0];
            exp11 = src_mem[src_base_addr + y1*src_stride + x1];

            @(posedge clk);
            sample_x0        <= x0;
            sample_y0        <= y0;
            sample_x1        <= x1;
            sample_y1        <= y1;
            sample_req_valid <= 1'b1;

            while (!sample_req_ready) begin
                @(posedge clk);
                if (error) begin
                    $fatal(1, "prefetch cache raised error while waiting sample (%0d,%0d)-(%0d,%0d)", x0, y0, x1, y1);
                end
            end

            sample_req_valid <= 1'b0;

            while (!sample_rsp_valid) begin
                @(posedge clk);
            end

            if ((sample_p00 !== exp00) || (sample_p01 !== exp01) ||
                (sample_p10 !== exp10) || (sample_p11 !== exp11)) begin
                $fatal(1, "Prefetch sample mismatch req=(%0d,%0d)-(%0d,%0d)", x0, y0, x1, y1);
            end

            @(posedge clk);
        end
    endtask

    task automatic wait_until_idle;
        int timeout;
        begin
            timeout = 0;
            while (busy) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 5000) begin
                    $fatal(1, "Timed out waiting for prefetch cache to become idle");
                end
            end
        end
    endtask

    task automatic wait_for_read_starts(input int expected_count);
        int timeout;
        begin
            timeout = 0;
            while (read_start_count < expected_count) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 5000) begin
                    $fatal(1, "Timed out waiting for read_start_count=%0d (got %0d)", expected_count, read_start_count);
                end
            end
        end
    endtask

    task automatic wait_for_prefetch_starts(input int expected_count);
        int timeout;
        begin
            timeout = 0;
            while (stat_prefetch_starts < expected_count) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 5000) begin
                    $fatal(1, "Timed out waiting for stat_prefetch_starts=%0d (got %0d)", expected_count, stat_prefetch_starts);
                end
            end
        end
    endtask

    always_ff @(posedge clk) begin
        if (sys_rst) begin
            read_busy        <= 1'b0;
            read_done        <= 1'b0;
            read_error       <= 1'b0;
            in_valid         <= 1'b0;
            rd_addr_reg      <= '0;
            rd_row_stride_reg <= '0;
            rd_row_width_reg <= '0;
            rd_remaining_reg <= 0;
            rd_index_reg     <= 0;
            max_read_byte_count <= 0;
        end else begin
            read_done  <= 1'b0;
            read_error <= 1'b0;

            if (!read_busy && read_start) begin
                read_busy        <= 1'b1;
                rd_addr_reg      <= read_addr;
                rd_row_stride_reg <= read_row_stride;
                rd_row_width_reg <= read_byte_count;
                rd_remaining_reg <= read_byte_count * read_row_count;
                rd_index_reg     <= 0;
                read_start_count <= read_start_count + 1;
                if (read_start_count < 24) begin
                    $display("PREFETCH_TB_READ idx=%0d addr=0x%08x bytes=%0d rows=%0d stat_pref=%0d stat_miss=%0d",
                        read_start_count, read_addr, read_byte_count, read_row_count, stat_prefetch_starts, stat_misses);
                end
                if (read_byte_count > max_read_byte_count) begin
                    max_read_byte_count <= read_byte_count;
                end
            end

            if (read_busy) begin
                in_valid <= (rd_remaining_reg > 0);
                if (in_valid && in_ready) begin
                    rd_index_reg     <= rd_index_reg + 1;
                    rd_remaining_reg <= rd_remaining_reg - 1;
                    if (rd_remaining_reg == 1) begin
                        read_busy <= 1'b0;
                        read_done <= 1'b1;
                        in_valid  <= 1'b0;
                    end
                end
            end else begin
                in_valid <= 1'b0;
            end

        end
    end

    always_comb begin
        if (read_busy && (rd_remaining_reg > 0)) begin
            in_data = src_mem[rd_addr_reg +
                              ((rd_index_reg / rd_row_width_reg) * rd_row_stride_reg) +
                              (rd_index_reg % rd_row_width_reg)];
        end else begin
            in_data = '0;
        end
    end

    assign in_row_last = read_busy && (rd_remaining_reg > 0) &&
                         (rd_row_width_reg != 0) &&
                         (((rd_index_reg % rd_row_width_reg) + 1) == rd_row_width_reg);
    assign read_start_ready = !read_busy;

    initial begin
        reset_dut();

        expect_sample(2, 3, 3, 4);
        if (read_start_count < 1) begin
            $fatal(1, "First tile load should issue at least one 2D read task, got %0d", read_start_count);
        end

        repeat (1000) @(posedge clk);

        if (max_read_byte_count < 16) begin
            $fatal(1, "Analytic FIFO merge should issue at least one multi-sector read, max byte_count=%0d", max_read_byte_count);
        end

        expect_sample(32, 6, 33, 7);
        expect_sample(64, 6, 65, 7);

        if (error) begin
            $fatal(1, "Prefetch cache error flag should remain low");
        end

        $display("tb_src_tile_cache_prefetch completed");
        $finish;
    end

endmodule
