`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_scale_core_nearest.md。

// Keep tb_scale_core_nearest.md in sync
module tb_scale_core_nearest;

    // 测试目标：
    // 1. 覆盖最近邻缩放的放大、缩小和边界裁剪
    // 2. 检查行请求、像素请求和输出像素序列

    localparam int PIXEL_W   = 8;
    localparam int MAX_SRC_W = 16;
    localparam int MAX_SRC_H = 16;
    localparam int MAX_DST_W = 16;
    localparam int MAX_DST_H = 16;
    localparam int FRAC_W    = 16;
    localparam int LINE_NUM  = 2;
    localparam int SRC_X_W   = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_Y_W   = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;
    localparam int DST_X_W   = $clog2(MAX_DST_W+1);
    localparam int DST_Y_W   = $clog2(MAX_DST_H+1);
    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int SCALE_W   = FRAC_W + 16;

    logic clk;
    logic rst;

    logic start;
    logic [DST_X_W-1:0] src_w;
    logic [DST_Y_W-1:0] src_h;
    logic [DST_X_W-1:0] dst_w;
    logic [DST_Y_W-1:0] dst_h;
    logic busy;
    logic done;
    logic error;

    logic                  line_req_valid;
    logic [SRC_Y_W-1:0]    line_req_y;
    logic                  line_req_ready;
    logic [LINE_SEL_W-1:0] line_req_sel;

    logic                  pixel_req_valid;
    logic [LINE_SEL_W-1:0] pixel_req_line_sel;
    logic [SRC_X_W-1:0]    pixel_req_x;
    logic [PIXEL_W-1:0]    pixel_rsp_data;
    logic                  pixel_rsp_valid;

    logic [PIXEL_W-1:0] pix_data;
    logic               pix_valid;
    logic               pix_ready;
    logic               row_done;

    logic [PIXEL_W-1:0] src_img [0:MAX_SRC_H-1][0:MAX_SRC_W-1];
    logic [PIXEL_W-1:0] observed [0:MAX_DST_H-1][0:MAX_DST_W-1];

    int out_x;
    int out_y;
    int row_done_count;
    int pixel_count;
    int cycle_count;
    int line_req_count;

    int pending_src_x;
    int pending_src_y;
    int pending_line_sel;
    bit pending_pixel_rsp;

    int expected_src_x;
    int expected_src_y;
    int case_src_w;
    int case_src_h;
    int case_dst_w;
    int case_dst_h;

    assign line_req_sel = line_req_y[LINE_SEL_W-1:0];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    scale_core_nearest #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .FRAC_W(FRAC_W),
        .LINE_NUM(LINE_NUM)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .src_w(src_w),
        .src_h(src_h),
        .dst_w(dst_w),
        .dst_h(dst_h),
        .busy(busy),
        .done(done),
        .error(error),
        .line_req_valid(line_req_valid),
        .line_req_y(line_req_y),
        .line_req_ready(line_req_ready),
        .line_req_sel(line_req_sel),
        .pixel_req_valid(pixel_req_valid),
        .pixel_req_line_sel(pixel_req_line_sel),
        .pixel_req_x(pixel_req_x),
        .pixel_rsp_data(pixel_rsp_data),
        .pixel_rsp_valid(pixel_rsp_valid),
        .pix_data(pix_data),
        .pix_valid(pix_valid),
        .pix_ready(pix_ready),
        .row_done(row_done)
    );

    function automatic int calc_nearest_index(
        input int dst_idx,
        input int src_size,
        input int dst_size
    );
        longint pos_fp;
        longint scale_fp;
        int idx;
        begin
            scale_fp = (longint'(src_size) << FRAC_W) / dst_size;
            pos_fp   = longint'(dst_idx) * scale_fp;
            idx      = int'((pos_fp + (1 << (FRAC_W-1))) >>> FRAC_W);
            if (idx >= src_size) begin
                idx = src_size - 1;
            end
            calc_nearest_index = idx;
        end
    endfunction

    task automatic init_source_image;
        int x;
        int y;
        begin
            for (y = 0; y < MAX_SRC_H; y = y + 1) begin
                for (x = 0; x < MAX_SRC_W; x = x + 1) begin
                    src_img[y][x] = ((y * 17) + (x * 5) + (y ^ x)) & 'hFF;
                end
            end
        end
    endtask

    task automatic clear_observed;
        int x;
        int y;
        begin
            for (y = 0; y < MAX_DST_H; y = y + 1) begin
                for (x = 0; x < MAX_DST_W; x = x + 1) begin
                    observed[y][x] = '0;
                end
            end
        end
    endtask

    task automatic reset_dut;
        begin
            rst              = 1'b1;
            start            = 1'b0;
            src_w            = '0;
            src_h            = '0;
            dst_w            = '0;
            dst_h            = '0;
            line_req_ready   = 1'b0;
            pixel_rsp_data   = '0;
            pixel_rsp_valid  = 1'b0;
            pix_ready        = 1'b0;
            out_x            = 0;
            out_y            = 0;
            row_done_count   = 0;
            pixel_count      = 0;
            cycle_count      = 0;
            line_req_count   = 0;
            pending_src_x    = 0;
            pending_src_y    = 0;
            pending_line_sel = 0;
            pending_pixel_rsp = 1'b0;
            clear_observed();
            repeat (5) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic start_case(
        input int src_w_i,
        input int src_h_i,
        input int dst_w_i,
        input int dst_h_i
    );
        begin
            case_src_w = src_w_i;
            case_src_h = src_h_i;
            case_dst_w = dst_w_i;
            case_dst_h = dst_h_i;
            @(posedge clk);
            src_w          <= src_w_i;
            src_h          <= src_h_i;
            dst_w          <= dst_w_i;
            dst_h          <= dst_h_i;
            line_req_ready <= 1'b1;
            pix_ready      <= 1'b1;
            start          <= 1'b1;
            @(posedge clk);
            start          <= 1'b0;
        end
    endtask

    task automatic wait_for_completion(input string case_name, input int timeout_cycles);
        begin
            while (!done && !error) begin
                @(posedge clk);
                if (cycle_count > timeout_cycles) begin
                    $fatal(1, "%s timed out", case_name);
                end
            end
        end
    endtask

    task automatic check_observed_pixels(input string case_name);
        int x;
        int y;
        int exp_x;
        int exp_y;
        begin
            if (pixel_count != (case_dst_w * case_dst_h)) begin
                $fatal(1, "%s pixel_count mismatch got=%0d exp=%0d",
                    case_name, pixel_count, case_dst_w * case_dst_h);
            end

            if (row_done_count != case_dst_h) begin
                $fatal(1, "%s row_done_count mismatch got=%0d exp=%0d",
                    case_name, row_done_count, case_dst_h);
            end

            for (y = 0; y < case_dst_h; y = y + 1) begin
                for (x = 0; x < case_dst_w; x = x + 1) begin
                    exp_x = calc_nearest_index(x, case_src_w, case_dst_w);
                    exp_y = calc_nearest_index(y, case_src_h, case_dst_h);
                    if (observed[y][x] !== src_img[exp_y][exp_x]) begin
                        $fatal(1,
                            "%s mismatch at dst(%0d,%0d): got=%0d exp=%0d from src(%0d,%0d)",
                            case_name, x, y, observed[y][x], src_img[exp_y][exp_x], exp_x, exp_y);
                    end
                end
            end
        end
    endtask

    task automatic run_success_case(
        input string case_name,
        input int src_w_i,
        input int src_h_i,
        input int dst_w_i,
        input int dst_h_i,
        input bit enable_line_stall,
        input bit enable_pix_backpressure
    );
        begin
            $display("Running %s", case_name);
            reset_dut();
            start_case(src_w_i, src_h_i, dst_w_i, dst_h_i);

            while (!done && !error) begin
                @(posedge clk);
                line_req_ready <= !(enable_line_stall && ((cycle_count % 4) == 1));
                pix_ready      <= !(enable_pix_backpressure && ((cycle_count % 5) == 2));
                if (cycle_count > 4000) begin
                    $fatal(1, "%s timed out", case_name);
                end
            end

            if (error) begin
                $fatal(1, "%s unexpectedly asserted error", case_name);
            end

            check_observed_pixels(case_name);

            if (line_req_count != case_dst_h) begin
                $fatal(1, "%s line request count mismatch got=%0d exp=%0d",
                    case_name, line_req_count, case_dst_h);
            end

            @(posedge clk);
            if (busy) begin
                $fatal(1, "%s busy should clear after done", case_name);
            end
        end
    endtask

    task automatic run_error_case(input string case_name);
        begin
            $display("Running %s", case_name);
            reset_dut();
            start_case(0, 5, 4, 4);
            wait_for_completion(case_name, 200);
            if (!error) begin
                $fatal(1, "%s should assert error", case_name);
            end
            if (done) begin
                $fatal(1, "%s should not assert done", case_name);
            end
            while (busy) begin
                @(posedge clk);
                if (cycle_count > 220) begin
                    $fatal(1, "%s busy did not clear after error", case_name);
                end
            end
            if ((pixel_count != 0) || (row_done_count != 0) || (line_req_count != 0)) begin
                $fatal(1, "%s should not emit output activity after invalid start", case_name);
            end
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count       <= 0;
            pixel_rsp_valid   <= 1'b0;
            pixel_rsp_data    <= '0;
            pending_pixel_rsp <= 1'b0;
        end else begin
            cycle_count     <= cycle_count + 1;
            pixel_rsp_valid <= 1'b0;

            if (line_req_valid && line_req_ready) begin
                line_req_count <= line_req_count + 1;
            end

            if (pixel_req_valid) begin
                expected_src_x = calc_nearest_index(out_x, case_src_w, case_dst_w);
                expected_src_y = calc_nearest_index(out_y, case_src_h, case_dst_h);

                if (pixel_req_x !== expected_src_x[SRC_X_W-1:0]) begin
                    $fatal(1, "pixel_req_x mismatch at dst(%0d,%0d): got=%0d exp=%0d",
                        out_x, out_y, pixel_req_x, expected_src_x);
                end

                if (pixel_req_line_sel !== expected_src_y[LINE_SEL_W-1:0]) begin
                    $fatal(1, "pixel_req_line_sel mismatch at dst(%0d,%0d): got=%0d exp=%0d",
                        out_x, out_y, pixel_req_line_sel, expected_src_y[LINE_SEL_W-1:0]);
                end

                pending_src_x    <= expected_src_x;
                pending_src_y    <= expected_src_y;
                pending_line_sel <= expected_src_y[LINE_SEL_W-1:0];
                pending_pixel_rsp <= 1'b1;
            end

            if (pending_pixel_rsp) begin
                pixel_rsp_valid   <= 1'b1;
                pixel_rsp_data    <= src_img[pending_src_y][pending_src_x];
                pending_pixel_rsp <= 1'b0;
            end

            if (pix_valid && pix_ready) begin
                observed[out_y][out_x] <= pix_data;
                pixel_count            <= pixel_count + 1;
                if (out_x == (case_dst_w - 1)) begin
                    out_x <= 0;
                    out_y <= out_y + 1;
                end else begin
                    out_x <= out_x + 1;
                end
            end

            if (row_done) begin
                row_done_count <= row_done_count + 1;
                if ((pixel_count == 0) || ((pixel_count % case_dst_w) != 0)) begin
                    $fatal(1, "row_done should occur after a full output row");
                end
            end
        end
    end

    initial begin
        init_source_image();
        run_success_case("identity_4x4",     4, 4, 4, 4, 1'b0, 1'b0);
        run_success_case("downscale_6x5_to_3x2", 6, 5, 3, 2, 1'b0, 1'b0);
        run_success_case("upscale_3x3_to_5x5",   3, 3, 5, 5, 1'b1, 1'b1);
        run_success_case("mixed_7x4_to_5x3",     7, 4, 5, 3, 1'b1, 1'b0);
        run_error_case("invalid_zero_src_w");
        $display("tb_scale_core_nearest completed");
        $finish;
    end

endmodule
