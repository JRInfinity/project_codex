`timescale 1ns/1ps
// 说明：修改测试场景或检查项时，同步更新 tb_task_cdc.md。

module tb_task_cdc;

    // 测试目标：
    // 1. 验证任务请求跨时钟域传输
    // 2. 检查地址、长度和握手行为是否保持一致

    localparam int ADDR_W = 32;

    logic              src_clk;
    logic              dst_clk;
    logic              sys_rst;
    logic              task_valid_src;
    logic [ADDR_W-1:0] task_addr_src;
    logic [31:0]       task_byte_count_src;
    logic              task_ready_src;
    logic              task_valid_dst;
    logic [ADDR_W-1:0] task_addr_dst;
    logic [31:0]       task_byte_count_dst;
    logic              task_ready_dst;

    int observed_count;
    logic [ADDR_W-1:0] observed_addr [0:7];
    logic [31:0]       observed_count_bytes [0:7];
    int case_cycle_count;

    initial src_clk = 1'b0;
    always #4 src_clk = ~src_clk;

    initial dst_clk = 1'b0;
    always #6 dst_clk = ~dst_clk;

    task_cdc #(
        .ADDR_W(ADDR_W)
    ) dut (
        .src_clk(src_clk),
        .sys_rst(sys_rst),
        .task_valid_src(task_valid_src),
        .task_addr_src(task_addr_src),
        .task_byte_count_src(task_byte_count_src),
        .task_ready_src(task_ready_src),
        .dst_clk(dst_clk),
        .task_valid_dst(task_valid_dst),
        .task_addr_dst(task_addr_dst),
        .task_byte_count_dst(task_byte_count_dst),
        .task_ready_dst(task_ready_dst)
    );

    task automatic apply_reset;
        begin
            sys_rst             = 1'b1;
            task_valid_src      = 1'b0;
            task_addr_src       = '0;
            task_byte_count_src = '0;
            task_ready_dst      = 1'b0;
            observed_count      = 0;
            case_cycle_count    = 0;
            repeat (4) @(posedge src_clk);
            repeat (4) @(posedge dst_clk);
            sys_rst = 1'b0;
            repeat (2) @(posedge src_clk);
        end
    endtask

    task automatic send_task(input logic [ADDR_W-1:0] addr, input logic [31:0] byte_count);
        begin
            wait (task_ready_src);
            @(posedge src_clk);
            task_addr_src       <= addr;
            task_byte_count_src <= byte_count;
            task_valid_src      <= 1'b1;
            @(posedge src_clk);
            task_valid_src      <= 1'b0;
        end
    endtask

    task automatic wait_for_observed_count(input int exp_count, input string case_name);
        begin
            while (observed_count != exp_count) begin
                @(posedge dst_clk);
                case_cycle_count = case_cycle_count + 1;
                if (case_cycle_count > 100) begin
                    $fatal(1, "%s timed out waiting for destination task", case_name);
                end
            end
        end
    endtask

    task automatic wait_for_src_ready(input string case_name);
        int wait_cycles;
        begin
            wait_cycles = 0;
            while (!task_ready_src) begin
                @(posedge src_clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 20) begin
                    $fatal(1, "%s source did not return ready after ack sync", case_name);
                end
            end
        end
    endtask

    task automatic run_single_transfer_case;
        begin
            $display("Running single_transfer");
            apply_reset();
            task_ready_dst = 1'b1;
            send_task(32'h1000_0020, 32'd64);
            wait_for_observed_count(1, "single_transfer");
            if (observed_addr[0] !== 32'h1000_0020) begin
                $fatal(1, "single_transfer addr mismatch got=%h exp=%h", observed_addr[0], 32'h1000_0020);
            end
            if (observed_count_bytes[0] !== 32'd64) begin
                $fatal(1, "single_transfer byte_count mismatch got=%0d exp=%0d", observed_count_bytes[0], 64);
            end
        end
    endtask

    task automatic run_dst_stall_case;
        int hold_cycles;
        begin
            $display("Running dst_stall");
            apply_reset();
            task_ready_dst = 1'b0;
            send_task(32'h2000_0100, 32'd19);

            hold_cycles = 0;
            while (!task_valid_dst) begin
                @(posedge dst_clk);
                hold_cycles = hold_cycles + 1;
                if (hold_cycles > 50) begin
                    $fatal(1, "dst_stall never asserted task_valid_dst");
                end
            end

            repeat (3) begin
                @(posedge dst_clk);
                if (!task_valid_dst) begin
                    $fatal(1, "dst_stall task_valid_dst dropped before ready");
                end
                if (task_addr_dst !== 32'h2000_0100 || task_byte_count_dst !== 32'd19) begin
                    $fatal(1, "dst_stall payload changed while waiting for ready");
                end
                if (task_ready_src) begin
                    $fatal(1, "dst_stall source became ready before destination ack");
                end
            end

            task_ready_dst = 1'b1;
            wait_for_observed_count(1, "dst_stall");
            wait_for_src_ready("dst_stall");
        end
    endtask

    task automatic run_back_to_back_case;
        begin
            $display("Running back_to_back");
            apply_reset();
            task_ready_dst = 1'b1;

            send_task(32'h3000_0000, 32'd32);
            wait_for_observed_count(1, "back_to_back_first");
            wait_for_src_ready("back_to_back_first");

            send_task(32'h3000_0040, 32'd48);
            wait_for_observed_count(2, "back_to_back_second");

            if (observed_addr[1] !== 32'h3000_0040 || observed_count_bytes[1] !== 32'd48) begin
                $fatal(1, "back_to_back second payload mismatch");
            end
        end
    endtask

    always_ff @(posedge dst_clk) begin
        if (sys_rst) begin
            observed_count <= 0;
        end else begin
            if (task_valid_dst && task_ready_dst) begin
                observed_addr[observed_count]        <= task_addr_dst;
                observed_count_bytes[observed_count] <= task_byte_count_dst;
                observed_count                       <= observed_count + 1;
            end
        end
    end

    initial begin
        run_single_transfer_case();
        run_dst_stall_case();
        run_back_to_back_case();
        $display("tb_task_cdc completed");
        $finish;
    end

endmodule
