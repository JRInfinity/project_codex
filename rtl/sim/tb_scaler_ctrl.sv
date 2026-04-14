`timescale 1ns/1ps

// Keep tb_scaler_ctrl.md in sync
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
    logic core_start;
    logic core_busy;
    logic core_done;
    logic core_error;
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
        .core_start(core_start),
        .core_busy(core_busy),
        .core_done(core_done),
        .core_error(core_error),
        .row_done(row_done),
        .wb_start(row_start),
        .wb_pixel_count(row_pixel_count),
        .wb_busy(row_busy),
        .wb_done_buf(row_done_buf),
        .wb_error(row_error),
        .wb_out_start(row_out_start),
        .wb_out_done(row_out_done),
        .write_start(write_start),
        .write_addr(write_addr),
        .write_byte_count(write_byte_count),
        .write_busy(write_busy),
        .write_done(write_done),
        .write_error(write_error)
    );

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
        sys_rst          = 1'b1;
        start            = 1'b0;
        src_base_addr    = 32'h0000_0100;
        dst_base_addr    = 32'h0000_0200;
        src_stride       = 32'd4;
        dst_stride       = 32'd4;
        src_w            = 4;
        src_h            = 4;
        dst_w            = 4;
        dst_h            = 2;
        core_busy        = 1'b0;
        core_done        = 1'b0;
        core_error       = 1'b0;
        row_done         = 1'b0;
        row_busy         = 1'b0;
        row_done_buf     = 1'b0;
        row_error        = 1'b0;
        row_out_done     = 1'b0;
        write_busy       = 1'b0;
        write_done       = 1'b0;
        write_error      = 1'b0;

        repeat (5) @(posedge clk);
        sys_rst = 1'b0;
        repeat (2) @(posedge clk);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (core_start);
        if (!row_start) $fatal(1, "row_start should align with first core_start after source prefill");
        if (row_pixel_count != dst_w) $fatal(1, "row buffer launch width mismatch");

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
        if (write_addr !== 32'h0000_0208) $fatal(1, "final write address mismatch: %h", write_addr);

        $display("tb_scaler_ctrl completed");
        $finish;
    end

endmodule
