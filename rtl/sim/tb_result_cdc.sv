`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_result_cdc.md。

module tb_result_cdc;

    // 测试目标：
    // 1. 验证结果事件跨时钟域传输
    // 2. 检查 done/error 脉冲和握手节奏

    logic src_clk;
    logic dst_clk;
    logic sys_rst;
    logic result_valid_src;
    logic result_done_src;
    logic result_error_src;
    logic result_ready_src;
    logic result_valid_dst;
    logic result_done_dst;
    logic result_error_dst;

    int observed_count;
    logic observed_done [0:7];
    logic observed_error [0:7];
    int case_cycle_count;

    initial src_clk = 1'b0;
    always #4 src_clk = ~src_clk;

    initial dst_clk = 1'b0;
    always #6 dst_clk = ~dst_clk;

    result_cdc dut (
        .src_clk(src_clk),
        .sys_rst(sys_rst),
        .result_valid_src(result_valid_src),
        .result_done_src(result_done_src),
        .result_error_src(result_error_src),
        .result_ready_src(result_ready_src),
        .dst_clk(dst_clk),
        .result_valid_dst(result_valid_dst),
        .result_done_dst(result_done_dst),
        .result_error_dst(result_error_dst)
    );

    task automatic apply_reset;
        begin
            sys_rst          = 1'b1;
            result_valid_src = 1'b0;
            result_done_src  = 1'b0;
            result_error_src = 1'b0;
            observed_count   = 0;
            case_cycle_count = 0;
            repeat (4) @(posedge src_clk);
            repeat (4) @(posedge dst_clk);
            sys_rst = 1'b0;
            repeat (2) @(posedge src_clk);
        end
    endtask

    task automatic send_result(input logic done_evt, input logic err_evt);
        begin
            wait (result_ready_src);
            @(posedge src_clk);
            result_done_src  <= done_evt;
            result_error_src <= err_evt;
            result_valid_src <= 1'b1;
            @(posedge src_clk);
            result_valid_src <= 1'b0;
            result_done_src  <= 1'b0;
            result_error_src <= 1'b0;
        end
    endtask

    task automatic wait_for_observed_count(input int exp_count, input string case_name);
        begin
            while (observed_count != exp_count) begin
                @(posedge dst_clk);
                case_cycle_count = case_cycle_count + 1;
                if (case_cycle_count > 100) begin
                    $fatal(1, "%s timed out waiting for destination result", case_name);
                end
            end
        end
    endtask

    task automatic wait_for_src_ready(input string case_name);
        int wait_cycles;
        begin
            wait_cycles = 0;
            while (!result_ready_src) begin
                @(posedge src_clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 20) begin
                    $fatal(1, "%s source did not return ready after ack sync", case_name);
                end
            end
        end
    endtask

    task automatic run_done_case;
        begin
            $display("Running done_event");
            apply_reset();
            send_result(1'b1, 1'b0);
            wait_for_observed_count(1, "done_event");
            wait_for_src_ready("done_event");
            if (!observed_done[0] || observed_error[0]) begin
                $fatal(1, "done_event payload mismatch");
            end
        end
    endtask

    task automatic run_error_case;
        begin
            $display("Running error_event");
            apply_reset();
            send_result(1'b0, 1'b1);
            wait_for_observed_count(1, "error_event");
            wait_for_src_ready("error_event");
            if (observed_done[0] || !observed_error[0]) begin
                $fatal(1, "error_event payload mismatch");
            end
        end
    endtask

    task automatic run_back_to_back_case;
        begin
            $display("Running back_to_back_result");
            apply_reset();
            send_result(1'b1, 1'b0);
            wait_for_observed_count(1, "back_to_back_first");
            wait_for_src_ready("back_to_back_first");

            send_result(1'b0, 1'b1);
            wait_for_observed_count(2, "back_to_back_second");
            wait_for_src_ready("back_to_back_second");
            if (observed_done[1] || !observed_error[1]) begin
                $fatal(1, "back_to_back second payload mismatch");
            end
        end
    endtask

    always_ff @(posedge dst_clk) begin
        if (sys_rst) begin
            observed_count <= 0;
        end else begin
            if (result_valid_dst) begin
                observed_done[observed_count]  <= result_done_dst;
                observed_error[observed_count] <= result_error_dst;
                observed_count                 <= observed_count + 1;
            end
        end
    end

    initial begin
        run_done_case();
        run_error_case();
        run_back_to_back_case();
        $display("tb_result_cdc completed");
        $finish;
    end

endmodule
