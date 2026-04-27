`timescale 1ns/1ps

module tb_rotate_core_bilinear_trace;
    localparam int PIXEL_W = 8;
    localparam int MAX_SRC_W = 32;
    localparam int MAX_SRC_H = 32;
    localparam int MAX_DST_W = 32;
    localparam int MAX_DST_H = 32;
    localparam int FRAC_W = 16;
    localparam int COORD_W = 48;
    localparam int SRC_X_W = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int SRC_Y_W = (MAX_SRC_H > 1) ? $clog2(MAX_SRC_H) : 1;

    logic clk;
    logic rst;
    logic start;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h;
    logic [$clog2(MAX_DST_W+1)-1:0] dst_w;
    logic [$clog2(MAX_DST_H+1)-1:0] dst_h;
    logic signed [31:0] angle_cos_q16;
    logic signed [31:0] angle_sin_q16;
    logic geom_ready;
    logic geom_error;
    logic signed [COORD_W-1:0] geom_step_x_x;
    logic signed [COORD_W-1:0] geom_step_y_x;
    logic signed [COORD_W-1:0] geom_step_x_y;
    logic signed [COORD_W-1:0] geom_step_y_y;
    logic signed [COORD_W-1:0] geom_row0_x;
    logic signed [COORD_W-1:0] geom_row0_y;
    logic [SRC_X_W-1:0] geom_src_x_last;
    logic [SRC_Y_W-1:0] geom_src_y_last;
    logic signed [COORD_W-1:0] geom_src_x_max_q16;
    logic signed [COORD_W-1:0] geom_src_y_max_q16;
    logic busy;
    logic done;
    logic error;
    logic sample_req_valid;
    logic [SRC_X_W-1:0] sample_x0;
    logic [SRC_Y_W-1:0] sample_y0;
    logic [SRC_X_W-1:0] sample_x1;
    logic [SRC_Y_W-1:0] sample_y1;
    logic sample_req_ready;
    logic [PIXEL_W-1:0] sample_p00;
    logic [PIXEL_W-1:0] sample_p01;
    logic [PIXEL_W-1:0] sample_p10;
    logic [PIXEL_W-1:0] sample_p11;
    logic sample_rsp_valid;
    logic signed [1:0] scan_dir_x;
    logic signed [1:0] scan_dir_y;
    logic scan_dir_valid;
    logic [PIXEL_W-1:0] pix_data;
    logic pix_valid;
    logic pix_ready;
    logic row_done;

    int req_count;
    int pix_count;

    rotate_core_bilinear #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .FRAC_W(FRAC_W),
        .COORD_W(COORD_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .src_w(src_w),
        .src_h(src_h),
        .dst_w(dst_w),
        .dst_h(dst_h),
        .angle_cos_q16(angle_cos_q16),
        .angle_sin_q16(angle_sin_q16),
        .geom_ready(geom_ready),
        .geom_error(geom_error),
        .geom_step_x_x(geom_step_x_x),
        .geom_step_y_x(geom_step_y_x),
        .geom_step_x_y(geom_step_x_y),
        .geom_step_y_y(geom_step_y_y),
        .geom_row0_x(geom_row0_x),
        .geom_row0_y(geom_row0_y),
        .geom_src_x_last(geom_src_x_last),
        .geom_src_y_last(geom_src_y_last),
        .geom_src_x_max_q16(geom_src_x_max_q16),
        .geom_src_y_max_q16(geom_src_y_max_q16),
        .busy(busy),
        .done(done),
        .error(error),
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
        .scan_dir_x(scan_dir_x),
        .scan_dir_y(scan_dir_y),
        .scan_dir_valid(scan_dir_valid),
        .pix_data(pix_data),
        .pix_valid(pix_valid),
        .pix_ready(pix_ready),
        .row_done(row_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic longint signed sx(input logic signed [31:0] v);
        sx = $signed(v);
    endfunction

    task automatic setup_geom(
        input int case_src_w,
        input int case_src_h,
        input int case_dst_w,
        input int case_dst_h,
        input logic signed [31:0] case_sin,
        input logic signed [31:0] case_cos
    );
        longint signed scale_x;
        longint signed scale_y;
        longint signed src_cx;
        longint signed src_cy;
        longint signed dst_cx;
        longint signed dst_cy;
        begin
            scale_x = (longint'(case_src_w) <<< FRAC_W) / case_dst_w;
            scale_y = (longint'(case_src_h) <<< FRAC_W) / case_dst_h;
            src_cx = longint'(case_src_w - 1) <<< (FRAC_W - 1);
            src_cy = longint'(case_src_h - 1) <<< (FRAC_W - 1);
            dst_cx = longint'(case_dst_w - 1) <<< (FRAC_W - 1);
            dst_cy = longint'(case_dst_h - 1) <<< (FRAC_W - 1);
            geom_step_x_x = (sx(case_cos) * scale_x) >>> FRAC_W;
            geom_step_y_x = -((sx(case_sin) * scale_x) >>> FRAC_W);
            geom_step_x_y = (sx(case_sin) * scale_y) >>> FRAC_W;
            geom_step_y_y = (sx(case_cos) * scale_y) >>> FRAC_W;
            geom_row0_x = src_cx
                - ((dst_cx * geom_step_x_x) >>> FRAC_W)
                - ((dst_cy * geom_step_x_y) >>> FRAC_W);
            geom_row0_y = src_cy
                - ((dst_cx * geom_step_y_x) >>> FRAC_W)
                - ((dst_cy * geom_step_y_y) >>> FRAC_W);
            geom_src_x_last = SRC_X_W'(case_src_w - 1);
            geom_src_y_last = SRC_Y_W'(case_src_h - 1);
            geom_src_x_max_q16 = longint'(case_src_w - 1) <<< FRAC_W;
            geom_src_y_max_q16 = longint'(case_src_h - 1) <<< FRAC_W;
        end
    endtask

    task automatic expected_sample(
        input int idx,
        output int exp_x0,
        output int exp_y0,
        output int exp_x1,
        output int exp_y1
    );
        int xd;
        int yd;
        longint signed x_q16;
        longint signed y_q16;
        begin
            xd = idx % dst_w;
            yd = idx / dst_w;
            x_q16 = geom_row0_x + (longint'(xd) * geom_step_x_x) + (longint'(yd) * geom_step_x_y);
            y_q16 = geom_row0_y + (longint'(xd) * geom_step_y_x) + (longint'(yd) * geom_step_y_y);
            if (x_q16 < 0) x_q16 = 0;
            if (y_q16 < 0) y_q16 = 0;
            if (x_q16 > geom_src_x_max_q16) x_q16 = geom_src_x_max_q16;
            if (y_q16 > geom_src_y_max_q16) y_q16 = geom_src_y_max_q16;
            exp_x0 = x_q16 >>> FRAC_W;
            exp_y0 = y_q16 >>> FRAC_W;
            exp_x1 = (exp_x0 >= geom_src_x_last) ? geom_src_x_last : (exp_x0 + 1);
            exp_y1 = (exp_y0 >= geom_src_y_last) ? geom_src_y_last : (exp_y0 + 1);
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_rsp_valid <= 1'b0;
            sample_p00 <= '0;
            sample_p01 <= '0;
            sample_p10 <= '0;
            sample_p11 <= '0;
            pix_count <= 0;
        end else begin
            sample_rsp_valid <= sample_req_valid && sample_req_ready;
            if (sample_req_valid && sample_req_ready) begin
                sample_p00 <= 8'd10;
                sample_p01 <= 8'd20;
                sample_p10 <= 8'd30;
                sample_p11 <= 8'd40;
            end
            if (pix_valid && pix_ready) begin
                pix_count <= pix_count + 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        int exp_x0;
        int exp_y0;
        int exp_x1;
        int exp_y1;
        if (rst) begin
            req_count <= 0;
        end else if (sample_req_valid && sample_req_ready) begin
            expected_sample(req_count, exp_x0, exp_y0, exp_x1, exp_y1);
            if ((sample_x0 !== exp_x0) || (sample_y0 !== exp_y0) ||
                (sample_x1 !== exp_x1) || (sample_y1 !== exp_y1)) begin
                $fatal(1, "sample trace mismatch idx=%0d got=(%0d,%0d,%0d,%0d) exp=(%0d,%0d,%0d,%0d)",
                    req_count, sample_x0, sample_y0, sample_x1, sample_y1,
                    exp_x0, exp_y0, exp_x1, exp_y1);
            end
            req_count <= req_count + 1;
        end
    end

    task automatic run_case(
        input string name,
        input int case_src_w,
        input int case_src_h,
        input int case_dst_w,
        input int case_dst_h,
        input logic signed [31:0] case_sin,
        input logic signed [31:0] case_cos
    );
        int wait_cycles;
        begin
            rst = 1'b1;
            start = 1'b0;
            geom_ready = 1'b0;
            geom_error = 1'b0;
            sample_req_ready = 1'b1;
            pix_ready = 1'b1;
            req_count = 0;
            pix_count = 0;
            repeat (4) @(posedge clk);
            src_w = case_src_w;
            src_h = case_src_h;
            dst_w = case_dst_w;
            dst_h = case_dst_h;
            angle_sin_q16 = case_sin;
            angle_cos_q16 = case_cos;
            setup_geom(case_src_w, case_src_h, case_dst_w, case_dst_h, case_sin, case_cos);
            rst = 1'b0;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            repeat (3) @(posedge clk);
            geom_ready = 1'b1;

            wait_cycles = 0;
            while (!done) begin
                @(posedge clk);
                wait_cycles++;
                if (wait_cycles > 5000) begin
                    $fatal(1, "%s timed out waiting for done", name);
                end
            end
            if (error) begin
                $fatal(1, "%s reported core error", name);
            end
            if (req_count != (case_dst_w * case_dst_h)) begin
                $fatal(1, "%s request count mismatch got=%0d exp=%0d", name, req_count, case_dst_w * case_dst_h);
            end
            $display("CORE_TRACE_PASS %s src=%0dx%0d dst=%0dx%0d req=%0d pix=%0d",
                name, case_src_w, case_src_h, case_dst_w, case_dst_h, req_count, pix_count);
        end
    endtask

    initial begin
        run_case("identity_16_to_8", 16, 16, 8, 8, 32'sh0000_0000, 32'sh0001_0000);
        run_case("rotate15_20_to_12", 20, 20, 12, 12, 32'sh0000_4242, 32'sh0000_F747);
        run_case("rotate45_24_to_16", 24, 24, 16, 16, 32'sh0000_B505, 32'sh0000_B505);
        run_case("rotate75_24_to_16", 24, 24, 16, 16, 32'sh0000_F747, 32'sh0000_4242);
        $display("tb_rotate_core_bilinear_trace completed");
        $finish;
    end
endmodule
