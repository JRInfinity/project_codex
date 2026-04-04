`timescale 1ns/1ps

// 说明：
// 1. 单独验证 scaler_ctrl 的预装缓存、双行就绪判断和任务收尾逻辑。
// 2. 当前使用 LINE_NUM=2，对应 bilinear 场景下的最小双行缓存配置。
module tb_scaler_ctrl;

    localparam int ADDR_W      = 32;
    localparam int MAX_SRC_W   = 16;
    localparam int MAX_SRC_H   = 16;
    localparam int MAX_DST_W   = 16;
    localparam int MAX_DST_H   = 16;
    localparam int LINE_NUM    = 2;
    localparam int LINE_SEL_W  = (LINE_NUM > 1) ? $clog2(LINE_NUM) : 1;

    logic clk;
    logic sys_rst;
    logic start;
    logic [ADDR_W-1:0] src_base_addr;
    logic [ADDR_W-1:0] dst_base_addr;
    logic [ADDR_W-1:0] src_stride;
    logic [ADDR_W-1:0] dst_stride;
    logic [$clog2(MAX_SRC_W+1)-1:0] src_w;
    logic [$clog2(MAX_SRC_H+1)-1:0] src_h;
    logic [$clog2(MAX_DST_W+1)-1:0] dst_w;
    logic [$clog2(MAX_DST_H+1)-1:0] dst_h;
    logic busy;
    logic done;
    logic error;

    logic read_start;
    logic [ADDR_W-1:0] read_addr;
    logic [31:0] read_byte_count;
    logic read_busy;
    logic read_done;
    logic read_error;

    logic [LINE_SEL_W-1:0] lb_load_sel;
    logic lb_load_start;
    logic [$clog2(MAX_SRC_W+1)-1:0] lb_load_pixel_count;
    logic lb_load_busy;
    logic lb_load_done;
    logic lb_load_error;

    logic core_start;
    logic core_busy;
    logic core_done;
    logic core_error;
    logic line_req_valid;
    logic [$clog2(MAX_SRC_H)-1:0] line_req_y;
    logic line_req_ready;
    logic [LINE_SEL_W-1:0] line_req_sel;
    logic row_done;

    logic row_start;
    logic [$clog2(MAX_DST_W+1)-1:0] row_pixel_count;
    logic row_busy;
    logic row_done_buf;
    logic row_error;
    logic row_out_start;
    logic row_out_done;

    logic write_start;
    logic [ADDR_W-1:0] write_addr;
    logic [31:0] write_byte_count;
    logic write_busy;
    logic write_done;
    logic write_error;

    int load_countdown;
    int read_issue_count;
    int read_seen_count;
    logic [ADDR_W-1:0] read_addr_log [0:3];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    scaler_ctrl #(
        .ADDR_W(ADDR_W),
        .MAX_SRC_W(MAX_SRC_W),
        .MAX_SRC_H(MAX_SRC_H),
        .MAX_DST_W(MAX_DST_W),
        .MAX_DST_H(MAX_DST_H),
        .LINE_NUM(LINE_NUM)
    ) dut (
        .clk(clk),
        .sys_rst(sys_rst),
        .start(start),
        .src_base_addr(src_base_addr),
        .dst_base_addr(dst_base_addr),
        .src_stride(src_stride),
        .dst_stride(dst_stride),
        .src_w(src_w),
        .src_h(src_h),
        .dst_w(dst_w),
        .dst_h(dst_h),
        .busy(busy),
        .done(done),
        .error(error),
        .read_start(read_start),
        .read_addr(read_addr),
        .read_byte_count(read_byte_count),
        .read_busy(read_busy),
        .read_done(read_done),
        .read_error(read_error),
        .lb_load_sel(lb_load_sel),
        .lb_load_start(lb_load_start),
        .lb_load_pixel_count(lb_load_pixel_count),
        .lb_load_busy(lb_load_busy),
        .lb_load_done(lb_load_done),
        .lb_load_error(lb_load_error),
        .core_start(core_start),
        .core_busy(core_busy),
        .core_done(core_done),
        .core_error(core_error),
        .line_req_valid(line_req_valid),
        .line_req_y(line_req_y),
        .line_req_ready(line_req_ready),
        .line_req_sel(line_req_sel),
        .row_done(row_done),
        .row_start(row_start),
        .row_pixel_count(row_pixel_count),
        .row_busy(row_busy),
        .row_done_buf(row_done_buf),
        .row_error(row_error),
        .row_out_start(row_out_start),
        .row_out_done(row_out_done),
        .write_start(write_start),
        .write_addr(write_addr),
        .write_byte_count(write_byte_count),
        .write_busy(write_busy),
        .write_done(write_done),
        .write_error(write_error)
    );

    // 简化模型：read_start 发出后两拍返回 lb_load_done/read_done。
    always_ff @(posedge clk) begin
        if (sys_rst) begin
            load_countdown <= 0;
            read_seen_count <= 0;
            read_busy      <= 1'b0;
            lb_load_busy   <= 1'b0;
            read_done      <= 1'b0;
            lb_load_done   <= 1'b0;
        end else begin
            read_done    <= 1'b0;
            lb_load_done <= 1'b0;

            if (read_start) begin
                read_addr_log[read_seen_count] <= read_addr;
                read_seen_count <= read_seen_count + 1;
                load_countdown <= 2;
                read_busy      <= 1'b1;
                lb_load_busy   <= 1'b1;
            end else if (load_countdown != 0) begin
                load_countdown <= load_countdown - 1;
                if (load_countdown == 1) begin
                    read_busy    <= 1'b0;
                    lb_load_busy <= 1'b0;
                    read_done    <= 1'b1;
                    lb_load_done <= 1'b1;
                end
            end
        end
    end

    task automatic pulse_write_done;
        begin
            @(posedge clk);
            write_done <= 1'b1;
            @(posedge clk);
            write_done <= 1'b0;
        end
    endtask

    task automatic pulse_row_done_buf;
        begin
            @(posedge clk);
            row_done_buf <= 1'b1;
            @(posedge clk);
            row_done_buf <= 1'b0;
        end
    endtask

    initial begin
        sys_rst        = 1'b1;
        start          = 1'b0;
        src_base_addr  = 32'h0000_0100;
        dst_base_addr  = 32'h0000_0200;
        src_stride     = 32'd4;
        dst_stride     = 32'd4;
        src_w          = 4;
        src_h          = 4;
        dst_w          = 4;
        dst_h          = 2;
        read_error     = 1'b0;
        lb_load_error  = 1'b0;
        core_busy      = 1'b0;
        core_done      = 1'b0;
        core_error     = 1'b0;
        line_req_valid = 1'b0;
        line_req_y     = '0;
        row_done       = 1'b0;
        row_busy       = 1'b0;
        row_done_buf   = 1'b0;
        row_error      = 1'b0;
        row_out_done   = 1'b0;
        write_busy     = 1'b0;
        write_done     = 1'b0;
        write_error    = 1'b0;
        read_issue_count = 0;

        repeat (5) @(posedge clk);
        sys_rst = 1'b0;
        repeat (2) @(posedge clk);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (read_seen_count == 1);
        if (read_addr_log[0] !== 32'h0000_0100) $fatal(1, "prefill row0 address mismatch: %h", read_addr_log[0]);
        read_issue_count = read_issue_count + 1;

        wait (read_seen_count == 2);
        if (read_addr_log[1] !== 32'h0000_0104) $fatal(1, "prefill row1 address mismatch: %h", read_addr_log[1]);
        read_issue_count = read_issue_count + 1;

        wait (core_start);
        if (!row_start) $fatal(1, "row_start should align with first core_start after prefill");

        line_req_valid <= 1'b1;
        line_req_y     <= 1;
        @(posedge clk);
        if (line_req_ready) $fatal(1, "line_req_ready should stay low before row2 is loaded");

        wait (read_seen_count == 3);
        if (read_addr_log[2] !== 32'h0000_0108) $fatal(1, "on-demand row2 address mismatch: %h", read_addr_log[2]);
        read_issue_count = read_issue_count + 1;

        wait (line_req_ready);
        if (line_req_sel !== 1) $fatal(1, "expected top cached row to stay in slot 1, got %0d", line_req_sel);
        line_req_valid <= 1'b0;

        pulse_row_done_buf();
        pulse_write_done();

        pulse_row_done_buf();
        @(posedge clk);
        core_done <= 1'b1;
        @(posedge clk);
        core_done <= 1'b0;
        pulse_write_done();

        wait (done);
        if (error) $fatal(1, "ctrl should not assert error");
        if (read_issue_count != 3) $fatal(1, "unexpected read issue count %0d", read_issue_count);

        $display("tb_scaler_ctrl completed");
        $finish;
    end

endmodule
