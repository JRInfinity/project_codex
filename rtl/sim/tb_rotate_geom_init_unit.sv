`timescale 1ns/1ps

module tb_rotate_geom_init_unit;
    localparam int MAX_SRC_W = 7200;
    localparam int MAX_SRC_H = 7200;
    localparam int MAX_DST_W = 600;
    localparam int MAX_DST_H = 600;
    localparam int FRAC_W    = 16;
    localparam int COORD_W   = 48;
    localparam int GEOM_ID_W = 8;

    logic clk;
    logic rst;
    logic start;
    logic [GEOM_ID_W-1:0] start_id;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h;
    logic [$clog2(MAX_DST_W+1)-1:0] dst_w;
    logic [$clog2(MAX_DST_H+1)-1:0] dst_h;
    logic signed [31:0] rot_sin_q16;
    logic signed [31:0] rot_cos_q16;
    logic geom_valid;
    logic geom_busy;
    logic geom_error;
    logic [GEOM_ID_W-1:0] geom_id;
    logic signed [31:0] scale_x_q16;
    logic signed [31:0] scale_y_q16;
    logic signed [COORD_W-1:0] step_x_x;
    logic signed [COORD_W-1:0] step_y_x;
    logic signed [COORD_W-1:0] step_x_y;
    logic signed [COORD_W-1:0] step_y_y;
    logic signed [COORD_W-1:0] row0_x;
    logic signed [COORD_W-1:0] row0_y;
    logic [(MAX_SRC_W > 1 ? $clog2(MAX_SRC_W) : 1)-1:0] src_x_last;
    logic [(MAX_SRC_H > 1 ? $clog2(MAX_SRC_H) : 1)-1:0] src_y_last;
    logic signed [COORD_W-1:0] src_x_max_q16;
    logic signed [COORD_W-1:0] src_y_max_q16;

    rotate_geom_init_unit #(
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .FRAC_W(FRAC_W),
        .COORD_W(COORD_W),
        .GEOM_ID_W(GEOM_ID_W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .start_id(start_id),
        .src_w(src_w),
        .src_h(src_h),
        .dst_w(dst_w),
        .dst_h(dst_h),
        .rot_sin_q16(rot_sin_q16),
        .rot_cos_q16(rot_cos_q16),
        .geom_valid(geom_valid),
        .geom_busy(geom_busy),
        .geom_error(geom_error),
        .geom_id(geom_id),
        .scale_x_q16(scale_x_q16),
        .scale_y_q16(scale_y_q16),
        .step_x_x(step_x_x),
        .step_y_x(step_y_x),
        .step_x_y(step_x_y),
        .step_y_y(step_y_y),
        .row0_x(row0_x),
        .row0_y(row0_y),
        .src_x_last(src_x_last),
        .src_y_last(src_y_last),
        .src_x_max_q16(src_x_max_q16),
        .src_y_max_q16(src_y_max_q16)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic longint signed sx(input logic signed [31:0] v);
        sx = $signed(v);
    endfunction

    task automatic check_i32(input string name, input logic signed [31:0] got, input longint signed exp);
        begin
            if ($signed(got) !== exp) begin
                $fatal(1, "%s mismatch got=%0d exp=%0d", name, $signed(got), exp);
            end
        end
    endtask

    task automatic check_coord(input string name, input logic signed [COORD_W-1:0] got, input longint signed exp);
        begin
            if ($signed(got) !== exp) begin
                $fatal(1, "%s mismatch got=%0d exp=%0d", name, $signed(got), exp);
            end
        end
    endtask

    task automatic run_case(
        input string name,
        input int case_src_w,
        input int case_src_h,
        input int case_dst_w,
        input int case_dst_h,
        input logic signed [31:0] case_sin,
        input logic signed [31:0] case_cos,
        input logic [GEOM_ID_W-1:0] case_id
    );
        longint signed exp_scale_x;
        longint signed exp_scale_y;
        longint signed exp_src_cx;
        longint signed exp_src_cy;
        longint signed exp_dst_cx;
        longint signed exp_dst_cy;
        longint signed exp_step_x_x;
        longint signed exp_step_y_x;
        longint signed exp_step_x_y;
        longint signed exp_step_y_y;
        longint signed exp_row0_x;
        longint signed exp_row0_y;
        int wait_cycles;
        begin
            exp_scale_x = (longint'(case_src_w) <<< FRAC_W) / case_dst_w;
            exp_scale_y = (longint'(case_src_h) <<< FRAC_W) / case_dst_h;
            exp_src_cx = longint'(case_src_w - 1) <<< (FRAC_W - 1);
            exp_src_cy = longint'(case_src_h - 1) <<< (FRAC_W - 1);
            exp_dst_cx = longint'(case_dst_w - 1) <<< (FRAC_W - 1);
            exp_dst_cy = longint'(case_dst_h - 1) <<< (FRAC_W - 1);
            exp_step_x_x = (sx(case_cos) * exp_scale_x) >>> FRAC_W;
            exp_step_y_x = -((sx(case_sin) * exp_scale_x) >>> FRAC_W);
            exp_step_x_y = (sx(case_sin) * exp_scale_y) >>> FRAC_W;
            exp_step_y_y = (sx(case_cos) * exp_scale_y) >>> FRAC_W;
            exp_row0_x = exp_src_cx
                - ((exp_dst_cx * exp_step_x_x) >>> FRAC_W)
                - ((exp_dst_cy * exp_step_x_y) >>> FRAC_W);
            exp_row0_y = exp_src_cy
                - ((exp_dst_cx * exp_step_y_x) >>> FRAC_W)
                - ((exp_dst_cy * exp_step_y_y) >>> FRAC_W);

            @(posedge clk);
            src_w <= case_src_w;
            src_h <= case_src_h;
            dst_w <= case_dst_w;
            dst_h <= case_dst_h;
            rot_sin_q16 <= case_sin;
            rot_cos_q16 <= case_cos;
            start_id <= case_id;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            wait_cycles = 0;
            while (!geom_valid) begin
                @(posedge clk);
                wait_cycles++;
                if (wait_cycles > 120) begin
                    $fatal(1, "%s timed out waiting for geom_valid", name);
                end
            end
            if (geom_error) begin
                $fatal(1, "%s unexpectedly reported geom_error", name);
            end
            if (geom_id !== case_id) begin
                $fatal(1, "%s geom_id mismatch got=%0d exp=%0d", name, geom_id, case_id);
            end
            check_i32({name, ".scale_x"}, scale_x_q16, exp_scale_x);
            check_i32({name, ".scale_y"}, scale_y_q16, exp_scale_y);
            check_coord({name, ".step_x_x"}, step_x_x, exp_step_x_x);
            check_coord({name, ".step_y_x"}, step_y_x, exp_step_y_x);
            check_coord({name, ".step_x_y"}, step_x_y, exp_step_x_y);
            check_coord({name, ".step_y_y"}, step_y_y, exp_step_y_y);
            check_coord({name, ".row0_x"}, row0_x, exp_row0_x);
            check_coord({name, ".row0_y"}, row0_y, exp_row0_y);
            if (src_x_last !== (case_src_w - 1)) begin
                $fatal(1, "%s src_x_last mismatch got=%0d exp=%0d", name, src_x_last, case_src_w - 1);
            end
            if (src_y_last !== (case_src_h - 1)) begin
                $fatal(1, "%s src_y_last mismatch got=%0d exp=%0d", name, src_y_last, case_src_h - 1);
            end
            check_coord({name, ".src_x_max"}, src_x_max_q16, longint'(case_src_w - 1) <<< FRAC_W);
            check_coord({name, ".src_y_max"}, src_y_max_q16, longint'(case_src_h - 1) <<< FRAC_W);
            $display("GEOM_PASS %s id=%0d src=%0dx%0d dst=%0dx%0d sin=0x%08h cos=0x%08h row0=%0d/%0d",
                name, case_id, case_src_w, case_src_h, case_dst_w, case_dst_h,
                case_sin, case_cos, row0_x, row0_y);
            @(posedge clk);
        end
    endtask

    initial begin
        rst = 1'b1;
        start = 1'b0;
        start_id = '0;
        src_w = '0;
        src_h = '0;
        dst_w = '0;
        dst_h = '0;
        rot_sin_q16 = '0;
        rot_cos_q16 = '0;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        run_case("a0_7200_square", 7200, 7200, 600, 600, 32'sh0000_0000, 32'sh0001_0000, 8'd1);
        run_case("a1_7200_square", 7200, 7200, 600, 600, 32'sh0000_0478, 32'sh0000_FFFC, 8'd2);
        run_case("a3_4096_square", 4096, 4096, 600, 600, 32'sh0000_0D65, 32'sh0000_FF72, 8'd3);
        run_case("a5_1920_1080", 1920, 1080, 600, 338, 32'sh0000_1651, 32'sh0000_FF06, 8'd4);
        run_case("a15_7200_wide", 7200, 4096, 600, 600, 32'sh0000_4242, 32'sh0000_F747, 8'd5);
        run_case("a30_4096_tall", 4096, 7200, 600, 600, 32'sh0000_8000, 32'sh0000_DDB4, 8'd6);
        run_case("a45_7200_square", 7200, 7200, 600, 600, 32'sh0000_B505, 32'sh0000_B505, 8'd7);
        run_case("a60_1920_1080", 1920, 1080, 600, 338, 32'sh0000_DDB4, 32'sh0000_8000, 8'd8);
        run_case("a75_7200_square", 7200, 7200, 600, 600, 32'sh0000_F747, 32'sh0000_4242, 8'd9);
        run_case("a90_7200_square", 7200, 7200, 600, 600, 32'sh0001_0000, 32'sh0000_0000, 8'd10);

        @(posedge clk);
        src_w <= '0;
        src_h <= 16;
        dst_w <= 16;
        dst_h <= 16;
        rot_sin_q16 <= '0;
        rot_cos_q16 <= 32'sh0001_0000;
        start_id <= 8'd99;
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        repeat (2) @(posedge clk);
        if (!geom_error) begin
            $fatal(1, "zero dimension did not raise geom_error");
        end

        $display("tb_rotate_geom_init_unit completed");
        $finish;
    end
endmodule
