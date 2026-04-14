`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_src_line_buffer.md。

// Keep tb_src_line_buffer.md in sync
module tb_src_line_buffer;

    // 测试目标：
    // 1. 覆盖单行装载、双端口读取和错误场景
    // 2. 检查缓存内容与读口返回时序

    localparam int PIXEL_W   = 8;
    localparam int MAX_SRC_W = 8;
    localparam int LINE_NUM  = 2;
    localparam int LINE_SEL_W = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;
    localparam int X_W        = (MAX_SRC_W > 1) ? $clog2(MAX_SRC_W) : 1;
    localparam int COUNT_W    = $clog2(MAX_SRC_W+1);

    logic                   clk;
    logic                   sys_rst;
    logic                   load_start;
    logic [LINE_SEL_W-1:0]  load_line_sel;
    logic [COUNT_W-1:0]     load_pixel_count;
    logic                   load_busy;
    logic                   load_done;
    logic                   load_error;
    logic [PIXEL_W-1:0]     in_data;
    logic                   in_valid;
    logic                   in_ready;
    logic                   rd0_req_valid;
    logic [LINE_SEL_W-1:0]  rd0_line_sel;
    logic [X_W-1:0]         rd0_x;
    logic [PIXEL_W-1:0]     rd0_data;
    logic                   rd0_data_valid;
    logic                   rd1_req_valid;
    logic [LINE_SEL_W-1:0]  rd1_line_sel;
    logic [X_W-1:0]         rd1_x;
    logic [PIXEL_W-1:0]     rd1_data;
    logic                   rd1_data_valid;

    int case_cycle_count;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    src_line_buffer #(
        .PIXEL_W(PIXEL_W),
        .MAX_SRC_W(MAX_SRC_W),
        .LINE_NUM(LINE_NUM)
    ) dut (
        .clk(clk),
        .sys_rst(sys_rst),
        .load_start(load_start),
        .load_line_sel(load_line_sel),
        .load_pixel_count(load_pixel_count),
        .load_busy(load_busy),
        .load_done(load_done),
        .load_error(load_error),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .rd0_req_valid(rd0_req_valid),
        .rd0_line_sel(rd0_line_sel),
        .rd0_x(rd0_x),
        .rd0_data(rd0_data),
        .rd0_data_valid(rd0_data_valid),
        .rd1_req_valid(rd1_req_valid),
        .rd1_line_sel(rd1_line_sel),
        .rd1_x(rd1_x),
        .rd1_data(rd1_data),
        .rd1_data_valid(rd1_data_valid)
    );

    task automatic apply_reset;
        begin
            sys_rst           = 1'b1;
            load_start        = 1'b0;
            load_line_sel     = '0;
            load_pixel_count  = '0;
            in_data           = '0;
            in_valid          = 1'b0;
            rd0_req_valid     = 1'b0;
            rd0_line_sel      = '0;
            rd0_x             = '0;
            rd1_req_valid     = 1'b0;
            rd1_line_sel      = '0;
            rd1_x             = '0;
            case_cycle_count  = 0;
            repeat (5) @(posedge clk);
            sys_rst = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic start_load(input logic [LINE_SEL_W-1:0] line_sel, input logic [COUNT_W-1:0] pixel_count);
        begin
            @(posedge clk);
            load_line_sel    <= line_sel;
            load_pixel_count <= pixel_count;
            load_start       <= 1'b1;
            @(posedge clk);
            load_start       <= 1'b0;
        end
    endtask

    task automatic send_pixels(input byte p0, input byte p1, input byte p2, input byte p3);
        byte pixels [0:3];
        int idx;
        begin
            pixels[0] = p0;
            pixels[1] = p1;
            pixels[2] = p2;
            pixels[3] = p3;
            idx = 0;
            while (idx < 4) begin
                @(posedge clk);
                if (in_ready) begin
                    in_valid <= 1'b1;
                    in_data  <= pixels[idx];
                    idx = idx + 1;
                end else begin
                    in_valid <= 1'b0;
                end
            end
            @(posedge clk);
            in_valid <= 1'b0;
        end
    endtask

    task automatic wait_for_done(input string case_name);
        begin
            case_cycle_count = 0;
            while (!load_done && !load_error) begin
                @(posedge clk);
                case_cycle_count = case_cycle_count + 1;
                if (case_cycle_count > 50) begin
                    $fatal(1, "%s timed out waiting for load result", case_name);
                end
            end
        end
    endtask

    task automatic read_dual_and_check(
        input logic [LINE_SEL_W-1:0] rd0_line,
        input logic [X_W-1:0]        rd0_pos,
        input byte                   exp0,
        input logic [LINE_SEL_W-1:0] rd1_line,
        input logic [X_W-1:0]        rd1_pos,
        input byte                   exp1,
        input string                 case_name
    );
        begin
            @(negedge clk);
            rd0_line_sel  <= rd0_line;
            rd0_x         <= rd0_pos;
            rd0_req_valid <= 1'b1;
            rd1_line_sel  <= rd1_line;
            rd1_x         <= rd1_pos;
            rd1_req_valid <= 1'b1;
            @(posedge clk);
            #1;

            if (!rd0_data_valid || !rd1_data_valid) begin
                $fatal(1, "%s expected both read valid signals", case_name);
            end
            if (rd0_data !== exp0 || rd1_data !== exp1) begin
                $fatal(1, "%s read mismatch rd0=%0d exp0=%0d rd1=%0d exp1=%0d",
                    case_name, rd0_data, exp0, rd1_data, exp1);
            end

            @(negedge clk);
            rd0_req_valid <= 1'b0;
            rd1_req_valid <= 1'b0;
        end
    endtask

    task automatic run_basic_load_and_read_case;
        begin
            $display("Running basic_load_and_read");
            apply_reset();
            start_load(0, 4);
            send_pixels(8'h11, 8'h22, 8'h33, 8'h44);
            wait_for_done("basic_load_and_read");
            if (load_error) begin
                $fatal(1, "basic_load_and_read unexpectedly asserted load_error");
            end
            read_dual_and_check(0, 0, 8'h11, 0, 3, 8'h44, "basic_load_and_read");
        end
    endtask

    task automatic run_two_line_case;
        begin
            $display("Running two_line_isolation");
            apply_reset();
            start_load(0, 4);
            send_pixels(8'h10, 8'h11, 8'h12, 8'h13);
            wait_for_done("two_line_line0");
            start_load(1, 4);
            send_pixels(8'h20, 8'h21, 8'h22, 8'h23);
            wait_for_done("two_line_line1");
            read_dual_and_check(0, 2, 8'h12, 1, 1, 8'h21, "two_line_isolation");
        end
    endtask

    task automatic run_overflow_count_error_case;
        begin
            $display("Running overflow_count_error");
            apply_reset();
            start_load(0, MAX_SRC_W + 1);
            wait_for_done("overflow_count_error");
            if (!load_error) begin
                $fatal(1, "overflow_count_error should assert load_error");
            end
            if (load_done) begin
                $fatal(1, "overflow_count_error should not assert load_done");
            end
        end
    endtask

    initial begin
        run_basic_load_and_read_case();
        run_two_line_case();
        run_overflow_count_error_case();
        $display("tb_src_line_buffer completed");
        $finish;
    end

endmodule
