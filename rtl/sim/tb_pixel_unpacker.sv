`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_pixel_unpacker.md。

// Keep tb_pixel_unpacker.md in sync
module tb_pixel_unpacker;

    // 测试目标：
    // 1. 覆盖首地址偏移、尾部裁剪和错误结束场景
    // 2. 检查输出像素字节流与任务状态

    localparam int DATA_W  = 32;
    localparam int ADDR_W  = 32;
    localparam int PIXEL_W = 8;

    logic               core_clk;
    logic               sys_rst;
    logic               task_start;
    logic [ADDR_W-1:0]  task_addr;
    logic [31:0]        task_byte_count;
    logic               reader_status_valid;
    logic               reader_done_evt;
    logic               reader_error_evt;
    logic               fifo_rd_en;
    logic [DATA_W-1:0]  fifo_rd_data;
    logic               fifo_empty;
    logic               fifo_underflow;
    logic [PIXEL_W-1:0] pixel_data;
    logic               pixel_valid;
    logic               pixel_ready;
    logic               task_done_pulse;
    logic               task_error_pulse;
    logic               task_error_flag;

    logic [DATA_W-1:0] fifo_words [0:15];
    byte               expected_bytes [0:63];
    int                fifo_rd_idx;
    int                fifo_wr_idx;
    int                fifo_count;
    int                expected_count;

    int observed_count;
    int case_cycle_count;

    initial core_clk = 1'b0;
    always #5 core_clk = ~core_clk;

    pixel_unpacker #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .PIXEL_W(PIXEL_W)
    ) dut (
        .core_clk(core_clk),
        .sys_rst(sys_rst),
        .task_start(task_start),
        .task_addr(task_addr),
        .task_byte_count(task_byte_count),
        .reader_status_valid(reader_status_valid),
        .reader_done_evt(reader_done_evt),
        .reader_error_evt(reader_error_evt),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty),
        .fifo_underflow(fifo_underflow),
        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .task_done_pulse(task_done_pulse),
        .task_error_pulse(task_error_pulse),
        .task_error_flag(task_error_flag)
    );

    assign fifo_empty   = (fifo_count == 0);
    assign fifo_rd_data = (fifo_count == 0) ? '0 : fifo_words[fifo_rd_idx];

    task automatic clear_queues;
        begin
            fifo_rd_idx    = 0;
            fifo_wr_idx    = 0;
            fifo_count     = 0;
            expected_count = 0;
        end
    endtask

    task automatic push_fifo_word(input logic [DATA_W-1:0] value);
        begin
            fifo_words[fifo_wr_idx] = value;
            fifo_wr_idx = fifo_wr_idx + 1;
            fifo_count  = fifo_count + 1;
        end
    endtask

    task automatic push_expected_byte(input byte value);
        begin
            expected_bytes[expected_count] = value;
            expected_count = expected_count + 1;
        end
    endtask

    task automatic apply_reset;
        begin
            sys_rst            = 1'b1;
            task_start         = 1'b0;
            task_addr          = '0;
            task_byte_count    = '0;
            reader_status_valid = 1'b0;
            reader_done_evt    = 1'b0;
            reader_error_evt   = 1'b0;
            fifo_underflow     = 1'b0;
            pixel_ready          = 1'b0;
            observed_count     = 0;
            case_cycle_count   = 0;
            clear_queues();
            repeat (5) @(posedge core_clk);
            sys_rst = 1'b0;
            repeat (3) @(posedge core_clk);
        end
    endtask

    task automatic start_task(input logic [ADDR_W-1:0] addr, input logic [31:0] byte_count);
        begin
            @(posedge core_clk);
            task_addr       <= addr;
            task_byte_count <= byte_count;
            task_start      <= 1'b1;
            @(posedge core_clk);
            task_start      <= 1'b0;
        end
    endtask

    task automatic pulse_reader_done;
        begin
            @(posedge core_clk);
            reader_status_valid <= 1'b1;
            reader_done_evt     <= 1'b1;
            reader_error_evt    <= 1'b0;
            @(posedge core_clk);
            reader_status_valid <= 1'b0;
            reader_done_evt     <= 1'b0;
        end
    endtask

    task automatic pulse_reader_error;
        begin
            @(posedge core_clk);
            reader_status_valid <= 1'b1;
            reader_done_evt     <= 1'b0;
            reader_error_evt    <= 1'b1;
            @(posedge core_clk);
            reader_status_valid <= 1'b0;
            reader_error_evt    <= 1'b0;
        end
    endtask

    task automatic pulse_fifo_underflow;
        begin
            @(posedge core_clk);
            fifo_underflow <= 1'b1;
            @(posedge core_clk);
            fifo_underflow <= 1'b0;
        end
    endtask

    task automatic wait_for_terminal(
        input string case_name,
        input bit expect_done,
        input bit enable_backpressure,
        input int timeout_cycles
    );
        begin
            while (!task_done_pulse && !task_error_pulse) begin
                @(posedge core_clk);
                case_cycle_count <= case_cycle_count + 1;
                if (enable_backpressure) begin
                    pixel_ready <= ((case_cycle_count % 4) != 1);
                end else begin
                    pixel_ready <= 1'b1;
                end

                if (case_cycle_count > timeout_cycles) begin
                    $fatal(1, "%s timed out", case_name);
                end
            end

            if (expect_done && task_error_pulse) begin
                $fatal(1, "%s unexpectedly raised task_error_pulse", case_name);
            end

            if (!expect_done && task_done_pulse) begin
                $fatal(1, "%s unexpectedly raised task_done_pulse", case_name);
            end
        end
    endtask

    task automatic run_success_case(input string case_name, input bit enable_backpressure);
        int wait_cycles;
        begin
            $display("Running %s", case_name);
            observed_count   = 0;
            case_cycle_count = 0;
            pixel_ready        = 1'b1;
            wait_cycles      = 0;

            while (observed_count != expected_count) begin
                @(posedge core_clk);
                case_cycle_count = case_cycle_count + 1;
                wait_cycles      = wait_cycles + 1;

                if (enable_backpressure) begin
                    pixel_ready = ((case_cycle_count % 4) != 1);
                end else begin
                    pixel_ready = 1'b1;
                end

                if (task_error_pulse) begin
                    $fatal(1, "%s unexpectedly raised task_error_pulse before all bytes were observed", case_name);
                end

                if (wait_cycles > 200) begin
                    $fatal(1, "%s timed out while waiting for output bytes", case_name);
                end
            end

            pulse_reader_done();
            wait_for_terminal(case_name, 1'b1, enable_backpressure, 200);

            if (observed_count != expected_count) begin
                $fatal(1, "%s output count mismatch got=%0d exp=%0d",
                    case_name, observed_count, expected_count);
            end

            if (task_error_flag) begin
                $fatal(1, "%s left task_error_flag asserted after success", case_name);
            end
        end
    endtask

    task automatic run_error_case(input string case_name);
        begin
            $display("Running %s", case_name);
            observed_count   = 0;
            case_cycle_count = 0;
            pixel_ready        = 1'b1;
            wait_for_terminal(case_name, 1'b0, 1'b0, 200);
        end
    endtask

    always_ff @(posedge core_clk) begin
        if (sys_rst) begin
            observed_count <= 0;
        end else begin
            if (fifo_rd_en && !fifo_empty) begin
                fifo_rd_idx <= fifo_rd_idx + 1;
                fifo_count  <= fifo_count - 1;
            end

            if (pixel_valid && pixel_ready) begin
                if (observed_count >= expected_count) begin
                    $fatal(1, "Observed more bytes than expected");
                end

                if (pixel_data !== expected_bytes[observed_count]) begin
                    $fatal(1, "Output mismatch idx=%0d got=%02h exp=%02h",
                        observed_count, pixel_data, expected_bytes[observed_count]);
                end

                observed_count <= observed_count + 1;
            end
        end
    end

    initial begin
        apply_reset();

        // aligned_full_words
        push_fifo_word(32'h44332211);
        push_fifo_word(32'h88776655);
        push_expected_byte(8'h11);
        push_expected_byte(8'h22);
        push_expected_byte(8'h33);
        push_expected_byte(8'h44);
        push_expected_byte(8'h55);
        push_expected_byte(8'h66);
        push_expected_byte(8'h77);
        push_expected_byte(8'h88);
        start_task(32'h0000_0100, 8);
        run_success_case("aligned_full_words", 1'b0);

        apply_reset();

        // unaligned_partial
        push_fifo_word(32'h44332211);
        push_fifo_word(32'h88776655);
        push_expected_byte(8'h22);
        push_expected_byte(8'h33);
        push_expected_byte(8'h44);
        push_expected_byte(8'h55);
        push_expected_byte(8'h66);
        start_task(32'h0000_0101, 5);
        run_success_case("unaligned_partial", 1'b0);

        apply_reset();

        // tail_three_bytes
        push_fifo_word(32'h04030201);
        push_expected_byte(8'h01);
        push_expected_byte(8'h02);
        push_expected_byte(8'h03);
        start_task(32'h0000_0200, 3);
        run_success_case("tail_three_bytes", 1'b0);

        apply_reset();

        // reader_done_without_data
        start_task(32'h0000_0300, 4);
        pulse_reader_done();
        run_error_case("reader_done_without_data");

        apply_reset();

        // reader_error_event
        start_task(32'h0000_0400, 4);
        pulse_reader_error();
        run_error_case("reader_error_event");

        apply_reset();

        // fifo_underflow_error
        start_task(32'h0000_0500, 4);
        pulse_fifo_underflow();
        run_error_case("fifo_underflow_error");

        $display("tb_pixel_unpacker completed");
        $finish;
    end

endmodule
